---
type: Playbook
title: Rails end-to-end check
description: script/rails_e2e/run.sh creates a fresh Rails app, scaffolds ERB and HAML resources, converts them and renders the generated classes in an integration test.
resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/script/rails_e2e/run.sh
tags: [ci, rails, haml]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
---

# What it does

`script/rails_e2e/run.sh <rails-series> [tmpdir]` (needs network):

1. `rails new` on the latest patch of the series;
2. scaffolds `Product` with every common column type (ERB) and `Supplier` with haml-rails (`--template-engine=haml`, because tailwindcss-rails registers its own engine);
3. converts both, patches the app (`patch_app.rb`), and runs `converted_views_test.rb` rendering index/show/new/edit, validation errors and create through the generated classes — with **eager loading on**, to catch issues like the prism pin in [compatibility](/tooling/compatibility.md).

CI runs it for every Rails 7.1–8.1 × Ruby 3.2–4.0 cell, after unit tests pass.

It is the only check of **runtime** behaviour; the unit suite only checks syntax (see [testing conventions](/practices/testing-conventions.md)).
