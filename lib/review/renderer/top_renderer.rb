# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/textutils'
require 'review/loggable'
require 'review/i18n'
require_relative 'text_renderer_common'
require_relative 'base'

module ReVIEW
  module Renderer
    class TopRenderer < Base
      include ReVIEW::TextUtils
      include ReVIEW::Loggable
      include ReVIEW::Renderer::TextRendererCommon

      # Japanese titles for different block types (matching TOPBuilder)
      # TOPBuilder's @titles, kept in the same order. These are the markers a
      # DTP operator reads, so a wrong one is a wrong instruction, not a
      # cosmetic difference: notice/caution/warning were each shifted by one
      # (注意/警告/危険 rendered as 注記/注意/警告), and twenty commands had no
      # entry at all and fell back to their command name.
      TITLES = {
        emlist: 'インラインリスト',
        # listnum/emlistnum reuse the plain list titles; TOPBuilder has no
        # separate entry for the numbered variants.
        emlistnum: 'インラインリスト',
        cmd: 'コマンド',
        quote: '引用',
        centering: '中央揃え',
        flushright: '右寄せ',
        note: 'ノート',
        memo: 'メモ',
        important: '重要',
        info: '情報',
        planning: 'プランニング',
        shoot: 'トラブルシュート',
        term: '用語解説',
        notice: '注意',
        caution: '警告',
        warning: '危険',
        point: 'ここがポイント',
        reference: '参考',
        link: 'リンク',
        best: 'ベストプラクティス',
        practice: '練習問題',
        security: 'セキュリティ',
        expert: 'エキスパートに訊け',
        tip: 'TIP',
        box: '書式',
        insn: '書式',
        column: 'コラム',
        xcolumn: 'コラムパターン2',
        world: 'Worldコラム',
        hood: 'Under The Hoodコラム',
        edition: 'Editionコラム',
        insideout: 'InSideOutコラム',
        ref: '参照',
        sup: '補足',
        read: 'リード',
        lead: 'リード',
        list: 'リスト',
        listnum: 'リスト',
        image: '図',
        texequation: 'TeX式',
        table: '表',
        bpo: 'bpo',
        source: 'ソースコードリスト',
        # Not in @titles: these come from other IDGXML/TOP paths but the
        # renderer dispatches block titles through this table.
        emtable: 'インライン表',
        imgtable: '画像付き表',
        indepimage: '独立図',
        numberlessimage: '番号なし図',
        icon: 'アイコン'
      }.freeze

      # Configure's default, used when the book config does not set one.
      DEFAULT_SECNOLEVEL = 2

      def initialize(chapter)
        super
        @table_row_separator_count = 0
        # Loggable#warn goes through this; without it, warning about an unbound
        # image would raise instead of reporting.
        @logger = ReVIEW.logger
        # Section numbering, as in the legacy builders (LaTeX/HTML/IDGXML
        # renderers already do this; text did not, so section numbers were
        # missing from its output entirely).
        @sec_counter = SecCounter.new(5, @chapter) if @chapter
      end

      # Format type for this renderer
      # @return [Symbol] Format type :top
      def format_type
        :top
      end

      def target_name
        'top'
      end

      def visit_headline(node)
        # TOPBuilder has no nodisp_begin, so it inherits PLAINTEXTBuilder's,
        # which prints nothing at all.
        return '' if node.nodisp?

        level = node.level
        caption = render_caption_inline(node.caption_node)

        # [nonum]/[notoc] headings print the bare title: TOPBuilder routes them
        # to nonum_begin/notoc_begin, which never call headline_prefix, so they
        # are unnumbered *and* leave the section counter untouched. notoc also
        # carries a note for the DTP operator.
        if node.notoc?
          return "■H#{level}■#{caption}◆→DTP連絡:目次に掲載しない←◆\n"
        end
        return "■H#{level}■#{caption}\n" if node.nonum?

        "■H#{level}■#{generate_headline_prefix(level)}#{caption}\n"
      end

      def visit_paragraph(node)
        content = render_children(node).chomp
        return '' if content.empty?

        "#{content}\n"
      end

      def visit_list(node)
        result = +''

        case node.list_type
        when :ul
          node.children.each do |item|
            result += visit_unordered_list_item(item)
          end
        when :ol
          node.children.each_with_index do |item, index|
            result += visit_ordered_list_item(item, index + 1)
          end
        when :dl
          node.children.each do |item|
            result += visit_definition_item(item)
          end
        end

        result
      end

      def visit_unordered_list_item(node)
        # Separate text content from nested lists
        text_content = +''
        nested_lists = +''

        node.children.each do |child|
          if child.class.name.include?('ListNode')
            # This is a nested list - render it separately
            nested_lists += visit(child)
          else
            # This is regular content
            text_content += visit(child)
          end
        end

        text_content = text_content.chomp

        # Use level for nested indentation (TOP style uses tabs for each level)
        level = node.level || 1
        indent = "\t" * (level - 1)

        result = "#{indent}●\t#{text_content}\n"

        # Add any nested lists after the item
        result += nested_lists
        result
      end

      def visit_ordered_list_item(node, number)
        # Separate text content from nested lists
        text_content = +''
        nested_lists = +''

        node.children.each do |child|
          if child.class.name.include?('ListNode')
            # This is a nested list - render it separately
            nested_lists += visit(child)
          else
            # This is regular content
            text_content += visit(child)
          end
        end

        text_content = text_content.chomp

        # Use level for nested indentation
        level = node.level || 1
        indent = "\t" * (level - 1)

        result = "#{indent}#{number}\t#{text_content}\n"

        # Add any nested lists after the item
        result += nested_lists
        result
      end

      def visit_item(node)
        # Handle list items that come directly without parent list context
        content = render_children(node).chomp
        "●\t#{content}\n"
      end

      def visit_definition_item(node)
        # Handle definition term - use term_children (AST structure)
        term = if node.term_children && !node.term_children.empty?
                 node.term_children.map { |child| visit(child) }.join
               else
                 '' # No term available
               end

        # Handle definition content (all children are definition content)
        definition = if node.children && !node.children.empty?
                       node.children.map { |child| visit(child) }.join
                     end

        # TOPBuilder#dt brackets the term on both sides ("★#{line}☆"); the
        # opening marker was missing here.
        result = "★#{term}☆\n"
        result += "\t#{definition}\n" if definition

        result
      end

      # Common code block rendering method used by all code block types
      def render_code_block_common(node)
        result = +''
        # Convert code_type to symbol if it's not already
        code_type = node.code_type.to_sym
        block_title = TITLES[code_type] || TITLES[:list]

        result += "\n"
        result += "◆→開始:#{block_title}←◆\n"

        # Add caption if present
        caption = render_caption_inline(node.caption_node)
        unless caption.empty?
          result += if node.id && (code_type == :list || code_type == :listnum)
                      # For list/listnum, use I18n formatting to match TOPBuilder
                      format_list_caption(node.id, caption, node.definition_number)
                    elsif node.id
                      "■#{node.id}■#{caption}\n"
                    else
                      "■#{caption}\n"
                    end
          result += "\n"
        end

        # Add line numbers if needed
        if node.line_numbers
          code_content = render_children(node).chomp
          lines = code_content.split("\n")
          # //firstlinenum sets where the numbering starts (Builder#line_num);
          # this used to be hardcoded to 1, so TOP silently ignored the directive.
          first_line_number = node.first_line_num || 1
          lines.each_with_index do |line, i|
            line_num = (first_line_number + i).to_s.rjust(2)
            result += "#{line_num}: #{line}\n"
          end
        else
          code_content = render_children(node)
          # Remove trailing newline if present to avoid double newlines
          code_content = code_content.chomp if code_content.end_with?("\n")
          result += code_content
          result += "\n"
        end

        result += "\n"
        result += "◆→終了:#{block_title}←◆\n"
        result += "\n"

        result
      end

      # Individual code block type visitors that delegate to common method
      def visit_code_block_list(node)
        render_code_block_common(node)
      end

      def visit_code_block_listnum(node)
        render_code_block_common(node)
      end

      def visit_code_block_emlist(node)
        render_code_block_common(node)
      end

      def visit_code_block_emlistnum(node)
        render_code_block_common(node)
      end

      def visit_code_block_cmd(node)
        render_code_block_common(node)
      end

      def visit_code_block_source(node)
        render_code_block_common(node)
      end

      def visit_code_line(node)
        render_children(node) + "\n"
      end

      def visit_table(node)
        result = +''
        @table_row_separator_count = 0

        result += "\n"
        result += "◆→開始:#{TITLES[:table]}←◆\n"

        # Add caption if present
        caption = render_caption_inline(node.caption_node)
        unless caption.empty?
          result += if node.id
                      # Use I18n formatting to match TOPBuilder
                      format_table_caption(node.id, caption, node.definition_number)
                    else
                      "■#{caption}\n"
                    end
          result += "\n"
        end

        # Process table content
        result += render_children(node)

        result += "◆→終了:#{TITLES[:table]}←◆\n"
        result += "\n"

        result
      end

      def visit_table_row(node)
        cells = []
        node.children.each do |cell|
          cell_content = render_children(cell)
          # Skip separator rows (rows that contain only dashes)
          unless /^-+$/.match?(cell_content.strip)
            cells << cell_content
          end
        end

        # Only process non-empty rows
        return '' if cells.empty? || cells.all? { |cell| cell.strip.empty? }

        result = cells.join("\t") + "\n"

        # Add separator after header rows
        @table_row_separator_count += 1
        # Check if this should be treated as header (simplified logic)
        if @table_row_separator_count == 1 && should_add_table_separator?
          result += "#{'-' * 12}\n"
        end

        result
      end

      def visit_table_cell(node)
        content = render_children(node)

        # Apply bold formatting for header cells if configured (matches TOPBuilder)
        if node.cell_type == :th && should_format_table_header?
          "★#{content}☆"
        else
          content
        end
      end

      def visit_image(node)
        result = +''

        result += "\n"
        result += "◆→開始:#{TITLES[:image]}←◆\n"

        # caption_position decides whether the caption goes above or below the
        # figure; TOPBuilder branches on it and the default for images is
        # 'bottom'. This renderer used to always emit the caption first, so the
        # setting had no effect on TOP output.
        caption = image_caption(node)
        result += "#{caption}\n" if caption_top?('image') && !caption.empty?

        result += image_marker(node)

        result += caption unless caption_top?('image') || caption.empty?

        result += "◆→終了:#{TITLES[:image]}←◆\n"
        result += "\n"

        result
      end

      # The caption line for an image block, empty when there is no caption.
      def image_caption(node)
        caption = render_caption_inline(node.caption_node)
        return '' if caption.empty?

        if node.id
          # Use I18n formatting to match TOPBuilder
          format_image_caption(node.id, caption, node.definition_number)
        else
          "■#{caption}\n"
        end
      end

      def visit_minicolumn(node)
        result = +''
        minicolumn_title = TITLES[node.minicolumn_type.to_sym] || node.minicolumn_type.to_s

        result += "\n"
        result += "◆→開始:#{minicolumn_title}←◆\n"

        # Add caption if present
        caption = render_caption_inline(node.caption_node)
        unless caption.empty?
          result += "■#{caption}\n"
          result += "\n"
        end

        result += render_children(node)

        result += "◆→終了:#{minicolumn_title}←◆\n"
        result += "\n"

        result
      end

      # TOPBuilder wraps a column in the same begin/end markers as its other
      # blocks and prefixes the title with "■" (common_column_begin/end). This
      # emitted the bare title and body, so a column was indistinguishable from
      # surrounding text in TOP output.
      def visit_column(node)
        result = +''
        caption = render_caption_inline(node.caption_node)

        result += "\n"
        result += "◆→開始:#{TITLES[:column]}←◆\n"
        result += "■#{caption}\n" unless caption.empty?
        result += render_children(node)
        result += "◆→終了:#{TITLES[:column]}←◆\n"
        result += "\n"

        result
      end

      # visit_block is now handled by Base renderer with dynamic method dispatch

      def visit_block_quote(node)
        result = +''

        result += "\n"
        result += "◆→開始:#{TITLES[:quote]}←◆\n"
        result += render_children(node)
        result += "◆→終了:#{TITLES[:quote]}←◆\n"
        result += "\n"

        result
      end

      def visit_generic_block(node)
        block_title = TITLES[node.block_type.to_sym] || node.block_type.to_s
        result = +''

        result += "\n"
        result += "◆→開始:#{block_title}←◆\n"
        result += render_children(node)
        result += "◆→終了:#{block_title}←◆\n"
        result += "\n"

        result
      end

      # Block elements from todo-top.md

      def visit_block_lead(node)
        result = +''
        result += "\n◆→開始:#{TITLES[:lead]}←◆\n"
        result += render_children(node)
        result += "◆→終了:#{TITLES[:lead]}←◆\n\n"
        result
      end

      alias_method :visit_block_read, :visit_block_lead

      def visit_block_flushright(node)
        result = +''
        result += "\n◆→開始:#{TITLES[:flushright]}←◆\n"
        result += render_children(node)
        result += "◆→終了:#{TITLES[:flushright]}←◆\n\n"
        result
      end

      def visit_block_centering(node)
        result = +''
        result += "\n◆→開始:#{TITLES[:centering]}←◆\n"
        result += render_children(node)
        result += "◆→終了:#{TITLES[:centering]}←◆\n\n"
        result
      end

      def visit_tex_equation(node)
        result = +''
        result += "\n◆→開始:#{TITLES[:texequation]}←◆\n"
        result += node.content if node.respond_to?(:content)
        result += render_children(node) unless node.respond_to?(:content)
        result += "\n◆→終了:#{TITLES[:texequation]}←◆\n\n"
        result
      end

      def visit_block_emtable(node)
        result = +''
        @table_row_separator_count = 0

        result += "\n"
        result += "◆→開始:#{TITLES[:emtable]}←◆\n"

        # Add caption if present
        caption = render_caption_inline(node.caption_node)
        unless caption.empty?
          result += "■#{caption}\n"
          result += "\n"
        end

        # Process table content
        result += render_children(node)

        result += "◆→終了:#{TITLES[:emtable]}←◆\n"
        result += "\n"

        result
      end

      def visit_block_imgtable(node)
        result = +''

        result += "\n"
        result += "◆→開始:#{TITLES[:table]}←◆\n"

        # Add caption if present
        caption = render_caption_inline(node.caption_node)
        unless caption.empty?
          result += if node.id
                      # Use I18n formatting to match TOPBuilder
                      format_table_caption(node.id, caption, node.definition_number)
                    else
                      "■#{caption}\n"
                    end
          result += "\n"
        end

        result += image_marker(node)

        result += "◆→終了:#{TITLES[:table]}←◆\n"
        result += "\n"

        result
      end

      def render_inline_element(type, content, node) # rubocop:disable Metrics/CyclomaticComplexity
        case type
        when :b, :strong
          "★#{content}☆"
        when :i, :em
          "▲#{content}☆"
        when :code, :tt
          "△#{content}☆"
        when :ttb, :ttbold
          "★#{content}☆◆→等幅フォント太字←◆"
        when :tti
          "▲#{content}☆◆→等幅フォントイタ←◆"
        when :u
          "＠#{content}＠◆→＠〜＠部分に下線←◆"
        when :ami
          "#{content}◆→DTP連絡:「#{content}」に網カケ←◆"
        when :bou
          "#{content}◆→DTP連絡:「#{content}」に傍点←◆"
        when :keytop
          "#{content}◆→キートップ#{content}←◆"
        when :idx
          "#{content}◆→索引項目:#{content}←◆"
        when :hidx
          "◆→索引項目:#{content}←◆"
        when :balloon
          "\t←#{content}"
        when :m
          "◆→TeX式ここから←◆#{content}◆→TeX式ここまで←◆"
        when :ins
          "◆→開始:挿入表現←◆#{content}◆→終了:挿入表現←◆"
        when :del
          "◆→開始:削除表現←◆#{content}◆→終了:削除表現←◆"
        when :tcy
          "◆→開始:回転←◆#{content}◆→終了:縦回転←◆"
        when :maru
          "#{content}◆→丸数字#{content}←◆"
        when :hint
          "◆→ヒントスタイルここから←◆#{content}◆→ヒントスタイルここまで←◆"
        when :sup
          "#{content}◆→DTP連絡:「#{content}」は上付き←◆"
        when :sub
          "#{content}◆→DTP連絡:「#{content}」は下付き←◆"
        when :br
          "\n"
        when :href
          render_href(node, content)
        when :url # rubocop:disable Lint/DuplicateBranch
          "△#{content}☆"
        when :fn
          render_footnote_ref(node, content)
        when :ruby
          render_ruby(node, content)
        when :comment
          render_comment(node, content)
        when :raw
          render_raw(node, content)
        when :labelref
          render_labelref(node, content)
        when :pageref
          render_pageref(node, content)
        else
          content
        end
      end

      def visit_footnote(node)
        content = render_children(node).chomp
        # The number is stamped on the definition node (definition_number).
        footnote_number = node.definition_number&.number || 1

        "【注#{footnote_number}】#{content}\n"
      end

      def visit_reference(node)
        format_resolved_reference(node.resolved_data)
      end

      private

      # The numbering prefix for a headline, as Builder#headline_prefix produces
      # it: advance the section counter for every headline (so later numbers stay
      # right even where nothing is printed), then let SecCounter decide what to
      # show for this level and secnolevel. It returns nil beyond secnolevel and
      # for a chapter with no number, which prints as the empty string.
      def generate_headline_prefix(level)
        return '' unless @sec_counter

        @sec_counter.inc(level)
        @sec_counter.prefix(level, config['secnolevel'] || DEFAULT_SECNOLEVEL).to_s
      end

      def should_add_table_separator?
        # Add separator when th_bold is not enabled (matches TOPBuilder logic)
        # TOPBuilder adds separator when: !@book.config['textmaker'] || !@book.config['textmaker']['th_bold']
        !config&.dig('textmaker', 'th_bold')
      end

      def should_format_table_header?
        # Check config for header formatting
        config&.dig('textmaker', 'th_bold') || false
      end

      # The "◆→<path>←◆" line naming the image file, as TOPBuilder emits it.
      # An unbound image warns and falls back to the block's raw body, so a
      # missing file is visible in the output instead of silently naming an id.
      def image_marker(node)
        unless node.image_path
          warn "image not bound: #{node.id}"
          body = render_children(node)
          return body if body.empty? || body.end_with?("\n")

          return "#{body}\n"
        end

        "◆→#{node.image_path}#{format_image_metrics(node)}←◆\n"
      end

      # Metrics targeted at this format, space-separated as TOPBuilder writes
      # them. Taking node.metric raw would leak another target's metric (e.g.
      # "latex::width=80mm") into the text output.
      def format_image_metrics(node)
        metrics = parse_metric('top', node.metric)
        metrics.present? ? " #{metrics}" : ''
      end

      # Format list caption using I18n (matches TOPBuilder)
      def format_list_caption(id, caption_text, definition_number)
        return "■#{caption_text}\n" unless render_context.chapter_present?
        return "■#{id}■#{caption_text}\n" unless definition_number

        formatted = text_formatter.format_caption_plain('list', definition_number.chapter_number, definition_number.number, caption_text)
        "#{formatted}\n"
      end

      # Format table caption using I18n (matches TOPBuilder)
      def format_table_caption(id, caption_text, definition_number)
        return "■#{caption_text}\n" unless render_context.chapter_present?
        return "■#{id}■#{caption_text}\n" unless definition_number

        formatted = text_formatter.format_caption_plain('table', definition_number.chapter_number, definition_number.number, caption_text)
        "#{formatted}\n"
      end

      # Format image caption using I18n (matches TOPBuilder)
      def format_image_caption(_id, caption_text, definition_number)
        return "■#{caption_text}\n" unless render_context.chapter_present?

        # No number means //indepimage or //numberlessimage, which TOPBuilder
        # renders through indepimage_header: the figure label and the caption,
        # with no number. It used to fall back to "■<id>■", naming the id
        # instead of labelling the figure.
        unless definition_number
          return "#{I18n.t('image')}#{I18n.t('caption_prefix_idgxml')}#{caption_text}\n"
        end

        formatted = text_formatter.format_caption_plain('image', definition_number.chapter_number, definition_number.number, caption_text)
        "#{formatted}\n"
      end

      def render_caption_inline(caption_node)
        caption_node ? render_children(caption_node) : ''
      end

      def render_href(node, content)
        args = node.args || []
        if args.length >= 2
          url = args[0]
          label = args[1]
          "#{label}（△#{url}☆）"
        else
          "△#{content}☆"
        end
      end

      def render_footnote_ref(node, _content)
        # The number comes from the resolved @<fn> reference data.
        ref = node.children.first
        footnote_number = ref&.resolved_data&.item_number || 1
        "【注#{footnote_number}】"
      end

      def render_ruby(node, content)
        args = node.args || []
        if args.length >= 2
          base = args[0]
          ruby = args[1]
          "#{base}◆→DTP連絡:「#{base}」に「#{ruby}」とルビ←◆"
        else
          content
        end
      end

      def render_comment(_node, content)
        # Only render in draft mode
        if config['draft']
          "◆→#{content}←◆"
        else
          ''
        end
      end

      def render_raw(node, content)
        args = node.args || []
        if args.any?
          format = args.first
          if format == 'top'
            content
          else
            '' # Ignore raw content for other formats
          end
        else
          content
        end
      end

      def render_labelref(node, content)
        args = node.args || []
        label_id = args.first || content
        "「◆→#{label_id}←◆」"
      end

      def render_pageref(node, content)
        args = node.args || []
        label_id = args.first || content
        "●ページ◆→#{label_id}←◆"
      end

      # Format resolved reference based on ResolvedData
      # Gets plain text from TextFormatter and wraps it with TOP-specific markup
      def format_resolved_reference(data)
        # Get plain text from TextFormatter (no TOP markup)
        plain_text = text_formatter.format_reference(data.reference_type, data)

        # Wrap with TOP-specific markup based on reference type
        case data.reference_type
        when :footnote
          # For footnote, use 【注】 markup
          number = data.item_number || data.item_id
          "【注#{number}】"
        when :endnote
          # For endnote, use 【後注】 markup
          number = data.item_number || data.item_id
          "【後注#{number}】"
        else
          # For other types, return plain text as-is
          plain_text
        end
      end

      def visit_block_bibpaper(node)
        id = node.args[0]
        caption_text = node.args[1]

        result = +''
        if id && render_context.chapter_present?
          bibpaper_number = node.definition_number&.number
          result += bibpaper_number ? "[#{bibpaper_number}]" : "[#{id}]"
        end

        # Render caption with inline elements if it has a caption_node
        if node.respond_to?(:caption_node) && node.caption_node
          caption = render_caption_inline(node.caption_node)
          result += " #{caption}\n"
        elsif caption_text
          result += " #{caption_text}\n"
        else
          result += "\n"
        end

        # Render body content
        content = render_children(node)
        result += "#{content}\n" unless content.strip.empty?

        result
      end

      def visit_embed(node)
        # Check if content should be output for this renderer
        # TOP format accepts 'top' and 'text' as target builders
        return '' unless node.targeted_for?('top') || node.targeted_for?('text')

        # Get content
        content = node.content || ''

        # Process \n based on embed type
        case node.embed_type
        when :inline, :raw
          # For inline and raw embeds, convert \\n to actual newlines
          content = content.gsub('\\n', "\n")
        end

        # For block embeds, add trailing newline
        node.embed_type == :block ? content + "\n" : content
      end
    end
  end
end
