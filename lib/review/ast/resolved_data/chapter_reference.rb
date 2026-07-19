# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    class ResolvedData
      # ChapterReference - represents chapter references (@<chap>, @<chapref>, @<title>)
      class ChapterReference < ResolvedData
        fields :chapter_number, :chapter_id, :item_id, :chapter_title,
               chapter_type: :symbol, caption_node: :node

        def initialize(chapter_number:, chapter_id:, item_id:, chapter_title: nil, caption_node: nil, chapter_type: nil)
          super()
          @chapter_number = chapter_number
          @chapter_id = chapter_id
          @item_id = item_id
          @chapter_title = chapter_title
          @caption_node = caption_node
          @chapter_type = chapter_type
        end

        def reference_type
          :chapter
        end
      end
    end
  end
end
