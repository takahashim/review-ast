# 索引生成の接続方法

`@<idx>` / `@<hidx>` で埋め込んだ索引語から、索引ページを生成する。yomikata gem
（表層形→読み、および五十音順の並べ替え）を使う。

## 現状

Re:VIEW の索引は LaTeX 経路にしか存在しない。

```
LaTeXBuilder が \index{よみ@表示} を出力
  → TeX が .idx を書く（ページ番号入り）
  → mendex が並べ替えて .ind を書く
  → TeX が再実行して取り込む
```

HTML / IDGXML では索引語を埋め込むだけで、索引ページは作られない。

| 形式 | `@<idx>` の出力 | 索引ページ |
|---|---|---|
| LaTeX | `\index{...}` | mendex 経由で生成される |
| HTML | `<!-- IDX:語 -->` | なし |
| IDGXML | `<index value="語">` | なし |
| plaintext / TOP | 語のみ | なし |

`doc/makeindex.ja.md` にも「LaTeX ビルダ以外のビルダでは、埋め込んだ索引を利用する
手法を提供していません」と明記されている。読み順に並べる一般的な解が無かったため。

yomikata がその解になるので、埋まっていた穴を塞げる。

## 対象を HTML 系に絞る理由

LaTeX 経路の置き換え（mendex を Ruby で書き直す）は別の話として切り離す。ページ番号
は TeX が組んで初めて決まるので、TeX 依存は消えず、得られるのは mendex 依存の除去
だけになる。mendex は TeXLive 同梱なので、TeX があれば mendex もある。

HTML / EPUB / Web はページ番号が不要で、アンカーへのリンクで済む。TeX が関与しない
ので pure Ruby 以外の選択肢が無く、かつ現状ゼロなので、多少粗くても改善になる。

## 設計

### 1. 設定で自動生成される後付録として作る

pdfmaker に合わせる。著者は何も書かない。`makeindex` を真にすると索引ページが後付録
の決まった位置に現れる。

PDF ではこうなっている。`config.erb` が `\def\review@makeindex{true}` を出し、
`review-base.sty` がそれを見て `\reviewprintindex` を `\printindex` として定義し、
`layout.tex.erb` が後付録の固定位置でそれを呼ぶ。

```
backmatter hook
postdef body
index page      ← \reviewprintindex
profile page
advfile page
```

`.re` ファイルも `catalog.yml` への登録も不要で、設定ひとつで出る。

EPUB 側には同じ形の前例が既にある。`EPUBMaker#copy_backmatter` は設定を見て、著者
紹介・広告・奥付・裏表紙を後付録に足す。奥付は静的ファイルの複製ではなく、
`_colophon.html.erb` から生成される。索引ページもこれと同じ扱いにする。

```ruby
# copy_backmatter の先頭。LaTeX が postdef の直後・profile の前に置くのに合わせる
if makeindex?
  build_indexpage(basetmpdir)
  @htmltoc.add_item(1, "index.#{@config['htmlext']}",
                    ReVIEW::I18n.t('indextitle'), chaptype: 'post')
end
```

この形なら Re:VIEW 本体へのブロック命令追加（`defsingle :printindex, 0`）は要らない。
著者に新しい記法を覚えてもらう必要もない。

なお `//printendnotes` のようなブロック命令として作る案もあったが、それだと著者が
索引ページの `.re` を書いて `POSTDEF` に登録する必要があり、同じ本の PDF と EPUB で
手順が食い違う。pdfmaker の挙動に合わせる方を採る。

### 1b. 設定をどこに置くか

現状 `makeindex` は `pdfmaker:` の下にある。

```yaml
pdfmaker:
  makeindex: true
  makeindex_dic: my.dic
```

`makeindex_command` / `makeindex_options` / `makeindex_sty` / `makeindex_mecab` は
mendex 固有なので `pdfmaker:` のままでよい。一方 `makeindex` そのものと
`makeindex_dic`（読み辞書）は形式に依らない。

`epubmaker:` / `webmaker:` にも `makeindex` を置き、読み辞書はトップレベルに上げるのが
素直だが、既存の `pdfmaker.makeindex_dic` を壊さないよう、当面は
「`epubmaker.makeindex` が未設定なら `pdfmaker.makeindex` を見る」といった継承で
逃げる手もある。要検討。

### 2. 章をまたぐ収集は WebTocBuilder の形を踏襲する

`//printendnotes` は当該章の後注だけを集めれば足りるが、索引は全章から集める必要が
ある。これは `WebTocBuilder` が既に解いている形で、book を受け取り各章の AST を
コンパイルして横断的な構造を作る。

```ruby
class BookIndexBuilder     # ReVIEW::IndexBuilder は gem 側に既にあるので別名
  def initialize(book, reader:, sorter:)
  def build  # => [[見出し, [Entry, ...]], ...]
end
```

`Entry` が持つのは、索引語（階層のときは親子）、読み、掲載箇所（章 ID とアンカー）。

`ChapterRegistryProvider` と同じく、provider を 1 つ作って全章で使い回せば、各章の
コンパイルは 1 回で済む。

### 3. アンカーの精度

索引から本文へ飛ぶにはアンカーが要る。現状 HTML は `<!-- IDX:語 -->` というコメント
を置くだけで、id が無い。

案A: 直近の節見出しのアンカー（`h1-2-3`）に飛ばす。レンダラを変えずに済むが、1 つの
節に複数の索引語があると、どれも同じ場所に着く。

案B: `@<idx>` の位置に id を出す。正確だが HTML 出力が変わる。

案B を採る。ただし `makeindex: true` のときだけ id を出す。既定では出力が変わらない
ので、HTMLBuilder との rendered-equivalence が保たれる。LaTeX 経路が `makeindex` で
既にゲートされているのと同じ扱いになる。

```html
<!-- makeindex: true のとき -->
<span id="idx-12">正規表現</span><!-- IDX:正規表現 -->
```

### 4. 読みの供給

`makeindex_dic`（タブ区切りの読み辞書）は `Yomikata.load_overrides` がそのまま読める
形式なので、既存の設定をそのまま渡せる。

```ruby
overrides = config['pdfmaker']['makeindex_dic'] ? Yomikata.load_overrides(path) : {}
reader = Yomikata.reader(overrides: overrides)
```

`reader.confident?` が false を返した語は読みが引けていない。ビルド時に警告を出して、
`makeindex_dic` への追加を促すのが親切。技術書の索引語は MeCab でも外しやすく、
`doc/makeindex.ja.md` 自身がそう書いている。

### 5. yomikata への依存

必須依存にする。pure Ruby で 3.1MB、ネイティブ拡張なし。既に依存している nokogiri
より小さい。

任意依存にして無いときは JIS コード順にフォールバックする、という手もあるが、その
フォールバックは `Yomikata::Sorter` が読み不明語に対して行うことと同じで、同じ判断
が 2 箇所に分かれる。この種の重複が実バグの温床になったのが `caption_top?` や
`over_secnolevel?` の件（design-improvements 項目 9）なので、避ける。

## 段取り

Re:VIEW 本体への変更は要らない。すべて review-ast 側で閉じる。

1. `BookIndexBuilder` を追加。全章の AST から索引語と掲載箇所を集める。テストは
   「AST から正しく集められること」に対して書く
2. `makeindex` が真のとき HTML レンダラが `@<idx>` / `@<hidx>` に id を出す
3. 索引ページのテンプレート（`_index.html.erb`）と、それを描画する処理
4. `epub_maker` / `web_maker` の後付録に索引ページを差し込む。位置は postdef の直後、
   著者紹介の前で、LaTeX の並びに合わせる
5. LaTeX 経路は従来どおり mendex に任せる（当面変更なし）
6. IDGXML / plaintext / TOP は当面何も出さない

## 未決

- 設定の置き場所（`epubmaker.makeindex` を新設するか、`pdfmaker.makeindex` を
  見に行くか）
- 索引ページのマークアップ（`<dl>` か入れ子 `<ul>` か）。`@<hidx>{親<<>>子}` の階層を
  どう表現するか
- 同じ語が複数箇所に出るときのリンクの並べ方
- 英字項目のグループ見出し。`Yomikata::Sorter` は `A` の 1 グループにまとめている
  が、`A` `B` `C` と分けたい本もある
- Web 版でサイドバーに索引へのリンクを出すか
- `review-ast` の EPUB は gem の `EPUBMaker` を継承しているだけなので、後付録への
  差し込みをどう実現するか。`copy_backmatter` の上書きで足りるか要確認
