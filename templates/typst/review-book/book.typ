// Book components: the general-purpose book API.
//
// This layer knows about books, not about Re:VIEW. It is the stable API for
// hand-written Typst documents (doc/typst-review-book.md); the Re:VIEW
// adapter in review.typ delegates to it. Everything here wraps a Typst standard
// element (heading / figure / table / raw / footnote / link) so the document
// keeps its structure for the outline, PDF tags and cross references.
//
// Theming works by handing the SEMANTIC values to a theme renderer and wrapping
// whatever it returns in the standard element. The structure -- heading level,
// outline membership, label, figure kind -- is applied here and is therefore
// not something a theme can drop (doc/typst-review-book.md).

#import "theme.typ": default-theme, merge-theme, text-block-size
#import "math.typ": render-math

// The active theme and book metadata, readable from the chapter files without
// threading them through every call.
#let theme-state = state("review-book-theme", default-theme)
#let meta-state = state("review-book-meta", (:))
#let numbering-state = state("review-book-page-numbering", "1")

#let renderer(name) = theme-state.get().renderers.at(name)

#let apply(name, ..args) = context {
  let t = theme-state.get()
  (t.renderers.at(name))(..args, t)
}

// Derive the margins from the text block.
//
// Each axis takes one stated side and derives the other; with neither the axis
// centres (§2.3, the same rule as style-vivliostyle.css). The head space and
// the gutter are stated by default, but a foot-space / fore-edge design states
// the opposite side instead (set the default side to none to drop it). Widening
// the gutter narrows the fore-edge by the same amount -- the text block never
// moves.
#let derived-margins(theme, paper-size) = {
  let block-size = text-block-size(theme)
  let (pw, ph) = paper-size
  let m = theme.margins
  let head = m.at("head-space", default: none)
  let foot = m.at("foot-space", default: none)
  let gutter = m.at("gutter", default: none)
  let fore = m.at("fore-edge", default: none)
  let v-centre = (ph - block-size.height) / 2
  let h-centre = (pw - block-size.width) / 2
  (
    top: if head != none { head } else if foot != none { ph - foot - block-size.height } else { v-centre },
    bottom: if foot != none { foot } else if head != none { ph - head - block-size.height } else { v-centre },
    inside: if gutter != none { gutter } else if fore != none { pw - fore - block-size.width } else { h-centre },
    outside: if fore != none { fore } else if gutter != none { pw - gutter - block-size.width } else { h-centre },
  )
}

// ------------------------------------------------------------ crop marks
//
// A press-ready file is bigger than the book: the sheet carries the finished
// page plus the bleed that gets trimmed away, plus the marks that say where to
// cut. Typst names paper sizes rather than exposing their dimensions, so the
// finished size has to be looked up (or stated in the theme) before the media
// can be enlarged around it.

#let paper-dimensions = (
  "a3": (297mm, 420mm),
  "a4": (210mm, 297mm),
  "a5": (148mm, 210mm),
  "a6": (105mm, 148mm),
  "iso-b5": (176mm, 250mm),
  "iso-b6": (125mm, 176mm),
  "jis-b4": (257mm, 364mm),
  "jis-b5": (182mm, 257mm),
  "jis-b6": (128mm, 182mm),
)

#let trim-size(theme) = {
  if theme.crop.trim != none { return theme.crop.trim }
  let found = paper-dimensions.at(theme.paper, default: none)
  if found == none {
    panic("review-book: crop marks need crop.trim for paper \"" + theme.paper + "\"")
  }
  found
}

// Distance from the sheet edge to the trim box, per axis.
//
// With `sheet: auto` the sheet is just big enough for the bleed and the marks.
// Naming a paper instead puts the finished page in the middle of a standard
// sheet, which is what Japanese printers usually expect and what
// review-jsbook's `media=print` produces (A5 trimmed out of B5).
#let crop-margins(theme) = {
  let c = theme.crop
  let (tw, th) = trim-size(theme)
  if c.sheet == auto {
    let m = c.bleed + c.mark-length
    (x: m, y: m)
  } else {
    let found = paper-dimensions.at(c.sheet, default: none)
    if found == none {
      panic("review-book: unknown crop.sheet \"" + c.sheet + "\"")
    }
    let (sw, sh) = found
    if sw < tw + 2 * c.bleed or sh < th + 2 * c.bleed {
      panic("review-book: crop.sheet is too small for the trim size plus bleed")
    }
    (x: (sw - tw) / 2, y: (sh - th) / 2)
  }
}

// Turn crop marks on or off without editing the theme file, so the same theme
// can produce a screen PDF and a press PDF. `color` overrides the mark colour,
// which is what a conformance mode needs (see crop.color in theme.typ).
#let with-crop(theme, enabled, color: none) = {
  let t = theme
  let updated = theme.crop + (enabled: enabled)
  if color != none { updated.insert("color", color) }
  t.insert("crop", updated)
  t
}

#let crop-marks(theme) = {
  let c = theme.crop
  let (tw, th) = trim-size(theme)
  let m = crop-margins(theme)
  let b = c.bleed
  // Marks may have to be shorter than asked for when the sheet leaves less
  // room than bleed + mark-length.
  let l = calc.min(c.mark-length, m.x - b, m.y - b)
  // Registration black by default, so every plate carries the marks.
  let s = c.stroke + (if c.color != none { c.color } else { cmyk(100%, 100%, 100%, 100%) })

  let seg(x, y, dx, dy) = place(
    top + left,
    dx: x,
    dy: y,
    line(start: (0pt, 0pt), end: (dx, dy), stroke: s),
  )

  // Corner marks: a pair of lines per direction, the inner one on the trim
  // line and the outer one on the bleed line.
  let corner(x-trim, y-trim, x-dir, y-dir) = {
    // Horizontal pair, lying beyond the bleed box on the x side.
    let hx = if x-dir < 0 { x-trim - b - l } else { x-trim + b }
    seg(hx, y-trim, l, 0pt)
    seg(hx, y-trim + y-dir * b, l, 0pt)
    // Vertical pair, lying beyond the bleed box on the y side.
    let vy = if y-dir < 0 { y-trim - b - l } else { y-trim + b }
    seg(x-trim, vy, 0pt, l)
    seg(x-trim + x-dir * b, vy, 0pt, l)
  }

  corner(m.x, m.y, -1, -1)
  corner(m.x + tw, m.y, 1, -1)
  corner(m.x, m.y + th, -1, 1)
  corner(m.x + tw, m.y + th, 1, 1)

  // Centre marks: a line across the mark area with a crossbar, marking the
  // middle of each edge for folding and registration.
  let centre-v(x, y) = {
    seg(x, y, 0pt, l)
    seg(x - l / 4, y + l / 2, l / 2, 0pt)
  }
  let centre-h(x, y) = {
    seg(x, y, l, 0pt)
    seg(x + l / 2, y - l / 4, 0pt, l / 2)
  }
  centre-v(m.x + tw / 2, m.y - b - l)
  centre-v(m.x + tw / 2, m.y + th + b)
  centre-h(m.x - b - l, m.y + th / 2)
  centre-h(m.x + tw + b, m.y + th / 2)
}

// ---------------------------------------------------------------- document

// Wrap the whole document. Applied as `#show: book.document.with(...)`.
#let document(
  metadata: (:),
  theme: default-theme,
  body,
) = {
  let m = (
    title: none,
    plain-title: none,
    subtitle: none,
    authors: (),
    publisher: none,
    language: "ja",
    date: none,
    keywords: (),
  ) + metadata

  theme-state.update(theme)
  meta-state.update(m)

  // std.document, not document: this function shadows the element name.
  set std.document(
    title: if m.plain-title != none { m.plain-title } else { "" },
    // PDF metadata is plain text, so authors carry a plain-name beside the
    // content `name` a title page would typeset.
    author: m.authors.map(a => if type(a) == dictionary { a.at("plain-name", default: "") } else { a }),
    keywords: m.keywords,
  )

  // With crop marks the sheet is larger than the book, so the page is sized
  // explicitly and every margin grows by the same amount -- the text block
  // keeps its position relative to the trim box, not to the sheet.
  let crop-on = theme.crop.enabled
  let extra = if crop-on { crop-margins(theme) } else { (x: 0pt, y: 0pt) }
  // The trim size. Margin derivation uses it even when no marks are drawn.
  let trim = trim-size(theme)
  let sheet = if crop-on {
    (width: trim.at(0) + 2 * extra.x, height: trim.at(1) + 2 * extra.y)
  } else {
    (width: trim.at(0), height: trim.at(1))
  }
  let margins = derived-margins(theme, trim)

  set page(
    ..sheet,
    margin: (
      inside: margins.inside + extra.x,
      outside: margins.outside + extra.x,
      top: margins.top + extra.y,
      bottom: margins.bottom + extra.y,
    ),
    binding: if theme.binding == "right" { right } else { left },
    numbering: none,
    header: none,
    footer: none,
    header-ascent: theme.margins.headsep,
    footer-descent: theme.margins.footskip,
    background: if crop-on { crop-marks(theme) },
  )

  // Make the line feed deterministic. Typst's leading is the gap between
  // line boxes, so pinning the box to 1em makes the baseline distance
  // exactly 1em + leading. The default top-edge is the cap height, which
  // varies per font and would make the line feed unspecifiable.
  set text(
    font: theme.fonts.body,
    size: theme.text.size,
    lang: m.language,
    fill: theme.colors.foreground,
    top-edge: 1em,
    bottom-edge: 0pt,
  )
  set par(
    leading: theme.text.baselineskip - theme.text.size,
    spacing: theme.text.baselineskip - theme.text.size,
    justify: true,
    first-line-indent: 1em,
  )

  // The chapter break lives in the show rule, and outside the block: a
  // pagebreak nested inside a block does not break the page.
  //
  // The theme's heading renderer is applied here rather than inside the heading
  // body, because a context block in the body breaks PDF/UA tagging. `theme` is
  // in scope directly, so no context is needed to reach it.
  show heading: it => {
    let is-chapter = it.level == 1
    if is-chapter and theme.chapter.pagebreak {
      pagebreak(weak: true, to: if theme.chapter.start == "odd" { "odd" })
    }
    set text(font: theme.fonts.heading, weight: "bold")
    (theme.renderers.heading)(it, theme)
  }

  show raw: set text(font: theme.fonts.code, size: theme.text.size * theme.text.xsmall)
  show raw.where(block: true): it => block(
    fill: theme.colors.code-bg,
    stroke: theme.box.rule + theme.colors.code-border,
    radius: theme.box.arc,
    inset: (x: theme.box.pad-x, y: theme.box.pad-y),
    width: 100%,
    breakable: true,
    it,
  )

  show link: set text(fill: theme.colors.accent)

  // Figure spacing from the theme (§2 "アキ"): the gap is the space between a
  // float and its caption (caption-sep); the block spacing is the space to the
  // surrounding body text (float-sep, \intextsep). Without this a figure would
  // use Typst's defaults and the paragraph spacing set above.
  set std.figure(gap: theme.spacing.caption-sep)
  show std.figure: set block(above: theme.spacing.float-sep, below: theme.spacing.float-sep)

  body
}

// ---------------------------------------------------- running heads / folio

// The chapter (and section) in effect at this point, for the running head.
#let current-titles() = {
  let page-now = here().page()
  let visible = h => h.location().page() <= page-now
  let chapters = query(heading.where(level: 1)).filter(visible)
  let sections = query(heading.where(level: 2)).filter(visible)
  (
    chapter-title: if chapters.len() > 0 { chapters.last().body } else { none },
    section-title: if sections.len() > 0 { sections.last().body } else { none },
  )
}

#let running-head() = context {
  let t = theme-state.get()
  if not t.running-head.enabled { return none }

  let titles = current-titles()
  let page-now = here().page()
  let verso = calc.even(page-now)
  let info = (
    page: page-now,
    book-title: meta-state.get().at("title", default: none),
    chapter-title: titles.chapter-title,
    section-title: titles.section-title,
    verso: verso,
  )
  // The renderer gets the whole width and decides what goes where; it knows
  // which side of the spread it is on from info.verso.
  let content = (t.renderers.running-head)(info, t)
  if content == none { return none }

  // Reserve a fixed running-head height (§2.9 headheight) so the text block
  // position does not shift with the running head's content.
  block(width: 100%, height: t.margins.headheight, content)
}

// The folio sits on the outside edge of a two-sided book, so it stays visible
// when the reader thumbs through; a single-sided book centres it.
#let folio() = context {
  let t = theme-state.get()
  let number = (t.renderers.page-number)(counter(page).display(numbering-state.get()), t)
  let placement = if not t.two-sided {
    center
  } else {
    let odd = calc.odd(here().page())
    if t.binding == "right" {
      if odd { left } else { right }
    } else {
      if odd { right } else { left }
    }
  }
  align(placement, number)
}

// ------------------------------------------------------------- book parts
//
// Each part is applied at the TOP LEVEL of the root file, not as a wrapper
// around an include. A `set` inside a function only affects the content that
// function returns, so wrapping each part in its own function call is what lets
// page numbering and heading rules differ per part (the lyceum lesson recorded
// in doc/typst-review-book.md / appendix C).

#let frontmatter(body) = {
  numbering-state.update("i")
  set page(footer: folio(), header: none)
  counter(page).update(1)
  body
}

#let mainmatter(body) = {
  numbering-state.update("1")
  set page(footer: folio(), header: running-head())
  counter(page).update(1)
  body
}

#let appendix(body) = { body }

#let backmatter(body) = { body }

// --------------------------------------------------------------- headings

// A heading numbering scheme for a hand-written document (not the Re:VIEW
// path, which supplies its own numbers). A book styled by this library can
// turn on native Typst numbering with
//
//   #set heading(numbering: book.heading-numbering)
//
// and write plain `= 章` / `== 節` headings: the theme's heading renderer
// shows whatever number the heading carries, so a supplied number (Re:VIEW,
// numbering: none) and an auto number look the same. Level 1 is a Japanese
// chapter ("第1章"), deeper levels are the dotted path ("1.1", "1.1.1").
#let heading-numbering(..nums) = {
  let n = nums.pos()
  if n.len() == 1 { "第" + str(n.first()) + "章" } else { n.map(str).join(".") }
}

// A chapter heading. `number` is display text supplied by the caller; the
// numbering itself is never computed here.
// The heading body is plain content, never a context block. Typst reads the
// body to fill in the PDF/UA tag tree, and a context block there makes the
// title undeterminable ("PDF/UA-1 error: heading title could not be
// determined"). Theming therefore happens in a show rule, where context is
// allowed -- see document().
#let chapter(id: none, number: none, title: [], outlined: true, visible: true) = {
  if not visible {
    return hide(heading(level: 1, numbering: none, outlined: true, title))
  }
  let body = if number != none { [#number#h(0.8em)#title] } else { title }
  let h = heading(level: 1, numbering: none, outlined: outlined, body)
  if id != none { [#h#label(id)] } else { h }
}

// A part title. Parts sit above chapters in Re:VIEW's structure, but Typst
// headings start at level 1 and chapters already use it, so a part is a level-1
// heading distinguished by its own styling rather than by depth.
#let part(id: none, number: none, title: []) = {
  let body = if number != none { [#number#linebreak()#title] } else { title }
  let h = {
    pagebreak(weak: true)
    v(6em)
    align(center, heading(level: 1, numbering: none, outlined: true, text(size: 1.6em, body)))
  }
  if id != none { [#h#label(id)] } else { h }
}

#let section(level: 2, id: none, number: none, title: [], outlined: true, visible: true) = {
  if not visible {
    return hide(heading(level: level, numbering: none, outlined: true, title))
  }
  let body = if number != none { [#number#h(0.5em)#title] } else { title }
  let h = heading(level: level, numbering: none, outlined: outlined, body)
  if id != none { [#h#label(id)] } else { h }
}

// ------------------------------------------------------- caption assembly

#let caption-content(number-text, caption) = {
  if number-text == none and caption == none { return none }
  apply("caption", number-text, caption)
}

// ---------------------------------------------------------------- figures

#let figure-block(
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
) = {
  let content = if missing != none {
    block(
      stroke: 0.5pt + red,
      inset: 8pt,
      width: 100%,
      text(fill: red, [missing image: #missing]),
    )
  } else if scale-ratio != none {
    scale(image(path, alt: alt), x: scale-ratio * 100%, y: scale-ratio * 100%)
  } else {
    image(
      path,
      alt: alt,
      width: if width != none { width } else { auto },
      height: if height != none { height } else { auto },
    )
  }

  let fig = {
    set std.figure.caption(position: if caption-top { top } else { bottom })
    std.figure(
      content,
      caption: caption-content(number-text, caption),
      supplement: none,
      numbering: none,
      kind: "review-figure",
    )
  }

  if id != none { [#fig#label(id)] } else { fig }
}

// ----------------------------------------------------------------- tables

#let table-block(
  id: none,
  number-text: none,
  caption: none,
  columns: 1,
  header: none,
  rows: (),
  aligns: none,
  caption-top: true,
) = {
  let cells = ()
  if header != none {
    cells.push(std.table.header(..header))
  }
  for row in rows {
    for cell in row {
      cells.push(cell)
    }
  }

  let t = std.table(
    columns: columns,
    align: if aligns != none { (col, _) => aligns.at(col, default: left) } else { left },
    ..cells,
  )

  let fig = {
    set std.figure.caption(position: if caption-top { top } else { bottom })
    std.figure(
      t,
      caption: caption-content(number-text, caption),
      supplement: none,
      numbering: none,
      kind: "review-table",
    )
  }
  if id != none { [#fig#label(id)] } else { fig }
}

// ------------------------------------------------------------------ lists

#let bullet-list(items: ()) = std.list(..items)

#let numbered-list(items: (), start: 1) = std.enum(start: start, ..items)

#let description-list(items: ()) = std.terms(
  ..items.map(pair => std.terms.item(pair.at(0), pair.at(1))),
)

// --------------------------------------------------------------- listings

#let listing(
  id: none,
  number-text: none,
  caption: none,
  lang: none,
  code: none,
  body: none,
  line-numbers: false,
  start-line: 1,
) = {
  let source = if code != none {
    raw(code, lang: lang, block: true)
  } else if body != none {
    body
  } else {
    raw("", block: true)
  }

  let shown = if line-numbers and code != none {
    let lines = code.split("\n")
    let width = str(start-line + lines.len() - 1).len()
    block(
      fill: luma(245),
      inset: 6pt,
      width: 100%,
      breakable: true,
      for (i, line) in lines.enumerate() {
        let n = str(start-line + i)
        raw(" " * (width - n.len()) + n + ": " + line, lang: lang)
        linebreak()
      },
    )
  } else { source }

  let content = apply("listing", caption-content(number-text, caption), shown)
  if id != none { [#content#label(id)] } else { content }
}

// ------------------------------------------------------------ admonitions

#let admonition(kind: "note", caption: none, breakable: true, body) = {
  apply("admonition", kind, caption, body)
}

// A column is a book structure, not just a decorated note: it takes an outline
// entry of its own.
#let column-block(id: none, caption: none, level: 3, outlined: true, body) = {
  let content = {
    if caption != none and outlined {
      // The column's outline entry. Taken out of the flow with place() so it
      // contributes to the outline and the PDF structure without printing a
      // second title or reserving vertical space.
      place(hide(heading(level: level, numbering: none, outlined: true, caption)))
    }
    admonition(kind: "column", caption: caption, body)
  }
  if id != none { [#content#label(id)] } else { content }
}

// ----------------------------------------------------------------- quotes

#let quote-block(kind: "quote", body) = {
  if kind == "lead" or kind == "read" {
    block(inset: (left: 1em, right: 1em), above: 1em, below: 1em, emph(body))
  } else {
    block(inset: (left: 1.5em), above: 1em, below: 1em, body)
  }
}

#let aligned-block(alignment: "center", body) = {
  let a = if alignment == "right" { right } else if alignment == "left" { left } else { center }
  block(width: 100%, align(a, body))
}

#let framed-block(caption: none, body) = {
  block(
    stroke: 0.5pt + luma(120),
    inset: 8pt,
    width: 100%,
    breakable: true,
    {
      if caption != none { block(below: 0.5em, text(weight: "bold", caption)) }
      body
    },
  )
}

// ------------------------------------------------------------- references

// A reference whose display text was decided by the caller. `link` rather than
// `ref`, because the number shown must be the one supplied, not one Typst
// derives (doc/typst-review-book.md).
#let reference(target: none, text-content: []) = {
  if target == none { text-content } else { link(label(target), text-content) }
}

// A page reference. The page is only known after layout, so this is the one
// place where a number is read from Typst rather than supplied by Re:VIEW --
// there is no Re:VIEW-side page number to be authoritative.
#let page-ref(target: none) = context {
  let found = query(label(target))
  if found.len() == 0 {
    text(fill: red, [??])
  } else {
    link(label(target), [#counter(page).at(found.first().location()).first()])
  }
}

// -------------------------------------------------------------- footnotes

// A footnote whose number is supplied. Setting the counter just before the
// footnote makes Re:VIEW's number the one that prints, so PDF, HTML and EPUB
// agree even when a //footnote is defined but never referenced.
#let footnote-def(id: none, number: none, body) = {
  if number != none { counter(std.footnote).update(number - 1) }
  let f = std.footnote(body)
  if id != none { [#f#label(id)] } else { f }
}

#let footnote-ref(id) = std.footnote(label(id))

// Endnotes are not Typst footnotes: they collect at //printendnotes.
#let endnote-ref(id: none, number: 0) = {
  let mark = super([#number])
  if id != none { link(label(id + ":body"), mark) } else { mark }
}

#let print-endnotes(items: ()) = {
  if items.len() == 0 { return }
  block(above: 1.5em, {
    for item in items {
      block(
        below: 0.5em,
        [#super([#item.number])#h(0.4em)#item.body#label(item.id + ":body")],
      )
    }
  })
}

// ---------------------------------------------------------- bibliography

#let bibpaper(id: none, number: 0, caption: none, body) = {
  let content = block(below: 0.8em, {
    [\[#number\]#h(0.4em)]
    if caption != none { caption }
    if body != none { body }
  })
  if id != none { [#content#label(id)] } else { content }
}

// -------------------------------------------------------------- equations

#let equation(id: none, number-text: none, caption: none, latex: "") = {
  let eq = render-math(latex, block: true)
  let cap = caption-content(number-text, caption)
  let content = if cap == none {
    eq
  } else {
    block(width: 100%, { eq; block(above: 0.4em, align(center, cap)) })
  }
  if id != none { [#content#label(id)] } else { content }
}

// ------------------------------------------------------------------ index
//
// Re:VIEW decides what a term is and how it sorts ; Typst only finds out
// what page each mark landed on.

#let index-entry(terms: (), sort-key: "") = [
  #metadata((terms: terms, sort-key: sort-key))#label("review-index-entry")
]

#let print-index(title: none, columns-count: 2) = context {
  let marks = query(<review-index-entry>)
  if marks.len() == 0 { return }


  // term path -> (sort-key, pages)
  let groups = (:)
  for mark in marks {
    let value = mark.value
    let key = value.terms.join("\u{0}")
    let page-no = counter(page).at(mark.location()).first()
    let existing = groups.at(key, default: (sort-key: value.sort-key, terms: value.terms, pages: ()))
    if not existing.pages.contains(page-no) {
      existing.pages.push(page-no)
    }
    groups.insert(key, existing)
  }

  let sorted = groups.values().sorted(key: g => (g.sort-key, g.terms.join("\u{0}")))

  if title != none { heading(level: 1, numbering: none, outlined: true, title) }

  let body = for group in sorted {
    let depth = group.terms.len() - 1
    block(
      below: 0.2em,
      inset: (left: depth * 1em),
      [#group.terms.last()#h(0.5em)#group.pages.sorted().map(p => str(p)).join(", ")],
    )
  }

  if columns-count > 1 { std.columns(columns-count, body) } else { body }
}

// ------------------------------------------------------- front and back matter

#let cover(image-path: none, title: none, authors: (), theme: none, force: false) = {
  // A press-ready body PDF carries no cover: the cover is submitted to the
  // printer as separate spread data (front, spine, back). So when crop marks
  // are on, the cover page is skipped by default -- the same semantics as
  // review-jsbook's media=print, whose cover=true likewise forces one in.
  if theme != none and theme.crop.enabled and not force { return }

  // Cover art has to run into the bleed, so its page keeps just enough margin
  // to sit on the trim box plus the bleed -- not zero, which would spill over
  // the crop marks.
  let margin = if theme != none and theme.crop.enabled {
    let m = crop-margins(theme)
    (x: m.x - theme.crop.bleed, y: m.y - theme.crop.bleed)
  } else { 0pt }

  // page(...) as a function, not `set page`: a set rule changes the page setup
  // from here on and forces a break to apply it, which left a blank sheet in
  // front of the cover. The function form makes exactly one page.
  page(margin: margin, header: none, footer: none, {
    if image-path != none {
      image(image-path, width: 100%, height: 100%, fit: "cover")
    } else {
      align(center + horizon, {
        if title != none { text(size: 2em, weight: "bold", title) }
        if authors.len() > 0 {
          v(2em)
          text(size: 1.1em, authors.map(a => a.name).join(", "))
        }
      })
    }
  })
}

#let titlepage(title: none, subtitle: none, authors: (), publisher: none) = {
  page(header: none, footer: none, align(center, {
    v(6em)
    if title != none { text(size: 1.9em, weight: "bold", title) }
    if subtitle != none {
      v(0.8em)
      text(size: 1.2em, subtitle)
    }
    v(4em)
    if authors.len() > 0 { text(size: 1.1em, authors.map(a => a.name).join(", ")) }
    v(1fr)
    if publisher != none { text(size: 1em, publisher) }
    v(3em)
  }))
}

#let toc(title: none, depth: none) = context {
  let t = theme-state.get()
  let d = if depth != none { depth } else { t.toc.depth }
  if title != none { heading(level: 1, numbering: none, outlined: false, title) }
  outline(title: none, depth: d, indent: auto)
  pagebreak(weak: true)
}

// The colophon.
//
// The book title set large, then a rule, the publication history and the
// people involved, then one more rule and the rights notice -- the same
// composition as the LaTeX colophon (review-jsbook). No "奥付" heading is
// printed: the page speaks for itself, and the LaTeX version prints none
// either.
//
// entries: an array of (label, value). history is an array of strings;
// rights is content.
#let colophon(book-title: none, entries: (), history: (), rights: none) = context {
  let t = theme-state.get()
  page(header: none, footer: none, {
    // Push to the bottom of the page: the customary place for a colophon,
    // and where the LaTeX version puts it.
    v(1fr)

    if book-title != none {
      block(below: 0.6em, text(size: t.text.size * t.text.large, weight: "bold", book-title))
    }
    line(length: 100%, stroke: 1pt + t.colors.foreground)
    v(1.2em)

    for line in history { block(below: 0.3em, line) }
    if history.len() > 0 { v(0.8em) }

    // Even out the label column so "著　者" and "発行所" start their values
    // at the same position.
    grid(
      columns: (auto, 1fr),
      column-gutter: 1em,
      row-gutter: 0.5em,
      ..entries.map(entry => (entry.at(0), entry.at(1))).flatten(),
    )

    if rights != none {
      v(1.2em)
      line(length: 100%, stroke: 1pt + t.colors.foreground)
      v(0.8em)
      rights
    }
  })
}
