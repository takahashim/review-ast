# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/latex_comparator'
require 'review/ast/diff/latex'

class TestLatexRendererBuilderComparison < Test::Unit::TestCase
  def setup
    @converter = ReVIEW::Test::LatexComparator.new
    @comparator = ReVIEW::AST::Diff::Latex.new
  end

  def test_simple_paragraph_comparison
    source = 'This is a simple paragraph.'

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?, 'Simple paragraph should produce equivalent LaTeX'
  end

  def test_headline_comparison
    source = '= Chapter Title'

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?, 'Headline should produce equivalent LaTeX'
  end

  def test_inline_formatting_comparison
    source = 'This has @<b>{bold} and @<i>{italic} and @<code>{code} text.'

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?
  end

  def test_code_block_comparison
    source = <<~RE
      //list[example][Code Example]{
      def hello
        puts "Hello World"
      end
      //}
    RE

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?
  end

  def test_table_comparison
    source = <<~RE
      //table[sample][Sample Table]{
      Header 1	Header 2
      ---------------------
      Data 1	Data 2
      Data 3	Data 4
      //}
    RE

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?
  end

  def test_list_comparison
    source = <<~RE
      * First item
      * Second item
      * Third item
    RE

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?
  end

  def test_note_block_comparison
    source = <<~RE
      //note[Note Title]{
      This is a note block.
      //}
    RE

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?
  end

  def test_complex_document_comparison
    source = <<~RE
      = Chapter Title

      This is a paragraph with @<b>{bold} text.

      == Section Title

      Here's a list:

      * Item 1
      * Item 2

      And a code block:

      //list[example][Example]{
      puts "Hello"
      //}

      //table[data][Data Table]{
      Name	Value
      ---------------------
      A	1
      B	2
      //}
    RE

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts 'Complex document differences found:'
      puts "Builder LaTeX length: #{builder_latex.length}"
      puts "Renderer LaTeX length: #{renderer_latex.length}"
      puts "Number of differences: #{result.differences.length}"
      puts
      puts 'Pretty diff:'
      puts result.pretty_diff
    end

    assert result.equal?
  end

  def test_comparator_options
    latex1 = '\\chapter{Test}\\label{chap:test}'
    latex2 = '\\chapter{Test} \\label{chap:test}'

    # Whitespace sensitive comparison
    whitespace_sensitive_comparator = ReVIEW::AST::Diff::Latex.new(ignore_whitespace: false)
    result1 = whitespace_sensitive_comparator.compare(latex1, latex2)

    # Whitespace insensitive comparison
    whitespace_insensitive_comparator = ReVIEW::AST::Diff::Latex.new(ignore_whitespace: true)
    result2 = whitespace_insensitive_comparator.compare(latex1, latex2)

    assert result1.different?, 'Whitespace sensitive comparison should detect differences'
    assert result2.equal?, 'Whitespace insensitive comparison should ignore whitespace'
  end

  def test_mathematical_expressions
    source = 'This is a formula: @<m>{x^2 + y^2 = z^2}.'

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts "Builder LaTeX: #{builder_latex.inspect}"
      puts "Renderer LaTeX: #{renderer_latex.inspect}"
      puts result.pretty_diff
    end

    assert result.equal?
  end

  # Tests with actual Re:VIEW files from samples/syntax-book
  def test_syntax_book_ch01
    file_path = File.join(__dir__, '../../samples/syntax-book/ch01.re')
    source = File.read(file_path)

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts 'ch01.re differences found:'
      puts "Builder LaTeX length: #{builder_latex.length}"
      puts "Renderer LaTeX length: #{renderer_latex.length}"
      puts result.pretty_diff
    end

    assert result.equal?, 'ch01.re should produce equivalent LaTeX'
  end

  def test_syntax_book_ch02
    book_dir = File.join(__dir__, '../../samples/syntax-book')
    result_hash = @converter.convert_chapter_with_book_context(book_dir, 'ch02')

    builder_latex = result_hash[:builder]
    renderer_latex = result_hash[:renderer]

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts 'ch02.re differences found:'
      puts "Builder LaTeX length: #{builder_latex.length}"
      puts "Renderer LaTeX length: #{renderer_latex.length}"
      puts result.pretty_diff
    end

    assert result.equal?, 'ch02.re should produce equivalent LaTeX'
  end

  def test_syntax_book_ch03
    file_path = File.join(__dir__, '../../samples/syntax-book/ch03.re')
    source = File.read(file_path)

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts 'ch03.re differences found:'
      puts "Builder LaTeX length: #{builder_latex.length}"
      puts "Renderer LaTeX length: #{renderer_latex.length}"
      puts result.pretty_diff
    end

    assert result.equal?, 'ch03.re should produce equivalent LaTeX'
  end

  # Regression test: within an appendix chapter, numbered captions
  # (list/table/image/equation) must use the appendix letter (e.g. "A.1"),
  # not the raw chapter number ("1.1"). Requires full book context so the
  # chapter is recognized as an appendix.
  def test_syntax_book_appA
    book_dir = File.join(__dir__, '../../samples/syntax-book')
    result_hash = @converter.convert_chapter_with_book_context(book_dir, 'appA')

    builder_latex = result_hash[:builder]
    renderer_latex = result_hash[:renderer]

    result = @comparator.compare(builder_latex, renderer_latex)

    if result.different?
      puts 'appA.re differences found:'
      puts result.pretty_diff
    end

    assert result.equal?, 'appA.re (appendix) should produce equivalent LaTeX'
  end

  # Regression (found by PBT coverage expansion): //pagebreak must emit
  # \pagebreak like LATEXBuilder#pagebreak. The renderer's control-command
  # handler was a stub returning '', silently dropping the page break.
  def test_pagebreak_comparison
    source = "Para one.\n\n//pagebreak\n\nPara two."

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, '//pagebreak should produce equivalent LaTeX'
    assert_include(renderer_latex, '\\pagebreak')
  end

  # Regression (same stub bug as pagebreak): //hr must emit \hrule like
  # LATEXBuilder#hr, not be dropped.
  def test_hr_comparison
    source = "Para one.\n\n//hr\n\nPara two."

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, '//hr should produce equivalent LaTeX'
    assert_include(renderer_latex, '\\hrule')
  end

  # Regression (same stub bug as pagebreak/hr): //parasep must emit \parasep like
  # LATEXBuilder#parasep, not be dropped.
  def test_parasep_comparison
    source = "Para one.\n\n//parasep\n\nPara two."

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, '//parasep should produce equivalent LaTeX'
    assert_include(renderer_latex, '\\parasep')
  end

  # Regression (found by PBT coverage expansion): @<hd>/@<secref> to an
  # unnumbered heading (a subsection beyond the default secnolevel=2) must show
  # the title alone, not a spurious number. LATEXBuilder#inline_hd_chap uses
  # hd_quote_without_number when !over_secnolevel?; the renderer always emitted
  # the number.
  def test_hd_reference_to_unnumbered_heading
    source = "== Parent\n\n==={target} Child\n\nSee @<hd>{target} here."

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, '@<hd> to an unnumbered heading should match builder'
    # Title only, no number prefix, for the unnumbered subsection.
    assert_include(renderer_latex, '\\reviewsecref{「Child」}')
  end

  # Companion: @<hd> to a numbered section still shows "number title".
  def test_hd_reference_to_numbered_heading
    source = "=={target} Section\n\nSee @<hd>{target} here."

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, '@<hd> to a numbered heading should match builder'
    assert_include(renderer_latex, '\\reviewsecref{「1.1 Section」}')
  end

  # Regression (found by a debug-book DVI sweep): a list item's continuation
  # lines must keep their source newlines, like LATEXBuilder's
  # `lines.map(&:chomp).join("\n")`. The AST parsed each line separately and
  # dropped the boundary, so ASCII continuation lines ran together
  # ("item2a.b.") -- a visible (DVI-level) divergence. This is a whitespace
  # class finding, so it asserts the exact rendered bytes, not via the
  # whitespace-blind canonical comparator.
  def test_list_item_continuation_lines_keep_newlines
    source = " 1. item1\n 2. item2\n   a. subA\n   b. subB\n 3. item3\n"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    # Byte-identical for the continuation lines: newline-separated, not merged.
    assert_include(renderer_latex, "\\item item2\na. subA\nb. subB")
    assert_equal(builder_latex, renderer_latex)
  end

  # Regression (found by a DVI edge-case probe): @<fn> inside a heading is a
  # LaTeX moving argument, so it must become \protect\footnotemark{} + a deferred
  # \footnotetext (like LATEXBuilder), not a bare \footnote{} which breaks
  # typesetting. Asserted on exact bytes because the \footnotetext lands at a
  # DVI-neutral but different position than the builder (so canonical/DVI compare
  # is not used here).
  def test_footnote_in_heading_uses_footnotemark
    source = "== Heading@<fn>{f1}\n\nBody.\n\n//footnote[f1][note text]"

    renderer_latex = @converter.convert_with_renderer(source)

    assert_include(renderer_latex, '\\section{Heading\\protect\\footnotemark{}}')
    assert_include(renderer_latex, '\\footnotetext[1]{note text}')
    assert_not_include(renderer_latex, '\\footnote{note text}')
  end

  # nodisp has no visible heading, only a TOC entry, so its footnote is a plain
  # \footnote in \addcontentsline and NO \footnotetext is emitted (matching
  # LATEXBuilder). Regression against the :heading context wrongly collecting it.
  def test_footnote_in_nodisp_heading_emits_no_footnotetext
    source = "==[nodisp] Heading@<fn>{f1}\n\nBody.\n\n//footnote[f1][note text]"

    renderer_latex = @converter.convert_with_renderer(source)

    assert_include(renderer_latex, '\\addcontentsline{toc}{section}{Heading\\footnote{note text}}')
    assert_not_include(renderer_latex, '\\footnotetext')
  end

  # Regression (found by a DVI edge-case probe): the :block wrappers (//quote,
  # //lead, //flushright, //centering, ...) do NOT re-parse list markup in
  # LATEXBuilder -- read_block only inline-compiles lines, so a "* item" line is
  # literal text, not an itemize. The AST used to build a nested list here.
  def test_quote_does_not_parse_nested_list
    source = "//quote{\n引用文\n\n * 項目\n//}"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, '//quote should not parse a nested list (matching builder)'
    assert_not_include(renderer_latex, '\\begin{itemize}')
  end

  # Regression: LATEXBuilder's :block wrappers (//quote, //centering, ...) join a
  # paragraph's source lines with "" (split_paragraph / join_lines_to_paragraph,
  # join_lines_by_lang off), unlike an ordinary paragraph which keeps "\n". The
  # renderer used to keep "\n" here, so ASCII continuation lines gained a spurious
  # space. Whitespace class -> assert exact bytes.
  def test_quote_joins_paragraph_lines_without_newline
    source = "//quote{\nline one\nline two\n//}"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    assert_include(renderer_latex, 'line oneline two')
    assert_equal(builder_latex, renderer_latex)
  end

  # A normal paragraph must NOT get the :block join -- it keeps its source
  # newlines, matching LATEXBuilder#paragraph. (assert_include, not assert_equal:
  # a bare paragraph with no heading differs from the builder only by a leading
  # blank line, a harness artifact the canonical comparator ignores.)
  def test_normal_paragraph_keeps_newlines
    source = "line one\nline two"

    renderer_latex = @converter.convert_with_renderer(source)

    assert_include(renderer_latex, "line one\nline two")
  end

  # Regression (found by a join_lines_by_lang config sweep): with
  # join_lines_by_lang on, LATEXBuilder joins source lines via
  # join_lines_to_paragraph, which inserts NO space at an ASCII->Japanese
  # boundary. The renderer used to keep the source "\n", which typesets as a
  # space there -- a real DVI difference. The fix joins every line-join site
  # (paragraph, list item, dd) language-aware. Japanese suppresses the space.
  def test_join_lines_by_lang_ascii_japanese_boundary
    converter = ReVIEW::Test::LatexComparator.new(config: { 'join_lines_by_lang' => true })
    # "code" (ASCII) then a line starting with Japanese -> no space between them.
    source = "code\n文字"

    builder_latex = converter.convert_with_builder(source)
    renderer_latex = converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'join_lines_by_lang must not add a space at an ASCII->Japanese join'
    assert_include(renderer_latex, 'code文字')
  end

  # Regression (found by a caption_position config sweep): with
  # caption_position bottom, LATEXBuilder places list/table/equation captions
  # *below* the body (common_code_block / table / texequation honor
  # caption_top?). The renderer always placed them at the top.
  def test_caption_position_bottom
    converter = ReVIEW::Test::LatexComparator.new(
      config: { 'caption_position' => { 'list' => 'bottom', 'table' => 'bottom', 'equation' => 'bottom', 'image' => 'bottom' } }
    )
    {
      'list' => "//list[l][cap]{\ncode\n//}",
      'table' => "//table[t][cap]{\nA\tB\n------------\nC\tD\n//}",
      'equation' => "//texequation[e][cap]{\nx^2\n//}"
    }.each do |name, source|
      builder_latex = converter.convert_with_builder(source)
      renderer_latex = converter.convert_with_renderer(source)
      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "#{name} caption should sit at the bottom under caption_position bottom"
    end
  end

  # Regression: a caption-less //table with an id emits neither a \begin{table}
  # float, a caption, NOR a \label -- LATEXBuilder#table only reaches table_header
  # (which puts caption + label) when the caption is present, so a caption-less
  # table is just the bare reviewtable.
  def test_table_without_caption_emits_no_float_caption_or_label
    source = "//table[t]{\nA\tB\n------------\nC\tD\n//}"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'caption-less table must match builder'
    assert_not_include(renderer_latex, '\\begin{table}')
    assert_not_include(renderer_latex, '\\reviewtablecaption')
    assert_not_include(renderer_latex, '\\label{table:test:t}')
  end

  # Regression (DVI): the raw-content adjacency rules apply INSIDE nested block
  # containers too (a //note or column), not just at the document level -- two
  # //embed blocks inside a //note must be adjacent, and a column whose first
  # content is an embed must not get a blank after \addcontentsline.
  def test_nested_embed_adjacency
    {
      'note with 2 embeds' => "//note{\n\n//embed[latex]{\n\\LaTeX{}\n//}\n\n//embed[latex]{\n\\LaTeX{}\n//}\n\n//}",
      'column with 2 embeds' => "===[column] C\n\n//embed[latex]{\n\\LaTeX{}\n//}\n\n//embed[latex]{\n\\LaTeX{}\n//}\n\n===[/column]"
    }.each do |name, source|
      builder_latex = @converter.convert_with_builder(source)
      renderer_latex = @converter.convert_with_renderer(source)

      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "#{name} must match builder"
      assert_match(/\\LaTeX\{\}\n\\LaTeX\{\}/, renderer_latex) # embeds adjacent
    end
  end

  # Regression (DVI): a minicolumn (//note etc.) directly followed by a block/raw
  # //embed must not leave a blank line between \end{review…} and the embed's
  # content -- the minicolumn emits no trailing #blank in LATEXBuilder, so the
  # embed content prints right after; the renderer's "\n\n" made a spurious \par.
  # (Found by the PBT DVI sweep, seed 971.)
  def test_minicolumn_followed_by_embed_no_blank
    source = "//note{\nbody\n//}\n\n//embed[latex]{\n\\LaTeX{}\n//}"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'minicolumn followed by embed must match builder'
    assert_match(/\\end\{reviewnote\}\n\\LaTeX/, renderer_latex)
    assert_no_match(/\\end\{reviewnote\}\n\n\\LaTeX/, renderer_latex)
  end

  # Regression (DVI): //raw is emitted verbatim (LATEXBuilder#raw does
  # `print content`, no added newline), so consecutive raws are adjacent ("AB",
  # not "A B") -- the renderer used to append "\n", turning them into "A B"
  # (newline = space). A raw immediately before a paragraph, though, DOES join it
  # with a space ("A\ntext"), and an embed before a raw must not leave a blank.
  def test_raw_block_adjacency
    {
      '//raw + //raw' => ["//raw[|latex|AAA]\n\n//raw[|latex|BBB]", "AAABBB\n"],
      'embed + //raw' => ["//embed[latex]{\nX\n//}\n\n//raw[|latex|Y]", "X\nY\n"],
      '//raw + paragraph' => ["//raw[|latex|A]\n\nnormal text", "A\nnormal text\n"]
    }.each do |name, (source, expected_renderer)|
      builder_latex = @converter.convert_with_builder(source)
      renderer_latex = @converter.convert_with_renderer(source)

      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "#{name} must match builder"
      assert_equal expected_renderer, renderer_latex, name
    end
  end

  # Regression (DVI): consecutive block //embed[latex] blocks must sit on
  # adjacent lines, not be separated by a blank line. LATEXBuilder#embed prints
  # its content with a single trailing "\n" (no #blank), so `\LaTeX{}\n\LaTeX{}`
  # stays on one line; the renderer's block-embed "\n\n" made the second embed a
  # new paragraph (a real DVI divergence found by the PBT DVI sweep).
  def test_consecutive_block_embeds_no_blank_line
    source = "//embed[latex]{\n\\LaTeX{}\n//}\n\n//embed[latex]{\n\\LaTeX{}\n//}"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'consecutive block embeds must match builder'
    assert_equal "\\LaTeX{}\n\\LaTeX{}\n", renderer_latex
  end

  # Regression: a footnote used in a moving argument (heading/caption/…) must
  # emit its \footnotetext at the //footnote DEFINITION, not right after the
  # heading -- otherwise a page break between the heading and the definition puts
  # the footnote on the wrong page (a real DVI divergence). Mirrors
  # LATEXBuilder's @foottext (set by inline_fn, consumed at footnote).
  def test_heading_footnote_emits_footnotetext_at_definition
    # //footnote defined far below the heading, past a //pagebreak
    source = "== Sec @<fn>{a}\n\nbody\n\n//pagebreak\n\nafter\n\n//footnote[a][na]"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'heading footnote must place \\footnotetext at the definition'
    # \footnotetext comes after the \pagebreak, not right after the \section
    assert_match(/\\pagebreak.*\\footnotetext\[1\]/m, renderer_latex)
    assert_no_match(/\\section\{Sec[^}]*\}\n\\label\{sec:1-1\}\n\\footnotetext/, renderer_latex)
  end

  # Regression: a footnote in a column caption is a LaTeX moving argument, so it
  # must become \protect\footnotemark{} + a deferred \footnotetext (like a
  # heading), not a bare \footnote. The column caption is also reused in
  # \addcontentsline, so both occurrences must use the footnotemark form.
  def test_footnote_in_column_caption_uses_footnotemark
    source = "===[column] Col @<fn>{a}\n\nbody@<fn>{b} text\n\n===[/column]\n\n//footnote[a][na]\n\n//footnote[b][nb]"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'footnote in column caption must match builder'
    assert_include(renderer_latex, '\\protect\\footnotemark{}')
    assert_not_include(renderer_latex, '\\footnote{na}')
  end

  # Regression: a table with multiple header/body separator lines drops EVERY
  # separator (LATEXBuilder#parse_table_rows `next`-s each one); only the first
  # sets the header/body split. A later separator must not survive as a data row.
  def test_table_multiple_separators
    source = "//table[t][C]{\nA\tB\n------------\nC\tD\n------------\nE\tF\n//}"

    builder_latex = @converter.convert_with_builder(source)
    renderer_latex = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'table with multiple separators must match builder'
  end

  # Regression (config sweep): with global footnotetext mode, @<fn> emits
  # \footnotemark[n]{} (note the braces) and each //footnote definition emits its
  # \footnotetext[n]{...} (LATEXBuilder#footnote). //endnote must NOT.
  def test_footnotetext_mode
    converter = ReVIEW::Test::LatexComparator.new(config: { 'footnotetext' => true })
    source = "Body@<fn>{a}.\n\n//footnote[a][note text]"

    builder_latex = converter.convert_with_builder(source)
    renderer_latex = converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'footnotetext mode must match builder'
    assert_include(renderer_latex, '\\footnotemark[1]{}')
    assert_include(renderer_latex, '\\footnotetext[1]{note text}')
  end

  # Regression (config sweep): at secnolevel 0 no chapter is numbered, so a
  # cross-reference drops the chapter prefix ("1.1" -> "1"), matching
  # LATEXBuilder's get_chap.
  def test_secnolevel0_reference_drops_chapter_number
    converter = ReVIEW::Test::LatexComparator.new(config: { 'secnolevel' => 0 })
    source = "//list[l][cap]{\ncode\n//}\n\nSee @<list>{l}."

    builder_latex = converter.convert_with_builder(source)
    renderer_latex = converter.convert_with_renderer(source)

    result = @comparator.compare(builder_latex, renderer_latex)
    puts result.pretty_diff if result.different?
    assert result.equal?, 'secnolevel 0 reference should drop the chapter number'
    assert_include(renderer_latex, '\\reviewlistref{1}')
  end

  # Regression (config sweep): with highlight={latex: listings}, code blocks are
  # rendered via review*lst environments. The body is emitted RAW (non-escaped:
  # $ & # _ % stay literal), while inline ops are still compiled AND their
  # arguments re-escaped. The caption goes into the environment option with NO
  # chapter-number prefix (unlike the verbatim path).
  def test_highlight_listings_code_blocks
    converter = ReVIEW::Test::LatexComparator.new(config: { 'highlight' => { 'latex' => 'listings' } })
    {
      'list' => "//list[l][cap]{\nputs \"hi\"\n//}",
      'list-nocap' => "//list[l][]{\nz = 3\n//}",
      'listnum' => "//listnum[l][cap][ruby]{\nx = 1\ny = 2\n//}",
      'emlist' => "//emlist[][ruby]{\nx = 1\n//}",
      'emlistnum' => "//emlistnum[cap]{\na\nb\n//}",
      'cmd' => "//cmd{\n$ ls\n//}",
      'source' => "//source[src.rb]{\nputs :x\n//}",
      'raw-and-inline' => "//emlist{\na_b & $x #y @<b>{c_d} @<code>{e_f}\n//}"
    }.each do |name, source|
      builder_latex = converter.convert_with_builder(source)
      renderer_latex = converter.convert_with_renderer(source)
      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "#{name} must match builder under highlight listings"
    end
  end

  # Regression: in listings mode the block's plain text is non-escaped but an
  # inline op's argument is still escaped (LATEXBuilder compiles @<...> via
  # compile_inline regardless of highlight mode).
  def test_highlight_listings_inline_argument_is_escaped
    converter = ReVIEW::Test::LatexComparator.new(config: { 'highlight' => { 'latex' => 'listings' } })
    source = "//emlist{\na_b @<b>{c_d}\n//}"

    renderer_latex = converter.convert_with_renderer(source)

    assert_include(renderer_latex, 'a_b ') # raw underscore in block text
    assert_include(renderer_latex, '\\reviewbold{c\\textunderscore{}d}') # escaped inside inline
  end

  # Regression: @<uchar>{code} passes the codepoint through as a literal Unicode
  # character regardless of texcommand. LATEXBuilder#inline_uchar keys on
  # @texcompiler, but that ivar is never set on the builder, so its platex \UTF
  # branch is dead -- it always passes through. The renderer must match under
  # every texcommand (it used to emit \UTF{code} for platex).
  def test_inline_uchar_passthrough_matches_builder
    %w[platex uplatex lualatex].each do |texcommand|
      converter = ReVIEW::Test::LatexComparator.new(config: { 'texcommand' => texcommand })
      source = 'test @<uchar>{2460} and @<uchar>{58F0}'

      builder_latex = converter.convert_with_builder(source)
      renderer_latex = converter.convert_with_renderer(source)

      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "@<uchar> must match builder under texcommand=#{texcommand}"
      assert_include(renderer_latex, '①') # literal ①, never \UTF{2460}
    end
  end

  # Regression: @<dtp>{...} and @<pageref>{id} were unimplemented and raised
  # NotImplementedError. LATEXBuilder ignores @<dtp> (empty) and emits
  # \pageref{id} (raw id, no escaping).
  def test_inline_dtp_and_pageref
    {
      '@<dtp>' => 'foo @<dtp>{pagebreak} bar',
      '@<pageref>' => 'see @<pageref>{sec1} here',
      '@<pageref> raw id' => 'see @<pageref>{a_b} here'
    }.each do |name, source|
      builder_latex = @converter.convert_with_builder(source)
      renderer_latex = @converter.convert_with_renderer(source)

      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "#{name} must match builder"
    end
  end

  # Regression: @<imgref>{id} appends the referenced image's caption as I18n
  # 'image_quote' (「caption」 in ja) when the image has one -- like
  # LATEXBuilder#inline_imgref. The renderer used to emit only \reviewimageref.
  def test_inline_imgref_appends_caption
    {
      'captioned' => "//image[iid][My Cap]\n\nSee @<imgref>{iid}.",
      'empty caption' => "//image[iid][]\n\nSee @<imgref>{iid}.",
      'special chars' => "//image[iid][a_b & c]\n\nSee @<imgref>{iid}."
    }.each do |name, source|
      builder_latex = @converter.convert_with_builder(source)
      renderer_latex = @converter.convert_with_renderer(source)

      result = @comparator.compare(builder_latex, renderer_latex)
      puts result.pretty_diff if result.different?
      assert result.equal?, "@<imgref> (#{name}) must match builder"
    end
    assert_include(@converter.convert_with_renderer("//image[iid][My Cap]\n\n@<imgref>{iid}"), '「My Cap」')
  end
end
