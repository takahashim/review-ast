# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'review/webmaker'
require 'review/ast/web_assets'
require_relative 'ast_html_converter'

module ReVIEW
  module AST
    module Command
      # WEBMaker that renders each chapter's HTML with the AST HtmlRenderer instead
      # of the legacy Converter + HTMLBuilder (doc/refactor-webmaker.ja.md step 1).
      #
      # Like the EPUB maker, the base WEBMaker touches @converter in exactly one
      # place -- build_chap, to turn one .re file into one .html -- so swapping it
      # there is the whole port; the rest (index page, titlepage, part pages,
      # stylesheet/image copy) runs unchanged. HtmlRenderer picks the webmaker
      # sidebar layout itself (config.maker == 'webmaker' -> layout-web.html.erb)
      # and fills the sidebar TOC in post_process, so chapter pages come out as the
      # legacy maker would render them.
      class WebMaker < ReVIEW::WEBMaker
        private

        def build_chap(chap, base_path, basetmpdir, ispart)
          @converter = ast_converter
          super
        end

        # The index / titlepage / part full pages are rendered by the base maker
        # (not through @converter), so point their default full-page layout at the
        # modern review-ast template too, keeping the whole site consistent. A
        # user's layouts/layout-web.html.erb still wins, and body partials
        # (systemfile given) keep the gem's templates.
        def template_name(localfile: 'layout-web.html.erb', systemfile: nil)
          if @basedir
            user_layout = File.join(@basedir, 'layouts', localfile)
            return user_layout if File.exist?(user_layout)
          end
          return super if systemfile

          ReVIEW::AST::WebAssets::LAYOUT_HTML5
        end

        # WEBMaker builds @book itself, so the converter reuses it (its chapter
        # order drives next/prev nav and the sidebar TOC).
        def ast_converter
          @ast_converter ||= AstHtmlConverter.new(@book, img_math: @img_math)
        end

        # Ship the modern default stylesheet alongside the user's own; the layout
        # links it under its fixed name. Runs after the base copy of config styles.
        def copy_stylesheet(basetmpdir)
          super
          FileUtils.cp(ReVIEW::AST::WebAssets::STYLESHEET,
                       File.join(basetmpdir, ReVIEW::AST::WebAssets::STYLESHEET_NAME))
        end
      end
    end
  end
end
