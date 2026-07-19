# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/book/image_finder'
require_relative 'post_processor'
require_relative '../image_node'
require_relative '../table_node'
require_relative '../inline_node'

module ReVIEW
  module AST
    class Compiler
      # ImagePathProcessor - resolve image file paths at compile time.
      #
      # Walks the whole tree (children AND caption nodes) and stamps the resolved
      # filesystem path on every image-bearing node: ImageNode, the //imgtable
      # TableNode, and the @<icon> InlineNode. The path comes from
      # ReVIEW::Book::ImageFinder, which searches <imagedir>/<builder>/... on
      # disk -- the one legitimate environment lookup -- so its result becomes a
      # source-derived fact the renderers read off the node (node.image_path),
      # needing no chapter image index (doc/design-improvements #7). Icons in
      # captions of id-less blocks (e.g. //emlist) are exactly why this walks the
      # full tree (Node#each_subnode, which includes captions and terms) rather
      # than relying on the Indexer's id-gated caption visits.
      class ImagePathProcessor < PostProcessor
        def process(ast_root)
          @finder = ReVIEW::Book::ImageFinder.new(@chapter) if @chapter&.book
          return ast_root unless @finder

          walk(ast_root)
          ast_root
        end

        private

        def walk(node)
          stamp(node)
          node.each_subnode { |child| walk(child) }
        end

        def stamp(node)
          case node
          when ImageNode
            node.image_path = @finder.find_path(node.id) if node.id?
          when TableNode
            node.image_path = @finder.find_path(node.id) if node.table_type == :imgtable && node.id?
          when InlineNode
            if node.inline_type == :icon && node.args.first
              node.image_path = @finder.find_path(node.args.first)
            end
          end
        end
      end
    end
  end
end
