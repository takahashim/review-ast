# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/compiler'
require 'review/location'
require 'review/exception'
require 'review/logger'

module ReVIEW
  module Renderer
    # Runs the methods a book's review-ext.rb adds to a legacy builder, so a
    # book with its own commands builds through the AST path unchanged.
    #
    # A review-ext.rb typically does two things: declares syntax
    # (ReVIEW::Compiler.defblock :foo / definline :bar) and implements it on a
    # builder (HTMLBuilder#foo(lines, *args), LATEXBuilder#inline_bar(str)).
    # The AST compiler keeps such a block as an ExtensionBlockNode and such an
    # inline as an ordinary InlineNode holding its raw argument; this bridge
    # hands both to the builder method exactly as ReVIEW::Compiler would --
    # block lines inline-compiled by the builder, the inline argument raw --
    # and returns what the method wrote.
    #
    # Only methods defined outside the review and review-ast gems count (that
    # is what tells a review-ext.rb method from the builder's own). Such a
    # method also wins over the renderer's built-in handling of a plain inline
    # command it redefines (`def inline_b`), as it does in the legacy path.
    # Redefinitions the AST cannot route -- a built-in block command such as
    # `def note`, a structural hook such as `def headline` -- are reported once
    # with a warning instead of being silently ignored.
    class LegacyExtensionBridge
      # A ReVIEW::Compiler that fails at the first error. The legacy compiler
      # logs errors and fails at the end of the chapter; here the error has to
      # surface while the AST renderer is still on the node that caused it.
      class StrictCompiler < ReVIEW::Compiler
        def error(msg, location: nil)
          raise ReVIEW::CompileError, location ? "#{location}: #{msg}" : msg
        end
      end

      # Stands in for the LineInput a ReVIEW::Location reads its line from.
      class LinePosition
        attr_accessor :lineno
      end

      # Where the review gem (lib/review/compiler.rb -> its root) and
      # review-ast (lib/) live. A method defined anywhere else is the book's.
      GEM_DIRS = [
        File.expand_path('../../..', ReVIEW::Compiler.instance_method(:compile).source_location.first),
        File.expand_path('../..', __dir__)
      ].map { |dir| File.join(dir, '') }.freeze

      # Builder methods whose redefinition the AST path does not pick up.
      STRUCTURAL_HOOKS = %i[headline paragraph ul_begin ul_item ul_end ol_begin ol_item ol_end
                            dl_begin dt dd dl_end column_begin column_end result].freeze

      @warned = {}

      class << self
        # Whether `name` on builder_class was defined by the book rather than
        # by Re:VIEW or review-ast.
        def extension_method?(klass, name)
          return false unless klass.method_defined?(name) || klass.private_method_defined?(name)

          file = klass.instance_method(name).source_location&.first
          !file.nil? && GEM_DIRS.none? { |dir| file.start_with?(dir) }
        end

        # Warn, once per builder class, about review-ext.rb methods the AST
        # path cannot call.
        def warn_unroutable_overrides(klass, logger: ReVIEW.logger)
          return if @warned[klass]

          @warned[klass] = true
          unroutable_overrides(klass).each do |name|
            logger.warn("review-ext.rb redefines #{klass.name.split('::').last}##{name}, which the AST renderer does not call; " \
                        'implement it on the renderer instead (see doc/review-ext.md)')
          end
        end

        def unroutable_overrides(klass)
          (klass.instance_methods + klass.private_instance_methods).uniq.select do |name|
            unroutable_name?(name) && extension_method?(klass, name)
          end.sort
        end

        private

        def unroutable_name?(name)
          name = name.to_s
          if name.start_with?('inline_')
            # A special inline keeps parsed fields, not the raw argument.
            ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS.key?(name.delete_prefix('inline_').to_sym)
          else
            STRUCTURAL_HOOKS.include?(name.to_sym) || ast_block_command?(name.to_sym)
          end
        end

        def ast_block_command?(name)
          ReVIEW::AST::BlockProcessor::BLOCK_COMMAND_TABLE.key?(name)
        end
      end

      def initialize(builder_class, chapter)
        @builder_class = builder_class
        @builder = builder_class.new
        @compiler = StrictCompiler.new(@builder)
        @position = LinePosition.new
        @builder.bind(@compiler, chapter, ReVIEW::Location.new(chapter.basename, @position))
      end

      attr_reader :builder_class

      # Whether review-ext.rb gave the builder an inline_<type> method.
      def inline?(type)
        self.class.extension_method?(@builder_class, :"inline_#{type}")
      end

      # Whether the builder implements the block command at all (it has to
      # be review-ext.rb's: the AST handles every command the gems define).
      def block?(name)
        @builder.respond_to?(name)
      end

      def render_inline(type, arg, location)
        at(location) { @builder.__send__(:"inline_#{type}", arg) }
      end

      # The builder method's output for one ExtensionBlockNode, as
      # ReVIEW::Compiler#compile_command would call it.
      def render_block(node)
        at(node.location) do
          captured do
            if node.body?
              lines = node.lines.map { |line| @compiler.text(line.rstrip, true) }
              @builder.__send__(node.block_type, lines, *node.args)
            else
              @builder.__send__(node.block_type, *node.args)
            end
          end
        end
      end

      private

      def at(location)
        @position.lineno = location&.lineno
        yield
      end

      # What the builder wrote to its output during the block.
      def captured
        start = @builder.raw_result.bytesize
        yield
        @builder.raw_result.byteslice(start..) || ''
      end
    end
  end
end
