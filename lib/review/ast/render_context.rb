# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/book/part'

module ReVIEW
  module AST
    # A small value object carrying exactly what a renderer reads about the
    # chapter being rendered: its number, its id, its type classification, and a
    # few environment paths and the config. It is captured once from the
    # ReVIEW::Book::Chapter at renderer construction, so renderers touch no Book
    # model object during rendering (doc/design-improvements #8, 手順4).
    #
    # It deliberately does NOT format the chapter number. Formatting is a reused
    # service (TextFormatter#format_chapter_number_short/full), driven by the
    # (chapter_number, chapter_type) pair this object exposes -- the datum is
    # owned here, the formatting service is shared. That also keeps construction
    # free of I18n, so building the context before a renderer runs I18n.setup is
    # safe.
    class RenderContext
      attr_reader :chapter_number, :chapter_id, :chapter_type, :imagedir, :basedir, :config

      # Classify a chapter into the type symbol used by TextFormatter and
      # ResolvedData: :chapter, :appendix, :part, :predef (nil for no chapter).
      # This is the single home for "chapter -> type"; ReferenceResolver delegates
      # here so cross-chapter references and the current chapter classify alike.
      def self.chapter_type(chapter)
        return nil unless chapter

        if chapter.is_a?(ReVIEW::Book::Part)
          :part
        elsif chapter.on_predef?
          :predef
        elsif chapter.on_appendix?
          :appendix
        else
          :chapter
        end
      end

      # Build from a chapter (nil-safe). Values are captured eagerly; no reference
      # to the chapter or book is retained.
      def self.from_chapter(chapter)
        book = chapter&.book
        new(
          chapter_present: !chapter.nil?,
          chapter_number: chapter&.number,
          chapter_id: chapter&.id,
          chapter_type: chapter_type(chapter),
          imagedir: book&.imagedir,
          basedir: book&.basedir,
          config: book&.config || {}
        )
      end

      def initialize(chapter_present:, chapter_number:, chapter_id:, chapter_type:, imagedir:, basedir:, config:)
        @chapter_present = chapter_present
        @chapter_number = chapter_number
        @chapter_id = chapter_id
        @chapter_type = chapter_type
        @imagedir = imagedir
        @basedir = basedir
        @config = config
      end

      # Whether a chapter was present at build time. Renderers that emitted
      # test-only fallbacks when @chapter was nil branch on this.
      def chapter_present?
        @chapter_present
      end

      def part?
        @chapter_type == :part
      end

      # Whether the chapter has a non-empty number (drives secnolevel/label logic).
      def chapter_number_present?
        !@chapter_number.to_s.empty?
      end
    end
  end
end
