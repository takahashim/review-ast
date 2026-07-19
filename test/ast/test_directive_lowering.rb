# frozen_string_literal: true

require_relative '../test_helper'
require 'review'
require 'review/ast/compiler'
require 'review/ast/document_node'
require 'review/ast/directive_node'
require 'review/ast/source_location'
require 'review/ast/json_serializer'
require 'stringio'

# Stage-boundary check for parser-instruction directives
# (doc/design-improvements #3). Every //noindent, //olnum, //tsize,
# //firstlinenum, //beginchild and //endchild must be lowered to an attribute
# and removed by the post-process passes; none may survive into the core tree.
class TestDirectiveLowering < Test::Unit::TestCase
  # Sources that use each directive with an eligible target -- all must lower
  # cleanly and leave no marker behind.
  SOURCES = [
    "Para one.\n\n//noindent\nPara two.\n",
    "//olnum[10]\n\n 1. a\n 2. b\n",
    "//tsize[|latex|10,18,50]\n\n//table[t][C]{\nA\tB\tC\n//}\n",
    "//firstlinenum[100]\n\n//listnum[c][C]{\nx\ny\n//}\n",
    " * parent\n\n//beginchild\n\n 1. child\n\n//endchild\n"
  ].freeze

  def test_directives_are_lowered_and_absent_from_core_tree
    SOURCES.each do |source|
      root = compile(source)
      leaked = find_marker(root)
      assert_nil(leaked, "a directive marker leaked for source: #{source.inspect}")
    end
  end

  # A directive that reaches the core tree is a fail-fast, located error.
  def test_leaked_directive_raises_with_location
    compiler = ReVIEW::AST::Compiler.new
    root = ReVIEW::AST::DocumentNode.new(location: loc(1))
    root.add_child(ReVIEW::AST::DirectiveNode.new(location: loc(5), directive_type: :noindent, args: []))

    error = assert_raise(ReVIEW::ApplicationError) do
      compiler.send(:assert_directives_lowered, root)
    end
    assert_match(/noindent directive was not lowered/, error.message)
    assert_match(/line 5, column 1/, error.message)
  end

  # A DirectiveNode round-trips through serialization (for a surface-tree dump
  # that keeps the markers), preserving its type and args.
  def test_directive_node_serialization_round_trip
    node = ReVIEW::AST::DirectiveNode.new(location: loc(3), directive_type: :olnum, args: ['10'])
    restored = ReVIEW::AST::JSONSerializer.deserialize(ReVIEW::AST::JSONSerializer.serialize(node))
    assert_instance_of(ReVIEW::AST::DirectiveNode, restored)
    assert restored.directive?
    assert_equal :olnum, restored.directive_type
    assert_equal ['10'], restored.args
  end

  private

  def loc(lineno)
    ReVIEW::AST::SourceLocation.new('t.re', lineno, 1)
  end

  def compile(source)
    config = ReVIEW::Configure.values
    config['builder'] ||= 'latex'
    ReVIEW::I18n.setup(config['language'] || 'ja')
    book = ReVIEW::Book::Base.new('.', config: config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(source))
    ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
  end

  def find_marker(node)
    return node if node.directive?

    node.children.each do |child|
      found = find_marker(child)
      return found if found
    end
    nil
  end
end
