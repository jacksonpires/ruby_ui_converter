---
type: Playbook
title: Testing conventions
description: Minitest conventions for this gem — no setup/teardown, convert_string as harness, syntax validity as the only automated guarantee.
tags: [testing, ci]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: claude-md
    title: CLAUDE.md — Testing notes
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CLAUDE.md
---

# Rules

- Minitest, assert-style, `test/*_test.rb`; tests assert on generated source strings; `convert_string` is the easiest harness.[^claude-md]
- **Self-contained tests: no `setup`/`teardown`.** File tests use `Dir.mktmpdir("ruc") do |dir| … end`; helpers take `dir` as their first argument.
- Default config emits RubyUI calls — tests asserting plain Phlex must pass `ruby_ui: false` (see [RubyUI mapping](/mapping/rubyui-element-mapping.md)).
- CLI tests must pass `--dry-run` so [Doctor](/tooling/doctor.md) never prompts or installs.
- Order is randomized; `rake test` runs `test/**/*_test.rb`.

# What is (and isn't) guaranteed

The suite checks generated files are valid Ruby (`ruby -c`). **Semantic equivalence is explicitly out of scope** — that is the [Rails end-to-end check](/tooling/rails-e2e-check.md)'s job, and ultimately the user's review.

# HAML specifics

`haml` is a development dependency, so HAML tests can rely on it. To test haml 5.2/6 locally, use a throwaway Gemfile pinning the version (`BUNDLE_GEMFILE=… bundle exec ruby -Ilib -Itest …`). Simulate a missing haml with `HamlParser.stub(:require_haml, -> { raise LoadError })` (see [HAML front-end](/pipeline/haml-front-end.md#optional-dependency)).
