# frozen_string_literal: true

module RubyUIConverter
  class Configuration
    attr_accessor :base_namespace, :base_class, :phlex_version, :indent,
                  :output_root, :verbose, :dry_run, :force, :ruby_ui,
                  :literal, :root, :component_map

    def initialize(base_namespace: "Views", base_class: "Phlex::HTML",
                   phlex_version: 2, indent: "  ", output_root: nil,
                   verbose: false, dry_run: false, force: false, ruby_ui: true,
                   literal: false, root: nil)
      @base_namespace = base_namespace
      @base_class = base_class
      @phlex_version = phlex_version
      @indent = indent
      @output_root = output_root
      @verbose = verbose
      @dry_run = dry_run
      @force = force
      @ruby_ui = ruby_ui
      @literal = literal
      @root = root
      @component_map = ComponentMap.new
      enable_rubyui_rules! if ruby_ui
    end

    # Phlex 2 uses `view_template`; Phlex 1 used `template`.
    def template_method
      phlex_version.to_i >= 2 ? "view_template" : "template"
    end

    # Emit a raw (unescaped) output call for the given Ruby expression. Phlex 2
    # dropped `unsafe_raw` in favor of `raw(safe(...))`; Phlex 1 used
    # `unsafe_raw(...)`.
    def raw_call(expr)
      phlex_version.to_i >= 2 ? "raw(safe(#{expr}))" : "unsafe_raw(#{expr})"
    end

    def ruby_ui?
      !!@ruby_ui
    end

    def literal?
      !!@literal
    end

    def enable_rubyui_rules!
      ComponentMap.rubyui_rules(@component_map)
      self
    end
  end
end
