# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'date'
require 'review/i18n'
require_relative 'text'

module ReVIEW
  module Renderer
    module Typst
      # The colophon: the page that records who made the book and when.
      #
      # This is bibliographic formatting, not build orchestration -- which
      # roles appear in which order, how an impression is worded, how a date
      # is spelled. It follows PDFMaker#make_history_list and Configure's
      # colophon_order, so one config.yml is worded the same way whichever
      # maker builds it.
      class Colophon
        # A labelled row: 「著　者」と、その人たち。
        class Entry
          attr_reader :label, :value

          def initialize(label, value)
            @label = Text.new(label)
            @value = Text.new(value)
          end
        end

        # One dated line above the roles.
        #
        # A bare date takes the edition and impression; a date followed by
        # text keeps that text instead of them; anything else is printed as
        # written. The book, not this class, decides which by how it wrote the
        # entry in config.yml.
        class HistoryLine
          ISO_DATE = /\A\d+-\d+-\d+\z/
          DATE_WITH_TEXT = /\A(\d+-\d+-\d+)[\s　](.+)/

          # An ISO date is spelled out through the locale's date_format. A
          # value that is not a date is left alone rather than raising, since
          # config.yml allows free-form entries.
          def self.spell_date(date)
            Date.parse(date.to_s).strftime(ReVIEW::I18n.t('date_format'))
          rescue ArgumentError, TypeError
            date.to_s
          end

          def initialize(source, edition:, impression:)
            @source = source.to_s
            @edition = edition
            @impression = impression
          end

          def text
            Text.new(wording)
          end

          private

          def wording
            case @source
            when ISO_DATE
              ReVIEW::I18n.t('published_by1',
                             [self.class.spell_date(@source), edition_label + impression_label])
            when DATE_WITH_TEXT
              ReVIEW::I18n.t('published_by3',
                             [self.class.spell_date(Regexp.last_match(1)), Regexp.last_match(2)])
            else
              @source
            end
          end

          def edition_label
            if @edition == 0
              ReVIEW::I18n.t('first_edition')
            else
              ReVIEW::I18n.t('nth_edition', (@edition + 1).to_s)
            end
          end

          def impression_label
            ReVIEW::I18n.t('nth_impression', (@impression + 1).to_s)
          end
        end

        def initialize(config, metadata)
          @config = config
          @metadata = metadata
        end

        # @return [Boolean] Whether the book asks for a colophon at all
        def wanted?
          !Text.presence(@config['colophon']).nil?
        end

        # @return [Array<Entry>] The labelled rows, in colophon_order
        def entries
          Array(@config['colophon_order']).filter_map do |role|
            names = role_names(role)
            Entry.new(ReVIEW::I18n.t(role), names) if names
          end
        end

        # @return [Array<Text>] The dated lines
        def history
          return [undated_line] if !@config['history'] && @config['date']
          return [] unless @config['history']

          Array(@config['history']).each_with_index.flat_map do |impressions, edition|
            Array(impressions).each_with_index.map do |source, impression|
              HistoryLine.new(source, edition: edition, impression: impression).text
            end
          end
        end

        def rights
          @metadata.rights
        end

        private

        # No history, but a date: the book has been published once.
        def undated_line
          Text.new(ReVIEW::I18n.t('published_by2', HistoryLine.spell_date(@config['date'])))
        end

        def role_names(role)
          return nil unless Text.presence(@config[role])

          Array(@config.names_of(role)).join(ReVIEW::I18n.t('names_splitter'))
        end
      end
    end
  end
end
