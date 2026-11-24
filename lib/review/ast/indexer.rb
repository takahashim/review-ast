# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require 'review/exception'
require 'review/sec_counter'
require_relative 'definition_number'
require_relative 'chapter_number_formatter'
require_relative 'render_context'
require_relative 'chapter_index_registry'
require_relative 'footnote_node'
require_relative 'footnote_index'
require_relative 'headline_node'
require_relative 'column_node'
require_relative 'minicolumn_node'
require_relative 'code_block_node'
require_relative 'image_node'
require_relative 'table_node'
require_relative 'embed_node'
require_relative 'section_counter'
require_relative 'tex_equation_node'
require_relative 'block_node'
require_relative 'inline_node'
require_relative 'visitor'

module ReVIEW
  module AST
    # Indexer - AST-based index building for Re:VIEW documents
    #
    # This class provides high-performance index building by directly analyzing
    # AST structures instead of going through Builder classes. It generates
    # the same index structures as IndexBuilder for compatibility.
    #
    # Features:
    # - AST node traversal using Visitor pattern
    # - Compatible with existing IndexBuilder output
    # - High-performance processing without Builder overhead
    # - Comprehensive index support (lists, tables, images, headlines, etc.)
    class Indexer < Visitor
      # AST-owned resolution table for this chapter -- the single index the rest
      # of the pipeline reads (see ChapterIndexRegistry, doc/design-improvements
      # #7/#8). The Indexer no longer builds any legacy ReVIEW::Book::*Index.
      attr_reader :registry

      def initialize(chapter)
        super()
        @chapter = chapter
        @book = chapter.book
        @registry = ChapterIndexRegistry.new
        initialize_counters
      end

      # Record an element in the AST-owned registry.
      def register(type, id, number:, caption_node: nil, footnote_node: nil)
        @registry.add(type, id, number: number, caption_node: caption_node, footnote_node: footnote_node)
      end

      # Main index building method
      # Traverses the AST and builds all indexes
      def build_indexes(ast_root)
        return self unless ast_root

        # Extract and set chapter title from first level-1 headline (for Markdown files)
        extract_and_set_chapter_title(ast_root)

        visit(ast_root)

        self
      end

      # Set the chapter title from the AST, making the AST the single authority
      # for it rather than deferring to ReVIEW::Book::BookUnit#title (whose parser
      # only understands Re:VIEW "=" headlines). The title is the first headline's
      # raw_caption -- the source-faithful caption of the chapter's first heading,
      # in document order, at any level. For Re:VIEW this reproduces BookUnit#title
      # byte-for-byte (both take the first "=+" line's caption, markers stripped,
      # markup kept raw); pinned by test/ast/test_chapter_title.rb.
      def extract_and_set_chapter_title(ast_root)
        headline = find_first_headline(ast_root)
        return unless headline&.raw_caption

        @chapter.instance_variable_set(:@title, headline.raw_caption)
      end

      private

      def visit_caption_children(node)
        visit_all(node.caption_node.children) if node.caption_node
      end

      # Extract footnote content from FootnoteNode
      def extract_footnote_content(node)
        node.to_inline_text
      end

      def initialize_counters
        # Footnotes/endnotes keep the AST's own reference-order-numbering index
        # (not a legacy ReVIEW::Book index); the number comes from #number(id).
        @footnote_index = AST::FootnoteIndex.new
        @endnote_index = AST::FootnoteIndex.new

        # Definition numbers were previously derived from each legacy index's
        # size; a plain per-type counter replicates that. //image and //graph
        # share the image counter; //indepimage, //numberlessimage and the
        # //imgtable image share the indepimage counter (matching IndexBuilder).
        @number = Hash.new(0)

        @sec_counter = ReVIEW::AST::SectionCounter.new(6, @chapter) # 6 is max level

        # Build the headline item id exactly like IndexBuilder.
        @headline_stack = []
      end

      # Next 1-based number for a counted definition type.
      def next_number(type)
        @number[type] += 1
      end

      def visit_document(node)
        visit_all(node.children)
      end

      def visit_paragraph(node)
        visit_all(node.children)
      end

      def visit_text(node)
        # Text nodes have no children and don't contribute to indexes
      end

      def visit_list(node)
        visit_all(node.children)
      end

      def visit_list_item(node)
        visit_all(node.term_children) if node.term_children&.any?
        visit_all(node.children)
      end

      def visit_caption(node)
        visit_all(node.children)
      end

      def visit_code_line(node)
        visit_all(node.children)
      end

      def visit_table_row(node)
        visit_all(node.children)
      end

      def visit_table_cell(node)
        visit_all(node.children)
      end

      def visit_reference(node)
        visit_all(node.children)
      end

      def visit_headline(node)
        check_id(node.label)
        # IndexBuilder advances the section counter in #headline only.
        # [nonum]/[notoc]/[nodisp] go to nonum_begin/notoc_begin/nodisp_begin,
        # which register the heading with a nil number and leave the counter
        # alone. Advancing it here shifted the number of every later heading,
        # so a reference to one resolved to the wrong anchor.
        numbered = !(node.nonum? || node.notoc? || node.nodisp?)
        @sec_counter.inc(node.level) if numbered

        if node.level >= 2
          # Build item_id exactly like IndexBuilder
          cursor = node.level - 2
          @headline_stack ||= []
          caption_text = extract_caption_text(node.caption_node)
          @headline_stack[cursor] = (node.label || caption_text)
          if @headline_stack.size > cursor + 1
            @headline_stack = @headline_stack.take(cursor + 1)
          end

          item_id = @headline_stack.join('|')
          leaf_id = @headline_stack[cursor]
          number = numbered ? @sec_counter.number_list : nil

          # A headline is addressable both by its full pipe-path and by its leaf
          # segment alone (its label or caption), matching Book::HeadlineIndex.
          register(:headline, item_id, number: number, caption_node: node.caption_node)
          register(:headline, leaf_id, number: number, caption_node: node.caption_node) unless leaf_id == item_id

          visit_caption_children(node)
        end

        visit_all(node.children)
      end

      def visit_column(node)
        # Extract caption text like IndexBuilder does
        caption_text = extract_caption_text(node.caption_node)

        # Use label if available, otherwise use caption as ID (like IndexBuilder does)
        item_id = node.label || caption_text

        check_id(node.label) if node.label

        register(:column, item_id, number: next_number(:column), caption_node: node.caption_node)

        visit_caption_children(node)
        visit_all(node.children)
      end

      # Stamp a DefinitionNumber onto a numbered definition node, so renderers
      # read the number off the node instead of the legacy @chapter index. The
      # chapter part mirrors Renderer::Base#get_chap (secnolevel/appendix aware).
      def stamp_definition_number(node, number)
        node.definition_number = DefinitionNumber.new(number: number, chapter_number: definition_chapter_number)
      end

      # Formatted chapter-number prefix for definition captions, or nil when none
      # applies (secnolevel 0, or a chapter without a number). Classification and
      # formatting are shared with the renderers (RenderContext.chapter_type and
      # ChapterNumberFormatter), so the compile side no longer re-derives Part-ness
      # or calls Chapter#format_number.
      def definition_chapter_number
        return @definition_chapter_number if defined?(@definition_chapter_number)

        @definition_chapter_number =
          if @book.config['secnolevel'].to_i > 0 && @chapter.number && !@chapter.number.to_s.empty?
            ChapterNumberFormatter.definition_prefix(
              @chapter.number, RenderContext.chapter_type(@chapter)
            )
          end
      end

      def visit_code_block(node)
        if node.id?
          check_id(node.id)
          number = next_number(:list)
          register(:list, node.id, number: number)
          stamp_definition_number(node, number)

          visit_caption_children(node)
        end

        visit_all(node.children)
      end

      def visit_table(node)
        if node.id?
          check_id(node.id)
          number = next_number(:table)
          register(:table, node.id, number: number, caption_node: node.caption_node)
          stamp_definition_number(node, number)

          # An //imgtable also consumes an indepimage number (like IndexBuilder).
          # The image path is stamped later by ImagePathProcessor; here we record
          # the number an unbound imgtable would show if rendered as an image.
          if node.table_type == :imgtable
            image_number = next_number(:indepimage)
            register(:indepimage, node.id, number: image_number)
            node.imgtable_image_number = ReVIEW::AST::DefinitionNumber.new(
              number: image_number, chapter_number: @chapter&.number
            )
          end

          visit_caption_children(node)
        end

        visit_all(node.children)
      end

      def visit_image(node)
        if node.id?
          check_id(node.id)
          # Only //image is numbered (the image counter). //indepimage and
          # //numberlessimage are unnumbered and take an indepimage number,
          # matching IndexBuilder (#image/#indepimage/#numberlessimage). Sharing
          # one counter would make a later //image's @<img> reference off by the
          # indepimage count.
          case node.image_type
          when :indepimage, :numberlessimage
            register(:indepimage, node.id, number: next_number(:indepimage))
          else
            number = next_number(:image)
            register(:image, node.id, number: number, caption_node: node.caption_node)
            stamp_definition_number(node, number)
          end

          visit_caption_children(node)
        end

        visit_all(node.children)
      end

      def visit_minicolumn(node)
        # Minicolumns are typically indexed by their type and content
        visit_caption_children(node)

        visit_all(node.children)
      end

      def visit_embed(node)
        case node.embed_type
        when :block
          # Embed blocks contain raw content that shouldn't be processed for inline elements
          # since it's meant to be output as-is for specific formats
        end

        visit_all(node.children)
      end

      def visit_footnote(node)
        check_id(node.id)

        footnote_content = extract_footnote_content(node)

        if node.footnote_type == :footnote
          @footnote_index.add_or_update(node.id, content: footnote_content, footnote_node: node)
          register(:footnote, node.id, number: @footnote_index.number(node.id), footnote_node: node)
          stamp_definition_number(node, @footnote_index.number(node.id))
        elsif node.footnote_type == :endnote
          @endnote_index.add_or_update(node.id, content: footnote_content, footnote_node: node)
          register(:endnote, node.id, number: @endnote_index.number(node.id), footnote_node: node)
          stamp_definition_number(node, @endnote_index.number(node.id))
        end

        visit_all(node.children)
      end

      def visit_tex_equation(node)
        if node.id?
          check_id(node.id)
          number = next_number(:equation)
          register(:equation, node.id, number: number, caption_node: node.caption_node)
          stamp_definition_number(node, number)
        end

        visit_all(node.children)
      end

      def visit_block(node)
        if node.block_type
          case node.block_type.to_s
          when 'bibpaper'
            if node.args.length >= 2
              bib_id = node.args[0]
              check_id(bib_id)
              number = next_number(:bibpaper)
              register(:bibpaper, bib_id, number: number, caption_node: node.caption_node)
              stamp_definition_number(node, number)
            end
          when 'graph'
            # //graph[id][command][caption] renders as a numbered image, so it
            # shares the image counter and gets a stamped definition_number
            # (matching the legacy ImageIndex, whose item_type is image|graph|
            # imgtable). Its file is generated at render time, so no path here.
            if node.args.first
              graph_id = node.args.first
              check_id(graph_id)
              number = next_number(:image)
              register(:image, graph_id, number: number, caption_node: node.caption_node)
              stamp_definition_number(node, number)
            end
          end
        end

        visit_caption_children(node)
        visit_all(node.children)
      end

      def visit_inline(node)
        case node.inline_type
        when :fn
          if node.args.first
            footnote_id = node.args.first
            check_id(footnote_id)
            # Add reference entry (content is filled when the FootnoteNode is seen).
            @footnote_index.add_or_update(footnote_id)
          end
        when :endnote
          if node.args.first
            endnote_id = node.args.first
            check_id(endnote_id)
            @endnote_index.add_or_update(endnote_id)
          end
        when :bib
          if node.args.first
            bib_id = node.args.first
            check_id(bib_id)
            # A bibpaper may be referenced by @<bib> without a parseable definition
            # (the bib file's one-line form isn't indexed by the compiler), so a
            # reference auto-registers the id, numbered by first-reference order.
            # This mirrors IndexBuilder and keeps the registry in sync.
            unless @registry.key?(:bibpaper, bib_id)
              register(:bibpaper, bib_id, number: next_number(:bibpaper), caption_node: nil)
            end
          end
        when :eq
          if node.args.first
            eq_id = node.args.first
            check_id(eq_id)
          end
        when :img, :icon
          # Image / icon references resolve to a path at compile time
          # (ImagePathProcessor); no index entry is needed here.
        when :list, :table
          # These are references, already processed in their respective nodes
        end

        visit_all(node.children)
      end

      # Find the first headline node in document order (pre-order), at any level.
      # This mirrors BookUnit#title, which takes the first "=+" line regardless of
      # level. Columns are ColumnNode, not HeadlineNode, so they are skipped.
      # @param node [Node] The node to search
      # @return [HeadlineNode, nil] The found headline or nil
      def find_first_headline(node)
        return node if node.is_a?(HeadlineNode)

        return nil unless node.respond_to?(:children)

        node.children.each do |child|
          result = find_first_headline(child)
          return result if result
        end

        nil
      end

      # Extract plain text from caption node
      def extract_caption_text(caption_node)
        caption_node&.to_inline_text || ''
      end

      # ID validation (same as IndexBuilder)
      def check_id(id)
        if id
          # Check for various deprecated characters
          id.scan(%r![#%\\{}\[\]~/$'"|*?&<>`\s]!) do |char|
            warn "deprecated ID: `#{char}` in `#{id}`"
          end

          if id.start_with?('.')
            warn "deprecated ID: `#{id}` begins from `.`"
          end
        end
      end

      # Warning output
      def warn(message)
        # For now, just output to stderr
        # In a real implementation, this should use the proper logging system
        $stderr.puts "WARNING: #{message}"
      end
    end
  end
end
