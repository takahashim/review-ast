# frozen_string_literal: true

require_relative 'node'
require_relative 'caption_node'
require_relative 'captionable'

module ReVIEW
  module AST
    class HeadlineNode < Node
      include Captionable

      attr_accessor :auto_id
      attr_reader :level, :label, :tag, :raw_caption

      # +raw_caption+ is the caption exactly as it appears in the source, after
      # removing the level markers and an optional leading tag/label but before
      # inline parsing (e.g. "@<b>{Foo}" stays raw). It is the source-faithful
      # chapter-title datum: the first headline's raw_caption is what the chapter
      # title is, matching ReVIEW::Book::BookUnit#title (set by Indexer, pinned by
      # test/ast/test_chapter_title.rb). caption_node holds the parsed form for
      # rendering.
      def initialize(location:, level: nil, label: nil, caption_node: nil, tag: nil, auto_id: nil, raw_caption: nil, **kwargs)
        super(location: location, **kwargs)
        @level = level
        @label = label
        @caption_node = caption_node
        @tag = tag
        @auto_id = auto_id
        @raw_caption = raw_caption
      end

      # Check if headline has specific tag option
      def tag?(tag_name)
        @tag == tag_name
      end

      # Check for specific headline options
      def nonum?
        tag?('nonum')
      end

      def notoc?
        tag?('notoc')
      end

      def nodisp?
        tag?('nodisp')
      end

      def self.deserialize_from_hash(hash)
        new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          level: hash['level'],
          label: hash['label'],
          caption_node: deserialize_caption_from_hash(hash),
          tag: hash['tag'],
          auto_id: hash['auto_id'],
          raw_caption: hash['raw_caption']
        )
      end

      private

      def serialize_properties(hash, options)
        hash[:level] = level
        hash[:label] = label
        serialize_caption_to_hash(hash, options)
        hash[:tag] = tag if tag
        hash[:auto_id] = auto_id if auto_id
        hash[:raw_caption] = raw_caption if raw_caption
        hash
      end
    end
  end
end
