# frozen_string_literal: true

require "test_helper"

class ComponentMapTest < Minitest::Test
  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", base_namespace: "Views", **opts)
  end

  def test_maps_a_href_to_link
    out = convert(%(<a href="/home" class="x">Home</a>))
    assert_includes out, %(Link(href: "/home", class: "x") { "Home" })
  end

  def test_keeps_anchors_without_href_as_plain_a
    out = convert(%(<a name="top">Top</a>))
    assert_includes out, %(a(name: "top") { "Top" })
  end

  def test_maps_button_to_button
    out = convert(%(<button type="submit" class="w-full">Save</button>))
    assert_includes out, %(Button(type: "submit", class: "w-full") { "Save" })
  end

  def test_maps_input_to_input_without_a_block
    out = convert(%(<input type="email" name="user[email]" placeholder="a@b.c">))
    assert_includes out, %(Input(type: "email", name: "user[email]", placeholder: "a@b.c"))
    refute_match(/Input\(.*\) (\{|do)/, out)
  end

  def test_maps_checkbox_and_radio_inputs_to_checkbox_radiobutton_dropping_type
    out = convert(%(<input type="checkbox" name="ok" checked>))
    assert_includes out, %(Checkbox(name: "ok", checked: true))
    refute_includes out, "type:"

    out = convert(%(<input type="radio" name="opt" value="1">))
    assert_includes out, %(RadioButton(name: "opt", value: "1"))
  end

  def test_falls_back_to_generic_input_when_type_is_dynamic
    out = convert(%(<input type="<%= kind %>" name="x">))
    assert_includes out, %(Input(type: kind, name: "x"))
  end

  def test_maps_textarea_to_textarea
    out = convert(%(<textarea name="bio" rows="6"><%= bio %></textarea>))
    assert_includes out, %(Textarea(name: "bio", rows: "6") { bio })
  end

  def test_maps_select_option_to_nativeselect_nativeselectoption
    out = convert(%(<select name="c"><option value="br">Brazil</option></select>))
    assert_includes out, %(NativeSelect(name: "c") do)
    assert_includes out, %(NativeSelectOption(value: "br") { "Brazil" })
  end

  def test_maps_the_table_family
    out = convert(<<~HTML)
      <table class="t">
        <caption>Users</caption>
        <thead><tr><th>Name</th></tr></thead>
        <tbody><tr><td>Maria</td></tr></tbody>
        <tfoot><tr><td>1 user</td></tr></tfoot>
      </table>
    HTML

    assert_includes out, %(Table(class: "t") do)
    assert_includes out, %(TableCaption() { "Users" })
    assert_includes out, "TableHeader() do"
    assert_includes out, %(TableHead() { "Name" })
    assert_includes out, "TableBody() do"
    assert_includes out, %(TableCell() { "Maria" })
    assert_includes out, "TableFooter() do"
  end

  def test_maps_hr_to_separator_with_parens_and_no_block
    assert_includes convert("<hr>"), "Separator()"
    assert_includes convert(%(<hr class="my-4">)), %(Separator(class: "my-4"))
  end

  def test_maps_a_flash_notice_paragraph_to_a_success_alert
    out = convert(%(<p class="bg-green-50" id="notice"><%= notice %></p>))
    assert_includes out, %(Alert(variant: :success, class: "mb-5") do)
    assert_includes out, %(AlertTitle { "Notice" })
    assert_includes out, "AlertDescription { notice }"
  end

  def test_maps_a_flash_alert_paragraph_to_a_destructive_alert
    out = convert(%(<p id="alert"><%= alert %></p>))
    assert_includes out, %(Alert(variant: :destructive, class: "mb-5") do)
    assert_includes out, %(AlertTitle { "Alert" })
    assert_includes out, "AlertDescription { alert }"
  end

  def test_leaves_other_paragraphs_as_plain_p
    assert_includes convert(%(<p id="intro">hi</p>)), %(p(id: "intro") { "hi" })
  end

  def test_does_not_map_the_notice_paragraph_with_ruby_ui_false
    out = convert(%(<p id="notice"><%= notice %></p>), ruby_ui: false)
    assert_includes out, %(p(id: "notice") { notice })
    refute_includes out, "Alert("
  end

  def test_maps_badge_and_card_classes
    assert_includes convert(%(<span class="badge">New</span>)), %(Badge(class: "badge") { "New" })

    out = convert(%(<div class="card"><p>x</p></div>))
    assert_includes out, %(Card(class: "card") do)
    assert_includes out, %(p { "x" })
  end

  def test_is_disabled_with_ruby_ui_false
    out = convert(%(<a href="/home">Home</a><input type="text">), ruby_ui: false)
    assert_includes out, %(a(href: "/home") { "Home" })
    assert_includes out, %(input(type: "text"))
    refute_includes out, "Link("
  end

  def test_user_rules_take_precedence_over_the_built_in_fallback_rules
    config = RubyUIConverter::Configuration.new(base_namespace: "")
    config.component_map.register(->(el) { el.name == "button" }) do |el, t, b|
      t.kit_component("Button", el, b, extra: "variant: :destructive")
    end

    document = RubyUIConverter::Parser.new(%(<button>Del</button>)).parse
    builder = RubyUIConverter::CodeBuilder.new(indent: "  ")
    RubyUIConverter::Transformer.new(config: config).emit(document, builder)

    assert_includes builder.to_s, %(Button(variant: :destructive) { "Del" })
  end
end
