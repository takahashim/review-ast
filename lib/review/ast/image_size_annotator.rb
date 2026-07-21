# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/intrinsic_size'

module ReVIEW
  module AST
    # Records each image's physical size on its <img> tag, so that a stylesheet
    # can size figures the way a TeX toolchain does.
    #
    # LaTeX places figures with
    #   \includegraphics[width=<scale>\maxwidth]
    #   \maxwidth = min(natural size, line width)
    # where the natural size comes from the resolution embedded in the image
    # (PNG pHYs, JPEG JFIF density), defaulting to 72dpi. Browsers ignore that
    # metadata and treat one image pixel as one CSS px (96dpi), so the same
    # figure comes out at a different size. With the size annotated, a
    # stylesheet reproduces \maxwidth and //image's scale= directly:
    #
    #   width: calc(var(--scale, 1) * min(var(--natural, 100%), 100%))
    #
    # scale= is a multiplier on the natural size, not a fraction of the measure:
    # //image[...][scale=0.5] on a figure narrower than the measure has to come
    # out at half that figure, which is what the LaTeX edition prints and what
    # documentation of the syntax demonstrates. Expressing that in CSS needs the
    # natural size as a value, which is why this is a length in mm rather than
    # the standard image-resolution property -- see
    # doc/vivliostyle-image-sizing.ja.md for the alternatives that were measured
    # and rejected.
    class ImageSizeAnnotator
      DEFAULT_PROPERTY = '--natural'
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
          value = width_for(tag, basedir)
          value ? tag.sub(TAG_END, %Q( style="#{@property}: #{value}"\\1)) : tag
        end
      end

      private

      def documents
        Dir.glob(File.join(@root, '**', '*.{xhtml,html}'))
      end

      def width_for(tag, basedir)
        return nil if tag.include?(@property)

        source = tag[SRC_ATTRIBUTE, 1]
        return nil if source.nil? || source.empty? || source.match?(ABSOLUTE_URL)

        size = IntrinsicSize.of(File.join(basedir, source))
        return nil unless size && size.width_mm > 0

        sprintf('%.3fmm', size.width_mm)
      end
    end
  end
end
