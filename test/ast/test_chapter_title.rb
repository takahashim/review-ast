# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/indexer'
require 'review/ast/compiler'
require 'review/book'
require 'review/book/chapter'
require 'review/configure'

# The chapter title is owned by the AST: the Indexer sets chapter.title from the
# first headline's raw_caption. For Re:VIEW this must reproduce the gem's
# ReVIEW::Book::BookUnit#title byte-for-byte (both take the first "=+" line's
# caption with the level markers / leading tag / leading label stripped and the
# inline markup kept raw). These tests pin that spec.
class TestChapterTitle < Test::Unit::TestCase
  def setup
    @config = ReVIEW::Configure.values
    @config['language'] = 'ja'
    @book = ReVIEW::Book::Base.new(config: @config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
  end

  # Title after the AST Indexer has run over the content.
  def ast_title(content)
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'c', 'c.re', StringIO.new)
    chapter.content = content
    ast = ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
    ReVIEW::AST::Indexer.new(chapter).build_indexes(ast)
    chapter.title
  end

  # The gem's own title parser, read from a fresh chapter (no AST involved).
  def book_title(content)
    chapter = ReVIEW::Book::Chapter.new(@book, 1, 'c', 'c.re', StringIO.new)
    chapter.content = content
    chapter.title
  end

  def assert_title(expected, content)
    assert_equal expected, ast_title(content)
    # Parity: the AST value equals the gem's BookUnit#title for Re:VIEW input.
    assert_equal book_title(content), ast_title(content)
  end

  def test_simple_title
    assert_title('Simple Title', "= Simple Title\n\nbody\n")
  end

  def test_tag_is_stripped
    assert_title('No Number', "=[nonum] No Number\n\nbody\n")
  end

  def test_leading_label_is_stripped
    assert_title('Labeled', "={mylabel} Labeled\n\nbody\n")
  end

  # The key parity case: inline markup in the title is kept raw (BookUnit#title
  # never parses it), so the AST must not use the parsed caption text here.
  def test_inline_markup_kept_raw
    assert_title('@<b>{Bold} and @<i>{it}', "= @<b>{Bold} and @<i>{it}\n\nbody\n")
    assert_equal '@<b>{Bold} and @<i>{it}', book_title("= @<b>{Bold} and @<i>{it}\n\nbody\n")
  end

  # Trailing whitespace on the heading line is stripped.
  def test_trailing_whitespace_stripped
    assert_title('Trimmed', "= Trimmed   \n\nbody\n")
  end

  # BookUnit#title takes the first "=+" line regardless of level; so does the
  # AST (first headline node in document order).
  def test_first_headline_any_level
    assert_title('Sub First', "== Sub First\n\nbody\n")
  end

  def test_no_headline_leaves_empty_title
    assert_title('', "just a paragraph, no heading\n")
  end
end
