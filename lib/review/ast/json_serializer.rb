# frozen_string_literal: true

require 'json'
require 'review/version'
require_relative 'definition_number'

module ReVIEW
  module AST
    module JSONSerializer
      # Options for JSON serialization
      class Options
        attr_accessor :pretty, :include_location, :indent

        def initialize(pretty: true, include_location: true)
          @pretty = pretty
          @include_location = include_location
          @indent = '  '
        end
      end

      # Wire-format version of a dumped document (the enveloped form produced by
      # serialize_document). Bump when the on-disk AST JSON contract changes in a
      # way older readers cannot handle; deserialize refuses versions it does not
      # know (doc/design-improvements #4).
      AST_FORMAT_VERSION = 1

      module_function

      # Serialize AST node to JSON
      def serialize(node, options = Options.new)
        hash = serialize_to_hash(node, options)
        if options.pretty
          JSON.pretty_generate(hash, indent: options.indent)
        else
          JSON.generate(hash)
        end
      end

      # Serialize a document root to the versioned dump envelope. This is the form
      # written by review-ast-dump: a self-describing artifact that external
      # renderers can check before trusting the tree. The node tree itself is
      # unchanged (serialize_to_hash), so per-node serialization stays bare; only
      # the dump boundary carries the header. deserialize accepts both forms.
      def serialize_document(node, options = Options.new)
        hash = {
          'ast_format' => AST_FORMAT_VERSION,
          'generator' => "review #{ReVIEW::VERSION}",
          'root' => serialize_to_hash(node, options)
        }
        if options.pretty
          JSON.pretty_generate(hash, indent: options.indent)
        else
          JSON.generate(hash)
        end
      end

      # Serialize AST node to Hash
      def serialize_to_hash(node, options = Options.new)
        case node
        when Array
          node.map { |item| serialize_to_hash(item, options) }
        when Hash
          node.transform_values { |value| serialize_to_hash(value, options) }
        when ReVIEW::AST::Node
          # Delegate to the node's own serialization method
          node.serialize_to_hash(options)
        else
          node
        end
      end

      # Deserialize JSON string to AST nodes. Accepts both the bare node form
      # (serialize) and the versioned dump envelope (serialize_document).
      def deserialize(json_string)
        hash = unwrap_document(JSON.parse(json_string))
        deserialize_from_hash(hash)
      end

      # If the hash is a versioned dump envelope, verify the format version and
      # return the inner root; otherwise return it unchanged (a bare node hash).
      def unwrap_document(hash)
        return hash unless hash.is_a?(Hash) && hash.key?('ast_format') && hash.key?('root')

        version = hash['ast_format']
        unless version == AST_FORMAT_VERSION
          raise StandardError, "Unsupported ast_format version: #{version.inspect} (this build reads #{AST_FORMAT_VERSION})"
        end

        hash['root']
      end

      def deserialize_caption_fields(hash)
        caption_value = hash['caption']
        caption_node_value = hash['caption_node']

        caption_node = if caption_node_value
                         deserialize_from_hash(caption_node_value)
                       elsif caption_value.is_a?(Hash) || caption_value.is_a?(Array)
                         deserialize_from_hash(caption_value)
                       end

        caption_string = caption_value.is_a?(String) ? caption_value : nil

        [caption_string, caption_node]
      end

      # Restore the cross-cutting base-node fields written by
      # Node#serialize_common_node_fields: the Indexer-stamped definition_number
      # and the //noindent flag.
      def restore_common_node_fields(node, hash)
        dn = hash['definition_number']
        if dn.is_a?(Hash)
          node.definition_number = ReVIEW::AST::DefinitionNumber.new(
            number: dn['number'],
            chapter_number: dn['chapter_number']
          )
        end

        node.noindent = true if hash['noindent']
        node.image_path = hash['image_path'] if hash['image_path']
      end

      # Helper method to create location from hash or use a default
      def restore_location(hash)
        location_data = hash['location']
        return nil unless location_data && location_data.is_a?(Hash)

        filename = location_data['filename']
        lineno = location_data['lineno']
        return nil unless filename && lineno

        ReVIEW::AST::SourceLocation.new(filename, lineno, location_data['column'])
      end

      # Deserialize hash to AST node
      def deserialize_from_hash(hash)
        return nil unless hash

        case hash
        when Array
          hash.map { |item| deserialize_from_hash(item) }
        when String
          # Plain string is treated as text content
          hash
        when Hash
          node_type = hash['type']
          return hash.to_s unless node_type

          # Check if the node class exists
          begin
            node_class = ReVIEW::AST.const_get(node_type)
          rescue NameError
            raise StandardError, "Unknown node type: #{node_type}. Cannot deserialize JSON with unknown node type."
          end

          # Verify it's actually a node class
          unless node_class.respond_to?(:deserialize_from_hash)
            raise StandardError, "Node class #{node_type} does not implement deserialize_from_hash method."
          end

          # Delegate to the node class, then restore the cross-cutting base-node
          # fields (definition_number, //noindent) that the base
          # Node#serialize_common_node_fields wrote.
          node = node_class.deserialize_from_hash(hash)
          restore_common_node_fields(node, hash) if node.is_a?(ReVIEW::AST::Node)
          node
        else
          raise StandardError, "invalid hash: `#{hash}`"
        end
      end
    end
  end
end
