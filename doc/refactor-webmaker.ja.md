# AST ベース webmaker の再生

本体の webmaker は使いやすいドキュメントが生成できないためメンテされていない。
本項目は、その原因を実測で特定し、AST レンダラと 2026 年時点の Web 標準を使って、手書き JavaScript をほぼゼロに保ったまま現代的な書籍サイト生成として再生する計画を記す。
項目 8 の EPUB 移植と同じ maker 差し替え面を触るため、その予行を兼ねる。

### 問題(本体 webmaker の実測、review 5.11.0)

生成物の骨格は悪くない。
`webmaker.rb` は章ごとの HTML、サイドバー目次(`nav.side-content`)、前後章ナビという 2 ペイン構成を ERB レイアウト(`templates/web/html/layout-html5.html.erb`)で組み立てる。
品質の低さは骨格ではなく、次の欠落に集約される。

- **レイアウトに対応する CSS が同梱されていない**。
  既定の style.css(494 行)には `.side-content` / `.book-toc` / `.book-body` / `@media` が 1 件もなく、テンプレートが前提とする 2 ペイン構成が素の状態では成立しない。
  これが見た目の貧弱さの最大の原因である。
- **head に viewport meta がなく**、モバイルでレスポンシブ表示にならない。
  テンプレートは XHTML 時代の書き方(`<?xml?>` 宣言、xmlns 属性)を残す。
- **目次が章レベルまで**。
  `WEBTOCPrinter` は part と chapter のみを出力し(`@upper = 1`)、節以下は目次に出ない。

つまり「HTML 構造は使えるが、スタイルと head が 2010 年代前半で止まっている」状態であり、直すべき場所は明確である。

### 前提: 2026 年の Web 標準で JS なしに賄える範囲

書籍サイトに必要な機能を JS の要否で仕分けする(2026-07 時点の Baseline 状況)。

- **CSS と宣言的 HTML だけで済むもの**:
  レスポンシブ 2 ペイン(grid、container queries、`:has()`。いずれも fallback 不要の水準)、
  モバイルの目次ドロワー(`popover` 属性、`<details>`)、
  脚注ポップアップ(CSS anchor positioning。2026-01 の Firefox 147 で Baseline 入り。画面外回避の `@position-try` のみ Safari 18.4+ 要件のため既定位置を持たせる)、
  ページ間遷移(cross-document view transitions。`@view-transition { navigation: auto }` の 1 行で、未対応ブラウザでは瞬時切り替えに劣化するだけ)、
  先読み(Speculation Rules。宣言的 JSON でありロジックを書く JS ではない)、
  ダークモード(`color-scheme` + `light-dark()`)、
  読書進捗バー(scroll-driven animations)、
  日本語組版(`text-wrap: pretty`、`word-break: auto-phrase` は Chrome 系のみだが劣化しても無害)。
- **ビルド時に済ませて表示側 JS をゼロにできるもの**:
  コードハイライト(Re:VIEW は既にビルド時ハイライトのクラス出力を持つ。CSS を当てるだけ)。
- **当面見送るもの**:
  目次のスクロール追従ハイライト。
  CSS の scroll-marker 系がこの用途だが現状 Chrome 系のみであり、「なし」か数十行の JS かの選択になる。まずは「なし」とする。

要するに、手書き JS ゼロで現代的な書籍サイトが成立する。

### 設計

- **maker は既存パターンの複製**:
  `class WebMaker < ReVIEW::WEBMaker` を作り、converter 生成箇所を override して `RendererConverterAdapter`(pdf / text / idgxml maker と同型)で `HtmlRenderer` を差す。
  `HtmlRenderer` には既に webmaker 用のレイアウト解決分岐(`config.maker == 'webmaker'` で `layout-web.html.erb` を探す)が実装済みである。
- **テンプレートと CSS の刷新は本体を汚さずに行う**:
  webmaker には元々「`layouts/layout-web.html.erb` があればユーザ版を優先する」上書き機構があるため、review-ast 側がモダンな既定レイアウトと CSS を同梱しても本体のテンプレート契約と衝突しない。
  ここが本項目の作業の本体であり、実装というよりデザイン作業である。
  同梱 CSS は上記「JS なしに賄える範囲」の機能を実装し、Baseline 未達の機能(anchor positioning の一部、cross-document view transitions)はすべて「欠けても機能が損なわれない」progressive enhancement として書く。
- **深い目次は AST から生成する**:
  `WEBTOCPrinter` の章止まり目次に対し、AST は見出しノードと番号(`definition_number` と同系の番号付け)を既に持つ。
  節レベルまでの目次ツリーを AST の走査で生成し、builder 経路では作りにくかった改善を最初から出す。
- **位置づけ**:
  webmaker には PDF のような厳密パリティのオラクルがない。
  したがって本項目は「本体 webmaker と同一出力」を目標にせず、AST ならではの改善を最初から出す、このプロジェクトで初めての攻めの出力先とする。
  パリティ第一の他項目とは検証方針が異なる(後述)。

### 移行手順

1. `command/web_maker.rb` を pdf / text / idgxml と同型で追加し、まず本体テンプレートのまま HtmlRenderer 経路で全章 HTML が出ることを確認する(骨格の確立)。
2. モダンな既定レイアウト(viewport、`color-scheme`、セマンティック HTML)と 2 ペイン CSS を同梱し、素の状態で成立する見た目にする(最小の再生)。
3. AST 走査による節レベル目次を導入する。
4. progressive enhancement 群(popover ドロワー、anchor positioning 脚注、view transitions、Speculation Rules、進捗バー)を CSS と宣言的 HTML だけで足す。

### 検証

パリティのオラクルがないため、検証は「本文の正しさ」と「生成物の健全性」に分けて考える。

- **本文の正しさは既存の HTML パリティに相乗りする**:
  本文 HTML は builder 等価テストを通る `HtmlRenderer` が生成するため、章本文の描画は既存の比較スイートで守られている。
  webmaker 固有の検証対象はレイアウト、目次、ナビゲーションに限られる。
- 生成物の健全性: 全章の HTML が valid であること(HTML チェッカを CI で回す)、章間リンクと目次リンクが全て解決すること(リンクチェッカ)。
- 手書き JS ゼロの維持を lint 水準で検査する(同梱ファイルに `<script>` が Speculation Rules 以外に存在しないこと)。
- スタイルの検証は自動化しない。
  `samples/syntax-book` と `samples/sample-book` の生成サイトを目視確認の基準フィクスチャとする。

### 実施時期

項目 8 の手順 6(EPUB 移植)より先に着手してよい。
maker 差し替えの面は同じであり、オラクル不在の webmaker で先に骨格(手順 1)を通しておくと、EPUB 移植の予行になる。

### 実装状況（2026-07 時点）

- 実装済み(手順 1: maker 骨格 = HtmlRenderer 経路で全章 HTML)
  - `ReVIEW::AST::Command::WebMaker < ReVIEW::WEBMaker`(`bin/review-ast-webmaker`、gemspec 登録)を追加。基底 WEBMaker が `@converter` を使うのは build_chap の 1 箇所だけなので、そこを override して `@converter` を AST アダプタ(`AstHtmlConverter`)へ差し替えるのみ。index/titlepage/part ページ、stylesheet・画像コピーは基底のまま。EPUB 移植と同型で、両者は `AstHtmlConverter`(`command/ast_html_converter.rb`)を共有する。
  - HtmlRenderer は `config.maker == 'webmaker'` で web レイアウト(`layout-web.html.erb`)を選ぶ既存分岐を持つ。今回 post_process にサイドバー目次 `@toc = WEBTOCPrinter.book_to_string(@book)`(webmaker 時のみ)を追加し、フルページ描画が web レイアウトの変数要件(@toc/@next/@prev/@book/@body_ext/@javascripts)を満たすようにした。深い目次(手順 3)は未実施で、現状は本体同等の part/chapter レベル目次。
  - 実測: legacy `review-webmaker` と生成サイトを比較。ファイル一覧完全一致。index/appA/bib/part/CSS/画像は byte 一致(= サイドバー目次・前後ナビ・レイアウトが正しい)。差は ch01-03.html のみで、HtmlRenderer 既知の rendered-equivalent 差(ブロック間空白・`<dl>` 改行)。本体テンプレートのまま骨格が通った。
- 実装済み(手順 2: モダン既定レイアウト + 2 ペイン CSS の同梱)
  - review-ast 側に `templates/web/html/layout-html5.html.erb`(セマンティック HTML5、`<!DOCTYPE html>`、viewport、`color-scheme`、`<aside>` サイドバー + `<main>` 本文 + `<nav>` 前後送り、skip link)と `templates/web/html/review-ast-web.css`(レスポンシブ 2 ペイン grid、ダークモード = `light-dark()`、可読タイポグラフィ、コード/脚注/ナビのスタイル、モバイルは `popover` 属性の目次ドロワー)を同梱。`ReVIEW::AST::WebAssets` がパスを提供。
  - バインディング契約は gem の web layout と同一(@body/@toc/@next/@prev/@book/@title/@stylesheets/@language/@body_ext/@javascripts)なので drop-in。
  - 配線: HtmlRenderer.layoutfile の webmaker フォールバックを `WebAssets::LAYOUT_HTML5` へ(EPUB/plain HTML は gem テンプレートのまま)。WebMaker は (a) `template_name` を override して index/titlepage/part のフルページも同じ modern layout に、(b) `copy_stylesheet` を override して同梱 CSS を webroot へコピー。ユーザの `layouts/layout-web.html.erb` は従来どおり優先。
  - 実測: samples/syntax-book で全 10 ページが DOCTYPE + viewport + `<aside>`/`<main>` + `review-ast-web.css` リンク + サイドバー TOC を持ち、ERB エラー痕跡なし。素の状態でモダンな 2 ペインサイトが成立。
  - Baseline 未達機能(`@view-transition`、`text-wrap`)は「欠けても無害」な progressive enhancement として記述。
- 実装済み(手順 3: AST 走査による節レベル目次)
  - `ReVIEW::AST::WebTocBuilder` を追加。各章を AST にコンパイルして見出しツリーを走査し、part/chapter に加えて節(level 2)・小節(level 3)まで含む入れ子 `<ul class="book-toc">` を生成。章は `chap.html`、節は `chap.html#アンカー` へリンク。
  - アンカー整合が肝。renderer が出す id と一致させるため、TOC 側でも `SecCounter.new(5, chapter)` を renderer と同一手順で回し(numbered 見出しで inc → `h#{anchor}`)、nonum/notoc/nodisp の分岐も一致させる(これらは counter を進めず label/auto_id をアンカーに、notoc/nodisp は目次から除外)。入れ子は木を組んで再帰描画し常に整形式。
  - 注入: HtmlRenderer に `web_toc:` を追加し post_process が注入 TOC を優先(なければ従来の WEBTOCPrinter へフォールバック)。WebMaker は deep_toc を1回構築し、章ページは converter 経由で、index/titlepage/part は `build_indexpage` override + `@toc` 継承で注入。
  - 検証: samples/syntax-book で全ページのサイドバー節リンク 25 本すべてがページ内の実 id へ解決(nonum 節含む)。`test/ast/test_web_toc_builder.rb` がアンカー整合の不変条件(TOC の fragment ⊆ renderer が出す id)と入れ子生成を pin。CSS(`.book-toc ul`)は入れ子インデント対応済み。
  - 既知の制約: TOC 用に各章を追加コンパイルする(converter 側と二重コンパイル)。正しさ優先で当面許容。
- 積み残し(手順 4): progressive enhancement 群(anchor positioning 脚注、Speculation Rules、進捗バー等)。
