# frozen_string_literal: true

# Applies the manual migration steps from docs/practical-example.md to the
# scaffolded app: helper adapters on the base component, explicit Phlex renders
# in the controllers and a validation so each form's error branch is exercised.
# Run from the app root.

def patch(path)
  src = File.read(path)
  out = yield(src.dup)
  abort "patch_app: nothing changed in #{path}" if out == src
  File.write(path, out)
end

HELPERS = %w[ContentFor Notice ButtonTo DOMID FormWith Pluralize].freeze

patch("app/components/base.rb") do |src|
  src.sub(/^(\s*)include Phlex::Rails::Helpers::Routes\n/) do
    indent = Regexp.last_match(1)
    $& + HELPERS.map { |m| "#{indent}include Phlex::Rails::Helpers::#{m}\n" }.join
  end
end

# Points a scaffolded controller at the converted Views::<Plural>::* classes.
def patch_controller(singular, plural)
  views = "Views::#{plural.capitalize}"

  patch("app/controllers/#{plural}_controller.rb") do |src|
    src
      .sub(/^(\s*)@#{plural} = #{singular.capitalize}\.all\n/) do
        "#{$&}#{Regexp.last_match(1)}render #{views}::Index.new(#{plural}: @#{plural})\n"
      end
      .sub(/^  def show\n/) { "#{$&}    render #{views}::Show.new(#{singular}: @#{singular})\n" }
      .sub(/^(\s*)@#{singular} = #{singular.capitalize}\.new\n/) do
        "#{$&}#{Regexp.last_match(1)}render #{views}::New.new(#{singular}: @#{singular})\n"
      end
      .sub(/^  def edit\n/) { "#{$&}    render #{views}::Edit.new(#{singular}: @#{singular})\n" }
      .gsub(/render :(new|edit), status: (:unprocessable_\w+)/) do
        "render #{views}::#{Regexp.last_match(1).capitalize}.new(#{singular}: @#{singular}), " \
          "status: #{Regexp.last_match(2)}"
      end
  end
end

patch_controller("product", "products") # ERB views
patch_controller("supplier", "suppliers") # HAML views

patch("app/models/product.rb") do |src|
  src.sub(/^(\s*)belongs_to :category\n/) { "#{$&}#{Regexp.last_match(1)}validates :name, presence: true\n" }
end

patch("app/models/supplier.rb") do |src|
  src.sub(/^class Supplier < ApplicationRecord\n/) { "#{$&}  validates :name, presence: true\n" }
end
