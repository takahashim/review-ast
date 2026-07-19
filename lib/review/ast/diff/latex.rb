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
      # Latex comparator: a coarse, text-level sieve.
      #
      # This does not decide LaTeX equivalence -- typesetting does. The parity
      # harness (tools/compare_book.rb) compiles both outputs and compares the
      # DVI, so this only has to be good enough to surface differences while
      # reading, which is why it can normalize as aggressively as it does (the
      # whitespace pass collapses space around every backslash, including
      # around a forced break).
      #
      # Blank lines, paragraph breaks and command spacing are always
      # normalized. Only whitespace collapsing is optional, because one test
      # compares a space-sensitive pair and has to see the difference.
      class Latex
        # @param ignore_whitespace [Boolean] Collapse whitespace before comparing
        def initialize(ignore_whitespace: true)
          @ignore_whitespace = ignore_whitespace
        end

        # Compare two LaTeX strings
        # @param left [String] First LaTeX content
        # @param right [String] Second LaTeX content
        # @return [Result] Comparison result
        def compare(left, right)
          normalized_left = normalize_latex(left)
          normalized_right = normalize_latex(right)

          # Generate line-by-line diff
          lines_left = normalized_left.split("\n")
          lines_right = normalized_right.split("\n")
          changes = ::Diff::LCS.sdiff(lines_left, lines_right)

          # For LaTeX, signatures are the normalized strings themselves
          Result.new(normalized_left, normalized_right, changes)
        end

        # Quick equality check
        # @param left [String] First LaTeX content
        # @param right [String] Second LaTeX content
        # @return [Boolean] true if contents are equivalent
        def equal?(left, right)
          compare(left, right).equal?
        end

        # Get pretty diff output
        # @param left [String] First LaTeX content
        # @param right [String] Second LaTeX content
        # @return [String] Formatted diff
        def diff(left, right)
          compare(left, right).pretty_diff
        end

        private

        # Normalize LaTeX string for comparison
        def normalize_latex(latex)
          return '' if latex.nil? || latex.empty?

          normalized = latex.dup

          # Collapse paragraph breaks, then drop the blank lines that leaves.
          normalized = normalized.gsub(/\n\n+/, "\n")
          normalized = normalized.split("\n").reject { |line| line.strip.empty? }.join("\n")

          if @ignore_whitespace
            # Normalize whitespace around commands
            normalized = normalized.gsub(/\s*\\\s*/, '\\')
            # Normalize multiple spaces
            normalized = normalized.gsub(/\s+/, ' ')
            # Remove leading/trailing whitespace from lines
            lines = normalized.split("\n")
            lines = lines.map(&:strip)
            normalized = lines.join("\n")
            # Remove leading/trailing whitespace
            normalized = normalized.strip
          end

          # Normalize command spacing
          normalized = normalized.gsub(/\\([a-zA-Z]+)\s*\{/, '\\\\\\1{')
          # Normalize environment spacing
          normalized = normalized.gsub(/\\(begin|end)\s*\{([^}]+)\}/, '\\\\\\1{\\2}')
          # Put each \begin{...}/\end{...} on its own line so the rendered diff
          # shows one environment per line
          normalized = normalized.gsub(/([^\n])\\begin\{/, "\\1\n\\\\begin{")
          normalized = normalized.gsub(/\\begin\{([^}]+)\}([^\n])/, "\\\\begin{\\1}\n\\2")
          normalized = normalized.gsub(/([^\n])\\end\{/, "\\1\n\\\\end{")
          normalized.gsub(/\\end\{([^}]+)\}([^\n])/, "\\\\end{\\1}\n\\2")
        end
      end
    end
  end
end
