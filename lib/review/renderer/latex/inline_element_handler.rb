# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative '../resolved_reference'
require 'review/latexutils'

module ReVIEW
  module Renderer
    module Latex
      # Inline element handler for LaTeX rendering
      # Uses InlineContext for shared logic
      class InlineElementHandler
        include ReVIEW::LaTeXUtils
        include ReVIEW::Renderer::ResolvedReference

        def initialize(inline_context)
          @ctx = inline_context
          @render_context = @ctx.render_context
          @config = @ctx.config
          # Initialize LaTeX character escaping
          initialize_metachars(@config['texcommand'])
        end

        def review_version2?
          ReVIEW::Renderer::Base.review_version2?(@config)
        end

        def render_inline_b(_type, content, _node)
          review_version2? ? "\\textbf{#{content}}" : "\\reviewbold{#{content}}"
        end

        def render_inline_i(_type, content, _node)
          review_version2? ? "\\textit{#{content}}" : "\\reviewit{#{content}}"
        end

        def render_inline_em(_type, content, _node)
          "\\reviewem{#{content}}"
        end

        def render_inline_tt(_type, content, _node)
          review_version2? ? "\\texttt{#{content}}" : "\\reviewtt{#{content}}"
        end

        def render_inline_ttb(_type, content, _node)
          review_version2? ? "\\texttt{\\textbf{#{content}}}" : "\\reviewttb{#{content}}"
        end

        def render_inline_tti(_type, content, _node)
          review_version2? ? "\\texttt{\\textit{#{content}}}" : "\\reviewtti{#{content}}"
        end

        def render_inline_code(_type, content, _node)
          review_version2? ? "\\texttt{#{content}}" : "\\reviewcode{#{content}}"
        end

        def render_inline_u(_type, content, _node)
          "\\reviewunderline{#{content}}"
        end

        def render_inline_strong(_type, content, _node)
          "\\reviewstrong{#{content}}"
        end

        def render_inline_href(_type, content, node)
          if node.args.length >= 2
            url = node.args[0]
            text = node.args[1]
            # Handle internal references (URLs starting with #)
            if url.start_with?('#')
              anchor = url.sub(/\A#/, '')
              "\\hyperref[#{escape_latex(anchor)}]{#{escape_latex(text)}}"
            elsif /\A[a-z]+:/.match?(url)
              # External URL with scheme
              "\\href{#{escape_url(url)}}{#{escape_latex(text)}}"
            else
              # Plain reference without scheme
              "\\ref{#{escape_latex(url)}}"
            end
          else
            # For single argument href, get raw text from first text child to avoid double escaping
            raw_url = if node.children.first.leaf_node?
                        node.children.first.content
                      else
                        raise NotImplementedError, "URL is invalid: #{content}"
                      end
            # Handle internal references (URLs starting with #)
            if raw_url.start_with?('#')
              anchor = raw_url.sub(/\A#/, '')
              "\\hyperref[#{escape_latex(anchor)}]{#{escape_latex(raw_url)}}"
            elsif /\A[a-z]+:/.match?(raw_url)
              # External URL with scheme
              url_content = escape_url(raw_url)
              "\\url{#{url_content}}"
            else
              # Plain reference without scheme
              "\\ref{#{escape_latex(raw_url)}}"
            end
          end
        end

        def render_inline_fn(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          footnote_number = data.item_number

          # Check if we need to use footnotetext mode
          if @ctx.config['footnotetext']
            # LATEXBuilder emits macro('footnotemark[n]', '') -> the trailing {}.
            "\\footnotemark[#{footnote_number}]{}"
          elsif @ctx.rendering_context.requires_footnotetext?
            # Inside a moving argument: emit \protect\footnotemark{} here and
            # defer the \footnotetext to the //footnote definition (matching
            # LATEXBuilder's @foottext), so it lands on the builder's page even
            # when a page break separates the heading from the definition.
            @ctx.defer_footnotetext(node.args.first)
            '\\protect\\footnotemark{}'
          else
            footnote_content = if data.caption_node
                                 @ctx.render_children(data.caption_node).strip
                               else
                                 escape(data.caption_text || '')
                               end
            "\\footnote{#{footnote_content}}"
          end
        end

        # The short chapter-number prefix for a cross-reference (e.g. "2" in
        # "2.1"), or nil when the chapter is unnumbered. Mirrors LATEXBuilder's
        # get_chap: at secnolevel 0 no chapter is numbered, so refs drop the
        # chapter part ("1.1" -> "1").
        def ref_chapter_number(data)
          return nil unless @ctx.config['secnolevel'].to_i > 0

          short = @ctx.text_formatter.format_chapter_number_short(data.chapter_number, data.chapter_type)
          short && !short.empty? ? short : nil
        end

        # Render list reference
        def render_inline_list(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          list_number = data.item_number

          chapter_num = ref_chapter_number(data)
          if chapter_num
            "\\reviewlistref{#{chapter_num}.#{list_number}}"
          else
            "\\reviewlistref{#{list_number}}"
          end
        end

        # Render listref reference (same as list)
        def render_inline_listref(type, content, node)
          render_inline_list(type, content, node)
        end

        # Render table reference
        def render_inline_table(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          table_number = data.item_number
          # Use current chapter ID if chapter_id is not set in resolved_data
          chapter_id = data.chapter_id || @render_context.chapter_id
          table_label = "table:#{chapter_id}:#{data.item_id}"

          short_num = ref_chapter_number(data)
          if short_num
            "\\reviewtableref{#{short_num}.#{table_number}}{#{table_label}}"
          else
            "\\reviewtableref{#{table_number}}{#{table_label}}"
          end
        end

        # Render tableref reference (same as table)
        def render_inline_tableref(type, content, node)
          render_inline_table(type, content, node)
        end

        # Render image reference
        def render_inline_img(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          image_number = data.item_number
          # Use current chapter ID if chapter_id is not set in resolved_data
          chapter_id = data.chapter_id || @render_context.chapter_id
          image_label = "image:#{chapter_id}:#{data.item_id}"

          short_num = ref_chapter_number(data)
          if short_num
            "\\reviewimageref{#{short_num}.#{image_number}}{#{image_label}}"
          else
            "\\reviewimageref{#{image_number}}{#{image_label}}"
          end
        end

        # Render imgref reference. Like @<img> but, when the referenced image has
        # a caption, LATEXBuilder#inline_imgref appends it as I18n 'image_quote'
        # (「caption」 in ja). The caption is inserted raw, matching the builder.
        def render_inline_imgref(type, content, node)
          img = render_inline_img(type, content, node)
          # The referenced image's caption comes from the resolved reference data
          # (the caption node the resolver copied from the //image definition),
          # matching LATEXBuilder's @chapter.image(id).caption without a chapter
          # index lookup. Nil caption node -> "" (an unnumbered image still gets
          # the empty quote), exactly like the legacy Index::Item#caption.
          caption = node.children.first.resolved_data.caption_node&.to_inline_text || ''
          "#{img}#{@ctx.text_formatter.format_image_quote(caption)}"
        end

        # Render equation reference
        def render_inline_eq(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          equation_number = data.item_number

          short_num = ref_chapter_number(data)
          if short_num
            "\\reviewequationref{#{short_num}.#{equation_number}}"
          else
            "\\reviewequationref{#{equation_number}}"
          end
        end

        # Render eqref reference (same as eq)
        def render_inline_eqref(type, content, node)
          render_inline_eq(type, content, node)
        end

        # Render bibliography reference
        def render_inline_bib(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          bib_number = data.item_number
          bib_id = data.item_id
          "\\reviewbibref{[#{bib_number}]}{bib:#{bib_id}}"
        end

        # Render bibref reference (same as bib)
        def render_inline_bibref(type, content, node)
          render_inline_bib(type, content, node)
        end

        # Render chapter number reference
        def render_inline_chap(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          # Format chapter number to full form (e.g., "第1章", "付録A", "第II部")
          chapter_num = @ctx.text_formatter.format_chapter_number_full(data.chapter_number, data.chapter_type)
          chapter_link(chapter_num, data.item_id)
        end

        # Render chapter title reference
        def render_inline_chapref(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          display_str = @ctx.text_formatter.format_reference(:chapter, data)
          chapter_link(escape(display_str), data.item_id)
        end

        # Extract heading reference from node.args, handling ReferenceResolver's array splitting
        # ReferenceResolver splits "ch02|ブロック命令" into ["ch02", "ブロック命令"]
        # We need to join them back together to get the original format
        # Build heading reference parts from resolved_data
        # Returns [section_number, section_label, section_title]
        def build_heading_reference_parts(data)
          # Get headline_number array (e.g., [1, 2] for section 1.2)
          headline_number = data.headline_number || []

          # Get caption from caption_node
          section_title = data.caption_text

          # Determine chapter context
          if data.chapter_id && data.chapter_number
            # Cross-chapter reference
            short_chapter = @ctx.text_formatter.format_chapter_number_short(data.chapter_number, data.chapter_type)
            chapter_prefix = short_chapter
          elsif @render_context.chapter_number
            # Same chapter reference. format_chapter_number_short replicates
            # Chapter#format_number(false), keyed by the current chapter's type.
            short_chapter = @ctx.text_formatter.format_chapter_number_short(
              @render_context.chapter_number, @render_context.chapter_type
            )
            chapter_prefix = short_chapter
          else
            # Reference without chapter number
            short_chapter = '0'
            chapter_prefix = '0'
          end

          # Build section number for display
          full_number_parts = [short_chapter] + headline_number
          full_section_number = full_number_parts.join('.')

          # A heading is *numbered* only when it has a chapter number and its
          # depth is within secnolevel -- exactly LATEXBuilder#inline_hd_chap's
          # `n.present? && chap.number && over_secnolevel?(n)`. When it is not
          # numbered (e.g. a subsection under the default secnolevel=2), @<hd>/
          # @<secref> must show the title alone, with no number.
          numbered = short_chapter != '0' && @ctx.over_secnolevel?(full_section_number)
          section_number = if numbered
                             # Show full number with chapter: "2.1", "2.1.2", etc.
                             full_section_number
                           else
                             # Without chapter number - use relative section number only
                             headline_number.join('.')
                           end

          # Generate label using chapter prefix and relative section number
          relative_parts = headline_number.join('-')
          section_label = "sec:#{chapter_prefix}-#{relative_parts}"

          [section_number, section_label, section_title, numbered]
        end

        # LATEXBuilder wraps chapter and section references in
        # \reviewchapref / \reviewsecref only when chapterlink is on; with it
        # off they are plain text.
        def chapter_link(text, chapter_id)
          @ctx.chapter_link_enabled? ? "\\reviewchapref{#{text}}{chap:#{chapter_id}}" : text
        end

        def section_link(text, label)
          @ctx.chapter_link_enabled? ? "\\reviewsecref{#{text}}{#{label}}" : text
        end

        # Render heading reference
        def render_inline_hd(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          section_number, section_label, section_title, numbered = build_heading_reference_parts(data)
          quoted = if numbered
                     "「#{section_number} #{escape(section_title)}」"
                   else
                     "「#{escape(section_title)}」"
                   end
          section_link(quoted, section_label)
        end

        # Render section reference
        def render_inline_sec(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          section_number, section_label, _section_title = build_heading_reference_parts(data)
          section_link(section_number, section_label)
        end

        # Render section reference with full title
        def render_inline_secref(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          section_number, section_label, section_title, numbered = build_heading_reference_parts(data)
          quoted = if numbered
                     "「#{section_number} #{escape(section_title)}」"
                   else
                     "「#{escape(section_title)}」"
                   end
          section_link(quoted, section_label)
        end

        # Render section title only
        def render_inline_sectitle(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          _section_number, section_label, section_title = build_heading_reference_parts(data)
          section_link(escape(section_title), section_label)
        end

        # Render index entry
        def render_inline_idx(_type, content, node)
          return content unless node.args.first

          index_str = node.args.first
          # Process hierarchical index like LATEXBuilder's index method
          index_entry = process_index(index_str)
          # Index entry like LATEXBuilder - content first, then index
          "#{content}\\index{#{index_entry}}"
        end

        # Render hidden index entry
        def render_inline_hidx(_type, content, node)
          return content unless node.args.first

          index_str = node.args.first
          # Process hierarchical index like LATEXBuilder's index method
          index_entry = process_index(index_str)
          # Hidden index entry like LATEXBuilder - just output index, content is already rendered
          "\\index{#{index_entry}}"
        end

        # Render DTP directive: LATEXBuilder#inline_dtp ignores it (returns '').
        def render_inline_dtp(_type, _content, _node)
          ''
        end

        # Render page reference. LATEXBuilder#inline_pageref emits \pageref{id}
        # with the raw id (no escaping).
        def render_inline_pageref(_type, content, node)
          id = node.args.first || content
          "\\pageref{#{id}}"
        end

        # Process index string for hierarchical index entries (mendex/upmendex)
        # This is a simplified version of LATEXBuilder's index method (latexbuilder.rb:1406-1427)
        def process_index(str)
          # Split by <<>> delimiter for hierarchical index entries
          parts = str.split('<<>>')

          # Process each part and format for mendex
          formatted_parts = parts.map { |item| format_index_item(item) }

          # Join hierarchical parts with '!' for mendex/upmendex
          formatted_parts.join('!')
        end

        # Format a single index item for mendex/upmendex
        def format_index_item(item)
          index_db = @ctx.index_db
          # Match LATEXBuilder#index: a "key@display" entry is only produced when
          # there is a real sort key -- a dictionary reading, or a MeCab-derived
          # yomi for Japanese. Without MeCab (and no dictionary entry), Japanese
          # terms are treated like ASCII: just the term, no "@".
          if ascii_only?(item) || (@ctx.index_mecab.nil? && !(index_db && index_db[item]))
            format_ascii_index_item(item)
          else
            format_japanese_index_item(item)
          end
        end

        # Check if string contains only ASCII characters
        def ascii_only?(str)
          str =~ /\A[[:ascii:]]+\Z/
        end

        # Format ASCII-only index item
        def format_ascii_index_item(item)
          escaped_item = escape(item)
          mendex_escaped = escape_index(escaped_item)

          # If no escaping was needed, just return the item
          return item if mendex_escaped == item

          # Generate key@display format for proper sorting like LATEXBuilder (latexbuilder.rb:1418)
          "#{escape_mendex_key(escape_index(item))}@#{escape_mendex_display(mendex_escaped)}"
        end

        # Format Japanese (non-ASCII) index item with yomi reading
        def format_japanese_index_item(item)
          # Check dictionary first like LATEXBuilder (latexbuilder.rb:1411-1412)
          index_db = @ctx.index_db
          yomi = if index_db && index_db[item]
                   index_db[item]
                 else
                   # Generate yomi using MeCab like LATEXBuilder (latexbuilder.rb:1421-1422)
                   generate_yomi(item)
                 end
          escaped_item = escape(item)
          "#{escape_mendex_key(escape_index(yomi))}@#{escape_mendex_display(escape_index(escaped_item))}"
        end

        # Generate yomi (reading) for Japanese text using MeCab + NKF like LATEXBuilder (latexbuilder.rb:1421)
        def generate_yomi(text)
          # If MeCab is available, use it to parse and generate reading
          index_mecab = @ctx.index_mecab
          if index_mecab
            require 'nkf'
            NKF.nkf('-w --hiragana', index_mecab.parse(text).force_encoding('UTF-8').chomp)
          else
            # Fallback: use the original text as-is if MeCab is unavailable
            text
          end
        rescue LoadError, ArgumentError, TypeError, RuntimeError
          # Fallback: use the original text as-is if processing fails
          text
        end

        # Render keyword notation
        def render_inline_kw(_type, content, node)
          if node.args.length >= 2
            term = escape(node.args[0])
            description = escape(node.args[1])
            "\\reviewkw{#{term}}（#{description}）"
          else
            "\\reviewkw{#{content}}"
          end
        end

        # Render ruby notation
        def render_inline_ruby(_type, content, node)
          if node.args.length >= 2
            base_text = escape(node.args[0])
            ruby_text = escape(node.args[1])
            "\\ruby{#{base_text}}{#{ruby_text}}"
          else
            content
          end
        end

        # Render icon
        def render_inline_icon(_type, content, node)
          return content unless node.args.first

          icon_id = node.args.first
          # Path resolved at compile time and stamped on this inline node.
          image_path = node.image_path

          if image_path
            command = review_version2? ? 'includegraphics' : 'reviewicon'
            "\\#{command}{#{image_path}}"
          else
            "\\verb|--[[path = #{icon_id} (not exist)]]--|"
          end
        end

        # Render ami notation
        def render_inline_ami(_type, content, _node)
          "\\reviewami{#{content}}"
        end

        # Render bou notation
        def render_inline_bou(_type, content, _node)
          # Boudou (emphasis)
          "\\reviewbou{#{content}}"
        end

        # Render tcy notation (tate-chu-yoko: horizontal-in-vertical text)
        def render_inline_tcy(_type, content, _node)
          # Tate-chu-yoko (縦中横) for vertical typesetting
          "\\reviewtcy{#{content}}"
        end

        # Render balloon notation
        def render_inline_balloon(_type, content, _node)
          # Balloon annotation - content contains the balloon text
          "\\reviewballoon{#{content}}"
        end

        # Render mathematical expression
        def render_inline_m(_type, content, node)
          # Mathematical expressions - don't escape content. Version 2 pads
          # them with spaces (LATEXBuilder#inline_m).
          math = "$#{node.args.first || content}$"
          review_version2? ? " #{math} " : math
        end

        # Render superscript
        def render_inline_sup(_type, content, _node)
          "\\textsuperscript{#{content}}"
        end

        # Render subscript
        def render_inline_sub(_type, content, _node)
          "\\textsubscript{#{content}}"
        end

        # Render strikethrough
        def render_inline_del(_type, content, _node)
          "\\reviewstrike{#{content}}"
        end

        # Render strikethrough (alias)
        def render_inline_strike(type, content, node)
          render_inline_del(type, content, node)
        end

        # Render insert
        def render_inline_ins(_type, content, _node)
          "\\reviewinsert{#{content}}"
        end

        # Render insert (alias)
        def render_inline_insert(type, content, node)
          render_inline_ins(type, content, node)
        end

        # Render unicode character.
        #
        # LATEXBuilder#inline_uchar branches on @texcompiler, but that ivar is
        # NEVER assigned on the builder (only PDFMaker sets @texcompiler on
        # itself, a different object), so it is always nil and the platex \UTF
        # branch is dead: the builder always passes the codepoint through as a
        # literal Unicode character. Match that (config['texcommand'] does not
        # reach the builder's @texcompiler, so keying on it here diverged).
        def render_inline_uchar(_type, content, node)
          if node.args.first
            [node.args.first.to_i(16)].pack('U')
          else
            content
          end
        end

        # Render line break
        def render_inline_br(_type, _content, _node)
          "\\\\\n"
        end

        # Render word expansion
        def render_inline_w(_type, content, _node)
          # Word expansion - pass through content
          content
        end

        # Render word expansion (bold)
        def render_inline_wb(type, content, node)
          # Builder#inline_wb is inline_b applied to the word
          render_inline_b(type, content, node)
        end

        # Render raw content
        def render_inline_raw(_type, _content, node)
          node.targeted_for?('latex') ? (node.content || '') : ''
        end

        # Render embedded content
        def render_inline_embed(_type, _content, node)
          node.targeted_for?('latex') ? (node.content || '') : ''
        end

        # Render label reference
        def render_inline_labelref(_type, content, node)
          # Use resolved content from ReferenceResolver if available,
          # otherwise fall back to legacy behavior
          if content && !content.empty?
            "\\textbf{#{escape(content)}}"
          elsif node.args.first
            ref_id = node.args.first
            "\\ref{#{escape(ref_id)}}"
          else
            ''
          end
        end

        # Render reference (same as labelref)
        def render_inline_ref(type, content, node)
          render_inline_labelref(type, content, node)
        end

        # Render inline comment
        def render_inline_comment(_type, content, _node)
          if @ctx.draft_mode?
            "\\pdfcomment{#{escape(content)}}"
          else
            ''
          end
        end

        # Render column reference
        def render_inline_column(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          column_number = data.item_number
          chapter_id = data.chapter_id || @render_context.chapter_id
          column_label = "column:#{chapter_id}:#{column_number}"

          # Render caption with inline markup
          compiled_caption = if data.caption_node
                               @ctx.render_caption_inline(data.caption_node)
                             else
                               data.caption_text
                             end
          column_text = @ctx.text_formatter.format_column_label(compiled_caption)
          "\\reviewcolumnref{#{column_text}}{#{column_label}}"
        end

        # Render endnote
        def render_inline_endnote(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          # LATEXBuilder#inline_endnote emits \endnote{compile_inline(content)}:
          # the content is inline-compiled (so @<b>{…}, @<fn>{…} etc. are
          # processed) and stripped. Render the parsed caption_node rather than
          # escaping the plain caption_text (which dropped inline markup).
          endnote_content = if data.caption_node
                              @ctx.render_children(data.caption_node).strip
                            else
                              escape((data.caption_text || '').strip)
                            end
          "\\endnote{#{endnote_content}}"
        end

        # Render title reference (@<title>{chapter_id})
        def render_inline_title(_type, _content, node)
          ref_node = resolved_reference_node(node)

          data = ref_node.resolved_data
          title = data.chapter_title || ''
          if @ctx.chapter_link_enabled?
            "\\reviewchapref{#{escape(title)}}{chap:#{data.item_id}}"
          else
            escape(title)
          end
        end
      end
    end
  end
end
