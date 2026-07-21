# Specification of the Typst renderer and maker

This document specifies the Ruby side of review-ast's Typst output:
TypstRenderer and TypstMaker. The design of the book library the generated
code calls into is in `typst-review-book.md`, which also defines the
`review.*` calling contract. Contracts shared by every renderer and maker (the
visitor protocol, how numbering and reference resolution work) live in
`review-ast-architecture.ja.md` and `ast-semantics.ja.md` and are not repeated
here.

The Japanese counterpart is `design-typst.ja.md`. Ruby code comments reference
this file.

## 1. Overview

The Typst output is a PDF path beside the LaTeX one.

```text
resolved core AST
    ↓ TypstRenderer (per chapter)
chapters/*.typ (a sequence of review.* calls)
    ↓ review-book library (bundled with the gem, copied at build time)
    ↓ typst CLI
PDF
```

Like the webmaker, this is an output target without a parity oracle. Matching
the LaTeX page layout is not a goal; correctness is guarded by the three
verification layers in chapter 8.

One invariant runs through everything: the build directory
`<bookname>-typst/` that TypstMaker creates is the Typst project root
(`typst --root`), and **every path in the generated sources is absolute from
that root**. Typst refuses to read outside the root, and a relative path
resolves against the file it is written in, so root-absolute paths are the
only form that resolves the same everywhere.

## 2. Code generation

The renderer never states layout. It emits nothing but semantic calls
(`review.*`) — no `#block(fill: ...)`.

Turning a value the renderer holds (a string from the manuscript, rendered
markup) into its spelling in the generated `.typ` source follows one rule — a
value travels by the path that matches where it lands — and that choice is a
type rather than a naming convention. The same string is spelled differently
per destination: escaped markup in a content block, a quoted literal in a
str argument.

- **`Text`** — a piece of text; `#content` yields `[escaped markup]`,
  `#literal` yields a `"quoted string"`
- **`Code`** — a Typst expression to be evaluated; never escaped
- **`Expression`** — spells call expressions in one place. An empty content
  argument is omitted entirely, because the contract distinguishes `none`
  from `[]`.

Unknown inlines are an error. `Renderer::Base#render_inline_element` defaults
to passing content through, which loses meaning silently, so the Typst
renderer overrides it to fail.

## 3. Producing numbers and labels

That numbers are fixed on the Re:VIEW side is common to all renderers. Since
the library never recomputes a number (its contract), the renderer produces
the finished display strings:

- `number-text` comes from TextFormatter's `format_caption_plain`
  (`format_caption` includes the caption separator, which belongs to the
  theme, between number and title).
- Heading numbers are counted with SecCounter, including the `secnolevel`
  visibility decision.
- Only the first level-1 heading of a chapter file carries the chapter label.
  `=[nonum]` sections are still level 1, so one file can hold several, and a
  duplicate label makes Typst reject the whole document.
- A footnote's body is emitted at its **first** `@<fn>` as `review.footnote`;
  later references become `review.footnote-ref`. The number is supplied; the
  library enforces it. This keeps numbers aligned with HTML even when a
  `//footnote` is never referenced.
- Endnotes: a linked mark at the reference, the list at `//printendnotes`.

Labels are three-part, `kind:chapter:item`. Element ids are chapter-scoped, so
without the chapter they collide across chapters. Elements without a chapter
(parts, the bibliography) get a deterministic document key derived from
catalog order and file names. References are emitted as `review.reference`
(link plus the supplied display string); Typst's `ref` is never used — it
would generate its own number.

## 4. Element mapping

The authority on how each element is handled is
`schema/review-elements.yml`. It records all 61 block commands and all 57
inlines as `render` / `ignore` / `lowered`, and a test cross-checks it in both
directions against the compiler's command tables and the renderer's defined
methods. Only `//bpo`, `//parasep` and `@<dtp>` are `ignore`, each with its
reason stated in the table.

Only the elements that needed a decision are described here:

**Math.** `//texequation` and `@<m>` carry LaTeX notation; the renderer passes
it through unchanged as the `latex:` argument. Conversion is the library's
math adapter: verbatim by default, swapped with `typst.math: mitex`. The mitex
version is pinned to 0.2.7 — package/compiler compatibility comes in pairs,
and 0.2.5 does not compile under current Typst (it predates the removal of
the `kai` symbol; fixed in 0.2.6). Raising the pin means building for real
against the target Typst. A `}` inside `@<m>` must be escaped as `\}` per Re:VIEW's own
rules (common to every output format).

**//graph.** GraphImage runs the external generator to produce an SVG first;
the block then renders as an ordinary figure (the same split as
IdgxmlRenderer).

**Images.** The builder name is `typst`, which governs both `//embed`/`//raw`
targeting and the `images/typst/` search. Alt text is taken from the caption —
the same string HtmlRenderer puts in the alt attribute, so both formats
describe an image identically.

`//embed` and `//raw` pass arbitrary Typst code through verbatim and assume a
trusted manuscript. Typst itself refuses file access outside the root, but
code execution is unrestricted, so an environment that processes untrusted
manuscripts must keep these commands out of reach (a disable switch is
deferred; chapter 9).

## 5. TypstMaker

TypstMaker does not subclass the gem's makers. `PDFMaker#generate_pdf`
hard-wires the LaTeX toolchain (LATEXBuilder, `ImgGraph(..., 'latex')`, the
`.tex` master, sty copying) into one method; a subclass would override nearly
every path and gain nothing. What is reused from the gem: Configure,
Book::Base, I18n, Loggable, MakerHelper.

Build layout:

```text
<basedir>/<bookname>-typst/     ← typst --root
├── book.typ                    ← generated root (part switching, furniture)
├── theme.typ                   ← copied from the book if present, else generated
├── chapters/*.typ
├── images/                     ← copied AFTER rendering (//graph produces
│                                 its images during rendering)
├── lib/review-book/            ← copy of the bundled library
└── source-map.json
```

The library is copied, not resolved as a package: the build works offline, and
the renderer and the library always move in lockstep within one gem.

The whole build runs with the book directory as the working directory. Re:VIEW
resolves several paths against the process's working directory rather than the
book's (`Book::Part` reading its source, `//graph` writing under imagedir).
The Part case is an upstream defect with a fix proposed; the chdir stays
regardless, for `//graph`.

The work directory survives with `debug: true` or `typst.keep_workdir: true`.

Configuration lives under the `typst:` namespace:

```yaml
typst:
  command: typst        # CLI name; detected and version-checked
  pdf_standard: ~       # e.g. "ua-1"
  math: ~               # "mitex" to typeset LaTeX math with mitex
  crop: ~               # true for crop marks and bleed (overrides the theme)
  index: false          # emit the index pages
  keep_workdir: false   # keep the generated .typ tree
  output: ~             # default <bookname>-typst.pdf
```

Existing keys consulted: `coverimage`, `cover` (with crop marks on, the cover
is skipped by default; `true` forces it in, as for review-jsbook), `titlepage`,
`toc`, `colophon`, `colophon_order`, `history`, `rights`, `dictionary`,
`secnolevel`, `toclevel`, `caption_position`, `debug`.

## 6. Diagnostics and the source map

Typst diagnostics point at the generated `.typ`, which the author never
wrote. The renderer records, per chapter, which line range of the generated
file came from which manuscript position (top-level block granularity), and
the maker annotates every position in a diagnostic with the manuscript one:

```text
error: unknown variable: ...
  ┌─ book-typst/chapters/ch01.typ:9:1  <- ch01.re:7:1
```

The generated position is kept too — that is the file the compiler actually
read. The map is also written as `source-map.json` in the build directory, so
a kept work directory can still be traced later. Lines inside a block are not
resolved (a deferred item; chapter 9).

## 7. Caveats for generated code

Things that break when generating Typst without knowing them. The caveats for
writing the library itself are in `typst-review-book.md`, chapter 6.

- `//` starts a line comment even in content mode; prose like "//list" needs
  escaping.
- `--` ligates to an en dash, `...` to an ellipsis; a leading `- ` `+ ` `= `
  `1. ` starts a list or heading.
- Never generate bullet or term lists in markup syntax: `:` and `/` inside
  item content collide with it. Pass items to the list functions as content
  arrays.
- Paths are root-absolute (the invariant in chapter 1).

## 8. Verification, and how to make changes

Without a parity oracle, three layers stand in:

1. **Element coverage** — `schema/review-elements.yml` is cross-checked
   against the compiler's command tables and the renderer's defined methods.
   A command missing from the table, a table entry without an implementation,
   and an `ignore` entry that actually emits output all fail the test.
2. **Number parity** — the same manuscript is rendered by HtmlRenderer and
   TypstRenderer and the heading numbers compared, with the expected values
   pinned so two empty extractions cannot pass vacuously.
3. **Real builds** — a structural test covering every catalog bucket and both
   part kinds, builds of the two sample books, and for PDF/A / PDF/UA a
   two-stage check (Typst's own export validation, then veraPDF).

CI runs in its own workflow, `.github/workflows/typst.yml` — the only suite
that needs an external typesetting engine. It also installs CJK fonts:
without them Typst falls back silently and the samples would pass without
ever setting Japanese text.

Typical changes:

- **Supporting an element**: implement the visit method or inline handler,
  update `review-elements.yml` (the coverage test fails otherwise), add a
  renderer test, and extend the structural fixture if the path is new.
- **Raising Typst or mitex**: re-read chapter 7 and the library document's
  chapter 6; mitex has broken compatibility with the compiler across
  versions before.

## 9. Out of scope and deferred

**Would be resolved by doing the work**

- `//graph` with gnuplot / blockdiag / seqdiag / actdiag / nwdiag is
  unverified (graphviz is verified); mermaid requires playwright.
- Index order without a `dictionary` falls back to code-point order.
- The source map is per top-level block.
- No warning for unknown keys under `typst:` — a misspelled setting
  (`keep_workdir`, say) is silently ignored.
- A maker switch to disable `//embed`/`//raw` for untrusted manuscripts
  (chapter 4).
- Alt text for equations under PDF/UA. Equations are set verbatim or via
  mitex; whether alt text becomes mandatory is undecided.

**Decided against**

- PDF/X — impossible on the Typst side (library document, chapter 5); revisit
  when upstream supports it.
- Imposition — the printer's (or a dedicated tool's) job.
- Publishing to Typst Universe — premature until `book.*` has hand-written
  usage and a stable API; until then the bundled copy is also operationally
  simpler.
- Adopting the `typst` gem (compiler bindings) — the CLI suffices, and the
  gem exposes no PDF-standard selection.

**Cannot be settled here**

- Actual print-shop submission. Dimensions, crop marks, font embedding and
  PDF/A conformance are machine-checked; the remaining uncertainty is each
  printer's individual requirements. Try a small run first.
