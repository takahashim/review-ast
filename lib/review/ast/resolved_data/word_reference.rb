# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    class ResolvedData
      class WordReference < ResolvedData
        fields :item_id, :word_content, caption_node: :node

        def initialize(item_id:, word_content:, caption_node: nil)
          super()
          @item_id = item_id
          @word_content = word_content
          @caption_node = caption_node
        end

        def reference_type
          :word
        end
      end
    end
  end
end
