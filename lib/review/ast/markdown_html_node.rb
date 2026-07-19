# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require_relative 'node'

module ReVIEW
  module AST
    # MarkdownHtmlNode - Node for HTML content in Markdown documents
    #
    # This node represents raw HTML content found in Markdown documents,
    # including HTML comments and tags that may have special meaning
    # for Re:VIEW processing (such as column markers).
    class MarkdownHtmlNode < Node
      attr_reader :html_content, :html_type

      # Initialize MarkdownHtmlNode
      #
      # @param location [SourceLocation] Source location
      # @param html_content [String] Raw HTML content
      # @param html_type [Symbol] Type of HTML content (:comment, :tag, :block)
      def initialize(location:, html_content:, html_type: :block)
        super(location: location)
        @html_content = html_content
        @html_type = html_type
      end

      # Check if this is an HTML comment
      #
      # @return [Boolean] True if this is an HTML comment
      def comment?
        @html_type == :comment
      end

      # Check if this is an HTML tag
      #
      # @return [Boolean] True if this is an HTML tag
      def tag?
        @html_type == :tag
      end

      def self.deserialize_from_hash(hash)
        new(
          location: ReVIEW::AST::JSONSerializer.restore_location(hash),
          html_content: hash['html_content'],
          html_type: (hash['html_type'] || 'block').to_sym
        )
      end

      private

      def serialize_properties(hash, _options)
        hash[:html_content] = html_content
        hash[:html_type] = html_type
        hash
      end
    end
  end
end
