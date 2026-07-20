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
      # A piece of text on its way into a generated Typst document.
      #
      # doc/design-typst.md keeps the manual's rule that a
      # value must travel by the path that matches where it lands: body text
      # is escaped markup, a str argument is a quoted literal. Those paths
      # used to be a naming convention -- one binding called `escaped_title`
      # beside another called `plain_title` -- which put the choice on
      # whoever wrote the template. Here they are the object's own methods,
      # so a value cannot be spelled the wrong way by picking the wrong name.
      class Text
        def initialize(raw)
          @raw = raw.to_s
        end

        def empty?
          @raw.empty?
        end

        # Escaped markup inside a content block: `[太字]`.
        def content
          "[#{ReVIEW::TypstEscapeUtils.escape_typst(@raw)}]"
        end

        # A quoted string literal: `"images/cover.jpg"`.
        def literal
          ReVIEW::TypstEscapeUtils.typst_string(@raw)
        end

        def to_s
          @raw
        end

        def ==(other)
          other.is_a?(Text) && other.to_s == @raw
        end

        # Joins several texts as one, for the places a book prints its authors
        # on a single line.
        def self.join(texts, separator)
          new(texts.map(&:to_s).join(separator))
        end

        # Nil and the empty string both mean "the book did not set this", and
        # every caller wants to skip such a value rather than print nothing.
        def self.presence(raw)
          text = new(raw)
          text.empty? ? nil : text
        end
      end
    end
  end
end
