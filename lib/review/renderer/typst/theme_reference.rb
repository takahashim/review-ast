# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'code'
require_relative 'text'

module ReVIEW
  module Renderer
    module Typst
      # How the root document refers to the theme.
      #
      # Crop marks belong to the theme, but a book usually wants both a screen
      # PDF and a press PDF out of one theme file, so config.yml can turn them
      # on without a second theme. That makes the reference an expression
      # rather than a plain name, and this is the object that knows which.
      class ThemeReference
        def initialize(typst_config, warn: nil)
          @typst_config = typst_config
          @warn = warn
        end

        # @return [Code] The Typst expression naming the theme
        def expression
          case @typst_config['crop']
          when nil then Code.new('theme')
          when true then Code.new("book.with-crop(theme, true#{crop_colour})")
          else Code.new('book.with-crop(theme, false)')
          end
        end

        private

        # Crop marks are drawn in registration black, which is a CMYK colour.
        # Typst ships no CMYK ICC profile, so any conformance mode rejects the
        # file ("the PDF is missing a CMYK profile"). Fall back to plain black
        # rather than failing on a combination the author did not know was
        # exclusive.
        def crop_colour
          return '' unless @typst_config['pdf_standard']

          @warn&.call('typst.pdf_standard is set, so crop marks are drawn in plain black ' \
                      'instead of registration black: Typst cannot embed a CMYK profile yet.')
          ', color: luma(0)'
        end
      end
    end
  end
end
