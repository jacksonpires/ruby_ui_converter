# frozen_string_literal: true

module RubyUIConverter
  # Splits an ERB document into HTML (with placeholders) + a registry of ERB
  # tokens. Each ERB tag is replaced in the source by a unique placeholder so
  # the HTML tokenizer can run over a well-formed string even when ERB appears
  # inside tags/attributes. The placeholder uses only [A-Za-z0-9_] characters,
  # which the HTML tokenizer treats as inert text/identifiers.
  class Lexer
    Token = Struct.new(:type, :value, :raw, keyword_init: true)

    # Matches <% %>, <%= %>, <%== %>, <%# %> with optional trim markers (<%- -%>).
    PATTERN = /<%(={1,2}|#|-)?(.*?)(-)?%>/m

    PLACEHOLDER_PREFIX = "RUCxERBx"
    PLACEHOLDER_SUFFIX = "xERBxRUC"
    PLACEHOLDER_PATTERN = /RUCxERBx(\d+)xERBxRUC/

    def initialize(source)
      @source = source.to_s
    end

    # @return [Array(String, Hash{String => Token})]
    def tokenize_with_placeholders
      registry = {}
      index = 0

      html = @source.gsub(PATTERN) do
        marker = Regexp.last_match(1)
        code = Regexp.last_match(2)
        key = self.class.placeholder(index)
        registry[key] = build_token(marker, code)
        index += 1
        key
      end

      [html, registry]
    end

    def build_token(marker, code)
      code = code.to_s
      case marker
      when "#"
        Token.new(type: :comment, value: code.strip, raw: false)
      when "="
        Token.new(type: :output, value: code.strip, raw: false)
      when "=="
        Token.new(type: :output, value: code.strip, raw: true)
      else
        Token.new(type: :eval, value: code.strip, raw: false)
      end
    end

    def self.placeholder(index)
      "#{PLACEHOLDER_PREFIX}#{index}#{PLACEHOLDER_SUFFIX}"
    end
  end
end
