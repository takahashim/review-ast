# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    # What the two plain-text renderers genuinely share.
    #
    # PlaintextRenderer and TopRenderer look like near-twins, but of the 36
    # methods they have in common only these produce identical output: TOP
    # wraps almost every block in "◆→開始:…←◆" markers that plaintext has no
    # equivalent for, so the rest differ in substance rather than in decoration.
    # Rather than force the pair under a template-method base class whose hooks
    # would each have one real implementation, this holds only the methods that
    # were byte-identical in both.
    module TextRendererCommon
      def visit_document(node)
        render_children(node)
      end

      def visit_text(node)
        node.content || ''
      end

      def visit_block_blankline(_node)
        "\n"
      end

      # Labels carry no text in either format.
      def visit_block_label(_node)
        ''
      end

      def visit_block_printendnotes(_node)
        # Print all endnotes collected from the AST (doc/design-improvements #7).
        return '' if endnote_nodes.empty?

        result = +''
        endnote_nodes.each do |en|
          # Format: (number) content -- the endnote's own node is its content.
          number = en.definition_number.number
          result += "(#{number}) #{render_children(en)}\n"
        end
        result
      end
    end
  end
end
