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
