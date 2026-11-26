# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'
require 'rbconfig'
require 'review/ast/command_table'
require 'review/htmlbuilder'
require 'review/latexbuilder'
require 'review/idgxmlbuilder'
require 'review/plaintextbuilder'
require 'review/topbuilder'

# AST::CommandTable answers "is this command declared" and "can this format
# render it" from a snapshot of Re:VIEW's builders instead of asking the
# builders at run time. The snapshot is generated
# (tools/generate_command_table.rb), so it is kept honest the way the AST
# schema is: regenerate and compare. And for every command Re:VIEW declares,
# the table has to give the answer the builder itself would.
class TestCommandTable < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)
  TABLE = ReVIEW::AST::CommandTable
  BUILDERS = [ReVIEW::HTMLBuilder, ReVIEW::LATEXBuilder, ReVIEW::IDGXMLBuilder,
              ReVIEW::PLAINTEXTBuilder, ReVIEW::TOPBuilder].freeze

  # The generator has to read builders nothing has reopened, so it runs in a
  # process of its own.
  #
  # The snapshot is of the released review gem the Gemfile.lock pins. Against
  # another Re:VIEW -- a git branch through REVIEW_HEAD, whose version string
  # can still read as the release -- it is expected to differ, and is not
  # compared; test_builtin_support_is_what_the_builder_implements still holds
  # the table to that Re:VIEW's builders.
  def test_committed_snapshot_matches_the_builders
    review_head = ENV.fetch('REVIEW_HEAD', '')
    omit("snapshot is of the released review gem, not REVIEW_HEAD=#{review_head}") unless review_head.empty?
    if ReVIEW::VERSION != TABLE::SNAPSHOT_REVIEW_VERSION
      omit("snapshot is from review #{TABLE::SNAPSHOT_REVIEW_VERSION}, installed is #{ReVIEW::VERSION}")
    end

    env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-rbundler/setup',
                                      File.join(ROOT, 'tools/generate_command_table.rb'), '--stdout')
    assert(status.success?, err)
    assert_equal(File.read(File.join(ROOT, 'lib/review/ast/command_table_snapshot.rb')), out,
                 'command table snapshot is stale; regenerate with: ruby tools/generate_command_table.rb')
  end

  def test_builtin_support_is_what_the_builder_implements
    BUILDERS.each do |builder|
      TABLE::BUILTIN_BLOCKS.each_key do |name|
        assert_equal(builder.public_method_defined?(name), TABLE.block_supported?(name, builder), "#{builder}: //#{name}")
      end
      TABLE::BUILTIN_INLINES.each_key do |name|
        assert_equal(builder.public_method_defined?(:"inline_#{name}"), TABLE.inline_supported?(name, builder),
                     "#{builder}: @<#{name}>")
      end
    end
  end

  def test_examples
    assert_true(TABLE.inline_supported?(:abbr, ReVIEW::HTMLBuilder))
    assert_false(TABLE.inline_supported?(:abbr, ReVIEW::TOPBuilder))
    assert_false(TABLE.inline_supported?(:maru, ReVIEW::HTMLBuilder))
    assert_false(TABLE.block_supported?(:talk, ReVIEW::LATEXBuilder))
    assert_false(TABLE.block_supported?(:hr, ReVIEW::PLAINTEXTBuilder))
  end

  # //column is the AST's own: Re:VIEW does not declare it, so no builder is
  # asked and every format renders it.
  def test_a_command_re_view_does_not_declare_is_supported_everywhere
    assert_false(TABLE.block?(:column))
    BUILDERS.each { |builder| assert_true(TABLE.block_supported?(:column, builder)) }
  end

  def test_declarations
    assert_true(TABLE.block?(:list))
    assert_true(TABLE.block?('emlist'))
    assert_true(TABLE.inline?(:b))
    assert_false(TABLE.block?(:no_such_block))
    assert_false(TABLE.inline?(:no_such_op))
    assert_equal(ReVIEW::Compiler::SYNTAX[:list], TABLE.syntax(:list))
  end

  # A command review-ext.rb declares is not in the snapshot; whether a format
  # renders it is still asked of the builder (the compatibility layer).
  def test_a_review_ext_command_is_looked_up_on_the_builder
    ReVIEW::Compiler.defblock(:zzcmdtable, 0)
    ReVIEW::Compiler.definline(:zzcmdtable)
    assert_true(TABLE.block?(:zzcmdtable))
    assert_true(TABLE.inline?(:zzcmdtable))
    assert_false(TABLE.block_supported?(:zzcmdtable, ReVIEW::HTMLBuilder))
    assert_false(TABLE.inline_supported?(:zzcmdtable, ReVIEW::HTMLBuilder))

    builder = Class.new(ReVIEW::HTMLBuilder) do
      def self.name
        'ReVIEW::HTMLBuilder'
      end

      def zzcmdtable(_lines)
      end

      def inline_zzcmdtable(_str)
      end
    end
    assert_true(TABLE.block_supported?(:zzcmdtable, builder))
    assert_true(TABLE.inline_supported?(:zzcmdtable, builder))
  ensure
    ReVIEW::Compiler::SYNTAX.delete(:zzcmdtable)
    ReVIEW::Compiler::INLINE.delete(:zzcmdtable)
  end

  # review-ext.rb can give a builder a built-in command it lacks; the format
  # then supports it, as it did when the builder was asked directly.
  def test_a_builtin_the_book_adds_to_a_builder_is_supported
    builder = Class.new(ReVIEW::TOPBuilder) do
      def self.name
        'ReVIEW::TOPBuilder'
      end

      def inline_abbr(str)
        str
      end
    end
    assert_true(TABLE.inline_supported?(:abbr, builder))
  end

  def test_review_builder_methods
    assert_true(TABLE.review_builder_method?(ReVIEW::HTMLBuilder, :table_begin))
    assert_true(TABLE.review_builder_method?(ReVIEW::HTMLBuilder, :headline))
    assert_true(TABLE.review_builder_method?(ReVIEW::LATEXBuilder, :escape_latex))
    assert_false(TABLE.review_builder_method?(ReVIEW::HTMLBuilder, :my_own_helper))
  end
end
