# frozen_string_literal: true

module RubyUIConverter
  # Translates Rails form-builder field calls (`form.text_field :name, ...`)
  # found inside a `form_with` / `form_for` block into RubyUI form components
  # (`Input`, `Textarea`, `Checkbox`, `FormFieldLabel`, `Button`), following the
  # convention of building `name`/`id` as `"model[attr]"` and `value` as
  # `model.attr`.
  #
  # Only active when `ruby_ui?` is on and the enclosing form has a determinable
  # model, so the name/value can be reconstructed; otherwise the calls are left
  # untouched (and the block keeps its `|form|` builder variable).
  module FormBuilder
    module_function

    # form field method -> input type (nil = no explicit type, like text_field)
    INPUT_TYPES = {
      "text_field" => nil,
      "email_field" => "email",
      "password_field" => "password",
      "number_field" => "number",
      "telephone_field" => "tel",
      "phone_field" => "tel",
      "url_field" => "url",
      "search_field" => "search",
      "color_field" => "color",
      "range_field" => "range",
      "date_field" => "date",
      "datetime_field" => "datetime-local",
      "datetime_local_field" => "datetime-local",
      "time_field" => "time",
      "month_field" => "month",
      "week_field" => "week",
      "file_field" => "file"
    }.freeze

    TEXTAREA_METHODS = %w[text_area textarea].freeze
    CHECKBOX_METHODS = %w[check_box checkbox].freeze

    # Every builder method this module knows how to translate.
    def mappable_methods
      INPUT_TYPES.keys + TEXTAREA_METHODS + CHECKBOX_METHODS + %w[label submit collection_select]
    end

    # Parse a `form_with`/`form_for` block header into a form scope
    # ({var:, model:, param:}) or nil when it isn't a model-bound form we can map.
    def form_scope(header)
      return nil unless header =~ /\A(form_with|form_for)\b/

      var = header[/\bdo\s*\|\s*(\w+)\s*\|/, 1]
      return nil unless var

      model = model_expression(header)
      return nil unless model

      param = model.sub(/\A@/, "")
      return nil unless param =~ /\A\w+\z/

      { var: var, model: model, param: param }
    end

    def model_expression(header)
      if (model = header[/\bmodel:\s*([^,)]+)/, 1])
        return model.strip
      end

      return nil unless header =~ /\Aform_for\b/

      rest = RailsHelpers.strip_parens(header.sub(/\Aform_for\b/, "").sub(/\bdo\b.*\z/m, "").strip)
      RailsHelpers.split_args(rest).first&.strip
    end

    # True when the children contain a `form.<var>` call this module won't map,
    # so the block variable must be kept.
    def needs_block_var?(var, codes)
      codes.any? do |code|
        method = code[/\A#{Regexp.escape(var)}\.(\w+)/, 1]
        method && !mappable_methods.include?(method)
      end
    end

    # True when the code is a mappable form field call (so it should not be
    # inlined as `{ ... }` but emitted through the field translation).
    def form_field?(code, form)
      return false unless form

      method = code[/\A#{Regexp.escape(form[:var])}\.(\w+)/, 1]
      method && mappable_methods.include?(method)
    end

    # Emit a form field call as a RubyUI component. Returns true when handled.
    def transform(code, transformer, builder)
      form = transformer.current_form
      return false unless form

      method = code[/\A#{Regexp.escape(form[:var])}\.(\w+)/, 1]
      return false unless method

      rest = code.sub(/\A#{Regexp.escape(form[:var])}\.\w+\s*/, "")
      args = RailsHelpers.split_args(RailsHelpers.strip_parens(rest))

      # collection_select expands into a NativeSelect with a loop, so it emits
      # its (indented) block directly rather than returning flat lines.
      return emit_collection_select(args, form, builder) if method == "collection_select"

      lines = build(method, args, form)
      return false unless lines

      Array(lines).each { |line| builder.line(line) }
      true
    end

    # form.collection_select :category_id, Category.all, :id, :name ->
    #   NativeSelect(name:, id:) do
    #     Category.all.each do |option|
    #       NativeSelectOption(value: option.id, selected: model.category_id == option.id) { option.name }
    #     end
    #   end
    #   FormFieldError { ... }
    # (extra options/html_options beyond the four positionals are not carried over)
    def emit_collection_select(args, form, builder)
      attr = attr_name(args[0])
      value_method = attr_name(args[2])
      text_method = attr_name(args[3])
      return false unless attr && args[1] && value_method && text_method

      collection = args[1].strip
      builder.line("NativeSelect(#{name_and_id(form, attr)}) do")
      builder.indent
      builder.line("#{collection}.each do |option|")
      builder.indent
      builder.line(
        "NativeSelectOption(value: option.#{value_method}, " \
        "selected: #{form[:model]}.#{attr} == option.#{value_method}) { option.#{text_method} }"
      )
      builder.dedent
      builder.line("end")
      builder.dedent
      builder.line("end")
      builder.line(error_line(form, attr))
      true
    end

    # Returns a line (or array of lines) for the field, or nil when unmappable.
    # Input/textarea/checkbox additionally get a FormFieldError reading the
    # attribute's backend errors, like the RubyUI form convention.
    def build(method, args, form)
      if INPUT_TYPES.key?(method)
        with_error(input_field(method, args, form), args, form)
      elsif TEXTAREA_METHODS.include?(method)
        with_error(textarea_field(args, form), args, form)
      elsif CHECKBOX_METHODS.include?(method)
        with_error(checkbox_field(args, form), args, form)
      elsif method == "label"
        label_field(args, form)
      elsif method == "submit"
        submit_button(args)
      end
    end

    def with_error(component, args, form)
      return nil unless component

      [component, error_line(form, attr_name(args[0]))]
    end

    # FormFieldError { product.errors[:name].to_sentence.upcase_first }
    def error_line(form, attr)
      "FormFieldError { #{form[:model]}.errors[:#{attr}].to_sentence.upcase_first }"
    end

    def input_field(method, args, form)
      attr = attr_name(args[0])
      return nil unless attr

      parts = []
      if (type = INPUT_TYPES[method])
        parts << %(type: "#{type}")
      end
      parts << name_and_id(form, attr)
      parts << "value: #{field_value(form, attr)}"
      parts.concat(args[1..] || [])
      "Input(#{parts.join(", ")})"
    end

    def textarea_field(args, form)
      attr = attr_name(args[0])
      return nil unless attr

      parts = [name_and_id(form, attr)].concat(args[1..] || [])
      "Textarea(#{parts.join(", ")}) { #{field_value(form, attr)} }"
    end

    # HTML attribute values are strings; calling #to_s keeps Phlex happy for
    # non-string columns (decimal/BigDecimal, integer, date, nil, ...) which it
    # would otherwise reject as invalid attribute values.
    def field_value(form, attr)
      "#{form[:model]}.#{attr}.to_s"
    end

    def checkbox_field(args, form)
      attr = attr_name(args[0])
      return nil unless attr

      parts = [%(value: "1"), name_and_id(form, attr), "checked: #{form[:model]}.#{attr}?"]
      parts.concat(args[1..] || [])
      "Checkbox(#{parts.join(", ")})"
    end

    def label_field(args, form)
      attr = attr_name(args[0])
      return nil unless attr

      text = string_arg?(args[1]) ? args[1].strip : %("#{humanize(attr)}")
      %(FormFieldLabel(for: "#{form[:param]}[#{attr}]") { #{text} })
    end

    def submit_button(args)
      if string_arg?(args[0])
        text = args[0].strip
        opts = args[1..] || []
      else
        text = '"Save"'
        opts = args
      end

      call = opts.empty? ? %(Button(type: "submit")) : %(Button(type: "submit", #{opts.join(", ")}))
      "#{call} { #{text} }"
    end

    # "product" + "name" -> name: "product[name]", id: "product[name]"
    def name_and_id(form, attr)
      key = %("#{form[:param]}[#{attr}]")
      "name: #{key}, id: #{key}"
    end

    # ":name" / "\"name\"" -> "name"
    def attr_name(arg)
      return nil unless arg

      arg.strip.sub(/\A:/, "").gsub(/\A["']|["']\z/, "")[/\A\w+\z/]
    end

    def string_arg?(arg)
      arg && arg.strip.start_with?('"', "'")
    end

    def humanize(attr)
      attr.tr("_", " ").capitalize
    end
  end
end
