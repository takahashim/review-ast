# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/indexer'
require 'review/index_builder'
require 'review/book'
require 'review/book/chapter'
require 'review/ast/compiler'
require 'review/configure'

class TestASTIndexer < Test::Unit::TestCase
  def setup
    @config = ReVIEW::Configure.values
    @config['secnolevel'] = 2
    @config['language'] = 'ja'
    @book = ReVIEW::Book::Base.new(config: @config)

    @log_io = StringIO.new
    ReVIEW.logger = ReVIEW::Logger.new(@log_io)

    @chapter = ReVIEW::Book::Chapter.new(@book, 1, 'test_chapter', 'test_chapter.re', StringIO.new)
    ReVIEW::I18n.setup(@config['language'])
  end

  def test_basic_index_building
    source = <<~EOS
      = Chapter Title

      Basic paragraph with text.

      //list[sample-code][Sample Code Caption][ruby]{
      puts "hello world"
      //}

      //table[sample-table][Sample Table Caption]{
      Header 1	Header 2
      ------------
      Cell 1	Cell 2
      //}

      //image[sample-image][Sample Image Caption]

      Text with @<fn>{footnote1} and @<eq>{equation1}.

      //footnote[footnote1][Footnote content]

      //texequation[equation1]{
      E = mc^2
      //}

      //footnote[footnote1][Footnote content]

      //texequation[equation1]{
      E = mc^2
      //}
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    list_entry = reg.lookup(:list, 'sample-code')
    assert_not_nil(list_entry)
    assert_equal 1, list_entry.number

    assert_equal 1, reg.ids(:table).size
    table_entry = reg.lookup(:table, 'sample-table')
    assert_not_nil(table_entry)
    assert_equal 1, table_entry.number
    assert_equal 'Sample Table Caption', table_entry.caption_node&.to_inline_text

    assert_equal 1, reg.ids(:image).size
    image_entry = reg.lookup(:image, 'sample-image')
    assert_not_nil(image_entry)
    assert_equal 1, image_entry.number
    assert_equal 'Sample Image Caption', image_entry.caption_node&.to_inline_text

    assert_equal 1, reg.ids(:footnote).size
    footnote_entry = reg.lookup(:footnote, 'footnote1')
    assert_not_nil(footnote_entry)
    assert_equal 1, footnote_entry.number

    assert_not_nil(reg.lookup(:equation, 'equation1'))
  end

  def test_headline_index_building
    source = <<~EOS
      = Chapter Title

      =={sec1} Section 1

      Basic text.

      =={sec2} Section 2

      More text.

      ==={subsec21} Subsection 2.1

      Subsection content.
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert reg.ids(:headline).size >= 2

    assert_equal [1], reg.lookup(:headline, 'sec1').number
    assert_equal [2], reg.lookup(:headline, 'sec2').number
    assert_equal [2, 1], reg.lookup(:headline, 'sec2|subsec21').number
  end

  def test_minicolumn_index_building
    source = <<~EOS
      = Chapter Title

      //note[Note Caption]{
      This is a note with @<fn>{note-footnote}.
      //}

      //memo[Memo Caption]{
      This is a memo with @<bib>{bibitem1}.
      //}

      //footnote[note-footnote][Note footnote]

      //bibpaper[bibitem1][Bib item content]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:footnote).size
    assert_not_nil(reg.lookup(:footnote, 'note-footnote'))

    assert_equal 1, reg.ids(:bibpaper).size
    assert_not_nil(reg.lookup(:bibpaper, 'bibitem1'))
  end

  def test_table_inline_elements
    source = <<~EOS
      = Chapter Title

      //table[inline-table][Table with inline elements]{
      Header @<b>{Bold}	@<i>{Italic} Header
      ------------
      Cell with @<fn>{table-fn}	@<eq>{table-eq}
      //}

      //footnote[table-fn][Table footnote]

      //texequation[table-eq]{
      x = y
      //}
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:table).size
    assert_not_nil(reg.lookup(:table, 'inline-table'))

    assert_equal 1, reg.ids(:footnote).size
    assert_not_nil(reg.lookup(:footnote, 'table-fn'))

    assert_equal 1, reg.ids(:equation).size
    assert_not_nil(reg.lookup(:equation, 'table-eq'))
  end

  def test_code_block_inline_elements
    source = <<~EOS
      = Chapter Title

      //list[code-with-inline][Code with inline elements][ruby]{
      puts @<b>{bold code}
      # Comment with @<fn>{code-fn}
      //}

      //footnote[code-fn][Footnote from code block]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:list).size
    assert_not_nil(reg.lookup(:list, 'code-with-inline'))

    assert_equal 1, reg.ids(:footnote).size
    assert_not_nil(reg.lookup(:footnote, 'code-fn'))
  end

  def test_empty_ast
    test_chapter = ReVIEW::Book::Chapter.new(@book, 1, 'empty_test', 'empty_test.re', StringIO.new)
    indexer = ReVIEW::AST::Indexer.new(test_chapter)
    result = indexer.build_indexes(nil)

    assert_equal indexer, result
    reg = indexer.registry
    assert_equal 0, reg.ids(:list).size
    assert_equal 0, reg.ids(:table).size
    assert_equal 0, reg.ids(:image).size
    assert_equal 0, reg.ids(:footnote).size
    assert_equal 0, reg.ids(:equation).size
  end

  def test_registry_records_elements
    source = <<~EOS
      = Chapter Title

      //list[sample][Sample]{
      code
      //}
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:list).size
    assert_not_nil(reg.lookup(:list, 'sample'))
    assert_equal 1, reg.lookup(:list, 'sample').number
  end

  def test_id_validation_warnings
    source = <<~EOS
      = Chapter Title

      //list[invalid#id][Invalid ID with #]{
      code
      //}

      //table[.starts_with_dot][ID starting with dot]{
      data
      //}

      Text with @<fn>{space id} and @<eq>{id with$pecial}.

      //footnote[space id][Footnote with space id]

      //texequation[id with$pecial]{
      z = 1
      //}
    EOS

    original_stderr = $stderr
    captured_stderr = StringIO.new
    $stderr = captured_stderr

    begin
      ast_root = compile_to_ast(source)

      indexer = ReVIEW::AST::Indexer.new(@chapter)
      indexer.build_indexes(ast_root)

      warnings = captured_stderr.string
      assert_include(warnings, 'deprecated ID: `#` in `invalid#id`')
      assert_include(warnings, 'deprecated ID: `.starts_with_dot` begins from `.`')
      assert_include(warnings, 'deprecated ID: ` ` in `space id`')
      assert_include(warnings, 'deprecated ID: `$` in `id with$pecial`')
    ensure
      $stderr = original_stderr
    end
  end

  def test_column_index_building
    source = <<~EOS
      = Chapter Title

      Regular paragraph.

      ===[column]{col1} Column Title

      Column content with @<fn>{col-footnote}.

      ===[/column]

      More content.

      //footnote[col-footnote][Column footnote content]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:column).size
    column_entry = reg.lookup(:column, 'col1')
    assert_not_nil(column_entry)
    assert_equal 'Column Title', column_entry.caption_node&.to_inline_text

    assert_equal 1, reg.ids(:footnote).size
    assert_not_nil(reg.lookup(:footnote, 'col-footnote'))
  end

  def test_endnote_index_building
    source = <<~EOS
      = Chapter Title

      Text with @<endnote>{endnote1} reference.

      //endnote[endnote1][Endnote content here]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:endnote).size
    endnote_entry = reg.lookup(:endnote, 'endnote1')
    assert_not_nil(endnote_entry)
    assert_equal 1, endnote_entry.number
  end

  def test_imgtable_index_building
    source = <<~EOS
      = Chapter Title

      //imgtable[table-image][Table as Image Caption]{
      dummy content
      //}
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:table).size
    assert_not_nil(reg.lookup(:table, 'table-image'))

    assert_equal 1, reg.ids(:indepimage).size
    assert_not_nil(reg.lookup(:indepimage, 'table-image'))
  end

  def test_bibpaper_block_index_building
    source = <<~EOS
      = Chapter Title

      Citation @<bib>{ref1} in text.

      //bibpaper[ref1][Author Name, "Book Title", Publisher, 2024]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:bibpaper).size
    bib_entry = reg.lookup(:bibpaper, 'ref1')
    assert_not_nil(bib_entry)
    assert_equal 'Author Name, "Book Title", Publisher, 2024', bib_entry.caption_node&.to_inline_text
  end

  def test_caption_inline_elements
    source = <<~EOS
      = Chapter Title

      //list[code-id][Caption with @<fn>{cap-fn} and @<bib>{cap-bib}]{
      code content
      //}

      //footnote[cap-fn][Caption footnote]
      //bibpaper[cap-bib][Bibliography in caption]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.ids(:list).size

    assert_equal 1, reg.ids(:footnote).size
    assert_not_nil(reg.lookup(:footnote, 'cap-fn'))

    assert_equal 1, reg.ids(:bibpaper).size
    assert_not_nil(reg.lookup(:bibpaper, 'cap-bib'))
  end

  def test_headline_caption_inline_elements
    source = <<~EOS
      = Chapter Title

      =={sec1} Section with @<fn>{head-fn} in title

      Content here.

      //footnote[head-fn][Headline footnote]
    EOS

    ast_root = compile_to_ast(source)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_not_nil(reg.lookup(:headline, 'sec1'))

    assert_equal 1, reg.ids(:footnote).size
    assert_not_nil(reg.lookup(:footnote, 'head-fn'))
  end

  def test_indepimage_does_not_advance_image_number
    # Regression (found by PBT): //indepimage and //numberlessimage are
    # unnumbered and must not increment the image counter. Otherwise a following
    # //image is numbered 1.2 instead of 1.1, so @<img> references diverge from
    # LATEXBuilder. They belong under :indepimage (matching IndexBuilder).
    source = <<~EOS
      = Chapter Title

      //indepimage[indep1][Indep caption]

      //numberlessimage[nl1][Numberless caption]

      //image[img1][Real image]
    EOS

    ast_root = compile_to_ast(source)
    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    # Only the numbered //image lands under :image, and it is 1.
    assert_equal 1, reg.ids(:image).size
    assert_equal 1, reg.lookup(:image, 'img1').number

    # indepimage and numberlessimage both go under :indepimage.
    assert_equal 2, reg.ids(:indepimage).size
    assert_not_nil(reg.lookup(:indepimage, 'indep1'))
    assert_not_nil(reg.lookup(:indepimage, 'nl1'))
  end

  private

  def compile_to_ast(content)
    @chapter.content = content

    @book.generate_indexes
    @chapter.generate_indexes

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_compiler.compile_to_ast(@chapter)
  end
end
