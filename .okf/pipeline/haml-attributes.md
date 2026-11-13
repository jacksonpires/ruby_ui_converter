---
type: Component
title: HAML attribute merging
description: Converts HAML's several attribute sources into the attribute-parts list while reproducing HAML's class/id/data merge semantics.
tags: [haml, parsing]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: haml-attrs
    title: lib/ruby_ui_converter/haml_attributes.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/haml_attributes.rb
  - id: readme-haml
    title: README — HAML-specific limitations
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#haml-templates
---

# Sources, in order

1. static `attributes` hash (shorthand `.class#id`),
2. `dynamic_attributes.new` (html-style `()`),
3. `dynamic_attributes.old` (`{}` hash — static literal hashes land here too),
4. `object_ref` (`[@obj]` → `dom_id`/`dom_class`).[^haml-attrs]

Hashes are split with `Haml::AttributeParser.parse`; when that returns nil the whole hash becomes a `**(...)` splat.

# Merge rules

| Attribute | Rule |
|-----------|------|
| `class` | all strings → one string; any expression → `[static, expr]` array (Phlex flattens) |
| `id` | joined with `_` |
| others | later source overrides |
| `false`/`nil` | dropped; `true` → boolean attribute |
| symbols | become text |
| literal `data:`/`aria:` hash | expanded to hyphenated keys |

# Known divergences from HAML

`[@obj]` uses Rails' `dom_id` (`new_user` vs HAML's `user_new`); `{id: [a, b]}` joins with a space in Phlex rather than `_`.[^readme-haml] Because class expressions make `static_classes` empty, class-based [RubyUI rules](/mapping/rubyui-element-mapping.md) don't fire on dynamic classes — same as ERB.
