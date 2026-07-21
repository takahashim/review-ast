# review-book: design of the Typst book library

This document describes the design of `review-book`, the Typst book library
bundled with the gem (`templates/typst/review-book/`). How the code that calls
it is generated is covered by `design-typst.md` (the renderer/maker
specification); this document covers what the library promises.

The Japanese counterpart is `typst-review-book.ja.md`. Comments inside the
library reference this file.

## 1. Purpose and principles

The library typesets books for Typst documents generated from Re:VIEW
manuscripts. Three principles:

**Delegate to Typst's standard elements.** Headings, figures, tables,
footnotes and links are thin wrappers over the standard elements, so the
outline, the PDF tag structure, cross references and future Typst improvements
come from the standard machinery for free.

**Two public API families.**

- **`book.*`** — the stable API for hand-written Typst documents
- **`review.*`** — the compatibility API for the generator (TypstRenderer);
  it delegates to `book.*`

Everything Re:VIEW-specific (how numbers arrive, the eight minicolumn kinds)
is confined to `review.*` and kept out of `book.*`. Two current exceptions:
endnotes and `//bibpaper` live in `book.*` with `review.*` merely delegating,
and the decoration inlines (inline code, ruby, icons, rules) are implemented
directly in `review.*`, styling included (inline code alone reads the theme's
`fonts.code`).

**The library produces no numbers.** Numbers arrive as finished display
strings; the library and the theme may decorate them but never recompute them.
This is what keeps HTML, EPUB and the Typst PDF in agreement. The one
exception is the page reference: page numbers only exist after layout, so they
are resolved with Typst's `query` and the page counter.

## 2. The review.* calling contract

This is the boundary between the generated code and the library; the renderer
generates calls that follow it.

Argument conventions:

- **`id`** — the complete label string (`"fig:ch01:architecture"`). The label
  scheme belongs to the caller; the library never reinterprets it.
- **`number-text`** — the finished display number (`[図1.1]`), as content.
- **`caption`** — the caption body, separate from the number; the separator
  between them belongs to the library (the theme).
- Bodies are content; paths, language names and alt text are str.

Three exceptions: endnotes and `//bibpaper` take an int number and the
library builds the display form (superscript, brackets); endnotes derive a
label on the library side (`id + ":body"`); and `chapter` / `part` also
accept an int `number:` that is currently received but unused.

**`none` and `[]` are distinct.** `caption: none` means "this element has no
caption"; `caption: []` means "it has one and it is empty". The caller omits
an empty caption argument entirely, and the library branches on the argument's
presence.

Tables distinguish header presence under the same discipline: rows are
converted to `std.table.header` only when a header exists, never otherwise.
The tag structure (header-cell accessibility) and the header repetition
across page breaks arise only from that conversion.

For footnotes, forcing the number is the library's half of the bargain:
`footnote-def(number: n)` places `counter(std.footnote).update(n - 1)`
immediately before the footnote, bending Typst's automatic numbering to the
supplied value. Deciding at which reference the body appears is the caller's
half.

## 3. Book structure

**Book parts (front matter, main matter, appendix, back matter) are switched
at the top level of the root file** — `#show: book.frontmatter` and friends in
sequence, never functions wrapping the includes. A `set` inside a function
does not escape to its caller, so the wrapping style cannot vary per-part page
setup (folio format, running heads).

Part title pages are drawn by `review.part`. Both kinds of part reach the same
function: one with its own `.re` file (the renderer generates the call) and
one named only in catalog.yml (the maker generates it).

The book furniture lives in the library, adjusted by the theme:

- With crop marks on, the cover (`cover`) is skipped by default: a press-ready
  body PDF carries no cover, which is submitted separately as spread data
  (front, spine, back) — the same semantics as review-jsbook's `media=print`.
  `cover: true` in config.yml forces one in, as it does there.
- When a cover is rendered, its artwork runs into the bleed; forced under
  crop marks, the page margin keeps the crop-mark area outside the bleed (at
  zero the artwork would sit on the crop marks). Under `crop.sheet: auto`
  that margin equals the mark length; on a named sheet it is wider.
- The colophon (`colophon`) reads title, rule, history, roles, rule, rights,
  aligned to the bottom of the page.
- Running heads put the chapter on the left and the section on the right over
  a rule; folios sit on the outside edge. Both are replaceable through
  `renderers`.
- The chapter page break is issued in the heading show rule, outside the
  block (a `pagebreak` inside a block does nothing).

The index division of labour is: Re:VIEW owns the terms and their sort order;
Typst contributes page numbers. `index-entry` only places a `metadata` mark;
`print-index` collects them with `query` and merges pages per term. Terms
travel as strings, not content — `metadata` values must be plain data, and the
term doubles as the grouping key.

## 4. The theme

The design vocabulary is shared with the Vivliostyle
`style-vivliostyle-design.css`, so a page design can be stated in the same
words for either output and its values carried across.

- **The Q unit** — `Q(13)` = 3.25mm. pt is avoided (TeX's pt differs from
  Typst's by 0.37%).
- **Derived text block** — characters-per-line × size gives the width,
  lines-per-page × baselineskip the height; only the top margin and the gutter
  are specified, the bottom and fore-edge follow.
- **The size scale** — ratios of the body size (xxlarge 2.5 … xsmall 0.8).

**Leading is deterministic.** With `top-edge: 1em, bottom-edge: 0pt` the
baseline distance is exactly 1em + leading. Under the default cap-height
reference it varies per font, and a design value like "21.65Q" would mean
nothing.

Theme extension points are the six `renderers` — heading, caption,
admonition, listing, running-head, page-number — plus one unguaranteed
escape hatch, `hooks`. A renderer receives semantic values, content and the
theme — nothing else. Ids, labels, numbers and alt text are applied by
`book.*` outside the renderer, so a theme cannot drop them.

`hooks` is a document transform (`doc => doc`). The generated root applies it
inside `book.document`, so set/show rules written there win over the library
defaults. It exists because show rules only work in the document flow: they
cannot be written in theme.typ directly (it is imported for its value), and
the root file is generated. Unlike renderers, hooks sit outside the parity
contract — a hook is free to break numbering, labels, or PDF/UA.

The heading renderer alone is styling-only: `book.*` composes the number and
title before the theme sees them. Letting the theme compose the body would
require `context` inside the heading body, and that breaks PDF/UA title
resolution (chapter 6).

`merge-theme` merges one level deep. Typst's dictionary `+` replaces whole
values, so `(fonts: (body: ...))` would otherwise drop every other font entry.

## 5. Print and PDF standards

Crop marks and bleed are drawn physically. Typst can write neither a TrimBox
nor an output intent, so drawing is the only way to communicate the trim.

- `crop.sheet: auto` sizes the sheet to trim + bleed + mark length.
- A paper name (`"jis-b5"`, …) centres the trim on that standard sheet — the
  form Japanese printers ask for, and what review-jsbook's `media=print`
  produces (A5 trimmed out of B5).
- Marks default to registration black. Typst cannot resolve a paper name to
  dimensions, so the library carries a table of the common trim sizes;
  anything else is stated via `crop.trim`.

PDF/A-2b and PDF/UA-1 outputs pass veraPDF. The library's side of conformance:

- no `context` in heading bodies (it breaks title resolution),
- the figure API keeps a way to pass alt text through, and
- PDF metadata accepts plain strings only, so the API takes plain text
  alongside display content (`title` / `plain-title`, an author's `name` /
  `plain-name`). PDF/UA requires a title, so this split is a precondition
  of conformance.

CMYK and conformance modes are mutually exclusive (Typst ships no CMYK ICC
profile), which is why `with-crop` accepts a colour override so the marks can
fall back to plain black under a conformance mode.

PDF/X is not possible: `--pdf-standard` has no value for it, and neither
TrimBox nor an output intent can be written. Revisit when upstream supports
it.

## 6. Typst caveats

Things that break when writing library code without knowing them.

- Call a standard element with the `std.` prefix when a same-named library
  function shadows it (`std.figure`, `std.footnote`, `std.table`, …).
  Elements with no same-named library function (heading, image, link, …) may
  be called bare.
- `set page` forces a page break to apply the new setup. Standalone pages
  (cover, title page, colophon) use the `page()` function form.
- `pagebreak` does nothing inside a block; the chapter break lives in the
  show rule.
- No `context` in heading bodies (PDF/UA; chapter 4). Ordinary content such
  as a grid is fine — PDF/UA title resolution survives it (verified).
- `heading.body` is consumed as-is by the running head (`current-titles`)
  and by the standard `outline`. Changing its shape (e.g. composing number
  and title as a grid) leaks into both. For hanging indentation of long
  chapter titles, keep the body inline and pass the parts to the show rule
  through a separate channel, changing only the rendering.
- Defining the same label twice rejects the whole document.
- Japanese B5 is `jis-b5`; there is no paper named `b5`.
- Relative paths resolve against the containing file. Paths received from the
  generated code are root-absolute by contract; the library neither searches
  for files nor checks their existence.
- Caption position is `set figure.caption(position: top | bottom)`.
