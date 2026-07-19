# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/table_column_width_parser'

class TestTableColumnWidthParser < Test::Unit::TestCase
  def test_default_spec
    parser = ReVIEW::AST::TableColumnWidthParser.new(nil, 3)
    result = parser.parse
    assert_equal '|l|l|l|', result.col_spec
    assert_equal ['l', 'l', 'l'], result.cellwidth
  end

  def test_empty_spec
    parser = ReVIEW::AST::TableColumnWidthParser.new('', 3)
    result = parser.parse
    assert_equal '|l|l|l|', result.col_spec
    assert_equal ['l', 'l', 'l'], result.cellwidth
  end

  def test_simple_format
    parser = ReVIEW::AST::TableColumnWidthParser.new('10,18,50', 3)
    result = parser.parse
    assert_equal '|p{10mm}|p{18mm}|p{50mm}|', result.col_spec
    assert_equal ['p{10mm}', 'p{18mm}', 'p{50mm}'], result.cellwidth
  end

  def test_complex_format
    parser = ReVIEW::AST::TableColumnWidthParser.new('p{10mm}p{18mm}|p{50mm}', 3)
    result = parser.parse
    assert_equal 'p{10mm}p{18mm}|p{50mm}', result.col_spec
    assert_equal ['p{10mm}', 'p{18mm}', 'p{50mm}'], result.cellwidth
  end

  def test_complex_format_with_lcr
    parser = ReVIEW::AST::TableColumnWidthParser.new('|l|c|r|', 3)
    result = parser.parse
    assert_equal '|l|c|r|', result.col_spec
    assert_equal ['l', 'c', 'r'], result.cellwidth
  end

  def test_invalid_col_count_zero
    assert_raise(ArgumentError) do
      ReVIEW::AST::TableColumnWidthParser.new('10,20', 0)
    end
  end

  def test_invalid_col_count_negative
    assert_raise(ArgumentError) do
      ReVIEW::AST::TableColumnWidthParser.new('10,20', -1)
    end
  end

  def test_invalid_col_count_nil
    assert_raise(ArgumentError) do
      ReVIEW::AST::TableColumnWidthParser.new('10,20', nil)
    end
  end

  def test_simple_format_with_spaces
    parser = ReVIEW::AST::TableColumnWidthParser.new('10, 18, 50', 3)
    result = parser.parse
    assert_equal '|p{10mm}|p{18mm}|p{50mm}|', result.col_spec
    assert_equal ['p{10mm}', 'p{18mm}', 'p{50mm}'], result.cellwidth
  end

  def test_complex_with_mixed_alignment
    parser = ReVIEW::AST::TableColumnWidthParser.new('lcr', 3)
    result = parser.parse
    assert_equal 'lcr', result.col_spec
    assert_equal ['l', 'c', 'r'], result.cellwidth
  end

  def test_complex_with_pipes_and_braces
    parser = ReVIEW::AST::TableColumnWidthParser.new('|p{10mm}|p{18mm}|p{50mm}|', 3)
    result = parser.parse
    assert_equal '|p{10mm}|p{18mm}|p{50mm}|', result.col_spec
    assert_equal ['p{10mm}', 'p{18mm}', 'p{50mm}'], result.cellwidth
  end

  def test_parse_returns_struct
    parser = ReVIEW::AST::TableColumnWidthParser.new('10,20', 2)
    result = parser.parse
    assert_instance_of(ReVIEW::AST::TableColumnWidthParser::Result, result)
    assert result.respond_to?(:col_spec)
    assert result.respond_to?(:cellwidth)
  end

  def test_parse_can_be_called_multiple_times
    parser = ReVIEW::AST::TableColumnWidthParser.new('10,20', 2)
    result1 = parser.parse
    result2 = parser.parse
    assert_equal result1, result2
  end

  # value_for_target resolves the |builder| prefix at render time.
  def test_value_for_target_generic_applies_to_all
    assert_equal '10,20,30', ReVIEW::AST::TableColumnWidthParser.value_for_target('10,20,30', 'latex')
    assert_equal '10,20,30', ReVIEW::AST::TableColumnWidthParser.value_for_target('10,20,30', 'idgxml')
  end

  def test_value_for_target_matching_builder
    raw = '|latex,idgxml|10,20,30'
    assert_equal '10,20,30', ReVIEW::AST::TableColumnWidthParser.value_for_target(raw, 'latex')
    assert_equal '10,20,30', ReVIEW::AST::TableColumnWidthParser.value_for_target(raw, 'idgxml')
  end

  def test_value_for_target_non_matching_builder
    assert_nil(ReVIEW::AST::TableColumnWidthParser.value_for_target('|html|10,20,30', 'latex'))
  end

  # A LaTeX column spec like |l|c|r| has single-char parts, so it is generic, not
  # a builder target.
  def test_value_for_target_latex_colspec_is_generic
    assert_equal '|l|c|r|', ReVIEW::AST::TableColumnWidthParser.value_for_target('|l|c|r|', 'latex')
    assert_equal '|l|c|r|', ReVIEW::AST::TableColumnWidthParser.value_for_target('|l|c|r|', 'idgxml')
  end

  def test_value_for_target_nil
    assert_nil(ReVIEW::AST::TableColumnWidthParser.value_for_target(nil, 'latex'))
  end
end
