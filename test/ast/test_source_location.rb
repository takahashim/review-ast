# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/source_location'
require 'review/ast/compiler'
require 'review/ast/json_serializer'
require 'review/book'
require 'review/book/chapter'
require 'json'
require 'stringio'

# Tests for ReVIEW::AST::SourceLocation (filename/lineno/column) and the column
# tracking wired through the compiler and serialization.
class TestSourceLocation < Test::Unit::TestCase
  SourceLocation = ReVIEW::AST::SourceLocation

  def test_basic_accessors
    loc = SourceLocation.new('ch.re', 42, 5)
    assert_equal 'ch.re', loc.filename
    assert_equal 42, loc.lineno
    assert_equal 5, loc.column
    assert_equal 'ch.re:42', loc.string
    assert_equal 'ch.re:42', loc.to_s
    assert_same(loc, loc.snapshot)
    assert loc.frozen?
  end

  def test_column_defaults_to_nil
    loc = SourceLocation.new('ch.re', 42)
    assert_nil(loc.column)
  end

  # When column is nil the hash and error string are byte-identical to the
  # legacy SnapshotLocation output (behaviour-preserving).
  def test_to_h_omits_nil_column
    assert_equal({ filename: 'ch.re', lineno: 42 }, SourceLocation.new('ch.re', 42).to_h)
    assert_equal({ filename: 'ch.re', lineno: 42, column: 5 }, SourceLocation.new('ch.re', 42, 5).to_h)
  end

  def test_format_for_error
    assert_equal ' at line 42 in ch.re', SourceLocation.new('ch.re', 42).format_for_error
    assert_equal ' at line 42, column 5 in ch.re', SourceLocation.new('ch.re', 42, 5).format_for_error
    assert_equal ' at line 42', SourceLocation.new(nil, 42).format_for_error
  end

  def test_equality_and_hash
    a = SourceLocation.new('ch.re', 42, 5)
    b = SourceLocation.new('ch.re', 42, 5)
    c = SourceLocation.new('ch.re', 42, 6)
    assert_equal a, b
    assert_not_equal(a, c)
    assert_equal a.hash, b.hash
    assert_equal 1, [a, b].uniq.size
  end

  def test_from_and_with_column
    base = SourceLocation.new('ch.re', 42, 5)
    assert_equal 9, SourceLocation.from(base, column: 9).column
    assert_equal 5, SourceLocation.from(base).column
    assert_equal 7, base.with_column(7).column
    assert_equal 42, base.with_column(7).lineno
    assert_nil(SourceLocation.from(nil))
  end

  # An inline element is stamped with the column of its '@' within the line.
  def test_compiler_stamps_inline_column
    root = compile("Hello @<b>{world} end\n")
    para = root.children.find { |c| c.class.name.include?('ParagraphNode') }
    inline = para.children.find { |c| c.class.name.include?('InlineNode') }
    assert_not_nil(inline)
    # "Hello " is 6 characters, so @<b> starts at column 7 (1-based).
    assert_equal 7, inline.location.column
  end

  def test_compiler_stamps_block_column
    root = compile("= Title\n\nBody.\n")
    headline = root.children.find { |c| c.class.name.include?('HeadlineNode') }
    assert_equal 1, headline.location.column
  end

  # Column survives a serialize -> deserialize round trip.
  def test_serialization_round_trip_preserves_column
    root = compile("Hello @<b>{world}\n")
    json = ReVIEW::AST::JSONSerializer.serialize(root)
    restored = ReVIEW::AST::JSONSerializer.deserialize(json)

    inline = find_inline(restored)
    assert_not_nil(inline)
    assert_equal find_inline(root).location.column, inline.location.column
    assert_instance_of(SourceLocation, inline.location)
  end

  private

  def compile(source)
    config = ReVIEW::Configure.values
    book = ReVIEW::Book::Base.new(config: config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'ch', 'ch.re', StringIO.new)
    chapter.content = source
    ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
  end

  def find_inline(node)
    return node if node.class.name.include?('InlineNode')

    node.children.each do |child|
      found = find_inline(child)
      return found if found
    end
    nil
  end
end
