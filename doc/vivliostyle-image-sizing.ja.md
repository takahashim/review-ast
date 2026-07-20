# Vivliostyle 版における図版の大きさ

`ImageSizeAnnotator` と `IntrinsicSize`、およびスタイルシートの `.image img`
が何をしているかと、なぜその形なのかを記録する。

これらは一見すると回りくどい。「標準の CSS プロパティを使えばよいのでは」
「そもそも要るのか」という疑問が自然に湧く仕組みなので、実際に測って
検討した代替案と、それを採らなかった理由を残しておく。

## 何を解決しているか

Re:VIEW のひとつの原稿から、LaTeX 版 PDF・EPUB・Vivliostyle 版 PDF が作られる。
図版の大きさについて、この三者は前提が違う。

**LaTeX 版**は `\includegraphics[width=<scale>\maxwidth]` で図を置く。

```
\maxwidth = min(画像の原寸, 版面幅)
```

ここでいう「原寸」は、画像に埋め込まれた解像度から決まる物理寸法である。
dvipdfmx は PNG の `pHYs` チャンクや JPEG の JFIF density を読み、
情報がなければ 72dpi とみなす。600px の画像でも、300dpi と書いてあれば
2 インチ（50.8mm）に置かれる。

**ブラウザ**（したがって Vivliostyle）はこの解像度情報を読まない。
1 画像ピクセルを 1 CSS px、すなわち 96dpi として扱う。同じ 600px・300dpi の
画像は 158.8mm になる。3 倍以上違う。

この差を埋めるのが `ImageSizeAnnotator` である。組版の直前に、展開済み
EPUB の各 `<img>` へ原寸を書き込む。

```html
<img src="images/foo.png" style="--natural: 52.910mm" />
```

スタイルシートはそれを受けて `\maxwidth` と同じ式を書く。

```css
.image img {
  width: calc(var(--scale, 1) * min(var(--natural, 100%), 100%));
  height: auto;
}
```

## scale の意味

`//image[id][caption][scale=0.5]` の `scale` は**原寸に対する倍率**である。
版面幅に対する割合ではない。

版面より狭い画像に `scale=0.5` を指定したら、その画像の半分の大きさになる。
これは LaTeX 版の印字がそうなっているというだけでなく、Re:VIEW の記法解説が
実演している挙動でもある。`FirstStepReVIEW-v3` の第7章がその例で、
LaTeX 版を実測するとこうなっている。

| 図 | 指定 | 実測 |
|---|---|---|
| 図7.1 | なし | 52.9mm |
| 図7.2 | `scale=0.5` | 26.5mm |
| （番号なし） | `scale=0.25` | 13.2mm |

原寸 52.9mm に対して 1/2、1/4 がきちんと段階を作っている。

なお同書の本文は「表示倍率は 1.0 を紙面の横幅いっぱいとして」と書いており、
これは EPUB 側の挙動（`width: 50%`）の説明になっている。本文・LaTeX 版・
EPUB の三者は元から食い違っている。Vivliostyle 版は LaTeX 版に合わせている。

## 採らなかった案

### 案1: scale を「上限」と読み替える

`max-width: calc(var(--scale, 1) * 100%)` として、原寸を知らずに済ませる案。
「版面幅の 50% に収める、ただし原寸より大きくはしない」という意味になる。
原寸が値として要らなくなるので、`ImageSizeAnnotator` ごと不要にできる。

**採らなかった理由**: 倍率の実演が成立しない。原寸が上限より小さい画像に
対して `scale` が何も起こさなくなる。上表の図7.2（原寸 52.9mm、上限 65mm）は
52.9mm のままとなり、図7.1 と同じ大きさになってしまう。記法解説として破綻する。

### 案2: 標準プロパティ `image-resolution` を注入する

`--natural` は独自プロパティなので、スタイルシート側に受け皿の式が要る。
かわりに標準の `image-resolution` を注入すれば画像の intrinsic な大きさ自体が
正され、`max-width: 100%` だけで済む——という案。

**採らなかった理由が2つある。**

ひとつは倍率が表現できないこと。`image-resolution` は intrinsic サイズを
正すだけで、「それに 0.5 を掛ける」を CSS で書く手段がない。案1 と同じ問題に
戻る。

もうひとつは Vivliostyle 2.44.1 の不具合。`image-resolution: from-image` は
未実装（無視される）なので値を明示する必要があるが、**96dpi 未満を指定すると
`max-width` が効かなくなる**。

原因は `core/src/vivliostyle/vgen.ts` の
`modifyElemDimensionWithImageResolution()` にある。縮小側（96dpi 以上）は
`width` を設定して著者の `max-width` を活かすのに、拡大側（96dpi 未満）は
`min-width` を設定する。CSS では `min-width` が `max-width` に優先するため、
クランプが無効化される。

実測（版面 130mm、1454px の PNG）:

| `image-resolution` | 原寸 | 配置 |
|---|---|---|
| 192dpi | 192.4mm | 130.0mm |
| 144dpi | 256.5mm | 130.0mm |
| 96dpi | 384.7mm | 130.0mm |
| **72dpi** | 512.9mm | **512.9mm** |
| **48dpi** | 769.4mm | **769.4mm** |

解像度情報のない画像は 72dpi 扱いになるので、これは例外ではなく通常のケース。

同じ関数に回避路はある。`min-width` が 0 以外なら `width` 経路に入るので、
スタイルシートに `min-width: 1px` を書けばクランプが復活する（実測で確認）。
ただしこれは、CSS と annotator が別リポジトリにあり更新時期が揃わない以上、
危険な結合を生む。

| 注記 | `min-width: 1px` | 版面 130mm 超過 |
|---|---|---|
| あり | あり | 0 点 |
| なし | あり | 0 点 |
| なし | なし | 0 点 |
| **あり** | **なし** | **3 点 / 最大 846.5mm** |

「本の CSS だけ更新して gem は古いまま」という自然に起こる組み合わせで
6.5 倍のはみ出しが起きる。片方向にだけ壊れるので気づきにくい。

Vivliostyle 側が拡大側でも `width` を設定するよう修正されれば、この案は
再検討に値する。

### 案3: 仕組みごとやめる

`ImageSizeAnnotator` と `IntrinsicSize` で 233 行あり、PNG チャンクと JPEG
マーカーの解析という独自の保守対象を抱えている。効果が小さいなら畳む、
という判断はありうる。

**採らなかった理由**: 倍率の実演（案1 と同じ問題）に加えて、依存している
解像度情報が実際には広く存在するため。`FirstStepReVIEW-v3` の本文画像 32 点を
調べると、解像度を申告しているものが 31 点、情報がないのは表紙の JPEG 1 点
だけだった。

## この仕組みが実際に効く条件

`scale` を掛ける相手が原寸である以上、`--natural` は**すべての図版の寸法に
効く**。ただし「注記の有無で結果が変わるか」となると条件がつく。

- 原寸が版面幅より広い画像は、どちらでも版面幅にクランプされる
- 原寸が版面幅より狭い画像で、はじめて差が出る

`FirstStepReVIEW-v3` では 32 点中 4 点が後者にあたる（記法解説のサンプル図
3 点と `workflow.png`）。解像度の分布は 144dpi が 20 点、600dpi が 4 点で、
これらは Retina キャプチャや書き出しの副産物だが、いずれも物理的に大きいので
クランプされて差が出ない。

## 将来の選択肢

`//image[id][caption][width=80mm]` のように**物理長を直接書ける書式**が
入れば、大きさを決めたい図はそれで表現でき、解像度メタデータからの推論に
頼る範囲が狭まる。`width=` は LaTeX なら `\includegraphics[width=80mm]`、
CSS なら `width: 80mm` にそのまま落ちるので、出力形式によらず同じ意味になる。

その段階でこの仕組みを縮小するか畳むかを再検討するのがよい。逆に、
推論の精度を上げる方向（対応形式を増やすなど）には投資しないほうがよい。

## 関連するコード

- `lib/review/ast/intrinsic_size.rb` — PNG/JPEG から解像度と画素数を読む
- `lib/review/ast/image_size_annotator.rb` — 各 `<img>` に `--natural` を書く
- `lib/review/ast/command/vivliostyle_maker.rb` — 組版前に上記を呼ぶ
  （`vivliostyle: image_intrinsic_size: false` で無効化できる）
- `templates/vivliostyle/css/style-vivliostyle.css` — `.image img` の式
