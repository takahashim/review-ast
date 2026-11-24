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
    # method also wins over the renderer's built-in handling of the command it
    # redefines, as it does in the legacy path: an inline (`def inline_b`,
    # `def inline_ruby`), a block (`def emlist`, `def table`) or a minicolumn's
    # ends (`def note_begin`). The renderer still numbers and indexes the
    # block; the builder method only writes it. For that, each node keeps the
    # command in the legacy compiler's form (Node#source_command,
    # InlineNode#source_arg). Redefinitions the AST cannot route -- structural
    # hooks such as `def headline`, and the parser directives -- are reported
    # once with a warning instead of being silently ignored.
    class LegacyExtensionBridge
      # A ReVIEW::Compiler that fails at the first error. The legacy compiler
      # logs errors and fails at the end of the chapter; here the error has to
      # surface while the AST renderer is still on the node that caused it.
      class StrictCompiler < ReVIEW::Compiler
        def error(msg, location: nil)
          raise ReVIEW::CompileError, location ? "#{location}: #{msg}" : msg
        end

        # One block command, as #read_command and #compile_command would run
        # it: the body's lines inline-compiled by the builder (raw for the
        # commands the compiler leaves unparsed), with the command on the
        # name stack the escaping decisions read.
        def run_command(name, args, lines)
          @command_name_stack.push(name)
          compile_command(syntax_descriptor(name), args, lines && compile_body(name, lines))
        ensure
          @command_name_stack.pop
        end

        # #compile_minicolumn_begin / #compile_minicolumn_end.
        def run_minicolumn_begin(name, args)
          compile_minicolumn_begin(name, *args)
        end

        def run_minicolumn_end
          compile_minicolumn_end
        end

        private

        def compile_body(name, lines)
          raw = @non_parsed_commands.include?(name)
          @builder.doc_status[name] = true
          lines.filter_map do |line|
            if raw
              line.chomp
            elsif !line.start_with?('#@')
              text(line.rstrip, true)
            end
          end
        ensure
          @builder.doc_status[name] = nil
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

      # Builder methods whose redefinition the AST path does not pick up: the
      # structure the AST renders itself, and the parser directives it lowers.
      STRUCTURAL_HOOKS = %i[headline paragraph ul_begin ul_item ul_end ol_begin ol_item ol_end
                            dl_begin dt dd dl_end column_begin column_end result
                            noindent olnum firstlinenum tsize beginchild endchild].freeze

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

        # Whether review-ext.rb redefined the builder method for this block
        # command (for a minicolumn, its _begin or _end). Asked for every
        # block, so it is answered without binding a builder.
        def block_overridden?(klass, name, minicolumn: false)
          @overridden ||= {}
          @overridden.fetch([klass, name, minicolumn]) do
            names = minicolumn ? [:"#{name}_begin", :"#{name}_end"] : [name.to_sym]
            @overridden[[klass, name, minicolumn]] = names.any? { |method| extension_method?(klass, method) }
          end
        end

        def unroutable_overrides(klass)
          (klass.instance_methods + klass.private_instance_methods).uniq.select do |name|
            unroutable_name?(name) && extension_method?(klass, name)
          end.sort
        end

        private

        def unroutable_name?(name)
          STRUCTURAL_HOOKS.include?(name.to_sym)
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
        render_command(node.block_type, node.args, node.lines, node.location)
      end

      # The builder method's output for a block command given in its legacy
      # form (Node#source_command): a review-ext.rb redefinition of a built-in
      # command such as LATEXBuilder#emlist.
      def render_command(name, args, lines, location)
        at(location) { captured { @compiler.run_command(name, args, lines) } }
      end

      # A minicolumn (//note{ ... //}) whose <name>_begin / <name>_end
      # review-ext.rb redefined: the builder writes both ends, the renderer
      # (the block) the content in between, as in the legacy compiler.
      def render_minicolumn(name, args, location)
        at(location) do
          head = captured { @compiler.run_minicolumn_begin(name, args) }
          body = yield
          head + body + captured { @compiler.run_minicolumn_end }
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
