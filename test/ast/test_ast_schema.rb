# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../tools/generate_ast_schema'
require 'json'

# Guards schema/ast-format-1.schema.json (doc/ast-format.ja.md section 5).
#
# The schema is generated from real dumps rather than hand-written, so the way
# to keep it honest is to regenerate it here and compare. A serializer change
# that alters the shape fails this test, and the fix is to rerun
# tools/generate_ast_schema.rb -- the schema cannot silently fall behind.
#
# No JSON Schema validator is involved. The schema is derived from the corpora,
# so "does the corpus validate" is true by construction; what needs checking is
# that the committed file still matches what the serializers emit.
class TestAstSchema < Test::Unit::TestCase
  SCHEMA_PATH = ReVIEW::AST::SchemaGenerator::SCHEMA_PATH

  # DirectiveNode is deliberately absent: it exists only in the surface tree and
  # every lowering pass removes it, so it can never appear in a dump
  # (ast-semantics 2.1). If it ever shows up here, lowering has a hole.
  NEVER_SERIALIZED = %w[LeafNode DirectiveNode].freeze

  def setup
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    @generator = ReVIEW::AST::SchemaGenerator.new
    ReVIEW::AST::SchemaSources.each_tree { |tree| @generator.observe(tree) }
  end

  def committed_schema
    JSON.parse(File.read(SCHEMA_PATH))
  end

  def test_schema_file_exists
    assert_path_exist(SCHEMA_PATH, 'run tools/generate_ast_schema.rb')
  end

  def test_committed_schema_matches_the_serializers
    assert_equal committed_schema, JSON.parse(JSON.generate(@generator.schema)),
                 'schema is stale; regenerate with: ruby tools/generate_ast_schema.rb'
  end

  def test_every_serializable_node_type_is_described
    described = committed_schema['$defs']['node']['oneOf'].map { |ref| ref['$ref'].split('/').last }
    concrete = ObjectSpace.each_object(Class).
               select { |klass| klass < ReVIEW::AST::Node }.
               map { |klass| klass.name.split('::').last }.
               uniq

    assert_empty(concrete - NEVER_SERIALIZED - described,
                 'these node types have no schema definition')
  end

  # A node's schema is closed, so an unknown key is a change that has to be
  # deliberate rather than something that slips through.
  def test_node_definitions_are_closed
    open = committed_schema['$defs'].except('node', 'resolved_data', 'location').
           reject { |_, definition| definition['additionalProperties'] == false }

    assert_empty(open.keys, 'these definitions accept unknown keys')
  end

  # ResolvedData carries a "type" like a node does but is not one; it must not
  # be accepted where a node belongs.
  def test_resolved_data_is_not_a_node
    described = committed_schema['$defs']['node']['oneOf'].map { |ref| ref['$ref'].split('/').last }
    resolved = committed_schema['$defs']['resolved_data']['oneOf'].map { |ref| ref['$ref'].split('/').last }

    assert_not_empty(resolved)
    assert_empty(described & resolved)
  end

  def test_envelope_pins_the_format_version
    envelope = committed_schema['properties']

    assert_equal ReVIEW::AST::JSONSerializer::AST_FORMAT_VERSION, envelope['ast_format']['const']
    assert_equal false, committed_schema['additionalProperties']
  end
end
