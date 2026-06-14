# frozen_string_literal: true

require "set"

module RubyUIConverter
  # Heuristically detects the locals a partial expects, so the generated
  # component can declare keyword arguments and private readers.
  #
  # This is intentionally conservative and best-effort: it favors a few clearly
  # detectable cases (local_assigns[:x]) plus bare identifiers that look like
  # locals. Anything it misses can be added by hand to the generated component.
  class LocalsDetector
    KEYWORDS = %w[
      if elsif else end unless case when in while until for do begin rescue
      ensure return yield self nil true false and or not then break next redo
      retry def class module super defined lambda proc new raise puts print p
      require require_relative attr_reader attr_accessor attr_writer
    ].to_set

    def initialize(tree)
      @tree = tree
    end

    def locals
      codes = []
      collect(@tree.children, codes)

      found = Set.new
      assigned = Set.new
      block_params = Set.new

      codes.each do |code|
        code.scan(/\|([^|]*)\|/) do
          Regexp.last_match(1).split(",").each do |param|
            block_params << param.strip.sub(/\A\*+/, "").sub(/:.*\z/, "").strip
          end
        end
        code.scan(/([a-z_]\w*)\s*=(?!=)/) { assigned << Regexp.last_match(1) }
        code.scan(/local_assigns\[:(\w+)\]/) { found << Regexp.last_match(1) }
        code.scan(/local_assigns\.fetch\(:(\w+)/) { found << Regexp.last_match(1) }
      end

      codes.each do |code|
        without_strings = code.gsub(/"[^"]*"|'[^']*'/, " ")
        without_strings.scan(/(?<![.\w:@$])([a-z_]\w*)/) do
          name = Regexp.last_match(1)
          after = Regexp.last_match.post_match

          next if after =~ /\A\s*\(/          # method call
          next if after =~ /\A\s*=(?!=)/      # assignment target
          next if after =~ /\A:(?!:)/         # keyword/hash key
          next if KEYWORDS.include?(name)
          next if RailsHelpers::HTML_HELPERS.include?(name)
          next if RailsHelpers::KNOWN_HELPERS.include?(name)
          next if block_params.include?(name)
          next if assigned.include?(name)

          found << name
        end
      end

      found.delete("local_assigns")
      found.to_a.sort
    end

    # Instance variables a top-level view reads from its controller (`@products`),
    # so the generated component can take them as keyword arguments. Excludes any
    # ivar assigned within the template and class variables (`@@foo`). Strings are
    # stripped first, like #locals, to avoid `@` inside literals (`"x@y.com"`).
    def ivars
      codes = []
      collect(@tree.children, codes)

      found = Set.new
      assigned = Set.new

      codes.each do |code|
        without_strings = code.gsub(/"[^"]*"|'[^']*'/, " ")
        without_strings.scan(/(?<!@)@([a-zA-Z_]\w*)\s*=(?!=)/) { assigned << Regexp.last_match(1) }
        without_strings.scan(/(?<!@)@([a-zA-Z_]\w*)/) { found << Regexp.last_match(1) }
      end

      (found - assigned).to_a.sort
    end

    private

    def collect(nodes, codes)
      nodes.each do |node|
        case node
        when Nodes::Output, Nodes::Statement
          codes << node.code
        when Nodes::Control
          node.branches.each do |branch|
            codes << branch.header
            collect(branch.children, codes)
          end
        when Nodes::Element
          node.attributes.each do |(_, parts)|
            next unless parts

            parts.each do |kind, value|
              codes << value.value if kind == :erb
            end
          end
          collect(node.children, codes)
        end
      end
    end
  end
end
