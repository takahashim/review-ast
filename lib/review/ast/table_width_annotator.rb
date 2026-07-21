# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'cgi'
require 'review/ast/table_column_width_parser'

module ReVIEW
  module AST
    # Turns the //tsize each <table> carries (as a data-tsize attribute, put
    # there by the HTML renderer for EPUB output) into CSS column widths, the
    # way the LaTeX renderer turns the same spec into p{<n>mm} columns.
    #
    # Specs are resolved for the "vivliostyle" target, falling back to "html"
    # (a |latex|-only spec stays LaTeX-only). The numeric form 10,18,50 means
    # millimetres, as it does for LaTeX and IDGXML; the column-spec form
    # contributes its p{<length>} entries. Each width becomes a <col> in a
    # colgroup; when every column has one, the table also gets
    # table-layout: fixed and the summed width, which reproduces the p-column
    # behaviour of wrapping within a fixed measure. Alignment letters (l/c/r)
    # and rule positions (|) have no colgroup equivalent and are ignored.
    #
    # NOTE: in fixed layout a col width is the column width, padding included,
    # while LaTeX's p{10mm} is 10mm of text with \tabcolsep added outside.
    # The difference is one cell padding per column and is not compensated.
    class TableWidthAnnotator
      TABLE_TAG = /<table\b[^>]*\bdata-tsize="([^"]*)"[^>]*>/
      # p{<number><unit>} with a unit CSS understands; anything else
      # (\linewidth expressions, zw, ...) yields a width-less column.
      P_COLUMN_WIDTH = /\Ap\{(\d+(?:\.\d+)?)(mm|cm|pt|in|px|em)\}\z/

      def initialize(root)
        @root = root
      end

      # Annotates every document under the root. Returns the number of files
      # that changed.
      def annotate
        Dir.glob(File.join(@root, '**', '*.{xhtml,html}')).count do |file|
          source = File.read(file)
          annotated = annotate_source(source)
          next false if annotated == source

          File.write(file, annotated)
          true
        end
      end

      # Edits the table tags textually, like ImageSizeAnnotator: an XML
      # round-trip would rewrite entities and self-closing tags throughout the
      # document for the sake of one colgroup.
      def annotate_source(source)
        source.gsub(TABLE_TAG) do |tag|
          widths = column_widths(CGI.unescapeHTML(Regexp.last_match(1)))
          widths ? "#{styled_tag(tag, widths)}\n#{colgroup(widths)}" : tag
        end
      end

      # The CSS width of each column (nil for a column without one), or nil
      # when the spec does not apply to this target or yields no widths.
      def column_widths(raw)
        spec = TableColumnWidthParser.value_for_target(raw, 'vivliostyle') ||
               TableColumnWidthParser.value_for_target(raw, 'html')
        return nil if spec.nil? || spec.strip.empty?

        # col_count only shapes the empty-spec default, which the guard above
        # rules out.
        cells = TableColumnWidthParser.new(spec, 1).parse.cellwidth
        widths = cells.map { |cell| width_of(cell) }
        widths.any? ? widths : nil
      end

      private

      def width_of(cell)
        return "#{cell.strip}mm" if /\A\d+(?:\.\d+)?\z/.match?(cell.strip)

        matched = P_COLUMN_WIDTH.match(cell)
        matched && (matched[1] + matched[2])
      end

      def colgroup(widths)
        cols = widths.map do |width|
          width ? %Q(<col style="width: #{width}" />) : '<col />'
        end
        "<colgroup>#{cols.join}</colgroup>"
      end

      # With every column width known the table reproduces LaTeX's fixed
      # measure: fixed layout plus the summed width (Chromium treats
      # table-layout: fixed with width: auto as auto layout, so the width is
      # required). With gaps left, the browser's auto layout distributes the
      # rest and the col widths act as preferences.
      def styled_tag(tag, widths)
        return tag unless widths.all?

        style = "table-layout: fixed; width: #{sum(widths)}"
        tag.sub(/>\z/, %Q( style="#{style}">))
      end

      def sum(widths)
        by_unit = widths.group_by { |width| width[/[a-z]+\z/] }
        parts = by_unit.map do |unit, values|
          total = values.sum(&:to_f)
          sprintf('%g%s', total, unit)
        end
        parts.one? ? parts.first : "calc(#{parts.join(' + ')})"
      end
    end
  end
end
