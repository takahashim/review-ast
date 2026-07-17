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
