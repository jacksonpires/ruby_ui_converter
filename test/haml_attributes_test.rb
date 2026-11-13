# frozen_string_literal: true

require "test_helper"

class HamlAttributesTest < Minitest::Test
  def element(src)
    RubyUIConverter.parse(src, format: :haml).children.first
  end

  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", format: :haml, **opts)
  end

  def test_turns_literal_hash_strings_into_static_attributes_matchers_can_see
    el = element(%(%span{class: "badge big", title: 'Hi'} x))

    assert_equal %w[badge big], el.static_classes
    assert_equal "Hi", el.static_attr("title")
  end

  def test_merges_shorthand_classes_with_hash_classes
    assert_equal %w[card shadow], element(%(.card{class: "shadow"})).static_classes
    assert_includes convert(%(%p.title{class: "x \#{extra}"} y)), %(p(class: "title x \#{extra}") { "y" })
  end

  def test_merges_classes_with_arbitrary_expressions_into_an_array
    assert_includes convert(%(%p.row{class: [a, ("on" if b)]} y)), %(p(class: ["row", [a, ("on" if b)]]) { "y" })
    assert_includes convert(%(%p{class: css} y)), "p(class: css)"
  end

  def test_joins_ids_with_an_underscore_like_haml
    assert_includes convert(%(%p#main{id: "x"} y)), %(p(id: "main_x"))
  end

  def test_later_sources_override_other_attributes
    assert_includes convert(%(%a(title="a"){title: "b"} y), ruby_ui: false), %(a(title: "b"))
  end

  def test_supports_html_style_attributes_with_ruby_values
    assert_includes convert(%(%a(href="/x" title=@title) Go), ruby_ui: false), %(a(href: "/x", title: @title) { "Go" })
  end

  def test_supports_hash_rocket_keys_and_symbol_values
    out = convert(%(%a{:href => "#", "data-x" => 1, method: :delete} Del), ruby_ui: false)
    assert_includes out, %(a(href: "#", "data-x": 1, method: "delete") { "Del" })
  end

  def test_expands_literal_data_and_aria_hashes_into_hyphenated_attributes
    out = convert(%(%button{data: {turbo_method: :delete, id: item.id}, aria: {label: "Close"}} x), ruby_ui: false)
    assert_includes out, %(button("data-turbo-method": "delete", "data-id": item.id, "aria-label": "Close"))
  end

  def test_keeps_non_literal_data_hashes_as_an_expression
    assert_includes convert(%(%p{data: stimulus_data} x)), "p(data: stimulus_data)"
  end

  def test_drops_false_and_nil_attributes_and_keeps_true_as_boolean
    out = convert(%(%input{type: "text", disabled: true, checked: false, value: nil}), ruby_ui: false)
    assert_includes out, %(input(type: "text", disabled: true))
  end

  def test_dispatches_inputs_on_the_hash_type_to_rubyui_components
    assert_includes convert(%(%input{type: "checkbox", name: "all"})), %(Checkbox(name: "all"))
  end

  def test_maps_object_references_to_rails_dom_helpers
    assert_includes convert(%(%li.item[@user] x)), %(li(class: ["item", dom_class(@user)], id: dom_id(@user)))
    assert_includes convert(%(%li[@user, :edit] x)), %(li(id: dom_id(@user, :edit), class: dom_class(@user, :edit)))
  end

  def test_splats_hashes_haml_cannot_split
    assert_includes convert(%(%div{html_attrs} x)), "div(**(html_attrs))"
    assert_includes convert(%(%div{**opts, id: "z"} x)), %(div(**({**opts, id: "z"})))
  end

  def test_keeps_non_ascii_attribute_text
    assert_includes convert(%(%p{title: "Olá"} x)), %(p(title: "Olá"))
  end

  def test_object_reference_ivars_are_initializer_args_of_a_top_level_view
    Dir.mktmpdir("ruc") do |dir|
      path = File.join(dir, "app/views/users/show.html.haml")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "%div[@user]\n  %h1{title: @title} x\n")

      RubyUIConverter::Converter.new(path).run
      out = File.join(dir, "app/views/users/show.rb")

      assert_includes File.read(out), "def initialize(title: nil, user: nil)"
      assert system("ruby", "-c", out, out: File::NULL, err: File::NULL)
    end
  end
end
