# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require_relative '../support/review/test/text_comparator'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'review/ast/compiler'
require 'review/ast/review_generator'
require 'tmpdir'

# Builder parity for behaviours the corpora do not exercise: settings and
# argument forms that a real book uses but syntax-book/debug-book do not.
# Each case is compared against the legacy builder of every format it applies
# to, so the expectation is the builder's own output, not a hand-written one.
class TestBuilderCompatFragments < Test::Unit::TestCase
  FORMATS = {
    html: ->(config) { [ReVIEW::Test::HtmlComparator.new(config: config), ReVIEW::AST::Diff::Html.new] },
    idgxml: ->(config) { [ReVIEW::Test::IdgxmlComparator.new(config: config), ReVIEW::AST::Diff::ByteExact.new] },
    latex: ->(config) { [ReVIEW::Test::LatexComparator.new(config: config), ReVIEW::AST::Diff::Latex.new] }
  }.freeze

  def assert_parity(source, formats: FORMATS.keys, config: {})
    formats.each do |format|
      comparator, diff = FORMATS.fetch(format).call(Marshal.load(Marshal.dump(config)))
      builder = comparator.convert_with_builder(source)
      renderer = comparator.convert_with_renderer(source)
      result = diff.compare(builder, renderer)
      assert(result.equal?, "#{format} diverges for #{source.inspect} #{config.inspect}:\n#{result.pretty_diff}")
    end
  end

  def assert_text_parity(source, config: {})
    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format, config: config)
      assert_equal comparator.convert_with_builder(source), comparator.convert_with_renderer(source),
                   "#{format} diverges for #{source.inspect} #{config.inspect}"
    end
  end

  # -- @<href> / @<ruby>: Builder splits on unescaped commas, `\,` is a comma

  def test_href_label_with_escaped_comma
    assert_parity("@<href>{http://example.com/?a=1&b, X\\, Y}\n")
    assert_parity("@<href>{http://example.com/?a=1&b, X\\, Y}\n", formats: [:html], config: { 'externallink' => false })
  end

  def test_href_extra_fields_are_dropped_like_the_builder
    assert_parity("@<href>{http://example.com, A, B}\n")
  end

  def test_ruby_with_escaped_comma
    assert_parity("@<ruby>{漢字, かん\\,じ}\n")
    assert_parity("@<ruby>{a\\,b, c, d}\n")
  end

  def test_href_and_ruby_commas_survive_a_round_trip
    source = "= C\n\n@<href>{http://example.com/a\\,b, X\\, Y} @<ruby>{a\\,b, c\\,d}\n"
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(source))
    ast = ReVIEW::AST::Compiler.new.compile_to_ast(chapter)
    regenerated = ReVIEW::AST::ReVIEWGenerator.new.generate(ast)
    assert_include(regenerated, '@<href>{http://example.com/a\\,b, X\\, Y}')
    assert_include(regenerated, '@<ruby>{a\\,b, c\\,d}')
  end

  # -- externallink: false prints the URL instead of linking it

  def test_externallink_off
    ["@<href>{http://example.com, Example}\n", "@<href>{http://example.com}\n", "@<href>{#anchor, Here}\n"].each do |source|
      assert_parity(source, formats: [:html], config: { 'externallink' => false })
    end
  end

  # -- tabwidth applies to every code block, numbered ones counting the prefix

  def test_tabwidth
    %W[//emlist{\n\tA\tB\n//}\n //emlistnum{\na\tb\n\tc\n//}\n //listnum[l][cap]{\na\tb\n//}\n].each do |source|
      assert_parity(source, config: { 'tabwidth' => 4 })
    end
  end

  # -- caption_position: bottom

  CAPTIONS_BOTTOM = { 'caption_position' => { 'image' => 'bottom', 'table' => 'bottom', 'list' => 'bottom', 'equation' => 'bottom' } }.freeze

  def test_captions_bottom
    ["//table[t][cap]{\nA\tB\n------------\nC\tD\n//}\n", "//emtable[cap]{\nA\n//}\n",
     "//list[l][cap]{\nputs 1\n//}\n", "//listnum[l][cap]{\nputs 1\n//}\n"].each do |source|
      assert_parity(source, config: CAPTIONS_BOTTOM)
    end
  end

  def test_text_table_caption_follows_caption_position
    plaintext = ReVIEW::Test::TextComparator.new(format: :plaintext, config: CAPTIONS_BOTTOM).
                convert_with_renderer("//table[t][cap]{\nA\tB\n//}\n")
    assert_operator(plaintext.index("A\tB"), :<, plaintext.index('cap'))
    top = ReVIEW::Test::TextComparator.new(format: :top, config: CAPTIONS_BOTTOM).
          convert_with_renderer("//table[t][cap]{\nA\tB\n//}\n")
    assert_operator(top.index("A\tB"), :<, top.index('cap'))
  end

  # -- @<tcy> in IDGXML (inherited Builder#inline_tcy)

  def test_tcy
    assert_parity("縦@<tcy>{12}横\n")
  end

  # -- @<w>/@<wb>: words_file, and a missing word degrades instead of failing

  def test_words_file_and_missing_words
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'words.csv'), "rails,Ruby on Rails\napi,A & <P>\n")
      # Builder#load_words opens the path relative to the working directory.
      Dir.chdir(dir) do
        source = "A @<w>{rails} B @<wb>{api} C @<w>{nope} D @<wb>{nope2}\n"
        config = { 'words_file' => 'words.csv' }
        assert_parity(source, config: config)
        assert_text_parity(source, config: config)
      end
    end
  end

  # -- htmlversion 4 (EPUB2): <tt> instead of <code class="tt">

  def test_html4_monospace
    assert_parity("@<tt>{a} @<ttb>{b} @<tti>{c} @<code>{d}\n", formats: [:html], config: { 'htmlversion' => 4, 'epubversion' => 2 })
  end
end
