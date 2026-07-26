# Differential testing (builder vs AST renderer)

review-ast reimplements Re:VIEW's output pipeline on top of an AST. The single
most important correctness question is therefore:

> Does the AST renderer produce the **same result** as the legacy
> `ReVIEW::LATEXBuilder` (and the other builders)?

This document describes how we answer that with **differential testing** — using
the legacy builder as an oracle — at two levels of strictness, and records the
methodology and the classes of divergence it has found.

Matching the builder means inheriting its behaviour whether or not that behaviour
is intended. Undocumented/suspicious behaviours we match anyway are tracked
separately in [spec-questions.md](spec-questions.md) so they can be triaged later
rather than silently treated as correct.

## Two oracles, two strictness levels

| Level | What it compares | Speed | Sees whitespace? |
| --- | --- | --- | --- |
| **text-canonical** | builder LaTeX vs renderer LaTeX, after normalizing whitespace/blank-lines | fast (no TeX) | **no** |
| **DVI** | the *typeset* output (DVI) of both | slow (runs uplatex) | **yes** |

The text-canonical comparators (`test/support/review/test/*_comparator.rb`) run
in the normal test suite. They deliberately ignore whitespace and blank lines,
so they answer "is the markup structurally equivalent?" — but they are **blind**
to differences that only whitespace can express.

The DVI comparator (`tools/compare/dvi_comparator.rb`) closes that blind spot. It
typesets both LaTeX bodies under an identical preamble and compares the DVI. If
the DVI differs, the two paths genuinely typeset differently — a real, visible
divergence. Because the preamble and the TeX toolchain are fixed, the DVI is the
*meaning* of the output; there is no further normalization to argue about.

**Every bug in the table below passed the full text-canonical suite.** DVI is
what caught them.

## Running a DVI sweep

```sh
BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/compare_book.rb samples/syntax-book
```

For each chapter it renders the LaTeX body twice (builder vs renderer, with full
book context), typesets both, and reports whether the DVI is identical. Chapters
that only one path can compile are reported as `CERR`. See `tools/README.md` for
details and the library API.

Determinism: the only nondeterministic part of a DVI is the timestamp comment in
the preamble, which is fixed with `-output-comment` and stripped from the dviasm
dump. DVI is otherwise tied to the TeXLive version, so a CI sweep needs a pinned
toolchain (that work is deliberately deferred).

## Localizing a divergence

When a chapter's DVI differs, this workflow pins the cause quickly:

1. **DVI dump → text.** Diff the dviasm dumps and read the nearest `set: '…'`
   glyphs around the first change to learn *what text* is mispositioned, and the
   `pdf:dest`/`[page …]` markers for *where*.
2. **Quantify.** Small, isolated `down:`/`right:` deltas (< 1pt, few lines) mean
   a local spacing difference; thousands of changed lines mean a pagination
   cascade from something earlier.
3. **Text → source construct.** Grep the mispositioned text in the `.re` source
   and look at the construct just before it.
4. **Compare the `.tex`.** Diff builder vs renderer LaTeX for that chapter and
   look at the exact lines around the construct (whitespace matters — view with
   markers). This usually shows the offending byte-level difference.
5. **Minimal repro.** Reconstruct the construct in a few lines and DVI-compare it
   in isolation (`DviComparator#compare`). This confirms the cause and becomes
   the basis for a regression test.

Because the text-canonical comparator ignores whitespace, regression tests for
whitespace-class findings must assert on the **exact** rendered string, not via
the canonical comparator.

## Divergence classes found so far

Each of these was found by a DVI sweep, fixed, and locked in with a regression
test. They cluster into a few recurring shapes.

| Area | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| Caption numbering | appendix caption numbered `1.1` instead of `A.1` | used raw `@chapter.number` instead of appendix/secnolevel-aware `get_chap` | route caption numbers through `get_chap` |
| Block + footnote | `\footnotetext` after a minicolumn placed after a blank line (spurious empty paragraph) | trailing blank emitted before the collected `\footnotetext` | emit `\end{…}` → `\footnotetext` → blank |
| Verbatim | tab-aligned code typeset at the wrong width | code lines not detabbed like `LATEXBuilder#code_line` | detab in `visit_code_line` (honoring `tabwidth`) |
| Forced break | `@<br>{}` at end of a source line adds ~0.95pt vertical space | `@<br>` emits `\\\n`; the preserved source newline makes it `\\\n\n` (a `\par`) | collapse a blank line right after a forced break in `visit_paragraph` |
| Compiler (not render) | `==[column]` containing `====` subsections fatally errors on `==[/column]` | headlines reset the current node to root, losing column context; close couldn't find the column | keep the current node inside the column across subsections; walk ancestors to close |
| Compiler (not render) | two blank-separated `ul`/`ol` merged into one list (numbers ran 1..6) | the list-structure normalizer merged *all* adjacent same-type lists | merge only `dl` across a blank line and only fold `ul`/`ol` continuations across `//beginchild` — matching LATEXBuilder |
| Numbering | trailing / lone blank line in `//listnum` not numbered | `add_line_numbers` skipped the last empty line and `split("\n")` dropped trailing empties | `split("\n", -1)[0...-1]` — keep genuine blank lines, drop only the artifact |
| Verbatim | tab-aligned code in `//listnum` mis-aligned by the `" N: "` width | detabbed the raw line before prepending the number | detab the final line *after* numbering (`detab_content` in the block wrappers) |
| Parser | `"===== {x} caption"` treated `{x}` as a heading label | the parser stripped the leading space before checking for `{label}` | don't strip: a label only counts immediately after `=`/`[tag]` (no space), matching Compiler |
| Parser | trailing `"Caption{label}"` treated `{label}` as a label | AST had a non-standard trailing-label syntax | remove it — Re:VIEW labels are leading (`=={label} Caption`); a trailing `{...}` is caption text |
| Renderer (gap) | `//box` raised NotImplementedError | the block was never implemented in the AST LaTeX renderer | implement `visit_block_box` (reviewbox env, detabbed inline-processed lines, optional caption) |
| Renderer | `@<idx>{和文}` emitted `\index{語@語}` | always produced a "key@display" sort key | only emit a sort key when one exists (dictionary/MeCab); otherwise `\index{語}` |
| Renderer | deep unnumbered headline TOC name wrong (level 5→subsection) | hardcoded `case` mapping capped at subsection | use the `HEADLINE` mapping (paragraph/subparagraph for 5/6) |
| Compiler | nested block inside a minicolumn/quote moved to the end | content lines and nested blocks were collected separately, losing order | record each nested block's line position and interleave in source order |
| Renderer | numbered-equation caption double-escaped (`a<b` → `a\reviewbackslash{}textless...`) | the already-escaped caption was escaped a second time | render it via `text_formatter.format_caption`, like the other captions |
| Renderer | a paragraph after a block `//embed` merged into the embed | the block embed ended with a single `\n`, not a paragraph break | end block embeds with `\n\n` (the AST separates blocks by trailing blank lines) |
| Renderer (DVI) | the raw-content adjacency rules only ran at the document level, so two `//embed` inside a `//note`/column still got a blank line between them (spurious `\par`); a column whose first content was an embed got a blank after `\addcontentsline` | `visit_minicolumn`/`visit_column` joined their children with plain `render_children`, bypassing the document-level separation logic | extract that logic into `join_block_children`/`apply_block_child_separation` and use it for the document, minicolumns, and columns; also drop the column's "blank after header" when its first content block is a raw-content embed (the column header is not an environment start, so the `\par` isn't absorbed) |
| Renderer (DVI) | a minicolumn (`//note` etc.) directly before a block/`:raw` `//embed` left a blank line, so the embed's raw content became a new paragraph (spurious `\par`) | the minicolumn's trailing `\n\n` sat before the embed content; a captionblock emits no trailing `#blank` in `LATEXBuilder`, so the embed prints right after `\end{review…}` | in `render_document_children`, drop a `MinicolumnNode`'s trailing blank when the next child is a block/`:raw` embed (node check, since embed content is arbitrary — the existing string rules already cover minicolumn → minicolumn/`\pagebreak`/`\hrule`/`\footnotetext`). Found by the PBT DVI sweep (seed 971) |
| Renderer (DVI) | `//raw` content got a trailing `\n`, so two consecutive `//raw` rendered as "A B" (newline = space) instead of the builder's adjacent "AB" | `render_document_children` appended `\n` after every `:raw` embed; `LATEXBuilder#raw` does `print content` with no added newline | append `\n` after a `:raw` embed only when the next child is a paragraph (the builder joins the raw into it as "A\ntext"); consecutive raws / raw→embed stay adjacent, and raw→block-env is DVI-neutral (leading space before `\begin`/`\section` is absorbed). Also extended the block-embed blank-drop to a following `:raw`. Found by extending the DVI adjacency audit |
| Renderer (DVI) | two consecutive block `//embed[latex]` blocks were separated by a blank line, so the second became a new paragraph (`\LaTeX{}\n\n\LaTeX{}` → spurious `\par`) | the block-embed `\n\n` (added to separate a following paragraph) is wrong before another embed — `LATEXBuilder#embed` uses `print content+"\n"` (no `#blank`), so consecutive embeds sit on adjacent lines | in `render_document_children`, drop the block embed's trailing blank when the next child is also a block embed (as already done for a following `//noindent` paragraph). Found by the PBT DVI sweep (seed 245); DVI-neutral for embed→paragraph/heading which keep the blank |
| Numbering | `@<img>` after an `//indepimage` numbered `1.2` instead of `1.1` | the indexer routed every image block to `@image_index`, so unnumbered `//indepimage`/`//numberlessimage` advanced the counter | branch `visit_image` on `image_type`: only `//image` uses `@image_index`; the rest go to `@indepimage_index` (matching IndexBuilder) |
| Renderer (gap) | `//pagebreak`, `//hr`, and `//parasep` produced no output | the control-command visitors were stubs returning `''` | emit `\pagebreak` / `\hrule` / `\parasep` like `LATEXBuilder#pagebreak` / `#hr` / `#parasep` |
| Config | with `join_lines_by_lang: true`, an ASCII→Japanese line boundary added a spurious space (`code文字` vs `code 文字`) | the renderer kept the source `\n` at line joins; `LATEXBuilder` joins via `join_lines_to_paragraph`, which inserts *no* space there, while a raw `\n` typesets as a space | honor `join_lines_by_lang` at every line-join site — ordinary/`:block` paragraphs (`join_paragraph_lines`), list-item continuations (`render_list_item_content`), and `dd` (`join_source_lines`) — inserting a language-aware space (`add_space?`) instead of `\n`. (Other boundary classes — ASCII–ASCII, Japanese–ASCII, Japanese–Japanese — were already DVI-identical; only ASCII→Japanese diverged.) |
| Config | with `caption_position` bottom, list/table/equation captions stayed at the top | `visit_list_block`/`visit_table`/`visit_tex_equation` (and emlist/cmd/source) always emitted the caption above the body | place the caption above or below per `caption_top?`, matching `LATEXBuilder`'s `common_code_block`/`table`/`texequation`. (A caption-less `//table` with an id also stopped emitting a `\begin{table}` float / caption; only its DVI-invisible `\label` is kept.) |
| Config | with `footnotetext: true`, `@<fn>` lost its `{}` and each `//footnote` emitted no `\footnotetext` | `render_inline_fn` returned `\footnotemark[n]` (no braces) and `visit_footnote` was an unconditional `''` | emit `\footnotemark[n]{}`, and in global footnotetext mode emit `\footnotetext[n]{…}` at each `//footnote` definition (`visit_footnote`), excluding `//endnote` |
| Config | at `secnolevel: 0`, `@<list>`/`@<table>`/`@<img>`/`@<eq>` kept the chapter prefix (`1.1` vs `1`) | the reference used `format_chapter_number_short(data.chapter_number)`, which ignores secnolevel | gate the chapter prefix on `secnolevel > 0` (`ref_chapter_number`), mirroring `LATEXBuilder#get_chap` |
| Whitespace | a minicolumn directly before `//pagebreak`/`//hr` added a spurious `\par` (~34pt) | the renderer gives every block a trailing blank line, but `captionblock` emits none in the builder and `\pagebreak`/`\hrule` take no leading blank | drop the separating blank between a minicolumn `\end{…}` and a following `\pagebreak`/`\hrule` (like the existing minicolumn→minicolumn rule) |
| Numbering | `@<hd>`/`@<secref>` to an unnumbered heading (subsection beyond secnolevel) showed a spurious number (`「1.1 子」` vs `「子」`) | `build_heading_reference_parts` always returned a number; the renderer always formatted `「number title」` | return a `numbered` flag (`over_secnolevel?` + chapter number, like `inline_hd_chap`); emit `hd_quote_without_number` (title only) when unnumbered |
| Whitespace | list-item continuation lines ran together (`項目2a.b.` vs `項目2 a. b.`) — visible only at an ASCII boundary | the AST flattened all of an item's source lines into one child list, losing the newline `LATEXBuilder` keeps (`ol_item`: `lines.join("\n")`) | record the line boundaries on `ListItemNode` (`latex_line_breaks`) and have only the LaTeX renderer reinsert `\n` — `HTMLBuilder` joins with `""`, so the split must stay renderer-local, not baked into the AST |
| Structure | a list inside `//quote`/`//lead`/`//flushright`/`//centering` became an `itemize`/`enumerate`; the builder keeps it as literal text | the AST ran `process_structured_content` (full block/list parsing) on `:block` wrapper content, but `LATEXBuilder`'s `read_block` only inline-compiles lines (no list markup) | pass `parse_lists: false` for those wrappers so list-marker lines stay paragraph text (matches the builder's `read_block`) |
| Renderer (gap) | `@<fn>` inside a heading emitted a bare `\footnote{}`, which breaks LaTeX (a heading is a moving argument) | `visit_headline` rendered the caption in the normal context, so `render_inline_fn` never took the `\footnotemark` branch | add a `:heading` footnotetext context; render the heading caption in it (→ `\protect\footnotemark{}`) and flush `\footnotetext` after, while the `\addcontentsline` TOC caption re-renders in the normal context (plain `\footnote`) and `nodisp` (no visible heading) emits neither — mirroring `LATEXBuilder`'s `@doc_status[:caption]` toggling. (The `\footnotetext` position is handled by the row below.) |
| Renderer (DVI) | a moving-argument footnote (heading/caption/table/column/dt) flushed its `\footnotetext` right after the context, not at the `//footnote` definition — so a page break between the two put the footnote on the wrong page | the per-context footnote *collectors* emitted `\footnotetext` immediately after the heading/minicolumn; `LATEXBuilder` instead records the id (`@foottext` in `inline_fn`) and emits `\footnotetext` at the `//footnote` definition (`footnote`) | mirror `@foottext`: `render_inline_fn` calls `defer_footnotetext(id)` (a renderer-level set) and emits only `\protect\footnotemark{}`; `visit_footnote` emits the `\footnotetext` at the definition when the id was deferred (or in global `footnotetext` mode). Whitespace: the `\footnotetext` gets a leading blank only when the preceding block called `#blank` — a headline (ends `\label`) and a minicolumn do not, so `render_document_children` trims that blank; it carries a trailing blank to separate the next paragraph. Verified DVI-equal across a `//pagebreak` between heading and definition (previously `differ`) |
| Renderer | `@<endnote>{id}` emitted the endnote content as escaped plain text, dropping inline markup (`@<b>{bold}` → `bold`) | `render_inline_endnote` used `escape(data.caption_text)` instead of rendering the parsed `caption_node` | inline-compile the content via `@ctx.render_children(data.caption_node).strip`, matching `LATEXBuilder#inline_endnote`'s `compile_inline(content.strip)` |
| Renderer | a `//bibpaper` caption was raw-escaped, so `@<fn>{…}`/`@<b>{…}` in it came out as literal text | `visit_bibpaper` did `escape(node.args[1])` on the raw caption string instead of rendering the parsed `caption_node` | inline-compile the caption via `render_children(node.caption_node)`, matching `LATEXBuilder#bibpaper_header`'s `compile_inline(caption)` (a normal, non-moving context, so a footnote there is a plain `\footnote`) |
| Renderer (crash) | a `//bibpaper` under `join_lines_by_lang: true` raised `NameError` | `visit_bibpaper` called `TextUtils#split_paragraph` (on an already-rendered string, no less), which needs `pre_paragraph`/`post_paragraph` — methods the renderer never defines | drop the `split_paragraph` call: the bibpaper body is parsed into paragraph nodes, so `render_children` already did the language-aware paragraph joining (`join_paragraph_lines`), matching `bibpaper_bibpaper` for both config settings |
| Renderer (gap) | a `@<fn>` in a column caption (`===[column] Cap @<fn>{x}`) emitted a bare `\footnote{}`, which breaks in the moving argument | `visit_column` rendered the caption in the ambient context, so `render_inline_fn` never took the `\footnotemark` branch (even though `:column` is a footnotetext context, the caption itself was rendered outside it) | render the column caption in a footnotetext-requiring `:caption` context (→ `\protect\footnotemark{}`) and flush its `\footnotetext` after the column — before the body's, matching source footnote order; the caption is reused in `\addcontentsline`, so both spots get the footnotemark |
| Table | a second `------------` separator row survived as a `{-}×12` data row | the AST split header/body at the *first* separator but kept later separators in the body; `LATEXBuilder#parse_table_rows` `next`-s **every** separator line | drop all further separator lines from `body_lines` in `TableStructure.from_lines` (only the first sets the split) |
| Table | a caption-less `//table[id]` emitted a spurious `\label{table:…}` | the renderer emitted the label for caption-less tables (to keep `@<table>` resolvable); `LATEXBuilder#table` only reaches `table_header` (caption **and** label) when the caption is present | emit no label for a caption-less table — matching the builder; `@<table>` refs embed the number directly, so they still render the same visible text |
| Renderer | `@<imgref>{id}` dropped the referenced image's caption | `render_inline_imgref` just delegated to `render_inline_img`, emitting only `\reviewimageref{n}{label}` | append the image caption as I18n `image_quote` (「caption」) when the image has one, mirroring `LATEXBuilder#inline_imgref` (raw caption, `@chapter.image(id).caption`) |
| Renderer (gap) | `@<dtp>{…}` and `@<pageref>{id}` raised `NotImplementedError` | neither inline op had a `render_inline_*` handler, so the dispatcher's unknown-op fallback raised | add `render_inline_dtp` (returns `''`, like `LATEXBuilder#inline_dtp` which ignores it) and `render_inline_pageref` (`\pageref{id}` with the raw id, no escaping) |
| Renderer | `@<uchar>{code}` emitted `\UTF{code}` under `texcommand: platex` | `render_inline_uchar` branched on `config['texcommand']`, but `LATEXBuilder#inline_uchar` keys on `@texcompiler` — an ivar that is never assigned on the builder (only `PDFMaker` sets it on itself), so the builder's platex branch is dead and it always passes the codepoint through as a literal Unicode character | drop the texcommand branch: always pass through (`[code.to_i(16)].pack('U')`), matching the builder under every engine |
| Config (gap) | with `highlight: {latex: listings}`, all code blocks were rendered as `review*` verbatim environments with escaped text; the builder uses `review*lst` (listings) environments with RAW text | the renderer had no listings path: it always escaped code text and emitted the verbatim envs, ignoring `highlight` | route `list`/`listnum`/`emlist`/`emlistnum`/`cmd`/`source` to `render_code_listings` (`review*lst` env + bracketed `caption=/title=/language=/firstnumber=` args via `make_code_block_lst_args`) when `highlight_listings?`. The body is emitted non-escaped (a `@nonescape_code` flag makes `visit_text` skip `escape`, mirroring `Compiler#non_escaped_commands`) while inline ops still compile and their arguments stay escaped (`visit_inline` clears the flag around the inline's children). The listings caption is inline-compiled with NO chapter-number prefix (unlike the verbatim caption). `//cmd` passes `lang: ''` because it has no lang argument (the AST's `default_lang: 'shell'` is HTML-only) |
| Table (IDGXML) | a ragged table (a header narrower than the body) emitted an extra empty `<td>` per short row that the builder never writes | `TableProcessor#adjust_columns` pads every short row out to the table width (mirroring `Builder#adjust_n_cols`), and the IDGXML renderer rendered all cells; but `IDGXMLBuilder` has no `adjust_n_cols` — it emits each row's own cells only (the shared column count lives in `aid:tcols`, not in padding cells) | record the source cell count before pop/pad on `TableRowNode#natural_cell_count` and have the IDGXML renderer emit only the first `natural_cell_count` cells of each row. The pre-pop count also keeps a trailing `.` cell (which `IDGXMLBuilder` preserves via DUMMYCELLSPLITTER but `LATEXBuilder` pops), so both the ragged-pad and the trailing-`.` classes match. LaTeX/HTML still render the padded row. Found by the PBT idgxml sweep (seed 14) |

### A design note: list merging

LATEXBuilder is the oracle, and it treats blank-separated lists per type:

- **`ul` / `ol`**: a blank line ends the list; the next group is a *separate*
  environment (numbering restarts). They only rejoin when interrupted by
  `//beginchild .. //endchild` (an explicit nesting directive).
- **`dl`**: consecutive blank-separated `: term` groups form *one* description
  list.

The AST originally merged all adjacent same-type lists unconditionally, which is
a reasonable-looking design choice but disagrees with the builder for `ul`/`ol`.
We aligned with the builder. If Re:VIEW ever decides blank-separated `ul`/`ol`
*should* merge, this is the place to revisit — but then the builder would need to
change too, so the two stay in sync.

### Recurring lessons

- **Whitespace is semantics in two places:** verbatim environments (tabs/spaces)
  and forced breaks / paragraph boundaries (`\\`, blank lines → `\par`). These
  are exactly what the text-canonical comparator cannot see, and where DVI earns
  its keep.
- **Japanese line handling hides differences.** upLaTeX suppresses the space at a
  source newline between Japanese characters, so builder "join lines into one"
  vs renderer "keep source lines" is usually DVI-identical — *except* when a
  forced break or a non-Japanese boundary is involved. Don't assume a `.tex`
  whitespace difference is invisible; confirm with DVI.
- **Match the legacy builder's byte output where whitespace is load-bearing.**
  Several fixes were simply "emit the same newlines the builder does."
- **Real books exercise constructs samples don't.** The column/subsection and
  `@<br>`-at-line-end bugs only surfaced on `FirstStepReVIEW-v3`; the bundled
  samples were already clean. Sweeping additional real books is high-value.

## Property-based testing

`tools/pbt/` generates random self-contained documents and runs the same two
oracles over them, shrinking any counterexample to a minimal `.re` (see
`tools/README.md`). The workflow is loop-until-dry: fix a finding, fold it into a
regression test, re-run. Structural bugs surface in the fast `canonical` mode;
whitespace-only bugs (e.g. the tab-after-number alignment above) surface only in
`dvi` mode, so the productive order is **canonical until dry, then dvi**.

At the time of writing both modes are dry across the first ~90 seeds. All five
PBT-found classes in the table above were fixed and locked in with regression
tests. Two operational notes learned here:

- The generator must only emit inputs *both* paths can compile and typeset;
  otherwise "both fail" noise (unsupported inline ops, `@<ins>{a<b}` breaking
  underline macros) drowns real findings. The runner classifies "both fail"
  separately from a genuine divergence.
- Seeds are reproducible but not stable across generator changes — fold findings
  into tests, never cite a seed as the regression.
- `@<raw>{|latex|...}` in the generator must carry a brace-free control *symbol*
  (e.g. `\,`). A `{` / `}` breaks the inline parser (a literal `{}` comes out as
  `{\}`), and a bare control *word* (`\TeX`, `\LaTeX`) has upTeX absorb the next
  letter/kana into its name (`\TeXと` scans as one undefined control sequence).
  Both make the input un-typesettable for *both* paths — pure skip noise, not a
  divergence. This was worth several DVI skips until the content was constrained.

## Known gaps (unimplemented in the AST LaTeX renderer)

Constructs the builder supports but the AST LaTeX renderer does not yet. They are
deliberately kept out of the PBT generator (so they don't flag every run) until
implemented. The runner classifies them as `renderer_error` (a divergence) if
they do appear.

- **`//graph`** — generates an image with an external tool (Graphviz/Gnuplot/…)
  and then renders it as an image. Implementing it means running the tool and
  emitting a file from the renderer (a side effect the AST renderer otherwise
  avoids), plus matching the builder's image path/binding. Deferred; niche.
- **`@<w>` / `@<wb>`** — word substitution from a dictionary. The AST's
  `resolve_word_ref` raises `CompileError: word not bound` for a missing id,
  whereas `LATEXBuilder#inline_w` degrades gracefully to `[missing word: id]`
  (and `#inline_wb` to `\reviewbold{[missing word: id]}`). The sources also
  differ (builder loads a words *file* via `load_words`; the resolver reads
  `config['dictionary']`), so a faithful fix is cross-cutting (shared resolver +
  every renderer's `render_inline_w`/`_wb`). Deferred; niche.

Constructs the builder itself does **not** support for LaTeX, which the AST
renderer nonetheless implements (a benign superset — a valid LaTeX book cannot
use them because the builder raises an error): `//talk`, `//bpo`,
`//blockquote`, `//address`, `//doorquote` ("unknown command"), and the inline
`=[part]` tagged section (LATEXBuilder raises "builder does not support tagged
section: part" — parts come from the catalog, not an inline heading tag; the
renderer instead treats it as a `\chapter`), and the inline `@<cite>` ("builder
does not support inline op: cite").

## Scope and limits

- DVI comparison is LaTeX-only. HTML/IDGXML keep using DOM/text normalization.
- It requires TeXLive (`uplatex`, `dviasm`, `extractbb`) and `python3`.
- It compares builder vs renderer, not against a published PDF: the preamble is
  harvested from the book but the goal is *equivalence of the two code paths*,
  not reproducing a specific book's layout.
- A residual DVI difference under ~1pt with equal page counts is a real (if tiny)
  divergence; treat it as a finding to localize, not noise, until explained.
