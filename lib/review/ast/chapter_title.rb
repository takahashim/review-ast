# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'headline_node'

module ReVIEW
  module AST
    # A chapter's title where Re:VIEW's own BookUnit#title cannot see it.
    #
    # BookUnit#title parses Re:VIEW "=" headlines only, so a Markdown chapter's
    # title is empty there. The Indexer sets it from the AST when a chapter is
    # fully compiled; this gives the same answer (the first headline's
    # raw_caption) for code that only has a chapter, or an AST compiled without
    # reference resolution.
    module ChapterTitle
      module_function

      # @param chapter [ReVIEW::Book::Chapter, ReVIEW::Book::Part]
      # @param ast [DocumentNode, nil] the chapter's AST, compiled here if nil
      def of(chapter, ast = nil)
        title = chapter.title.to_s
        return title unless markdown?(chapter) || title.empty?
        # A part named in the catalog only (no file) is titled by that name.
        return title if ast.nil? && chapter.content.to_s.empty?

        ast ||= ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter, reference_resolution: false)
        first_headline(ast)&.raw_caption || title
      end

      # A Markdown chapter or part file. (Part#file? accepts ".re" names only,
      # so a Markdown part file is titled with its file name there.)
      def markdown?(chapter)
        chapter.respond_to?(:path) && chapter.path.to_s.end_with?('.md')
      end

      def first_headline(node)
        return node if node.is_a?(HeadlineNode)
        return unless node.respond_to?(:children)

        node.children.each do |child|
          found = first_headline(child)
          return found if found
        end
        nil
      end
    end
  end
end
