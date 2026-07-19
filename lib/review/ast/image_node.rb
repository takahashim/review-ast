# frozen_string_literal: true

require_relative 'leaf_node'
require_relative 'caption_node'
require_relative 'captionable'

module ReVIEW
  module AST
    class ImageNode < LeafNode
      include Captionable

      attr_reader :metric, :image_type

      # Filesystem path of the image file, resolved once at compile time by the
      # Indexer via ReVIEW::Book::ImageFinder (nil when the image is unbound).
      # This is a source-derived fact stamped on the node -- like
      # definition_number -- so renderers need no chapter image index and dumps
      # are self-contained (doc/design-improvements #7). It is builder-specific
      # (the finder searches <imagedir>/<builder>/...), matching the single
      # builder a given compile targets.
      attr_accessor :image_path

      def initialize(location:, id: nil, caption_node: nil, metric: nil, image_type: :image, content: '', image_path: nil, **kwargs)
        super(location: location, id: id, content: content, **kwargs)
        @caption_node = caption_node
        @metric = metric
        @image_type = image_type
        @image_path = image_path
      end

      # Override to_h to include ImageNode-specific attributes
      def to_h
        result = super
        result[:id] = id if id?
        result[:caption_node] = caption_node&.to_h if caption_node
        result[:metric] = metric if metric
        result[:image_type] = image_type
        result
      end

      # Override serialize_to_hash to include ImageNode-specific attributes
      def serialize_to_hash(options = nil)
        options ||= ReVIEW::AST::JSONSerializer::Options.new

        # Start with type
        hash = {
          type: self.class.name.split('::').last
        }

        # Include location information
        if options.include_location
          hash[:location] = location&.to_h
        end

        # Call node-specific serialization
        serialize_properties(hash, options)

        # LeafNode automatically excludes children
        serialize_common_node_fields(hash)
      end

      def self.deserialize_from_hash(hash)
        new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          id: hash['id'],
          caption_node: deserialize_caption_from_hash(hash),
          metric: hash['metric'],
          image_type: hash['image_type']&.to_sym || :image,
          content: hash['content'] || '',
          image_path: hash['image_path']
        )
      end

      private

      def serialize_properties(hash, options)
        hash[:id] = id if id?
        serialize_caption_to_hash(hash, options)
        hash[:metric] = metric if metric
        hash[:image_type] = image_type
        hash[:content] = content if content && !content.empty?
        hash[:image_path] = image_path if image_path
        hash
      end
    end
  end
end
