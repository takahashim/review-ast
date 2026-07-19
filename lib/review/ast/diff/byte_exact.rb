# frozen_string_literal: true

require 'diff/lcs'
require_relative 'result'

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    module Diff
      # ByteExact comparator: two outputs are equal iff they are byte-for-byte
      # identical.
      #
      # This is the right criterion for IDGXML (InDesign XML): unlike HTML, there
      # is no CSS white-space collapsing model and InDesign imports text
      # literally, so every space/newline is significant. The builder's IDGXML is
      # also compact (no pretty-printing / indentation, stable attribute order),
      # so there is essentially no insignificant formatting to normalize away --
      # a byte difference is a real difference.
      #
      # Equality is exact string equality; the diff is rendered at tag granularity
      # (split after each '>') only for human-readable output.
      class ByteExact
        # @param left [String]
        # @param right [String]
        # @return [Result]
        def compare(left, right)
          changes = ::Diff::LCS.sdiff(tokenize(left), tokenize(right))
          # Signatures are the raw strings, so Result#equal? is exact equality.
          Result.new(left, right, changes)
        end

        # @return [Boolean]
        def equal?(left, right)
          left == right
        end

        # @return [String]
        def diff(left, right)
          compare(left, right).pretty_diff
        end

        private

        # Split into tag-sized tokens for a readable diff (does not affect
        # equality, which is byte-exact on the raw strings).
        def tokenize(str)
          str.to_s.scan(/[^>]*>|[^>]+\z/)
        end
      end
    end
  end
end
