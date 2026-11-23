# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # Base visitor class for traversing AST nodes using the Visitor pattern.
    # This class provides a generic way to walk through AST structures and
    # perform operations on each node type.
    #
    # Usage:
    #   class MyVisitor < ReVIEW::AST::Visitor
    #     def visit_headline(node)
    #       # Process headline node
    #     end
    #
    #     def visit_paragraph(node)
    #       # Process paragraph node
    #     end
    #   end
    #
    #   visitor = MyVisitor.new
    #   result = visitor.visit(ast_root)
    class Visitor
      # Visit a node and dispatch to the appropriate visit method.
      #
      # @param node [Object] The AST node to visit
      # @return [Object] The result of the visit method
      def visit(node)
        return nil if node.nil?

        method_name = node.visit_method_name

        if respond_to?(method_name, true)
          send(method_name, node)
        else
          raise NotImplementedError, "Visitor #{self.class.name} does not implement #{method_name} for #{node.class.name}"
        end
      end

      # Default handling for a DirectiveNode (a parser-instruction marker such as
      # //noindent or //olnum). Markers carry no semantic content of their own and
      # are removed by a post-process pass before the core tree is rendered or
      # serialized, so a visitor just descends into the marker (normally empty) by
      # default. A visitor that must act on a specific directive overrides this.
      def visit_directive(node)
        visit_all(node.children)
        nil
      end

      # Default handling for an ExtensionBlockNode (a block command defined in
      # review-ext.rb). It has no children and its meaning is the book's, so a
      # visitor that is not rendering it has nothing to do. Renderers and the
      # source generator override this.
      def visit_extension_block(_node)
        nil
      end

      # Visit multiple nodes and return an array of results.
      #
      # @param nodes [Array] Array of AST nodes to visit
      # @return [Array] Array of visit results
      def visit_all(nodes)
        return [] unless nodes

        nodes.map { |node| visit(node) }
      end
    end
  end
end
