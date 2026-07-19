# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast'
require 'review/ast/compiler'
require 'review/ast/json_serializer'
require 'review/book'
require 'review/book/chapter'
require 'review/configure'

# Completeness of the serialization contract (doc/design-improvements #4). The
# per-field round-trip tests pin known-lossy fields; these tests instead guard
# the whole node-type set, so a newly added node type (or one that loses its
# deserialize path) is caught even if no hand-written fixture exercises it.
class TestSerializationCompleteness < Test::Unit::TestCase
  # Node subclasses that are never serialized as a concrete type.
  ABSTRACT = %w[ReVIEW::AST::LeafNode].freeze

  def setup
    Dir[File.expand_path('../../lib/review/ast/*_node.rb', __dir__)].each { |f| require f }
  end

  def node_subclasses
    ObjectSpace.each_object(Class).select { |c| c < ReVIEW::AST::Node }.uniq
  end

  # Every concrete Node subclass must implement deserialize_from_hash, or
  # JSONSerializer#deserialize_from_hash raises "does not implement" for it.
  def test_every_concrete_node_type_can_deserialize
    missing = node_subclasses.reject { |c| c.respond_to?(:deserialize_from_hash) }.map(&:name).sort
    assert_equal ABSTRACT.sort, missing,
                 "these Node subclasses lack deserialize_from_hash: #{(missing - ABSTRACT).inspect}"
  end

  # Types reachable by compiling Re:VIEW source into the final (post-lowering)
  # tree. DirectiveNode is lowered away and LeafNode is abstract, so neither
  # appears here.
  SOURCE_REACHABLE = %w[
    DocumentNode HeadlineNode ParagraphNode TextNode InlineNode ReferenceNode
    CodeBlockNode CodeLineNode ImageNode TableNode TableRowNode TableCellNode
    TexEquationNode FootnoteNode MinicolumnNode CaptionNode ColumnNode
    ListNode ListItemNode BlockNode EmbedNode
  ].freeze

  FIXTURE = <<~RE
    = 章タイトル

    段落テキスト @<b>{強調} と @<hd>{節1} 参照。

    == 節1

    //list[l1][リスト]{
    code line
    //}

    //image[img1][画像]

    //table[t1][表]{
    a	b
    ------------
    c	d
    //}

    //texequation[eq1]{
    E=mc^2
    //}

    //footnote[fn1][脚注]

    //note[ノート]{
    ノート本文。
    //}

    ===[column]{col1} コラム

    コラム本文。

    ===[/column]

     * ul item
     ** nested item

     1. ol item

     : 定義語
    	定義説明

    //bibpaper[bib1][文献]

    //embed[html]{
    <div>raw</div>
    //}
  RE

  def compile(source)
    config = ReVIEW::Configure.values
    book = ReVIEW::Book::Base.new(config: config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'c', 'c.re', StringIO.new)
    chapter.content = source
    ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
  end

  def types_in(hash, acc = Set.new)
    return acc unless hash.is_a?(Hash)

    acc << hash['type'] if hash['type']
    hash.each_value do |v|
      case v
      when Hash then types_in(v, acc)
      when Array then v.each { |e| types_in(e, acc) }
      end
    end
    acc
  end

  def test_fixture_round_trips_and_covers_source_reachable_types
    root = compile(FIXTURE)

    s1 = ReVIEW::AST::JSONSerializer.serialize(root)
    s2 = ReVIEW::AST::JSONSerializer.serialize(ReVIEW::AST::JSONSerializer.deserialize(s1))
    assert_equal s1, s2, 'comprehensive fixture is not byte-identical across a round trip'

    covered = types_in(JSON.parse(s1))
    uncovered = SOURCE_REACHABLE - covered.to_a
    assert_empty(uncovered, "fixture missed source-reachable node types: #{uncovered.inspect}")
  end
end
