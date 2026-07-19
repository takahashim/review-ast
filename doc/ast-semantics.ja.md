# Re:VIEW AST セマンティクス

本書は、review-ast が構築する木(AST)の仕様である。
各ノードの意味、それを生むソース構文、コンパイルパイプラインが木をどう変換するか、AST がレガシー実装と意図的に異なる箇所、そして再実装が適合と見なされる条件を定める。

想定読者は、シリアライズ済みの AST(JSON。実装は `lib/review/ast/json_serializer.rb`)を消費して、Ruby ソースを読まずに Re:VIEW 文書を描画・解析したい人である。
AST やコンパイラの一般概念は既知とするが、Re:VIEW の知識は仮定しない。
Re:VIEW を知らない読者は、まず次節「前提」を読めば以降の構文欄が読めるようになる。

本書は生きた文書である。
`test/ast/test_semantics_coverage.rb` が鮮度を保っており、コンパイラが本書に載っていないブロック命令、特殊インライン命令、ノード型を獲得するとテストが失敗する。
英語版 `doc/ast-semantics.md` と対を成し、網羅する命令、ノード、乖離項目は同一に保つ(本書は日本語読者向けに前提の解説を加えている)。

## 0. 前提: Re:VIEW という入力言語と、パリティ第一の方針

**Re:VIEW** は技術書執筆用の軽量マークアップ言語である。
書籍を章単位の `.re` ファイルとして書き、PDF(LaTeX 経由)、EPUB、Web ページ(HTML)、DTP 用 XML(IDGXML)、プレーンテキストへ変換する。

ソースに現れる構文は、次の三種類を知っていればよい。

- **見出し行**:
  行頭の `=` の個数がレベルを表す(`= 章`、`== 節`、…)。
  `=={label}` のようにラベルを、`==[column]` のように角括弧のタグを付けられる。
- **ブロック命令**:
  `//名前[引数1][引数2]{` から `//}` までが一つのブロックである(本文を持たない `//名前[引数]` の形もある)。
  コードブロック、図、表、脚注などがこの形で書かれる。
- **インライン命令**:
  本文中の `@<名前>{内容}` である。
  太字(`@<b>`)、コード(`@<code>`)、相互参照(`@<img>` など)がこの形で書かれる。

従来の Re:VIEW 実装では、出力形式ごとの「ビルダー」(LATEXBuilder、HTMLBuilder など)が構文解析と出力生成を兼ねていた。
review-ast はこの構文解析を AST として分離し、各形式のレンダラが同じ木から出力を描画する。

**パリティ第一**の方針とは、AST パイプラインの正しさを当面「レガシービルダーと同じ出力を生むこと」で定義することである。
一致の厳密度は形式ごとに異なる。
LaTeX は DVI 一致(TeX の組版結果ファイルどうしの比較。TeX ソースのバイト列ではなく、組版結果(DVI)の一致を見る)、IDGXML は byte 一致、HTML は rendered-equivalent(ブラウザ描画として等価)である。
この方針の例外は二つだけである。
[乖離レジストリ](#4-乖離レジストリ)が明示する箇所と、まだレンダラに未実装の一部の命令(LaTeX レンダラの `//graph` と `@<w>`/`@<wb>`。乖離レジストリ末尾を参照)である。

## 1. ノード目録

すべてのノードは `type` とソース位置 `location`(`filename`、`lineno`、`column`)を持つ。
子を持ちうるノードは `children` を持つ。
**leaf ノード**(抽象基底 `LeafNode` の派生である `TextNode`、`ReferenceNode`、`ImageNode`、`TexEquationNode`、`EmbedNode`)は構造上子を持たず、JSON に `children` キーを出さない。

このほか、状況に応じて付く共通フィールドが三つある。
番号付き定義ノードの `definition_number`([2.3 節](#23-定義番号))、`//noindent` の適用対象が持つ `noindent`、画像を参照するノードが持つ解決済みの `image_path` である。

### 文書構造

| ノード | 意味 | 主要フィールド | 生成する構文 |
|---|---|---|---|
| `DocumentNode` | 章全体。木の根 | — | コンパイルされた `.re` 章 |
| `HeadlineNode` | 見出し | `level`, `label`, `tag`(`nonum`/`notoc`/`nodisp`), `raw_caption`, `caption_node` | `=`, `==`, … の行 |
| `ColumnNode` | コラム(見出し記法で囲む長めの囲み記事) | `label`, `level`, `caption_node` | `===[column]` … `===[/column]` |
| `CaptionNode` | ブロックや見出しのキャプション | — | ブロックのキャプション引数 |

### 本文とインライン

| ノード | 意味 | 主要フィールド | 生成する構文 |
|---|---|---|---|
| `ParagraphNode` | 段落 | `noindent` | 空行区切りのテキスト |
| `TextNode` | リテラルなテキスト片 | `content` | テキスト |
| `InlineNode` | インライン命令 | `inline_type`, `args` | `@<b>{…}`, `@<code>{…}`, `@<img>{…}`, … |
| `ReferenceNode` | 相互参照。コンパイル時に番号やラベルへ解決される | `ref_id`, `context_id`, `resolved_data` | 参照系 `InlineNode` の子(例: `@<hd>`, `@<img>`, `@<fn>`) |

### ブロック要素

| ノード | 意味 | 主要フィールド | 生成する構文 |
|---|---|---|---|
| `CodeBlockNode` | 逐語ブロックとコードブロック | `id`, `lang`, `code_type`, `line_numbers` | `//list`, `//listnum`, `//emlist`, `//emlistnum`, `//cmd`, `//source` |
| `CodeLineNode` | コードブロック内の 1 行。インライン記法を含みうるため leaf ではなくブランチ | `line_number`, `original_text`, `children` | `//list` 等の内部行 |
| `ListNode` | 箇条書きのコンテナ | `list_type`(`ul`/`ol`/`dl`) | `*`, `1.`, `:` の行、`//ul`/`//ol`/`//dl` |
| `ListItemNode` | 箇条書きの項目 | `level`, `term_children`(`dl` の用語側) | リスト項目、`//li`/`//dt`/`//dd` |
| `ImageNode` | 画像 | `id`, `image_type`, `image_path`, `metric` | `//image`, `//indepimage`, `//numberlessimage` |
| `TableNode` | 表 | `id`, `table_type`(`table`/`emtable`/`imgtable`), `tsize`, ヘッダ行 | `//table`, `//emtable`, `//imgtable` |
| `TableRowNode` | 表の行 | — | 表の本体行とヘッダ行 |
| `TableCellNode` | 表のセル | ヘッダフラグ | タブ区切りのセル |
| `MinicolumnNode` | 注意書きの小さな囲み | `minicolumn_type` | `//note`, `//memo`, `//tip`, `//info`, `//warning`, `//important`, `//caution`, `//notice` |
| `FootnoteNode` | 脚注と後注の定義 | `id`, `footnote_type`(`footnote`/`endnote`) | `//footnote`, `//endnote` |
| `TexEquationNode` | 別行立て数式 | `id`, `caption_node` | `//texequation` |
| `EmbedNode` | 指定ビルダー向けの生の埋め込み(将来 Markdown 入力に対応する場合、生 HTML もここに載せる) | `embed_type`, 対象ビルダー, `content` | `//embed`, `@<embed>`, `//raw`, `@<raw>` |

### 汎用ブロックと一時ノード

| ノード | 意味 | 主要フィールド | 生成する構文 |
|---|---|---|---|
| `BlockNode` | 専用ノードへ分化していない汎用ブロック | `block_type`, `args` | `//bibpaper`, `//graph`, `//box`, `//insn`, `//point`, `//term`, `//doorquote`, 制御命令, … |
| `DirectiveNode` | 次のノードを修飾するパーサ指示。lowering で必ず除去される | `directive_type`, `args` | `//tsize`, `//firstlinenum`, `//noindent`, `//olnum`, `//beginchild`, `//endchild` |
| `LeafNode` | 子を持たない内容ノードの抽象基底 | — | 直接シリアライズされない |

## 2. パイプラインセマンティクス

`Compiler#compile_to_ast(input)` は `CompileInput`(ソーステキストと、画像やクロス章参照のルックアップに使うサービスハンドル)を受け取り、以下の段階を経て観測可能な木を作る。

### 2.1 surface tree → lowering パス群 → core tree

構文解析の直接の出力を **surface tree** と呼ぶ。
ソースに忠実な木であり、「次のノードを修飾せよ」というパーサ指示(`//noindent` など)も `DirectiveNode` としてそのまま含む。

続いて、順序付きの二つの段階が lowering パス群として走る(`Compiler#post_processors`。各パスは一つのことだけを行う nanopass 構成。設計の経緯は doc/design-improvements #3)。

- **Stage B**: 互いに可換な directive マイクロパス群。
  各パスは一種類の directive を、後続の兄弟から探索した「次の適格な対象」へ適用し、directive を削除する。
  対応は `//tsize` → 表、`//firstlinenum` → コードブロック、`//noindent` → 段落または引用、`//olnum` → 順序付きリストである。
  探索は前方の最初の適格ノードまで進むので、間に別種のノードがあっても飛び越える(例: `//noindent` と段落の間に `//embed` が挟まっていても、段落に適用される)。
  各パスが触れる directive 種と対象属性は互いに素なので、どの順で走らせても同じ木になる(この可換性はテストで検査されている)。
- **Stage A**: 順序に依存する構造パス群。
  `//beginchild`/`//endchild` による子ブロックの入れ子化、順序付きリストへの項目番号付与、`nonum`/`notoc`/`nodisp` 見出しとコラムへの auto-id 生成を行う。

lowering 後の木を **core tree** と呼ぶ。
core tree に `DirectiveNode` は残らず(残っていればコンパイルエラー)、その効果は対象ノードのフィールドとして存在する。
レンダラとシリアライザが見るのはこの core tree である。
参照解決と画像パス解決はさらに別のフェーズであり、描画を伴うフルビルドのときだけ走る。

### 2.2 ブロック分離

隣接するブロックは別々の兄弟ノードとしてモデル化され、コンパイラはブロック境界をまたいだ統合や平坦化を行わない。
ブロックの隣接関係を木から消してしまうと、レンダラが出力文字列の書き換えで隣接を再構成する羽目になるからである(このバグ類型の記録は doc/design-improvements #2)。
再実装も、ブロック境界を木の中で観測可能に保たなければならない。

例外は、レガシー LATEXBuilder の挙動に合わせた二つの統合だけである。
空行で区切られた連続する定義リスト(`:` 行、`//dl`)は一つに統合される。
また `//beginchild`/`//endchild` をまたぐ `//ul`/`//ol` の継続は親リストへ統合される(`ListStructureNormalizer`)。

### 2.3 定義番号

番号付き定義(`//list`、`//image`、`//table`、`//texequation`、`//graph`、`//bibpaper`、脚注)は、コンパイル時に Indexer が採番し、`definition_number` = `{number, chapter_number}` をノードへ刻印する。
たとえば第 2 章の最初の図なら `{number: 1, chapter_number: "2"}` であり、描画側は「図2.1」を出すために章のインデックスへ問い合わせる必要がない。

番号を持たない画像(`//indepimage`、`//numberlessimage`)は `definition_number` を持たない。
`//imgtable`(画像を表として扱う命令)は表として採番されるが、参照先の画像が見つからない場合のフォールバック描画用に、画像系列の番号 `imgtable_image_number` も別途持つ。
カウンタの共有関係(image と graph が一つのカウンタを共有し、indepimage、numberlessimage、imgtable の画像が別の一つを共有する)は、レガシー IndexBuilder と一致させている(doc/design-improvements #1 と #7)。

章タイトルは最初の見出しの `raw_caption`(マーカーとラベルを除去し、インライン記法は生のまま残した源泉忠実なキャプション)であり、AST が所有する。
レガシー book モデル(`BookUnit#title`)には依存しない。

## 3. 命令リファレンス

コンパイラが認識する命令の全体は、固定のブロック命令集合(`BLOCK_COMMAND_TABLE`)と特殊インライン命令集合(`DEFAULT_INLINE_HANDLERS`)である。
網羅性検査が各命令を本書へ対応付けられるよう、両方をここに列挙する。

### 3.1 ブロック命令

- コードブロック(`CodeBlockNode` になる):
  `//list`(採番あり)、`//listnum`(採番と行番号)、`//emlist`(採番なし)、`//emlistnum`(行番号のみ)、`//cmd`(コマンドライン)、`//source`(引用元付きコード)。
- 画像(`ImageNode`):
  `//image`(採番あり)、`//indepimage`(採番なし)、`//numberlessimage`(同)。
- 表(`TableNode`):
  `//table`(採番あり)、`//emtable`(採番なし)、`//imgtable`(画像を表として採番)。
- 箇条書き(`ListNode`/`ListItemNode`):
  `//ul`、`//ol`、`//dl`、`//li`、`//dt`、`//dd`。
  通常は `*` などの行記法で書かれ、これらのブロック形は補助である。
- ミニコラム(`MinicolumnNode`):
  `//note`、`//memo`、`//tip`、`//info`、`//warning`、`//important`、`//caution`、`//notice`。
  種類は違うが構造は同一で、`minicolumn_type` だけが異なる。
- コラム(`ColumnNode`): `//column`。
- 脚注(`FootnoteNode`): `//footnote`(ページ内脚注)、`//endnote`(章末の後注)。
- 数式(`TexEquationNode`): `//texequation`。
- 埋め込み(`EmbedNode`): `//embed`、`//raw`。
- 引用系(`BlockNode`):
  `//read`、`//quote`、`//blockquote`、`//lead`、`//centering`、`//flushright`、`//address`、`//talk`。
- その他(`BlockNode`):
  `//doorquote`(扉引用)、`//bibpaper`(参考文献)、`//graph`(外部ツールで生成する図)、`//box`、`//insn`、`//point`、`//term`。
- 制御命令(`BlockNode`):
  `//comment`、`//blankline`、`//pagebreak`、`//label`、`//printendnotes`、`//hr`、`//bpo`、`//parasep`。
- directive(`DirectiveNode`。lowering で除去):
  `//olnum`、`//noindent`、`//firstlinenum`、`//tsize`、`//beginchild`、`//endchild`。

### 3.2 特殊インライン命令

専用のハンドラを持つ命令である。
木の形はグループごとに異なる。

- パススルー。直接 `EmbedNode` になる: `@<embed>`、`@<raw>`。
- 素の `InlineNode`(`inline_type` が命令名、引数がペイロード): `@<ruby>`(ルビ)、`@<href>`(リンク)、`@<kw>`(キーワード)。
- 参照。
  `InlineNode`(`inline_type: :img` や `:fn` など)が、`ref_id`/`context_id`/`resolved_data` を持つ `ReferenceNode` を子として包む:
  `@<img>`、`@<imgref>`、`@<list>`、`@<table>`、`@<eq>`、`@<fn>`、`@<endnote>`、`@<column>`、`@<w>`、`@<wb>`、`@<bib>`、`@<bibref>`。
- クロス参照。木の形は参照と同じ:
  `@<hd>`(見出し)、`@<chap>`(章番号)、`@<chapref>`(章)、`@<title>`(章題)、`@<sec>`(節番号)、`@<secref>`(節)、`@<sectitle>`(節題)、`@<labelref>`、`@<ref>`。

上記以外の `@<名前>{…}`(`@<b>`、`@<i>`、`@<code>`、`@<tt>`、`@<bou>`(圏点)、`@<ami>`(網掛け)、`@<u>`、`@<em>`、`@<strong>` など)は、`inline_type` が命令名の装飾 `InlineNode` になる。
その出力は描画側の `render_inline_<名前>` が決め、木の形はどれも同じである。

## 4. 乖離レジストリ

パリティ第一の方針の下でも、レガシービルダーと出力が異なる箇所が少数ある。
本節はその全件を記録する台帳である。

各項目には**互換分類**(doc/design-improvements #6 の分類)を付す。
**即修正**はその挙動に動く文書が依存し得ない場合(組版不能な出力しか生まなかったものなど)。
**ゲート**は誤りだが依存が生じうるため `review_version` 指定で旧挙動を残すべきもの。
**正典化**は定着していて害が小さく、仕様として採用するものである。

下表の #1 と #4 は、ビルダーの挙動を AST が byte 単位で再現しているケースである(仕様の問いとしてトリアージ済み。`doc/spec-questions.md` にあり、upstream(kmuto/review)の裁定待ち)。
#2、#3、#5 は、ビルダーの挙動がバグまたはビルダー固有の癖であるため、AST が意図的に再現しないケースである。

| # | 構文 | ビルダーの挙動 | AST の挙動 | 想定分類 | upstream |
|---|---|---|---|---|---|
| 1 | Part 見出しの TOC 名 | 星付き Part は `part`、`[nonum]` Part は `chapter` | ビルダーを再現 | 正典化? | open |
| 2 | `@<comment>` で空描画になる表セル | 空描画セルが潰れ行がずれる(LATEXBuilder のバグ) | 再現しない: 正しく分割した行を保つ | 即修正 | open |
| 3 | 表ヘッダ/本体区切りの閾値 | LATEXBuilder はエスケープ後の行で検出するため罫線 4〜11 本で既に分割 | 再現しない: 12 本閾値(HTML と同じ)を使い、4〜11 本はデータとして保つ | ゲート | open |
| 4 | `footnotetext: true` + 見出し中の脚注 | 保護なしの `\footnotemark` を出す(組版不能) | ビルダーを byte 単位で再現 | 即修正 | open |
| 5 | 表セル先頭ドットのエスケープ | HTMLBuilder は `..15`→`.15`、IDGXMLBuilder は `..15` のまま | `.15` に正規化(HTML に一致。IDGXML byte 一致とは意図的に非互換) | 即修正 | open |

このほかに、乖離ではなく単なる未実装が二つある(`doc/differential-testing.md` 参照)。
`//graph`(外部ツール画像)と `@<w>`/`@<wb>`(辞書による語句置換)は、AST の LaTeX レンダラで未実装である。

乖離ではないが明記しておくべき点として、`//tsize`(表の列幅指定)の解釈は形式ごとに異なる。
IDGXML はソースの数値 CSV を直接読み、LaTeX 列指定の形(`|l|c|r|`)は IDGXML では無視されて等分になる。
これはビルダーと同一の挙動である(doc/design-improvements #5)。

## 5. 適合基準

再実装が、あるソース(および将来版ゲートが入れば `review_version`)について適合するのは、段階を追って次を満たすときである。

1. **surface tree**:
   ソースの構文解析が、同じノード型とフィールドを持つ同じ surface tree を生む(シリアライズ形式に対してスキーマ妥当であること)。
2. **core tree**:
   lowering 後に同じ core tree を生む。
   すなわち `DirectiveNode` が残っておらず、directive の効果は対象ノードのフィールドにあり、[2.3 節](#23-定義番号)の番号付けが済んでいる。
3. **描画**:
   形式ごとに定められた厳密度で同じ出力を生む。
   LaTeX は DVI 一致、IDGXML は byte 一致、HTML は rendered-equivalent、plaintext と TOP は byte 一致である。

版の扱いは次の設計意図に従う。
セマンティクスは版に依存しないことを基本とし、トリアージ済みの乖離点だけが `review_version` の範囲を持つ(予定)。
ノードのスキーマは版で分岐させず、分岐はコンパイラとレンダラの挙動にのみ置く。
現状のダンプのエンベロープは `ast_format` と生成元を示す `generator` 文字列(例: `review 5.11.0`)のみを記録しており、専用の `review_version` フィールドや版ゲートは未実装である。

実行可能な適合キットは、シリアライズ AST のスキーマ、samples と PBT のコーパス、差分比較器(DVI 用の `tools/compare_book.rb`、IDGXML と HTML のスイープ)であり、いずれも Ruby ソースを読まずに実行できる。
