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
      # The book's bibliographic details, as the root document needs them.
      class Metadata
        # One person named in the book's front matter.
        #
        # A title page typesets the name, while PDF metadata takes plain text
        # only (doc/design-typst.md). Both come off the same object
        # rather than being prepared as two separate bindings.
        class Author
          attr_reader :name

          def initialize(name)
            @name = Text.new(name)
          end
        end

        def initialize(config)
          @config = config
        end

        def title
          Text.new(@config.name_of('booktitle').to_s)
        end

        def subtitle
          Text.presence(@config['subtitle'] && @config.name_of('subtitle'))
        end

        def publisher
          named('pbl')
        end

        def rights
          Text.presence(@config['rights'] && @config.name_of('rights'))
        end

        def authors
          names_of('aut').map { |name| Author.new(name) }
        end

        # The authors as one line, for a cover or title page.
        def author_line
          Text.join(authors.map(&:name), ReVIEW::I18n.t('names_splitter'))
        end

        def language
          Text.new(@config['language'] || 'ja')
        end

        def keywords
          []
        end

        private

        # A role can hold several names; the locale decides how they join.
        def named(role)
          return nil unless present?(role)

          Text.new(names_of(role).join(ReVIEW::I18n.t('names_splitter')))
        end

        def names_of(role)
          return [] unless present?(role)

          Array(@config.names_of(role)).map(&:to_s)
        end

        def present?(role)
          !Text.presence(@config[role]).nil?
        end
      end
    end
  end
end
