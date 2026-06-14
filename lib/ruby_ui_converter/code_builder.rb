# frozen_string_literal: true

module RubyUIConverter
  # Accumulates indented lines of Ruby source.
  class CodeBuilder
    def initialize(indent: "  ", level: 0)
      @indent = indent
      @level = level
      @lines = []
    end

    attr_reader :level

    def line(str = nil)
      @lines << (str.nil? || str.empty? ? "" : (@indent * @level) + str)
      self
    end

    def indent
      @level += 1
      self
    end

    def dedent
      @level -= 1 if @level.positive?
      self
    end

    def to_s
      "#{@lines.join("\n")}\n"
    end
  end
end
