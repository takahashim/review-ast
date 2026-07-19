# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require 'review/ast/chapter_number_formatter'
require_relative 'section_numbering'

module ReVIEW
  module Renderer
    # TextFormatter - Centralized text formatting and I18n service
    #
    # This class consolidates all text formatting and internationalization logic
    # that was previously scattered across Renderer, InlineElementHandler, Formatter,
    # and ResolvedData classes.
    #
    # Design principles:
    # - Single responsibility: All I18n and text generation in one place
    # - Format-agnostic core with format-specific decorations
    # - Reusable from Renderer, InlineElementHandler, and ResolvedData
    class TextFormatter
      include ReVIEW::Renderer::SectionNumbering

      attr_reader :config

      # Initialize formatter
      # @param config [Hash] Configuration hash
      def initialize(config:)
        @config = config
      end

      # Format a numbered item's caption for HTML/LaTeX (e.g., "図1.1: キャプション")
      # Uses format_number_header (with colon) + caption_prefix
      # @param label_key [String] I18n key for the label (e.g., 'image', 'table', 'list')
      # @param chapter_number [String, nil] Chapter number (e.g., "第1章")
      # @param item_number [Integer] Item number within chapter
      # @param caption_text [String, nil] Caption text
      # @return [String] Formatted caption
      def format_caption(label_key, chapter_number, item_number, caption_text = nil)
        label = I18n.t(label_key)
        number_text = format_number_header(chapter_number, item_number)
        separator = I18n.t('caption_prefix')

        base = "#{label}#{number_text}"
        return base if caption_text.nil? || caption_text.empty?

        "#{base}#{separator}#{caption_text}"
      end

      # Format a numbered item's caption for IDGXML/TOP/TEXT (e.g., "図1.1 キャプション")
      # Uses format_number (without colon) + caption_separator
      # @param label_key [String] I18n key for the label (e.g., 'image', 'table', 'list')
      # @param chapter_number [String, nil] Chapter number (e.g., "第1章")
      # @param item_number [Integer] Item number within chapter
      # @param caption_text [String, nil] Caption text
      # @return [String] Formatted caption
      def format_caption_plain(label_key, chapter_number, item_number, caption_text = nil)
        label = I18n.t(label_key)
        number_text = format_number(chapter_number, item_number)
        separator = caption_separator

        base = "#{label}#{number_text}"
        return base if caption_text.nil? || caption_text.empty?

        "#{base}#{separator}#{caption_text}"
      end

      # Format just the number part (e.g., "1.1" or "1")
      # @param chapter_number [String, nil] Chapter number
      # @param item_number [Integer] Item number
      # @return [String] Formatted number
      def format_number(chapter_number, item_number)
        if chapter_number && !chapter_number.to_s.empty?
          I18n.t('format_number', [chapter_number, item_number])
        else
          I18n.t('format_number_without_chapter', [item_number])
        end
      end

      # Format number for caption header (HTML/LaTeX style)
      # Used in block elements (//image, //table, //list, //equation) caption headers
      # @param chapter_number [String, nil] Chapter number
      # @param item_number [Integer] Item number
      # @return [String] Formatted number for header
      def format_number_header(chapter_number, item_number)
        if chapter_number && !chapter_number.to_s.empty?
          I18n.t('format_number_header', [chapter_number, item_number])
        else
          I18n.t('format_number_header_without_chapter', [item_number])
        end
      end

      # Format a reference to an item (with format-specific decorations)
      # Used by LaTeX, IDGXML, TOP, and TEXT renderers
      # @param type [Symbol] Reference type (:image, :table, :list, :equation, etc.)
      # @param data [ResolvedData] Resolved reference data
      # @return [String] Formatted reference
      def format_reference(type, data)
        case type
        when :image
          format_image_reference(data)
        when :table
          format_table_reference(data)
        when :list
          format_list_reference(data)
        when :equation
          format_equation_reference(data)
        when :footnote
          format_footnote_reference(data)
        when :endnote
          format_endnote_reference(data)
        when :chapter
          format_chapter_reference(data)
        when :headline
          format_headline_reference(data)
        when :column
          format_column_reference(data)
        when :bibpaper
          format_bibpaper_reference(data)
        when :word
          format_word_reference(data)
        else
          raise ArgumentError, "Unknown reference type: #{type}"
        end
      end

      # Format chapter number with I18n (long form, e.g., "第1章", "Appendix A", "Part I")
      # Used for @<chap>, @<chapref>, @<title> references
      # @param raw_number [Integer, nil] Raw chapter number from chapter.number
      # @param chapter_type [Symbol, nil] Chapter type (:chapter, :appendix, :part, :predef)
      # @return [String] Formatted chapter number
      def format_chapter_number_full(raw_number, chapter_type)
        ReVIEW::AST::ChapterNumberFormatter.full(raw_number, chapter_type)
      end

      # Format chapter number without heading (short form, e.g., "1", "A", "I")
      # Used for figure/table/list references where format is "図2.1" not "図第2章.1"
      # Matches Chapter#format_number(false) behavior
      # @param raw_number [Integer, nil] Raw chapter number from chapter.number
      # @param chapter_type [Symbol, nil] Chapter type (:chapter, :appendix, :part, :predef)
      # @return [String] Short form chapter number
      def format_chapter_number_short(raw_number, chapter_type)
        ReVIEW::AST::ChapterNumberFormatter.short(raw_number, chapter_type)
      end

      # Prefix/postfix wrapping a ruby reading in HTML output.
      def ruby_prefix
        I18n.t('ruby_prefix')
      end

      def ruby_postfix
        I18n.t('ruby_postfix')
      end

      # Format footnote reference mark
      # @param number [Integer] Footnote number
      # @return [String] Formatted footnote mark
      def format_footnote_mark(number)
        I18n.t('html_footnote_refmark', number)
      end

      # Format endnote reference mark
      # @param number [Integer] Endnote number
      # @return [String] Formatted endnote mark
      def format_endnote_mark(number)
        I18n.t('html_endnote_refmark', number)
      end

      # Format footnote text mark (used in footnote body)
      # @param number [Integer] Footnote number
      # @return [String] Formatted footnote text mark
      def format_footnote_textmark(number)
        I18n.t('html_footnote_textmark', number)
      end

      # Format endnote text mark (used in endnote body)
      # @param number [Integer] Endnote number
      # @return [String] Formatted endnote text mark
      def format_endnote_textmark(number)
        I18n.t('html_endnote_textmark', number)
      end

      # Format footnote back mark (back link)
      # @return [String] Formatted footnote back mark
      def format_footnote_backmark
        I18n.t('html_footnote_backmark')
      end

      # Format numberless image label
      # @return [String] Numberless image label
      def format_numberless_image
        I18n.t('numberless_image')
      end

      # Format caption prefix
      # @return [String] Caption prefix string
      def format_caption_prefix
        prefix = I18n.t('caption_prefix')
        prefix == 'caption_prefix' ? ' ' : prefix
      end

      # Format column reference from ResolvedData
      # @param data [ResolvedData] Resolved column reference data
      # @return [String] Formatted column reference
      def format_column_reference(data)
        # caption_text is always plain text from caption_node.to_inline_text
        I18n.t('column', data.caption_text)
      end

      # Format column label with I18n
      # Takes already-rendered caption (in target format)
      # Used by InlineElementHandlers for format-specific rendering
      # @param caption [String] Already rendered caption
      # @return [String] Formatted column label
      def format_column_label(caption)
        I18n.t('column', caption)
      end

      # Format label marker for labelref/ref inline elements
      # @param idref [String] Reference ID
      # @return [String] Formatted label marker
      def format_label_marker(idref)
        I18n.t('label_marker') + idref.to_s
      end

      # Format headline quote
      # @param full_number [String, nil] Full section number (e.g., "1.2.3")
      # @param caption_text [String] Caption text (already rendered in target format)
      # @return [String] Formatted headline quote
      def format_headline_quote(full_number, caption_text)
        if full_number
          I18n.t('hd_quote', [full_number, caption_text])
        else
          I18n.t('hd_quote_without_number', caption_text)
        end
      end

      # Format image quote (IDGXML specific)
      # @param caption_text [String] Caption text
      # @return [String] Formatted image quote
      def format_image_quote(caption_text)
        I18n.t('image_quote', caption_text)
      end

      private

      # Format numbered reference (image, table, list) using common logic
      # @param label_key [String] I18n key for the label (e.g., 'image', 'table', 'list')
      # @param data [ResolvedData] Resolved reference data
      # @param html_css_class [String] CSS class for HTML output (unused, kept for compatibility)
      # @return [String] Formatted reference without caption (e.g., "図1.1")
      def format_numbered_reference(label_key, data)
        # Use short form of chapter number for figure/table/list references
        chapter_number_short = format_chapter_number_short(data.chapter_number, data.chapter_type)

        format_caption_plain(label_key, chapter_number_short, data.item_number, nil)
      end

      # Format image reference
      def format_image_reference(data)
        format_numbered_reference('image', data)
      end

      # Format table reference
      def format_table_reference(data)
        format_numbered_reference('table', data)
      end

      # Format list reference
      def format_list_reference(data)
        format_numbered_reference('list', data)
      end

      # Format equation reference
      # @param data [ResolvedData] Resolved reference data
      # @return [String] Formatted reference without caption (e.g., "式3.1")
      def format_equation_reference(data)
        # Use short form of chapter number for equation references
        chapter_number_short = format_chapter_number_short(data.chapter_number, data.chapter_type)

        # Return reference without caption text
        format_caption_plain('equation', chapter_number_short, data.item_number)
      end

      # Format footnote reference
      def format_footnote_reference(data)
        # For all formats - return plain number without markup
        data.item_number.to_s
      end

      # Format endnote reference
      def format_endnote_reference(data)
        # For all formats - return plain number without markup
        data.item_number.to_s
      end

      # Format chapter reference
      def format_chapter_reference(data)
        chapter_title = data.chapter_title

        # Use full form of chapter number for chapter references
        chapter_number_full = format_chapter_number_full(data.chapter_number, data.chapter_type)

        if chapter_title && !chapter_number_full.empty?
          I18n.t('chapter_quote', [chapter_number_full, chapter_title])
        elsif chapter_title
          I18n.t('chapter_quote_without_number', chapter_title)
        elsif !chapter_number_full.empty?
          chapter_number_full
        else
          data.item_id || ''
        end
      end

      # Format headline reference
      def format_headline_reference(data)
        caption = data.caption_text
        headline_numbers = Array(data.headline_number).compact

        # The builders drop the number for a heading deeper than secnolevel
        # (inline_hd_chap picks hd_quote_without_number); this showed it at any
        # depth, so IDGXML printed "「1.1.1.1 段」" where the builder prints
        # "「段」". HTML was unaffected -- its handler makes the same check
        # itself before asking for the text.
        if !headline_numbers.empty? && over_secnolevel?(headline_numbers)
          # Use short form of chapter number for headline references
          chapter_number_short = format_chapter_number_short(data.chapter_number, data.chapter_type)

          # Build full number with chapter number if available
          number_str = if chapter_number_short.empty?
                         headline_numbers.join('.')
                       else
                         ([chapter_number_short] + headline_numbers).join('.')
                       end
          I18n.t('hd_quote', [number_str, caption])
        elsif !caption.empty?
          I18n.t('hd_quote_without_number', caption)
        else
          data.item_id || ''
        end
      end

      # Format bibpaper reference
      def format_bibpaper_reference(data)
        # For all formats - return plain reference without markup
        "[#{data.item_number}]"
      end

      # Format word reference
      def format_word_reference(data)
        data.word_content.to_s
      end

      # Get caption separator
      def caption_separator
        separator = I18n.t('caption_prefix_idgxml')
        if separator == 'caption_prefix_idgxml'
          # Fallback to regular caption prefix
          fallback = I18n.t('caption_prefix')
          fallback == 'caption_prefix' ? ' ' : fallback
        else
          separator
        end
      end

      # Check if string is numeric
    end
  end
end
