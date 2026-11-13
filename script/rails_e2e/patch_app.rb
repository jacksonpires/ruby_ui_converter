# frozen_string_literal: true

# Applies the manual migration steps from docs/practical-example.md to the
# scaffolded app: helper adapters on the base component, explicit Phlex renders
# in the controller and a validation so the form's error branch is exercised.
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

patch("app/controllers/products_controller.rb") do |src|
  src
    .sub(/^(\s*)@products = Product\.all\n/) { "#{$&}#{Regexp.last_match(1)}render Views::Products::Index.new(products: @products)\n" }
    .sub(/^  def show\n/) { "#{$&}    render Views::Products::Show.new(product: @product)\n" }
    .sub(/^(\s*)@product = Product\.new\n/) { "#{$&}#{Regexp.last_match(1)}render Views::Products::New.new(product: @product)\n" }
    .sub(/^  def edit\n/) { "#{$&}    render Views::Products::Edit.new(product: @product)\n" }
    .gsub(/render :(new|edit), status: (:unprocessable_\w+)/) do
      "render Views::Products::#{Regexp.last_match(1).capitalize}.new(product: @product), status: #{Regexp.last_match(2)}"
    end
end

patch("app/models/product.rb") do |src|
  src.sub(/^(\s*)belongs_to :category\n/) { "#{$&}#{Regexp.last_match(1)}validates :name, presence: true\n" }
end
