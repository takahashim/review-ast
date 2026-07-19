# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/htmlutils'
require_relative '../section_numbering'
require_relative '../inline_render_proxy'

module ReVIEW
  module Renderer
    module Idgxml
      # Context for inline element rendering with business logic
      # Used by InlineElementHandler
      class InlineContext
        include ReVIEW::HTMLUtils
        include ReVIEW::Renderer::SectionNumbering

        attr_reader :config, :img_math

        def initialize(config:, renderer:, img_math: nil)
          @config = config
          # Automatically create proxy from renderer to limit access
          @render_proxy = InlineRenderProxy.new(renderer)
          @img_math = img_math
          @texinlineequation = 0
        end

        # === HTMLUtils methods are available via include ===
        # - escape_html(str)
        # - normalize_id(id)

        # Escape for IDGXML (uses HTML escaping)
        def escape(str)
          escape_html(str.to_s)
        end

        def chapter_link_enabled?
          config['chapterlink']
        end

        def draft_mode?
          config['draft']
        end

        def math_format
          config['math_format']
        end

        # Numbering for inline TeX equations. Held here rather than pushed
        # back into the renderer through the proxy: the handler is the only
        # thing that advances it, and the value it returns is all that is used.
        def increment_texinlineequation
          @texinlineequation += 1
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
      end
    end
  end
end
