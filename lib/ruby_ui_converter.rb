# frozen_string_literal: true

require "set"
require "strscan"

require_relative "ruby_ui_converter/version"
require_relative "ruby_ui_converter/nodes"
require_relative "ruby_ui_converter/lexer"
require_relative "ruby_ui_converter/html_tokenizer"
require_relative "ruby_ui_converter/parser"
require_relative "ruby_ui_converter/code_builder"
require_relative "ruby_ui_converter/naming"
require_relative "ruby_ui_converter/rails_helpers"
require_relative "ruby_ui_converter/form_builder"
require_relative "ruby_ui_converter/locals_detector"
require_relative "ruby_ui_converter/component_map"
require_relative "ruby_ui_converter/configuration"
require_relative "ruby_ui_converter/transformer"
require_relative "ruby_ui_converter/template"
require_relative "ruby_ui_converter/file_walker"
require_relative "ruby_ui_converter/converter"
require_relative "ruby_ui_converter/doctor"

module RubyUIConverter
  class Error < StandardError; end

  # Convert a single .erb string into Ruby/Phlex source (no file IO).
  #
  #   RubyUIConverter.convert_string("<h1><%= @title %></h1>")
  def self.convert_string(source, class_name: "Component", base_namespace: "",
                          base_class: "Phlex::HTML", **opts)
    config = Configuration.new(base_namespace: base_namespace, base_class: base_class, **opts)
    document = Parser.new(source).parse
    builder = CodeBuilder.new(indent: config.indent)
    builder.line("class #{class_name} < #{config.base_class}")
    builder.indent
    builder.line("def #{config.template_method}")
    builder.indent
    Transformer.new(config: config).emit(document, builder)
    builder.dedent
    builder.line("end")
    builder.dedent
    builder.line("end")
    builder.to_s
  end

  # Convert files under a path, writing .rb files. Returns Converter::Result[].
  #
  #   RubyUIConverter.convert("app/views/users")
  def self.convert(path, **opts)
    config = Configuration.new(**opts)
    Converter.new(path, config: config).run
  end
end
