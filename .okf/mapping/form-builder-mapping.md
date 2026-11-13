---
type: Component
title: Form-builder mapping
description: Inside a model-bound form_with/form_for, form.* field calls become RubyUI form components with name/id/value reconstructed by hand.
tags: [ruby-ui, rails, needs-review]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: fb
    title: lib/ruby_ui_converter/form_builder.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/form_builder.rb
  - id: readme-fb
    title: README — Form-builder mapping
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#form-builder-mapping
  - id: changelog
    title: CHANGELOG 0.2.0
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Overview

Form-builder calls aren't HTML elements, so the [element mapping](/mapping/rubyui-element-mapping.md) can't see them. Active only when `ruby_ui?` **and** a model is determinable; otherwise calls are left as-is.[^fb]

The [Transformer](/pipeline/transformer.md) pushes `{var:, model:, param:}` onto `@form_stack` while emitting the form block (`emit_form_control`, `current_form`) and routes `<%= form.* %>` through `FormBuilder.transform`.

| Call | Output |
|------|--------|
| `text_field` / typed fields | `Input(type:, name: "m[a]", id: "m[a]", value: m.a.to_s)` |
| `textarea` | `Textarea { m.a }` |
| `checkbox` | `Checkbox(value: "1", checked: m.a?)` |
| `label` | `FormFieldLabel(for: "m[a]")` |
| `collection_select` | `NativeSelect` wrapping a `NativeSelectOption` loop |
| `submit` | `Button(type: "submit") { "Save" }` |

Each input/textarea/checkbox is followed by `FormFieldError { m.errors[:a].to_sentence.upcase_first }`.[^readme-fb] The `|form|` block var is dropped only when every call maps.

# Why `.to_s` on values

Phlex rejects attribute values that aren't strings/numbers — a `decimal` (BigDecimal) column crashed rendering. `.to_s` makes every column safe.[^readme-fb]

# Caveats (review the output)

- `Checkbox` drops Rails' hidden `"0"` field — unchecked booleans no longer submit.
- `form.submit`'s Create/Update label becomes `"Save"`.
- A scaffolded `references` column is a `text_field`, so it maps to `Input`, not a select — the converter never infers an association select.
- `form_with model: @x do |form|` without parentheses used to swallow `do |form|` in the model capture; fixed in 0.2.0.[^changelog]
