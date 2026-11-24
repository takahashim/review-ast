# Re:VIEW AST semantics

This document is the specification of the tree (AST) that review-ast builds.
It defines what each node means, which source syntax produces it, how the
compile pipeline transforms the tree, where the AST intentionally diverges from
the legacy implementation, and what a re-implementation must satisfy to be
conformant.

It is written for a consumer of the serialized AST (JSON; the implementation is
`lib/review/ast/json_serializer.rb`) who wants to render or analyze Re:VIEW
documents without reading the Ruby source. General AST and compiler concepts
are assumed; knowledge of Re:VIEW is not. If Re:VIEW is new to you, the next
section ("Prerequisites") is enough to read the syntax columns that follow.

This is a living document. `test/ast/test_semantics_coverage.rb` keeps it
fresh: the test fails whenever the compiler learns a block command, a special
inline command, or a node type that this document does not mention. It pairs
with the Japanese version `doc/ast-semantics.ja.md`; the two cover the same
commands, nodes, and divergence entries.

## 0. Prerequisites: the Re:VIEW input language, and the parity-first rule

**Re:VIEW** is a lightweight markup language for writing technical books.
A book is written as one `.re` file per chapter and converted to PDF (via
LaTeX), EPUB, web pages (HTML), XML for DTP software (IDGXML), and plain text.

Three kinds of syntax cover everything that appears in a source file:

- **Heading lines**: the number of leading `=` characters gives the level
  (`= chapter`, `== section`, …). A heading can carry a label as `=={label}`
  and bracketed tags as `==[column]`.
- **Block commands**: a block spans from `//name[arg1][arg2]{` to `//}` (there
  is also a bodyless form `//name[arg]`). Code blocks, figures, tables, and
  footnotes are written this way.
- **Inline commands**: `@<name>{content}` inside body text. Bold (`@<b>`),
  code (`@<code>`), and cross-references (`@<img>` etc.) are written this way.

In the legacy Re:VIEW implementation, a per-format "builder" (LATEXBuilder,
HTMLBuilder, …) combines parsing with output generation. review-ast separates
the parsing out into an AST, and per-format renderers draw output from that
one tree.

The **parity-first** rule defines correctness of the AST pipeline, for now, as
"produces the same output as the legacy builders." The strictness of "same"
differs per format. LaTeX is DVI-identical (the comparison is between typeset
results (DVI files), not between the bytes of the TeX source), IDGXML is
byte-identical, and HTML is rendered-equivalent (equal as a browser rendering).
The only exceptions to the rule are the places listed in the
[divergence registry](#4-divergence-registry).

## 1. Node inventory

Every node carries a `type` and a source position `location` (`filename`,
`lineno`, `column`).
Nodes that can have children carry `children`.
**Leaf nodes** (the subclasses of the abstract base `LeafNode`: `TextNode`,
`ReferenceNode`, `ImageNode`, `TexEquationNode`, `EmbedNode`,
`ExtensionBlockNode`) are childless by
construction and emit no `children` key in JSON.

Three more common fields appear where applicable: `definition_number` on
numbered definition nodes ([section 2.3](#23-definition-numbering)), `noindent`
on the target of a `//noindent`, and a resolved `image_path` on image-bearing
nodes.

### Document structure

| Node | Meaning | Key fields | Produced by |
|---|---|---|---|
| `DocumentNode` | Whole chapter; the tree root | — | a compiled `.re` chapter |
| `HeadlineNode` | Heading | `level`, `label`, `tag` (`nonum`/`notoc`/`nodisp`), `raw_caption`, `caption_node` | `=`, `==`, … lines |
| `ColumnNode` | Column (a longer boxed article delimited with heading syntax) | `label`, `level`, `caption_node` | `===[column]` … `===[/column]` |
| `CaptionNode` | Caption of a block or heading | — | the caption argument of a block |

### Body text and inlines

| Node | Meaning | Key fields | Produced by |
|---|---|---|---|
| `ParagraphNode` | Paragraph | `noindent` | blank-line-separated text |
| `TextNode` | Literal text run | `content` | text |
| `InlineNode` | Inline command | `inline_type`, `args` | `@<b>{…}`, `@<code>{…}`, `@<img>{…}`, … |
| `ReferenceNode` | Cross-reference; resolved to a number or label at compile time | `ref_id`, `context_id`, `resolved_data` | the child of a reference `InlineNode` (e.g. `@<hd>`, `@<img>`, `@<fn>`) |

### Block elements

| Node | Meaning | Key fields | Produced by |
|---|---|---|---|
| `CodeBlockNode` | Verbatim and code blocks | `id`, `lang`, `code_type`, `line_numbers` | `//list`, `//listnum`, `//emlist`, `//emlistnum`, `//cmd`, `//source` |
| `CodeLineNode` | One line inside a code block; a branch rather than a leaf because it can contain inline markup | `line_number`, `original_text`, `children` | lines inside `//list` etc. |
| `ListNode` | List container | `list_type` (`ul`/`ol`/`dl`) | `*`, `1.`, `:` lines, `//ul`/`//ol`/`//dl` |
| `ListItemNode` | List item | `level`, `term_children` (the term side of a `dl`) | list items, `//li`/`//dt`/`//dd` |
| `ImageNode` | Image | `id`, `image_type`, `image_path`, `metric` | `//image`, `//indepimage`, `//numberlessimage` |
| `TableNode` | Table | `id`, `table_type` (`table`/`emtable`/`imgtable`), `tsize`, header rows | `//table`, `//emtable`, `//imgtable` |
| `TableRowNode` | Table row | — | table body and header lines |
| `TableCellNode` | Table cell | header flag | tab-separated cells |
| `MinicolumnNode` | Small admonition box | `minicolumn_type` | `//note`, `//memo`, `//tip`, `//info`, `//warning`, `//important`, `//caution`, `//notice` |
| `FootnoteNode` | Footnote and endnote definitions | `id`, `footnote_type` (`footnote`/`endnote`) | `//footnote`, `//endnote` |
| `TexEquationNode` | Display equation | `id`, `caption_node` | `//texequation` |
| `EmbedNode` | Raw pass-through for chosen builders. `embed_type` names the command: `:block` (`//embed`), `:raw` (`//raw`), `:inline` (`@<raw>`), `:inline_embed` (`@<embed>`); the raw ones turn a literal `\n` into a newline, the embed ones do not. A raw HTML block from Markdown input lands here too (`embed_type: :block`, html only) | `embed_type`, target builders, `content` | `//embed`, `@<embed>`, `//raw`, `@<raw>`, a Markdown HTML block |

### Generic blocks and transient nodes

| Node | Meaning | Key fields | Produced by |
|---|---|---|---|
| `BlockNode` | Generic block not specialized into a dedicated node | `block_type`, `args` | `//bibpaper`, `//graph`, `//box`, `//insn`, `//point`, `//term`, `//doorquote`, control commands, … |
| `ExtensionBlockNode` | A block command the book defines in `review-ext.rb` (`ReVIEW::Compiler.defblock`/`defsingle`/`defminicolumn`) and the AST has no handler for. Childless: it keeps what the legacy compiler hands the builder, and a renderer either implements `visit_block_<name>` or runs the review-ext.rb builder method ([doc/review-ext.md](review-ext.md)) | `block_type`, `args`, `lines` (raw body lines; absent for a single-line command) | any `//name` declared in review-ext.rb |
| `DirectiveNode` | Parser instruction that modifies the next node; always removed by lowering | `directive_type`, `args` | `//tsize`, `//firstlinenum`, `//noindent`, `//olnum`, `//beginchild`, `//endchild` |
| `LeafNode` | Abstract base for childless content nodes | — | never serialized directly |

## 2. Pipeline semantics

`Compiler#compile_to_ast(input)` takes a `CompileInput` (the source text plus a
service handle used for image and cross-chapter lookups) and produces the
observable tree through the following stages.

### 2.1 Surface tree → lowering passes → core tree

The direct output of parsing is called the **surface tree**.
It is faithful to the source: parser instructions that say "modify the next
node" (`//noindent` and friends) are still present as `DirectiveNode`s.

Two ordered stages then run as lowering passes (`Compiler#post_processors`;
each pass does exactly one thing, nanopass-style — the design history is in
doc/design-improvements #3).

- **Stage B**: mutually commutative directive micro-passes.
  Each pass takes one kind of directive, applies it to the "next eligible
  target" found among the following siblings, and deletes the directive.
  The pairings are `//tsize` → table, `//firstlinenum` → code block,
  `//noindent` → paragraph or quote, `//olnum` → ordered list.
  The search runs forward to the first eligible node, so it skips over nodes of
  other kinds (for example, `//noindent` still applies to the paragraph when a
  `//embed` sits between them).
  The directive kinds and target attributes each pass touches are disjoint, so
  the passes commute: any order yields the same tree (this commutativity is
  checked by a test).
- **Stage A**: order-dependent structural passes.
  These perform child-block nesting via `//beginchild`/`//endchild`, item
  numbering for ordered lists, and auto-id generation for
  `nonum`/`notoc`/`nodisp` headlines and columns.

The tree after lowering is called the **core tree**.
No `DirectiveNode` remains in the core tree (a leftover is a compile error);
each directive's effect lives on as fields of its target node.
Renderers and the serializer consume this core tree.
Reference resolution and image-path resolution are separate phases that run
only for a full (rendered) build.

### 2.2 Block separation

Adjacent blocks are modeled as distinct sibling nodes, and the compiler does
not merge or flatten across block boundaries.
Erasing block adjacency from the tree would force renderers to reconstruct it
by rewriting output strings (that class of bug is recorded in
doc/design-improvements #2).
A re-implementation must likewise keep block boundaries observable in the tree.

The only exceptions are two merges that match the legacy LATEXBuilder.
Consecutive definition lists separated by blank lines (`:` lines, `//dl`) merge
into one list.
And `//ul`/`//ol` continuations across `//beginchild`/`//endchild` merge into
the parent list (`ListStructureNormalizer`).

### 2.3 Definition numbering

Numbered definitions (`//list`, `//image`, `//table`, `//texequation`,
`//graph`, `//bibpaper`, footnotes) are numbered at compile time by the
Indexer, which stamps `definition_number` = `{number, chapter_number}` onto the
node.
For example, the first figure of chapter 2 carries
`{number: 1, chapter_number: "2"}`, so a renderer can print "図2.1" (Figure
2.1) without consulting any chapter index.

Unnumbered images (`//indepimage`, `//numberlessimage`) carry no
`definition_number`.
An `//imgtable` (a command that treats an image as a table) is numbered as a
table, but also carries an image-series number `imgtable_image_number` used for
the fallback rendering when the referenced image is missing.
The counter sharing (image and graph share one counter; the images of
indepimage, numberlessimage, and imgtable share another) matches the legacy
IndexBuilder (doc/design-improvements #1 and #7).

The chapter title is the first headline's `raw_caption` (the source-faithful
caption with markers and label stripped and inline markup kept raw), owned by
the AST.
It does not depend on the legacy book model (`BookUnit#title`).

### 2.4 The other input language: Markdown

Re:VIEW notation is not the only input. A chapter whose extension is `.md` is
handled by `MarkdownCompiler`, which `Compiler.for_chapter` selects by
extension. The dialect itself is documented in `doc/ast_markdown.ja.md`.

What matters here is that Markdown replaces only the construction of the
surface tree. `MarkdownCompiler` overrides the parent's
`build_ast_from_chapter` and nothing else, so the lowering passes, numbering,
auto ids, reference resolution and image path resolution are all inherited. A
`.md` chapter's core tree therefore satisfies the same contract as a `.re`
one (2.1 through 2.3), and renderers downstream do not distinguish the two.

No node type was added for Markdown. Its constructs map onto existing nodes: a
raw HTML block becomes an `EmbedNode` (`embed_type: :block`, html only) and a
thematic break becomes `BlockNode(:hr)`. Definition lists are not read from
Markdown input -- they parse as paragraphs; `ListNode(list_type: :dl)` comes
from Re:VIEW's `: term`, and on the Markdown side it is an output concern.

Re:VIEW inline notation such as `@<img>{id}` may be written inside Markdown.
It is not interpreted on the Markdown side: the adapter hands it to the same
`InlineProcessor` the `.re` path uses, so the same notation cannot build
different nodes depending on the input language.

## 3. Command reference

The complete command set the compiler recognizes is the fixed block-command
set (`BLOCK_COMMAND_TABLE`) and the special-inline-command set
(`DEFAULT_INLINE_HANDLERS`).
Both are enumerated here so the coverage test can map every command to this
document.

### 3.1 Block commands

- Code blocks (become `CodeBlockNode`):
  `//list` (numbered), `//listnum` (numbered, with line numbers), `//emlist`
  (unnumbered), `//emlistnum` (line numbers only), `//cmd` (command line),
  `//source` (code with an origin caption).
- Images (`ImageNode`):
  `//image` (numbered), `//indepimage` (unnumbered), `//numberlessimage`
  (ditto).
- Tables (`TableNode`):
  `//table` (numbered), `//emtable` (unnumbered), `//imgtable` (an image
  numbered as a table).
- Lists (`ListNode`/`ListItemNode`):
  `//ul`, `//ol`, `//dl`, `//li`, `//dt`, `//dd`.
  Lists are normally written with line syntax such as `*`; these block forms
  are auxiliary.
- Mini columns (`MinicolumnNode`):
  `//note`, `//memo`, `//tip`, `//info`, `//warning`, `//important`,
  `//caution`, `//notice`.
  The kinds differ but the structure is identical; only `minicolumn_type`
  varies.
- Column (`ColumnNode`): `//column`.
- Footnotes (`FootnoteNode`): `//footnote` (footnote), `//endnote`
  (chapter-end endnote).
- Equations (`TexEquationNode`): `//texequation`.
- Pass-through (`EmbedNode`): `//embed`, `//raw`.
- Quote-like blocks (`BlockNode`):
  `//read`, `//quote`, `//blockquote`, `//lead`, `//centering`,
  `//flushright`, `//address`, `//talk`.
- Other blocks (`BlockNode`):
  `//doorquote` (door-page quote), `//bibpaper` (bibliography entry),
  `//graph` (figure generated by an external tool), `//box`, `//insn`,
  `//point`, `//term`; `//bpo` and `//rawblock` (IDGXML only) keep their body
  line by line, as `//box` does.
- Control commands (`BlockNode`):
  `//comment`, `//blankline`, `//pagebreak`, `//label`, `//printendnotes`,
  `//hr`, `//parasep`.
- Directives (`DirectiveNode`; removed by lowering):
  `//olnum`, `//noindent`, `//firstlinenum`, `//tsize`, `//beginchild`,
  `//endchild`.

### 3.2 Special inline commands

These commands have dedicated handlers.
The tree shape differs by group.

- Pass-through; becomes an `EmbedNode` directly: `@<embed>`, `@<raw>`.
- A plain `InlineNode` (`inline_type` is the command name, the args carry the
  payload): `@<ruby>` (ruby annotation), `@<href>` (link), `@<kw>` (keyword).
- References.
  An `InlineNode` (`inline_type: :img`, `:fn`, …) wraps a `ReferenceNode`
  child holding `ref_id`/`context_id`/`resolved_data`:
  `@<img>`, `@<imgref>`, `@<list>`, `@<table>`, `@<eq>`, `@<fn>`,
  `@<endnote>`, `@<column>`, `@<w>`, `@<wb>`, `@<bib>`, `@<bibref>`.
- Cross references; the same tree shape as references:
  `@<hd>` (heading), `@<chap>` (chapter number), `@<chapref>` (chapter),
  `@<title>` (chapter title), `@<sec>` (section number), `@<secref>`
  (section), `@<sectitle>` (section title), `@<labelref>`, `@<ref>`.

Every other `@<name>{…}` (`@<b>`, `@<i>`, `@<code>`, `@<tt>`, `@<bou>`
(sesame dots), `@<ami>` (shaded background), `@<u>`, `@<em>`, `@<strong>`, …)
becomes a decoration `InlineNode` whose `inline_type` is the command name.
The renderer's `render_inline_<name>` decides its output; the tree shape is
identical for all of them.

## 4. Divergence registry

Even under the parity-first rule, a small number of places produce output that
differs from the legacy builders.
This section is the ledger that records every one of them.

Each entry carries a **compat class** (the classification from
doc/design-improvements #6).
**Fix-now** means no working document can depend on the behaviour (for
example, it only ever produced un-typesettable output).
**Gate** means the behaviour is wrong but documents may depend on it, so the
old behaviour should stay available behind a `review_version` declaration.
**Canonicalize** means the behaviour is established and harmless, and is
adopted as the specification.

Rows 1 and 4 below are cases where the AST reproduces the builder behaviour
byte-for-byte (triaged as spec questions in `doc/spec-questions.md`, awaiting
an upstream (kmuto/review) ruling).
Rows 2, 3, and 5 are cases the AST deliberately does not reproduce, because
the builder behaviour is a bug or a builder-specific quirk.

| # | Syntax | Builder behaviour | AST behaviour | Suspected class | Upstream |
|---|---|---|---|---|---|
| 1 | Part heading TOC name | `part` for a starred Part, `chapter` for a `[nonum]` Part | reproduces the builder | canonicalize? | open |
| 2 | Table cell rendering empty via `@<comment>` | the empty-rendering cell collapses, shifting the row (a LATEXBuilder bug) | does not reproduce: keeps the correctly split row | fix-now | open |
| 3 | Table header/body separator threshold | LATEXBuilder detects on the escaped line, so 4–11 dashes already split | does not reproduce: uses the 12-dash threshold (same as HTML), so 4–11 dashes stay data | gate | open |
| 4 | `footnotetext: true` + footnote in a heading | emits an unprotected `\footnotemark` (un-typesettable) | reproduces the builder byte-for-byte | fix-now | open |
| 5 | Table-cell leading-dot escaping | HTMLBuilder unescapes `..15`→`.15`; IDGXMLBuilder keeps `..15` | normalizes to `.15` (matches HTML; intentionally incompatible with IDGXML byte-exactness) | fix-now | open |
| 6 | Fields after the second in `@<href>` | dropped without a warning (`@<ruby>` joins them into the reading) | reproduces the builder (same splitting regexp) | canonicalize? | open |
| 7 | `@<tcy>` in IDGXML | the generic `Builder#inline_tcy` writes the text unescaped | emits the same `[rotate 90 degree]` note but escapes the text (intentionally incompatible) | fix-now | open |
| 8 | `@<chapref>` in the text formats | with `chapterlink` on, writes a `<link href="…">` element into plain text | prints the reference text alone (intentionally incompatible) | fix-now | open |

No command is left unimplemented in a renderer whose builder supports it:
`//graph` (external-tool image) now runs the generator and renders the image in
every format, as Builder#graph does, and `@<w>`/`@<wb>` match the builders in
every format, including loading `words_file` and degrading an unknown word to
`[missing word: id]`.

One non-divergent point worth stating: the interpretation of `//tsize` (table
column widths) differs per format.
IDGXML reads the numeric CSV from the source directly, and a LaTeX column spec
(`|l|c|r|`) is ignored by IDGXML (equal distribution).
This is identical to the builder behaviour (doc/design-improvements #5).

## 5. Conformance criteria

A re-implementation is conformant for a given source (and, once version gating
exists, a `review_version`) when, stage by stage, it satisfies:

1. **Surface tree**:
   parsing the source yields the same surface tree, with the same node types
   and fields (and schema-valid against the serialized format).
2. **Core tree**:
   after lowering, it yields the same core tree.
   That is, no `DirectiveNode` remains, directive effects live on the target
   nodes' fields, and the numbering of
   [section 2.3](#23-definition-numbering) is done.
3. **Rendering**:
   per format, it yields the same output at that format's strictness.
   LaTeX is DVI-identical, IDGXML is byte-identical, HTML is
   rendered-equivalent. plaintext and TOP are not held to byte equality but to
   semantic correctness: blank-line placement, table rule width and nested-list
   indentation may differ from the builders (design-improvements item 9, "the
   differences kept on purpose").

Version handling follows this design intent.
Semantics are version-independent by default; only triaged divergence points
will carry a `review_version` range (planned).
The node schema never forks on version; forks live only in compiler and
renderer behaviour.
Today the dump envelope records only `ast_format` and a `generator` string
naming the producer (e.g. `review 5.11.0`); a dedicated `review_version` field
and the version gating are not yet implemented.

The executable conformance kit is the serialized-AST schema, the samples and
PBT corpora, and the differential comparators (`tools/compare_book.rb` for
DVI, the IDGXML and HTML sweeps) — all runnable without reading the Ruby
source.
