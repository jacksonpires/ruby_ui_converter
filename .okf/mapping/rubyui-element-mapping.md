---
type: Decision
title: RubyUI element mapping on by default
description: Basic HTML elements map to RubyUI kit components by default (ruby_ui true); --no-ruby-ui emits plain Phlex.
tags: [ruby-ui, defaults]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: readme-map
    title: README — RubyUI element mapping
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#rubyui-element-mapping
  - id: changelog
    title: CHANGELOG 0.1.0
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Decision

Since 0.1.0 the mapping is **enabled by default** and replaced the old opt-in `--starter-rules`.[^changelog] Built-ins are installed as [fallback rules](/mapping/component-map.md), so custom rules still win.

| HTML | RubyUI |
|------|--------|
| `a[href]` | `Link(href: …)` (no `href` → stays `a`) |
| `button` | `Button` |
| `input` / checkbox / radio | `Input` / `Checkbox` / `RadioButton` |
| `textarea`, `select`/`option` | `Textarea`, `NativeSelect`/`NativeSelectOption` |
| `table` family | `Table`, `TableHeader`, `TableBody`, `TableRow`, `TableHead`, `TableCell`, … |
| `hr` | `Separator` |
| static `class="badge"` / `"card"` | `Badge` / `Card` |
| `<p id="notice">` / `<p id="alert">` | `Alert(variant: :success)` / `Alert(variant: :destructive)` with title + description |

[^readme-map]

# Tradeoffs

- Original attributes (incl. `class`) pass through; RubyUI merges them via `tailwind_merge`. **No `variant:`/`size:` inference** is attempted — deliberate, to avoid guessing design intent.
- The app must have each RubyUI component generated; [Doctor](/tooling/doctor.md) detects which are missing.
- `link_to` → `Link` is done separately in [Rails helper translation](/mapping/rails-helpers.md), gated on `config.ruby_ui?`.
- `ruby_ui: true` installs rules **in the Configuration constructor** — setting `config.ruby_ui = true` later does nothing (see [Configuration](/tooling/configuration.md)).
