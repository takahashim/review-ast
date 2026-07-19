# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast'
require 'review/ast/block_processor'
require 'review/ast/inline_processor'

# Freshness guard for the semantics documents (design-improvements #6): every
# block command the compiler recognizes, every special inline command, and every
# node type must be mentioned in both ast-semantics.md and its Japanese companion
# ast-semantics.ja.md. Adding a command/node type without documenting it (or
# letting the two versions drift apart) fails here, so the spec cannot silently
# fall behind the code.
class TestSemanticsCoverage < Test::Unit::TestCase
  DOCS = {
    'doc/ast-semantics.md' => File.read(File.expand_path('../../doc/ast-semantics.md', __dir__)),
    'doc/ast-semantics.ja.md' => File.read(File.expand_path('../../doc/ast-semantics.ja.md', __dir__))
  }.freeze

  def each_doc(&block)
    DOCS.each(&block)
  end

  def test_every_block_command_is_documented
    commands = ReVIEW::AST::BlockProcessor::BLOCK_COMMAND_TABLE.keys
    each_doc do |name, text|
      missing = commands.reject { |c| text.include?("//#{c}") }
      assert_empty(missing, "block commands missing from #{name}: #{missing.inspect}")
    end
  end

  def test_every_special_inline_command_is_documented
    commands = ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS.keys
    each_doc do |name, text|
      missing = commands.reject { |c| text.include?("@<#{c}>") }
      assert_empty(missing, "special inline commands missing from #{name}: #{missing.inspect}")
    end
  end

  def test_every_node_type_is_in_the_inventory
    Dir[File.expand_path('../../lib/review/ast/*_node.rb', __dir__)].each { |f| require f }
    names = ObjectSpace.each_object(Class).
            select { |c| c < ReVIEW::AST::Node }.
            map { |c| c.name.split('::').last }.uniq
    each_doc do |name, text|
      missing = names.reject { |n| text.include?("`#{n}`") }
      assert_empty(missing, "node types missing from #{name} inventory: #{missing.inspect}")
    end
  end
end
