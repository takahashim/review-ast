# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/textutils'
require 'review/loggable'
require_relative 'text_renderer_common'
require_relative 'base'

module ReVIEW
  module Renderer
    class PlaintextRenderer < Base
      # review-ext.rb methods on this builder render the book's own commands.
      # PLAINTEXTBuilder#image_ext: the format //graph generators are asked for.
      def image_ext
        'png'
      end

      def legacy_builder_class
        require 'review/plaintextbuilder'
        ReVIEW::PLAINTEXTBuilder
      end

      include ReVIEW::TextUtils
      include ReVIEW::Loggable
      include ReVIEW::Renderer::TextRendererCommon

      # Configure's default, used when the book config does not set one.
      DEFAULT_SECNOLEVEL = 2

      def initialize(chapter)
        super
        @ol_num = nil
        @logger = ReVIEW.logger
        # Section numbering, as in the legacy builders (LaTeX/HTML/IDGXML
        # renderers already do this; text did not, so section numbers were
        # missing from its output entirely).
        @sec_counter = ReVIEW::AST::SectionCounter.new(5, @chapter) if @chapter
      end

      # Format type for this renderer
      # @return [Symbol] Format type :text
      def format_type
        :text
      end

      def target_name
        'plaintext'
      end

      def visit_headline(node)
        # PLAINTEXTBuilder#nodisp_begin prints nothing at all.
        return '' if node.nodisp?

        caption = render_caption_inline(node.caption_node)

        # [nonum]/[notoc] headings print the bare title: PLAINTEXTBuilder routes
        # them to nonum_begin/notoc_begin, which never call headline_prefix, so
        # they are unnumbered *and* leave the section counter untouched.
        return "#{caption}\n" if node.nonum? || node.notoc?

        "#{headline_prefix(node.level)}#{caption}\n"
      end

      def visit_paragraph(node)
        # As puts prints it: a trailing @<br> is the line's own newline.
        "#{render_source_lines(node.children).chomp}\n"
      end

      def visit_list(node)
        result = +''

        case node.list_type
        when :ul
          node.children.each do |item|
            result += visit_list_item(item, :ul)
          end
        when :ol
          # Reset ol counter
          @ol_num = node.start_number || 1
          node.children.each do |item|
            result += visit_list_item(item, :ol)
            @ol_num += 1
          end
          @ol_num = nil
        when :dl
          node.children.each do |item|
            result += visit_definition_item(item)
          end
        else
          raise NotImplementedError, "PlaintextRenderer does not support list_type #{node.list_type}."
        end

        "\n#{result}\n"
      end

      # One item per line, as PLAINTEXTBuilder#ul_item/#ol_item print it: the
      # item's own source lines folded by join_lines_to_paragraph (continuation
      # lines are separate children, marked by source_line_breaks), then any
      # nested list on the lines after it -- not folded into the item's line.
      def visit_list_item(node, type = :ul)
        breaks = node.source_line_breaks
        inline = []
        inline_breaks = []
        nested = +''
        node.children.each_with_index do |child, index|
          if inline_content_node?(child)
            inline_breaks << inline.size if breaks.include?(index)
            inline << child
          else
            nested << visit_nested_block(child)
          end
        end
        # Not stripped: the source lines were (by the parser, as
        # ReVIEW::Compiler strips them), but a trailing space an inline writes
        # (@<fn>'s " 注1 ") stays, as in PLAINTEXTBuilder#ul_item.
        text = render_source_lines(inline, breaks: inline_breaks)

        # PLAINTEXTBuilder#ol_item prints the number the item was written
        # with (//olnum does not renumber a text list); the counter is for a
        # list with no written numbers.
        line = type == :ol ? "#{node.number || @ol_num}　#{text}\n" : "#{text}\n"
        line + nested
      end

      # A nested //ol restarts and then clears the item counter; keep the
      # enclosing list's.
      def visit_nested_block(node)
        saved = @ol_num
        visit(node)
      ensure
        @ol_num = saved
      end

      def visit_definition_item(node)
        # Handle definition term
        term = if node.term_children && !node.term_children.empty?
                 node.term_children.map { |child| visit(child) }.join
               else
                 ''
               end

        # Handle definition content: one line per paragraph (PLAINTEXTBuilder#dd).
        "#{term}\n" + definition_paragraphs(node).map { |paragraph| "#{paragraph}\n" }.join
      end

      def text_block(node, caption_top:)
        caption = node.caption_node ? render_caption_inline(node.caption_node) : ''
        body = render_children(node)
        body += "\n" unless body.empty? || body.end_with?("\n")

        result = +"\n"
        result << "#{caption}\n" if caption_top && !caption.empty?
        result << body
        result << "#{caption}\n" if !caption_top && !caption.empty?
        result << "\n"
      end

      # Numbered code block (listnum, emlistnum)
      def render_numbered_code_block(node)
        result = +''
        caption = render_caption_inline(node.caption_node)
        lines_content = render_children(node)

        # -1: empty lines at the end of the block are numbered too.
        lines = lines_content.split("\n", -1)
        lines.pop if lines.last && lines.last.empty?

        first_line_number = node.first_line_num || 1

        # PLAINTEXTBuilder#listnum runs its caption through list_header, so it
        # is numbered ("リスト1.1　..."), while #emlistnum prints the caption as
        # written. Both used the bare caption here, which dropped the list
        # number from every //listnum.
        header = if node.code_type.to_sym == :listnum && !caption.empty?
                   generate_list_header(node.id, caption, node.definition_number)
                 else
                   caption
                 end

        result += "\n" if caption_top?('list') && !caption.empty?
        result += "#{header}\n" if caption_top?('list') && !caption.empty?
        result += "\n" if caption_top?('list') && !caption.empty?

        lines.each_with_index do |line, i|
          result += "#{(i + first_line_number).to_s.rjust(2)}: #{line}\n"
        end

        result += "\n" unless caption_top?('list')
        result += "#{header}\n" unless caption_top?('list') || caption.empty?
        result += "\n"

        result
      end

      # Regular code block (emlist, cmd, source, etc.). Its lines are printed
      # as written: PLAINTEXTBuilder expands tabs in a //list body only
      # (list_body), not in these or in the numbered blocks.
      def render_regular_code_block(node)
        result = +''
        caption = render_caption_inline(node.caption_node)
        lines_content = render_children(node)

        result += "\n" if caption_top?('list') && !caption.empty?
        result += "#{caption}\n" if caption_top?('list') && !caption.empty?

        lines_content.each_line do |line|
          result += line.chomp + "\n"
        end

        result += "#{caption}\n" unless caption_top?('list') || caption.empty?
        result += "\n"

        result
      end

      def visit_code_block_list(node)
        result = +''
        caption = render_caption_inline(node.caption_node)
        lines_content = render_children(node)

        result += "\n" if caption_top?('list') && !caption.empty?
        result += generate_list_header(node.id, caption, node.definition_number) + "\n" if caption_top?('list') && !caption.empty?
        result += "\n" if caption_top?('list') && !caption.empty?

        lines_content.each_line do |line|
          result += detab(line.chomp) + "\n"
        end

        result += "\n" unless caption_top?('list')
        result += generate_list_header(node.id, caption, node.definition_number) + "\n" unless caption_top?('list') || caption.empty?
        result += "\n"

        result
      end

      def visit_code_block_listnum(node)
        render_numbered_code_block(node)
      end

      def visit_code_block_emlist(node)
        render_regular_code_block(node)
      end

      def visit_code_block_emlistnum(node)
        render_numbered_code_block(node)
      end

      def visit_code_block_cmd(node)
        render_regular_code_block(node)
      end

      def visit_code_block_source(node)
        render_regular_code_block(node)
      end

      def visit_code_line(node)
        line_content = render_children(node)
        # Add newline after each line
        line_content + "\n"
      end

      def visit_table(node)
        result = +''

        # Check if this is an imgtable
        if node.table_type == :imgtable
          return render_imgtable(node)
        end

        caption = render_caption_inline(node.caption_node)
        header = unless caption.empty?
                   node.id ? generate_table_header(node.id, caption, node.definition_number) : caption
                 end
        rows = (node.header_rows + node.body_rows).map { |row| visit_table_row(row) }.join

        # PLAINTEXTBuilder#table_header puts the caption above or below the
        # rows per caption_position.
        if caption_top?('table')
          result += "\n#{header}\n\n" if header
          result += rows
        else
          result += "\n#{rows}"
          result += "\n#{header}\n" if header
        end
        result += "\n"

        result
      end

      def visit_table_row(node)
        cells = node.children.map { |cell| render_children(cell) }
        cells.join("\t") + "\n"
      end

      def visit_table_cell(node)
        render_children(node)
      end

      def visit_image(node)
        result = +''
        caption = render_caption_inline(node.caption_node)

        result += "\n"
        if node.id && node.definition_number
          dn = node.definition_number
          # PLAINTEXTBuilder#image prints the separator even before an empty
          # caption (//image[id][][scale=0.5]).
          result += "#{text_formatter.format_caption_plain('image', dn.chapter_number, dn.number)}#{I18n.t('caption_prefix_idgxml')}#{caption}\n"
        else
          result += "図　#{caption}\n" unless caption.empty?
        end
        result += "\n"

        result
      end

      def visit_minicolumn(node)
        result = +''
        caption = render_caption_inline(node.caption_node)

        result += "\n"
        result += "#{caption}\n" unless caption.empty?
        result += render_children(node)
        result += "\n"

        result
      end

      def visit_column(node)
        result = +''
        caption = render_caption_inline(node.caption_node)

        result += "\n"
        result += "#{caption}\n" unless caption.empty?
        result += render_children(node)
        result += "\n"

        result
      end

      # visit_block is now handled by Base renderer with dynamic method dispatch

      def visit_block_quote(node)
        result = +"\n"
        result += render_children(node)
        result += "\n"
        result
      end

      def visit_block_blockquote(node)
        visit_block_quote(node)
      end

      def visit_block_comment(_node)
        # Comments are not rendered in plaintext
        ''
      end

      def visit_block_pagebreak(_node)
        # Page breaks are not meaningful in plaintext
        ''
      end

      def visit_block_lead(node)
        result = +"\n"
        result += render_children(node)
        result += "\n"
        result
      end

      alias_method :visit_block_read, :visit_block_lead

      def visit_block_flushright(node)
        result = +"\n"
        result += render_children(node)
        result += "\n"
        result
      end

      def visit_block_centering(node)
        result = +"\n"
        result += render_children(node)
        result += "\n"
        result
      end

      # PLAINTEXTBuilder#base_block (//box, //insn, //bpo): the caption above
      # or below the lines per caption_position (list), between blank lines.
      def visit_block_box(node)
        text_block(node, caption_top: caption_top?('list'))
      end

      alias_method :visit_block_insn, :visit_block_box
      alias_method :visit_block_bpo, :visit_block_box

      # PLAINTEXTBuilder#base_parablock (//point, //term): the caption always
      # above the paragraphs.
      def visit_block_point(node)
        text_block(node, caption_top: true)
      end

      alias_method :visit_block_term, :visit_block_point

      # //hr and //parasep (a Markdown thematic break is an //hr) have no
      # PLAINTEXTBuilder method; in plain text they separate nothing.
      def visit_block_hr(_node)
        ''
      end

      alias_method :visit_block_parasep, :visit_block_hr

      def visit_block_bibpaper(node)
        visit_bibpaper_block(node)
      end

      def visit_bibpaper_block(node)
        id = node.args[0]
        caption_text = node.args[1]

        result = +''
        if id && node.definition_number
          result += "#{node.definition_number.number} "
        end
        result += "#{caption_text}\n" if caption_text

        content = render_children(node)
        result += "#{content}\n" unless content.strip.empty?

        result
      end

      def visit_generic_block(node)
        result = +''
        caption = render_caption_inline(node.caption_node) if node.respond_to?(:caption_node)

        result += "\n"
        result += "#{caption}\n" if caption && !caption.empty?
        result += render_children(node)
        result += "\n"

        result
      end

      def visit_tex_equation(node)
        result = +''
        content = node.content

        result += "\n"

        if node.id? && node.definition_number
          caption = render_caption_inline(node.caption_node)
          dn = node.definition_number
          result += "#{text_formatter.format_caption_plain('equation', dn.chapter_number, dn.number, caption)}\n" if caption_top?('equation')
        end

        result += "#{content}\n"

        if node.id? && node.definition_number
          caption = render_caption_inline(node.caption_node)
          dn = node.definition_number
          result += "#{text_formatter.format_caption_plain('equation', dn.chapter_number, dn.number, caption)}\n" unless caption_top?('equation')
        end

        result += "\n"
        result
      end

      def render_inline_element(type, content, node)
        method_name = "render_inline_#{type}"
        if respond_to?(method_name, true)
          send(method_name, type, content, node)
        else
          # For unknown inline elements (typically reference types), the content is
          # Reference types (list, img, table, hd, column, etc.) have their content already resolved
          content || ''
        end
      end

      # A resolved reference renders as its formatted text ("図1.1"), the same
      # text the builders produce. This returned node.content, which is the
      # reference's own id, so every @<img>/@<list>/@<table> in plain-text
      # output named the id instead of the number.
      def visit_reference(node)
        return node.content || '' unless node.resolved?

        data = node.resolved_data
        text_formatter.format_reference(data.reference_type, data)
      end

      def visit_footnote(node)
        return '' if endnote_definition?(node)

        content = render_children(node)
        # The number is stamped on the definition node (definition_number).
        footnote_number = node.definition_number&.number || '??'

        "注#{footnote_number} #{content}\n"
      end

      def visit_embed(node)
        # Check if content should be output for this renderer
        return '' unless node.targeted_for?('plaintext')

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

      # Inline rendering methods

      # Deleted text is dropped, not just undecorated: plain text has no way to
      # show a strikethrough, so PLAINTEXTBuilder#inline_del returns nothing and
      # the reader sees the text as it stands after the deletion. (@<ins> is the
      # other half of that pair and keeps its content.)
      def render_inline_del(_type, _content, _node)
        ''
      end

      def render_inline_fn(_type, _content, node)
        # The number comes from the resolved @<fn> reference data.
        ref = node.children.first
        number = ref&.resolved_data&.item_number
        return '' unless number

        " 注#{number} "
      end

      def render_inline_kw(_type, _content, node)
        if node.args.length >= 2
          word = node.args[0]
          alt = node.args[1].strip
          "#{word}（#{alt}）"
        else
          node.args.first || ''
        end
      end

      def render_inline_href(_type, _content, node)
        args = node.args || []
        if args.length >= 2
          url = args[0]
          label = args[1]
          "#{label}（#{url}）"
        else
          args.first || ''
        end
      end

      def render_inline_ruby(_type, _content, node)
        # Ruby base text only, ignore ruby annotation
        node.args.first || ''
      end

      def render_inline_imgref(_type, content, node)
        image_reference_with_caption(node, content)
      end

      # PLAINTEXTBuilder#inline_dtp: a DTP instruction has no place in text.
      def render_inline_dtp(_type, _content, _node)
        ''
      end

      def render_inline_br(_type, _content, _node)
        "\n"
      end

      def render_inline_raw(_type, _content, node)
        # Convert \n to actual newlines like PLAINTEXTBuilder
        if node.targeted_for?('plaintext')
          (node.content || '').gsub('\\n', "\n")
        else
          ''
        end
      end

      def render_inline_embed(_type, _content, node)
        # Convert \n to actual newlines like PLAINTEXTBuilder
        if node.targeted_for?('plaintext')
          (node.content || '').gsub('\\n', "\n")
        else
          ''
        end
      end

      def render_inline_hidx(_type, _content, _node)
        ''
      end

      def render_inline_icon(_type, _content, _node)
        ''
      end

      def render_inline_comment(_type, _content, _node)
        ''
      end

      def render_inline_balloon(_type, content, _node)
        "←#{content}"
      end

      def render_inline_uchar(_type, content, _node)
        [content.to_i(16)].pack('U')
      end

      def render_inline_bib(_type, _content, node)
        ref_node = node.children.first
        unless ref_node.reference_node? && ref_node.resolved?
          raise 'BUG: Reference should be resolved at AST construction time'
        end

        data = ref_node.resolved_data
        # The trailing space is PLAINTEXTBuilder#inline_bib's: with no brackets
        # around the number it is what keeps "1" from running into the word
        # after it.
        "#{data.item_number} "
      end

      def render_inline_hd(_type, _content, node)
        # Headline reference
        ref_node = node.children.first
        unless ref_node.reference_node? && ref_node.resolved?
          raise 'BUG: Reference should be resolved at AST construction time'
        end

        data = ref_node.resolved_data
        text_formatter.format_reference(:headline, data)
      end

      def render_inline_labelref(_type, _content, _node)
        '●'
      end

      alias_method :render_inline_ref, :render_inline_labelref

      def render_inline_pageref(_type, _content, _node)
        '●ページ'
      end

      def render_inline_chap(_type, _content, node)
        ref_node = node.children.first
        unless ref_node.reference_node? && ref_node.resolved?
          raise 'BUG: Reference should be resolved at AST construction time'
        end

        data = ref_node.resolved_data
        text_formatter.format_chapter_number_full(data.chapter_number, data.chapter_type).to_s
      end

      def render_inline_title(_type, _content, node)
        chapter_title_of(node)
      end

      def render_inline_sec(_type, _content, node)
        section_number_of(node)
      end

      def render_inline_sectitle(_type, _content, node)
        section_title_of(node)
      end

      def render_inline_chapref(_type, _content, node)
        ref_node = node.children.first
        unless ref_node.reference_node? && ref_node.resolved?
          raise 'BUG: Reference should be resolved at AST construction time'
        end

        chapter_reference_text(ref_node.resolved_data)
      end

      def render_inline_default(_type, content, _node)
        content
      end

      # Default inline rendering - just return content
      alias_method :render_inline_b, :render_inline_default
      alias_method :render_inline_strong, :render_inline_default
      alias_method :render_inline_i, :render_inline_default
      alias_method :render_inline_em, :render_inline_default
      alias_method :render_inline_tt, :render_inline_default
      alias_method :render_inline_code, :render_inline_default
      alias_method :render_inline_ttb, :render_inline_default
      alias_method :render_inline_ttbold, :render_inline_default
      alias_method :render_inline_tti, :render_inline_default
      alias_method :render_inline_ttibold, :render_inline_default
      alias_method :render_inline_u, :render_inline_default
      alias_method :render_inline_bou, :render_inline_default
      alias_method :render_inline_keytop, :render_inline_default
      alias_method :render_inline_m, :render_inline_default
      alias_method :render_inline_ami, :render_inline_default
      alias_method :render_inline_sup, :render_inline_default
      alias_method :render_inline_sub, :render_inline_default
      alias_method :render_inline_hint, :render_inline_default
      alias_method :render_inline_maru, :render_inline_default
      alias_method :render_inline_idx, :render_inline_default
      alias_method :render_inline_ins, :render_inline_default
      # No del alias: render_inline_del drops the content rather than keeping it.
      alias_method :render_inline_tcy, :render_inline_default

      # Helper methods
      def render_caption_inline(caption_node)
        return '' unless caption_node

        # A caption's source line breaks fold the same way a paragraph's do.
        render_source_lines(caption_node.children)
      end

      # The numbering prefix for a headline, as Builder#headline_prefix produces
      # it: advance the section counter for every headline (so later numbers stay
      # right even where nothing is printed), then let SecCounter decide what to
      # show for this level and secnolevel. It returns nil beyond secnolevel and
      # for a chapter with no number, which prints as the empty string.
      def headline_prefix(level)
        return '' unless @sec_counter

        @sec_counter.inc(level)
        @sec_counter.prefix(level, config['secnolevel'] || DEFAULT_SECNOLEVEL).to_s
      end

      def generate_list_header(id, caption, definition_number)
        return caption unless id && definition_number

        text_formatter.format_caption_plain('list', definition_number.chapter_number, definition_number.number, caption)
      end

      def generate_table_header(id, caption, definition_number)
        return caption unless id && definition_number

        text_formatter.format_caption_plain('table', definition_number.chapter_number, definition_number.number, caption)
      end

      def render_imgtable(node)
        result = +''
        caption = render_caption_inline(node.caption_node)

        result += "\n"
        if node.id && !caption.empty?
          result += generate_table_header(node.id, caption, node.definition_number) + "\n"
          result += "\n"
        end
        result += "\n"

        result
      end

      def escape(str)
        # Plaintext doesn't need escaping
        str.to_s
      end
    end
  end
end
