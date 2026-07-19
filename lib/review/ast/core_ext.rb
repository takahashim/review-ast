# frozen_string_literal: true

# Monkey patches applied to the released `review` gem so that the AST
# subsystem can run without modifying Re:VIEW itself.
#
# One purely-additive hook remains, existing only so the AST can install its
# own computed indexes onto legacy Re:VIEW objects (see doc/design-improvements
# #7):
#   - ReVIEW::Book::BookUnit#ast_indexes=
#
# The former Index::Item#caption_node patch was retired: caption nodes now live
# in the AST-owned ChapterIndexRegistry (chapter_index_registry.rb) that the
# reference resolver reads, so the legacy index items no longer need to carry
# them. The former SnapshotLocation#to_h / #format_for_error patch was likewise
# retired once the AST gained its own location type (ReVIEW::AST::SourceLocation).
#
# If/when these hooks are upstreamed into Re:VIEW, this file can be made
# conditional (e.g. skip patching when the methods already exist).

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
  module Book
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
