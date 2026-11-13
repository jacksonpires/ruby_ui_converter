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
  # FormBuilder, LocalsDetector — is shared between both formats.
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

    def convert_children(nodes, target)
      nodes.each { |node| convert(node, target) }
    end

    def convert(node, target)
      case node.type
      when :tag then target << element(node)
      when :plain then target << Nodes::Text.new(content: node.value[:text].to_s)
      when :script then script(node, target)
      when :silent_script then silent_script(node, target)
      when :haml_comment then target << ruby_comment(node.value[:text])
      when :comment then html_comment(node, target)
      when :doctype then doctype(node, target)
      when :filter then filter(node, target)
      end
    end

    # --- tags --------------------------------------------------------------

    def element(node)
      value = node.value
      element = Nodes::Element.new(
        name: value[:name],
        attributes: attributes(value),
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
        target << Nodes::Text.new(content: content.to_s)
      end
    end

    # Static attributes (`.a#b`, `(x="y")`, `(disabled)`) become text parts.
    # Dynamic hashes (`{...}` / html-style with Ruby values) are passed through
    # as a `**(hash)` splat for now.
    def attributes(value)
      attrs = []

      value[:attributes].to_h.each do |name, val|
        next if val.nil? || val == false

        attrs << [name.to_s, val == true ? nil : [[:text, val.to_s]]]
      end

      dynamic = value[:dynamic_attributes]
      [dynamic&.new, dynamic&.old].compact.each do |hash_code|
        attrs << [:__splat__, [[:erb, output_token(splat_code(hash_code))]]]
      end

      attrs
    end

    # "{a: 1}" -> "{a: 1}"; "{html_attrs}" -> "html_attrs" (haml treats the
    # braces' content as an argument list, so a bare expression is the hash).
    def splat_code(hash_code)
      inner = hash_code.to_s.strip.sub(/\A\{/, "").sub(/\}\z/, "").strip
      args = RailsHelpers.split_args(inner)
      pairs = args.any? { |arg| arg =~ /\A(\*\*|[\w?!]+:(?!:)|"[^"]*":|'[^']*':)/ || arg.include?("=>") }
      pairs ? "{#{inner}}" : inner
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
      branch = Nodes::Branch.new(header: header)
      control.branches << branch

      node.children.each do |child|
        if mid_keyword?(child)
          branch = Nodes::Branch.new(header: child.value[:text].to_s.strip)
          control.branches << branch
          convert_children(child.children, branch.children)
        else
          convert(child, branch.children)
        end
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
    # (`!=`), or text with `#{}` interpolation — split into Text + Output
    # nodes like the ERB `Hello <%= name %>` equivalent, so helpers and locals
    # inside the interpolation are seen by the rest of the pipeline.
    def expression(code, escape_html, escape_interpolation, target)
      code = code.to_s.strip
      parts = interpolated_text_parts(code, escape_html, escape_interpolation)

      if parts
        parts.each do |kind, value|
          target << (kind == :text ? Nodes::Text.new(content: value) : Nodes::Output.new(code: value))
        end
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

    # --- comments, doctype, filters ----------------------------------------

    def ruby_comment(text)
      Nodes::Comment.new(text: text.to_s.strip, html: false)
    end

    def html_comment(node, target)
      value = node.value
      if value[:conditional] || node.children.any?
        target << ruby_comment("TODO: HAML block/conditional comment #{value[:conditional]} not converted".squeeze(" "))
      else
        target << Nodes::Comment.new(text: value[:text].to_s, html: true)
      end
    end

    def doctype(node, target)
      return if node.value[:type].to_s.downcase == "xml"

      target << Nodes::Doctype.new(value: "<!DOCTYPE html>")
    end

    def filter(node, target)
      text = node.value[:text].to_s.rstrip
      target << ruby_comment("TODO: HAML :#{node.value[:name]} filter not converted\n#{text}")
    end

    def output_token(code)
      Lexer::Token.new(type: :output, value: code, raw: false)
    end
  end
end
