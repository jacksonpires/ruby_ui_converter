# Practical example: scaffold → Phlex/RubyUI in a fresh Rails app

A complete, copy-pasteable walkthrough: create a Rails app, scaffold a resource
with every common column type, add the gem, convert the views, point the
controller at the new components, and see it render.

## 1. Create the app

```bash
rails new test_app --css=tailwind
cd test_app
```

## 2. Scaffold a resource with all the data types

We also add a `belongs_to` association (`category:references`) so the form has a
select. Scaffold `Category` too (so there's a UI to register categories), then
scaffold `Product`:

```bash
bin/rails generate scaffold Category name:string

bin/rails generate scaffold Product \
  name:string \
  description:text \
  price:decimal \
  quantity:integer \
  rating:float \
  active:boolean \
  published_on:date \
  published_at:datetime \
  metadata:json \
  category:references

bin/rails db:migrate
```

(`category:references` adds `belongs_to :category` to the `Product` model and a
`category_id` column.) This generates the usual ERB views under
`app/views/categories/` and `app/views/products/`
(`index.html.erb`, `show.html.erb`, `new.html.erb`, `edit.html.erb`,
`_form.html.erb`, `_product.html.erb`). Start the server and visit
`http://localhost:3000/products` to confirm the plain-ERB scaffold works first:

```bash
bin/dev
```

### Marking required fields

The converter is a static ERB → Phlex tool — it never boots Rails or reads your
database, so it **cannot** infer `required` from `NOT NULL` columns or model
validations. What it does instead is **pass through** whatever options the field
already has. So to get `required` on the front end, add it in
`app/views/products/_form.html.erb` for the fields you want (typically your
`null: false` columns — say `name` and `price`):

```erb
<%= form.text_field :name, required: true %>
<%= form.text_field :price, required: true %>
```

The converter then keeps it on the generated RubyUI component:

```ruby
Input(name: "product[name]", id: "product[name]", value: product.name.to_s, required: true)
```

### An association select

> [!IMPORTANT]
> Rails scaffolds a `references` column as a plain
> `<%= form.text_field :category_id %>` — **it does not build a select**. So out
> of the box the converter (correctly) maps that to an `Input`, not a
> `NativeSelect`. To get the select, you must **edit the ERB before converting**:
> swap the `text_field` for a `collection_select`. No edit, no `NativeSelect`.

In `app/views/products/_form.html.erb`, replace the generated category field:

```erb
<%# before — what the scaffold generated %>
<%= form.text_field :category_id %>

<%# after — edit it to this, then convert %>
<%= form.collection_select :category_id, Category.all, :id, :name %>
```

The converter maps the `collection_select` to a RubyUI `NativeSelect`, building
the `<option>` loop for you. So this:

```erb
<div class="my-5">
  <%= form.label :category_id %>
  <%= form.collection_select :category_id, Category.all, :id, :name %>
</div>
```

becomes:

```ruby
div(class: "my-5") do
  FormFieldLabel(for: "product[category_id]") { "Category id" }
  NativeSelect(name: "product[category_id]", id: "product[category_id]") do
    Category.all.each do |option|
      NativeSelectOption(value: option.id, selected: product.category_id == option.id) { option.name }
    end
  end
  FormFieldError { product.errors[:category_id].to_sentence.upcase_first }
end
```

Notice it goes well past a one-to-one tag swap: the collection becomes a real
`each` loop of `NativeSelectOption`s, the current value is pre-selected, and a
`FormFieldError` is wired up — all from one line of ERB. (Extra
`collection_select` options/`html_options` beyond the four positionals aren't
carried over; add them to the `NativeSelect` by hand. `form.select` with
arbitrary `choices` is left as-is for you to convert.)

### Showing the association name instead of the id

The same scaffold limitation shows up on the **show** page: the `_product`
partial renders `<%= product.category_id %>`, so it prints the raw foreign key
(e.g. `3`). The converter maps it faithfully to `plain(product.category_id)` —
it can't know you'd rather show the category's name. Fix it in the ERB
(`app/views/products/_product.html.erb`) to read through the association:

```erb
<%# before — prints the id %>
<%= product.category_id %>

<%# after — prints the name %>
<%= product.category&.name %>
```

which converts to `plain(product.category&.name)`. (The `&.` guards against a
product without a category.)

## 3. Add phlex-rails and RubyUI

The converter only generates the component source — the app needs Phlex (and,
for the default mapping, RubyUI) to render it:

```bash
bundle add phlex-rails
bin/rails generate phlex:install        # creates Views::Base / Components::Base, wires the autoloader

bundle add ruby_ui
bin/rails generate ruby_ui:install       # adds `include RubyUI` to Components::Base
```

Then add the converter itself (development only):

```bash
bundle add ruby_ui_converter --group development
```

This scaffold renders its links with `link_to` (→ `Link`) and its form with
`form_with` field helpers, which the converter maps to RubyUI form components
(`form.text_field` → `Input`, `form.textarea` → `Textarea`, `form.checkbox` →
`Checkbox`, `form.collection_select` → `NativeSelect`, `form.label` →
`FormFieldLabel` from the `Form` family, `form.submit` → `Button`, and the flash
`<p id="notice">` → `Alert`).

You **don't** need to generate those components up front: after you convert
(next step) the CLI's doctor detects exactly which ones the generated code
references but are missing, and offers to run `ruby_ui:component` for you — so
just convert and let it guide you. (See the
[RubyUI element mapping](../README.md#rubyui-element-mapping) and
[form-builder mapping](../README.md#form-builder-mapping) in the README.)

Generated components call Rails view helpers, so include the phlex-rails
adapters once on the base class:

For this `Product` scaffold the converted views call these helpers, so include
the matching adapters (each comment shows which view uses it):

```ruby
# app/components/base.rb
class Components::Base < Phlex::HTML
  include RubyUI

  include Phlex::Rails::Helpers::Routes      # *_path / url_for (index, show, new, edit)
  include Phlex::Rails::Helpers::ContentFor  # content_for :title (every top-level view)
  include Phlex::Rails::Helpers::Notice      # notice (index, show)
  include Phlex::Rails::Helpers::ButtonTo    # button_to "Destroy" (index, show)
  include Phlex::Rails::Helpers::DOMID       # dom_id product (_product)
  include Phlex::Rails::Helpers::FormWith    # form_with (_form)
  include Phlex::Rails::Helpers::Pluralize   # pluralize(...errors...) (_form)
end
```

(`render` is handled by Phlex/phlex-rails itself, and the `form.label` /
`form.text_field` / ... calls are methods on the `form_with` builder, so neither
needs its own adapter.)

Each bare helper a converted view calls needs the matching
`Phlex::Rails::Helpers::*` module included here, or it raises `NoMethodError` /
`undefined local variable or method` at render time — the error message tells
you exactly which module to add. If your views use other helpers, add the
corresponding module the same way.

## 4. Convert the views

Preview first, then convert for real. Use `--base-class "Views::Base"` so the
generated classes inherit the helpers configured above:

```bash
# preview — prints what would be generated, writes nothing
bundle exec ruby_ui_converter convert app/views/products --dry-run

# convert — writes app/views/products/*.rb next to each .erb
bundle exec ruby_ui_converter convert app/views/products --base-class "Views::Base"
```

You now have, for example:

```
app/views/products/index.html.erb    ->  app/views/products/index.rb    (Views::Products::Index)
app/views/products/show.html.erb      ->  app/views/products/show.rb     (Views::Products::Show)
app/views/products/_form.html.erb     ->  app/views/products/form.rb     (Views::Products::Form)
app/views/products/_product.html.erb  ->  app/views/products/product.rb  (Views::Products::Product)
```

After the run the CLI's doctor checks the app for missing prerequisites (gems,
RubyUI components actually referenced by the generated code, `Literal::Properties`
on the base class) and **offers to install them**. Since we skipped generating
the components in step 3, you'll see something like:

```
Missing prerequisites detected:
  - RubyUI components not generated: Link, Input, Textarea, Checkbox, NativeSelect, Button, Form, Alert
Install now? [Y/n]
```

Just press Enter (yes is the default) and it runs
`bin/rails generate ruby_ui:component ...` for you — no need to have typed them
by hand. (Answer `n`, or run with `--dry-run` / no TTY, and it just prints the
exact commands instead of installing.)

## 5. Update the controller

Controller instance variables are **not** shared with Phlex components, so each
view needs an initializer that takes them as keyword arguments. The converter
generates this for you — it reads the controller ivars each top-level view
references and emits a matching initializer:

```ruby
# app/views/products/index.rb  (generated)
class Views::Products::Index < Views::Base
  def initialize(products: nil)
    @products = products
  end
  # ...
end

# app/views/products/show.rb  (generated)
class Views::Products::Show < Views::Base
  def initialize(product: nil)
    @product = product
  end
  # ...
end
```

(The keyword args default to `nil`; tighten them to required where it makes
sense. `notice` in the scaffold views is a flash helper, not an ivar, so the
converter leaves it as a bare `notice` call and does **not** add it as an
argument — that's why `Phlex::Rails::Helpers::Notice` is included on the base
class in step 3. Without it you get `undefined local variable or method
'notice'`.)

Then swap the implicit renders in the controller for explicit component
renders:

```ruby
# app/controllers/products_controller.rb
def index
  @products = Product.all
  render Views::Products::Index.new(products: @products)
end

def show
  render Views::Products::Show.new(product: @product)
end
```

Leave the actions you haven't migrated alone — the original `.erb` files are
never modified, so they keep rendering through ERB until you convert them.

## 6. See the result

```bash
bin/dev
```

First register a couple of categories at `http://localhost:3000/categories/new`
(that scaffold is still plain ERB — we only converted `products`), so the
product form's select has something to choose from. Then head to
`http://localhost:3000/products/new` to create a product and pick its category.

Reload `http://localhost:3000/products`: the index, show and form pages now
render through your Phlex/RubyUI components (`Link`, the flash `notice` as an
`Alert`, and on the form `Input`, `Textarea`, `Checkbox`, `NativeSelect` for the
category association, `Button`, `FormFieldLabel`, with a `FormFieldError` per
field for backend errors) plus plain Phlex elements like `div`/`h1`/`p`, instead
of ERB. Review each generated file — see
[Design & limitations](../README.md#design--limitations) for the cases that need
manual attention (notably the `_form` partial, where `form_with` blocks may need
phlex-rails idioms).

> [!TIP]
> Layout spacing lives outside the converted views, so the converter never
> touches it. The default Rails layout (`app/views/layouts/application.html.erb`)
> wraps content in `<main class="container mx-auto mt-28 px-5 flex">` — top
> margin but **no bottom padding**, so on long pages (like the form) the buttons
> end up flush against the bottom of the window. Add some bottom padding there:
>
> ```erb
> <main class="container mx-auto mt-28 pb-28 px-5 flex">
> ```
