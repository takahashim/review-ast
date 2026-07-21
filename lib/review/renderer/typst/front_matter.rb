# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require_relative 'text'

module ReVIEW
  module Renderer
    module Typst
      # Which pages surround the chapters, and what goes on them.
      #
      # The book furniture LaTeX gets from its class file and Vivliostyle from
      # the EPUB pipeline has to be decided here instead
      # (doc/design-typst.md). Each question is answered
      # by asking this object, not by reading config keys at the template.
      class FrontMatter
        def initialize(config, basedir)
          @config = config
          @basedir = basedir
        end

        # A generated cover only earns its page when the book supplies
        # artwork; without an image it would just repeat the title page.
        def cover?
          @config.fetch('cover', true) && !cover_image.nil?
        end

        # @return [Text, nil] Path from the Typst project root
        def cover_image
          name = Text.presence(@config['coverimage'])
          return nil unless name
          return nil unless File.exist?(File.join(@basedir, imagedir, name.to_s))

          Text.new("/#{imagedir}/#{name}")
        end

        def titlepage?
          @config.fetch('titlepage', true)
        end

        def toc?
          @config.fetch('toc', false)
        end

        def toc_title
          Text.new(ReVIEW::I18n.t('toctitle'))
        end

        # How deep the table of contents goes. The depth belongs to the book,
        # not to the theme: EPUB and the LaTeX path both read `toclevel`, so
        # leaving it to the theme would give one manuscript a different table
        # of contents per format. The theme's own depth stays as the default
        # for documents written against `book.*` by hand.
        #
        # @return [Integer, nil] nil when the book states no usable level
        def toc_depth
          level = @config['toclevel'].to_i
          level > 0 ? level : nil
        end

        private

        def imagedir
          @config['imagedir'] || 'images'
        end
      end
    end
  end
end
