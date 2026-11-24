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
      # Line comparator for the text formats (plaintext, TOP): the outputs are
      # equal when their non-blank lines are, leading tabs aside.
      #
      # The text renderers do not reproduce the builders' blank-line layout,
      # and keep the list nesting (as leading tabs) that the builders flatten
      # (test/ast/test_text_renderer_semantics.rb). The builders' <link href>
      # around a @<chapref> is not reproduced either (doc/spec-questions.md #8),
      # so it is dropped from the left (builder) side.
      class TextLines
        # @param left [String] builder output
        # @param right [String] renderer output
        # @return [Result]
        def compare(left, right)
          expected = lines(left.to_s.gsub(%r{<link href="[^"]*">(.*?)</link>}, '\\1'))
          actual = lines(right)
          Result.new(expected, actual, ::Diff::LCS.sdiff(expected, actual))
        end

        # @return [Boolean]
        def equal?(left, right)
          compare(left, right).equal?
        end

        private

        def lines(text)
          text.to_s.lines.map { |line| line.sub(/\A\t+/, '').chomp }.reject { |line| line.strip.empty? }
        end
      end
    end
  end
end
