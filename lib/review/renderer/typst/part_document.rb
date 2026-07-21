# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require_relative 'expression'
require_relative 'text'

module ReVIEW
  module Renderer
    module Typst
      # The whole source of a chapter file for a part that has no .re of its
      # own.
      #
      # A part named only in catalog.yml has nothing to compile, but the root
      # still includes a file for it. Spelling that call here, through the same
      # Expression the renderer uses, keeps the two from disagreeing on how a
      # part is written.
      module PartDocument
        module_function

        # @param part [ReVIEW::Book::Part]
        # @param library_import [String] Import path of the book library
        # @return [String] Typst source for the part's chapter file
        def source(part, library_import)
          import = "#import #{Text.new(library_import).literal}: review"
          call = Expression.new('review.part').
                 value(:number, part.number).
                 text('number-text', ReVIEW::I18n.t('part', part.number)).
                 text(:title, part.name.to_s)

          "#{import}\n\n#{call}\n"
        end
      end
    end
  end
end
