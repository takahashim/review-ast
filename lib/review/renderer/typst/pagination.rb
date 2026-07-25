# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    module Typst
      # How the pages are numbered, for print submission.
      #
      # These mirror review-jsbook's class options (serial_pagination,
      # startpage): they are submission practicalities, not page design, so they
      # live in the `typst:` config rather than in theme.typ (doc/design-hanmen
      # §4.4). By default the front matter is roman (i, ii, ...) and the main
      # matter restarts at arabic 1; serial pagination runs one arabic counter
      # across the whole book, from the start page.
      class Pagination
        def initialize(typst_config)
          @typst_config = typst_config
        end

        # One continuous arabic counter across front and main matter, with no
        # roman numerals and no restart (review-jsbook serial_pagination).
        def serial?
          @typst_config.fetch('serial_pagination', false) ? true : false
        end

        # The number the first page carries (review-jsbook startpage), e.g. 3
        # when the cover and a blank take physical pages 1 and 2.
        def start
          Integer(@typst_config.fetch('startpage', 1))
        rescue ArgumentError, TypeError
          1
        end
      end
    end
  end
end
