# tools/

Development tooling for review-ast. Not shipped in the gem.

## DVI differential comparison

`compare/dvi_comparator.rb` typesets two LaTeX *bodies* under an identical
Re:VIEW preamble and compares the resulting DVI. Because the preamble and the
TeX toolchain are held fixed, any DVI difference is a real, visible divergence
between the legacy `LATEXBuilder` and the AST `LatexRenderer`.

It is the strict oracle for:

- **book sweeps** (differential testing over real books), and
- **confirming property-based-testing findings**.

Requirements: TeXLive (`uplatex`, `dviasm`, `extractbb`) and `python3`.

### Sweep a book

```sh
BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/compare_book.rb samples/syntax-book
```

Renders every chapter twice (builder vs renderer, full book context), typesets
both, and reports per-chapter whether the DVI is identical. Exit status is
non-zero if any chapter diverges. Divergences are localized to a page and
dviasm line.

### As a library

```ruby
require 'dvi_comparator'
dvi = ReVIEW::Compare::DviComparator.from_book(book_dir, template_dir: tpl)
result = dvi.compare(builder_latex_body, renderer_latex_body)
result.identical?   # => true / false
result.diff         # => { page:, first_diff_line:, removed:, added:, ... }
```

Determinism note: the only nondeterministic part of a DVI is the build
timestamp in the preamble comment, which is fixed via `-output-comment` and
stripped from the dviasm dump before comparison. DVI output is otherwise tied
to the TeXLive version, so cross-machine comparison requires a pinned toolchain.

## Property-based differential testing

`pbt/generator.rb` generates random, self-contained Re:VIEW documents (seed
-deterministic). `pbt/runner.rb` renders each through both a legacy builder and
the matching AST renderer (`LATEXBuilder` / `LatexRenderer` by default), asserts
they agree, and on a counterexample **shrinks** the document to a minimal
reproducer. `--mode html`, `idgxml`, `plaintext` and `top` compare those formats
instead. The nightly workflow runs these four and `canonical`, each with the
default settings, `--config review_version=2.0` and `--config language=en`.

```sh
# fast structural pass (canonical comparison, no TeX)
BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/pbt/runner.rb --mode canonical --seeds 100

# strict pass (DVI comparison; sees whitespace differences, needs TeXLive)
BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/pbt/runner.rb --mode dvi --seeds 50

# another format
BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/pbt/runner.rb --mode top --seeds 200
```

The generator covers the constructs where divergences tend to hide: inline
commands in paragraphs (especially `@<br>{}`), code blocks (tabs, blank lines),
lists, definition lists, minicolumns with captions/footnotes, and tables. It
only emits inline ops that BOTH paths implement, so any divergence is a real
disagreement rather than an unsupported-op error.

Seeds are deterministic: a reported failing seed reproduces exactly. Fold real
findings into permanent regression tests (see doc/differential-testing.md);
don't rely on the seed, which can shift if the generator changes.
