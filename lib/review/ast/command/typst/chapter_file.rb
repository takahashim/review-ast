# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require 'review/renderer/typst/expression'
require 'review/renderer/typst/text'

module ReVIEW
  module AST
    module Command
      module Typst
        # One generated chapter file.
        #
        # Two things can produce one: a .re file, which is compiled and
        # rendered; and a part named only in catalog.yml, which has no source to
        # compile and is written out as its title alone. Asking the entry which
        # it is (rather than testing for a :part key in a hash) keeps that fork
        # in one place.
        class ChapterFile
          attr_reader :basename

          def self.for_source(basename, chapter)
            new(basename, chapter: chapter)
          end

          def self.for_part(part)
            new("part-#{part.number}", part: part)
          end

          def initialize(basename, chapter: nil, part: nil)
            @basename = basename
            @chapter = chapter
            @part = part
          end

          def compiled?
            !@chapter.nil?
          end

          attr_reader :chapter

          # The Typst source of a part that has no .re file of its own.
          #
          # A part named only in catalog.yml has nothing to compile, so the call
          # is spelled here rather than by the renderer -- through the same
          # Expression the renderer uses, so the two cannot disagree on how a
          # part is written.
          def part_source(library_import)
            import = "#import #{ReVIEW::Renderer::Typst::Text.new(library_import).literal}: review"
            call = ReVIEW::Renderer::Typst::Expression.new('review.part').
                   value(:number, @part.number).
                   text('number-text', ReVIEW::I18n.t('part', @part.number)).
                   text(:title, @part.name.to_s)

            "#{import}\n\n#{call}\n"
          end
        end
      end
    end
  end
end
