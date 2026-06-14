# frozen_string_literal: true

require "test_helper"

class FormBuilderTest < Minitest::Test
  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", base_namespace: "Views", **opts)
  end

  def form(body, **opts)
    convert(%(<%= form_with(model: product) do |form| %>#{body}<% end %>), **opts)
  end

  def test_maps_text_fields_to_input_with_reconstructed_name_id_value
    assert_includes form("<%= form.text_field :name %>"),
                    %(Input(name: "product[name]", id: "product[name]", value: product.name.to_s))
  end

  def test_adds_the_matching_type_for_typed_fields
    assert_includes form("<%= form.email_field :email %>"),
                    %(Input(type: "email", name: "product[email]", id: "product[email]", value: product.email.to_s))
    assert_includes form("<%= form.number_field :qty %>"), %(type: "number")
    assert_includes form("<%= form.date_field :on %>"), %(type: "date")
    assert_includes form("<%= form.datetime_field :at %>"), %(type: "datetime-local")
  end

  def test_maps_textarea_with_the_value_in_the_block
    assert_includes form("<%= form.textarea :bio %>"),
                    %(Textarea(name: "product[bio]", id: "product[bio]") { product.bio.to_s })
    assert_includes form("<%= form.text_area :bio %>"), "Textarea("
  end

  def test_appends_a_formfielderror_reading_the_fields_backend_errors
    assert_includes form("<%= form.text_field :name %>"),
                    %(FormFieldError { product.errors[:name].to_sentence.upcase_first })
    assert_includes form("<%= form.textarea :bio %>"),
                    %(FormFieldError { product.errors[:bio].to_sentence.upcase_first })
    assert_includes form("<%= form.checkbox :active %>"),
                    %(FormFieldError { product.errors[:active].to_sentence.upcase_first })
  end

  def test_does_not_append_a_formfielderror_to_labels_or_submit_buttons
    out = form("<%= form.label :name %><%= form.submit %>")
    refute_includes out, "FormFieldError"
  end

  def test_reads_errors_from_the_ivar_model_in_the_formfielderror
    out = convert(%(<%= form_with(model: @user) do |form| %><%= form.text_field :name %><% end %>))
    assert_includes out, %(FormFieldError { @user.errors[:name].to_sentence.upcase_first })
  end

  def test_maps_checkboxes_with_value_checked_and_the_hidden_field_caveat_dropped
    assert_includes form("<%= form.checkbox :active %>"),
                    %(Checkbox(value: "1", name: "product[active]", id: "product[active]", checked: product.active?))
    assert_includes form("<%= form.check_box :active %>"), "Checkbox("
  end

  def test_maps_labels_to_formfieldlabel_with_a_humanized_default
    assert_includes form("<%= form.label :published_on %>"),
                    %(FormFieldLabel(for: "product[published_on]") { "Published on" })
  end

  def test_keeps_an_explicit_label_string
    assert_includes form(%(<%= form.label :name, "Full name" %>)),
                    %(FormFieldLabel(for: "product[name]") { "Full name" })
  end

  def test_maps_collection_select_to_a_nativeselect_with_an_option_loop_and_error
    out = form("<%= form.collection_select :category_id, Category.all, :id, :name %>")
    assert_includes out, %(NativeSelect(name: "product[category_id]", id: "product[category_id]") do)
    assert_includes out, "Category.all.each do |option|"
    assert_includes out,
                    "NativeSelectOption(value: option.id, selected: product.category_id == option.id) { option.name }"
    assert_includes out, %(FormFieldError { product.errors[:category_id].to_sentence.upcase_first })
  end

  def test_maps_submit_to_a_rubyui_button
    assert_includes form(%(<%= form.submit %>)), %(Button(type: "submit") { "Save" })
    assert_includes form(%(<%= form.submit "Create" %>)), %(Button(type: "submit") { "Create" })
    assert_includes form(%(<%= form.submit class: "btn" %>)), %(Button(type: "submit", class: "btn") { "Save" })
  end

  def test_passes_through_extra_options
    assert_includes form(%(<%= form.text_field :name, class: "x", required: true %>)),
                    %(value: product.name.to_s, class: "x", required: true)
  end

  def test_drops_the_block_variable_when_every_field_is_mapped
    assert_includes form("<%= form.text_field :name %>"), "form_with(model: product) do\n"
    refute_includes form("<%= form.text_field :name %>"), "|form|"
  end

  def test_keeps_the_block_variable_when_an_unmapped_form_call_remains
    out = form("<%= form.text_field :name %><%= form.hidden_field :token %>")
    assert_includes out, "do |form|"
    assert_includes out, "plain(form.hidden_field :token)"
  end

  def test_reconstructs_value_name_from_an_ivar_model_and_param_key
    out = convert(%(<%= form_with(model: @user) do |form| %><%= form.text_field :name %><% end %>))
    assert_includes out, %(Input(name: "user[name]", id: "user[name]", value: @user.name.to_s))
  end

  def test_leaves_form_fields_untouched_with_ruby_ui_false
    out = form("<%= form.text_field :name %>", ruby_ui: false)
    assert_includes out, "plain(form.text_field :name)"
    assert_includes out, "do |form|"
  end

  def test_does_not_map_a_form_without_a_determinable_model
    out = convert(%(<%= form_with(url: "/x") do |form| %><%= form.text_field :name %><% end %>))
    assert_includes out, "plain(form.text_field :name)"
    assert_includes out, "do |form|"
  end
end
