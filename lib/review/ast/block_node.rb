# frozen_string_literal: true

require_relative 'node'
require_relative 'caption_node'
require_relative 'captionable'

module ReVIEW
  module AST
    # BlockNode - Generic block container node
    # Used for various block-level constructs like quote, read, etc.
    class BlockNode < Node
      include Captionable

      attr_accessor :caption_node
      attr_reader :block_type, :args

      def initialize(location:, block_type:, args: nil, caption_node: nil, **kwargs)
        super(location: location, **kwargs)
        # :quote, :read, etc. Canonicalize to a Symbol at construction.
        @block_type = block_type&.to_sym
        @args = args || []
        @caption_node = caption_node
      end

      def self.deserialize_from_hash(hash)
        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          block_type: hash['block_type'] || :quote,
          args: hash['args'],
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
        hash[:block_type] = block_type
        hash[:args] = args if args
        serialize_caption_to_hash(hash, options)
        if children.any?
          hash[:children] = children.map { |child| child.serialize_to_hash(options) }
        end
        hash
      end
    end
  end
end
