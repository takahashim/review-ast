# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

# Loaded before the book (and its review-ext.rb), as the other commands do.
require 'review'
require 'review/volumeprinter'
require 'review/ast'
require 'review/ast/compiler'
require 'review/ast/chapter_title'
require 'review/ast/chapter_number_formatter'
require 'review/ast/chapter_registry_provider'
require 'review/ast/render_context'
require 'review/renderer/plaintext_renderer'

module ReVIEW
  module AST
    module Command
      # review-vol through the AST: the same options and output as
      # ReVIEW::VolumePrinter, but each chapter's number and title come from
      # the AST side. The legacy printer reads the title with BookUnit#title
      # (Re:VIEW "=" headlines only) and the number with Chapter#format_number
      # (which misses a Markdown appendix), so a Markdown book listed every
      # chapter untitled and its appendix as "第1章".
      #
      # The legacy printer writes the title with PLAINTEXTBuilder#compile_inline
      # on a builder bound without a location, so any error in a title's inline
      # -- an op only a renderer implements, for one -- ends in a NoMethodError.
      # Here the title is the chapter's first headline as PlaintextRenderer
      # writes its caption, with no builder involved.
      class VolumePrinter < ReVIEW::VolumePrinter
        # PlaintextRenderer, asked for a headline's caption alone (no number
        # prefix, no newline).
        class TitleRenderer < ReVIEW::Renderer::PlaintextRenderer
          def title(headline)
            render_caption_inline(headline.caption_node)
          end
        end

        def print_chapter_volume(chap)
          vol = chap.volume
          title = ReVIEW::AST::ChapterNumberFormatter.full(chap.number, ReVIEW::AST::RenderContext.chapter_type(chap))
          title += '  ' unless title.empty?
          title += rendered_title(chap)

          printf("%3dKB %6dC %5dL %3dP  %s %-s\n",
                 vol.kbytes, vol.chars, vol.lines, vol.page,
                 "#{chap.name} ".ljust(15, '.'), title)
        end

        private

        # A chapter that does not compile is still listed, with a warning and
        # its title as written in the source.
        def rendered_title(chap)
          # A part named in the catalog only (no file) is titled by that name.
          return chap.title.to_s if chap.content.to_s.empty?

          ast = ReVIEW::AST::Compiler.for_chapter(chap).compile_to_ast(chap, registry_provider: registry_provider)
          headline = ReVIEW::AST::ChapterTitle.first_headline(ast)
          headline ? TitleRenderer.new(chap).title(headline) : ''
        rescue ReVIEW::ApplicationError, ReVIEW::CompileError => e
          @logger.warn "#{chap.name} : #{e.message.sub(/.+error: /, '')}"
          chap.title.to_s
        end

        # One provider for the whole listing, so a chapter other chapters refer
        # to is indexed once.
        def registry_provider
          @registry_provider ||= ReVIEW::AST::ChapterRegistryProvider.new
        end
      end
    end
  end
end
