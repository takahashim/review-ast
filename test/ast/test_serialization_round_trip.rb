# frozen_string_literal: true

require_relative '../test_helper'
require 'review'
require 'review/ast/compiler'
require 'review/ast/json_serializer'
require 'review/renderer/latex_renderer'
require 'review/renderer/html_renderer'
require 'review/renderer/idgxml_renderer'
require 'stringio'

# Serialization fidelity tests (doc/design-improvements #4).
#
# Two guarantees, each catching a different class of loss:
#
# - Round-trip byte-identity: serialize(deserialize(serialize(tree))) is byte
#   identical to serialize(tree). Catches a field that is serialized but dropped
#   on deserialize.
# - Render identity: a chapter rendered from a freshly compiled tree and from
#   that tree's serialize -> deserialize is byte identical, for every builder.
#   Catches a field that affects rendering but is not serialized at all (the
#   round-trip test cannot see those -- they are absent from both dumps).
class TestSerializationRoundTrip < Test::Unit::TestCase
  # Sources exercising the fields whose round trip was historically lossy:
  # //noindent, ordered-list start (//olnum), //tsize column spec, //imgtable
  # table_type, [nonum] headline tag/auto_id, //list caption number
  # (definition_number), numbered code first-line number, and an inline @<list>
  # target id.
  SOURCES = {
    'noindent' => "Para one.\n\n//noindent\nPara two.\n",
    'olnum' => "//olnum[10]\n\n 1. item ten\n 2. item eleven\n",
    'tsize_table' => "//tsize[|latex,html,idgxml|10,18,50]\n\n//table[t1][Cap]{\nA\tB\tC\n----\nD\tE\tF\n//}\n",
    'nonum_headline' => "==[nonum] No Number Heading\n\nBody.\n",
    'numbered_code' => "//firstlinenum[100]\n\n//listnum[c1][Cap]{\nputs 1\nputs 2\n//}\n",
    'numbered_list' => "//list[l1][A caption]{\ncode\n//}\n\nSee it.\n",
    # A list item split across source lines records source_line_breaks, which the
    # LaTeX renderer reinserts as "\n"; it must survive a round trip.
    'list_continuation' => " * first line@<br>{}\n   second continuation line\n"
  }.freeze

  RENDERERS = {
    latex: ReVIEW::Renderer::LatexRenderer,
    html: ReVIEW::Renderer::HtmlRenderer,
    idgxml: ReVIEW::Renderer::IdgxmlRenderer
  }.freeze

  SOURCES.each do |name, source|
    define_method("test_round_trip_identity_#{name}") do
      _chapter, root = compile(source)
      s1 = ReVIEW::AST::JSONSerializer.serialize(root)
      s2 = ReVIEW::AST::JSONSerializer.serialize(ReVIEW::AST::JSONSerializer.deserialize(s1))
      assert_equal s1, s2, "round trip not byte-identical for #{name}"
    end

    define_method("test_render_identity_#{name}") do
      RENDERERS.each do |fmt, renderer_class|
        chapter, root = compile(source)
        reloaded = ReVIEW::AST::JSONSerializer.deserialize(ReVIEW::AST::JSONSerializer.serialize(root))
        fresh_out = renderer_class.new(chapter).render(root)
        reloaded_out = renderer_class.new(chapter).render(reloaded)
        assert_equal fresh_out, reloaded_out,
                     "#{fmt} render differs between fresh and reloaded tree for #{name}"
      end
    end
  end

  # A numbered block's definition_number is part of the core tree and survives a
  # round trip (so a re-loaded tree needs no re-indexing to render its number).
  def test_definition_number_round_trips
    _chapter, root = compile(SOURCES['numbered_list'])
    reloaded = ReVIEW::AST::JSONSerializer.deserialize(ReVIEW::AST::JSONSerializer.serialize(root))
    code = find(reloaded) { |n| n.class.name.include?('CodeBlockNode') }
    assert_not_nil(code)
    assert_not_nil(code.definition_number)
    assert_equal find(root) { |n| n.class.name.include?('CodeBlockNode') }.definition_number.number,
                 code.definition_number.number
  end

  # The versioned dump envelope (serialize_document) carries the format version
  # and generator, wraps the same node tree, and round-trips byte-identically.
  def test_document_envelope_round_trips_and_carries_version
    _chapter, root = compile(SOURCES['numbered_list'])

    d1 = ReVIEW::AST::JSONSerializer.serialize_document(root)
    parsed = JSON.parse(d1)
    assert_equal ReVIEW::AST::JSONSerializer::AST_FORMAT_VERSION, parsed['ast_format']
    assert_match(/\Areview /, parsed['generator'])
    assert_equal 'DocumentNode', parsed['root']['type']

    # deserialize transparently unwraps the envelope, so re-dumping is identical.
    d2 = ReVIEW::AST::JSONSerializer.serialize_document(ReVIEW::AST::JSONSerializer.deserialize(d1))
    assert_equal d1, d2
  end

  # A bare node dump (serialize) still deserializes, so both forms are accepted.
  def test_deserialize_accepts_both_bare_and_enveloped
    _chapter, root = compile(SOURCES['nonum_headline'])
    bare = ReVIEW::AST::JSONSerializer.serialize(root)
    enveloped = ReVIEW::AST::JSONSerializer.serialize_document(root)
    assert_equal ReVIEW::AST::JSONSerializer.serialize(ReVIEW::AST::JSONSerializer.deserialize(bare)),
                 ReVIEW::AST::JSONSerializer.serialize(ReVIEW::AST::JSONSerializer.deserialize(enveloped))
  end

  # An unknown format version is refused rather than silently mis-read.
  def test_deserialize_refuses_unknown_format_version
    _chapter, root = compile(SOURCES['noindent'])
    hash = JSON.parse(ReVIEW::AST::JSONSerializer.serialize_document(root))
    hash['ast_format'] = 999
    assert_raise(StandardError) do
      ReVIEW::AST::JSONSerializer.deserialize(JSON.generate(hash))
    end
  end

  private

  def compile(source)
    config = ReVIEW::Configure.values
    config['builder'] ||= 'latex'
    ReVIEW::I18n.setup(config['language'] || 'ja')
    book = ReVIEW::Book::Base.new('.', config: config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(source))
    root = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
    [chapter, root]
  end

  def find(node, &block)
    return node if yield(node)

    node.children.each do |child|
      found = find(child, &block)
      return found if found
    end
    nil
  end
end
