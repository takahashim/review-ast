# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'

module ReVIEW
  module AST
    # The single place that turns a (chapter number, chapter type) pair into the
    # display strings Re:VIEW uses for chapter numbers. It replaces the two copies
    # that had drifted apart: the compile-side Indexer (stamping a definition's
    # chapter prefix) and the render-side TextFormatter (formatting @<chap>/@<hd>
    # references). Both now delegate here, so classification (RenderContext) and
    # formatting each live in one home (doc/design-improvements #8, 手順4).
    #
    # It lives on the AST side because the compile-side Indexer must reach it; the
    # render-side TextFormatter depending on the AST side is the correct direction
    # (renderer -> AST), not a back-reference. I18n is a reused service.
    module ChapterNumberFormatter
      module_function

      # Long form, e.g. "第1章" / "Appendix A" / "Part I". Used by @<chap>,
      # @<chapref>, @<title>.
      def full(raw_number, chapter_type)
        return '' unless raw_number

        case chapter_type
        when :chapter
          ReVIEW::I18n.t('chapter', raw_number)
        when :appendix
          ReVIEW::I18n.t('appendix', raw_number)
        when :part
          ReVIEW::I18n.t('part', raw_number)
        else # :predef and others
          raw_number.to_s
        end
      end

      # Short form, e.g. "1" / "A" / "I". Used where the format is "図2.1" (not
      # "図第2章.1"). Matches Chapter#format_number(false).
      def short(raw_number, chapter_type)
        return '' unless raw_number

        case chapter_type
        when :appendix
          # Extract the format from the 'appendix' I18n key and build
          # 'appendix_without_heading', replicating Chapter#format_number(false).
          i18n_appendix = ReVIEW::I18n.get('appendix')
          fmt = i18n_appendix.scan(/%\w{1,3}/).first || '%s'
          ReVIEW::I18n.update('appendix_without_heading' => fmt)
          ReVIEW::I18n.t('appendix_without_heading', raw_number)
        else # :chapter, :part, :predef
          raw_number.to_s
        end
      end

      # The prefix stamped onto a numbered definition's caption (e.g. the "2" in
      # "図2.1"). Same as #short except a Part uses its part_short label, matching
      # the Indexer's historical definition_chapter_number.
      def definition_prefix(raw_number, chapter_type)
        return '' unless raw_number

        if chapter_type == :part
          ReVIEW::I18n.t('part_short', raw_number)
        else
          short(raw_number, chapter_type)
        end
      end
    end
  end
end
