---
type: Component
title: AST nodes
description: The Nodes AST shared by both front-ends — elements with attribute parts, ERB nodes, and Control/Branch for Ruby control flow.
tags: [architecture, extension-api]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: nodes
    title: lib/ruby_ui_converter/nodes.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/nodes.rb
---

# Overview

`nodes.rb` defines the AST both front-ends build.[^nodes] Two non-obvious modelling choices:

- **Attribute parts.** An attribute value is an array of `[:text, "literal"]` / `[:erb, token]` entries (a consequence of [placeholder lexing](/pipeline/erb-placeholder-lexing.md)). The [Transformer](/pipeline/transformer.md) inspects the parts to emit a plain string, a bare Ruby expression, or an interpolated string.
- **Control flow is structural.** `<% if %>` / `each do` become `Nodes::Control` with `Branch` children, so the output is real Ruby `if/elsif/else/end` and blocks, not strings. HAML's flattened `else`/`when` siblings are reshaped into the same structure.
- `Comment` may carry `children` (HAML `/` with nested content → `comment do … end`).

# Matcher API

`Element#static_attr(name)`, `#static_classes` and `#attr?` are what [ComponentMap](/mapping/component-map.md) rules match on. They return `nil` / `[]` when the value contains ERB, which is why class-based rules (`.card` → `Card`) only fire on fully static classes.
