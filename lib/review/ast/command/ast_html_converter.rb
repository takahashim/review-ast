# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast'
require 'review/renderer/html_renderer'

module ReVIEW
  module AST
    module Command
      # Renders one chapter's full-page HTML with the AST HtmlRenderer, exposing
      # the ReVIEW::Converter#convert(file, output_path) interface the legacy HTML
      # makers (EPUB, Web) call in build_chap. The layout (plain html vs webmaker
      # sidebar) is chosen by HtmlRenderer from config.maker, so the same converter
      # serves both makers.
      class AstHtmlConverter
        def initialize(book, img_math:, web_toc: nil)
          @book = book
          # Match ReVIEW::Converter.new, which sets the builder so image paths
          # resolve under <imagedir>/html/... as the legacy converter would.
          @book.config['builder'] = 'html'
          @img_math = img_math
          @web_toc = web_toc
        end

        def convert(file, output_path)
          chapter = find_chapter(file)
          raise ReVIEW::ApplicationError, "chapter not found for #{file}" unless chapter

          compiler = ReVIEW::AST::Compiler.for_chapter(chapter)
          ast_root = compiler.compile_to_ast(chapter)
          renderer = ReVIEW::Renderer::HtmlRenderer.new(chapter, img_math: @img_math, web_toc: @web_toc)
          File.write(output_path, renderer.render(ast_root))
        end

        private

        def find_chapter(file)
          basename = File.basename(file, '.*')
          @book.chapters.find { |ch| File.basename(ch.path, '.*') == basename } ||
            @book.parts_in_file.find { |part| File.basename(part.path, '.*') == basename }
        end
      end
    end
  end
end
