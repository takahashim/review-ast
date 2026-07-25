# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    module Typst
      # Label strings for Typst.
      #
      # Re:VIEW ids are scoped to their chapter (ChapterIndexRegistry is built
      # per chapter, and a cross-chapter reference has to name the chapter), so
      # a two-part "figure:architecture" collides the moment two chapters use
      # the same id. Labels therefore carry the chapter
      # (doc/design-typst.md).
      #
      # Both the renderer (which defines labels) and the inline handler (which
      # points at them) build labels here, so a definition and a reference to it
      # cannot drift apart.
      module Labels
        # Re:VIEW element kind => label prefix.
        PREFIX = {
          image: 'fig',
          table: 'tbl',
          list: 'lst',
          equation: 'eq',
          chapter: 'chap',
          headline: 'sec',
          column: 'col',
          footnote: 'fn',
          endnote: 'en'
        }.freeze

        # @param kind [Symbol] Element kind, a key of PREFIX
        # @param chapter_id [String, nil] Chapter the item is defined in
        # @param item_id [String] The item's id within that chapter
        # @return [String] Label string
        def label_for(kind, chapter_id, item_id)
          prefix = PREFIX.fetch(kind)
          "#{prefix}:#{document_key(chapter_id)}:#{typst_label(item_id.to_s)}"
        end

        # A chapter label has no item part.
        def chapter_label(chapter_id)
          "chap:#{document_key(chapter_id)}"
        end

        # Bibliography entries are book-wide, not chapter-scoped: the resolver
        # falls back to the book's bib registry, so ids there are already unique
        # across the book and there is no chapter to qualify them with.
        def bib_label(item_id)
          "bib:#{typst_label(item_id.to_s)}"
        end

        # A //label id, which authors write themselves.
        def user_label(item_id)
          "label:#{typst_label(item_id.to_s)}"
        end

        # A section label built from the heading's number path (e.g. sec:ch01:1-2).
        def section_label(chapter_id, numbers)
          path = Array(numbers).compact.join('-')
          "sec:#{document_key(chapter_id)}:#{path}"
        end

        private

        # Elements outside a chapter (parts, the bibliography file) still need a
        # stable middle segment. Anything derived from object identity or a
        # per-run counter would change between builds, so fall back to a fixed
        # key rather than something incidental.
        def document_key(chapter_id)
          key = chapter_id.to_s
          key.empty? ? 'book' : typst_label(key)
        end
      end
    end
  end
end
