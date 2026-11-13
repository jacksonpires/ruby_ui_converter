---
type: Component
title: ComponentMap
description: Registry of matcher/emitter rules where user rules always win over the built-in fallback rules.
tags: [extension-api, ruby-ui]
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-11-13T12:00:00Z
sources:
  - id: cmap
    title: lib/ruby_ui_converter/component_map.rb
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/lib/ruby_ui_converter/component_map.rb
  - id: readme-rules
    title: README — Custom rules
    resource: https://github.com/jacksonpires/ruby_ui_converter/blob/main/README.md#custom-rules
---

# Overview

A rule is `{matcher: ->(Element) { bool }, emitter: ->(el, transformer, builder) { … }}`.[^cmap] Two layers:

- `register` — **user** rules, always checked first;
- `register_fallback` — built-ins; `ComponentMap.rubyui_rules` installs the [RubyUI element mapping](/mapping/rubyui-element-mapping.md) here.

The layering is the design point: users can override any built-in mapping without having to disable the defaults.[^readme-rules]

Matchers use the [AST matcher API](/pipeline/ast-nodes.md#matcher-api); emitters use the [Transformer emitter API](/pipeline/transformer.md#emitter-api-public-used-by-custom-rules).

# Examples

```ruby
config.component_map.register(
  ->(el) { el.name == "button" && el.static_classes.include?("danger") }
) { |el, t, b| t.kit_component("Button", el, b, extra: "variant: :destructive") }
```
