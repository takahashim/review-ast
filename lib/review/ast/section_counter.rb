# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'delegate'
require 'review/sec_counter'
require_relative 'chapter_number_formatter'
require_relative 'render_context'

module ReVIEW
  module AST
    # The legacy SecCounter, numbering from the AST's chapter type.
    #
    # SecCounter builds heading numbers from Chapter#format_number, which
    # decides appendix-ness with Chapter#on_appendix? -- and that only matches
    # catalog entries ending in the book's ext (".re"), so a Markdown appendix
    # (appA.md) was numbered "第1章". This hands SecCounter a view of the
    # chapter whose format_number follows RenderContext.chapter_type instead.
    # A Part is passed through unchanged: SecCounter tells parts apart with
    # is_a?, which a delegator would hide.
    class SectionCounter < ReVIEW::SecCounter
      # A chapter whose format_number uses the AST's chapter type.
      class ChapterView < SimpleDelegator
        def initialize(chapter)
          super
          @chapter_type = RenderContext.chapter_type(chapter)
        end

        def format_number(heading = true)
          number = __getobj__.number
          heading ? ChapterNumberFormatter.full(number, @chapter_type) : ChapterNumberFormatter.short(number, @chapter_type)
        end
      end

      def initialize(n, chapter)
        super(n, chapter.is_a?(ReVIEW::Book::Part) ? chapter : ChapterView.new(chapter))
      end
    end
  end
end
