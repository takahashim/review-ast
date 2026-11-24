# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/command/compile'
require 'tmpdir'

# review-ast-compile is the AST counterpart of review-compile: same options,
# same file / directory modes, every AST renderer as a target.
class TestCompileCommand < Test::Unit::TestCase
  SYNTAX_BOOK = File.expand_path('../../samples/syntax-book', __dir__)

  def run_compile(*args)
    out = StringIO.new
    $stdout = out
    status = ReVIEW::AST::Command::Compile.new.run(args.flatten)
    [status, out.string]
  ensure
    $stdout = STDOUT
  end

  def with_quiet_logger
    original = ReVIEW.logger
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    yield
  ensure
    ReVIEW.logger = original
  end

  def test_every_renderer_is_a_target
    with_quiet_logger do
      ReVIEW::AST::Command::Compile::RENDERERS.each_key do |target|
        status, out = run_compile('--target', target, File.join(SYNTAX_BOOK, 'ch01.re'))
        assert_equal 0, status, "--target #{target} failed"
        assert_false(out.empty?, "--target #{target} printed nothing")
      end
    end
  end

  def test_unsupported_target_is_a_compile_error
    with_quiet_logger do
      # markdown used to be advertised and then failed with LoadError.
      status, = run_compile('--target', 'markdown', File.join(SYNTAX_BOOK, 'ch01.re'))
      assert_equal ReVIEW::AST::Command::Compile::EXIT_COMPILE_ERROR, status
    end
  end

  def test_chapter_in_the_catalog_resolves_cross_chapter_references
    with_quiet_logger do
      # ch02 refers to ch01 via @<chap>; a stand-alone chapter could not
      # resolve it, so this only passes if the catalog's chapter is used.
      status, out = run_compile('--target', 'plaintext', File.join(SYNTAX_BOOK, 'ch02.re'))
      assert_equal 0, status
      assert_include(out, '章番号：第1章、付録A')
    end
  end

  def test_level_option_overrides_secnolevel
    with_quiet_logger do
      _, numbered = run_compile('--target', 'plaintext', File.join(SYNTAX_BOOK, 'ch01.re'))
      _, unnumbered = run_compile('--target', 'plaintext', '--level', '1', File.join(SYNTAX_BOOK, 'ch01.re'))
      assert_match(/^1\.1　/, numbered)
      assert_no_match(/^1\.1　/, unnumbered)
    end
  end

  def test_check_defaults_to_html_and_prints_nothing
    with_quiet_logger do
      status, out = run_compile('--check', File.join(SYNTAX_BOOK, 'ch01.re'))
      assert_equal 0, status
      assert_equal '', out
    end
  end

  def test_directory_mode_writes_every_chapter_and_part
    with_quiet_logger do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          status, = run_compile('--target', 'idgxml', '--directory', SYNTAX_BOOK)
          assert_equal 0, status
          assert_equal %w[appA.xml bib.xml ch01.xml ch02.xml ch03.xml part2.xml pre01.xml], Dir.glob('*.xml').sort
        end
      end
    end
  end

  def test_output_file
    with_quiet_logger do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'out.tex')
        status, out = run_compile('--target', 'latex', '-o', path, File.join(SYNTAX_BOOK, 'ch01.re'))
        assert_equal 0, status
        assert_equal '', out
        assert_include(File.read(path), '\\chapter')
      end
    end
  end

  def test_file_outside_the_catalog_is_compiled_stand_alone
    with_quiet_logger do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'ch03.re')
        File.write(path, "= Loose\n\ntext\n")
        status, out = run_compile('--target', 'plaintext', path)
        assert_equal 0, status
        assert_include(out, '第3章　Loose')
      end
    end
  end
end
