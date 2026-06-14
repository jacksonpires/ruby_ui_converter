# ruby_ui_converter

Convert Rails `.erb` views and partials into [Phlex](https://www.phlex.fun) /
[RubyUI](https://rubyui.com) Ruby components.

Point it at a views directory and it walks recursively, converting each `.erb`
template into an equivalent `.rb` file **next to it**:

```
app/views/users/index.html.erb   ->  app/views/users/index.rb   (Views::Users::Index)
app/views/users/_user.html.erb   ->  app/views/users/user.rb    (Views::Users::User)
```

Traditional Rails partials (`_user.html.erb`) become their own Phlex component
classes, with detected locals exposed as keyword arguments. Top-level views get
an initializer for the controller instance variables they reference, so you can
render them with `render Views::Users::Index.new(users: ...)`.

## Installation

Add it to your Gemfile (typically in the `:development` group):

```ruby
gem "ruby_ui_converter", group: :development
```

Or install it directly:

```bash
gem install ruby_ui_converter
```

> [!IMPORTANT]
> The converter itself has no runtime dependencies beyond `thor` — conversion
> works anywhere. However, by default the **generated code** calls RubyUI
> components (`Link(...)`, `Button(...)`, `Input(...)`, ...), so for it to run
> your app must have the [ruby_ui](https://rubygems.org/gems/ruby_ui) gem
> installed, with the corresponding components generated and the kit included
> (`rails g ruby_ui:install` + `rails g ruby_ui:component ...` — see
> [Migrating a Rails ERB app](#migrating-a-rails-erb-app)). If you don't use
> RubyUI, convert with `--no-ruby-ui` to emit plain Phlex elements — then only
> [phlex-rails](https://github.com/phlex-ruby/phlex-rails) is required.
>
> Likewise, converting with `--literal` makes the generated code depend on the
> [literal](https://rubygems.org/gems/literal) gem (`bundle add literal` +
> `extend Literal::Properties` on your base component class — see
> [`--literal`](#--literal-literalproperties-instead-of-initialize)).
>
> You don't have to track this by hand: after each run the CLI **checks the
> target app for these prerequisites** (gems in the Gemfile, generated RubyUI
> components for what the converted code actually uses, `Literal::Properties`
> on the base class) and offers to install what's missing — in non-interactive
> sessions and on `--dry-run` it just prints the exact commands.

> [!TIP]
> Want a hands-on walkthrough? See
> [docs/practical-example.md](docs/practical-example.md) — it goes from
> `rails new` and a scaffold with every common column type all the way to
> rendering the converted Phlex/RubyUI components, step by step.

## CLI usage

```bash
# Convert a whole folder (recursively), writing .rb next to each .erb
bundle exec ruby_ui_converter convert app/views/users

# Preview without writing anything
bundle exec ruby_ui_converter convert app/views --dry-run

# Overwrite existing .rb files
bundle exec ruby_ui_converter convert app/views --force

# Customize the base module namespace and superclass
bundle exec ruby_ui_converter convert app/views --namespace Views --base-class Views::Base

# Write into a separate output tree (mirrors the directory structure)
bundle exec ruby_ui_converter convert app/views -o app/components

# Emit plain Phlex elements instead of RubyUI components
bundle exec ruby_ui_converter convert app/views --no-ruby-ui
```

| Option           | Default       | Description                                                                                   |
| ---------------- | ------------- | --------------------------------------------------------------------------------------------- |
| `--namespace`    | `Views`       | Base module namespace for generated constants                                                 |
| `--root`         | _(auto)_      | Directory namespaces are derived from (default: nearest `app/views` ancestor, else PATH)      |
| `--base-class`   | `Phlex::HTML` | Superclass for generated components                                                           |
| `--phlex`        | `2`           | Target Phlex major version (`2` => `view_template`)                                           |
| `--output`, `-o` | _(in place)_  | Write into this directory instead of next to the source                                       |
| `--dry-run`      | `false`       | Print what would be generated without writing                                                 |
| `--force`        | `false`       | Overwrite existing `.rb` files                                                                |
| `--ruby-ui`      | `true`        | Map basic HTML elements onto RubyUI components (`--no-ruby-ui` for plain Phlex)               |
| `--literal`      | `false`       | Emit [Literal](https://literal.fun) `prop` declarations instead of `initialize`/`attr_reader` |
| `--verbose`      | `false`       | Print the generated source for each file                                                      |

## Ruby API

```ruby
require "ruby_ui_converter"

# Convert a directory (returns Converter::Result structs)
RubyUIConverter.convert("app/views/users", force: true)

# Convert a single ERB string (no file IO)
RubyUIConverter.convert_string('<h1><%= @title %></h1>', class_name: "Page")
# =>
# class Page < Phlex::HTML
#   def view_template
#     h1 { @title }
#   end
# end
```

## What gets converted

| ERB                                       | Generated Ruby                                      |
| ----------------------------------------- | --------------------------------------------------- |
| `<div class="box">hi</div>`               | `div(class: "box") { "hi" }`                        |
| `<%= user.name %>`                        | `plain(user.name)` (escaped)                        |
| `<%== markup %>`                          | `raw(safe(markup))` (Phlex 1: `unsafe_raw(markup)`) |
| `<p class="a <%= b %>">`                  | `p(class: "a #{b}")`                                |
| `<p class="<%= css %>">`                  | `p(class: css)`                                     |
| `<% if x %>…<% else %>…<% end %>`         | real `if / else / end`                              |
| `<% items.each do \|i\| %>…<% end %>`     | `items.each do \|i\| … end`                         |
| `<%= link_to "Home", path, class: "x" %>` | `Link(href: path, class: "x") { "Home" }`           |
| `<%= link_to "Show", user %>`             | `Link(href: url_for(user)) { "Show" }`              |
| `id="<%= dom_id user %>"`                 | `id: (dom_id user)`                                 |
| `<%= image_tag "logo.png", alt: "L" %>`   | `img(src: "logo.png", alt: "L")`                    |
| `<%= render "shared/header" %>`           | `render Views::Shared::Header.new`                  |
| `<%= render "form", user: @user %>`       | `render Views::Users::Form.new(user: @user)`        |
| `data-id="<%= id %>"`                     | `"data-id": id`                                     |
| `<%# comment %>`                          | `# comment`                                         |

Top-level views get an initializer built from the controller instance variables
they reference (`@products` → `def initialize(products: nil); @products = products; end`),
so the component can be rendered with `render Views::Products::Index.new(products: ...)`.

Partials additionally get an initializer and private readers for detected
locals:

```ruby
class User < Phlex::HTML
  def initialize(user: nil)
    @user = user
  end

  def view_template
    li(class: "user", "data-id": user.id) { ... }
  end

  private

  attr_reader :user
end
```

### `--literal`: Literal::Properties instead of initialize

With `--literal`, partials declare [Literal](https://literal.fun) props instead
of the initializer boilerplate, and the body references locals as instance
variables (props always set `@ivar`s; no readers are generated):

```ruby
class User < Phlex::HTML
  prop :user, _Nilable(User)

  def view_template
    li(class: "user", "data-id": @user.id) { ... }
  end
end
```

The local matching the partial's name gets an inferred model type
(`_user.html.erb` → `_Nilable(User)` — adjust if the constant doesn't exist);
other locals get the permissive `_Any?` (accepts anything, including nil).
Nilable types make the keyword argument optional automatically. Top-level views
likewise get a `prop` for each controller ivar they reference, all typed
`_Any?` (the partial-name model inference doesn't apply to them).

Requirements: `bundle add literal` and `extend Literal::Properties` on your
base component class:

```ruby
# app/components/base.rb
class Components::Base < Phlex::HTML
  extend Literal::Properties
  # ...
end
```

## Migrating a Rails ERB app

`ruby_ui_converter` only **generates** the component source — running it
requires [Phlex](https://www.phlex.fun) in your app. For a typical Rails app
the migration looks like this:

### 1. Install phlex-rails and RubyUI

```bash
bundle add phlex-rails
bin/rails generate phlex:install
```

The generator creates `Views::Base` / `Components::Base` and registers
`app/views` and `app/components` in the Rails autoloader under the `Views` /
`Components` namespaces — that's what makes `render Views::Users::Index.new`
work from a controller.

The converter maps basic elements onto [RubyUI](https://rubyui.com) components
by default (see [RubyUI element mapping](#rubyui-element-mapping)), so install
RubyUI and generate the components your views will use:

```bash
bundle add ruby_ui
bin/rails generate ruby_ui:install

# ruby_ui:component takes one component per invocation — loop over the list
for c in Button Link Input; do bin/rails generate ruby_ui:component "$c"; done
```

(`ruby_ui:install` also wires `include RubyUI` into `Components::Base`, which
is what enables the kit-style `Link(...)` / `Button(...)` calls.)

If you'd rather stay on plain Phlex, skip this and convert with `--no-ruby-ui`.

### 2. Convert

Zeitwerk expects `app/views/users/index.rb` to define `Views::Users::Index` —
and the converter guarantees that automatically: whenever the converted path is
inside an `app/views` directory, namespaces are derived **relative to
`app/views`**, no matter which subfolder (or single file) you point it at:

```bash
# whole tree or a single folder — both produce Views::Users::Index etc.
bundle exec ruby_ui_converter convert app/views --base-class "Views::Base"
bundle exec ruby_ui_converter convert app/views/users --base-class "Views::Base"
```

(Outside an `app/views` tree, namespaces are relative to the converted folder;
pass `--root DIR` to set the anchor explicitly.)

Use `--base-class "Views::Base"` so the generated classes inherit the helpers
configured in the next step.

### 3. Include the Rails helpers your views use

Generated components call view helpers (`content_for`, `button_to`, `dom_id`,
`notice`, route helpers, ...) that are not available in plain Phlex. Include the
phlex-rails adapters once in `Components::Base` — and keep the `include RubyUI`
that `ruby_ui:install` added, it's what enables the `Link(...)` / `Button(...)`
kit calls:

```ruby
# app/components/base.rb
class Components::Base < Phlex::HTML
  include RubyUI

  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::ButtonTo
  include Phlex::Rails::Helpers::DOMID
  include Phlex::Rails::Helpers::Notice    # scaffold views render `notice`
  include Phlex::Rails::Helpers::FormWith  # `_form` partials use `form_with`
end
```

Each bare helper a converted view calls (`notice`, `form_with`, `current_user`,
...) needs a matching `Phlex::Rails::Helpers::*` module included here, or it
raises `NoMethodError` / `undefined local variable or method '...'` at render
time. phlex-rails' error message names the exact module to add.

### 4. Pass data explicitly from controllers

Controller instance variables are **not** shared with Phlex components. The
converter generates an initializer for each top-level view from the controller
ivars it references (and for partials from their detected locals), so all you
have to do is render the component and pass the data from the action:

```ruby
# app/views/users/index.rb  (generated)
class Views::Users::Index < Views::Base
  def initialize(users: nil)
    @users = users
  end
  # ...
end

# app/controllers/users_controller.rb
def index
  render Views::Users::Index.new(users: User.all)
end
```

The generated keyword arguments default to `nil` — tighten them to required
where it helps. Bare view helpers (`notice`, `current_user`, ...) are not
ivars, so they are not added as arguments; pass them in explicitly or include
the matching helper on your base class.

Converted partials are plain components too — render them from other
components, passing the detected locals as keyword arguments:

```ruby
# app/views/users/_user.html.erb  ->  Views::Users::User
render Views::Users::User.new(user: user)
```

If you converted with `--literal`, the converter emits `prop` declarations
instead of an initializer — a `prop` for each controller ivar a top-level view
references (requires `extend Literal::Properties` on the base class — see
[`--literal`](#--literal-literalproperties-instead-of-initialize)):

```ruby
# app/views/users/index.rb  (generated)
class Views::Users::Index < Views::Base
  prop :users, _Any?
  # ...
end
```

Review the generated props and tighten the permissive `_Any?` types where you
can.

### 5. Review the output

Run with `--dry-run` first, convert incrementally (one folder at a time), and
review each file — see [Design & limitations](#design--limitations) for what
needs manual attention (e.g. `form_with` blocks and inline `<script>` /
`<style>` content). The original `.erb` files are never modified, so actions you haven't
migrated keep rendering through ERB.

Every RubyUI component the converted code references must exist in
`app/components/ruby_ui/` — if a converted view uses a `<table>`, generate it
too (`bin/rails generate ruby_ui:component Table`), otherwise rendering raises
`NameError`. The full list of components the mapping can emit is in
[RubyUI element mapping](#rubyui-element-mapping).

## RubyUI element mapping

By default the converter maps basic HTML elements onto
[RubyUI](https://rubyui.com) kit components (disable with `--no-ruby-ui` /
`ruby_ui: false` to get plain Phlex elements):

| HTML                                               | RubyUI                                                                                                          |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `<a href="...">`                                   | `Link(href: ...) { ... }` (without `href` stays `a`)                                                            |
| `<button>`                                         | `Button(...) { ... }`                                                                                           |
| `<input>`                                          | `Input(...)`                                                                                                    |
| `<input type="checkbox">`                          | `Checkbox(...)`                                                                                                 |
| `<input type="radio">`                             | `RadioButton(...)`                                                                                              |
| `<textarea>`                                       | `Textarea(...) { ... }`                                                                                         |
| `<select>` / `<option>`                            | `NativeSelect(...)` / `NativeSelectOption(...)`                                                                 |
| `<table>` and friends                              | `Table` / `TableHeader` / `TableBody` / `TableFooter` / `TableRow` / `TableHead` / `TableCell` / `TableCaption` |
| `<hr>`                                             | `Separator(...)`                                                                                                |
| `class="badge"` / `class="card"`                   | `Badge(...)` / `Card(...)`                                                                                      |
| `<p id="notice">` / `<p id="alert">` (Rails flash) | `Alert(variant: :success) { ... }` (notice) / `Alert(variant: :destructive) { ... }` (alert, error)             |
| `<%= link_to "X", target %>`                       | `Link(href: target) { "X" }`                                                                                    |

The original attributes (including `class`) are passed through — RubyUI merges
them with each component's defaults via `tailwind_merge`. No `variant:`/`size:`
inference is attempted; review and add them where you want them.

For the generated code to run, the app needs the corresponding RubyUI
components generated and the kit included (see
[Migrating a Rails ERB app](#migrating-a-rails-erb-app)):

```bash
# ruby_ui:component takes one component per invocation — loop over the list
for c in Button Link Input Checkbox RadioButton Textarea NativeSelect Table Separator Badge Card Alert; do
  bin/rails generate ruby_ui:component "$c"
done
```

### Custom rules

To map specific markup onto other RubyUI (or your own) components, register
rules on the configuration — user rules always take precedence over the
built-in mapping:

```ruby
config = RubyUIConverter::Configuration.new

config.component_map.register(
  ->(el) { el.name == "button" && el.static_classes.include?("danger") }
) do |el, transformer, builder|
  transformer.kit_component("Button", el, builder, extra: "variant: :destructive")
end

RubyUIConverter::Converter.new("app/views", config: config).run
```

Emitters can use the transformer's public helpers: `kit_component` (kit-style
calls like `Button(...) { ... }`), `wrap_component` (render-style
`render Const.new(...)`), `component_block` (a nested content component with no
attributes, like `AlertDescription { ... }`), `emit_children`, `render_attrs`
and `meaningful`.

## Form-builder mapping

Inside a `form_with` / `form_for` block, Rails form-builder field calls
(`form.text_field`, ...) aren't HTML elements, so the element mapping above
doesn't see them. When `ruby_ui` is on **and** the form is model-bound, the
converter instead translates them into RubyUI form components, reconstructing
`name`/`id` as `"model[attr]"` and `value` as `model.attr`:

| ERB (inside `form_with model: product`)                                | Generated Ruby                                                                                                |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `<%= form.text_field :name %>`                                         | `Input(name: "product[name]", id: "product[name]", value: product.name.to_s)`                                 |
| `<%= form.email_field :email %>`                                       | `Input(type: "email", name: "product[email]", ...)`                                                           |
| `<%= form.number_field :qty %>`                                        | `Input(type: "number", ...)` (also `date`/`datetime`/`time`/`color`/...)                                      |
| `<%= form.textarea :bio %>`                                            | `Textarea(name: "product[bio]", id: "product[bio]") { product.bio }`                                          |
| `<%= form.checkbox :active %>`                                         | `Checkbox(value: "1", name: "product[active]", id: "product[active]", checked: product.active?)`              |
| `<%= form.label :published_on %>`                                      | `FormFieldLabel(for: "product[published_on]") { "Published on" }`                                             |
| `<%= form.collection_select :category_id, Category.all, :id, :name %>` | `NativeSelect(...)` wrapping a `Category.all.each { ... NativeSelectOption(value:, selected:) { ... } }` loop |
| `<%= form.submit %>`                                                   | `Button(type: "submit") { "Save" }`                                                                           |

Each input/textarea/checkbox is followed by a `FormFieldError` that surfaces the
attribute's backend (model) errors, mirroring the RubyUI form convention:

```ruby
Input(name: "product[name]", id: "product[name]", value: product.name.to_s)
FormFieldError { product.errors[:name].to_sentence.upcase_first }
```

The `value` is emitted as `model.attr.to_s` because HTML attribute values are
strings — Phlex rejects non-string/number columns (e.g. a `decimal`/BigDecimal
`price`) otherwise.

> [!NOTE]
> A select only appears if the ERB actually uses `collection_select`. Rails
> scaffolds a `belongs_to`/`references` column as a plain `form.text_field
:category_id`, which maps to an `Input` — **not** a `NativeSelect`. To get the
> select, swap the `text_field` for `collection_select` in the ERB _before_
> converting. The converter only translates what the template contains; it never
> infers an association select on its own.

Extra options (`class:`, `required:`, ...) are passed through. The block's
`|form|` variable is dropped when every `form.*` call is mapped, and kept when
an unmapped one (e.g. `form.hidden_field`) remains. This needs the `Form`
component family generated (`bin/rails generate ruby_ui:component Form`) for
`FormFieldLabel` / `FormFieldError`.

Caveats worth reviewing (heuristic, model binding is reconstructed by hand):

- `Checkbox` drops the hidden field Rails' `check_box` emits, so an unchecked
  boolean no longer submits `"0"` — add it back if you rely on it.
- `name`/`id` use the bracketed `"model[attr]"` form; `form.submit`'s
  auto-generated "Create/Update" label becomes a `"Save"` placeholder.
- With `--no-ruby-ui` (or a form without a determinable model) the calls are
  left as `form.text_field :name` and the `|form|` variable is kept.

## Design & limitations

The converter is a pure-Ruby pipeline with **no native dependencies**:

```
ERB ─▶ Lexer ─▶ HtmlTokenizer ─▶ Parser ─▶ Transformer ─▶ Ruby/Phlex
       (tokens)   (html tokens)  (AST)      (CodeBuilder)
```

It covers the common cases well, but it is a heuristic source-to-source tool —
**review the output**. Known limitations:

- Locals detection for partials is heuristic; add/remove keyword args as needed.
- `form_with` / `form_for` field helpers map to RubyUI form components (see
  [Form-builder mapping](#form-builder-mapping)) — review the reconstructed
  bindings (notably checkboxes). Other `<%= ... do %>` block helpers are emitted
  as blocks but may need manual adjustment for phlex-rails idioms.
- `render @collection` / object forms are emitted as a bare `render ...` call;
  phlex-rails' `#render` handles model objects and relations.
- Inline `<script>` / `<style>` content is wrapped in a raw call
  (`raw(safe(...))` on Phlex 2, `unsafe_raw(...)` on Phlex 1) with a TODO.
- Custom elements (e.g. `<my-widget>`) are emitted as method calls and may need
  a Phlex-compatible registration.

Generated files are checked for valid Ruby syntax by the test suite, but
semantic equivalence is your responsibility to verify.

## Development

```bash
bin/setup        # bundle install
bundle exec rake test
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
