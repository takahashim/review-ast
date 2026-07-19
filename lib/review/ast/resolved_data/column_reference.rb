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
      class ColumnReference < CaptionedItemReference
        def reference_type
          :column
        end
      end
    end
  end
end
