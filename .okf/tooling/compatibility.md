---
type: Reference
title: Compatibility
description: Converter runs on Ruby 3.0–4.0 with haml 5.2/6/7; generated code needs phlex-rails 2.x/ruby_ui 1.x on Ruby ≥ 3.2 and Rails 7.1–8.1, with known pins.
tags: [ci, rails, haml]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: readme-compat
    title: README — Compatibility
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#compatibility
  - id: ci
    title: CI workflow
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/.github/workflows/ci.yml
---

# Two layers

| Layer | Requirement |
|-------|-------------|
| Converter | Ruby 3.0–4.0 (+ `ruby-head`, allowed to fail); haml 5.2/6.x/7.x |
| Generated code | phlex-rails 2.x / ruby_ui 1.x → Ruby ≥ 3.2, Rails ≥ 7.1, < 9 |

haml 7 needs Ruby ≥ 3.2; with no committed lockfile constraint, CI resolves haml 6 on 3.0/3.1 and haml 7 on 3.2+, covering both interpolation shapes the [HAML front-end](/pipeline/haml-front-end.md) handles.[^ci] Last verified with Ruby 4.0.9, Rails 8.1.4.1, phlex-rails 2.4.0, ruby_ui 1.6.0.[^readme-compat]

# Known pins in target apps

- `gem "prism", "< 2"` — `refract` 1.1.0 (phlex 2.4 dep) references `Prism::MissingNode`, removed in prism 2.x; crashes only on **eager load** (production / `CI`), so dev looks fine.[^readme-compat]
- Rails 7.1/7.2/8.0: `gem "json", "< 3"` and `gem "minitest", "< 6"` — unrelated to the converter.

The [Rails end-to-end check](/tooling/rails-e2e-check.md) applies the same pins.
