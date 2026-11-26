# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/builder'
require 'review/idgxmlbuilder'

module ReVIEW
  module AST
    # How the installed Re:VIEW builders split and pad table rows.
    #
    # Re:VIEW 5.11 strips each row before splitting it into cells, so a row
    # written with a leading tab loses its empty first cell, and IDGXMLBuilder
    # emits only a row's own cells. Later Re:VIEW (kmuto/review#1972) keeps the
    # leading empty cells (rstrip) and pads a short IDGXML row out to the
    # table's column count. review-ast follows whichever builder is installed,
    # so its output stays the same as review-compile's on both.
    #
    # Each answer comes from the builder itself, not from a version number: the
    # change landed under the same 5.11.0 version string on master.
    module BuilderTableCompat
      class << self
        # Whether Builder#parse_table_rows keeps the empty cells a row's leading
        # separators make (line.rstrip), rather than stripping them away.
        def keeps_leading_empty_cells?
          return @keeps_leading_empty_cells if defined?(@keeps_leading_empty_cells)

          probe = ReVIEW::Builder.allocate
          probe.define_singleton_method(:table_row_separator_regexp) { /\t+/ }
          _sepidx, rows = probe.send(:parse_table_rows, ["\tx"])
          @keeps_leading_empty_cells = rows.first.first == ''
        end

        # Whether IDGXMLBuilder pads a short row with empty cells up to the
        # table's column count when the table has a width (aid:tcols).
        def idgxml_pads_short_rows?
          return @idgxml_pads_short_rows if defined?(@idgxml_pads_short_rows)

          @idgxml_pads_short_rows = ReVIEW::IDGXMLBuilder.private_method_defined?(:pad_table_row) ||
                                    ReVIEW::IDGXMLBuilder.method_defined?(:pad_table_row)
        end
      end
    end
  end
end
