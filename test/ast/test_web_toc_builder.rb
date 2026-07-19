# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/web_toc_builder'
require 'review/renderer/html_renderer'
require 'review/ast/compiler'
require 'review/book'
require 'review/book/chapter'
require 'review/configure'

# The web sidebar TOC links to sections by anchor, so those anchors must match
# exactly what HtmlRenderer emits on the headlines. WebTocBuilder replays the
# renderer's SecCounter walk; this test pins that invariant: every section link
# fragment resolves to an id in the rendered page.
class TestWebTocBuilder < Test::Unit::TestCase
  CONTENT = <<~RE
    = 章タイトル

    == 節A

    本文。

    === 小節A1

    本文。

    == 節B

    本文。

    ==[nonum] 番号なし節

    本文。
  RE

  def setup
    @config = ReVIEW::Configure.values
    @config['maker'] = 'webmaker'
    @config['language'] = 'ja'
    @book = ReVIEW::Book::Base.new(config: @config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
    @chapter = ReVIEW::Book::Chapter.new(@book, 1, 'ch01', 'ch01.re', StringIO.new)
    @chapter.content = CONTENT
  end

  def test_section_anchors_match_rendered_ids
    # Anchors the TOC will link to.
    builder = ReVIEW::AST::WebTocBuilder.new(@book)
    entries = builder.send(:section_entries, @chapter)
    fragments = entries.map { |e| e[:fragment] }

    assert_operator(entries.size, :>=, 4, 'sections (incl. subsection and nonum) should be collected')

    # Ids the renderer actually emits.
    ast = ReVIEW::AST::Compiler.for_chapter(@chapter).compile_to_ast(@chapter, reference_resolution: false)
    html = ReVIEW::Renderer::HtmlRenderer.new(@chapter).render(ast)
    ids = html.scan(/id="([^"]+)"/).flatten

    fragments.each do |frag|
      assert_include(ids, frag, "TOC fragment ##{frag} has no matching id in the page")
    end

    # The numbered section anchors follow the SecCounter scheme, and the nonum
    # section uses its auto id rather than an h-number.
    assert_include(fragments, 'h1-1')
    assert_include(fragments, 'h1-1-1')
    assert_include(fragments, 'h1-2')
    assert(fragments.any? { |f| !f.start_with?('h') }, 'nonum section uses a non-h anchor')
  end

  def test_build_wraps_in_book_toc_list
    toc = ReVIEW::AST::WebTocBuilder.new(@book).build
    assert_include(toc, '<ul class="book-toc">')
    assert_include(toc, 'index.html')
  end

  def test_render_sections_nests_by_level
    builder = ReVIEW::AST::WebTocBuilder.new(@book)
    entries = [
      { level: 2, fragment: 'h1-1', text: 'A' },
      { level: 3, fragment: 'h1-1-1', text: 'A1' },
      { level: 2, fragment: 'h1-2', text: 'B' }
    ]
    html = builder.send(:render_sections, entries, 'ch01.html')
    # A1 nests inside A (a <ul> appears before A's </li>), and B is a sibling of A.
    assert_equal '<ul><li><a href="ch01.html#h1-1">A</a><ul><li><a href="ch01.html#h1-1-1">A1</a></li></ul></li>' \
                 '<li><a href="ch01.html#h1-2">B</a></li></ul>',
                 html
  end
end
