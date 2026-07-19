# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/chapter_registry_provider'
require 'review/ast/reference_resolver'
require 'review/ast/document_node'
require 'review/ast/inline_node'
require 'review/ast/reference_node'
require 'review/ast/image_node'
require 'review/book'
require 'review/book/chapter'
require 'review/i18n'

# ChapterRegistryProvider owns "where does another chapter's index table come
# from", which ReferenceResolver used to answer itself by invoking the compiler
# (doc/design-improvements #7). These tests pin the two things that separation
# buys: the table is built once per chapter, and a resolver can be driven with
# prepared tables without any compilation happening at all.
class ChapterRegistryProviderTest < Test::Unit::TestCase
  def setup
    ReVIEW::I18n.setup('ja')
    @book = ReVIEW::Book::Base.new
    @chapter = ReVIEW::Book::Chapter.new(@book, 1, 'chap01', 'chap01.re')
    @chapter.instance_variable_set(:@number, 1)
  end

  def loc
    ReVIEW::AST::SourceLocation.new(nil, 0)
  end

  def other_chapter
    chapter = ReVIEW::Book::Chapter.new(@book, 2, 'chap02', 'chap02.re')
    chapter.instance_variable_set(:@number, 2)
    chapter
  end

  def test_builds_each_chapter_once_and_caches
    built = []
    provider = ReVIEW::AST::ChapterRegistryProvider.new do |chapter|
      built << chapter.id
      ReVIEW::AST::ChapterIndexRegistry.new
    end
    chapter = other_chapter

    first = provider.registry_for(chapter)
    second = provider.registry_for(chapter)

    assert_same(first, second)
    assert_equal ['chap02'], built
  end

  def test_seeded_chapter_is_not_built
    built = []
    provider = ReVIEW::AST::ChapterRegistryProvider.new do |chapter|
      built << chapter.id
      ReVIEW::AST::ChapterIndexRegistry.new
    end
    seeded = ReVIEW::AST::ChapterIndexRegistry.new

    provider.seed(@chapter, seeded)

    assert_same(seeded, provider.registry_for(@chapter))
    assert_empty(built)
  end

  def test_nil_chapter_has_no_registry
    provider = ReVIEW::AST::ChapterRegistryProvider.new { flunk('should not build') }

    assert_nil(provider.registry_for(nil))
  end

  # The point of the injection: resolution of a cross-chapter reference needs
  # only a table, so the other chapter never has to be compiled.
  def test_resolver_uses_injected_table_without_compiling
    target = other_chapter
    contents = [@chapter, target]
    @book.define_singleton_method(:contents) { contents }

    registry = ReVIEW::AST::ChapterIndexRegistry.new
    registry.add(:image, 'img01', number: '1', caption_node: nil)

    provider = ReVIEW::AST::ChapterRegistryProvider.new do |chapter|
      flunk("compiled #{chapter.id} instead of using the injected table") unless chapter.equal?(@chapter)
      ReVIEW::AST::ChapterIndexRegistry.new
    end
    provider.seed(target, registry)

    doc = ReVIEW::AST::DocumentNode.new(location: loc)
    inline = ReVIEW::AST::InlineNode.new(location: loc, inline_type: :img)
    inline.add_child(ReVIEW::AST::ReferenceNode.new('img01', 'chap02', location: loc))
    doc.add_child(inline)

    resolver = ReVIEW::AST::ReferenceResolver.new(@chapter, registry_provider: provider)
    assert_equal 1, resolver.resolve_references(doc)

    data = inline.children.first.resolved_data
    assert_equal ReVIEW::AST::ResolvedData::ImageReference, data.class
    assert_equal 'img01', data.item_id
    assert_equal 2, data.chapter_number
  end
end
