# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    module Typst
      # Paths as the generated Typst has to state them.
      #
      # A relative path in Typst resolves against the file it appears in, so an
      # image path that works from a chapter file breaks when the same string is
      # used inside the library. Every path is therefore emitted absolute from
      # the Typst project root, which TypstMaker fixes to the build directory
      # (doc/design-typst.md, BuildLayout).
      module BuildPaths
        # @param path [String] Path relative to the book's base directory
        # @return [String] Path from the Typst project root
        def build_relative_image_path(path)
          normalized = path.to_s.sub(%r{\A\./}, '')
          normalized.start_with?('/') ? normalized : "/#{normalized}"
        end
      end
    end
  end
end
