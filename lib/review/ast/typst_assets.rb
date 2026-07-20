# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # Locations of the Typst assets review-ast ships for TypstMaker.
    #
    # The book library is copied into the build directory rather than resolved
    # as a Typst package: that keeps it working without a package cache or
    # network, and lets the library and TypstRenderer move together in one gem
    # (doc/design-typst.md). Publishing to Typst Universe is a
    # later phase, at which point the copy becomes a package import.
    module TypstAssets
      # <repo>/templates/typst (this file is at lib/review/ast).
      DIR = File.expand_path('../../../templates/typst', __dir__)

      # The book library, copied to <build>/lib/review-book.
      LIBRARY = File.join(DIR, 'review-book')

      # Directory name the library is copied to, relative to the build root.
      LIBRARY_DIR = 'lib/review-book'

      # ERB for the root file that switches book parts and includes chapters.
      ROOT_TEMPLATE = File.join(DIR, 'book.typ.erb')

      # Math adapters. The default renders LaTeX source verbatim and always
      # compiles; the mitex one needs @preview/mitex in the package cache.
      MATH_DEFAULT = File.join(DIR, 'review-book', 'math.typ')
      MATH_MITEX = File.join(DIR, 'review-book', 'math-mitex.typ')
    end
  end
end
