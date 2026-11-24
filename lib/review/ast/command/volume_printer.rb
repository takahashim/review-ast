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
require 'review/ast/render_context'

module ReVIEW
  module AST
    module Command
      # review-vol through the AST: the same options and output as
      # ReVIEW::VolumePrinter, but each chapter's number and title come from
      # the AST side. The legacy printer reads the title with BookUnit#title
      # (Re:VIEW "=" headlines only) and the number with Chapter#format_number
      # (which misses a Markdown appendix), so a Markdown book listed every
      # chapter untitled and its appendix as "第1章".
      class VolumePrinter < ReVIEW::VolumePrinter
        def print_chapter_volume(chap)
          builder = ReVIEW::PLAINTEXTBuilder.new
          builder.bind(ReVIEW::Compiler.new(builder), chap, nil)

          vol = chap.volume
          title = ReVIEW::AST::ChapterNumberFormatter.full(chap.number, ReVIEW::AST::RenderContext.chapter_type(chap))
          title += '  ' unless title.empty?
          begin
            title += builder.compile_inline(ReVIEW::AST::ChapterTitle.of(chap))
          rescue ReVIEW::ApplicationError => e
            @logger.warn "#{chap.name} : #{e.message.sub(/.+error: /, '')}"
          end

          printf("%3dKB %6dC %5dL %3dP  %s %-s\n",
                 vol.kbytes, vol.chars, vol.lines, vol.page,
                 "#{chap.name} ".ljust(15, '.'), title)
        end
      end
    end
  end
end
