# frozen_string_literal: true

# Monkey patches applied to the released `review` gem so that the AST
# subsystem can run without modifying Re:VIEW itself.
#
# These correspond to the only changes the AST branch makes to existing
# Re:VIEW files (34 lines total). All three are purely additive:
#   - ReVIEW::SnapshotLocation#to_h / #format_for_error
#   - ReVIEW::Book::Index::Item : caption_node support
#   - ReVIEW::Book::BookUnit#ast_indexes=
#
# If/when these hooks are upstreamed into Re:VIEW, this file can be made
# conditional (e.g. skip patching when the methods already exist).

require 'review/snapshot_location'
require 'review/book/index'
require 'review/book/book_unit'

# Re:VIEW's TextUtils references Unicode::Eaw for join_lines_by_lang but does
# not require it itself; ensure it is loaded when available. Mirrors Re:VIEW's
# own soft handling (join_lines_by_lang is disabled when the gem is absent).
begin
  require 'unicode/eaw'
rescue LoadError
  # join_lines_by_lang feature will be unavailable
end

module ReVIEW
  class SnapshotLocation
    unless method_defined?(:to_h)
      def to_h
        {
          filename: filename,
          lineno: lineno
        }
      end
    end

    unless method_defined?(:format_for_error)
      # Format location information for error messages
      # Returns a string like " at line 42 in chapter01.re"
      def format_for_error
        info = " at line #{@lineno}"
        info += " in #{@filename}" if @filename
        info
      end
    end
  end

  module Book
    class Index
      class Item
        unless method_defined?(:caption_node)
          attr_accessor :caption_node

          module ASTCaptionNode
            def initialize(id, number, caption = nil, caption_node: nil)
              super(id, number, caption)
              @caption_node = caption_node
            end
          end
          prepend ASTCaptionNode
        end
      end
    end

    class BookUnit
      unless method_defined?(:ast_indexes=)
        # Set indexes using AST-based indexing
        def ast_indexes=(indexes)
          @footnote_index = indexes[:footnote_index] if indexes[:footnote_index]
          @endnote_index = indexes[:endnote_index] if indexes[:endnote_index]
          @list_index = indexes[:list_index] if indexes[:list_index]
          @table_index = indexes[:table_index] if indexes[:table_index]
          @equation_index = indexes[:equation_index] if indexes[:equation_index]
          @image_index = indexes[:image_index] if indexes[:image_index]
          @icon_index = indexes[:icon_index] if indexes[:icon_index]
          @numberless_image_index = indexes[:numberless_image_index] if indexes[:numberless_image_index]
          @indepimage_index = indexes[:indepimage_index] if indexes[:indepimage_index]
          @headline_index = indexes[:headline_index] if indexes[:headline_index]
          @column_index = indexes[:column_index] if indexes[:column_index]
          @book.bibpaper_index = indexes[:bibpaper_index] if @book.present? && indexes[:bibpaper_index]
        end
      end
    end
  end
end
