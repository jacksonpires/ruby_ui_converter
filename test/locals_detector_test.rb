# frozen_string_literal: true

require "test_helper"

class LocalsDetectorTest < Minitest::Test
  def locals_for(src)
    RubyUIConverter::LocalsDetector.new(RubyUIConverter::Parser.new(src).parse).locals
  end

  def ivars_for(src)
    RubyUIConverter::LocalsDetector.new(RubyUIConverter::Parser.new(src).parse).ivars
  end

  def test_detects_bare_identifiers_as_locals
    assert_equal ["user"], locals_for("<p><%= user.name %></p>")
  end

  def test_detects_local_assigns_lookups
    assert_includes locals_for("<% title = local_assigns[:title] %>"), "title"
  end

  def test_ignores_block_parameters_and_assigned_variables
    src = "<% items.each do |item| %><p><%= item %></p><% end %>"
    assert_equal ["items"], locals_for(src)
  end

  def test_ignores_rails_helpers_like_dom_id_and_notice
    src = %(<div id="<%= dom_id user %>"><%= notice %><%= alert %></div>)
    assert_equal ["user"], locals_for(src)
  end

  def test_ivars_detects_controller_instance_variables_sorted
    src = "<h1><%= @title %></h1><% @products.each do |p| %><%= p %><% end %>"
    assert_equal %w[products title], ivars_for(src)
  end

  def test_ivars_ignores_ivars_assigned_within_the_template
    assert_equal [], ivars_for("<% @count = items.size %><p><%= @count %></p>")
  end

  def test_ivars_ignores_class_variables
    assert_equal [], ivars_for("<p><%= @@registry %></p>")
  end

  def test_ivars_ignores_at_inside_string_literals
    assert_equal [], ivars_for(%(<%= mail_to "user@example.com" %>))
  end
end
