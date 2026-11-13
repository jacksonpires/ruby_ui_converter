# Pipeline

* [Conversion pipeline](conversion-pipeline.md) - The linear stage chain from template source to Ruby, with two front-ends sharing one AST.
* [ERB placeholder lexing](erb-placeholder-lexing.md) - Why ERB tags are swapped for alphanumeric placeholders before HTML tokenizing.
* [HTML entity decoding](html-entity-decoding.md) - Why text reaches the Transformer decoded, and what is exempt.
* [AST nodes](ast-nodes.md) - Node types, attribute "parts", and the matcher API rules use.
* [HAML front-end](haml-front-end.md) - Building the ERB-equivalent AST from the haml gem's parse tree.
* [HAML attribute merging](haml-attributes.md) - Reproducing HAML's class/id/data merge rules as attribute parts.
* [Transformer](transformer.md) - Walks the AST, emits Phlex calls, and exposes the emitter API.
