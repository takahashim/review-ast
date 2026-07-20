# frozen_string_literal: true

require_relative '../test_helper'
require 'review'
require 'review/ast'
require 'review/renderer/typst_renderer'
require 'stringio'

# Renders .re source through the real compile pipeline, so the numbers and
# resolved references under test are the ones the Indexer and ReferenceResolver
# actually produce.
class TestTypstRenderer < Test::Unit::TestCase
  include ReVIEW

  def setup
    @config = ReVIEW::Configure.values
    @config['builder'] = 'typst'
    ReVIEW::I18n.setup(@config['language'])
    @book = ReVIEW::Book::Base.new(config: @config)
  end

  def render(source, chapter_number: 1, chapter_id: 'ch01')
    chapter = ReVIEW::Book::Chapter.new(@book, chapter_number, chapter_id, "#{chapter_id}.re", StringIO.new(source))
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    ReVIEW::Renderer::TypstRenderer.new(chapter).render(ast)
  end

  def test_format_type
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'ch01', 'ch01.re', StringIO.new(''))
    assert_equal :typst, ReVIEW::Renderer::TypstRenderer.new(chapter).format_type
  end

  def test_document_imports_the_library_from_the_project_root
    result = render("= タイトル\n")
    assert_match(%r{\A#import "/lib/review-book/lib\.typ": review\n}, result)
  end

  def test_chapter_heading_carries_id_and_supplied_number
    result = render("= はじめに\n")
    assert_match(/#review\.chapter\(id: "chap:ch01", number: 1, number-text: \[第1章\], title: \[はじめに\]\)/, result)
  end

  def test_section_heading_carries_label_and_number
    result = render("= 章\n\n== 節\n")
    assert_match(/#review\.section\(level: 2, id: "sec:ch01:1", number-text: \[1\.1\], title: \[節\]\)/, result)
  end

  # nonum/notoc/nodisp must not advance the counter, so the next numbered
  # heading keeps the number it would have had.
  def test_unnumbered_heading_does_not_consume_a_number
    result = render("= 章\n\n==[nonum] 番号なし\n\n== 節\n")
    assert_match(/number-text: \[1\.1\], title: \[節\]/, result)
    assert_include(result, '#review.section(level: 2, title: [番号なし])')
  end

  # A chapter file can hold more than one level-1 heading, but the chapter label
  # may be defined only once or Typst rejects the document.
  def test_chapter_label_is_emitted_once_per_file
    result = render("= 章\n\n=[nonum] もう一つ\n")
    assert_equal 1, result.scan('id: "chap:ch01"').size
  end

  def test_paragraph_text_is_escaped
    result = render("= 章\n\n#記号 [括弧] //list を含む段落。\n")
    assert_include(result, '\\#記号 \\[括弧\\] \\//list を含む段落。')
  end

  # ------------------------------------------------------------- numbering

  # The caption's number and the reference to it must read the same; both come
  # from TextFormatter over the same stamped DefinitionNumber.
  def test_caption_number_and_reference_agree
    result = render(<<~RE)
      = 章

      //list[hello][キャプション][ruby]{
      puts 1
      //}

      @<list>{hello}
    RE
    assert_include(result, 'number-text: [リスト1.1]')
    assert_include(result, 'text-content: [リスト1.1]')
  end

  def test_reference_links_to_the_chapter_scoped_label
    result = render(<<~RE)
      = 章

      //image[fig1][図版]{
      //}

      @<img>{fig1}
    RE
    assert_include(result, 'id: "fig:ch01:fig1"')
    assert_include(result, 'target: "fig:ch01:fig1"')
  end

  def test_numberless_image_has_no_number
    result = render("= 章\n\n//indepimage[fig1][図版]\n")
    figure_line = result.lines.find { |line| line.include?('#review.figure') }
    assert_not_include(figure_line, 'number-text')
  end

  # ------------------------------------------------------------- footnotes

  # The body is emitted at the first reference with Re:VIEW's number, and later
  # references point at the label rather than repeating the body.
  def test_footnote_body_at_first_reference_then_label_reference
    result = render(<<~RE)
      = 章

      一つ目@<fn>{f1}と二つ目@<fn>{f1}。

      //footnote[f1][脚注本文]
    RE
    assert_include(result, '#review.footnote(id: "fn:ch01:f1", number: 1)[脚注本文]')
    assert_include(result, '#review.footnote-ref(id: "fn:ch01:f1")')
    assert_equal 1, result.scan('[脚注本文]').size
  end

  def test_footnote_definition_alone_emits_nothing
    result = render("= 章\n\n//footnote[f1][未参照]\n")
    assert_not_include(result, '未参照')
  end

  # --------------------------------------------------------------- blocks

  def test_minicolumn_kind_is_the_ast_type
    result = render("= 章\n\n//warning[警告]{\n本文\n//}\n")
    assert_include(result, '#review.minicolumn(kind: "warning", caption: [警告])[')
  end

  def test_table_header_and_rows
    result = render(<<~RE)
      = 章

      //table[t1][表]{
      A	B
      -------------
      1	2
      //}
    RE
    assert_include(result, 'columns: 2')
    assert_include(result, 'header: ([A], [B],)')
    assert_include(result, 'rows: (([1], [2],),)')
  end

  # Item content routinely contains ":" and "/" from generated calls, which
  # would break Typst's term-list markup; the list functions take content.
  def test_lists_are_emitted_as_function_calls
    result = render("= 章\n\n * 一つ\n * 二つ\n")
    assert_include(result, '#review.bullet-list(items: ([一つ], [二つ],))')
  end

  def test_description_list_terms_are_content
    result = render("= 章\n\n : 用語\n    説明\n")
    assert_include(result, '#review.description-list(items: (([用語], [説明]),))')
  end

  def test_plain_code_block_becomes_a_typst_string
    result = render("= 章\n\n//emlist[][ruby]{\nputs \"a\"\n//}\n")
    assert_include(result, 'code: "puts \\"a\\""')
  end

  def test_listnum_passes_line_numbering_as_semantic_values
    result = render("= 章\n\n//listnum[l1][キャプション][ruby]{\nputs 1\n//}\n")
    assert_include(result, 'line-numbers: true')
    assert_include(result, 'start-line: 1')
  end

  # ---------------------------------------------------------------- index

  # Re:VIEW decides the term and its sort key; Typst only supplies the page.
  def test_idx_shows_content_and_records_an_entry
    result = render('= 章

本文@<idx>{索引語}です。
')
    assert_include(result, '本文索引語#review.index-entry(terms: ("索引語",), sort-key: "索引語")')
  end

  def test_hidx_records_without_showing
    result = render('= 章

本文@<hidx>{隠し語}です。
')
    assert_include(result, '#review.index-entry(terms: ("隠し語",), sort-key: "隠し語")')
    assert_not_include(result, '本文隠し語')
  end

  # "<<>>" separates the levels of a hierarchical entry, as it does for mendex.
  def test_index_entry_splits_hierarchy
    result = render('= 章

@<idx>{親<<>>子}
')
    assert_include(result, 'terms: ("親", "子",)')
  end

  # ---------------------------------------------------------- raw / embed

  def test_embed_passes_through_only_for_typst
    result = render("= 章\n\n//embed[typst]{\n#pagebreak()\n//}\n")
    assert_include(result, '#pagebreak()')
  end

  def test_embed_for_another_builder_is_dropped
    result = render("= 章\n\n//embed[latex]{\n\\clearpage\n//}\n")
    assert_not_include(result, 'clearpage')
  end

  # --------------------------------------------------------- source map

  # Typst reports errors against the generated file, so the renderer records
  # which manuscript block produced each line range.
  def test_source_map_covers_each_top_level_block
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'ch01', 'ch01.re', StringIO.new(<<~RE))
      = 章

      一つ目の段落。

      二つ目の段落。
    RE
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    renderer = ReVIEW::Renderer::TypstRenderer.new(chapter)
    output = renderer.render(ast)

    map = renderer.source_map
    assert_equal(3, map.size, 'heading and two paragraphs')
    assert_equal(%w[ch01.re], map.map { |e| e[:filename] }.uniq)
    assert_equal([1, 3, 5], map.map { |e| e[:lineno] })

    # The recorded range must really be where that block landed.
    lines = output.lines
    heading = map.first
    assert_include(lines[heading[:first_line] - 1], '#review.chapter(')
  end

  # The ranges have to be contiguous and ordered, or a lookup by line lands in
  # the wrong block.
  def test_source_map_ranges_are_ordered_and_contiguous
    result = render("= 章\n\n段落一。\n\n段落二。\n\n段落三。\n")
    assert_not_nil(result)

    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'ch01', 'ch01.re', StringIO.new("= 章\n\n段落一。\n\n段落二。\n"))
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    renderer = ReVIEW::Renderer::TypstRenderer.new(chapter)
    renderer.render(ast)

    renderer.source_map.each_cons(2) do |a, b|
      assert_operator(a[:last_line], :<, b[:first_line])
      assert_equal(a[:last_line] + 1, b[:first_line], 'ranges should not have gaps')
    end
  end

  # ------------------------------------------------------------ diagnostics

  # Base#render_inline_element passes unknown inlines through unchanged, which
  # would silently drop the command's meaning; the Typst renderer refuses.
  def test_unknown_inline_raises_with_position
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'ch01', 'ch01.re', StringIO.new(''))
    renderer = ReVIEW::Renderer::TypstRenderer.new(chapter)
    node = ReVIEW::AST::InlineNode.new(
      location: ReVIEW::AST::SourceLocation.new('ch01.re', 7, column: 3),
      inline_type: 'nosuchcommand'
    )

    error = assert_raise(NotImplementedError) do
      renderer.render_inline_element('nosuchcommand', 'text', node)
    end
    assert_include(error.message, '@<nosuchcommand>')
    assert_include(error.message, 'line 7')
    assert_include(error.message, 'ch01.re')
  end

  def test_unknown_node_type_raises
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'ch01', 'ch01.re', StringIO.new(''))
    renderer = ReVIEW::Renderer::TypstRenderer.new(chapter)
    node = ReVIEW::AST::BlockNode.new(
      location: ReVIEW::AST::SourceLocation.new('ch01.re', 1),
      block_type: :nosuchblock
    )

    assert_raise(NotImplementedError) { renderer.visit(node) }
  end
end
