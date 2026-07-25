// A minimal hand-written book with review-book. Compile from this directory:
//
//   typst compile minimal.typ
//
// The library is imported by a relative path so the example runs from a copy
// of the package anywhere; an installed package would use
// `#import "@local/review-book:0.1.0": book, default-theme`.

#import "../lib.typ": book, default-theme

#show: book.document.with(
  metadata: (title: [手書きの本], language: "ja"),
  theme: default-theme,
)

// The default folio is an arabic page number; the front matter overrides it to
// roman. Headings are unnumbered until a numbering scheme is set.
#set page(numbering: "i")
= まえがき

前付の本文。ノンブルはローマ数字で出る。

// Main matter: arabic folio, running head, and the Japanese chapter scheme.
#set page(numbering: "1", header: book.running-head())
#counter(page).update(1)
#set heading(numbering: book.heading-numbering)

= 最初の章
本文。図は @fig1 のように参照できる。

#figure(rect(width: 4cm, height: 2cm), caption: [サンプル図]) <fig1>

== 節
節の本文。

// Appendix: restart the chapter counter and letter it ("付録A").
#counter(heading).update(0)
#set heading(numbering: book.appendix-numbering)

= 付録の章
== 付録の節

// Back matter is unnumbered again.
#set heading(numbering: none)

= あとがき
