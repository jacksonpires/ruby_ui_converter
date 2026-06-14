# frozen_string_literal: true

require "test_helper"

class LiteralTest < Minitest::Test
  def write(dir, rel, content)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def convert(dir, rel, content, **opts)
    path = write(dir, rel, content)
    config = RubyUIConverter::Configuration.new(literal: true, **opts)
    RubyUIConverter::Converter.new(File.join(dir, "views"), config: config).run
    File.read(path.sub(/_?(\w+)\.html\.erb\z/, '\1.rb'))
  end

  def test_emits_props_instead_of_initialize_attr_reader
    Dir.mktmpdir("ruc") do |dir|
      code = convert(dir, "views/users/_user.html.erb", <<~ERB)
        <div id="<%= dom_id user %>">
          <p><%= user.name %></p>
        </div>
      ERB

      assert_includes code, "prop :user, _Nilable(User)"
      refute_includes code, "def initialize"
      refute_includes code, "attr_reader"
    end
  end

  def test_rewrites_bare_local_references_to_ivars_in_the_body
    Dir.mktmpdir("ruc") do |dir|
      code = convert(dir, "views/users/_user.html.erb", <<~ERB)
        <div id="<%= dom_id user %>" title="hi <%= user.name %>">
          <% if user.admin? %>
            <p><%= user.email %></p>
          <% end %>
        </div>
      ERB

      assert_includes code, "(dom_id @user)"
      assert_includes code, 'title: "hi #{@user.name}"'
      assert_includes code, "if @user.admin?"
      assert_includes code, "p { @user.email }"
    end
  end

  def test_infers_the_model_type_only_for_the_local_matching_the_partial_name
    Dir.mktmpdir("ruc") do |dir|
      code = convert(dir, "views/users/_card.html.erb", <<~ERB)
        <div><%= card.title %><%= status %></div>
      ERB

      assert_includes code, "prop :card, _Nilable(Card)"
      assert_includes code, "prop :status, _Any?"
    end
  end

  def test_does_not_rewrite_hash_keys_symbols_or_string_contents
    Dir.mktmpdir("ruc") do |dir|
      code = convert(dir, "views/users/_user.html.erb", <<~ERB)
        <%= render "badge", user: user, kind: :user %>
        <p><%= t("user") %></p>
      ERB

      assert_includes code, "Views::Users::Badge.new(user: @user, kind: :user)"
      assert_includes code, %(t("user"))
    end
  end

  def test_leaves_block_shadowed_names_alone
    Dir.mktmpdir("ruc") do |dir|
      code = convert(dir, "views/users/_list.html.erb", <<~ERB)
        <% items.each do |user| %>
          <p><%= user.name %></p>
        <% end %>
      ERB

      assert_includes code, "prop :items, _Any?"
      assert_includes code, "@items.each do |user|"
      assert_includes code, "p { user.name }"
    end
  end

  def test_emits_props_for_the_controller_ivars_a_top_level_view_reads
    Dir.mktmpdir("ruc") do |dir|
      code = convert(dir, "views/users/index.html.erb", "<h1><%= @title %></h1>")

      assert_includes code, "prop :title, _Any?"
      assert_includes code, "h1 { @title }"
      refute_includes code, "def initialize"
    end
  end

  def test_produces_syntactically_valid_ruby
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/x/_user.html.erb", <<~ERB)
        <div id="<%= dom_id user %>"><%= user.name %></div>
      ERB
      config = RubyUIConverter::Configuration.new(literal: true)
      RubyUIConverter::Converter.new(File.join(dir, "views"), config: config).run

      out = File.join(dir, "views/x/user.rb")
      assert system("ruby", "-c", out, out: File::NULL, err: File::NULL)
    end
  end

  def test_default_config_keeps_the_initializer_readers
    Dir.mktmpdir("ruc") do |dir|
      path = write(dir, "views/y/_user.html.erb", "<p><%= user.name %></p>")
      RubyUIConverter::Converter.new(File.join(dir, "views")).run
      code = File.read(path.sub("_user.html.erb", "user.rb"))

      assert_includes code, "def initialize(user: nil)"
      assert_includes code, "attr_reader :user"
      assert_includes code, "user.name"
      refute_includes code, "@user.name"
    end
  end
end
