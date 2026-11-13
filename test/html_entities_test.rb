# frozen_string_literal: true

require "test_helper"

class HtmlEntitiesTest < Minitest::Test
  def decode(text)
    RubyUIConverter::HtmlEntities.decode(text)
  end

  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", ruby_ui: false, **opts)
  end

  # --- decoding ----------------------------------------------------------

  def test_decodes_named_references
    assert_equal "© — Olá", decode("&copy; &mdash; Ol&aacute;")
  end

  def test_decodes_decimal_and_hex_references
    assert_equal "— —", decode("&#8212; &#x2014;")
  end

  def test_decodes_in_a_single_pass
    assert_equal "&amp; <b>", decode("&amp;amp; &lt;b&gt;")
  end

  def test_leaves_unknown_unterminated_and_invalid_references_untouched
    assert_equal "&foo; &copy & AT&T &#0; &#xD800; &#x110000;", decode("&foo; &copy & AT&T &#0; &#xD800; &#x110000;")
  end

  # --- conversion --------------------------------------------------------

  def test_decodes_text_so_phlex_does_not_double_escape_it
    assert_includes convert("<p>&copy; 2026 &mdash; Acme &amp; Co</p>"), %(p { "© 2026 — Acme & Co" })
  end

  def test_keeps_escaped_markup_as_text
    assert_includes convert("<p>&lt;b&gt;bold&lt;/b&gt;</p>"), %(p { "<b>bold</b>" })
  end

  def test_writes_a_decoded_no_break_space_as_an_escape
    assert_includes convert("<p>a&nbsp;b</p>"), 'p { "a\\u00A0b" }'
  end

  def test_decodes_literal_attribute_values
    out = convert(%(<a href="/x?a=1&amp;b=2" title="Tom &amp; Jerry">Go</a>))
    assert_includes out, %(a(href: "/x?a=1&b=2", title: "Tom & Jerry") { "Go" })
  end

  def test_decodes_the_literal_parts_of_interpolated_attributes
    assert_includes convert(%(<p title="&copy; <%= year %>">x</p>)), %(p(title: "© \#{year}"))
  end

  def test_keeps_static_class_matching_working_after_decoding
    el = RubyUIConverter.parse(%(<span class="badge&#32;big">x</span>)).children.first
    assert_equal %w[badge big], el.static_classes
  end

  def test_leaves_script_and_style_content_verbatim
    assert_includes convert("<script>if (a &amp;&amp; b) {}</script>"), %(raw(safe("if (a &amp;&amp; b) {}")))
  end

  def test_decodes_haml_text_but_not_the_escaped_filter
    out = RubyUIConverter.convert_string("%p &copy; 2026\n:escaped\n  &copy;\n", format: :haml)

    assert_includes out, %(p { "© 2026" })
    assert_includes out, %(plain " &copy;")
  end
end
