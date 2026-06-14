# Changelog

## [0.1.0] - Unreleased

- RubyUI element mapping **enabled by default**: basic HTML elements are
  converted to RubyUI kit components — `a[href]` → `Link`, `button` → `Button`,
  `input` → `Input`/`Checkbox`/`RadioButton`, `textarea` → `Textarea`,
  `select`/`option` → `NativeSelect`/`NativeSelectOption`, the `table` family,
  `hr` → `Separator`, plus class-based `Badge`/`Card`; `link_to` becomes
  `Link(href: ...)`. Disable with `--no-ruby-ui` / `ruby_ui: false`.
- New `Transformer#kit_component` helper for kit-style component emission;
  built-in rules are fallbacks, so custom `component_map.register` rules
  always take precedence.
- Removed `--starter-rules` / `enable_starter_rubyui_rules!` (replaced by the
  default mapping above and `enable_rubyui_rules!`).
- Fix: `--output` now creates missing directories in the output tree.
- New `--literal` flag (`literal: true`): partials declare
  `Literal::Properties` props (`prop :user, _Nilable(User)`) instead of
  `initialize`/`attr_reader`, and the template body references locals as
  `@ivar`s (rewritten safely via Ripper token-level pass). The local matching
  the partial name gets an inferred model type; others get `_Any?`.
- Fix: `LocalsDetector` no longer treats `render` as a partial local.
- Namespaces are now anchored at the nearest `app/views` ancestor: converting
  `app/views/users` (or a single file inside it) generates `Views::Users::*`,
  matching the Zeitwerk/phlex-rails layout regardless of which subfolder was
  converted. `--output` mirroring follows the same root. Outside an `app/views`
  tree the previous relative behavior is kept; `--root DIR` sets the anchor
  explicitly (passing the converted folder itself restores the old behavior).
- Prerequisite check after each CLI run (`Doctor`): detects missing
  `phlex-rails`/`ruby_ui`/`literal` gems, ungenerated RubyUI components
  referenced by the converted code, and a missing `extend Literal::Properties`,
  then offers to install them (prompt; warn-only on `--dry-run`/non-TTY).
  After installing, a follow-up diagnosis fixes problems that only appear
  post-install — notably the broken `tw-animate-css` import that
  `ruby_ui:install` leaves on importmap apps (the jspm pin fails for this
  CSS-only package): the real CSS is vendored next to `application.css` and
  the import is rewritten.

- Fix: whole-value ERB attribute expressions with unparenthesized arguments
  (e.g. `id="<%= dom_id user %>"`) are now wrapped in parens so they parse
  correctly inside the attribute list.
- Fix: `link_to` targets that are not strings or route helpers (e.g.
  `link_to "Show", user`) are now wrapped in `url_for(...)`.
- Fix: `LocalsDetector` no longer treats common Rails helpers (`dom_id`,
  `dom_class`, `notice`, `alert`, `content_for`, `cycle`) as partial locals.

- Initial release.
- Recursive conversion of `.erb` views into Phlex/RubyUI `.rb` components.
- Conversion of Rails partials (`_partial.html.erb`) into dedicated Phlex component classes.
- Pure-Ruby ERB + HTML lexer/parser (no native dependencies).
- Best-effort mapping of common Rails helpers (`render`, `link_to`, `image_tag`, `content_tag`, `yield`).
- Configurable, conservative RubyUI component mapping via `ComponentMap`.
- `ruby_ui_converter convert PATH` CLI.
