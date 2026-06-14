# frozen_string_literal: true

module RubyUIConverter
  # Builds a unified HTML + ERB tree from a source template.
  #
  # The tricky part is that HTML nesting (tags) and Ruby nesting (if/each/do
  # ... end) interleave. We track both on a single stack and pop tolerantly so
  # that well-formed templates produce a correct tree and slightly malformed
  # ones degrade gracefully instead of raising.
  class Parser
    def initialize(source)
      @html, @registry = Lexer.new(source).tokenize_with_placeholders
    end

    def parse
      root = Nodes::Document.new
      stack = [root]

      HtmlTokenizer.new(@html).tokens.each do |token|
        dispatch(token, stack)
      end

      root
    end

    private

    def dispatch(token, stack)
      case token[0]
      when :text
        emit_text(token[1], stack)
      when :html_comment
        append(stack, Nodes::Comment.new(text: strip_placeholders(token[1]), html: true))
      when :doctype
        append(stack, Nodes::Doctype.new(value: token[1]))
      when :open
        element = Nodes::Element.new(name: token[1], attributes: build_attrs(token[2]))
        append(stack, element)
        stack.push(element)
      when :selfclose
        append(stack, Nodes::Element.new(name: token[1], attributes: build_attrs(token[2]), self_closing: true))
      when :raw_element
        element = Nodes::Element.new(name: token[1], attributes: build_attrs(token[2]))
        element.children << Nodes::RawText.new(content: token[3]) unless token[3].to_s.strip.empty?
        append(stack, element)
      when :close
        close_element(stack, token[1])
      end
    end

    # --- tree helpers ------------------------------------------------------

    def append(stack, node)
      container(stack.last) << node
    end

    def container(node)
      case node
      when Nodes::Control
        node.branches.last.children
      else
        node.children
      end
    end

    def close_element(stack, name)
      target = name.to_s.downcase
      index = stack.rindex { |node| node.is_a?(Nodes::Element) && node.name.to_s.downcase == target }
      stack.slice!(index..) if index && index.positive?
    end

    def close_control(stack)
      while stack.size > 1
        node = stack.pop
        break if node.is_a?(Nodes::Control)
      end
    end

    # --- text + ERB --------------------------------------------------------

    def emit_text(text, stack)
      split_parts(text).each do |kind, value|
        if kind == :text
          append(stack, Nodes::Text.new(content: value)) unless value.empty?
        else
          emit_erb(value, stack)
        end
      end
    end

    def emit_erb(token, stack)
      case token.type
      when :output
        if block_opener?(token.value)
          control = Nodes::Control.new(block: true, output: true)
          control.branches << Nodes::Branch.new(header: token.value)
          append(stack, control)
          stack.push(control)
        else
          append(stack, Nodes::Output.new(code: token.value, raw: token.raw))
        end
      when :comment
        append(stack, Nodes::Comment.new(text: token.value, html: false))
      when :eval
        handle_eval(token.value, stack)
      end
    end

    def handle_eval(code, stack)
      case classify(code)
      when :opener
        control = Nodes::Control.new(block: block_opener?(code))
        control.branches << Nodes::Branch.new(header: code)
        append(stack, control)
        stack.push(control)
      when :mid
        control = stack.reverse.find { |node| node.is_a?(Nodes::Control) }
        if control
          control.branches << Nodes::Branch.new(header: code)
          stack.pop until stack.last.equal?(control) || stack.size <= 1
        else
          append(stack, Nodes::Statement.new(code: code))
        end
      when :close
        close_control(stack)
      else
        append(stack, Nodes::Statement.new(code: code))
      end
    end

    def classify(code)
      stripped = code.strip
      return :close if stripped == "end"
      return :mid if stripped =~ /\A(else|elsif|when|in|rescue|ensure)\b/
      return :opener if stripped =~ /\A(if|unless|case|while|until|for|begin)\b/
      return :opener if block_opener?(stripped)

      :statement
    end

    def block_opener?(code)
      code =~ /\bdo\s*(\|[^|]*\|)?\s*\z/ ? true : false
    end

    # --- attributes + placeholders ----------------------------------------

    def build_attrs(raw_attrs)
      raw_attrs.map do |name, value|
        if name.include?("RUCxERBx") && value.nil?
          [:__splat__, split_parts(name)]
        else
          [name, value.nil? ? nil : split_parts(value)]
        end
      end
    end

    def split_parts(string)
      parts = []
      pos = 0
      str = string.to_s

      str.scan(Lexer::PLACEHOLDER_PATTERN) do
        match = Regexp.last_match
        parts << [:text, str[pos...match.begin(0)]] if match.begin(0) > pos
        parts << [:erb, @registry.fetch(Lexer.placeholder(match[1]))]
        pos = match.end(0)
      end

      parts << [:text, str[pos..]] if pos < str.length
      parts
    end

    def strip_placeholders(string)
      split_parts(string).map do |kind, value|
        kind == :text ? value : value.value.to_s
      end.join
    end
  end
end
