# frozen_string_literal: true

require "ripper"

module RubyUIConverter
  # Splits a Ruby string literal into its literal text and interpolated code.
  # Used by the HAML front-end, whose parser hands interpolated text and
  # attribute values over as Ruby source (`"Hello #{name}!"`), so they can be
  # turned into the same Text/Output nodes and attribute "parts" the ERB
  # front-end produces. Lexing is done with Ripper (stdlib), so this has no
  # dependency on the haml gem.
  module RubyLiteral
    module_function

    QUOTES = ['"', "'"].freeze

    # '"Hi #{name}!"' -> [[:text, "Hi "], [:code, "name"], [:text, "!"]]
    # "'static'"      -> [[:text, "static"]]
    #
    # Returns nil unless `code` is exactly one single- or double-quoted string
    # literal (so `"a" + b`, `"a".upcase`, `:sym`, `%w[]` and heredocs are
    # rejected), or when an escape sequence can't be decoded safely.
    def string_parts(code)
      code = code.to_s.strip
      return nil unless single_string_literal?(code)

      tokens = Ripper.lex(code)
      quote = tokens.first[2]
      return nil unless QUOTES.include?(quote) && tokens.last[1] == :on_tstring_end

      parts = scan_parts(tokens[1...-1], quote)
      parts && merge_text(parts)
    rescue StandardError
      nil
    end

    def single_string_literal?(code)
      sexp = Ripper.sexp(code)
      statements = sexp && sexp[1]
      statements.is_a?(Array) && statements.length == 1 &&
        statements[0].is_a?(Array) && statements[0][0] == :string_literal
    end

    def scan_parts(tokens, quote)
      parts = []
      depth = 0
      buffer = +""
      embedded_var = false

      tokens.each do |(_, type, tok, _)|
        if depth.positive?
          depth += 1 if type == :on_embexpr_beg
          depth -= 1 if type == :on_embexpr_end
          depth.zero? ? parts << [:code, buffer.strip] : buffer << tok
          next
        end

        case type
        when :on_tstring_content
          parts << [:text, unescape(tok, quote)]
        when :on_embexpr_beg
          depth = 1
          buffer = +""
        when :on_embvar # "#@ivar" / "#$global" shorthand
          embedded_var = true
        when :on_ivar, :on_gvar, :on_cvar
          return nil unless embedded_var

          embedded_var = false
          parts << [:code, tok]
        else
          return nil
        end
      end

      depth.zero? ? parts : nil
    end

    # Decodes the escapes of a literal's raw content. String#undump understands
    # every escape String#dump emits (which is how haml hands text over) but
    # rejects raw non-ASCII characters, so those are \u-escaped first.
    def unescape(content, quote)
      return content.gsub(/\\([\\'])/, '\1') if quote == "'"
      return content unless content.include?("\\")

      ascii = content.gsub(/[^\x00-\x7F]/) { |char| format("\\u{%x}", char.ord) }
      "\"#{ascii}\"".undump.force_encoding(content.encoding)
    end

    def merge_text(parts)
      parts.each_with_object([]) do |part, merged|
        if part[0] == :text && merged.last && merged.last[0] == :text
          merged.last[1] = merged.last[1] + part[1]
        elsif part[0] != :text || !part[1].empty?
          merged << part.dup
        end
      end
    end
  end
end
