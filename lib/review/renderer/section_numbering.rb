# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    # Whether a section number is deep enough to be suppressed by secnolevel.
    #
    # Builder#over_secnolevel? counts the levels in a dotted number string that
    # already includes the chapter ("1.1" is two levels). The AST hands over
    # ResolvedData#headline_number instead, an array of the section counters
    # *without* the chapter, so the chapter has to be added back.
    #
    # Getting that wrong is quiet: `[1, 2].to_s.split('.').size` is 1, not 3, so
    # a copy written for the string form reports every heading as being within
    # secnolevel and numbers show up where the builder suppresses them.
    module SectionNumbering
      # Configure's default, used when the book config does not set one.
      DEFAULT_SECNOLEVEL = 2

      # @param number [Array, String, nil] Section number, from headline_number
      # @return [Boolean] true if the number is within secnolevel
      def over_secnolevel?(number)
        secnolevel = config['secnolevel'] || DEFAULT_SECNOLEVEL
        secnolevel >= section_level_of(number)
      end

      private

      # Depth of the heading, counting the chapter as level 1.
      def section_level_of(number)
        return 1 + number.size if number.is_a?(::Array)

        # A dotted string from the builders already counts the chapter.
        number.to_s.split('.').size
      end
    end
  end
end
