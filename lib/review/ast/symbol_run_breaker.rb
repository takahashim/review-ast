# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'unicode/eaw'

module ReVIEW
  module AST
    # Restores pTeX's line-break opportunities inside runs of fullwidth-looking
    # symbols (■□★☆→※… and the like).
    #
    # pTeX treats these as JAchars and breaks lines anywhere between them, so
    # the LaTeX edition fills each line before folding. Chromium classifies the
    # same characters -- East Asian Width "ambiguous" symbols -- as Western
    # word characters regardless of the document language, so a run becomes a
    # single unbreakable word: it either overflows the measure or, with
    # overflow-wrap, folds one break too early (before the run instead of
    # inside it). Neither matches the LaTeX edition.
    #
    # Inserting ZERO WIDTH SPACE between adjacent such symbols gives the
    # browser the same break opportunities pTeX has. Only symbol/punctuation
    # pairs whose East Asian Width is "ambiguous" qualify: fullwidth kana and
    # kanji already break natively, ASCII stays Western, and ambiguous-width
    # letters (Greek, Cyrillic) are left alone -- breaking Russian words
    # anywhere would repair one deviation by introducing a worse one.
    #
    # The running heads do not inherit the fix: text reaching the page margin
    # boxes through string-set does not fold at the ZWSPs (measured), so a
    # symbol-run title is clipped at the measure there. The ZWSPs end up in
    # text extracted from the PDF and in outline entries built from the nav;
    # both render invisibly.
    class SymbolRunBreaker
      ZWSP = "\u200B"
      TAG = /<[^>]*>/
      # Text inside these elements is left untouched: code must copy out
      # byte-identical, and head metadata never renders as running text.
      SKIP_ELEMENTS = %w[pre code script style head title].freeze
      PAIR = /([\p{S}\p{P}])(?=[\p{S}\p{P}])/

      def initialize(root)
        @root = root
        @ambiguous = Hash.new { |cache, char| cache[char] = Unicode::Eaw.property(char) == :A }
      end

      # Rewrites every document under the root. Returns the number of files
      # that changed.
      def annotate
        Dir.glob(File.join(@root, '**', '*.{xhtml,html}')).count do |file|
          source = File.read(file)
          broken = break_source(source)
          next false if broken == source

          File.write(file, broken)
          true
        end
      end

      # Edits the markup textually, like ImageSizeAnnotator: an XML round-trip
      # would rewrite entities and self-closing tags throughout the document
      # for the sake of a few characters.
      def break_source(source)
        depth = 0
        source.split(/(#{TAG})/o).map do |part|
          if part.start_with?('<')
            depth += skip_delta(part)
            part
          elsif depth > 0
            part
          else
            break_runs(part)
          end
        end.join
      end

      private

      def skip_delta(tag)
        name = tag[%r{\A</?([a-zA-Z][a-zA-Z0-9]*)}, 1]&.downcase
        return 0 unless SKIP_ELEMENTS.include?(name)
        return 0 if tag.end_with?('/>')

        tag.start_with?('</') ? -1 : 1
      end

      def break_runs(text)
        text.gsub(PAIR) do
          match = Regexp.last_match
          char = match[1]
          if @ambiguous[char] && @ambiguous[text[match.end(0), 1]]
            char + ZWSP
          else
            char
          end
        end
      end
    end
  end
end
