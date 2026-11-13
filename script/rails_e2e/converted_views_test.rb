# frozen_string_literal: true

require "test_helper"

# Copied into the throwaway app by script/rails_e2e/run.sh.
class ConvertedViewsTest < ActionDispatch::IntegrationTest
  test "converted Phlex/RubyUI views render end to end" do
    category = Category.create!(name: "Books")
    product = Product.create!(
      name: "Widget", description: "A widget", price: 9.99, quantity: 3, rating: 4.5,
      active: true, published_on: Date.today, published_at: Time.current,
      metadata: { "a" => 1 }, category: category
    )

    get products_path
    assert_response :success
    assert_includes response.body, "Widget"
    assert_includes response.body, "New product"

    get product_path(product)
    assert_response :success
    assert_includes response.body, "9.99"

    get new_product_path
    assert_response :success
    assert_includes response.body, 'name="product[name]"'

    get edit_product_path(product)
    assert_response :success
    assert_includes response.body, 'value="Widget"'

    post products_path, params: { product: { name: "", category_id: category.id } }
    assert_equal 422, response.status
    assert_includes response.body, "prohibited this product from being saved"

    post products_path, params: { product: { name: "Gadget", category_id: category.id, active: "1" } }
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Product was successfully created"
  end
end
