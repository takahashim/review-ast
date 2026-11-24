# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'leaf_node'

module ReVIEW
  module AST
    # ExtensionBlockNode - a block command the book defines itself, in
    # review-ext.rb, with ReVIEW::Compiler.defblock / defsingle /
    # defminicolumn, and which the AST compiler has no handler of its own for.
    #
    # The AST cannot know what such a command means, so it keeps exactly what
    # the legacy compiler would hand the builder method: the arguments and the
    # body's source lines (nil for a single-line command). A renderer either
    # implements `visit_block_<name>` itself or passes the node on to the
    # matching legacy builder method that review-ext.rb defined (see
    # Renderer::LegacyExtensionBridge).
    #
    # Attributes:
    # - block_type: the command name (Symbol)
    # - args: the bracketed arguments, as the legacy parse_args produces them
    # - lines: the body's raw source lines, or nil when the command has no body
    class ExtensionBlockNode < LeafNode
      attr_reader :block_type, :args, :lines

      def initialize(location:, block_type:, args: nil, lines: nil, **kwargs)
        super(location: location, content: '', **kwargs)
        @block_type = block_type.to_sym
        @args = args || []
        @lines = lines
      end

      # Whether the command was written with a `{ ... //}` body.
      def body?
        !@lines.nil?
      end

      def serialize_to_hash(options = nil)
        options ||= ReVIEW::AST::JSONSerializer::Options.new

        hash = { type: self.class.name.split('::').last }
        hash[:location] = location&.to_h if options.include_location
        serialize_properties(hash, options)
        hash
      end

      def self.deserialize_from_hash(hash)
        new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          block_type: hash['block_type'],
          args: hash['args'],
          lines: hash['lines']
        )
      end

      private

      def serialize_properties(hash, _options)
        hash[:block_type] = block_type
        hash[:args] = args
        hash[:lines] = lines unless lines.nil?
        hash
      end
    end
  end
end
