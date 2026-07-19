# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative '../json_serializer'

module ReVIEW
  module AST
    module Diff
      # Compares two AST trees for structural equivalence, ignoring source
      # locations.
      #
      # The comparison runs over serialize_to_hash rather than a hand-written
      # list of fields per node type. Each node already enumerates its semantic
      # fields once, for serialization; a second enumeration here drifted from
      # it, and silently: noindent, headline tags ([nonum]), code_type,
      # first_line_num, ordered-list start numbers and definition_number were
      # all absent, so trees differing in any of them compared as equal. Since
      # the consumer is the equivalence oracle of the round-trip tests, every
      # omission weakened those tests without failing anything.
      #
      # Comparing the serialized form means a field added to a node is compared
      # from the moment it is serialized. It also makes this work on surface
      # trees (DirectiveNode and all), which the visitor-based version could not
      # walk.
      class Node
        # Result of AST node comparison
        class Result
          attr_reader :differences

          def initialize
            @differences = []
          end

          # Add a difference to the result
          def add_difference(path, message)
            @differences << "#{path}: #{message}"
          end

          # Check if the comparison was successful (no differences)
          def equal?
            @differences.empty?
          end

          # Get a human-readable summary of differences
          def to_s
            if equal?
              'AST nodes are equivalent'
            else
              "AST nodes differ:\n  " + @differences.join("\n  ")
            end
          end
        end

        # Fields excluded from the comparison, by the node type they belong to.
        #
        # Keep this list short and justified: anything here is a field whose
        # difference this comparison will not report.
        IGNORED_FIELDS = {
          # An inline command's arguments are re-parsed from regenerated source
          # in the round-trip tests, where an equivalent argument can come back
          # spelled differently. The rendered output is what the parity
          # harnesses check.
          'InlineNode' => %i[args].freeze
        }.freeze

        # Compare two AST nodes and return a Result
        #
        # @param node1 [AST::Node] First node to compare
        # @param node2 [AST::Node] Second node to compare
        # @param path [String] Path to current node (for error messages)
        # @return [Result] Result of comparison
        def compare(node1, node2, path = 'root')
          @result = Result.new

          if node1.nil? || node2.nil?
            report_nil_mismatch(node1, node2, path)
          else
            compare_hashes(serialize(node1), serialize(node2), path)
          end

          @result
        end

        private

        # Locations are excluded: the trees being compared come from different
        # sources (original vs regenerated), so their line numbers legitimately
        # differ.
        def serialize(node)
          node.serialize_to_hash(JSONSerializer::Options.new(include_location: false))
        end

        def report_nil_mismatch(node1, node2, path)
          return if node1.nil? && node2.nil?

          if node1.nil?
            @result.add_difference(path, "node1 is nil but node2 is #{node2.class}")
          else
            @result.add_difference(path, "node1 is #{node1.class} but node2 is nil")
          end
        end

        def compare_hashes(hash1, hash2, path)
          if hash1[:type] != hash2[:type]
            @result.add_difference(path, "node types differ (#{hash1[:type]} vs #{hash2[:type]})")
            return
          end

          ignored = IGNORED_FIELDS.fetch(hash1[:type].to_s, [])
          keys = (hash1.keys | hash2.keys) - ignored - [:type]
          keys.each { |key| compare_field(hash1[key], hash2[key], path, key) }
        end

        # Compare the value of `key` on the node at `path`.
        def compare_field(value1, value2, path, key)
          if value1.is_a?(::Hash) && value2.is_a?(::Hash)
            compare_hashes(value1, value2, "#{path}.#{key}")
          elsif value1.is_a?(::Array) && value2.is_a?(::Array)
            compare_arrays(value1, value2, path, key)
          elsif value1 != value2
            @result.add_difference(path, "#{key} mismatch (#{value1.inspect} vs #{value2.inspect})")
          end
        end

        def compare_arrays(array1, array2, path, key)
          if array1.size != array2.size
            @result.add_difference(path, "#{key} count mismatch (#{array1.size} vs #{array2.size})")
            return
          end

          array1.zip(array2).each_with_index do |(item1, item2), index|
            # Children keep the bare "path[i]" form; other collections are
            # qualified so the key they came from stays visible.
            item_path = key == :children ? "#{path}[#{index}]" : "#{path}.#{key}[#{index}]"
            compare_element(item1, item2, item_path)
          end
        end

        # Compare a value that is already addressed by `path` (an array element),
        # so the path is not extended again.
        def compare_element(value1, value2, path)
          if value1.is_a?(::Hash) && value2.is_a?(::Hash)
            compare_hashes(value1, value2, path)
          elsif value1.is_a?(::Array) && value2.is_a?(::Array)
            compare_arrays(value1, value2, path, :element)
          elsif value1 != value2
            @result.add_difference(path, "value mismatch (#{value1.inspect} vs #{value2.inspect})")
          end
        end
      end
    end
  end
end
