# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/latexutils'
require_relative '../inline_render_proxy'

module ReVIEW
  module Renderer
    module Latex
      # Context for inline element rendering with business logic
      # Used by InlineElementHandler
      class InlineContext
        include ReVIEW::LaTeXUtils

        attr_reader :config, :render_context, :index_db, :index_mecab

        def initialize(config:, render_context:, renderer:)
          @config = config
          @render_context = render_context
          # Automatically create proxy from renderer to limit access
          @render_proxy = InlineRenderProxy.new(renderer)
          # Initialize index support
          initialize_index_support
        end

        # Get current rendering context dynamically from renderer
        # This ensures we always have the most up-to-date context,
        # even when it changes during rendering (e.g., caption context)
        def rendering_context
          @render_proxy.rendering_context
        end

        # Defer a footnote's \footnotetext to its //footnote definition.
        def defer_footnotetext(id)
          @render_proxy.defer_footnotetext(id)
        end

        def chapter_link_enabled?
          config['chapterlink']
        end

        def draft_mode?
          config['draft']
        end

        def over_secnolevel?(n)
          secnolevel = config['secnolevel'] || 2
          secnolevel >= n.to_s.split('.').size
        end

        def render_children(node)
          @render_proxy.render_children(node)
        end

        def render_caption_inline(caption_node)
          @render_proxy.render_caption_inline(caption_node)
        end

        def text_formatter
          @render_proxy.text_formatter
        end

        private

        # Initialize index support (database and MeCab)
        def initialize_index_support
          @index_db = {}
          @index_mecab = nil

          return unless config['pdfmaker'] && config['pdfmaker']['makeindex']

          # Load index dictionary file
          if config['pdfmaker']['makeindex_dic']
            @index_db = load_idxdb(config['pdfmaker']['makeindex_dic'])
          end

          return unless config['pdfmaker']['makeindex_mecab']

          # Initialize MeCab for Japanese text indexing
          begin
            begin
              require 'MeCab'
            rescue LoadError
              require 'mecab'
            end
            require 'nkf'
            @index_mecab = MeCab::Tagger.new(config['pdfmaker']['makeindex_mecab_opts'])
          rescue LoadError
            # MeCab not available, will fall back to text-only indexing
          end
        end

        # Load index database from file
        def load_idxdb(file)
          table = {}
          File.foreach(file) do |line|
            key, value = *line.strip.split(/\t+/, 2)
            table[key] = value
          end
          table
        end
      end
    end
  end
end
