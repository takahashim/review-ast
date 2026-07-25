# frozen_string_literal: true

require_relative '../test_helper'
require 'review'
require 'review/ast'
require 'review/renderer/html_renderer'
require 'review/renderer/typst_renderer'
require 'tmpdir'
require 'fileutils'

# Heading numbers must read the same in HTML and in Typst.
#
# Both renderers count with their own SecCounter, so "Re:VIEW owns the numbers"
# (doc/design-typst.md) is only a claim about the design until
# something compares the two outputs. Chapters, appendices, parts and the
# unnumbered heading tags each have their own path through that counting, which
# is why they all appear in the fixture below.
class TestTypstHeadingNumberParity < Test::Unit::TestCase
  def setup
    @config = ReVIEW::Configure.values
    ReVIEW::I18n.setup(@config['language'])
  end

  def test_heading_numbers_match_between_html_and_typst
    Dir.mktmpdir do |dir|
      write_book(dir)
      book = ReVIEW::Book::Base.new(dir, config: @config)

      seen = []
      book.chapters.each do |chapter|
        html = heading_numbers_from_html(chapter)
        typst = heading_numbers_from_typst(chapter)
        assert_equal(html, typst, "heading numbers differ in #{chapter.id}")
        seen.concat(html)
      end

      # Both extractions returning nothing would make the comparison above pass
      # without comparing anything, so pin the numbers the fixture must produce.
      assert_equal(%w[第1章 1.1 1.2 1.3 1.4 第2章 2.1 付録A A.1 A.2], seen)
    end
  end

  # A chapter with no number of its own must not give its sections one.
  def test_frontmatter_chapter_is_unnumbered_in_both
    Dir.mktmpdir do |dir|
      write_book(dir)
      book = ReVIEW::Book::Base.new(dir, config: @config)
      chapter = book.chapters.find { |c| c.id == 'pre01' }

      assert_empty(heading_numbers_from_html(chapter))
      assert_empty(heading_numbers_from_typst(chapter))
    end
  end

  # The heading in a part's own file carries no number in either format: the
  # part number belongs to the part page the maker builds, not to this heading.
  def test_part_file_heading_is_unnumbered_in_both
    Dir.mktmpdir do |dir|
      write_book(dir)
      book = ReVIEW::Book::Base.new(dir, config: @config)
      part = book.parts_in_file.first
      assert_not_nil(part, 'the fixture should contain a part with its own file')

      assert_empty(heading_numbers_from_html(part))
      assert_empty(heading_numbers_from_typst(part))
    end
  end

  private

  def render(renderer_class, chapter)
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    renderer_class.new(chapter).render(ast)
  end

  # HTML prints the number in a secno span, followed by I18n's chapter_postfix.
  def heading_numbers_from_html(chapter)
    output = render(ReVIEW::Renderer::HtmlRenderer, chapter)
    output.scan(%r{<span class="secno">(.*?)</span>}).flatten.map { |n| normalize(n) }
  end

  # Typst carries it as number-text on the heading call. Figures and tables use
  # the same argument name, so only the heading calls are scanned.
  def heading_numbers_from_typst(chapter)
    output = render(ReVIEW::Renderer::TypstRenderer, chapter)
    output.lines.filter_map do |line|
      next unless line.start_with?('#review.chapter(', '#review.section(', '#review.part(')

      match = line.match(/number-text: \[(.*?)\]/)
      normalize(match[1]) if match
    end
  end

  # The separator between the number and the title belongs to the format, not to
  # the number: HTML keeps I18n's chapter_postfix inside the span, Typst leaves
  # the spacing to the theme.
  def normalize(number)
    number.gsub(/[[:space:]　]/, '')
  end

  def write_book(dir)
    File.write(File.join(dir, 'config.yml'), <<~YAML)
      bookname: book
      booktitle: 番号一致テスト
      language: ja
    YAML

    File.write(File.join(dir, 'catalog.yml'), <<~YAML)
      PREDEF:
        - pre01.re
      CHAPS:
        - ch01.re
        - part2.re:
          - ch02.re
      APPENDIX:
        - appA.re
      POSTDEF:
        - post01.re
    YAML

    # A front-matter chapter carries no chapter number, so its sections must not
    # show one either.
    File.write(File.join(dir, 'pre01.re'), "= 前書き\n\n== 前書きの節\n\n本文。\n")

    # nonum / notoc / nodisp must not consume a number: the section after each
    # of them keeps the number it would otherwise have had.
    File.write(File.join(dir, 'ch01.re'), <<~RE)
      = 第一章

      == 一節

      ==[nonum] 番号なし

      == 二節

      ===[notoc] 目次に出ない

      == 三節

      === 深い項

      ==[nodisp] 表示しない

      == 四節
    RE

    File.write(File.join(dir, 'part2.re'), "= 部の扉\n\n部の説明。\n")
    File.write(File.join(dir, 'ch02.re'), "= 第二章\n\n== 節\n\n=== 項\n")

    # An appendix numbers its chapter "A", which changes every section number
    # under it.
    File.write(File.join(dir, 'appA.re'), "= 付録\n\n== 付録の節\n\n== 付録の二節\n")

    File.write(File.join(dir, 'post01.re'), "= 後書き\n\n== 後書きの節\n")
  end
end
