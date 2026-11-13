# frozen_string_literal: true

module RubyUIConverter
  # Builds the converter's AST (Nodes) from a HAML template.
  #
  # Parsing itself is delegated to the haml gem's own parser (Haml::Parser), an
  # OPTIONAL dependency required lazily — only when a .haml file is converted —
  # so ERB-only users keep `thor` as the sole runtime dependency. Apps with
  # .haml views already have haml in their bundle.
  #
  # The result has the same shape the ERB Parser builds for the equivalent ERB
  # (Text/Output/Statement/Control/Element nodes, attribute "parts"), so the
  # whole downstream pipeline — Transformer, ComponentMap, RailsHelpers,
  # FormBuilder, LocalsDetector — is shared between both formats. HAML text
  # (which may hold inline HTML) is itself routed through the ERB Parser, with
  # each `#{}` interpolation turned into an `<%= %>` tag.
  #
  # Verified against haml 5.2, 6.x and 7.x, which share the ParseNode tree
  # shape and the `Haml::Parser.new(options).call(source)` API.
  class HamlParser
    # Mid-block keywords. Haml nests them (flattened) among the children of the
    # `if`/`case`/`begin` node they belong to; each one starts a new Branch.
    MID_KEYWORDS = %w[else elsif when in rescue ensure].freeze

    # With escape_html on, haml 5 and 6 wrap every text interpolation in an
    # escape call (haml 5: `Haml::Helpers.html_escape((x))`, haml 6:
    # `Haml::Util.escape_html_safe((x).to_s)`); haml 7 doesn't. Phlex escapes
    # output itself, so the wrapper is stripped back to the original code.
    ESCAPE_WRAPPER = /\A(?:::)?Haml::(?:Helpers\.html_escape|Util\.escape_html_safe|Util\.escape_html)\(\((.*)\)(?:\.to_s)?\)\z/m

    # Filters whose content is HAML/HTML text (interpolated, unescaped HTML).
    TEXT_FILTERS = %w[plain preserve].freeze
    # Filters rendered as an element wrapping their raw content.
    RAW_ELEMENT_FILTERS = { "javascript" => "script", "css" => "style" }.freeze

    MISSING_HAML = "converting .haml templates requires the haml gem " \
                   "(add `gem \"haml\"` to your Gemfile or run `gem install haml`)"

    def self.load_haml!
      require_haml
      true
    rescue LoadError
      raise Error, MISSING_HAML
    end

    # Separate seam so tests can simulate a missing haml gem.
    def self.require_haml
      require "haml"
    end

    # `Haml::Helpers.html_escape((name))` -> `name`; anything else unchanged.
    def self.unwrap_escape(code)
      code = code.to_s.strip
      (inner = code[ESCAPE_WRAPPER, 1]) ? inner.strip : code
    end

    def initialize(source)
      @source = source.to_s
    end

    def parse
      self.class.load_haml!
      # escape_html: true (the Rails default) is what lets the parser tell
      # `=` (escaped) apart from `!=` (raw).
      root = ::Haml::Parser.new(escape_html: true).call(@source)

      document = Nodes::Document.new
      convert_children(root.children, document.children)
      document
    end

    private

    # Converts sibling HAML nodes, then pads text that sits next to another
    # rendered sibling: HAML puts a newline between lines, so `Signed in as`
    # followed by `%strong= name` renders with a space in between.
    def convert_children(nodes, target)
      rendered = nodes.reject { |node| silent?(node) }

      nodes.each do |node|
        start = target.length
        convert(node, target)
        next if silent?(node)

        position = rendered.index { |other| other.equal?(node) }
        before = position.positive? && !nuke_outer?(rendered[position - 1])
        after = position < rendered.length - 1 && !nuke_outer?(rendered[position + 1])
        pad_text(target, start, before: before && !nuke_outer?(node), after: after && !nuke_outer?(node))
      end
    end

    # Nodes that render nothing between their siblings.
    def silent?(node)
      node.type == :haml_comment || (node.type == :silent_script && node.children.empty?)
    end

    # `%img>`: whitespace around the tag is removed.
    def nuke_outer?(node)
      node.type == :tag && node.value[:nuke_outer_whitespace] ? true : false
    end

    def pad_text(target, start, before:, after:)
      return if start >= target.length

      first = target[start]
      if before && first.is_a?(Nodes::Text) && first.content !~ /\A\s/
        target[start] = Nodes::Text.new(content: " #{first.content}")
      end

      last = target[-1]
      return unless after && last.is_a?(Nodes::Text) && last.content !~ /\s\z/

      target[-1] = Nodes::Text.new(content: "#{last.content} ")
    end

    def convert(node, target)
      case node.type
      when :tag then target << element(node)
      when :plain then target.concat(text_nodes([[:text, node.value[:text].to_s]]))
      when :script then script(node, target)
      when :silent_script then silent_script(node, target)
      when :haml_comment then target << ruby_comment(node.value[:text])
      when :comment then html_comment(node, target)
      when :doctype then doctype(node, target)
      when :filter then filter(node, target)
      end
    end

    # HAML text is unescaped HTML with escaped `#{}` interpolations — exactly
    # what ERB text with `<%= %>` tags is — so it goes through the ERB Parser:
    # inline markup (`Hi <strong>you</strong>`) becomes real elements, and
    # interpolated helpers (`#{link_to ...}`) become Output nodes the
    # RailsHelpers mapping understands.
    def text_nodes(parts)
      erb = parts.map { |kind, value| kind == :text ? value : "<%= #{value} %>" }.join
      Parser.new(erb).parse.children
    end

    # --- tags --------------------------------------------------------------

    def element(node)
      value = node.value
      element = Nodes::Element.new(
        name: value[:name],
        attributes: HamlAttributes.build(value),
        self_closing: value[:self_closing] ? true : false
      )
      inline_content(value, element.children)
      convert_children(node.children, element.children)
      element
    end

    # `%p Hello` / `%p= code` / `%p!= code` / `%p Hi #{name}`
    def inline_content(value, target)
      content = value[:value]
      return if content.nil? || content.to_s.empty?

      if value[:parse]
        expression(content, value[:escape_html], value[:escape_interpolation], target)
      else
        target.concat(text_nodes([[:text, content.to_s]]))
      end
    end

    # --- Ruby --------------------------------------------------------------

    # `= code` (with or without a block) and interpolated plain text, which
    # haml hands over as a script node.
    def script(node, target)
      text = node.value[:text].to_s.strip

      if node.children.any?
        target << control(node, text, output: true)
      else
        expression(text, node.value[:escape_html], node.value[:escape_interpolation], target)
      end
    end

    def silent_script(node, target)
      text = node.value[:text].to_s.strip

      if mid_keyword?(node) && target.last.is_a?(Nodes::Control)
        # Defensive: a mid-block keyword left as a sibling of its opener.
        branch = Nodes::Branch.new(header: text)
        target.last.branches << branch
        convert_children(node.children, branch.children)
      elsif node.children.any?
        target << control(node, text, output: false)
      else
        target << Nodes::Statement.new(code: text)
      end
    end

    # `- if a` … `- elsif b` … `- else`, `- case`/`- when`, `- x.each do |i|`,
    # `= form_with(...) do |f|`. Haml always closes blocks by indentation, so
    # the matching `end` is implicit (the Transformer emits it).
    def control(node, header, output:)
      control = Nodes::Control.new(block: block_opener?(header), output: output)
      segments = [[header, []]]

      node.children.each do |child|
        if mid_keyword?(child)
          segments << [child.value[:text].to_s.strip, child.children.dup]
        else
          segments.last[1] << child
        end
      end

      segments.each do |branch_header, children|
        branch = Nodes::Branch.new(header: branch_header)
        convert_children(children, branch.children)
        control.branches << branch
      end

      control
    end

    def mid_keyword?(node)
      node.type == :silent_script && MID_KEYWORDS.include?(node.value[:keyword])
    end

    def block_opener?(code)
      code =~ /\bdo\s*(\|[^|]*\|)?\s*\z/ ? true : false
    end

    # A Ruby expression whose value is output: escaped (`=`, `&=`, `~`), raw
    # (`!=`), or text with `#{}` interpolation — parsed like the ERB
    # `Hello <%= name %>` equivalent, so helpers and locals inside the
    # interpolation are seen by the rest of the pipeline.
    def expression(code, escape_html, escape_interpolation, target)
      code = code.to_s.strip
      parts = interpolated_text_parts(code, escape_html, escape_interpolation)

      if parts
        target.concat(text_nodes(parts))
      else
        target << Nodes::Output.new(code: code, raw: escape_html == false)
      end
    end

    # Interpolated text is flagged with escape_interpolation (haml 6/7 plain
    # lines, haml 7 inline text); haml 5/6 inline text is only recognizable by
    # the escape wrappers around its interpolations.
    def interpolated_text_parts(code, escape_html, escape_interpolation)
      parts = RubyLiteral.string_parts(code)
      return nil unless parts

      wrapped = parts.any? { |kind, value| kind == :code && value.match?(ESCAPE_WRAPPER) }
      return nil unless escape_interpolation || (escape_html == false && wrapped)

      parts.map { |kind, value| kind == :code ? [kind, self.class.unwrap_escape(value)] : [kind, value] }
    end

    # Text with HAML `#{}` interpolation (filter content) as text/code parts.
    def interpolation_parts(text)
      return [[:text, text]] unless text =~ /#[{@$]/

      RubyLiteral.string_parts(::Haml::Util.unescape_interpolation(text)) || [[:text, text]]
    end

    # --- comments, doctype, filters ----------------------------------------

    def ruby_comment(text)
      Nodes::Comment.new(text: text.to_s.strip, html: false)
    end

    # `/ note` -> comment { "note" }; a `/` with nested HAML renders that
    # content inside the comment (`comment do ... end`). IE conditional
    # comments (`/[if IE]`) are obsolete and left as a TODO.
    def html_comment(node, target)
      value = node.value

      if value[:conditional]
        target << ruby_comment("TODO: HAML conditional comment #{value[:conditional]} dropped (content not converted)")
      else
        comment = Nodes::Comment.new(text: value[:text].to_s, html: true)
        convert_children(node.children, comment.children)
        target << comment
      end
    end

    def doctype(node, target)
      return if node.value[:type].to_s.downcase == "xml"

      target << Nodes::Doctype.new(value: "<!DOCTYPE html>")
    end

    def filter(node, target)
      name = node.value[:name].to_s
      text = node.value[:text].to_s

      if RAW_ELEMENT_FILTERS.key?(name)
        target << raw_element(RAW_ELEMENT_FILTERS[name], text)
      elsif TEXT_FILTERS.include?(name)
        target.concat(text_nodes(interpolation_parts(text.rstrip)))
      elsif name == "escaped"
        interpolation_parts(text.rstrip).each do |kind, value|
          target << (kind == :text ? Nodes::Text.new(content: value) : Nodes::Output.new(code: value))
        end
      elsif name == "erb"
        target.concat(Parser.new(text).parse.children)
      elsif name == "ruby"
        text.each_line { |line| target << Nodes::Statement.new(code: line.rstrip) unless line.strip.empty? }
      else
        target << ruby_comment("TODO: HAML :#{name} filter not converted\n#{text.rstrip}")
      end
    end

    # :javascript / :css -> script / style. Content without interpolation is
    # kept verbatim (RawText, like an ERB <script>); with `#{}` it becomes a
    # raw interpolated string.
    def raw_element(tag, text)
      element = Nodes::Element.new(name: tag)
      return element if text.strip.empty?

      parts = interpolation_parts(text)
      element.children <<
        if parts.any? { |kind, _| kind == :code }
          Nodes::Output.new(code: ::Haml::Util.unescape_interpolation(text), raw: true)
        else
          Nodes::RawText.new(content: text)
        end
      element
    end
  end
end
