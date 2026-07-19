# Re:VIEW AST セマンティクス

本書は review-ast の木のビルダー非依存な仕様である。各ノードの意味、それを生む
ソース構文、コンパイルパイプラインが木をどう変換するか、AST がレガシー Re:VIEW
ビルダーと意図的に異なる箇所、そして再実装が適合と見なされるために満たすべき条件
を定める。英語版 `doc/ast-semantics.md` と対の関係にあり、内容は同一を保つ。

想定読者は、シリアライズ済み AST(JSON 形式は `lib/review/ast/json_serializer.rb`)
を消費し、Ruby ソースを読まずに Re:VIEW 文書を描画・解析したい人である。
パリティ第一のプロジェクト方針は変わらない。AST はビルダーの出力を再現する
(LaTeX は DVI 一致、IDGXML は byte 一致、HTML は rendered-equivalent)。ただし
[乖離レジストリ](#4-乖離レジストリ)が別途定める箇所を除く。

状態: 生きた文書。`test/ast/test_semantics_coverage.rb` によって鮮度が保たれ、
コンパイラが本書に載っていないブロック命令・特殊インライン命令を獲得すると失敗する。

## 1. ノード目録

すべてのノードは `type`、ソース `location`(`filename`・`lineno`・`column`)、
`children` を持つ。番号付き定義ノードは `definition_number`([番号付け](#23-定義番号)
参照)を、`//noindent` の対象は `noindent` を、画像を持つノードは解決済みの
`image_path` を持つ。

| ノード | 意味 | 主要フィールド | 生成する構文 |
|---|---|---|---|
| `DocumentNode` | 章全体・木の根 | — | コンパイルされた `.re` 章 |
| `HeadlineNode` | 見出し | `level`, `label`, `tag`(`nonum`/`notoc`/`nodisp`), `raw_caption`, `caption_node` | `=`, `==`, … の行 |
| `ParagraphNode` | 段落 | `noindent` | 空行区切りのテキスト |
| `TextNode` | リテラルなテキスト片 | `content` | テキスト(`LeafNode`) |
| `CodeLineNode` | コードブロック内の1行 | `content` | `//list` 等の内部行(`LeafNode`) |
| `InlineNode` | インライン命令 | `inline_type`, `args` | `@<b>{…}`, `@<code>{…}`, … |
| `ReferenceNode` | 相互参照(コンパイル時に番号/ラベルへ解決) | `inline_type`, `resolved_data` | `@<hd>`, `@<img>`, `@<fn>`, … |
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

- Stage B — 可換な directive マイクロパス群。各々が1つの directive を、異なる型の
  直後ノード1つへ lowering する: `//tsize`→表、`//firstlinenum`→コード、
  `//noindent`→段落/引用、`//olnum`→順序付きリスト。対象が互いに素なので可換
  (どの並べ替えでも同じ core tree になる)。
- Stage A — 順序依存の構造パス群: `//beginchild`/`//endchild` による子の入れ子化、
  順序付きリストの項目番号付与、`nonum`/`notoc`/`nodisp` 見出しとコラムの auto-id 生成。

結果は core tree: `DirectiveNode` は残らず、その効果は対象ノードのフィールドとして
存在する。参照解決と画像パス解決は別フェーズで、フル(描画)ビルドのときだけ走る。

### 2.2 ブロック分離

隣接するブロックは別々の兄弟ノードとしてモデル化され、コンパイラはブロック境界を
またいで統合・平坦化しない(これが避けるバグの種類 — doc/design-improvements #2)。
再実装はブロック境界を木の中で観測可能に保たねばならない。

### 2.3 定義番号

番号付き定義(`//list`, `//image`, `//table`, `//texequation`, `//graph`、脚注)は
コンパイル時に Indexer が採番し、`definition_number` = `{number, chapter_number}` を
ノードへ stamp する。よって描画側は「図2.1」を出すのに章インデックスを要さない。
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

これらは素の装飾 `InlineNode` ではなく専用ノードを作る:

- 内容: `@<embed>`, `@<ruby>`, `@<href>`, `@<kw>`, `@<raw>`。
- 参照(`ReferenceNode`): `@<img>`, `@<imgref>`, `@<list>`, `@<table>`, `@<eq>`,
  `@<fn>`, `@<endnote>`, `@<column>`, `@<w>`, `@<wb>`, `@<bib>`, `@<bibref>`。
- クロス参照(`ReferenceNode`): `@<hd>`, `@<chap>`, `@<chapref>`, `@<title>`,
  `@<sec>`, `@<secref>`, `@<sectitle>`, `@<labelref>`, `@<ref>`。

その他の `@<name>{…}`(`@<b>`, `@<i>`, `@<code>`, `@<tt>`, `@<kw>`, `@<bou>`,
`@<ami>`, `@<u>`, `@<em>`, `@<strong>`, …)は `inline_type` が `name` の装飾
`InlineNode` になり、描画側の `render_inline_<name>` が出力を決める。

## 4. 乖離レジストリ

レガシービルダーとの意図的な差異。各項目はトリアージ済みの仕様の問い
(`doc/spec-questions.md`)であり、upstream(kmuto/review)が裁定するまでは AST は
ビルダーの現挙動に一致させ、既存の本がそのままビルドできるようにする。互換分類
(doc/design-improvements #6 より): 即修正(どの文書も依存し得ない)、ゲート
(`review_version` で保護)、正典化(仕様として採用)。

| # | 構文 | ビルダーの挙動 | AST の挙動 | 想定分類 | upstream |
|---|---|---|---|---|---|
| 1 | Part 見出しの TOC 名 | 星付き Part は `part`、`[nonum]` Part は `chapter` | ビルダーに一致 | 正典化? | open |
| 2 | `@<comment>` で空描画になる表セル | 空描画セルが潰れ行がずれる | ビルダーに一致 | 即修正 | open |
| 3 | 表ヘッダ/本体区切りの閾値 | LATEXBuilder ではエスケープ後の行で検出(エスケープ依存) | ビルダーに一致 | ゲート | open |
| 4 | `footnotetext: true` + 見出し中の脚注 | 保護なしの `\footnotemark` を出す(組版不能) | ビルダーに一致 | 即修正 | open |
| 5 | 表セル先頭ドットのエスケープ | HTML は `..15`→`.15` に、IDGXML は `..15` のまま | 各ビルダーに一致 | 即修正 | open |

乖離ではないが明記すべき点: `//tsize` は IDGXML ではソースの数値 CSV を直接読み、
LaTeX 列指定(`|l|c|r|`)は IDGXML では無視される(等分)。ビルダーと同一
(doc/design-improvements #5)。

## 5. 適合基準

再実装が `(ソース, review_version)` の組について適合するのは、段階を追って次を満たす
ときである:

1. surface tree — ソースの構文解析が同じ surface tree(シリアライズ形式に対して
   スキーマ妥当)を、同じノード型・フィールドで生む。
2. core tree — lowering 後に同じ core tree(`DirectiveNode` なし、directive の効果は
   対象ノードのフィールド、2.3 の番号付け)。
3. 描画 — 形式ごとにその厳密度で同じ出力: LaTeX は DVI 一致、IDGXML は byte 一致、
   HTML は rendered-equivalent、plaintext/TOP は byte 一致。

版の扱い: セマンティクスは版に依存しない。ただしトリアージ済みの乖離点だけは
`review_version` の範囲を持つ。ノードスキーマは版で分岐させず、分岐は
コンパイラ/レンダラの挙動にのみ置く。ダンプはエンベロープに生成時の
`review_version` を記録する。

実行可能な適合キットは、シリアライズ AST のスキーマ、samples/PBT コーパス、
差分比較器(DVI 用 `tools/compare_book.rb`、IDGXML/HTML スイープ)であり、Ruby
ソースを読まずに実行できる。
