# Re:VIEW AST セマンティクス

本書は review-ast の木のビルダー非依存な仕様である。各ノードの意味、それを生む
ソース構文、コンパイルパイプラインが木をどう変換するか、AST がレガシー Re:VIEW
ビルダーと意図的に異なる箇所、そして再実装が適合と見なされるために満たすべき条件
を定める。英語版 `doc/ast-semantics.md` と対の関係にあり、内容は同一を保つ。

想定読者は、シリアライズ済み AST(JSON 形式は `lib/review/ast/json_serializer.rb`)
を消費し、Ruby ソースを読まずに Re:VIEW 文書を描画・解析したい人である。
パリティ第一の方針は実装済みの構文について成り立つ。AST はビルダーの出力を再現する
(LaTeX は DVI 一致、IDGXML は byte 一致、HTML は rendered-equivalent)。ただし
[乖離レジストリ](#4-乖離レジストリ)が別途定める箇所と、まだレンダラに未実装の一部の
命令(LaTeX レンダラの `//graph` と `@<w>`/`@<wb>` — 乖離レジストリ参照)を除く。

状態: 生きた文書。`test/ast/test_semantics_coverage.rb` によって鮮度が保たれ、
コンパイラが本書に載っていないブロック命令・特殊インライン命令を獲得すると失敗する。

## 1. ノード目録

すべてのノードは `type` とソース `location`(`filename`・`lineno`・`column`)を
持つ。ブランチノードは `children` を持つが、leaf ノード(`LeafNode` の派生である
`TextNode`・`ReferenceNode`・`ImageNode`・`TexEquationNode`・`EmbedNode`)は JSON に
`children` キーを出さない。番号付き定義ノードは `definition_number`
([番号付け](#23-定義番号)参照)を、`//noindent` の対象は `noindent` を、画像を持つ
ノードは解決済みの `image_path` を持つ。

| ノード | 意味 | 主要フィールド | 生成する構文 |
|---|---|---|---|
| `DocumentNode` | 章全体・木の根 | — | コンパイルされた `.re` 章 |
| `HeadlineNode` | 見出し | `level`, `label`, `tag`(`nonum`/`notoc`/`nodisp`), `raw_caption`, `caption_node` | `=`, `==`, … の行 |
| `ParagraphNode` | 段落 | `noindent` | 空行区切りのテキスト |
| `TextNode` | リテラルなテキスト片 | `content` | テキスト(`LeafNode`) |
| `CodeLineNode` | コードブロック内の1行 | `line_number`, `original_text`, `children`(インライン記法) | `//list` 等の内部行(leaf ではなくブランチ) |
| `InlineNode` | インライン命令 | `inline_type`, `args` | `@<b>{…}`, `@<code>{…}`, `@<img>{…}`, … |
| `ReferenceNode` | 相互参照(コンパイル時に番号/ラベルへ解決) | `ref_id`, `context_id`, `resolved_data` | 参照命令の `InlineNode` の子(例: `@<hd>`, `@<img>`, `@<fn>`) |
| `CaptionNode` | ブロック/見出しのキャプション | — | ブロックのキャプション引数 |
| `ListNode` | リストコンテナ | `list_type`(`ul`/`ol`/`dl`) | `*`, `1.`, `:` の行、`//ul`/`//ol`/`//dl` |
| `ListItemNode` | リスト項目 | `level`, `term_children`(`dl` 用) | リスト項目、`//li`/`//dt`/`//dd` |
| `CodeBlockNode` | 逐語/コードブロック | `id`, `lang`, `code_type`, `line_numbers` | `//list`, `//listnum`, `//emlist`, `//emlistnum`, `//cmd`, `//source` |
| `ImageNode` | 画像 | `id`, `image_type`, `image_path`, `metric` | `//image`, `//indepimage`, `//numberlessimage` |
| `TableNode` | 表 | `id`, `table_type`(`table`/`emtable`/`imgtable`), `tsize`, ヘッダ行 | `//table`, `//emtable`, `//imgtable` |
| `TableRowNode` | 表の行 | — | 表の本体/ヘッダ行 |
| `TableCellNode` | 表のセル | ヘッダフラグ | タブ区切りのセル |
| `MinicolumnNode` | 注意書き/ミニコラム | `minicolumn_type` | `//note`, `//memo`, `//tip`, `//info`, `//warning`, `//important`, `//caution`, `//notice` |
| `ColumnNode` | コラム | `label`, `level`, `caption_node` | `===[column]` … `===[/column]` |
| `FootnoteNode` | 脚注/後注の定義 | `id`, `footnote_type`(`footnote`/`endnote`) | `//footnote`, `//endnote` |
| `TexEquationNode` | 別行立て数式 | `id`, `caption_node` | `//texequation` |
| `EmbedNode` | 指定ビルダー向けの生の埋め込み | `embed_type`, 対象ビルダー | `//embed`, `@<embed>`, `//raw`, `@<raw>` |
| `BlockNode` | 専用ノードへ lowering されない汎用ブロック | `block_type`, `args` | `//bibpaper`, `//graph`, `//box`, `//insn`, `//point`, `//term`, `//doorquote`, 制御命令, … |
| `DirectiveNode` | 次のノードを修飾する `//directive`。lowering で除去 | `directive_type`, `args` | `//tsize`, `//firstlinenum`, `//noindent`, `//olnum`, `//beginchild`, `//endchild` |
| `MarkdownHtmlNode` | Markdown 中の生 HTML | `html_content`, `html_type` | Markdown ソース(Markdown コンパイラは未配線) |
| `LeafNode` | 子を持たない内容ノードの抽象基底 | — | 直接シリアライズされない |

## 2. パイプラインセマンティクス

`Compiler#compile_to_ast(input)` は `CompileInput`(ソーステキストと、画像/
クロス章ルックアップ用のサービスハンドル)を受け、次の三段階で観測可能な木を作る。

### 2.1 surface tree → lowering パス群 → core tree

構文解析は、次のノードを修飾する `//directive` マーカーを表す `DirectiveNode` を
まだ含む surface tree を生む。続いて二つの順序付き段階が走る
(`Compiler#post_processors`。nanopass 的に分解 — doc/design-improvements #3 参照):

- Stage B — 可換な directive マイクロパス群。各々が1つの directive を、後続の兄弟
  から探索した「次の適格な対象」へ lowering する(前方探索なので途中のノードを飛び
  越えうる。例: 間に `//embed` があっても `//noindent` は後続段落へ適用される):
  `//tsize`→表、`//firstlinenum`→コード、`//noindent`→段落/引用、`//olnum`→順序付き
  リスト。対象が互いに素なので可換(どの並べ替えでも同じ core tree になる)。
- Stage A — 順序依存の構造パス群: `//beginchild`/`//endchild` による子の入れ子化、
  順序付きリストの項目番号付与、`nonum`/`notoc`/`nodisp` 見出しとコラムの auto-id 生成。

結果は core tree: `DirectiveNode` は残らず、その効果は対象ノードのフィールドとして
存在する。参照解決と画像パス解決は別フェーズで、フル(描画)ビルドのときだけ走る。

### 2.2 ブロック分離

隣接するブロックは別々の兄弟ノードとしてモデル化され、コンパイラはブロック境界を
またいで統合・平坦化しない(これが避けるバグの種類 — doc/design-improvements #2)。
再実装はブロック境界を木の中で観測可能に保たねばならない。例外は LATEXBuilder に
合わせたもの: 空行で区切られた連続する定義リスト(`:` / `//dl`)は1つに統合され、
`//beginchild`/`//endchild` をまたぐ `//ul`/`//ol` の継続は親リストへ統合される
(`ListStructureNormalizer`)。

### 2.3 定義番号

番号付き定義(`//list`, `//image`, `//table`, `//texequation`, `//graph`,
`//bibpaper`、脚注)はコンパイル時に Indexer が採番し、`definition_number` =
`{number, chapter_number}` をノードへ stamp する。よって描画側は「図2.1」を出すのに
章インデックスを要さない。`//indepimage` と `//numberlessimage` は番号なしで
`definition_number` を持たない。`//imgtable` は表として採番(`definition_number`)
されるが、未束縛画像のフォールバック描画用に別途 `imgtable_image_number` も持つ。
カウンタとその共有(image/graph は1つを共有、indepimage/numberlessimage/imgtable の
画像は別の1つを共有)はレガシー IndexBuilder に一致する。doc/design-improvements
#1 と #7 参照。

章タイトルは最初の見出しの `raw_caption`(最初の見出しの源泉忠実なキャプション。
マーカー/ラベルを除去し、インライン記法は生のまま)であり、本体の `BookUnit#title`
ではなく AST が所有する。

## 3. 命令リファレンス

コンパイラは固定のブロック命令集合(`BLOCK_COMMAND_TABLE`)と特殊インライン命令集合
(`DEFAULT_INLINE_HANDLERS`)を認識する。網羅性検査が各命令を文書化済みセマンティクス
へ対応付けられるよう、両方をここに列挙する。

### 3.1 ブロック命令

- コードブロック(`CodeBlockNode`): `//list`, `//listnum`, `//emlist`,
  `//emlistnum`, `//cmd`, `//source`。
- 画像(`ImageNode`): `//image`, `//indepimage`, `//numberlessimage`。
- 表(`TableNode`): `//table`, `//emtable`, `//imgtable`。
- リスト(`ListNode`/`ListItemNode`): `//ul`, `//ol`, `//dl`, `//li`, `//dt`,
  `//dd`。
- ミニコラム(`MinicolumnNode`): `//note`, `//memo`, `//tip`, `//info`,
  `//warning`, `//important`, `//caution`, `//notice`。
- コラム(`ColumnNode`): `//column`。
- 脚注(`FootnoteNode`): `//footnote`, `//endnote`。
- 数式(`TexEquationNode`): `//texequation`。
- 埋め込み(`EmbedNode`): `//embed`, `//raw`。
- 引用系ブロック(`BlockNode`): `//read`, `//quote`, `//blockquote`, `//lead`,
  `//centering`, `//flushright`, `//address`, `//talk`。
- その他のブロック(`BlockNode`): `//doorquote`, `//bibpaper`, `//graph`, `//box`,
  `//insn`, `//point`, `//term`。
- 制御命令(`BlockNode`): `//comment`, `//blankline`, `//pagebreak`, `//label`,
  `//printendnotes`, `//hr`, `//bpo`, `//parasep`。
- directive(`DirectiveNode`。lowering で除去): `//olnum`, `//noindent`,
  `//firstlinenum`, `//tsize`, `//beginchild`, `//endchild`。

### 3.2 特殊インライン命令

これらは専用のハンドラを持つが、木の形はグループごとに異なる。

- パススルー、直接 `EmbedNode`: `@<embed>`, `@<raw>`。
- 素の `InlineNode`(`inline_type` = 命令名、引数がペイロード): `@<ruby>`,
  `@<href>`, `@<kw>`。
- 参照 — `InlineNode`(`inline_type: :img`・`:fn` 等)が、`ref_id`/`context_id`/
  `resolved_data` を持つ `ReferenceNode` を子として包む: `@<img>`, `@<imgref>`,
  `@<list>`, `@<table>`, `@<eq>`, `@<fn>`, `@<endnote>`, `@<column>`, `@<w>`,
  `@<wb>`, `@<bib>`, `@<bibref>`。
- クロス参照 — 同じ `InlineNode` + `ReferenceNode` の形: `@<hd>`, `@<chap>`,
  `@<chapref>`, `@<title>`, `@<sec>`, `@<secref>`, `@<sectitle>`, `@<labelref>`,
  `@<ref>`。

その他の `@<name>{…}`(`@<b>`, `@<i>`, `@<code>`, `@<tt>`, `@<bou>`, `@<ami>`,
`@<u>`, `@<em>`, `@<strong>`, …)は `inline_type` が `name` の装飾 `InlineNode` に
なり、描画側の `render_inline_<name>` が出力を決める。

## 4. 乖離レジストリ

レガシービルダーとの差異。#1 と #4 は AST が byte 単位で再現するケース(トリアージ
済みの仕様の問い `doc/spec-questions.md`。upstream(kmuto/review)の裁定待ち)。
#2・#3・#5 は、ビルダー挙動がバグまたはビルダー固有の癖であるため AST が意図的に
再現しないケース。互換分類(doc/design-improvements #6 より): 即修正(どの文書も
依存し得ない)、ゲート(`review_version` で保護)、正典化(仕様として採用)。

| # | 構文 | ビルダーの挙動 | AST の挙動 | 想定分類 | upstream |
|---|---|---|---|---|---|
| 1 | Part 見出しの TOC 名 | 星付き Part は `part`、`[nonum]` Part は `chapter` | ビルダーを再現 | 正典化? | open |
| 2 | `@<comment>` で空描画になる表セル | 空描画セルが潰れ行がずれる(LATEXBuilder のバグ) | 再現しない: 正しく分割した行を保つ | 即修正 | open |
| 3 | 表ヘッダ/本体区切りの閾値 | LATEXBuilder はエスケープ後の行で検出するため罫線4–11本で既に分割 | 再現しない: 12本閾値(HTML と同じ)を使い、4–11本はデータとして保つ | ゲート | open |
| 4 | `footnotetext: true` + 見出し中の脚注 | 保護なしの `\footnotemark` を出す(組版不能) | ビルダーを byte 単位で再現 | 即修正 | open |
| 5 | 表セル先頭ドットのエスケープ | HTMLBuilder は `..15`→`.15`、IDGXMLBuilder は `..15` のまま | `.15` に正規化(HTML に一致・IDGXML byte 一致とは意図的に非互換) | 即修正 | open |

未実装(再現すべきレンダラ差ではなく単に未対応 — `doc/differential-testing.md`
参照): `//graph`(外部ツール画像)と `@<w>`/`@<wb>`(辞書による語句置換)は AST の
LaTeX レンダラで未実装。

乖離ではないが明記すべき点: `//tsize` は IDGXML ではソースの数値 CSV を直接読み、
LaTeX 列指定(`|l|c|r|`)は IDGXML では無視される(等分)。ビルダーと同一
(doc/design-improvements #5)。

## 5. 適合基準

再実装がソース(および将来版ゲートが入れば `review_version`)について適合するのは、
段階を追って次を満たすときである:

1. surface tree — ソースの構文解析が同じ surface tree(シリアライズ形式に対して
   スキーマ妥当)を、同じノード型・フィールドで生む。
2. core tree — lowering 後に同じ core tree(`DirectiveNode` なし、directive の効果は
   対象ノードのフィールド、2.3 の番号付け)。
3. 描画 — 形式ごとにその厳密度で同じ出力: LaTeX は DVI 一致、IDGXML は byte 一致、
   HTML は rendered-equivalent、plaintext/TOP は byte 一致。

版の扱い(設計意図): セマンティクスは版に依存しない。ただしトリアージ済みの乖離点
だけは `review_version` の範囲を持つ(予定)。ノードスキーマは版で分岐させず、分岐は
コンパイラ/レンダラの挙動にのみ置く。現状ダンプのエンベロープは `ast_format` と
生成時の review 版名を含む `generator` 文字列(例: `review 5.11.0`)のみを記録し、
専用の `review_version` フィールドや版ゲートは未実装。

実行可能な適合キットは、シリアライズ AST のスキーマ、samples/PBT コーパス、
差分比較器(DVI 用 `tools/compare_book.rb`、IDGXML/HTML スイープ)であり、Ruby
ソースを読まずに実行できる。
