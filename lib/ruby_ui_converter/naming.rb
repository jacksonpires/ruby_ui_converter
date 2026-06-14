# frozen_string_literal: true

module RubyUIConverter
  # Converts file paths into Ruby constant names following Rails-ish
  # conventions: app/views/users/index.html.erb -> Views::Users::Index.
  module Naming
    module_function

    def camelize(string)
      string.to_s.split(/[_\-\s]+/).reject(&:empty?).map do |part|
        part[0].upcase + part[1..].to_s
      end.join
    end

    # Class name for a template basename ("index" / "_form" -> Index / Form).
    def class_name(basename)
      camelize(basename.sub(/\A_/, ""))
    end

    # Module segments derived from base namespace + relative directory.
    # ("users", "Views") -> ["Views", "Users"]
    def namespace_parts(dir_rel, base_namespace)
      base_parts = base_namespace.to_s.split("::").reject(&:empty?)
      dir_parts = dir_rel.to_s.split("/").reject(&:empty?).map { |part| camelize(part) }
      base_parts + dir_parts
    end

    # Resolves a render partial path to a fully-qualified constant.
    #   "shared/header" -> "Views::Shared::Header"
    #   "form"          -> "<current namespace>::Form"
    def partial_const(path, base_namespace:, current_namespace_parts: [])
      segments = path.to_s.split("/")
      name = segments.pop.to_s.sub(/\A_/, "")

      if path.to_s.include?("/")
        base_parts = base_namespace.to_s.split("::").reject(&:empty?)
        dir_parts = segments.map { |segment| camelize(segment) }
        (base_parts + dir_parts + [camelize(name)]).join("::")
      else
        current = current_namespace_parts.empty? ? [base_namespace.to_s].reject(&:empty?) : current_namespace_parts
        (current + [camelize(name)]).join("::")
      end
    end
  end
end
