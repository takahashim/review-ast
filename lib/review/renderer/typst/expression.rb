# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/typst_escape_utils'

module ReVIEW
  module Renderer
    module Typst
      # A call expression in the Typst source being generated.
      #
      # "Expression" is Typst's own word: `#` switches markup into code mode,
      # and `#review.figure(..)` is an expression there. Nothing is invoked on
      # the Ruby side -- this only decides how the call is spelled.
      #
      # It exists because those spelling rules were repeated at every visit
      # method: how a value is quoted, whether an empty one is written as `[]`
      # or left out, how a body is attached. Twenty-four sites each restating
      # them is twenty-four chances to differ, and they did: //bibpaper emitted
      # `caption: []` where every other block omitted the argument, which the
      # library then drew as an empty bold line.
      #
      #   Expression.new('review.figure')
      #     .str(:id, 'fig:ch01:a')
      #     .content(:caption, '図版')
      #     .to_s   # => #review.figure(id: "fig:ch01:a", caption: [図版])
      class Expression
        include ReVIEW::TypstEscapeUtils

        # @param function [String] The function to call, e.g. "review.figure"
        def initialize(function)
          @function = function
          @arguments = []
          @body = nil
        end

        # A str argument: paths, language names, labels.
        # @param value [String, nil] Skipped when nil
        def str(name, value)
          return self if value.nil?

          argument(name, typst_string(value))
        end

        # A content argument holding already-rendered markup.
        #
        # An absent or empty caption is left out rather than written as `[]`.
        # The library reads a missing argument as `none`, and the two mean
        # different things: `none` is "this element has no caption", `[]` is
        # "it has one and the author left it empty"
        # (doc/design-typst.md).
        def content(name, markup)
          return self if markup.nil? || markup.to_s.empty?

          argument(name, "[#{markup}]")
        end

        # A content argument built from raw text, escaped here.
        def text(name, raw)
          return self if raw.nil? || raw.to_s.empty?

          argument(name, "[#{escape_typst(raw)}]")
        end

        # A number, boolean, or any other Typst literal that is not a string.
        # @param value [Object, nil] Skipped when nil
        def value(name, value)
          return self if value.nil?

          argument(name, value.to_s)
        end

        # An array argument. Typst needs the trailing comma to tell a
        # one-element array from a parenthesised expression, and an empty array
        # must not have one.
        # @param items [Array<String>] Already-spelled elements
        def array(name, items)
          argument(name, "(#{items.join(', ')}#{items.empty? ? '' : ','})")
        end

        # Arguments already spelled by a caller that had to build them itself.
        def raw_arguments(arguments)
          @arguments.concat(Array(arguments))
          self
        end

        # The trailing content block: `#review.column(..)[ body ]`.
        def body(markup)
          @body = markup
          self
        end

        def to_s
          call = "##{@function}(#{@arguments.join(', ')})"
          return call if @body.nil?

          "#{call}[\n#{indent(@body)}]"
        end

        # A block-level call stands alone, separated from its neighbours by a
        # blank line.
        def to_block
          "#{self}\n\n"
        end

        private

        def argument(name, spelled)
          @arguments << "#{name}: #{spelled}"
          self
        end

        # Indent a nested body so the generated source stays readable.
        def indent(markup, prefix = '  ')
          markup.sub(/\n+\z/, "\n").gsub(/^(?=.)/, prefix)
        end
      end
    end
  end
end
