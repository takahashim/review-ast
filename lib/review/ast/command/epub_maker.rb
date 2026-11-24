# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/epubmaker'
require 'review/ast/stylesheet_resolver'
require_relative 'ast_html_converter'
require 'review/ast/book_unit_view'

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

        # The base maker copies stylesheets from the book root only; resolve
        # them through the AST search path (root, css/, bundled) instead.
        def copy_stylesheet(basetmpdir)
          ReVIEW::AST::StylesheetResolver.new(@config['stylesheet']).copy_to(basetmpdir) do |name|
            @producer.contents.push(ReVIEW::EPUBMaker::Content.new(file: name))
          end
        rescue ReVIEW::AST::StylesheetResolver::Error => e
          error! e.message
        end

        # The base EPUBMaker#build_body, with every part and chapter passed
        # through BookUnitView so a Markdown book is laid out like a .re one
        # (page names, chapter types, part files). Otherwise as in the base.
        def build_body(basetmpdir, yamlfile)
          @precount = 0
          @bodycount = 0
          @postcount = 0

          @manifeststr = ''
          @ncxstr = ''
          @tocdesc = []
          @img_graph = ReVIEW::ImgGraph.new(@config, 'html', path_name: '_review_graph')

          basedir = File.dirname(yamlfile)
          base_path = Pathname.new(basedir)
          book = ReVIEW::Book::Base.new(basedir, config: @config)
          @compile_errors = nil

          book.parts.each do |part|
            part = BookUnitView.wrap(part)
            if part.name.present?
              if part.file?
                build_chap(part, base_path, basetmpdir, true)
              else
                build_part_page(part, basetmpdir)
              end
            end

            part.chapters.each do |chap|
              build_chap(BookUnitView.wrap(chap), base_path, basetmpdir, false)
            end
          end
          check_compile_status

          begin
            @img_graph.make_mermaid_images
          rescue ApplicationError => e
            error! e.message
          end
          @img_graph.cleanup_graphimg
        end

        # A part named in the catalog only: a title page, as the base maker
        # makes it.
        def build_part_page(part, basetmpdir)
          htmlfile = "part_#{part.number}.#{@config['htmlext']}"
          build_part(part, basetmpdir, htmlfile)
          title = ReVIEW::I18n.t('part', part.number)
          title += ReVIEW::I18n.t('chapter_postfix') + part.name.strip if part.name.strip.present?
          @htmltoc.add_item(0, htmlfile, title, chaptype: 'part')
          write_buildlogtxt(basetmpdir, htmlfile, '')
        end

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
    end
  end
end
