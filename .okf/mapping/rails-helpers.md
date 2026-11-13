---
type: Component
title: Rails helper translation
description: Translates link_to, image_tag, render and other Rails view helpers into Phlex equivalents; unmapped helpers become bare calls.
tags: [rails, phlex-rails]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: helpers
    title: lib/ruby_ui_converter/rails_helpers.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/rails_helpers.rb
  - id: changelog
    title: CHANGELOG 0.1.0
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Overview

- `render "partial"` resolves to a constant via `Naming.partial_const` (see [class generation](/output/class-generation.md)).
- `link_to` → `Link(href: …)` when RubyUI is on; targets that are neither strings nor route helpers (`link_to "Show", user`) are wrapped in `url_for(...)`.[^changelog]
- `render @collection` / object forms stay a **bare** `render ...` — phlex-rails' `render` handles models and relations.

# Bare calls vs raw wrapping

phlex-rails registers Rails HTML helpers as *output helpers* that write to the buffer themselves, so unmapped helpers are emitted as bare calls. Only the string-returning helpers in `STRING_HELPERS` (`sanitize`, `safe_join`, `raw`, `strip_tags`) are wrapped in `config.raw_call`.[^helpers] Wrapping an output helper would double-render; leaving a string helper bare would render nothing.

# Hidden coupling

`HTML_HELPERS`/`KNOWN_HELPERS` also serve as the exclusion list of [locals detection](/output/locals-detection.md). Adding a helper name here **changes which partial locals are detected**.
