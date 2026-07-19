# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../tools/pbt/generator'
require 'review/ast/compiler'
require 'review/ast/json_serializer'
require 'review/renderer/latex_renderer'
require 'review/renderer/html_renderer'
require 'review/renderer/idgxml_renderer'
require 'review/renderer/plaintext_renderer'
require 'review/renderer/top_renderer'
require 'review/book'
require 'review/book/chapter'
require 'review/configure'

# Property-based round-trip / render identity (design-improvements #4
# verification). The samples corpus is fixed; this runs the same
# fresh-vs-reloaded check over property-based random documents from the PBT
# generator, so a serialization gap that only a rarely-combined construct would
# expose is caught in the normal test run. Seeds are fixed, so it is
# deterministic. It does not need the builder oracle -- it is a self-consistency
# property (a re-loaded tree must serialize and render identically).
class TestPbtRoundTripIdentity < Test::Unit::TestCase
  SEEDS = (1..30)

  RENDERERS = {
    latex: ReVIEW::Renderer::LatexRenderer,
    html: ReVIEW::Renderer::HtmlRenderer,
    idgxml: ReVIEW::Renderer::IdgxmlRenderer,
    plaintext: ReVIEW::Renderer::PlaintextRenderer,
    top: ReVIEW::Renderer::TopRenderer
  }.freeze

  def setup
    @config = ReVIEW::Configure.values
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
  end

  def chapter_for(source)
    book = ReVIEW::Book::Base.new(config: @config)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'c', 'c.re', StringIO.new)
    chapter.content = source
    chapter
  end

  # A renderer may legitimately reject a construct (NotImplementedError, a
  # ScriptError); render identity then means the fresh and reloaded trees reject
  # it the same way, so collapse either outcome to a comparable value.
  def render_or_error(renderer_class, chapter, ast)
    renderer_class.new(chapter).render(ast)
  rescue StandardError, ScriptError => e
    "ERROR:#{e.class}"
  end

  def test_generated_documents_round_trip_and_render_identically
    SEEDS.each do |seed|
      source = ReVIEW::PBT::Generator.new(seed).document.to_re
      chapter = chapter_for(source)
      ast = ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)

      dump = ReVIEW::AST::JSONSerializer.serialize(ast)
      reloaded = ReVIEW::AST::JSONSerializer.deserialize(dump)
      assert_equal dump, ReVIEW::AST::JSONSerializer.serialize(reloaded),
                   "round trip not byte-identical for seed #{seed}"

      RENDERERS.each do |fmt, renderer_class|
        fresh = render_or_error(renderer_class, chapter, ast)
        reload = render_or_error(renderer_class, chapter, reloaded)
        assert_equal fresh, reload,
                     "#{fmt} render differs between fresh and reloaded tree for seed #{seed}"
      end
    end
  end
end
