# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Whole-book parity: each sample book is built by a legacy maker
# (review-epubmaker, ...) and by its review-ast counterpart, and every file of
# the two output trees is compared.
#
# The per-chapter comparators check what the renderers write; this checks what
# a user actually gets -- the packaging, the book-level files (the OPF, the
# __REVIEW_BOOK__.tex wrapper), the per-chapter files the makers write, and
# that a maker has the same file set at all.
#
# - EPUB: the unpacked tree the maker leaves with `debug: true`.
# - PDF: there is no TeX in CI, so TeX and dvipdfmx are replaced with `true`;
#   both makers then stop at the same point (no PDF to copy) and leave the
#   .tex tree, which is what is compared.
# - Text (TOP and plain): compared ignoring blank lines and leading tabs --
#   the renderers do not match the builders' blank-line layout and keep list
#   nesting the builders flatten (test_text_renderer_semantics.rb).
# - The web maker is a deliberate redesign (doc/refactor-webmaker.ja.md) and
#   is not compared.
#
# Makers exit, chdir and load the book's review-ext.rb, so each build runs in
# a child process.
class TestMakerParity < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)
  REVIEW_BIN = File.join(Gem::Specification.find_by_name('review').gem_dir, 'bin')
  BOOKS = %w[syntax-book debug-book].freeze

  # Makes pdfmaker run without TeX, and keeps the unpacked EPUB tree.
  CONFIG_APPENDIX = <<~YAML
    debug: true
    texcommand: "true"
    dvicommand: "true"
    dvioptions: ""
    makeindex_command: "true"
  YAML

  # Per-build identifiers that differ between any two runs of the same maker.
  VOLATILE = [
    [%r{<meta property="dcterms:modified">[^<]*</meta>}, '<meta property="dcterms:modified">*</meta>'],
    [/urn:uuid:[0-9a-f{}-]+/, 'urn:uuid:*']
  ].freeze

  def self.workdir
    @workdir ||= Dir.mktmpdir('maker-parity').tap do |dir|
      Test::Unit.at_exit { FileUtils.rm_rf(dir) }
    end
  end

  # Build every book once per side and maker, shared by the tests below.
  def self.build(book, maker, side)
    @builds ||= {}
    @builds[[book, maker, side]] ||= begin
      dir = File.join(workdir, "#{book}-#{maker}-#{side}")
      FileUtils.mkdir_p(dir)
      FileUtils.cp_r(Dir.glob(File.join(ROOT, 'samples', book, '*')), dir)
      FileUtils.rm_f([File.join(dir, 'Gemfile'), File.join(dir, 'Rakefile')])
      # The legacy makers look for stylesheets at the book root only.
      Dir.glob(File.join(dir, 'css', '*.css')).each { |css| FileUtils.cp(css, dir) }
      config = File.join(dir, 'config.yml')
      File.write(config, "#{File.read(config)}\n#{CONFIG_APPENDIX}")

      name, *flags = maker.split
      bin = side == :legacy ? File.join(REVIEW_BIN, "review-#{name}") : File.join(ROOT, 'bin', "review-ast-#{name}")
      env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
      output, = Open3.capture2e(env, RbConfig.ruby, '-rbundler/setup', bin, *flags, 'config.yml', chdir: dir)
      [dir, output]
    end
  end

  def output_tree(book, maker, side, suffix)
    dir, log = self.class.build(book, maker, side)
    tree = Dir.glob(File.join(dir, "*-#{suffix}")).find { |path| File.directory?(path) }
    assert_not_nil(tree, "#{side} #{maker} left no *-#{suffix} directory for #{book}:\n#{log.lines.last(15).join}")
    tree
  end

  def files_in(tree)
    Dir.glob('**/*', base: tree).reject { |rel| File.directory?(File.join(tree, rel)) }.sort
  end

  def normalize(text)
    VOLATILE.reduce(text) { |str, (pattern, replacement)| str.gsub(pattern, replacement) }
  end

  # Text output without blank lines and leading tabs. TOPBuilder and
  # PLAINTEXTBuilder also wrap a @<chapref> in <link href="..."> when
  # chapterlink is on -- markup with no meaning in plain text, which the
  # renderers deliberately do not reproduce (doc/spec-questions.md #8).
  def text_lines(text, legacy:)
    text = text.gsub(%r{<link href="[^"]*">(.*?)</link>}, '\1') if legacy
    text.lines.map { |line| line.sub(/\A\t+/, '') }.reject { |line| line.strip.empty? }.join
  end

  def compare_file(rel, legacy, ast)
    case rel
    when /\.x?html\z/ then ReVIEW::AST::Diff::Html.new.compare(legacy, ast)
    when /\.tex\z/ then ReVIEW::AST::Diff::Latex.new.compare(legacy, ast)
    else ReVIEW::AST::Diff::ByteExact.new.compare(legacy, ast)
    end
  end

  def assert_tree_parity(book, maker, suffix, text: false)
    legacy_tree = output_tree(book, maker, :legacy, suffix)
    ast_tree = output_tree(book, maker, :ast, suffix)
    assert_equal files_in(legacy_tree), files_in(ast_tree), "#{book}: #{maker} writes a different set of files"

    failures = files_in(legacy_tree).filter_map do |rel|
      legacy = File.binread(File.join(legacy_tree, rel))
      ast = File.binread(File.join(ast_tree, rel))
      next if legacy == ast

      legacy = legacy.force_encoding('UTF-8')
      ast = ast.force_encoding('UTF-8')
      next "#{rel}: binary files differ" unless legacy.valid_encoding?

      if text
        expected = text_lines(legacy, legacy: true).lines
        actual = text_lines(ast, legacy: false).lines
        next if expected == actual

        at = expected.zip(actual).index { |a, b| a != b } || [expected.size, actual.size].min
        next "#{rel}: line #{at + 1} differs\n  legacy: #{expected[at].inspect}\n  ast:    #{actual[at].inspect}"
      end
      diff = compare_file(rel, normalize(legacy), normalize(ast))
      "#{rel}:\n#{diff.pretty_diff}" unless diff.equal?
    end
    assert(failures.empty?, "#{book}: #{maker} output diverges from the legacy maker:\n#{failures.join("\n")}")
  end

  BOOKS.each do |book|
    key = book.tr('-', '_')

    define_method("test_epubmaker_#{key}") { assert_tree_parity(book, 'epubmaker', 'epub') }
    define_method("test_idgxmlmaker_#{key}") { assert_tree_parity(book, 'idgxmlmaker', 'idgxml') }
    define_method("test_pdfmaker_#{key}") { assert_tree_parity(book, 'pdfmaker', 'pdf') }
    define_method("test_textmaker_top_#{key}") { assert_tree_parity(book, 'textmaker', 'text', text: true) }
    define_method("test_textmaker_plain_#{key}") { assert_tree_parity(book, 'textmaker -n', 'text', text: true) }
  end
end
