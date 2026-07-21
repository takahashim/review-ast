# AST 設計改善

本書は、現行実装の設計レビューから導いた AST とそのパイプラインの構造改善計画を記録する。
各項目は「問題(証拠付き)」「設計」「移行手順」「検証方法」の順で述べる。
検証は既存のパリティ検証基盤([differential-testing.md](differential-testing.md))を前提とする。

項目 1〜3 は、レビューで見つかった構造上の欠落のうち大きい三つに対応する。

1. ブロック定義ノードが自分の番号を持たず、レンダラがレガシーの `Book::Chapter` インデックスへ手を伸ばしている。
2. ブロック間の分離(空行や隣接)が AST にモデル化されておらず、レンダラがペアごとの特例と出力文字列の書き換えで再構成している。
3. 一時的な制御マーカーが型のない擬似ノードとして木に入り、散在した順序結合のポストプロセッサ群に消費され、除去の保証がない。

項目 4〜6 は、交換フォーマットと仕様そのものに対応する。

4. JSON シリアライズが lossy で、版がなく、二つの並行したコード経路に分かれている。
5. 共有ノードのいくつかのフィールドが、ソースの事実ではなく出力形式の決定を記録している。
6. AST のセマンティクスが、置き換え対象であるレガシービルダーから独立に定義されていない。

項目 1〜3 の並び順は効果対労力の見込みによる。
1 と 3 はどちらもポストプロセスへの依存を減らすものであり並行して進められ、2 はどちらにも依存しない。
項目 4〜6 はこれらの後に続くのではなく、かみ合って進む(末尾の実施順の節を参照)。

---

## 1. ブロック定義ノードへの番号付与

### 問題

番号付きブロック要素(`//list`、`//table`、`//image`、`//texequation`、`//bibpaper`、脚注、後注)は、AST 上に自分の番号を持たない。
そのため、すべてのレンダラが「いま描画しているまさにそのノード」の番号を、レガシーの book モデルへの問い合わせで解決し直している。

```ruby
# latex_renderer.rb
@chapter.list(node.id).number
@chapter.equation_index.number(node.id)
# html_renderer.rb
@chapter.image(id).number
@chapter.footnote(node.id).number
# plaintext_renderer.rb、top_renderer.rb、idgxml_renderer.rb も同様
```

この形の呼び出しは 5 つのレンダラに約 51 箇所あり、それぞれが独自の `ReVIEW::KeyError` rescue と微妙に異なる代替文言を持つ。

これはインライン参照との非対称でもある。
インライン側は既に正しく解決されており、`ReferenceResolver` が解決結果を `ResolvedData` として AST に畳み込み(`reference_node.rb`)、レンダラは書式の包装(`format_resolved_reference`)だけを行う。
定義側も使用側と同じ方式で扱うべきである。

この非対称は、より深い問題も固定化している。
`BookIndexer` は結果をレガシーの `Book` と `Chapter` オブジェクトへ書き込み(monkey patch の `ast_indexes=` 経由で `BookUnit` の私有インスタンス変数 12 個へ代入)、レンダラはそれをレガシーのインデックス API で読み返す。
つまり AST インデクサの出力は、レンダラに届く前に旧 book モデルを経由して洗浄されている。
レンダラが番号付けのために `@chapter` を必要とする限り、AST は自己記述的とは言えず、レンダラを別のホスト(あるいは別言語)へ移植するには book モデルも一緒に移植することになる。

### 設計

`ResolvedData` と対になる小さな値オブジェクトを、番号付き定義ノードに導入する。

```ruby
# lib/review/ast/definition_number.rb
class DefinitionNumber
  attr_reader :number          # 例: 3       (章内の項目番号)
  attr_reader :chapter_number  # 例: "2"     (整形済みの章番号部分)
  # 表示用の全体("2.3" など)は TextFormatter がこの二つから組み立てる
end
```

- `CodeBlockNode`、`TableNode`、`ImageNode`、`TexEquationNode`、脚注、後注、bibpaper の各ノードに、省略可能な `definition_number` 属性を追加する
  (番号なしの要素、たとえば `//emlist` では nil)。
- 番号の割り当てはインデックスパスで行う。
  このパスは今もレガシーインデックスのために同じ番号を計算している。
  `Indexer` は現在 `ReVIEW::Book::Index` オブジェクトを構築して `chapter.ast_indexes=` へ押し込んでおり、そこに加えて、いま訪問したノードへ番号を刻印する。
- `definition_number` はシリアライズ対象とする。
  これにより、ダンプした AST は `Book` なしでキャプションを描画するのに必要な情報をすべて含む。

レンダラは `@chapter.list(node.id).number` を `node.definition_number` に置き換える。
キャプションの整形は `TextFormatter#format_caption` のまま変えない。
レンダラごとの `KeyError` rescue は消え、「番号なし」は例外ではなく `definition_number.nil?` で表現される。

### この項目で変えないこと

- レガシーインデックスは引き続き構築し、book モデルへも押し込む。
  review gem 側の消費者(epubmaker の経路や TOC 生成)がそれを読むためである。
  `ast_indexes=` の廃止自体は別の後続ステップであり、この項目が取り除くのは「レンダラの」依存だけである。
- 章をまたぐ番号は、参照側では従来どおり `ResolvedData` を流れる。
  この項目は定義側だけを扱う。

### 移行手順

1. `DefinitionNumber` と、対象ノードへの `definition_number` アクセサとシリアライズを追加する
   (入れ子ハッシュとして直列化し、デシリアライズで必ず復元する。項目 4 の厳密な round-trip テストがこれを釘付けにする)。
2. `Indexer` で、各インデックス項目を作る箇所で番号を刻印する
   (visitor は項目登録の時点でノードを保持しており、`core_ext` のフックで `caption_node` をレガシーの `Index::Item` へ渡している。つまりノードと項目の対応付けはその時点で既にある)。
3. レンダラを一つずつ変換する。
   まず LaTeX(DVI オラクルがある)、次に HTML と IDGXML(テキスト比較器がある)、最後に plaintext と TOP。
   変換のたびに該当する `@chapter.*(...).number` 呼び出しを削除する。
4. 5 つのレンダラの変換が終わったら、`Renderer::Base` は番号付けのための `@chapter` を必要としなくなる。
   残る `@chapter` と `@book` の利用を棚卸しする
   (正当に残る主な用途はファイル解決のための `@chapter.image(id)` である。パス解決は文書構造ではなく環境の問題であるため)。

### 検証

- 各ステップでテキスト正規化比較の全スイート(HTML、LaTeX、IDGXML)が緑であり続けること。
  番号はテキスト比較器から完全に見えるため、このリファクタリングは既存テストで十分に守られている。
- LaTeX の変換後に `samples/syntax-book` で DVI スイープを一度行う。
- 新しいユニットテストとして、章を JSON にダンプし、読み戻し、`Book` を構築せずにキャプションを描画する。
  これが「情報の欠落が実際に閉じた」ことの受け入れテストになる。

### 実装状況（2026-07 時点）

- 実装済み
  - `lib/review/ast/definition_number.rb`（`number` と `chapter_number` を持つ値オブジェクト）。
  - `Node#definition_number` アクセサ。
  - `Indexer` が list / table / image（番号付き分岐のみ）/ texequation / bibpaper / 脚注 / 後注の各ノードへ番号を刻印する
    （`chapter_number` は `Renderer::Base#get_chap` と同一の値を持たせる）。
  - 5 レンダラすべての定義側を `node.definition_number` に変換し、対応する `@chapter.*(...).number` 呼び出しを削除した。
    - LaTeX: list / equation / footnote / bibpaper
    - HTML: list / table / image / equation / bibpaper / 脚注 / 後注
    - IDGXML: list / table / image / equation / bibpaper / 後注
    - plaintext: list / table / image / equation / bibpaper
    - TOP: list / table / image / bibpaper
- 意図的に残したインデックス参照（本項目の時点。その後、項目 7 の作業でインデックス読みはすべて撤去済み）
  - 非バインドの `//imgtable` ダミー描画（HTML `image_caption_number`、IDGXML `generate_image_header` のフォールバック）。
    このノードは「表」番号を持つため画像として振り直す必要があり、当時は `@chapter.image(id).number` を残した。
    現在は `Indexer` が刻印する `node.imgtable_image_number` を読む。
  - コレクション描画で index 項目を直参照する箇所（plaintext `render_inline_fn`、TOP `printendnotes` の `en.number`）。
    現在は定義側 `definition_number` と AST 収集の `endnote_nodes` に置換済み。
  - 参照側（`@<fn>` / `@<list>` / `@<bib>` など、inline handler / inline context）。本項目の対象外（従来どおり `ResolvedData`）。
- 検証
  - 全テストスイート 1021 件緑、rubocop クリーン。
  - LaTeX: `samples/syntax-book` の DVI スイープ 6/6 一致。
  - HTML（仕様準拠比較）と IDGXML（バイト一致）: `samples/syntax-book` 6/6、`samples/sample-book` 3/3 一致。
- 積み残し（本項目の範囲外として次に回す）
  - `definition_number` のシリアライズ／デシリアライズ配線。設計上は移行手順 1 に含むが、
    ドキュメントどおり項目 4 の厳密な round-trip テストで釘付けにするため、項目 4 で実装する。

---

## 2. ブロック間分離のモデル化

### 問題

AST は各ブロックが何であるかを記録するが、隣のブロックとどう分離するかを記録しない。
本当の規則(「隣接するこのペアの間に、出力上の空行が入るか」)はノードのペアの性質であり、レガシービルダーは `puts` と `print` の使い分けとして暗黙にそれを符号化している。
AST がそれを表現しないため、LaTeX レンダラは事後に隣接関係を再構成している。
`LatexRenderer#render_document_children` は子を訪問した後に結果へパッチを当て、`//raw` の後で段落の前なら `\n` を挿入し、ブロック `//embed` と後続の `//noindent` 段落の間の空行を取り除き、連結後の出力へ 4 回の `gsub!` を走らせて minicolumn、`\pagebreak`、`\footnotetext` の隣接を直す。

これはパリティ維持の最大の出費源である。
直近 30 コミット中 6 件が空行と隣接の修正であり(`45dc9a7`、`53c6526`、`af75dce`、`0156ea7`、`ebb497e`、`72ff395`)、そのすべてがテキスト正規化スイートを通過し、DVI オラクルだけが捕捉した。
新しいブロック型を足すたびに新しいペア特例が生まれうる。
この修正パターンは収束しない。
レンダラが復元しているのは AST が捨てた情報であり、構造上もぐら叩きになるためである。

### 設計

分離を、レンダラの文字列連結から創発する性質ではなく、ノードが持つ明示的で問い合わせ可能な性質にする。

各ブロックレベルノードが自分の境界要件を宣言する。

```ruby
# Node(ブロックレベル)上
def leading_separation   # :none | :newline | :blank_line
def trailing_separation  # :none | :newline | :blank_line
```

隣接する 2 ブロック間の実際の区切りは `max(prev.trailing_separation, next.leading_separation)` で決める
(順序は `:none < :newline < :blank_line`)。
列の描画はこうなる。

```ruby
results = children.map { |c| visit(c) }
join_with_separations(children, results)   # 単一の汎用ジョイナ
```

既定値は通常ブロックで `:blank_line`/`:blank_line`(現在の一律 `\n\n` と同じ挙動)とし、上書きしたノード以外では変化が見えないようにする。
上書きの例は次のとおり。

- `embed_type: :raw` の `EmbedNode` は `:none`/`:none`
  (LATEXBuilder の `print` 意味論。連続する raw は密着しなければならない)。
- ブロック `//embed` は trailing `:newline`(ビルダーはちょうど 1 つの `\n` を出す)。
- ブロック embed の後の `//noindent` 付き段落は leading `:newline`
  (現在の兄弟覗き見の特例をこれで置き換える)。
- minicolumn、`\pagebreak` 系ブロック、遅延 `\footnotetext` は、現在の `gsub!` の結果を再現する値。

設計上の注意を二つ添える。

- この値の意味は出力形式に依存しない
  (「隙間なし」「改行」「段落間隔」)。
  発見の経緯は LaTeX の挙動だが、意味は共通である。
  HTML と IDGXML は今日ほとんど分離を無視しており(タグ構造が分離を担う)、それを続けてよい。
  ジョイナはレンダラごと、データは共有という分担である。
  これにより、形式固有の知識を AST から締め出したまま、文字列書き換えを廃止できる。
- ノードの分離が型ではなくソース上の文脈で決まる場合(稀である。たとえば `//embed` がインラインかブロックかは既に `embed_type` が捕捉している)は、コンパイラが構築時に属性を設定する。
  レンダラは兄弟を覗かない。

これで `render_document_children` の特例群と `gsub!` の連打を丸ごと削除する。
column 本体、minicolumn 本体など、現在この論理の断片を複製している子列描画にも同じジョイナを使う。

### 設計上の重要な制約（実測による）

現行レンダラ（DVI 一致）の出力で隣接ブロックの区切りを実測すると、2 スカラー `max(prev.trailing, next.leading)` モデルだけでは LATEXBuilder の挙動を完全には再現できないことが分かった（区切りを none=0 / newline=1 / blank=2 とする）。

- `raw→raw = 0` より `t_raw = 0`、`raw→段落 = 1` より `l_段落 = 1`。
- しかし `block_embed→段落 = 2` は `t_embed = 2` を、`block_embed→raw = 1` は `t_embed = 1` を要求し矛盾する。
- 同型の矛盾が `minicolumn`（`→minicolumn=1` かつ `→段落=2`）や `headline`（`→段落=2` かつ `→遅延footnotetext=1`）でも生じる。いずれも `l_段落=1` が原因。

原因は `//raw` の出力が「後続の段落へ流し込まれる verbatim/inline なテキスト」であり、ブロック分離ではないこと。したがって次のように分ける。

- スカラーモデルで表現できるケース（`minicolumn`、`block embed`、`//pagebreak`・`//hrule`、`//noindent` 段落）はノード宣言へ移植する。既定は `:blank_line`/`:blank_line`。
- スカラーで表現できない少数の特例（`//raw`→段落、`headline`→遅延 `\footnotetext`）は、ジョイナ内の明示的な特例として残しコメントで根拠を記す。これらは `//raw` と遅延脚注という「inline/verbatim がブロック列に紛れる」限られた場面に閉じている。

ジョイナは「各ブロックは自分の宣言どおりの trailing 区切りだけを末尾に出す」という不変条件のもと、隣接ペアで `max(prev.trailing, next.leading)` まで不足分を pad する（`max ≥ prev.trailing` なので trim は不要）。この不変条件を満たすため、既定と異なる trailing を宣言するノード（minicolumn、block embed など）は visitor の末尾出力もその区切りに合わせる。

### 移行手順

1. `Node` に既定値 `:blank_line` の 2 メソッドを追加し、`Renderer::Base` に汎用ジョイナを追加する。
2. `render_document_children` の特例を一つずつノードの上書きへ移植する。
   DVI スイープが乾くまで旧経路をフラグの裏に残す。
3. 旧経路を削除し、他の子列描画箇所へジョイナを広げる。
4. 分離の上書きは既定値と異なる場合だけシリアライズする(ダンプを小さく安定に保つ)。

### 検証

この項目はテキスト比較器にバグが見えないからこそ存在する。
したがって検証は DVI を第一とする。

- 各特例の移植の前後で、`samples/syntax-book` と PBT コーパスに対して DVI スイープ
  (`tools/compare_book.rb` と `tools/pbt/runner.rb --mode dvi`)を行う。
- 上に挙げた 6 つの回帰コミットはそれぞれ具体的な構文を指している。
  それぞれを最小の `.re` フィクスチャにして専用の比較テストに収め、このクラスの修正全体を手動 DVI ではなく高速なテストで釘付けにする。

### 実装状況（2026-07 時点）

現行レンダラの出力で全ブロックペアの区切りを実測した結果、当初想定した「2 スカラー宣言 + 汎用 `max` ジョイナ」は LATEXBuilder の挙動を表現できないことが判明した（上記「設計上の重要な制約」参照）。区切りは既約に pairwise（`raw→list=0` だが `minicolumn→list=2`、`bembed→minicolumn=2` だが `minicolumn→minicolumn=1`）であり、単一ノードのスカラーだけでは決まらない。そのため実装は次の形に落ち着いた。

- 追加した `Node#leading_separation`/`#trailing_separation` と `Renderer::Base#join_with_separations`（スカラー pad-to-max ジョイナ）は、上記理由で LaTeX を駆動できず未使用となるため削除した。
- 代わりに、隣接ペアの区切り改行数を返す node 型ベースの単一決定関数 `LatexRenderer#latex_block_gap(prev, next)` を実装し、`join_block_children` がこれで各境界の trailing 改行数を正規化する。visitor の出力（末尾 `\n\n`）は変えない。
- これにより、旧 `apply_block_child_separation`（raw/embed/minicolumn の隣接特例）と、`render_document_children` にあった 4 つの `gsub!`（rendered LaTeX への文字列パターン書き換え。minicolumn 連結・`\pagebreak`/`\hrule`・遅延 `\footnotetext`）を、構造判定に基づく 1 関数へ一元化した。
- 同じ `join_block_children` を文書本体・column 本体・minicolumn 本体で共有する（区切りモデルの一本化）。
- `//raw`（verbatim が段落へ流し込まれる）と遅延 `\footnotetext` の既約な特例は、`latex_block_gap` 内の明示的な分岐として根拠コメント付きで残した。

改善の本質は「rendered 文字列へのパターン書き換えの排除」と「散在ロジックの一元化・構造化」であり達成した。一方、区切りを純粋なノード属性にする（dump2re / シリアライズで共有する）当初案は、区切りが本質的に pairwise であるため見送った（ノード単独では隣接相手が分からない）。

- 検証
  - 全テストスイート 1021 件緑、rubocop クリーン。
  - 全ブロックペアの区切り実測マトリクスが変更前と完全一致（回帰なし）。
  - DVI: `samples/syntax-book` スイープ 6/6 一致、`tools/pbt/runner.rb --mode dvi` 21 シード分離なし。
  - HTML / IDGXML: `samples/syntax-book` 6/6 一致（分離モデルは LaTeX 専用のため影響なし）。
- 実装済み(回帰6コミット由来の最小フィクスチャによる高速テスト化)
  - `test/ast/test_latex_block_separation.rb` が、6 回帰コミット(`45dc9a7`/`53c6526`/`af75dce`/`0156ea7`/`ebb497e`/`72ff395`)が直した各隣接を最小 `.re` フィクスチャで直接 pin。raw→段落/raw→raw/raw→ブロック環境、block embed→段落/→raw/→noindent、minicolumn→minicolumn/→段落/→pagebreak、見出し→遅延 footnotetext、minicolumn→遅延 footnotetext を、`latex_block_gap` が出す inter-block 空白の厳密検査(該当箇所はビルダーと byte 一致)で釘付け。手動 DVI ではなく高速な文字列比較でこのクラス全体を守る。
  - 注記: 一般のブロックペアは DVI 一致であって byte 一致ではない(例: minicolumn→list は空行1本ぶん異なるが DVI 不可視)。それらは引き続き DVI スイープで担保し、本テストは byte 一致する6回帰隣接に限定する。

---

## 3. 型付き directive による一時制御マーカーの lowering

### 問題

Re:VIEW の命令のいくつかは内容ではなくパーサへの指示である。
`//beginchild` と `//endchild`(後続リストの入れ子化)、`//noindent`(次の段落の修飾)、`//olnum`(次の番号付きリストの開始番号)、`//tsize`(次の表の列指定)、`//firstlinenum`(次のリストの開始行番号)がそれにあたる。
現在のパイプラインはこれらを汎用の `BlockNode`(約 20 の無関係な命令を `block_type` で束ねる受け皿)にして木へ挿入し、その後に専用のポストプロセッサがそれを探し、兄弟へ効果を適用し、削除する。

```
compiler.rb: 順序付きのポストプロセス 7 パス
  TsizeProcessor、FirstLineNumProcessor、NoindentProcessor、OlnumProcessor、
  ListItemNumberingProcessor、ListStructureNormalizer、AutoIdProcessor
```

**問題は、マーカーがノードになることではない。**
ソースを忠実に写す中間表現はむしろ利点である。
段階ごとにダンプして検査と比較ができ、`dump2re` はマーカーを属性からの再構成ではなくそのまま再出力できる。
実際の問題は次の四つである。

- **型がない**：マーカーが実内容のブロックと同じ受け皿 `BlockNode` を共有しており、「これはパーサ指示か」が検査可能な性質ではなく `block_type` の命名慣習になっている。
- **消費が散在し、順序に結合している**：マーカーごとに専用のポストプロセッサがあり、順序の制約は `compiler.rb` のコメント(「他のプロセッサより先に実行」)としてしか存在しない。
  どのパスが実際に可換なのかは、どこにも記録されていない。
- **除去の保証がない**：レンダラとシリアライザが見る木から directive が消えていることを、何も強制していない。
  シリアライズされた AST に、どのレンダラも見るべきでない擬似ノードが含まれうる。
- **パス内部が脆い**：`ListStructureNormalizer` は one-shot の可変フラグに駆動されて木の外科手術を行う。
  コミット `d6d6273` は、RuboCop の自動修正が「無意味な代入」として削除したフラグのリセットを復元したものであり、その削除はリスト統合を静かに壊し、既存テストのどれも捕捉しなかった。
  この脆さは一つのパスの内部にある。
  パスを統合しても防げず、防ぐのは小さく単純なパスと回帰テストである。

### 設計

マーカーは木に残す。
ただし型を付け、小さな検証されたパスの列で lower し、結果を検査する。
構成は意図的に nanopass スタイルとする。
各パスは一つのことだけを行い、一〜二文で仕様化できる。
その一文仕様はそのまま、再実装が必要とする言語中立のアルゴリズム記述になる
(項目 6 の AST セマンティクス文書の素材になる)。

```
Surface tree — 型付き DirectiveNode を含む。ソースに忠実。
│              dump2re はこの段階を読み、マーカーをそのまま再出力する。
│
├─ 段階 A: 構造の lowering
│    pass: 子入れ子化    (//beginchild と //endchild。明示スタックで
│                         後続ブロックを付け替え、マーカーを削除)
│    pass: リスト統合    (連続する dl の統合。1df4926 の
│                         「空行区切りのリストは統合しない」互換規則)
│                         宣言された依存: 子入れ子化の後に実行
│
├─ 段階 B: 属性の lowering — 互いに可換なマイクロパス群
│    pass: //tsize        → 次の表の列指定
│    pass: //olnum        → 次の番号付きリストの開始番号
│    pass: //firstlinenum → 次のリストブロックの開始行番号
│    pass: //noindent     → 次の段落の noindent フラグ
│
├─ 段階境界の検証: DirectiveNode が残っていないことを assert
│
Core tree — レンダラと(既定では)シリアライザが消費する木。
```

段階 B の各パスの仕様は同じ一文の形をとる。
「兄弟を走査し、種類 k の directive を直後の適格な兄弟に適用して属性を設定し、directive を削除する。適格な対象が現れない directive は、位置情報付きのコンパイルエラーとする」。

順序についての規律は次の二つだけである。

- **可換性の主張は検証する**：段階 B のパスは互いに素なマーカー種と互いに素な対象属性に触れるので可換である。
  パスをシャッフルした順で走らせ、結果の木が一致することをプロパティテストで確認する。
  順序非依存は、コメント上の願望ではなく検査される性質になる。
- **可換でない依存は最小化して宣言する**：この再構成の後に残る依存は一つ(リスト統合は子入れ子化の後)である。
  宣言された辺が一本であれば、それは暗黙の順序の網ではなく、仕様の一行である。

`ListStructureNormalizer` のマーカー駆動のノード移動は子入れ子化パスへ吸収される(one-shot フラグではなく明示スタック)。
残るのは縮小した単能のリスト統合パスである。
`BlockNode` の `block_type` 語彙からパーサ指示のメンバーが消える。
dump コマンドには `--stage surface|core` オプションを追加し、両方の表現を検査可能に保つ。

### 移行手順

1. `DirectiveNode` 型を導入し、マーカー命令についてブロックプロセッサから出力する。
   既存ポストプロセッサの型チェックを追随させる。
   これは機械的な変更であり、挙動を変えない。
2. 段階境界の検証(ポストプロセス後に directive が残っていないこと)を追加する。
   パスの再構成より前に入れられ、「マーカーが最終の木に漏れた」を潜在バグから即時のエラーに変える。
3. 単純な修飾子を段階 B のマイクロパスへ一つずつ変換する。
   易しい順に `//firstlinenum` と `//olnum`、次に `//tsize`、次に `//noindent` とし、置き換えるたびに旧プロセッサを削除する。
   段階 B のパスが二つできた時点で、シャッフル順の可換性テストを追加する
   (`//noindent` は embed の後の noindent という隣接ケースで項目 2 の分離モデルと相互作用する。二つを協調させる)。
4. `//beginchild` と `//endchild` を最後に扱う。
   子入れ子化を明示スタック付きの段階 A パスへ抽出し、`ListStructureNormalizer` をリスト統合だけに縮小する。
   手術の前に、`d6d6273` の回帰テストに加えて入れ子リスト形状の新しいフィクスチャを揃えておく。
5. `dump2re` を surface tree 読みに切り替える。
   マーカーは自分のノードからそのまま再出力され、吸収済み属性からの再構成は行わない。

### 検証

- 比較スイートはこれらの構文の大半を覆っている。
  加えて、各マーカーと「ありうる各対象」の隣接についてフィクスチャを追加する
  (表以外が続く `//tsize`、連続する `//noindent`、章末の `//beginchild` など。エラー経路は現在テストされていない)。
- 段階 B の可換性プロパティテスト(シャッフルしたパス順で木が一致すること)。
- 段階境界の assert はテスト時だけでなく、すべてのコンパイルで実行する。
- PBT(`tools/pbt/generator.rb`)は既に入れ子リストを生成する。
  移行中のマーカーについては、その移行が進んでいる間だけ生成の重みを上げる。
- 手順 4 の間、`d6d6273` の回帰テストが緑であり続けること。

### 実装状況（2026-07 時点）

移行手順どおり、まず段階境界の検証(手順 2)を先に入れ、続けて型付け(設計問題#1)を行った。

- 段階境界の検証(手順 2)
  - `Compiler#assert_directives_lowered` を `execute_post_processes` の末尾に追加。core tree に directive が残っていたら、ソース位置(行・桁)付きで `ReVIEW::ApplicationError` を送出する。全コンパイルで実行される(設計の「テスト時だけでなくすべてのコンパイルで」を満たす)。`d6d6273` クラスの「マーカーが最終木に漏れる」静かな破壊を、以後は即時の located エラーに変える防波堤。
  - 前提の確認: 6 つのプロセッサはいずれも対象の有無に関わらずマーカーを削除する(`beginchild`/`endchild` は orphan で既にエラー)。よって挙動保存で、`samples/syntax-book`・`samples/sample-book` のポストプロセス後の木にマーカーは 0 個。
- 型付け(設計問題#1)
  - 専用ノード `ReVIEW::AST::DirectiveNode`(`directive_type`/`args`)を新設。`Node#directive?` は既定 false、`DirectiveNode#directive?` は true。マーカーが「パーサ指示か」を命名慣習(`block_type`)ではなく検査可能な型にした。
  - `block_processor` の 6 マーカー(`noindent`/`olnum`/`tsize`/`firstlinenum`/`beginchild`/`endchild`)を `build_control_command_ast`(汎用 BlockNode)から `build_directive_ast`(DirectiveNode)へ振り分け。
  - 6 プロセッサ(noindent/olnum/tsize/firstlinenum/list_structure_normalizer)の述語を `DirectiveNode` + `directive_type` 判定に更新。
  - `assert_directives_lowered` は「`directive?` なノードが残っていないこと」に簡素化(設計どおりの形)。
  - `Visitor#visit_directive` の既定(子を辿るだけ)を基底に追加。Indexer / ReferenceResolver は lowering 前の surface tree を走査するため、旧来 `visit_block` がマーカーを素通ししていたのと等価。
  - マーカーは lowering 後にシリアライズ/描画されるため、`DirectiveNode` は core-tree ダンプにもレンダラにも現れない。よって serializer・renderer への波及はなし(renderer の `visit_block_<marker>` は元から dead code)。`DirectiveNode` 自体のシリアライズ/デシリアライズは将来の surface-tree ダンプ用に実装しテストで担保。
- 検証
  - フル `rake` 緑(1057 tests)、rubocop クリーン。
  - 挙動保存を確認: DVI `samples/syntax-book` 6/6、round-trip(参照解決あり)syntax-book 6/6・sample-book 3/3、render-identity(LaTeX/HTML/IDGXML)6/6、PBT round-trip 60/60。
  - テスト `test/ast/test_directive_lowering.rb`: 各 directive の lowering・漏れの fail-fast・`DirectiveNode` のシリアライズ round-trip。
- 実装済み(手順 6: nanopass 化・dead handler 整理・dump2re の marker 再出力)
  - nanopass 化(設計問題#2・#4): `@post_processors` を段階 B(可換な directive マイクロパス: tsize/firstlinenum/noindent/olnum)/段階 A(順序依存の構造パス: ListStructureNormalizer/ListItemNumbering/AutoId)に明示分離しコメントで文書化。段階 B のシャッフル順可換性プロパティテストを追加(`test_directive_lowering.rb#test_stage_b_micro_passes_are_commutative`、全 24 順列で最終 AST のシリアライズが一致)。その後 `5357e26` で、段階 B の 4 パス共通の骨格(directive の探索・適用・削除)を基底クラス `DirectiveLoweringPass`(`lib/review/ast/compiler/directive_lowering_pass.rb`)へ抽出し、各パスは directive 種別と適用ロジックだけを持つ。設計の一文仕様(「種類 k の directive を直後の適格な兄弟に適用して削除する」)がこの基底クラスに一箇所で実装された形になる。
  - dead handler 整理: renderer の `visit_block_<marker>`(noindent/olnum/tsize/firstlinenum/beginchild/endchild とその helper `render_tsize_block`/`render_firstlinenum_block`、idgxml の `visit_beginchild`/`visit_endchild`)を全削除。マーカーは lowering 済みで renderer に BlockNode として到達せず、DirectiveNode は `visit_directive`(子を辿るだけ)へ行くため、いずれも到達不能だった。挙動不変(DVI 6/6 ident 一致)。
  - dump2re の marker 再出力: `review_generator` は core tree を受け取るため、marker は lowered 属性から再出力する必要がある。従来 `//tsize` のみ属性(`node.tsize`)から再出力し、`//noindent`/`//olnum`/`//firstlinenum` は dead な `visit_block_<marker>` に頼って silently drop していた。これを tsize と同じ属性ベース再出力に統一(`noindent?`/`olnum_start`/`first_line_num`)し、dead な `visit_block_<marker>` を削除。`test_ast_review_generator.rb#test_directive_attributes_survive_dump2re_round_trip` が compile → generate → recompile で 4 種の属性が保持されることを担保。
  - 検証: フル `rake` 緑(1072 tests)、rubocop クリーン、DVI `samples/syntax-book` 6/6 ident 一致。
- 積み残し(本項目の残り)
  - surface-tree ダンプ(設計本来の手順 5): `DirectiveNode` を保持した lowering 前 tree を dump2re が直接読む経路。現状は core tree + 属性からの再出力で marker round-trip を満たしており、surface-tree 経路は将来の選択肢。
  - ネストリストの `//beginchild`///endchild` 再出力: 現状 dump2re はネスト構造から直接ネストリストを出力し marker を出さない(構造は保たれる)。marker 忠実な round-trip が要る場合は別途対応。

---

## 4. シリアライズの単一路線化と版付け

### 問題

JSON ダンプは AST の交換形式であり(`review-ast-dump` と `review-ast-dump2re`)、このプロジェクトの動機である配布構想は「安定した AST JSON」を外部レンダラが依拠する契約として扱う。
現在のシリアライズ層は、その契約を守れない。

- **手書きの対称性が既に壊れている**：各ノードクラスが `serialize_to_hash` と `deserialize_from_hash` の両方向を手書きしており、二方向が乖離している。
  `HeadlineNode` は `tag` と `auto_id` をシリアライズするが、デシリアライザは両方を捨てる。
  つまり `[nonum]` 見出しは round-trip を生き残らない。
  `ColumnNode` は `auto_id` と `column_number` を、`InlineNode` は `target_chapter_id` と `target_item_id` を捨てる。
  `ListItemNode#item_number` はそもそもシリアライズされない。
- **二つの並行した表現**：`Node#to_h` と `serialize_to_hash` が異なるキー集合で共存し(`to_h` は `node_type` を出すがシリアライザは出さない)、デシリアライザは別名綴りを受け付ける(`numbered` または `line_numbers`、`element` または `inline_type`)。
  過去のスキーマ変更の堆積物であり、移行の記録はない。
- **版がなく、スキーマは装飾品**：wire format に版フィールドがない。
  `json_schema` メソッドは約 23 のノード型のうち 12 しか列挙せず、`additionalProperties: true` であり、どこにも接続されていない。
  実質的に何も検証しない。
- **テストは部分文字列しか見ない**：双方向変換のテストは `assert_match(/= Test Chapter/, ...)` と `.index(...)` による順序確認であり、デシリアライズがシリアライズ済みの木を再現することを主張するテストはない。

### 設計

原則を三つ置き、そのうえで機構を述べる。

- **正準の経路は一つ**：ノードごとのシリアライズ経路を一本にする。
  `to_h` はその別名にするか、削除する。
- **読み込みでコンパイラのパスを再実行しない**：コンパイラが core tree に計算し込んだもの(項目 1 の `definition_number`、`item_number`、項目 2 の既定値以外の分離、項目 5 の `source_line_breaks`)は、すべてダンプに入る。
  読み戻した木が新規コンパイルの木と同一に描画されることを、慣習ではなく構造で保証する。
- **対称性は規律ではなく構造で守る**：各ノードクラスはシリアライズ対象フィールドを一度だけ宣言し、シリアライザ、デシリアライザ、スキーマのすべてをその宣言から導出する。
  手書きのペアが存在しなければ、手書きのペアは乖離しようがない。

```ruby
class HeadlineNode < Node
  serialize_fields :level, :label, :tag, :auto_id, caption_node: :node
end
```

ダンプにはヘッダを持たせる。
フォーマット版(`"ast_format": 1`)と、生成した gem のバージョンである。
別名キーは 1 リリースの間だけ非推奨警告付きで受理し、フォーマット版の更新で落とす。
スキーマはフィールド宣言から生成する。

> 実装は上記三点(宣言 DSL、別名の非推奨期間、宣言からのスキーマ生成)を採らなかった。
> 実際に採った形と理由は「実装状況」を参照。
全ノード型を覆い、`additionalProperties: false` とし、gem と一緒に配布し、サンプルコーパスのダンプに対する検証を CI で行う。
特殊な形のノード(`TableNode` の `header_rows`/`body_rows` 導出、`ListItemNode` の並行する `term_children`)は、宣言 DSL でその形を表現するか、文書化された例外として理由を残す。
今日それらは、すべての消費者が知っていなければならない無文書の特例である。

### 移行手順

1. フィールド宣言 DSL を導入し、ノードクラスを一つずつ移行する。
   既知の lossy な四クラス(`HeadlineNode`、`ColumnNode`、`InlineNode`、`ListItemNode`)から始める。
   各移行はそのクラスの round-trip 欠落をその場で閉じる。
2. フォーマット版ヘッダと正準キー名を追加する。
   別名の読み取りは 1 リリースの間だけ残す。
3. 宣言からスキーマを生成し、装飾品の `json_schema` を削除する。
   生成スキーマに対するコーパスダンプの検証を CI に追加する。
4. 部分文字列ベースの変換テストを、下記の同一性テストで置き換える。

### 検証

- round-trip の同一性。
  ノードの等価性を定義せずに検証できる形として、`serialize(deserialize(serialize(tree)))` が `serialize(tree)` とバイト同一であることを、`samples/syntax-book` の全章と PBT コーパスに対して確認する。
- 同じダンプ群のスキーマ検証を CI で行う。
- レンダラ水準の同一性。
  新規コンパイルの木と、そのダンプの読み戻しから、同じ章を描画して形式ごとにバイト同一であることを確認する。
  「シリアライズはされるが挙動に復元されない」フィールドを捕まえるのはこの検査である。

### 実装状況（2026-07 時点）

設計の二大検証(round-trip 同一性・レンダラ水準の同一性)をまず成立させ、それをオラクルにして lossy フィールドを閉じた。

- 実装済み(round-trip / render-identity を通すための修正)
  - デシリアライズで捨てられていたフィールドを復元: `InlineNode`(`target_chapter_id`/`target_item_id`)、`HeadlineNode`(`tag`/`auto_id`)、`ColumnNode`(`auto_id`/`column_number`)、`ListNode`(`start_number`/`olnum_start`)、`TableCellNode`(`cell_type`)、`CodeBlockNode`(`first_line_num`)、`TableNode`(`table_type` を symbol 化・`col_spec`/`cellwidth`)。
  - 全く未シリアライズだった描画影響フィールドを追加: `ParagraphNode` の `//noindent` 属性、`ListNode#olnum_start`。これらは round-trip では見えず(両側とも欠落)、render-identity 検査だけが捕捉した。
  - 項目1で積み残した `definition_number` を全ノード共通でシリアライズ/デシリアライズ。`serialize_to_hash` を override する numbered ノード(`TableNode`/`ImageNode`/`TexEquationNode`)も `Node#serialize_definition_number` を呼ぶ。復元は `JSONSerializer#restore_definition_number` に集約(対称)。のちに noindent と統合して `serialize_common_node_fields`/`restore_common_node_fields` へ改名(後述のクラス設計の整理)。現行のメソッド名はこちら。
  - リーフの独自 `location_to_h`(`TextNode`/`ReferenceNode`)を `location.to_h` 委譲にし、桁(タスク別)も含め欠落を解消。
- 検証
  - round-trip バイト同一: `samples/syntax-book` 6/6、`samples/sample-book` 3/3。
  - レンダラ水準の同一性(新規コンパイル描画 == ダンプ読み戻し描画): LaTeX / HTML / IDGXML すべてで両書籍 6/6・3/3。
  - 新規テスト `test/ast/test_serialization_round_trip.rb`(13 tests): 上記 lossy 構文(noindent / olnum / tsize表 / nonum見出し / 連番コード / 連番リスト)について round-trip と render-identity を釘付け。
  - フル `rake` 緑(1054 tests)、rubocop クリーン。
- 方針の見直し: 乖離防止の本体は DSL ではなくクラス設計
  - `serialize(deserialize(serialize(t))) == serialize(t)`(round-trip バイト同一性)は「serialize と deserialize が互いに逆写像である」ことと同値であり、DSL が構造で保証しようとする性質とちょうど同じ。よって round-trip テストがある今、DSL の「乖離防止」は宣言済みフィールドについてはほぼ冗長。
  - さらに DSL は「宣言し忘れた・挙動に効くフィールド」(noindent 型のバグ)には効かない — それを捕まえるのは render-identity だけ。
  - 乖離を構造的に不可能にするのは「源泉に忠実・型付き・単一に宣言された状態」というノードのクラス設計であり、DSL はそれを serialize に活用する薄い糖衣にすぎない。したがって投資順はクラス設計を主軸、DSL は後付けとする。
- クラス設計の整理(実施済み)
  - 汎用の型なし属性バッグ(`Node#add_attribute`/`attribute?`/`@attributes`)を撤廃。これは唯一 `//noindent` フラグのためだけに存在していた。`noindent` を基底 `Node` の型付きフィールド(`#noindent?` / `attr_writer :noindent`)へ昇格し、`serialize_common_node_fields`(旧 `serialize_definition_number`)/`restore_common_node_fields` で `definition_number` と一括して直列化。これで noindent は宣言された状態の一部となり、「シリアライズし忘れ」が構造的に起きえなくなった。
  - symbol 型フィールドを構築時に正規化(`initialize` で `to_sym`): `TableNode#table_type`・`ListNode#list_type`・`ColumnNode#column_type`・`TableCellNode#cell_type`。経路(新規コンパイルの symbol / デシリアライズの string)に依存せず常に正準型となり、`deserialize` 側の場当たり `.to_sym` を除去。
- 実装済み(フォーマット版ヘッダ = 版付け)
  - ダンプ artifact に版付きエンベロープを導入: `JSONSerializer.serialize_document` が `{ "ast_format": 1, "generator": "review X.Y.Z", "root": <tree> }` を出力。`AST_FORMAT_VERSION` 定数で管理し、`review-ast-dump`(`Dumper#dump_ast`)がこの形で書く。ノード木自体は不変(`serialize_to_hash`)で、ヘッダはダンプ境界だけが持つ。
  - `deserialize` はエンベロープを自動判別(`unwrap_document`): `ast_format`+`root` があれば版を検証して中身を取り出し、無ければ従来どおり bare ノードとして読む。未知の版は黙って誤読せず `StandardError`。`review-ast-dump2re` は `deserialize` 経由なので新旧両形式を読める。
  - コアの `serialize()` は据え置き(ノード単体のシリアライズは bare のまま)なので、既存テスト(`parsed['type']` を最上位で見る 31 箇所)への波及なし。境界テスト `test_dumper.rb` のみエンベロープに更新し、ヘッダ検証を追加。
  - テスト: `test_serialization_round_trip.rb` にエンベロープの round-trip バイト同一・版/generator の存在・bare/enveloped 両受理・未知版の拒否を追加。dump→dump2re の実フローも確認。フル `rake` 緑(1075 tests)、rubocop クリーン。
- 見送り(2026-07 判断): フィールド宣言 DSL(`serialize_fields`)。以下の理由で、具体的な駆動要因が現れるまで実装しない(同時に見送っていたスキーマ生成と別名キー非推奨化は、後日それぞれ別の形で決着した。本項末尾を参照)。
  - 乖離防止という当初の主目的は別手段で達成済み: 型判別子のコンストラクタ正規化統一(Symbol/String バグの根治)、全ノード型 deserialize 契約テスト、スカラーフィールド忠実性テスト、samples/PBT の render-identity、drift の温床だった `to_h` の撤去(表現を1系統化)。DSL で防ぐ必要がない。
  - boilerplate 削減は残るが効果は限定的。不規則シリアライズ(TableNode の header/body、CaptionNode の空→`''`、ReferenceNode の resolved_data、`if id?`/`start_number != 1`/`footnote_type.to_s` 等の条件付き)を素朴な DSL では表現できず、escape hatch を足すほど旨みが薄れる。規則的な一部だけ DSL 化し不規則な残りは手書き、という中途半端になりやすい。
  - スキーマ生成は今スキーマを消費する相手がいない(配布構想は近い具体ユースケースでない)。必要になった時点で、既に生成できる実ダンプ(samples/PBT)を introspect して起こす方が DSL 前提より素直。未使用ノードの構造的カバレッジも完全性テストが既に担う。
  - 将来 boilerplate を減らす場合も、全ノードに DSL を強いず「規則的なスカラー群だけを宣言する軽いヘルパを合う所にだけ」適用する方が現実的。
  - 駆動要因の例: 外部の AST 消費者がスキーマ(`additionalProperties: false` 含む)を要求する / 一度に多ノードを触るシリアライズ変更が必要になる。
  - 運用規則は先行して文書化済み: [ast-format.ja.md](ast-format.ja.md)(草案)が、キー命名の規則、`ast_format` の版更新判断基準、読み手への適合条件、スキーマとの関係、版更新チェックリストを定める。駆動要因が現れたときはこの規則に従って実装する。
  - 実装済み(render-identity を samples コーパスへ): `test/ast/test_corpus_render_identity.rb` が `samples/syntax-book` の全章を compile→serialize→deserialize し、5レンダラ全てで fresh と reloaded の描画一致を検査(実コンテンツでの round-trip 忠実性ガード)。
  - 実装済み(render-identity を PBT コーパスへ = 検証 CI 化): `test/ast/test_pbt_round_trip_identity.rb` が `tools/pbt` の生成器で固定 seed(1..30)のランダム Re:VIEW 文書を作り、round-trip byte 一致 + 5レンダラの fresh/reloaded 描画一致を検査。builder オラクル不要の自己整合性プロパティで、`rake test` に載るため恒常実行(≈0.3s)。「稀な構文の組み合わせでだけ出るシリアライズ欠落」を通常のテスト実行で捕捉する。
  - 実装済み(render-identity に plaintext / TOP を追加): `test_serialization_round_trip.rb` の RENDERERS に plaintext/TOP を追加。これが `InlineNode#inline_type` の Symbol→String 復元バグを検出(JSON では両方 `"br"` で byte 一致するため round-trip 検査では不可視、TopRenderer の `case ... when :br` が String で外れて `@<br>` の改行が消えていた)。deserialize で `.to_sym` 復元して修正。「シリアライズには現れないが描画に効く差」を捕捉する render-identity の狙いどおりの検出。
  - 実装済み(deserialize フィールド忠実性の系統ガード): `test/ast/test_deserialize_field_fidelity.rb` が包括フィクスチャの fresh と reloaded を並行走査し、全スカラーフィールドの値・クラス一致を検査(既知の良性省略 `ListNode#start_number`/`ListItemNode#item_number` のみ allowlist)。これで新ノード/フィールド追加時の Symbol/String・型変化バグを網羅的に捕捉。同ガードで `CodeBlockNode#code_type`・`MinicolumnNode#minicolumn_type` の同種バグも検出・修正済み。
  - 実装済み(round-trip 完全性テスト): `test/ast/test_serialization_completeness.rb`。(A) 全具象 Node サブクラスが `deserialize_from_hash` を実装している契約テスト(抽象は `LeafNode` のみと固定。新ノード型追加で deserialize を忘れると失敗)。(B) 21 のソース到達ノード型を1フィクスチャで実体化して byte 往復一致 + 型カバレッジ検証。
  - 決着(スキーマ生成、2026-07): 駆動要因(ast-semantics 5 章が適合キットとしてスキーマを挙げているのに実体が無い)が現れたため実装した。
    ただし当初設計の「フィールド宣言から生成する」は採らず、見送り時に記した代替どおり**実ダンプの introspect** で起こした。
    `tools/generate_ast_schema.rb` が samples の 2 コーパス(`syntax-book`、`md-syntax-book`)の全章をコンパイルしてダンプを走査し、`schema/ast-format-1.schema.json` を生成する(ノード 21 型 + ResolvedData 10 型、全定義 `additionalProperties: false`)。
    DSL は不要だった。不規則シリアライズを表現する必要がそもそも生じないためで、見送り理由 3 点目の想定どおりである。
    `test/ast/test_ast_schema.rb` が再生成して同梱物と比較し、シリアライズの形が変われば「schema is stale」で失敗する(`ParagraphNode` にキーを足して発火を実測)。JSON Schema バリデータ gem は不要: スキーマはコーパスから導出されるため妥当性は構成上自明で、検査すべきは同梱物の追随だけである。
    副産物として、`DirectiveNode` がスキーマに現れないことを lowering への表明としてテストに固定した(現れたら lowering に穴がある)。また `ResolvedData` 系はノードと同じく `type` を持つため初回生成でノード型に混入しており、`$defs/resolved_data` に分離した(ノードが来る位置に `ImageReference` を置けてはならない)。
  - 決着(別名キー、2026-07): 非推奨期間は設けず**削除**した。
    調査の結果、`element`/`numbered` を書き出すシリアライザは review-ast にも抽出元 upstream にも履歴上存在せず、受理コードだけが gem 抽出時から読み取り専用で入っていた。
    つまり互換コードではなく対応する生成側のない受理であり、該当するダンプは存在しない。削除しても観測可能な変化がなく、`ast_format` は 1 のままである。
    ポリシー文書([ast-format.ja.md](ast-format.ja.md))には規則(キーは正準名ひとつ、別名は作らない)だけを残し、別名が存在した経緯は書いていない。読み手に「そのキーを含むダンプがあるのか、対応が要るのか」という無用の問いを起こさせないためである(経緯はコミットに残した)。

---

## 5. 形式固有フィールドのソース事実への置き換え

### 問題

共有 AST のフィールドは、ソースが述べていることの再掲によって居場所を得る。
出力の決定の記録によってではない。
`EmbedNode#target_builders` はこの基準に適合する。
ソース自体が `//embed[latex]{...}` と書くのだから、ビルダー指定はソースの事実である。
適合しない箇所が三つある。

- `ListItemNode#latex_line_breaks` は、継続行の間でソースの改行が起きた位置を記録する。
  これは正真正銘ソースレベルの情報である。
  しかし唯一の消費者の名を冠し、その理由で意図的にシリアライズから除外されている。
  データは正しく、名前とシリアライズ方針が誤っている。
- `TableNode#col_spec` と `cellwidth` は、コンパイル時に `//tsize` から LaTeX 語彙の列指定文字列へ計算される。
  しかし `//tsize` 自体がソース上でビルダー指定の形(`//tsize[|latex|...]`)を持つ。
  ソースに忠実な表現は「`//tsize` の内容を、対象ビルダーごとに」であり(`target_builders` と並行)、中立なノードに焼き込まれた LaTeX 文字列ではない。
- `build_quote_block_ast` は quote ブロックの内容を平坦に(`parse_lists: false`)パースする。
  `LATEXBuilder` が quote の行をインラインコンパイルしかしないためである。
  一つのビルダーのパース挙動が、すべての消費者が受け取る木の形に焼き込まれている。

### 設計

- `latex_line_breaks` を `source_line_breaks` に改名し、シリアライズ対象にする
  (改名は項目 4 のフォーマット版更新が吸収する)。
  今日の消費者は引き続き LaTeX レンダラだけである。
  フィールドは正直な名前になり、`dump2re` はダンプから継続行を正確に再構成できるようになる。
- `//tsize` は書かれたとおりに保存する。
  内容とビルダー指定の組であり、`target_builders` と同じ形である。
  解釈は各レンダラが導出する。
  LaTeX の列指定の導出は `TsizeProcessor` から LaTeX レンダラ(または LaTeX 側のヘルパ)へ移す。
  内容からパースした数値幅はソースの事実であり、パース済みデータとして残してよい。
- quote ブロックの内容は、他のコンテナと同じく構造的にパースする。
  quote 内のリストの扱いがビルダー間で異なるべきかどうかは仕様の問いであり、AST の決定ではない。
  項目 6 のトリアージへ回す。
  裁定が出るまでは LaTeX レンダラが描画時に平坦化し、木を中立に保ったまま出力パリティを維持する。

### 移行手順

1. `source_line_breaks` への改名とシリアライズ化を、項目 4 の別名受理期間の下で行う。
2. `//tsize` の保存形を再構成し、LaTeX の導出をレンダラ側へ移す。
   全期間で比較スイートを緑に保つ。
3. quote ブロックをフラグの裏で構造的パースへ切り替え、LaTeX レンダラに描画時平坦化を入れる。
   仕様の問いを upstream へ提出する。
   DVI スイープが乾いたらフラグを外す。

### 検証

- 各ステップの後に比較スイート全体を回す。
  空白に敏感な二つのステップ(リスト継続行、quote パース)は DVI スイープも行う。
- 項目 4 の round-trip 同一性が `source_line_breaks` を覆う。
  加えて、継続行が正確に再構成されることを主張する `dump2re` のフィクスチャを追加する。
- 共有ノードクラスに対する lint 水準の検査として、出力形式の名を冠したフィールド(`latex_*`、`html_*` など)が残っていないことを確認する。
  形式名を冠したメンバーはレンダラの名前空間の中でだけ許す。

### 実装状況（2026-07 時点）

- 実装済み(移行手順 1: `source_line_breaks` への改名とシリアライズ化)
  - `ListItemNode#latex_line_breaks` → `source_line_breaks` に改名(`mark_latex_line_break!` → `mark_source_line_break!`)。ソース事実(著者が行を折った位置)に正直な名前にした。
  - シリアライズ対象にした(`serialize_properties` / `deserialize_from_hash`。空配列のときは省略)。LaTeX レンダラの消費側(`render_list_item_content`)を新名に更新。
  - これは源泉忠実化であると同時に、項目4で残っていた lossy の閉塞でもある。従来 `latex_line_breaks` は未シリアライズで、複数行リスト項目をダンプ→読み戻すと LaTeX の行結合(`\n`)が失われていた。`source_line_breaks = [2]` を持つ継続行フィクスチャで render-identity(新規描画 == 読み戻し描画)が一致することを確認し閉塞した。
  - 検証: フル `rake` 緑(1057 tests)、rubocop クリーン。DVI `samples/syntax-book` 6/6、round-trip 6/6、render-identity(LaTeX/HTML/IDGXML)6/6。新規フィクスチャ `list_continuation` を `test/ast/test_serialization_round_trip.rb` に追加。
- 現状の形式名フィールドの棚卸し
  - `ListItemNode#latex_line_breaks` → 解消済み。
  - Markdown 中の生 HTML 用の `MarkdownHtmlNode` は削除し、将来 MarkdownCompiler 導入時は `EmbedNode`(形式中立な `content`)を使う方針。format 名フィールドの allowlist も空にした。
- 実装済み(移行手順 2: `//tsize` の源泉忠実化)
  - `TableNode#col_spec`/`cellwidth`(焼き込まれた LaTeX 文字列)を廃し、生の `//tsize` 引数(例 `"10,18,50"` / `"|latex|10,18,50"` / `"|l|c|r|"`)を `TableNode#tsize` にソース事実・対象中立で保持する。
  - `TsizeProcessor` はフィルタも導出もせず、生の tsize を次の表へ付与して directive を除去するだけにした。これにより共有木が「どのビルダーでコンパイルしたか」に依存しなくなった(従来は `config['builder']` で compile 時にフィルタしていた)。
  - 対象フィルタと列指定導出を描画時へ移した。`TableColumnWidthParser.value_for_target(raw, format)` が `|builder|` プレフィックスを描画時に解決(`target_builders` と同型)。LaTeX レンダラが `latex_col_spec`/`latex_cellwidths` を、IDGXML レンダラが `idgxml_cellwidth` を、`TableNode#tsize_value_for(format)` 経由で導出する。デフォルト(全列左寄せ)もレンダラ側へ移した。
  - `review_generator`(dump2re)は `node.tsize` から `//tsize[...]` を再出力するようにした(源泉忠実な往復)。シリアライズも `col_spec`/`cellwidth` ではなく `tsize` を出す。
  - 検証: フル `rake` 緑(1064 tests)、rubocop クリーン。パリティ厳格確認 — DVI(LaTeX 列指定)`samples/syntax-book` 6/6、IDGXML バイト一致(セル幅)6/6、HTML 6/6。round-trip 9/9、render-identity 6/6。`TsizeProcessor`/`TableColumnWidthParser.value_for_target` のテストを新契約へ更新。
- 現状の形式名フィールドの棚卸し
  - `ListItemNode#latex_line_breaks` → 解消済み。
  - `TableNode#col_spec`/`cellwidth` → 解消済み(生の `tsize` に置換、描画時導出)。
  - Markdown 中の生 HTML 用の `MarkdownHtmlNode` は削除し、将来 MarkdownCompiler 導入時は `EmbedNode`(形式中立な `content`)を使う方針。format 名フィールドの allowlist も空にした。
- 移行手順 3(quote の構造的パース): 見送り。前提が実測に反する。
  - この手順の前提は「`build_quote_block_ast` の平坦パースは LATEXBuilder のパース挙動を焼き込んだもの」だが、実測すると LaTeX / HTML / IDGXML の 3 ビルダーすべてが `//quote` 内の `* x` / `1. x` / `: term` を「リストではなく平坦テキスト」として扱う(各 builder の read_block が行をインラインコンパイルするだけ)。
  - つまり `parse_lists: false` は「一つのビルダーの決定」ではなく Re:VIEW 共通のセマンティクスであり、むしろソース忠実(Re:VIEW における quote 内容の意味は「平坦テキスト」)。
  - これを構造的にパース(`parse_lists: true`)すると、(a) ソースの意味を誤って「リスト」と表現し、(b) パリティ維持のため LaTeX だけでなく 3 レンダラ全てに描画時平坦化を要し、(c) 出力上の利点はゼロでリスクだけ増える。よって実装しない。`build_quote_block_ast` のコメントを「全ビルダー共通の挙動」と明確化するに留めた。
  - 「quote 内リストをビルダー間で異ならせるべきか」という仕様の問いは依然として項目 6 のトリアージ対象。ただし現状の全ビルダー一致(平坦)が既定の答えである。
- 実装済み(lint 水準の検査)
  - `test/ast/test_no_format_named_fields.rb`: 共有 AST ノードに出力形式名を冠したフィールド(`latex_*`/`html_*`/`idgxml_*`/`top_*`/`epub_*`/`markdown_*`)が無いことを構造的に検査する。allowlist は空(生 HTML は EmbedNode の `content` で表す方針のため)。`col_spec`/`latex_line_breaks` 等の再導入を parity スイートに見えない段階で捕捉する。
- 実装済み(IDGXML cellwidth の源泉数値直読)
  - IDGXML は `TableColumnWidthParser`(LaTeX 語彙)で `p{Nmm}` を作ってから regex で数値を逆抽出していたのをやめ、ソースの `//tsize` 数値 CSV(mm)を直接 `split(/\s*,\s*/)` して読む。これは legacy IDGXMLBuilder#table(`@tsize.split(/\s*,\s*/)`)そのままで、LaTeX 経由の往復を排除。`TableColumnWidthParser` は LaTeX renderer と target フィルタ(`value_for_target`)で引き続き使用。
  - 非数値 tsize(`|l|c|r|` のような LaTeX 列指定)は IDGXML では無意味なので幅なし=等分に倒す。これは legacy(tsize target フィルタで idgxml 非該当→nil→等分)とも、旧 AST(非数値を regex で落として空→等分)とも一致。旧コードが `.compact` で偶然マスクしていた `value_for_target` の単一文字 heuristic 差(`|l|c|r|` を generic 扱い)による乖離を、数値 CSV ガードで回避。
  - 検証: `test/ast/test_idgxml_tsize.rb` が AST renderer と legacy IDGXMLBuilder の `aid:ccolwidth` 一致を数値/generic 数値/`|l|c|r|`/`|latex|` 限定の各ケースで pin。IDGXML sweep 6/6・DVI 6/6・全テスト緑・rubocop クリーン。

---

## 6. ビルダーから独立したセマンティクスの文書化

### 問題

現在、正しさは「`LATEXBuilder` と一致すること」と定義されている。
レガシービルダーがオラクルなので、AST はビルダーのバグを正しさの定義として継承する。
[spec-questions.md](spec-questions.md) は、作者がまさにそれを自覚しているからこそ存在し、[differential-testing.md](differential-testing.md) は既知のギャップ一覧を保持している。
存在しないのは、AST が何を意味するかを自立して述べる文書である。
参照実装はセマンティクスを定義する側だが、ここではセマンティクスが置き換え対象によって定義されている。

このギャップは実務にも直結する。
配布構想は AST JSON を消費する外部レンダラを想定しており、その作者に必要なのは Ruby ソースではなく文書である。
また、ビルダーからの意図的な乖離(表区切りの閾値、AST が再現を拒む `@<comment>` セルのバグ)は、現在コードコメントと spec-questions に半分ずつ散っており、何がなぜ決まったのかを記録する単一の場所がない。

### 設計

`doc/ast-semantics.md`(日本語版を併設)を、四つの部分から組み立てる。
これまでの項目はこの素材を生産するように書かれており、本項目はそれを組み立てて誠実に保つ。

1. **ノード目録**：すべてのノード型について、意味、フィールド、それを生むソース構文を記す。
   骨格は項目 4 のフィールド宣言から生成する。
   これにより、ノード型が黙って抜け落ちることはない。
2. **パイプラインのセマンティクス**：項目 3 の段階モデル(surface tree → lowering パス群 → core tree)と各パスの一文仕様、項目 2 の分離セマンティクス、項目 1 の番号付けセマンティクス。
   段階ごとのセマンティクスがあってはじめて、再実装の適合性が検査可能になる。
3. **乖離レジストリ**：AST がビルダーと意図的に異なるすべての箇所について、構文、ビルダーの挙動、AST の挙動、理由、互換分類(後述)、upstream の状態を記す。
   spec-questions.md と differential-testing.md の既知ギャップ一覧から機械的に種を起こす。
4. **適合基準**：再実装が満たすべきことを、ソースと `review_version` の組ごとに、段階を追って述べる。
   同じ surface tree(スキーマ検証付き)、lowering 後に同じ core tree、形式ごとに同じ描画出力。
   コーパス、生成スキーマ、比較器を合わせたものが、実行可能な適合キットになる。

仕様の問いのトリアージは次のループで回す。
各問いを upstream(kmuto/review)へ提出し、裁定をレジストリに記録する。
「意図どおり」なら仕様になり、「バグ」なら upstream の修正となり、修正が出荷されるまで AST は意図的な乖離として文書化する。
jlreq-trimmarks の一件は、このループが端から端まで機能することを既に実証している(最小再現 → upstream 修正 → TeX Live 版をまたぐ CI の固定)。

### 互換性政策

仕様が既存文書に挙動変更を強制してはならない。
「既存のソースがビルドでき続けること」自体が仕様の一部である。
具体的には次のとおり。

- **仕様は一つ、分岐点にだけ版注釈**：セマンティクスは版に依存しないことを基本とし、トリアージ済みの乖離点にだけ `review_version` の範囲を付す(「5.x まで: …、6.0 から: …」)。
  これは Re:VIEW が既に使っている機構の公式化である。
  ビルダーと pdfmaker は今日、`config.check_version('2', exception: false)` による挙動分岐を十数箇所持っている。
- **バグの裁定には互換分類を付す**：
  **即修正**：その挙動に動く文書が依存し得ない場合に限る(組版不能な出力しか生まなかったもの。spec-questions の 4 番)。
  **`review_version` でゲート**：誤っているが、もっともらしい出力に依存が生じうるもの。旧版を宣言した文書はバグ互換の挙動を受け取り続ける。
  **正典化**：定着していて害が小さいもの。意図された挙動として仕様に採用する。
- **影響は推測せず測る**：分類の前に、実書籍コーパスと PBT コーパスを新旧両方のセマンティクスで描画し、影響を受ける文書数を数える。
  新しい `review_version` で意味が変わる構文を検出する lint があれば、著者は壊れる前に移行の警告を受け取れる。
- **ゲートには予算を設ける**：ゲートを一つ作るたびに、旧版のサポートが続く限り両方の挙動をテストで固定し続ける義務が生じる(比較器とフィクスチャを `review_version` でパラメタ化する)。
  Re:VIEW は今日も 2.x の挙動を維持しており、ゲートは長寿命の約束である。
  乖離レジストリがゲートの台帳を兼ねる。
- **木の形は版に依存させない**：分岐はコンパイラ、lowering、レンダラの挙動に置き、ノードのスキーマには決して置かない。
  項目 4 のフォーマット契約を `review_version` で分裂させない。
  ダンプのヘッダには生成時の `review_version` を記録する。

パリティ第一の移行戦略は変わらない。
AST はまずバグ互換でビルダーを置き換え、ゲート付きの修正はその後に `review_version` を通って入る。

### 移行手順

1. 骨格を今すぐ作る。
   乖離レジストリは既存二文書からの機械的な抽出であり、ノード目録はスタブを置く。
2. 未解決の仕様の問い四件を upstream へ提出し、裁定と互換分類を届き次第レジストリへ記録する。
3. 項目 1〜3 が完了するたびに、その設計節をセマンティクス文書へ移し込む(そのまま持ち上げられるように書いてある)。
4. 文書の網羅性検査を追加する。
   コンパイラが認識するブロック命令とインライン命令の集合と、セマンティクス文書が覆う構文の集合を突き合わせ、セマンティクスなしに命令が追加されたら失敗するテストとする。

### 検証

文書に対する検証は、網羅性と鮮度である。

- 上記の網羅性検査を CI で実行する。
- 乖離レジストリの全項目が upstream の issue へのリンクか明示的な決定の記録を持つこと。
  「未定」のまま 1 リリースを越える項目を作らない。
- レジストリ上のすべての `review_version` ゲートが、両方の挙動のフィクスチャで覆われていること。
- 適合キットが第三者にとって実行可能であること。
  スキーマ検証、round-trip 同一性、コーパスに対する比較器の実行が、Ruby ソースを読まずに行える。

### 実装状況（2026-07 時点）

- 実装済み(骨格 + 実体のある初版)
  - `doc/ast-semantics.md` を作成。四部構成: (1) ノード目録(全24ノード型の意味/主要フィールド/生成する構文)、(2) パイプラインセマンティクス(surface→lowering→core の段階、ブロック分離、定義番号・章タイトル)、(3) 命令リファレンス(`BLOCK_COMMAND_TABLE` の全ブロック命令と `DEFAULT_INLINE_HANDLERS` の特殊インライン命令を列挙)、(4) 乖離レジストリ(spec-questions の5件を表化: 構文/builder 挙動/AST 挙動/互換分類/upstream 状態)、(5) 適合基準(段階別: 同一 surface tree → 同一 core tree → 形式別の描画一致)。
  - 日本語版 `doc/ast-semantics.ja.md` を併設(英語版と同一内容・同一コードトークン)。
  - 網羅性検査を実装: `test/ast/test_semantics_coverage.rb` が (a) 全ブロック命令、(b) 全特殊インライン命令、(c) 全 Node サブクラスが英語版・日本語版の両方に載っていることを検査。命令やノード型を追加して文書化を忘れる、または両版が乖離すると失敗する(文書がコードに遅れず、両版が同期する鮮度ガード)。
- 積み残し
  - 乖離レジストリ5件の upstream(kmuto/review)提出と裁定・`review_version` ゲートの記録(現状はすべて open)。
  - 適合キットのスキーマ生成(項目4のフィールド宣言 DSL 前提)と第三者実行可能性の CI 化。

---

## 実施順について

項目 1 と 3 はどちらもコンパイラとインデクサ側に触れ、ポストプロセスを減らす。
項目 2 はレンダラ側で独立している。
構造系三項目の実際的な順序は次のとおり。

1. 項目 1(定義番号)。効果が高く、既存テストによる保護が厚い。
2. 項目 2(分離モデル)。もぐら叩き型のバグのクラスを絶つ。DVI の規律が要る。
3. 項目 3(マーカー)。最も侵襲的であり、先行二項目で作られるフィクスチャの恩恵を受ける。

項目 4〜6 はこれらの後に続くのではなく、かみ合って進む。

- 項目 4 は項目 1 と並走で始める。
  `definition_number` はシリアライズが必要であり、フィールド宣言 DSL がその自然な着地点になる。
  以後の構造系項目は、手書きのシリアライザ対を編集する代わりに宣言を拡張する。
- 項目 5 は小さく、項目 4 のフォーマット版更新に相乗りする。
  quote パースのステップだけは項目 6 のトリアージの裁定を待つ。
- 項目 6 は継続的に進める。
  乖離レジストリは今日組み立てられ、項目 1〜3 はそれぞれ完了時にセマンティクス文書の担当節を納める。

---

## 7. AST 側インデックス表と monkey patch の撤去

項目 1 の実装進行から派生した項目である。
`core_ext` の三フックのうち二つの撤去条件を定め、AST と本体の依存を一方向に整理する。

### 問題

二つのフックは、AST が自分の計算結果を本体オブジェクト経由で受け渡すためだけに存在している。

- `Index::Item` への `caption_node` 追加(prepend)。
  実測では、読み手は `ReferenceResolver` だけ(約 10 箇所)で、書き手は `Indexer` である。
  両端が AST 側にあり、レガシー `Item` は AST が自分自身にデータを渡すための運び屋にすぎない。
  resolver に残る `item.respond_to?(:caption_node)` ガード(`reference_resolver.rb:294`)は、この方式の不安定さの症状である。
  ただし対象は Item 側のガードだけである。`node.respond_to?(:caption_node)`(`reference_resolver.rb:85`、`top_renderer.rb`、`plaintext_renderer.rb`)は「その AST ノード型が caption を持つか」という別事であり、prepend とは無関係に正当なので残す。
- `BookUnit#ast_indexes=`。
  `BookUnit` の私有インスタンス変数 12 個へ書き込み、AST 自身が `chapter.list_index` などで読み返している。

このためデータフローが循環し、AST は本体の内部表現(ivar 名と `Item` の形)に結合している。

```
現在:   本体(Book) ──構造の入力──▶ AST(Indexer)
            ▲                        │
            └── ast_indexes= で書込 ──┘
            ┌── Item を読み返し ─────▶ AST(Resolver)
```

判定の一般則も記録しておく。
**AST の契約(スキーマとセマンティクス文書)に現れるデータ型は所有し、契約に現れないサービス(book モデル、i18n、maker 群など)は再利用する。**
位置情報を `SourceLocation` として所有したのはこの規則の適用例である。
`Item` は境界上にあるが、答えは「自前の Item で置き換える」ことではなく、役割を分割して AST の世界から `Item` を消すことである。

### 設計

`BookIndexer` が所有する AST 側の章別インデックス表を導入する。

```
仮称 ChapterIndexRegistry
章 id → 要素種別 → 要素 id → { definition_number, caption_node, ... }
```

- `ReferenceResolver` は `Item` ではなくこの表を読む。
  `caption_node` の prepend は削除する。
  表が持つ `definition_number` は項目 1 で定義側ノードへ刻印したものと同じ `DefinitionNumber` 値オブジェクトを再利用する。
  これで「定義側はノード、使用側は表」という対称が完成し、resolver が `item.number` を読む最後の経路も畳める。
- `ast_indexes=` は書き込み専用の一方向アダプタへ縮小する。
  AST のデータから素のレガシー `Index`/`Item` を構築して本体側消費者(将来の epubmaker、TOC 生成)へ供給するだけで、AST は読み返さない。
  合流時には本体内の通常コードに置き換わり、パッチとしては消滅する。
- レンダラに残る `@chapter`/`@book` 到達(約 38 箇所)を棚卸しする。
  インデックス読み(非バインド `//imgtable` のフォールバック、plaintext `render_inline_fn`、TOP `printendnotes` など)は表または `definition_number` へ移し、環境系(画像パスの解決)は正当な残余として残す。

データフローは次の形になり、循環が消える。

```
今後:   本体(Book) ──構造の入力──▶ AST(索引 → 解決 → 描画)
                                      │
                                      └──(一方向アダプタ)──▶ 本体側消費者
```

この整理の実利は依存の削減量そのものではなく、AST が本体の内部表現から切り離され、本体との関係が「構造の入力」と「出口アダプタ」という二つの細い公開インターフェースに集約されることにある。
シリアライズした AST の自己完結(項目 1 の受け入れテスト)と、AST JSON を読む外部レンダラの review 非依存化は、この形を前提とする。
副産物として、章別インデックス表は LSP 構想における増分キャッシュの単位を兼ねる。

### 移行手順

1. 章別インデックス表を導入し、`Indexer` が `Item` と並行して表にも書く(挙動不変)。
2. `ReferenceResolver` の読み先を表へ切り替え、`caption_node` の prepend を削除する。
3. レンダラの残存インデックス読みを棚卸しし、表または `definition_number` へ移す。
4. `ast_indexes=` を書き込み専用アダプタとして固定する
   (読み返し禁止をコメントで明記し、可能なら ivar 直接代入を公開コンストラクタ経由の構築に置き換える)。
5. 合流時にアダプタを本体内の通常コードへ置換する。

### 検証

- 全比較スイートが緑であり続けること(参照解決の結果はテキスト比較で完全に見える)。
- 受け入れテスト: AST パイプライン(コンパイル → 索引 → 解決 → 描画)が、本体の `Index` オブジェクトを一度も読まずに完走すること。
- 計器: monkey patch の本数が単調減少すること(本項目で prepend が消える)、`require 'review/...'` の一覧が安定していること。
  ある置き換え案がパッチを一つも減らさないなら、契約データ型の所有ではなくサービス再実装への逸脱(creep)を疑う。

### 実施時期

項目 1 の続きとして早期に着手できる。
項目 4(シリアライズ)とは独立であり、LSP 構想の前提部品を先に作る効果がある。

先行して可能な低リスク作業として、第三フック(`SnapshotLocation#to_h`/`#format_for_error`)の撤去がある。
このフックは位置情報を `SourceLocation` として所有した時点で production からは既に外れており(`lib/` に `SnapshotLocation.new` は 0 件、AST は生成・復元とも `SourceLocation`)、いま生かしているのはテストの `ReVIEW::SnapshotLocation.new`(約 511 箇所 / 20 ファイル)だけである。
これらを `ReVIEW::AST::SourceLocation.new` へ機械移行すれば SnapshotLocation パッチを削除でき、本項目の表を作るより前に monkey patch の本数を 3 → 2 に減らせる。

### 実装状況（2026-07 時点）

- 実装済み(第三フックの撤去 = 上記の低リスク前哨)
  - テストの `SnapshotLocation.new`(511 箇所 / 20 ファイル)と `require 'review/snapshot_location'`(8 ファイル)を `ReVIEW::AST::SourceLocation` へ機械移行。
  - `core_ext.rb` から `SnapshotLocation#to_h`/`#format_for_error` パッチを削除。monkey patch は 3 → 2(`Index::Item#caption_node` prepend と `BookUnit#ast_indexes=` のみ)。
  - `lib/` の `@param location [SnapshotLocation]` docstring を実体に合わせ `[SourceLocation]` に更新。
  - 検証: フル `rake` 緑(1065 tests)、rubocop クリーン、DVI 6/6・round-trip 6/6(挙動保存)。`test/ast/test_source_location.rb` が「column nil のとき to_h/format_for_error はレガシー一致」を担保し、移行の安全性を裏付ける。
- 実装済み(手順 1: 表の導入 + Indexer 並行書き込み、挙動不変)
  - `ReVIEW::AST::ChapterIndexRegistry` を新設(章内の `種別 → id → {number, caption_node, footnote_node}`)。`Indexer` が各 `Index::Item` 生成箇所と並行して `register(...)` で表にも書く。caption は Item ではなく AST ノード(`node.caption_node`)から直接取り、脚注/後注は定義ノードを持つ。番号はレガシーインデックスと一致。
  - テスト `test/ast/test_chapter_index_registry.rb`: 表クラスの add/lookup/key?/ids と、Indexer が list/table/image/equation/footnote について番号・caption・脚注ノードを正しく表へ書くことを検証。現段階では resolver は表を読まない(挙動不変)。
  - 検証: フル `rake` 緑(1070 tests)、rubocop クリーン。
- 実装済み(手順 2: resolver の読み先を表へ切替 + `Item#caption_node` prepend 撤去)
  - `ReferenceResolver` の全 `resolve_*` を、レガシー `Book::Index`/`Item` ではなく `ChapterIndexRegistry` の `lookup` から読むよう書き換え。caption_node・footnote_node・番号はすべて表由来。`find_index_item`/`safe_column_fetch`/`index_item_number`、および Item 側 `respond_to?(:caption_node)` ガードを削除。
  - 相互参照(cross-chapter)は `registry_for(chapter)` が対象章を on-demand で compile+index して章別に表をキャッシュする(ブック全体の事前パスや `@book` 経由の Book::Index 読み返しは不要)。同章は生成時の表を再利用。
  - キー付けの実測対応: 見出しはレガシー `HeadlineIndex` に合わせフルパス(`親|子`)と葉(label/caption)単体の両方で登録。bibpaper は bib ファイルの1行形式を compiler が索引化できないため、`@<bib>` 参照時に first-reference 順で自動登録(レガシー `IndexBuilder` と一致)し、表にも登録。定義があれば bib ファイル/現章の表から caption_node を得る。
  - `core_ext.rb` から `Index::Item#caption_node` prepend を削除。monkey patch は 2 → 1(`BookUnit#ast_indexes=` のみ)。`Indexer` は `Item.new` に `caption_node:` を渡さなくなり、caption は表だけが持つ。`item.caption_node` を読んでいたテストは `indexer.registry.lookup(...).caption_node` へ移行。
  - 注入型ユニットテスト(レガシー index を手動注入し参照のみをコンパイルしていた image/cross-chapter 系)は、新モデルの契約(定義は AST にある)に合わせ、定義をソースに含める形へ更新。
  - 検証: フル `rake` 緑(1070 tests)、rubocop クリーン。IDGXML byte 一致(syntax-book 6/6、FirstStep 11/12 = review-introduction は本項目と無関係の既存差)。DVI ident 一致(syntax-book 6/6、FirstStep 12/12、cross-chapter `@<hd>`・bib 参照を含む)。HTML の残差はブロック間空白と `@<idx>` コメント内エスケープのみで、いずれも参照解決と無関係の既存 gap。
- 実装済み(手順 3: レンダラ残存インデックス読みの棚卸し)
  - 棚卸しの結果、レンダラの `chapter.<x>_index` 読みは大半が dead code だった。参照は resolved_data、定義側番号は node の `definition_number` に統一済みで、以下は到達不能:
    - LaTeX inline handler の `render_same_chapter_{list,table,image}_reference` / `render_cross_chapter_{list,table,image}_reference`(6メソッド、呼び出し元ゼロ。`render_inline_{list,table,img}` は resolved_data 経由)。
    - `latex_renderer` の `visit_block_footnote`(//footnote は FootnoteNode になり `visit_footnote` が `node.definition_number` で処理。probe で BlockNode 化しないことを確認)と `get_equation_number`(`visit_tex_equation` は既に `node.definition_number` を使用)。
    - `latex/inline_context` の `bibpaper_number`(top/html renderer は既に `node.definition_number` を使用)。
  - これら dead handler を削除(手順 6 の dead handler 整理も兼ねる)。残る唯一のインデックス読みは IDGXML の `@chapter.image_index.image_finder.add_entry`(画像パス登録=環境系)で、設計どおり正当な残余として保持。
  - 検証: フル `rake` 緑(1070 tests)、rubocop クリーン、DVI 6/6 ident 一致(挙動不変=削除は純粋な dead code)。
- 実装済み(手順 4: `ast_indexes=` の書込専用アダプタ化=文書化)
  - 手順 2/3 の結果、AST パイプラインは参照解決・番号付与のために `chapter.<x>_index` を一切読まなくなった(唯一の読み手は image_finder の環境用途)。よって `ast_indexes=` と `Indexer#set_indexes_on_chapter` は事実上すでに一方向。両者に「書込専用・読み返し禁止(読み返しは旧循環への回帰=registry へ回せ)」の契約をコメントで明記。
  - 「ivar 直接代入 → 公開コンストラクタ」への置換は BookUnit に公開 setter が無く本体改修が必要なため、手順 5(合流時)へ持ち越し。
- 実装済み(手順 5 相当: 画像パスの AST 所有化 → `ast_indexes=` 撤去 → core_ext を patch ゼロ化)
  - 手順 4 時点で残っていた唯一の実消費者は「画像パス解決」だった(`@chapter.image(id).path` を全レンダラ + maker が読む)。これを `definition_number` と同じ要領で AST 所有化: 基底 `Node` に `image_path` フィールドを追加し、新設のポストパス `ImagePathProcessor` がコンパイル時に `ReVIEW::Book::ImageFinder` で一度だけ解決して ImageNode / `//imgtable` TableNode / `@<icon>` InlineNode へ刻印(ツリー全体=caption 内も走査。id 無しブロックの caption 内 icon を取りこぼさないため)。FS 走査という I/O はコンパイル時の一度きりで、結果は AST が持つ。unbound `//imgtable` の画像番号振り直しは Indexer が刻印する `imgtable_image_number` を使う。
  - 併せて残りの chapter インデックス読みを AST 由来へ移行: endnotes は `//endnote` 定義ノードをツリーから収集(`Base#endnote_nodes`、番号順)、footnote 番号は定義側 `definition_number`・参照側 `resolved_data`、`//graph` は生成パスを直接使用(`image_finder.add_entry` 削除)。これでレンダラ・maker・比較ハーネスから `chapter.<x>_index` 読みが全廃。
  - `Indexer#set_indexes_on_chapter` と `BookUnit#ast_indexes=` を撤去。`core_ext.rb` は monkey patch ゼロになり、`require 'review/book/index'` と `require 'review/book/book_unit'` も不要に(残るは `unicode/eaw` の soft require のみ)。その後 `f2b6d17` で空になった `core_ext.rb` をファイルごと削除した。`BookIndexer` は索引を書き戻さなくなり vestigial な no-op(外部呼び出し互換のため保持)。
  - 検証: フル `rake` 緑(1075 tests)、rubocop クリーン。IDGXML byte 一致(syntax-book 6/6、FirstStep 11/12=review-introduction は既存差)。DVI ident 一致(syntax-book 6/6、FirstStep 12/12)。画像・icon・imgtable・endnote・脚注を含めて挙動不変。
- 手順 5(完了): レジストリ供給の注入化 —— 表の作り手を resolver から追い出す
  - 動機: `ReferenceResolver#build_registry_for_chapter` が cross-chapter 参照のたびに `Compiler.for_chapter(...).compile_to_ast(...)` を呼んでいた。Compiler が解決フェーズとして resolver を呼び、resolver が Compiler を作るという相互知識(循環)であり、resolver を単体で検証するには Compiler ごと差し替える必要があった。
  - `ChapterRegistryProvider` を新設(`lib/review/ast/chapter_registry_provider.rb`)。「章 → `ChapterIndexRegistry`」の供給とキャッシュだけを持つ。既定の作り手は従来どおり on-demand コンパイル+索引化で、`Compiler` の require は循環回避のため呼び出し時に遅延させる。
  - `ReferenceResolver.new(chapter, registry_provider:)` で注入。resolver から `Compiler` 参照が 0 になり、`registry_for` は表を引くだけになった。自章の表は `provider.seed` で渡すので二重コンパイルはしない。`bib_file_registry` も provider 経由。
  - `compile_to_ast(..., registry_provider:)` でスレッド可能にし、book 全体を回す出力側(`AstHtmlConverter`、PDF/IDGXML/Text の `RendererConverterAdapter`)が book 単位で 1 つの provider を共有するようにした。これが上記「効率化(任意)」の着地点であり、`BookIndexer` 前提の当初案は同クラス撤去済みのため provider 共有で置き換えた。
  - 効果(索引構築回数): syntax-book 3 → 2、FirstStepReVIEW-v3(12章)3 → 0。book を順に回す間に各章の表が seed されるため、後方参照は追加コンパイルなしで解決する。
  - 併せて、索引構築失敗時の `rescue` を `$DEBUG` 条件なしの warn に変更。従来は無言で空表にフォールバックし、その章への参照すべてが「reference not found」として現れて原因を誤診させていた。
  - テスト `test/ast/test_chapter_registry_provider.rb`: キャッシュ(章ごと1回)、seed 済み章を再構築しないこと、nil 章、そして「用意した表だけで cross-chapter 参照が解決でき、対象章のコンパイルが一切起きないこと」(作り手が呼ばれたら `flunk`)を検証。
  - 検証: フル `rake` 緑(1090 tests)、rubocop クリーン、syntax-book 6/6 DVI 一致。
- 積み残しなし(本項目は完了)。vestigial だった `BookIndexer` とその外部呼び出しは手順 2 で撤去済みで、コード上に残存はない。

---

## 8. 本体との界面の縮約と契約化

項目 7 の完了(monkey patch ゼロ化)を受けて、本体と review-ast の関係全体を実測し直した結果から導いた項目である。
項目 7 の一般則「AST の契約に現れるデータ型は所有し、契約に現れないサービスは再利用する」を、残る界面の全域に適用する。

### 界面の実測(2026-07 時点)

依存の現状は次のとおりで、界面はすでに三つの狭い箇所に集約されている。

- **入口**: compiler が `@chapter.content` を `ReVIEW::LineInput` へ流す 1 箇所。
  本体のパーサ部品への依存はこの `LineInput` だけで、字句解析(inline / block / headline)は全て AST の独自実装である。
- **renderer の初期化**: `Renderer::Base#initialize` の 1 箇所で chapter → book → config を束ねる。
  以降の live な読みは `chapter.number`(見出し番号と secnolevel 判定)、`chapter.id`(リンクとファイル名)、`is_a?(ReVIEW::Book::Part)` 判定、`book.imagedir`/`basedir`(環境パス)、および config に限られる。
  旧 `@chapter.image` / `.list` / `.endnotes` 系の読みは全てコメント内にのみ残る(live 依存ゼロ)。
- **索引**: `Indexer` がレガシー `ReVIEW::Book::*Index` / `Index::Item` を約 40 箇所で構築するが、消費者は AST 内の `ChapterIndexRegistry` に移っており、本体側にも読み手はいない(構築は vestigial)。

このほかの数字は次のとおり。
本体 require は 19 種(純粋ユーティリティ 12、パーサ 1、Book モデル 3、config 1、画像 2、maker 継承 3)。
config の読みは約 30 キー、約 100 箇所。
`ReVIEW::I18n` の呼び出しは 47 箇所で、うち約 35 箇所が `TextFormatter` に集まる。
本体 → AST の逆参照はゼロ、monkey patch もゼロである。

### 問題

界面は細いが、まだ「契約」になっていない箇所が残る。

- **README が実装より古い**:
  README は今も「本体クラスへの変更は 3 つの純粋追加フック(34 行)を `core_ext.rb` の load-time patch として当てる」と説明しているが、実態は `core_ext.rb` ごと削除済みでパッチ 0 件である。
  単なる陳腐化ではなく、本体との関係を実際より侵襲的に見せており、upstream への提案材料として最も強い事実(released gem への通常依存だけで動く)を主張し損ねている。
- **使われない索引を作り続けている**:
  レガシー Index 構築は出力に効かない副産物であり、`ReVIEW::Book::*` への参照の大半(約 40 箇所)と `require 'review/book/index'` をこれだけのために抱えている。
  `BookIndexer.build` は maker、比較ハーネス、compile から呼ばれ続ける実質 no-op である(項目 7 の積み残しと同一)。
- **renderer の入力が本体オブジェクトのまま**:
  renderer が本当に必要とするのは章番号、章 id、Part かどうか、少数のパス、config の値であり、`Book`/`Chapter` オブジェクトそのものではない。
  Book を要求し続ける限り、「AST JSON を読む外部レンダラの review 非依存化」(配布構想)は設計としては未達で、項目 1 の受け入れテスト(`Book` なしでの描画)もフィクスチャ上の事実にとどまる。
- **config 依存が暗黙**:
  どの config キーが描画結果に効くのかがコードを読まないと分からない。
  `secnolevel` や `join_lines_by_lang` のように出力を変えるキーはセマンティクスの一部であり、AST JSON の消費者に対する契約に含まれるべきである。
- **I18n の集約が不完全**:
  ロケール依存の文字列組み立ては `TextFormatter` にほぼ集まっているが、indexer(`part_short`)と inline handler 2 箇所が直接 `I18n` を呼んでおり、「1 クラスの責務」と言い切れない。
- **EPUB 経路が未移植**:
  maker は PDF / IDGXML / TEXT が本体 maker の継承 + converter 差し替えで動くが、EPUB だけ AST レンダラへの差し替えが存在しない。

### 設計

- **README の現行化**:
  「パッチフリーの別 gem。本体クラスの再オープンなし、依存は released gem の公開 API のみ」という現状を正面の説明にする。
  本体との関係の節は、実測に基づく界面一覧(入口、renderer 初期化、サービス再利用)へ置き換える。
- **レガシー索引構築の撤去**:
  `Indexer` から `ReVIEW::Book::*Index` / `Index::Item` の構築を取り除き、`ChapterIndexRegistry` への登録だけにする。
  `BookIndexer.build` の外部呼び出し(maker、比較ハーネス、bin)を除去し、`require 'review/book/index'` を落とす。
- **型付き描画コンテキストの導入**:
  renderer が chapter/book から読んでいる値の束を、AST 契約側が所有する小さな値オブジェクト(仮称 `RenderContext`: 章番号、章 id、part 判定、imagedir 等のパス、検証済み config サブセット)にまとめ、renderer は本体オブジェクトに触れない形にする。
  compiler の入口も同様に「ソース文字列 + メタデータ」を受ける形へ寄せ、入口の契約を明文化する。
- **config キーの契約化**:
  描画に効くキーの一覧と意味を項目 6 のセマンティクス文書と適合キットに含める。
  実装上は `RenderContext` の config サブセットがその一覧と一対一に対応する。
- **I18n の集約**:
  直接呼び出しの残り(indexer と inline handler)を `TextFormatter` 経由へ寄せる。
  i18n サービス自体は一般則どおり本体のものを再利用し続ける(切り離さない)。
- **EPUB maker の移植**:
  他の maker と同じ「本体 maker 継承 + converter 差し替え」の形で揃える。

### 移行手順

低リスクで効果が見える順に並べる。

1. README の現行化(コード変更なし)。
2. レガシー索引構築の撤去と `BookIndexer.build` 呼び出しの除去(項目 7 の積み残しの回収)。
3. I18n の直接呼び出しを `TextFormatter` へ集約。
4. `RenderContext` を導入し、renderer を一つずつ本体オブジェクト非依存へ変換する(項目 1 のレンダラ変換と同じ順序: LaTeX → HTML / IDGXML → plaintext / TOP)。
5. config キーの契約化(項目 6 のセマンティクス文書と同時に進める)。
6. EPUB maker の移植。

### 検証

- 全比較スイート(DVI、HTML、IDGXML)が各手順で緑であり続けること。
- 計器: 本体 require の種類数と `ReVIEW::Book::*` 参照数が単調減少すること。
  手順 2 の完了時点で `require 'review/book/index'` が消えていること。
- 受け入れテストの昇格: 項目 1 の「`Book` を構築せずに描画する」テストを、`RenderContext` + AST JSON だけを入力とする形に拡張し、外部レンダラの review 非依存化が設計として成立したことをこれで判定する。
- 手順 5 の完了時点で、描画に効く config キーの一覧に対する網羅性検査(コード中の config 読みと文書の一覧の突き合わせ)を項目 6 の網羅性検査に相乗りさせる。

### 実装状況（2026-07 時点）

- 実装済み(手順 1: README の現行化)
  - 冒頭の「本体クラスへの 3 つの純粋追加フック(34 行)を core_ext.rb で load-time patch」という記述を撤去し、「re-opens no Re:VIEW class / applies no monkey patch / 依存は released gem の公開 API のみ」を正面に。「How the upstream hooks work」の 3 パッチ表を「Relationship to Re:VIEW」節へ置換し、界面実測(LineInput 入口、renderer 初期化の live な読み、再利用サービス)と「patch ゼロ・逆参照ゼロ」を明記。
- 実装済み(手順 3: I18n の render 側集約、一部)
  - render 側の直接 `I18n.t` を `TextFormatter` 経由へ: LaTeX imgref は既存の `format_image_quote`、HTML ruby は新設 `ruby_prefix`/`ruby_postfix` を使用。
  - `indexer.rb` の `part_short` は据え置き。これは compile 側の章番号整形で、`TextFormatter#format_chapter_number_*` と実質重複しており、render 側ヘルパへ移すより「番号整形の共通化」として手順 4(RenderContext)で扱うのが適切。`I18n.setup`(ロケール初期化)は文字列組み立てではないので対象外。
- 実装済み(手順 2: レガシー索引構築の撤去)
  - `Indexer` を全面書き換え。`ReVIEW::Book::*Index`/`Index::Item` の構築を全廃し、採番は `@number = Hash.new(0)` の `next_number(type)`(`@X_index.size+1` の等価再現)へ置換。indepimage/numberlessimage/imgtable-image は indepimage カウンタ共有、image/graph は image カウンタ共有という採番規則を厳密維持。`indexes`/`index_for`/各 `attr_reader :*_index` を撤去し、残すのは `attr_reader :registry` のみ。footnote/endnote は AST 自前の `FootnoteIndex`(参照順採番)を保持。
  - `require 'review/book/index'` を `indexer.rb` から削除。
  - `BookIndexer` を撤去(ファイル削除)し、全 9 呼び出し(dumper/compile/pdf/idgxml/text maker + 比較ハーネス 3 + renderer テストの require)を除去。production の maker は book ディレクトリ内で走るため書き戻し prepass は不要。
  - テスト(test_ast_indexer/_pure、test_chapter_index_registry)を `indexer.registry.lookup(:X, id)` / `ids(:X)` 参照へ移行。icon は索引化していなかった(番号未使用)ため対応テストを削除。`ChapterIndexRegistry#ids` を追加。
  - 比較ハーネスの `load_book` では `BookIndexer.build` の代わりに `book.generate_indexes` を `Dir.chdir(book_dir)` 内で呼ぶ。`imagedir` は cwd 相対解決のため、ここで ImageFinder の dir キャッシュを暖める必要がある(production は book ディレクトリ内実行なので不要)。これで DVI 6/6・IDGXML 6/6(articles 11/12、review-introduction は既存差分)を維持。
- 実装済み(手順 4: RenderContext 導入、LaTeX 先頭の一段)
  - `ReVIEW::AST::RenderContext` を新設(AST 契約側所有の値オブジェクト)。chapter の number / id / 型分類(:chapter/:appendix/:part/:predef)/ imagedir / basedir / config を renderer 構築時に一度だけ捕捉し、live な Book/Chapter 参照は保持しない。番号整形は持たず、`(chapter_number, chapter_type)` を露出して `TextFormatter#format_chapter_number_short/full` に委ねる(データは所有、整形サービスは再利用)。分類は catalog 参照のみで I18n 非依存なので、`I18n.setup` 前に構築しても安全。
  - 「chapter → 型分類」の正準を `RenderContext.chapter_type` に集約し、`ReferenceResolver#chapter_type` は委譲(クロス章参照と現在章が同一分類)。
  - `Renderer::Base#initialize` が `render_context` を構築・公開。LaTeX renderer と latex/inline_element_handler・latex/inline_context を全面的に render_context 経由へ:`@chapter.number/id`、`is_a?(ReVIEW::Book::Part)`、`chapter.format_number(false)` の読みを撤去。InlineContext からは `chapter:`/`book:` 引数を削除(Book 依存断ち)。
  - LaTeX 経路に残る `@chapter` はサービス渡し(`SecCounter.new`、埋め込み `Compiler.for_chapter`)のみで、本体スカラーデータの直接読みはゼロ。
  - 検証: DVI syntax-book 6/6・FirstStep articles 12/12 一致、全テスト緑、rubocop クリーン。
- 実装済み(手順 4: HTML の body/inline 経路)
  - RenderContext に `bib_file` / `htmlversion` を追加。html/inline_context・inline_element_handler・html_renderer の本体データ読み(`@ctx.chapter.id`、`@ctx.book.htmlversion`、`@book.basedir`、`book.bib_file`)を render_context 経由へ。InlineContext から `chapter:`/`book:` 引数を削除。
  - html/inline_context の `chapter_number`/`chapter_title`(唯一の `book.chapter_index` 読み)は定義のみで未使用の dead code だったため削除。これで inline 経路のクロス章 book 依存が消えた。
  - `chapter_present?` は `chapter_type` の nil 判定で導出(present な章は必ず非 nil 型に分類される)。
  - 残る HTML の `@chapter` 読みは SecCounter へのサービス渡しと、`post_process`(フルHTML: 現在章タイトル・`next/prev_chapter` ナビ)のみ。後者は比較スイート(render_body)の対象外で byte-identity 保証がないため別増分に分離。
  - 検証: HTML/IDGXML sweep がベースラインと不変(HTML は元々 rendered-equivalent、IDGXML syntax-book 6/6)、DVI 6/6、全テスト緑。
- 実装済み(手順 4: IDGXML)
  - idgxml_renderer の `@chapter.number`(sect id)5 箇所と `@book.imagedir` 2 箇所を render_context 経由へ。InlineContext から `chapter:`/`book:` を削除。
  - idgxml/inline_context の `get_chap`(chapter.number/is_a?(Part)/format_number 読み)と `bibpaper_number`(chapter.bibpaper 読み)はいずれも定義のみで未使用の dead code だったため削除。IDGXML は現状 get_chap 経由の章プレフィックスを出しておらず(sweep 6/6 で確認)、削除しても出力不変。
  - 上記に伴い dead になった `TextFormatter#format_part_short`(chapter を引数に取る leaky API、唯一の呼び出し元が get_chap)と専用テストも削除。
  - 残る IDGXML の `@chapter` はサービス渡し(SecCounter・埋め込み Compiler)のみ。
  - 検証: IDGXML sweep 不変(syntax-book 6/6)、DVI 6/6、全テスト緑。
- 実装済み(手順 4: plaintext / TOP)
  - plaintext_renderer の `headline_prefix`(`@chapter`/`@chapter.number`)と `over_secnolevel?` の未使用デフォルト `@chapter`、top_renderer の `generate_headline_prefix`(`@chapter.nil?`/`@chapter.number`)および各所の `unless @chapter` を render_context 経由へ。両 renderer とも本体データの直接読みはゼロに(残りは comment のみ)。
  - 検証: 全テスト緑、rubocop クリーン。
- 実装済み(手順 4: 番号整形の compile/render 重複解消)
  - 章番号整形を AST 中立の `ReVIEW::AST::ChapterNumberFormatter`(`full`/`short`/`definition_prefix`)へ集約。`TextFormatter#format_chapter_number_full/short` は委譲、indexer の `definition_chapter_number` は `is_a?(ReVIEW::Book::Part)` と `Chapter#format_number` と `I18n.t('part_short')` の直呼びをやめ、`RenderContext.chapter_type` で分類 + `ChapterNumberFormatter.definition_prefix` で整形。分類も整形も各1箇所に集約された。Part の caption prefix が part_short、参照 short が番号、という差は `definition_prefix` に明示保持。renderer→AST の依存方向で層は正しい。
  - 検証: DVI 6/6、IDGXML 6/6、全テスト緑、rubocop クリーン。
- 実現不可と判断(手順 4: HTML post_process の Book 切り離し)
  - `post_process` のフルページ経路は同梱テンプレート `templates/web/html/layout-html5.html.erb` に `binding` を渡す。テンプレートが `@next.id`/`@prev.id`(隣接章 Chapter)と `@book.config` を直接読むため、renderer は `@book` と前後章 Chapter を露出し続ける契約がある。テンプレートは gem/プロジェクト資産で AST 側では変更対象外。よって post_process の Book 非依存化は不可(値オブジェクト化するとテンプレートが壊れる)。`@chapter.title`/`next_chapter`/`prev_chapter` の読みはこの契約の一部として残す。
- 実装済み(手順 4: 章タイトルの AST 所有化 = 仕様確定)
  - 章タイトルの権威を本体 `ReVIEW::Book::BookUnit#title`(Re:VIEW の `=` 見出ししか解釈しない)から AST へ移した。仕様:「章タイトル = 最初の見出し(ドキュメント順・レベル不問)の生キャプション」。生キャプション = `=+`・先頭 `[tag]`・先頭 `{label}` を除去し `.strip` した生文字列で、インライン記法(`@<b>{…}`)は生のまま保持する。
  - 実装: `HeadlineNode#raw_caption`(compiler が `HeadlineParser` の生キャプションから設定、シリアライズ対応)を追加。Indexer が最初の見出しの raw_caption で `chapter.title` を権威的に設定(従来の「空のときだけ」ガードを撤去)。従来の parsed キャプション抽出(`extract_text_from_caption` 等)は撤去。
  - parity: 実コーパス18章で `BookUnit#title` と byte 一致を実測(生 vs パース済みの差はインライン記法入りタイトルで出るが、生キャプション採用で解消)。`test/ast/test_chapter_title.rb` が tag/label 除去・生記法保持・任意レベル・見出しなし・BookUnit との一致を pin。
  - 背景: Markdown は「唯一の情報源はソースファイル」という点で Re:VIEW と同格だが、本体のタイトル抽出が Re:VIEW 専用なので従来 AST 側で `.md` だけ特別扱いしていた。タイトルを AST 所有にしたことで、この非対称の根(BookUnit#title 依存)を解消。Markdown コンパイラ自体は未実装のため実配線は Re:VIEW のみ(MarkdownCompiler 整備時に同じ経路で乗る)。
  - 検証: DVI 6/6、IDGXML 6/6、全テスト緑、rubocop クリーン。
- 実装済み(手順 4: compiler 入口の契約化 = 縮約形)
  - `ReVIEW::AST::CompileInput` を導入。compiler が Chapter から読んでいたものを2種に仕分けた:純データ(`source`/`basename`)と、明示サービスハンドル(`chapter` とその `book`。ImageFinder のファイル走査とクロス章参照解決という環境依存パスだけが使う)。`compile_to_ast` は CompileInput を受ける(後方互換で Chapter も受け、内部で `from_chapter` ラップ)。source/basename は input から読み、`@chapter` は resolution パス専用の service handle として残す(source-only 入力では nil)。
  - 新capability: `CompileInput.from_source(src, basename:)` で Book なしにソース文字列→AST を生成可能(resolution はスキップ)。テストや「ソースはあるが Book が無い」消費者向け。RenderContext(出力側)と対になる入力契約。
  - Book 非依存化は目指していない(実現不可)。狙いは god-object の implicit reach-through 排除と入口契約の明示化。ImagePathProcessor / ReferenceResolver は gem の ImageFinder / 他章再コンパイルに live な Chapter を要するため named service として明示的に受ける。
  - 検証: DVI 6/6、IDGXML 6/6、全テスト緑(`test/ast/test_compile_input.rb` が source-only と from_chapter 等価性を pin)、rubocop クリーン。
- 実装済み(手順 6: EPUB maker 移植)
  - `ReVIEW::AST::Command::EPUBMaker < ReVIEW::EPUBMaker` を追加(`bin/review-ast-epubmaker`、gemspec 登録)。EPUB 梱包(OPF/NCX/nav、mimetype、container、TOC、stylesheet・画像コピー、mermaid 生成、zip)はレガシーを丸ごと再利用し、章 XHTML 生成だけを AST HtmlRenderer に差し替え。
  - seam: 基底 EPUBMaker が `@converter` を使うのは build_chap(1 章 → 1 XHTML)だけなので、build_chap を override して `@converter` を AST アダプタ(`AstHtmlConverter#convert(file, output)`)へ差し替えるのみ。build_body のループごとコピー(既存 idgxml/text maker の流儀)は踏襲せず、梱包機構を最大限再利用する最小構成にした。フルページ描画は同じ layout テンプレート(`config.maker='epubmaker'` なので web でなく `html/layout*.erb`)を使うため出力が一致。
  - 実測: samples/syntax-book で legacy `review-epubmaker` と生成 EPUB を比較。ファイル一覧完全一致。OPF は生成時刻(dcterms:modified)と乱数 UUID のみ差(非決定要素)。parts/appendix/bib/TOC/stylesheet/画像は byte 一致。差は ch01-03.xhtml のみで、これは HtmlRenderer 既知の rendered-equivalent 差(ブロック間空白・`<dl>` の改行有無)であり EPUB maker 由来ではない。
  - 既知の限界: HtmlRenderer は `//graph`(img_graph)未対応。graph を含む本の EPUB では画像参照が不足しうる(HTML レンダラ側の別課題)。
- 積み残し(規模順)
  - 手順 5(config キーの契約化): 項目 6 と同時(大)。

---

## 9. レンダラのオラクル比較と、形式をまたぐ契約の一本化

`lib/review/renderer/` 全体のレビューを起点とする項目。指摘の大半は重複整理だったが、
調査の過程で「同じ判断が複数箇所に複製され、片方だけ正しい」型の実バグが 9 件出た。
根因は次の一点に集約される。

検証の空白: LaTeX / HTML / IDGXML には比較ハーネス(`test/support/review/test/*_comparator.rb`)が
あるのに、plaintext と TOP には無かった。既存の round-trip / render-identity テストは
AST 対 AST の自己整合性であってオラクル比較ではないため、この 2 形式は誰にも見られないまま
レガシービルダーから乖離していた。

- 実装済み(手順 1: plaintext/TOP のオラクル比較器と、それが検出した乖離の修正)
  - `ReVIEW::Test::TextComparator`(`test/support/review/test/text_comparator.rb`)を追加。
    既存 3 形式と同じ流儀で、`format:`(`:plaintext` / `:top`)を受けて legacy builder と
    AST renderer の両方を回す。オラクルは `builder.result`(`check_printendnotes` と
    `solve_nest` を含む。TEXTMaker が書き出すのはこれ)。
  - 検出・修正した乖離(いずれもテキスト出力から情報が失われていたもの):
    - 節番号が全欠落。`headline_prefix` が章より下のレベルで空文字を返しており、コードにも
      「section counter needs proper implementation」と書かれたままだった。両レンダラを
      `ReVIEW::SecCounter` 駆動にし、番号と secnolevel の挙動をビルダーに揃えた。
    - `[nonum]`/`[notoc]`/`[nodisp]` が通常見出し扱い。採番されるうえカウンタも進めるため、
      以降の節番号が全てずれていた。ビルダーは `nonum_begin`/`notoc_begin` へ振り分けて
      `headline_prefix` を呼ばない(= 非採番かつカウンタ不変)。`nodisp` は出力なし。
    - TOP が `//firstlinenum` を無視(開始行 1 固定)。
    - TOP の画像マーカーが束縛済みファイルパスでなく id を出力し、metric も未パースで
      他ターゲット用の値が混入していた。未束縛時は warn してブロック本体へフォールバック。
    - TOP が `caption_position` を完全に無視(既定 image=bottom に反して常に上)。
    - TOP のコラムがブロックマーカーと `■` 前置ごと消失し、本文と区別できなかった。
      ほかに定義語の `★` 欠落、`//indepimage` の `■id■` 表記、独自の `連番付きリスト` マーカー。
    - plaintext が `//listnum` キャプションから番号を欠落(ビルダーは `list_header` を通す)。
    - TOP に `@logger` が無く、`Loggable#warn` が例外になる状態だった。
  - テスト `test/ast/test_text_renderer_semantics.rb`。バイト一致ではなく「出力が担うべき情報」を
    検証する(後述の許容差があるため)。
- 実装済み(手順 2: 重複 API の統合と dead code の一掃)
  - `TextFormatter#format_reference_text`(公開 1 + private 7、約 118 行)を削除。「装飾なし版」と
    説明されていたが、全 11 参照型で `format_reference` と出力が同一だった(背後の private 対が
    共有ではなくコピーだったため)。呼び出し 4 箇所はすべて HTML の inline handler。
    `_text` 側のテストが参照整形の唯一のカバレッジだったので、削除せず `format_reference` に付け替えた。
  - dead code 削除: latex `@ast_indexer`/`@list_structure_normalizer`、idgxml `@ast_indexer`/
    `parse_tsize_target`/`over_secnolevel?`、plaintext `@blank_seen`/`over_secnolevel?`、
    top `@minicolumn_stack`(push/pop のみで読み出しなし)/`@rendering_context`、
    TextFormatter `numeric_string?`・未使用の `chapter` 引数とリーダー・`html_css_class` 引数。
  - レビューの誤指摘 2 件は残した: `@ast_compiler`(latex/idgxml)は memoize されて入れ子コンパイルに
    使われており dead ではない。plaintext の `@logger` は `Loggable#warn` が必要とする
    (TOP でこれが無いために手順 1 のバグが起きていた)。
- 実装済み(手順 3: 状態逆流の解消と、共通化できる範囲の見極め)
  - handler が renderer の ivar を `handler → ctx → proxy → renderer` と 3 クラス貫通で書き換えていた
    2 つの状態(LaTeX の遅延 `\footnotetext` id、IDGXML のインライン数式カウンタ)を、双方が既に
    共有している inline context の所有に移した。`InlineRenderProxy` から形式固有メソッドと
    `respond_to?` ガードが消え、本来のアクセス制限に戻った。
  - 3 形式で 41 箇所に逐語コピーされていた resolved ガード(4 行)を `ResolvedReference` モジュールの
    `resolved_reference_node(node)` に集約。IDGXML の寛容版 3 箇所(raise せず content へフォールバック)は
    意図的な差なので温存。
  - plaintext の `visit_reference` が `ReferenceNode#content`(= 参照自身の id)を返しており、
    `@<img>{img1}` が `図1.1` でなく `img1` と出力されていた。TextFormatter 経由の整形に修正。
  - plaintext/top の共通基底は見送った。同名 36 メソッドのうち完全同一は 5 件のみで、TOP はほぼ全ブロックを
    `◆→開始:…←◆` で囲む形式、plaintext には対応物がない。残り 31 件は装飾差ではなく実質的な差であり、
    テンプレートメソッド基底にすると「実装が 1 つしかないフック」が並ぶ。実際に同一だった 5 件だけを
    `TextRendererCommon` に切り出した(`visit_block_printendnotes` はコメントまで逐語同一だった)。
- 実装済み(手順 4: config を読む述語の一本化)
  - `caption_top?` が 3 実装。legacy は「`'bottom'` でなければ top」(未設定も top)で、LaTeX の実装だけが
    一致。Base と IDGXML は `== 'top'` を判定していたため、caption_position が無い設定では全キャプションが
    下に落ちていた。Base を legacy 準拠にし override を削除。
  - `over_secnolevel?` が 3 実装。legacy は章を含むドット文字列の階層数を数えるが、AST が渡すのは章を含まない
    配列 `headline_number`。latex/idgxml の実装は文字列前提のままで、`[1, 2].to_s.split('.').size` は 1 に
    なるため、どの深さの見出しも「secnolevel 内」と判定していた。配列を正しく扱う HTML の規則を
    `SectionNumbering` モジュールへ集約。
  - 述語だけでは足りなかった: IDGXML の `@<hd>`/`@<secref>` はそもそも述語を通らず、
    `TextFormatter#format_headline_reference` が深さに関わらず番号を付けていた(ビルダーは secnolevel を
    超えると `hd_quote_without_number` に切り替える)。formatter 側にも secnolevel を適用。
  - レンダラのコンストラクタから `I18n.setup` を撤去。生成のたびにグローバルを書き換えており、最後に
    生成されたレンダラがロケールを決める状態だった。legacy はビルダーではなく maker 側で設定しており、
    AST の maker はその経路を継承している(`review-ast-compile` は自前で設定済み)。
- 検証: 全テスト緑(1106 tests)、rubocop クリーン、syntax-book は DVI 6/6 一致・IDGXML 6/6 バイト一致。
  `I18n.setup` 撤去は実ビルドでも確認(review-ast-textmaker が `■H1■第1章　章見出し`、
  review-ast-idgxmlmaker が `第1章　章見出し` を出力)。
  構文スイープ(27 構文)での内容差は TOP 12 → 2、plaintext 5 → 1 に減少。残ったのはいずれも
  下記「許容している残差」に該当するもの(TOP は入れ子リストと表の罫線幅、plaintext は入れ子リスト)で、
  未修正の乖離は無い。なお同スイープの `//bibpaper` は bib ファイルを要するためハーネス側の制約で
  エラーになり、集計から除いている。

- 実装済み(手順 5: コーパス全体での残差の解消 / JM-000089)
  - 手順 1 は構文スイープ(単発の構文断片)で検証していたが、samples の実文書でコーパス全章を
    走らせると差が残っていた。断片では出ない組み合わせ(章をまたぐ参照、`chapterlink`、
    複数行段落)が原因。命令単位で 13 件を修正。
    - TOP のみ: `@<kw>` の `★…☆（…）`、`@<uchar>` の文字化、`@<icon>` のパス、`//noindent` の
      DTP 連絡、`//texequation` の採番キャプション、`//olnum` の開始番号、`//emtable` キャプションの
      余分な `■`、`//imgtable` の画像行。最後の 2 つは `visit_block_imgtable`/`visit_block_emtable` が
      dead code だったことによる(TableNode は全て `visit_table` にディスパッチされる)。
    - 両形式: `//endnote` の二重出力(定義位置と `//printendnotes` の両方。LaTeX/HTML には
      既にガードがあった)、`@<title>`/`@<sec>`/`@<sectitle>` が `@<chapref>`/`@<hd>` の形に
      素通ししていた件、`chapterlink` の未対応。
    - plaintext のみ: `@<del>` が削除文字列を残していた(ビルダーは落とす)、`@<bib>` の末尾空白。
  - 段落の行畳み込みは「同じ判断の複製」型: 段落内の改行はソースの整形であって内容ではなく、
    ビルダーは `split_paragraph`/`join_lines_to_paragraph` で畳む。LaTeX にのみ正しい実装があり、
    plaintext は `join_lines_by_lang` を無視する版、TOP は畳み込み自体が無かった。
    `Base#join_paragraph_lines` に一本化。
  - 検証: 全テスト緑(1223 tests)、rubocop クリーン。コーパス(syntax-book 6 章 + debug-book 4 章)の
    実質差は、上記「許容している残差」に該当するもののみになった。

### 意図的に許容している残差(plaintext / TOP)

この 2 形式はバイト一致を目標にしない(方針決定済み)。意味的に正しければよく、次の差は許容する。
乖離として「修正」しないこと。

- 入れ子リストのインデント: AST は入れ子を字下げで保持し、ビルダーは平坦化して空行で区切る。
  AST の方が情報を保っているため、こちらを採る。
- 空行の位置: ビルダーは `blank`/`@blank_seen` による連続空行の抑制を持つが、AST は再現していない。
- 表の罫線幅: 区切り行のダッシュ数と末尾タブの有無。
- TOP の `@<em>`: 許容差ではなく Re:VIEW 本体側のバグだった。TOPBuilder は装飾系 16 命令のうち
  15 個を上書きしており、`@<em>` だけが PLAINTEXTBuilder の素通しに落ちていた。本体に
  `alias_method :inline_em, :inline_i` を追加(ブランチ `fix-top-inline-em`)。AST 側は変更不要で、
  取り込み後は `▲…☆` で一致する。

上記のため `test_text_renderer_semantics.rb` はバイト一致ではなく情報の有無を検証している。
LaTeX / HTML / IDGXML の目標(DVI 一致 / rendered-equivalence / byte 一致)は従来どおり変更なし。

### 見送り(理由付き)

いずれも挙動を変えない整理であり、レンダラは現状オラクルと一致しているため、利益のない変更で
退行リスクを負わない判断とした。

- HTML `post_process` の WebPageAssembler 抽出: 「webmaker を育てるなら投資効率が良い」という条件付きの
  提案。webmaker 手順 4-5(progressive enhancement CSS、build-time MathML、静的検索)に着手する際、
  その作業の一部として行う方が、必要な形が分かってからになる。
- verbatim 重複ペアの統合(html `format_emlistnum_content` ≡ `format_listnum_content`、idgxml の
  quotedlist 系、top の caption 3 つ子): 安全だが得られるのは行数削減のみ。
- 巨大メソッドの分割(latex `visit_table` 109 行、top `render_inline_element` 64 行 29 分岐)。
- ただし idgxml `visit_graph` が描画メソッド内で `system("dot ...")` と Tempfile I/O を行っている点は
  設計として筋が悪く、いつか ImgGraph 側(既に遅延生成を持つ)へ寄せる価値がある。挙動に触れるため、
  単独で検証する変更として切り出すこと。

### 検証の拡張と、PBT が検出した未修正の乖離(2026-07)

CI が検証する範囲を広げた。いずれもリポジトリ内の素材か生成物で駆動し、再配布できない文書に依存しない。

- `test/ast/test_corpus_builder_parity.rb`: catalog が宣言する全章(syntax-book 6・debug-book 4)を IDGXML(byte)・HTML(描画等価)・LaTeX(テキスト篩)でビルダーと比較する。従来は各形式2章の抜き取りだった。約1秒。
- `test/ast/test_command_parity_coverage.rb`: `BLOCK_COMMAND_TABLE`(61)と `DEFAULT_INLINE_HANDLERS`(26)を実行時に列挙し、各命令に断片か理由付き除外があることを強制する。命令が増えるとカバレッジを用意するまで落ちる。
- `.github/workflows/nightly.yml`: PBT を PR より深く(既定 500 seed)、html と idgxml の両モードでビルダーと比較する。PR 側の PBT テストは AST 対 AST の自己整合性なので、オラクル比較はここが担う。

この拡張で見つけて修正したもの: HTML レンダラに `//read`・`//talk`・`//doorquote`・`//point`・`//bpo`・`@<imgref>` のハンドラが無かった件(ビルダーは実装済み)、`//doorquote` の内容が段落分割されていなかった件、IDGXML の `olnum` が源泉番号を使っていた件(正しくは 1 始まりの連番で、`//olnum[N]` のみが起点を変える)、入れ子リスト後に `olnum` がリセットされない件、`@<hd>` の見出しキャプションが未エスケープで XML 不正になっていた件。
`olnum` の 2 件については `test_idgxml_renderer.rb` の期待値自体が誤っており(ビルダーの実出力と不一致)、ビルダーに合わせて訂正した。

未修正(nightly が現に落ちる)。いずれも `//table` のセル分割の問題で、原因は Re:VIEW 本体側にあり、
レンダラの出力のほうが正しい。本体へ報告し、取り込まれたらこの 2 件は消える。AST 側の修正は不要。

- 先頭セルがインライン展開後に空になると、以降のセルが 1 列左へずれる(nightly html、seed 167)。
  `ReVIEW::Builder#parse_table_rows` はインライン展開済みの行を `line.strip.split` で分割するため、
  空になった先頭セルの区切りタブを `strip` が食い、`adjust_n_cols` が代わりに末尾へ空セルを足す。
  形式に依らず、その形式で空になるインラインが先頭セルにあれば起きる。

  ```
  //table[t1][cap]{
  @<raw>{|latex|X}	B
  ------------
  C	D
  //}
  ```

  latex は `\reviewth{X} & \reviewth{B}` と 2 列に組むが、html は
  `<tr><th>B</th><th></th></tr>` になり B が 1 列目へ移る。
  逆に `@<raw>{|html|X}` を先頭に置けば latex 側が同じずれ方をする。

- 桁の揃わない表で、IDGXML の宣言とセル数が食い違う(nightly idgxml、seed 14 ほか計 18)。
  `IDGXMLBuilder#parse_table_rows` は基底と違って短い行を詰めない。`aid:tcols` は最大列数になる
  一方、短い行はそのセル数のまま出るため、2 行 3 列の宣言に 5 セルという出力になり、行×列の
  セルを期待する InDesign 側でずれる。`tableopt` 指定時に起きる。

  ```
  //table[t2][cap]{
  A	B
  ------------
  C	D	E
  //}
  ```

---

## 10. MarkdownCompiler の取り込み

upstream 作業ブランチ(kmuto/review の `ast-renderer`。以下「元ブランチ」)には、Markdown を入力とするコンパイラ一式が実装済みである。
本項目は、それを現在の review-ast の契約(CompileInput、SourceLocation、EmbedNode、lowering パイプライン)に合わせて取り込む計画を記す。

### 現状と元ブランチの実測

review-ast 側には受け口だけが残っている。
`Compiler.for_chapter` は `.md` 拡張子で `markdown_compiler` を require する分岐を持ち(実体が存在しないため現状は LoadError)、`review-ast-compile -t markdown` も同様に `markdown_renderer` へのダングリング参照を持つ。
`MarkdownHtmlNode` は既に削除済みである。

元ブランチの構成(行数は実測):

- `markdown_compiler.rb`(111 行): 外部 gem **markly**(cmark-gfm の C 拡張バインディング)でパースし、`markdown_adapter.rb`(904 行)が markly の木を Re:VIEW AST へ変換する。
  生成されるノードは既存ノード型のみで、新しいノード型は要らない。
  `InlineTokenizer` と `ReferenceResolver` は Re:VIEW 側と共有する(Markdown 中の `@<img>{id}` 等の参照記法をそのまま解釈する)。
  なお本項目では markly を採らず、pure Ruby の **red_quilt** に差し替える(後述)。
- 方言は CommonMark + GFM(strikethrough、table、autolink、脚注)。
  Re:VIEW 拡張として、コラム(`### [column]` 開始、`<!-- /column -->` または見出しレベルで終了)、属性ブロック(`{#id caption="..."}`)、Re:VIEW 参照記法を持つ。
  `//cmd` 等の特殊ブロックや一部インライン記法は意図的に非対応(全機能が要る章は `.re` で書く)。
- `markdown_renderer.rb`(1,039 行): 逆方向(AST → Markdown)のレンダラ。
  `Renderer::Base` の dispatch 契約に準拠しており移植は容易。
- `diff/markdown.rb`(120 行): テスト専用の正規化比較器。
- テスト 7 ファイルと 2 系統のコーパス。
  `samples/md-syntax-book`(`.md` コーパス)と、`.re` から生成したゴールデン `.md`(Re:VIEW→Markdown 方向のオラクル)。
  なお元ブランチの md-syntax-book には同名の `.re` が併存していたが、移植後に削除した。
  `catalog.yml` が `.md` を指すため book モデルは `.re` を章として認識せず、どのテストからも使われていなかった。
  「Markdown→AST 方向のオラクル」という当初の役割も果たせない:
  両者は機械的な対訳ではなく各記法で自然に書いた別文書であり(`.md` の段落が `.re` では `//lead{}`、`#@#` コメントは `.re` のみ)、
  AST でも描画結果でも突き合わせが成立しない。
  実害もあり、章名 `ch01` が `.md` に解決される一方で隣に `.re` があるため、
  コーパス比較を書いた際に「レガシーが Markdown を Re:VIEW として読んだ出力」と比較する誤りを誘発した。
- モンキーパッチ、旧 `core_ext`、レガシー Index 系への依存はない。

### 設計(review-ast の契約への適合)

取り込みは「移植 + 4 点の適合」で構成する。

- **パイプラインへの接ぎ方**:
  元ブランチの `MarkdownCompiler` は `compile_to_ast` を丸ごと override し、参照解決の呼び出しを親と重複実装している。
  review-ast では「surface tree の構築だけを差し替えるテンプレートメソッド」として接ぐ。
  すなわち親 `Compiler` を「surface tree 構築(フック)→ lowering パス群 → 参照解決・画像パス解決」に整理し、`MarkdownCompiler` はフックだけを override する。
  これにより directive lowering(Markdown は `DirectiveNode` を生まないので実質 no-op)、リスト項目番号付与、auto-id、`definition_number` の刻印、`ChapterIndexRegistry`、`ImagePathProcessor` がすべて自動で共有され、Markdown 章も `.re` 章と同じ core tree 契約(項目 3、ast-semantics 2.1)を満たす。
- **入力契約**:
  `compile_to_ast(chapter)` 前提のコードを `CompileInput` 契約(`input.source` / `input.basename` / `input.book`、source-only 入力可)へ書き換える。
  元実装が chapter から読んでいるのはこの 3 要素だけであり、機械的な置換で済む。
- **位置情報**:
  `SnapshotLocation.new(basename, line)`(review-ast には存在しない)を `SourceLocation` へ置換する。
  red_quilt 0.9.0 は行・列とも 1-based で、ブロックの span がマーカーを含む(`# 見出し` が `#` から始まる)ため、
  `source_location` の `start_line` / `start_column` をそのまま `SourceLocation` に渡せる。
  ただしインライン要素は `source_location` が nil を返す(red_quilt が `track_source: false` で走らせる経路がある)。
  元実装のフォールバックは「行 1」だが、それでは誤った位置を持つノードができるので、
  移植では囲んでいるブロックの位置を継承する。
- **MarkdownHtmlNode は復活させない**(先行検討どおり)。
  元実装でもこのノードは adapter 内の一時オブジェクトで、最終 AST には残らない(HTML ブロックは `EmbedNode` になり、`<!-- /column -->` はコラム閉じ判定にだけ使われる)。
  移植では、コラム終了コメント判定(正規表現 1 本)を adapter のローカルヘルパにし、生 HTML は `EmbedNode(embed_type: :block, target_builders: ['html'])` とする。
  元ブランチの `embed_type: :html` は採らない。
  レンダラが知らない embed_type を増やさず、既存の `targeted_for?` 機構だけで「HTML 出力にのみ現れる」意味論を表現するためである。
  インライン HTML(元実装はテキスト化の暫定)は、将来 `embed_type: :inline, target_builders: ['html']` へ寄せる。
- **依存**:
  パーサは markly ではなく **red_quilt** を使い、gemspec の実依存に加える
  (元実装の「soft require + 実行時 CompileError」はやめる。条件分岐を持ち続ける理由がない)。
  markly は cmark-gfm への C 拡張バインディングだが、red_quilt は pure Ruby で外部依存を持たない。
  `required_ruby_version` は 0.9.0 で `>= 3.1` に下げられており、review-ast の下限を引き上げる必要はない。
  `diff-lcs` は既存依存。

  パースの呼び出しは次の形になる(表・打消し線・HTML ブロックは既定で有効、脚注と拡張 autolink は opt-in)。

  ```ruby
  RedQuilt.parse(source, footnotes: true, extended_autolinks: true)
  ```

- **ノード型の対応**:
  markly と red_quilt で型名が異なるため、adapter の分岐をリネームする(不足している型はない)。
  `:header`→`:heading`、`:hrule`→`:thematic_break`、`:code`→`:code_span`、`:emph`→`:emphasis`、
  `:linebreak`→`:hardbreak`、`:table_header`→`:table_row`(`header?` で判別)。
  他は同名。
  ノード属性は `NodeRef` の公開アクセサ(`heading_level` / `list_ordered?` / `list_start` /
  `list_delimiter` / `link_destination` / `link_title` / `footnote_label` / `footnote_number` /
  `header?` / `info`)から読む。型が合わない場合は nil が返る。

### 移行手順

0. (完了)パーサ側の前提を整える。
   red_quilt に必要な変更を `doc/red-quilt-requirements.ja.md` にまとめ、0.9.0 で対応済み。
   多バイト文字で行番号がずれるバグ(行頭テーブルを文字オフセットで作り、バイトとして引いていた)の修正、
   列の 1-based 化、ブロック span をマーカー込みにする修正(フェンスコードブロックは行番号自体が誤っていた)、
   ノード属性アクセサの `NodeRef` への公開。
   `required_ruby_version` も `>= 3.1` に下げられた。
1. red_quilt を依存に追加し、`markdown_compiler.rb` と `markdown_adapter.rb` を移植する(SourceLocation 化、CompileInput 化、EmbedNode 化、コラム判定のローカル化、ノード型のリネームを含む)。
   単体テスト(`test_markdown_compiler.rb`、`test_markdown_adapter.rb`、`test_markdown_column.rb`)を同時に移植し、AST 構造のオラクルを先に立てる。
2. 親 `Compiler` に surface-tree 構築フックを抽出し、`MarkdownCompiler` をフック override に縮める(参照解決の重複実装を削除)。
   `.md` 章に `definition_number`、registry、`image_path` が刻印されることをテストで確認する。
3. 参照解決の統合テスト(`test_markdown_references_integration.rb`)と `samples/md-syntax-book` 並行コーパスを移植し、`.md` 章を既存 5 レンダラで描画できることを確認する。
   ダングリングだった `.md` 経路(`review-ast-compile` の各ターゲット)がここで機能し始める。
4. `markdown_renderer.rb`(AST → Markdown)と `diff/markdown.rb`、fixtures テストを移植する。
   ゴールデン `.md` はコピーせず review-ast 側で再生成する(バックアップファイル `*~` は持ち込まない)。
5. (完了)文書整備。
   `doc/ast_markdown.ja.md` を移植し、実装と合っていなかった記述を直した:
   パーサ名(markly → red_quilt)、`MarkdownHtmlNode`(削除済み)、
   `DefinitionListNode`/`DefinitionItemNode`(実体は `ListNode(list_type: :dl)` /
   `ListItemNode(item_type: :dt/:dd)`)、生 HTML の表記(`EmbedNode(:html)` は誤り)。
   CLI の記述にも誤りがあり実測で訂正した(`--target=ast` は存在せず、
   `review-ast-dump2re` の入力は `.md` ではなくダンプ JSON)。
   AST → Markdown 方向は未移植なので、冒頭に実装状況の節を置いて区別した。
   ast-semantics(英日)には 2.4「もう一つの入力言語: Markdown」を追加し、
   `EmbedNode` の「将来 Markdown 対応時の想定」という記述を現実に更新した。
   旧文書整備の項目:
   元ブランチの `doc/ast_markdown.ja.md` を移植し、実装との既知の齟齬(`DefinitionListNode` 表記。実体は `ListNode(list_type: :dl)`)を直す。
   ast-semantics の `EmbedNode` の「Markdown 対応時の想定」記述を現実に更新し、Markdown 入力の節を追加する(項目 6 と合流)。

### 検証

- 移植した単体テスト(AST 構造オラクル)と統合テスト(参照解決 + HTML 描画)が緑であること。
- round-trip: `.md` からコンパイルした core tree のシリアライズがバイト同一で往復すること。
  新ノード型ゼロなので `ast_format` は不変であり、既存の round-trip ハーネスに md コーパスを足すだけでよい。
- render-identity: `.md` 章について「新規コンパイル描画 == ダンプ読み戻し描画」が 5 形式で一致すること。
- Re:VIEW→Markdown 方向はゴールデン比較(`Diff::Markdown`)。
  ゴールデンの再生成手順をリポジトリに残す。
- `.re` 経路の全比較スイート(DVI、IDGXML byte、HTML)が手順 2 のフック抽出の前後で緑であり続けること(既存経路の挙動保存が最優先)。

### 範囲外・要確認

- **book モデルの `.md` 章の扱い**(実測済み。当初の懸念は解消):
  `catalog.yml` の `CHAPS` に `ch02.md` を並べたところ、review gem 5.11 の `Book` は
  `.re` と同じように章として列挙した(`chapters` に `["ch02", "ch02.md"]` が入る)。
  したがって maker 統合を後続に回す必要はなく、`Compiler.for_chapter` の `.md` 分岐が
  機能し始めた時点で、maker 経由のビルドもそのまま通る見込みである。
- `Diff::Markdown` の正規化オプション 5 種は、`Diff::Latex` と同様のコンフィグ過剰(lib/diff レビューでの指摘と同種)であり、移植時に実使用分へ縮めてよい。
- Markdown 方言の拡張(定義リストの入力対応、インライン HTML の EmbedNode 化)は、取り込み完了後の別項目とする。

## 11. //tsize の Vivliostyle への翻訳(アイデア、未実施)

### 動機

`//tsize` は LaTeX では列指定、IDGXML では mm 幅になるが、HTML 系では捨てられ、
Vivliostyle の表はすべて自動レイアウトになる。固定幅列(LaTeX の p 列)で
折り返しを制御したい表が CSS 組版で再現できない。

### 設計

情報は AST まで来ている(`TableNode#tsize` が生値を保持し、
`TableColumnWidthParser.value_for_target` がビルダ限定指定を選別する)ので、
翻訳は二段で行う。

- HtmlRenderer は epubmaker 経由のときだけ `//tsize` の生値を
  `<table data-tsize="...">` として透過する。描画に影響しない不活性な属性で、
  プレーン HTML と webmaker はレガシー HTMLBuilder とのパリティを保つ。
- VivliostyleMaker が組版前の後処理(ImageSizeAnnotator と同型の
  TableWidthAnnotator)で data-tsize を `<colgroup>` に変換する。数値形式は mm、
  `p{長さ}` は CSS 単位のもののみ幅として拾う。全列の幅が揃うときは
  `table-layout: fixed` と合計幅も与え、「固定幅内で折り返す」p 列の挙動を
  再現する。l/c/r と罫線位置は colgroup で表現できないので扱わない。
  対象の選別は `value_for_target` をそのまま使い、`|latex|` 限定は無視、
  汎用指定と `|vivliostyle|` / `|html|` 指定を拾う。

動作する実装とテストは一度コミットしたうえで取り消してある
(ef0f0f2、revert は 8d3229b)。再開するときは revert の revert で復元できる。

### 見送りの理由と再開の条件

これまで `//tsize` は HTML 系出力に影響しなかったため、汎用の数値指定
(`//tsize[10,18,50]`)を書いている既存の本では EPUB / Vivliostyle の紙面が
変わる。導入するなら非互換の受け皿が要る:

- 既定を off(`vivliostyle: table_tsize: true` で opt-in)にする、または
- 効果を `|vivliostyle|` 明示指定に限る(汎用指定は従来どおり無視する)、または
- メジャーバージョン境界で既定 on に切り替える。

### 検証

サンプル表(syntax-book 表2.1)に汎用 tsize を付けた紙面で、列幅の反映と
固定幅内の折り返し、`|latex|` 限定指定がスキップされることを確認済み。
単体テストは TableWidthAnnotator の revert 前コミットにある。
