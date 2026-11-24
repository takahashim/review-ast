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
require 'review/renderer/graph_image'
require 'review/ast/image_node'
require 'review/ast/minicolumn_node'
require 'review/ast/extension_block_node'
require 'review/ast/section_counter'
require 'review/ast/book_unit_view'

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
      # Re:VIEW 2 compatibility mode, as the builders ask for it
      # (Configure#check_version('2', exception: false): review_version 2.x,
      # or a blank one). LATEXBuilder then writes the older macros
      # (\textbf, \includegraphics, \caption, no reviewlistblock ...).
      def self.review_version2?(config)
        config.respond_to?(:check_version) && config.check_version('2', exception: false)
      end

      def review_version2?
        return @review_version2 if defined?(@review_version2)

        @review_version2 = Base.review_version2?(config)
      end

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

      # The maker's ImgGraph, which draws deferred Mermaid diagrams in a
      # browser at the end of the build (EPUBMaker, PDFMaker, IDGXMLMaker).
      attr_writer :img_graph

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

        fold_source_lines(content.split("\n"))
      end

      # join_paragraph_lines for content already split into its source lines
      # (LatexRenderer#join_source_lines is a different join, for dd and list
      # items).
      #
      # @param lines [Array<String>]
      # @return [String]
      def fold_source_lines(lines)
        return lines.join unless config['join_lines_by_lang']

        lang = config['language'] || 'ja'
        lines = lines.dup
        0.upto(lines.size - 2) do |n|
          lines[n] += ' ' if add_space?(lines[n], lines[n + 1], lang, true)
        end
        lines.join
      end

      # Inline content rendered and joined as join_lines_to_paragraph joins
      # a paragraph's lines. Only the source line breaks fold: the newlines
      # in the text nodes, and the breaks before the child indexes `breaks`
      # gives (a list item's continuation lines). A newline an inline writes
      # (@<br>, @<raw>{|text|a\\nb}) is content, and stays -- the builders
      # compile each source line on its own and only then join them.
      def render_source_lines(children, breaks: [])
        lines = [+'']
        children.each_with_index do |child, index|
          lines << +'' if index > 0 && breaks.include?(index)
          output = visit(child)
          if child.instance_of?(ReVIEW::AST::TextNode)
            first, *rest = output.split("\n", -1)
            lines.last << first.to_s
            lines.concat(rest.map(&:dup))
          else
            lines.last << output
          end
        end
        fold_source_lines(lines)
      end

      # Whether a list item's child is part of its own text (inline content)
      # rather than a block nested in it: text, an inline command, or an
      # inline @<raw>/@<embed>.
      def inline_content_node?(node)
        node.is_a?(ReVIEW::AST::TextNode) || node.is_a?(ReVIEW::AST::InlineNode) ||
          (node.is_a?(ReVIEW::AST::EmbedNode) && node.inline?)
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
        dispatch_inline_element(node.inline_type, content, node)
      end

      # render_inline_element, unless review-ext.rb gave this renderer its own
      # `render_inline_<type>`: that wins, in every format. (The renderers
      # dispatch built-in inlines differently -- HTML, LaTeX, IDGXML and Typst
      # through an inline element handler, TOP through a case -- so the
      # extension method is looked for here, once, rather than in each.)
      def dispatch_inline_element(type, content, node)
        return send(:"render_inline_#{type}", type, content, node) if renderer_extension_inline?(type)

        render_inline_element(type, content, node)
      end

      # Whether review-ext.rb defined `render_inline_<type>` on this renderer.
      def renderer_extension_inline?(type)
        @renderer_extension_inline ||= {}
        @renderer_extension_inline.fetch(type) do
          @renderer_extension_inline[type] = LegacyExtensionBridge.extension_method?(self.class, :"render_inline_#{type}")
        end
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
        return unless LegacyExtensionBridge.extension_method?(builder_class, :"inline_#{type}")
        return if renderer_extension_inline?(type)

        # The argument as the legacy compiler passes it. A special inline
        # (ruby, href, references ...) keeps parsed fields in args, so only its
        # source_arg will do; a tree loaded from JSON has none.
        arg = node.source_arg
        arg ||= node.args.first.to_s unless ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS.key?(type)
        return unless arg

        extension_bridge.render_inline(type, arg, node.location)
      end

      # Every node passes here first: a block command its builder does not
      # implement is an error, and a block whose builder method review-ext.rb
      # redefined is written by that method (LegacyExtensionBridge).
      def visit(node)
        check_builder_support(node)
        delegated = render_overridden_block(node)
        return delegated if delegated

        super
      end
      public :visit

      # A built-in block command (or a minicolumn's ends) that review-ext.rb
      # redefined on this format's builder, rendered by the redefinition from
      # the command's legacy form. nil when it is not redefined, the node has
      # no legacy form (a tree loaded from JSON), or the format has no builder.
      def render_overridden_block(node)
        command = node.respond_to?(:source_command) && node.source_command
        return unless command
        return if node.is_a?(ReVIEW::AST::ExtensionBlockNode) || legacy_builder_class.nil?

        minicolumn = node.is_a?(ReVIEW::AST::MinicolumnNode)
        return unless LegacyExtensionBridge.block_overridden?(legacy_builder_class, command.name, minicolumn: minicolumn)

        bridge = extension_bridge

        if minicolumn
          bridge.render_minicolumn(command.name, command.args, node.location) { render_children(node) }
        else
          bridge.render_command(command.name, command.args, command.lines, node.location)
        end
      end

      # As in ReVIEW::Compiler#compile_command, a block command the format's builder
      # has no method for is an error -- LaTeX has no //talk, the text formats
      # no //hr or //parasep. Read from the block's type, so a tree loaded from
      # JSON is checked as the fresh one is. A Markdown chapter is not checked:
      # its blocks are the adapter's (a thematic break is an hr in every
      # format), not commands anyone wrote.
      #
      # The same for an inline op (ReVIEW::Compiler#compile_inline): the text
      # formats have no @<abbr>, HTML no @<pageref>.
      def check_builder_support(node)
        inline = node.is_a?(ReVIEW::AST::InlineNode)
        return unless inline || node.is_a?(ReVIEW::AST::BlockNode)

        builder_class = legacy_builder_class
        return if builder_class.nil? || AST::BookUnitView.markdown?(@chapter)

        if inline
          # A review-ext.rb `render_inline_<type>` on the renderer implements
          # the op for this format as well as a builder method would.
          return if renderer_extension_inline?(node.inline_type)
          return if LegacyExtensionBridge.builder_supports_inline?(builder_class, node.inline_type)

          raise ReVIEW::CompileError, "builder does not support inline op: @<#{node.inline_type}>#{node.location&.format_for_error}"
        end
        return if LegacyExtensionBridge.builder_supports?(builder_class, node.block_type)

        raise ReVIEW::CompileError, "builder does not support command: //#{node.block_type}#{node.location&.format_for_error}"
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

      # //graph, as Builder#graph does it: produce the image file with the
      # generator the block names, then render the block as the image it now
      # is (the builder ends with image(lines, id, caption)) -- here through
      # this renderer's own visit_image. IDGXML and Typst write their own
      # markup but share the generation below.
      def visit_block_graph(node)
        image = ReVIEW::AST::ImageNode.new(location: node.location, id: node.args[0], caption_node: node.caption_node)
        image.image_path = generate_graph_image(node)
        image.definition_number = node.definition_number
        visit_image(image)
      end

      # The builder name that names the image subdirectory
      # (<imagedir>/<target_name>/<id>.<image_ext>), as Builder#target_name.
      def target_name
        format_type.to_s
      end

      # The image format this renderer asks //graph generators for, as each
      # builder's #image_ext.
      def image_ext
        raise NotImplementedError, "#{self.class} must implement #image_ext"
      end

      # Run the //graph block's generator and return the image's path.
      def generate_graph_image(node)
        id, command = node.args
        content = node.children.map { |child| child.is_a?(ReVIEW::AST::TextNode) ? child.content : '' }.join("\n")
        content += "\n" unless content.empty?

        return deferred_mermaid_path(id, content) if command == 'mermaid'

        # Builder#graph dispatches to graph_<command> and fails on a command
        # it has no method for.
        unless GraphImage::GENERATORS.key?(command)
          raise ReVIEW::CompileError, "unknown graph command: #{command}#{node.location&.format_for_error}"
        end

        graph_image.generate(id: id, command: command, content: content)
      end

      def graph_image
        @graph_image ||= GraphImage.new(imagedir: render_context.imagedir, target_name: target_name, image_ext: image_ext)
      end

      # Mermaid diagrams are drawn in a browser after the build, so ImgGraph
      # only records the request here. Builder#graph_mermaid stops the build
      # when playwright-runner is missing; the AST renderers warn and point at
      # the path the image would have had.
      def deferred_mermaid_path(id, content)
        require 'playwrightrunner'
        @img_graph ||= begin
          require 'review/img_graph'
          ReVIEW::ImgGraph.new(config, target_name)
        end
        @img_graph.defer_mermaid_image(content, id)
      rescue LoadError
        ReVIEW.logger.warn("could not handle Mermaid of //graph[#{id}] (playwright-runner is not installed)")
        graph_image.file_path(id)
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
