# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

# Loaded before the book (and its review-ext.rb), as the other commands do.
require 'review'
require 'review/tocprinter'
require 'review/ast'
require 'review/ast/compiler'
require 'review/renderer/plaintext_renderer'
require 'review/ast/chapter_title'

module ReVIEW
  module AST
    module Command
      # review-index through the AST: the same options and output as
      # ReVIEW::TOCPrinter, with each chapter read by the AST compiler -- so a
      # Markdown chapter, which the legacy compiler cannot read, has its
      # headings listed too.
      #
      # TOCPrinter compiles each chapter with PLAINTEXTTocBuilder, which marks
      # headlines ("\x01H<level>\x01") and code blocks (STARTLIST/ENDLIST) in
      # plain-text output that parse_contents then measures. TocRenderer emits
      # the same marked stream from the AST; everything else is TOCPrinter's.
      class TOCPrinter < ReVIEW::TOCPrinter
        # PlaintextRenderer output marked up the way PLAINTEXTTocBuilder marks it.
        class TocRenderer < ReVIEW::Renderer::PlaintextRenderer
          # The blocks PLAINTEXTBuilder prints through base_block, which
          # PLAINTEXTTocBuilder brackets as list lines.
          LIST_BLOCKS = %i[emlist cmd source].freeze

          def visit_headline(node)
            out = super
            # [nonum]/[notoc]/[nodisp] headings never reach #headline in the
            # builder, so they carry no mark (and are not listed).
            return out if out.empty? || node.nonum? || node.notoc? || node.nodisp?

            level = @chapter.is_a?(ReVIEW::Book::Part) ? 0 : node.level
            "\x01H#{level}\x01#{out}"
          end

          def visit_code_block(node)
            out = super
            return out unless LIST_BLOCKS.include?(node.code_type&.to_sym)

            "\x01STARTLIST\x01\n#{out}\x01ENDLIST\x01\n"
          end

          # PLAINTEXTTocBuilder#blank prints nothing, so its stream has no
          # blank lines; they would count as lines of text.
          def render(ast)
            super.gsub(/^\n/, '')
          end
        end

        # TOCPrinter#build_result_array, with a Markdown part file read like a
        # .re one: Part#file? accepts ".re" names only, so the legacy loop
        # printed such a part as its file name and skipped its headings.
        def build_result_array
          result_array = []
          @book.parts.each do |part|
            listed = part.name.present? && (@buildonly.nil? || @buildonly.include?(part.name))
            if listed
              result_array.push(Counter.new(part: 'start'))
              if part.file? || ReVIEW::AST::ChapterTitle.markdown?(part)
                result_array.concat(parse_contents(part.name, @upper, build_chap(part)))
              else
                title = part.format_number + I18n.t('chapter_postfix') + part.title
                result_array.push(
                  Counter.new(name: '', lines: 1, chars: title.size, list_lines: 0, text_lines: 1),
                  Counter.new(level: 0, headline: title, lines: 1, chars: title.size, list_lines: 0, text_lines: 1)
                )
              end
            end

            part.chapters.each do |chap|
              if @buildonly.nil? || @buildonly.include?(chap.name)
                result_array.concat(parse_contents(chap.name, @upper, build_chap(chap)))
              end
            end
            result_array.push(Counter.new(part: 'end')) if listed
          end
          result_array
        rescue ReVIEW::FileNotFound, ReVIEW::CompileError => e
          @logger.error e
          exit 1
        end

        def build_chap(chap)
          ast = ReVIEW::AST::Compiler.for_chapter(chap).compile_to_ast(chap)
          TocRenderer.new(chap).render(ast)
        rescue ReVIEW::ApplicationError, ReVIEW::CompileError => e
          @logger.error "#{chap.name}: #{e.message}"
          ''
        end
      end
    end
  end
end
