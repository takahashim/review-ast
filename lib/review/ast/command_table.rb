# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'set'
require 'review/compiler'
require_relative 'command_table_snapshot'

module ReVIEW
  module AST
    # Which commands exist, and which formats can render them -- answered by
    # review-ast instead of by asking Re:VIEW's builders at run time
    # (doc/design-extension-api.ja.md, section 2).
    #
    # Two sources:
    #
    # - the commands Re:VIEW itself declares, with the builders that
    #   implement them, read once into CommandTable::BUILTIN_BLOCKS /
    #   BUILTIN_INLINES by tools/generate_command_table.rb;
    # - the commands a book's review-ext.rb declares
    #   (ReVIEW::Compiler.defblock / definline), read from Re:VIEW's tables
    #   as they are now. For these, and only these, a builder is still asked
    #   whether it implements the command: that is the compatibility layer
    #   for review-ext.rb builder methods (LegacyExtensionBridge).
    #
    # A command the AST handles that Re:VIEW does not declare (//column, say)
    # is not in either table, and every format renders it.
    class CommandTable
      class << self
        # Whether //name is a declared block command: Re:VIEW's own, or one
        # review-ext.rb declared.
        def block?(name)
          name = name.to_sym
          BUILTIN_BLOCKS.key?(name) || ReVIEW::Compiler::SYNTAX.key?(name)
        end

        # Whether @<name> is a declared inline op.
        def inline?(name)
          name = name.to_sym
          BUILTIN_INLINES.key?(name) || ReVIEW::Compiler::INLINE.key?(name)
        end

        # The declaration of a block command (argument count, body rules).
        def syntax(name)
          ReVIEW::Compiler::SYNTAX.fetch(name.to_sym)
        end

        # Whether the format whose legacy builder is builder_class can render
        # //name -- the rule ReVIEW::Compiler#compile_command applies.
        def block_supported?(name, builder_class)
          supported?(BUILTIN_BLOCKS, ReVIEW::Compiler::SYNTAX, name.to_sym, name.to_sym, builder_class)
        end

        # #block_supported? for @<name> (ReVIEW::Compiler#compile_inline).
        def inline_supported?(name, builder_class)
          supported?(BUILTIN_INLINES, ReVIEW::Compiler::INLINE, name.to_sym, :"inline_#{name}", builder_class)
        end

        # Whether Re:VIEW itself defines `name` on builder_class (or on what
        # it inherits), public or private. A review-ext.rb method by that
        # name is a redefinition; any other is the book's own helper.
        def review_builder_method?(builder_class, name)
          methods = review_builder_methods(builder_class)
          !methods.nil? && methods.include?(name.to_sym)
        end

        private

        # A command Re:VIEW declares is supported where the snapshot says its
        # builder implements it -- or where review-ext.rb gave the builder
        # the method itself. A command only review-ext.rb declares is
        # supported where the builder has the method (the compatibility
        # layer). Anything else is the AST's own and supported everywhere.
        def supported?(builtin, legacy_table, name, method_name, builder_class)
          builder = builder_key(builder_class)
          if (builders = builtin[name])
            builders.include?(builder) || extension_public_method?(builder_class, method_name)
          elsif legacy_table.key?(name)
            builder_class.public_method_defined?(method_name)
          else
            true
          end
        end

        def extension_public_method?(builder_class, method_name)
          builder_class.public_method_defined?(method_name) &&
            !review_builder_method?(builder_class, method_name)
        end

        def review_builder_methods(builder_class)
          @review_builder_methods ||= BUILDER_METHODS.transform_values(&:to_set)
          @review_builder_methods[builder_key(builder_class)]
        end

        def builder_key(builder_class)
          builder_class.name.split('::').last
        end
      end
    end
  end
end
