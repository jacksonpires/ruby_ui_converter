# frozen_string_literal: true

module RubyUIConverter
  # Turns the attributes of a HAML tag (as Haml::Parser reports them) into the
  # converter's attribute list — `[[name, parts], ...]`, the same shape the ERB
  # Parser builds (see Nodes) — merging them the way HAML does:
  #
  #   * sources, in order: static (`.a#b`, `(x="y")`, `(disabled)`), html-style
  #     dynamic `(x=expr)`, the `{...}` hash, then the object reference `[@obj]`;
  #   * `class` values are merged (space-joined), `id` values joined with `_`;
  #     any other repeated attribute is overridden by the later source;
  #   * `false`/`nil` literals drop the attribute, `true` makes it boolean;
  #   * literal `data:`/`aria:` hashes expand to hyphenated attributes
  #     (`data: {turbo_method: :delete}` -> `"data-turbo-method": "delete"`);
  #   * string literals become text/erb parts (so ComponentMap matchers like
  #     `static_classes` keep working); symbol literals become text;
  #   * a hash Haml can't split (`{html_attrs}`, `{**opts}`) becomes a
  #     `**(...)` splat.
  class HamlAttributes
    NESTED = %w[data aria].freeze
    MERGED = { "class" => " ", "id" => "_" }.freeze

    Entry = Struct.new(:name, :values)

    def self.build(tag_value)
      new(tag_value).build
    end

    def initialize(tag_value)
      @tag = tag_value
      @entries = []
    end

    def build
      static_attributes
      dynamic = @tag[:dynamic_attributes]
      dynamic_hash(dynamic&.new)
      dynamic_hash(dynamic&.old)
      object_reference
      @entries.map { |entry| finalize(entry) }
    end

    private

    # --- sources -----------------------------------------------------------

    def static_attributes
      @tag[:attributes].to_h.each do |name, value|
        case value
        when true then add(name.to_s, [:bool])
        when nil, false then add(name.to_s, nil)
        else add(name.to_s, [:parts, [[:text, value.to_s]]])
        end
      end
    end

    def dynamic_hash(hash_code)
      return if hash_code.nil? || hash_code.strip.empty?

      pairs = ::Haml::AttributeParser.parse(hash_code)
      if pairs
        pairs.each { |name, code| add_code(name.to_s, code) }
      else
        @entries << Entry.new(:__splat__, [[:parts, [erb(splat_code(hash_code))]]])
      end
    end

    # `%div[@user]` / `%div[@user, :edit]` -> Rails' dom_id / dom_class.
    def object_reference
      ref = @tag[:object_ref]
      return if ref.nil? || ref == :nil

      args = RailsHelpers.split_args(ref.to_s.strip.sub(/\A\[/, "").sub(/\]\z/, ""))
      return if args.empty?

      call_args = args.first(2).join(", ")
      add("id", [:code, "dom_id(#{call_args})"])
      add("class", [:code, "dom_class(#{call_args})"])
    end

    # --- values ------------------------------------------------------------

    def add_code(name, code)
      if NESTED.include?(name) && (nested = nested_hash(code))
        nested.each { |key, value| add_code("#{name}-#{key.to_s.tr("_", "-")}", value) }
      else
        add(name, value_for(code))
      end
    end

    def nested_hash(code)
      code = code.to_s.strip
      return nil unless code.start_with?("{")

      ::Haml::AttributeParser.parse(code)
    end

    # nil means "drop the attribute".
    def value_for(code)
      code = code.to_s.strip
      return [:bool] if code == "true"
      return nil if %w[false nil].include?(code)
      return [:parts, [[:text, code[1..]]]] if code.match?(/\A:\w+[?!]?\z/)

      parts = RubyLiteral.string_parts(code)
      return [:parts, parts.map { |kind, value| kind == :text ? [:text, value] : erb(value) }] if parts

      [:code, code]
    end

    def add(name, value)
      entry = @entries.find { |e| e.name == name }

      if MERGED.key?(name)
        return unless value

        entry ? entry.values << value : @entries << Entry.new(name, [value])
      elsif value.nil?
        @entries.delete(entry)
      elsif entry
        entry.values = [value]
      else
        @entries << Entry.new(name, [value])
      end
    end

    # --- output ------------------------------------------------------------

    def finalize(entry)
      values = entry.values
      return [entry.name, nil] if values == [[:bool]]
      return [entry.name, to_parts(values.first)] if values.length == 1

      separator = MERGED.fetch(entry.name, " ")
      if entry.name == "class" && values.any? { |kind, _| kind == :code }
        # Arbitrary expressions may be arrays/nil: let Phlex flatten them.
        [entry.name, [erb("[#{values.map { |value| to_code(value) }.join(", ")}]")]]
      else
        parts = values.flat_map.with_index do |value, index|
          (index.zero? ? [] : [[:text, separator]]) + to_parts(value)
        end
        [entry.name, parts]
      end
    end

    def to_parts(value)
      kind, payload = value
      case kind
      when :parts then payload
      when :code then [erb(payload)]
      when :bool then [erb("true")]
      end
    end

    def to_code(value)
      kind, payload = value
      return payload if kind == :code
      return "true" if kind == :bool
      return payload[0][1].value if payload.length == 1 && payload[0][0] == :erb

      body = payload.map do |part_kind, part|
        part_kind == :text ? escape(part) : "\#{#{part.value}}"
      end.join
      "\"#{body}\""
    end

    def escape(text)
      text.gsub(/[\\"\n\t]|\#\{/) do |match|
        { "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\t" => "\\t", "\#{" => "\\\#{" }[match]
      end
    end

    # "{a: 1}" -> "{a: 1}"; "{html_attrs}" -> "html_attrs" (haml treats the
    # braces' content as an argument list, so a bare expression is the hash).
    def splat_code(hash_code)
      inner = hash_code.to_s.strip.sub(/\A\{/, "").sub(/\}\z/, "").strip
      args = RailsHelpers.split_args(inner)
      pairs = args.any? { |arg| arg =~ /\A(\*\*|[\w?!]+:(?!:)|"[^"]*":|'[^']*':)/ || arg.include?("=>") }
      pairs ? "{#{inner}}" : inner
    end

    def erb(code)
      [:erb, Lexer::Token.new(type: :output, value: code, raw: false)]
    end
  end
end
