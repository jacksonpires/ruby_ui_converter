# frozen_string_literal: true

module RubyUIConverter
  # AST node types produced by the Parser and consumed by the Transformer.
  #
  # Attribute values are stored as "parts": an array whose entries are either
  # `[:text, "literal"]` or `[:erb, <Lexer::Token>]`. This lets the transformer
  # decide between a plain string, a bare Ruby expression or an interpolated
  # string when emitting the attribute.
  module Nodes
    class Base; end

    class Document < Base
      attr_reader :children

      def initialize
        @children = []
      end
    end

    class Element < Base
      attr_reader :name, :attributes, :children
      attr_accessor :self_closing

      def initialize(name:, attributes: [], self_closing: false)
        @name = name
        @attributes = attributes
        @children = []
        @self_closing = self_closing
      end

      # Returns the literal value of an attribute when it has no ERB parts,
      # otherwise nil. Useful for ComponentMap matchers/emitters.
      def static_attr(name)
        attr = attributes.find { |attr_name, _| attr_name == name }
        return nil unless attr && attr[1]
        return nil unless attr[1].all? { |kind, _| kind == :text }

        attr[1].map { |_, value| value }.join
      end

      # Returns the static CSS classes when the `class` attribute has no ERB,
      # otherwise an empty array. Useful for ComponentMap matchers.
      def static_classes
        static_attr("class").to_s.split
      end

      def attr?(name)
        attributes.any? { |attr_name, _| attr_name == name }
      end
    end

    class Text < Base
      attr_reader :content

      def initialize(content:)
        @content = content
      end
    end

    # Raw inner content of <script>/<style> elements (kept verbatim).
    class RawText < Base
      attr_reader :content

      def initialize(content:)
        @content = content
      end
    end

    # <%= code %> or <%== code %>
    class Output < Base
      attr_reader :code, :raw

      def initialize(code:, raw: false)
        @code = code
        @raw = raw
      end
    end

    # <% code %> that is a plain statement (assignment, method call, etc.)
    class Statement < Base
      attr_reader :code

      def initialize(code:)
        @code = code
      end
    end

    class Comment < Base
      attr_reader :text, :html

      def initialize(text:, html: false)
        @text = text
        @html = html
      end
    end

    class Doctype < Base
      attr_reader :value

      def initialize(value:)
        @value = value
      end
    end

    # A single branch of a control structure (if / elsif / else / when / each-do...).
    class Branch
      attr_reader :header, :children

      def initialize(header:)
        @header = header
        @children = []
      end
    end

    # if/unless/case/while statements and `... do |x|` blocks.
    class Control < Base
      attr_reader :branches
      attr_accessor :block, :output

      def initialize(block: false, output: false)
        @branches = []
        @block = block
        @output = output
      end
    end
  end
end
