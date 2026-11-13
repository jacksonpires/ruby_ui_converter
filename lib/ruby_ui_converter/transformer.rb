# frozen_string_literal: true

require "ripper"

module RubyUIConverter
  # Walks the AST and writes Phlex/RubyUI Ruby source into a CodeBuilder.
  class Transformer
    attr_reader :config, :template

    def initialize(config:, template: nil)
      @config = config
      @template = template
      @form_stack = []
    end

    # The form scope ({var:, model:, param:}) currently being emitted, if any.
    # Set while inside a mapped form_with/form_for block; used by FormBuilder.
    def current_form
      @form_stack.last
    end

    # Entry point: emits the body of the view_template method.
    def emit(document, builder)
      emit_children(meaningful(document.children), builder)
    end

    # --- public helpers (also used by ComponentMap emitters) ---------------

    def emit_children(nodes, builder)
      nodes.each { |node| emit_node(node, builder) }
    end

    def meaningful(nodes)
      nodes.each_with_index.reject do |node, index|
        (node.is_a?(Nodes::Text) && node.content.strip.empty? && !inline_space?(nodes, index)) ||
          (node.is_a?(Nodes::RawText) && node.content.strip.empty?)
      end.map(&:first)
    end

    def render_attrs(attributes, except: [])
      attributes.reject { |name, _| except.include?(name) }
                .map { |name, parts| attr_pair(name, parts) }
                .join(", ")
    end

    def base_namespace
      config.base_namespace
    end

    def current_namespace_parts
      template ? template.namespace_parts : []
    end

    # Convenience for component emitters: render a component wrapping children.
    def wrap_component(const, element, builder)
      attrs = render_attrs(element.attributes)
      call = attrs.empty? ? "#{const}.new" : "#{const}.new(#{attrs})"
      kids = meaningful(element.children)

      if kids.empty?
        builder.line("render #{call}")
      else
        builder.line("render #{call} do")
        builder.indent
        emit_children(kids, builder)
        builder.dedent
        builder.line("end")
      end
    end

    # Emits a Phlex::Kit-style component call (`Link(href: x) { "Home" }`).
    # Parens are always kept — a bare capitalized name would be a constant.
    # `void: true` components (Input, Checkbox...) never take a block.
    # `extra:` prepends literal arguments (e.g. "variant: :destructive").
    def kit_component(name, element, builder, except: [], void: false, extra: nil)
      attrs = [extra, render_attrs(element.attributes, except: except)]
              .compact.reject(&:empty?).join(", ")
      call = "#{name}(#{attrs})"
      kids = void ? [] : meaningful(element.children)

      if kids.empty?
        builder.line(call)
      elsif kids.length == 1 && inlineable?(kids.first)
        builder.line("#{call} { #{inline_value(kids.first)} }")
      else
        builder.line("#{call} do")
        builder.indent
        emit_children(kids, builder)
        builder.dedent
        builder.line("end")
      end
    end

    # Emits a component that wraps the given children with no attributes:
    # `Name { inline }` for a single inlineable child, else a do/end block.
    # Handy for ComponentMap emitters that nest content components (e.g.
    # `AlertDescription { notice }`).
    def component_block(name, children, builder)
      kids = meaningful(children)

      if kids.empty?
        builder.line(name)
      elsif kids.length == 1 && inlineable?(kids.first)
        builder.line("#{name} { #{inline_value(kids.first)} }")
      else
        builder.line("#{name} do")
        builder.indent
        emit_children(kids, builder)
        builder.dedent
        builder.line("end")
      end
    end

    private

    def emit_node(node, builder)
      case node
      when Nodes::Element   then emit_element_or_component(node, builder)
      when Nodes::Text      then emit_text(node, builder)
      when Nodes::RawText   then emit_raw_text(node, builder)
      when Nodes::Output    then emit_output(node, builder)
      when Nodes::Statement then emit_statement(node, builder)
      when Nodes::Control   then emit_control(node, builder)
      when Nodes::Comment   then emit_comment(node, builder)
      when Nodes::Doctype   then emit_doctype(node, builder)
      end
    end

    def emit_element_or_component(node, builder)
      emitter = config.component_map.lookup(node)
      return emitter.call(node, self, builder) if emitter

      emit_element(node, builder)
    end

    def emit_element(node, builder)
      method = element_method(node.name)
      attrs = render_attrs(node.attributes)
      call = attrs.empty? ? method : "#{method}(#{attrs})"
      kids = meaningful(node.children)

      if kids.empty?
        builder.line(call)
      elsif kids.length == 1 && inlineable?(kids.first)
        builder.line("#{call} { #{inline_value(kids.first)} }")
      else
        builder.line("#{call} do")
        builder.indent
        emit_children(kids, builder)
        builder.dedent
        builder.line("end")
      end
    end

    def emit_text(node, builder)
      # Collapse runs of whitespace to a single space but keep meaningful
      # leading/trailing spaces so inline text ("Hello, ") stays readable.
      content = node.content.gsub(/\s+/, " ")
      return builder.line("whitespace") if content == " " # see #inline_space?
      return if content.strip.empty?

      builder.line("plain #{ruby_string(content)}")
    end

    def emit_raw_text(node, builder)
      content = node.content.strip
      return if content.empty?

      builder.line("# TODO: move inline script/style to an asset or helper")
      builder.line(config.raw_call(ruby_string(node.content)))
    end

    def emit_output(node, builder)
      code = sanitize_code(node.code)
      return if FormBuilder.transform(code, self, builder)
      return if RailsHelpers.transform(code, node, self, builder)

      if node.raw
        builder.line(config.raw_call(code))
      else
        builder.line("plain(#{code})")
      end
    end

    def emit_statement(node, builder)
      builder.line(sanitize_code(node.code))
    end

    def emit_control(node, builder)
      if config.ruby_ui? && node.branches.length == 1 &&
         (form = FormBuilder.form_scope(sanitize_code(node.branches.first.header)))
        return emit_form_control(node, form, builder)
      end

      node.branches.each do |branch|
        builder.line(sanitize_code(branch.header))
        builder.indent
        emit_children(meaningful(branch.children), builder)
        builder.dedent
      end
      builder.line("end")
    end

    # A form_with/form_for block whose fields map to RubyUI components. The
    # block variable (`|form|`) is dropped unless an unmapped `form.*` call needs it.
    def emit_form_control(node, form, builder)
      branch = node.branches.first
      header = sanitize_code(branch.header)
      header = strip_block_var(header) unless FormBuilder.needs_block_var?(form[:var], collect_codes(branch.children))

      @form_stack.push(form)
      builder.line(header)
      builder.indent
      emit_children(meaningful(branch.children), builder)
      builder.dedent
      builder.line("end")
    ensure
      @form_stack.pop
    end

    def strip_block_var(header)
      header.sub(/(\bdo\b)\s*\|[^|]*\|/, '\1')
    end

    # All Output/Statement codes anywhere under these nodes (used to decide
    # whether the form block variable is still referenced).
    def collect_codes(nodes, acc = [])
      nodes.each do |node|
        case node
        when Nodes::Output, Nodes::Statement then acc << node.code
        when Nodes::Control then node.branches.each { |b| collect_codes(b.children, acc) }
        when Nodes::Element, Nodes::Comment then collect_codes(node.children, acc)
        end
      end
      acc
    end

    def emit_comment(node, builder)
      if node.html && meaningful(node.children).any?
        builder.line("comment do")
        builder.indent
        text = node.text.strip
        builder.line("plain #{ruby_string(text)}") unless text.empty?
        emit_children(meaningful(node.children), builder)
        builder.dedent
        builder.line("end")
      elsif node.html
        text = node.text.strip
        builder.line("comment { #{ruby_string(text)} }") unless text.empty?
      else
        node.text.to_s.each_line { |line| builder.line("# #{line.chomp}") }
      end
    end

    def emit_doctype(node, builder)
      builder.line("doctype") if node.value =~ /doctype/i
    end

    # --- attribute helpers -------------------------------------------------

    def attr_pair(name, parts)
      if name == :__splat__
        code = parts.find { |kind, _| kind == :erb }&.dig(1)&.value
        return "**(#{code})"
      end

      "#{attr_key(name)}: #{attr_value(parts)}"
    end

    def attr_key(name)
      name =~ /\A[a-zA-Z_][a-zA-Z0-9_]*\z/ ? name : name.inspect
    end

    def attr_value(parts)
      return "true" if parts.nil?

      if parts.length == 1 && parts[0][0] == :erb && parts[0][1].type == :output
        bare_expression(sanitize_code(parts[0][1].value))
      elsif parts.all? { |kind, _| kind == :text }
        ruby_string(parts.map { |_, value| value }.join)
      else
        interpolated(parts)
      end
    end

    # Expressions with whitespace (`dom_id user`, `a ? b : c`) would parse
    # incorrectly inside the attribute argument list, so wrap them in parens.
    # Self-delimited expressions (`[a, b]`, `{a: 1}`, `dom_id(user, :x)`) are
    # safe as-is.
    def bare_expression(code)
      return code unless code =~ /\s/

      self_delimited?(code) ? code : "(#{code})"
    end

    GROUP_TOKENS = {
      on_lparen: 1, on_lbracket: 1, on_lbrace: 1,
      on_rparen: -1, on_rbracket: -1, on_rbrace: -1
    }.freeze
    CALL_PREFIX_TOKENS = %i[on_ident on_const on_ivar on_cvar on_gvar on_period].freeze

    # True when the code is a bracketed literal or a parenthesized call
    # (optionally on a receiver chain written without spaces) whose opening
    # bracket closes exactly at the end of the code.
    def self_delimited?(code)
      tokens = Ripper.lex(code)
      index = 0
      while index < tokens.length &&
            (CALL_PREFIX_TOKENS.include?(tokens[index][1]) ||
             (tokens[index][1] == :on_op && ["::", "&."].include?(tokens[index][2])))
        index += 1
      end
      return false if index.positive? && !%i[on_ident on_const].include?(tokens[index - 1][1])
      return false unless tokens[index] && GROUP_TOKENS[tokens[index][1]] == 1
      return false if index.positive? && tokens[index][1] != :on_lparen

      depth = 0
      tokens[index..].each_with_index do |token, offset|
        depth += GROUP_TOKENS.fetch(token[1], 0)
        return index + offset == tokens.length - 1 if depth.zero?
      end
      false
    rescue StandardError
      false
    end

    def interpolated(parts)
      buffer = +'"'
      parts.each do |kind, value|
        if kind == :text
          buffer << escape_inner(value)
        else
          buffer << "\#{#{sanitize_code(value.value)}}"
        end
      end
      buffer << '"'
      buffer
    end

    # --- misc helpers ------------------------------------------------------

    def element_method(name)
      name.to_s.downcase
    end

    # A whitespace-only text node on a single line between two siblings
    # (`<em>a</em> <%= b %>`) separates inline content and is kept (emitted as
    # Phlex's `whitespace`); whitespace spanning lines between tags is layout
    # and is dropped.
    def inline_space?(nodes, index)
      content = nodes[index].content
      !content.empty? && !content.include?("\n") && index.positive? && index < nodes.length - 1
    end

    def inlineable?(node)
      node.is_a?(Nodes::Text) ||
        (node.is_a?(Nodes::Output) && !node.raw && !special_output?(node.code))
    end

    def inline_value(node)
      if node.is_a?(Nodes::Text)
        ruby_string(node.content.strip)
      else
        sanitize_code(node.code)
      end
    end

    def special_output?(code)
      stripped = code.strip
      return true if stripped.start_with?("render", "yield")
      return true if FormBuilder.form_field?(stripped, current_form)

      RailsHelpers.html_helper?(stripped)
    end

    def sanitize_code(code)
      code = code.to_s
                 .gsub(/local_assigns\.fetch\(:(\w+)[^)]*\)/, '\1')
                 .gsub(/local_assigns\[:(\w+)\]/, '\1')
                 .strip
      code = rewrite_locals_to_ivars(code) if literal_locals.any?
      code
    end

    # With --literal, props set ivars and generate no readers, so every bare
    # reference to a detected local must become `@local`. Safe by design:
    # LocalsDetector only reports names that are never assigned or shadowed by
    # block params anywhere in the template (read-only identifiers).
    def literal_locals
      @literal_locals ||=
        if config.literal? && template&.partial?
          template.locals
        else
          []
        end
    end

    # Token-level rewrite via Ripper (lossless lexer): hash keys (`user:`) lex
    # as :on_label, symbols are preceded by :on_symbeg, string contents are
    # :on_tstring_content — none are :on_ident, so they're naturally skipped.
    # Interpolated code inside strings lexes as regular idents and is rewritten.
    def rewrite_locals_to_ivars(code)
      tokens = Ripper.lex(code)
      return code if tokens.nil? || tokens.empty?

      tokens.each_with_index.map do |(_, type, tok, _), index|
        next tok unless type == :on_ident && literal_locals.include?(tok)
        next tok if method_call_token?(tokens, index)

        "@#{tok}"
      end.join
    rescue StandardError
      code
    end

    # True when the ident is a method call (`x.user`, `x&.user`, `user(...)`)
    # or a symbol (`:user`) rather than a bare local reference.
    def method_call_token?(tokens, index)
      prev = significant_token(tokens, index, -1)
      return true if prev && (prev[1] == :on_period || prev[1] == :on_symbeg ||
                              (prev[1] == :on_op && ["&.", "::"].include?(prev[2])))

      following = significant_token(tokens, index, 1)
      following && following[1] == :on_lparen
    end

    def significant_token(tokens, index, step)
      index += step
      while index >= 0 && index < tokens.length
        return tokens[index] unless %i[on_sp on_ignored_nl on_nl].include?(tokens[index][1])

        index += step
      end
      nil
    end

    def ruby_string(string)
      "\"#{escape_inner(string)}\""
    end

    STRING_ESCAPES = {
      "\\" => "\\\\",
      "\"" => "\\\"",
      "\n" => "\\n",
      "\t" => "\\t",
      "\r" => "\\r",
      "\#{" => "\\\#{"
    }.freeze

    # Invisible / easily-confused characters (no-break and other Unicode
    # spaces, soft hyphen, zero-width characters, BOM) — typically from a
    # decoded `&nbsp;` — are written as \u escapes so the generated source
    # stays readable.
    INVISIBLE_CHARS = /[ ­ -‏ -  -⁤﻿]/

    def escape_inner(string)
      string.to_s.gsub(/[\\"\n\t\r]|\#\{|#{INVISIBLE_CHARS}/o) do |match|
        STRING_ESCAPES.fetch(match) { format("\\u%04X", match.ord) }
      end
    end
  end
end
