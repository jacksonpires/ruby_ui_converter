# frozen_string_literal: true

require "test_helper"

class ConverterTest < Minitest::Test
  def write(dir, rel, content)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def test_converts_views_recursively_and_writes_rb_files_in_place
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/users/index.html.erb", "<h1><%= @title %></h1>")
      write(dir, "views/users/_form.html.erb", "<p><%= user.email %></p>")

      results = RubyUIConverter::Converter.new(File.join(dir, "views")).run

      assert results.all? { |r| r.status == :written }

      index = File.read(File.join(dir, "views/users/index.rb"))
      assert_includes index, "module Views"
      assert_includes index, "class Index < Phlex::HTML"
      assert_includes index, "def view_template"

      form = File.read(File.join(dir, "views/users/form.rb"))
      assert_includes form, "class Form < Phlex::HTML"
      assert_includes form, "def initialize(user: nil)"
      assert_includes form, "attr_reader :user"
    end
  end

  def test_generates_an_initializer_from_the_controller_ivars_a_top_level_view_reads
    Dir.mktmpdir("ruc") do |dir|
      path = write(dir, "views/products/index.html.erb", <<~ERB)
        <h1><%= @title %></h1>
        <% @products.each do |product| %>
          <p><%= product.name %></p>
        <% end %>
      ERB

      RubyUIConverter::Converter.new(path).run
      out = File.join(dir, "views/products/index.rb")
      code = File.read(out)

      assert_includes code, "def initialize(products: nil, title: nil)"
      assert_includes code, "@products = products"
      assert_includes code, "@title = title"
      refute_includes code, "attr_reader"
      assert system("ruby", "-c", out, out: File::NULL, err: File::NULL)
    end
  end

  def test_emits_no_initializer_for_a_top_level_view_with_no_controller_ivars
    Dir.mktmpdir("ruc") do |dir|
      path = write(dir, "views/pages/about.html.erb", "<h1>About</h1>")

      RubyUIConverter::Converter.new(path).run
      code = File.read(File.join(dir, "views/pages/about.rb"))

      refute_includes code, "def initialize"
    end
  end

  def test_anchors_the_namespace_at_app_views_even_when_converting_a_subfolder
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "app/views/users/index.html.erb", "<h1>Hi</h1>")

      RubyUIConverter::Converter.new(File.join(dir, "app/views/users")).run
      code = File.read(File.join(dir, "app/views/users/index.rb"))

      assert_includes code, "module Views"
      assert_includes code, "module Users"
      assert_includes code, "class Index"
    end
  end

  def test_anchors_single_file_conversions_inside_app_views
    Dir.mktmpdir("ruc") do |dir|
      path = write(dir, "app/views/users/show.html.erb", "<p>x</p>")

      RubyUIConverter::Converter.new(path).run
      code = File.read(File.join(dir, "app/views/users/show.rb"))

      assert_includes code, "module Users"
    end
  end

  def test_mirrors_the_anchored_subtree_into_output_root
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "app/views/users/index.html.erb", "<p>x</p>")
      config = RubyUIConverter::Configuration.new(output_root: File.join(dir, "out"))

      RubyUIConverter::Converter.new(File.join(dir, "app/views/users"), config: config).run

      assert File.exist?(File.join(dir, "out/users/index.rb"))
    end
  end

  def test_honors_an_explicit_config_root_over_the_convention
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "app/views/users/index.html.erb", "<h1>Hi</h1>")
      config = RubyUIConverter::Configuration.new(root: File.join(dir, "app/views/users"))

      RubyUIConverter::Converter.new(File.join(dir, "app/views/users"), config: config).run
      code = File.read(File.join(dir, "app/views/users/index.rb"))

      assert_includes code, "module Views"
      refute_includes code, "module Users"
    end
  end

  def test_keeps_paths_outside_app_views_relative_to_the_converted_folder
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "erb/widgets/box.html.erb", "<p>x</p>")

      RubyUIConverter::Converter.new(File.join(dir, "erb")).run
      code = File.read(File.join(dir, "erb/widgets/box.rb"))

      assert_includes code, "module Widgets"
    end
  end

  def test_skips_existing_files_unless_force_is_given
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/x/show.html.erb", "<p>hi</p>")
      config = RubyUIConverter::Configuration.new
      first = RubyUIConverter::Converter.new(File.join(dir, "views"), config: config).run
      assert_equal :written, first.first.status

      second = RubyUIConverter::Converter.new(File.join(dir, "views"), config: config).run
      assert_equal :skipped, second.first.status

      forced = RubyUIConverter::Converter.new(
        File.join(dir, "views"),
        config: RubyUIConverter::Configuration.new(force: true)
      ).run
      assert_equal :written, forced.first.status
    end
  end

  def test_creates_the_output_tree_when_output_root_is_given
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/users/index.html.erb", "<p>hi</p>")
      config = RubyUIConverter::Configuration.new(output_root: File.join(dir, "out"))
      results = RubyUIConverter::Converter.new(File.join(dir, "views"), config: config).run

      assert_equal :written, results.first.status
      assert File.exist?(File.join(dir, "out/users/index.rb"))
    end
  end

  def test_does_not_write_files_in_dry_run_mode
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/y/edit.html.erb", "<p>hi</p>")
      config = RubyUIConverter::Configuration.new(dry_run: true)
      results = RubyUIConverter::Converter.new(File.join(dir, "views"), config: config).run

      assert_equal :previewed, results.first.status
      refute File.exist?(File.join(dir, "views/y/edit.rb"))
    end
  end

  def test_produces_syntactically_valid_ruby
    Dir.mktmpdir("ruc") do |dir|
      path = write(dir, "views/z/page.html.erb", <<~ERB)
        <section class="wrap">
          <% if @ok %>
            <%= link_to "Go", path, class: "x" %>
          <% else %>
            <p>no</p>
          <% end %>
        </section>
      ERB

      RubyUIConverter::Converter.new(path).run
      out = File.join(dir, "views/z/page.rb")
      assert system("ruby", "-c", out, out: File::NULL, err: File::NULL)
    end
  end

  def test_maps_elements_to_rubyui_components_end_to_end
    Dir.mktmpdir("ruc") do |dir|
      path = write(dir, "views/w/list.html.erb", <<~ERB)
        <table>
          <tbody>
            <% @users.each do |user| %>
              <tr>
                <td><%= user.name %></td>
                <td><a href="<%= url_for(user) %>">Show</a></td>
              </tr>
            <% end %>
          </tbody>
        </table>
        <input type="checkbox" name="all">
        <button type="submit">Save</button>
      ERB

      RubyUIConverter::Converter.new(path).run
      out = File.join(dir, "views/w/list.rb")
      code = File.read(out)

      assert_includes code, "Table() do"
      assert_includes code, "TableBody() do"
      assert_includes code, "TableRow() do"
      assert_includes code, "TableCell() { user.name }"
      assert_includes code, %(Link(href: url_for(user)) { "Show" })
      assert_includes code, %(Checkbox(name: "all"))
      assert_includes code, %(Button(type: "submit") { "Save" })
      assert system("ruby", "-c", out, out: File::NULL, err: File::NULL)
    end
  end
end
