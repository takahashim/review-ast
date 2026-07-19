# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/table_node'
require_relative 'directive_lowering_pass'

module ReVIEW
  module AST
    class Compiler
      # TsizeProcessor - lowers //tsize onto the next TableNode.
      #
      # Attaches the raw //tsize argument to the table as a source fact
      # (target-neutral). Resolving the builder target and deriving the column
      # specification happen at render time, so the shared tree does not depend
      # on which builder it was compiled for. See doc/design-improvements #5.
      class TsizeProcessor < DirectiveLoweringPass
        private

        def directive_type
          :tsize
        end

        def target?(node)
          node.is_a?(TableNode)
        end

        def apply(target, directive)
          raw = directive.args.first
          target.tsize = raw if raw
        end
      end
    end
  end
end
