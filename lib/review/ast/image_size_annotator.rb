# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/intrinsic_size'

module ReVIEW
  module AST
    # Records the resolution embedded in each image on its <img> tag, so that
    # figures come out at the physical size a TeX toolchain would give them.
    #
    # LaTeX places figures with
    #   \includegraphics[width=<scale>\maxwidth]
    #   \maxwidth = min(natural size, line width)
    # where the natural size comes from the resolution embedded in the image
    # (PNG pHYs, JPEG JFIF density), defaulting to 72dpi. Browsers ignore that
    # metadata and treat one image pixel as one CSS px (96dpi), so a screenshot
    # taken at 300dpi grows to the full measure.
    #
    # Annotating image-resolution corrects the image's *intrinsic* size, so an
    # ordinary stylesheet caps figures with no cooperation needed:
    #
    #   img { max-width: 100%; height: auto; }
    #
    # This is deliberately a standard property rather than a custom one. A
    # custom property only works if the stylesheet is written to consume it,
    # which couples the two silently; and when this annotation does not run,
    # image-resolution degrades to the browser's 96dpi reading (figures a little
    # large but still clamped) rather than leaving them unconstrained.
    #
    # Renderer notes (Vivliostyle 2.44.1):
    #   - `image-resolution: from-image` is not implemented, which is why the
    #     value is resolved here and written out per image.
    #   - Below 96dpi the renderer enlarges the image by setting min-width,
    #     which defeats the stylesheet's max-width (min-width wins in CSS).
    #     Stylesheets must carry `min-width: 1px` to route around it; see
    #     modifyElemDimensionWithImageResolution in core/src/vivliostyle/vgen.ts.
    class ImageSizeAnnotator
      DEFAULT_PROPERTY = 'image-resolution'
      IMG_TAG = /<img\b[^>]*>/
      SRC_ATTRIBUTE = /\ssrc="([^"]*)"/
      ABSOLUTE_URL = /\A[a-z][a-z0-9+.-]*:/i
      TAG_END = %r{(\s*/?>)\z}

      def initialize(root, property: DEFAULT_PROPERTY)
        @root = root
        @property = property
      end

      # Annotates every document under the root. Returns the number of files
      # that changed.
      def annotate
        documents.count do |file|
          source = File.read(file)
          annotated = annotate_source(source, File.dirname(file))
          next false if annotated == source

          File.write(file, annotated)
          true
        end
      end

      # Edits the img tags textually: the chapter files are generated markup,
      # and an XML round-trip would rewrite entities and self-closing tags
      # throughout the document for the sake of one attribute.
      def annotate_source(source, basedir)
        source.gsub(IMG_TAG) do |tag|
          value = resolution_for(tag, basedir)
          value ? tag.sub(TAG_END, %Q( style="#{@property}: #{value}"\\1)) : tag
        end
      end

      private

      def documents
        Dir.glob(File.join(@root, '**', '*.{xhtml,html}'))
      end

      def resolution_for(tag, basedir)
        return nil if tag.include?(@property)

        source = tag[SRC_ATTRIBUTE, 1]
        return nil if source.nil? || source.empty? || source.match?(ABSOLUTE_URL)

        size = IntrinsicSize.of(File.join(basedir, source))
        return nil unless size && size.dpi.to_f > 0

        format('%gdpi', tidy(size.dpi))
      end

      # PNG stores pixels per metre, so converting back to inches leaves values
      # like 72.009 where the author plainly meant 72. Snap those to the whole
      # number: the difference is a few micrometres on the page, and the markup
      # is much easier to read.
      def tidy(dpi)
        (dpi - dpi.round).abs < 0.05 ? dpi.round : dpi.round(2)
      end
    end
  end
end
