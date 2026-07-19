# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/node'
require 'review/ast/list_node'
require 'review/ast/text_node'
require 'review/ast/paragraph_node'

module ReVIEW
  module AST
    class ListProcessor
      # NestedListAssembler - Build nested list AST structures
      #
      # This class constructs properly nested AST node structures from
      # parsed list item data. It handles the complex logic of building
      # nested parent-child relationships between list nodes and items.
      #
      # Responsibilities:
      # - Build nested ListNode and ListItemNode structures
      # - Handle different list types (ul, ol, dl) with type-specific logic
      # - Manage nesting levels and parent-child relationships
      # - Create proper AST hierarchy for complex nested lists
      #
      class NestedListAssembler
        def initialize(compiler, inline_processor)
          @compiler = compiler
          @inline_processor = inline_processor
        end

        # Build unordered list with proper nesting
        # @param items [Array<ListParser::ListItemData>] Parsed unordered list items
        # @return [ReVIEW::AST::ListNode] Root unordered list node
        def build_unordered_list(items)
          create_list_node(:ul) do |root_list|
            build_nested_items(items, root_list, :ul)
          end
        end

        # Build ordered list with proper nesting
        # @param items [Array<ListParser::ListItemData>] Parsed ordered list items
        # @return [ReVIEW::AST::ListNode] Root ordered list node
        def build_ordered_list(items)
          create_list_node(:ol) do |root_list|
            # Set start_number based on the first item's number if available
            if items.first && items.first.metadata[:number]
              root_list.start_number = items.first.metadata[:number]
            end

            build_nested_items(items, root_list, :ol)
          end
        end

        # Build definition list with proper structure
        # @param items [Array<ListParser::ListItemData>] Parsed definition list items
        # @return [ReVIEW::AST::ListNode] Root definition list node
        def build_definition_list(items)
          create_list_node(:dl) do |root_list|
            items.each do |item_data|
              list = create_list_item_node(item_data) do |item_node|
                # Add definition content (additional children) - only definition, not term
                item_data.continuation_lines.each do |definition_line|
                  add_definition_content(item_node, definition_line)
                end
              end
              # Create list item for term/definition pair with term_children
              root_list.add_child(list)
            end
          end
        end

        private

        # Assemble the flat items into the nested ListNode/ListItemNode tree,
        # tracking the current list at each level and validating level jumps.
        def build_nested_items(items, root_list, list_type)
          return if items.empty?

          current_lists = { 1 => root_list }
          previous_level = 0

          items.each do |item_data|
            # 1. Validate and adjust level
            level = item_data.level
            if level > previous_level && (level - previous_level) > 1
              @compiler.error('too many *.')
              level = previous_level + 1
            end
            previous_level = level

            # 2. Build item node with content
            item_data = item_data.with_adjusted_level(level)
            item_node = create_list_item_node(item_data) do |node|
              add_all_content_to_item(node, item_data)
            end

            # 3. Add to structure
            if level == 1
              root_list.add_child(item_node)
              current_lists[1] = root_list
            else
              add_to_parent_list(item_node, level, list_type, current_lists)
            end
          end
        end

        # Add item to parent list at nested level
        # @param item_node [ReVIEW::AST::ListItemNode] Item to add
        # @param level [Integer] Nesting level
        # @param list_type [Symbol] Type of list
        # @param current_lists [Hash] Map of level to list node
        def add_to_parent_list(item_node, level, list_type, current_lists)
          parent_list = current_lists[level - 1]
          return unless parent_list&.children&.any?

          last_parent_item = parent_list.children.last

          # Find or create nested list
          nested_list = last_parent_item.children.find do |child|
            child.is_a?(ReVIEW::AST::ListNode) && child.list_type == list_type
          end

          nested_list ||= create_list_node(list_type) do |list|
              last_parent_item.add_child(list)
            end

          nested_list.add_child(item_node)
          current_lists[level] = nested_list
        end

        # Add all content from item data to list item node
        # @param item_node [ReVIEW::AST::ListItemNode] Target item node
        # @param item_data [ListParser::ListItemData] Source item data
        def add_all_content_to_item(item_node, item_data)
          # Add main content
          add_content_to_item(item_node, item_data.content)

          # Add continuation lines. Each is a separate source line; record the
          # boundary so the LaTeX renderer can reinsert the newline (LATEXBuilder
          # joins item lines with "\n"; HTMLBuilder joins with "", so the split
          # must stay a renderer-level decision, not be baked into the AST).
          item_data.continuation_lines.each do |line|
            item_node.mark_source_line_break!
            add_content_to_item(item_node, line)
          end
        end

        # Add content to list item using inline processor
        # @param item_node [ReVIEW::AST::ListItemNode] Target item node
        # @param content [String] Content to add
        def add_content_to_item(item_node, content)
          @inline_processor.parse_inline_elements(content, item_node)
        end

        # Add one definition line to a definition-list item as a paragraph.
        # Always parses the line as inline content -- a line with no inline
        # command simply yields a single text node inside the paragraph -- rather
        # than deciding the node type from a fragile content.include?('@<') check.
        def add_definition_content(item_node, definition_content)
          item_node.add_child(parse_inline_to_paragraph(definition_content))
        end

        # Process definition list term content into inline element nodes.
        # @param term_content [String] Term content to process
        # @return [Array<Node>] Processed term children nodes
        def process_definition_term_content(term_content)
          parse_inline_to_paragraph(term_content).children
        end

        # Parse a string of inline content into a fresh ParagraphNode. Used both
        # to hold a definition line and (via #children) to collect a term's inline
        # nodes -- the inline processor parses into a node, so a paragraph is the
        # natural container.
        def parse_inline_to_paragraph(content)
          paragraph = ReVIEW::AST::ParagraphNode.new(location: current_location)
          @inline_processor.parse_inline_elements(content, paragraph)
          paragraph
        end

        # Create a new ListNode
        # @param list_type [Symbol] Type of list (:ul, :ol, :dl, etc.)
        # @yield [node] Optional block for node initialization
        # @yieldparam node [ReVIEW::AST::ListNode] The created list node
        # @return [ReVIEW::AST::ListNode] New list node
        def create_list_node(list_type)
          node = ReVIEW::AST::ListNode.new(location: current_location, list_type: list_type)
          yield(node) if block_given?
          node
        end

        # Create a new ListItemNode from parsed data
        # @param item_data [ListParser::ListItemData] Parsed item data
        # @param term_children [Array<Node>] Optional term children for definition lists
        # @yield [node] Optional block for node initialization
        # @yieldparam node [ReVIEW::AST::ListItemNode] The created list item node
        # @return [ReVIEW::AST::ListItemNode] New list item node
        def create_list_item_node(item_data)
          node_attributes = {
            location: current_location,
            level: item_data.level
          }

          # Add type-specific attributes
          case item_data.type
          when :ol
            node_attributes[:number] = item_data.metadata[:number]
          when :dl
            node_attributes[:term_children] = process_definition_term_content(item_data.content)
          end

          node = ReVIEW::AST::ListItemNode.new(**node_attributes)
          yield(node) if block_given?
          node
        end

        # Get current location for node creation
        # @return [SourceLocation] Current location
        def current_location
          @compiler.location
        end
      end
    end
  end
end
