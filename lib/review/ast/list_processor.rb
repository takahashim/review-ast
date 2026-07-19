# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'list_parser'
require_relative 'list_processor/nested_list_assembler'

module ReVIEW
  module AST
    # ListProcessor - Main coordinator for list processing
    #
    # This class orchestrates the full list processing pipeline by coordinating
    # between ListParser (for parsing) and NestedListAssembler (for AST construction).
    # It provides clean, testable methods that replace the monolithic list processing
    # methods in ASTCompiler.
    #
    # Responsibilities:
    # - Coordinate the full list processing pipeline
    # - Provide clean interfaces for different list types
    # - Handle rendering through AST renderer
    # - Manage dependencies between parser, builder, and renderer
    class ListProcessor
      # Each list kind maps to the ListParser method that parses it and the
      # NestedListAssembler method that assembles its AST. One table drives every
      # dispatch below, so a new kind (or an unknown one) is handled in one place.
      KINDS = {
        ul: { parse: :parse_unordered_list, build: :build_unordered_list },
        ol: { parse: :parse_ordered_list,   build: :build_ordered_list },
        dl: { parse: :parse_definition_list, build: :build_definition_list }
      }.freeze

      def initialize(ast_compiler)
        @ast_compiler = ast_compiler
        @parser = ListParser.new(ast_compiler)
        @nested_list_assembler = NestedListAssembler.new(ast_compiler, ast_compiler.inline_processor)
      end

      # Named entry points the compiler dispatches to per detected list marker.
      def process_unordered_list(f)
        process_list(f, :ul)
      end

      def process_ordered_list(f)
        process_list(f, :ol)
      end

      def process_definition_list(f)
        process_list(f, :dl)
      end

      # Parse a list of the given kind and add the assembled node to the AST.
      # @param f [LineInput] Input file stream
      # @param list_type [Symbol] Type of list (:ul, :ol, :dl)
      def process_list(f, list_type)
        items = parse_list_items(f, list_type)
        return if items.empty?

        list_node = @nested_list_assembler.public_send(kind_for(list_type)[:build], items)
        @ast_compiler.add_child_to_current_node(list_node)
      end

      # Parse list items of the given kind without building the AST.
      # @param f [LineInput] Input file stream
      # @param list_type [Symbol] Type of list (:ul, :ol, :dl)
      # @return [Array<ListParser::ListItemData>] Parsed items
      def parse_list_items(f, list_type)
        @parser.public_send(kind_for(list_type)[:parse], f)
      end

      private

      # Look up the parse/build methods for a kind, or fail with a located error.
      def kind_for(list_type)
        KINDS.fetch(list_type) do
          raise CompileError, "Unknown list type: #{list_type}#{@ast_compiler.location.format_for_error}"
        end
      end
    end
  end
end
