---
type: Decision
title: Knowledge capture with OKF
description: Knowledge, design decisions and documentation about this gem are recorded in this OKF bundle and kept in sync with the code.
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: claude-md
    title: CLAUDE.md — Knowledge management (OKF)
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/CLAUDE.md
---

# Decision

This bundle (`.okf/` at the repo root) is the system of record for what is known about the gem.[^claude-md] When code or behaviour changes, update the affected concepts and append to `log.md`; when a new design decision is made, record it as a `Decision` concept in the area it concerns (e.g. [HTML entity decoding](/pipeline/html-entity-decoding.md)).

Capture what the code doesn't say on its own — the *why*, cross-file coupling, invariants, tradeoffs — and link to source files rather than restating them.
