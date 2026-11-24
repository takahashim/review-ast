# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'delegate'
require 'review/ast/render_context'
require 'review/ast/chapter_title'

module ReVIEW
  module AST
    # Markdown chapters and parts as the legacy makers expect a .re one to look.
    #
    # Re:VIEW's book model and makers assume ".re" in several places, so on a
    # Markdown book (catalog entries ending in .md):
    #
    # - Chapter#on_chaps?/on_predef?/on_appendix?/on_postdef? match the catalog
    #   against "<id><book.ext>" and are all false -- PDFMaker#make_input_files
    #   then \input's no chapter at all;
    # - the makers name a chapter's output after its file with only ".re"
    #   stripped (ch01.md.xhtml, ch01.md.xml), while links point at ch01.xhtml;
    # - Part#file? accepts ".re" names only, so a part file (part2.md) is made
    #   into a title page named after the file, its content unused.
    #
    # The makers' loops get these views instead of the units themselves. A view
    # reports a ".re" path (which gives the output its ordinary name -- the
    # converters find the real unit by basename, so the .md source is what is
    # compiled) and answers the questions above from the AST side
    # (RenderContext.catalog_section, ChapterTitle). Renderers never see a
    # view: they get the real chapter or part from the converter's lookup.
    module BookUnitView
      module_function

      def markdown?(unit)
        unit.respond_to?(:path) && unit.path.to_s.end_with?('.md')
      end

      # Part#file?, also true for a Markdown part file.
      def part_file?(part)
        return true if part.file?

        part.name.to_s.strip != '' && markdown?(part) && !part.content.to_s.empty?
      end

      # Book#parts_in_file, Markdown part files included.
      def parts_in_file(book)
        book.parts.select { |part| part.present? && part_file?(part) }
      end

      def wrap(unit)
        return unit unless markdown?(unit)

        unit.is_a?(ReVIEW::Book::Part) ? PartView.new(unit) : ChapterView.new(unit)
      end

      # Common to both views: a ".re" path.
      module ReExtension
        def path
          __getobj__.path.sub(/\.md\z/, '.re')
        end
      end

      class ChapterView < SimpleDelegator
        include ReExtension

        def on_predef?
          section == :predef
        end

        def on_appendix?
          section == :appendix
        end

        def on_postdef?
          section == :postdef
        end

        def on_chaps?
          section.nil?
        end

        private

        def section
          ReVIEW::AST::RenderContext.catalog_section(__getobj__)
        end
      end

      class PartView < SimpleDelegator
        include ReExtension

        def file?
          BookUnitView.part_file?(__getobj__)
        end

        # Part#name is the catalog entry as written ("part2.md"); for a .re
        # part file Part#initialize strips the ".re".
        def name
          File.basename(__getobj__.name, '.md')
        end

        def title
          ReVIEW::AST::ChapterTitle.of(__getobj__)
        end
      end
    end
  end
end
