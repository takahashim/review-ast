# review-ast

An AST-based compiler / renderer pipeline for [Re:VIEW](https://github.com/kmuto/review),
distributed as a **separate gem that depends on the released `review` gem**.

The goal is to develop the AST subsystem independently, with real users and a
measurable output-parity signal, without requiring a large merge into Re:VIEW
itself. It runs against the released `review` gem through its public API alone:
it re-opens no Re:VIEW class and applies no monkey patch. Everything the AST
owns — its node model, indexes, reference resolution, image paths — lives in
`ReVIEW::AST`; Re:VIEW is used only as a library of services (source line input,
the Book/Chapter model for a handful of metadata values, i18n, image lookup, and
the maker base classes). See [Relationship to Re:VIEW](#relationship-to-review).

## Status

Experimental. No API stability guarantees yet.

Current scope:

- AST compiler and node model (`ReVIEW::AST`)
- Re:VIEW source round-trip (`review-ast-dump2re`)
- Renderers (`ReVIEW::Renderer`): HTML, LaTeX, IDGXML, plaintext, TOP, Typst
- Commands:
  - `review-ast-dump` — dump AST as JSON
  - `review-ast-dump2re` — regenerate Re:VIEW source from the AST
  - `review-ast-compile` — counterpart of `review-compile`: render chapters
    (`--target html|latex|idgxml|plaintext|top|typst`), with review-compile's
    options (`--level`, `--toclevel`, `--chapterlink`, `--directory`, …)
  - `review-ast-pdfmaker` / `review-ast-idgxmlmaker` / `review-ast-textmaker` — book makers
  - `review-ast-vivliostylemaker` — PDF through Vivliostyle (CSS paged media)
    instead of LaTeX; needs Chrome/Chromium and the `vivlio-pdf` gem
  - `review-ast-typstmaker` — PDF through Typst instead of LaTeX; needs the
    `typst` binary
  - `review-ast-index` / `review-ast-vol` — `review-index` / `review-vol` with
    chapters read by the AST, so a Markdown book is listed with its titles

A book's `review-ext.rb` keeps working: commands it declares with
`ReVIEW::Compiler.defblock`/`definline` are rendered by the builder methods it
defines, as in the legacy path; see [doc/review-ext.md](doc/review-ext.md).

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

`REVIEW_HEAD=master bundle install && REVIEW_HEAD=master bundle exec rake test`
runs the same suite against Re:VIEW's master branch (see
[doc/differential-testing.md](doc/differential-testing.md#tracking-review-master)).

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

## Relationship to Re:VIEW

The AST subsystem re-opens no Re:VIEW class and applies no monkey patch; there
are no back-references from Re:VIEW into the AST either. It touches the released
gem at three narrow, well-defined interfaces:

- **Entry** — the compiler feeds `chapter.content` into `ReVIEW::LineInput`. That
  is the only dependency on Re:VIEW's parser; the lexing (inline, block, headline)
  is the AST's own.
- **Renderer initialization** — `Renderer::Base#initialize` bundles chapter →
  book → config. The values actually read afterwards are `chapter.number` (section
  numbering), `chapter.id` (links and filenames), `is_a?(ReVIEW::Book::Part)`,
  `book.imagedir` / `basedir` (asset paths), and `config`.
- **Reused services** — `ReVIEW::I18n` for localized strings,
  `ReVIEW::Book::ImageFinder` for image-path resolution, and the maker base
  classes (PDF / IDGXML / TEXT extend Re:VIEW's own makers).

Reference data, numbering, and image paths are all owned by the AST (stamped on
the nodes or held in `ReVIEW::AST::ChapterIndexRegistry`), so the renderers read
nothing back out of Re:VIEW's index objects.

## License

LGPL 2.1 (same as Re:VIEW).
