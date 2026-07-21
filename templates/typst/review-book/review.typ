// Re:VIEW adapter.
//
// The API TypstRenderer generates calls to. Every function here maps one
// Re:VIEW semantic element onto the general book API in book.typ; nothing here
// decides layout, and nothing computes a number. Hand-written Typst documents
// should use book.* instead (doc/typst-review-book.md).
//
// Argument conventions (doc/typst-review-book.md):
//   id          str   -- full label, already namespaced as kind:chapter:item
//   number      int   -- the item's number within its chapter, or none
//   number-text content -- the display string TextFormatter produced ("図1.1")
//   caption     content -- caption body, or none when the element has no caption

#import "book.typ"
#import "math.typ": render-math

// ------------------------------------------------------------- structure

#let chapter(id: none, number: none, number-text: none, title: [], toc: true, visible: true) = {
  book.chapter(id: id, number: number-text, title: title, outlined: toc, visible: visible)
}

#let part(id: none, number: none, number-text: none, title: []) = {
  book.part(id: id, number: number-text, title: title)
}

#let section(level: 2, id: none, number-text: none, title: [], toc: true, visible: true) = {
  book.section(level: level, id: id, number: number-text, title: title, outlined: toc, visible: visible)
}

// ---------------------------------------------------------------- blocks

#let figure(
  id: none,
  number-text: none,
  caption: none,
  path: none,
  alt: none,
  width: none,
  height: none,
  scale-ratio: none,
  missing: none,
  caption-top: false,
) = book.figure-block(
  id: id,
  number-text: number-text,
  caption: caption,
  path: path,
  alt: alt,
  width: width,
  height: height,
  scale-ratio: scale-ratio,
  missing: missing,
  caption-top: caption-top,
)

#let table(
  id: none,
  number-text: none,
  caption: none,
  columns: 1,
  header: none,
  rows: (),
  aligns: none,
  caption-top: true,
) = book.table-block(
  id: id,
  number-text: number-text,
  caption: caption,
  columns: columns,
  header: header,
  rows: rows,
  aligns: aligns,
  caption-top: caption-top,
)

// //imgtable: a table whose body is an image, numbered as a table.
#let imgtable(id: none, number-text: none, caption: none, path: none, alt: none, missing: none, caption-top: true) = {
  book.figure-block(
    id: id,
    number-text: number-text,
    caption: caption,
    path: path,
    alt: alt,
    missing: missing,
    caption-top: caption-top,
  )
}

#let listing(
  id: none,
  number-text: none,
  caption: none,
  lang: none,
  code: none,
  body: none,
  line-numbers: false,
  start-line: 1,
) = book.listing(
  id: id,
  number-text: number-text,
  caption: caption,
  lang: lang,
  code: code,
  body: body,
  line-numbers: line-numbers,
  start-line: start-line,
)

#let equation(id: none, number-text: none, caption: none, latex: "") = {
  book.equation(id: id, number-text: number-text, caption: caption, latex: latex)
}

// The eight //note-family blocks plus //column share one implementation and
// differ only by kind (doc/typst-review-book.md).
#let minicolumn(kind: "note", caption: none, body) = {
  book.admonition(kind: kind, caption: caption, body)
}

#let column(id: none, caption: none, level: 3, body) = {
  book.column-block(id: id, caption: caption, level: level, body)
}

#let bullet-list(items: ()) = book.bullet-list(items: items)

#let numbered-list(items: (), start: 1) = book.numbered-list(items: items, start: start)

#let description-list(items: ()) = book.description-list(items: items)

#let quote(kind: "quote", body) = book.quote-block(kind: kind, body)

// ---------------------------------------------------- front and back matter

#let cover(image-path: none, title: none, authors: (), theme: none, force: false) = book.cover(
  image-path: image-path,
  title: title,
  authors: authors,
  theme: theme,
  force: force,
)

#let titlepage(title: none, subtitle: none, authors: (), publisher: none) = book.titlepage(
  title: title,
  subtitle: subtitle,
  authors: authors,
  publisher: publisher,
)

#let toc(title: none, depth: none) = book.toc(title: title, depth: depth)

#let colophon(book-title: none, entries: (), history: (), rights: none) = book.colophon(
  book-title: book-title,
  entries: entries,
  history: history,
  rights: rights,
)

#let aligned(alignment: "center", body) = book.aligned-block(alignment: alignment, body)

#let framed(caption: none, body) = book.framed-block(caption: caption, body)

#let bibpaper(id: none, number: 0, caption: none, body) = {
  book.bibpaper(id: id, number: number, caption: caption, body)
}

// ------------------------------------------------------------- footnotes

#let footnote(id: none, number: none, body) = {
  book.footnote-def(id: id, number: number, body)
}

#let footnote-ref(id: none) = book.footnote-ref(id)

#let endnote-ref(id: none, number: 0) = book.endnote-ref(id: id, number: number)

#let print-endnotes(items: ()) = book.print-endnotes(items: items)

// ------------------------------------------------------------ references

#let reference(target: none, text-content: []) = {
  book.reference(target: target, text-content: text-content)
}

// A reference whose target is outside this document (or deliberately unlinked).
#let plain-reference(text-content: []) = text-content

#let page-ref(target: none) = book.page-ref(target: target)

// -------------------------------------------------------------------- index
//
// @<idx> shows its content and records an entry; @<hidx> records only. The term
// path and its sort key are decided on the Re:VIEW side
// (doc/typst-review-book.md); Typst contributes the page number and nothing else.
#let index-entry(terms: (), sort-key: "") = book.index-entry(terms: terms, sort-key: sort-key)

#let print-index(title: none, columns-count: 2) = book.print-index(
  title: title,
  columns-count: columns-count,
)

// ---------------------------------------------------------------- inline

// Inline code. `raw` takes a string, but Re:VIEW inline content may itself hold
// markup, so this styles content instead of building a raw element.
#let raw-inline(body) = box(text(font: ("Menlo", "Noto Sans Mono CJK JP"), body))

// One entry point for every decoration inline, keyed by Re:VIEW's inline_type.
// Keeping the set closed here mirrors the renderer, which refuses unknown
// inlines rather than passing their content through
// (doc/typst-review-book.md).
#let inline(kind, body) = {
  if kind == "b" or kind == "strong" { strong(body) }
  else if kind == "i" or kind == "em" { emph(body) }
  else if kind == "tt" or kind == "code" { raw-inline(body) }
  else if kind == "ttb" { strong(raw-inline(body)) }
  else if kind == "tti" { emph(raw-inline(body)) }
  else if kind == "u" { underline(body) }
  else if kind == "del" or kind == "strike" { strike(body) }
  else if kind == "ins" or kind == "insert" { underline(body) }
  else if kind == "sup" { super(body) }
  else if kind == "sub" { sub(body) }
  else if kind == "ami" { highlight(body) }
  else if kind == "bou" { emph(body) }
  else if kind == "tcy" { body }
  else if kind == "balloon" { text(size: 0.85em, [⟨#body⟩]) }
  else if kind == "idx" or kind == "hidx" { body }
  else { panic("review.inline: unknown kind " + kind) }
}

#let ruby(base: [], reading: []) = {
  // Typst has no ruby element yet; stack the reading above the base so the base
  // text stays selectable and in the reading order.
  box(baseline: 0pt, {
    stack(
      dir: ttb,
      spacing: 0.1em,
      align(center, text(size: 0.5em, reading)),
      align(center, base),
    )
  })
}

#let kw(term: [], desc: none) = {
  if desc == none { strong(term) } else { [#strong(term)（#desc）] }
}

#let link-to(url: "", body: none) = {
  if body == none { link(url) } else { link(url, body) }
}

#let icon(path: none, missing: none) = {
  if missing != none { text(fill: red, [missing icon: #missing]) } else { box(image(path, height: 1em)) }
}

#let math-inline(latex: "") = render-math(latex, block: false)

#let uchar(code) = str.from-unicode(code)

#let br() = linebreak()

// ------------------------------------------------------- control commands

#let label-target(id: none) = {
  if id != none { [#metadata(id)#label(id)] }
}

#let pagebreak-block() = pagebreak(weak: true)

#let hr() = line(length: 100%, stroke: 0.5pt + luma(150))

#let blankline() = v(1em)

#let comment-block(body) = {
  // Only reachable when config['draft'] is on; the renderer drops it otherwise.
  block(fill: rgb("#fff8dc"), inset: 6pt, width: 100%, text(size: 0.9em, body))
}
