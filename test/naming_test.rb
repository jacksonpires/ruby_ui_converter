# frozen_string_literal: true

require "test_helper"

class NamingTest < Minitest::Test
  def test_class_name_camelizes_basenames_and_strips_partial_underscores
    assert_equal "Index", RubyUIConverter::Naming.class_name("index")
    assert_equal "Form", RubyUIConverter::Naming.class_name("_form")
    assert_equal "UserProfile", RubyUIConverter::Naming.class_name("user_profile")
  end

  def test_namespace_parts_combines_base_namespace_with_directory_parts
    assert_equal %w[Views Users], RubyUIConverter::Naming.namespace_parts("users", "Views")
    assert_equal %w[Views Admin Reports], RubyUIConverter::Naming.namespace_parts("admin/reports", "Views")
    assert_equal %w[Views], RubyUIConverter::Naming.namespace_parts("", "Views")
  end

  def test_namespace_parts_supports_nested_base_namespaces
    assert_equal %w[App Views Users], RubyUIConverter::Naming.namespace_parts("users", "App::Views")
  end

  def test_partial_const_resolves_absolute_partial_paths
    const = RubyUIConverter::Naming.partial_const("shared/header", base_namespace: "Views")
    assert_equal "Views::Shared::Header", const
  end

  def test_partial_const_resolves_relative_partials_against_the_current_namespace
    const = RubyUIConverter::Naming.partial_const(
      "form",
      base_namespace: "Views",
      current_namespace_parts: %w[Views Users]
    )
    assert_equal "Views::Users::Form", const
  end
end
