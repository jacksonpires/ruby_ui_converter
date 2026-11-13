# frozen_string_literal: true

require "test_helper"

class RubyLiteralTest < Minitest::Test
  def parts(code)
    RubyUIConverter::RubyLiteral.string_parts(code)
  end

  def test_splits_a_double_quoted_literal_into_text_and_code
    assert_equal [[:text, "Hello "], [:code, "@user.name"], [:text, "!"]], parts('"Hello #{@user.name}!"')
  end

  def test_keeps_nested_strings_and_braces_inside_interpolations
    assert_equal [[:code, 'a ? "x" : { b: 1 }[:b]'], [:text, " end"]], parts('"#{a ? "x" : { b: 1 }[:b]} end"')
  end

  def test_supports_the_ivar_shorthand_interpolation
    assert_equal [[:text, "x "], [:code, "@foo"], [:text, " y"]], parts('"x #@foo y"')
  end

  def test_decodes_escapes_in_double_quoted_literals
    assert_equal [[:text, %(say "hi"\nnow \#{not})]], parts('"say \"hi\"\nnow \#{not}"')
  end

  def test_decodes_dumped_unicode_escapes_like_haml_produces
    assert_equal [[:text, "Olá "], [:code, "x"]], parts('"Olá #{x}"')
  end

  def test_keeps_raw_non_ascii_text_even_next_to_escapes
    assert_equal [[:text, "Olá\t\"mundo\""]], parts('"Olá\t\"mundo\""')
  end

  def test_decodes_single_quoted_literals
    assert_equal [[:text, "it's static"]], parts(%q('it\'s static'))
  end

  def test_returns_an_empty_list_for_an_empty_string
    assert_equal [], parts('""')
  end

  def test_rejects_anything_that_is_not_a_single_string_literal
    ['"a" + b', '"a".upcase', ":delete", "user.name", "%w[a b]", '"a" "b"', "", "x(", '"#{x}" if y'].each do |code|
      assert_nil parts(code), "expected nil for #{code.inspect}"
    end
  end
end
