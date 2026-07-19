# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'reference_node'
require_relative 'resolved_data'
require_relative 'render_context'
require_relative 'inline_node'
require_relative 'indexer'
require_relative 'chapter_registry_provider'
require_relative 'visitor'
require 'review/exception'

module ReVIEW
  module AST
    # ReferenceResolver - Specialized class for reference resolution
    #
    # Traverses ReferenceNodes contained in AST and resolves them to
    # appropriate reference content using index information.
    class ReferenceResolver < Visitor
      # Default mapping of reference types to resolver methods
      DEFAULT_RESOLVER_METHODS = {
        img: :resolve_image_ref,
        imgref: :resolve_image_ref,
        table: :resolve_table_ref,
        list: :resolve_list_ref,
        eq: :resolve_equation_ref,
        fn: :resolve_footnote_ref,
        endnote: :resolve_endnote_ref,
        column: :resolve_column_ref,
        chap: :resolve_chapter_ref,
        chapref: :resolve_chapter_ref_with_title,
        title: :resolve_chapter_title,
        hd: :resolve_headline_ref,
        sec: :resolve_section_ref,
        secref: :resolve_section_ref,
        sectitle: :resolve_section_ref,
        labelref: :resolve_label_ref,
        ref: :resolve_label_ref,
        w: :resolve_word_ref,
        wb: :resolve_word_ref,
        bib: :resolve_bib_ref,
        bibref: :resolve_bib_ref
      }.freeze

      # The resolved-data class for each indexed item type. Spelling the pairs
      # out keeps the registry key and the class visible in one place, instead
      # of relying on a label and a factory method happening to share a name.
      INDEXED_ITEM_CLASSES = {
        image: ResolvedData::ImageReference,
        table: ResolvedData::TableReference,
        list: ResolvedData::ListReference,
        column: ResolvedData::ColumnReference
      }.freeze

      # @param chapter [Book::Chapter] The chapter whose references are resolved
      # @param registry_provider [ChapterRegistryProvider] Source of the index
      #   table for any chapter this one refers to. Pass a provider shared across
      #   a book build to index each chapter once; the default indexes on demand
      #   for this resolver alone.
      def initialize(chapter, registry_provider: ChapterRegistryProvider.new)
        super()
        @chapter = chapter
        @book = chapter.book
        @registry_provider = registry_provider
        @resolver_methods = DEFAULT_RESOLVER_METHODS.dup
      end

      # Resolve every reference in the tree, replacing each ReferenceNode with a
      # resolved copy. Resolution is fail-fast: an unresolvable reference raises
      # CompileError rather than being counted and skipped.
      # @param ast [Node] The tree to resolve
      # @return [Integer] Number of references resolved
      def resolve_references(ast)
        # Build indexes for current chapter from AST. This also stamps the AST
        # nodes, sets chapter title for Markdown files, and yields the AST-owned
        # ChapterIndexRegistry the resolution reads from (doc/design-improvements
        # #7 -- instead of reading back the legacy Book::Index / Index::Item).
        @registry = build_indexes_from_ast(ast)
        # This chapter is indexed right here, so hand that table to the provider
        # rather than letting it compile the same chapter again.
        @registry_provider.seed(@chapter, @registry)

        @resolve_count = 0

        visit(ast)

        @resolve_count
      end

      # The AST index registry for a chapter, from the provider.
      def registry_for(chapter)
        @registry_provider.registry_for(chapter)
      end

      # AST index registry of the book's bib file (bibpapers are book-wide and
      # usually live there), built on demand. Bibpapers defined inside a chapter
      # are found via that chapter's registry instead (see resolve_bib_ref).
      def bib_file_registry
        @bib_file_registry ||=
          if @book.bib_exist?
            bib = ReVIEW::Book::Bib.new(file_content: @book.bib_content, book: @book)
            registry_for(bib)
          else
            ChapterIndexRegistry.new
          end
      end

      # Register a new reference type resolver
      # @param ref_type [Symbol] The reference type (e.g., :custom)
      # @param resolver_method [Symbol] The method name to handle this reference type
      # @example
      #   resolver.register_resolver_method(:custom, :resolve_custom_ref)
      def register_resolver_method(ref_type, resolver_method)
        @resolver_methods[ref_type.to_sym] = resolver_method
      end

      private

      def visit_all_with_caption(node)
        visit(node.caption_node) if node.respond_to?(:caption_node) && node.caption_node
        visit_all(node.children)
      end

      def build_indexes_from_ast(ast)
        indexer = Indexer.new(@chapter)
        indexer.build_indexes(ast)
        indexer.registry
      end

      # Resolve ReferenceNode (ref_type taken from parent InlineNode) and swap in
      # the resolved copy. Raises CompileError if the reference cannot be resolved.
      # @param node [ReferenceNode] The reference node to resolve
      # @param ref_type [Symbol] The reference type (e.g., :img, :table, :list)
      def resolve_node(node, ref_type)
        method_name = @resolver_methods[ref_type]
        raise CompileError, "Unknown reference type: #{ref_type}" unless method_name

        resolved_node = node.with_resolved_data(send(method_name, node))
        node.parent&.replace_child(node, resolved_node)
      end

      def visit_document(node)
        visit_all(node.children)
      end

      def visit_paragraph(node)
        visit_all(node.children)
      end

      def visit_text(node)
      end

      def visit_headline(node)
        visit_all_with_caption(node)
      end

      def visit_column(node)
        visit_all_with_caption(node)
      end

      def visit_code_block(node)
        visit_all_with_caption(node)
      end

      def visit_table(node)
        visit_all_with_caption(node)
      end

      def visit_image(node)
        visit_all_with_caption(node)
      end

      def visit_minicolumn(node)
        visit_all_with_caption(node)
      end

      def visit_embed(node)
        visit_all(node.children)
      end

      def visit_footnote(node)
        visit_all(node.children)
      end

      def visit_tex_equation(node)
        visit_all_with_caption(node)
      end

      def visit_block(node)
        visit_all_with_caption(node)
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

      def visit_inline(node)
        visit_all(node.children)
      end

      def visit_reference(node)
        return if node.resolved?

        parent_inline = node.parent
        return unless parent_inline.is_a?(InlineNode)

        ref_type = parent_inline.inline_type

        # Skip non-reference inline elements (decoration elements)
        # Only process elements that are registered as reference types
        return unless @resolver_methods.key?(ref_type.to_sym)

        resolve_node(node, ref_type.to_sym)
        @resolve_count += 1
      end

      # Generic method to resolve indexed item references (image, table, list, etc.)
      # @param node [ReferenceNode] The reference node containing ref_id and context_id
      # @param item_type_label [Symbol] Registry key, also used in error messages (e.g., :image, :table, :list)
      # @return [ResolvedData] The resolved reference data
      def resolve_indexed_item_ref(node, item_type_label)
        target_chapter = target_chapter_for(node)
        raise CompileError, "Chapter not found for #{item_type_label} reference: #{node.context_id}" unless target_chapter

        entry = registry_for(target_chapter).lookup(item_type_label, node.ref_id)
        raise CompileError, "#{item_type_label.to_s.capitalize} reference not found: #{node.full_ref_id}" unless entry

        INDEXED_ITEM_CLASSES.fetch(item_type_label).new(
          chapter_number: target_chapter.number,
          item_number: entry_number(entry),
          chapter_id: node.context_id,
          item_id: node.ref_id,
          chapter_type: chapter_type(target_chapter),
          caption_node: entry.caption_node
        )
      end

      def resolve_image_ref(node)
        resolve_indexed_item_ref(node, :image)
      end

      def resolve_table_ref(node)
        resolve_indexed_item_ref(node, :table)
      end

      def resolve_list_ref(node)
        resolve_indexed_item_ref(node, :list)
      end

      def resolve_equation_ref(node)
        entry = registry_for(@chapter).lookup(:equation, node.ref_id)
        unless entry
          raise CompileError, "Equation reference not found: #{node.ref_id}"
        end

        ResolvedData.equation(
          chapter_number: @chapter.number,
          item_number: entry_number(entry),
          item_id: node.ref_id,
          chapter_type: chapter_type(@chapter),
          caption_node: entry.caption_node
        )
      end

      def resolve_footnote_ref(node)
        entry = registry_for(@chapter).lookup(:footnote, node.ref_id)
        unless entry
          raise CompileError, "Footnote reference not found: #{node.ref_id}"
        end

        # The footnote's definition node is the "caption" the renderers render.
        ResolvedData.footnote(
          item_number: entry.number,
          item_id: node.ref_id,
          caption_node: entry.footnote_node
        )
      end

      def resolve_endnote_ref(node)
        entry = registry_for(@chapter).lookup(:endnote, node.ref_id)
        unless entry
          raise CompileError, "Endnote reference not found: #{node.ref_id}"
        end

        ResolvedData.endnote(
          item_number: entry.number,
          item_id: node.ref_id,
          caption_node: entry.footnote_node
        )
      end

      def resolve_column_ref(node)
        target_chapter = target_chapter_for(node)
        raise CompileError, "Chapter not found for column reference: #{node.context_id}" unless target_chapter

        entry = registry_for(target_chapter).lookup(:column, node.ref_id)
        raise CompileError, "Column reference not found: #{node.ref_id}" unless entry

        ResolvedData.column(
          chapter_number: target_chapter.number,
          item_number: entry_number(entry),
          chapter_id: node.context_id,
          item_id: node.ref_id,
          chapter_type: chapter_type(target_chapter),
          caption_node: entry.caption_node
        )
      end

      # Resolve chapter references (for @<chap>, @<chapref>, @<title>)
      # These all resolve to the same ResolvedData::ChapterReference, but renderers
      # format them differently based on the inline type
      def resolve_chapter_ref(node)
        resolve_chapter_ref_common(node)
      end

      def resolve_chapter_ref_with_title(node)
        resolve_chapter_ref_common(node)
      end

      def resolve_chapter_title(node)
        resolve_chapter_ref_common(node)
      end

      def resolve_chapter_ref_common(node)
        chapter = find_chapter_by_id(node.ref_id)
        raise CompileError, "Chapter reference not found: #{node.ref_id}" unless chapter

        ResolvedData.chapter(
          chapter_number: chapter.number,
          chapter_id: node.ref_id,
          item_id: node.ref_id,
          chapter_title: chapter.title,
          chapter_type: chapter_type(chapter)
        )
      end

      def resolve_headline_ref(node)
        target_chapter = target_chapter_for(node)
        raise CompileError, "Chapter not found for headline reference: #{node.context_id}" if node.cross_chapter? && !target_chapter

        entry = registry_for(target_chapter)&.lookup(:headline, node.ref_id)
        raise CompileError, "Headline not found: #{node.full_ref_id}" unless entry

        ResolvedData.headline(
          headline_number: entry.number,
          chapter_number: target_chapter&.number,
          chapter_id: node.context_id,
          item_id: node.ref_id,
          chapter_type: chapter_type(target_chapter),
          caption_node: entry.caption_node
        )
      end

      def resolve_section_ref(node)
        # Section references use the same data structure as headline references
        # Renderers will format appropriately (e.g., adding "節" for secref)
        resolve_headline_ref(node)
      end

      # Label references search multiple indexes (by priority order)
      # Try to find the label in various indexes and return appropriate ResolvedData
      def resolve_label_ref(node)
        registry = registry_for(@chapter)
        common = { chapter_number: @chapter.number, item_id: node.ref_id, chapter_type: chapter_type(@chapter) }

        if (entry = registry.lookup(:image, node.ref_id))
          return ResolvedData.image(**common, item_number: entry_number(entry), caption_node: entry.caption_node)
        end
        if (entry = registry.lookup(:table, node.ref_id))
          return ResolvedData.table(**common, item_number: entry_number(entry), caption_node: entry.caption_node)
        end
        if (entry = registry.lookup(:list, node.ref_id))
          return ResolvedData.list(**common, item_number: entry_number(entry), caption_node: entry.caption_node)
        end
        if (entry = registry.lookup(:equation, node.ref_id))
          return ResolvedData.equation(**common, item_number: entry_number(entry), caption_node: entry.caption_node)
        end

        if (entry = registry.lookup(:headline, node.ref_id))
          return ResolvedData.headline(chapter_number: @chapter.number, item_id: node.ref_id,
                                       chapter_type: chapter_type(@chapter),
                                       headline_number: entry.number, caption_node: entry.caption_node)
        end
        if (entry = registry.lookup(:column, node.ref_id))
          return ResolvedData.column(**common, item_number: entry_number(entry), caption_node: entry.caption_node)
        end

        # TODO: Support for other labeled elements (note, memo, tip, etc.)
        # Currently there are no dedicated indexes for these elements,
        # so we need to add label_index in the future

        raise CompileError, "Label not found: #{node.ref_id}"
      end

      # Stringified item number from a registry Entry (matching the legacy
      # index-item number formatting), or nil.
      def entry_number(entry)
        return unless entry

        entry.number.nil? ? nil : entry.number.to_s
      end

      def resolve_word_ref(node)
        dictionary = @book.config['dictionary'] || {}
        unless dictionary.key?(node.ref_id)
          raise CompileError, "word not bound: #{node.ref_id}"
        end

        ResolvedData.word(
          word_content: dictionary[node.ref_id],
          item_id: node.ref_id
        )
      end

      # Bibpapers are book-wide. They usually live in the book's bib file, but can
      # also be defined inside a chapter, so look in the current chapter's registry
      # first and fall back to the bib file's.
      def resolve_bib_ref(node)
        entry = registry_for(@chapter).lookup(:bibpaper, node.ref_id) ||
                bib_file_registry.lookup(:bibpaper, node.ref_id)
        raise CompileError, "unknown bib: #{node.ref_id}" unless entry

        ResolvedData.bibpaper(
          item_number: entry_number(entry),
          item_id: node.ref_id,
          caption_node: entry.caption_node
        )
      end

      # Get target chapter for a reference node
      # Returns the referenced chapter if context_id is present, otherwise current chapter
      # @param node [ReferenceNode] The reference node
      # @return [Chapter] The target chapter
      def target_chapter_for(node)
        node.cross_chapter? ? find_chapter_by_id(node.context_id) : @chapter
      end

      def find_chapter_by_id(id)
        begin
          item = @book.chapter_index[id]
          return item.content if item
        rescue ReVIEW::KeyError
          # fall through to contents search
        end

        Array(@book.contents).find { |chap| chap.id == id }
      end

      # Determine chapter type based on chapter attributes
      # @param chapter [Chapter] The chapter to check
      # @return [Symbol] One of :chapter, :appendix, :part, :predef
      def chapter_type(chapter)
        ReVIEW::AST::RenderContext.chapter_type(chapter)
      end
    end
  end
end
