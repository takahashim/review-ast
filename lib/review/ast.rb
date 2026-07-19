# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

# Re:VIEW's TextUtils references Unicode::Eaw for join_lines_by_lang but does
# not require it itself; ensure it is loaded when available. Mirrors Re:VIEW's
# own soft handling (join_lines_by_lang is disabled when the gem is absent).
begin
  require 'unicode/eaw'
rescue LoadError
  # join_lines_by_lang feature will be unavailable
end

# AST Node classes
require 'review/ast/node'
require 'review/ast/document_node'
require 'review/ast/headline_node'
require 'review/ast/paragraph_node'
require 'review/ast/list_node'
require 'review/ast/table_node'
require 'review/ast/table_row_node'
require 'review/ast/table_cell_node'
require 'review/ast/image_node'
require 'review/ast/code_block_node'
require 'review/ast/code_line_node'
require 'review/ast/inline_node'
require 'review/ast/text_node'
require 'review/ast/embed_node'
require 'review/ast/block_node'
require 'review/ast/column_node'
require 'review/ast/minicolumn_node'
require 'review/ast/caption_node'
require 'review/ast/tex_equation_node'

# AST Processing classes
require 'review/ast/compiler'
require 'review/ast/block_processor'
require 'review/ast/inline_processor'

# AST Utility classes
require 'review/ast/exception'
require 'review/ast/json_serializer'
require 'review/ast/list_processor'
require 'review/ast/list_parser'
require 'review/ast/review_generator'

module ReVIEW
  module AST
    # AST module namespace for all AST-related functionality
  end
end
