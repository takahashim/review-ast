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

## What works unchanged

| review-ext.rb | Through the AST path |
|---|---|
| `defblock` / `defsingle` / `defminicolumn` + `XXXBuilder#name(lines, *args)` | The command becomes an `ExtensionBlockNode` (arguments and raw body lines). The renderer for that format calls the builder method exactly as `ReVIEW::Compiler` would — each body line inline-compiled by the builder, then `name(lines, *args)`, or `name(*args)` for a single-line command — and inserts what it wrote. |
| `definline` + `XXXBuilder#inline_name(str)` | The inline is an ordinary `InlineNode`; the renderer calls `inline_name` with the raw argument and inserts the result. |
| Redefining a plain inline (`def inline_b(str)`, `def inline_u(str)`, …) | The redefinition is used, as in the legacy path. |
| Argument counts and body rules of `defblock`/`defsingle` | Checked the same way (`check_args`; "block is required" / "block is not allowed"). |
| A command the builder for the target format does not implement | An error, `builder does not support command: //name`, as in the legacy path. |

Formats map to builders as the legacy makers use them: HTML (and EPUB/Web) →
`HTMLBuilder`, LaTeX → `LATEXBuilder`, IDGXML → `IDGXMLBuilder`, plaintext →
`PLAINTEXTBuilder`, TOP → `TOPBuilder`. The Typst renderer has no legacy
builder; see below.

Only methods defined *outside* the `review` and `review-ast` gems are treated as
extensions — that is how a review-ext.rb method is told apart from the builder's
own.

`review-ast-dump` keeps an extension block in the JSON (`ExtensionBlockNode`
with `block_type`, `args`, `lines`) and `review-ast-dump2re` writes it back as
it was.

## What is not picked up

Redefinitions of things the AST renders itself are **not** used, because the
AST does not go through those builder methods:

- built-in block commands (`def note`, `def list`, `def table`, …);
- special inline commands whose argument the AST parses into fields
  (`inline_ruby`, `inline_href`, `inline_kw`, and the reference commands such
  as `inline_img`, `inline_hd`, `inline_chap`);
- structural hooks (`headline`, `paragraph`, `ul_item`, `column_begin`,
  `result`, …).

Each such redefinition is reported once per run with a warning:

```text
review-ext.rb redefines HTMLBuilder#note, which the AST renderer does not call; implement it on the renderer instead (see doc/review-ext.md)
```

Helper methods that only your own extension methods call are not reported.

## Writing an extension for the AST renderers

A renderer method takes precedence over the builder method, and is the only
option for Typst. Define it in review-ext.rb (requiring the renderer first):

```ruby
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
  `node.lines` (raw source lines, `nil` for a single-line command),
  `node.body?`, `node.location`.
- `render_inline_<name>(type, content, node)` receives the inline's rendered
  (escaped) content; `node.args.first` is the raw argument.

The same applies to `LatexRenderer`, `IdgxmlRenderer`, `PlaintextRenderer`,
`TopRenderer` and `TypstRenderer`.

## Testing

`test/ast/test_review_ext_compat.rb` builds a small book with a review-ext.rb
through `review-compile` and `review-ast-compile` and requires the HTML, LaTeX
and IDGXML output to match. (review-ext.rb reopens classes for the rest of the
process, so those builds run in child processes.)
