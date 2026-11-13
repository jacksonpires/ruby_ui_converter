# frozen_string_literal: true

require "test_helper"

# Text, whitespace, comments and filters of the HAML front-end.
class HamlTextTest < Minitest::Test
  def convert(src, **opts)
    RubyUIConverter.convert_string(src, class_name: "T", format: :haml, **opts)
  end

  # --- text --------------------------------------------------------------

  def test_separates_text_lines_from_neighbouring_siblings_like_haml_newlines
    out = convert(<<~HAML)
      %p
        Signed in as
        %strong= name
        and online
    HAML

    assert_includes out, %(plain "Signed in as "\n      strong { name }\n      plain " and online")
  end

  def test_keeps_the_pipe_separator_between_links_spaced
    out = convert(<<~HAML)
      %div
        = link_to "Show", product
        |
        = link_to "Back", products_path
    HAML

    assert_includes out, %(plain " | ")
  end

  def test_does_not_pad_text_next_to_a_tag_that_removes_outer_whitespace
    out = convert("%p\n  before\n  %img{src: \"a.png\"}>\n  after\n", ruby_ui: false)

    assert_includes out, %(plain "before"\n      img(src: "a.png")\n      plain "after")
  end

  def test_turns_inline_html_inside_text_into_elements
    out = convert(%(%p Hello <em>there</em> \#{name}!), ruby_ui: false)

    assert_includes out, %(plain "Hello "\n      em { "there" }\n      whitespace\n      plain(name)\n      plain "!")
  end

  def test_keeps_a_lone_inline_text_child_inline
    assert_includes convert("%p Hello"), %(p { "Hello" })
  end

  # --- comments ----------------------------------------------------------

  def test_renders_nested_content_of_an_html_comment_inside_a_comment_block
    out = convert("/\n  %p= secret\n", ruby_ui: false)

    assert_includes out, "comment do\n      p { secret }\n    end"
  end

  def test_leaves_conditional_comments_as_a_todo
    out = convert("/[if IE]\n  %p old\n")

    assert_includes out, "# TODO: HAML conditional comment [if IE] dropped"
    refute_includes out, "old"
  end

  def test_detects_locals_used_inside_a_commented_block
    Dir.mktmpdir("ruc") do |dir|
      path = File.join(dir, "app/views/users/_card.html.haml")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "/\n  %p= user.name\n")

      RubyUIConverter::Converter.new(path).run

      assert_includes File.read(File.join(dir, "app/views/users/card.rb")), "def initialize(user: nil)"
    end
  end

  # --- filters -----------------------------------------------------------

  def test_wraps_javascript_and_css_filters_in_script_and_style
    out = convert(":javascript\n  console.log(\"hi\");\n:css\n  .a { color: red }\n")

    assert_includes out, "script do"
    assert_includes out, %(raw(safe("console.log(\\"hi\\");\\n")))
    assert_includes out, "style do"
    assert_includes out, %(raw(safe(".a { color: red }\\n")))
  end

  def test_keeps_interpolation_inside_a_javascript_filter
    out = convert(":javascript\n  var data = \#{raw_json};\n")

    assert_includes out, %(raw(safe("var data = \#{raw_json};\\n")))
    refute_includes out, "\\\#{raw_json}"
  end

  def test_parses_plain_filter_text_as_html_with_interpolation
    out = convert(":plain\n  Hi <b>there</b> \#{who}\n", ruby_ui: false)

    assert_includes out, %(b { "there" })
    assert_includes out, "plain(who)"
  end

  def test_escapes_the_escaped_filter
    assert_includes convert(":escaped\n  <b>x</b>\n"), %(plain "<b>x</b>")
  end

  def test_reuses_the_erb_parser_for_the_erb_filter
    assert_includes convert(":erb\n  <i><%= foo %></i>\n"), "i { foo }"
  end

  def test_turns_the_ruby_filter_into_statements
    assert_includes convert(":ruby\n  total = items.sum(&:price)\n"), "total = items.sum(&:price)"
  end

  def test_leaves_unsupported_filters_as_commented_todos
    out = convert(":markdown\n  # Title\n")

    assert_includes out, "# TODO: HAML :markdown filter not converted"
    assert_includes out, "# # Title"
  end

  def test_full_template_produces_valid_ruby
    Dir.mktmpdir("ruc") do |dir|
      path = File.join(dir, "page.rb")
      File.write(path, convert(<<~HAML))
        !!!
        %p
          Hi <em>you</em> \#{name}
          %img{src: "a.png"}>
        /
          %p= secret
        :javascript
          var x = \#{json};
        :plain
          done
      HAML

      assert system("ruby", "-c", path, out: File::NULL, err: File::NULL)
    end
  end
end
