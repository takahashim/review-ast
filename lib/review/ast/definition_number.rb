# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # The number a numbered definition block carries (//list, //table, //image,
    # //texequation, //bibpaper, footnote, endnote). It is the counterpart of
    # ResolvedData for the *use* side: the Indexer stamps it onto the node during
    # index building, so a renderer reads +node.definition_number+ instead of
    # reaching back into the legacy +@chapter+ index (e.g.
    # +@chapter.list(id).number+). See doc/design-improvements #1.
    #
    # - +number+ is the item's position in its chapter (e.g. 3 for the third
    #   //list). Always present.
    # - +chapter_number+ is the formatted chapter part of the display number
    #   (e.g. "2", or "A" for an appendix), or nil when no chapter prefix applies
    #   (secnolevel 0, or a chapter without a number). This mirrors
    #   Renderer::Base#get_chap so the renderer needs neither the index nor the
    #   chapter to build the full "2.3" caption -- TextFormatter#format_caption
    #   assembles it from these two.
    class DefinitionNumber
      attr_reader :number, :chapter_number

      def initialize(number:, chapter_number: nil)
        @number = number
        @chapter_number = chapter_number
      end

      def to_h
        { number: number, chapter_number: chapter_number }
      end

      def ==(other)
        other.is_a?(DefinitionNumber) &&
          number == other.number &&
          chapter_number == other.chapter_number
      end
      alias_method :eql?, :==

      def hash
        [number, chapter_number].hash
      end
    end
  end
end
