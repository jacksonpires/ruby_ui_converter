---
type: Component
title: Configuration
description: Single options object threaded through every stage; decides the Phlex template method and raw-output form and installs RubyUI rules at construction.
resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/configuration.rb
tags: [defaults, phlex-rails]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
---

# Overview

Options: `base_namespace` ("Views"), `base_class` ("Phlex::HTML"), `phlex_version` (2), `indent`, `output_root`, `verbose`, `dry_run`, `force`, `ruby_ui` (true), `literal` (false), `root`, `component_map`.

# Phlex version switches

| | Phlex 2 | Phlex 1 |
|-|---------|---------|
| `template_method` | `view_template` | `template` |
| `raw_call(expr)` | `raw(safe(expr))` | `unsafe_raw(expr)` |

Phlex 2 removed `unsafe_raw`; every raw emission (script/style bodies, `!=`, string helpers in [Rails helper translation](/mapping/rails-helpers.md)) must go through `raw_call`.

# Gotcha

`ruby_ui: true` installs the [RubyUI fallback rules](/mapping/rubyui-element-mapping.md) **in the constructor**. `config.ruby_ui = true` after construction does nothing — pass it as a kwarg or call `enable_rubyui_rules!`.
