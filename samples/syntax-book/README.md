# syntax-book

Re:VIEW の文法要素をひと通り使ったサンプル書籍です。review-ast の各 maker で
ビルドできます。

## 準備

```console
$ bundle install
```

vivlio-pdf を手元のチェックアウトで使う場合は、先に次を実行しておきます。

```console
$ bundle config set --local local.vivlio-pdf ~/git/vivlio-pdf
```

## ビルド

```console
$ bundle exec rake pdf          # LaTeX 経由の PDF (uplatex + dvipdfmx が必要)
$ bundle exec rake epub         # EPUB
$ bundle exec rake web          # Web サイト (webroot/)
$ bundle exec rake vivliostyle  # Vivliostyle 経由の PDF (Chrome/Chromium が必要)
$ bundle exec rake text         # テキスト
$ bundle exec rake idgxml       # InDesign 用 XML
$ bundle exec rake clean        # 成果物の削除
```

`rake pdf` は review gem 同梱のクラスファイルを `sty/` にコピーしてから
ビルドします(`rake copy_sty`)。クラスを review-jlreq に切り替えるときは
次のようにします。

```console
$ REVIEW_TEMPLATE=review-jlreq REVIEW_CONFIG_FILE=config-jlreq.yml bundle exec rake pdf
```

スタイルシートは `css/` に置きます。config.yml の `stylesheet:` には
ファイル名だけを書けば、プロジェクトルート → `css/` → review-ast 同梱の
テンプレート (`templates/vivliostyle/css/`) の順で探索されます。
`config-vivliostyle.yml` が指す Vivliostyle 用 CSS はこのプロジェクトには
置いておらず、review-ast 同梱のものが使われます。
