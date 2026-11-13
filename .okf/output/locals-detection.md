---
type: Component
title: Locals detection
description: Heuristic detection of a partial's locals and a view's controller ivars, which become the generated initializer's keyword arguments.
tags: [needs-review]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: ld
    title: lib/ruby_ui_converter/locals_detector.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/locals_detector.rb
  - id: changelog
    title: CHANGELOG 0.1.0
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Overview

`LocalsDetector` scans the ERB code in the AST.[^ld]

- **`#locals`** (partials): `local_assigns[:x]` / `local_assigns.fetch(:x)` plus bare identifiers that look like locals. Excludes Ruby keywords, anything **assigned** or used as a **block param** anywhere in the template, and the helper names from [Rails helper translation](/mapping/rails-helpers.md#hidden-coupling). Output: `initialize(user: nil)` + private `attr_reader`s.
- **`#ivars`** (top-level views): `@ivars` read but not assigned in the template, excluding class variables. Output: an initializer that assigns them directly, no readers — so controllers can `render Views::Products::Index.new(products: @products)`.[^changelog]

`Template#init_args` unifies both into one keyword list.

# The invariant that matters

Only **read-only** names are reported. That invariant is what makes the blanket rewrite in [Literal mode](/output/literal-mode.md) safe — weakening the exclusions would break it.

# History of false positives

`render`, `dom_id`, `dom_class`, `notice`, `alert`, `content_for`, `cycle` were once detected as locals and are now excluded.[^changelog] Expect more of this class; fix by extending the exclusion lists.
