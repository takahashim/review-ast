# frozen_string_literal: true

require_relative '../test_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# review-ast-index / review-ast-vol: review-index / review-vol with chapters
# read by the AST. On a Re:VIEW-format book they must print exactly what the
# legacy tools print; on a Markdown book -- which the legacy tools list
# untitled, with its appendix as "第1章" and its part file by file name --
# they must print the real titles and numbers.
class TestIndexVolCommands < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)
  REVIEW_BIN = File.join(Gem::Specification.find_by_name('review').gem_dir, 'bin')

  def run_tool(bin, book, *args)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(ROOT, 'samples', book, '*')), dir)
      FileUtils.rm_f([File.join(dir, 'Gemfile'), File.join(dir, 'Rakefile')])
      env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
      out, err, status = Open3.capture3(env, RbConfig.ruby, '-rbundler/setup', bin, *args, chdir: dir)
      assert(status.success?, "#{File.basename(bin)} #{args.join(' ')} failed on #{book}:\n#{err}")
      out
    end
  end

  def legacy(tool, book, *args)
    run_tool(File.join(REVIEW_BIN, "review-#{tool}"), book, *args)
  end

  def ast(tool, book, *args)
    run_tool(File.join(ROOT, 'bin', "review-ast-#{tool}"), book, *args)
  end

  def test_index_matches_review_index
    [[], ['-l', '2'], ['--noindent']].each do |args|
      assert_equal legacy('index', 'syntax-book', *args), ast('index', 'syntax-book', *args), "review-index #{args.join(' ')}"
    end
  end

  def test_vol_matches_review_vol
    assert_equal legacy('vol', 'syntax-book'), ast('vol', 'syntax-book')
  end

  def test_index_of_a_markdown_book
    out = ast('index', 'md-syntax-book', '-l', '2')
    assert_include(out, "第1章　章見出し\n  1.1　節見出し\n")
    assert_include(out, '第II部　部見出し')
    assert_include(out, "付録A　付録の見出し\n  A.1　付録の節\n")
  end

  def test_vol_of_a_markdown_book
    out = ast('vol', 'md-syntax-book')
    assert_match(/ch01 \.+ 第1章  章見出し$/, out)
    assert_match(/part2\.md \.+ 第II部  部見出し/, out)
    assert_match(/appA \.+ 付録A  付録の見出し$/, out)
  end
end
