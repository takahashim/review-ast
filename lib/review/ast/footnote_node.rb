# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'node'

module ReVIEW
  module AST
    # FootnoteNode represents a footnote definition in the AST
    #
    # This node corresponds to the //footnote command in Re:VIEW syntax.
    # It stores the footnote ID and the parsed content as children nodes.
    # The footnote content is available through the children attribute.
    class FootnoteNode < Node
      attr_reader :id, :footnote_type

      def initialize(location:, id:, footnote_type: :footnote)
        super(location: location)
        @id = id
        # :footnote or :endnote. Canonicalize to a Symbol at construction.
        @footnote_type = (footnote_type || :footnote).to_sym
      end

      # Convert footnote content to plain text (with markup removed)
      #
      # @return [String] The plain text content without markup
      def to_inline_text
        children.map(&:to_inline_text).join
      end

      def self.deserialize_from_hash(hash)
        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          id: hash['id'],
          footnote_type: hash['footnote_type']
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
        hash[:id] = @id
        hash[:footnote_type] = @footnote_type.to_s if @footnote_type != :footnote
        if children.any?
          hash[:children] = children.map { |child| child.serialize_to_hash(options) }
        end
        hash
      end
    end
  end
end
