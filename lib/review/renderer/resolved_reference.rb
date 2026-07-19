# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    # Access to the resolved reference under a reference-type InlineNode.
    #
    # Renderers only ever see trees that have been through reference
    # resolution, so an unresolved reference here is a pipeline bug rather than
    # a document error -- hence the raise. Every inline handler used to inline
    # the same four-line check, once per reference command.
    module ResolvedReference
      # @param node [InlineNode] The inline node holding the reference
      # @return [ReferenceNode] Its resolved reference child
      # @raise [RuntimeError] If the reference was never resolved
      def resolved_reference_node(node)
        ref_node = node.children.first
        unless ref_node.respond_to?(:reference_node?) && ref_node.reference_node? && ref_node.resolved?
          raise 'BUG: Reference should be resolved at AST construction time'
        end

        ref_node
      end

      # @param node [InlineNode] The inline node holding the reference
      # @return [ResolvedData] The resolved data itself
      def resolved_data_for(node)
        resolved_reference_node(node).resolved_data
      end
    end
  end
end
