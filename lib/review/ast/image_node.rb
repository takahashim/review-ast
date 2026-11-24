# frozen_string_literal: true

require_relative 'leaf_node'
require_relative 'caption_node'
require_relative 'captionable'
require_relative 'code_line_node'

module ReVIEW
  module AST
    class ImageNode < LeafNode
      include Captionable

      attr_reader :metric, :image_type

      # The block's body lines, inline-compiled (one CodeLineNode each): what
      # the builders print in place of an image that is not found
      # (Builder#image_dummy). `content` keeps the same lines as written.
      attr_reader :dummy_lines

      def initialize(location:, id: nil, caption_node: nil, metric: nil, image_type: :image, content: '', dummy_lines: nil, **kwargs)
        super(location: location, id: id, content: content, **kwargs)
        @caption_node = caption_node
        @metric = metric
        @image_type = image_type&.to_sym # canonicalize to Symbol at construction
        @dummy_lines = dummy_lines || []
      end

      # Include the dummy lines in a full-tree walk (see Node#each_subnode).
      def extra_subnodes
        super + dummy_lines
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
          image_type: hash['image_type'] || :image,
          content: hash['content'] || '',
          dummy_lines: (hash['dummy_lines'] || []).map { |line| ReVIEW::AST::JSONSerializer.deserialize_from_hash(line) }
        )
      end

      private

      def serialize_properties(hash, options)
        hash[:id] = id if id?
        serialize_caption_to_hash(hash, options)
        hash[:metric] = metric if metric
        hash[:image_type] = image_type
        hash[:content] = content if content && !content.empty?
        hash[:dummy_lines] = dummy_lines.map { |line| line.serialize_to_hash(options) } unless dummy_lines.empty?
        hash
      end
    end
  end
end
