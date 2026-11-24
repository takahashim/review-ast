# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/text_comparator'

# Semantic checks for the plain-text renderers against the legacy builders.
#
# LaTeX, HTML and IDGXML each had a comparator holding them to their builder;
# plaintext and TOP had none, and had drifted: section numbers were missing
# entirely, //firstlinenum was ignored by TOP, and several block markers were
# wrong or absent. These tests pin the information the output has to carry.
#
# They deliberately do not demand byte equality. The remaining differences from
# the builders are layout (where blank lines fall, how wide a table rule is) and
# one improvement -- nested list items keep their nesting here, where the
# builders flatten them -- so exact-match assertions would lock in noise.
class TestTextRendererSemantics < Test::Unit::TestCase
  def plaintext(source)
    ReVIEW::Test::TextComparator.new(format: :plaintext).convert_with_renderer(source)
  end

  def top(source)
    ReVIEW::Test::TextComparator.new(format: :top).convert_with_renderer(source)
  end

  def builder_plaintext(source)
    ReVIEW::Test::TextComparator.new(format: :plaintext).convert_with_builder(source)
  end

  NUMBERED_HEADINGS = "= 章\n\n== 節\n\n=== 項\n"

  def test_section_numbers_are_rendered
    # Was missing: headline_prefix returned '' for every level below the
    # chapter, so no text output carried section numbers at all.
    assert_include(plaintext(NUMBERED_HEADINGS), '第1章　章')
    assert_include(plaintext(NUMBERED_HEADINGS), '1.1　節')
    assert_include(top(NUMBERED_HEADINGS), '■H2■1.1　節')

    # secnolevel defaults to 2, so the level-3 heading is left unnumbered --
    # as the builders leave it.
    assert_include(plaintext(NUMBERED_HEADINGS), "\n項\n")
  end

  def test_deeper_numbering_follows_secnolevel
    comparator = ReVIEW::Test::TextComparator.new(format: :plaintext, config: { 'secnolevel' => 3 })

    assert_include(comparator.convert_with_renderer(NUMBERED_HEADINGS), '1.1.1　項')
  end

  def test_section_numbers_match_the_builder
    assert_equal builder_plaintext(NUMBERED_HEADINGS).scan(/^[\d.]+/),
                 plaintext(NUMBERED_HEADINGS).scan(/^[\d.]+/)
  end

  def test_secnolevel_limits_numbering
    comparator = ReVIEW::Test::TextComparator.new(format: :plaintext, config: { 'secnolevel' => 1 })
    output = comparator.convert_with_renderer(NUMBERED_HEADINGS)

    assert_include(output, '第1章　章')
    assert_include(output, "\n節\n")
    assert_not_include(output, '1.1　節')
  end

  NONUM_HEADINGS = "= 章\n\n==[nonum] 番号なし\n\n== 番号あり\n"

  def test_nonum_heading_is_unnumbered_and_does_not_consume_a_number
    # The counter must not advance for [nonum], or every later section shifts.
    output = plaintext(NONUM_HEADINGS)

    assert_include(output, "\n番号なし\n")
    assert_include(output, '1.1　番号あり')
    assert_equal builder_plaintext(NONUM_HEADINGS), output
  end

  def test_notoc_heading_carries_the_dtp_note_in_top
    output = top("= 章\n\n==[notoc] 目次に出さない\n")

    assert_include(output, '■H2■目次に出さない◆→DTP連絡:目次に掲載しない←◆')
  end

  def test_nodisp_heading_is_omitted
    assert_not_include(plaintext("= 章\n\n==[nodisp] 隠す\n"), '隠す')
    assert_not_include(top("= 章\n\n==[nodisp] 隠す\n"), '隠す')
  end

  FIRSTLINENUM = "= 章\n\n//firstlinenum[100]\n//listnum[id1][キャプション]{\ncode1\ncode2\n//}\n"

  def test_firstlinenum_is_honoured
    # TOP hardcoded the start at 1, so //firstlinenum was silently dropped.
    assert_include(top(FIRSTLINENUM), '100: code1')
    assert_include(top(FIRSTLINENUM), '101: code2')
    assert_include(plaintext(FIRSTLINENUM), '100: code1')
  end

  def test_listnum_caption_is_numbered
    # PLAINTEXTBuilder#listnum runs the caption through list_header; the bare
    # caption was used instead, dropping the list number.
    assert_include(plaintext(FIRSTLINENUM), 'リスト1.1　キャプション')
  end

  def test_numbered_list_block_marker_matches_the_builder
    # TOPBuilder reuses the 'list' title for listnum rather than inventing a
    # "連番付きリスト" marker.
    assert_include(top(FIRSTLINENUM), '◆→開始:リスト←◆')
    assert_not_include(top(FIRSTLINENUM), '連番付き')
  end

  def test_definition_term_is_bracketed_in_top
    output = top("= 章\n\n : 用語\n\t説明\n")

    assert_include(output, '★用語☆')
  end

  def test_column_keeps_its_block_markers_in_top
    # A column used to render as bare text, indistinguishable from body copy.
    output = top("= 章\n\n===[column] コラム見出し\n\nコラム本文\n\n===[/column]\n")

    assert_include(output, '◆→開始:コラム←◆')
    assert_include(output, '■コラム見出し')
    assert_include(output, '◆→終了:コラム←◆')
  end

  def test_unnumbered_image_caption_is_labelled_in_top
    # //indepimage has no number, and used to fall back to "■<id>■", naming the
    # id instead of labelling the figure.
    output = top("= 章\n\n//indepimage[img1][独立画像]\n")

    assert_include(output, '図　独立画像')
    assert_not_include(output, '■img1■')
  end

  REFERENCES = <<~RE
    = 章

    //image[img1][図キャプション]{
    //}

    //table[tbl1][表キャプション]{
    A\tB
    //}

    //list[lst1][リストキャプション]{
    code
    //}

    参照 @<img>{img1} @<table>{tbl1} @<list>{lst1} 終わり。
  RE

  def test_references_render_as_numbers_not_ids
    # plaintext returned the ReferenceNode's content, which is the reference's
    # own id, so every @<img>/@<table>/@<list> named the id instead of the
    # number.
    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format)
      line = comparator.convert_with_renderer(REFERENCES).lines.grep(/参照/).first

      assert_equal '参照 図1.1 表1.1 リスト1.1 終わり。', line.chomp, "#{format} reference text"
      assert_not_include(line, 'img1')
    end
  end

  def test_references_match_the_builder
    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format)

      assert_equal comparator.convert_with_builder(REFERENCES).lines.grep(/参照/),
                   comparator.convert_with_renderer(REFERENCES).lines.grep(/参照/),
                   "#{format} reference line"
    end
  end

  def test_deep_headline_reference_drops_the_number_beyond_secnolevel
    # The builders switch to hd_quote_without_number past secnolevel; the
    # formatter numbered at any depth, so IDGXML printed "「1.1.1.1 段」".
    source = "= 章\n\n== 節\n\n=== 項\n\n===={deep} 段\n\n参照 @<hd>{deep} 終わり。\n"
    comparator = ReVIEW::Test::TextComparator.new(format: :plaintext)

    assert_equal comparator.convert_with_builder(source).lines.grep(/参照/),
                 comparator.convert_with_renderer(source).lines.grep(/参照/)
  end

  def test_image_marker_names_the_file_not_the_id
    # An unbound image warns and falls back to the body; either way the marker
    # must never be built from the id.
    output = top("= 章\n\n//image[img1][キャプション]{\n代替テキスト\n//}\n")

    assert_not_include(output, '◆→img1←◆')
  end

  # Each of these was a command whose output dropped information the builder
  # kept. They are checked against the builder line for line rather than by
  # pattern, since the point is that the two agree.
  #
  # source => the lines to compare, per format
  DROPPED_INFORMATION = {
    'キーワード@<kw>{キーワード, keyword}です。' => /キーワード/,
    'UTF@<uchar>{3042}です。' => /UTF/,
    '削除@<del>{del削除}です。' => /削除/,
    "//noindent\n段落です。" => /段落/,
    "//texequation[eq1][式のキャプション]{\nE = mc^2\n//}" => /式/
  }.freeze

  data(DROPPED_INFORMATION.keys.to_h { |src| [src, src] })
  def test_command_keeps_what_the_builder_keeps(source)
    pattern = DROPPED_INFORMATION.fetch(source)
    document = "= 章\n\n#{source}\n"

    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format)

      assert_equal comparator.convert_with_builder(document).lines.grep(pattern),
                   comparator.convert_with_renderer(document).lines.grep(pattern),
                   "#{format}: #{source.inspect}"
    end
  end

  def test_ordered_items_keep_their_written_numbers
    # TOPBuilder#ol_item / PLAINTEXTBuilder#ol_item print the number each item
    # was written with: the renderers counted up from 1 (or from //olnum),
    # renumbering "3. 3. 7." as 3, 4, 5. //olnum does not renumber a text list.
    source = "= 章\n\n 3. 三\n 3. また三\n 7. 七\n\n//olnum[10]\n\n 1. 一\n 2. 二\n"

    assert_equal ["3\t三\n", "3\tまた三\n", "7\t七\n", "1\t一\n", "2\t二\n"], top(source).lines.grep(/\A\d+\t/)
    assert_equal builder_plaintext(source).lines.grep(/\A\d+　/), plaintext(source).lines.grep(/\A\d+　/)
  end

  def test_emtable_caption_carries_no_block_marker
    # An id-less table goes through table_header, which prints the caption bare;
    # the ■ that other TOP block captions carry does not belong here.
    output = top("= 章\n\n//emtable[説明表]{\nA\tB\n//}\n")

    assert_include(output, "\n説明表\n")
    assert_not_include(output, '■説明表')
  end

  def test_endnote_is_printed_only_where_printendnotes_asks
    # The //endnote definition also rendered in place, so every endnote
    # appeared twice.
    source = "= 章\n\n本文@<endnote>{en1}です。\n\n//endnote[en1][後注の内容]\n\n//printendnotes\n"

    assert_equal 1, plaintext(source).scan('後注の内容').size
    assert_equal 1, top(source).scan('後注の内容').size
    # Builder#inline_endnote's reference form, which plain text had as a bare
    # number.
    assert_include(plaintext(source), '本文(1)です。')
  end

  # @<sec> and @<sectitle> both fell through to the @<hd> form, so three
  # commands printed the same thing.
  def test_section_commands_differ_from_each_other
    source = "= 章\n\n=={target} 節\n\n@<hd>{target}／@<sec>{target}／@<sectitle>{target}\n"

    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format)

      assert_equal comparator.convert_with_builder(source).lines.grep(/／/),
                   comparator.convert_with_renderer(source).lines.grep(/／/),
                   format.to_s
    end
  end

  def test_paragraph_source_line_breaks_are_folded
    # A paragraph's newlines are source formatting; every builder folds them
    # away. The text renderers kept them, so paragraphs came out pre-wrapped at
    # the author's line breaks.
    source = "= 章\n\n一行目の続きが\n二行目にあります。\n"

    assert_include(plaintext(source), '一行目の続きが二行目にあります。')
    assert_include(top(source), '一行目の続きが二行目にあります。')
  end
end
