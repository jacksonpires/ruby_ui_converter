---
type: Component
title: Literal mode
description: With --literal, initializer args become Literal::Properties props and partial bodies reference locals as @ivars via a Ripper token rewrite.
tags: [optional-dependency, needs-review]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: transformer
    title: lib/ruby_ui_converter/transformer.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/transformer.rb
  - id: readme-literal
    title: README — --literal
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#--literal-literalproperties-instead-of-initialize
---

# Overview

`literal: true` emits `prop :user, _Nilable(User)` (the local matching the partial name gets an inferred model type) or `_Any?` instead of `initialize`/`attr_reader`.[^readme-literal] The app's base component needs `extend Literal::Properties` — [Doctor](/tooling/doctor.md) checks it.

# The rewrite

Props are ivars, so bare local references in the body must become `@ivar`s. `Transformer#sanitize_code` runs `rewrite_locals_to_ivars`, a Ripper **token-level** pass (not a regex), so strings, symbols and method calls with the same name aren't touched.[^transformer]

It is a *blanket* rewrite, safe only because [locals detection](/output/locals-detection.md#the-invariant-that-matters) reports read-only names. Top-level views already use `@ivars`, so `literal_locals` is empty and nothing is rewritten for them.
