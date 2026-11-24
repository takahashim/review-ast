# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast/visitor'
require 'review/ast/footnote_node'
require 'review/ast/render_context'
require 'review/exception'
require 'review/renderer/text_formatter'
require 'review/textutils'
require 'review/ast/inline_processor'
require 'review/ast/block_processor'
require 'review/renderer/legacy_extension_bridge'
require 'review/ast/section_counter'

module ReVIEW
  module Renderer
    # Error class for renderer-specific errors
    class RenderError < ReVIEW::ApplicationError; end

    # Base class for all AST renderers.
    # This class extends the Visitor pattern to provide rendering capabilities
    # for converting AST nodes into various output formats.
    #
    # Subclasses should implement visit methods for specific node types:
    #   - visit_document(node)
    #   - visit_headline(node)
    #   - visit_paragraph(node)
    #   - visit_codeblock(node)
    #   - visit_table(node)
    #   - etc.
    #
    # Usage:
    #   class HtmlRenderer < ReVIEW::Renderer::Base
    #     def visit_headline(node)
    #       level = node.level
    #       caption = process_inline_content(node.caption)
    #       "<h#{level}>#{caption}</h#{level}>"
    #     end
    #   end
    #
    #   renderer = HtmlRenderer.new
    #   html_output = renderer.render(ast_root)
    class Base < ReVIEW::AST::Visitor
      # For add_space?, which decides where join_paragraph_lines puts a space.
      include ReVIEW::TextUtils

      # Initialize the renderer with chapter context.
      #
      # @param chapter [ReVIEW::Book::Chapter] Chapter context
      def initialize(chapter)
        @chapter = chapter
        @book = chapter&.book
        @config = @book&.config || {}
        @render_context = ReVIEW::AST::RenderContext.from_chapter(chapter)
        super()
        @text_formatter = ReVIEW::Renderer::TextFormatter.new(config: @config)
        builder_class = legacy_builder_class
        LegacyExtensionBridge.warn_unroutable_overrides(builder_class) if builder_class
      end

      # The legacy builder whose review-ext.rb methods this renderer runs for
      # commands it has no handler of its own for (LegacyExtensionBridge).
      # nil for a format with no legacy builder.
      def legacy_builder_class
        nil
      end

      attr_reader :text_formatter, :render_context

      # Builder#detab: expand tabs to the book's `tabwidth` when it is set,
      # TextUtils' default of 8 otherwise. An explicit width wins.
      def detab(str, num = nil)
        num ||= @config['tabwidth']
        num ? super(str, num.to_i) : super(str)
      end

      # Render an AST node to the target format.
      #
      # @param ast_root [Object] The root AST node to render
      # @return [String] The rendered output
      def render(ast_root)
        @endnote_nodes = collect_endnotes(ast_root)
        result = visit(ast_root)
        post_process(result)
      end

      # The chapter's //endnote definition nodes, in number order. Collected from
      # the AST (each carries its number as definition_number and is its own
      # content node), so //printendnotes needs no chapter endnote index
      # (doc/design-improvements #7). Replaces reading @chapter.endnotes.
      def endnote_nodes
        @endnote_nodes ||= []
      end

      # Check if caption should be positioned at top for given type
      #
      # @param type [String] Element type (e.g., 'image', 'table', 'list', 'equation')
      # @return [Boolean] true if caption should be at top, false otherwise
      # Whether the caption for this block type goes above it.
      #
      # Builder#caption_top? treats anything that is not the string 'bottom' --
      # including a missing or malformed setting -- as 'top'. This used to test
      # for 'top' instead, so an absent caption_position flipped every caption
      # to the bottom; LaTeX carried its own correct copy, and IDGXML a second
      # inverted one. Configure supplies defaults (image bottom, the rest top),
      # so this only shows up when the config does not come from there.
      #
      # @param type [String] Block type: 'image', 'table', 'list' or 'equation'
      # @return [Boolean] true if the caption goes above the block
      def caption_top?(type)
        config.dig('caption_position', type) != 'bottom'
      end

      # Join a paragraph's source lines the way the builders do.
      #
      # A paragraph's newlines are source formatting, not content: every builder
      # folds them away via split_paragraph / join_lines_to_paragraph. With
      # join_lines_by_lang off the newlines are simply dropped; with it on, a
      # space goes in wherever add_space? wants one at the boundary (an
      # ASCII/Japanese transition). LaTeX, plaintext and TOP all need this, so it
      # lives here rather than once per renderer -- the text renderers did not
      # fold at all, and kept the source's line breaks in their output.
      #
      # @param content [String] Rendered paragraph content
      # @return [String] The content with its source line breaks folded
      def join_paragraph_lines(content)
        return content unless content.include?("\n")

        unless config['join_lines_by_lang']
          return content.gsub(/\n+/, '')
        end

        lines = content.split("\n")
        lang = config['language'] || 'ja'
        0.upto(lines.size - 2) do |n|
          lines[n] += ' ' if add_space?(lines[n], lines[n + 1], lang, true)
        end
        lines.join
      end

      # Render all children of a node and join the results.
      #
      # @param node [Object] The parent node whose children should be rendered
      # @return [String] The joined rendered output of all children
      def render_children(node)
        node.children.map { |child| visit(child) }.join
      end

      # Get the format type for this renderer.
      # Subclasses must override this method to specify their format.
      #
      # @return [Symbol] Format type (:html, :latex, :idgxml, :text, :top)
      def format_type
        raise NotImplementedError, "#{self.class} must implement #format_type"
      end

      private

      attr_reader :config

      # Walk the tree collecting //endnote definition nodes (FootnoteNode with
      # footnote_type == :endnote), ordered by their stamped number.
      def collect_endnotes(root)
        acc = []
        gather_endnotes(root, acc)
        acc.sort_by { |n| n.definition_number&.number || 0 }
      end

      def gather_endnotes(node, acc)
        if node.is_a?(ReVIEW::AST::FootnoteNode) && node.footnote_type == :endnote
          acc << node
        end
        node.each_subnode { |child| gather_endnotes(child, acc) }
      end

      # Post-process the rendered result.
      # Subclasses can override this to perform final formatting,
      # cleanup, or validation.
      #
      # @param result [Object] The result from visiting the AST
      # @return [String] The final rendered output
      def post_process(result)
        result.to_s
      end

      # Escape special characters for the target format.
      #
      # @param str [String] The string to escape
      # @return [String] The escaped string
      def escape(str)
        str.to_s
      end

      # Default visit methods for common node types.
      # These provide basic fallback behavior that subclasses can override.

      def visit_text(node)
        escape(node.content.to_s)
      end

      def visit_inline(node)
        extended = render_extension_inline(node)
        return extended if extended

        content = render_children(node)
        render_inline_element(node.inline_type, content, node)
      end

      # A block command defined in review-ext.rb. A renderer method
      # `visit_block_<name>` (the AST-native way to implement one) wins;
      # otherwise the legacy builder method review-ext.rb defined renders it.
      def visit_extension_block(node)
        method_name = "visit_block_#{node.block_type}"
        return send(method_name, node) if respond_to?(method_name, true)

        bridge = extension_bridge
        return bridge.render_block(node) if bridge&.block?(node.block_type)

        renderer = self.class.name.split('::').last
        hint = if legacy_builder_class
                 "define #{legacy_builder_class.name.split('::').last}##{node.block_type} or #{renderer}##{method_name}"
               else
                 "define #{renderer}##{method_name}"
               end
        raise ReVIEW::CompileError,
              "builder does not support command: //#{node.block_type}#{node.location&.format_for_error} (#{hint} in review-ext.rb)"
      end

      # An inline command whose builder method review-ext.rb defined -- a new
      # command, or a redefined plain one such as inline_b -- rendered by that
      # method from the raw argument, as the legacy compiler would. nil when
      # the renderer handles it itself: no such method, a special inline
      # (ruby, href, references ...) that keeps parsed fields instead of the
      # raw argument, or a review-ext.rb `render_inline_<type>` on the renderer.
      def render_extension_inline(node)
        builder_class = legacy_builder_class
        return unless builder_class

        type = node.inline_type
        return if ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS.key?(type)
        return unless LegacyExtensionBridge.extension_method?(builder_class, :"inline_#{type}")
        return if LegacyExtensionBridge.extension_method?(self.class, :"render_inline_#{type}")

        extension_bridge.render_inline(type, node.args.first.to_s, node.location)
      end

      def extension_bridge
        return @extension_bridge if defined?(@extension_bridge)

        builder_class = legacy_builder_class
        @extension_bridge = builder_class && @chapter ? LegacyExtensionBridge.new(builder_class, @chapter) : nil
      end

      # Render a specific inline element.
      #
      # @param type [String] The inline element type (e.g., 'b', 'i', 'code')
      # @param content [String] The content of the inline element
      # @param node [Object] The original inline node (for additional attributes)
      # @return [String] The rendered inline element
      def render_inline_element(_type, content, _node = nil)
        # Default implementation just returns the content
        content
      end

      # Visit a code block node.
      # This method uses dynamic method dispatch to call format-specific handlers.
      # Subclasses should implement visit_code_block_<type> methods for each code block type.
      #
      # @param node [Object] The code block node
      # @return [String] The rendered code block
      def visit_code_block(node)
        method_name = "visit_code_block_#{node.code_type}"
        if respond_to?(method_name, true)
          send(method_name, node)
        else
          raise NotImplementedError, "Unknown code block type: #{node.code_type}"
        end
      end

      # Visit a block node.
      # This method uses dynamic method dispatch to call format-specific handlers.
      # Subclasses should implement visit_block_<type> methods for each block type.
      #
      # @param node [Object] The block node
      # @return [String] The rendered block
      def visit_block(node)
        method_name = "visit_block_#{node.block_type}"
        if respond_to?(method_name, true)
          send(method_name, node)
        else
          raise NotImplementedError, "Unknown block type: #{node.block_type}"
        end
      end

      # Parse metric option for images and tables
      #
      # @param type [String] Builder type (e.g., 'latex', 'html')
      # @param metric [String] Metric string (e.g., 'latex::width=80mm,scale=0.5')
      # @return [String] Processed metric string
      #
      # @example
      #   parse_metric('latex', 'latex::width=80mm') # => 'width=80mm'
      #   parse_metric('latex', 'scale=0.5') # => 'scale=0.5'
      #   parse_metric('html', 'latex::width=80mm') # => ''
      def parse_metric(type, metric)
        return '' if metric.nil? || metric.empty?

        params = metric.split(/,\s*/)
        results = []
        params.each do |param|
          # Check if param has builder prefix (e.g., "latex::")
          if /\A.+?::/.match?(param)
            # Skip if not for this builder type
            next unless /\A#{type}::/.match?(param)

            # Remove the builder prefix
            param = param.sub(/\A#{type}::/, '')
          end
          # Handle metric transformations if needed
          param2 = handle_metric(param)
          results.push(param2)
        end
        result_metric(results)
      end

      # Handle individual metric transformations
      #
      # @param str [String] Metric string (e.g., 'scale=0.5')
      # @return [String] Transformed metric string
      def handle_metric(str)
        str
      end

      # Combine metric results into final string
      #
      # @param array [Array<String>] Array of metric strings
      # @return [String] Combined metric string
      def result_metric(array)
        array.join(',')
      end

      # Extract text content from a node, handling various node types.
      # This is useful for extracting plain text from caption nodes or
      # inline content.
      #
      # @param node [Object] The node to extract text from
      # @return [String] The extracted text content
      def extract_text(node)
        case node
        when String
          node
        when nil
          ''
        else
          if node.children&.any?
            node.children.map { |child| extract_text(child) }.join
          elsif node.leaf_node?
            node.content.to_s
          else
            node.to_s
          end
        end
      end
    end
  end
end
