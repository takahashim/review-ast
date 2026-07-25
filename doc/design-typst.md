# The Typst renderer and maker

## 1. Purpose and audience

### 1.1 Scope and audience

- This document describes the generating side of the Typst output: TypstRenderer and TypstMaker
- It is written for the developers who change and maintain that side, and aims to be enough on its own for the work they do — adding support for an element, changing the maker

### 1.2 The pipeline

- The Typst output is a PDF path of its own, beside the LaTeX one

```text
resolved core AST
    ↓ TypstRenderer (per chapter)
chapters/*.typ (a sequence of review.* calls)
    ↓ the review-book library (shipped in the gem, copied in at build time)
    ↓ the typst CLI
PDF
```

- One invariant over all of it: every path inside the generated files is absolute from the root (the build directory). Typst resolves a relative path against the file it is written in, and the generated files and the library do not share a directory

## 2. Generating code

### 2.1 Semantic calls only

- The renderer never states layout: it emits no `#block(fill: ...)` and the like, only calls into the semantic API (`review.*`)

### 2.2 A value's path is decided by its type

- Turning a value the renderer holds (a string from the manuscript, rendered markup) into its spelling in the `.typ` source follows one rule: a value travels by the path that matches where it lands
- Why: the same string is spelled differently per destination — escaped markup in a content block, a quoted literal in a str argument
- That choice is a type rather than a naming convention
  - `Text`: a piece of text. `#content` yields `[escaped markup]`, `#literal` a `"quoted string"`
  - `Code`: a Typst expression to be evaluated; never escaped
  - `Expression`: holds the spelling of a call in one place. An empty content argument is omitted entirely, since the contract distinguishes `none` from `[]`

### 2.3 An unknown inline is an error

- Unknown inlines are errors
- `Renderer::Base#render_inline_element` defaults to passing the content through, which loses meaning silently, so it is overridden to fail

## 3. Numbers and labels

### 3.1 Numbers are fixed on the Re:VIEW side

- That numbers are fixed on the Re:VIEW side is common to every renderer. The library never recomposes a number (its contract), so the renderer produces the display text and hands it over
- `number-text` comes from TextFormatter's `format_caption_plain`. `format_caption` is not used: its number form carries the separator, and the separator between number and title belongs to the theme
- Heading numbers are counted by SecCounter, and whether `secnolevel` shows them is decided on the Ruby side too

### 3.2 Chapter labels

- A chapter label goes on the first level-1 heading of each chapter file, and only there
- Why: `=[nonum]` is level 1 as well, so one file can hold several level-1 headings, and defining the same label twice makes Typst reject the whole document

### 3.3 Footnotes and endnotes

- A footnote is emitted at the position of its first `@<fn>` as a `review.footnote` carrying the body; later references become `review.footnote-ref`
- The number is supplied and the library forces it. This keeps the numbering equal to HTML's even when a `//footnote` is never referenced
- An endnote emits `endnote-ref` at the reference and the list at `//printendnotes`

### 3.4 How a label is built, and how a reference is made

- A numbered element's label has three parts, `kind:chapter:item` (figures, tables, listings, equations, columns, endnotes, sections)
- Why the chapter id is in there: element ids are chapter-scoped, so without it they would collide across chapters
- Some labels have two parts: a chapter is `chap:chapterkey`, a bibliography entry `bib:item`, a `//label` `label:item`. Bibliography ids are unique book-wide, so nothing qualifies them
- The chapter key is the chapter id as it stands. Where there is no chapter (a part, say) it falls back to the fixed string `book`: building it from object identity or a per-run counter would change between builds, so a fixed value is preferred to an incidental one
- References are emitted as `review.reference` (a link plus the supplied display text). Typst's `ref` is not used, since it would produce a number of its own

## 4. Turning elements into calls

### 4.1 The table is the source of truth

- How each element is treated is `schema/review-elements.yml`'s to say
- It records all 61 block commands and all 57 inlines as `render`, `ignore` or `lowered`, and a test reconciles it mechanically against both the compiler's command table and the renderer's defined methods
- Only three are `ignore` — `//bpo`, `//parasep`, `@<dtp>` — each with its reason stated in the table
- The sections below single out only the elements that needed a judgement call

### 4.2 Equations

- The bodies of `//texequation` and `@<m>` are LaTeX, and the renderer passes them to the `latex:` argument in that notation
- The conversion is the library's math adapter's job: verbatim display by default, replaced by `typst.math: mitex`
- mitex is pinned to 0.2.7. Package and compiler compatibility comes in pairs: 0.2.5, for one, no longer compiles under current Typst (it predates the removal of the `kai` symbol; fixed in 0.2.6). Raising the pin means building for real
- A `}` inside `@<m>` is escaped as `\}` by Re:VIEW's own convention, the same in every output format

### 4.3 //graph

- GraphImage produces an SVG with an external generator first, and the block is then drawn as an ordinary figure (the same split as IdgxmlRenderer)

### 4.4 Images

- The builder name is `typst`, which governs both `//embed`/`//raw` targeting and the search that prefers `images/typst/`
- Alt text is taken from the caption — the same string HtmlRenderer puts in the alt attribute, so both formats describe an image identically

### 4.5 //embed and //raw

- These pass arbitrary Typst code through as it stands, and assume a trusted manuscript
- Typst itself refuses file access outside the root, but code execution is unrestricted, so an environment handling untrusted manuscripts has to decide to keep them out of reach (a switch for it is deferred; chapter 9)

## 5. TypstMaker

### 5.1 It does not subclass the gem's maker

- `PDFMaker#generate_pdf` holds the whole LaTeX toolchain in one method (LATEXBuilder, `ImgGraph(..., 'latex')`, generating the `.tex` master, placing sty files), so subclassing it would mean overriding nearly every path and leave no advantage
- What is reused from the gem is Configure, Book::Base, I18n, Loggable and MakerHelper

### 5.2 The build layout

```text
<basedir>/<bookname>-typst/     ← typst --root
├── book.typ                    ← generated root (part switching, furniture)
├── theme.typ                   ← copied from the manuscript, or generated
├── chapters/*.typ
├── images/                     ← copied after rendering (//graph makes images while it runs)
├── lib/review-book/            ← a copy of the library shipped in the gem
└── source-map.json
```

- The working directory survives the build under `debug: true` or `typst.keep_workdir: true`

### 5.3 The library is copied in, not resolved

- The library arrives as copied files rather than through package resolution
- Why: it works offline, and the renderer and the library are always a pair from one gem version

### 5.4 The working directory

- The whole build runs with basedir as the working directory
- Why: review 5.11, the version depended on, resolves several paths against the process's working directory rather than the book's — contentdir, through which `Book::Part` reads its body, and imagedir, under which `//graph` writes its image. Called from elsewhere, a part's body comes back empty, and silently
- Upstream has since resolved both against the book, so once a release carries that and the dependency floor can rise, the chdir goes away (9.1)

### 5.5 Configuration

- Settings live under the `typst:` namespace

```yaml
typst:
  command: typst        # the CLI name; detected and version-checked
  pdf_standard: ~       # "ua-1", for one
  math: ~               # "mitex" sets LaTeX equations with mitex
  crop: ~               # true draws crop marks and bleed (overriding the theme)
  index: false          # emit the index page
  keep_workdir: false   # keep the generated .typ files
  output: ~             # defaults to <bookname>-typst.pdf
```

- Existing keys consulted: `coverimage`, `cover` (with crop marks on the cover is skipped by default; `true` forces it in, as for review-jsbook), `titlepage`, `toc`, `toclevel` (the depth of the table of contents, passed as `review.toc`'s `depth` and winning over the theme's `toc.depth`; EPUB and LaTeX read the same key, which is what keeps the depth equal across formats), `colophon`, `colophon_order`, `history`, `rights`, `dictionary`, `secnolevel`, `caption_position`, `debug`

## 6. Diagnostics and the source map

### 6.1 Putting the manuscript position beside the diagnostic

- Typst reports positions in the generated `.typ`, but what the author wrote is the manuscript
- The renderer records, per chapter, which line range of the generated file came from which manuscript position (at top-level block granularity), and the maker annotates every position in a diagnostic with it

```text
error: unknown variable: ...
  ┌─ book-typst/chapters/ch01.typ:9:1  <- ch01.re:7:1
```

- The generated position is not removed: that is the file the compiler actually read

### 6.2 source-map.json

- The table is also written into the build directory as `source-map.json`, so it can be followed afterwards with `keep_workdir`
- It does not reach inside a block (deferred; chapter 9)

## 7. Things Typst will punish

- The list of things that break the generated code if its author does not know them. What the library's author needs is in chapter 6 of `typst-review-book.md`
- `//` starts a line comment in content mode too. Writing something like "//list" in a paragraph needs escaping
- `--` becomes an en dash and `...` an ellipsis. At the start of a line, `- `, `+ `, `= `, `/ ` and `1. ` become list items, headings or term entries (`/ ` is a term)
- Do not generate bullet lists or term lists in markup syntax: a `:` or `/` inside an item collides with the syntax. Pass an array of content to a function call instead
- Write paths absolute from the root (the invariant in 1.2)

## 8. Verifying, and how to make a change

### 8.1 Three layers of assurance

- There is no oracle for parity, so three layers stand in for one
  1. Element coverage: `schema/review-elements.yml` is reconciled both ways with the compiler's command table and the renderer's defined methods. A command missing from the table, a table entry with no implementation, and an element that declares `ignore` yet emits output all fail the test
  2. Numbering equality: the same manuscript is rendered by HtmlRenderer and TypstRenderer and their heading numbers compared. The expected values are pinned as well, so two empty results cannot pass vacuously
  3. Building for real: a structure test covering every book part and both kinds of part page, the two sample books, and for PDF/A and PDF/UA a two-stage check — Typst's own conformance check and veraPDF

### 8.2 CI

- CI stands alone as `.github/workflows/typst.yml`, since it needs a document engine installed
- It installs CJK fonts too: without them Typst falls back silently, and the tests would pass without ever setting Japanese
- It installs veraPDF too: the test skips the second stage silently when the binary is absent, so without it a conformance regression goes unnoticed — the same trap as the fonts

### 8.3 Making a change

- Adding support for an element: implement the visit method or the inline handler and update `review-elements.yml` (the coverage test fails otherwise). Add a renderer test, and for a new path add it to the structure test's fixture as well
- Raising the Typst or mitex version: read chapter 7 and chapter 6 of the library document again. mitex has broken compatibility with the compiler across versions before (4.2)

## 9. Out of scope and deferred

### 9.1 Would be resolved by doing the work

- `//graph` with gnuplot / blockdiag / seqdiag / actdiag / nwdiag is unverified (graphviz is verified); mermaid requires playwright
- No warning for an unknown key under `typst:`. A misspelled setting (`keep_workdir`, say) is ignored silently
- A maker switch to keep `//embed`/`//raw` out of reach for untrusted manuscripts (4.5)
- Alt text for equations under PDF/UA. They are set verbatim or through mitex today; whether alt text becomes mandatory is undecided
- Index order falls back to code-point order in a book without a `dictionary`
- The source map is per top-level block (6.2)
- Removing the `Dir.chdir` around the build (5.4). Upstream has resolved contentdir and imagedir against the book, so it can go once a release carries that and the dependency floor rises

### 9.2 Decided against

- PDF/X — impossible on the Typst side (chapter 5 of the library document); revisit when upstream supports it
- Imposition. Arranging pages into signatures is the printer's step, or a dedicated tool's
- Publishing to Typst Universe. It needs examples of writing `book.*` by hand and a settled API; until then the bundled copy is the better arrangement operationally
- The `typst` gem (Ruby bindings for the compiler). The CLI is enough, and the gem cannot state a PDF standard

### 9.3 Cannot be settled here

- Actual submission to a printer. Dimensions, mark positions, font embedding and PDF/A conformance are verified mechanically. What remains uncertain is each printer's own requirements, so start small the first time
