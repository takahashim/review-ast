# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/chapter_index_registry'
require 'review/ast/indexer'
require 'review/book'
require 'review/book/chapter'
require 'review/ast/compiler'
require 'review/configure'

# ChapterIndexRegistry, and the Indexer writing it in parallel with the legacy
# indexes (doc/design-improvements #7 migration step 1). At this step the
# registry is populated but not yet read by the ReferenceResolver, so this test
# pins its contents directly.
class TestChapterIndexRegistry < Test::Unit::TestCase
  Registry = ReVIEW::AST::ChapterIndexRegistry

  def test_add_and_lookup
    r = Registry.new
    r.add(:table, 't1', number: 3, caption_node: :cap)
    entry = r.lookup(:table, 't1')
    assert_equal 3, entry.number
    assert_equal :cap, entry.caption_node
    assert_nil(entry.footnote_node)
    assert r.key?(:table, 't1')
    assert_equal ['t1'], r.ids(:table)
  end

  def test_lookup_absent
    r = Registry.new
    assert_nil(r.lookup(:table, 'missing'))
    assert_false(r.key?(:table, 'missing'))
    assert_equal [], r.ids(:table)
  end

  def test_ignores_blank_id
    r = Registry.new
    r.add(:list, nil, number: 1)
    r.add(:list, '', number: 1)
    assert_equal [], r.ids(:list)
  end

  def test_last_definition_wins
    r = Registry.new
    r.add(:list, 'dup', number: 1)
    r.add(:list, 'dup', number: 2)
    assert_equal 2, r.lookup(:list, 'dup').number
  end

  # The Indexer records the same numbers as the legacy indexes, and attaches the
  # caption node straight from the AST (from the node, not the Index::Item).
  def test_indexer_populates_registry
    source = <<~EOS
      = 章

      //list[l1][リスト説明]{
      code
      //}

      //table[t1][表説明]{
      A\tB
      ------------
      C\tD
      //}

      //image[img1][画像説明]{
      //}

      //texequation[eq1][式説明]{
      E=mc^2
      //}

      本文@<fn>{fn1}。

      //footnote[fn1][脚注本文]
    EOS

    indexer = build_indexer(source)
    reg = indexer.registry

    # numbers mirror the legacy indexes
    assert_equal 1, reg.lookup(:list, 'l1').number
    assert_equal 1, reg.lookup(:table, 't1').number
    assert_equal 1, reg.lookup(:image, 'img1').number
    assert_equal 1, reg.lookup(:equation, 'eq1').number
    assert_equal indexer.footnote_index.number('fn1'), reg.lookup(:footnote, 'fn1').number

    # caption nodes come straight from the AST nodes (CaptionNode), except //list
    # whose legacy Index::Item carries no caption (mirrored as nil).
    assert_instance_of(ReVIEW::AST::CaptionNode, reg.lookup(:table, 't1').caption_node)
    assert_instance_of(ReVIEW::AST::CaptionNode, reg.lookup(:image, 'img1').caption_node)
    assert_instance_of(ReVIEW::AST::CaptionNode, reg.lookup(:equation, 'eq1').caption_node)
    assert_nil(reg.lookup(:list, 'l1').caption_node)

    # footnote records its definition node
    assert_instance_of(ReVIEW::AST::FootnoteNode, reg.lookup(:footnote, 'fn1').footnote_node)
  end

  private

  def build_indexer(source)
    config = ReVIEW::Configure.values
    config['secnolevel'] = 2
    config['language'] = 'ja'
    book = ReVIEW::Book::Base.new(config: config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new)
    chapter.content = source
    ast = ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
    indexer = ReVIEW::AST::Indexer.new(chapter)
    indexer.build_indexes(ast)
    indexer
  end
end
