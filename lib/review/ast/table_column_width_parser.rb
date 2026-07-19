# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # Parse tsize specification and generate column width information
    # This class handles the logic from LATEXBuilder's tsize/separate_tsize methods
    class TableColumnWidthParser
      # Result struct for parse method
      Result = Struct.new(:col_spec, :cellwidth)

      # Check if cellwidth is a fixed-width specification (contains '{')
      # @param cellwidth [String] column width specification (e.g., "p{10mm}", "l", "c")
      # @return [Boolean] true if fixed-width (contains braces)
      def self.fixed_width?(cellwidth)
        cellwidth && cellwidth.include?('{')
      end

      # Resolve a raw //tsize argument for a given output format, returning the
      # applicable spec string or nil. A `|latex,html|value` prefix restricts the
      # spec to those builders (parallel to EmbedNode#target_builders); anything
      # else (including a LaTeX column spec like `|l|c|r|`) is generic and applies
      # to every format. The filtering happens at render time so the shared tree
      # stays target-neutral. See doc/design-improvements #5.
      def self.value_for_target(raw, format)
        return nil unless raw

        # Target names are multi-character words (latex, html, idgxml, ...); a
        # LaTeX column spec like |l|c|r| is NOT a target spec (single-char parts).
        if (matched = raw.match(/\A\|([a-z]{2,}(?:\s*,\s*[a-z]{2,})*)\|(.*)/m))
          targets = matched[1].split(',').map(&:strip)
          targets.include?(format.to_s) ? matched[2] : nil
        else
          raw
        end
      end

      # Initialize parser with tsize specification and column count
      # @param tsize [String] tsize specification (e.g., "10,18,50" or "p{10mm}p{18mm}|p{50mm}")
      # @param col_count [Integer] number of columns
      def initialize(tsize, col_count)
        raise ArgumentError, 'col_count must be positive' if col_count.nil? || col_count <= 0

        @tsize = tsize
        @col_count = col_count
      end

      # Parse tsize specification and return result as Struct
      # @return [Result] Result struct with col_spec and cellwidth
      def parse
        if @tsize.nil? || @tsize.empty?
          default_spec
        elsif simple_format?
          parse_simple_format
        else
          parse_complex_format
        end
      end

      private

      # Generate default column specification
      # @return [Result] Result struct with default values
      def default_spec
        Result.new(
          '|' + ('l|' * @col_count),
          ['l'] * @col_count
        )
      end

      # Check if tsize is in simple format (e.g., "10,18,50")
      # @return [Boolean] true if simple format
      def simple_format?
        /\A[\d., ]+\Z/.match?(@tsize)
      end

      # Parse simple format tsize (e.g., "10,18,50" means p{10mm},p{18mm},p{50mm})
      # @return [Result] Result struct with parsed values
      def parse_simple_format
        cellwidth = @tsize.split(/\s*,\s*/).map { |i| "p{#{i}mm}" }
        col_spec = '|' + cellwidth.join('|') + '|'

        Result.new(col_spec, cellwidth)
      end

      # Parse complex format tsize (e.g., "p{10mm}p{18mm}|p{50mm}")
      # @return [Result] Result struct with parsed values
      def parse_complex_format
        cellwidth = separate_columns(@tsize)
        Result.new(@tsize, cellwidth)
      end

      # Parse tsize string into array of column specifications
      # Example: "p{10mm}p{18mm}|p{50mm}" -> ["p{10mm}", "p{18mm}", "p{50mm}"]
      # @param size [String] tsize specification
      # @return [Array<String>] array of column specifications
      def separate_columns(size)
        columns = []
        current = +''
        in_brace = false

        size.each_char do |ch|
          case ch
          when '|'
            # Skip pipe characters (table borders)
            next
          when '{'
            in_brace = true
            current << ch
          when '}'
            in_brace = false
            current << ch
            columns << current
            current = +''
          else
            if in_brace || current.empty?
              current << ch
            else
              columns << current
              current = ch.dup
            end
          end
        end

        columns << current unless current.empty?

        columns
      end
    end
  end
end
