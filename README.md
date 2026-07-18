# review-ast

An AST-based compiler / renderer pipeline for [Re:VIEW](https://github.com/kmuto/review),
distributed as a **separate gem that depends on the released `review` gem**.

The goal is to develop the AST subsystem independently, with real users and a
measurable output-parity signal, without requiring a large merge into Re:VIEW
itself. The only changes the AST code needs in existing Re:VIEW classes are three
small, purely-additive hooks (34 lines); here they are applied at load time as
monkey patches in [`lib/review/ast/core_ext.rb`](lib/review/ast/core_ext.rb)
instead of being merged upstream.

## Status

Experimental. No API stability guarantees yet.

Current scope:

- AST compiler and node model (`ReVIEW::AST`)
- Re:VIEW source round-trip (`review-ast-dump2re`)
- Renderers (`ReVIEW::Renderer`): HTML, LaTeX, IDGXML, plaintext, TOP
- Commands:
  - `review-ast-dump` — dump AST as JSON
  - `review-ast-dump2re` — regenerate Re:VIEW source from the AST
  - `review-ast-compile` — render a chapter (`--target html|latex|idgxml`)
  - `review-ast-pdfmaker` / `review-ast-idgxmlmaker` / `review-ast-textmaker` — book makers

EPUB maker and Markdown input exist in the upstream `ast-renderer` branch and can
be brought in as follow-ups.

## Requirements

- Ruby >= 3.1
- `review` ~> 5.11 (used as a normal gem dependency)

## Usage

```bash
bundle install

# Dump the AST of a chapter as JSON
bundle exec review-ast-dump chapter.re

# Render a chapter to HTML via the AST pipeline
bundle exec review-ast-compile --target html chapter.re
```

## Development

```bash
bundle exec rake test
```

The test suite includes comparator tests that render sample books through both
the AST HTML renderer and Re:VIEW's own `HTMLBuilder`, asserting the two outputs
match. This parity signal is the basis for deciding when the AST path is ready to
become opt-in inside Re:VIEW.

Beyond the text-level comparators, the AST LaTeX renderer is checked against the
legacy `LATEXBuilder` at the *typeset* (DVI) level, which catches whitespace-only
divergences the text comparators are blind to. See
[doc/differential-testing.md](doc/differential-testing.md) for the methodology,
the localization workflow, and a catalog of divergence classes found so far, and
[tools/README.md](tools/README.md) for the sweep tool.
[doc/spec-questions.md](doc/spec-questions.md) tracks builder behaviours we match
that are undocumented or look questionable, so they can be triaged rather than
mistaken for AST bugs.

## How the upstream hooks work

`core_ext.rb` adds three things to the released `review` gem, each guarded so it
is a no-op if Re:VIEW ever ships them natively:

| Patched | Change |
| --- | --- |
| `ReVIEW::SnapshotLocation` | `#to_h`, `#format_for_error` |
| `ReVIEW::Book::Index::Item` | `caption_node:` keyword + accessor |
| `ReVIEW::Book::BookUnit` | `#ast_indexes=` |

## License

LGPL 2.1 (same as Re:VIEW).
