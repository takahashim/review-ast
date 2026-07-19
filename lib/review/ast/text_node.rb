# frozen_string_literal: true

require_relative 'leaf_node'

module ReVIEW
  module AST
    class TextNode < LeafNode
      # Override serialize_to_hash to exclude children array for TextNode
      def serialize_to_hash(options = nil)
        options ||= ReVIEW::AST::JSONSerializer::Options.new

        # Start with type
        hash = {
          type: self.class.name.split('::').last
        }

        # Include location information
        if options.include_location
          hash[:location] = location_to_h
        end

        # Call node-specific serialization (adds content)
        serialize_properties(hash, options)

        # TextNode is a leaf node - do not include children array
        hash
      end

      def self.deserialize_from_hash(hash)
        new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          content: hash['content'] || ''
        )
      end

      private

      def serialize_properties(hash, _options)
        # Add content property explicitly for TextNode
        hash[:content] = content if content
        hash
      end

      def location_to_h
        return nil unless location

        # Delegate to the location so the column is included when present
        # (SourceLocation#to_h omits column only when it is nil).
        location.to_h
      end
    end
  end
end
