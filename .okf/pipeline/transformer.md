---
type: Component
title: Transformer
description: Walks the AST and writes Phlex method calls into a CodeBuilder; its public helpers form the emitter API for ComponentMap rules.
tags: [architecture, extension-api]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: transformer
    title: lib/ruby_ui_converter/transformer.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/transformer.rb
  - id: changelog
    title: CHANGELOG
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Overview

Before emitting a plain element, the Transformer asks `config.component_map.lookup(node)`; a matching [ComponentMap](/mapping/component-map.md) rule's emitter takes over.[^transformer] ERB outputs are routed through [Rails helper translation](/mapping/rails-helpers.md) and, inside model-bound forms, the [form-builder mapping](/mapping/form-builder-mapping.md) (`@form_stack`, `special_output?`).

# Emitter API (public, used by custom rules)

| Helper | Purpose |
|--------|---------|
| `kit_component` | Phlex::Kit-style call `Link(href: x) { … }`, always parenthesized; `void: true` for Input-like components |
| `wrap_component` | render-style `render Const.new(...)` |
| `component_block` | nested content component with no attributes (`AlertDescription { … }`) |
| `emit_children`, `render_attrs`, `meaningful` | building blocks |

# Non-obvious behaviours

- `meaningful` drops whitespace-only text **except** a same-line space between two siblings (`inline_space?`), emitted as Phlex `whitespace` (fixed in 0.2.0).[^changelog]
- `bare_expression` parenthesizes an attribute expression only if it contains whitespace and is not `self_delimited?` (bracket literals, parenthesized calls) — e.g. `id: (dom_id user)` but `id: dom_id(user, :row)`.
- All emitted Ruby funnels through `sanitize_code`, which is where [Literal mode](/output/literal-mode.md) rewrites locals to ivars.
- `escape_inner` writes invisible characters as `\u` escapes (see [entity decoding](/pipeline/html-entity-decoding.md)).
