# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'node'

module ReVIEW
  module AST
    # TableRowNode - Represents a row in a table
    #
    # A table row contains multiple table cells (TableCellNode).
    # Each cell can contain text and inline elements.
    class TableRowNode < Node
      ROW_TYPES = %i[header body]

      def initialize(location:, row_type: :body, natural_cell_count: nil, **kwargs)
        super
        @children = []
        @row_type = row_type.to_sym
        # The row's own cell count as split from the source, before
        # TableProcessor#adjust_columns pops trailing empty cells and pads short
        # rows out to the table width. LaTeX/HTML render the padded row; IDGXML
        # never pads or pops -- IDGXMLBuilder emits each row's own cells only --
        # so the IDGXML renderer emits just the first #natural_cell_count cells.
        # nil until adjust_columns records it; round-tripped so a reloaded tree
        # renders identically.
        @natural_cell_count = natural_cell_count

        validate_row_type
      end

      attr_reader :children, :row_type
      attr_accessor :natural_cell_count

      def self.deserialize_from_hash(hash)
        row_type = hash['row_type']&.to_sym || :body
        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          row_type: row_type,
          natural_cell_count: hash['natural_cell_count']
        )
        if hash['children']
          hash['children'].each do |child_hash|
            child = ReVIEW::AST::JSONSerializer.deserialize_from_hash(child_hash)
            node.add_child(child) if child.is_a?(ReVIEW::AST::Node)
          end
        end
        node
      end

      private

      def serialize_properties(hash, options)
        super
        hash[:row_type] = @row_type.to_s
        hash[:natural_cell_count] = @natural_cell_count unless @natural_cell_count.nil?
      end

      def validate_row_type
        unless ROW_TYPES.include?(row_type)
          raise ArgumentError, "invalid row_type in TableRowNode: `#{row_type}`"
        end
      end
    end
  end
end
