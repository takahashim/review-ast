# frozen_string_literal: true

require_relative 'node'
require_relative 'caption_node'
require_relative 'captionable'
require_relative 'json_serializer'
require_relative 'definition_number'
require_relative 'table_column_width_parser'

module ReVIEW
  module AST
    class TableNode < Node
      include Captionable

      attr_reader :table_type, :metric
      # The raw //tsize argument that precedes this table (e.g. "10,18,50" or
      # "|latex|10,18,50" or "|l|c|r|"), or nil. This is a source fact kept
      # target-neutral: the LaTeX column spec is derived by the renderer, not
      # baked here. See doc/design-improvements #5.
      attr_accessor :tsize

      # For //imgtable only: the DefinitionNumber the image would carry if it were
      # rendered as an image. An imgtable is numbered as a table (definition_number)
      # when bound, but an unbound one falls back to the image-dummy rendering,
      # which numbers it as an image. Stamped by the Indexer so that path needs no
      # chapter image index (doc/design-improvements #7).
      attr_accessor :imgtable_image_number

      def initialize(location:, id: nil, caption_node: nil, table_type: :table, metric: nil, tsize: nil, **kwargs)
        super(location: location, id: id, **kwargs)
        @caption_node = caption_node
        # Canonicalize at construction so the field is always a symbol regardless
        # of the path (fresh compile vs. deserialized string), and no consumer or
        # serializer has to remember to coerce it.
        @table_type = (table_type || :table).to_sym # :table, :emtable, :imgtable
        @metric = metric
        @tsize = tsize
        @header_rows = []
        @body_rows = []
      end

      # The //tsize spec that applies to this table for +format+ (nil if none),
      # after resolving any |builder| target prefix. Renderers parse it into
      # their own column vocabulary.
      def tsize_value_for(format)
        TableColumnWidthParser.value_for_target(@tsize, format)
      end

      def header_rows
        @children.find_all do |node|
          node.row_type == :header
        end
      end

      def body_rows
        @children.find_all do |node|
          node.row_type == :body
        end
      end

      def add_header_row(row_node)
        unless row_node.row_type == :header
          raise ArgumentError, "Expected header row (row_type: :header), got #{row_node.row_type}"
        end

        idx = @children.index { |child| child.row_type == :body }
        if idx
          insert_child(idx, row_node)
        else
          add_child(row_node)
        end
      end

      def add_body_row(row_node)
        unless row_node.row_type == :body
          raise ArgumentError, "Expected body row (row_type: :body), got #{row_node.row_type}"
        end

        add_child(row_node)
      end

      # Get column count from table rows
      def column_count
        all_rows = header_rows + body_rows
        all_rows.first&.children&.length || 1
      end

      # Rows are grouped as header_rows/body_rows in serialize_properties, so the
      # generic "children" key is suppressed. The base skeleton still runs
      # serialize_common_node_fields, so no field is dropped.
      def serialize_children(hash, _options)
        hash
      end

      def self.deserialize_from_hash(hash)
        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          id: hash['id'],
          caption_node: deserialize_caption_from_hash(hash),
          table_type: hash['table_type'],
          metric: hash['metric'],
          tsize: hash['tsize']
        )
        if (iin = hash['imgtable_image_number']).is_a?(Hash)
          node.imgtable_image_number = ReVIEW::AST::DefinitionNumber.new(
            number: iin['number'], chapter_number: iin['chapter_number']
          )
        end
        # Process header and body rows
        (hash['header_rows'] || []).each do |row_hash|
          row = ReVIEW::AST::JSONSerializer.deserialize_from_hash(row_hash)
          node.add_header_row(row) if row.is_a?(ReVIEW::AST::TableRowNode)
        end
        (hash['body_rows'] || []).each do |row_hash|
          row = ReVIEW::AST::JSONSerializer.deserialize_from_hash(row_hash)
          node.add_body_row(row) if row.is_a?(ReVIEW::AST::TableRowNode)
        end

        node
      end

      private

      def serialize_properties(hash, options)
        hash[:id] = id if id && !id.empty?
        hash[:table_type] = table_type
        serialize_caption_to_hash(hash, options)
        hash[:header_rows] = header_rows.map { |row| row.serialize_to_hash(options) }
        hash[:body_rows] = body_rows.map { |row| row.serialize_to_hash(options) }
        hash[:metric] = metric if metric
        hash[:tsize] = tsize if tsize
        hash[:imgtable_image_number] = @imgtable_image_number.to_h if @imgtable_image_number
        hash
      end
    end
  end
end
