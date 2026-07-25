# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

# Builds books whose *structure* is complete, and builds the real sample books.
#
# The other maker tests use a one-chapter fixture, which keeps them quick but
# leaves whole code paths untouched: a part with no .re file is written straight
# from the catalog and appears nowhere else, and that path once survived a
# namespace move with an unqualified constant in it -- every test passed while
# the sample books failed to build.
#
# So this file exists to be the slow, wide one. It walks the structures a real
# book has (front matter, parts of both kinds, appendix, back matter) and then
# builds the books in samples/ as they actually are.
class TestAstTypstMakerStructure < Test::Unit::TestCase
  BIN = File.expand_path('../../bin/review-ast-typstmaker', __dir__)
  SAMPLES = File.expand_path('../../samples', __dir__)

  def setup
    omit('typst command not found') unless system('typst', '--version', out: File::NULL, err: File::NULL)
  end

  # Every bucket the catalog can fill, and both kinds of part.
  def test_builds_a_book_with_every_structural_part
    Dir.mktmpdir do |dir|
      write_structured_book(dir)

      output = build(dir)
      chapters = File.join(dir, 'book-typst', 'chapters')

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      # A part named only in catalog.yml is generated; one with a file is
      # compiled. Both have to appear, and they take different code paths.
      assert(File.exist?(File.join(chapters, 'part-2.typ')), "no generated part page:\n#{output}")
      assert(File.exist?(File.join(chapters, 'part1.typ')), "no compiled part page:\n#{output}")
      assert_include(File.read(File.join(chapters, 'part-2.typ')), '#review.part(')
      assert_include(File.read(File.join(chapters, 'part1.typ')), '#review.part(')

      root = File.read(File.join(dir, 'book-typst', 'book.typ'))
      %w[book.frontmatter book.mainmatter book.appendix book.backmatter].each do |part|
        assert_include(root, "#show: #{part}")
      end
    end
  end

  # The books in samples/ use far more of Re:VIEW than any fixture here does,
  # and they are what this output target is developed against. Building a copy
  # keeps the suite from passing while the thing it is for is broken.
  data('syntax-book' => 'syntax-book', 'md-syntax-book' => 'md-syntax-book')
  def test_sample_book_builds(name)
    source = File.join(SAMPLES, name)
    omit("#{name} is not in this checkout") unless File.directory?(source)

    Dir.mktmpdir do |dir|
      book = File.join(dir, name)
      FileUtils.cp_r(source, book)
      # Whatever a previous local build left behind is not part of the fixture.
      FileUtils.rm_rf(Dir[File.join(book, '*-typst')] + Dir[File.join(book, '*-pdf')])

      output = IO.popen([BIN, File.join(book, 'config.yml'), { err: %i[child out] }], &:read)

      assert(Dir[File.join(book, '*-typst.pdf')].any?, "#{name} did not build:\n#{output}")
    end
  end

  private

  def build(dir)
    IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
  end

  def write_structured_book(dir)
    File.write(File.join(dir, 'config.yml'), <<~YAML)
      bookname: book
      booktitle: 構造テスト
      aut: [著者]
      language: ja
      toc: true
      colophon: true
      date: 2026-07-20
      typst:
        keep_workdir: true
    YAML

    File.write(File.join(dir, 'catalog.yml'), <<~YAML)
      PREDEF:
        - pre01.re
      CHAPS:
        - ch01.re
        - part1.re:
          - ch02.re
        - 第II部:
          - ch03.re
      APPENDIX:
        - appA.re
      POSTDEF:
        - post01.re
    YAML

    File.write(File.join(dir, 'pre01.re'), "= 前書き\n\n前付の本文。\n")
    File.write(File.join(dir, 'ch01.re'), "= 第一章\n\n本文。\n\n== 節\n\n節の本文。\n")
    File.write(File.join(dir, 'part1.re'), "= 部の扉\n\n部の説明。\n")
    File.write(File.join(dir, 'ch02.re'), "= 第二章\n\n本文。\n")
    File.write(File.join(dir, 'ch03.re'), "= 第三章\n\n本文。\n")
    File.write(File.join(dir, 'appA.re'), "= 付録\n\n付録の本文。\n")
    File.write(File.join(dir, 'post01.re'), "= 後書き\n\n後付の本文。\n")
  end
end
