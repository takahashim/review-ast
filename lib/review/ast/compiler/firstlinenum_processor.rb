# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/code_block_node'
require_relative 'directive_lowering_pass'

module ReVIEW
  module AST
    class Compiler
      # FirstLineNumProcessor - lowers //firstlinenum onto the next CodeBlockNode,
      # setting its starting line number.
      class FirstLineNumProcessor < DirectiveLoweringPass
        private

        def directive_type
          :firstlinenum
        end

        def target?(node)
          node.is_a?(CodeBlockNode)
        end

        def apply(target, directive)
          arg = directive.args.first
          target.first_line_num = arg.to_i if arg
        end
      end
    end
  end
end
