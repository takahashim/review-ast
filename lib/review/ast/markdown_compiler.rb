# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'red_quilt'
require_relative 'compiler'
require_relative 'markdown_adapter'

module ReVIEW
  module AST
    # Compiler for Markdown chapters (.md), producing the same AST as the
    # Re:VIEW compiler does for .re.
    #
    # Only the surface tree is built differently: red_quilt parses the Markdown
    # and MarkdownAdapter converts its tree into Re:VIEW AST nodes. Everything
    # after that -- directive lowering (a no-op here, since Markdown produces no
    # DirectiveNode), list numbering, auto ids, definition numbers, the chapter
    # index registry and image path resolution -- comes from the parent, so a
    # Markdown chapter satisfies the same core tree contract as a Re:VIEW one
    # (doc/ast-semantics 2.1).
    class MarkdownCompiler < Compiler
      # GFM features red_quilt does not enable by default. Tables,
      # strikethrough and HTML blocks are on already.
      PARSE_OPTIONS = { footnotes: true, extended_autolinks: true }.freeze

      def initialize
        super
        @adapter = MarkdownAdapter.new(self)
      end

      private

      # Build the surface tree from Markdown. Called by Compiler#compile_to_ast,
      # which owns the phases around it.
      def build_ast_from_chapter
        # red_quilt reads "@<img>" as an HTML tag and splits it across nodes, so
        # the notation is hidden behind a placeholder for the duration of the
        # parse and restored by the adapter. The placeholder passes through
        # untouched while Markdown's own inline structure is preserved.
        source = @input.source.gsub('@<', MarkdownAdapter::REVIEW_NOTATION_PLACEHOLDER)

        document = RedQuilt.parse(source, **PARSE_OPTIONS)
        @adapter.convert(document.root, @ast_root, @input)
      end
    end
  end
end
