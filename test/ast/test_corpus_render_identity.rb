# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/latex_comparator'
require 'review/ast/compiler'
require 'review/ast/json_serializer'
require 'review/renderer/latex_renderer'
require 'review/renderer/html_renderer'
require 'review/renderer/idgxml_renderer'
require 'review/renderer/plaintext_renderer'
require 'review/renderer/top_renderer'

# Corpus-level render identity (design-improvements #4 verification): the unit
# fixtures pin known-lossy fields; this runs the same fresh-vs-reloaded render
# check over a real book so any serialization gap that only shows on real content
# (across all five renderers) is caught too. This is where the inline_type /
# code_type / minicolumn_type Symbol-vs-String bugs would have surfaced on real
# chapters.
class TestCorpusRenderIdentity < Test::Unit::TestCase
  BOOK_DIR = File.expand_path('../../samples/syntax-book', __dir__)

  RENDERERS = {
    latex: ReVIEW::Renderer::LatexRenderer,
    html: ReVIEW::Renderer::HtmlRenderer,
    idgxml: ReVIEW::Renderer::IdgxmlRenderer,
    plaintext: ReVIEW::Renderer::PlaintextRenderer,
    top: ReVIEW::Renderer::TopRenderer
  }.freeze

  def book
    @book ||= ReVIEW::Test::LatexComparator.new.send(:load_book, BOOK_DIR)
  end

  def test_every_chapter_renders_identically_after_a_round_trip
    omit("sample book not found at #{BOOK_DIR}") unless File.directory?(BOOK_DIR)

    checked = 0
    book.chapters.each do |chapter|
      ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
      reloaded = ReVIEW::AST::JSONSerializer.deserialize(ReVIEW::AST::JSONSerializer.serialize(ast))

      RENDERERS.each do |fmt, renderer_class|
        fresh = renderer_class.new(chapter).render(ast)
        reload = renderer_class.new(chapter).render(reloaded)
        assert_equal fresh, reload,
                     "#{fmt} render differs between fresh and reloaded tree for #{chapter.name}"
        checked += 1
      end
    end
    assert_operator(checked, :>=, 5, 'expected at least one chapter to be checked')
  end
end
