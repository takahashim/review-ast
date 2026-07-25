# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    module Typst
      # Generated Typst source: an expression the document is meant to
      # evaluate, not text it should display. Never escaped, which is why it
      # is a type of its own rather than another String -- the distinction
      # from Text is the whole point (doc/design-typst.md).
      class Code
        def initialize(source)
          @source = source.to_s
        end

        def to_s
          @source
        end
      end
    end
  end
end
