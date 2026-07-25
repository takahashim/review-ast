# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'colophon'
require_relative 'erb_template'
require_relative 'front_matter'
require_relative 'index'
require_relative 'metadata'
require_relative 'pagination'
require_relative 'theme_reference'

module ReVIEW
  module Renderer
    module Typst
      # The root book.typ: what surrounds the chapters, and in what order.
      #
      # It formats nothing itself. Each question the template asks -- what is
      # the title, is there a cover, how is the third impression worded -- is
      # answered by the object whose subject that is, and this class only
      # introduces them to the template. A new config key means teaching the
      # object it belongs to, rather than lengthening a bindings hash here.
      class RootDocument
        # @param config [ReVIEW::Configure]
        # @param basedir [String] The book's directory, for locating artwork
        # @param typst_config [Hash] The `typst:` section
        # @param warn [Proc] Called when a setting has to be adjusted
        def initialize(config:, basedir:, typst_config:, warn: nil)
          @metadata = Metadata.new(config)
          @front_matter = FrontMatter.new(config, basedir)
          @index = Index.new(config, typst_config)
          @colophon = Colophon.new(config, @metadata)
          @theme = ThemeReference.new(typst_config, warn: warn)
          @pagination = Pagination.new(typst_config)
        end

        attr_reader :metadata, :front_matter, :index, :colophon, :theme, :pagination

        # @param template [String] The ERB source
        # @param chapters [ChapterSet]
        # @return [String] The generated root document
        def render(template, chapters)
          ErbTemplate.render(template, book: self, chapters: chapters)
        end
      end
    end
  end
end
