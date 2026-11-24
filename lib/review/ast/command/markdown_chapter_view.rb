# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'delegate'
require 'review/ast/render_context'

module ReVIEW
  module AST
    module Command
      # A Markdown chapter as the legacy HTML makers' build_chap expects a
      # chapter to look.
      #
      # EPUBMaker#build_chap and WEBMaker#build_chap name the output after the
      # source file with `.sub(/\.re\Z/, '')`, so ch01.md became ch01.md.xhtml
      # -- while every link the renderer writes to that chapter (@<chap>,
      # @<hd>, the TOC) points at ch01.xhtml, the name a .re chapter gets.
      # They also classify the chapter with on_predef?/on_appendix?, which miss
      # Markdown entries (see RenderContext.catalog_section).
      #
      # The view reports the path with a .re extension, which gives the output
      # its ordinary name (AstHtmlConverter finds the chapter by basename, so
      # the conversion itself still reads the .md file), and answers the
      # catalog-section questions from RenderContext.
      class MarkdownChapterView < SimpleDelegator
        def self.wrap(chapter)
          chapter.respond_to?(:path) && chapter.path.to_s.end_with?('.md') ? new(chapter) : chapter
        end

        def path
          __getobj__.path.sub(/\.md\z/, '.re')
        end

        def on_predef?
          section == :predef
        end

        def on_appendix?
          section == :appendix
        end

        def on_postdef?
          section == :postdef
        end

        private

        def section
          ReVIEW::AST::RenderContext.catalog_section(__getobj__)
        end
      end
    end
  end
end
