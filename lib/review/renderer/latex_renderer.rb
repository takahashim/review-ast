# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/caption_node'
require 'review/ast/table_column_width_parser'
require 'review/latexutils'
require 'review/sec_counter'
require 'review/i18n'
require 'review/textutils'
require_relative 'base'
require_relative 'rendering_context'
require_relative 'latex/inline_context'
require_relative 'latex/inline_element_handler'

module ReVIEW
  module Renderer
    class LatexRenderer < Base
      include ReVIEW::LaTeXUtils
      include ReVIEW::TextUtils

      attr_reader :chapter, :book, :rendering_context

      def initialize(chapter)
        super

        # For AST rendering, we need to set up indexing properly
        # The indexing will be done when we process the AST
        @ast_indexer = nil
        @ast_compiler = nil
        @list_structure_normalizer = nil

        I18n.setup(config['language'] || 'ja')

        # Initialize LaTeX character escaping
        initialize_metachars(config['texcommand'])

        # Initialize section counter like LATEXBuilder
        @sec_counter = SecCounter.new(5, @chapter) if @chapter

        # Initialize RenderingContext for cleaner state management
        @rendering_context = RenderingContext.new(:document)

        # Footnote ids used inside a moving argument (heading/caption/table/…),
        # which therefore need a deferred \footnotetext emitted at the //footnote
        # DEFINITION -- mirroring LATEXBuilder's @foottext (set by inline_fn,
        # consumed by footnote). Emitting there rather than right after the
        # heading keeps the footnote on the builder's page even across a break.
        @deferred_footnotetext_ids = {}

        # Initialize LaTeX-specific inline context and inline element handler
        @inline_context = Latex::InlineContext.new(
          config: config,
          book: book,
          chapter: chapter,
          renderer: self
        )
        @inline_element_handler = Latex::InlineElementHandler.new(@inline_context)
      end

      # Format type for this renderer
      # @return [Symbol] Format type :latex
      def format_type
        :latex
      end

      def visit_document(node)
        # Generate content with proper separation between document-level elements
        content = render_document_children(node)

        # Wrap Part documents with reviewpart environment
        if should_wrap_part_with_reviewpart?
          content = "\\begin{reviewpart}\n" + content + "\\end{reviewpart}\n"
        end

        # Add any remaining collected footnotetext commands
        if @rendering_context.footnote_collector.any?
          content += generate_footnotetext_from_collector(@rendering_context.footnote_collector)
          @rendering_context.footnote_collector.clear
        end

        # Ensure content ends with single newline if it contains content
        # Remove all trailing newlines and add exactly one back
        if content && !content.empty?
          content.sub(/\n+\z/, '') + "\n"
        else
          content || ''
        end
      end

      def visit_headline(node)
        level = node.level

        # nodisp has no *visible* heading -- only a TOC entry. Its caption is a
        # non-moving argument there, so a footnote is a plain \footnote and no
        # \footnotetext is emitted (matching LATEXBuilder). Render it in the
        # normal context and return, before the :heading footnote collection.
        if node.nodisp?
          return generate_toc_entry(level, node.caption_node ? render_children(node.caption_node) : nil)
        end

        # A heading is a LaTeX moving argument, so a footnote in the caption must
        # become \protect\footnotemark{} + a deferred \footnotetext (matching
        # LATEXBuilder, which sets @doc_status[:caption] here). Render the caption
        # in a :heading context and collect any footnotes to flush afterwards.
        caption_collector = nil
        caption =
          if node.caption_node
            @rendering_context.with_child_context(:heading) do |heading_context|
              rendered = render_children_with_context(node.caption_node, heading_context)
              caption_collector = heading_context.footnote_collector
              rendered
            end
          end

        body = build_headline_body(node, level, caption)
        append_footnotetext_from_collector(body, caption_collector)
      end

      # Build the heading's LaTeX (without the trailing \footnotetext, which the
      # caller appends). Split out so the footnote flush wraps every path.
      def build_headline_body(node, level, caption)
        # Handle special headline options (nonum, notoc).
        # These do NOT increment the section counter (matching LATEXBuilder behavior).
        # nodisp is handled earlier in visit_headline (no visible heading).
        if node.nonum?
          # nonum: Unnumbered section that appears in TOC
          return generate_nonum_headline(level, caption, node)
        elsif node.notoc?
          # notoc: Unnumbered section that does NOT appear in TOC
          return generate_notoc_headline(level, caption, node)
        end

        # Update section counter like LATEXBuilder (only for regular numbered headlines)
        if @sec_counter
          @sec_counter.inc(level)
        end

        # Regular headline processing
        section_command = headline_name(level)

        # Format with exact newlines like LATEXBuilder to match expected format
        result = []
        result << "\\#{section_command}{#{caption}}"

        # Add \addcontentsline for unnumbered sections within toclevel
        # Match LATEXBuilder logic: only add to TOC if level is within toclevel
        if (level > config['secnolevel'] || (@chapter.number.to_s.empty? && level > 1)) &&
           level <= config['toclevel'].to_i
          result << "\\addcontentsline{toc}{#{get_base_section_name(level)}}{#{headline_toc_caption(node, caption)}}"
        end

        # Generate labels like LATEXBuilder - add both automatic and custom labels
        if level == 1 && @chapter
          result << "\\label{chap:#{@chapter.id}}"
        elsif @sec_counter && level >= 2
          # Generate section labels like LATEXBuilder (sec:x-y format)
          anchor = @sec_counter.anchor(level)
          result << "\\label{sec:#{anchor}}"
          # Add custom label if specified (only for level > 1, matching LATEXBuilder)
          if node.label && !node.label.empty?
            result << "\\label{#{escape(node.label)}}"
          end
        end

        result.join("\n") + "\n\n"
      end

      # The caption for a \addcontentsline TOC entry. LATEXBuilder resets
      # @doc_status[:caption] before the TOC line, so a footnote there is a plain
      # \footnote (not \footnotemark). Re-render outside the :heading context to
      # reproduce that; falls back to the heading caption when there is no
      # caption node.
      def headline_toc_caption(node, caption)
        return caption unless node.caption_node

        render_children(node.caption_node)
      end

      def visit_paragraph(node)
        content = render_children(node)

        # Join the paragraph's source lines like LATEXBuilder. Two triggers:
        #  - inside a :block wrapper (//quote, //lead, ...), latex_block always
        #    joins via split_paragraph (join ""); at an ASCII boundary that "" is
        #    a real DVI difference from the renderer's default "\n";
        #  - with join_lines_by_lang on, LATEXBuilder#paragraph joins ordinary
        #    paragraphs via join_lines_to_paragraph. At an ASCII->Japanese
        #    boundary the builder inserts no space while a raw "\n" typesets as
        #    one, so this too is a real DVI difference.
        # join_paragraph_lines honors join_lines_by_lang for how it joins.
        if block_wrapper_paragraph?(node) || config['join_lines_by_lang']
          content = join_paragraph_lines(content)
        end

        # @<br>{} renders to "\\\n"; when it sits at the end of a source line,
        # the preserved source newline turns it into "\\\n\n", i.e. a forced
        # break followed by a blank line (a spurious empty paragraph, ~0.95pt of
        # extra vertical space). A paragraph never contains a real blank line, so
        # collapse any blank line that immediately follows a forced break, to
        # match LATEXBuilder.
        content = content.gsub(/\\\\\n\n+/, "\\\\\\\\\n")

        # Check for noindent attribute
        if node.noindent?
          # Add \noindent command like LATEXBuilder
          "\\noindent\n#{content}\n\n"
        else
          # Add double newline for paragraph separation (LaTeX standard)
          "#{content}\n\n"
        end
      end

      def visit_text(node)
        content = node.content.to_s
        # Inside a highlight (listings) code block, LATEXBuilder treats
        # list/emlist/listnum/emlistnum/cmd/source as "non-escaped commands"
        # (Compiler#non_escaped_commands): the block's plain text is emitted raw,
        # while inline ops are still compiled. Mirror that here -- but only for the
        # code line's direct text; inline arguments are re-escaped in visit_inline.
        return content if @nonescape_code

        # Preserve newlines and escape content properly
        # Don't escape newlines so they are preserved in the output
        escape(content)
      end

      # Override to keep inline-op arguments escaped even inside a non-escaped
      # code block: LATEXBuilder escapes @<b>{...} arguments via compile_inline
      # regardless of highlight mode, so only the surrounding block text is raw.
      def visit_inline(node)
        saved = @nonescape_code
        @nonescape_code = false
        content = render_children(node)
        @nonescape_code = saved
        render_inline_element(node.inline_type, content, node)
      end

      # True when config['highlight']['latex'] is set (any value). LATEXBuilder
      # then routes list/emlist/... through the non-escaped-command path.
      def highlight?
        h = config['highlight']
        h && h['latex']
      end

      # True when highlight is specifically the LaTeX "listings" backend, which
      # renders code via the review*lst environments instead of review* verbatim.
      def highlight_listings?
        h = config['highlight']
        h && h['latex'] == 'listings'
      end

      # Block types whose content LATEXBuilder renders via latex_block, i.e. it
      # joins each paragraph's lines with split_paragraph rather than keeping the
      # source newlines. A paragraph directly inside one of these is a "block
      # wrapper paragraph". (//box is excluded: it has its own line-based path.)
      BLOCK_WRAPPER_TYPES = %i[quote lead blockquote read centering flushright address talk].freeze

      # True when this paragraph sits directly inside a :block wrapper, so its
      # lines must be joined like LATEXBuilder's latex_block. Read straight from
      # the AST (the paragraph's parent) -- no renderer-side state needed.
      def block_wrapper_paragraph?(node)
        parent = node.parent
        parent.is_a?(ReVIEW::AST::BlockNode) && BLOCK_WRAPPER_TYPES.include?(parent.block_type)
      end

      # Join an array of already-rendered source lines the way LATEXBuilder does
      # for dd()/ol_item()/ul_item(): "\n" by default, or a language-aware space
      # (join_lines_to_paragraph) when join_lines_by_lang is on.
      def join_source_lines(lines)
        return lines.join("\n") unless config['join_lines_by_lang']

        lang = config['language'] || 'ja'
        result = +''
        lines.each do |line|
          result << ' ' if !result.empty? && add_space?(result[-1], line[0], lang, true)
          result << line
        end
        result
      end

      # Join a paragraph's source lines the way LATEXBuilder's split_paragraph /
      # join_lines_to_paragraph does: with join_lines_by_lang off, drop the
      # newlines (""); with it on, insert a language-aware space (add_space?).
      def join_paragraph_lines(content)
        return content unless content.include?("\n")

        if config['join_lines_by_lang']
          lines = content.split("\n")
          lang = config['language'] || 'ja'
          0.upto(lines.size - 2) do |n|
            lines[n] += ' ' if add_space?(lines[n], lines[n + 1], lang, true)
          end
          lines.join
        else
          content.gsub(/\n+/, '')
        end
      end

      # Process caption for code blocks with proper context management
      # @param node [CodeBlockNode] The code block node
      # @return [Array<String, Object>] [caption, caption_collector]
      def process_code_block_caption(node)
        caption = nil
        caption_collector = nil

        if node.caption_node
          @rendering_context.with_child_context(:caption) do |caption_context|
            caption = render_children_with_context(node.caption_node, caption_context)
            caption_collector = caption_context.footnote_collector
          end
        end

        [caption, caption_collector]
      end

      # Add footnotetext commands from collector to result
      # @param result [String] The rendered result
      # @param caption_collector [Object] The footnote collector
      # @return [String] Result with footnotetext commands appended
      def append_footnotetext_from_collector(result, caption_collector)
        if caption_collector && caption_collector.any?
          result += generate_footnotetext_from_collector(caption_collector)
          caption_collector.clear
        end
        result
      end

      # Visit list code block
      def visit_code_block_list(node)
        return render_code_listings(node, 'reviewlistlst', 'caption', numbered: false) if highlight_listings?

        caption, caption_collector = process_code_block_caption(node)
        content = render_children(node)
        result = visit_list_block(node, content, caption)
        append_footnotetext_from_collector(result, caption_collector)
      end

      # Visit listnum code block (list with line numbers)
      def visit_code_block_listnum(node)
        return render_code_listings(node, 'reviewlistnumlst', 'caption', numbered: true) if highlight_listings?

        caption, caption_collector = process_code_block_caption(node)
        content = render_children(node)
        result = visit_list_block(node, add_line_numbers(content, node), caption)
        append_footnotetext_from_collector(result, caption_collector)
      end

      # Visit emlist code block
      def visit_code_block_emlist(node)
        return render_code_listings(node, 'reviewemlistlst', 'title', numbered: false) if highlight_listings?

        caption, caption_collector = process_code_block_caption(node)
        content = render_children(node)
        result = visit_emlist_block(node, content, caption)
        append_footnotetext_from_collector(result, caption_collector)
      end

      # Visit emlistnum code block (emlist with line numbers)
      def visit_code_block_emlistnum(node)
        return render_code_listings(node, 'reviewemlistnumlst', 'title', numbered: true) if highlight_listings?

        caption, caption_collector = process_code_block_caption(node)
        content = render_children(node)
        result = visit_emlist_block(node, add_line_numbers(content, node), caption)
        append_footnotetext_from_collector(result, caption_collector)
      end

      # Visit cmd code block
      def visit_code_block_cmd(node)
        # //cmd has no lang argument (its first arg is the caption), so
        # LATEXBuilder#cmd passes lang=nil. The AST assigns default_lang 'shell'
        # for HTML highlighting; suppress it here to match the builder's empty
        # language={} option.
        return render_code_listings(node, 'reviewcmdlst', 'title', numbered: false, lang: '') if highlight_listings?

        caption, caption_collector = process_code_block_caption(node)
        content = render_children(node)
        result = visit_cmd_block(node, content, caption)
        append_footnotetext_from_collector(result, caption_collector)
      end

      # Visit source code block
      def visit_code_block_source(node)
        return render_code_listings(node, 'reviewsourcelst', 'title', numbered: false) if highlight_listings?

        caption, caption_collector = process_code_block_caption(node)
        content = render_children(node)
        result = visit_source_block(node, content, caption)
        append_footnotetext_from_collector(result, caption_collector)
      end

      # Render a code block through the LaTeX "listings" backend, matching
      # LATEXBuilder#common_code_block_lst / #make_code_block_args. The body is
      # emitted raw (non-escaped, inline ops still compiled); the caption is
      # inline-compiled into the environment's option arg with NO chapter number
      # prefix (unlike the verbatim path). version-2-only \vspace/\relax hacks are
      # omitted (the comparison harness runs the current spec).
      def render_code_listings(node, env, title, numbered:, lang: node.lang)
        caption_str = node.caption_node ? render_children(node.caption_node) : ''
        first_line_num = numbered ? (node.first_line_num || 1) : 1
        args = make_code_block_lst_args(title, caption_str, lang, first_line_num)

        saved = @nonescape_code
        @nonescape_code = true
        content = render_children(node)
        @nonescape_code = saved
        body = detab_content(content)

        "\\begin{#{env}}[#{args}]\n#{body}\\end{#{env}}\n\n"
      end

      # Build the bracketed option list for a review*lst environment, matching
      # LATEXBuilder#make_code_block_args. title is 'caption' (list/listnum) or
      # 'title' (emlist/cmd/source); the latter drops an empty caption entirely.
      def make_code_block_lst_args(title, caption_str, lang, first_line_num)
        highlight_cfg = config['highlight']
        lexer = (highlight_cfg && highlight_cfg['lang']) || ''
        lexer = lang if lang && !lang.empty?
        args = "language={#{lexer}}"
        unless title == 'title' && caption_str == ''
          args = "#{title}={#{caption_str}},#{args}"
        end
        args = "#{args},firstnumber=#{first_line_num}" if first_line_num != 1
        args
      end

      def visit_code_line(node)
        # Render children (TextNode and InlineNode) to process inline elements
        # properly. Tabs are NOT expanded here: for numbered lists LATEXBuilder
        # detabs *after* prepending the " N: " prefix, so detab happens on the
        # final line in the block wrappers (see detab_content).
        "#{render_children(node)}\n"
      end

      # Expand tabs per line like LATEXBuilder#code_line/#code_line_num, applied
      # to the final code content (after any line-number prefix) so tab stops
      # align exactly as the builder's do.
      def detab_content(text)
        tw = config['tabwidth']
        text.split("\n", -1).map { |line| tw ? detab(line, tw.to_i) : detab(line) }.join("\n")
      end

      def visit_table(node)
        # Process caption with proper context management and collect footnotes
        caption = nil
        caption_collector = nil

        if node.caption_node
          @rendering_context.with_child_context(:caption) do |caption_context|
            caption = render_children_with_context(node.caption_node, caption_context)
            # Save the collector for later processing
            caption_collector = caption_context.footnote_collector
          end
        end

        table_type = node.table_type

        # Handle imgtable specially - it should be rendered as an image
        if table_type == :imgtable
          result = visit_imgtable(node, caption)
          # Add collected footnotetext commands from caption context for imgtable
          if caption_collector && caption_collector.any?
            result += generate_footnotetext_from_collector(caption_collector)
            caption_collector.clear
          end
          return result
        end

        # Process table content with table context
        table_context = nil
        table_content = @rendering_context.with_child_context(:table) do |ctx|
          table_context = ctx

          # Derive the LaTeX column spec from the table's source //tsize at render
          # time (the shared node keeps only the raw spec); default when there is
          # no applicable //tsize.
          col_spec = latex_col_spec(node)

          # Get all rows for processing
          all_rows = node.header_rows + node.body_rows

          result = []

          # Only output \begin{table} if caption is present (like LATEXBuilder)
          if caption.present?
            result << if node.id?
                        "\\begin{table}%%#{node.id}"
                      else
                        '\\begin{table}%%'
                      end
          end

          # A caption is placed above or below the table per caption_position
          # (caption_top?('table')), matching LATEXBuilder#table (which moves
          # table_header around the tabular). The \label rides with the caption.
          label = nil
          if node.id?
            # Don't escape underscores in labels - they're allowed in LaTeX label names
            label = @chapter ? "\\label{table:#{@chapter.id}:#{node.id}}" : "\\label{table:test:#{node.id}}"
          end

          header = []
          if caption.present?
            # emtable uses reviewtablecaption* (with asterisk)
            caption_command = table_type == :emtable ? 'reviewtablecaption*' : 'reviewtablecaption'
            header << "\\#{caption_command}{#{caption}}"
            header << label if label
          end

          result.concat(header) if caption_top?('table')
          # A caption-less table emits NO label: LATEXBuilder#table only reaches
          # table_header (which puts the \label) when the caption is present, so a
          # caption-less table has neither a \begin{table} float nor a \label.
          # (@<table> refs embed the number directly, so they still resolve to the
          # same visible text as the builder's.)

          result << "\\begin{reviewtable}{#{col_spec}}"
          result << '\\hline'

          # Process all rows using visitor pattern with table context
          all_rows.each do |row|
            row_content = visit_with_context(row, table_context)
            result << "#{row_content} \\\\  \\hline"
          end

          result << '\\end{reviewtable}'

          result.concat(header) unless caption_top?('table')

          # Only output \end{table} if caption is present (like LATEXBuilder)
          if caption.present?
            result << '\\end{table}'
          end

          result.join("\n") + "\n"
        end

        # Add collected footnotetext commands from caption context
        if caption_collector && caption_collector.any?
          table_content += generate_footnotetext_from_collector(caption_collector)
          caption_collector.clear
        end

        # Add collected footnotetext commands from table context
        if table_context && table_context.footnote_collector.any?
          table_content += generate_footnotetext_from_collector(table_context.footnote_collector)
          table_context.footnote_collector.clear
        end

        table_content.chomp + "\n\n"
      end

      def visit_imgtable(node, caption)
        # imgtable is rendered as table with image inside (like LATEXBuilder)
        result = []

        # Path resolved at compile time and stamped on the node; nil = unbound.
        unless node.id? && node.image_path
          # Not bound: emit the same dummy image as a regular //image (path
          # placeholder + label + caption), matching LATEXBuilder#image_dummy.
          return render_dummy_image(node, caption, double_escape_id: false, with_label: true)
        end

        image_path = node.image_path

        # Generate table structure with image like LATEXBuilder
        # Start table environment if caption exists (line 911)
        if caption && !caption.empty?
          result << "\\begin{table}[h]%%#{node.id}"

          # Add caption and label at top if caption_top?
          if caption_top?('table')
            result << "\\reviewimgtablecaption{#{caption}}"
          end

          # Add table label (line 919) - this needs table index
          begin
            result << "\\label{table:#{@chapter.id}:#{node.id}}"
          rescue ReVIEW::KeyError
            # If table lookup fails, still continue
          end
        end

        # Add image inside reviewimage environment (lines 937-949)
        result << "\\begin{reviewimage}%%#{node.id}"

        # Parse metric option like LATEXBuilder
        metrics = parse_metric('latex', node.metric)
        command = 'reviewincludegraphics'

        # Use metric if provided, otherwise use default width
        result << if metrics.present?
                    "\\#{command}[#{metrics}]{#{image_path}}"
                  else
                    "\\#{command}[width=\\maxwidth]{#{image_path}}"
                  end

        result << '\\end{reviewimage}'

        # Close table if caption exists
        if caption.present?
          # Add caption at bottom if not caption_top?
          unless caption_top?('table')
            result << "\\reviewimgtablecaption{#{caption}}"
          end

          result << '\\end{table}'
        end

        result.join("\n") + "\n\n"
      end

      def visit_table_row(node)
        # Process all cells in the row using visitor pattern while maintaining table context
        # Note: table context should already be set by visit_table
        cells = node.children.map.with_index do |cell, col_index|
          visit_table_cell_with_index(cell, col_index)
        end
        cells.join(' & ')
      end

      def visit_table_cell(node)
        # Fallback method if called without index
        visit_table_cell_with_index(node, 0)
      end

      # The per-column widths of the table that owns this cell, via the AST parent
      # chain (cell -> TableRowNode -> TableNode). Returns nil when the chain
      # isn't a table (then the caller defaults each column to 'l').
      def table_cellwidths_for(cell_node)
        table = cell_node.parent&.parent
        return nil unless table.is_a?(ReVIEW::AST::TableNode)

        latex_cellwidths(table)
      end

      # LaTeX column spec (e.g. "|p{10mm}|l|") derived from the table's source
      # //tsize; all-left default when there is no //tsize for LaTeX.
      def latex_col_spec(table)
        widths = latex_column_widths(table)
        widths ? widths.col_spec : ('|' + ('l|' * table.column_count))
      end

      # Per-column LaTeX cell widths (e.g. ["p{10mm}", "l"]) derived from //tsize;
      # all-left default otherwise.
      def latex_cellwidths(table)
        widths = latex_column_widths(table)
        widths ? widths.cellwidth : (['l'] * table.column_count)
      end

      # Parse the LaTeX-applicable //tsize into a column-width Result, or nil when
      # the table has no //tsize targeting LaTeX.
      def latex_column_widths(table)
        value = table.tsize_value_for('latex')
        return nil unless value

        AST::TableColumnWidthParser.new(value, table.column_count).parse
      end

      def visit_table_cell_with_index(node, col_index)
        # Process cell content while maintaining table context to collect footnotes
        # Note: table context should already be set by visit_table
        content = render_children(node)

        # Get cellwidth for this column straight from the owning TableNode via the
        # parent chain (cell -> row -> table), rather than a renderer ivar that
        # would otherwise persist stale between tables.
        cellwidths = table_cellwidths_for(node)
        cellwidth = cellwidths && cellwidths[col_index] ? cellwidths[col_index] : 'l'

        # Check if content contains line breaks (from @<br>{})
        # Like LATEXBuilder: use \newline{} for fixed-width cells (p{...}), otherwise use \shortstack
        if /\\\\/.match?(content)
          # Check if cellwidth is fixed-width format (contains `{`)
          if AST::TableColumnWidthParser.fixed_width?(cellwidth)
            # Fixed-width cell: replace \\\n with \newline{}
            content = content.gsub("\\\\\n", '\\newline{}')
            if node.cell_type == :th
              "\\reviewth{#{content}}"
            else
              content
            end
          elsif node.cell_type == :th
            # Non-fixed-width cell: use \shortstack[l] like LATEXBuilder does
            "\\reviewth{\\shortstack[l]{#{content}}}"
          else
            "\\shortstack[l]{#{content}}"
          end
        elsif node.cell_type == :th
          # No line breaks - standard formatting
          "\\reviewth{#{content}}"
        else
          content
        end
      end

      def visit_image(node)
        # Process caption with proper context management
        caption = nil
        caption_collector = nil

        if node.caption_node
          @rendering_context.with_child_context(:caption) do |caption_context|
            caption = render_children_with_context(node.caption_node, caption_context)
            # Save the collector for later processing
            caption_collector = caption_context.footnote_collector
          end
        end

        image_type = node.image_type

        result = case image_type
                 when :indepimage, :numberlessimage
                   visit_indepimage(node, caption)
                 else
                   visit_regular_image(node, caption)
                 end

        # Add collected footnotetext commands from caption context
        if caption_collector && caption_collector.any?
          result += generate_footnotetext_from_collector(caption_collector)
          caption_collector.clear
        end

        result
      end

      def visit_regular_image(node, caption)
        # Path resolved at compile time and stamped on the node (no chapter index).
        image_path = node.image_path

        if image_path
          render_existing_image(node, image_path, caption, with_label: true)
        else
          render_dummy_image(node, caption, double_escape_id: false, with_label: true)
        end
      end

      def visit_indepimage(node, caption)
        # Path resolved at compile time and stamped on the node (no chapter index).
        image_path = node.image_path

        if image_path
          render_existing_indepimage(node, image_path, caption)
        else
          render_dummy_image(node, caption, double_escape_id: true, with_label: false)
        end
      end

      def visit_list(node)
        case node.list_type
        when :ul
          # Unordered list - generate LaTeX itemize environment
          items = node.children.map { |item| "\\item #{render_list_item_content(item)}" }.join("\n")
          "\n\\begin{itemize}\n#{items}\n\\end{itemize}\n\n"
        when :ol
          # Ordered list - generate LaTeX enumerate environment
          items = node.children.map { |item| "\\item #{render_list_item_content(item)}" }.join("\n")

          # Check if this list has start_number
          if node.start_number && node.start_number != 1
            # Generate enumerate with setcounter for non-default start
            start_num = node.start_number - 1 # LaTeX counter is 0-based
            "\n\\begin{enumerate}\n\\setcounter{enumi}{#{start_num}}\n#{items}\n\\end{enumerate}\n\n"
          else
            "\n\\begin{enumerate}\n#{items}\n\\end{enumerate}\n\n"
          end
        when :dl
          # Definition list - generate LaTeX description environment like LATEXBuilder
          visit_definition_list(node)
        else
          raise NotImplementedError, "Unsupported list type: #{node.list_type}"
        end
      end

      def visit_list_item(node)
        raise NotImplementedError, 'List item processing should be handled by visit_list, not as standalone items'
      end

      # Render a list item's children, reinserting the source newline between
      # continuation lines (LATEXBuilder joins item lines with "\n"; an ASCII
      # boundary then becomes an inter-word space). source_line_breaks holds the
      # child indices where a line break precedes the child.
      def render_list_item_content(item)
        breaks = item.respond_to?(:source_line_breaks) ? item.source_line_breaks : nil
        return render_children(item) if breaks.nil? || breaks.empty?

        # Insert the line separator only at a recorded break (never inside a
        # nested list a child may render). LATEXBuilder's ol_item/ul_item joins
        # item lines with "\n" by default, or via join_lines_to_paragraph (a
        # language-aware space) when join_lines_by_lang is on.
        lang_join = config['join_lines_by_lang']
        lang = config['language'] || 'ja'
        result = +''
        item.children.each_with_index do |child, i|
          rendered = visit(child).to_s
          if breaks.include?(i) && !result.empty?
            result << if lang_join
                        add_space?(result[-1], rendered[0], lang, true) ? ' ' : ''
                      else
                        "\n"
                      end
          end
          result << rendered
        end
        result
      end

      # Visit quote block
      def visit_block_quote(node)
        content = render_children(node)
        result = "\n\\begin{quote}\n#{content.chomp}\\end{quote}\n\n"
        apply_noindent_if_needed(node, result)
      end

      # Visit lead block (lead paragraph)
      def visit_block_lead(node)
        content = render_children(node)
        result = "\n\\begin{quotation}\n#{content.chomp}\\end{quotation}\n\n"
        apply_noindent_if_needed(node, result)
      end

      # Visit texequation block (mathematical equation)
      def visit_block_texequation(node)
        content = render_children(node)
        # Handle mathematical equation blocks - output content directly
        # without LaTeX environment wrapping since content is raw LaTeX math
        content.strip.empty? ? '' : "\n#{content}\n\n"
      end

      # Visit comment block
      def visit_block_comment(node)
        # Handle comment blocks - only output in draft mode
        visit_comment_block(node)
      end

      # Visit centering block (center alignment)
      def visit_block_centering(node)
        content = render_children(node)
        "\n\\begin{center}\n#{content.chomp}\\end{center}\n\n"
      end

      # Visit flushright block (right alignment)
      def visit_block_flushright(node)
        content = render_children(node)
        "\n\\begin{flushright}\n#{content.chomp}\\end{flushright}\n\n"
      end

      # Visit address block (similar to flushright)
      def visit_block_address(node)
        content = render_children(node)
        "\n\\begin{flushright}\n#{content.chomp}\\end{flushright}\n\n"
      end

      # Visit talk block (dialog/conversation)
      def visit_block_talk(node)
        content = render_children(node)
        "#{content}\n"
      end

      # Visit read block (reading material)
      def visit_block_read(node)
        content = render_children(node)
        "\n\\begin{quotation}\n#{content.chomp}\\end{quotation}\n\n"
      end

      # Visit blockquote block
      def visit_block_blockquote(node)
        content = render_children(node)
        "\n\\begin{quote}\n#{content.chomp}\\end{quote}\n\n"
      end

      # Visit box block. Like LATEXBuilder#box: an optional \reviewboxcaption
      # followed by the (inline-processed, detabbed) lines inside reviewbox.
      # Each child is a ParagraphNode holding one source line (empty lines kept).
      def visit_block_box(node)
        result = []
        if node.caption_node
          caption = render_children(node.caption_node)
          result << "\\reviewboxcaption{#{caption}}" unless caption.empty?
        end
        result << '\\begin{reviewbox}'
        node.children.each { |line_node| result << detab_content(render_children(line_node)) }
        result << '\\end{reviewbox}'
        "\n" + result.join("\n") + "\n\n"
      end

      # Visit printendnotes block (print collected endnotes)
      def visit_block_printendnotes(_node)
        "\n\\theendnotes\n\n"
      end

      # Visit label block (create label)
      def visit_block_label(node)
        if node.args.first
          label_id = node.args.first
          "\\label{#{escape(label_id)}}\n"
        else
          ''
        end
      end

      # Visit blankline block (control command)
      def visit_block_blankline(_node)
        "\\par\\vspace{\\baselineskip}\\par\n\n"
      end

      # Visit pagebreak block (control command)
      def visit_block_pagebreak(_node)
        # Emit \pagebreak like LATEXBuilder#pagebreak; the stub dropped it.
        "\\pagebreak\n\n"
      end

      # Visit endnote block (control command)
      def visit_block_endnote(_node)
        ''
      end

      # Visit hr block (control command)
      def visit_block_hr(_node)
        # Emit \hrule like LATEXBuilder#hr; the stub dropped it.
        "\\hrule\n\n"
      end

      # Visit bpo block (control command)
      def visit_block_bpo(_node)
        ''
      end

      # Visit parasep block (control command)
      def visit_block_parasep(_node)
        # Emit \parasep like LATEXBuilder#parasep; the stub dropped it.
        "\\parasep\n\n"
      end

      # Visit bibpaper block (bibliography paper)
      def visit_block_bibpaper(node)
        visit_bibpaper(node)
      end

      def visit_minicolumn(node)
        # Process caption with proper context management and collect footnotes
        caption = nil
        caption_collector = nil

        if node.caption_node
          @rendering_context.with_child_context(:caption) do |caption_context|
            caption = render_children_with_context(node.caption_node, caption_context)
            # Save the collector for later processing
            caption_collector = caption_context.footnote_collector
          end
        end

        content = join_block_children(node)

        env_name = case node.minicolumn_type.to_s
                   when 'note'
                     'reviewnote'
                   when 'memo'
                     'reviewmemo'
                   when 'tip'
                     'reviewtip'
                   when 'info'
                     'reviewinfo'
                   when 'warning'
                     'reviewwarning'
                   when 'important'
                     'reviewimportant'
                   when 'caution'
                     'reviewcaution'
                   when 'notice'
                     'reviewnotice'
                   else
                     'reviewcolumn'
                   end

        result = []
        result << if caption && !caption.empty?
                    "\\begin{#{env_name}}[#{caption}]"
                  else
                    "\\begin{#{env_name}}"
                  end
        result << '' # blank line after begin
        result << content.chomp
        result << "\\end{#{env_name}}"

        # Emit the block, then any \footnotetext from the caption, then the
        # trailing blank line. This matches LATEXBuilder, which places
        # \footnotetext immediately after \end{...} (no blank in between) and
        # the paragraph break after it. When there is no footnotetext this is
        # equivalent to "...\end{...}\n\n".
        output = result.join("\n") + "\n"

        if caption_collector && caption_collector.any?
          output += generate_footnotetext_from_collector(caption_collector)
          caption_collector.clear
        end

        output + "\n"
      end

      def visit_caption(node)
        render_children(node)
      end

      def visit_comment_block(node)
        # block comment - only display in draft mode
        return '' unless config['draft']

        content_lines = []

        # add argument if it exists
        if node.args.first&.then { |arg| !arg.empty? }
          content_lines << escape(node.args.first)
        end

        # add body content
        if node.content && !node.content.empty?
          body_content = render_children(node)
          content_lines << body_content unless body_content.empty?
        end

        return '' if content_lines.empty?

        # use pdfcomment macro in LaTeX
        content_str = content_lines.join('\\par ')
        "\\pdfcomment{#{content_str}}\n"
      end

      def visit_column(node)
        # A column caption is a LaTeX moving argument (it rides into the
        # reviewcolumn optional arg AND \addcontentsline), so a footnote there
        # must become \protect\footnotemark{} + a deferred \footnotetext, exactly
        # like a heading. LATEXBuilder sets @doc_status[:caption] around the
        # column caption; mirror it with a footnotetext-requiring :caption
        # context and flush the collected \footnotetext after the column.
        caption = nil
        caption_collector = nil
        if node.caption_node
          @rendering_context.with_child_context(:caption) do |caption_context|
            caption = render_children_with_context(node.caption_node, caption_context)
            caption_collector = caption_context.footnote_collector
          end
        end

        # Generate column label for hypertarget (using auto_id from Compiler)
        column_label = generate_column_label(node, caption)
        hypertarget = "\\hypertarget{#{column_label}}{}"

        # Process column content with :column context to collect footnotes.
        # Use join_block_children (not render_children) so adjacent raw-content
        # blocks (embed/raw) inside the column get the same whitespace treatment
        # as at the document level.
        column_context = nil
        content = @rendering_context.with_child_context(:column) do |ctx|
          column_context = ctx
          old_context = @rendering_context
          @rendering_context = column_context
          begin
            join_block_children(node)
          ensure
            @rendering_context = old_context
          end
        end

        result = []
        result << '' # blank line before column

        # support Re:VIEW Version 3+ format only
        caption_part = caption ? "[#{caption}#{hypertarget}]" : "[#{hypertarget}]"
        result << "\\begin{reviewcolumn}#{caption_part}"

        # Add TOC entry if within toclevel
        if node.level && caption && node.level <= config['toclevel'].to_i
          result << "\\addcontentsline{toc}{#{get_base_section_name(node.level)}}{#{caption}}"
        end

        # Blank line after the header, EXCEPT when the first content block is a
        # raw-content embed (//embed / //raw): LATEXBuilder prints its content
        # right after the \addcontentsline with no blank, so a blank here would be
        # a spurious \par before it (unlike a minicolumn, the column header is not
        # an environment start, so the \par is not absorbed).
        first = node.children.first
        leading_raw_embed = first.is_a?(ReVIEW::AST::EmbedNode) && %i[block raw].include?(first.embed_type)
        result << '' unless leading_raw_embed
        result << content.chomp
        result << '\\end{reviewcolumn}'
        result << '' # blank line after column

        output = result.join("\n") + "\n"

        # Flush the caption's deferred \footnotetext first (its footnote is
        # numbered before any in the body), then the body's.
        output = append_footnotetext_from_collector(output, caption_collector)
        if column_context && column_context.footnote_collector.any?
          output += generate_footnotetext_from_collector(column_context.footnote_collector)
          column_context.footnote_collector.clear
        end

        output
      end

      def visit_embed(node)
        # All embed types now use unified processing
        process_raw_embed(node)
      end

      # Code block type handlers
      def visit_list_block(node, content, caption)
        content = detab_content(content)

        captionstr = nil
        if caption && !caption.empty?
          # Use LATEXBuilder logic for list caption with proper numbering
          if node.id?
            # For list blocks with ID, generate numbered caption like LATEXBuilder.
            # The number is stamped on the node by the Indexer (definition_number),
            # so we don't reach into the legacy @chapter list index here.
            dn = node.definition_number
            raise NotImplementedError, "no such list: #{node.id}" unless dn

            captionstr = "\\reviewlistcaption{#{text_formatter.format_caption('list', dn.chapter_number, dn.number, caption)}}"
          else
            # For list blocks without ID, use simple caption
            captionstr = "\\reviewlistcaption{#{caption}}"
          end
        end

        # LATEXBuilder#common_code_block places the caption above or below the
        # verbatim body per caption_position (caption_top?('list')).
        result = []
        result << '\\begin{reviewlistblock}'
        result << captionstr if captionstr && caption_top?('list')
        result << '\\begin{reviewlist}'
        result << content.chomp
        result << '\\end{reviewlist}'
        result << captionstr if captionstr && !caption_top?('list')
        result << '\\end{reviewlistblock}'
        result.join("\n") + "\n\n"
      end

      def visit_emlist_block(_node, content, caption)
        render_captioned_code_block(content, caption, 'reviewemlistcaption', 'reviewemlist')
      end

      def visit_cmd_block(_node, content, caption)
        render_captioned_code_block(content, caption, 'reviewcmdcaption', 'reviewcmd')
      end

      def visit_source_block(_node, content, caption)
        render_captioned_code_block(content, caption, 'reviewsourcecaption', 'reviewsource')
      end

      # Shared body for the caption-carrying verbatim blocks (emlist/cmd/source).
      # LATEXBuilder#common_code_block places the caption above or below the body
      # per caption_position (caption_top?('list') -- the same key for all three).
      def render_captioned_code_block(content, caption, caption_command, env)
        content = detab_content(content)
        captionstr = "\\#{caption_command}{#{caption}}" if caption && !caption.empty?

        result = []
        result << '\\begin{reviewlistblock}'
        result << captionstr if captionstr && caption_top?('list')
        result << "\\begin{#{env}}"
        result << content.chomp
        result << "\\end{#{env}}"
        result << captionstr if captionstr && !caption_top?('list')
        result << '\\end{reviewlistblock}'
        result.join("\n") + "\n\n"
      end

      def visit_tex_equation(node)
        # Handle LaTeX mathematical equation blocks
        # Output the LaTeX content directly without escaping since it's raw LaTeX
        content = node.content

        result = []
        if node.id?
          # Equation with ID - use reviewequationblock like the traditional
          # compiler. caption_content is already inline-processed/escaped;
          # format_caption (i18n-aware, like the list/image/table captions) must
          # not escape it again -- doing so double-escaped LaTeX metacharacters.
          # The caption goes above or below the equation per caption_position
          # (caption_top?('equation')), matching LATEXBuilder#texequation.
          dn = node.definition_number
          caption_content = node.caption? ? render_children(node.caption_node) : nil
          captionstr = "\\reviewequationcaption{#{text_formatter.format_caption('equation', dn.chapter_number, dn.number, caption_content)}}"
          result << '\\begin{reviewequationblock}'
          result << captionstr if caption_top?('equation')
          result << '\\begin{equation*}'
          result << content
          result << '\\end{equation*}'
          result << captionstr unless caption_top?('equation')
          result << '\\end{reviewequationblock}'
        else
          # Equation without ID - use equation* environment (no numbering)
          result << '\\begin{equation*}'
          result << content
          result << '\\end{equation*}'
        end
        result.join("\n") + "\n\n"
      end

      def visit_bibpaper(node)
        # Extract bibliography arguments
        if node.args.length >= 2
          bib_id = node.args[0]
          # The caption is inline-compiled like LATEXBuilder#bibpaper_header
          # (compile_inline(caption)) -- NOT raw-escaped -- so @<fn>{…}, @<b>{…}
          # etc. in the caption are processed. It is a normal (non-moving) text
          # context, so a footnote there is a plain \footnote.
          bib_caption = node.caption_node ? render_children(node.caption_node) : escape(node.args[1])

          # Process content
          content = render_children(node)

          # Generate bibliography entry like LATEXBuilder
          result = []

          # Header with number and caption. The number is stamped on the node by
          # the Indexer (definition_number); "??" if somehow unindexed.
          bib_number = node.definition_number&.number
          result << "[#{bib_number || '??'}] #{bib_caption}"

          # Add label for cross-references
          result << "\\label{bib:#{escape(bib_id)}}"
          result << ''

          # Add content. The bibpaper body is parsed into paragraph nodes, so
          # render_children already applied the language-aware paragraph joining
          # (join_paragraph_lines) and separated paragraphs with blank lines --
          # matching LATEXBuilder#bibpaper_bibpaper's split_paragraph. (The old
          # split_paragraph(content) call was doubly wrong: it re-split an
          # already-rendered string and relied on pre_paragraph/post_paragraph,
          # which the renderer does not define, crashing under join_lines_by_lang.)
          result << content

          result.join("\n") + "\n"
        else
          raise NotImplementedError, 'Malformed bibpaper block: insufficient arguments'
        end
      end

      # Add line numbers to content like LATEXBuilder does. LATEXBuilder numbers
      # every code line, including a trailing blank line, so we must too.
      def add_line_numbers(content, node = nil)
        # `content` is a concatenation of "line\n" per code line, so it always
        # ends with one artifact newline. split(-1) keeps every field (including
        # genuine blank lines); dropping the final field removes just that
        # artifact. This correctly distinguishes "one blank line" ([""], numbered)
        # from "no lines" ([], not numbered).
        lines = content.split("\n", -1)[0...-1]

        # Use node.first_line_num if set, otherwise start from 1
        start_num = node&.first_line_num || 1

        lines.each_with_index.map { |line, i| sprintf('%2d: %s', start_num + i, line) }.join("\n")
      end

      # Render footnote content for footnotetext
      # This method processes the footnote node's children to properly handle
      # inline markup like @<b>{text} within footnotes
      def render_footnote_content(footnote_node)
        render_children(footnote_node)
      end

      # Record that footnote `id` was used inside a moving argument, so its
      # \footnotetext must be emitted at the //footnote definition (visit_footnote)
      # rather than inline. Called from render_inline_fn via the inline context.
      def defer_footnotetext(id)
        @deferred_footnotetext_ids[id] = true
      end

      # Render inline elements from caption_node
      # @param caption_node [CaptionNode] Caption node to render
      # @return [String] Rendered inline elements
      def render_caption_inline(caption_node)
        caption_node ? render_children(caption_node) : ''
      end

      private

      # Render existing image (for regular //image)
      def render_existing_image(node, image_path, caption, with_label:)
        result = []
        result << if node.id?
                    "\\begin{reviewimage}%%#{node.id}"
                  else
                    '\\begin{reviewimage}'
                  end

        metrics = parse_metric('latex', node.metric)
        command = 'reviewincludegraphics'

        result << if metrics && !metrics.empty?
                    "\\#{command}[#{metrics}]{#{image_path}}"
                  else
                    "\\#{command}[width=\\maxwidth]{#{image_path}}"
                  end

        result << "\\reviewimagecaption{#{caption}}" if caption && !caption.empty?

        if with_label && node.id?
          result << if @chapter
                      "\\label{image:#{@chapter.id}:#{node.id}}"
                    else
                      "\\label{image:test:#{node.id}}"
                    end
        end

        result << '\\end{reviewimage}'
        result.join("\n") + "\n"
      end

      # Render existing indepimage (for //indepimage)
      def render_existing_indepimage(node, image_path, caption)
        result = []
        result << "\\begin{reviewimage}%%#{node.id}"

        if caption_top?('image') && caption && !caption.empty?
          caption_str = "\\reviewindepimagecaption{#{text_formatter.format_numberless_image}#{text_formatter.format_caption_prefix}#{caption}}"
          result << caption_str
        end

        metrics = parse_metric('latex', node.metric)
        command = 'reviewincludegraphics'

        result << if metrics && !metrics.empty?
                    "\\#{command}[#{metrics}]{#{image_path}}"
                  else
                    "\\#{command}[width=\\maxwidth]{#{image_path}}"
                  end

        if !caption_top?('image') && caption && !caption.empty?
          caption_str = "\\reviewindepimagecaption{#{text_formatter.format_numberless_image}#{text_formatter.format_caption_prefix}#{caption}}"
          result << caption_str
        end

        result << '\\end{reviewimage}'
        result.join("\n") + "\n"
      end

      # Render dummy image for missing images
      def render_dummy_image(node, caption, double_escape_id:, with_label:)
        result = []
        result << '\\begin{reviewdummyimage}'

        if node.id?
          # For regular images: single escape, for indepimage: double escape (like Builder)
          result << if double_escape_id
                      escape_latex("--[[path = #{escape_latex(node.id)} (not exist)]]--")
                    else
                      escape_latex("--[[path = #{node.id} (not exist)]]--")
                    end
        end

        if with_label && node.id?
          result << if @chapter
                      "\\label{image:#{@chapter.id}:#{node.id}}"
                    else
                      "\\label{image:test:#{node.id}}"
                    end
        end

        if caption && !caption.empty?
          result << if double_escape_id
                      # indepimage uses reviewindepimagecaption
                      "\\reviewindepimagecaption{#{text_formatter.format_numberless_image}#{text_formatter.format_caption_prefix}#{caption}}"
                    else
                      # regular image uses reviewimagecaption
                      "\\reviewimagecaption{#{caption}}"
                    end
        end

        result << '\\end{reviewdummyimage}'
        result.join("\n") + "\n"
      end

      def ast_compiler
        @ast_compiler ||= ReVIEW::AST::Compiler.for_chapter(@chapter)
      end

      # Render definition list with proper footnote handling
      # Footnotes in definition terms require special handling in LaTeX:
      # they must use \protect\footnotemark{} in the term and \footnotetext
      # after the description environment
      def visit_definition_list(node)
        dl_context = nil
        items_content = @rendering_context.with_child_context(:dl) do |ctx|
          dl_context = ctx
          # Temporarily set the renderer's context to the dl context
          old_context = @rendering_context
          @rendering_context = dl_context
          begin
            node.children.map do |item|
              render_definition_item(item, dl_context)
            end.join("\n")
          ensure
            # Restore even if item rendering raises.
            @rendering_context = old_context
          end
        end

        # Build output
        result = "\n\\begin{description}\n#{items_content}\n\\end{description}\n\n"

        # Add collected footnotetext commands from dt contexts (transferred to dl_context)
        if dl_context && dl_context.footnote_collector.any?
          result += generate_footnotetext_from_collector(dl_context.footnote_collector)
          dl_context.footnote_collector.clear
        end

        result
      end

      # Render a single definition list item
      def render_definition_item(item, dl_context)
        # Render term with :dt context like LATEXBuilder does (latexbuilder.rb:361-382)
        term = render_definition_term(item, dl_context)

        # Escape square brackets in terms like LATEXBuilder does
        term = term.gsub('[', '\\lbrack{}').gsub(']', '\\rbrack{}')

        # Handle definition content (all children are definition content)
        if item.children && !item.children.empty?
          definition_parts = item.children.map do |child|
            result = visit(child) # Use visit instead of render_children for individual nodes
            # Strip all trailing whitespace and newlines
            # LATEXBuilder's dd() joins lines with "\n", so we need single newlines between paragraphs
            result.rstrip
          end
          # Match LATEXBuilder#dd: join with "\n" by default, or via
          # join_lines_to_paragraph (language-aware) when join_lines_by_lang is on.
          definition = join_source_lines(definition_parts)

          # Use exact LATEXBuilder format: \item[term] \mbox{} \\
          "\\item[#{term}] \\mbox{} \\\\\n#{definition}"
        else
          # No definition content - term only
          "\\item[#{term}] \\mbox{} \\\\"
        end
      end

      # Render definition term with proper footnote collection
      def render_definition_term(item, dl_context)
        term = nil
        dt_footnote_collector = nil

        @rendering_context.with_child_context(:dt) do |dt_context|
          # Temporarily set renderer's context to dt context for term rendering
          old_dt_context = @rendering_context
          @rendering_context = dt_context
          begin
            term = if item.term_children&.any?
                     # Render term children (which contain inline elements)
                     item.term_children.map { |child| visit(child) }.join
                   else
                     ''
                   end
          ensure
            @rendering_context = old_dt_context
          end

          # Save dt_context's footnote collector to transfer footnotes to dl_context
          dt_footnote_collector = dt_context.footnote_collector
        end

        # Transfer footnotes from dt_context to dl_context
        if dt_footnote_collector && dt_footnote_collector.any?
          dt_footnote_collector.each do |entry|
            dl_context.collect_footnote(entry.node, entry.number)
          end
          dt_footnote_collector.clear
        end

        term
      end

      # Generate LaTeX footnotetext commands from collected footnotes
      # @param collector [FootnoteCollector] the footnote collector
      # @return [String] LaTeX footnotetext commands
      def generate_footnotetext_from_collector(collector)
        return '' unless collector.any?

        footnotetext_commands = []
        collector.each do |entry|
          content = render_footnote_content(entry.node)
          footnotetext_commands << "\\footnotetext[#{entry.number}]{#{content}}"
        end

        footnotetext_commands.join("\n") + "\n"
      end

      HEADLINE = { # rubocop:disable Lint/UselessConstantScoping
        1 => 'chapter',
        2 => 'section',
        3 => 'subsection',
        4 => 'subsubsection',
        5 => 'paragraph',
        6 => 'subparagraph'
      }.freeze

      def headline_name(level)
        name = if @chapter.is_a?(ReVIEW::Book::Part) && level == 1
                 'part'
               else
                 HEADLINE[level] || raise(CompileError, "Unsupported headline level: #{level}. LaTeX only supports levels 1-6")
               end

        if level > config['secnolevel'] || (@chapter.number.to_s.empty? && level > 1)
          "#{name}*"
        else
          name
        end
      end

      def render_inline_element(type, content, node)
        # Delegate to inline element handler
        method_name = "render_inline_#{type}"
        if @inline_element_handler.respond_to?(method_name, true)
          @inline_element_handler.send(method_name, type, content, node)
        else
          raise NotImplementedError, "Unknown inline element: #{type}"
        end
      end

      def visit_reference(node)
        if node.resolved?
          format_resolved_reference(node.resolved_data)
        else
          # Reference resolution was skipped or disabled
          # Return content as fallback
          escape(node.content || '')
        end
      end

      # Format resolved reference based on ResolvedData
      # Gets plain text from TextFormatter and wraps it with LaTeX markup
      def format_resolved_reference(data)
        # Get plain text from TextFormatter (no LaTeX markup)
        plain_text = text_formatter.format_reference(data.reference_type, data)

        # Wrap with LaTeX-specific markup based on reference type
        case data.reference_type
        when :image, :table, :list
          # For image/table/list, use \ref command
          if data.cross_chapter?
            "\\ref{#{data.chapter_id}:#{data.item_id}}"
          else
            "\\ref{#{data.item_id}}"
          end
        when :equation
          # For equation, use \ref command
          "\\ref{#{data.item_id}}"
        when :footnote
          # For footnote, use \footnotemark command
          "\\footnotemark[#{data.item_number}]"
        when :bibpaper
          # For bibliography, use \reviewbibref command
          "\\reviewbibref{[#{data.item_number}]}{bib:#{data.item_id}}"
        else
          # For other types (chapter, headline, column, word, endnote), return escaped plain text
          escape(plain_text)
        end
      end

      # Join a node's block children, applying the LATEXBuilder-matching
      # whitespace rules between adjacent raw-content blocks (embed/raw) and
      # after minicolumns. This runs for the document AND for nested block
      # containers (minicolumn/column), since the same "A\n\nB → spurious \par"
      # issue happens for embeds/raws sitting inside a //note or column too.
      # Join block-level children, setting the separation between each adjacent
      # pair to the gap LATEXBuilder produces (see #latex_block_gap). Each block
      # visitor emits its natural trailing "\n\n"; this normalises the trailing
      # newline run at every boundary to the required count. Used for the
      # document body and for column / minicolumn bodies, so all three share one
      # separation model (doc/design-improvements #2).
      def join_block_children(node)
        pieces = []
        prev = nil
        node.children.each do |child|
          result = visit(child)
          next if result.nil? || result.empty?

          if prev
            gap = latex_block_gap(prev, child)
            pieces[-1] = pieces[-1].sub(/\n*\z/, "\n" * gap)
          end
          pieces << result
          prev = child
        end
        pieces.join
      end

      # The number of newlines LATEXBuilder places between two adjacent blocks
      # (0 = abutting, 1 = single line break, 2 = blank line / \par). Most pairs
      # are a blank line; the exceptions below are where the builder's #print vs
      # #blank usage, verbatim content (//raw, //embed) and solve_nest produce a
      # tighter gap. A two-scalar leading/trailing model provably cannot express
      # these (e.g. raw→list=0 but minicolumn→list=2; bembed→minicolumn=2 but
      # minicolumn→minicolumn=1), so the irreducible pairs are encoded directly
      # here as a single node-based decision instead of post-hoc string rewrites
      # on the rendered LaTeX. Verified against the DVI oracle.
      def latex_block_gap(prev, nxt)
        # //raw content is verbatim (LATEXBuilder#raw uses `print`, no newline):
        # it abuts whatever follows, except it flows into a following paragraph
        # with one separating newline (otherwise the two would token-merge).
        return paragraph_node?(nxt) ? 1 : 0 if raw_embed?(prev)

        # A //raw or block //embed successor attaches with no leading blank, so
        # the gap is the predecessor's own trailing: 1 for the "tight" blocks
        # (minicolumn / block embed emit a single trailing newline), else a blank.
        return tight_trailing?(prev) ? 1 : 2 if raw_embed?(nxt) || block_embed?(nxt)

        # A block //embed before a //noindent paragraph: single newline (the
        # paragraph continues without its own leading blank).
        return 1 if block_embed?(prev) && noindent_paragraph?(nxt)

        # A minicolumn (captionblock) emits no trailing blank line, so a
        # following minicolumn (solve_nest), control command (\pagebreak /
        # \hrule) or deferred \footnotetext attaches with a single newline.
        if minicolumn_node?(prev) && (minicolumn_node?(nxt) || pagebreak_like?(nxt) || footnotetext_output?(nxt))
          return 1
        end

        # A headline ends with \label and emits no trailing blank, so a deferred
        # \footnotetext at the definition attaches with a single newline.
        return 1 if headline_node?(prev) && footnotetext_output?(nxt)

        2
      end

      def raw_embed?(node)
        node.is_a?(ReVIEW::AST::EmbedNode) && node.embed_type == :raw
      end

      def block_embed?(node)
        node.is_a?(ReVIEW::AST::EmbedNode) && node.embed_type == :block
      end

      def paragraph_node?(node)
        node.is_a?(ReVIEW::AST::ParagraphNode)
      end

      def noindent_paragraph?(node)
        paragraph_node?(node) && node.noindent?
      end

      def minicolumn_node?(node)
        node.is_a?(ReVIEW::AST::MinicolumnNode)
      end

      def headline_node?(node)
        node.is_a?(ReVIEW::AST::HeadlineNode)
      end

      # A minicolumn or block embed emits a single trailing newline; every other
      # block emits a trailing blank line.
      def tight_trailing?(node)
        minicolumn_node?(node) || block_embed?(node)
      end

      def pagebreak_like?(node)
        node.is_a?(ReVIEW::AST::BlockNode) && %i[pagebreak hrule].include?(node.block_type)
      end

      # A FootnoteNode that renders as \footnotetext at this point: a real
      # footnote (not //endnote) emitted here because of global footnotetext mode
      # or because its @<fn> sat in a moving argument (deferred).
      def footnotetext_output?(node)
        node.is_a?(ReVIEW::AST::FootnoteNode) &&
          node.footnote_type != :endnote &&
          (config['footnotetext'] || @deferred_footnotetext_ids.key?(node.id))
      end

      # Render document children with proper separation
      def render_document_children(node)
        join_block_children(node)
      end

      # Render children with specific rendering context
      def render_children_with_context(node, context)
        old_context = @rendering_context
        @rendering_context = context
        render_children(node)
      ensure
        # Restore even if rendering raises, so a rescued error can't leave the
        # renderer stuck in a child (e.g. :caption/:heading) context.
        @rendering_context = old_context
      end

      # Visit node with specific rendering context
      def visit_with_context(node, context)
        old_context = @rendering_context
        @rendering_context = context
        visit(node)
      ensure
        @rendering_context = old_context
      end

      def visit_footnote(node)
        # FootnoteNode represents a footnote definition (//footnote[id][content]).
        # Normally it produces nothing here -- @<fn>{id} inlines it directly.
        # It emits the \footnotetext at THIS definition point (matching
        # LATEXBuilder#footnote) in two cases: global footnotetext mode, or when
        # this footnote was used inside a moving argument (heading/caption/table/
        # column/dt) so @<fn> emitted a \footnotemark and deferred the text.
        return '' if node.footnote_type == :endnote # //endnote is not a footnote
        return '' unless config['footnotetext'] || @deferred_footnotetext_ids.key?(node.id)
        return '' unless node.id && node.definition_number

        number = node.definition_number.number
        # Trailing blank so the next block (e.g. a paragraph, which does not emit
        # its own leading blank) is separated, matching LATEXBuilder. The leading
        # blank is trimmed by render_document_children when the \footnotetext
        # follows a headline/minicolumn (which emit none).
        "\\footnotetext[#{number}]{#{render_footnote_content(node)}}\n\n"
      end

      # Check caption position configuration
      def caption_top?(type)
        unless %w[top bottom].include?(config.dig('caption_position', type))
          # Default to top if not configured
          return true
        end

        config['caption_position'][type] != 'bottom'
      end

      # This method calls super to use the base implementation, then applies LaTeX-specific logic
      def parse_metric(type, metric)
        s = super
        # If use_original_image_size is enabled and result is empty and no metric provided
        if config&.dig('pdfmaker', 'use_original_image_size') && s.empty? && !metric&.present?
          return ' ' # pass empty space to \reviewincludegraphics to use original size
        end

        s
      end

      # Handle individual metric transformations (like scale to width conversion)
      def handle_metric(str)
        # Check if image_scale2width is enabled and metric is scale
        if config&.dig('pdfmaker', 'image_scale2width') && str =~ /\Ascale=([\d.]+)\Z/
          return "width=#{$1}\\maxwidth"
        end

        str
      end

      # Apply noindent if the node has the noindent attribute
      def apply_noindent_if_needed(node, content)
        if node.noindent?
          "\\noindent\n#{content}"
        else
          content
        end
      end

      # Check if Part document should be wrapped with reviewpart environment
      def should_wrap_part_with_reviewpart?
        @chapter.is_a?(ReVIEW::Book::Part)
      end

      # Generate TOC entry only (for nodisp headlines)
      def generate_toc_entry(level, caption)
        "\\addcontentsline{toc}{#{get_base_section_name(level)}}{#{caption}}\n"
      end

      # Generate unnumbered headline with TOC entry (for nonum headlines)
      def generate_nonum_headline(level, caption, node)
        section_command = get_base_section_name(level) + '*'
        # The visible heading (a moving argument) keeps \footnotemark from the
        # :heading caption; the \addcontentsline TOC entry uses a plain \footnote,
        # matching LATEXBuilder (which resets @doc_status[:caption] before it).
        toc_caption = headline_toc_caption(node, caption)
        "\\#{section_command}{#{caption}}\n\\addcontentsline{toc}{#{HEADLINE[level]}}{#{toc_caption}}\n\n"
      end

      # Generate unnumbered headline without TOC entry (for notoc headlines)
      def generate_notoc_headline(level, caption, _node)
        section_command = get_base_section_name(level) + '*'

        "\\#{section_command}{#{caption}}\n\n"
      end

      # Get base section name without star
      def get_base_section_name(level)
        if @chapter.is_a?(ReVIEW::Book::Part) && level == 1
          'part'
        else
          HEADLINE[level] || raise(CompileError, "Unsupported headline level: #{level}")
        end
      end

      # Generate column label for hypertarget (matches LATEXBuilder behavior)
      def generate_column_label(node, _caption)
        # Use column_number directly instead of parsing auto_id
        num = node.column_number || 'unknown'

        "column:#{@chapter&.id || 'unknown'}:#{num}"
      end

      # Process //raw command with LATEXBuilder-compatible behavior
      def process_raw_embed(node)
        # Skip HTML embeds (from Markdown raw HTML) - they are not compatible with LaTeX
        return '' if node.embed_type.to_s == 'html'

        # Check if this embed is targeted for LaTeX builder
        unless node.targeted_for?('latex')
          return ''
        end

        # Get content
        content = node.content || ''

        # Process \n based on embed type
        case node.embed_type
        when :inline, :raw
          # For inline and raw embeds, convert \\n to actual newlines
          content = content.gsub('\\n', "\n")
        end

        # For block embeds, end with a blank line so a following paragraph is a
        # separate paragraph. (The AST renderer separates blocks by trailing
        # blank lines; LATEXBuilder relies on the *next* element's leading blank,
        # so a single "\n" here would merge the next paragraph into the embed.)
        node.embed_type == :block ? content + "\n\n" : content
      end
    end
  end
end
