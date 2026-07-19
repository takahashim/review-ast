# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/indexer'
require 'review/book'
require 'review/book/chapter'
require 'review/ast/compiler'

class TestASTIndexerPure < Test::Unit::TestCase
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

    @chapter.content = source

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_root = ast_compiler.compile_to_ast(@chapter)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_equal 1, reg.lookup(:list, 'sample-code').number

    assert_equal 1, reg.ids(:table).size
    assert_equal 1, reg.lookup(:table, 'sample-table').number
    assert_equal 'Sample Table Caption', reg.lookup(:table, 'sample-table').caption_node&.to_inline_text

    assert_equal 1, reg.ids(:image).size
    assert_equal 1, reg.lookup(:image, 'sample-image').number
    assert_equal 'Sample Image Caption', reg.lookup(:image, 'sample-image').caption_node&.to_inline_text

    assert_equal 1, reg.ids(:footnote).size
    assert_equal 1, reg.lookup(:footnote, 'footnote1').number

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

    @chapter.content = source

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_root = ast_compiler.compile_to_ast(@chapter)

    indexer = ReVIEW::AST::Indexer.new(@chapter)
    indexer.build_indexes(ast_root)

    reg = indexer.registry
    assert_operator(reg.ids(:headline).size, :>=, 2)

    assert_equal [1], reg.lookup(:headline, 'sec1').number
    assert_equal [2], reg.lookup(:headline, 'sec2').number
    # Addressable by full pipe-path and by leaf alone.
    assert_equal [2, 1], reg.lookup(:headline, 'sec2|subsec21').number
    assert_equal [2, 1], reg.lookup(:headline, 'subsec21').number
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

    @chapter.content = source

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_root = ast_compiler.compile_to_ast(@chapter)

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

    @chapter.content = source

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_root = ast_compiler.compile_to_ast(@chapter)

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

    @chapter.content = source

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_root = ast_compiler.compile_to_ast(@chapter)

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

    @chapter.content = source

    ast_compiler = ReVIEW::AST::Compiler.new
    ast_root = ast_compiler.compile_to_ast(@chapter)

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

    @chapter.content = source

    original_stderr = $stderr
    captured_stderr = StringIO.new
    $stderr = captured_stderr

    begin
      ast_compiler = ReVIEW::AST::Compiler.new
      ast_root = ast_compiler.compile_to_ast(@chapter)

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
end
