# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # An AST-owned index table for one chapter: for each element type (:list,
    # :table, :image, :equation, :headline, :column, :footnote, :endnote,
    # :bibpaper, ...) it maps an element id to the data the ReferenceResolver
    # needs to resolve a @<...>{id} use -- the number, the caption node, and (for
    # footnotes/endnotes) the definition node.
    #
    # This replaces reading back the legacy ReVIEW::Book::Index / Index::Item on
    # the chapter (and the caption_node prepend on Index::Item): the Indexer
    # writes this table straight from the AST nodes, so the resolution data flows
    # AST -> AST instead of round-tripping through the gem's book model. See
    # doc/design-improvements #7.
    class ChapterIndexRegistry
      # One resolved-reference record. +number+ is the element's number within
      # its chapter (or a section number list for headlines); +caption_node+ is
      # the CaptionNode (nil when the element has no caption); +footnote_node+ is
      # the FootnoteNode for footnotes/endnotes (nil otherwise).
      Entry = Struct.new(:number, :caption_node, :footnote_node, keyword_init: true)

      def initialize
        @table = {}
      end

      # Record an element. Later calls for the same (type, id) overwrite, matching
      # the legacy indexes' "last definition wins" for a duplicate id.
      def add(type, id, number:, caption_node: nil, footnote_node: nil)
        return if id.nil? || id.empty?

        (@table[type] ||= {})[id] = Entry.new(
          number: number,
          caption_node: caption_node,
          footnote_node: footnote_node
        )
      end

      # The Entry for (type, id), or nil if absent.
      def lookup(type, id)
        @table[type]&.[](id)
      end

      def key?(type, id)
        !lookup(type, id).nil?
      end

      # All ids recorded for a type (mainly for tests/introspection).
      def ids(type)
        @table[type]&.keys || []
      end
    end
  end
end
