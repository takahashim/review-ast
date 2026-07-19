# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'json'
require_relative 'json_serializer'
require_relative 'source_location'

module ReVIEW
  module AST
    # Abstract base class for all AST nodes
    # This class should not be instantiated directly - use specific subclasses instead
    #
    # Design principles:
    # - Branch nodes (like ParagraphNode, InlineNode) inherit from Node and have children
    # - Leaf nodes (like TextNode, ImageNode) inherit from LeafNode and cannot have children
    # - LeafNode may have a content attribute, but subclasses can define their own data attributes
    # - Never mix content and children in the same node
    class Node
      attr_reader :location, :type, :id, :original_text, :children
      attr_accessor :parent

      # Set by the Indexer for numbered definition blocks (//list, //table,
      # //image, //texequation, //bibpaper, footnote, endnote). A DefinitionNumber
      # or nil. Lets a renderer read the number off the node instead of querying
      # the legacy @chapter index. See doc/design-improvements #1.
      attr_accessor :definition_number

      # //noindent modifier, set by NoindentProcessor on the following block. It
      # is cross-cutting -- it applies to a paragraph or to certain blocks
      # (quote/lead/flushright/flushleft) -- so it is a typed field on the base
      # node rather than an entry in an untyped attribute bag. Read via #noindent?.
      attr_writer :noindent

      def initialize(location:, type: nil, id: nil, original_text: nil, **_kwargs)
        # Prevent direct instantiation of abstract base class (except in tests)
        if self.instance_of?(ReVIEW::AST::Node)
          raise StandardError, 'AST::Node is an abstract class and cannot be instantiated directly. Use a specific subclass instead.'
        end

        @location = location
        @children = []
        @parent = nil
        @type = type
        @id = id
        @original_text = original_text
        @noindent = false
      end

      def noindent?
        @noindent ? true : false
      end

      def leaf_node?
        false
      end

      def reference_node?
        false
      end

      # True only for DirectiveNode (a parser-instruction marker). Lets a pass or
      # the stage-boundary check test for markers without a type/name convention.
      def directive?
        false
      end

      def add_child(child)
        child.parent = self
        @children << child
      end

      def remove_child(child)
        child.parent = nil
        @children.delete(child)
      end

      # Replace a child node with a new node
      def replace_child(old_child, new_child)
        index = @children.index(old_child)
        return false unless index

        old_child.parent = nil
        @children[index] = new_child
        new_child.parent = self
        true
      end

      def insert_child(idx, *nodes)
        nodes.each do |node|
          node.parent = self
        end
        @children.insert(idx, *nodes)
      end

      # Check if node has a non-empty id
      def id?
        @id && !@id.empty?
      end

      # Return the visit method name for this node as a symbol.
      # This is used by the Visitor pattern for method dispatch.
      #
      # @return [Symbol] The visit method symbol (e.g., :visit_headline)
      #
      # @example
      #   HeadlineNode.new.visit_method_name #=> :visit_headline
      def visit_method_name
        class_name = self.class.name.split('::').last

        # Convert CamelCase to snake_case and remove 'Node' suffix
        method_name = class_name.
                      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
                      gsub(/([a-z\d])([A-Z])/, '\1_\2').
                      downcase.
                      gsub(/_node$/, '')

        :"visit_#{method_name}"
      end

      # Convert node to inline text representation (text without markup).
      # This is used in inline contexts such as captions, headings, and footnotes.
      #
      # Default implementation for branch nodes (block elements):
      # Block elements cannot be used in inline contexts, so this raises an error.
      # Subclasses that can produce inline text should override this method.
      #
      # @return [String] The text content without markup
      # @raise [ArgumentError] If block element is used in inline context
      def to_inline_text
        raise ArgumentError, "Block element #{self.class} cannot be used in inline context"
      end

      # Basic JSON serialization for compatibility
      def to_h
        result = {
          type: self.class.name.split('::').last,
          location: location&.to_h,
          children: children.map(&:to_h)
        }
        result[:node_type] = @type if @type && !@type.empty?
        result[:id] = @id if @id && !@id.empty?
        result
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      # Enhanced JSON serialization with options (using JSONSerializer)
      def serialize_to_hash(options = nil)
        options ||= JSONSerializer::Options.new

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

        # Serialize child nodes if any
        if children && children.any?
          hash[:children] = children.map { |child| child.serialize_to_hash(options) }
        end

        serialize_common_node_fields(hash)
      end

      # Attach the cross-cutting base-node fields (the Indexer-stamped
      # definition_number for numbered blocks, and the //noindent flag) to a
      # serialized hash. These are part of the core tree and must survive a round
      # trip so a re-loaded tree renders identically without re-running the
      # indexing / post-process passes. Nodes that override #serialize_to_hash
      # (TableNode, ImageNode, TexEquationNode) must call this too. Symmetric with
      # JSONSerializer#restore_common_node_fields.
      def serialize_common_node_fields(hash)
        hash[:definition_number] = @definition_number.to_h if @definition_number
        hash[:noindent] = true if @noindent
        hash
      end

      private

      # Override this method in subclasses to add node-specific properties
      def serialize_properties(hash, _options)
        # Base Node implementation - does nothing by default
        hash
      end
    end
  end
end
