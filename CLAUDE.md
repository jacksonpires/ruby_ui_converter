# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Ruby gem (no native dependencies, only `thor` at runtime) that converts Rails `.erb` views/partials into Phlex/RubyUI component classes. It is a heuristic source-to-source tool: `app/views/users/index.html.erb` → `app/views/users/index.rb` (`Views::Users::Index`). Partials (`_user.html.erb`) become their own classes with detected locals as keyword arguments; top-level views get an initializer built from the controller instance variables they reference. By default, basic HTML elements are mapped onto RubyUI kit components (`a[href]`→`Link(...)`, `button`→`Button(...)`, `input`→`Input(...)`, the table family, etc.); `ruby_ui: false` / `--no-ruby-ui` emits plain Phlex elements instead.

## Commands

```bash
bin/setup                                  # bundle install
bundle exec rake test                      # run all tests (rake default does the same)
bundle exec ruby -Itest test/transformer_test.rb           # run one test file
bundle exec ruby -Itest test/transformer_test.rb -n test_converts_each_blocks  # run one test by name
bundle exec exe/ruby_ui_converter convert PATH --dry-run  # try the CLI locally
```

Release tasks come from `bundler/gem_tasks` (`rake build`, `rake release`).

## Architecture: the conversion pipeline

The whole gem is a single linear pipeline; each stage is one file in `lib/ruby_ui_converter/`:

```
ERB source ─▶ Lexer ─▶ HtmlTokenizer ─▶ Parser ─▶ Transformer ─▶ Ruby/Phlex source
              (ERB tokens +  (html tokens)  (Nodes AST)  (writes into CodeBuilder)
               placeholders)
```

The key trick that makes this work without a real HTML5 parser: **`Lexer` replaces every ERB tag with an alphanumeric placeholder** (`RUCxERBx<n>xERBxRUC`) and keeps a registry of placeholder → `Lexer::Token`. The placeholder uses only word characters, so ERB inside tags and attribute values survives `HtmlTokenizer` as inert text. `Parser` then resolves placeholders back into ERB nodes while building the AST.

Other pieces around the pipeline:

- **`nodes.rb`** — AST node types. Attribute values are stored as "parts" arrays of `[:text, "literal"]` / `[:erb, token]` entries, which is how the Transformer decides between a plain string, a bare Ruby expression, or an interpolated string for an attribute. `<% if %>`/`each do` become `Nodes::Control` with `Branch` children (so output is real Ruby control flow, not strings). `Element#static_attr(name)` / `#static_classes` / `#attr?` are the matcher API for ComponentMap rules (they return nil/[] when the value contains ERB).
- **`transformer.rb`** — walks the AST, emits Phlex method calls. Before emitting a plain element it consults `config.component_map.lookup(node)`; a matching rule's emitter takes over. Its public helpers (`emit_children`, `render_attrs`, `meaningful`, `kit_component`, `wrap_component`, `component_block`) form the API that ComponentMap emitters use. `kit_component` emits Phlex::Kit-style calls (`Link(href: x) { ... }`, always parenthesized; `void: true` for Input-like components).
- **`component_map.rb`** — two-layer registry of `{matcher: ->(Element){bool}, emitter: ->(el, transformer, builder){}}` rules: user rules (`register`) always win over fallback rules (`register_fallback`). `ComponentMap.rubyui_rules` installs the built-in RubyUI element mapping (a→Link, button→Button, input→Input/Checkbox/RadioButton, table family, etc.) as fallbacks — Configuration does this by default (`ruby_ui: true`, CLI `--no-ruby-ui` to disable). `link_to`→`Link` happens separately in `rails_helpers.rb`, gated on `config.ruby_ui?`.
- **`rails_helpers.rb`** — translates `link_to`, `image_tag`, `render "partial"`, etc. into Phlex equivalents; `render` paths resolve to constants via `Naming.partial_const`. `link_to` targets that aren't strings or route helpers get wrapped in `url_for(...)`. Unmapped HTML helpers and object/collection `render` are emitted as **bare calls** — phlex-rails registers these as output helpers that write to the buffer themselves; only the string-returning helpers in `STRING_HELPERS` (`sanitize`, `safe_join`, `raw`, `strip_tags`) are wrapped via `transformer.config.raw_call`. Cross-file coupling to know about: `HTML_HELPERS`/`KNOWN_HELPERS` also serve as the LocalsDetector's exclusion list — adding a helper name there changes partial locals detection.
- **`form_builder.rb`** — translates Rails form-builder field calls (`form.text_field :name`, ...) inside a `form_with`/`form_for` block into RubyUI form components (`Input`/`Textarea`/`Checkbox`/`FormFieldLabel`/`Button`, and `collection_select` into a `NativeSelect` wrapping a `NativeSelectOption` loop), reconstructing `name`/`id` as `"model[attr]"` and `value` as `model.attr.to_s` (`.to_s` because Phlex rejects non-string/number attribute values like a `decimal`/BigDecimal column), and appending a `FormFieldError { model.errors[:attr].to_sentence.upcase_first }` after each input/textarea/checkbox. The Transformer pushes a form scope (`{var:, model:, param:}`) onto `@form_stack` while emitting a model-bound form block (`emit_form_control`, `current_form`), drops the `|form|` block var when every call maps, and routes `<%= form.* %>` outputs through `FormBuilder.transform` (and `special_output?` so they aren't inlined). Only active when `ruby_ui?` and a model is determinable; otherwise calls stay as-is. Heuristic — checkbox loses Rails' hidden field; bindings need review.
- **`locals_detector.rb`** — heuristic detection used by `Template`. `#locals` finds a partial's bare locals (→ initializer + private `attr_reader`s); excludes Ruby keywords plus the `RailsHelpers` constants above. `#ivars` finds the controller `@ivars` a top-level view reads (→ initializer that assigns them directly, no readers); excludes ivars assigned in the template and class variables.
- **`template.rb`** — per-file orchestrator: derives class name/namespace from the path (via `naming.rb`), parses, and renders the full class (frozen-string header, module nesting, initializer, `view_template`). `init_args` unifies the initializer's keyword args: a partial's detected `locals` (referenced via `attr_reader`s) or a top-level view's referenced `ivars` (assigned directly, no readers). With `literal: true`, those same names emit `prop :x, _Nilable(X)/_Any?` (Literal::Properties) instead of initialize/attr_reader.
- **Literal mode rewriting** — all emitted Ruby code funnels through `Transformer#sanitize_code`, which (in literal mode) rewrites bare local references to `@ivar`s via a Ripper token-level pass (`rewrite_locals_to_ivars`). This is safe because LocalsDetector only reports read-only names (anything assigned or used as a block param anywhere in the template is excluded) — that invariant is what makes blanket rewriting correct. Only partials need this: top-level views already reference `@ivars`, so `literal_locals` is empty for them and nothing is rewritten.
- **`converter.rb`** + **`file_walker.rb`** — directory-level orchestration; returns `Converter::Result` structs with `status` of `:written/:previewed/:skipped/:error`. Never overwrites existing `.rb` files unless `force`. `Converter#root` anchors namespace derivation (and `--output` mirroring) at the nearest `app/views` ancestor when present — so `convert app/views/users` still yields `Views::Users::*` — falling back to the converted folder; `config.root` overrides both.
- **`configuration.rb`** — single options object threaded through everything. `phlex_version` decides the template method name (`view_template` for 2, `template` for 1) and the raw-output form via `raw_call` (`raw(safe(...))` for 2, `unsafe_raw(...)` for 1). `ruby_ui: true` (the default) installs the RubyUI fallback rules **in the constructor** — setting `config.ruby_ui = true` after construction does nothing; pass it as a kwarg.
- **`cli.rb`** — Thor CLI (`exe/ruby_ui_converter`); maps flags onto a `Configuration`. After each run it consults `Doctor` and (interactively) offers to install missing prerequisites.
- **`doctor.rb`** — post-conversion diagnostics: walks up from the converted path to the nearest Gemfile (`app_root`), then checks gems (phlex-rails/ruby_ui/literal), `extend Literal::Properties` on the base class, and which RubyUI generator families the emitted code references (`COMPONENT_FAMILIES` maps e.g. `TableCell`→`Table`) vs `app/components/ruby_ui/*`. Pure diagnosis — `Issue` structs carry shell `commands` (strings starting with `#` are manual hints, never executed) and an optional `fixer` proc; the CLI prompts and executes.

Entry points: `RubyUIConverter.convert(path, **opts)` (files) and `RubyUIConverter.convert_string(erb, ...)` (no IO — useful in tests).

## Testing notes

- Tests use **Minitest** (`Minitest::Test`, assert-style) under `test/*_test.rb` with a shared `test/test_helper.rb`; tests assert on generated source strings, and `convert_string` is the easiest harness for transformer behavior.
- **Tests must be self-contained: no `setup`/`teardown`.** A test that needs files creates its own temp dir inline with `Dir.mktmpdir("ruc") do |dir| ... end` (auto-cleaned), and stateless helpers (`write`, `doctor`, ...) take that `dir` as their first argument rather than reading shared instance state.
- The default config maps elements/`link_to` to RubyUI kit calls (`Link(...)`, `Button(...)`) — tests asserting plain Phlex output (`a(...)`, `input(...)`) must pass `ruby_ui: false`.
- The suite checks generated files are valid Ruby syntax (`ruby -c`) — semantic equivalence is explicitly out of scope (the README documents the known limitations: heuristic locals, `form_with` blocks, `render @collection`/object forms emit a bare `render ...` call (phlex-rails handles it), raw `<script>/<style>` content wrapped via `Configuration#raw_call` — `raw(safe(...))` on Phlex 2, `unsafe_raw(...)` on Phlex 1).
- Minitest randomizes test order by default; the `rake test` task runs `test/**/*_test.rb`.
