# frozen_string_literal: true

require "test_helper"

class LexerTest < Minitest::Test
  def tokens_for(src)
    _html, registry = RubyUIConverter::Lexer.new(src).tokenize_with_placeholders
    registry.values
  end

  def test_classifies_output_tags
    token = tokens_for("<%= user.name %>").first
    assert_equal :output, token.type
    assert_equal "user.name", token.value
    refute token.raw
  end

  def test_classifies_unescaped_output_tags
    token = tokens_for("<%== raw_html %>").first
    assert_equal :output, token.type
    assert token.raw
  end

  def test_classifies_eval_and_comment_tags
    types = tokens_for("<% x = 1 %><%# note %>").map(&:type)
    assert_equal %i[eval comment], types
  end

  def test_replaces_erb_with_placeholders_in_the_html_stream
    html, = RubyUIConverter::Lexer.new("<a><%= 1 %></a>").tokenize_with_placeholders
    assert_match(%r{<a>RUCxERBx0xERBxRUC</a>}, html)
  end

  def test_handles_trim_markers
    token = tokens_for("<%- y = 2 -%>").first
    assert_equal :eval, token.type
    assert_equal "y = 2", token.value
  end
end
