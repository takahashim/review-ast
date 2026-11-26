# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/caption_node'
require 'review/sec_counter'
require 'review/i18n'
require 'review/typst_escape_utils'
require_relative 'base'
require_relative 'graph_image'
require_relative 'typst/build_paths'
require_relative 'typst/expression'
require_relative 'typst/inline_context'
require_relative 'typst/inline_element_handler'
require_relative 'typst/labels'
require_relative 'typst/metric_parser'

module ReVIEW
  module Renderer
    # Renders a resolved core AST into Typst source that calls the review-book
    # library's review.* API.
    #
    # The renderer never states layout: no colours, no boxes, no spacing. It
    # converts AST nodes into semantic calls and lets the library and its theme
    # decide how those look (doc/design-typst.md). Numbers are
    # not computed here either -- they are read from the DefinitionNumber the
    # Indexer stamped, and their display strings come from TextFormatter.
    class TypstRenderer < Base
      include ReVIEW::TypstEscapeUtils
      include Typst::Labels
      include Typst::BuildPaths

      # Builder name used for //embed[|typst|] and images/<builder>/ lookups.
      BUILDER_NAME = 'typst'

      # Import path for the bundled library, absolute from the Typst project
      # root so every generated file resolves it the same way regardless of how
      # deep it sits (doc/design-typst.md, BuildLayout).
      LIBRARY_IMPORT = '/lib/review-book/lib.typ'

      # Minicolumn kinds, straight from MinicolumnNode.
      MINICOLUMN_KINDS = %i[note memo tip info warning important caution notice].freeze

      # Quote-family blocks and the library kind they map to.
      QUOTE_BLOCKS = {
        quote: 'quote',
        blockquote: 'quote',
        lead: 'lead',
        read: 'read',
        doorquote: 'quote'
      }.freeze

      # Blocks that only change alignment.
      ALIGNED_BLOCKS = {
        centering: 'center',
        flushright: 'right',
        address: 'right'
      }.freeze

      # Blocks drawn as a framed box with an optional caption.
      FRAMED_BLOCKS = %i[box insn point term].freeze

      attr_reader :chapter, :book

      def initialize(chapter)
        super

        @sec_counter = ReVIEW::AST::SectionCounter.new(5, @chapter) if @chapter
        @inline_context = Typst::InlineContext.new(
          config: config,
          render_context: render_context,
          renderer: self
        )
        @inline_element_handler = Typst::InlineElementHandler.new(@inline_context)
      end

      # @return [Symbol] Format type :typst
      def format_type
        :typst
      end

      # ------------------------------------------------------------ document

      # Line ranges of the generated file, each with the manuscript position of
      # the block that produced it.
      #
      # Typst reports errors against the generated .typ, which is not what the
      # author wrote. Recording where each top-level block landed lets the maker
      # answer with a manuscript position instead
      # (doc/design-typst.md).
      #
      # @return [Array<Hash>] {first_line:, last_line:, filename:, lineno:, column:}
      attr_reader :source_map

      def visit_document(node)
        header = "#import #{typst_string(LIBRARY_IMPORT)}: review\n\n"
        # The +1 is the line the first block starts on, after the header.
        line = header.count("\n") + 1

        @source_map = []
        pieces = []

        node.children.each do |child|
          result = visit(child)
          next if result.nil? || result.empty?

          result = result.sub(/\n*\z/, "\n\n")
          height = result.count("\n")
          @source_map << source_map_entry(child, line, line + height - 1)
          pieces << result
          line += height
        end

        header + pieces.join.sub(/\n+\z/, "\n")
      end

      # ------------------------------------------------------------ headings

      def visit_headline(node)
        caption = node.caption_node ? render_children(node.caption_node) : ''
        level = node.level

        # nonum / notoc / nodisp are mutually exclusive (one tag slot) and none
        # of them advances the section counter, matching the builders.
        numbered = !(node.nonum? || node.notoc? || node.nodisp?)
        @sec_counter.inc(level) if numbered && @sec_counter

        if level == 1
          expression = chapter_expression(caption, numbered)
          # review.part takes neither toc nor visible: a part title is not a
          # chapter, and passing an argument the function does not declare is a
          # Typst error rather than a no-op.
          return expression.to_block if render_context.part?
        else
          expression = section_expression(level, caption, numbered)
        end

        expression.value(:toc, false) if node.notoc?
        expression.value(:visible, false) if node.nodisp?
        expression.to_block
      end

      # A part's own .re file has a level-1 heading that is the part title, not
      # a chapter title, so the two share everything but the function called.
      def chapter_expression(caption, numbered)
        function = render_context.part? ? 'review.part' : 'review.chapter'
        expression = Typst::Expression.new(function)

        # Only the first level-1 heading carries the chapter label. A chapter
        # file may hold several (a =[nonum] section is still level 1), and
        # emitting the same label twice makes Typst reject the document.
        if render_context.chapter_present? && !@chapter_label_emitted
          expression.str(:id, chapter_label(render_context.chapter_id))
          @chapter_label_emitted = true
        end
        expression.value(:number, render_context.chapter_number) if render_context.chapter_number_present?
        expression.text('number-text', numbered ? chapter_number_text : nil)
        expression.content(:title, caption)
      end

      def section_expression(level, caption, numbered)
        expression = Typst::Expression.new('review.section').value(:level, level)

        if numbered && @sec_counter
          # The label is emitted whether or not the number prints: @<hd> can
          # point at a heading deeper than secnolevel, which shows its title
          # alone but still has to link somewhere.
          expression.str(:id, section_label(render_context.chapter_id, @sec_counter.number_list))
          expression.text('number-text', section_number_text(level))
        end
        expression.content(:title, caption)
      end

      # ----------------------------------------------------------- paragraph

      def visit_paragraph(node)
        content = render_children(node)
        # Source line breaks inside a paragraph are not paragraph breaks; Typst
        # would treat a bare newline as a space anyway, which is what the other
        # renderers produce for Japanese text.
        "#{content.strip}\n\n"
      end

      def visit_caption(node)
        render_children(node)
      end

      # ------------------------------------------------------------- images

      def visit_image(node)
        caption = node.caption_node ? render_children(node.caption_node) : nil
        numbered = !%i[indepimage numberlessimage].include?(node.image_type)

        expression = Typst::Expression.new('review.figure')
        expression.raw_arguments(numbered_args(node, kind: :image, label_key: 'image')) if numbered
        expression.content(:caption, caption)
        expression.raw_arguments(image_source_args(node))
        expression.value('caption-top', true) if caption_top?('image')
        expression.to_block
      end

      # ------------------------------------------------------------- tables

      def visit_table(node)
        caption = node.caption_node ? render_children(node.caption_node) : nil

        return render_imgtable(node, caption) if node.table_type == :imgtable

        expression = Typst::Expression.new('review.table').
                     raw_arguments(numbered_args(node, kind: :table, label_key: 'table')).
                     content(:caption, caption).
                     value(:columns, node.column_count)

        header = node.header_rows
        expression.array(:header, header.flat_map { |row| cells_of(row) }) unless header.empty?
        expression.array(:rows, node.body_rows.map { |row| "(#{cells_of(row).join(', ')},)" })
        expression.value('caption-top', caption_top?('table'))
        expression.to_block
      end

      # A row's cells, each as a content block.
      def cells_of(row)
        row.children.map { |cell| "[#{render_children(cell)}]" }
      end

      def visit_table_row(node)
        node.children.map { |cell| visit(cell) }.join
      end

      def visit_table_cell(node)
        render_children(node)
      end

      def render_imgtable(node, caption)
        Typst::Expression.new('review.imgtable').
          raw_arguments(numbered_args(node, kind: :table, label_key: 'table')).
          content(:caption, caption).
          raw_arguments(image_source_args(node)).
          value('caption-top', caption_top?('table')).
          to_block
      end

      # ------------------------------------------------------------- lists

      # Lists are emitted as function calls, not as "-"/"+"/"/ term:" markup.
      # Item content is generated Typst that routinely contains ":" and "/", and
      # in markup those would terminate a term or start a comment; passing the
      # items as content values sidesteps the question entirely.
      def visit_list(node)
        case node.list_type
        when :ul
          Typst::Expression.new('review.bullet-list').array(:items, list_items(node)).to_block
        when :ol
          expression = Typst::Expression.new('review.numbered-list').array(:items, list_items(node))
          expression.value(:start, node.start_number) if node.start_number && node.start_number != 1
          expression.to_block
        when :dl
          items = node.children.map do |item|
            term = item.term_children ? item.term_children.map { |c| visit(c) }.join : ''
            desc = item.children.map { |c| visit(c) }.join.strip
            "([#{term.strip}], [#{desc}])"
          end
          Typst::Expression.new('review.description-list').array(:items, items).to_block
        else
          raise NotImplementedError, "Unsupported list type: #{node.list_type}"
        end
      end

      # Each item as a content block, ready for the list functions.
      def list_items(node)
        node.children.map { |item| "[#{render_children(item).strip}]" }
      end

      def visit_list_item(node)
        render_children(node)
      end

      # ------------------------------------------------------- code blocks

      def visit_code_block_list(node)
        render_listing(node, numbered: false, id_kind: :list)
      end

      def visit_code_block_listnum(node)
        render_listing(node, numbered: true, id_kind: :list)
      end

      def visit_code_block_emlist(node)
        render_listing(node, numbered: false, id_kind: nil)
      end

      def visit_code_block_emlistnum(node)
        render_listing(node, numbered: true, id_kind: nil)
      end

      def visit_code_block_cmd(node)
        render_listing(node, numbered: false, id_kind: nil, lang: nil)
      end

      def visit_code_block_source(node)
        render_listing(node, numbered: false, id_kind: nil)
      end

      def visit_code_line(node)
        "#{render_children(node)}\n"
      end

      # --------------------------------------------------------- equations

      def visit_tex_equation(node)
        expression = Typst::Expression.new('review.equation')
        if node.definition_number
          expression.raw_arguments(numbered_args(node, kind: :equation, label_key: 'equation'))
        end
        expression.content(:caption, node.caption? ? render_children(node.caption_node) : nil)
        expression.str(:latex, node.content.to_s)
        expression.to_block
      end

      # -------------------------------------------------- columns and notes

      def visit_minicolumn(node)
        caption = node.caption_node ? render_children(node.caption_node) : nil
        kind = node.minicolumn_type.to_s
        unless MINICOLUMN_KINDS.include?(node.minicolumn_type)
          raise NotImplementedError, "Unknown minicolumn type: #{kind}#{node.location&.format_for_error}"
        end

        Typst::Expression.new('review.minicolumn').
          str(:kind, kind).
          content(:caption, caption).
          body(join_block_children(node)).
          to_block
      end

      def visit_column(node)
        caption = node.caption_node ? render_children(node.caption_node) : nil
        expression = Typst::Expression.new('review.column')
        if node.column_number
          expression.str(:id, label_for(:column, render_context.chapter_id, node.column_number.to_s))
        end
        expression.content(:caption, caption)
        expression.value(:level, node.level)
        expression.body(join_block_children(node)).to_block
      end

      # ------------------------------------------------------------ blocks

      QUOTE_BLOCKS.each_key do |type|
        define_method("visit_block_#{type}") do |node|
          Typst::Expression.new('review.quote').
            str(:kind, QUOTE_BLOCKS[type]).
            body(join_block_children(node)).
            to_block
        end
      end

      ALIGNED_BLOCKS.each_key do |type|
        define_method("visit_block_#{type}") do |node|
          Typst::Expression.new('review.aligned').
            str(:alignment, ALIGNED_BLOCKS[type]).
            body(join_block_children(node)).
            to_block
        end
      end

      FRAMED_BLOCKS.each do |type|
        define_method("visit_block_#{type}") do |node|
          Typst::Expression.new('review.framed').
            content(:caption, node.caption_node ? render_children(node.caption_node) : nil).
            body(join_block_children(node)).
            to_block
        end
      end

      # //talk is a dialogue paragraph; it carries no decoration of its own.
      def visit_block_talk(node)
        "#{join_block_children(node).strip}\n\n"
      end

      def visit_block_bibpaper(node)
        raise NotImplementedError, "Malformed bibpaper block#{node.location&.format_for_error}" if node.args.length < 2

        bib_id = node.args[0]
        caption = node.caption_node ? render_children(node.caption_node) : escape_typst(node.args[1])
        number = node.definition_number&.number

        Typst::Expression.new('review.bibpaper').
          str(:id, bib_label(bib_id)).
          value(:number, number).
          content(:caption, caption).
          body(join_block_children(node)).
          to_block
      end

      # //graph renders as a numbered figure whose file is produced by running
      # the named generator. The process execution itself lives in GraphImage,
      # so this decides only what markup to emit (same split as IdgxmlRenderer).
      def visit_block_graph(node)
        id = node.args[0]
        path = generate_graph_image(node)

        caption = node.caption_node ? render_children(node.caption_node) : nil

        expression = Typst::Expression.new('review.figure').
                     raw_arguments(numbered_args(node, kind: :image, label_key: 'image', id: id)).
                     content(:caption, caption).
                     str(:path, build_relative_image_path(path)).
                     str(:alt, image_alt_text(node))
        expression.value('caption-top', true) if caption_top?('image')
        expression.to_block
      end

      def visit_block_printendnotes(_node)
        return '' if endnote_nodes.empty?

        items = endnote_nodes.map do |endnote|
          number = endnote.definition_number&.number
          target = label_for(:endnote, render_context.chapter_id, endnote.id)
          "(number: #{number}, id: #{typst_string(target)}, body: [#{render_children(endnote).strip}])"
        end
        Typst::Expression.new('review.print-endnotes').array(:items, items).to_block
      end

      def visit_block_label(node)
        id = node.args.first
        return '' unless id

        Typst::Expression.new('review.label-target').str(:id, user_label(id)).to_block
      end

      def visit_block_comment(node)
        return '' unless config['draft']

        parts = []
        parts << escape_typst(node.args.first) if node.args.first && !node.args.first.empty?
        body = join_block_children(node).strip
        parts << body unless body.empty?
        return '' if parts.empty?

        Typst::Expression.new('review.comment-block').body(parts.join(' ')).to_block
      end

      def visit_block_pagebreak(_node)
        Typst::Expression.new('review.pagebreak-block').to_block
      end

      def visit_block_hr(_node)
        Typst::Expression.new('review.hr').to_block
      end

      def visit_block_blankline(_node)
        Typst::Expression.new('review.blankline').to_block
      end

      # Control commands with no output of their own. Listed explicitly rather
      # than caught by a default, so a new block type still fails loudly.
      def visit_block_parasep(_node)
        ''
      end

      def visit_block_bpo(_node)
        ''
      end

      # IDGXMLBuilder's raw output; nothing in Typst.
      def visit_block_rawblock(_node)
        ''
      end

      # ---------------------------------------------------------- footnotes

      # A //footnote definition emits nothing: its body is rendered at the first
      # @<fn> that references it (doc/design-typst.md).
      def visit_footnote(_node)
        ''
      end

      # ------------------------------------------------------------- embeds

      def visit_embed(node)
        return '' if node.embed_type.to_s == 'html'
        return '' unless node.targeted_for?(BUILDER_NAME)

        content = node.content || ''
        content = content.gsub('\\n', "\n") if %i[inline raw].include?(node.embed_type)
        node.embed_type == :block ? "#{content}\n\n" : content
      end

      # ------------------------------------------------------------ inline

      # A ReferenceNode is visited as the child of its reference inline, so this
      # only supplies the `content` the handler receives. The handlers that
      # matter build their own output from resolved_data; the ones that fall
      # back to content (@<labelref>) want the resolved display text.
      def visit_reference(node)
        return escape_typst(node.content.to_s) unless node.resolved?

        data = node.resolved_data
        escape_typst(text_formatter.format_reference(data.reference_type, data))
      rescue ArgumentError
        escape_typst(node.content.to_s)
      end

      # Unknown inlines are an error, not a pass-through. Base's default returns
      # the content unchanged, which would silently drop the command's meaning
      # (doc/design-typst.md). The error is the one the other formats give for
      # an inline op they do not implement; with no builder to fall back on,
      # a `render_inline_<type>` in review-ext.rb is the way to add one.
      def render_inline_element(type, content, node)
        method_name = "render_inline_#{type}"
        unless @inline_element_handler.respond_to?(method_name, true)
          raise ReVIEW::CompileError,
                "builder does not support inline op: @<#{type}>#{node&.location&.format_for_error} " \
                "(#{extension_hint("inline_#{type}", method_name)})"
        end

        @inline_element_handler.send(method_name, type, content, node)
      end

      def render_caption_inline(caption_node)
        caption_node ? render_children(caption_node) : ''
      end

      private

      def escape(str)
        escape_typst(str)
      end

      # ------------------------------------------------------------ helpers

      # The label and number arguments every numbered element carries.
      #
      # Which id kind and which I18n label key differ per element, but the rule
      # -- a label when the element has an id, a number when the Indexer stamped
      # one -- is one rule, so it lives in one place. Spelling it out at each
      # call site meant a change to the numbering (when the display
      # string moved from format_caption to format_caption_plain) had to be
      # repeated six times.
      #
      # @param node [Node] The element being rendered
      # @param kind [Symbol] Label kind, a key of Labels::PREFIX
      # @param label_key [String] I18n key for the number's prefix word
      # @param id [String, nil] Id to use when it is not node.id (//graph)
      # @return [Array<String>] Zero, one or two Typst arguments
      def numbered_args(node, kind:, label_key:, id: nil)
        item_id = id || (node.id if node.id?)
        return [] unless item_id

        args = ["id: #{typst_string(label_for(kind, render_context.chapter_id, item_id))}"]
        args << "number-text: [#{escape_typst(number_text_for(node, label_key))}]" if node.definition_number
        args
      end

      # The display string for a numbered element, e.g. "図1.1". Built by
      # TextFormatter from the stamped DefinitionNumber, with no caption body
      # (the caption travels as its own argument).
      #
      # format_caption_plain, not format_caption: the latter's number form ends
      # in the caption separator ("図1.1:"), which belongs between the number
      # and the caption and is added by the library. Using the plain form also
      # makes this string identical to the one @<img>/@<list>/@<table> show,
      # since TextFormatter#format_numbered_reference builds references the same
      # way (doc/design-typst.md).
      def number_text_for(node, label_key)
        dn = node.definition_number
        raise NotImplementedError, "no number stamped for #{label_key}: #{node.id}" unless dn

        text_formatter.format_caption_plain(label_key, dn.chapter_number, dn.number)
      end

      def chapter_number_text
        return nil unless render_context.chapter_number_present?

        text_formatter.format_chapter_number_full(render_context.chapter_number, render_context.chapter_type)
      end

      # The heading number as it should print, e.g. "1.1". SecCounter#prefix
      # appends I18n's chapter_postfix (a full-width space in ja) as the
      # separator before the title; that spacing belongs to the theme, so it is
      # stripped here and the number alone is handed over.
      def section_number_text(level)
        return nil unless @sec_counter

        prefix = @sec_counter.prefix(level, config['secnolevel'].to_i)
        return nil if prefix.nil? || prefix.to_s.empty?

        postfix = ReVIEW::I18n.t('chapter_postfix')
        prefix.to_s.sub(/#{Regexp.escape(postfix)}\z/, '').strip
      end

      # Image files this renderer asks generators for. Typst reads SVG natively,
      # and every //graph generator can emit it.
      def image_ext
        'svg'
      end

      # The image's alternative text.
      #
      # Re:VIEW has no separate alt syntax, so the caption is what describes the
      # image -- which is what HtmlRenderer puts in the alt attribute too, so
      # the two formats describe an image the same way. An image with no caption
      # gets none, and a PDF/UA build then fails on it by design: Typst reports
      # the figure, and the source map names the line in the manuscript
      # (doc/design-typst.md).
      def image_alt_text(node)
        text = node.caption_node&.to_inline_text.to_s
        text.empty? ? nil : text
      end

      # Image arguments shared by //image, //imgtable and //graph.
      def image_source_args(node)
        return ["missing: #{typst_string(node.id.to_s)}"] unless node.image_path

        args = ["path: #{typst_string(build_relative_image_path(node.image_path))}"]
        alt = image_alt_text(node)
        args << "alt: #{typst_string(alt)}" if alt
        metric = Typst::MetricParser.new(parse_metric(BUILDER_NAME, node.metric), location: node.location).parse
        args << "width: #{metric[:width]}" if metric[:width]
        args << "height: #{metric[:height]}" if metric[:height]
        args << "scale-ratio: #{metric[:scale]}" if metric[:scale]
        args
      end

      def render_listing(node, numbered:, id_kind:, lang: node.lang)
        expression = Typst::Expression.new('review.listing')
        expression.raw_arguments(numbered_args(node, kind: id_kind, label_key: 'list')) if id_kind
        expression.content(:caption, node.caption_node ? render_children(node.caption_node) : nil)
        expression.str(:lang, lang.to_s.empty? ? nil : lang)

        if plain_code?(node)
          expression.str(:code, plain_code_text(node))
        else
          # A code block carrying inline commands cannot go through raw(), which
          # takes a string; keep the markup and lose highlighting for it.
          expression.content(:body, node.children.map { |line| render_children(line) }.join("\\\n"))
        end

        if numbered
          expression.value('line-numbers', true)
          expression.value('start-line', node.first_line_num || 1)
        end

        expression.to_block
      end

      # True when every code line is plain text, so the body can be a Typst
      # string and get syntax highlighting.
      def plain_code?(node)
        node.children.all? do |line|
          line.children.all?(ReVIEW::AST::TextNode)
        end
      end

      def plain_code_text(node)
        node.children.map { |line| line.children.map(&:content).join }.join("\n")
      end

      # One row of the source map. Granularity is the top-level block: an error
      # deeper inside resolves to the block that contains it, which is enough to
      # find the place in the manuscript.
      def source_map_entry(node, first_line, last_line)
        location = node.location
        {
          first_line: first_line,
          last_line: last_line,
          filename: location&.filename,
          lineno: location&.lineno,
          column: location&.column
        }
      end

      # Join block-level children, separating each by a blank line. Typst has no
      # equivalent of LaTeX's spacing subtleties between blocks, so unlike
      # LatexRenderer#latex_block_gap this needs no per-pair model.
      def join_block_children(node)
        node.children.filter_map do |child|
          result = visit(child)
          next if result.nil? || result.empty?

          result.sub(/\n*\z/, "\n\n")
        end.join
      end

      # Indent a nested block's body so the generated source stays readable.
      def indent(text, prefix = '  ')
        text.sub(/\n+\z/, "\n").gsub(/^(?=.)/, prefix)
      end

      # Continuation lines of a list item must line up under the marker.
      def indent_item(text)
        text.strip.gsub("\n", "\n  ")
      end
    end
  end
end
