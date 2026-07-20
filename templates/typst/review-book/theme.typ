// 版面設計 — この本の紙面を決める値
//
// 項目名と考え方は Vivliostyle 版の style-vivliostyle-design.css に合わせてある。
// どちらの出力でも同じ言葉で版面を設計でき、値をそのまま移せる。
// 「どの要素をどう組むか」の実装は book.typ にあり、版面の大きさや余白は
// ここの値から導出される。
//
// 字詰めと行数が版面の大きさを決める。天とノドだけを指定すれば、地と小口は
// そこから導出される。ノドを広げれば小口が同じだけ狭くなり、版面は動かない。
//
// 単位について:
//   Q は 0.25mm。日本語組版で級数と歯送りに使う単位で、CSS 版はそのまま
//   書ける。Typst に Q はないので、下の `Q` 関数で mm に直して使う。
//   pt は使わない。TeX の pt(1/72.27インチ)と Typst の pt(1/72インチ)は
//   0.37% 違い、取り違えると紙面がずれるため。
//
// レンダラは意味値と content だけを受け取り、最後にテーマを受け取る。
// ID・ラベル・番号・代替テキストは book.* がレンダラの外側で付けるので、
// テーマがそれらを落とすことはできない。

// 級数・歯送りを書くための単位。13Q は Q(13)。
#let Q(n) = n * 0.25mm

// ------------------------------------------------------------ 既定レンダラ

// 見出しは体裁だけを決める。番号とタイトルの組み立ては book.* が済ませている
// (見出し本文に context を入れると PDF/UA のタグ付けが壊れるため)。
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

// 番号("図1.1")とキャプション本文をつなぐ。どちらも none がありうる。
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

// 柱。章名を左、節名を右に並べ、下に罫を引く。
// info: page / book-title / chapter-title / section-title / verso
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

// ------------------------------------------------------------------ 設計値

#let default-theme = (
  // --- 判型 ---------------------------------------------------------------
  paper: "jis-b5",
  binding: "left",
  two-sided: true,

  // --- 基本の組み ---------------------------------------------------------
  // 字詰め(line-length)と行数(number-of-lines)が版面の大きさを決める。
  text: (
    size: Q(13),                 // 本文の級数(jsbook の 10pt 相当)
    baselineskip: Q(21.65),      // 行送り(jsbook の 15.4pt 相当)
    line-length: 40,             // 字詰め(1行の字数)
    number-of-lines: 35,         // 1ページの行数
    // 級数表。本文級数の倍率で表す。
    xxlarge: 2.5,                // 大扉
    xlarge: 2.0,                 // 章見出し
    large: 1.4,                  // 節見出し
    medium: 1.2,                 // 小見出し・コラム
    small: 0.9,                  // キャプション・表
    xsmall: 0.8,                 // コード・脚注
    // 柱とノンブルは本文と同寸(auto)。LaTeX 版(fancyhdr にサイズ指定がなく
    // 本文級数で組まれる)に合わせた。実寸で上書きしてもよい。
    running-head-size: auto,
    folio-size: auto,
  ),

  // --- 余白 ---------------------------------------------------------------
  // 天とノドだけを指定する。地と小口は版面の大きさから導出される。
  margins: (
    head-space: 30mm,            // 天(用紙上端から版面まで)
    gutter: 26mm,                // ノド(綴じ側)
    headsep: 10mm,               // 柱と版面のアキ
    footskip: 10mm,              // 版面とノンブルのアキ
  ),

  // --- 書体 ---------------------------------------------------------------
  // 欧文を先、和文を後に並べる。総称は末尾にだけ置く。
  // 和欧は同寸で組む(jlreq の既定と同じ)。jsbook 流の欧文 1.081 倍補正は
  // 全出力形式で採らないことにした。欧文が小さく見えるときは
  // 倍率ではなく x-height の大きい書体を選ぶ。
  fonts: (
    body: ("Latin Modern Roman", "CMU Serif", "Times New Roman",
           "Hiragino Mincho ProN", "Yu Mincho", "Noto Serif CJK JP", "IPAexMincho"),
    heading: ("Helvetica Neue", "Helvetica", "Arial",
              "Hiragino Kaku Gothic ProN", "Yu Gothic", "Noto Sans CJK JP", "IPAexGothic"),
    code: ("Latin Modern Mono", "DejaVu Sans Mono", "Menlo", "Noto Sans Mono CJK JP"),
  ),

  // --- 色 -----------------------------------------------------------------
  colors: (
    foreground: luma(0),
    accent: luma(70),
    code-bg: rgb("#e6e6e6"),      // black!10!white
    code-border: rgb("#b3b3b3"),  // black!30!white
    cmd-bg: rgb("#333333"),       // black!80!white
    cmd-fg: rgb("#ffffff"),
    caption-marker: rgb("#b3b3b3"),
    // 注記の地色。kind ごとに引く。
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
    running-head: 0.4pt + luma(0),   // none にすれば消える
  ),

  // --- 囲みの寸法 ---------------------------------------------------------
  // tcolorbox の size/normal 既定値に対応
  box: (
    pad-x: 5mm,
    pad-y: 3mm,
    rule: 0.5mm,
    arc: 1mm,
  ),

  // --- そのほか -----------------------------------------------------------
  toc: (depth: 2),
  chapter: (pagebreak: true, start: "any"),
  running-head: (enabled: true),

  // --- トンボと裁ち落とし -------------------------------------------------
  crop: (
    enabled: false,
    // auto: 塗り足しとトンボが載るだけの用紙。
    // 判型名("jis-b5" など): その標準用紙の中央に仕上がりを置く。
    // 日本の印刷所は後者を求めることが多い。
    sheet: auto,
    bleed: 3mm,
    mark-length: 10mm,
    stroke: 0.3pt,
    color: none,        // none = レジストレーションブラック(CMYK)
    trim: none,         // paper が寸法表にないときだけ指定する
  ),

  renderers: (
    heading: default-heading,
    caption: default-caption,
    admonition: default-admonition,
    listing: default-listing,
    running-head: default-running-head,
    page-number: default-page-number,
  ),

  // --- 保証外フック -------------------------------------------------------
  // 文書変換関数(doc => doc)。生成された root が book.document の内側で
  // 適用するので、ここに書いた set / show はライブラリの既定に勝つ。
  // show rule は文書フローにしか効かず、import される theme.typ に直接は
  // 書けないため、この出口を設けている。renderers と違い、契約
  // (番号・ラベル・PDF/UA)の保証外である。
  hooks: none,
)

// ------------------------------------------------------------------ 導出

// 版面の大きさ。字詰め × 級数、行数 × 行送り。
#let text-block-size(theme) = (
  width: theme.text.size * theme.text.line-length,
  height: theme.text.baselineskip * theme.text.number-of-lines,
)

// テーマを1段だけ再帰的に上書きする。
// Typst の辞書の `+` は値ごと差し替えるので、(fonts: (body: ...)) と書くと
// 他の書体指定が消える。それを避ける。
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
