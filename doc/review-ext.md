# review-ext.rb and the AST path

Many Re:VIEW books carry a `review-ext.rb` next to `config.yml`. Re:VIEW loads it
when the book is opened, and it usually does two things:

1. declares syntax on the compiler —
   `ReVIEW::Compiler.defblock :mybox, 0..1`, `defsingle :mymark, 1`,
   `definline :mykbd`;
2. implements that syntax on one or more builders —
   `HTMLBuilder#mybox(lines, caption = nil)`, `LATEXBuilder#inline_mykbd(str)`,
   … — or redefines a builder method that already exists.

The AST path loads the same file (it opens the book with Re:VIEW's own
`Book::Base`), and honours both parts. This page says what is supported, what is
not, and how to write an extension against the AST renderers directly.

Builder methods are run for backward compatibility only, and this support will
be removed in a future version, once an extension can be written for the
renderers alone (the plan is in
[design-extension-api.ja.md](design-extension-api.ja.md)). Write new
extensions [for the renderers](#writing-an-extension-for-the-ast-renderers).

## What works unchanged

| review-ext.rb | Through the AST path |
|---|---|
| `defblock` / `defsingle` / `defminicolumn` + `XXXBuilder#name(lines, *args)` | The command becomes an `ExtensionBlockNode` (arguments and raw body lines). The renderer for that format calls the builder method exactly as `ReVIEW::Compiler` would — each body line inline-compiled by the builder, then `name(lines, *args)`, or `name(*args)` for a single-line command — and inserts what it wrote. |
| `definline` + `XXXBuilder#inline_name(str)` | The inline is an ordinary `InlineNode`; the renderer calls `inline_name` with the raw argument and inserts the result. |
| Redefining an inline command (`def inline_b(str)`, `def inline_ruby(str)`, `def inline_href(str)`, a reference such as `def inline_list(id)`, …) | The redefinition is used, as in the legacy path, called with the argument exactly as the legacy compiler passes it. |
| Redefining a built-in block command (`def emlist(lines, caption, lang)`, `def list(...)`, `def table(...)`, `def quote(lines)`, …) | The redefinition writes the block, called as `ReVIEW::Compiler` would call it (body lines inline-compiled by the builder, the bracketed arguments raw). The AST still numbers and indexes the block, so `@<list>{id}` and the like keep resolving. |
| Redefining a minicolumn's ends (`def note_begin(caption)`, `def note_end`) | Used for the two ends, as the legacy compiler uses them for `//note{ … //}`; the content in between is rendered by the AST renderer. |
| Argument counts and body rules of `defblock`/`defsingle` | Checked the same way (`check_args`; "block is required" / "block is not allowed"). |
| A command the builder for the target format does not implement | An error, `builder does not support command: //name`, as in the legacy path. |

Formats map to builders as the legacy makers use them: HTML (and EPUB/Web) →
`HTMLBuilder`, LaTeX → `LATEXBuilder`, IDGXML → `IDGXMLBuilder`, plaintext →
`PLAINTEXTBuilder`, TOP → `TOPBuilder`. The Typst renderer has no legacy
builder; see below.

Only methods defined *outside* the `review` and `review-ast` gems are treated as
extensions — that is how a review-ext.rb method is told apart from the builder's
own.

Calling a builder method has a cost: the AST path binds a builder, and
Re:VIEW's `Builder#bind` then indexes the chapter and the whole book with the
legacy compiler (`generate_indexes`, once per chapter), as `review-compile`
does. References a builder method resolves (`@chapter.list(id)`, an `@<list>`
compiled by `compile_inline`) read that legacy index, not the AST's numbering.
A book whose review-ext.rb defines no builder methods never pays this.

`review-ast-dump` keeps an extension block in the JSON (`ExtensionBlockNode`
with `block_type`, `args`, `lines`) and `review-ast-dump2re` writes it back as
it was.

To call a redefinition with the arguments the legacy compiler would pass, each
node keeps the command in that form while the chapter is rendered
(`Node#source_command`, `InlineNode#source_arg`). This is not part of the JSON
dump, so a tree rendered from `review-ast-dump` output does not use
redefinitions of built-in commands.

## What is not picked up

Redefinitions of the structure the AST renders itself are not used, because
the AST does not go through those builder methods:

- structural hooks (`headline`, `paragraph`, `ul_item`, `ol_item`, `dt`, `dd`,
  `column_begin`, `column_end`, `result`, …);
- the parser directives the AST lowers onto the next block (`noindent`,
  `olnum`, `firstlinenum`, `tsize`, `beginchild`, `endchild`);
- any other method of Re:VIEW's builder that is not a command, a
  minicolumn's `_begin`/`_end` or an `inline_*` method: the helpers the
  builders' own commands call, such as `table_begin`, `image_header` or
  `list_header`.

Each such redefinition is reported once per run with a warning:

```text
review-ext.rb redefines HTMLBuilder#headline, which the AST renderer does not call, so it has no effect (see doc/review-ext.md)
```

The AST path has no review-ext.rb hook for these. Change how they look with
CSS (HTML, EPUB), a `.sty` (LaTeX) or the templates. Reopening the renderer's
own method (`visit_headline`) does take effect, but is not a supported
extension point (see
[Renderer methods are not a stable interface](#renderer-methods-are-not-a-stable-interface)).

Redefining `def note(lines, caption)` itself has no effect in either path: the
legacy compiler, too, renders `//note{ … //}` through `note_begin` / `note_end`.

Helper methods that only your own extension methods call are not reported.

## Writing an extension for the AST renderers

A renderer method takes precedence over the builder method, in every format
(except inside a block a builder method renders; see below), and is the only
option for Typst (which has no legacy builder). Declare the
command as for the legacy path, then define the method in review-ext.rb
(requiring the renderer first):

```ruby
ReVIEW::Compiler.defblock :mybox, 0..1
ReVIEW::Compiler.definline :mykbd

require 'review/renderer/html_renderer'

module ReVIEW
  module Renderer
    class HtmlRenderer
      # //mybox[caption]{ ... //}  (an ExtensionBlockNode)
      def visit_block_mybox(node)
        caption = node.args.first
        body = node.lines.map { |line| escape(line) }.join("\n")
        %Q(<aside class="mybox" title="#{escape(caption.to_s)}">#{body}</aside>\n)
      end

      # @<mykbd>{...}
      def render_inline_mykbd(_type, content, _node)
        %Q(<kbd>#{content}</kbd>)
      end
    end
  end
end
```

- `visit_block_<name>(node)` receives the `ExtensionBlockNode`: `node.args`,
  `node.lines`, `node.body?`, `node.location`.
  `node.lines` holds the body's raw source lines (`nil` for a
  single-line `defsingle` command): the AST does not parse an extension
  block's body, so inline commands in it are not rendered. In the example,
  `@<b>{x}` in a `//mybox` body comes out as the literal text `@<b>{x}`. A
  builder method, by contrast, receives the lines inline-compiled by the
  builder. (Bodies parsed into nodes are planned; see
  [design-extension-api.ja.md](design-extension-api.ja.md).)
- `render_inline_<name>(type, content, node)` receives the inline's rendered
  (escaped) content; `node.args.first` is the raw argument. It is enough on
  its own wherever the renderer renders the text: the builder for that format
  needs no `inline_<name>` as well.
  The exception is a block a builder method renders — an extension block
  implemented on the builder, or a built-in command review-ext.rb redefined
  there (`def emlist`). Its body is inline-compiled by the builder, as in
  the legacy path, and so is a caption the builder method passes to
  `compile_inline`; an inline used there needs `inline_<name>` on the
  builder, and without it is an error that names the method to add
  (`builder does not support inline op: @<name> (inside //mybox, which
  HTMLBuilder renders; define HTMLBuilder#inline_name in review-ext.rb)`).
  When both methods exist,
  the builder's is used inside such a block and the renderer's elsewhere.
- Either way the command has to be declared (`ReVIEW::Compiler.defblock`,
  `definline`, …): as in the legacy compiler, a command nobody declared is a
  compile error (`no such inline op: mykbd`), in every format.

The same applies to `LatexRenderer`, `IdgxmlRenderer`, `PlaintextRenderer`,
`TopRenderer` and `TypstRenderer`. For a command, the order is:

1. the renderer's `visit_block_<name>` / `render_inline_<name>`;
2. the builder method review-ext.rb defined (`name` / `inline_name`);
3. otherwise an error, `builder does not support command: //name` (or
   `inline op: @<name>`).

### Renderer methods are not a stable interface

Only `visit_block_<name>` and `render_inline_<name>` for a command
review-ext.rb declared are supported extension points. Everything else on a
renderer is internal:

- Reopening a renderer lets you replace any of its methods, including those
  that render built-in commands (`visit_block_box`, `visit_headline`, …). A
  `render_inline_<name>` named after a built-in inline (`render_inline_b`) is
  used too, in every format (outside a block a builder method renders). Such
  replacements are not checked or reported, unlike a builder redefinition
  the AST does not call, and may break when the renderer changes. To change a
  built-in command, redefine it on the builder instead (see
  [What works unchanged](#what-works-unchanged)). The structure of the
  document (headings, paragraphs, list items, …) has no supported hook (see
  [What is not picked up](#what-is-not-picked-up)).
- Helpers an extension method calls, such as `escape` and `render_children`,
  are the renderer's own and carry no compatibility promise.

## Testing

`test/ast/test_review_ext_compat.rb` builds a small book with a review-ext.rb
through `review-compile` and `review-ast-compile` and requires the HTML, LaTeX
and IDGXML output to match. It also checks that a renderer's
`render_inline_<name>` works in all six formats. (review-ext.rb reopens classes
for the rest of the process, so those builds run in child processes.)
