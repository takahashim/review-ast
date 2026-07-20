# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require 'review/ast/block_processor'
require 'review/ast/inline_processor'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'

# Generated-coverage counterpart to test_idgxml_renderer_builder_comparison.rb.
#
# That file is a hand-picked list of cases pinning known byte-level
# regressions. This one goes the other way: it enumerates the compiler's two
# command tables at runtime and insists that *every* command is either
# exercised by a minimal source fragment or explicitly excluded with a reason.
# The point is the coverage assertion -- when someone adds a command to
# BLOCK_COMMAND_TABLE or DEFAULT_INLINE_HANDLERS, this test fails until they
# add a fragment or an exclusion. Breadth over depth: one small fragment per
# command, compared in all three formats.
class TestCommandParityCoverage < Test::Unit::TestCase
  # Minimal Re:VIEW source per block command. Each fragment carries only the
  # context the command needs (a heading for section refs, rows for a table, a
  # surrounding list for //beginchild, a target block for reference inlines).
  BLOCK_FRAGMENTS = {
    # Code blocks
    list: "//list[lst][Caption]{\nputs 1\n//}",
    listnum: "//listnum[lstn][Caption]{\nputs 1\n//}",
    emlist: "//emlist[Caption]{\nputs 1\n//}",
    emlistnum: "//emlistnum[Caption]{\nputs 1\n//}",
    cmd: "//cmd[Caption]{\n$ ls\n//}",
    source: "//source[foo.rb]{\nputs 1\n//}",

    # Images. The referenced file need not exist on disk: with no image bound,
    # both builder and renderer fall back to the same unresolved-path output,
    # which is exactly the parity we want to check here.
    image: "//image[sample1][Caption]{\n//}",
    indepimage: '//indepimage[sample1][Caption]',
    numberlessimage: '//numberlessimage[sample1][Caption]',

    # Tables. //imgtable takes no rows but still requires an (empty) block.
    table: "//table[tbl][Caption]{\nA\tB\n------------\nC\tD\n//}",
    emtable: "//emtable[Caption]{\nA\tB\n------------\nC\tD\n//}",
    imgtable: "//imgtable[itbl][Caption][sample1]{\n//}",

    # Lists. These are normally written in line notation (`*`, `1.`, `:`)
    # rather than as //ul etc.; the line notation is what the compiler
    # actually produces these nodes from, so that is what the fragments use.
    ul: " * a\n * b\n",
    ol: " 1. a\n 2. b\n",
    dl: " : term\n\texplanation\n",
    li: " * a\n",
    dt: " : term\n\tdesc\n",
    dd: " : term\n\tdesc\n",

    # Minicolumns: same structure, different minicolumn_type.
    note: "//note[Title]{\nbody\n//}",
    memo: "//memo[Title]{\nbody\n//}",
    tip: "//tip[Title]{\nbody\n//}",
    info: "//info[Title]{\nbody\n//}",
    warning: "//warning[Title]{\nbody\n//}",
    important: "//important[Title]{\nbody\n//}",
    caution: "//caution[Title]{\nbody\n//}",
    notice: "//notice[Title]{\nbody\n//}",

    # A column is written as a tagged heading, not as //column. The trailing
    # section closes the column so the fragment exercises column_end too.
    column: "= Chapter\n\n==[column] Column Title\n\nbody\n\n== Next\n\ntext\n",

    # Footnotes
    footnote: "text@<fn>{fnid}\n\n//footnote[fnid][note body]\n",
    endnote: "text@<endnote>{enid}\n\n//endnote[enid][note body]\n\n//printendnotes\n",

    # Math
    texequation: "//texequation[eq1][Caption]{\nx = y\n//}",

    # Embedded raw output
    embed: "//embed[html]{\n<p>raw</p>\n//}",
    raw: "//raw[|html|<hr />]\n",

    # Quote family
    read: "//read{\nlead text\n//}",
    quote: "//quote{\nquoted\n//}",
    lead: "//lead{\nlead\n//}",
    centering: "//centering{\ncentered\n//}",
    flushright: "//flushright{\nright\n//}",
    talk: "//talk{\ntalk\n//}",

    # Other blocks
    doorquote: "//doorquote[Author]{\nquoted\n//}",
    box: "//box[Caption]{\nboxed\n//}",
    insn: "//insn[Caption]{\nbody\n//}",
    point: "//point[Caption]{\nbody\n//}",
    term: "//term{\nbody\n//}",

    # Control commands. The ones with no output of their own are wrapped in
    # surrounding paragraphs so that any stray blank line or separator shows up
    # as a difference rather than being swallowed by an empty document.
    comment: "//comment[hidden]\n",
    blankline: "text\n\n//blankline\n\nmore\n",
    pagebreak: "text\n\n//pagebreak\n\nmore\n",
    label: "text\n\n//label[lbl]\n\nmore\n",
    printendnotes: "text@<endnote>{e1}\n\n//endnote[e1][body]\n\n//printendnotes\n",
    hr: "text\n\n//hr\n\nmore\n",
    bpo: "//bpo{\nbpo body\n//}",
    parasep: "text\n\n//parasep\n\nmore\n",

    # Directives (removed during lowering; the effect must land on the target
    # node, so each fragment pairs the directive with the node it modifies).
    olnum: "//olnum[5]\n\n 1. a\n 2. b\n",
    noindent: "//noindent\ntext paragraph\n",
    firstlinenum: "//firstlinenum[100]\n\n//listnum[l2][Cap]{\nputs 1\n//}",
    tsize: "//tsize[|latex|lll]\n\n//table[t2][Cap]{\nA\tB\tC\n------------\nD\tE\tF\n//}",
    beginchild: " * parent\n\n//beginchild\n\n * child\n\n//endchild\n\n * parent2\n",
    endchild: " * parent\n\n//beginchild\n\n * child\n\n//endchild\n"
  }.freeze

  # Minimal Re:VIEW source per special inline command.
  INLINE_FRAGMENTS = {
    column: "= Chapter\n\n==[column] Col\n\nbody\n\n== Sec\n\nSee @<column>{Col}.\n",
    embed: "text @<embed>{|html|<b>x</b>} end\n",
    endnote: "text@<endnote>{e1}\n\n//endnote[e1][body]\n\n//printendnotes\n",
    eq: "See @<eq>{eq1}.\n\n//texequation[eq1][Cap]{\nx=y\n//}",
    fn: "text@<fn>{f1}\n\n//footnote[f1][body]\n",
    hd: "= Chapter\n\n=={secid} Sec A\n\nSee @<hd>{secid}.\n",
    href: "See @<href>{https://example.com, Example}.\n",
    img: "See @<img>{sample1}.\n\n//image[sample1][Cap]{\n//}",
    imgref: "See @<imgref>{sample1}.\n\n//image[sample1][Cap]{\n//}",
    kw: "The @<kw>{keyword, kw} here.\n",
    list: "See @<list>{lst}.\n\n//list[lst][Cap]{\nputs 1\n//}",
    raw: "text @<raw>{|html|<hr />} end\n",
    ruby: "The @<ruby>{漢字, かんじ} here.\n",
    sec: "= Chapter\n\n=={secid} Sec A\n\nSee @<sec>{secid}.\n",
    secref: "= Chapter\n\n=={secid} Sec A\n\nSee @<secref>{secid}.\n",
    sectitle: "= Chapter\n\n=={secid} Sec A\n\nSee @<sectitle>{secid}.\n",
    table: "See @<table>{tbl}.\n\n//table[tbl][Cap]{\nA\tB\n------------\nC\tD\n//}",

    # @<labelref> and @<ref> must point at something the reference resolver has
    # an index for; a table id is the cheapest such target. (A bare
    # //label[...] target is *not* resolvable -- see LABEL_TARGET note below.)
    labelref: "//table[tbl][Cap]{\nA\tB\n------------\nC\tD\n//}\n\nSee @<labelref>{tbl}.\n",
    ref: "//table[tbl][Cap]{\nA\tB\n------------\nC\tD\n//}\n\nSee @<ref>{tbl}.\n"
  }.freeze

  # Commands with no comparable output in any of the three formats.
  BLOCK_EXCLUSIONS = {
    blockquote: 'no legacy builder implements #blockquote in html/idgxml/latex, ' \
                'so there is no builder output to compare against.',
    address: 'no legacy builder implements #address in html/idgxml/latex, ' \
             'so there is no builder output to compare against.',
    bibpaper: 'requires a book-level bib.re; a single-chapter fragment raises ' \
              'FileNotFound during index generation. Covered with book context by ' \
              'test_idgxml_renderer_builder_comparison.rb#test_syntax_book_bib.',
    graph: 'shells out to dot/gnuplot and writes generated images into the book ' \
           'imagedir, so it is not safe to run on every CI push. The html and latex ' \
           'renderers also leave it unimplemented (ast-semantics.ja.md section 4), and ' \
           'idgxml diverges on the generated filename (builder .eps vs renderer .pdf).'
  }.freeze

  INLINE_EXCLUSIONS = {
    bib: 'requires a book-level bib.re; a single-chapter fragment raises FileNotFound.',
    bibref: 'requires a book-level bib.re; a single-chapter fragment raises FileNotFound.',
    chap: 'resolves against the book catalog; the comparators build a one-chapter ' \
          'book with no catalog, so the chapter id is not registered.',
    chapref: 'resolves against the book catalog; see @<chap>.',
    title: 'resolves against the book catalog; see @<chap>.',
    w: 'needs a dictionary/words file supplied at book level, and the latex renderer ' \
       'leaves it unimplemented (ast-semantics.ja.md section 4).',
    wb: 'needs a dictionary/words file supplied at book level, and the latex renderer ' \
        'leaves it unimplemented (ast-semantics.ja.md section 4).'
  }.freeze

  # Per-format exclusions: the fragment is compared in the other formats.
  #
  # Two distinct reasons appear here.
  #
  # (a) The legacy builder for that format simply has no method for the command,
  #     so the compiler aborts with "builder does not support command". There is
  #     nothing to compare and nothing wrong.
  #
  # Only (a) belongs here. When this sweep was first written it also found six
  # cases of the opposite kind -- the renderer lacking a handler the builder has
  # (//read, //talk, //doorquote, //point, //bpo and @<imgref> in HTML). Those
  # were implemented rather than excluded, which is what should happen to any
  # future finding of that shape: an exclusion here must mean "there is nothing
  # to compare", never "we render this differently".
  BLOCK_FORMAT_EXCLUSIONS = {
    talk: { idgxml: 'IDGXMLBuilder has no #talk.', latex: 'LATEXBuilder has no #talk.' },
    doorquote: { idgxml: 'IDGXMLBuilder has no #doorquote.', latex: 'LATEXBuilder has no #doorquote.' },
    point: { latex: 'LATEXBuilder has no #point.' },
    bpo: { latex: 'LATEXBuilder has no #bpo.' },
    insn: { html: 'HTMLBuilder has no #insn.', latex: 'LATEXBuilder has no #insn.' },
    term: { html: 'HTMLBuilder has no #term.', latex: 'LATEXBuilder has no #term.' },
    parasep: { idgxml: 'IDGXMLBuilder has no #parasep.' }
  }.freeze

  INLINE_FORMAT_EXCLUSIONS = {
    labelref: { latex: 'LATEXBuilder has no #inline_labelref.' },
    ref: { latex: 'LATEXBuilder has no #inline_ref.' }
  }.freeze

  def setup
    @formats = {
      idgxml: [ReVIEW::Test::IdgxmlComparator.new, ReVIEW::AST::Diff::ByteExact.new],
      html: [ReVIEW::Test::HtmlComparator.new, ReVIEW::AST::Diff::Html.new],
      latex: [ReVIEW::Test::LatexComparator.new, ReVIEW::AST::Diff::Latex.new]
    }
  end

  # The coverage gate. Every key of both command tables must be accounted for,
  # and conversely no fragment/exclusion may name a command that no longer
  # exists (which would otherwise rot silently).
  def test_every_block_command_is_covered
    assert_table_covered(
      ReVIEW::AST::BlockProcessor::BLOCK_COMMAND_TABLE,
      'BLOCK_COMMAND_TABLE', BLOCK_FRAGMENTS, BLOCK_EXCLUSIONS
    )
  end

  def test_every_inline_command_is_covered
    assert_table_covered(
      ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS,
      'DEFAULT_INLINE_HANDLERS', INLINE_FRAGMENTS, INLINE_EXCLUSIONS
    )
  end

  # Per-format exclusions must also stay honest: they may only name a command
  # that actually has a fragment.
  def test_format_exclusions_reference_known_fragments
    stale_block = BLOCK_FORMAT_EXCLUSIONS.keys - BLOCK_FRAGMENTS.keys
    assert_empty(stale_block,
                 'BLOCK_FORMAT_EXCLUSIONS names commands with no fragment: ' \
                 "#{stale_block.join(', ')}")

    stale_inline = INLINE_FORMAT_EXCLUSIONS.keys - INLINE_FRAGMENTS.keys
    assert_empty(stale_inline,
                 'INLINE_FORMAT_EXCLUSIONS names commands with no fragment: ' \
                 "#{stale_inline.join(', ')}")
  end

  def test_block_command_parity
    assert_fragments_match(BLOCK_FRAGMENTS, BLOCK_FORMAT_EXCLUSIONS, '//')
  end

  def test_inline_command_parity
    assert_fragments_match(INLINE_FRAGMENTS, INLINE_FORMAT_EXCLUSIONS, '@<')
  end

  # A [notoc]/[nonum]/[nodisp] heading does not consume a section number:
  # IndexBuilder advances its counter in #headline only. Advancing it for them
  # shifted every later heading's number, so a reference resolved to the wrong
  # anchor. Found by the generator at seed 600.
  def test_unnumbered_heading_does_not_shift_later_anchors
    source = "= 章\n\n==[notoc] 目次外\n\n== 通常節\n\n==={g2} 項\n\n参照 @<hd>{g2}\n"
    comparator = ReVIEW::Test::HtmlComparator.new

    assert(ReVIEW::AST::Diff::Html.new.equal?(comparator.convert_with_builder(source),
                                              comparator.convert_with_renderer(source)),
           'a notoc heading must not shift the anchors of the headings after it')
  end

  private

  def assert_table_covered(table, table_name, fragments, exclusions)
    overlap = fragments.keys & exclusions.keys
    assert_empty(overlap,
                 "#{table_name}: commands are both covered and excluded: #{overlap.join(', ')}")

    uncovered = table.keys - fragments.keys - exclusions.keys
    assert_empty(uncovered,
                 "#{table_name} gained commands with no parity coverage: " \
                 "#{uncovered.join(', ')}. Add a source fragment for each, or add it to " \
                 'the exclusion map with a reason.')

    stale = (fragments.keys + exclusions.keys) - table.keys
    assert_empty(stale,
                 "#{table_name} no longer defines: #{stale.join(', ')}. " \
                 'Remove the stale fragment or exclusion.')
  end

  def assert_fragments_match(fragments, format_exclusions, prefix)
    failures = []

    fragments.each do |command, source|
      @formats.each do |format, (comparator, diff)|
        next if format_exclusions.dig(command, format)

        builder_output = comparator.convert_with_builder(source)
        renderer_output = comparator.convert_with_renderer(source)
        next if diff.equal?(builder_output, renderer_output)

        failures << "#{prefix}#{command} (#{format}):\n" \
                    "#{comparator.class}\n#{diff.compare(builder_output, renderer_output).pretty_diff}"
      end
    end

    assert_empty(failures, "builder/renderer parity broke:\n\n#{failures.join("\n\n")}")
  end
end
