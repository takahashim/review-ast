# 拡張 API の設計(草案)

本書は、本が独自に定義する命令を AST 上でどう宣言し、どう表し、どう描画させるかの設計を定める。
前提は「**AST の描画はレンダラが担い、ビルダーは既存の本の後方互換のためだけに使う**」である(0 章)。
新しく作る命令・拡張・機能は、レンダラだけで完結し、ビルダーを一切必要としないようにする。

現行の仕組み(review-ext.rb のビルダーメソッドを AST 経路で呼ぶこと、`visit_block_<名前>` によるレンダラ拡張)は [review-ext.md](review-ext.md) が述べている。
本書は、その上にレンダラ向けの正式な拡張の仕組みを足し、ビルダーへの依存を互換層の中に閉じ込める計画である。

構成は、基盤(2 章)のあとに、優先度の高い順に三つの拡張点を置く。

1. 引数のインライン解析(3 章): 今はレンダラで書いた拡張が、キャプションのインライン命令を描画できない。
2. 本文の形(4 章): 今はレンダラで書いた拡張が、本文のインライン命令を描画できない。
3. 登録 API(5・6 章): 今も書けるが、書きにくく、レンダラの内部に依存する。

1 と 2 は「レンダラだけではそもそも書けない」問題、3 は「書きにくい」問題なので、この順に解く。

---

## 0. 前提: 描画はレンダラ、ビルダーは後方互換のため

### 現状

AST 経路の出力は、最初からレンダラが作っている。
ビルダーは描画に使われていない。
それでもビルダーが実行時に参照される箇所が、次の三種類ある。

| 用途 | 場所 | ビルダーの使い方 | 性格 |
|---|---|---|---|
| review-ext.rb のメソッドを呼ぶ | `Renderer::LegacyExtensionBridge` | インスタンスを作り、独自命令・組み込み命令の再定義に出力させる | 後方互換(一部を残す。9 章) |
| 命令がその形式で使えるかの確認 | `Renderer::Base#check_builder_support` | クラスを調べる(`respond_to?`、メソッドの定義元) | **レンダラだけで作る命令の妨げになる** |
| 個別の判定 | `TopRenderer#em_marked_like_i?`、`Command::VolumePrinter` | クラスを調べる、`compile_inline` を呼ぶ | 実装の都合 |

1 行目は後方互換のためのもので、価値の高い部分だけを残す(9 章)。
問題は 2・3 行目である。
とくに 2 行目は、「この命令が使えるか」の根拠がビルダーにあるため、ビルダーを持たない命令(レンダラだけで実装した命令)を正しく扱えない。
review-ext.rb がレンダラにだけ `render_inline_<名前>` を定義すると、ビルダー側にメソッドがないという理由でエラーになっていたのは、この構造が原因である(個別には修正済み)。

### 目標

- 新しく作る命令・拡張・機能は、レンダラだけで実装でき、ビルダーに何も要らない。
- どの命令がどの形式で使えるか、という決まりを review-ast が持つ(2 章)。
- 本の拡張は、レンダラ向けの API で書ける(5 章)。
- ビルダーを参照するのは、後方互換の層(9 章)の中だけにする。

### 変えないもの

- `review` gem への依存そのもの。
  Book/Chapter のモデル、i18n、画像の探索、maker の基底クラスは今後も使う(README の Relationship to Re:VIEW)。
- review-ext.rb のビルダーメソッドを呼ぶ互換層(`LegacyExtensionBridge`)のうち、独自命令の部分。
  既存の本を動かし続けるために、範囲を限定して残す。
  組み込み命令の再定義の互換は、複雑さと壊れやすさに見合わないので外す(9 章)。
- テストのオラクルとしてのビルダー。
  旧経路との出力比較(`test/ast/*_comparator`、DVI 比較など)は今後も続ける。
  これはテストの中の話で、ライブラリの実行時には関わらない。

---

## 1. 原則: ノード型は閉じたまま、拡張は「名前」と「決まった形」で表す

**拡張から新しいノード型を登録できるようにはしない。**

ノード型を開くと、次の性質が失われる。

- 交換形式の自己完結性。
  `ast_format` だけを見れば読めるという契約([ast-format.ja.md](ast-format.ja.md))が、
  「その本の review-ext.rb がなければ読めない」ダンプに変わる。
  スキーマ(`additionalProperties: false`)も閉じていられない。
- 全形式での網羅。
  型を一つ足すと HTML / LaTeX / IDGXML / plaintext / TOP / Typst の 6 レンダラと
  `ReviewGenerator`、インデクサ、参照解決が対応を要する。
  実装されない組み合わせが必ず残る。
- パイプラインの意味づけ。
  定義番号、参照解決、ブロック分離などのパスは、ノード型ごとの意味を前提にしている
  ([ast-semantics.ja.md](ast-semantics.ja.md) 2 章)。
  知らない型についての判断が拡張側に漏れ出す。

代わりに、拡張が選べるものを次に限る。

- **名前**: 命令名(`block_type` / `inline_type`)。
- **引数の種類**: 引数ごとに、生の文字列かインライン解析するか(3 章)。
- **本文の形**: 本体が用意した少数の選択肢から選ぶ(4 章)。

新しい形そのものは本体(review-ast)側でしか増やさない。
これは Pandoc が AST の型を固定し、拡張を `Div` / `Span` と属性で表すのと同じ考え方である。

---

## 2. 基盤: 命令表を review-ast が持つ

### 問題

命令の宣言と、形式ごとの対応状況が、どちらも Re:VIEW 側にある。

- 宣言: 独自命令は `ReVIEW::Compiler.defblock` / `definline` で Re:VIEW の大域表(`ReVIEW::Compiler::SYNTAX` など)に登録される。
  AST のコンパイラは「その表にあり、AST 自身に処理系がない」命令を独自命令とみなしている(`AST::Compiler#extension_command?`)。
- 対応状況: 「この命令はこの形式で使えるか」は、ビルダーがそのメソッドを持つかで決まっている(`check_builder_support`)。
  たとえば plaintext と TOP には `@<abbr>` がなく、HTML には `@<pageref>` がない、という決まりは、ビルダーのクラスから実行時に読み取っている。

後者は、レンダラだけで実装した命令(ビルダーにメソッドがない命令)を正しく扱えない。
また、3・4 章で命令の宣言に情報(引数の種類、本文の形)を足すには、Re:VIEW 側の表は使えない(引数を変えられない。review-ast は Re:VIEW に monkey patch を当てない)。

### 設計

review-ast に命令表 `ReVIEW::AST::CommandTable` を置く。
一つの命令について、次を持つ。

| 項目 | 内容 |
|---|---|
| 名前と種類 | ブロック / 1 行命令 / インライン |
| 引数の個数 | 現行の `check_args` と同じ規則 |
| 引数の種類 | 3 章 |
| 本文の有無と形 | 4 章 |
| 対応する形式 | どの形式で描画できるか |

- 組み込み命令は、既存の `BlockProcessor::BLOCK_COMMAND_TABLE` と `InlineProcessor::DEFAULT_INLINE_HANDLERS` を元にこの表へ載せる。
  今後足す組み込み命令は、レンダラで実装し、この表に載せるだけで使えるようにする(ビルダーに対応するメソッドは要らない)。
- 既存の組み込み命令の「対応する形式」は、**ビルダーから生成した表**として同梱する。
  スキーマと同じ流儀である([ast-format.ja.md](ast-format.ja.md) 5 章)。
  生成ツールがビルダーのメソッドを調べて表を書き、テストが同梱物とビルダーの実際が一致することを確かめる。
  実行時にはビルダーを見ず、同梱の表だけを見る。
- ビルダーにない命令(今後レンダラだけで足す組み込み命令)は、生成した表とは別に、手で書いた表に載せる。
  一致テストの対象は生成した部分だけである。
- 独自命令は、5 章の API で宣言したものと、互換のために Re:VIEW の表から読み取ったもの(`defblock` などで宣言されたもの)の両方をこの表に載せる。
  後者の「対応する形式」は、互換層として、review-ext.rb がその形式のビルダーにメソッドを定義しているかで決める(9 章)。
- `check_builder_support` は、この表を引く形に置き換える。
  エラーの文言は今と同じにする(`builder does not support command: //名前` など)。

---

## 3. 引数のインライン解析(優先度 1)

### 問題

`//mybox[A @<b>{bold} box]{ ... //}` の第 1 引数は、`ExtensionBlockNode#args` に生の文字列 `"A @<b>{bold} box"` として入る。
レンダラのキャプション描画(`render_caption_inline`)はパース済みの `CaptionNode` しか受け取らないので、
AST ネイティブの拡張には、引数の中のインライン命令を描画する公開の手段がない。

ビルダーメソッドなら `compile_inline(caption)` で描画できる。
独自の囲み枠はたいていキャプションを持つので、レンダラで書くとビルダーより劣る。
新しく作るものをレンダラだけで書く前提では、これは致命的である。

描画時に文字列をインライン解析させる案(`ctx.render_inline_source(str)`)は採らない。
描画時の解析で生まれたノードは、索引と参照解決を通らない。
キャプション中の `@<fn>` や `@<list>` が、ほかのキャプションと同じに番号付け・解決されなくなる。

### 設計

命令の宣言で、引数ごとに種類を指定する。

| 種類 | 意味 |
|---|---|
| `:raw`(既定) | 生の文字列(ID、言語名、オプションなど) |
| `:caption` | キャプション。`CaptionNode` に解析する。一つの命令に一つまで |
| `:inline` | インライン命令を含む文字列。インライン列に解析する |

```ruby
ReVIEW::AST::Extension.block(:mybox, args: [:caption], body: :blocks)
ReVIEW::AST::Extension.block(:quiz, args: [:raw, :caption, :inline], body: :blocks)
```

- `:caption` の引数は `ExtensionBlockNode#caption_node` に入る。
  既存の `CaptionNode` と `Captionable` をそのまま使うので、ノード型は増えない。
  キャプション中の脚注の扱い(LaTeX での `\footnotemark` への切り替えなど)も、組み込み命令のキャプションと同じ処理に乗る。
  レンダラは `render_caption_inline(node.caption_node)` で描画できる(5 章の `ctx.render_caption(node)`)。
- `:inline` の引数は `ExtensionBlockNode#arg_nodes` に入る。
  `args` と同じ長さの配列で、`:inline` の位置にインライン列(ノードの配列)、それ以外の位置に `nil` を置く。
- `args` は、種類にかかわらず常に生の文字列を保持する(ソースの事実であり、dump2re の書き戻しに使う)。

JSON の形:

```json
{
  "type": "ExtensionBlockNode",
  "block_type": "quiz",
  "args": ["q1", "問 @<b>{1}", "ヒント: @<i>{表}"],
  "caption_node": { "type": "CaptionNode", "children": [ "..." ] },
  "arg_nodes": [null, null, [ { "type": "TextNode", "...": "..." }, { "type": "InlineNode", "...": "..." } ]],
  "...": "..."
}
```

`caption_node` と `arg_nodes` はどちらも省略可能なフィールドの追加なので、
[ast-format.ja.md](ast-format.ja.md) 3 章により `ast_format` は 1 のまま上げずに済む。

- インデクサと参照解決は、`caption_node` と `arg_nodes` の中へも降りる。
- 1 行命令(`defsingle` に当たるもの)にも同じ宣言が使える。

---

## 4. 本文の形(優先度 2)

### 問題

`ExtensionBlockNode` は `LeafNode` の派生で、本文を生の行(`lines`)のまま持つ。
そのため、本文中のインライン命令や段落が AST のノードにならない。
AST ネイティブの拡張は本文のインライン命令を描画できず、JSON を読む外部ツールからも本文の構造が見えない。
本文中の `@<fn>`、`@<list>` なども AST の索引・参照解決の対象にならない。

### 設計

本文の形を次の二つから選べるようにする。

| 形 | 本文の表し方 | 想定する命令 |
|---|---|---|
| `raw`(既定) | `lines` に生の行。子は持たない(現行と同じ) | 本文が独自の小言語である命令(図の記述、データの列挙など) |
| `blocks` | `children` に通常のブロック列(段落、リスト、入れ子のブロック命令など) | `//note` のような囲み枠、注記、独自のコラム |

`ExtensionBlockNode` を子を持てるノードにし、`blocks` 形のときだけ `children` を持たせる。

```json
{
  "type": "ExtensionBlockNode",
  "block_type": "mybox",
  "body": "blocks",
  "args": ["A @<b>{bold} box"],
  "caption_node": { "type": "CaptionNode", "children": [ "..." ] },
  "children": [ { "type": "ParagraphNode", "...": "..." }, { "type": "ListNode", "...": "..." } ]
}
```

- `body` は `raw` のとき省略する。
- `blocks` 形では `lines` を持たない。
  本文の唯一の表現は `children` であり、dump2re は組み込みのブロックと同じく子から書き戻す。
  生の行が要るのはビルダーメソッドへの受け渡しだけであり、`blocks` 形は新しい機能なので互換層の対象にしない。
  互換層(`LegacyExtensionBridge`)が扱うのは `raw` 形の命令だけとする(9 章)。
- `body` と `children` は省略可能なフィールドの追加なので、`ast_format` は上げずに済む。
  ただし、`ExtensionBlockNode` は今は「`children` キーを出さない leaf ノード」と [ast-semantics.ja.md](ast-semantics.ja.md) に書かれている。
  この記述は「`blocks` 形のときだけ `children` を持つ」に改める。

#### コンパイラ側の変更

- `blocks` 形の本文は `read_block_with_nesting` で読む(現行の `read_extension_block_lines` は最初の `//}` で止まり、入れ子を認めない)。
- 子のブロック列は通常の本文と同じ規則でコンパイルし、ポストプロセス(directive の lowering、リスト正規化など)もかける。
- インデクサと参照解決は `blocks` 形の子へも降りる。

#### `defminicolumn` との関係

Re:VIEW の `defminicolumn` で宣言された独自命令は、旧経路でも本文を通常の本文としてコンパイルする(`//note` と同じ扱い)。
したがって、互換のために Re:VIEW の表から読み取るとき、`defminicolumn` の命令は「第 1 引数が `:caption`、本文が `blocks`」として扱うのが自然である。
これでビルダーメソッドがなくても、7 章の既定の描画で表示できる。

#### `inline` 形を今回は入れない理由

「行ごとにインライン解析した本文」も候補だった。
ただし、これを表すには「インライン列を持つ 1 行」というノードが要る。
既存の `CodeLineNode` は名前も意味もコード用であり、流用すると意味がぼやける。
新しいノード型を足すかどうかは 1 章の原則に関わるので、`raw` と `blocks` の運用を見てから決める(11 章)。

---

## 5. 登録 API(優先度 3)

### 問題

現行のレンダラ拡張は、名前の慣習(`visit_block_<名前>` / `render_inline_<名前>`)、
クラスの開き直し、メソッドの定義元による判定(`LegacyExtensionBridge.extension_method?`)の組み合わせで成り立っている。

- レンダラの内部メソッドがすべて拡張から使え、事実上の公開契約になっている。
- 開き直したクラスで、組み込み命令の描画(`visit_block_box` など)も黙って置き換えられる。
- 一つの命令に 6 つのクラスを開く必要があり、ブロックとインラインで受け取る引数の形も異なる。
- プロセス全体のクラスを書き換えるので、テストは子プロセスに分けて回す必要がある。
- 対象形式に実装がないことは、描画がその命令に到達して初めて分かる。

新しく作る拡張はレンダラだけで書く、という前提では、これが唯一の書き方になる。
その書き方が上の状態では困るので、正式な API を用意する。

### 設計

#### 呼び出しの形

```ruby
# review-ext.rb
require 'review/ast/extension'

ReVIEW::AST::Extension.block(:mybox, args: [:caption], body: :blocks)
ReVIEW::AST::Extension.inline(:mykbd)

ReVIEW::AST::Extension.render_block(:mybox, format: :html) do |node, ctx|
  title = ctx.render_caption(node)
  head = title.empty? ? '' : %Q(<p class="mybox-title">#{title}</p>\n)
  %Q(<div class="mybox">\n#{head}#{ctx.render_children(node)}</div>\n)
end

ReVIEW::AST::Extension.render_inline(:mykbd, format: [:html, :idgxml]) do |_node, ctx|
  %Q(<kbd>#{ctx.content}</kbd>)
end

ReVIEW::AST::Extension.render_inline(:mykbd, format: :latex) do |_node, ctx|
  %Q(\\mykbd{#{ctx.content}})
end
```

- `block` / `inline` は宣言で、2 章の命令表に載る。
  Re:VIEW の `defblock` などは呼ばない。この API で宣言した命令はレンダラだけで描画するものであり、旧経路(`review-compile`)は対象にしない。
- `render_block` / `render_inline` は描画の登録で、命令表の「対応する形式」にも反映される。
  `format:` は `:html`(EPUB・Web を含む)、`:latex`、`:idgxml`、`:plaintext`、`:top`、`:typst` のいずれか、またはその配列。
- ブロックハンドラもインラインハンドラも、受け取る引数は `(node, ctx)` にそろえる。
- ブロックハンドラの出力は一つのブロックとして扱い、ブロック間の分離はレンダラが今までどおり付ける([design-improvements.ja.md](design-improvements.ja.md) 項目 2)。

#### 呼び出しの優先順

1. 登録されたハンドラ
2. `blocks` 形の既定の描画(7 章)
3. レンダラのメソッド `visit_block_<名前>` / `render_inline_<名前>`(開き直し方式)と、独自命令の review-ext.rb のビルダーメソッド(互換層。9 章)
4. エラー(`builder does not support command: //名前`。文言は現行と同じ)

既定の描画を互換層より前に置くのは、`blocks` 形を宣言した命令は AST ネイティブだからである。
`blocks` 形の命令に互換層は使えない(4 章: `lines` を持たない)。

#### 登録の検査

- 同じ(命令名, 形式)を二度登録したらエラーにし、両方の定義位置を示す。
- 組み込み命令の名前は `block` / `inline` で宣言できない(描画の差し替えは 8 章の別の入口で行う)。
- 宣言のない命令への描画登録はエラーにする。
- book maker は描画を始める前に、命令表を見て「その本で宣言されたが、対象形式で描画できない命令」を一覧にして警告する。
  実際に使われているものは、使われた位置付きで描画時にエラーになる(現行と同じ)。

#### 登録表の範囲

登録表は命令表とともに `ReVIEW::AST::Extension` が持つ。
review-ext.rb は本を開くときにプロセスへ読み込まれるので、登録の範囲は実質「そのプロセスで開いた本」になる。
maker は一つのプロセスで一冊を扱うので、これで足りる。

テストでは、命令表と登録表を差し替えて同じプロセス内で独立に検査できるようにする(`Extension.with_registry(...)` のような入口)。
Re:VIEW の大域表に触れないので、5 章の API だけを使うテストは子プロセスを要しない。

#### JSON から読み戻した木

登録ハンドラはノードと `ctx` しか使わないので、`review-ast-dump` の出力から読み戻した木でも動く。

---

## 6. ハンドラに渡す `ctx`

`ctx` は、拡張に公開すると約束するものだけを持つ小さなオブジェクトとする。
レンダラのインスタンスそのものは渡さない。
`ctx` にないものは契約に含まれず、予告なく変わりうる。

| メソッド | 意味 |
|---|---|
| `format` | 出力形式(`:html` など) |
| `render_children(node)` | ノードの子を、この形式で描画した文字列 |
| `render(node)` | 一つのノードを描画した文字列 |
| `render_caption(node)` | `node.caption_node` を描画した文字列(キャプションがなければ空文字列) |
| `render_arg(node, index)` | `:inline` の引数を描画した文字列 |
| `escape(str)` | この形式でのエスケープ |
| `content` | インラインハンドラのみ。描画済みの内容 |
| `config` | 本の設定の読み取り専用の参照(`[]`、`fetch`、`dig`) |
| `location` | 描画中のノードのソース位置 |
| `error(message)` | ソース位置付きの `ReVIEW::CompileError` を送出する |
| `render_default(node)` | 8 章の差し替えでのみ使う。本来の描画結果 |

次は公開しない。

- `@chapter`、`@book` などの本体モデル。
- レンダラの内部ヘルパ(番号の整形、ブロック分離の内部など)。
- 他の命令の描画を直接呼ぶ手段(`visit_block_list` を呼ぶ、など)。

`ctx` を小さく保てば、レンダラの内部を変えても拡張を壊さずに済む。
足りないものは、要求が出た時点で足す。
足すのは互換性を壊さないが、削るのは破壊的変更になるので、最初は少なく始める。

---

## 7. `blocks` 形の既定の描画

`blocks` 形の命令は、ハンドラが登録されていなくても描画できるようにする。
既定の描画は、**組み込みの囲み(`//note` などの minicolumn)の描画規則を命令名で使う**ものとする。

組み込みの囲みの描画は、すでに多くの形式で命令名に依存しない作りになっている。

| 形式 | 現行の囲みの描画 | 既定の描画として使うための変更 |
|---|---|---|
| HTML | `<div class="名前">` とキャプションの `<p class="caption">`(`HtmlRenderer#visit_minicolumn`) | 不要 |
| IDGXML | 名前の要素で囲む(`IdgxmlRenderer#visit_minicolumn`) | 不要 |
| TOP | `◆→開始:見出し←◆` の囲み(見出しは既知の名前なら表から、なければ命令名) | 不要 |
| plaintext | キャプションの行と子を描画する(命令名を使わない) | 不要 |
| LaTeX | 既知の名前を `reviewnote` などの環境名に対応させる `case` | 未知の名前を `review名前` 環境にする規則を足す |
| Typst | 既知の名前以外をエラーにする(`MINICOLUMN_KINDS`) | 未知の名前を汎用の囲みとして描く規則を足す |

LaTeX の環境と IDGXML の要素は、本の側(sty やスタイル定義)に定義がなければ組版・取り込みで失敗する。
ただしこれは、旧経路で独自の minicolumn を定義した本がすでに負っている条件と同じである。
本が定義を用意しないまま使った場合の失敗をどう分かりやすくするかは、11 章に残す。

---

## 8. 組み込み命令の描画の差し替え

### 問題

組み込み命令の見た目を変える手段は、今はビルダーメソッドの再定義(`def emlist`、`def inline_b`、`def note_begin` など)しかない。
実際の本では、これは独自命令と同じくらい使われている(CSS クラスを足す、LaTeX のマクロ名を変える、など)。
9 章でこの再定義の互換を外すので、その移行先がレンダラ側に要る。

### 設計

**命令単位の描画だけ**を差し替えられるようにする。

```ruby
ReVIEW::AST::Extension.override_block(:emlist, format: :html) do |node, ctx|
  ctx.render_default(node).sub('<div class="emlist-code">', '<div class="emlist-code my-code">')
end

ReVIEW::AST::Extension.override_inline(:b, format: :latex) do |_node, ctx|
  %Q(\\mybold{#{ctx.content}})
end
```

- 対象は、命令表に載っている組み込みのブロック命令・インライン命令・囲み(minicolumn)である。
- ハンドラには型の決まったノード(`CodeBlockNode`、`InlineNode` など)が渡る。
  番号付けと索引は AST が済ませたあとなので、差し替えても `@<list>{id}` などの参照は壊れない。
- `ctx.render_default(node)` で本来の描画結果を得られる。
  多くの差し替えは「本来の出力を少し変える」ものなので、全体を書き直さずに済む。
- 差し替えたブロックの出力も一つのブロックとして扱い、ブロック間の分離はレンダラが付ける。

### 差し替えられないもの

見出し、段落、リスト項目、表の行など、**文書の構造**は差し替えの対象にしない。
番号付け、ブロック分離、目次などの前提が崩れるためである。
現行の互換層でも、これらをビルダーで再定義したものは警告して使っていない([review-ext.md](review-ext.md) の What is not picked up)。
見た目の変更は、CSS・sty・テンプレートで受ける。

---

## 9. 互換層の位置づけ: 部分サポート

### 方針

互換層は、**価値が高く、範囲を閉じられるものだけを残す**。
複雑さや壊れやすさに見合わないものは外す。
AST 版の互換は「旧経路と同じ本がすべて同じに組める」ことではなく、
「よく使われる書き方の多くがそのまま動き、動かないものは黙らずに知らせる」ことを目標とする。

### 現行の互換層の複雑さ

| 機能 | 価値 | 複雑さ・壊れやすさの原因 |
|---|---|---|
| 独自命令(`defblock`/`definline` + ビルダーメソッド) | 高い。review-ext.rb を持つ本の多くがこれ | `StrictCompiler` が Re:VIEW の非公開の内部(`compile_command`、`syntax_descriptor`、`@command_name_stack`、`@non_parsed_commands`、`text`)とビルダーの状態(`doc_status`、`raw_result`)に依存する |
| 組み込み命令の再定義(`def emlist`、`def inline_b`、`def note_begin`、`def inline_list` など) | 中程度。8 章の差し替えで置き換えられる | 全ノードに旧形式の命令(`Node#source_command`、`InlineNode#source_arg`)を持たせる必要がある(`node.rb`、`inline_node.rb`、`block_processor.rb`、`inline_processor.rb`、`renderer/base.rb` の 5 ファイル)。囲みでは、ビルダーが書いた両端の間にレンダラの出力を挟み込む。JSON から読み戻した木では使えない |
| AST が呼ばない再定義の警告 | 補助的 | どのメソッドが Re:VIEW 自身の定義かを知るため、Re:VIEW のソースファイルを正規表現で読む(`review_defined_methods`) |

さらに、ビルダーメソッドの中で `@chapter.list(id)` などを呼んだり、`compile_inline` が参照を解決したりすると、
Re:VIEW の `BookUnit#execute_indexer` が章全体を旧コンパイラでもう一度コンパイルして索引を作る。
その部分だけ AST とは別の旧フロントエンドで番号が付き、AST の番号と食い違う可能性がある。
Markdown の章ではそもそも成り立たない。
これは組み込み命令の再定義で起きやすいが、独自命令でもキャプションや本文に参照があれば起きる。

### 残すもの: 独自命令のビルダーメソッド(範囲を限定して)

- `defblock` / `defsingle` / `defminicolumn` / `definline` で宣言し、ビルダーメソッドで描画する独自命令は、今までどおり動かす。
- ただし範囲を次のとおり限定し、[review-ext.md](review-ext.md) に明記する。
  - 本文は `raw` 形だけ。3〜8 章の新しい機能(引数の種類、`blocks` 形、既定の描画、登録 API、差し替え)はこの経路に足さない。
  - ビルダーメソッドの中のインライン解析と参照解決は旧経路の動作であり、AST の番号付けとの一致は保証しない。
  - Markdown の章では使えない。
- 新しい API(5 章)と同じ命令を扱うときは、新しい API が勝つ。
- Re:VIEW の非公開の内部への依存は `StrictCompiler` の中だけに閉じ込め、Re:VIEW master に対する CI(`REVIEW_HEAD=master`)で見張る。

### 外すもの: 組み込み命令の再定義

- review-ext.rb がビルダーで組み込み命令を再定義していても、AST 経路では使わない。
  対象は、組み込みのブロック命令(`def emlist` など)、インライン命令(`def inline_b`、`def inline_ruby`、`def inline_list` など)、囲みの両端(`def note_begin` / `def note_end`)である。
- 黙って無視せず、再定義ごとに一度、移行先を示して警告する。

  ```text
  review-ext.rb redefines HTMLBuilder#emlist, which the AST path does not use; override it with ReVIEW::AST::Extension.override_block (see doc/review-ext.md)
  ```

- これにより次を削除できる。
  - `Node#source_command`、`InlineNode#source_arg` と、それを作る `BlockProcessor` / `InlineProcessor` の処理。
  - `Renderer::Base#render_overridden_block` と、囲みの両端を挟み込む `LegacyExtensionBridge#render_minicolumn`。
  - `LegacyExtensionBridge.block_overridden?` と、`render_extension_inline` のうち組み込みのインライン命令を扱う部分。
- 移行先は 8 章の `override_block` / `override_inline` である。
  8 章より先に外す場合、その間は組み込み命令の見た目を review-ext.rb で変える手段がなくなる。
  CSS・sty・テンプレートで代えられない本は、その間 AST 経路では組めない。
  先に外すか 8 章と同時にするかは 11 章で選ぶ。

### 簡素化するもの: 再定義の警告

- Re:VIEW のソースファイルを正規表現で読むのをやめる。
- 代わりに、2 章の命令表を生成するツールで、各ビルダーが Re:VIEW の中で定義しているメソッド名の一覧も生成して同梱する。
  「gem の外で定義され、かつこの一覧にあるメソッド」が、AST 経路で使われない再定義である。
  組み込み命令の再定義は上の警告、構造部分(`headline` など)とヘルパ(`table_begin` など)の再定義は今の警告になる。
- 一覧の一致テストは、命令表と同じくビルダーの実際と突き合わせる。

### レンダラを開き直す方式

`visit_block_<名前>` / `render_inline_<名前>` をレンダラに定義する方式は、ビルダーに依存しないので互換層とは分けて扱い、当面残す。
登録 API(5 章)が入ったら、新しく書く拡張には登録 API を勧める。
開き直しで組み込み命令の描画を置き換えることは、今と同じくサポートしない([review-ext.md](review-ext.md))。

### 将来: 独自命令の互換も外すかどうか

登録 API が実際に使われるようになった時点で、独自命令のビルダーメソッドの互換も外すかを改めて判断する。
外す場合も、`defblock` などの宣言は Re:VIEW の表から読めるので、引数の個数の確認はビルダーなしで続けられる。
ビルダーメソッドは使わず、命令ごとに「AST 版ではビルダーメソッドを使わない」と知らせる。

### 互換層の外にあるビルダーへの依存の置き換え

| 依存 | 置き換え |
|---|---|
| `check_builder_support` | 2 章の命令表を引く |
| `TopRenderer#em_marked_like_i?`(`TOPBuilder#inline_em` が `inline_i` の別名かを調べる) | インストールされたビルダーに追従するのをやめ、AST の仕様として一つに決める(新しい Re:VIEW に合わせて `@<i>` と同じ記号で囲む)。旧経路との出力比較では、Re:VIEW 5.11 との差として扱う |
| `Command::VolumePrinter`(章タイトルを `PLAINTEXTBuilder#compile_inline` で文字列にする) | AST の章タイトル(`ChapterTitle`)を `PlaintextRenderer` で描画する |

---

## 10. 範囲に入れないもの

- **新しいノード型の登録**(1 章)。
- **文書の構造の差し替え**(8 章)。
- **`inline` 形の本文**(4 章末尾)。
- **独自命令の定義番号**。
  独自の「図」のような番号付きブロックを許すと、参照(`@<名前>{id}`)と番号の書式まで拡張範囲に入り、範囲が大きく広がる。

---

## 11. 移行手順

依存関係の順に並べる。

1. **命令表**(2 章)。
   組み込み命令と、Re:VIEW の表から読み取った独自命令を載せる。
   ビルダーから「対応する形式」の表と、ビルダーが定義するメソッド名の一覧を生成するツールと、その一致テストを作る。
   `check_builder_support` を命令表に、再定義の警告の判定を同梱の一覧に置き換える。出力は変わらない。
2. **組み込み命令の再定義の互換を外す**(9 章)。
   警告に置き換え、`source_command` / `source_arg` などを削除する。
   この手順は 7(差し替え)と同時にしてもよい。
   先に行えば以降の手順でノードに旧形式の情報を気にせずに済むが、7 までの間、組み込み命令の見た目を変える手段がなくなる。
3. **引数のインライン解析**(3 章)。
   `Extension.block` の `args:` と、`caption_node` / `arg_nodes`。
   コンパイラ、インデクサ、参照解決、JSON、`ReviewGenerator` を対応させる。
   この時点では、描画は現行の `visit_block_<名前>` から `node.caption_node` を使う。
4. **本文の `blocks` 形**(4 章)と**既定の描画**(7 章)。
   `defminicolumn` の命令も `blocks` 形として扱う。
5. **登録 API と `ctx`**(5・6 章)。
6. **[review-ext.md](review-ext.md) の書き直し**。
   新しい API を推奨とし、独自命令の互換の範囲(9 章)と、互換層の書き方から新しい API への対応表を載せる。
   互換層の外にあるビルダー依存(`em_marked_like_i?`、`VolumePrinter`)を置き換える。
7. **組み込み命令の差し替え**(8 章)。

手順 3〜5 は、レンダラだけで拡張が「書ける」ようになる順である。
手順 5 までで、新しく書く独自命令はビルダーを使わずに済む。
手順 6 までで、互換層の外でビルダーを参照する箇所がなくなる。
手順 7 で、外した組み込み命令の再定義の移行先がそろう。

各手順のたびに、スキーマを再生成し、[ast-semantics.ja.md](ast-semantics.ja.md) と英語版を更新する。

---

## 12. 未決事項

- `blocks` 形の既定の描画で、本が LaTeX の環境や IDGXML のスタイルを定義していないときの失敗を、どう分かりやすくするか。
- `:inline` の引数を表す `arg_nodes` を、位置で引く配列にするか、名前付きの引数(`args: { title: :caption, hint: :inline }`)にするか。
  名前付きにすると `args` の位置との対応を別に持つ必要がある。
- `ctx` に章番号・章 ID などの文書情報を入れるか。
- `inline` 形を入れるか。入れるなら行を表すノードをどうするか。
- 組み込み命令の再定義の互換を、差し替え(8 章)より先に外すか、同時に外すか(11 章の手順 2)。
- 独自命令のビルダーメソッドの互換も、いずれ外すか(9 章末尾)。
- 命令表の「対応する形式」を、いつまでビルダーから生成し続けるか。
  旧経路との出力比較を続ける限りは生成でよいが、どこかで review-ast の仕様として手で書く表に一本化するかどうか。

---

## 13. 検証

- `test/ast/test_ast_schema.rb`: フィールドを足すたびにスキーマを再生成し、同梱物と一致すること。
- 命令表: 生成した「対応する形式」の表が、ビルダーの実際と一致すること。
- round-trip: 引数の種類と本文の形を宣言した命令を含む章について、dump → 読み戻し → 描画の一致と、dump2re → 再コンパイルの一致。
- 索引と参照解決: キャプション・`:inline` 引数・`blocks` 形の本文の中の `@<fn>` / `@<list>` が、通常の本文と同じ番号・解決結果になること。
- `test/ast/test_review_ext_compat.rb`: 独自命令をビルダーメソッドで書いた本で、旧経路と AST 経路の出力が今までどおり一致すること。
  組み込み命令の再定義のテスト(`test_redefined_builtin_commands_are_used_as_in_the_legacy_path`)は、
  再定義が使われず、移行先を示す警告が出ることを確かめるテストに改める。
- 登録 API の単体テスト: 優先順、二重登録、組み込み命令名の拒否、宣言のない命令の拒否、事前一覧の警告、差し替えでの `render_default`。
  登録表の差し替えにより同一プロセスで回す。
- 既定の描画: 6 形式すべてで、ハンドラのない `blocks` 形の命令が描画されること。
- 6 形式すべてで、描画できない独自命令が同じエラー文言で止まること。
