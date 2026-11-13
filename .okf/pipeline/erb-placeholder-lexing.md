---
type: Decision
title: ERB placeholder lexing
description: ERB tags are replaced by word-character placeholders so a simple HTML tokenizer can run without a real HTML5 parser.
tags: [erb, parsing]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: lexer
    title: lib/ruby_ui_converter/lexer.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/lexer.rb
---

# Decision

`Lexer` replaces every `<% %>`, `<%= %>`, `<%== %>` and `<%# %>` tag with a placeholder `RUCxERBx<n>xERBxRUC` and keeps a registry placeholder → `Lexer::Token` (`:eval`, `:output` with `raw` for `<%==`, `:comment`).[^lexer] `Parser` resolves placeholders back into ERB nodes while building the [AST](/pipeline/ast-nodes.md).

# Why

ERB legally appears *inside* tags and attribute values (`class="a <%= b %>"`), which breaks naive HTML tokenizing. Because the placeholder uses only `[A-Za-z0-9_]`, the `HtmlTokenizer` sees it as inert text or an identifier, so the source stays well-formed HTML. This is what lets the gem avoid a native HTML5 parser and stay dependency-free.

# Consequences

- Attribute values become mixed "parts" (`[:text, …]` / `[:erb, token]`), which the [Transformer](/pipeline/transformer.md) uses to choose between a string, a bare expression, or an interpolated string.
- The marker string must never appear in real templates; it is intentionally unlikely.
