# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class HamlParserTest < Minitest::Test
  def tree(src)
    RubyUIConverter.parse(src, format: :haml)
  end

  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", base_namespace: "Views", format: :haml, **opts)
  end

  # --- AST shape ---------------------------------------------------------

  def test_builds_elements_with_shorthand_class_and_id_as_static_attributes
    element = tree("%p.lead.big#intro Hi").children.first

    assert_equal "p", element.name
    assert_equal "intro", element.static_attr("id")
    assert_equal %w[lead big], element.static_classes
    assert_equal "Hi", element.children.first.content
  end

  def test_turns_mid_block_keywords_into_branches_of_one_control
    control = tree(<<~HAML).children.first
      - if a
        %p x
      - elsif b
        %p y
      - else
        %p z
    HAML

    assert_kind_of RubyUIConverter::Nodes::Control, control
    assert_equal ["if a", "elsif b", "else"], control.branches.map(&:header)
    assert(control.branches.all? { |branch| branch.children.length == 1 })
  end

  def test_marks_output_blocks_and_plain_blocks
    nodes = tree(<<~HAML).children
      = form_with(model: user) do |form|
        = form.submit
      - items.each do |item|
        %li= item
    HAML

    assert nodes[0].output
    assert nodes[0].block
    refute nodes[1].output
    assert nodes[1].block
  end

  def test_splits_interpolated_text_into_text_and_output_nodes
    nodes = tree("Hello \#{user.name}!").children

    assert_equal [RubyUIConverter::Nodes::Text, RubyUIConverter::Nodes::Output, RubyUIConverter::Nodes::Text],
                 nodes.map(&:class)
    assert_equal "user.name", nodes[1].code
  end

  def test_strips_the_escape_wrappers_haml_5_and_6_put_around_interpolations
    assert_equal "name", RubyUIConverter::HamlParser.unwrap_escape("Haml::Helpers.html_escape((name))")
    assert_equal "@user.name",
                 RubyUIConverter::HamlParser.unwrap_escape("Haml::Util.escape_html_safe((@user.name).to_s)")
    assert_equal "a(b)", RubyUIConverter::HamlParser.unwrap_escape("a(b)")
  end

  def test_reports_a_friendly_error_when_haml_is_not_available
    RubyUIConverter::HamlParser.stub(:require_haml, -> { raise LoadError }) do
      error = assert_raises(RubyUIConverter::Error) { tree("%p hi") }
      assert_includes error.message, "requires the haml gem"
    end
  end

  # --- generated code ----------------------------------------------------

  def test_converts_tags_with_inline_text_and_expressions
    out = convert(<<~HAML)
      %h1.title Hello
      %p= user.email
    HAML

    assert_includes out, %(h1(class: "title") { "Hello" })
    assert_includes out, "p { user.email }"
  end

  def test_distinguishes_escaped_and_raw_output
    out = convert(<<~HAML)
      = escaped
      != markup
      &= forced
    HAML

    assert_includes out, "plain(escaped)"
    assert_includes out, "raw(safe(markup))"
    assert_includes out, "plain(forced)"
  end

  def test_converts_conditionals_and_case_into_ruby_control_flow
    out = convert(<<~HAML)
      - if a
        %p x
      - else
        %p y
      - case kind
      - when :a
        %span A
    HAML

    assert_includes out, "    if a\n      p { \"x\" }\n    else\n      p { \"y\" }\n    end\n"
    assert_includes out, "    case kind\n    when :a\n      span { \"A\" }\n    end\n"
  end

  def test_converts_each_blocks
    out = convert("%ul\n  - items.each do |i|\n    %li= i\n")
    assert_includes out, "items.each do |i|"
    assert_includes out, "li { i }"
  end

  def test_keeps_interpolated_helpers_visible_to_the_rails_helper_mapping
    out = convert(%(%p Go to \#{link_to "Home", root_path}))
    assert_includes out, %(Link(href: root_path) { "Home" })
  end

  def test_shares_the_rubyui_and_rails_helper_mapping_with_erb
    out = convert(<<~HAML)
      .card
        %button Save
        = link_to "Show", user
        = render "shared/header"
    HAML

    assert_includes out, %(Card(class: "card") do)
    assert_includes out, %(Button() { "Save" })
    assert_includes out, %(Link(href: url_for(user)) { "Show" })
    assert_includes out, "render Views::Shared::Header.new"
  end

  def test_maps_form_builder_fields_inside_a_haml_form
    out = convert(<<~HAML)
      = form_with(model: product) do |form|
        = form.text_field :name
        = form.submit
    HAML

    assert_includes out, "form_with(model: product) do\n"
    assert_includes out, %(Input(name: "product[name]", id: "product[name]", value: product.name.to_s))
    assert_includes out, %(Button(type: "submit") { "Save" })
  end

  def test_converts_comments_and_doctype
    out = convert("!!!\n-# private note\n/ public note\n%p x\n")

    assert_includes out, "doctype"
    assert_includes out, "# private note"
    assert_includes out, %(comment { "public note" })
  end

  def test_passes_dynamic_attribute_hashes_through_as_a_splat
    out = convert(%(%div{html_attrs}\n%span{**opts, id: "z"} x\n))

    assert_includes out, "div(**(html_attrs))"
    assert_includes out, %(span(**({**opts, id: "z"})) { "x" })
  end

  def test_keeps_boolean_html_style_attributes
    assert_includes convert(%(%input(type="text" disabled)), ruby_ui: false), %(input(type: "text", disabled: true))
  end
end
