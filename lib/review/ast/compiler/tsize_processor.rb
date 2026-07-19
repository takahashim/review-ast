# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/node'
require 'review/ast/block_node'
require 'review/ast/directive_node'
require 'review/ast/table_node'
require_relative 'post_processor'

module ReVIEW
  module AST
    class Compiler
      # TsizeProcessor - Processes //tsize commands in AST
      #
      # Attaches the raw //tsize argument to the next TableNode (as a source fact,
      # target-neutral) and removes the //tsize directive. Resolving the builder
      # target and deriving the column specification happen at render time, so the
      # shared tree does not depend on which builder it was compiled for. See
      # doc/design-improvements #5.
      #
      # Usage:
      #   TsizeProcessor.process(ast_root, chapter: chapter)
      class TsizeProcessor < PostProcessor
        private

        def process_node(node)
          indices_to_remove = []

          node.children.each_with_index do |child, idx|
            if tsize_command?(child)
              raw = child.args.first
              target_table = find_next_table(node.children, idx + 1)
              target_table.tsize = raw if target_table && raw

              # Mark tsize node for removal
              indices_to_remove << idx
            else
              # Recursively process child nodes
              process_node(child)
            end
          end

          # Remove marked nodes in reverse order to avoid index shifting
          indices_to_remove.reverse_each do |idx|
            node.children.delete_at(idx)
          end
        end

        def tsize_command?(node)
          node.is_a?(DirectiveNode) && node.directive_type == :tsize
        end

        # Find the next TableNode in children array
        # @param children [Array<Node>] array of child nodes
        # @param start_index [Integer] index to start searching from
        # @return [TableNode, nil] next TableNode or nil if not found
        def find_next_table(children, start_index)
          (start_index...children.length).each do |j|
            node = children[j]
            return node if node.is_a?(TableNode)
          end
          nil
        end
      end
    end
  end
end
