# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require 'review/ast/diff/byte_exact'

class TestIdgxmlRendererBuilderComparison < Test::Unit::TestCase
  def setup
    @converter = ReVIEW::Test::IdgxmlComparator.new
    # Byte equality is the criterion for IDGXML, so there is one comparator here
    # and not two. A whitespace-collapsing comparator used to judge most of
    # these cases while the byte-level regressions below were pinned separately,
    # which left "what counts as equal for IDGXML" answered twice.
    @comparator = ReVIEW::AST::Diff::ByteExact.new
  end

  # IDGXML is compared byte-for-byte (see ReVIEW::AST::Diff::ByteExact): the
  # output is compact and InDesign imports text literally, so any byte counts.
  # Each case below was a real builder-vs-renderer divergence found by the
  # byte-exact sweep. (convert_* strips the <?xml?><doc> wrapper, so these are
  # body-level; the wrapper newline is checked separately below.)
  def test_idgxml_byte_regressions
    byte = ReVIEW::AST::Diff::ByteExact.new
    {
      'endnote block has no extra newlines' => "本文@<endnote>{e}。\n\n//endnote[e][内容]\n\n//printendnotes",
      'numbered code detab includes lineno span width' => "//emlistnum{\ncol1\tcol2\tcol3\n//}",
      'box keeps content trailing newline' => "//box[題]{\nline\n//}",
      'nonum heading has no number' => "= 章\n\n==[nonum] 番号なし節",
      'notoc heading has no number and no dtp' => "= 章\n\n==[notoc] TOCなし節",
      # IDGXML derives per-column widths (aid:ccolwidth) from //tsize when it
      # targets idgxml. samples/*.re only carry |latex|-only //tsize, so the
      # corpus never exercises this; pin it here. (tableopt defaults to '10' in
      # the comparator, so @tablewidth is set and cell widths are computed.)
      'tsize generic applies to idgxml' => "//tsize[10,18,50]\n\n//table[t][C]{\nA\tB\tC\n============\nD\tE\tF\n//}",
      'tsize idgxml target applies' => "//tsize[|idgxml|10,18,50]\n\n//table[t][C]{\nA\tB\tC\n============\nD\tE\tF\n//}",
      'tsize latex+idgxml target applies' => "//tsize[|latex,idgxml|10,18,50]\n\n//table[t][C]{\nA\tB\tC\n============\nD\tE\tF\n//}",
      'tsize latex-only is ignored by idgxml' => "//tsize[|latex|10,18,50]\n\n//table[t][C]{\nA\tB\tC\n============\nD\tE\tF\n//}",
      # The //quote family (flushright/lead/centering/...) passes its lines to
      # split_paragraph untouched, so the author's leading indent survives
      # (a document-level paragraph, by contrast, strips it). IDGXML is
      # byte-exact so those spaces matter. Found via FirstStepReVIEW-v3.
      'flushright keeps leading spaces' => "//flushright{\n  （発行代表）\n//}",
      'quote keeps leading spaces' => "//quote{\n  引用文です\n//}",
      'centering keeps leading spaces' => "//centering{\n  中央寄せ\n//}",
      'document paragraph strips leading spaces' => "  通常段落\n"
    }.each do |name, source|
      b = @converter.convert_with_builder(source)
      r = @converter.convert_with_renderer(source)
      assert byte.equal?(b, r), "#{name}: byte mismatch\n#{byte.diff(b, r)}"
    end
  end

  # The XML declaration keeps its trailing newline before <doc>, matching
  # IDGXMLBuilder (`<?xml …?>\n<doc …>`).
  def test_idgxml_xml_declaration_newline
    require 'review/book'
    require 'review/renderer/idgxml_renderer'
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values.tap { |c| c['builder'] = 'idgxml' })
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new('本文'))
    chapter.generate_indexes
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    output = ReVIEW::Renderer::IdgxmlRenderer.new(chapter).render(ast)

    assert_match(/\A<\?xml version="1.0" encoding="UTF-8"\?>\n<doc /, output)
  end

  def test_simple_paragraph_comparison
    source = 'This is a simple paragraph.'

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'Simple paragraph should produce equivalent IDGXML'
  end

  def test_headline_comparison
    source = '= Chapter Title'

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'Headline should produce equivalent IDGXML'
  end

  def test_inline_formatting_comparison
    source = 'This has @<b>{bold} and @<i>{italic} and @<code>{code} text.'

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'Inline formatting should produce equivalent IDGXML'
  end

  def test_code_block_comparison
    source = <<~RE
      //list[example][Code Example]{
      def hello
        puts "Hello World"
      end
      //}
    RE

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?
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

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?
  end

  def test_list_comparison
    source = <<~RE
      * First item
      * Second item
      * Third item
    RE

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?
  end

  def test_note_block_comparison
    source = <<~RE
      //note[Note Title]{
      This is a note block.
      //}
    RE

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?
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
      ----------------------
      A	1
      B	2
      //}
    RE

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'Complex document differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts "Builder IDGXML: #{builder_idgxml.inspect}"
      puts "Renderer IDGXML: #{renderer_idgxml.inspect}"
      puts result.pretty_diff
    end

    assert result.same_hash?
  end

  # Tests with actual Re:VIEW files from samples/syntax-book
  def test_syntax_book_ch01
    file_path = File.join(__dir__, '../../samples/syntax-book/ch01.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'ch01.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'ch01.re should produce equivalent IDGXML'
  end

  def test_syntax_book_ch02
    book_dir = File.join(__dir__, '../../samples/syntax-book')
    result = @converter.convert_chapter_with_book_context(book_dir, 'ch02')

    builder_idgxml = result[:builder]
    renderer_idgxml = result[:renderer]

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'ch02.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'ch02.re should produce equivalent IDGXML'
  end

  def test_syntax_book_ch03
    file_path = File.join(__dir__, '../../samples/syntax-book/ch03.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'ch03.re differences found:'
      puts "Builder IDGXML: #{builder_idgxml}"
      puts "Renderer IDGXML: #{renderer_idgxml}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'ch03.re should produce equivalent IDGXML'
  end

  def test_syntax_book_pre01
    file_path = File.join(__dir__, '../../samples/syntax-book/pre01.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'pre01.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'pre01.re should produce equivalent IDGXML'
  end

  def test_syntax_book_appA
    file_path = File.join(__dir__, '../../samples/syntax-book/appA.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'appA.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'appA.re should produce equivalent IDGXML'
  end

  def test_syntax_book_part2
    file_path = File.join(__dir__, '../../samples/syntax-book/part2.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'part2.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'part2.re should produce equivalent IDGXML'
  end

  def test_syntax_book_bib
    book_dir = File.join(__dir__, '../../samples/syntax-book')
    result = @converter.convert_chapter_with_book_context(book_dir, 'bib')

    builder_idgxml = result[:builder]
    renderer_idgxml = result[:renderer]

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'bib.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'bib.re should produce equivalent IDGXML'
  end

  # Tests with actual Re:VIEW files from samples/debug-book
  def test_debug_book_advanced_features
    file_path = File.join(__dir__, '../../samples/debug-book/advanced_features.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'advanced_features.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'advanced_features.re should produce equivalent IDGXML'
  end

  def test_debug_book_comprehensive
    file_path = File.join(__dir__, '../../samples/debug-book/comprehensive.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'comprehensive.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'comprehensive.re should produce equivalent IDGXML'
  end

  def test_debug_book_edge_cases_test
    file_path = File.join(__dir__, '../../samples/debug-book/edge_cases_test.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'edge_cases_test.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'edge_cases_test.re should produce equivalent IDGXML'
  end

  def test_debug_book_extreme_features
    file_path = File.join(__dir__, '../../samples/debug-book/extreme_features.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'extreme_features.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'extreme_features.re should produce equivalent IDGXML'
  end

  def test_debug_book_multicontent_test
    file_path = File.join(__dir__, '../../samples/debug-book/multicontent_test.re')
    source = File.read(file_path)

    builder_idgxml = @converter.convert_with_builder(source)
    renderer_idgxml = @converter.convert_with_renderer(source)

    result = @comparator.compare(builder_idgxml, renderer_idgxml)

    unless result.same_hash?
      puts 'multicontent_test.re differences found:'
      puts "Builder IDGXML length: #{builder_idgxml.length}"
      puts "Renderer IDGXML length: #{renderer_idgxml.length}"
      puts result.pretty_diff
    end

    assert result.same_hash?, 'multicontent_test.re should produce equivalent IDGXML'
  end
end
