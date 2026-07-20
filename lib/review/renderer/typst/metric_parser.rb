# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/exception'

module ReVIEW
  module Renderer
    module Typst
      # Turns a //image metric into semantic values for review.figure.
      #
      # Base#parse_metric only strips the "typst::" builder prefix; what is left
      # is still an untyped "key=value,key=value" string written for whatever
      # backend the author had in mind. Passing that through to Typst would mean
      # the renderer emitting layout code, which
      # doc/design-typst.md rules out, so each key is
      # recognized here and rejected with the node's source position otherwise.
      class MetricParser
        # Length units Typst understands, plus percentages of the available width.
        LENGTH = /\A\d+(?:\.\d+)?(?:pt|mm|cm|in|em|%)\z/
        RATIO = /\A\d+(?:\.\d+)?\z/

        # @param metric [String] Metric string with the builder prefix removed
        # @param location [ReVIEW::AST::SourceLocation, nil] Position for errors
        def initialize(metric, location: nil)
          @metric = metric.to_s
          @location = location
        end

        # @return [Hash] Semantic values: :width, :height, :scale
        # @raise [ReVIEW::CompileError] On an unknown key or malformed value
        def parse
          result = {}
          return result if @metric.empty?

          @metric.split(/,\s*/).each do |param|
            key, value = param.split('=', 2)
            key = key.to_s.strip
            value = value.to_s.strip

            case key
            when 'width', 'height'
              error("#{key} must be a length such as 80mm or 60% (got #{value.inspect})") unless LENGTH.match?(value)
              result[key.to_sym] = value
            when 'scale'
              error("scale must be a ratio such as 0.5 (got #{value.inspect})") unless RATIO.match?(value)
              result[:scale] = value
            else
              error("unknown image metric #{key.inspect}; typst supports width, height and scale")
            end
          end

          if result[:scale] && (result[:width] || result[:height])
            error('scale cannot be combined with width or height')
          end

          result
        end

        private

        def error(message)
          raise ReVIEW::CompileError, "#{message}#{@location&.format_for_error}"
        end
      end
    end
  end
end
