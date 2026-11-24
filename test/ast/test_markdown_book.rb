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
# "第1章"). The HTML makers also named a chapter's page after the file with
# only ".re" stripped (ch01.md.xhtml) while every link pointed at ch01.xhtml.
class TestMarkdownBook < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)

  CATALOG = <<~YAML
    PREDEF:
      - pre01.md
    CHAPS:
      - ch01.md
      - ch02.md
    APPENDIX:
      - appA.md
  YAML

  FILES = {
    'pre01.md' => "# 前書き\n\n本文\n",
    'ch01.md' => "# 章A\n\n## 節\n\n参照: @<title>{ch02} / @<chap>{appA} / @<chapref>{appA} / @<chapref>{ch02}\n",
    'ch02.md' => "# 章B\n\n本文\n",
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

  def test_epub_chapter_pages_are_named_like_the_links_to_them
    with_book do |dir, _book|
      env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
      out, status = Open3.capture2e(env, RbConfig.ruby, '-rbundler/setup', File.join(ROOT, 'bin/review-ast-epubmaker'),
                                    'config.yml', chdir: dir)
      assert(status.success?, out)

      require 'zip'
      entries = Zip::File.open(File.join(dir, 'book.epub')) do |zip|
        zip.entries.to_h { |entry| [entry.name, entry.get_input_stream.read.force_encoding('UTF-8')] }
      end
      pages = entries.keys.grep(%r{\AOEBPS/[^/]+\.html\z}).map { |name| File.basename(name) }
      assert_include(pages, 'ch01.html')
      assert_include(pages, 'appA.html')
      assert_empty(pages.grep(/\.md\./), 'no page should keep the .md extension in its name')

      links = entries.fetch('OEBPS/ch01.html').scan(%r{href="\./([^"#]+)}).flatten.uniq
      assert_not_empty(links)
      links.each { |target| assert_include(pages, target, "ch01.html links to a missing page #{target}") }

      nav = entries.fetch('OEBPS/book-toc.html')
      assert_include(nav, '付録A　付録')
    end
  end
end
