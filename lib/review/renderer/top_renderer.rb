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
      # review-ext.rb methods on this builder render the book's own commands.
      # TOPBuilder (inherited from PLAINTEXTBuilder)#image_ext: the format //graph generators are asked for.
      def image_ext
        'png'
      end

      def legacy_builder_class
        require 'review/topbuilder'
        ReVIEW::TOPBuilder
      end

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
        icon: 'アイコン',
        endnote: '後注'
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
        @sec_counter = ReVIEW::AST::SectionCounter.new(5, @chapter) if @chapter
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
        # chomp: as puts prints it, a trailing @<br> is the line's own newline.
        content = render_source_lines(node.children).chomp
        return '' if content.empty?

        # //noindent has no typographic effect in a text dump, so TOP passes it
        # to the DTP operator as a note (TOPBuilder#noindent). PLAINTEXTBuilder
        # drops it, which is why only this renderer emits the marker.
        return "◆→DTP連絡:次の1行インデントなし←◆\n#{content}\n" if node.noindent?

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
          # TOPBuilder#ol_item prints the number each item was written with
          # (//olnum does not renumber a text list). Counting from
          # start_number is for a list with no written numbers.
          start = node.start_number || 1
          node.children.each_with_index do |item, index|
            result += visit_ordered_list_item(item, item.number || (start + index))
          end
        when :dl
          node.children.each do |item|
            result += visit_definition_item(item)
          end
        end

        result
      end

      def visit_unordered_list_item(node)
        text_content, nested_lists = list_item_parts(node)

        # Use level for nested indentation (TOP style uses tabs for each level)
        level = node.level || 1
        indent = "\t" * (level - 1)

        result = "#{indent}●\t#{text_content}\n"

        # Add any nested lists after the item
        result += nested_lists
        result
      end

      def visit_ordered_list_item(node, number)
        text_content, nested_lists = list_item_parts(node)

        # Use level for nested indentation
        level = node.level || 1
        indent = "\t" * (level - 1)

        result = "#{indent}#{number}\t#{text_content}\n"

        # Add any nested lists after the item
        result += nested_lists
        result
      end

      # A list item's own text and its nested lists. The item's source lines
      # (continuation lines are separate children, marked by
      # source_line_breaks) are folded as TOPBuilder#ul_item/#ol_item fold
      # them, with join_lines_to_paragraph.
      def list_item_parts(node)
        breaks = node.source_line_breaks
        inline = []
        inline_breaks = []
        nested = +''
        node.children.each_with_index do |child, index|
          if child.is_a?(ReVIEW::AST::ListNode)
            nested << visit(child)
          else
            inline_breaks << inline.size if breaks.include?(index)
            inline << child
          end
        end
        [render_source_lines(inline, breaks: inline_breaks).chomp, nested]
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

        # Handle definition content (all children are definition content).
        # TOPBuilder#dd deletes the newlines inside a definition so it prints on
        # one line; keeping them broke the leading tab across the wrapped lines.
        definition = if node.children && !node.children.empty?
                       node.children.map { |child| visit(child) }.join.delete("\n")
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

        # The caption goes above or below the code per caption_position (list),
        # as in TOPBuilder#list / #base_block.
        caption = render_caption_inline(node.caption_node)
        caption_line = unless caption.empty?
                         if node.id && (code_type == :list || code_type == :listnum)
                           # For list/listnum, use I18n formatting to match TOPBuilder
                           format_list_caption(node.id, caption, node.definition_number)
                         elsif node.id
                           "■#{node.id}■#{caption}\n"
                         else
                           "■#{caption}\n"
                         end
                       end
        result += "#{caption_line}\n" if caption_line && caption_top?('list')

        # Add line numbers if needed
        if node.line_numbers
          # -1: empty lines at the end of the block are numbered too (each
          # code line renders with its own "\n", so the last field is empty).
          lines = render_children(node).split("\n", -1)
          lines.pop if lines.last && lines.last.empty?
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
          # TOPBuilder expands tabs in a //list body only (list_body).
          code_content = code_content.split("\n", -1).map { |line| detab(line) }.join("\n") if code_type == :list
          result += code_content
          result += "\n"
        end

        result += "\n#{caption_line}" if caption_line && !caption_top?('list')
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
        # //imgtable is a table by numbering but an image by content.
        return render_imgtable(node) if node.table_type == :imgtable

        result = +''
        @table_row_separator_count = 0
        @table_header_row_count = node.header_rows.size

        result += "\n"
        result += "◆→開始:#{TITLES[:table]}←◆\n"

        # An id-less table (//emtable) prints its caption bare: TOPBuilder
        # routes it through PLAINTEXTBuilder#table_header, which does not add
        # the ■ that block captions elsewhere in this format carry.
        caption = render_caption_inline(node.caption_node)
        header = unless caption.empty?
                   node.id ? format_table_caption(node.id, caption, node.definition_number) : "#{caption}\n"
                 end

        # The caption goes above or below the rows per caption_position.
        result += "#{header}\n" if header && caption_top?('table')
        result += render_children(node)
        result += "\n#{header}" if header && !caption_top?('table')

        result += "◆→終了:#{TITLES[:table]}←◆\n"
        result += "\n"

        result
      end

      def visit_table_row(node)
        cells = []
        node.children.each do |cell|
          # Skip separator rows (rows that contain only dashes)
          next if /^-+$/.match?(render_children(cell).strip)

          cells << visit(cell)
        end

        # Only process non-empty rows
        return '' if cells.empty? || cells.all? { |cell| cell.strip.empty? }

        result = cells.join("\t") + "\n"

        # TOPBuilder#table_rows draws the rule after the header rows, and only
        # for a table that has some (a source separator line); a table
        # without one gets no rule.
        @table_row_separator_count += 1
        if @table_header_row_count.to_i > 0 && @table_row_separator_count == @table_header_row_count && should_add_table_separator?
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
        # TOPBuilder#image prints the heading even for an empty caption
        # (//image[id][][scale=0.5]); #indepimage only for a present one.
        if caption.empty?
          return '' unless node.image_type == :image && node.definition_number && render_context.chapter_present?

          dn = node.definition_number
          return "#{text_formatter.format_caption_plain('image', dn.chapter_number, dn.number)}#{I18n.t('caption_prefix_idgxml')}\n"
        end

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

      # TOPBuilder#base_block (//box, //insn, //bpo): the caption ("■...")
      # above or below the lines per caption_position (list).
      def visit_block_box(node)
        top_block(node, caption_top: caption_top?('list'))
      end

      alias_method :visit_block_insn, :visit_block_box
      alias_method :visit_block_bpo, :visit_block_box

      # TOPBuilder#base_parablock (//point, //term): the caption always above.
      def visit_block_point(node)
        top_block(node, caption_top: true)
      end

      alias_method :visit_block_term, :visit_block_point

      # TOPBuilder#comment: only in draft mode, as "◆→...←◆".
      def visit_block_comment(node)
        return '' unless config['draft']

        lines = node.children.map { |child| child.respond_to?(:content) ? child.content.to_s : render_children(child) }
        comment = node.args.first
        lines.unshift(comment) unless comment.nil? || comment.empty?
        "◆→#{lines.join("\n")}←◆\n"
      end

      # //hr, //parasep and //pagebreak have no TOPBuilder method (a Markdown
      # thematic break is an //hr); they leave no mark.
      def visit_block_hr(_node)
        ''
      end

      alias_method :visit_block_parasep, :visit_block_hr
      alias_method :visit_block_pagebreak, :visit_block_hr

      def top_block(node, caption_top:)
        title = TITLES[node.block_type.to_sym] || node.block_type.to_s
        caption = node.caption_node ? render_caption_inline(node.caption_node) : ''
        body = render_children(node)
        body += "\n" unless body.empty? || body.end_with?("\n")

        result = "\n◆→開始:#{title}←◆\n"
        result << "■#{caption}\n" if caption_top && !caption.empty?
        result << body
        result << "■#{caption}\n" if !caption_top && !caption.empty?
        result << "◆→終了:#{title}←◆\n\n"
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
        result += "#{equation_caption(node)}\n" if equation_caption(node) && caption_top?('equation')
        result += node.content if node.respond_to?(:content)
        result += render_children(node) unless node.respond_to?(:content)
        result += "\n"
        result += "#{equation_caption(node)}\n" if equation_caption(node) && !caption_top?('equation')
        result += "◆→終了:#{TITLES[:texequation]}←◆\n\n"
        result
      end

      # The numbered caption line ("式1.1　…") a //texequation with an id gets,
      # matching TOPBuilder#texequation_header. Nil when the equation has no id,
      # which is the unnumbered case.
      def equation_caption(node)
        return nil unless node.id? && node.definition_number

        dn = node.definition_number
        text_formatter.format_caption_plain('equation', dn.chapter_number, dn.number, render_caption_inline(node.caption_node))
      end

      def render_imgtable(node)
        result = +''

        result += "\n"
        result += "◆→開始:#{TITLES[:table]}←◆\n"

        # The caption sits above or below the image per caption_position, as in
        # TOPBuilder#imgtable.
        caption = imgtable_caption(node)
        result += caption if caption && caption_top?('table')

        result += image_marker(node)

        result += caption if caption && !caption_top?('table')

        result += "◆→終了:#{TITLES[:table]}←◆\n"
        result += "\n"

        result
      end

      # The caption line for an //imgtable, or nil when it has none.
      def imgtable_caption(node)
        caption = render_caption_inline(node.caption_node)
        return nil if caption.empty?

        node.id ? format_table_caption(node.id, caption, node.definition_number) : "#{caption}\n"
      end

      def render_inline_element(type, content, node) # rubocop:disable Metrics/CyclomaticComplexity
        case type
        when :b, :strong, :wb # Builder#inline_wb is inline_b of the word
          "★#{content}☆"
        when :i
          "▲#{content}☆"
        when :em
          em_marked_like_i? ? "▲#{content}☆" : content
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
        when :imgref
          image_reference_with_caption(node, content)
        when :dtp # inherited PLAINTEXTBuilder#inline_dtp
          ''
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
        when :kw
          render_kw(node, content)
        when :title
          chapter_title_of(node)
        when :chap
          # The chapter number alone ("第1章"), not the @<chapref> form.
          data = resolved_data_of(node)
          text_formatter.format_chapter_number_full(data.chapter_number, data.chapter_type).to_s
        when :sec
          section_number_of(node)
        when :sectitle
          section_title_of(node)
        when :uchar
          [content.to_i(16)].pack('U')
        when :icon
          render_icon(node, content)
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
        return '' if endnote_definition?(node)

        content = render_children(node).chomp
        # The number is stamped on the definition node (definition_number).
        footnote_number = node.definition_number&.number || 1

        "【注#{footnote_number}】#{content}\n"
      end

      def visit_reference(node)
        format_resolved_reference(node.resolved_data)
      end

      # TOP wraps its endnotes in block markers and labels each 【後注n】, where
      # the shared (plaintext) form is a bare "(n)". TOPBuilder overrides
      # endnote_begin/endnote_end/endnote_item for exactly this.
      def visit_block_printendnotes(_node)
        return '' if endnote_nodes.empty?

        result = "◆→開始:#{TITLES[:endnote]}←◆\n"
        endnote_nodes.each do |en|
          result += "【後注#{en.definition_number.number}】#{render_children(en)}\n"
        end
        result += "◆→終了:#{TITLES[:endnote]}←◆\n"
        result
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

      # TOPBuilder in Re:VIEW 5.11 leaves @<em> plain (it inherits
      # PLAINTEXTBuilder#inline_em); later Re:VIEW aliases it to inline_i and
      # marks it. Follow the installed builder.
      def em_marked_like_i?
        return @em_marked_like_i if defined?(@em_marked_like_i)

        @em_marked_like_i = ReVIEW::TOPBuilder.instance_method(:inline_em).original_name == :inline_i
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
          # TOPBuilder prints the block's body lines in its place (for an
          # //imgtable, its rows).
          return node.dummy_lines.map { |line| "#{render_children(line)}\n" }.join if node.respond_to?(:dummy_lines)

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

      # @<icon> names an image file, so TOP prints its path. An unbound icon
      # warns and falls back to the id, as TOPBuilder#inline_icon does -- the
      # marker still appears so the missing image is visible in the output.
      def render_icon(node, content)
        return "◆→画像 #{node.image_path.sub(%r{\A\./}, '')}←◆" if node.image_path

        warn "image not bound: #{node.args&.first || content}"
        "◆→画像 #{node.args&.first || content}←◆"
      end

      def render_kw(node, content)
        args = node.args || []
        if args.length >= 2
          "★#{args[0]}☆（#{args[1].strip}）"
        else
          "★#{args[0] || content}☆"
        end
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
        when :chapter
          chapter_reference_text(data)
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
        return '' unless node.targeted_for?('top')

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
