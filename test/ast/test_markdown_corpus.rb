# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/compiler'
require 'review/renderer/latex_renderer'
require 'review/renderer/html_renderer'
require 'review/renderer/idgxml_renderer'
require 'review/ast/json_serializer'
require 'review/book'
require 'review/configure'
require 'review/i18n'
require 'yaml'

# Drives the samples/md-syntax-book corpus (design-improvements item 10, step 3).
#
# The unit tests check the adapter against hand-built expectations; this checks
# that whole Markdown chapters survive the real pipeline -- compile, stamp,
# render -- which is what caught the divergences the unit tests could not see
# (an unsupported hr block, and Re:VIEW inline notation building different nodes
# than the .re path builds).
class TestMarkdownCorpus < Test::Unit::TestCase
  CORPUS = File.expand_path('../../samples/md-syntax-book', __dir__)

  # plaintext and TOP are absent on purpose: the corpus uses a thematic break,
  # which maps to //hr, and the text builders reject that command outright.
  RENDERERS = {
    latex: ReVIEW::Renderer::LatexRenderer,
    html: ReVIEW::Renderer::HtmlRenderer,
    idgxml: ReVIEW::Renderer::IdgxmlRenderer
  }.freeze

  def each_markdown_chapter
    Dir.chdir(CORPUS) do
      config = ReVIEW::Configure.values
      loaded = YAML.safe_load_file('config.yml', permitted_classes: [Date, Time, Symbol])
      config.merge!(loaded) if loaded
      book = ReVIEW::Book::Base.new('.', config: config)
      book.generate_indexes
      ReVIEW::I18n.setup(config['language'] || 'ja')

      Dir.glob('*.md').sort.each do |file|
        name = File.basename(file, '.md')
        chapter = book.chapters.find { |c| c.name == name } ||
                  ReVIEW::Book::Chapter.new(book, 1, name, file)
        yield(file, chapter)
      end
    end
  end

  def test_corpus_is_not_empty
    files = Dir.glob(File.join(CORPUS, '*.md'))

    assert_operator(files.size, :>=, 5, 'the Markdown corpus should have been imported')
  end

  def test_every_chapter_compiles_and_renders
    each_markdown_chapter do |file, chapter|
      ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)

      assert_instance_of(ReVIEW::AST::DocumentNode, ast, "#{file} should compile")

      RENDERERS.each do |format, renderer_class|
        output = renderer_class.new(chapter).render(ast)

        assert_not_empty(output, "#{file} should render as #{format}")
      end
    end
  end

  # Same property the .re corpus is held to: a chapter's dump reloads into a
  # tree that serializes identically.
  def test_every_chapter_round_trips
    each_markdown_chapter do |file, chapter|
      ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
      dump = ReVIEW::AST::JSONSerializer.serialize(ast)
      reloaded = ReVIEW::AST::JSONSerializer.deserialize(dump)

      assert_equal dump, ReVIEW::AST::JSONSerializer.serialize(reloaded),
                   "#{file} should round trip byte-identically"
    end
  end

  # Markdown and Re:VIEW must build the same nodes for Re:VIEW inline notation.
  # The adapter used to tokenize it itself, which wrapped every command in a
  # ReferenceNode -- including commands that are not references -- and never
  # split multi-argument commands.
  def test_inline_notation_matches_the_review_path
    notation = '@<bou>{傍点}と@<ruby>{愕然,がくぜん}と@<href>{http://example.com,例}'

    assert_equal inline_shape("= 章\n\n#{notation}\n", 'c.re'),
                 inline_shape("# 章\n\n#{notation}\n", 'c.md')
  end

  private

  def inline_shape(source, basename)
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'c', basename, StringIO.new)
    chapter.content = source
    ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter, reference_resolution: false)

    shape = []
    collect_inline_shape(ast, shape)
    shape
  end

  def collect_inline_shape(node, shape)
    if node.is_a?(ReVIEW::AST::InlineNode)
      shape << [node.inline_type, node.args, node.children.map(&:class)]
    end
    return unless node.respond_to?(:each_subnode)

    node.each_subnode { |child| collect_inline_shape(child, shape) }
  end
end
