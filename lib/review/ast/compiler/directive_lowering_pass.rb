# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/directive_node'
require_relative 'post_processor'

module ReVIEW
  module AST
    class Compiler
      # DirectiveLoweringPass - shared skeleton for the stage-B directive
      # micro-passes (tsize, firstlinenum, noindent, olnum).
      #
      # Each of those lowers one //directive onto the single following node of a
      # distinct type: find the directive among a node's children, find the next
      # eligible target after it, fold the directive's value onto that target as
      # an attribute, and drop the directive node. Only three things vary between
      # them, which subclasses supply:
      #   - #directive_type : the DirectiveNode type this pass consumes
      #   - #target?(node)  : whether a node is an eligible lowering target
      #   - #apply(target, directive) : fold the directive onto the target
      # The walk / find-next / delete-in-reverse mechanics live here once (see
      # doc/design-improvements #3).
      class DirectiveLoweringPass < PostProcessor
        private

        def process_node(node)
          indices_to_remove = []

          node.children.each_with_index do |child, idx|
            if lowered_directive?(child)
              target = find_next_target(node.children, idx + 1)
              apply(target, child) if target
              indices_to_remove << idx
            else
              process_node(child)
            end
          end

          # Delete in reverse so earlier indices stay valid.
          indices_to_remove.reverse_each { |idx| node.children.delete_at(idx) }
        end

        def lowered_directive?(node)
          node.is_a?(DirectiveNode) && node.directive_type == directive_type
        end

        def find_next_target(children, start_index)
          (start_index...children.length).each do |j|
            return children[j] if target?(children[j])
          end
          nil
        end

        # --- subclass hooks ---

        def directive_type
          raise NotImplementedError, "#{self.class} must define #directive_type"
        end

        def target?(_node)
          raise NotImplementedError, "#{self.class} must define #target?"
        end

        def apply(_target, _directive)
          raise NotImplementedError, "#{self.class} must define #apply"
        end
      end
    end
  end
end
