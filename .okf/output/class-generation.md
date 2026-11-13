---
type: Component
title: Class generation
description: Template, Naming and Converter turn each template path into one Phlex class file, anchored at app/views, never overwriting by default.
tags: [rails, phlex-rails]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: template
    title: lib/ruby_ui_converter/template.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/template.rb
  - id: converter
    title: lib/ruby_ui_converter/converter.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/converter.rb
  - id: changelog
    title: CHANGELOG
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Overview

`Template` derives class name and module nesting from the path (`naming.rb`), parses, and renders the class: frozen-string header, modules, initializer (see [locals detection](/output/locals-detection.md)), and `view_template` (`template` on Phlex 1).[^template] `_user.html.erb` → `Views::Users::User`.

# Namespace anchoring (decision)

`Converter#root` anchors at the **nearest `app/views` ancestor**, so `convert app/views/users` or a single file still yields `Views::Users::*` — matching Zeitwerk/phlex-rails autoloading regardless of which subfolder was converted. Outside `app/views` it falls back to the converted folder; `--root`/`config.root` overrides both. `--output` mirroring follows the same root.[^changelog]

# Write rules

- Results are `Converter::Result` with `status` `:written/:previewed/:skipped/:error`.[^converter]
- Existing `.rb` files are never overwritten without `force`.
- Two templates mapping to the same output in one run (`show.html.erb` + `show.html.haml`, or `+variant`s) → the later one is an `:error`, checked before rendering. Before 0.2.0 this silently skipped/overwrote.[^changelog]
