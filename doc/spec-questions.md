# Spec questions: builder-derived behaviours that may or may not be intended

review-ast reproduces the output of Re:VIEW's legacy builders bit-for-bit (see
[differential-testing.md](differential-testing.md)). The builder is the oracle,
so wherever we align with it we inherit its behaviour *whether that behaviour is
an intended feature or an accident of the implementation*.

Most of the time this is fine. But some behaviours are **not documented in the
Re:VIEW format spec** and look questionable. We match the builder anyway (that is
the whole point of parity), but we should not pretend they are "correct" — they
are open questions for the Re:VIEW maintainers.

This file is that list. It exists so that:

- a future reader does not "fix" an intentional builder-matching quirk, mistaking
  it for an AST bug;
- when the AST path is ready to become the source of truth, each entry can be
  triaged: **spec it** (document the behaviour and keep it), or **fix it** (change
  the builder *and* the renderer together, updating the oracle).

Prefer adding an entry here over sprinkling `# matches builder, spec unclear`
comments through the code.

## How to use

- Add an entry when you match the builder on something undocumented/surprising.
- Keep it short: what the builder does, why it's suspicious, where it lives.
- Resolve an entry by either documenting the behaviour in the Re:VIEW format spec
  (and linking it) or fixing builder + renderer together, then delete the entry.

## Open questions

### 1. TOC sectioning name for a Part differs by path (`part` vs `chapter`)

For an unnumbered Part, the `\addcontentsline{toc}{...}` sectioning name depends
on *how* the Part is rendered:

- a starred Part (`secnolevel: 0`, the normal numbered path) records its TOC entry
  under **`part`**;
- a `[nonum]` Part records it under **`chapter`**.

Both match LATEXBuilder (and both are pinned by existing tests:
`test_visit_headline_part_with_secnolevel0` → `part`,
`test_visit_headline_part_nonum` → `chapter`). There is no obvious reason the two
paths should disagree, and the format spec does not describe Part TOC entries.

- Renderer: `LatexRenderer#visit_headline` (regular path, uses
  `get_base_section_name`) vs `#generate_nonum_headline` (uses `HEADLINE[level]`).
- Question: is the `part`/`chapter` split intended, or an accident? If intended,
  document it; if not, unify (in the builder and the renderer together).

### 2. A table cell that renders empty via `@<comment>` shifts the row (builder)

A table row whose first cell is `@<comment>{x}` (which compiles to `""`) is
mis-rendered by LATEXBuilder: the *second* cell's content moves into the first
column and the second column comes out empty. For example
`@<comment>{x}\tB | ------- | C\tD` yields `\reviewth{B} & \reviewth{}` instead of
`\reviewth{} & \reviewth{B}`. A `.` empty cell (the documented empty-cell syntax)
does not shift — only an inline that *renders* to empty does.

This looks like a genuine builder bug (an empty-rendering cell collapses), not
intended behaviour, so the AST renderer does **not** reproduce it — it keeps the
cell in its source column, which is what a reader expects. This is therefore a
real builder-vs-renderer divergence we deliberately do **not** match; the PBT
generator avoids emitting `@<comment>` so it is not flagged every run.

The same bug (and same deliberate non-match) shows up in **HTML and IDGXML**,
not just LaTeX: any inline that renders to `""` in the target format triggers the
shift. The most common trigger in those sweeps is `@<raw>{|latex|…}` in a cell —
non-empty for LaTeX (so the LaTeX sweep never sees it), but empty for HTML/IDGXML,
so their sweeps do. (Builder: `<th>一致</th><th></th>` vs the renderer's correct
`<th></th><th>一致</th>`.) So the HTML/IDGXML differential sweeps also leave this
single class of divergence unmatched by design. To keep it out of the sweeps, the
PBT generator's cell context (`inline_fragment(cell_safe: true)`, used by
`inline_cell_table_block`) excludes `@<raw>{|latex|…}` just as the whole generator
already excludes `@<comment>` — an empty-in-HTML/IDGXML inline in a cell produces
a builder-only "divergence", not a useful one. (`@<raw>` still appears in ordinary
prose, so the LaTeX sweep keeps its cell-and-prose coverage of it.)

- Builder: `Builder#parse_table_rows` splits cells correctly, so the shift is in
  the cell-rendering / `adjust_n_cols` path when a cell compiles to `""`.
- Question: fix the builder (don't collapse an empty-rendering cell), then this
  entry and the generator exclusion can both go away.

### 3. Table header/body separator threshold is escape-dependent in LATEXBuilder

The header/body separator is a row of dashes/equals. `Builder#parse_table_rows`
tests each row with `/\A[=-]{12}/ || /\A[={}-]{12}/` — but it runs *after* the
compiler has inline-compiled (and escaped) each line. In LaTeX, `-` escapes to
`{-}`, so a row of N dashes becomes `{-}` × N = 3N characters drawn from the set
`[={}-]`. The `/\A[={}-]{12}/` alternative then matches once 3N ≥ 12, i.e. at **4
or more dashes**. So LATEXBuilder treats `----` (4 dashes) as a separator.

Every other builder escapes `-` as `-` (HTMLBuilder verified: `-----` stays five
chars), so it needs the documented **12** dashes. The AST detects the separator
once, format-agnostically, on the raw line (`table_structure.rb`, same `{12}`
rule), so it agrees with HTML and the 12-dash convention — and with LaTeX too for
any conventional 12+ separator.

For 4–11 dashes the AST (and HTML) keep the row as data while LATEXBuilder treats
it as a separator. The AST deliberately does **not** reproduce the LaTeX-only,
escape-order-dependent threshold: the separator split is shared across all
renderers and cannot carry a LaTeX-specific rule without breaking HTML parity.
The PBT generator only emits 12-dash separators, so this is not flagged per run.

- Builder: `Builder#parse_table_rows` (regex runs on the escaped line).
- Question: make the separator detection escape-independent (e.g. detect on the
  raw source, thresholded consistently) in the builder, then builder, HTML and
  LaTeX would all agree and this entry can go away.

### 4. `footnotetext: true` + a footnote in a heading emits an unprotected `\footnotemark` (un-typesettable)

With global `footnotetext` mode, `LATEXBuilder#inline_fn` emits
`\footnotemark[n]{}` for every `@<fn>` — including one inside a heading. A
heading is a LaTeX moving argument, so a bare `\footnotemark` (no `\protect`)
breaks when the heading is written to the `.toc`/marks. So
`\section{A \footnotemark[1]{}}` fails to typeset. In the *normal* footnote path
the builder correctly emits `\protect\footnotemark{}` in a moving argument (see
`@doc_status[:caption]` handling), but the global-`footnotetext` branch does not.

The AST renderer reproduces the builder byte-for-byte here (verified via the
canonical comparator), so both paths emit the same un-typesettable LaTeX — the
DVI harness reports `build_error_both`, i.e. no divergence, just a faithfully
matched builder bug. Not reproduced-differently on purpose: matching *is* correct.

- Builder: `LATEXBuilder#inline_fn`, the `if @book.config['footnotetext']` branch
  (missing the `\protect` that the caption branch has).
- Question: add `\protect` there in the builder (and the renderer will follow),
  then `footnotetext`-mode heading footnotes become typesettable.

### 5. Table-cell leading-dot escaping is inconsistent between HTML and IDGXML (builder)

A cell whose content is `..15` (a leading `..`) renders differently depending on
the builder:

- HTMLBuilder unescapes it to `.15` (the `..` is a literal-dot escape);
- IDGXMLBuilder keeps it as `..15` (its row-level `parse_table_rows` only special-
  cases a cell that is *exactly* `.` or `..`, so `..15` with trailing content is
  left untouched).

The two oracles disagree on the same source, so a single AST tree cannot be
byte-identical to both. The AST compiler unescapes the cell at parse time
(`..15` → `.15`) — matching HTMLBuilder, and arguably the intended meaning of the
`..` escape. The IDGXML byte-exact sweep therefore reports this one cell as a
divergence (renderer `.15` vs builder `..15`), which we deliberately do **not**
match: reproducing `..15` would mean re-adding a dot in the IDGXML renderer to
mirror a builder quirk. Found via `FirstStepReVIEW-v3` (`review-introduction`);
`samples/syntax-book` does not exercise it.

- Builder: `IDGXMLBuilder#parse_table_rows` (`gsub("\t..\t", "\t.\t")` only, no
  general leading-`..` unescape) vs `HTMLBuilder`'s cell handling.
- Question: make the two builders agree on `..`-prefixed cells (unescape one
  leading dot in both), then the AST already matches and this entry goes away.

### 6. `@<href>` silently drops every field after the second (builder)

`Builder#inline_href` splits its argument on unescaped commas and keeps only
the first two fields: `@<href>{http://example.com, A, B}` links "A" and the
", B" is lost without a warning. (`\,` is the documented way to put a comma in
the label.) `Builder#inline_ruby`, by contrast, re-joins every field after the
first into the reading. The AST splits the same way (it uses the builder's own
regexp, `InlineProcessor::COMMA_FIELD_PATTERN`), so it drops the third field
too -- matching the builder is the parity target, but losing text silently is
suspicious.

- Builder: `Builder#inline_href` (`url, label = *arg.scan(...)`).
- Question: warn on (or keep) the extra fields in the builder, then the AST
  follows.

### 7. IDGXMLBuilder leaves `@<tcy>` text unescaped

IDGXMLBuilder has no `#inline_tcy`; it inherits `Builder#inline_tcy`, which
returns `"#{arg}[rotate 90 degree]"` with the argument *unescaped*, so
`@<tcy>{a&b}` writes a bare `&` into the XML. The AST renderer emits the same
"[rotate 90 degree]" marker but escapes the text (`a&amp;b`). This is a
deliberate non-match, invisible for the digits and short Latin runs `@<tcy>` is
used for.

- Builder: `Builder#inline_tcy` (generic fallback, used by IDGXMLBuilder).
- Question: give IDGXMLBuilder its own `#inline_tcy` that escapes (and perhaps
  emits real InDesign markup), then this entry goes away.

### 8. The text builders put `<link href>` markup into plain text

With `chapterlink` on (the default), `PLAINTEXTBuilder#inline_chapref` -- which
TOPBuilder inherits -- returns `<link href="ch01">第1章「章見出し」</link>`:
the IDGXML-style link element, in a plain-text format where it means nothing
and reads as garbage. The plaintext and TOP renderers print the reference text
alone. This is a deliberate non-match; the whole-book comparison
(`test/ast/test_maker_parity.rb`) strips the element from the builder's side
before comparing.

- Builder: `PLAINTEXTBuilder#inline_chapref` (the `chapterlink` branch).
- Question: drop the element in the text builders, then the strip in the test
  and this entry go away.

### 9. A table row is split into cells after its inline commands are compiled (builder)

`ReVIEW::Compiler` inline-compiles every line of a `//table` before
`Builder#parse_table_rows` splits it on `table_row_separator`. So the
separator is looked for in the *output* of the inline commands: TOP's
`@<balloon>{x}` returns `"\t←x"`, whose tab starts a new cell (and
`adjust_n_cols` then pads every other row with it); with
`table_row_separator: spaces`, `@<b>{a b}` is cut in two in every format. The
renderers split the row on the source text, so a command stays in its cell.
This is a deliberate non-match; the PBT generator keeps `@<balloon>` out of
table cells.

- Builder: `Builder#parse_table_rows` (and `Compiler#compile_block`, which
  compiles the lines first).
- Question: split the source line first and compile each cell, as the
  renderers do; then this entry goes away.
