# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # The `vivliostyle:` section of config.yml.
    #
    # Every default the Vivliostyle path applies is stated here, so that the
    # maker reads intent ("keep the workdir?") rather than Hash lookups, and so
    # that the answer to "what can I put under vivliostyle:" is one file rather
    # than a grep.
    #
    #   vivliostyle:
    #     output: mybook-vivliostyle.pdf  # default: <bookname>-vivliostyle.pdf
    #     outline: toc                    # toc (default) / headings / none
    #     timeout: 300
    #     browser_path: ~                 # default: auto-detect Chrome/Chromium
    #     viewer_path: ~                  # default: viewer bundled in vivlio-pdf
    #     keep_workdir: false             # keep the extracted EPUB tree
    #     image_intrinsic_size: true      # size figures from the resolution
    #                                     # embedded in each image
    #     cover: true                     # false drops the cover page
    #     toc_titlepage: true             # false drops the title page from the
    #                                     # navigation
    class VivliostyleConfig
      DEFAULT_OUTLINE = 'toc'

      def initialize(section)
        @section = section || {}
      end

      def cover?
        @section.fetch('cover', true)
      end

      def toc_titlepage?
        @section.fetch('toc_titlepage', true)
      end

      def image_intrinsic_size?
        @section.fetch('image_intrinsic_size', true)
      end

      def keep_workdir?
        @section.fetch('keep_workdir', false)
      end

      # NOTE: not <bookname>.pdf -- that would overwrite pdfmaker's output.
      def output_for(bookname)
        @section['output'] || "#{bookname}-vivliostyle.pdf"
      end

      # The keyword arguments Vivlio::PDF.print takes. The optional ones are
      # left out entirely rather than passed as nil, so that vivlio-pdf's own
      # defaults apply.
      def print_options(metadata:)
        options = { outline: (@section['outline'] || DEFAULT_OUTLINE).to_sym,
                    metadata: metadata }
        options[:timeout] = @section['timeout'] if @section['timeout']
        options[:browser_path] = @section['browser_path'] if @section['browser_path']
        options[:viewer] = @section['viewer_path'] if @section['viewer_path']
        options
      end
    end
  end
end
