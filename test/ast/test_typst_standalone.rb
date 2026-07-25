# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

# The Typst review-book library is usable without Re:VIEW: a hand-written book
# imports book.*, styles native headings/figures with the theme, and turns on
# native numbering with `set heading(numbering: book.heading-numbering)`. The
# Re:VIEW path supplies its own numbers instead, so nothing here exercises that
# path -- this guards the standalone one it would not otherwise touch.
class TestTypstStandalone < Test::Unit::TestCase
  LIBRARY = File.expand_path('../../templates/typst/review-book', __dir__)

  def setup
    omit('typst command not found') unless system('typst', '--version', out: File::NULL, err: File::NULL)
  end

  def test_a_hand_written_book_auto_numbers_headings_figures_and_references
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(LIBRARY, File.join(dir, 'review-book'))
      File.write(File.join(dir, 'book.typ'), <<~TYP)
        #import "/review-book/lib.typ": book, default-theme
        #show: book.document.with(metadata: (title: [手書き本], language: "ja"), theme: default-theme)
        #set heading(numbering: book.heading-numbering)
        = 最初の章
        @fig1 を参照する。
        #figure(rect(width: 2cm, height: 1cm), caption: [サンプル図]) <fig1>
        == 節
      TYP

      text = compile(dir)
      assert_include(text, '第1章', 'the chapter is not numbered 第N章')
      assert_include(text, '1.1節', 'the section is not numbered N.N')
      assert_include(text, '図1', 'the figure / its reference is not numbered')
    end
  end

  # The book matters number their headings the way the LaTeX edition does:
  # front/back matter unnumbered, main matter 第N章, appendix lettered 付録A.
  def test_the_matters_number_headings_like_the_latex_edition
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(LIBRARY, File.join(dir, 'review-book'))
      File.write(File.join(dir, 'book.typ'), <<~TYP)
        #import "/review-book/lib.typ": book, default-theme
        #show: book.document.with(metadata: (title: [手書き本], language: "ja"), theme: default-theme)
        // front matter: roman folio (the default is arabic), unnumbered headings
        #set page(numbering: "i")
        = まえがき
        // main matter: arabic folio, running head, chapter numbering
        #set page(numbering: "1", header: book.running-head())
        #counter(page).update(1)
        #set heading(numbering: book.heading-numbering)
        = 最初の章
        == 節
        // appendix: reset the chapter counter and letter it
        #counter(heading).update(0)
        #set heading(numbering: book.appendix-numbering)
        = 付録の章
        == 付録の節
        // back matter: unnumbered again
        #set heading(numbering: none)
        = あとがき
      TYP

      text = compile(dir)
      assert_include(text, '第1章', 'main matter chapter should be 第N章')
      assert_include(text, '付録A', 'appendix chapter should be lettered 付録A')
      assert_include(text, 'A.1', 'appendix section should be A.1')
      # Front and back matter carry no chapter number.
      assert_not_include(text, '第2章', 'the appendix must not continue the chapter count')
    end
  end

  private

  # Compiles the standalone book in +dir+ and returns its whitespace-stripped
  # text, failing if it does not compile.
  def compile(dir)
    pdf = File.join(dir, 'book.pdf')
    output = IO.popen(['typst', 'compile', '--root', dir, File.join(dir, 'book.typ'), pdf],
                      err: %i[child out], &:read)
    assert(File.exist?(pdf), "the standalone book did not compile:\n#{output}")
    IO.popen(['pdftotext', pdf, '-'], &:read).gsub(/\s+/, '')
  end
end
