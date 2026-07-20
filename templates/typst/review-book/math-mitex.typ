// Math adapter backed by mitex (LaTeX math in Typst).
//
// TypstMaker copies this over math.typ when `typst: {math: mitex}` is set. It
// needs @preview/mitex in the Typst package cache; the maker checks for it and
// says so rather than letting the first build stall on a fetch
// (doc/typst-review-book.md).
//
// The version is pinned because mitex renamed its inline entry point between
// 0.2.5 and 0.2.7 (mitexinline -> mi), and 0.2.5 no longer compiles under
// Typst 0.15. Raising it means checking both names again.

#import "@preview/mitex:0.2.7": mitex, mi

// mitex takes the LaTeX source as a string or raw block; a plain string is what
// TypstRenderer emits.
#let render-math(latex, block: false) = {
  if block {
    std.block(width: 100%, align(center, mitex(latex)))
  } else {
    mi(latex)
  }
}
