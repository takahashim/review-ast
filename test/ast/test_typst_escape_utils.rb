# frozen_string_literal: true

require_relative '../test_helper'
require 'review/typst_escape_utils'

class TestTypstEscapeUtils < Test::Unit::TestCase
  include ReVIEW::TypstEscapeUtils

  def test_escapes_markup_characters
    assert_equal '\\#\\$\\*\\_\\`\\[\\]\\<\\>\\@\\~', escape_typst('#$*_`[]<>@~')
  end

  def test_escapes_backslash
    assert_equal '\\\\n', escape_typst('\\n')
  end

  # "//list" and friends appear constantly in Re:VIEW prose about Re:VIEW, and
  # "//" opens a comment in Typst content mode as well as code mode.
  def test_escapes_comment_openers
    assert_equal '\\//list', escape_typst('//list')
    assert_equal 'a/b', escape_typst('a/b')
  end

  # "/*" opens a block comment, but escaping "*" as a markup character already
  # breaks the pair, so no separate rule is needed. Verified against Typst:
  # "/\*" typesets as "/*".
  def test_block_comment_opener_is_broken_by_the_asterisk_escape
    assert_equal '/\\* comment', escape_typst('/* comment')
  end

  # Typst rewrites "--" into an en dash and "..." into an ellipsis.
  def test_breaks_shorthand_ligatures
    assert_equal '\\--option', escape_typst('--option')
    assert_equal 'a\\.\\..', escape_typst('a...')
  end

  # A line-leading marker only counts as one when a space follows, so ordinary
  # numbers and hyphenated text stay unescaped.
  def test_escapes_line_leading_markers_only_when_they_are_markers
    assert_equal '\\- item', escape_typst('- item')
    assert_equal '\\= heading', escape_typst('= heading')
    assert_equal '\\/ term: description', escape_typst('/ term: description')
    assert_equal '1\\. item', escape_typst('1. item')
    assert_equal '1.5', escape_typst('1.5')
    assert_equal '-3', escape_typst('-3')
    assert_equal 'and/or', escape_typst('and/or')
  end

  def test_escapes_line_leading_markers_on_later_lines
    assert_equal "text\n\\+ item", escape_typst("text\n+ item")
  end

  def test_typst_string_quotes_and_escapes
    assert_equal '"a\\"b"', typst_string('a"b')
    assert_equal '"a\\\\b"', typst_string('a\\b')
    assert_equal '"a\\nb"', typst_string("a\nb")
  end

  # A string argument must not be escaped as if it were markup: "#" inside a
  # Typst string literal is an ordinary character.
  def test_typst_string_leaves_markup_characters_alone
    assert_equal '"a#b[c]"', typst_string('a#b[c]')
  end

  def test_typst_label_removes_whitespace
    assert_equal 'a-b', typst_label(' a b ')
  end
end
