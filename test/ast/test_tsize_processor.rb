# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/compiler/tsize_processor'
require 'review/ast/directive_node'
require 'review/ast/table_node'
require 'review/ast/table_row_node'
require 'review/ast/table_cell_node'
require 'review/ast/document_node'
require 'review/book'
require 'review/book/chapter'

# TsizeProcessor attaches the raw //tsize argument to the next table as a
# source fact (target-neutral) and removes the directive. Resolving the builder
# target and deriving the column spec happen at render time, so those are tested
# at the parser / renderer level, not here.
class TestTsizeProcessor < Test::Unit::TestCase
  def setup
    @config = ReVIEW::Configure.values
    @config['builder'] = 'latex'
    @book = ReVIEW::Book::Base.new(config: @config)
    @chapter = ReVIEW::Book::Chapter.new(@book, 1, 'test', 'test.re', StringIO.new)
    @compiler = ReVIEW::AST::Compiler.new
  end

  def build_table(id, columns)
    table = ReVIEW::AST::TableNode.new(location: nil, id: id)
    row = ReVIEW::AST::TableRowNode.new(location: nil, row_type: :body)
    columns.times { row.add_child(ReVIEW::AST::TableCellNode.new(location: nil)) }
    table.add_body_row(row)
    table
  end

  def process(root)
    ReVIEW::AST::Compiler::TsizeProcessor.process(root, chapter: @chapter, compiler: @compiler)
  end

  def with_tsize(arg, columns)
    root = ReVIEW::AST::DocumentNode.new(location: nil)
    root.add_child(ReVIEW::AST::DirectiveNode.new(location: nil, directive_type: :tsize, args: [arg]))
    table = build_table('t', columns)
    root.add_child(table)
    process(root)
    [root, table]
  end

  def test_attaches_raw_tsize_and_removes_directive
    root, table = with_tsize('10,20,30', 3)
    assert_equal 1, root.children.length
    assert_equal table, root.children.first
    assert_equal '10,20,30', table.tsize
  end

  # The raw arg is attached verbatim; the |builder| target prefix is kept and
  # resolved at render time, not stripped or filtered here.
  def test_keeps_target_prefix_verbatim
    _root, table = with_tsize('|latex,idgxml|10,20,30', 3)
    assert_equal '|latex,idgxml|10,20,30', table.tsize
  end

  def test_does_not_filter_by_target
    _root, table = with_tsize('|html|10,20,30', 3)
    # Attached even though builder is latex; filtering is a render-time concern.
    assert_equal '|html|10,20,30', table.tsize
  end

  def test_keeps_complex_latex_spec_verbatim
    _root, table = with_tsize('|l|c|r|', 3)
    assert_equal '|l|c|r|', table.tsize
  end

  def test_multiple_tsize_commands
    root = ReVIEW::AST::DocumentNode.new(location: nil)
    root.add_child(ReVIEW::AST::DirectiveNode.new(location: nil, directive_type: :tsize, args: ['10,20']))
    table1 = build_table('table1', 2)
    root.add_child(table1)
    root.add_child(ReVIEW::AST::DirectiveNode.new(location: nil, directive_type: :tsize, args: ['30,40,50']))
    table2 = build_table('table2', 3)
    root.add_child(table2)

    process(root)

    assert_equal 2, root.children.length
    assert_equal '10,20', table1.tsize
    assert_equal '30,40,50', table2.tsize
  end
end
