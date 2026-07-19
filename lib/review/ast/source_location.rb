# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # Immutable source location for AST nodes: filename, line number and,
    # additionally, column number.
    #
    # The released +review+ gem's ReVIEW::SnapshotLocation records only
    # filename and lineno (and is frozen, so it cannot carry a column). The AST
    # subsystem uses this richer value object instead so nodes can point at the
    # exact column of a construct -- notably inline elements, whose offset within
    # the line is known from the tokenizer. It is a faithful superset of
    # SnapshotLocation (same +filename+/+lineno+/+string+/+snapshot+ interface),
    # so it is a drop-in replacement wherever the AST previously built a
    # SnapshotLocation.
    #
    # +column+ is 1-based and optional: nil means "column unknown" (e.g. a
    # position restored from an old dump, or a synthetic node). When +column+ is
    # nil, #to_h and #format_for_error are byte-identical to SnapshotLocation's,
    # so adding this class is behaviour-preserving for existing consumers.
    class SourceLocation
      attr_reader :filename, :lineno, :column

      def initialize(filename, lineno, column = nil)
        @filename = filename
        @lineno = lineno
        @column = column
        freeze
      end

      # Build a SourceLocation from any location-like object (SnapshotLocation or
      # SourceLocation), optionally overriding/adding the column.
      def self.from(location, column: nil)
        return nil unless location

        column ||= location.column if location.respond_to?(:column)
        new(location.filename, location.lineno, column)
      end

      def string
        "#{@filename}:#{@lineno}"
      end

      alias_method :to_s, :string

      def to_h
        h = { filename: @filename, lineno: @lineno }
        h[:column] = @column unless @column.nil?
        h
      end

      # Format location information for error messages, e.g.
      # " at line 42 in chapter01.re" or " at line 42, column 5 in chapter01.re".
      def format_for_error
        info = " at line #{@lineno}"
        info += ", column #{@column}" unless @column.nil?
        info += " in #{@filename}" if @filename
        info
      end

      def ==(other)
        other.is_a?(SourceLocation) &&
          filename == other.filename &&
          lineno == other.lineno &&
          column == other.column
      end
      alias_method :eql?, :==

      def hash
        [filename, lineno, column].hash
      end
    end
  end
end
