# frozen_string_literal: true

require "test_helper"

class TransformerTest < Minitest::Test
  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", base_namespace: "Views", **opts)
  end

  def test_converts_plain_elements_with_attributes
    out = convert(%(<div class="box" id="main">hi</div>))
    assert_includes out, %(div(class: "box", id: "main") { "hi" })
  end

  def test_outputs_escaped_expressions_with_plain
    assert_includes convert("<span><%= user.name %></span>"), "span { user.name }"
  end

  def test_outputs_unescaped_expressions_with_raw_safe_on_phlex_2
    assert_includes convert("<%== markup %>"), "raw(safe(markup))"
  end

  def test_outputs_unescaped_expressions_with_unsafe_raw_on_phlex_1
    assert_includes convert("<%== markup %>", phlex_version: 1), "unsafe_raw(markup)"
  end

  def test_interpolates_erb_inside_attribute_values
    out = convert(%(<p class="a <%= b %>">x</p>))
    assert_includes out, 'p(class: "a #{b}")'
  end

  def test_emits_a_bare_ruby_expression_for_whole_value_erb_attributes
    out = convert(%(<p class="<%= css %>">x</p>))
    assert_includes out, "p(class: css)"
  end

  def test_parenthesizes_attribute_expressions_that_take_unparenthesized_arguments
    out = convert(%(<div id="<%= dom_id user %>" class="row">x</div>))
    assert_includes out, %(div(id: (dom_id user), class: "row"))
  end

  def test_converts_if_else_into_ruby_control_flow
    out = convert("<% if a %><p>x</p><% else %><p>y</p><% end %>")
    assert_includes out, "if a"
    assert_includes out, "else"
    assert_includes out, "end"
  end

  def test_converts_each_blocks
    out = convert("<ul><% items.each do |i| %><li><%= i %></li><% end %></ul>")
    assert_includes out, "items.each do |i|"
    assert_includes out, "li { i }"
  end

  def test_maps_link_to_to_a_rubyui_link_by_default
    out = convert(%(<%= link_to "Home", root_path, class: "nav" %>))
    assert_includes out, %(Link(href: root_path, class: "nav") { "Home" })
  end

  def test_maps_link_to_to_an_anchor_element_with_ruby_ui_disabled
    out = convert(%(<%= link_to "Home", root_path, class: "nav" %>), ruby_ui: false)
    assert_includes out, %(a(href: root_path, class: "nav") { "Home" })
  end

  def test_wraps_non_path_link_to_targets_in_url_for
    out = convert(%(<%= link_to "Show", user %>))
    assert_includes out, %(Link(href: url_for(user)) { "Show" })
  end

  def test_keeps_route_helper_and_string_link_to_targets_as_is
    out = convert(%(<%= link_to "Edit", edit_user_path(user) %>))
    assert_includes out, %(Link(href: edit_user_path(user)) { "Edit" })

    out = convert(%(<%= link_to "Site", "https://example.com" %>), ruby_ui: false)
    assert_includes out, %(a(href: "https://example.com") { "Site" })
  end

  def test_maps_render_to_a_component
    out = convert(%(<%= render "shared/header" %>))
    assert_includes out, "render Views::Shared::Header.new"
  end

  def test_maps_render_with_locals
    out = convert(%(<%= render "shared/header", title: "Hi" %>))
    assert_includes out, %(render Views::Shared::Header.new(title: "Hi"))
  end

  def test_emits_object_collection_render_as_a_bare_call
    assert_includes convert("<%= render product %>"), "render product"
    refute_includes convert("<%= render product %>"), "raw("
    assert_includes convert("<%= render @products %>"), "render @products"
  end

  def test_emits_unmapped_output_helpers_like_button_to_as_bare_calls
    out = convert(%(<%= button_to "Destroy", product, method: :delete %>))
    assert_includes out, %(button_to "Destroy", product, method: :delete)
    refute_includes out, "raw("
    refute_includes out, "unsafe_raw("
  end

  def test_wraps_string_returning_helpers_in_a_raw_call
    assert_includes convert("<%= sanitize(body) %>"), "raw(safe(sanitize(body)))"
    assert_includes convert("<%= sanitize(body) %>", phlex_version: 1), "unsafe_raw(sanitize(body))"
  end

  def test_keeps_data_attributes_with_quoted_symbol_keys
    out = convert(%(<div data-controller="x">y</div>))
    assert_includes out, %("data-controller": "x")
  end

  def test_handles_void_elements_without_a_block
    assert_includes convert(%(<img src="a.png">)), %(img(src: "a.png"))
  end
end
