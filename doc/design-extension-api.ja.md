# 拡張 API の設計(草案)

本書は、本が review-ext.rb で定義する独自命令を AST 上でどう表し、どう描画させるかの設計を定める。
対象は二つである。

1. 独自ブロック命令の本文を、AST のノードとして表せるようにすること(`ExtensionBlockNode` の本文の形)。
2. レンダラ拡張を、クラスの開き直しではなく登録で行えるようにすること(登録 API)。

現行の仕組み(review-ext.rb のビルダーメソッドを AST 経路で呼ぶこと、`visit_block_<名前>` によるレンダラ拡張)は [review-ext.md](review-ext.md) が述べている。
本書の設計はそれを置き換えず、その上に足す。

---

## 0. 原則: ノード型は閉じたまま、拡張は「名前」と「決まった形」で表す

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
- パリティ検証。
  オラクルであるレガシービルダーには「ノード型」という概念がない。

代わりに、拡張が選べるものを次の二つに限る。

- **名前**: 命令名(`block_type` / `inline_type`)。今もこの形である。
- **形**: 本文の形を、本体が用意した少数の選択肢から選ぶ(1 章)。

新しい形そのものは本体(review-ast)側でしか増やさない。
これは Pandoc が AST の型を固定し、拡張を `Div` / `Span` と属性で表すのと同じ考え方である。

---

## 1. 本文の形

### 問題

`ExtensionBlockNode` は `LeafNode` の派生で、本文を生の行(`lines`)のまま持つ
(`lib/review/ast/extension_block_node.rb`)。
これはレガシーのビルダーメソッドに渡す引数としては正しいが、次の不便がある。

- JSON を読む外部ツールから、独自ブロックの中のインライン構造や段落が見えない。
- 本文中の `@<fn>`、`@<list>` などが AST の索引・参照解決の対象にならない。
  解決はビルダーメソッド内の inline コンパイルに委ねられている。
- AST ネイティブに描画したい拡張(`visit_block_<名前>`)は、生の行を自分で解釈するしかない。
  [review-ext.md](review-ext.md) の例も `node.lines.map { |line| escape(line) }` で、本文中のインライン命令は描画されない。

### 設計

本文の形を次の二つから選べるようにする。

| 形 | 本文の表し方 | 想定する命令 |
|---|---|---|
| `raw`(既定) | `lines` に生の行。子は持たない(現行と同じ) | ビルダーメソッドにそのまま渡す命令、本文が独自の小言語である命令 |
| `blocks` | `children` に通常のブロック列(段落、リスト、入れ子のブロック命令など) | `//note` のような囲み枠、注記、独自のコラム |

形の宣言は review-ast 側の API で行う(2 章の `ReVIEW::AST::Extension.block`)。
Re:VIEW の `ReVIEW::Compiler.defblock` の引数は変えられない(review-ast は Re:VIEW に monkey patch を当てない)ためである。
宣言しない命令は `raw` のままとし、現行の本はすべて今と同じに動く。

#### `blocks` 形のノード

`ExtensionBlockNode` を子を持てるノードにし、`blocks` 形のときだけ `children` を持たせる。

```json
{
  "type": "ExtensionBlockNode",
  "block_type": "mybox",
  "body": "blocks",
  "args": ["注意"],
  "lines": ["本文の @<b>{一行目}", "", " * 項目"],
  "children": [ { "type": "ParagraphNode", "...": "..." }, { "type": "ListNode", "...": "..." } ]
}
```

- `body` は `raw` のとき省略する。
- `lines` は `blocks` 形でも保持する。
  レガシーのビルダーメソッド(`LegacyExtensionBridge#render_block`)は生の行を受け取るので、
  ビルダーメソッドで描画する本でも形の宣言を足せるようにするためである。
  `ReviewGenerator`(dump2re)も `lines` から書き戻せば元のソースと一致する。
- `body` と `children` はどちらも省略可能なフィールドの追加なので、
  [ast-format.ja.md](ast-format.ja.md) 3 章により `ast_format` は 1 のまま上げずに済む。
  知らないキーを無視する既存の読み手は、今までどおり `lines` を読む。

#### コンパイラ側の変更

- `blocks` 形の本文は `read_block_with_nesting` で読む(現行の `read_extension_block_lines` は最初の `//}` で止まり、入れ子を認めない)。
- 子のブロック列は通常の本文と同じ規則でコンパイルし、ポストプロセス(directive の lowering、リスト正規化など)もかける。
- インデクサと参照解決は `blocks` 形の子へも降りる。
  本文中の脚注や参照が、他の本文と同じに番号付け・解決される。

#### レガシー経路との差

`blocks` 形の宣言は AST 経路だけが知っている。
`review-compile`(レガシー経路)は今までどおり最初の `//}` までを本文として読む。
したがって、`blocks` 形の本文に入れ子のブロック命令を書いた本は、二つの経路で読み方が変わる。
これは形を宣言した本だけに生じる差で、宣言しない本のパリティには影響しない。
[review-ext.md](review-ext.md) に明記する。

### `inline` 形を今回は入れない理由

「行ごとにインライン解析した本文」(レガシーのビルダーメソッドが受け取るものに対応する形)も候補だった。
ただし、これを表すには「インライン列を持つ 1 行」というノードが要る。
既存の `CodeLineNode` は名前も意味もコード用であり、流用すると意味がぼやける。
新しいノード型を足すかどうかは本書の原則に関わるので、`raw` と `blocks` の運用を見てから決める(7 章)。

---

## 2. 登録 API

### 問題

現行のレンダラ拡張は、次の三つの組み合わせで成り立っている(`lib/review/renderer/base.rb` の `visit_extension_block`、`render_extension_inline`)。

- 名前の慣習: `visit_block_<名前>` / `render_inline_<名前>` というメソッドがあれば呼ぶ。
- クラスの開き直し: review-ext.rb が `HtmlRenderer` などを再オープンしてメソッドを足す。
- 定義元による判定: メソッドが gem の外で定義されていれば拡張とみなす(`LegacyExtensionBridge.extension_method?`)。

この方式には次の問題がある。

- レンダラの内部メソッド(`escape`、`render_children`、`@chapter` など)がすべて拡張から使えるため、事実上の公開契約になっている。
  内部を変えると、どの本が壊れるか分からない。
- プロセス全体のクラスを書き換える。
  テストでは子プロセスに分けて回す必要がある([review-ext.md](review-ext.md) の Testing 節)。
- 同じ命令を二か所で定義しても気づけない。
- 対象形式に実装がないことは、描画がその命令に到達して初めて分かる。

### 設計

#### 呼び出しの形

```ruby
# review-ext.rb
require 'review/ast/extension'

ReVIEW::AST::Extension.block(:mybox, args: 0..1, body: :blocks)
ReVIEW::AST::Extension.inline(:mykbd)

ReVIEW::AST::Extension.render_block(:mybox, format: :html) do |node, ctx|
  title = node.args.first
  head = title ? %Q(<p class="mybox-title">#{ctx.escape(title)}</p>\n) : ''
  %Q(<div class="mybox">\n#{head}#{ctx.render_children(node)}</div>\n)
end

ReVIEW::AST::Extension.render_inline(:mykbd, format: :html) do |_node, ctx|
  %Q(<kbd>#{ctx.content}</kbd>)
end
```

- `block` / `inline` は構文の宣言である。
  まだ宣言されていなければ `ReVIEW::Compiler.defblock` / `definline` を呼ぶ(Re:VIEW の公開 API の呼び出しであり、monkey patch ではない)。
  一つの宣言でレガシー経路と AST 経路の両方が命令を知る。
  `body:` は 1 章の形で、省略時は `:raw`。
- `render_block` / `render_inline` は描画の登録である。
  `format:` は `:html`(EPUB・Web を含む)、`:latex`、`:idgxml`、`:plaintext`、`:top`、`:typst` のいずれか、または配列。
- ブロックハンドラは `(node, ctx)` を受け取り、そのブロックの出力を文字列で返す。
  ブロック間の分離はレンダラが今までどおり付ける([design-improvements.ja.md](design-improvements.ja.md) 項目 2)。
  ハンドラの出力は一つのブロックとして扱う。
- インラインハンドラは `(node, ctx)` を受け取る。
  `ctx.content` は描画・エスケープ済みの内容、`node.args.first` は生の引数である(現行の `render_inline_<名前>` と同じ)。

#### 呼び出しの優先順

1. 登録されたハンドラ
2. レンダラのメソッド `visit_block_<名前>` / `render_inline_<名前>`(現行方式。互換のため残す)
3. review-ext.rb のビルダーメソッド(`LegacyExtensionBridge`)
4. `blocks` 形の既定の描画(3 章)
5. エラー(`builder does not support command: //名前`。現行と同じ)

#### 登録の検査

- 同じ(命令名, 形式)を二度登録したらエラーにし、両方の定義位置を示す。
- 組み込み命令(`//list`、`@<b>` など)の名前は登録できない。
  組み込み命令の上書きは今のビルダーメソッド再定義の経路だけで扱い、新しい API の範囲に入れない(5 章)。
- 構文の宣言がない命令への描画登録はエラーにする。
- book maker は描画を始める前に、その本で宣言された独自命令のうち対象形式にハンドラも
  ビルダーメソッドも既定の描画もないものを一覧にして警告する。
  実際に使われているものは、使われた位置付きで描画時にエラーになる(現行と同じ)。

#### 登録表の範囲

登録表は `ReVIEW::AST::Extension` が持つ一つの表である。
review-ext.rb は本を開くときにプロセスへ読み込まれるので、登録の範囲は実質「そのプロセスで開いた本」になる。
maker は一つのプロセスで一冊を扱うので、これで足りる。

テストでは、登録表を差し替えて同じプロセス内で独立に検査できる(`Extension.with_registry(...)` のような入口を用意する)。
ただし構文の宣言(`ReVIEW::Compiler::SYNTAX`)は Re:VIEW 側の大域表なので、構文まで含めて分けたいテストは今までどおり子プロセスを使う。

#### JSON から読み戻した木

登録ハンドラはノードと `ctx` しか使わないので、`review-ast-dump` の出力から読み戻した木でも動く。
組み込み命令の再定義(`Node#source_command` に頼る)が読み戻した木では効かないのと異なる点である。

---

## 3. `blocks` 形の既定の描画

`blocks` 形の命令は、ハンドラが登録されていなくても子を描画できる。
形式ごとに「汎用の囲み」を既定の描画として持たせる。

| 形式 | 既定の描画(案) |
|---|---|
| HTML | `<div class="名前">` で子を囲む。第 1 引数があれば見出しとして先頭に置く |
| plaintext / TOP | 子をそのまま描画する(TOP は `◆→開始:名前←◆` / `◆→終了:名前←◆` の囲みを付ける) |
| Typst | 子を `#block` で囲む |
| LaTeX | `\begin{review名前}` ... `\end{review名前}` |
| IDGXML | `<名前>` 要素で子を囲む |

LaTeX の環境と IDGXML の要素は、本の側(sty やスタイル定義)に定義がなければ組版・取り込みで失敗する。
したがって既定の描画は「定義を本が用意する前提の出力」であり、どの形式で既定の描画を有効にするかは未決とする(7 章)。

---

## 4. ハンドラに渡す `ctx`

### 設計

`ctx` は、拡張に公開すると約束するものだけを持つ小さなオブジェクトとする。
レンダラのインスタンスそのものは渡さない。
`ctx` にないものは契約に含まれず、予告なく変わりうる。

| メソッド | 意味 |
|---|---|
| `format` | 出力形式(`:html` など) |
| `render_children(node)` | ノードの子を、この形式で描画した文字列 |
| `render(node)` | 一つのノードを描画した文字列 |
| `escape(str)` | この形式でのエスケープ |
| `content` | インラインハンドラのみ。描画済みの内容 |
| `config` | 本の設定の読み取り専用の参照(`[]`、`fetch`、`dig`) |
| `location` | 描画中のノードのソース位置 |
| `error(message)` | ソース位置付きの `ReVIEW::CompileError` を送出する |

次は公開しない。

- `@chapter`、`@book` などの本体モデル。
- レンダラの内部ヘルパ(キャプション生成、番号の整形、ブロック分離の内部など)。
- 他の命令を呼び出す手段(`visit_block_list` を直接呼ぶ、など)。

### 判断の根拠

`ctx` を小さく保てば、レンダラの内部を変えても拡張を壊さずに済む。
足りないものは、要求が出た時点で `ctx` に足す。
足すのは版を上げずにできるが、削るのは破壊的変更になるので、最初は少なく始める。

候補として保留しているものは 7 章に挙げる。

---

## 5. 範囲に入れないもの

- **新しいノード型の登録**(0 章)。
- **構造部分の差し替え**(見出し、段落、リスト項目、`//column` など)。
  番号付け・ブロック分離・パリティ検証の前提が崩れる。
  現行と同じく、ビルダーでこれらを再定義したものは警告して使わない。
- **組み込み命令の上書き**。
  ビルダーメソッド再定義による現行の経路を互換のため残すが、登録 API では扱わない。
  組み込み命令の見た目を変えたい要求は、まず CSS・sty・テンプレートで受ける。
- **`inline` 形**(1 章末尾)。

---

## 6. 移行手順

1. 登録表・`ctx`・呼び分けを実装する(本文は `raw` 形のみ。ノードは変えない)。
   `render_block` / `render_inline` は現行の `visit_block_<名前>` / `render_inline_<名前>` と同じ入力で呼べるので、ノードの変更なしに入れられる。
2. `body: :blocks` を実装する。
   `ExtensionBlockNode` を子を持てるノードにし、コンパイラの読み込み、ポストプロセス、インデクサ、参照解決、`ReviewGenerator`、JSON のシリアライズ/デシリアライズを対応させる。
   スキーマを再生成し、[ast-semantics.ja.md](ast-semantics.ja.md) とその英語版のノード目録を更新する。
3. `blocks` 形の既定の描画を、未決事項の結論に従って形式ごとに入れる。
4. [review-ext.md](review-ext.md) を書き直し、登録 API を推奨の書き方とする。
   クラスの開き直し方式は互換のために動き続けることを明記する。
5. `inline` 形の要否を判断する。

手順 1 と 2 は独立しており、どちらを先に進めてもよい。
手順 3 は 2 に依存する。

---

## 7. 未決事項

- `blocks` 形の既定の描画を、LaTeX と IDGXML でも有効にするか。
  有効にするなら、本が環境・要素を定義していないときの失敗をどう分かりやすくするか。
- `ctx` に、文字列中のインライン命令を描画する手段(`ctx.render_inline_source(str)`)を入れるか。
  引数(キャプションなど)にインライン命令を書く命令で必要になる。
  入れると、描画時にインライン解析が走ることになり、その中の参照は索引の対象外になる。
  引数を構文の宣言時に「インライン解析する引数」と指定して、コンパイル時に解析させる方が筋がよい可能性がある。
- `ctx` に章番号・章 ID などの文書情報を入れるか。
- `inline` 形を入れるか。入れるなら行を表すノードをどうするか。
- 独自命令が定義番号を持てるようにするか(独自の「図」のような番号付きブロック)。
  持たせると参照(`@<名前>{id}`)と番号の書式まで拡張範囲に入り、範囲が大きく広がる。現時点では入れない方向とする。

---

## 8. 検証

- `test/ast/test_ast_schema.rb`: `body` / `children` の追加後にスキーマを再生成し、同梱物と一致すること。
- round-trip: `blocks` 形の命令を含む章について、dump → 読み戻し → 描画の一致と、dump2re → 再コンパイルの一致。
- `test/ast/test_review_ext_compat.rb`: 形を宣言しない本で、レガシー経路と AST 経路の出力が今までどおり一致すること。
- 登録 API の単体テスト: 優先順、二重登録、組み込み命令名の拒否、構文未宣言の拒否、事前一覧の警告。
  登録表の差し替えにより同一プロセスで回す。
- `blocks` 形の本文中の `@<fn>` / `@<list>` が、通常の本文と同じ番号・解決結果になること。
- 6 形式すべてで、ハンドラがない独自命令が同じエラー文言で止まること。
