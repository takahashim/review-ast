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

  # review-ast-vol on a one-chapter book written here: [stdout, stderr, status].
  def vol_of(chapter, review_ext: nil)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'config.yml'), "review_version: 5.0\nlanguage: ja\nbookname: book\n")
      File.write(File.join(dir, 'catalog.yml'), "CHAPS:\n  - ch01.re\n")
      File.write(File.join(dir, 'ch01.re'), chapter)
      File.write(File.join(dir, 'review-ext.rb'), review_ext) if review_ext
      env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
      Open3.capture3(env, RbConfig.ruby, '-rbundler/setup', File.join(ROOT, 'bin', 'review-ast-vol'), chdir: dir)
    end
  end

  # The title is rendered by PlaintextRenderer, so an inline op review-ext.rb
  # implements on the renderer alone is rendered in it. Compiled by
  # PLAINTEXTBuilder, as review-vol does it, this title ended in a
  # NoMethodError (the builder is bound without a location to report at).
  def test_vol_title_with_a_renderer_only_inline
    out, err, status = vol_of("= C @<mykbd>{K} title\n\ntext\n", review_ext: <<~'RUBY')
      ReVIEW::Compiler.definline :mykbd
      require 'review/renderer/plaintext_renderer'
      class ReVIEW::Renderer::PlaintextRenderer
        def render_inline_mykbd(_type, content, _node)
          "[kbd #{content}]"
        end
      end
    RUBY
    assert(status.success?, err)
    assert_match(/ch01 \.+ 第1章  C \[kbd K\] title$/, out)
  end

  def test_vol_title_resolves_references
    out, err, status = vol_of("= Title@<fn>{n1} and @<code>{code}\n\ntext\n\n//footnote[n1][note]\n")
    assert(status.success?, err)
    assert_match(/ch01 \.+ 第1章  Title 注1  and code$/, out)
  end

  # A chapter that does not compile is still measured and listed, with a
  # warning and its title as written.
  def test_vol_lists_a_chapter_that_does_not_compile
    out, err, status = vol_of("= Broken @<b>{title}\n\ntext @<nosuchop>{x}\n")
    assert(status.success?, err)
    assert_match(/WARN.*ch01 : no such inline op: nosuchop/, err)
    assert_match(/ch01 \.+ 第1章  Broken @<b>\{title\}$/, out)
    assert_not_match(/NoMethodError/, err)
  end
end
