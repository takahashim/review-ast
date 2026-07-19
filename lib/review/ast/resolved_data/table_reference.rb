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
      class TableReference < CaptionedItemReference
        def reference_type
          :table
        end
      end
    end
  end
end
