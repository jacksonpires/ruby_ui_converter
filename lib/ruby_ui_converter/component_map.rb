# frozen_string_literal: true

module RubyUIConverter
  # Maps HTML elements onto RubyUI (or any Phlex) components.
  #
  # Two layers of rules:
  #   * user rules, added with #register — always win;
  #   * fallback rules — the built-in RubyUI element mapping installed by
  #     Configuration when `ruby_ui` is enabled (the default).
  #
  # Each rule has:
  #   * matcher: ->(Nodes::Element) { Boolean }
  #   * emitter: ->(Nodes::Element, Transformer, CodeBuilder) { ... }
  #
  # The emitter is responsible for writing the component call. It can use the
  # transformer's public helpers (kit_component, wrap_component, emit_children,
  # render_attrs, meaningful).
  #
  # Example of a custom rule (overrides the built-in `button` mapping):
  #
  #   config.component_map.register(
  #     ->(el) { el.name == "button" && el.static_classes.include?("danger") }
  #   ) do |el, transformer, builder|
  #     transformer.kit_component("Button", el, builder, extra: "variant: :destructive")
  #   end
  class ComponentMap
    Rule = Struct.new(:matcher, :emitter)

    # Element name -> [RubyUI kit component, void?] for 1:1 mappings.
    ELEMENT_COMPONENTS = {
      "button" => ["Button", false],
      "textarea" => ["Textarea", false],
      "select" => ["NativeSelect", false],
      "option" => ["NativeSelectOption", false],
      "table" => ["Table", false],
      "thead" => ["TableHeader", false],
      "tbody" => ["TableBody", false],
      "tfoot" => ["TableFooter", false],
      "tr" => ["TableRow", false],
      "th" => ["TableHead", false],
      "td" => ["TableCell", false],
      "caption" => ["TableCaption", false],
      "hr" => ["Separator", true]
    }.freeze

    def initialize
      @rules = []
      @fallback_rules = []
    end

    def register(matcher, &emitter)
      @rules << Rule.new(matcher, emitter)
      self
    end

    def register_fallback(matcher, &emitter)
      @fallback_rules << Rule.new(matcher, emitter)
      self
    end

    # @return [Proc, nil] the emitter for the first matching rule.
    # User rules take precedence over the built-in fallback rules.
    def lookup(node)
      rule = @rules.find { |r| r.matcher.call(node) } ||
             @fallback_rules.find { |r| r.matcher.call(node) }
      rule&.emitter
    end

    def empty?
      @rules.empty? && @fallback_rules.empty?
    end

    # Built-in mapping of basic HTML elements onto RubyUI kit components
    # (Link, Button, Input, ...). Installed as fallback rules so user rules
    # registered with #register always win.
    def self.rubyui_rules(map)
      # <a href=...> -> Link(href: ...). Anchors without href stay plain.
      map.register_fallback(->(el) { el.name == "a" && el.attr?("href") }) do |el, t, b|
        t.kit_component("Link", el, b)
      end

      # <input> -> Checkbox / RadioButton / Input, dispatched on a static
      # type attribute (Checkbox and RadioButton set their own type).
      map.register_fallback(->(el) { el.name == "input" }) do |el, t, b|
        case el.static_attr("type")
        when "checkbox" then t.kit_component("Checkbox", el, b, except: ["type"], void: true)
        when "radio" then t.kit_component("RadioButton", el, b, except: ["type"], void: true)
        else t.kit_component("Input", el, b, void: true)
        end
      end

      ELEMENT_COMPONENTS.each do |element, (component, void)|
        map.register_fallback(->(el) { el.name == element }) do |el, t, b|
          t.kit_component(component, el, b, void: void)
        end
      end

      # Rails flash paragraphs (<p id="notice">/<p id="alert">) -> RubyUI Alert.
      # `notice` is a success message; `alert` is an error (destructive).
      map.register_fallback(->(el) { el.name == "p" && %w[notice alert].include?(el.static_attr("id")) }) do |el, t, b|
        kind = el.static_attr("id")
        variant = kind == "alert" ? "destructive" : "success"
        # mb-5 keeps the alert from sitting flush against the content below it
        # (the scaffold's flash <p> had mb-5, dropped when we replace the tag).
        b.line(%(Alert(variant: :#{variant}, class: "mb-5") do))
        b.indent
        b.line(%(AlertTitle { "#{kind.capitalize}" }))
        t.component_block("AlertDescription", el.children, b)
        b.dedent
        b.line("end")
      end

      # Class-based heuristics for common Bootstrap-ish markup.
      map.register_fallback(->(el) { el.static_classes.include?("badge") }) do |el, t, b|
        t.kit_component("Badge", el, b)
      end

      map.register_fallback(->(el) { el.static_classes.include?("card") }) do |el, t, b|
        t.kit_component("Card", el, b)
      end

      map
    end
  end
end
