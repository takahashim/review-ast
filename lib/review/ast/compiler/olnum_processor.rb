# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/list_node'
require 'review/ast/list_item_node'
require_relative 'directive_lowering_pass'

module ReVIEW
  module AST
    class Compiler
      # OlnumProcessor - lowers //olnum onto the next ordered list (setting its
      # start number), then records olnum_start for every ordered list.
      #
      # This is a superset of the plain directive lowering: after the shared
      # lowering pass it runs a second pass that marks each ordered list with the
      # start value InDesign's olnum needs (its explicit //olnum value, or the
      # list's own start when the item numbers run consecutively, else 1).
      class OlnumProcessor < DirectiveLoweringPass
        def process(ast_root)
          super # shared lowering: fold //olnum onto the next ordered list
          add_olnum_starts(ast_root)
          ast_root
        end

        private

        def directive_type
          :olnum
        end

        def target?(node)
          ordered_list_node?(node)
        end

        def apply(target, directive)
          value = (directive.args.first || 1).to_i
          target.start_number = value
          # Mark this list as explicitly set by //olnum.
          target.olnum_start = value
        end

        # Set olnum_start for lists without an explicit //olnum.
        def add_olnum_starts(node)
          # IDGXMLBuilder keeps olnum as a plain 1-based counter over the list
          # (ol_begin does `@ol_num ||= 1`, ol_item increments it), and only
          # //olnum[N] presets it -- which the directive pass has already
          # recorded when olnum_start is non-nil. The numbers written in the
          # source affect the num attribute, never olnum.
          #
          # This used to start olnum at the source's first number whenever the
          # items ran consecutively, so a list written "3. / 4." emitted
          # olnum="3" where the builder emits olnum="1".
          node.olnum_start = 1 if ordered_list_node?(node) && node.olnum_start.nil?

          node.children.each { |child| add_olnum_starts(child) }
        end

        def ordered_list_node?(node)
          node.is_a?(ListNode) && node.ol?
        end
      end
    end
  end
end
