# frozen_string_literal: true

require_relative '../test_helper'
require 'review'
require 'review/ast/compiler'
require 'review/ast/web_toc_builder'
require 'review/renderer/plaintext_renderer'
require 'review/renderer/html_renderer'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# A book written in Markdown has to number, title and link its chapters the
# way a Re:VIEW-format book does.
#
# Re:VIEW's own book model assumes .re files in two places: Chapter#title
# parses "=" headlines (so a Markdown chapter had an empty title, and
# @<title>/@<chapref> printed nothing), and on_appendix?/on_predef? match
# catalog entries against "<id>.re" (so a Markdown appendix was numbered
# "第1章"). The makers named a chapter's output after the file with only
# ".re" stripped (ch01.md.xhtml) while every link pointed at ch01.xhtml,
# PDFMaker \input'ed no Markdown chapter at all, and a Markdown part file was
# made into a title page named after the file (Part#file? wants ".re").
class TestMarkdownBook < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)

  CATALOG = <<~YAML
    PREDEF:
      - pre01.md
    CHAPS:
      - ch01.md
      - part2.md:
        - ch02.md
    APPENDIX:
      - appA.md
  YAML

  FILES = {
    'pre01.md' => "# 前書き\n\n本文\n",
    'ch01.md' => "# 章A\n\n## 節\n\n参照: @<title>{ch02} / @<chap>{appA} / @<chapref>{appA} / @<chapref>{ch02}\n",
    'ch02.md' => "# 章B\n\n本文\n",
    'part2.md' => "# 部の題\n\n部のリード。\n",
    'appA.md' => "# 付録\n\n## 付録の節\n"
  }.freeze

  def with_book
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'catalog.yml'), CATALOG)
      File.write(File.join(dir, 'config.yml'), "review_version: 5.0\nlanguage: ja\nbookname: book\ntitle: T\naut: [A]\n")
      FILES.each { |name, content| File.write(File.join(dir, name), content) }
      Dir.chdir(dir) do
        config = ReVIEW::Configure.create(yamlfile: 'config.yml')
        ReVIEW::I18n.setup('ja')
        yield(dir, ReVIEW::Book::Base.new(dir, config: config))
      end
    end
  end

  def run_maker(dir, maker, *args)
    env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
    out, status = Open3.capture2e(env, RbConfig.ruby, '-rbundler/setup', File.join(ROOT, "bin/review-ast-#{maker}"),
                                  *args, 'config.yml', chdir: dir)
    [out, status]
  end

  def render(book, name, renderer_class = ReVIEW::Renderer::PlaintextRenderer)
    chapter = book.chapters.find { |ch| ch.name == name }
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    renderer_class.new(chapter).render(ast)
  end

  def test_chapter_references_carry_titles_and_appendix_numbers
    with_book do |_dir, book|
      assert_include(render(book, 'ch01'), '参照: 章B / 付録A / 付録A「付録」 / 第2章「章B」')
    end
  end

  def test_appendix_headings_are_numbered_as_an_appendix
    with_book do |_dir, book|
      text = render(book, 'appA')
      assert_include(text, '付録A　付録')
      assert_include(text, 'A.1　付録の節')

      html = render(book, 'appA', ReVIEW::Renderer::HtmlRenderer)
      assert_include(html, '<span class="secno">付録A　</span>付録')
      assert_include(html, '<a id="hA-1"></a>')
    end
  end

  def test_predef_chapter_is_unnumbered
    with_book do |_dir, book|
      assert_no_match(/第\d章/, render(book, 'pre01'))
    end
  end

  def test_web_toc_labels
    with_book do |_dir, book|
      toc = ReVIEW::AST::WebTocBuilder.new(book).build
      assert_include(toc, '<a href="ch01.html">第1章 章A</a>')
      assert_include(toc, '<a href="appA.html">付録A 付録</a>')
      assert_include(toc, '<a href="appA.html#hA-1">付録の節</a>')
    end
  end

  def test_epub_pages_chapter_types_and_part_file
    with_book do |dir, _book|
      out, status = run_maker(dir, 'epubmaker')
      assert(status.success?, out)

      require 'zip'
      entries = Zip::File.open(File.join(dir, 'book.epub')) do |zip|
        zip.entries.to_h { |entry| [entry.name, entry.get_input_stream.read.force_encoding('UTF-8')] }
      end
      pages = entries.keys.grep(%r{\AOEBPS/[^/]+\.html\z}).map { |name| File.basename(name) }
      assert_equal %w[appA.html book-toc.html book.html ch01.html ch02.html part2.html pre01.html titlepage.html], pages.sort

      links = entries.fetch('OEBPS/ch01.html').scan(%r{href="\./([^"#]+)}).flatten.uniq
      assert_not_empty(links)
      links.each { |target| assert_include(pages, target, "ch01.html links to a missing page #{target}") }

      nav = entries.fetch('OEBPS/book-toc.html')
      assert_include(nav, '付録A　付録')
      assert_include(nav, '<a href="part2.html">第I部　部の題</a>')
      assert_include(entries.fetch('OEBPS/part2.html'), '部のリード。')
    end
  end

  def test_pdf_book_inputs_every_chapter_in_its_section
    with_book do |dir, _book|
      # No TeX needed: with TeX a no-op the build stops after writing the
      # .tex tree, which debug: true keeps.
      File.write(File.join(dir, 'config.yml'), "debug: true\ntexcommand: \"true\"\ndvicommand: \"true\"\ndvioptions: \"\"\n", mode: 'a')
      run_maker(dir, 'pdfmaker')
      book_tex = File.read(File.join(dir, 'book-pdf', '__REVIEW_BOOK__.tex'))

      assert_include(book_tex, "\\def\\reviewprefacefiles{\\input{pre01.tex}\n}")
      assert_include(book_tex, "\\def\\reviewchapterfiles{\\input{ch01.tex}\n\\input{part2.tex}\n\\input{ch02.tex}\n}")
      assert_include(book_tex, "\\def\\reviewappendixfiles{\\input{appA.tex}\n}")
      assert_include(File.read(File.join(dir, 'book-pdf', 'part2.tex')), '部のリード。')
    end
  end

  def test_text_and_idgxml_outputs_are_named_after_the_chapter
    with_book do |dir, _book|
      [%w[textmaker book-text txt], %w[idgxmlmaker book-idgxml xml]].each do |maker, outdir, ext|
        out, status = run_maker(dir, maker)
        assert(status.success?, out)
        files = Dir.glob("*.#{ext}", base: File.join(dir, outdir)).sort
        assert_equal %w[appA ch01 ch02 part2 pre01].map { |name| "#{name}.#{ext}" }, files, maker
      end
      assert_include(File.read(File.join(dir, 'book-text', 'part2.txt')), '第I部　部の題')
    end
  end

  def test_web_pages_and_part_file
    with_book do |dir, _book|
      out, status = run_maker(dir, 'webmaker')
      assert(status.success?, out)
      pages = Dir.glob('*.html', base: File.join(dir, 'webroot')).sort
      assert_equal %w[appA.html ch01.html ch02.html index.html part2.html pre01.html titlepage.html], pages
      assert_include(File.read(File.join(dir, 'webroot', 'index.html')), '<a href="part2.html">第I部 部の題</a>')
    end
  end
end
