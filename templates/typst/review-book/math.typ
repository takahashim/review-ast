// Math adapter: LaTeX notation to Typst.
//
// //texequation and @<m> carry LaTeX, which Typst's own math syntax does not
// accept. This file is the single place that decides what to do with it, so
// switching engines never touches a generated chapter
// (doc/typst-review-book.md).
//
// This is the OFFLINE DEFAULT: it typesets the LaTeX source verbatim in the
// code font, which is readable and always compiles. TypstMaker replaces this
// file with math-mitex.typ when `typst: {math: mitex}` is configured, which
// needs the mitex package to be available in the Typst package cache.

#let render-math(latex, block: false) = {
  if block {
    std.block(width: 100%, align(center, raw(latex, lang: "latex")))
  } else {
    raw(latex, lang: "latex")
  }
}
