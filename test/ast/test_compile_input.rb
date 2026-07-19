# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/compiler'
require 'review/ast/compile_input'
require 'review/book'
require 'review/book/chapter'
require 'review/configure'

# CompileInput is the compiler's input contract: pure data (source, basename)
# plus an explicit service handle (chapter/book) used only by the resolution
# passes. These tests pin the source-only capability and backward compatibility.
class TestCompileInput < Test::Unit::TestCase
  SOURCE = "= Title\n\nA paragraph with @<b>{bold}.\n\n//list[l1][cap]{\ncode\n//}\n"

  def setup
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
  end

  def test_from_source_needs_no_chapter_or_book
    input = ReVIEW::AST::CompileInput.from_source(SOURCE, basename: 'mem')
    assert_nil(input.chapter)
    assert_nil(input.book)
    assert_equal SOURCE, input.source
    assert_equal 'mem', input.basename

    ast = ReVIEW::AST::Compiler.new.compile_to_ast(input)
    assert_kind_of(ReVIEW::AST::DocumentNode, ast)
    # basename flows into source locations
    assert_equal 'mem', ast.location.filename
  end

  def test_from_chapter_matches_passing_the_chapter
    config = ReVIEW::Configure.values
    book = ReVIEW::Book::Base.new(config: config)

    chapter1 = ReVIEW::Book::Chapter.new(book, 1, 'c', 'c.re', StringIO.new)
    chapter1.content = SOURCE
    ast_via_chapter = ReVIEW::AST::Compiler.new.compile_to_ast(chapter1, reference_resolution: false)

    chapter2 = ReVIEW::Book::Chapter.new(book, 1, 'c', 'c.re', StringIO.new)
    chapter2.content = SOURCE
    input = ReVIEW::AST::CompileInput.from_chapter(chapter2)
    assert_same(chapter2, input.chapter)
    assert_same(book, input.book)
    ast_via_input = ReVIEW::AST::Compiler.new.compile_to_ast(input, reference_resolution: false)

    assert_equal ast_via_chapter.serialize_to_hash, ast_via_input.serialize_to_hash
  end
end
