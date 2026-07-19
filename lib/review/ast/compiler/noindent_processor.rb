# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/block_node'
require 'review/ast/paragraph_node'
require_relative 'directive_lowering_pass'

module ReVIEW
  module AST
    class Compiler
      # NoindentProcessor - lowers //noindent onto the next paragraph or eligible
      # block (quote/lead/flushright/flushleft), setting its noindent flag.
      class NoindentProcessor < DirectiveLoweringPass
        NOINDENT_BLOCK_TYPES = %i[quote lead flushright flushleft].freeze

        private

        def directive_type
          :noindent
        end

        def target?(node)
          return true if node.is_a?(ParagraphNode)

          node.is_a?(BlockNode) && NOINDENT_BLOCK_TYPES.include?(node.block_type)
        end

        def apply(target, _directive)
          target.noindent = true
        end
      end
    end
  end
end
