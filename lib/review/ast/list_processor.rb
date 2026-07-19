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
      def initialize(ast_compiler)
        @ast_compiler = ast_compiler
        @parser = ListParser.new(ast_compiler)
        @assembler = NestedListAssembler.new(ast_compiler, ast_compiler.inline_processor)
      end

      # The compiler dispatches to one of these per the list marker it detected,
      # so each just wires its own parser and assembler methods together -- no
      # runtime type dispatch is needed here.
      def process_unordered_list(f)
        build_and_add(@parser.parse_unordered_list(f)) { |items| @assembler.build_unordered_list(items) }
      end

      def process_ordered_list(f)
        build_and_add(@parser.parse_ordered_list(f)) { |items| @assembler.build_ordered_list(items) }
      end

      def process_definition_list(f)
        build_and_add(@parser.parse_definition_list(f)) { |items| @assembler.build_definition_list(items) }
      end

      private

      # Assemble the parsed items (yielded to the given block) and add the result
      # to the AST, unless the list turned out empty.
      def build_and_add(items)
        return if items.empty?

        @ast_compiler.add_child_to_current_node(yield(items))
      end
    end
  end
end
