# review-book: the Typst book library

## 1. Purpose and principles

### 1.1 Scope and audience

- This document describes `review-book` (`templates/typst/review-book/`), the Typst book library shipped with the gem
- It is written for whoever writes the library or a theme, and for whoever needs the `review.*` calling contract (the renderer's maintainers)
- The generator side (TypstRenderer, TypstMaker) is in `design-typst.md`. The page design vocabulary and its values are in `design-hanmen.ja.md`

### 1.2 A thin wrapper over Typst's own elements

- Headings, figures, tables, footnotes and links are thin wrappers over the standard elements (heading, figure, table, footnote, link)
- Why: the outline, the PDF tag tree, cross references and Typst's future improvements all come free from the standard machinery

### 1.3 Two public APIs

- `book.*`: the stable API for documents written in Typst by hand
- `review.*`: the compatibility API for the generator (TypstRenderer); it delegates to `book.*`
- What is specific to Re:VIEW (how numbers arrive, the eight minicolumn kinds) stays in `review.*` and out of `book.*`
- Two exceptions as things stand
  - Endnotes and `//bibpaper` live in `book.*`, with `review.*` only delegating
  - The decoration inlines (inline code, ruby, icons, rules) are not delegated: `review.*` decides their styling too (inline code alone reads the theme's `fonts.code`)

### 1.4 The library produces no numbers

- Numbers arrive from the caller as finished display text. The library and the theme may decorate them but never recompose them
- Why: so that HTML, EPUB and the Typst PDF agree on every number
- The one exception is a page reference: a page number is known only after layout, so it is resolved with Typst's `query` and the page counter

## 2. The review.* calling contract

- This is the boundary between the generated code and the library. The renderer generates calls that follow it

### 2.1 Argument conventions

- `id`: the complete label string (of the form `"fig:ch01:architecture"`). The label scheme belongs to the caller; the library never reinterprets it
- `number-text`: the finished display number (`[図1.1]`), taken as content
- `caption`: the caption body, a separate argument from the number; the separator between them is the library's (the theme's) to insert
- Bodies are content; paths, language names and alt text are str
- Three exceptions
  - Endnotes and `//bibpaper` take an int number and the library builds the display form (superscript, brackets)
  - Endnotes derive a label on the library side (`id + ":body"`)
  - `chapter` and `part` also accept an int `number:`, which is currently received but unused

### 2.2 none is not an empty value

- `caption: none` means "this element has no caption"; `caption: []` means "it has one and it is empty"
- The caller omits an empty caption argument entirely, and the library branches on whether the argument is there

### 2.3 Table header rows

- Header rows are converted to `std.table.header` only when a header exists, never otherwise (the same discipline as 2.2)
- The tag structure (header-cell accessibility) and the repetition of the header across page breaks both arise from that conversion

### 2.4 Footnote numbers

- Forcing the number is the library's half: `footnote-def(number: n)` places `counter(std.footnote).update(n - 1)` immediately before the footnote, bending Typst's automatic numbering to the supplied value
- Deciding at which reference the body appears is the caller's half

## 3. Book structure

### 3.1 Switching the book parts

- Front matter, main matter, appendix and back matter are switched at the top level of the root file with native `set page(numbering: ...)` / `set heading(numbering: ...)` / `counter(...).update`, never functions wrapping the includes. Keeping no library state of its own lets the folio, the native `outline` and the index all read the same `page.numbering`
- Why: a `set` inside a function does not escape to its caller, so the wrapping style cannot vary the per-part page setup (folio format, running heads)

### 3.2 Part title pages

- A part's title page is drawn by `review.part`
- Both kinds reach the same function: a part with its own `.re` (the renderer generates the call) and a part named only in catalog.yml (the maker does)

### 3.3 Cover, title page and colophon

- With crop marks on, the cover (`cover`) is skipped by default: at the printer the cover is separate spread data (front, spine, back), so a body PDF carries no cover page (the same semantics as review-jsbook's `media=print`). `cover: true` in config.yml forces one in, as `cover=true` does there
- When a cover is rendered its artwork runs into the bleed. Forced under crop marks, the page margin keeps the crop-mark area outside the bleed (at zero the artwork would sit on the marks). Under `crop.sheet: auto` that margin equals the mark length; on a named sheet it is wider
- The colophon (`colophon`) reads title, rule, history, roles, rule, rights, aligned to the bottom of the page

### 3.4 Running heads and folios

- The running head carries the chapter title on the left and the section title on the right, with a rule underneath. The folio sits on the fore edge
- Both are replaceable through `renderers` (4.3)

### 3.5 Chapter page breaks

- A chapter's page break is issued inside the heading's show rule and outside the block
- Why: a `pagebreak` inside a block has no effect (6.2)

### 3.6 The index

- The split is: the terms and their reading order come from Re:VIEW, the page numbers from Typst
- `index-entry` only places a `metadata` mark; `print-index` collects them with `query` and gathers the pages of identical terms
- Terms travel as strings, not content: a `metadata` value has to be plain data, and it doubles as the grouping key

## 4. The theme

### 4.1 Design values

- The vocabulary, the values and the derivation rules of a page design are `design-hanmen.ja.md`'s to state. The vocabulary is shared with the Vivliostyle design file, so values carry over as they are
- What this document holds is the shape of the theme dictionary: trim size (`paper` / `binding` / `two-sided`), design values (`text` / `margins` / `fonts` / `colors` / `rules` / `box` / `crop`), behaviour (`toc` / `chapter` / `running-head`) and the extension points (`renderers` / `hooks`)
- `toc.depth` is the default for authors writing by hand. On the generated path `review.toc(depth:)` carries the manuscript's `toclevel`, which wins
- The book states its theme in a `theme.typ` at the top of the project (beside config.yml), placed there by the author; the build copies it in as it is
- Without one, a starter theme is generated inside the build directory and used from there. That directory is rebuilt every run, so the starter never reaches the author's hands

### 4.2 The extension points at a glance

- There are three layers, each with a different guarantee
  - Values: overriding the theme's design values. Fully guaranteed
  - `renderers`: redrawing an element (4.3). The structure cannot be broken
  - `hooks`: arbitrary set and show rules (4.4). Not guaranteed
- The line is drawn by asking whether a decision can contradict another format (HTML, EPUB) on a matter of fact, or break the PDF's structure

### 4.3 renderers

- Six are replaceable: heading, caption, admonition, listing, running-head, page-number
- A renderer receives semantic values, content and the theme — nothing else
- Ids, labels, numbers and alt text are applied by `book.*` outside the renderer, so a theme cannot drop them however it is written

### 4.4 The unguaranteed hook

- `hooks` is a document transform (`doc => doc`). The generated root applies it inside `book.document`, so set and show rules written there win over the library's defaults
- Why the escape hatch is needed: show rules only work in the document flow, they cannot be written in a theme.typ that is imported for its value, and the root file is generated
- Unlike renderers it sits outside the contract: a hook is free to break numbering, labels or PDF/UA

### 4.5 What the heading renderer may do

- The heading renderer alone is styling-only: `book.*` composes the number and the title before the theme sees them
- Why: letting the theme compose them would require `context` inside the heading body, and that breaks PDF/UA title resolution (6.1)

### 4.6 merge-theme

- `merge-theme` merges one level deep
- Why: Typst's dictionary `+` replaces whole values, so `(fonts: (body: ...))` would otherwise drop every other font entry

## 5. Print and PDF standards

### 5.1 Crop marks and bleed

- Crop marks and bleed are drawn physically: Typst can write neither a TrimBox nor an output intent, so drawing them is the only way to say where the trim is
- `crop.sheet: auto` sizes the sheet to trim plus bleed plus mark length
- Naming a paper (`"jis-b5"` and the like) centres the finished page on that standard sheet. This is what Japanese printers ask for, and what review-jsbook's `media=print` produces (an A5 book trimmed out of B5)
- Marks default to registration black. Typst cannot resolve a paper name to dimensions, so the library carries a table of the common trim sizes; anything else is stated with `crop.trim`

### 5.2 Conditions for PDF/A and PDF/UA

- PDF/A-2b and PDF/UA-1 outputs are confirmed to pass veraPDF
- The library's side of conformance is three conditions
  - No `context` in a heading body (it breaks title resolution)
  - The figure API keeps a way to pass alt text through
  - PDF metadata accepts plain text only, so the API takes plain text alongside display content (`title` and `plain-title`, an author's `name` and `plain-name`). PDF/UA requires a title, which makes the split a precondition of conformance

### 5.3 CMYK and conformance modes exclude each other

- CMYK and a conformance mode (PDF/A, PDF/UA) are mutually exclusive, because Typst ships no CMYK ICC profile
- So `with-crop` accepts a colour override, letting the marks fall back to plain black under a conformance mode

### 5.4 PDF/X

- Not supported
- Why: `--pdf-standard` has no value for it, and neither a TrimBox nor an output intent can be written
- To be revisited if upstream supports it

## 6. Things Typst will punish

- The list of things that break the library if its author does not know them

### 6.1 Elements and show rules

- Inside the library, call a standard element with the `std.` prefix when a same-named library function shadows it (`std.figure`, `std.footnote`, `std.table` and so on). Elements with no same-named function (heading, image, link) may be called bare
- No `context` in a heading body (PDF/UA; 4.5). Ordinary content such as a grid is fine — PDF/UA title resolution survives it (verified)
- A heading's body (`heading.body`) is consumed as it is by the running head (`current-titles`) and by the standard `outline`. Changing its shape (composing number and title as a grid, say) leaks into both
  - To hang long chapter titles under their number, keep the body inline and pass the parts to the show rule through a separate channel, changing only what is drawn

### 6.2 Pages and page breaks

- `set page` counts as a change of page setup and forces a break to apply it. A standalone page (cover, title page, colophon) is made directly with the `page()` function
- `pagebreak` has no effect inside a block. A chapter's break belongs in the show rule (3.5)

### 6.3 Paths and labels

- A relative path is resolved against the file it is written in. Paths arriving from the generated code are root-absolute by contract, and the library neither searches for them nor checks that they exist
- Defining the same label twice is an error for the whole document

### 6.4 Miscellany

- The Japanese B5 is `jis-b5`; there is no paper named `b5`
- A figure or table caption goes above or below by `set figure.caption(position: top | bottom)`
