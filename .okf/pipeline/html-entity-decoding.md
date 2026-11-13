---
type: Decision
title: HTML entity decoding
description: Character references in text and literal attribute values are decoded before emitting, because Phlex escapes all output.
tags: [parsing, phlex-rails]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: changelog
    title: CHANGELOG 0.2.0 — Fixed
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
  - id: entities
    title: lib/ruby_ui_converter/html_entities.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/html_entities.rb
---

# Decision

`Parser` decodes HTML character references (`HtmlEntities.decode`: the HTML 4 named set plus numeric `&#…;`/`&#x…;`) in Text nodes and in the literal parts of attribute values.[^entities] Unknown names are left as written.

# Why

Phlex escapes everything it outputs. Before 0.2.0, `&copy;` was emitted verbatim and Phlex re-escaped it, so the page showed the literal text "&copy;".[^changelog] Text must therefore reach the [Transformer](/pipeline/transformer.md) already decoded.

# Exemptions

- `<script>`/`<style>` RawText is **never** decoded (it is emitted via the raw call, see [Configuration](/tooling/configuration.md)).
- HAML's `:escaped` filter builds Text directly and is deliberately not decoded; other HAML text gets decoding for free because it goes through the ERB Parser (see [HAML front-end](/pipeline/haml-front-end.md)).
- Invisible characters (e.g. a decoded `&nbsp;`) are written as `\u` escapes by `Transformer#escape_inner` so the generated source stays readable.
