# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/ast'
require_relative 'inline_tokenizer'
require_relative 'reference_node'
require_relative 'raw_content_parser'

require 'review/compiler'

module ReVIEW
  module AST
    # InlineProcessor - Inline element parsing and AST node creation
    #
    # This class handles the complex parsing of Re:VIEW inline elements
    # and converts them to appropriate AST nodes with proper nesting.
    #
    # Responsibilities:
    # - Parse inline markup (@<command>{content}) within text
    # - Create appropriate AST nodes for different inline types
    # - Handle nested inline elements
    # - Process specialized inline formats (ruby, href, kw, etc.)
    class InlineProcessor
      # Split a comma-separated inline argument the way Builder#inline_ruby and
      # Builder#inline_href do: an unescaped comma separates fields and `\,`
      # stands for a literal comma. (The scan is the builder's own regexp, so
      # quirks such as a lone backslash also ending a field are shared.)
      COMMA_FIELD_PATTERN = /(?:(?:(?:\\\\)*\\,)|[^,\\]+)+/

      # Default mapping of inline commands to handler methods
      DEFAULT_INLINE_HANDLERS = {
        embed: :create_inline_embed_ast_node,
        ruby: :create_inline_ruby_ast_node,
        href: :create_inline_href_ast_node,
        kw: :create_inline_kw_ast_node,
        img: :create_inline_ref_ast_node,
        imgref: :create_inline_ref_ast_node,
        list: :create_inline_ref_ast_node,
        table: :create_inline_ref_ast_node,
        eq: :create_inline_ref_ast_node,
        fn: :create_inline_ref_ast_node,
        endnote: :create_inline_ref_ast_node,
        column: :create_inline_ref_ast_node,
        w: :create_inline_ref_ast_node,
        wb: :create_inline_ref_ast_node,
        bib: :create_inline_ref_ast_node,
        bibref: :create_inline_ref_ast_node,
        hd: :create_inline_cross_ref_ast_node,
        chap: :create_inline_cross_ref_ast_node,
        chapref: :create_inline_cross_ref_ast_node,
        title: :create_inline_cross_ref_ast_node,
        sec: :create_inline_cross_ref_ast_node,
        secref: :create_inline_cross_ref_ast_node,
        sectitle: :create_inline_cross_ref_ast_node,
        labelref: :create_inline_cross_ref_ast_node,
        ref: :create_inline_cross_ref_ast_node,
        raw: :create_inline_raw_ast_node
      }.freeze

      def initialize(ast_compiler)
        @ast_compiler = ast_compiler
        @tokenizer = InlineTokenizer.new
        # Copy the static table to allow runtime modifications
        @inline_handlers = DEFAULT_INLINE_HANDLERS.dup
      end

      # Parse inline elements and create AST nodes
      def parse_inline_elements(str, parent_node)
        return if str.empty?

        # Use tokenizer to parse both fence syntax (@<cmd>$...$, @<cmd>|...|) and brace syntax (@<cmd>{...})
        tokens = @tokenizer.tokenize(str, location: @ast_compiler.location)

        tokens.each do |token|
          # Point the compiler's current location at this token's column so that
          # every node built while processing it (here and inside the per-command
          # handlers, which all read @ast_compiler.location) carries the column.
          @ast_compiler.with_temporary_location!(token_location(token.start_pos)) do
            if token.type == :inline
              create_inline_ast_node_from_token(token, parent_node)
            else
              # Plain text
              unless token.content.empty?
                text_node = AST::TextNode.new(
                  location: @ast_compiler.location,
                  content: token.content
                )
                parent_node.add_child(text_node)
              end
            end
          end
        end
      end

      # Build a location at the current line but at the column of a token, from
      # its 0-based offset within the tokenized string. Falls back to the line
      # location when the offset or base location is unavailable.
      def token_location(start_pos)
        base = @ast_compiler.location
        return base unless base && start_pos

        base_column = (base.respond_to?(:column) && base.column) || 1
        AST::SourceLocation.new(base.filename, base.lineno, base_column + start_pos)
      end

      # Register a new inline command handler
      # @param command [Symbol] The inline command name (e.g., :custom)
      # @param handler_method [Symbol] The method name to handle this command
      # @example
      #   processor.register_inline_handler(:custom, :create_inline_custom_ast_node)
      def register_inline_handler(command, handler_method)
        @inline_handlers[command.to_sym] = handler_method
      end

      private

      # Create inline AST node from parsed token
      def create_inline_ast_node_from_token(token, parent_node)
        command = token.command.to_sym
        content = token.content

        # Look up handler method from dynamic registry
        handler_method = @inline_handlers[command]

        if handler_method
          # Call registered handler
          # ref_ast_node and cross_ref_ast_node need command as first argument (ref_type)
          # Others just need content and parent_node
          if handler_method == :create_inline_ref_ast_node || handler_method == :create_inline_cross_ref_ast_node
            send(handler_method, command, content, parent_node)
          else
            send(handler_method, content, parent_node)
          end
        else
          # The legacy Compiler#compile_inline rejects an op nobody declared --
          # the usual typo, @<bb>{...} -- in every format. Ops declared in the
          # legacy INLINE table (built-ins, and review-ext.rb's definline) get a
          # plain InlineNode for the renderer.
          unless ReVIEW::Compiler::INLINE.key?(command)
            raise CompileError, "no such inline op: #{command}#{@ast_compiler.location&.format_for_error}"
          end

          create_standard_inline_node(command, content, parent_node)
        end
      end

      # Create standard inline node (default handler for unknown commands)
      def create_standard_inline_node(command, content, parent_node)
        inline_node = AST::InlineNode.new(
          location: @ast_compiler.location,
          inline_type: command,
          args: [content]
        )

        # Handle nested inline elements in the content
        if content.include?('@<')
          parse_inline_elements(content, inline_node)
        else
          # Simple text content
          text_node = AST::TextNode.new(
            location: @ast_compiler.location,
            content: content
          )
          inline_node.add_child(text_node)
        end

        parent_node.add_child(inline_node)
      end

      # Create inline embed AST node
      def create_inline_embed_ast_node(arg, parent_node)
        target_builders, embed_content = RawContentParser.parse(arg)

        node = AST::EmbedNode.new(
          location: @ast_compiler.location,
          embed_type: :inline,
          target_builders: target_builders,
          content: embed_content || ''
        )
        parent_node.add_child(node)
      end

      # Split a comma-separated inline argument the way Builder#inline_ruby and
      # Builder#inline_href do (see COMMA_FIELD_PATTERN).
      def split_comma_fields(arg)
        arg.scan(COMMA_FIELD_PATTERN)
      end

      def unescape_comma(str)
        str.gsub('\,', ',')
      end

      def build_two_part_inline(type, args, parent_node)
        inline_node = AST::InlineNode.new(
          location: @ast_compiler.location,
          inline_type: type,
          args: args
        )
        args.each do |part|
          inline_node.add_child(AST::TextNode.new(location: @ast_compiler.location, content: part))
        end
        parent_node.add_child(inline_node)
      end

      # Create inline ruby AST node: "base, ruby". Builder#inline_ruby keeps
      # every field after the first as the ruby text (re-joined with commas).
      def create_inline_ruby_ast_node(arg, parent_node)
        base, *ruby = split_comma_fields(arg)
        if base && !ruby.empty?
          build_two_part_inline(:ruby, [unescape_comma(base).strip, unescape_comma(ruby.join(',')).strip], parent_node)
        else
          build_two_part_inline(:ruby, [unescape_comma(arg)], parent_node)
        end
      end

      # Create inline href AST node: "URL" or "URL, label". As in
      # Builder#inline_href, only the first two fields are used.
      def create_inline_href_ast_node(arg, parent_node)
        url, label = split_comma_fields(arg).map(&:lstrip)
        url = url.nil? ? arg : unescape_comma(url).strip
        if label.nil?
          build_two_part_inline(:href, [url], parent_node)
        else
          label = unescape_comma(label).strip
          inline_node = AST::InlineNode.new(
            location: @ast_compiler.location,
            inline_type: :href,
            args: [url, label]
          )
          inline_node.add_child(AST::TextNode.new(location: @ast_compiler.location, content: label))
          parent_node.add_child(inline_node)
        end
      end

      # Create inline kw AST node
      def create_inline_kw_ast_node(arg, parent_node)
        # Parse kw format: "keyword" or "keyword, supplement"
        if arg.include?(',')
          parts = arg.split(',', 2)
          args = [parts[0].strip, parts[1].strip]

          inline_node = AST::InlineNode.new(
            location: @ast_compiler.location,
            inline_type: :kw,
            args: args
          )

          # Add text nodes for both parts
          main_text = AST::TextNode.new(
            location: @ast_compiler.location,
            content: parts[0].strip
          )
          inline_node.add_child(main_text)

          supplement_text = AST::TextNode.new(
            location: @ast_compiler.location,
            content: parts[1].strip
          )
          inline_node.add_child(supplement_text)
        else
          inline_node = AST::InlineNode.new(
            location: @ast_compiler.location,
            inline_type: :kw,
            args: [arg]
          )

          text_node = AST::TextNode.new(
            location: @ast_compiler.location,
            content: arg
          )
          inline_node.add_child(text_node)
        end

        parent_node.add_child(inline_node)
      end

      # Create inline reference AST node (for img, list, table, eq, fn, endnote)
      def create_inline_ref_ast_node(ref_type, arg, parent_node)
        # Parse reference format: "ID" or "chapter_id|ID"
        if arg.include?('|')
          parts = arg.split('|', 2)
          chapter_id = parts[0].strip
          item_id = parts[1].strip
          reference_node = AST::ReferenceNode.new(item_id, chapter_id, location: @ast_compiler.location)
          args = [chapter_id, item_id]
        else
          chapter_id = nil
          item_id = arg
          reference_node = AST::ReferenceNode.new(item_id, nil, location: @ast_compiler.location)
          args = [arg]
        end

        inline_node = AST::InlineNode.new(
          location: @ast_compiler.location,
          inline_type: ref_type,
          args: args,
          target_chapter_id: chapter_id,
          target_item_id: item_id
        )

        inline_node.add_child(reference_node)

        parent_node.add_child(inline_node)
      end

      # Create inline cross-reference AST node (for chap, chapref, sec, secref, sectitle, labelref, ref)
      def create_inline_cross_ref_ast_node(ref_type, arg, parent_node)
        # Handle special case for hd, sec, secref, and sectitle which support pipe-separated format
        if %i[hd sec secref sectitle].include?(ref_type.to_sym) && arg.include?('|')
          parts = arg.split('|', 2)
          chapter_id = parts[0].strip
          item_id = parts[1].strip
          reference_node = AST::ReferenceNode.new(item_id, chapter_id, location: @ast_compiler.location)
          args = [chapter_id, item_id]
        else
          # Standard cross-references with single ID argument
          chapter_id = nil
          item_id = arg
          reference_node = AST::ReferenceNode.new(item_id, nil, location: @ast_compiler.location)
          args = [arg]
        end

        inline_node = AST::InlineNode.new(
          location: @ast_compiler.location,
          inline_type: ref_type,
          args: args,
          target_chapter_id: chapter_id,
          target_item_id: item_id
        )

        inline_node.add_child(reference_node)

        parent_node.add_child(inline_node)
      end

      # Create inline raw AST node (@<raw> command)
      def create_inline_raw_ast_node(content, parent_node)
        target_builders, processed_content = RawContentParser.parse(content)

        embed_node = AST::EmbedNode.new(
          location: @ast_compiler.location,
          embed_type: :inline,
          target_builders: target_builders,
          content: processed_content || ''
        )

        parent_node.add_child(embed_node)
      end
    end
  end
end
