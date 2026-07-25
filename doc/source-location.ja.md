# ソース位置情報(行・桁)

AST の各ノードは、由来するソース上の位置を `location` に保持する。従来は行番号(lineno)だけだったが、桁(column)も記録する。

## 位置型

`ReVIEW::AST::SourceLocation`(`lib/review/ast/source_location.rb`)。

- 属性: `filename` / `lineno` / `column`。イミュータブル(`freeze`)。
- リリース版 `review` gem の `ReVIEW::SnapshotLocation` は `filename`/`lineno` のみで frozen のため桁を持てない。AST は自前のこの値オブジェクトを使う。`SnapshotLocation` の忠実な上位互換(`filename`/`lineno`/`string`/`to_s`/`snapshot` 同一インタフェース)であり、AST が従来 `SnapshotLocation` を生成していた箇所の drop-in 置換になっている。
- `column` は 1 始まりで任意(nil=不明)。`column` が nil のとき `#to_h` と `#format_for_error` はレガシー `SnapshotLocation` と byte 一致し、既存の消費者に対して挙動を変えない。
- 補助: `SourceLocation.from(location, column:)` / `#with_column(col)` / `==`・`eql?`・`hash`。

## 桁の埋め方

- ブロック・行レベル(見出し・段落・各種ブロック・コード行・キャプション等): 行頭を表す `column: 1`。`Compiler` が行単位で位置を更新する箇所(`compiler.rb`)で付与する。
- インライン要素(`@<...>{}` など): 行内の実際の桁。`InlineTokenizer` が保持する各トークンの 0 始まりオフセット(`start_pos`)を用い、`InlineProcessor#parse_inline_elements` がトークン処理中だけ `Compiler#with_temporary_location!` で位置を「桁付き」に差し替える。これにより、各インラインハンドラ(`@ast_compiler.location` を読む)が一律に桁を得る。桁 = 行の基準桁 + `start_pos`。

## シリアライズ

- `SourceLocation#to_h` は `column` が存在するときのみ `column` を含める。`json_serializer.rb` の schema に `column`(integer/null)を追加済み。
- デシリアライズ(`JSONSerializer.restore_location`)は `column` を読み、`SourceLocation` を復元する。桁は serialize→deserialize の round-trip で保存される。
- 一部のリーフノード(`TextNode`・`ReferenceNode`)は `location_to_h` を独自実装していたが、`location.to_h` へ委譲するよう修正し桁を含めるようにした。

## 範囲と既知の制限

- ブロック・行レベルの桁は行頭 `1` を既定とする。行にインデント(先頭空白)がある場合の厳密な桁は未対応(実務上の大半は列 1 始まり)。
- ネストしたインライン内容の `start_pos` は内側文字列に対する相対値のため、深い入れ子では絶対桁が近似になる。
- レンダリング出力は位置情報に依存しないため、桁の追加による出力差分はない(DVI/HTML/IDGXML スイープで確認済み)。
- テストのフィクスチャで手動構築する位置(`ReVIEW::SnapshotLocation.new(...)`)は現状維持(有効な位置であり column=nil)。必要なら機械的に `ReVIEW::AST::SourceLocation.new` へ移行可能。
