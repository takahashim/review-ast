# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'captioned_item_reference'

module ReVIEW
  module AST
    class ResolvedData
      class EquationReference < CaptionedItemReference
        # Equation has no chapter_id, so it narrows the inherited constructor.
        # The inherited field declaration still applies; chapter_id stays nil and
        # is therefore omitted from the dump.
        def initialize(chapter_number:, item_number:, item_id:, chapter_type: nil, caption_node: nil)
          super(chapter_number: chapter_number,
                item_number: item_number,
                item_id: item_id,
                chapter_id: nil,
                chapter_type: chapter_type,
                caption_node: caption_node)
        end

        def reference_type
          :equation
        end
      end
    end
  end
end
