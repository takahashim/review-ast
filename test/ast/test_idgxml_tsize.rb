# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'

# IDGXML reads the per-column table widths straight from the source //tsize
# numeric CSV (doc/design-improvements #5), rather than routing through the LaTeX
# p{Nmm} vocabulary. These tests pin that the AST IdgxmlRenderer produces the same
# aid:ccolwidth values as the legacy IDGXMLBuilder oracle.
class TestIdgxmlTsize < Test::Unit::TestCase
  def widths(source)
    comp = ReVIEW::Test::IdgxmlComparator.new(
      config: { 'tableopt' => '160', 'pt_to_mm_unit' => 0.3514 }
    )
    builder = comp.convert_with_builder(source).scan(/ccolwidth="([^"]+)"/).flatten
    renderer = comp.convert_with_renderer(source).scan(/ccolwidth="([^"]+)"/).flatten
    [builder, renderer]
  end

  def table(tsize, cols: 3)
    header = (0...cols).map { |i| "h#{i}" }.join("\t")
    body = (0...cols).map { |i| "c#{i}" }.join("\t")
    "= C\n\n//tsize[#{tsize}]\n//table[t][cap]{\n#{header}\n------------\n#{body}\n//}\n"
  end

  def test_numeric_tsize_matches_builder
    b, r = widths(table('|idgxml|30,40,90'))
    assert_equal b, r
    assert_equal 3, r.uniq.size, 'three distinct source widths'
  end

  def test_generic_numeric_tsize_matches_builder
    b, r = widths(table('20,50', cols: 2))
    assert_equal b, r
  end

  # A LaTeX column spec is meaningless for IDGXML: both the builder and the
  # renderer ignore it and distribute the columns equally.
  def test_latex_colspec_tsize_falls_back_to_equal_distribution
    b, r = widths(table('|l|c|r|'))
    assert_equal b, r
    assert_equal 1, r.uniq.size, 'equal distribution -> one distinct width'
  end

  # //tsize targeting only latex leaves IDGXML with no width -> equal distribution.
  def test_latex_only_tsize_is_ignored_by_idgxml
    b, r = widths(table('|latex|p{10mm}p{18mm}|p{50mm}'))
    assert_equal b, r
    assert_equal 1, r.uniq.size
  end
end
