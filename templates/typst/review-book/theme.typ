// Page design (hanmen) -- the values that decide this book's printed page.
//
// The item names and the approach match the Vivliostyle counterpart,
// style-vivliostyle-design.css: a page design can be stated in the same
// vocabulary for either output and the values carry over as they are.
// How each element is typeset lives in book.typ; the text block size and the
// margins are derived from the values here.
//
// Characters per line and lines per page decide the text block. State only
// the head space and the gutter; the foot and fore-edge follow. Widening the
// gutter narrows the fore-edge by the same amount -- the text block itself
// never moves.
//
// About units:
//   Q is 0.25mm, the Japanese typesetting unit for type size (kyu) and line
//   feed (ha). CSS can write it directly; Typst has no Q, so the `Q` function
//   below converts to mm.
//   Do not use pt. TeX's pt (1/72.27 inch) and Typst's pt (1/72 inch) differ
//   by 0.37%, and mixing them up shifts the page.
//
// A renderer receives semantic values and content, with the theme last.
// Ids, labels, numbers and alt text are applied by book.* outside the
// renderer, so a theme cannot drop them.

// The unit for type sizes and line feeds: 13Q is Q(13).
#let Q(n) = n * 0.25mm

// ------------------------------------------------------ default renderers

// Headings decide styling only. book.* has already composed the number and
// the title (a context block in a heading body breaks PDF/UA tagging).
#let default-heading(it, theme) = {
  let scale = if it.level == 1 { theme.text.xlarge } else if it.level == 2 {
    theme.text.large
  } else { theme.text.medium }

  block(
    above: if it.level == 1 { 2.2em } else { 1.6em },
    below: 0.9em,
    text(size: theme.text.size * scale, it),
  )
}

// Joins the number ("図1.1") and the caption body; either may be none.
#let default-caption(number-text, caption, theme) = {
  let joined = if number-text == none and caption == none {
    none
  } else if caption == none {
    number-text
  } else if number-text == none {
    caption
  } else {
    [#number-text: #caption]
  }
  if joined == none { none } else { text(size: theme.text.size * theme.text.small, joined) }
}

#let default-admonition(kind, caption, body, theme) = {
  block(
    fill: theme.colors.at(kind, default: theme.colors.code-bg),
    inset: (x: theme.box.pad-x, y: theme.box.pad-y),
    radius: theme.box.arc,
    width: 100%,
    breakable: true,
    stroke: theme.box.rule + theme.colors.code-border,
    {
      if caption != none { block(below: 0.5em, text(weight: "bold", caption)) }
      body
    },
  )
}

#let default-listing(caption, body, theme) = {
  if caption == none {
    body
  } else {
    block(breakable: true, width: 100%, {
      block(below: 0.4em, caption)
      body
    })
  }
}

// Running head: chapter title on the left, section title on the right, a rule
// underneath. info: page / book-title / chapter-title / section-title / verso
#let default-running-head(info, theme) = {
  if info.chapter-title == none { return none }

  let size = if theme.text.running-head-size == auto { theme.text.size }
             else { theme.text.running-head-size }
  block(width: 100%, {
    block(below: 0.3em, text(
      size: size,
      font: theme.fonts.heading,
      {
        info.chapter-title
        h(1fr)
        if info.section-title != none { info.section-title }
      },
    ))
    if theme.rules.running-head != none {
      line(length: 100%, stroke: theme.rules.running-head)
    }
  })
}

#let default-page-number(number, theme) = text(
  size: if theme.text.folio-size == auto { theme.text.size } else { theme.text.folio-size },
  number,
)

// -------------------------------------------------------- design values

#let default-theme = (
  // --- trim size ----------------------------------------------------------
  paper: "jis-b5",
  binding: "left",
  two-sided: true,

  // --- basic setting ------------------------------------------------------
  // Characters per line (line-length) and lines per page (number-of-lines)
  // decide the text block size.
  text: (
    size: Q(13),                 // body type size (jsbook's 10pt equivalent)
    baselineskip: Q(21.65),      // line feed (jsbook's 15.4pt equivalent)
    line-length: 40,             // characters per line
    number-of-lines: 35,         // lines per page
    // The size ladder, as multiples of the body size.
    xxlarge: 2.5,                // title page
    xlarge: 2.0,                 // chapter headings
    large: 1.4,                  // section headings
    medium: 1.2,                 // subsections, columns
    small: 0.9,                  // captions, tables
    xsmall: 0.8,                 // code, footnotes
    // Running head and folio match the body size (auto), like the LaTeX
    // templates, whose fancyhdr fields carry no size command and are set at
    // the body size. Override with a concrete size to shrink them.
    running-head-size: auto,
    folio-size: auto,
  ),

  // --- margins ------------------------------------------------------------
  // State only the head space and the gutter; the foot and the fore-edge are
  // derived from the text block size.
  margins: (
    head-space: 30mm,            // head (sheet top edge to the text block)
    gutter: 26mm,                // gutter (binding side)
    headsep: 10mm,               // running head to text block
    footskip: 10mm,              // text block to folio
    headheight: 5mm,             // running head height (§2.9)
  ),

  // --- figure spacing (§2 "アキ") -----------------------------------------
  // Space around a float and between a float and its caption. The defaults
  // mirror the LaTeX edition: \intextsep (TeX 12pt) and \abovecaptionskip
  // (TeX 5pt). Both are set in Q-derived millimetres, not pt (§2.4).
  spacing: (
    float-sep: 4.217mm,          // float to body text (\intextsep)
    caption-sep: 1.757mm,        // float to caption (\above/\belowcaptionskip)
  ),

  // --- fonts --------------------------------------------------------------
  // Latin faces first, Japanese after; generic families only at the end.
  // Japanese and Latin are set at the same size (jlreq's default). The
  // jsbook-style 1.081x Latin scaling is not adopted in any output format;
  // if the Latin looks small, pick a face with a larger x-height instead of
  // scaling.
  fonts: (
    body: ("Latin Modern Roman", "CMU Serif", "Times New Roman",
           "Hiragino Mincho ProN", "Yu Mincho", "Noto Serif CJK JP", "IPAexMincho"),
    heading: ("Helvetica Neue", "Helvetica", "Arial",
              "Hiragino Kaku Gothic ProN", "Yu Gothic", "Noto Sans CJK JP", "IPAexGothic"),
    code: ("Latin Modern Mono", "DejaVu Sans Mono", "Menlo", "Noto Sans Mono CJK JP"),
  ),

  // --- colours ------------------------------------------------------------
  colors: (
    foreground: luma(0),
    accent: luma(70),
    code-bg: rgb("#e6e6e6"),      // black!10!white
    code-border: rgb("#b3b3b3"),  // black!30!white
    cmd-bg: rgb("#333333"),       // black!80!white
    cmd-fg: rgb("#ffffff"),
    caption-marker: rgb("#b3b3b3"),
    // Admonition backgrounds, one per kind.
    note: rgb("#e6e6e6"),
    memo: rgb("#e6e6e6"),
    tip: rgb("#eef7ee"),
    info: rgb("#eef2f8"),
    warning: rgb("#fdf6e3"),
    important: rgb("#fdf0f0"),
    caution: rgb("#fdf0f0"),
    notice: rgb("#fdf6e3"),
    column: rgb("#f6f6f6"),
  ),

  rules: (
    running-head: 0.4pt + luma(0),   // set to none to remove the rule
  ),

  // --- box dimensions -----------------------------------------------------
  // Matches tcolorbox's size/normal defaults.
  box: (
    pad-x: 5mm,
    pad-y: 3mm,
    rule: 0.5mm,
    arc: 1mm,
  ),

  // --- miscellany ---------------------------------------------------------
  toc: (depth: 2),
  chapter: (pagebreak: true, start: "any"),
  running-head: (enabled: true),

  // --- crop marks and bleed -----------------------------------------------
  crop: (
    enabled: false,
    // auto: a sheet just big enough for the bleed and the marks.
    // A paper name ("jis-b5", ...): centre the finished page on that
    // standard sheet, which is what Japanese printers usually expect.
    sheet: auto,
    bleed: 3mm,
    mark-length: 10mm,
    stroke: 0.3pt,
    color: none,        // none = registration black (CMYK)
    trim: none,         // state only when paper is not in the dimension table
  ),

  renderers: (
    heading: default-heading,
    caption: default-caption,
    admonition: default-admonition,
    listing: default-listing,
    running-head: default-running-head,
    page-number: default-page-number,
  ),

  // --- unguaranteed hook --------------------------------------------------
  // A document transform (doc => doc). The generated root applies it inside
  // book.document, so set/show rules written here win over the library
  // defaults. The escape hatch exists because show rules only work in the
  // document flow: they cannot be written in an imported theme.typ, and the
  // root file is generated. Unlike renderers, hooks sit outside the parity
  // contract (numbering, labels, PDF/UA).
  hooks: none,
)

// ------------------------------------------------------------ derivation

// The text block: characters x size wide, lines x line feed high.
#let text-block-size(theme) = (
  width: theme.text.size * theme.text.line-length,
  height: theme.text.baselineskip * theme.text.number-of-lines,
)

// Override a theme one level deep. Typst's dictionary `+` replaces whole
// values, so `(fonts: (body: ...))` would otherwise drop every other font
// entry; this keeps them.
#let merge-theme(base, overrides) = {
  let result = base
  for (key, value) in overrides {
    if type(value) == dictionary and key in base and type(base.at(key)) == dictionary {
      result.insert(key, base.at(key) + value)
    } else {
      result.insert(key, value)
    }
  }
  result
}
