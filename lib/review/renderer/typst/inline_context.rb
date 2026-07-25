# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative '../section_numbering'
require_relative '../inline_render_proxy'

module ReVIEW
  module Renderer
    module Typst
      # Shared state and services for Typst inline rendering.
      #
      # Smaller than its LaTeX counterpart: Typst has no moving arguments, so
      # there is no deferred-footnote bookkeeping here. What it does own is the
      # per-chapter footnote ledger, because a footnote's body is emitted at its
      # FIRST @<fn> and later references become label references
      # (doc/design-typst.md).
      class InlineContext
        include ReVIEW::Renderer::SectionNumbering

        attr_reader :config, :render_context

        def initialize(config:, render_context:, renderer:)
          @config = config
          @render_context = render_context
          @render_proxy = InlineRenderProxy.new(renderer)
          @emitted_footnotes = {}
          @footnote_sequence = []
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

        def chapter_link_enabled?
          config['chapterlink']
        end

        def draft_mode?
          config['draft']
        end

        # Whether this footnote's body has already been emitted in this chapter.
        def footnote_emitted?(id)
          @emitted_footnotes.key?(id)
        end

        # Record that a footnote's body is being emitted here, and keep the order
        # so the renderer can check it against the numbers the Indexer stamped.
        def record_footnote(id, number)
          @emitted_footnotes[id] = number
          @footnote_sequence << number
        end

        # Numbers of the footnotes whose bodies were emitted, in output order.
        attr_reader :footnote_sequence
      end
    end
  end
end
