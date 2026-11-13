---
type: Gem
title: ruby_ui_converter
description: Heuristic source-to-source converter from Rails .erb/.haml views and partials to Phlex/RubyUI component classes.
resource: https://github.com/jacksonpires/ruby_ui_converter
tags: [architecture]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: readme
    title: README
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md
  - id: changelog
    title: CHANGELOG
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CHANGELOG.md
  - id: gemspec
    title: Gemspec
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/ruby_ui_converter.gemspec
---

# Overview

`ruby_ui_converter` turns a Rails views tree into Phlex classes: `app/views/users/index.html.erb` → `app/views/users/index.rb` defining `Views::Users::Index`. Partials become their own classes with their locals as keyword arguments; top-level views get an initializer built from the controller `@ivars` they read.[^readme] Current version is 0.2.0 (2026-11-13), which added HAML support.[^changelog]

It is deliberately **heuristic**: the goal is a strong first draft that is always valid Ruby, not a semantically proven translation — reviewing the output is part of the contract (see [testing conventions](/practices/testing-conventions.md)).

# Shape

- **Runtime deps:** only `thor`; no native extensions. `haml` is optional and loaded lazily.[^gemspec]
- **Ruby:** ≥ 3.0 for the converter; the *generated* code targets phlex-rails 2.x / ruby_ui 1.x (Ruby ≥ 3.2, Rails 7.1–8.x) — see [compatibility](/tooling/compatibility.md).
- **Default output:** RubyUI kit calls (`Link`, `Button`, `Table…`), opt out with `--no-ruby-ui` — see [RubyUI element mapping](/mapping/rubyui-element-mapping.md).

# Where to go next

- How conversion works end to end: [conversion pipeline](/pipeline/conversion-pipeline.md).
- How output classes are shaped: [output](/output/).
- How a user runs it and what it checks after: [CLI](/tooling/cli.md), [Doctor](/tooling/doctor.md).
