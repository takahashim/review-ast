# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require_relative 'chapter_file'
require 'review/renderer/typst/text'

module ReVIEW
  module AST
    module Command
      module Typst
        # The chapters of a book, grouped the way the root document includes
        # them. Built by walking the catalog; read by RootDocument.
        class ChapterSet
          PARTS = %i[predef chaps appendix postdef].freeze

          def initialize
            @groups = PARTS.to_h { |name| [name, []] }
          end

          def add(part_name, file)
            @groups.fetch(part_name) << file
          end

          # @return [Array<ChapterFile>]
          def fetch(part_name)
            @groups.fetch(part_name)
          end

          PARTS.each do |name|
            define_method(name) { @groups.fetch(name) }
          end

          def each(&block)
            @groups.each_value { |files| files.each(&block) }
          end

          # Which group a chapter belongs to, from the catalog's own answer.
          def self.group_for(chapter)
            if chapter.on_predef? then :predef
            elsif chapter.on_appendix? then :appendix
            elsif chapter.on_postdef? then :postdef
            else
              :chaps
            end
          end
        end
      end
    end
  end
end
