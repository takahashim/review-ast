# frozen_string_literal: true

require_relative 'node'
require_relative 'caption_node'
require_relative 'captionable'

module ReVIEW
  module AST
    # MinicolumnNode - Represents minicolumn blocks (note, memo, tip, etc.)
    class MinicolumnNode < Node
      include Captionable

      attr_reader :minicolumn_type

      def initialize(location:, minicolumn_type: nil, caption_node: nil, **kwargs)
        super(location: location, **kwargs)
        # :note, :memo, :tip, :info, :warning, :important, :caution, :notice.
        # Canonicalize to a Symbol at construction (fresh compile or deserialized).
        @minicolumn_type = minicolumn_type&.to_sym
        @caption_node = caption_node
      end

      # Deserialize from hash
      def self.deserialize_from_hash(hash)
        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          minicolumn_type: hash['minicolumn_type'] || hash['column_type'],
          caption_node: deserialize_caption_from_hash(hash)
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
        hash[:minicolumn_type] = minicolumn_type
        serialize_caption_to_hash(hash, options)
        if children.any?
          hash[:children] = children.map { |child| child.serialize_to_hash(options) }
        end
        hash
      end
    end
  end
end
