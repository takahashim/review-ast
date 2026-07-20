# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/i18n'
require_relative 'text'

module ReVIEW
  module Renderer
    module Typst
      # The index at the back of the book.
      #
      # Re:VIEW decides what a term is and how it sorts; Typst only finds out
      # what page each mark landed on (doc/design-typst.md). This object
      # answers whether the book wants one at all, and under what heading.
      class Index
        def initialize(config, typst_config)
          @config = config
          @typst_config = typst_config
        end

        def wanted?
          @typst_config.fetch('index', false)
        end

        # The review gem's locales have no key for an index heading -- the
        # LaTeX class supplies the word itself -- so a book can define
        # `indextitle` in its own locale file and otherwise gets a sensible
        # default. I18n.t returns the key when it is missing, which is how
        # that is detected.
        def title
          heading = ReVIEW::I18n.t('indextitle')
          heading = japanese? ? '索引' : 'Index' if heading == 'indextitle'
          Text.new(heading)
        end

        private

        def japanese?
          @config['language'].to_s.start_with?('ja')
        end
      end
    end
  end
end
