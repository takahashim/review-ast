# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/typst_escape_utils'
require_relative '../resolved_reference'
require_relative 'labels'
require_relative 'build_paths'

module ReVIEW
  module Renderer
    module Typst
      # Inline element handler for Typst rendering.
      #
      # Every inline Re:VIEW understands has a method here. There is no
      # catch-all: TypstRenderer raises for an inline this class does not
      # implement, so a command added upstream fails loudly instead of silently
      # losing its markup (doc/design-typst.md).
      class InlineElementHandler
        include ReVIEW::TypstEscapeUtils
        include ReVIEW::Renderer::ResolvedReference
        include Labels
        include BuildPaths

        def initialize(inline_context)
          @ctx = inline_context
          @render_context = @ctx.render_context
          @config = @ctx.config
        end

        # ------------------------------------------------------- decoration

        # The decoration inlines share one library entry point keyed by
        # inline_type, so adding a decoration is a change in one place on each
        # side rather than a new function per command.
        %w[b i em tt ttb tti code u strong ami bou tcy balloon sup sub del strike ins insert].each do |kind|
          define_method("render_inline_#{kind}") do |_type, content, _node|
            "#review.inline(#{typst_string(kind)})[#{content}]"
          end
        end

        # @<idx> shows its content and records an index entry; @<hidx> records
        # only. Re:VIEW decides the term path and its sort key
        # (doc/design-typst.md); the page number is all Typst adds.
        def render_inline_idx(_type, content, node)
          return content unless node.args.first

          "#{content}#{index_entry(node.args.first)}"
        end

        def render_inline_hidx(_type, _content, node)
          node.args.first ? index_entry(node.args.first) : ''
        end

        # DTP instructions target InDesign only; every renderer drops them.
        def render_inline_dtp(_type, _content, _node)
          ''
        end

        def render_inline_br(_type, _content, _node)
          '#review.br()'
        end

        def render_inline_uchar(_type, content, node)
          node.args.first ? escape_typst([node.args.first.to_i(16)].pack('U')) : content
        end

        def render_inline_ruby(_type, content, node)
          return content unless node.args.length >= 2

          "#review.ruby(base: [#{escape_typst(node.args[0])}], reading: [#{escape_typst(node.args[1])}])"
        end

        def render_inline_kw(_type, content, node)
          if node.args.length >= 2
            "#review.kw(term: [#{escape_typst(node.args[0])}], desc: [#{escape_typst(node.args[1])}])"
          else
            "#review.kw(term: [#{content}])"
          end
        end

        def render_inline_href(_type, _content, node)
          if node.args.length >= 2
            url = node.args[0]
            "#review.link-to(url: #{typst_string(url)}, body: [#{escape_typst(node.args[1])}])"
          else
            raw_url = node.children.first&.leaf_node? ? node.children.first.content : nil
            raise ReVIEW::CompileError, "@<href> has no URL#{node.location&.format_for_error}" unless raw_url

            "#review.link-to(url: #{typst_string(raw_url)})"
          end
        end

        def render_inline_icon(_type, content, node)
          return content unless node.args.first

          if node.image_path
            "#review.icon(path: #{typst_string(build_relative_image_path(node.image_path))})"
          else
            "#review.icon(missing: #{typst_string(node.args.first)})"
          end
        end

        # @<m> carries LaTeX, handed to the library's math adapter unchanged.
        def render_inline_m(_type, content, node)
          "#review.math-inline(latex: #{typst_string(node.args.first || content)})"
        end

        def render_inline_comment(_type, content, _node)
          @ctx.draft_mode? ? "#review.inline(\"balloon\")[#{escape_typst(content)}]" : ''
        end

        # ------------------------------------------------------------- raw

        # //raw and //embed pass through only for their target builder; the
        # author opted in by naming typst (doc/design-typst.md).
        def render_inline_raw(_type, _content, node)
          node.targeted_for?('typst') ? (node.content || '') : ''
        end

        def render_inline_embed(_type, _content, node)
          node.targeted_for?('typst') ? (node.content || '') : ''
        end

        # ------------------------------------------------------ references

        def render_inline_img(_type, _content, node)
          data = resolved_data_for(node)
          target = label_for(:image, data.chapter_id || @render_context.chapter_id, data.item_id)
          reference(target, @ctx.text_formatter.format_reference(:image, data))
        end

        # Like @<img>, but with the referenced image's caption appended.
        def render_inline_imgref(type, content, node)
          data = resolved_data_for(node)
          caption = data.caption_node&.to_inline_text || ''
          "#{render_inline_img(type, content, node)}#{escape_typst(@ctx.text_formatter.format_image_quote(caption))}"
        end

        def render_inline_list(_type, _content, node)
          data = resolved_data_for(node)
          target = label_for(:list, data.chapter_id || @render_context.chapter_id, data.item_id)
          reference(target, @ctx.text_formatter.format_reference(:list, data))
        end

        def render_inline_listref(type, content, node)
          render_inline_list(type, content, node)
        end

        def render_inline_table(_type, _content, node)
          data = resolved_data_for(node)
          target = label_for(:table, data.chapter_id || @render_context.chapter_id, data.item_id)
          reference(target, @ctx.text_formatter.format_reference(:table, data))
        end

        def render_inline_tableref(type, content, node)
          render_inline_table(type, content, node)
        end

        def render_inline_eq(_type, _content, node)
          data = resolved_data_for(node)
          target = label_for(:equation, data.chapter_id || @render_context.chapter_id, data.item_id)
          reference(target, @ctx.text_formatter.format_reference(:equation, data))
        end

        def render_inline_eqref(type, content, node)
          render_inline_eq(type, content, node)
        end

        def render_inline_bib(_type, _content, node)
          data = resolved_data_for(node)
          reference(bib_label(data.item_id), @ctx.text_formatter.format_reference(:bibpaper, data))
        end

        def render_inline_bibref(type, content, node)
          render_inline_bib(type, content, node)
        end

        def render_inline_chap(_type, _content, node)
          data = resolved_data_for(node)
          text = @ctx.text_formatter.format_chapter_number_full(data.chapter_number, data.chapter_type)
          reference(chapter_label(data.item_id), text)
        end

        def render_inline_chapref(_type, _content, node)
          data = resolved_data_for(node)
          reference(chapter_label(data.item_id), @ctx.text_formatter.format_reference(:chapter, data))
        end

        # @<title> links only when chapterlink is on, matching the builders.
        def render_inline_title(_type, _content, node)
          data = resolved_data_for(node)
          title = data.chapter_title || ''
          if @ctx.chapter_link_enabled?
            reference(chapter_label(data.item_id), title)
          else
            escape_typst(title)
          end
        end

        def render_inline_hd(_type, _content, node)
          data = resolved_data_for(node)
          reference(heading_label(data), @ctx.text_formatter.format_reference(:headline, data))
        end

        def render_inline_secref(type, content, node)
          render_inline_hd(type, content, node)
        end

        # @<sec> shows the number alone, @<sectitle> the title alone.
        def render_inline_sec(_type, _content, node)
          data = resolved_data_for(node)
          reference(heading_label(data), heading_number_text(data))
        end

        def render_inline_sectitle(_type, _content, node)
          data = resolved_data_for(node)
          reference(heading_label(data), data.caption_text.to_s)
        end

        def render_inline_column(_type, _content, node)
          data = resolved_data_for(node)
          chapter_id = data.chapter_id || @render_context.chapter_id
          target = label_for(:column, chapter_id, data.item_number.to_s)
          caption = data.caption_node ? data.caption_node.to_inline_text : data.caption_text
          reference(target, @ctx.text_formatter.format_column_label(caption))
        end

        # A footnote's body is emitted at its FIRST reference and later
        # references point at that label; the number comes from Re:VIEW either
        # way (doc/design-typst.md).
        def render_inline_fn(_type, _content, node)
          data = resolved_data_for(node)
          id = data.item_id
          target = label_for(:footnote, @render_context.chapter_id, id)

          if @ctx.footnote_emitted?(id)
            "#review.footnote-ref(id: #{typst_string(target)})"
          else
            @ctx.record_footnote(id, data.item_number)
            body = if data.caption_node
                     @ctx.render_children(data.caption_node).strip
                   else
                     escape_typst(data.caption_text.to_s)
                   end
            "#review.footnote(id: #{typst_string(target)}, number: #{data.item_number})[#{body}]"
          end
        end

        # An endnote's body is printed at //printendnotes, so only the mark is
        # emitted here.
        def render_inline_endnote(_type, _content, node)
          data = resolved_data_for(node)
          target = label_for(:endnote, @render_context.chapter_id, data.item_id)
          "#review.endnote-ref(id: #{typst_string(target)}, number: #{data.item_number})"
        end

        # @<w> / @<wb> expand a dictionary word; there is nothing to link to.
        def render_inline_w(_type, content, _node)
          content
        end

        def render_inline_wb(_type, content, _node)
          "#review.inline(\"b\")[#{content}]"
        end

        def render_inline_labelref(_type, content, node)
          id = node.args.first
          return escape_typst(content.to_s) unless id

          reference(user_label(id), content.to_s.empty? ? id : content, escape: content.to_s.empty?)
        end

        def render_inline_ref(type, content, node)
          render_inline_labelref(type, content, node)
        end

        # Page numbers are only known after layout, so this is resolved in the
        # library through Typst's page counter rather than here.
        def render_inline_pageref(_type, content, node)
          id = node.args.first || content
          "#review.page-ref(target: #{typst_string(user_label(id))})"
        end

        private

        # An index mark. "<<>>" separates the levels of a hierarchical entry,
        # matching what LATEXBuilder feeds to mendex.
        #
        # The sort key comes from config['dictionary'] when the book supplies
        # one, which is where a Japanese reading has to come from -- Typst
        # cannot derive it. Without an entry the term sorts as itself, so ASCII
        # terms behave and Japanese ones fall back to code-point order.
        def index_entry(index_string)
          terms = index_string.split('<<>>')
          sort_key = index_dictionary[index_string] || terms.join(' ')
          # Strings, not content: the marks travel through Typst's metadata(),
          # whose values must be plain data, and the term doubles as the key the
          # entries are grouped by.
          levels = terms.map { |term| typst_string(term) }
          "#review.index-entry(terms: (#{levels.join(', ')},), sort-key: #{typst_string(sort_key)})"
        end

        def index_dictionary
          @index_dictionary ||= load_index_dictionary
        end

        def load_index_dictionary
          path = @config['dictionary']
          return {} unless path && File.exist?(path)

          table = {}
          File.foreach(path) do |line|
            key, value = *line.strip.split(/\t+/, 2)
            table[key] = value if key && value
          end
          table
        rescue SystemCallError
          {}
        end

        # A reference with a supplied display string: a link to the label, never
        # a Typst `ref` (which would generate its own number).
        def reference(target, text, escape: true)
          body = escape ? escape_typst(text.to_s) : text.to_s
          "#review.reference(target: #{typst_string(target)}, text-content: [#{body}])"
        end

        def heading_label(data)
          chapter_id = data.chapter_id || @render_context.chapter_id
          section_label(chapter_id, Array(data.headline_number).compact)
        end

        # The number a heading reference shows, with the chapter prefix when the
        # heading is numbered at all.
        def heading_number_text(data)
          numbers = Array(data.headline_number).compact
          return '' if numbers.empty?

          chapter_number = data.chapter_number || @render_context.chapter_number
          chapter_type = data.chapter_type || @render_context.chapter_type
          short = @ctx.text_formatter.format_chapter_number_short(chapter_number, chapter_type)
          short.to_s.empty? ? numbers.join('.') : ([short] + numbers).join('.')
        end
      end
    end
  end
end
