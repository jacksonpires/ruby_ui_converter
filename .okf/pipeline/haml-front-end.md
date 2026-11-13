---
type: Component
title: HAML front-end
description: HamlParser walks the haml gem's ParseNode tree and emits the AST the equivalent ERB would produce; haml is an optional, lazily loaded dependency.
tags: [haml, parsing, optional-dependency]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: haml-parser
    title: lib/ruby_ui_converter/haml_parser.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/haml_parser.rb
  - id: readme-haml
    title: README — HAML templates
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#haml-templates
---

# Overview

`HamlParser` calls `Haml::Parser.new(escape_html: true).call(src)` — the tree shape is the same on haml 5.2, 6 and 7 — and converts each node into the shared [AST](/pipeline/ast-nodes.md).[^haml-parser] It follows the pipeline's rule of [converging on the ERB AST](/pipeline/conversion-pipeline.md).

# Optional dependency

Never `require "haml"` at load time. `HamlParser.load_haml!` requires it lazily through a `require_haml` seam (stubbed in tests) and raises `Error` with `MISSING_HAML`, which the [CLI](/tooling/cli.md) reports once; `.erb` files still convert.

# Facts about the haml parse tree the code relies on

| Fact | Handling |
|------|----------|
| `escape_html: true` is what distinguishes `=` from `!=` | `!=` → raw output |
| `else`/`elsif`/`when` arrive *flattened among the children* of their `if`/`case` | `control` splits them into Branches |
| Script text has a leading space | stripped |
| Interpolated text arrives as a dumped Ruby string literal — flagged `escape_interpolation` on haml 6/7, recognizable on haml 5/6 only by escape wrappers around each `#{}` | `ESCAPE_WRAPPER` + `unwrap_escape`, then `RubyLiteral` (below) |

# Text goes through the ERB parser

Plain lines, inline tag text and `:plain` are rewritten as an ERB snippet (`#{x}` → `<%= x %>`) and parsed by the ERB Parser (`text_nodes`). That way inline HTML becomes elements, `#{link_to …}` becomes a [Link](/mapping/rails-helpers.md), locals inside interpolation are seen by [locals detection](/output/locals-detection.md), and [entity decoding](/pipeline/html-entity-decoding.md) applies.

# Whitespace

`convert_children` pads text next to rendered siblings with a space (HAML's newline), skipping silent nodes and `%tag>`. This is an approximation; known gaps are listed in the README.[^readme-haml]

# Ruby literals

`ruby_literal.rb` (`RubyLiteral.string_parts`) splits one Ruby string literal into `[:text]`/`[:code]` parts using Ripper, decoding escapes with `String#undump` (raw non-ASCII is `\u`-escaped first because undump rejects it). It has no haml dependency.

# Unsupported

`/[if IE]` conditional comments and unknown filters (`:markdown`, `:scss`, …) become `# TODO` comments. Attributes are covered separately in [HAML attribute merging](/pipeline/haml-attributes.md).
