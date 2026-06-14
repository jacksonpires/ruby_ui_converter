# frozen_string_literal: true

module RubyUIConverter
  # Best-effort translation of common Rails view helpers found inside <%= %>
  # into Phlex/RubyUI equivalents. Anything not understood is emitted as a bare
  # call (phlex-rails registers these as output helpers that write to the buffer
  # themselves) or, for the few that return a string, through a raw call.
  module RailsHelpers
    module_function

    # Rails helpers that produce HTML. Under phlex-rails these are output
    # helpers (they write to the buffer and return nil), so an unmapped one is
    # emitted as a bare call — except STRING_HELPERS below, which return a value.
    HTML_HELPERS = %w[
      link_to button_to image_tag video_tag audio_tag content_tag tag
      form_with form_for fields_for label_tag text_field_tag mail_to
      link_to_unless link_to_if sanitize simple_format raw safe_join
      time_tag favicon_link_tag stylesheet_link_tag javascript_include_tag
    ].freeze

    # The subset of HTML_HELPERS that RETURN a string instead of writing to the
    # Phlex buffer, so they must be wrapped in a raw call to appear in the output.
    STRING_HELPERS = %w[sanitize safe_join raw strip_tags].freeze

    # Helpers that return plain (already-escaped or scalar) values.
    KNOWN_HELPERS = %w[
      t l translate localize number_to_currency number_with_delimiter
      number_to_percentage pluralize truncate current_user current_page?
      params session flash request cookies asset_path image_path url_for
      polymorphic_path time_ago_in_words distance_of_time_in_words
      dom_id dom_class notice alert content_for cycle render
    ].freeze

    # Attempts to emit a transformed helper. Returns true when it wrote
    # something to the builder, false otherwise.
    def transform(code, node, transformer, builder)
      stripped = code.strip

      if stripped == "yield" || stripped =~ /\Ayield\b/
        builder.line(stripped)
        return true
      end

      if stripped.start_with?("render")
        rendered = safe { render_call(stripped, transformer) }
        # phlex-rails' #render handles model objects / relations and writes to
        # the buffer itself, so the object/collection fallback is a bare call.
        builder.line(rendered || stripped)
        return true
      end

      if stripped.start_with?("link_to")
        rendered = safe { link_to_call(stripped, ruby_ui: transformer.config.ruby_ui?) }
        return builder.line(rendered) && true if rendered
      end

      if stripped.start_with?("image_tag")
        rendered = safe { image_tag_call(stripped) }
        return builder.line(rendered) && true if rendered
      end

      if stripped.start_with?("content_tag")
        rendered = safe { content_tag_call(stripped) }
        return builder.line(rendered) && true if rendered
      end

      if html_helper?(stripped)
        # Output helpers write to the buffer (bare call); string-returning ones
        # need a raw call to be emitted.
        builder.line(string_helper?(stripped) ? transformer.config.raw_call(stripped) : stripped)
        return true
      end

      false
    end

    def html_helper?(code)
      matches_helper?(code, HTML_HELPERS)
    end

    def string_helper?(code)
      matches_helper?(code, STRING_HELPERS)
    end

    def matches_helper?(code, helpers)
      helpers.any? do |helper|
        code == helper || code.start_with?("#{helper}(") || code.start_with?("#{helper} ")
      end
    end

    # render "shared/header" / render partial: "x", locals: {..} / render "form", a: 1
    def render_call(code, transformer)
      rest = strip_parens(code.sub(/\Arender\b/, "").strip)
      args = split_args(rest)
      return nil if args.empty?

      first = args[0]
      first = Regexp.last_match(1).strip if first =~ /\Apartial:\s*(.+)\z/m

      match = first.match(/\A["']([^"']+)["']\z/)
      return nil unless match

      const = Naming.partial_const(
        match[1],
        base_namespace: transformer.base_namespace,
        current_namespace_parts: transformer.current_namespace_parts
      )
      locals = build_locals(args[1..])
      locals ? "render #{const}.new(#{locals})" : "render #{const}.new"
    end

    def build_locals(arg_list)
      return nil if arg_list.nil? || arg_list.empty?

      pairs = arg_list.map do |arg|
        if arg =~ /\Alocals:\s*\{(.*)\}\z/m
          Regexp.last_match(1).strip
        else
          arg
        end
      end

      result = pairs.reject(&:empty?).join(", ")
      result.empty? ? nil : result
    end

    # link_to "Text", path, class: "x" -> a(href: path, class: "x") { "Text" }
    # With ruby_ui enabled               -> Link(href: path, class: "x") { "Text" }
    def link_to_call(code, ruby_ui: false)
      return nil if code =~ /\bdo\b/ # block form handled elsewhere

      rest = strip_parens(code.sub(/\Alink_to\b/, "").strip)
      args = split_args(rest)
      return nil if args.length < 2

      text, path, *options = args
      attrs = ["href: #{link_target(path)}"] + options
      call = ruby_ui ? "Link" : "a"
      "#{call}(#{attrs.join(", ")}) { #{text} }"
    end

    # Targets that are not strings or route helper calls (e.g. a record:
    # `link_to "Show", user`) need url_for to resolve to a path.
    def link_target(path)
      return path if path.start_with?('"', "'") # literal string
      return path if path =~ /\A(\w+_)?(path|url)\b/ # route helper call

      "url_for(#{path})"
    end

    # image_tag "logo.png", alt: "Logo" -> img(src: "logo.png", alt: "Logo")
    def image_tag_call(code)
      rest = strip_parens(code.sub(/\Aimage_tag\b/, "").strip)
      args = split_args(rest)
      return nil if args.empty?

      src, *options = args
      attrs = ["src: #{src}"] + options
      "img(#{attrs.join(", ")})"
    end

    # content_tag(:div, "hi", class: "x") -> div(class: "x") { "hi" }
    def content_tag_call(code)
      rest = strip_parens(code.sub(/\Acontent_tag\b/, "").strip)
      args = split_args(rest)
      return nil if args.length < 2

      name = args[0].sub(/\A:/, "").gsub(/['"]/, "")
      content = args[1]
      options = args[2..] || []
      call = options.empty? ? name : "#{name}(#{options.join(", ")})"
      "#{call} { #{content} }"
    end

    # Splits a top-level argument list, respecting strings and nested brackets.
    def split_args(string)
      args = []
      depth = 0
      current = +""
      quote = nil

      string.each_char do |char|
        if quote
          current << char
          quote = nil if char == quote
          next
        end

        case char
        when '"', "'"
          quote = char
          current << char
        when "(", "[", "{"
          depth += 1
          current << char
        when ")", "]", "}"
          depth -= 1
          current << char
        when ","
          if depth.zero?
            args << current.strip
            current = +""
          else
            current << char
          end
        else
          current << char
        end
      end

      args << current.strip unless current.strip.empty?
      args
    end

    def strip_parens(string)
      stripped = string.strip
      if stripped.start_with?("(") && stripped.end_with?(")")
        stripped[1..-2].strip
      else
        stripped
      end
    end

    def safe
      yield
    rescue StandardError
      nil
    end
  end
end
