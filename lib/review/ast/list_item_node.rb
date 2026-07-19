# frozen_string_literal: true

require_relative 'node'

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    class ListItemNode < Node
      attr_reader :level, :number, :item_type, :term_children
      attr_accessor :item_number

      # Child indices at which a source line break occurred between continuation
      # lines. This is a source fact (where the author broke the line), not a
      # render decision, so it is named after the source and serialized. Only the
      # LaTeX renderer currently consumes it (it joins item lines with "\n" like
      # LATEXBuilder); other renderers concatenate and ignore it.
      attr_reader :source_line_breaks

      def initialize(location:, level: 1, number: nil, item_type: nil, term_children: [], source_line_breaks: nil, **kwargs)
        super(location: location, **kwargs)
        @level = level
        @number = number
        @item_type = item_type&.to_sym # :dt, :dd, or nil; canonicalized at construction
        @term_children = term_children # For definition lists: stores processed term content separately
        @item_number = nil # Absolute item number for ordered lists (set by ListItemNumberingProcessor)
        @source_line_breaks = source_line_breaks || []
      end

      # Record that a source line break precedes the next child to be added
      # (i.e. between the previous continuation line and the next one).
      def mark_source_line_break!
        @source_line_breaks << children.size
      end

      def to_h
        result = super.merge(
          level: level
        )
        result[:number] = number if number
        result[:item_type] = item_type if item_type
        result[:term_children] = term_children.map(&:to_h) if term_children.any?
        result
      end

      # Convenience methods for type checking
      def definition_term?
        item_type == :dt
      end

      def definition_desc?
        item_type == :dd
      end

      def self.deserialize_from_hash(hash)
        # Deserialize term_children if present
        term_children = []
        if hash['term_children']
          term_children = hash['term_children'].map do |child_hash|
            ReVIEW::AST::JSONSerializer.deserialize_from_hash(child_hash)
          end.compact
        end

        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          level: hash['level'] || 1,
          number: hash['number'],
          item_type: hash['item_type'],
          term_children: term_children,
          source_line_breaks: hash['source_line_breaks']
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
        hash[:children] = children.map { |child| child.serialize_to_hash(options) } if children.any?
        hash[:term_children] = term_children.map { |child| child.serialize_to_hash(options) } if term_children.any?
        hash[:level] = level
        hash[:number] = number if number
        hash[:item_type] = item_type if item_type
        hash[:source_line_breaks] = source_line_breaks if source_line_breaks.any?
        hash
      end
    end
  end
end
