# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'review/book'

# Builder-vs-renderer parity over every chapter of the in-repo corpora.
#
# The per-format comparison tests each pin a couple of hand-picked chapters;
# this runs all of them, so a divergence in a chapter nobody thought to list
# still fails. Whole chapters are where the divergences of this project have
# actually turned up -- the fragment cases were written after the fact.
#
# Corpora are the ones in this repository, so nothing here depends on a
# document we cannot redistribute.
class TestCorpusBuilderParity < Test::Unit::TestCase
  CORPORA = %w[syntax-book debug-book].freeze

  # md-syntax-book is absent on purpose: its chapters are Markdown, and the
  # legacy builders have no Markdown input to be compared against.
  FORMATS = {
    # IDGXML is compact and InDesign reads it literally, so every byte counts.
    idgxml: [ReVIEW::Test::IdgxmlComparator, ReVIEW::AST::Diff::ByteExact],
    # HTML is held to rendered equivalence (CSS white-space model).
    html: [ReVIEW::Test::HtmlComparator, ReVIEW::AST::Diff::Html],
    # LaTeX equality is decided by typesetting (tools/compare_book.rb compares
    # DVI); this is the coarse text-level sieve that runs without TeX.
    latex: [ReVIEW::Test::LatexComparator, ReVIEW::AST::Diff::Latex]
  }.freeze

  def corpus_dir(name)
    File.expand_path("../../samples/#{name}", __dir__)
  end

  # Every chapter the catalog declares, in every section (PREDEF, CHAPS,
  # APPENDIX, POSTDEF). Parts are not chapters and have no chapter-level
  # builder output to compare.
  def chapter_names(dir)
    # The book has to be built with an absolute path: constructed with '.', it
    # resolves its catalog against the working directory and silently returns
    # only part of the book.
    book = ReVIEW::Book::Base.new(dir, config: ReVIEW::Configure.values)
    book.chapters.map(&:name)
  end

  def assert_corpus_parity(format)
    comparator_class, diff_class = FORMATS.fetch(format)
    checked = 0

    CORPORA.each do |corpus|
      dir = corpus_dir(corpus)
      names = chapter_names(dir)

      assert_not_empty(names, "#{corpus} should declare chapters")

      names.each do |name|
        result = comparator_class.new.convert_chapter_with_book_context(dir, name)
        diff = diff_class.new.compare(result[:builder], result[:renderer])

        assert(diff.equal?, "#{corpus}/#{name} diverges from the builder as #{format}:\n#{diff.pretty_diff}")
        checked += 1
      end
    end

    assert_operator(checked, :>=, 10, 'the sweep should cover every corpus chapter')
  end

  def test_idgxml_parity_over_every_chapter
    assert_corpus_parity(:idgxml)
  end

  def test_html_parity_over_every_chapter
    assert_corpus_parity(:html)
  end

  def test_latex_parity_over_every_chapter
    assert_corpus_parity(:latex)
  end
end
