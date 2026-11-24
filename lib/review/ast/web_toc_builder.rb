# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/htmlutils'
require 'review/sec_counter'
require_relative 'compiler'
require_relative 'headline_node'
require_relative 'section_counter'
require_relative 'chapter_title'

module ReVIEW
  module AST
    # Builds the web sidebar table of contents down to section level from the AST
    # (doc/refactor-webmaker.ja.md step 3). The gem's WEBTOCPrinter stops at
    # part/chapter; walking each chapter's headline tree lets the site show
    # sections and link straight to them.
    #
    # Section anchors must match what HtmlRenderer emits, so this replays the same
    # ReVIEW::SecCounter walk the renderer uses (SecCounter.new(5, chapter), inc
    # per numbered headline, "h#{anchor}") and mirrors its nonum/notoc/nodisp
    # branch (those do not advance the counter and use their label/auto_id as the
    # fragment; notoc/nodisp are kept out of the TOC).
    class WebTocBuilder
      include ReVIEW::HTMLUtils

      # Include headlines down to this level (2 = section, 3 = subsection).
      def initialize(book, max_level: 3)
        @book = book
        @max_level = max_level
        @htmlext = book.config['htmlext'] || 'html'
      end

      def build
        items = [%Q(<ul class="book-toc">), %Q(<li><a href="index.#{@htmlext}">TOP</a></li>)]
        @book.parts.each do |part|
          if part.name.present?
            items << if part.file?
                       chapter_li(part)
                     else
                       %Q(<li>#{escape(part_label(part))}</li>)
                     end
          end
          part.chapters.each { |chap| items << chapter_li(chap) }
        end
        items << '</ul>'
        items.join("\n")
      end

      private

      def chapter_li(chap)
        href = "#{chap.id}.#{@htmlext}"
        ast = compile(chap)
        sections = section_entries(chap, ast)
        inner = sections.empty? ? '' : "\n#{render_sections(sections, href)}\n"
        %Q(<li><a href="#{href}">#{escape(chapter_label(chap, ast))}</a>#{inner}</li>)
      end

      def compile(chap)
        ReVIEW::AST::Compiler.for_chapter(chap).compile_to_ast(chap, reference_resolution: false)
      end

      # [{level:, fragment:, text:}, ...] in document order, sections only.
      def section_entries(chap, ast = compile(chap))
        sec_counter = ReVIEW::AST::SectionCounter.new(5, chap)
        entries = []
        each_headline(ast) do |node|
          if node.nonum? || node.notoc? || node.nodisp?
            next if node.notoc? || node.nodisp?

            fragment = normalize_id(node.label || node.auto_id)
          else
            sec_counter.inc(node.level)
            fragment = "h#{sec_counter.anchor(node.level)}"
          end
          next unless node.level.between?(2, @max_level)

          entries << { level: node.level, fragment: fragment, text: node.caption_node&.to_inline_text.to_s }
        end
        entries
      end

      # Nest the flat, document-ordered section entries into a tree by level, then
      # render it, so the <ul>/<li> nesting is always well-formed regardless of
      # skipped levels.
      def render_sections(entries, href)
        root = { children: [] }
        stack = [{ level: 1, node: root }]
        entries.each do |e|
          node = { entry: e, children: [] }
          stack.pop while stack.last[:level] >= e[:level]
          stack.last[:node][:children] << node
          stack.push({ level: e[:level], node: node })
        end
        render_tree(root[:children], href)
      end

      def render_tree(nodes, href)
        return '' if nodes.empty?

        out = +'<ul>'
        nodes.each do |n|
          e = n[:entry]
          out << %Q(<li><a href="#{href}##{e[:fragment]}">#{escape(e[:text])}</a>)
          out << render_tree(n[:children], href)
          out << '</li>'
        end
        out << '</ul>'
        out
      end

      def each_headline(node, &block)
        yield(node) if node.is_a?(HeadlineNode)
        return unless node.respond_to?(:children)

        node.children.each { |child| each_headline(child, &block) }
      end

      # Chapter#format_number misses Markdown appendices (see
      # RenderContext.catalog_section), so number from the AST's own type.
      def chapter_label(chap, ast)
        num = ChapterNumberFormatter.full(chap.number, RenderContext.chapter_type(chap))
        title = chapter_title(chap, ast)
        num.empty? ? title : "#{num} #{title}"
      end

      # A Markdown chapter's title comes from its AST (ChapterTitle).
      def chapter_title(chap, ast)
        ChapterTitle.of(chap, ast)
      end

      def part_label(part)
        title = part.name.strip
        num = ReVIEW::I18n.t('part', part.number)
        title.empty? ? num : "#{num} #{title}"
      end
    end
  end
end
