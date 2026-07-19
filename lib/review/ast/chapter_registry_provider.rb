# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'chapter_index_registry'
require_relative 'indexer'

module ReVIEW
  module AST
    # Supplies the ChapterIndexRegistry for a chapter, and caches it.
    #
    # Resolving a reference needs the index table of whatever chapter the
    # reference points at, which may be a chapter other than the one being
    # compiled. Producing that table means compiling and indexing the other
    # chapter. Keeping that here rather than in ReferenceResolver means the
    # resolver only ever looks a table up, and does not know how one is made --
    # so it no longer reaches back into the compiler that invoked it, and a test
    # can hand it prepared tables instead of a working compiler
    # (doc/design-improvements #7).
    #
    # The cache lives in the provider, so its lifetime is the caller's choice:
    # one provider per book build indexes each chapter at most once, while the
    # default of one per resolver is equally correct but re-indexes a
    # cross-referenced chapter once per referring chapter.
    class ChapterRegistryProvider
      # @yieldparam chapter [Book::Chapter] Chapter to build a registry for
      # @yieldreturn [ChapterIndexRegistry] That chapter's table
      def initialize(&builder)
        @builder = builder || method(:build_by_compiling)
        @registries = {}
      end

      # Adopt an already-built registry. The chapter being compiled is indexed
      # as part of its own resolution, so it must not be compiled a second time
      # here -- doing so would recurse.
      # @param chapter [Book::Chapter] The chapter the registry belongs to
      # @param registry [ChapterIndexRegistry] Its table
      # @return [ChapterIndexRegistry] The registry
      def seed(chapter, registry)
        @registries[key_for(chapter)] = registry
      end

      # @param chapter [Book::Chapter, nil] Chapter to look up
      # @return [ChapterIndexRegistry, nil] Its table, nil for a nil chapter
      def registry_for(chapter)
        return nil unless chapter

        key = key_for(chapter)
        return @registries[key] if @registries.key?(key)

        @registries[key] = @builder.call(chapter)
      end

      private

      # Bib and Part are chapter-like but need not carry an id.
      def key_for(chapter)
        (chapter.id if chapter.respond_to?(:id)) || chapter.object_id
      end

      # Compile the chapter with its own reference resolution off -- resolving
      # it would ask for other chapters' tables in turn -- and index the result.
      def build_by_compiling(chapter)
        # Required here rather than at the top of the file: the compiler builds
        # a provider, so requiring it up front would be circular. Fully
        # qualified so the constant cannot resolve to ReVIEW::Compiler, the
        # legacy gem compiler.
        require 'review/ast/compiler'
        ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter, reference_resolution: false)
        Indexer.new(chapter).build_indexes(ast).registry
      rescue StandardError => e
        # Warn unconditionally: swallowed silently, a chapter that fails to
        # index surfaces later as "reference not found" for every reference into
        # it, which points at the reference rather than at the real cause.
        warn "Failed to index chapter #{chapter.id} for cross-reference: #{e.message}"
        ChapterIndexRegistry.new
      end
    end
  end
end
