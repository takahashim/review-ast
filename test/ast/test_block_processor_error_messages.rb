# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/compiler'
require 'review/configure'
require 'review/book'
require 'review/i18n'

class TestBlockProcessorErrorMessages < Test::Unit::TestCase
  def setup
    @config = ReVIEW::Configure.values
    @config['language'] = 'ja'
    @book = ReVIEW::Book::Base.new(config: @config)
    @log_io = StringIO.new
    ReVIEW.logger = ReVIEW::Logger.new(@log_io)
    ReVIEW::I18n.setup(@config['language'])
  end

  def test_unknown_block_command_error_message
    content = "= Chapter\n\n//unknown_command{\ncontent\n//}"

    chapter = ReVIEW::Book::Chapter.new(
      @book,
      1,
      'test',
      'sample.re',
      StringIO.new(content)
    )

    error = assert_raises(ReVIEW::CompileError) do
      compiler = ReVIEW::AST::Compiler.for_chapter(chapter)
      compiler.compile_to_ast(chapter)
    end

    # Verify error message contains expected information
    assert_match(%r{Unknown block command: //unknown}, error.message)
    assert_match(/at line 3/, error.message)
    assert_match(/in sample\.re/, error.message)
  end

  def test_blank_table_row_is_not_an_error
    # A blank line in a table is an empty row, as Builder#parse_table_rows
    # reads it, padded out to the table's columns.
    content = "= Chapter\n\n//table[id][caption]{\nA\tB\n\nC\tD\n//}"
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'test', 'table_test.re', StringIO.new(content))

    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    table = ast.children.find { |node| node.is_a?(ReVIEW::AST::TableNode) }
    assert_equal([2, 2, 2], table.body_rows.map { |row| row.children.size })
  end

  # NOTE: The unknown code block type test is harder to trigger in practice
  # since CODE_BLOCK_CONFIGS covers most common types, and it would require
  # internal method access that changes based on implementation details.

  def test_error_message_formatting
    content = "= Chapter\n\n//invalid_block{\ncontent\n//}"

    chapter = ReVIEW::Book::Chapter.new(
      @book,
      1,
      'test',
      'format_test.re',
      StringIO.new(content)
    )

    error = assert_raises(ReVIEW::CompileError) do
      compiler = ReVIEW::AST::Compiler.for_chapter(chapter)
      compiler.compile_to_ast(chapter)
    end

    # Test the general format of location info
    assert_match(/at line 3/, error.message)
    assert_match(/in \w+\.re/, error.message)
  end
end
