---
type: Component
title: Doctor
description: Pure post-conversion diagnosis of the target Rails app — gems, Literal setup, ungenerated RubyUI components, and the tw-animate-css import — whose fixes the CLI executes.
resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/doctor.rb
tags: [cli, ruby-ui, rails]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: changelog
    title: CHANGELOG 0.1.0
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
---

# Overview

Walks up from the converted path to the nearest `Gemfile` (`app_root`) and checks:

- gems: `phlex-rails`, `ruby_ui`, `literal` (the last only with [Literal mode](/output/literal-mode.md));
- `extend Literal::Properties` on the base component;
- which RubyUI component families the emitted code references (`COMPONENT_FAMILIES`, e.g. `TableCell` → `Table`) vs `app/components/ruby_ui/*`.

# Design

Doctor is **pure diagnosis**: it returns `Issue` structs with shell `commands` (strings starting with `#` are manual hints, never executed) and an optional `fixer` proc. The [CLI](/tooling/cli.md) prompts and executes. It emits one `bin/rails generate ruby_ui:component <Name>` per missing component because the generator takes a single component per call.[^changelog]

# tw-animate-css

`ruby_ui:install` pins `tw-animate-css` via importmap, but the jspm pin fails for this CSS-only package. After installing, a follow-up diagnosis vendors the real CSS next to `application.css` and rewrites the import.[^changelog] This only appears post-install, hence the second pass.
