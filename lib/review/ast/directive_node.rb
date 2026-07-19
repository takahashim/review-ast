# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'node'

module ReVIEW
  module AST
    # DirectiveNode - a parser-instruction marker, not content.
    #
    # These commands (//noindent, //olnum, //tsize, //firstlinenum, //beginchild,
    # //endchild) do not render anything themselves; they modify a sibling (the
    # next paragraph's indent, the next list's start number, etc.). The compiler
    # keeps them in the surface tree so it stays faithful to the source, then a
    # post-process pass lowers each into an attribute on its target and removes
    # it. Giving them their own type (instead of a generic BlockNode with a
    # naming-convention block_type) makes "is this a parser instruction?" a
    # checkable property, and lets the stage-boundary check assert that no
    # DirectiveNode survives into the core tree. See doc/design-improvements #3.
    class DirectiveNode < Node
      attr_reader :directive_type, :args

      def initialize(location:, directive_type:, args: nil, **kwargs)
        super(location: location, **kwargs)
        @directive_type = directive_type
        @args = args || []
      end

      # A DirectiveNode is a parser instruction, not renderable content.
      def directive?
        true
      end

      def to_h
        result = super.merge(directive_type: directive_type)
        result[:args] = args if args && !args.empty?
        result
      end

      def self.deserialize_from_hash(hash)
        node = new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          directive_type: hash['directive_type']&.to_sym,
          args: hash['args']
        )
        (hash['children'] || []).each do |child_hash|
          child = ReVIEW::AST::JSONSerializer.deserialize_from_hash(child_hash)
          node.add_child(child) if child.is_a?(ReVIEW::AST::Node)
        end
        node
      end

      private

      def serialize_properties(hash, options)
        hash[:directive_type] = directive_type
        hash[:args] = args if args && !args.empty?
        if children.any?
          hash[:children] = children.map { |child| child.serialize_to_hash(options) }
        end
        hash
      end
    end
  end
end
