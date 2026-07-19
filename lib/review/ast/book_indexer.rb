# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/book/index'
require_relative 'indexer'
require_relative 'compiler'

module ReVIEW
  module AST
    # BookIndexer - Book-wide index management for AST-based processing.
    #
    # NOTE: largely vestigial since the AST became self-contained
    # (doc/design-improvements #7). The Indexer no longer writes its indexes back
    # onto the chapter (ast_indexes= is gone) and cross-chapter references resolve
    # on demand via ReferenceResolver#registry_for, so building indexes here has
    # no lasting effect beyond lazily initializing @book.chapter_index. Kept as a
    # harmless no-op for external callers (makers, comparators) until they drop
    # the call.
    class BookIndexer
      attr_reader :book, :chapter_indexers

      # Build book-wide indexes for cross-chapter references
      # This is the main entry point for building indexes for an entire book
      def self.build(book)
        return unless book

        indexer = new(book)
        indexer.build_all_chapter_indexes
        indexer
      end

      def initialize(book)
        @book = book
      end

      # Build indexes for all chapters in the book
      def build_all_chapter_indexes
        @book.each_chapter do |chapter|
          build_chapter_index(chapter)
        end

        # Build book-level indexes
        build_bibpaper_index_from_bib_file
        build_chapter_index_for_book
      end

      # Build index for a specific chapter using AST::Indexer
      def build_chapter_index(chapter)
        begin
          # Compile chapter to AST
          ast = compile_chapter_to_ast(chapter)

          # Create indexer and build indexes
          indexer = AST::Indexer.new(chapter)
          indexer.build_indexes(ast)
        rescue StandardError => e
          warn "Failed to build index for chapter #{chapter.id}: #{e.message}"
        end
      end

      private

      # Compile chapter to AST using appropriate compiler
      def compile_chapter_to_ast(chapter)
        compiler = AST::Compiler.for_chapter(chapter)
        compiler.compile_to_ast(chapter, reference_resolution: false)
      end

      # Build bibpaper index from bib file if it exists
      def build_bibpaper_index_from_bib_file
        return unless @book.bib_exist?

        begin
          # Create a Bib object with file content
          bib = ReVIEW::Book::Bib.new(file_content: @book.bib_content, book: @book)

          # Compile bib file to AST
          ast = compile_chapter_to_ast(bib)

          # Build the bib indexes (no longer written back to @book; the resolver
          # reads the bib file itself via ReferenceResolver#bib_file_registry).
          indexer = AST::Indexer.new(bib)
          indexer.build_indexes(ast)
        rescue StandardError => e
          warn "Failed to build bibpaper index: #{e.message}"
        end
      end

      # Build chapter index for the book (chapters and parts)
      # Calling chapter_index triggers lazy initialization via create_chapter_index
      def build_chapter_index_for_book
        @book.chapter_index
      end
    end
  end
end
