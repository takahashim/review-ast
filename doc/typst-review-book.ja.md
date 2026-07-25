# review-book: Typst 書籍ライブラリの設計

## 1. 目的と方針

### 1.1 位置づけと想定読者

- 本書は gem に同梱する Typst 書籍ライブラリ `review-book`(`templates/typst/review-book/`)の設計を記す
- 想定読者は、ライブラリまたはテーマを書く人と、`review.*` の呼び出し契約を知りたい人(レンダラの保守者)である
- 生成器(TypstRenderer・TypstMaker)側の設計は `design-typst.ja.md` にある。版面設計の語彙と値は `design-hanmen.ja.md` にある

### 1.2 Typst 標準要素の薄い包み

- 見出し、図、表、脚注、リンクは標準要素(heading、figure、table、footnote、link)の薄い包みとして実装する
- 理由:目次、PDF のタグ構造、相互参照、将来の Typst の改善を、標準機構から無償で受け取るため

### 1.3 公開 API の2系統

- `book.*`:Typst 直書きの著者向けの安定 API
- `review.*`:生成器(TypstRenderer)向けの互換 API。`book.*` へ委譲する
- Re:VIEW 固有の事情(採番の受け取り方、minicolumn の8種)は `review.*` に隔離し、`book.*` を汚さない
- 現状の例外が2つある
  - 後注(endnote)と `//bibpaper` の実体は `book.*` 側にあり、`review.*` は委譲だけしている
  - 装飾インライン(コード・ルビ・アイコン・罫など)は委譲せず `review.*` 内で体裁まで決めている(インラインコードの書体だけはテーマの `fonts.code` を参照する)

### 1.4 番号は生成しない(生成器経路)

- `review.*` 経路では、番号は呼び出し側(TypstRenderer)が確定済みの表示文字列として渡す。ライブラリとテーマは装飾はしても再構成しない
- 理由:HTML、EPUB、Typst PDF の番号を一致させるため
- 唯一の例外はページ参照。ページ番号だけはレイアウト後にしか決まらないため、Typst の `query` と page counter で解決する
- これは生成器経路の契約であり、Typst 直書きの著者は Typst のネイティブ採番を使える(1.5)。両者が両立するのは、テーマの見出しレンダラが見出し要素 `it` をそのまま描き、供給された番号(`numbering: none`)でもネイティブ採番でも同じに扱うためである

### 1.5 直書き文書での自動採番

- Re:VIEW を通さず、このライブラリを Typst 書籍ライブラリとして直に使える。`templates/typst/review-book/` を丸ごとコピー(vendoring)し、ネイティブ要素(`= 見出し`、`#figure`、`#table`)を書けばテーマが整形する。図表と参照(`@label`)は Typst の標準機構で採番・解決され、`language: "ja"` により「図」「表」のサプリメントも付く
- `book.document` は既定でアラビアのノンブル(小口側の folio)を出す。最小の文書でもページ番号が出るので、ページ設定を書かずに始められる。前付のローマ数字や柱は下記のように必要なところで上書きする
- 見出しの自動採番は `set heading(numbering: ...)` で有効にする。既製の日本語スキーム `book.heading-numbering`(レベル1=「第N章」、以降=「1.1」「1.1.1」)を用意してある

```typst
#import "/review-book/lib.typ": book, default-theme
#show: book.document.with(metadata: (title: [手書き本], language: "ja"), theme: default-theme)
#set heading(numbering: book.heading-numbering)
= 最初の章
@fig1 を参照する。
#figure(rect(width: 3cm, height: 1cm), caption: [サンプル図]) <fig1>
== 節
```

- 書籍の付き物(表紙・大扉・目次・奥付・囲み記事・コラム)は `book.*` を呼ぶ。ネイティブ要素にない部分だけを補う
- 番号を著者が明示したいとき(または Re:VIEW のように外から与えるとき)は `book.chapter(number: ...)` 等を使う。この場合レベルの見出しは `numbering: none` になり、ネイティブ採番とは混ざらない

#### 前付・本文・付録・後付

- LaTeX の frontmatter / mainmatter / appendix / backmatter に相当する切り替えは、専用の関数ではなく Typst のネイティブな `set`/`counter` で行う。ライブラリは独自の状態を持たず、ページ番号は `set page(numbering: ...)` に、見出し番号は `set heading(numbering: ...)` に素直に乗る。だから folio・目次(ネイティブ `outline`)・索引が同じ `page.numbering` を読み、表示ページ番号が食い違わない
- ライブラリが提供するのは部品だけ:`book.folio`(小口側のノンブル。footer に置く)、`book.running-head`(柱。header に置く)、採番スキーム `book.heading-numbering`(第N章 / 1.1)と `book.appendix-numbering`(付録A / A.1)

```typst
// 前付: ノンブルをローマに上書き(既定はアラビア)、柱なし、見出しは無番号
#set page(numbering: "i")
= まえがき
// 本文: ノンブルをアラビアに戻し、柱あり、章番号を有効化
#set page(numbering: "1", header: book.running-head())
#counter(page).update(1)
#set heading(numbering: book.heading-numbering)
= 最初の章                               // 第1章
== 節                                    // 1.1
// 付録: 章カウンタをリセットして字送りに(LaTeX の \appendix 相当)
#counter(heading).update(0)
#set heading(numbering: book.appendix-numbering)
= 付録の章                               // 付録A
== 付録の節                              // A.1
// 後付: 無番号に戻す
#set heading(numbering: none)
= あとがき
```

- 通しノンブル(全編アラビア・カウンタ非リセット)や開始ページも、`set page(numbering: "1")` と `counter(page).update(n)` の置き方で表せる。Re:VIEW 生成器(book.typ.erb)は typst config の serial_pagination / startpage からこの遷移を出す
- これらは native の `set heading(numbering: ...)` なので、Re:VIEW 経路の見出し(`numbering: none` + 供給番号)には影響しない。ネイティブ採番の見出しだけに効く
- 版面の設計値(判型・字詰め・級数・書体・トンボ)は `theme.typ`(design-hanmen 参照)。直書き文書もテーマを差し替えるだけで同じ版面を得る

## 2. review.* の呼び出し契約

- 生成コードとライブラリの境界である。renderer はこの契約に従って呼び出しを生成する

### 2.1 引数の規約

- `id`:完全なラベル文字列(`"fig:ch01:architecture"` の形)。ラベルの構成規則は呼び出し側が持ち、ライブラリは再解釈しない
- `number-text`:確定済みの表示番号(`[図1.1]`)。content として受け取る
- `caption`:キャプション本文。番号とは別引数で、区切り記号はライブラリ(テーマ)が入れる
- 本文は content、パス・言語名・代替テキストは str で受け取る
- 例外が3つある
  - 後注と `//bibpaper` は番号を int で受け取り、表示形(上付き、角括弧)はライブラリが作る
  - 後注はラベルをライブラリ側で派生させる(`id + ":body"`)
  - `chapter` / `part` は int の `number:` も受け取るが、現状は受理するだけで使わない

### 2.2 none と空の区別

- `caption: none` は「キャプションという概念がない」、`caption: []` は「あるが中身が空」である
- 呼び出し側は空のキャプションを引数ごと省き、ライブラリは引数の有無で分岐する

### 2.3 表のヘッダ行

- header 行があるときだけ `std.table.header` に変換し、ないときは付けない(2.2 と同じ規律)
- タグ構造(ヘッダセルのアクセシビリティ)と改ページ時のヘッダ行の繰り返しは、この変換があって初めて生じる

### 2.4 脚注の番号

- 番号を強制する側はライブラリが担う。`footnote-def(number: n)` は `counter(std.footnote).update(n - 1)` を footnote の直前に置き、Typst の自動採番を供給番号へ揃える
- どの参照で本文を出すかの判断は呼び出し側にある

## 3. 書籍の構造

### 3.1 区分の切替

- 区分(前付・本文・付録・後付)の切替は root ファイルのトップレベルで、ネイティブな `set page(numbering: ...)` / `set page(header: ...)` / `counter(page).update` / `counter(heading).update` / `set heading(numbering: ...)` を並べて行う。専用の関数では包まない
- 理由:関数内の `set` は呼び出し元へ波及しない。トップレベルの `set` は以降すべてに効くので、区分ごとのページ設定(ノンブル形式、柱の有無)と見出し採番を切り替えられる。独自状態を持たないぶん、folio・目次・索引が同じ `page.numbering` を読み、表示ページ番号が食い違わない(§1.5)

### 3.2 パートの扉

- パートの扉は `review.part` が描く
- `.re` を持つパートも catalog.yml に名前だけのパートも同じ関数に到達する(前者は renderer が、後者は maker が呼び出しを生成する)

### 3.3 表紙・大扉・奥付

- 表紙(`cover`)はトンボ有効時には既定で出さない。入稿では表紙は表1・背・表4の別データが通例で、本文 PDF に表紙ページを入れないため(review-jsbook の `media=print` と同じ意味論)。config の `cover: true` で強制できる(同じく `cover=true` 相当)
- 表紙を出すとき、画像は裁ち落としまで届かせる。トンボつきで強制した場合、ページ余白はトンボ領域(塗り足しの外側)ぶんだけ残す(0 にするとトンボの上に絵柄が乗る)。`crop.sheet: auto` のときこの余白はトンボ長に一致し、名前付き用紙のときはより広くなる
- 奥付(`colophon`)は書名、罫、履歴、関係者、罫、権利表記の順で、ページ下端に寄せる

### 3.4 柱とノンブル

- 柱は章名を左、節名を右に並べて罫を引く。ノンブルは小口側
- どちらも `renderers` で差し替えられる(4.3)

### 3.5 章の改ページ

- 章の改ページは見出しの show rule 内、かつ block の外で発行する
- 理由:block 内の `pagebreak` は効かない(6.2)

### 3.6 索引

- 分担は「語と読み順は Re:VIEW、ページ番号は Typst」である
- `index-entry` は `metadata` マークを置くだけで、`print-index` が `query` で集めて同一語のページをまとめる
- 用語は content でなく文字列で運ぶ。`metadata` の値は平文データでなければならず、グループ化のキーも兼ねるためである

## 4. テーマ

### 4.1 設計値

- 版面設計の語彙・値・導出の規約は `design-hanmen.ja.md` が正である。語彙は Vivliostyle 版の設計値ファイルと共通で、値をそのまま移せる
- この文書が持つのはテーマ辞書の構造だけである:判型系(`paper` / `binding` / `two-sided`)、設計値(`text` / `margins` / `fonts` / `colors` / `rules` / `box` / `crop`)、機能設定(`toc` / `chapter` / `running-head`)、拡張点(`renderers` / `hooks`)
- `toc.depth` は直書きの著者のための既定である。生成経路では `review.toc(depth:)` が原稿の `toclevel` を運んでくるので、そちらが優先される
- 書籍側の記述場所はプロジェクト直下(config.yml の隣)の `theme.typ` で、著者が自分で置く。ビルドはそれをそのままコピーして使う
- `theme.typ` が無ければ、既定の雛形が作業ディレクトリ内に生成されて使われる。作業ディレクトリはビルドごとに作り直されるので、雛形は著者の手元には残らない

### 4.2 拡張点の全体像

- 拡張点は3層あり、層ごとに保証が違う
  - 値:テーマ辞書の設計値の上書き。全保証
  - renderers:要素の描き直し(4.3)。構造は壊せない
  - hooks:任意の set / show(4.4)。保証外
- 保証の線引きは「その決定が別形式(HTML/EPUB)と食い違う事実、または PDF の構造を壊しうるか」である

### 4.3 renderers

- 差し替えられるのは6点:heading、caption、admonition、listing、running-head、page-number
- renderer が受け取るのは意味値と content とテーマだけである
- ID、ラベル、番号、代替テキストは `book.*` が renderer の外側で付けるため、テーマがそれらを落とすことは構造上できない

### 4.4 保証外フック(hooks)

- `hooks` は文書変換関数(`doc => doc`)である。生成された root が `book.document` の内側で適用するので、ここに書いた set / show はライブラリの既定に勝つ
- この出口が要る理由:show rule は文書フローにしか効かず、import される theme.typ に直接は書けず、root は生成物である
- renderers と違い契約の保証外であり、番号・ラベル・PDF/UA を壊す自由も著者にある

### 4.5 見出し renderer の制約

- 見出しの renderer だけは体裁専用である。番号とタイトルの組み立ては `book.*` が済ませてから渡す
- 理由:組み立てをテーマに任せるには見出し本文に `context` が要り、それが PDF/UA のタイトル解決を壊す(6.1)

### 4.6 merge-theme

- `merge-theme` は1段だけ再帰マージする
- 理由:Typst の辞書の `+` は値ごと差し替えるので、`(fonts: (body: ...))` と書くと他の書体指定が消えてしまう

## 5. 印刷と PDF 規格

### 5.1 トンボと裁ち落とし

- トンボと裁ち落としは物理的に描く。Typst は TrimBox も出力インテントも書き出せないため、仕上がり位置を伝える手段が他にない
- `crop.sheet: auto` は仕上がり + 塗り足し + トンボ長の実寸
- 判型名(`"jis-b5"` など)を指定すると、その標準用紙の中央に仕上がりを置く。日本の印刷所が求める形で、review-jsbook の `media=print` と同じ(A5 仕上がりを B5 用紙に)
- 既定色はレジストレーションブラック。Typst は判型名から寸法を引けないため、ライブラリが主要判型の寸法表を持ち、表にない判型は `crop.trim` で明示する

### 5.2 PDF/A・PDF/UA の適合条件

- PDF/A-2b と PDF/UA-1 は veraPDF での PASS を確認済みである
- ライブラリ側の適合条件は次の3つ
  - 見出しの本文に `context` を入れない(タイトル解決が壊れる)
  - 図には代替テキスト(`alt`)を渡せる構造を保つ
  - PDF メタデータには平文しか書けないため、表示用の content とは別に平文を受け取る(`title` と `plain-title`、著者の `name` と `plain-name`)。PDF/UA はタイトル必須なので、この分離が適合の前提になる

### 5.3 CMYK と適合モードの排他

- CMYK と適合モード(PDF/A・PDF/UA)は排他である。Typst が CMYK の ICC プロファイルを持たないため
- そのため `with-crop` はトンボ色の上書きを受け付け、適合モード時は通常の黒に落とせる

### 5.4 PDF/X

- サポートしない
- 理由: `--pdf-standard` に値がなく、TrimBox と出力インテントを書けないため
- 上流が対応したら再検討する

## 6. Typst の注意点

- ライブラリを書く側が知らないと壊す事項の一覧である

### 6.1 要素と show rule

- ライブラリ内で、自前の同名関数に隠される標準要素名は `std.` 前置で呼ぶ(`std.figure`、`std.footnote`、`std.table` など)。同名の自前関数がない要素(heading、image、link など)は裸で呼んでよい
- 見出しの本文に `context` を入れない(PDF/UA。4.5)。grid のような通常のコンテンツは入れても PDF/UA のタイトル解決は壊れない(確認済み)
- 見出しの本文(`heading.body`)は柱(`current-titles`)と目次(標準 `outline`)がそのまま消費する。本文の形を変える(番号とタイトルを grid で組むなど)とその両方に波及する
  - 長い章題のぶら下げ組みをやる場合は、本文はインラインのまま保ち、番号とタイトルを別チャネルで show rule に渡して描画だけを変えること

### 6.2 ページと改ページ

- `set page` はページ設定の変更として改ページを誘発する。単独ページ(表紙、大扉、奥付)は `page()` 関数形で1ページを直接作る
- `pagebreak` は block の内側では効かない。章の改ページは show rule 側に置く(3.5)

### 6.3 パスとラベル

- 相対パスは書かれたファイル基準で解決される。生成コードから受け取るパスは root 絶対を前提とし、ライブラリは探索も存在検査もしない
- 同一ラベルの2回定義は文書全体のエラーになる

### 6.4 そのほか

- 日本語の B5 は `jis-b5`。`b5` という判型名は存在しない
- 図表キャプションの上下は `set figure.caption(position: top | bottom)`
