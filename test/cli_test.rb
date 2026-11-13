# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "ruby_ui_converter/cli"

class CLITest < Minitest::Test
  def write(dir, rel, content)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  # --dry-run keeps the prerequisite check warn-only (never prompts/installs).
  def run_cli(*args)
    capture_io { RubyUIConverter::CLI.start(["convert", *args, "--dry-run"]) }.first
  end

  def test_explains_a_missing_haml_gem_once_for_all_haml_files
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/a/one.html.haml", "%p one")
      write(dir, "views/a/two.html.haml", "%p two")
      write(dir, "views/a/three.html.erb", "<p>three</p>")

      out = RubyUIConverter::HamlParser.stub(:require_haml, -> { raise LoadError }) do
        run_cli(File.join(dir, "views"))
      end

      assert_equal 2, out.scan("haml gem not available").size
      assert_equal 1, out.scan("requires the haml gem").size
      assert_includes out, "2 error"
      assert_includes out, "1 previewed"
    end
  end

  def test_says_nothing_about_haml_when_it_is_available
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "views/a/one.html.haml", "%p one")

      out = run_cli(File.join(dir, "views"))

      assert_includes out, "preview"
      refute_includes out, "haml gem"
    end
  end
end
