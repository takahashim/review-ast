# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require_relative '../support/review/test/text_comparator'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'review/ast/diff/text_lines'
require 'review/book'

# Builder-vs-renderer parity over every corpus chapter, under non-default
# configurations.
#
# TestCorpusBuilderParity runs the corpora with each book's own config.yml
# only, so a setting the builder honours and the renderer ignores is invisible
# to it as long as the book leaves the setting at its default. That is exactly
# how `externallink`, `tabwidth` and `caption_position` (table/list in HTML)
# went unnoticed. Each entry below flips settings the builders read, and the
# whole corpus has to stay at parity under it.
#
# Add a configuration here whenever a renderer starts honouring (or is found
# ignoring) a config key.
class TestCorpusConfigParity < Test::Unit::TestCase
  CORPORA = %w[syntax-book debug-book].freeze

  # The text comparators take the format as an argument; these fix it.
  class PlaintextComparator < ReVIEW::Test::TextComparator
    def initialize(config: {})
      super(format: :plaintext, config: config)
    end
  end

  class TopComparator < ReVIEW::Test::TextComparator
    def initialize(config: {})
      super(format: :top, config: config)
    end
  end

  FORMATS = {
    idgxml: [ReVIEW::Test::IdgxmlComparator, ReVIEW::AST::Diff::ByteExact],
    html: [ReVIEW::Test::HtmlComparator, ReVIEW::AST::Diff::Html],
    latex: [ReVIEW::Test::LatexComparator, ReVIEW::AST::Diff::Latex],
    plaintext: [PlaintextComparator, ReVIEW::AST::Diff::TextLines],
    top: [TopComparator, ReVIEW::AST::Diff::TextLines]
  }.freeze

  CAPTIONS_BOTTOM = { 'caption_position' => { 'image' => 'bottom', 'table' => 'bottom', 'list' => 'bottom', 'equation' => 'bottom' } }.freeze

  # name => [config, formats it applies to]
  CONFIGS = {
    captions_bottom: [CAPTIONS_BOTTOM, %i[idgxml html latex plaintext top]],
    no_externallink: [{ 'externallink' => false }, %i[html]],
    tabwidth4: [{ 'tabwidth' => 4 }, %i[idgxml html latex plaintext top]],
    secnolevel1: [{ 'secnolevel' => 1 }, %i[idgxml html latex plaintext top]],
    secnolevel4: [{ 'secnolevel' => 4 }, %i[idgxml html latex plaintext top]],
    no_chapterlink: [{ 'chapterlink' => false }, %i[html latex plaintext top]],
    draft: [{ 'draft' => true }, %i[idgxml html latex plaintext top]],
    footnotetext: [{ 'footnotetext' => true }, %i[latex]],
    join_lines_by_lang: [{ 'join_lines_by_lang' => true }, %i[idgxml html latex plaintext top]],
    th_bold: [{ 'textmaker' => { 'th_bold' => true } }, %i[top]],
    structured_idgxml: [{ 'structuredxml' => true, 'listinfo' => true }, %i[idgxml]],
    epub2: [{ 'epubversion' => 2, 'htmlversion' => 4 }, %i[html]],
    # Re:VIEW 2 compatibility mode (Configure#check_version('2')): older
    # macros in LaTeX, among others.
    review_version2: [{ 'review_version' => 2.0 }, %i[latex]]
  }.freeze

  def corpus_dir(name)
    File.expand_path("../../samples/#{name}", __dir__)
  end

  def chapter_names(dir)
    ReVIEW::Book::Base.new(dir, config: ReVIEW::Configure.values).chapters.map(&:name)
  end

  def assert_config_parity(format, config_name)
    config, formats = CONFIGS.fetch(config_name)
    omit("#{config_name} does not apply to #{format}") unless formats.include?(format)

    comparator_class, diff_class = FORMATS.fetch(format)
    failures = []
    CORPORA.each do |corpus|
      dir = corpus_dir(corpus)
      chapter_names(dir).each do |name|
        failure = chapter_divergence(comparator_class, diff_class, config, dir, name)
        failures << "#{corpus}/#{name}:\n#{failure}" if failure
      end
    end

    assert(failures.empty?, "#{format} under #{config_name} (#{config.inspect}) diverges from the builder:\n#{failures.join("\n")}")
  end

  # nil when the chapter is at parity. A configuration can make the builder
  # reject a chapter (secnolevel: 1 leaves the @<sec> targets unnumbered); the
  # renderer then has to reject it too rather than print something.
  def chapter_divergence(comparator_class, diff_class, config, dir, name)
    # A fresh deep copy each time: the comparators and builders mutate the
    # config hash they are handed.
    comparator = comparator_class.new(config: Marshal.load(Marshal.dump(config)))
    builder_error = nil
    begin
      result = comparator.convert_chapter_with_book_context(dir, name)
    rescue ReVIEW::ApplicationError => e
      builder_error = e
    end
    return renderer_accepts(comparator, dir, name, builder_error) if builder_error

    diff = diff_class.new.compare(result[:builder], result[:renderer])
    diff.equal? ? nil : diff.pretty_diff
  end

  def renderer_accepts(comparator, dir, name, builder_error)
    book = comparator.send(:load_book, dir)
    chapter = book.chapters.find { |ch| ch.name == name }
    comparator.convert_with_renderer(nil, chapter: chapter)
    "the builder rejects it (#{builder_error.message}) but the renderer renders it"
  rescue ReVIEW::ApplicationError, ReVIEW::CompileError
    nil
  end

  FORMATS.each_key do |format|
    CONFIGS.each_key do |config_name|
      define_method("test_#{format}_#{config_name}") do
        assert_config_parity(format, config_name)
      end
    end
  end
end
