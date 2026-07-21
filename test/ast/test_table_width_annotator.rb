# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/table_width_annotator'
require 'tmpdir'

class TableWidthAnnotatorTest < Test::Unit::TestCase
  def annotate(source)
    ReVIEW::AST::TableWidthAnnotator.new('.').annotate_source(source)
  end

  def test_numeric_spec_becomes_fixed_layout_and_colgroup
    source = %Q(<table data-tsize="10,18,50">\n<tr><td>a</td></tr>\n</table>)
    result = annotate(source)
    assert_include(result, 'style="table-layout: fixed; width: 78mm"')
    assert_include(result,
                   '<colgroup><col style="width: 10mm" />' \
                   '<col style="width: 18mm" /><col style="width: 50mm" /></colgroup>')
  end

  def test_p_column_spec_contributes_widths
    source = %Q(<table data-tsize="p{10mm}p{18mm}|p{50mm}"><tr><td>a</td></tr></table>)
    result = annotate(source)
    assert_include(result, 'width: 78mm')
    assert_include(result, '<col style="width: 50mm" />')
  end

  def test_mixed_spec_gets_colgroup_but_no_fixed_layout
    source = %Q(<table data-tsize="lp{50mm}"><tr><td>a</td></tr></table>)
    result = annotate(source)
    assert_include(result, '<colgroup><col /><col style="width: 50mm" /></colgroup>')
    assert_not_include(result, 'table-layout')
  end

  def test_latex_only_spec_is_ignored
    source = %Q(<table data-tsize="|latex|p{10mm}p{50mm}"><tr><td>a</td></tr></table>)
    assert_equal source, annotate(source)
  end

  def test_vivliostyle_target_spec_is_honored
    source = %Q(<table data-tsize="|vivliostyle|20,30"><tr><td>a</td></tr></table>)
    result = annotate(source)
    assert_include(result, 'width: 50mm')
  end

  def test_html_target_spec_is_honored
    source = %Q(<table data-tsize="|html|20,30"><tr><td>a</td></tr></table>)
    assert_include(annotate(source), 'width: 50mm')
  end

  def test_unresolvable_widths_leave_table_untouched
    source = %Q(<table data-tsize="lcr"><tr><td>a</td></tr></table>)
    assert_equal source, annotate(source)
  end

  def test_table_without_tsize_is_untouched
    source = '<table><tr><td>a</td></tr></table>'
    assert_equal source, annotate(source)
  end

  def test_attribute_value_is_html_unescaped
    source = %Q(<table data-tsize="p{10mm}&gt;p{20mm}"><tr><td>a</td></tr></table>)
    result = annotate(source)
    # The unescaped ">" is not a column spec letter with a width, so the
    # column it forms has none; the p columns still get theirs.
    assert_include(result, '<col style="width: 10mm" />')
  end

  def test_annotate_rewrites_files_under_root
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.xhtml'),
                 %Q(<table data-tsize="10,20"><tr><td>a</td></tr></table>))
      File.write(File.join(dir, 'b.xhtml'), '<table><tr><td>a</td></tr></table>')
      changed = ReVIEW::AST::TableWidthAnnotator.new(dir).annotate
      assert_equal 1, changed
      assert_include(File.read(File.join(dir, 'a.xhtml')), 'colgroup')
    end
  end
end
