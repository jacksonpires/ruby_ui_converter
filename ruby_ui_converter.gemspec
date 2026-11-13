# frozen_string_literal: true

require_relative "lib/ruby_ui_converter/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_ui_converter"
  spec.version = RubyUIConverter::VERSION
  spec.authors = ["Jackson Pires"]
  spec.email = ["jackson@linkana.com"]

  spec.summary = "Convert Rails .erb and .haml views and partials into RubyUI/Phlex Ruby components."
  spec.description = <<~DESC
    ruby_ui_converter walks a Rails views directory recursively and converts each
    .erb or .haml template into an equivalent .rb file written with Phlex (and
    RubyUI when configured). Traditional Rails partials (_partial.html.erb) are
    converted into their own Phlex component classes. HAML conversion uses the
    haml gem when it is available (optional dependency).
  DESC
  spec.homepage = "https://github.com/jacksonpires/ruby_ui_converter"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    exe/*
    README.md
    LICENSE.txt
    CHANGELOG.md
  ]).select { |f| File.file?(f) }

  spec.bindir = "exe"
  spec.executables = ["ruby_ui_converter"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  # Optional at runtime: only needed to convert .haml templates (loaded lazily).
  spec.add_development_dependency "haml", ">= 5.2"
end
