# hanmen-compare

同じ設計値から三系統(Typst / Vivliostyle / LaTeX)で全角べた組みの1ページを
組み、版面(型)の四辺・行数・字詰めを突き合わせるツール。
doc/design-hanmen.ja.md §7.3 の「一致の検証」を自動化したもの(R3)。

## 何をするか

- design.css の設計値(字詰め・行数・級数・天・ノド・用紙)を単一ソースとして読む。
- 約物も欧文も含まない「田」だけのべた組みページを、各エンジンの実際の設計ファイルで組む。
  - Typst: `templates/typst/review-book` + `default-theme`
  - Vivliostyle: `style-vivliostyle-design.css` + `style-vivliostyle.css` を vivlio-pdf で印刷
  - LaTeX: review gem の `review-jlreq` クラス(設計値をクラスオプションで渡す)
- 各 PDF の最初の満杯ページから、行数・1行の字数・版面四辺(mm)を測る。
  測定対象は「田」の行だけなので、柱・ノンブルは自然に除外される。
- 水平(字詰め・行数・版面の左右)は一致を判定し、天地(字面の上端/下端)は
  組版系ごとに1行目の置き方が違うため、情報として差分だけを出す。

## 使い方

```
rake hanmen:compare
# または
ruby tools/hanmen-compare/compare.rb
```

ツールチェーンの無いエンジンは自動でスキップする(2系統あれば比較する)。

### 生成した PDF を確認する

既定では一時ディレクトリに組んで終了時に消す。出力先を渡すと PDF と
probe のソースをそこに残し、最後にパスを表示する:

```
ruby tools/hanmen-compare/compare.rb out/
rake 'hanmen:compare[out]'

# 表示されたパスを開く（macOS なら open、Linux なら xdg-open）
open out/typst/typst.pdf out/vivlio/vivliostyle.pdf out/latex/probe.pdf
```

## 必要なもの

- `pdftotext`(poppler) — 測定に必須
- Typst: `typst`
- LaTeX: `uplatex` と `dvipdfmx`、および review gem(review-jlreq.cls を持つ)
- Vivliostyle: [vivlio-pdf](https://github.com/takahashim/vivlio-pdf) とローカルの Chrome/Chromium

vivlio-pdf は review-ast の Gemfile には無い任意依存なので、そのままだと
Vivliostyle はスキップされる。含めるには vivlio-pdf を読み込めるようにして走らせる:

```
# 例: review と vivlio-pdf を持つ Gemfile を作って
bundle exec ruby /path/to/review-ast/tools/hanmen-compare/compare.rb
```

## LaTeX を強制オプションで組む理由

review-ast の jlreq 設定は line_length / number_of_lines / 余白を固定していない
(jlreq が自動で型を組む)。同じ設計を比べるため、このツールは設計値をクラス
オプションとして渡す。ここで一致するのは「設計そのもの」であって、既定の jlreq
設定がそれを再現するかは別の配線問題である(§7.3)。

## 読み方

- `left` / `right`(版面の左右)と `lines` / `chars` が一致していれば、三系統が
  同じ設計値から同じ水平版面を組めている。
- `top` / `bottom` は字面(インク)の上端・下端で、ベースラインではない。1行目を
  天(head-space)と行送りの中でどこに置くかは系ごとに違うので、数 mm の差が出る。
  これは既知の差で、失敗ではない。
