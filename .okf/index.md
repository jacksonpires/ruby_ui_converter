---
okf_version: "0.2"
---

# ruby_ui_converter

* [ruby_ui_converter](overview.md) - What the gem is, who it is for, and the shape of its output.

# Areas

* [Pipeline](pipeline/) - How templates become an AST: the ERB and HAML front-ends, the shared AST, and the Transformer.
* [Mapping](mapping/) - How HTML elements, Rails helpers and form builders become RubyUI/Phlex calls.
* [Output](output/) - The shape of each generated class: naming, initializers, locals, Literal mode, collisions.
* [Tooling](tooling/) - CLI, Doctor, compatibility matrix and the Rails end-to-end check.
* [Practices](practices/) - How to work on this codebase: testing conventions and invariants to keep.
