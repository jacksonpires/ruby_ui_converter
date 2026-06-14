# frozen_string_literal: true

require "thor"

module RubyUIConverter
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "convert PATH", "Convert .erb views/partials under PATH into RubyUI/Phlex .rb files"
    long_desc <<~DESC
      Recursively walks PATH looking for *.erb files and writes an equivalent
      .rb component next to each one (e.g. index.html.erb -> index.rb). Rails
      partials (_form.html.erb) become their own component classes (form.rb).

      By default, basic HTML elements are mapped onto RubyUI kit components
      (a -> Link, button -> Button, input -> Input, table -> Table, ...).
      Pass --no-ruby-ui to emit plain Phlex elements instead.
    DESC
    option :namespace, default: "Views", desc: "Base module namespace for generated constants"
    option :root, desc: "Directory namespaces are derived from (default: nearest app/views ancestor, else PATH)"
    option :base_class, default: "Phlex::HTML", desc: "Superclass for generated components"
    option :phlex, default: "2", desc: "Target Phlex major version (2 => view_template, 1 => template)"
    option :output, aliases: "-o", desc: "Write into this directory instead of in place (mirrors structure)"
    option :dry_run, type: :boolean, default: false, desc: "Print what would be generated without writing"
    option :force, type: :boolean, default: false, desc: "Overwrite existing .rb files"
    option :ruby_ui, type: :boolean, default: true, desc: "Map basic HTML elements onto RubyUI components (--no-ruby-ui for plain Phlex)"
    option :literal, type: :boolean, default: false, desc: "Emit Literal::Properties props instead of initialize/attr_reader (requires the literal gem)"
    option :verbose, type: :boolean, default: false
    def convert(path)
      unless File.exist?(path)
        say "Path not found: #{path}", :red
        exit 1
      end

      if options[:root]
        root = File.expand_path(options[:root])
        unless File.directory?(root) && File.expand_path(path).start_with?(root)
          say "Invalid --root: #{options[:root]} (must be an existing ancestor of PATH)", :red
          exit 1
        end
      end

      config = Configuration.new(
        base_namespace: options[:namespace],
        root: options[:root],
        base_class: options[:base_class],
        phlex_version: options[:phlex],
        output_root: options[:output],
        dry_run: options[:dry_run],
        force: options[:force],
        ruby_ui: options[:ruby_ui],
        literal: options[:literal],
        verbose: options[:verbose]
      )

      results = Converter.new(path, config: config).run
      report(results, config)
      check_prerequisites(results, config, path)
    end

    desc "version", "Print the ruby_ui_converter version"
    def version
      say RubyUIConverter::VERSION
    end

    map %w[--version -v] => :version

    private

    def report(results, config)
      if results.empty?
        say "No .erb files found.", :yellow
        return
      end

      results.each do |result|
        case result.status
        when :written
          say "  created  #{relative(result.output)}", :green
          preview(result) if config.verbose
        when :previewed
          say "  preview  #{relative(result.output)}", :cyan
          preview(result)
        when :skipped
          say "  skipped  #{relative(result.output)} (exists, use --force)", :yellow
        when :error
          say "  error    #{relative(result.source)}: #{result.error.message}", :red
        end
      end

      counts = results.group_by(&:status).transform_values(&:size)
      say ""
      say "Done. #{counts.map { |status, n| "#{n} #{status}" }.join(", ")}."
    end

    def preview(result)
      return unless result.code

      say "", nil
      say result.code, :white
      say "", nil
    end

    # Diagnoses the target app for the prerequisites the generated code needs
    # (gems, RubyUI components, Literal::Properties) and offers to install
    # them. Only warns in non-interactive sessions and on --dry-run.
    def check_prerequisites(results, config, path)
      doctor = Doctor.new(results, config: config, start_path: path)
      issues = doctor.issues
      return if issues.empty?

      say ""
      say "Missing prerequisites detected:", :yellow
      issues.each { |issue| say "  - #{issue.description}", :yellow }

      if config.dry_run || !$stdin.tty?
        pending_commands(issues)
        return
      end

      # Default to yes: only an explicit "n"/"no" skips; a bare Enter installs.
      if no?("Install now? [Y/n]")
        pending_commands(issues)
        return
      end

      apply_fixes(issues, doctor.app_root)

      # Some problems only appear after installing (e.g. ruby_ui:install
      # leaving a broken tw-animate-css import, or the base class to extend
      # Literal::Properties being created by phlex:install). One follow-up
      # diagnosis catches and fixes those under the same consent.
      follow_up = Doctor.new(results, config: config, start_path: path).issues
      return if follow_up.empty?

      say ""
      say "Applying follow-up fixes:", :yellow
      follow_up.each { |issue| say "  - #{issue.description}", :yellow }
      apply_fixes(follow_up, doctor.app_root)
    end

    def apply_fixes(issues, app_root)
      issues.each { |issue| issue.fixer&.call }
      run_commands(issues.flat_map { |issue| issue.commands || [] }, app_root)
    end

    def pending_commands(issues)
      say ""
      say "To fix, run:", :yellow
      issues.flat_map { |issue| issue.commands || [] }.each { |cmd| say "  #{cmd}", :yellow }
    end

    def run_commands(commands, app_root)
      commands.reject { |cmd| cmd.start_with?("#") }.each do |cmd|
        say "  running #{cmd}", :cyan
        unless run_in_app(cmd, app_root)
          say "  command failed: #{cmd} — run it manually.", :red
          break
        end
      end
    end

    def run_in_app(cmd, app_root)
      if defined?(Bundler)
        Bundler.with_unbundled_env { system(cmd, chdir: app_root) }
      else
        system(cmd, chdir: app_root)
      end
    end

    def relative(path)
      return path unless path

      path.delete_prefix("#{Dir.pwd}/")
    end
  end
end
