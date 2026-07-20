# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'json'

module ReVIEW
  module Renderer
    module Typst
      # Where each line of the generated Typst came from.
      #
      # Typst reports errors against files the author never wrote. This keeps
      # the line ranges the renderer recorded, so a diagnostic can be answered
      # with a position in the manuscript instead
      # (doc/design-typst.md).
      #
      # The granularity is the top-level block: an error deeper inside
      # resolves to the block containing it, which is enough to find the place
      # in the .re file.
      class SourceMap
        # How Typst points at a place in a file: "path/to/ch01.typ:12:34".
        POSITION = %r{([\w./-]+\.typ):(\d+):(\d+)}

        FILENAME = 'source-map.json'

        def initialize
          @entries = {}
        end

        # @param path [String] Generated file, relative to the build root
        # @param entries [Array<Hash>] As produced by TypstRenderer#source_map
        def record(path, entries)
          @entries[path] = entries
        end

        # Kept beside the generated sources, so a build inspected later
        # (keep_workdir) can still be traced back to the manuscript.
        def write(build_dir)
          File.write(File.join(build_dir, FILENAME), JSON.pretty_generate(@entries))
        end

        # Annotate a Typst diagnostic with the manuscript positions it maps
        # to. The generated position is kept as well, since that is the file
        # the compiler actually read.
        def annotate(output)
          output.gsub(POSITION) do |match|
            origin = origin_for(Regexp.last_match(1), Regexp.last_match(2).to_i)
            origin ? "#{match}  <- #{origin}" : match
          end
        end

        private

        def origin_for(path, line)
          entries = entries_for(path)
          return nil unless entries

          entry = entries.find { |e| line.between?(e[:first_line], e[:last_line]) }
          return nil unless entry && entry[:filename]

          position = "#{entry[:filename]}:#{entry[:lineno]}"
          entry[:column] ? "#{position}:#{entry[:column]}" : position
        end

        # Typst prints whatever path it was given, which may be absolute or
        # relative to somewhere else; match on the tail we recorded.
        def entries_for(path)
          key = @entries.keys.find { |recorded| path.end_with?(recorded) }
          key && @entries[key]
        end
      end
    end
  end
end
