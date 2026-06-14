# frozen_string_literal: true

require "strscan"

module RubyUIConverter
  # A small, forgiving HTML tokenizer. It does not validate markup; it emits a
  # flat stream of tokens that the Parser turns into a tree. ERB placeholders
  # (from the Lexer) are treated as ordinary text/attribute characters.
  #
  # Token shapes:
  #   [:text, string]
  #   [:html_comment, inner]
  #   [:doctype, raw]
  #   [:open, name, attrs]        attrs => [[name, value_or_nil], ...]
  #   [:selfclose, name, attrs]
  #   [:close, name]
  #   [:raw_element, name, attrs, inner_text]   (script/style)
  class HtmlTokenizer
    VOID = %w[area base br col embed hr img input link meta param source track wbr].freeze
    RAW = %w[script style].freeze

    def initialize(html)
      @s = StringScanner.new(html.to_s)
    end

    def tokens
      out = []

      until @s.eos?
        if @s.scan(/<!--(.*?)-->/m)
          out << [:html_comment, @s[1]]
        elsif @s.scan(/<!\[CDATA\[.*?\]\]>/m)
          out << [:text, @s.matched]
        elsif @s.scan(/<![^>]*>/m)
          out << [:doctype, @s.matched]
        elsif @s.scan(%r{</\s*([a-zA-Z][\w:-]*)\s*>})
          out << [:close, @s[1]]
        elsif @s.scan(/<([a-zA-Z][\w:-]*)/)
          out << scan_tag(@s[1])
        else
          text = @s.scan(/[^<]+/) || @s.getch
          out << [:text, text]
        end
      end

      out
    end

    private

    def scan_tag(name)
      attrs, self_close = scan_attrs

      if RAW.include?(name.downcase) && !self_close
        inner = scan_raw_content(name)
        [:raw_element, name, attrs, inner]
      elsif self_close || VOID.include?(name.downcase)
        [:selfclose, name, attrs]
      else
        [:open, name, attrs]
      end
    end

    def scan_attrs
      attrs = []

      loop do
        @s.skip(/\s+/)

        return [attrs, true] if @s.scan(%r{/\s*>})
        return [attrs, false] if @s.scan(/>/)
        return [attrs, false] if @s.eos?

        if @s.scan(%r{([^\s=/>]+)})
          name = @s[1]
          value = nil

          if @s.skip(/\s*=\s*/)
            value =
              if @s.scan(/"([^"]*)"/)
                @s[1]
              elsif @s.scan(/'([^']*)'/)
                @s[1]
              elsif @s.scan(/([^\s>]+)/)
                @s[1]
              end
          end

          attrs << [name, value]
        else
          @s.getch # defensive: never loop forever
        end
      end
    end

    def scan_raw_content(name)
      closing = %r{</\s*#{Regexp.escape(name)}\s*>}im
      captured = @s.scan_until(closing)

      if captured
        captured.sub(closing, "")
      else
        rest = @s.rest
        @s.terminate
        rest
      end
    end
  end
end
