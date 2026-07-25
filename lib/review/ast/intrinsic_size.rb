# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # Physical size of a bitmap image, as a TeX-side toolchain sees it.
    #
    # dvipdfmx derives \Gin@nat@width from the resolution embedded in the file
    # (PNG pHYs, JPEG JFIF density) and falls back to 72dpi when there is none,
    # so \includegraphics places a 600px 300dpi screenshot at two inches rather
    # than at some pixel-derived width. Browsers ignore that metadata and treat
    # one image pixel as one CSS px (96dpi), which is why the same figure comes
    # out larger in a CSS-typeset PDF.
    #
    # This reads the metadata so a renderer can hand the physical size to CSS.
    module IntrinsicSize
      # dvipdfmx's assumption for images that carry no resolution.
      DEFAULT_DPI = 72.0
      MM_PER_INCH = 25.4
      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

      Size = Struct.new(:width_px, :height_px, :dpi) do
        def width_mm
          width_px / dpi * MM_PER_INCH
        end

        def height_mm
          height_px / dpi * MM_PER_INCH
        end
      end

      module_function

      # Returns a Size, or nil for formats we cannot measure (SVG has its own
      # sizing rules; unknown formats are left to the browser).
      #
      # The whole file is read because the metadata is not bounded to the head:
      # an ICC profile (iCCP) or Exif block written by an image editor routinely
      # runs to hundreds of kilobytes and precedes pHYs. Reading a fixed prefix
      # instead would silently fall back to DEFAULT_DPI and place the figure at
      # the wrong size. Both scans stop at the first chunk that can no longer be
      # followed by the metadata, so the cost is the read itself.
      def of(path)
        return nil unless File.file?(path)

        data = File.binread(path)
        if data.start_with?(PNG_SIGNATURE)
          png(data)
        elsif data.start_with?("\xFF\xD8".b)
          jpeg(data)
        end
      rescue StandardError
        nil
      end

      def png(data)
        return nil if data.bytesize < 24

        width, height = data[16, 8].unpack('N2')
        Size.new(width, height, png_dpi(data) || DEFAULT_DPI)
      end

      # pHYs holds pixels per unit; unit 1 is metres, anything else is
      # "unknown aspect ratio only" and carries no physical size.
      def png_dpi(data)
        offset = 8
        while offset + 8 <= data.bytesize
          length = data[offset, 4].unpack1('N')
          type = data[offset + 4, 4]
          return nil if type == 'IDAT'

          if type == 'pHYs' && length >= 9
            pixels_per_metre, _y, unit = data[offset + 8, 9].unpack('N2C')
            return nil unless unit == 1 && pixels_per_metre > 0

            return pixels_per_metre * 0.0254
          end
          offset += 12 + length
        end
        nil
      end

      def jpeg(data)
        size = jpeg_dimensions(data)
        return nil unless size

        Size.new(size[0], size[1], jpeg_dpi(data) || DEFAULT_DPI)
      end

      # Walk the marker segments to the frame header, which carries the size.
      def jpeg_dimensions(data)
        offset = 2
        while offset + 4 <= data.bytesize
          return nil unless data.getbyte(offset) == 0xFF

          marker = data.getbyte(offset + 1)
          length = data[offset + 2, 2].unpack1('n')
          # SOF0-SOF15, excluding DHT(C4), JPG(C8) and DAC(CC)
          if marker.between?(0xC0, 0xCF) && ![0xC4, 0xC8, 0xCC].include?(marker)
            height, width = data[offset + 5, 4].unpack('n2')
            return [width, height]
          end
          offset += 2 + length
        end
        nil
      end

      # APP0/JFIF density: units 1 is dots per inch, 2 is dots per centimetre.
      def jpeg_dpi(data)
        offset = 2
        while offset + 4 <= data.bytesize
          return nil unless data.getbyte(offset) == 0xFF

          marker = data.getbyte(offset + 1)
          length = data[offset + 2, 2].unpack1('n')
          if marker == 0xE0 && data[offset + 4, 5] == "JFIF\0"
            units, x_density = data[offset + 11, 3].unpack('Cn')
            return nil unless x_density > 0

            return x_density.to_f if units == 1
            return x_density * 2.54 if units == 2

            return nil
          end
          offset += 2 + length
        end
        nil
      end
    end
  end
end
