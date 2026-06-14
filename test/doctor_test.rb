# frozen_string_literal: true

require "test_helper"

class DoctorTest < Minitest::Test
  def write(dir, rel, content)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def result_with(code)
    RubyUIConverter::Converter::Result.new(code: code, status: :written)
  end

  def doctor(dir, results: [], config: RubyUIConverter::Configuration.new, start_path: nil)
    start_path ||= File.join(dir, "app/views")
    FileUtils.mkdir_p(start_path)
    RubyUIConverter::Doctor.new(results, config: config, start_path: start_path)
  end

  def test_finds_the_app_root_by_walking_up_to_the_nearest_gemfile
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", "")
      assert_equal dir, doctor(dir).app_root
    end
  end

  def test_reports_no_issues_when_there_is_no_gemfile_above_the_path
    Dir.mktmpdir("ruc") do |dir|
      assert_equal [], doctor(dir).issues
    end
  end

  def test_detects_a_missing_phlex_rails_gem
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "rails"\n))
      issue = doctor(dir).issues.find { |i| i.description.include?("phlex-rails") }
      assert_includes issue.commands, "bundle add phlex-rails"
    end
  end

  def test_detects_missing_ruby_ui_gem_and_components_from_the_emitted_code
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\n))
      results = [result_with(%(Link(href: x) { "a" }\nTableCell() { "b" }))]

      issues = doctor(dir, results: results).issues
      gem_issue = issues.find { |i| i.description.include?(%(gem "ruby_ui")) }
      components = issues.find { |i| i.description.include?("components not generated") }

      assert_includes gem_issue.commands, "bundle add ruby_ui"
      assert_includes components.description, "Link, Table"
      assert_equal [
        "bin/rails generate ruby_ui:component Link",
        "bin/rails generate ruby_ui:component Table"
      ], components.commands
    end
  end

  def test_skips_components_already_generated_in_app_components_ruby_ui
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\ngem "ruby_ui"\n))
      write(dir, "app/components/ruby_ui/link/link.rb", "")
      results = [result_with(%(Link(href: x) { "a" }\nInput(type: "text")))]

      components = doctor(dir, results: results).issues.find { |i| i.description.include?("not generated") }
      assert_includes components.description, "Input"
      refute_includes components.description, "Link"
    end
  end

  def test_is_silent_about_ruby_ui_when_no_kit_components_were_emitted
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\n))
      results = [result_with("div { 'x' }")]

      refute_includes doctor(dir, results: results).issues.map(&:description).join, "ruby_ui"
    end
  end

  def test_detects_the_missing_literal_gem_and_literal_properties_with_literal
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\n))
      write(dir, "app/components/base.rb", "class Components::Base < Phlex::HTML\nend\n")
      config = RubyUIConverter::Configuration.new(literal: true)

      issues = doctor(dir, config: config).issues
      assert_equal ["bundle add literal"], issues.find { |i| i.description.include?(%(gem "literal")) }.commands
      refute_nil issues.find { |i| i.description.include?("Literal::Properties") }
    end
  end

  def test_fixer_inserts_extend_literal_properties_into_the_base_class
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\ngem "literal"\n))
      base = write(dir, "app/components/base.rb", "class Components::Base < Phlex::HTML\n  include RubyUI\nend\n")
      config = RubyUIConverter::Configuration.new(literal: true)

      issue = doctor(dir, config: config).issues.find { |i| i.description.include?("Literal::Properties") }
      issue.fixer.call

      assert_includes File.read(base),
                      "class Components::Base < Phlex::HTML\n  extend Literal::Properties\n  include RubyUI"
    end
  end

  def test_detects_the_broken_tw_animate_css_import_left_by_ruby_ui_install
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\n))
      css = write(dir, "app/assets/tailwind/application.css",
                  %(@import "tailwindcss";\n@import "../../../vendor/javascript/tw-animate-css.js";\n))

      issue = doctor(dir).issues.find { |i| i.description.include?("tw-animate-css") }
      assert_includes issue.commands.first, "curl -fsSL -o app/assets/tailwind/tw-animate.css"

      issue.fixer.call
      assert_includes File.read(css), %(@import "./tw-animate.css";)
      refute_includes File.read(css), "vendor/javascript"
    end
  end

  def test_does_not_flag_tw_animate_css_when_the_vendor_file_exists_or_the_import_is_absent
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\n))
      write(dir, "app/assets/tailwind/application.css",
            %(@import "tailwindcss";\n@import "../../../vendor/javascript/tw-animate-css.js";\n))
      write(dir, "vendor/javascript/tw-animate-css.js", "/* pinned */")

      refute_includes doctor(dir).issues.map(&:description).join, "tw-animate-css"

      write(dir, "app/assets/tailwind/application.css", %(@import "tailwindcss";\n))
      FileUtils.rm(File.join(dir, "vendor/javascript/tw-animate-css.js"))
      refute_includes doctor(dir).issues.map(&:description).join, "tw-animate-css"
    end
  end

  def test_reports_nothing_when_everything_is_in_place
    Dir.mktmpdir("ruc") do |dir|
      write(dir, "Gemfile", %(gem "phlex-rails"\ngem "ruby_ui"\ngem "literal"\n))
      write(dir, "app/components/base.rb", "class Components::Base < Phlex::HTML\n  extend Literal::Properties\nend\n")
      write(dir, "app/components/ruby_ui/link/link.rb", "")
      config = RubyUIConverter::Configuration.new(literal: true)
      results = [result_with(%(Link(href: x) { "a" }))]

      assert_equal [], doctor(dir, results: results, config: config).issues
    end
  end
end
