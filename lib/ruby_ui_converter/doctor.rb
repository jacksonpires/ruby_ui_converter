# frozen_string_literal: true

module RubyUIConverter
  # Post-conversion diagnostics: inspects the target app (the nearest Gemfile
  # at or above the converted path) for the prerequisites the generated code
  # needs — phlex-rails, the ruby_ui gem + generated components and, with
  # --literal, the literal gem + Literal::Properties on the base class.
  #
  # The Doctor only diagnoses; executing the fix commands (and prompting the
  # user) is the CLI's responsibility. Commands starting with "#" are manual
  # hints, not executable; issues may also carry a `fixer` proc that applies
  # a file edit (e.g. inserting `extend Literal::Properties`).
  class Doctor
    Issue = Struct.new(:description, :commands, :fixer, keyword_init: true)

    # Emitted kit component -> `ruby_ui:component` generator family.
    COMPONENT_FAMILIES = {
      "Link" => "Link", "Button" => "Button", "Input" => "Input",
      "Checkbox" => "Checkbox", "RadioButton" => "RadioButton",
      "Textarea" => "Textarea",
      "NativeSelect" => "NativeSelect", "NativeSelectOption" => "NativeSelect",
      "Table" => "Table", "TableHeader" => "Table", "TableBody" => "Table",
      "TableFooter" => "Table", "TableRow" => "Table", "TableHead" => "Table",
      "TableCell" => "Table", "TableCaption" => "Table",
      "Separator" => "Separator", "Badge" => "Badge", "Card" => "Card",
      "FormField" => "Form", "FormFieldLabel" => "Form",
      "FormFieldError" => "Form", "FormFieldHint" => "Form",
      "Alert" => "Alert", "AlertTitle" => "Alert", "AlertDescription" => "Alert"
    }.freeze

    def initialize(results, config:, start_path:)
      @results = results
      @config = config
      @start_path = File.expand_path(start_path)
    end

    # The nearest directory at or above start_path containing a Gemfile.
    # nil when the converted path is not inside a bundled app.
    def app_root
      return @app_root if defined?(@app_root)

      dir = File.directory?(@start_path) ? @start_path : File.dirname(@start_path)
      @app_root = loop do
        break dir if File.exist?(File.join(dir, "Gemfile"))

        parent = File.dirname(dir)
        break nil if parent == dir

        dir = parent
      end
    end

    def issues
      return [] unless app_root

      [
        phlex_rails_issue,
        literal_gem_issue,
        literal_properties_issue,
        ruby_ui_gem_issue,
        missing_components_issue,
        tw_animate_issue
      ].compact
    end

    private

    def gemfile
      @gemfile ||= File.read(File.join(app_root, "Gemfile"))
    end

    def gem?(name)
      gemfile.match?(/^\s*gem\s+["']#{Regexp.escape(name)}["']/)
    end

    def phlex_rails_issue
      return if gem?("phlex-rails")

      Issue.new(
        description: %(gem "phlex-rails" not in Gemfile (required by the generated Phlex classes)),
        commands: ["bundle add phlex-rails", "bin/rails generate phlex:install"]
      )
    end

    def literal_gem_issue
      return unless @config.literal?
      return if gem?("literal")

      Issue.new(
        description: %(gem "literal" not in Gemfile (required by --literal props)),
        commands: ["bundle add literal"]
      )
    end

    def literal_properties_issue
      return unless @config.literal?

      base = base_component_file
      if base.nil?
        return Issue.new(
          description: "no base component class found to extend Literal::Properties",
          commands: ["# add `extend Literal::Properties` to your base component class"]
        )
      end
      return if File.read(base).include?("Literal::Properties")

      rel = base.delete_prefix("#{app_root}/")
      Issue.new(
        description: "Literal::Properties not extended in #{rel}",
        commands: ["# add `extend Literal::Properties` to #{rel} (auto-applied on install)"],
        fixer: lambda do
          content = File.read(base)
          updated = content.sub(/^(\s*class\s+\S+\s*<\s*\S+.*)$/) do
            "#{Regexp.last_match(1)}\n  extend Literal::Properties"
          end
          File.write(base, updated) unless updated == content
        end
      )
    end

    def base_component_file
      ["app/components/base.rb", "app/views/base.rb"]
        .map { |rel| File.join(app_root, rel) }
        .find { |path| File.exist?(path) }
    end

    def ruby_ui_gem_issue
      return unless @config.ruby_ui? && emitted_families.any?
      return if gem?("ruby_ui")

      Issue.new(
        description: %(gem "ruby_ui" not in Gemfile (the generated code calls RubyUI components)),
        commands: ["bundle add ruby_ui", "bin/rails generate ruby_ui:install"]
      )
    end

    def missing_components_issue
      return unless @config.ruby_ui?

      missing = emitted_families.reject { |family| component_installed?(family) }
      return if missing.empty?

      Issue.new(
        description: "RubyUI components not generated: #{missing.join(", ")}",
        # ruby_ui:component takes a single component per invocation, so emit one
        # command per missing component rather than a single multi-arg call.
        commands: missing.map { |family| "bin/rails generate ruby_ui:component #{family}" }
      )
    end

    # Which generator families the converted code actually references.
    def emitted_families
      @emitted_families ||= begin
        code = @results.map(&:code).compact.join("\n")
        COMPONENT_FAMILIES.select { |name, _| code.match?(/\b#{name}\(/) }
                          .values.uniq
      end
    end

    def component_installed?(family)
      snake = family.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      File.directory?(File.join(app_root, "app/components/ruby_ui", snake))
    end

    TW_ANIMATE_URL = "https://cdn.jsdelivr.net/npm/tw-animate-css/dist/tw-animate.css"
    TW_ANIMATE_IMPORT = /@import\s+["'][^"']*tw-animate-css\.js["'];?/

    # `ruby_ui:install` pins tw-animate-css via importmap, but the package is
    # CSS-only and the pin fails on jspm — leaving application.css importing a
    # vendor file that was never downloaded (breaks tailwindcss:build/bin/dev).
    # Fix: vendor the real CSS next to application.css and point the import
    # at it.
    def tw_animate_issue
      css_path = File.join(app_root, "app/assets/tailwind/application.css")
      return unless File.exist?(css_path)
      return unless File.read(css_path).match?(TW_ANIMATE_IMPORT)
      return if File.exist?(File.join(app_root, "vendor/javascript/tw-animate-css.js"))

      Issue.new(
        description: "broken tw-animate-css import in app/assets/tailwind/application.css " \
                     "(the importmap pin from ruby_ui:install failed)",
        commands: ["curl -fsSL -o app/assets/tailwind/tw-animate.css #{TW_ANIMATE_URL}"],
        fixer: lambda do
          content = File.read(css_path)
          File.write(css_path, content.sub(TW_ANIMATE_IMPORT, %(@import "./tw-animate.css";)))
        end
      )
    end
  end
end
