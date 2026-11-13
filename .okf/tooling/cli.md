---
type: Component
title: CLI
description: Thor-based ruby_ui_converter convert command that maps flags onto a Configuration and runs Doctor after each conversion.
resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/cli.rb
tags: [cli]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: readme-cli
    title: README — CLI usage
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#cli-usage
---

# Overview

`exe/ruby_ui_converter convert PATH` with `--dry-run`, `--force`, `--output`, `--root`, namespace/base-class options, `--no-ruby-ui` and `--literal`.[^readme-cli] Flags become a [Configuration](/tooling/configuration.md).

After each run it consults [Doctor](/tooling/doctor.md) and, **interactively only**, offers to install missing prerequisites; on `--dry-run` or non-TTY it just warns. That is why CLI tests must pass `--dry-run` (see [testing conventions](/practices/testing-conventions.md)). A missing haml gem is reported once per run (see [HAML front-end](/pipeline/haml-front-end.md#optional-dependency)).
