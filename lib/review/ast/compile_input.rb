# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # The compiler's input contract. It separates the two kinds of things the
    # pipeline reads from a chapter, which used to be reached out of a
    # ReVIEW::Book::Chapter god-object scattered across the compiler:
    #
    #   - pure data: the +source+ text and the +basename+ (for source locations),
    #   - an explicit service handle: the +chapter+ (hence its +book+), used only
    #     by the resolution passes that genuinely need the environment -- the
    #     ImageFinder filesystem lookup and cross-chapter reference resolution.
    #
    # A chapter-backed input (from_chapter) behaves exactly as before. A
    # source-only input (from_source) has no chapter/book, so compiling it yields
    # an AST without reference/image resolution -- useful for tests and any
    # consumer that has source text but no Book (doc/design-improvements #8, 手順4).
    class CompileInput
      attr_reader :source, :basename, :chapter

      # Build from a ReVIEW::Book::Chapter (or Part/Bib): the source and basename
      # are captured as data, the object itself is kept as the service handle.
      def self.from_chapter(chapter)
        new(source: chapter.content, basename: chapter.basename, chapter: chapter)
      end

      # Build from a bare source string, with no environment. Resolution passes
      # are skipped when compiled (there is no book).
      def self.from_source(source, basename: nil)
        new(source: source, basename: basename)
      end

      def initialize(source:, basename: nil, chapter: nil)
        @source = source
        @basename = basename
        @chapter = chapter
      end

      # The book, when an environment is available; nil for a source-only input.
      def book
        @chapter&.book
      end
    end
  end
end
