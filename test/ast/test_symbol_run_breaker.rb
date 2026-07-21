# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/symbol_run_breaker'
require 'tmpdir'

class SymbolRunBreakerTest < Test::Unit::TestCase
  ZWSP = ReVIEW::AST::SymbolRunBreaker::ZWSP

  def break_source(source)
    ReVIEW::AST::SymbolRunBreaker.new('.').break_source(source)
  end

  def test_breaks_between_ambiguous_symbols
    assert_equal "■#{ZWSP}□#{ZWSP}■", break_source('■□■')
  end

  def test_breaks_mixed_symbol_runs
    assert_equal "★#{ZWSP}→#{ZWSP}※", break_source('★→※')
  end

  def test_leaves_kana_kanji_and_ascii_alone
    %w[漢字かな カタカナ abc… A+B a-b 「かぎ」 句読点、。].each do |text|
      assert_equal text, break_source(text)
    end
  end

  def test_leaves_ambiguous_width_letters_alone
    assert_equal 'αβγ', break_source('αβγ')
    assert_equal 'Мир', break_source('Мир')
  end

  def test_symbol_next_to_kanji_gets_no_zwsp
    assert_equal '見出し■', break_source('見出し■')
    assert_equal '※注記', break_source('※注記')
  end

  def test_skips_code_and_pre_and_head
    source = '<head><title>■□</title></head>' \
             '<pre>■□</pre><code>■□</code><p>■□</p>'
    expected = '<head><title>■□</title></head>' \
               "<pre>■□</pre><code>■□</code><p>■#{ZWSP}□</p>"
    assert_equal expected, break_source(source)
  end

  def test_handles_nested_skip_elements
    source = '<pre><code>■□</code>■□</pre><p>■□</p>'
    assert_equal "<pre><code>■□</code>■□</pre><p>■#{ZWSP}□</p>",
                 break_source(source)
  end

  def test_does_not_touch_markup
    source = '<img src="a.png" alt="fig"/><p class="x">本文</p>'
    assert_equal source, break_source(source)
  end

  def test_annotate_rewrites_only_changed_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.xhtml'), '<p>■□</p>')
      File.write(File.join(dir, 'b.xhtml'), '<p>本文</p>')
      changed = ReVIEW::AST::SymbolRunBreaker.new(dir).annotate
      assert_equal 1, changed
      assert_equal "<p>■#{ZWSP}□</p>", File.read(File.join(dir, 'a.xhtml'))
      assert_equal '<p>本文</p>', File.read(File.join(dir, 'b.xhtml'))
    end
  end
end
