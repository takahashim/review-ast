# Re:VIEW AST semantics

This document is the builder-independent specification of the review-ast tree:
what each node means, which source syntax produces it, how the compile pipeline
transforms the tree, where the AST intentionally diverges from the legacy
Re:VIEW builders, and what a re-implementation must satisfy to be conformant.

It is written for a consumer of the serialized AST (see the JSON format in
`lib/review/ast/json_serializer.rb`) who wants to render or analyze Re:VIEW
documents without reading the Ruby source. The parity-first project rule holds
for the implemented syntax: the AST reproduces the builders' output
(DVI-identical for LaTeX, byte-identical for IDGXML, rendered-equivalent for
HTML) except where the [divergence registry](#4-divergence-registry) says
otherwise, and except for a few commands not yet implemented in a renderer
(`//graph` and `@<w>`/`@<wb>` in the LaTeX renderer — see the divergence
registry).

Status: living document, with a Japanese companion `doc/ast-semantics.ja.md`
kept in sync. Both are kept fresh by `test/ast/test_semantics_coverage.rb`, which
fails if the compiler learns a block or special-inline command, or a node type,
that either file does not mention.

## 1. Node inventory

Every node carries a `type` and a source `location` (`filename`, `lineno`,
`column`). Branch nodes carry `children`; leaf nodes (the `LeafNode` subclasses
`TextNode`, `ReferenceNode`, `ImageNode`, `TexEquationNode`, `EmbedNode`) emit no
`children` key. Numbered definition nodes also carry a `definition_number` (see
[numbering](#23-definition-numbering)); a `//noindent` target carries `noindent`;
an image-bearing node carries a resolved `image_path`.

| Node | Meaning | Key fields | Produced by |
|---|---|---|---|
| `DocumentNode` | Whole chapter; tree root | — | a compiled `.re` chapter |
| `HeadlineNode` | Heading | `level`, `label`, `tag` (`nonum`/`notoc`/`nodisp`), `raw_caption`, `caption_node` | `=`, `==`, … lines |
| `ParagraphNode` | Paragraph | `noindent` | blank-line-separated text |
| `TextNode` | Literal text run | `content` | text; a `LeafNode` |
| `CodeLineNode` | One line inside a code block | `line_number`, `original_text`, `children` (inline markup) | lines inside `//list` etc. (a branch node, not a leaf) |
| `InlineNode` | Inline command | `inline_type`, `args` | `@<b>{…}`, `@<code>{…}`, `@<img>{…}`, … |
| `ReferenceNode` | Cross-reference (resolved to a number/label at compile time) | `ref_id`, `context_id`, `resolved_data` | the child of the reference's `InlineNode` (e.g. `@<hd>`, `@<img>`, `@<fn>`) |
| `CaptionNode` | Caption of a block/heading | — | the caption argument of a block |
| `ListNode` | List container | `list_type` (`ul`/`ol`/`dl`) | `*`, `1.`, `:` lines and `//ul`/`//ol`/`//dl` |
| `ListItemNode` | List item | `level`, `term_children` (for `dl`) | list items, `//li`/`//dt`/`//dd` |
| `CodeBlockNode` | Verbatim/code block | `id`, `lang`, `code_type`, `line_numbers` | `//list`, `//listnum`, `//emlist`, `//emlistnum`, `//cmd`, `//source` |
| `ImageNode` | Image | `id`, `image_type`, `image_path`, `metric` | `//image`, `//indepimage`, `//numberlessimage` |
| `TableNode` | Table | `id`, `table_type` (`table`/`emtable`/`imgtable`), `tsize`, header rows | `//table`, `//emtable`, `//imgtable` |
| `TableRowNode` | Table row | — | a table body/header line |
| `TableCellNode` | Table cell | header flag | tab-separated cells |
| `MinicolumnNode` | Admonition/mini column | `minicolumn_type` | `//note`, `//memo`, `//tip`, `//info`, `//warning`, `//important`, `//caution`, `//notice` |
| `ColumnNode` | Column (sidebar section) | `label`, `level`, `caption_node` | `===[column]` … `===[/column]` |
| `FootnoteNode` | Footnote/endnote definition | `id`, `footnote_type` (`footnote`/`endnote`) | `//footnote`, `//endnote` |
| `TexEquationNode` | Display equation | `id`, `caption_node` | `//texequation` |
| `EmbedNode` | Raw pass-through for chosen builders | `embed_type`, target builders | `//embed`, `@<embed>`, `//raw`, `@<raw>` |
| `BlockNode` | Generic block not lowered to a specific node | `block_type`, `args` | `//bibpaper`, `//graph`, `//box`, `//insn`, `//point`, `//term`, `//doorquote`, control commands, … |
| `DirectiveNode` | A `//directive` that modifies the next node; removed by lowering | `directive_type`, `args` | `//tsize`, `//firstlinenum`, `//noindent`, `//olnum`, `//beginchild`, `//endchild` |
| `MarkdownHtmlNode` | Raw HTML inside Markdown | `html_content`, `html_type` | Markdown source (Markdown compiler not wired yet) |
| `LeafNode` | Abstract base for childless content nodes | — | never serialized directly |

## 2. Pipeline semantics

`Compiler#compile_to_ast(input)` takes a `CompileInput` (source text plus a
service handle for image/cross-chapter lookups) and produces the tree in three
observable stages.

### 2.1 Surface tree → lowering passes → core tree

Parsing yields a *surface tree* that still contains `DirectiveNode`s for
`//directive` markers that modify a following node. Two ordered stages then run
(`Compiler#post_processors`, decomposed nanopass-style — see
doc/design-improvements #3):

- Stage B — commutative directive micro-passes. Each lowers one directive onto
  the next eligible target among its following siblings — it searches forward, so
  it can skip an intervening node (e.g. `//noindent` applies to the paragraph even
  when a `//embed` sits between them): `//tsize`→table, `//firstlinenum`→code,
  `//noindent`→paragraph/quote, `//olnum`→ordered list. Their targets are
  disjoint, so they commute (every shuffle yields the same core tree).
- Stage A — order-dependent structural passes: child nesting via
  `//beginchild`/`//endchild`, ordered-list item numbering, and auto-id
  generation for `nonum`/`notoc`/`nodisp` headlines and columns.

The result is the *core tree*: no `DirectiveNode`s remain; their effect lives as
fields on the target nodes. Reference resolution and image-path resolution run
in a separate phase and only for a full (rendered) build.

### 2.2 Block separation

Adjacent blocks are modeled as distinct sibling nodes; the compiler does not
merge or flatten across block boundaries (which is the class of bug this avoids —
see doc/design-improvements #2). A re-implementation must keep block boundaries
observable in the tree. The exceptions match LATEXBuilder: consecutive
blank-line-separated definition lists (`:` / `//dl`) merge into one list, and
`//ul`/`//ol` continuations across `//beginchild`/`//endchild` merge into the
parent list (`ListStructureNormalizer`).

### 2.3 Definition numbering

Numbered definitions (`//list`, `//image`, `//table`, `//texequation`, `//graph`,
`//bibpaper`, footnotes) are numbered at compile time by the Indexer and stamped
as `definition_number` = `{number, chapter_number}` on the node, so a renderer
needs no chapter index to print "図2.1". `//indepimage` and `//numberlessimage`
are unnumbered and carry no `definition_number`. An `//imgtable` is numbered as a
table (`definition_number`) but also carries a separate `imgtable_image_number`
for the fallback rendering of an unbound image. Counters and their sharing
(image/graph share one; indepimage/numberlessimage/imgtable-image share another)
mirror the legacy IndexBuilder. See doc/design-improvements #1 and #7.

The chapter title is the first headline's `raw_caption` (the source-faithful
caption of the first heading, markers/label stripped, inline markup kept raw),
owned by the AST rather than the gem's `BookUnit#title`.

## 3. Command reference

The compiler recognizes a fixed set of block commands (`BLOCK_COMMAND_TABLE`)
and special inline commands (`DEFAULT_INLINE_HANDLERS`). Both are enumerated here
so the coverage test can map every command to documented semantics.

### 3.1 Block commands

- Code blocks (`CodeBlockNode`): `//list`, `//listnum`, `//emlist`, `//emlistnum`,
  `//cmd`, `//source`.
- Images (`ImageNode`): `//image`, `//indepimage`, `//numberlessimage`.
- Tables (`TableNode`): `//table`, `//emtable`, `//imgtable`.
- Lists (`ListNode`/`ListItemNode`): `//ul`, `//ol`, `//dl`, `//li`, `//dt`,
  `//dd`.
- Mini columns (`MinicolumnNode`): `//note`, `//memo`, `//tip`, `//info`,
  `//warning`, `//important`, `//caution`, `//notice`.
- Column (`ColumnNode`): `//column`.
- Footnotes (`FootnoteNode`): `//footnote`, `//endnote`.
- Equations (`TexEquationNode`): `//texequation`.
- Pass-through (`EmbedNode`): `//embed`, `//raw`.
- Quote-like blocks (`BlockNode`): `//read`, `//quote`, `//blockquote`, `//lead`,
  `//centering`, `//flushright`, `//address`, `//talk`.
- Other blocks (`BlockNode`): `//doorquote`, `//bibpaper`, `//graph`, `//box`,
  `//insn`, `//point`, `//term`.
- Control commands (`BlockNode`): `//comment`, `//blankline`, `//pagebreak`,
  `//label`, `//printendnotes`, `//hr`, `//bpo`, `//parasep`.
- Directives (`DirectiveNode`, lowered away): `//olnum`, `//noindent`,
  `//firstlinenum`, `//tsize`, `//beginchild`, `//endchild`.

### 3.2 Special inline commands

These have a dedicated handler; the tree shape differs by group.

- Pass-through, a direct `EmbedNode`: `@<embed>`, `@<raw>`.
- A plain `InlineNode` (`inline_type` = the command; the args carry the payload):
  `@<ruby>`, `@<href>`, `@<kw>`.
- References — an `InlineNode` (`inline_type: :img`, `:fn`, …) that wraps a
  `ReferenceNode` child holding `ref_id`/`context_id`/`resolved_data`: `@<img>`,
  `@<imgref>`, `@<list>`, `@<table>`, `@<eq>`, `@<fn>`, `@<endnote>`, `@<column>`,
  `@<w>`, `@<wb>`, `@<bib>`, `@<bibref>`.
- Cross references — the same `InlineNode` + `ReferenceNode` shape: `@<hd>`,
  `@<chap>`, `@<chapref>`, `@<title>`, `@<sec>`, `@<secref>`, `@<sectitle>`,
  `@<labelref>`, `@<ref>`.

Any other `@<name>{…}` (`@<b>`, `@<i>`, `@<code>`, `@<tt>`, `@<bou>`, `@<ami>`,
`@<u>`, `@<em>`, `@<strong>`, …) becomes a decoration `InlineNode` whose
`inline_type` is `name`; the renderer's `render_inline_<name>` decides its
output.

## 4. Divergence registry

Differences from the legacy builders. Rows 1 and 4 are cases the AST reproduces
byte-for-byte (a triaged spec question, `doc/spec-questions.md`, awaiting an
upstream ruling). Rows 2, 3 and 5 are cases the AST deliberately does *not*
reproduce, because the builder behaviour is a bug or a builder-specific quirk.
Compat classes (from doc/design-improvements #6): *fix-now* (no document can
depend on it), *gate* (`review_version`-guarded), *canonicalize* (adopt as spec).

| # | Syntax | Builder behaviour | AST behaviour | Suspected class | Upstream |
|---|---|---|---|---|---|
| 1 | Part heading TOC name | `part` for a starred Part, `chapter` for a `[nonum]` Part | reproduces the builder | canonicalize? | open |
| 2 | Table cell rendering empty via `@<comment>` | the empty-rendering cell collapses, shifting the row (LATEXBuilder bug) | does NOT reproduce: keeps the correctly split row | fix-now | open |
| 3 | Table header/body separator threshold | LATEXBuilder detects on the *escaped* line, so 4–11 dashes already split | does NOT reproduce: uses the 12-dash threshold (like HTML), so 4–11 dashes stay data | gate | open |
| 4 | `footnotetext: true` + footnote in a heading | emits an unprotected `\footnotemark` (un-typesettable) | reproduces the builder byte-for-byte | fix-now | open |
| 5 | Table-cell leading-dot escaping | HTMLBuilder unescapes `..15`→`.15`; IDGXMLBuilder keeps `..15` | unescapes to `.15` (matches HTML; intentionally diverges from IDGXML byte-exact) | fix-now | open |

Known unimplemented (not yet a renderer difference to reproduce, just missing —
see `doc/differential-testing.md`): `//graph` (external-tool image) and
`@<w>`/`@<wb>` (dictionary word substitution) are not implemented in the AST
LaTeX renderer.

Non-divergent but worth stating: `//tsize` for IDGXML reads the source numeric
CSV directly, and a LaTeX column spec (`|l|c|r|`) is ignored for IDGXML (equal
distribution) — identical to the builder (doc/design-improvements #5).

## 5. Conformance criteria

A re-implementation is conformant for a given source (and, once version gating
exists, a `review_version`) when, stage by stage:

1. Surface tree — parsing the source yields the same surface tree (schema-valid
   against the serialized format), same node types and fields.
2. Core tree — after lowering, the same core tree (no `DirectiveNode`s; directive
   effects on target-node fields; the numbering of 2.3).
3. Rendering — per format, the same output at that format's strictness: LaTeX
   DVI-identical, IDGXML byte-identical, HTML rendered-equivalent, plaintext/TOP
   byte-identical.

Version handling (design intent): semantics are version-independent except at
triaged divergence points, which would carry a `review_version` range. The node
schema never forks on version; only compiler/renderer behaviour does. Today the
dump envelope records only `ast_format` and a `generator` string (which names the
generating review version, e.g. `review 5.11.0`); a dedicated `review_version`
field and the version gating are not yet implemented.

The executable conformance kit is the serialized-AST schema, the sample/PBT
corpus, and the differential comparators (`tools/compare_book.rb` for DVI, the
IDGXML/HTML sweeps) — runnable without reading the Ruby source.
