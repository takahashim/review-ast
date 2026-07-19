# red_quilt への要望: バグ 1 件と API 提案 4 件

review-ast の Markdown 対応(`doc/design-improvements.ja.md` 項目 10)は、Markdown パーサとして
[red_quilt](https://github.com/takahashim/red_quilt) を使う方針である。
項目 10 の当初計画は markly(cmark-gfm の C 拡張バインディング)前提で書かれていたが、
pure Ruby の red_quilt に置き換える。

本書は、その取り込みにあたって red_quilt 側に必要な変更をまとめたものである。
調査対象は red_quilt 0.8.0(`/Users/maki/git/red_quilt`)、
比較対象は upstream 作業ブランチ(kmuto/review の `ast-renderer`)にある
`lib/review/ast/markdown_adapter.rb`(904 行)が markly に対して行っている呼び出しである。

結論を先に書くと、必要なノード型と属性は red_quilt にほぼ揃っている。
足りないのは公開面(private に隠れている)と、位置情報のバグ 1 件である。

---

## 1. バグ: 多バイト文字でソース位置がずれる

### 症状

`NodeRef#source_location` が返す行番号が、ASCII のみの文書では正しく、
日本語を含む文書では狂う。Re:VIEW の文書はほぼ日本語なので、このままでは
Markdown 章の位置情報が全滅する。

再現(red_quilt 0.8.0):

```ruby
require "red_quilt"

RedQuilt.parse("# H1\n\npara\n").root.children.each { |n| p [n.type, n.source_location] }
# [:heading,   {start_line: 1, start_column: 2, end_line: 1, end_column: 4}]
# [:paragraph, {start_line: 3, start_column: 0, end_line: 3, end_column: 4}]   ← 正しい

RedQuilt.parse("# 見出し\n\n本文\n").root.children.each { |n| p [n.type, n.source_location] }
# [:heading,   {start_line: 1, start_column: 2, end_line: 4, end_column: 1}]   ← end_line が 4(正: 1)
# [:paragraph, {start_line: 4, start_column: 3, end_line: 4, end_column: 5}]   ← start_line が 4(正: 3)
```

### 原因

`lib/red_quilt/source_map.rb` で、行頭テーブルを作る側と引く側で単位が食い違っている。

```ruby
def line_column(byte_offset)
  line = (@line_starts.bsearch_index { |s| s > byte_offset } || @line_starts.length) - 1
  line_start = @line_starts[line]
  # ここは byte_offset / line_start をバイトとして扱う
  column = @source.byteslice(line_start, byte_offset - line_start).to_s.length
  { line: line + 1, column: column }
end

def build_line_starts(source)
  starts = [0]
  pos = 0
  while (idx = source.index("\n", pos))
    starts << (idx + 1)   # String#index は「文字」インデックスを返す
    pos = idx + 1
  end
  starts
end
```

`build_line_starts` は `String#index` の戻り値、すなわち文字オフセットを保存している。
一方 `line_column` は引数も `@line_starts` の要素もバイトオフセットとして扱う
(`SourceSpan` も `start_byte` / `end_byte` と名乗っており、バイトが正)。
ASCII では両者が一致するため露見せず、多バイト文字が入ると行数がずれる。

### 修正案

`SourceSpan` がバイトを名乗っている以上、行頭テーブルもバイトで持つのが筋である。
`each_line` で `bytesize` を累積すれば O(n) で済む。

```ruby
def build_line_starts(source)
  starts = [0]
  offset = 0
  source.each_line do |line|
    offset += line.bytesize
    starts << offset
  end
  # 末尾が改行で終わらない場合、最後の要素は行頭ではなく終端なので落とす
  starts.pop if starts.size > 1 && !source.end_with?("\n")
  starts
end
```

この差し替えをモンキーパッチで当てて確認した結果:

```
日本語:
  heading:   {start_line: 1, start_column: 2, end_line: 1, end_column: 5}
  paragraph: {start_line: 3, start_column: 0, end_line: 3, end_column: 2}
混在("# 見出し H1" / "本文 text" / "- 項目"):
  heading:   {start_line: 1, ...}
  paragraph: {start_line: 3, ...}
  list:      {start_line: 5, ...}
```

いずれも実際の行と一致する。
なお修正の検証はモンキーパッチで行い、red_quilt のワーキングツリーは変更していない。

### 回帰テストの提案

行頭テーブルの単位取り違えは ASCII のテストをいくら足しても捕まらない。
多バイト文字を含むフィクスチャを 1 本置いておくと再発を防げる。

```ruby
def test_source_location_with_multibyte_source
  doc = RedQuilt.parse("# 見出し\n\n本文\n")
  heading, paragraph = doc.root.children
  assert_equal 1, heading.source_location[:start_line]
  assert_equal 1, heading.source_location[:end_line]
  assert_equal 3, paragraph.source_location[:start_line]
end
```

---

## 2. API 提案

### 2.1 ノード属性を `NodeRef` の公開メソッドにする(最優先)

アダプタが必要とする属性は `Arena` に既に全て存在する。

`heading_level` / `list_ordered?` / `list_start` / `list_tight?` / `list_delimiter` /
`code_block_info` / `link_destination` / `link_title` /
`footnote_label` / `footnote_number` / `table_row_header?` / `table_cell_header?`

しかし `NodeRef` の公開メソッドは
`children` / `document` / `each` / `find_all` / `info` / `node_id` /
`source_location` / `source_span` / `text` / `to_h` / `type` / `walk` だけで、
上記は private な `ast_attributes` の中と `to_h` の出力にしか現れない。

アダプタは「型で分岐しながら木を歩き、その型固有の属性を読む」コードなので、
欲しいのは `node.heading_level` であって `node.to_h[:attributes][:level]` ではない。
`to_h` は木全体分の Hash を作るため、走査のたびに呼ぶ用途には重すぎる。

提案: 上記アクセサを `NodeRef` の公開メソッドとして出す。

```ruby
node.heading_level      # => 2      (HEADING 以外は nil)
node.list_ordered?      # => true   (LIST 以外は nil)
node.list_start         # => 1
node.link_destination   # => "https://example.com"  (LINK / IMAGE)
node.link_title         # => "title"
node.footnote_label     # => "fn1"  (FOOTNOTE_DEFINITION / FOOTNOTE_REFERENCE)
node.header?            # => true   (TABLE_ROW / TABLE_CELL)
```

型が合わないときは nil を返す方針が扱いやすい。
現状 `info` だけは CODE_BLOCK 以外で `""` を返すので、そこも nil に揃うと
「値が無い」と「空文字」の区別で迷わなくなる。

### 2.2 `literal` と `text` を分ける

現状の `NodeRef#text` は「子が無ければ自分の内容、あれば子孫の連結」という二役である。
アダプタはこの 2 つを別々に必要とする。

- ノード自身の生の内容
  `html_block` の生 HTML(review-ast ではこれをそのまま `EmbedNode` にする)、
  `code_block` の本文、`text` ノードの文字列。
- 子孫を平坦化した文字列
  見出しキャプションやリンクラベルの組み立て。

提案: `literal`(そのノード自身の内容。コンテナでは nil)と
`text`(子孫を平坦化した文字列)に分ける。
生 HTML を子孫連結と取り違える事故が構造的に起きなくなる。

### 2.3 `start_line` / `start_column` を直接読めるようにする

`source_location` はノードごとに Hash を生成するため、全ノードを歩く用途では無駄が出る。
`start_line` / `start_column`(必要なら `end_line` / `end_column`)を
単独のリーダーとして持たせてほしい。

あわせて座標の基準を明示してほしい。実測では次のように混在している。

- 行は 1-based(`# H1` が `start_line: 1`)
- 列は 0-based(行頭から始まる段落が `start_column: 0`)

review-ast の `SourceLocation` は行・列とも 1-based なので、
1-based に揃えてもらえるとそのまま渡せる。
揃えない場合でも、どちらの基準かを README か RBS に明記してほしい。

もう 1 点、見出しの span がマーカーを含まず本文から始まっている
(`# H1` で `start_column: 2` = `H` の位置)。
エラー表示の指し先としてはマーカー先頭のほうが自然なので、
ブロック開始位置に寄せるほうが使いやすい。

### 2.4 パースオプション

実測した既定値:

| 機能 | 既定 | 備考 |
|---|---|---|
| テーブル | 有効 | `:table` / `:table_row` / `:table_cell` が出る |
| 打消し線 | 有効 | `:strikethrough` |
| HTML ブロック | 有効 | `allow_html` の値によらず `:html_block` ノードは生成される |
| 脚注 | 無効 | `footnotes: true` が必要 |
| 拡張 autolink | 無効 | `extended_autolinks: true` が必要 |

review-ast 側の呼び出しは次のようになる。

```ruby
RedQuilt.parse(source, footnotes: true, extended_autolinks: true)
```

`dialect: :gfm` のようなプリセットがあると意図が読み取りやすいが、優先度は低い。

---

## 3. 参考: ノード型の対応(API 変更は不要)

移植時のリネーム表。red_quilt 側に不足している型はない。

| markly(元実装) | red_quilt |
|---|---|
| `:header` | `:heading` |
| `:hrule` | `:thematic_break` |
| `:code` | `:code_span` |
| `:emph` | `:emphasis` |
| `:linebreak` | `:hardbreak` |
| `:table_header` | `:table_row`(`header?` で判別) |
| `:document` `:paragraph` `:blockquote` `:list` `:list_item` `:code_block` | 同名 |
| `:html_block` `:html_inline` `:strikethrough` `:text` `:softbreak` | 同名 |
| `:link` `:image` `:strong` `:table` `:table_cell` | 同名 |
| `:footnote_definition` `:footnote_reference` | 同名 |

---

## 4. 取り込み側(review-ast)に残る判断

red_quilt の `required_ruby_version` は `>= 3.3` で、review-ast の現在の宣言 `>= 3.1` より高い。
別途検討している `review-math_ml` も `Data.define` を使うため `>= 3.2` を要求する。
Markdown 対応を入れる時点で review-ast の下限を引き上げる判断が必要になる。
3.3 は 3.2 を包含するので、まとめて決めるのが無駄がない
(Ruby 3.1 は 2025-03 に EOL、3.2 は 2026-03 に EOL 予定)。

## 5. 進め方

1 のバグ修正が前提条件である。位置情報が正しくならないと、Markdown 章の
`SourceLocation` が全て誤りになり、項目 10 の手順 1(SourceLocation 化)を検証できない。

2.1 と 2.2 は移植作業に直接効く。これが無いとアダプタは `to_h` 経由か
private メソッドへの到達で書くことになり、どちらも避けたい。

2.3 と 2.4 は無くても書けるが、あると素直になる。

---

## 6. 対応結果(red_quilt 0.9.0, 2026-07-20)

| 項目 | 結果 |
|---|---|
| 1. 多バイトでの位置ズレ | 対応済み |
| 2.1 ノード属性のアクセサ公開 | 対応済み(`info` の nil 化を含む。破壊的変更) |
| 2.2 `literal` と `text` の分離 | 先送り(6.6) |
| 2.3 `start_line` 等の直読み | 先送り(6.6) |
| 2.3 座標基準の明記 | 対応済み |
| 2.3 列を 1-based に | 対応済み(破壊的変更) |
| 2.3 heading span のマーカー込み | 対応済み(想定より広範囲。破壊的変更) |
| 2.4 パースオプション | 対応不要(既に全て存在) |
| 4. Ruby バージョン | 前提が変わった(下記) |

### 6.1 バグ修正(項目 1)

指摘のとおりであった。`build_line_starts` が `String#index` の文字インデックスを保存し、
`line_column` がそれをバイトとして引いていた。

修正は提案の `each_line` 版ではなく、`source.b` を走査する形とした。結果は同一で、
差分が 1 行に収まり、lexer / builder が既に持つ「バイト走査には `.b` ビューを使う」
という既存イディオムと揃うためである。提案書の期待値と一致することを確認した。

なお、多バイトの位置情報テストは red_quilt 側に既に存在していたが、
単一行の文書だったため行頭テーブルのズレが発現していなかった。
複数行のフィクスチャを追加してある。

### 6.2 位置情報の正規化(項目 2.3)

調査の結果、これは好みの問題ではなく仕様準拠の問題であることが分かったため、
提案書の「揃えない場合でも基準を明記」ではなく、1-based に揃える方を採用した。

根拠は Markdown 領域の慣行が一致していることである。

| 実装 | line | column | offset |
|---|---|---|---|
| cmark / cmark-gfm(markly の中身) | 1-based | 1-based | — |
| unist / mdast / remark | 1-based | 1-based | 0-based **文字** |
| red_quilt 0.8.0 | 1-based | 0-based | 0-based **バイト** |

0-based 列は Ruby 自身のパーサ(Ripper・Prism)や LSP の流儀であり、
Markdown の隣人はいずれも 1-based である。

あわせて、red_quilt の mdast レンダラが unist 仕様に違反していたことが判明した。
`column: 0` は unist の「1-indexed integer」の範囲外であり、
`offset` はバイトオフセットを入れていたが unist の定義は「0-indexed の**文字**」である。
後者は項目 1 と同種の取り違えが別の場所に残っていたものである。両方修正した。

### 6.3 ブロック span(項目 2.3 後半)

提案書は heading のみを挙げていたが、参照実装(commonmark.js と
mdast-util-from-markdown)を実際に動かして突き合わせたところ、
同じ欠陥が広範囲に及んでいた。以下を修正した。

- ATX 見出しが `#` を含まない
- setext 見出しが `===` / `---` 下線を含まない
- blockquote が `>` を含まない
- フェンスコードブロックが両フェンスを含まない
  — これは列ではなく**行番号が誤っていた**(開始フェンスの 1 行下を指していた)
- 段落・setext 見出し・リスト・水平線が先頭インデントを含んでいる
- `list_item` がマーカーではなく本文から始まる

結果として、検証した 18 ケース全てで mdast と一致する。
唯一の相違は未閉じフェンスで、ここは mdast と cmark 自体が食い違っており cmark 側を採用した。

エラー表示の指し先という観点では、フェンスコードブロックの行ずれが実害として最も大きい。
Re:VIEW の文書でコードブロックは頻出するため、項目 10 の SourceLocation 化には
この修正が効くはずである。

### 6.4 取り込み側で必要な追随

破壊的変更であるため、review-ast 側で以下の対応が要る。

- 列に +1 する処理を入れていた場合は削除する(red_quilt が 1-based になった)
- heading の span が `# ` を含まない前提のコードがあれば見直す
- ブロックの span が本文のみを指す前提のコードがあれば見直す

`NodeRef#text` の挙動は変えていない。見出しのテキストは従来どおり本文のみで、
マーカーは含まない。

### 6.5 ノード属性のアクセサ(項目 2.1)

対応済みである。`NodeRef` に以下を追加した。いずれも型が合わないときは nil を返す。

```ruby
node.heading_level     # HEADING: 1..6
node.list_ordered?     # LIST
node.list_start        # LIST
node.list_tight?       # LIST
node.list_delimiter    # LIST: "-" / "." など
node.link_destination  # LINK / IMAGE
node.link_title        # LINK / IMAGE
node.footnote_label    # FOOTNOTE_DEFINITION / FOOTNOTE_REFERENCE
node.footnote_number   # FOOTNOTE_DEFINITION / FOOTNOTE_REFERENCE
node.header?           # TABLE_ROW / TABLE_CELL
```

提案書の案からの相違点は 2 つある。

`footnote_number` は FOOTNOTE_REFERENCE 専用にする案だったが、実測すると
FOOTNOTE_DEFINITION も解決済みの番号を持っていたため、両方で読めるようにした。

`header?` は提案書の案どおり TABLE_ROW / TABLE_CELL を 1 つのメソッドで扱う。
表の外では false ではなく nil を返す。段落は「ヘッダでない行」ではなく
ヘッダ性を持たないためで、どちらも偽値なので `if node.header?` の書き味は変わらない。

`info` は CODE_BLOCK 以外で nil を返すようにした(0.8.0 では `""`)。
情報文字列なしで書かれたコードブロックは従来どおり `""` を返すため、
「型が違う」と「info が空」が区別できる。**これは 0.8.0 に対する破壊的変更である。**

実装上の注意として、これらは Arena への単純委譲ではない。
「必要な属性は Arena に既に存在するので公開するだけ」という前提は正確ではなかった。
Arena のアクセサは型を検証せず、生カラムを共有しているため、
型が合わないときに nil や 0 ではなく**別フィールドの実データ**が返る。実測値を示す。

```
list       | text="-"             link_dest="-"            list_delim="-"
paragraph  | text="item"          link_dest="item"         list_delim="item"
link       | text="http://ex.com" link_dest="http://ex.com"
code_block | text="code\n"                                 link_title="rb"
```

`link_destination` を段落に呼ぶと本文が、`link_title` をコードブロックに呼ぶと
info 文字列が返る。誤用が静かに通るため、追加したアクセサは全て
`NodeType` 判定を挟んでいる。提案書の「型が合わないときは nil を返す方針」が
まさに正しく、それが `NodeRef` ラッパを設ける価値であった。

Arena 側の挙動は変えていない。従来どおり生の層であり、型検査を行わない。
アダプタからは `NodeRef` のアクセサを使うこと。

`to_h` が重いという指摘も裏付けが取れた。257 ノードのリストに対し `to_h` は
5391 オブジェクトを確保する。追加したアクセサは 10,000 回呼んでも
ベースラインと同じ、すなわち呼び出しごとの確保はゼロである。

### 6.6 先送りとした項目(2.2 / 2.3 の直読みアクセサ)

いずれも red_quilt 側で対応せず先送りとした。アダプタは `to_h` や private
メソッドに頼らずに書けるため、着手の前提条件にはならない。
必要になった時点で改めて判断する。

#### 2.2 `literal` と `text` の分離

`literal` を素朴に arena の str1 に対応させると、**LIST は delimiter(`"-"`)、
LINK / IMAGE は destination(URL)、FOOTNOTE_DEFINITION は label** を返す。
`node.literal` がリンクで URL を返すのは、提案書が防ごうとしている
「生 HTML を子孫連結と取り違える事故」と同種の事故である。
実装するなら `{CODE_BLOCK, HTML_BLOCK, TEXT, CODE_SPAN, HTML_INLINE}` の
allowlist が必須で、それ以外は nil を返す形になる。

先送りの理由は、現状 `html_block` も `code_block` も葉ノードであるため
`NodeRef#text` が既に生の内容を返しており、この事故が今日は起きていないことである。
`literal` が新たに取れるようにするものは実質ない。価値は契約の明文化にあり、
`text` の契約(葉なら自身の内容、そうでなければ子孫連結)が将来変わったときに
初めて効く。アダプタを実際に書いて困った時点で入れるのが妥当と判断した。

なお `text` の現在の契約は「`html_block` が生 HTML を返すことを保証する」ものでは
ない点に注意されたい。今それが成り立つのは葉ノードだからである。

#### 2.3 `start_line` / `start_column` の直読み

`source_location` は 1 回あたり約 6 オブジェクトを確保する(`source_span` は 1)。
実在するコストだが、6919 ノードの文書で 4 万個程度であり、劇的ではない。
座標基準の明記(項目 2.3 の後半)は対応済みなので、
残るのは純粋な最適化であり、先送りとした。

### 6.7 項目 4 の前提変更

red_quilt の `required_ruby_version` を **`>= 3.1.0` に引き下げた**(0.8.0 では `>= 3.3.0`)。
3.1 での唯一の非互換は `String#byteindex`(3.2 以降)で、
2 箇所ともバイナリビュー上の呼び出しだったため `String#index` で置換できた。
3.1 / 3.2 / 3.3 / 3.4 / 4.0 でテストが通ることを確認しており、CI も 5 バージョンで回している。

したがって、red_quilt のために review-ast の下限を引き上げる必要はない。
`review-math_ml` の 3.2 要求は別途残るため、判断材料としては弱まるのみである。

なお red_quilt は複数 Ruby 対応にあたり `Gemfile.lock` を git 管理から外した。
ある Ruby で解決した lockfile は他のバージョンに存在しない gem を pin するためである。

### 6.8 補足: インライン要素の位置情報

リスト項目や blockquote の内部など、ブロック変換を経たコンテンツのインライン要素は
`source_location` が nil を返す(`track_source: false` のため)。
アダプタがインラインレベルの位置情報を必要とする場合、これは別途の課題となる。
今回の対応範囲には含めていない。
