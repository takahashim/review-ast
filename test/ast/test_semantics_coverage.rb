# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast'
require 'review/ast/block_processor'
require 'review/ast/inline_processor'

# Freshness guard for doc/ast-semantics.md (design-improvements #6): every block
# command the compiler recognizes, and every special inline command, must be
# mentioned in the semantics document. Adding a command without documenting its
# meaning fails here, so the spec cannot silently fall behind the code.
class TestSemanticsCoverage < Test::Unit::TestCase
  DOC = File.read(File.expand_path('../../doc/ast-semantics.md', __dir__))

  def test_every_block_command_is_documented
    commands = ReVIEW::AST::BlockProcessor::BLOCK_COMMAND_TABLE.keys
    missing = commands.reject { |c| DOC.include?("//#{c}") }
    assert_empty(missing,
                 "block commands missing from doc/ast-semantics.md: #{missing.inspect}")
  end

  def test_every_special_inline_command_is_documented
    commands = ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS.keys
    missing = commands.reject { |c| DOC.include?("@<#{c}>") }
    assert_empty(missing,
                 "special inline commands missing from doc/ast-semantics.md: #{missing.inspect}")
  end

  def test_every_node_type_is_in_the_inventory
    Dir[File.expand_path('../../lib/review/ast/*_node.rb', __dir__)].each { |f| require f }
    names = ObjectSpace.each_object(Class).
            select { |c| c < ReVIEW::AST::Node }.
            map { |c| c.name.split('::').last }.uniq
    missing = names.reject { |n| DOC.include?("`#{n}`") }
    assert_empty(missing,
                 "node types missing from doc/ast-semantics.md inventory: #{missing.inspect}")
  end
end
