# Differential testing (builder vs AST renderer)

review-ast reimplements Re:VIEW's output pipeline on top of an AST. The single
most important correctness question is therefore:

> Does the AST renderer produce the **same result** as the legacy
> `ReVIEW::LATEXBuilder` (and the other builders)?

This document describes how we answer that with **differential testing** — using
the legacy builder as an oracle — at two levels of strictness, and records the
methodology and the classes of divergence it has found.

## Two oracles, two strictness levels

| Level | What it compares | Speed | Sees whitespace? |
| --- | --- | --- | --- |
| **text-canonical** | builder LaTeX vs renderer LaTeX, after normalizing whitespace/blank-lines | fast (no TeX) | **no** |
| **DVI** | the *typeset* output (DVI) of both | slow (runs uplatex) | **yes** |

The text-canonical comparators (`test/support/review/test/*_comparator.rb`) run
in the normal test suite. They deliberately ignore whitespace and blank lines,
so they answer "is the markup structurally equivalent?" — but they are **blind**
to differences that only whitespace can express.

The DVI comparator (`tools/compare/dvi_comparator.rb`) closes that blind spot. It
typesets both LaTeX bodies under an identical preamble and compares the DVI. If
the DVI differs, the two paths genuinely typeset differently — a real, visible
divergence. Because the preamble and the TeX toolchain are fixed, the DVI is the
*meaning* of the output; there is no further normalization to argue about.

**Every bug in the table below passed the full text-canonical suite.** DVI is
what caught them.

## Running a DVI sweep

```sh
BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/compare_book.rb samples/syntax-book
```

For each chapter it renders the LaTeX body twice (builder vs renderer, with full
book context), typesets both, and reports whether the DVI is identical. Chapters
that only one path can compile are reported as `CERR`. See `tools/README.md` for
details and the library API.

Determinism: the only nondeterministic part of a DVI is the timestamp comment in
the preamble, which is fixed with `-output-comment` and stripped from the dviasm
dump. DVI is otherwise tied to the TeXLive version, so a CI sweep needs a pinned
toolchain (that work is deliberately deferred).

## Localizing a divergence

When a chapter's DVI differs, this workflow pins the cause quickly:

1. **DVI dump → text.** Diff the dviasm dumps and read the nearest `set: '…'`
   glyphs around the first change to learn *what text* is mispositioned, and the
   `pdf:dest`/`[page …]` markers for *where*.
2. **Quantify.** Small, isolated `down:`/`right:` deltas (< 1pt, few lines) mean
   a local spacing difference; thousands of changed lines mean a pagination
   cascade from something earlier.
3. **Text → source construct.** Grep the mispositioned text in the `.re` source
   and look at the construct just before it.
4. **Compare the `.tex`.** Diff builder vs renderer LaTeX for that chapter and
   look at the exact lines around the construct (whitespace matters — view with
   markers). This usually shows the offending byte-level difference.
5. **Minimal repro.** Reconstruct the construct in a few lines and DVI-compare it
   in isolation (`DviComparator#compare`). This confirms the cause and becomes
   the basis for a regression test.

Because the text-canonical comparator ignores whitespace, regression tests for
whitespace-class findings must assert on the **exact** rendered string, not via
the canonical comparator.

## Divergence classes found so far

Each of these was found by a DVI sweep, fixed, and locked in with a regression
test. They cluster into a few recurring shapes.

| Area | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| Caption numbering | appendix caption numbered `1.1` instead of `A.1` | used raw `@chapter.number` instead of appendix/secnolevel-aware `get_chap` | route caption numbers through `get_chap` |
| Block + footnote | `\footnotetext` after a minicolumn placed after a blank line (spurious empty paragraph) | trailing blank emitted before the collected `\footnotetext` | emit `\end{…}` → `\footnotetext` → blank |
| Verbatim | tab-aligned code typeset at the wrong width | code lines not detabbed like `LATEXBuilder#code_line` | detab in `visit_code_line` (honoring `tabwidth`) |
| Forced break | `@<br>{}` at end of a source line adds ~0.95pt vertical space | `@<br>` emits `\\\n`; the preserved source newline makes it `\\\n\n` (a `\par`) | collapse a blank line right after a forced break in `visit_paragraph` |
| Compiler (not render) | `==[column]` containing `====` subsections fatally errors on `==[/column]` | headlines reset the current node to root, losing column context; close couldn't find the column | keep the current node inside the column across subsections; walk ancestors to close |
| Compiler (not render) | two blank-separated `ul`/`ol` merged into one list (numbers ran 1..6) | the list-structure normalizer merged *all* adjacent same-type lists | merge only `dl` across a blank line and only fold `ul`/`ol` continuations across `//beginchild` — matching LATEXBuilder |
| Numbering | trailing / lone blank line in `//listnum` not numbered | `add_line_numbers` skipped the last empty line and `split("\n")` dropped trailing empties | `split("\n", -1)[0...-1]` — keep genuine blank lines, drop only the artifact |
| Verbatim | tab-aligned code in `//listnum` mis-aligned by the `" N: "` width | detabbed the raw line before prepending the number | detab the final line *after* numbering (`detab_content` in the block wrappers) |
| Parser | `"===== {x} caption"` treated `{x}` as a heading label | the parser stripped the leading space before checking for `{label}` | don't strip: a label only counts immediately after `=`/`[tag]` (no space), matching Compiler |
| Parser | trailing `"Caption{label}"` treated `{label}` as a label | AST had a non-standard trailing-label syntax | remove it — Re:VIEW labels are leading (`=={label} Caption`); a trailing `{...}` is caption text |
| Renderer (gap) | `//box` raised NotImplementedError | the block was never implemented in the AST LaTeX renderer | implement `visit_block_box` (reviewbox env, detabbed inline-processed lines, optional caption) |
| Renderer | `@<idx>{和文}` emitted `\index{語@語}` | always produced a "key@display" sort key | only emit a sort key when one exists (dictionary/MeCab); otherwise `\index{語}` |
| Renderer | deep unnumbered headline TOC name wrong (level 5→subsection) | hardcoded `case` mapping capped at subsection | use the `HEADLINE` mapping (paragraph/subparagraph for 5/6) |
| Compiler | nested block inside a minicolumn/quote moved to the end | content lines and nested blocks were collected separately, losing order | record each nested block's line position and interleave in source order |

### A design note: list merging

LATEXBuilder is the oracle, and it treats blank-separated lists per type:

- **`ul` / `ol`**: a blank line ends the list; the next group is a *separate*
  environment (numbering restarts). They only rejoin when interrupted by
  `//beginchild .. //endchild` (an explicit nesting directive).
- **`dl`**: consecutive blank-separated `: term` groups form *one* description
  list.

The AST originally merged all adjacent same-type lists unconditionally, which is
a reasonable-looking design choice but disagrees with the builder for `ul`/`ol`.
We aligned with the builder. If Re:VIEW ever decides blank-separated `ul`/`ol`
*should* merge, this is the place to revisit — but then the builder would need to
change too, so the two stay in sync.

### Recurring lessons

- **Whitespace is semantics in two places:** verbatim environments (tabs/spaces)
  and forced breaks / paragraph boundaries (`\\`, blank lines → `\par`). These
  are exactly what the text-canonical comparator cannot see, and where DVI earns
  its keep.
- **Japanese line handling hides differences.** upLaTeX suppresses the space at a
  source newline between Japanese characters, so builder "join lines into one"
  vs renderer "keep source lines" is usually DVI-identical — *except* when a
  forced break or a non-Japanese boundary is involved. Don't assume a `.tex`
  whitespace difference is invisible; confirm with DVI.
- **Match the legacy builder's byte output where whitespace is load-bearing.**
  Several fixes were simply "emit the same newlines the builder does."
- **Real books exercise constructs samples don't.** The column/subsection and
  `@<br>`-at-line-end bugs only surfaced on `FirstStepReVIEW-v3`; the bundled
  samples were already clean. Sweeping additional real books is high-value.

## Property-based testing

`tools/pbt/` generates random self-contained documents and runs the same two
oracles over them, shrinking any counterexample to a minimal `.re` (see
`tools/README.md`). The workflow is loop-until-dry: fix a finding, fold it into a
regression test, re-run. Structural bugs surface in the fast `canonical` mode;
whitespace-only bugs (e.g. the tab-after-number alignment above) surface only in
`dvi` mode, so the productive order is **canonical until dry, then dvi**.

At the time of writing both modes are dry across the first ~90 seeds. All five
PBT-found classes in the table above were fixed and locked in with regression
tests. Two operational notes learned here:

- The generator must only emit inputs *both* paths can compile and typeset;
  otherwise "both fail" noise (unsupported inline ops, `@<ins>{a<b}` breaking
  underline macros) drowns real findings. The runner classifies "both fail"
  separately from a genuine divergence.
- Seeds are reproducible but not stable across generator changes — fold findings
  into tests, never cite a seed as the regression.

## Scope and limits

- DVI comparison is LaTeX-only. HTML/IDGXML keep using DOM/text normalization.
- It requires TeXLive (`uplatex`, `dviasm`, `extractbb`) and `python3`.
- It compares builder vs renderer, not against a published PDF: the preamble is
  harvested from the book but the goal is *equivalence of the two code paths*,
  not reproducing a specific book's layout.
- A residual DVI difference under ~1pt with equal page counts is a real (if tiny)
  divergence; treat it as a finding to localize, not noise, until explained.
