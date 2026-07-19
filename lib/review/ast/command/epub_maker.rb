# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/epubmaker'
require_relative 'ast_html_converter'

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
    end
  end
end
