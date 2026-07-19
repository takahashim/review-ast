# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/epubmaker'
require 'review/ast'
require 'review/renderer/html_renderer'

module ReVIEW
  module AST
    module Command
      # EPUBMaker that renders each chapter's XHTML with the AST HtmlRenderer
      # instead of the legacy Converter + HTMLBuilder.
      #
      # All EPUB packaging -- OPF / NCX / nav, the mimetype, container.xml, the
      # TOC, stylesheet and image copying, mermaid image generation, and the final
      # zip -- is reused unchanged from ReVIEW::EPUBMaker. The base maker touches
      # @converter in exactly one place (build_chap, to turn one .re file into one
      # .xhtml file), so swapping @converter there is the whole port: everything
      # else runs as-is. The full-page render uses the same layout templates the
      # base maker would (config.maker is 'epubmaker', not 'webmaker', so both pick
      # html/layout*.erb), so the output matches the legacy maker (HTML is
      # rendered-equivalent, not byte-identical).
      class EPUBMaker < ReVIEW::EPUBMaker
        private

        def build_chap(chap, base_path, basetmpdir, ispart)
          @converter = ast_converter
          super
        end

        def ast_converter
          @ast_converter ||= AstHtmlConverter.new(
            ReVIEW::Book::Base.new(@basedir, config: @config),
            img_math: @img_math
          )
        end
      end

      # Renders one chapter's full XHTML with the AST HtmlRenderer, exposing the
      # ReVIEW::Converter#convert(file, output_path) interface the base EPUBMaker
      # calls in build_chap.
      class AstHtmlConverter
        def initialize(book, img_math:)
          @book = book
          # Match ReVIEW::Converter.new, which sets the builder so image paths
          # resolve under <imagedir>/html/... as the legacy converter would.
          @book.config['builder'] = 'html'
          @img_math = img_math
        end

        def convert(file, output_path)
          chapter = find_chapter(file)
          raise ReVIEW::ApplicationError, "chapter not found for #{file}" unless chapter

          compiler = ReVIEW::AST::Compiler.for_chapter(chapter)
          ast_root = compiler.compile_to_ast(chapter)
          renderer = ReVIEW::Renderer::HtmlRenderer.new(chapter, img_math: @img_math)
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
