---
type: Component
title: Conversion pipeline
description: Linear pipeline where an ERB front-end and a HAML front-end both produce the same Nodes AST, consumed by a single Transformer.
tags: [architecture, erb, haml]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: entry
    title: lib/ruby_ui_converter.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter.rb
  - id: readme-design
    title: README — Design & limitations
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#design--limitations
---

# Overview

```
ERB  ─▶ Lexer ─▶ HtmlTokenizer ─▶ Parser ────┐
HAML ─▶ Haml::Parser (haml gem) ─▶ HamlParser ┴─▶ Nodes AST ─▶ Transformer ─▶ Ruby (CodeBuilder)
```

Each stage is one file in `lib/ruby_ui_converter/`.[^readme-design] `RubyUIConverter.parse(source, format:)` is the single dispatch point; `FORMATS` maps extensions to `:erb`/`:haml` and `FileWalker` globs `**/*.{erb,haml}` — the glob must be kept in sync with `FORMATS`.[^entry]

# Design rule: front-ends converge on the AST

Everything after the AST is shared, so a fix in the [Transformer](/pipeline/transformer.md) or the [mapping layer](/mapping/) applies to both formats. Consequently a HAML feature must be expressed **as the AST the equivalent ERB would produce**, never as a Transformer special case — the [HAML front-end](/pipeline/haml-front-end.md) even routes HAML text through the ERB [Parser](/pipeline/erb-placeholder-lexing.md) to get there.

# Entry points

- `RubyUIConverter.convert(path, **opts)` — files/directories, via [Converter](/output/class-generation.md).
- `RubyUIConverter.convert_string(source, format:, ...)` — no IO; the main test harness.
