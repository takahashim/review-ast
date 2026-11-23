# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# A book that defines its own commands in review-ext.rb has to build the same
# through the AST path as through the legacy one.
#
# review-ext.rb reopens builder classes for the rest of the process, so each
# build runs in a child process: review-compile (legacy) and
# review-ast-compile (AST) on the same book, compared per format.
class TestReviewExtCompat < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)

  REVIEW_EXT = <<~'RUBY'
    module ReVIEW
      class Compiler
        defblock :mybox, 0..1
        defsingle :mymark, 1
        definline :mykbd
      end

      class HTMLBuilder
        def mybox(lines, caption = nil)
          puts %Q(<div class="mybox">)
          puts %Q(<p class="caption">#{compile_inline(caption)}</p>) if caption
          lines.each { |line| puts line }
          puts '</div>'
        end

        def mymark(id)
          puts %Q(<a id="#{id}"></a>)
        end

        def inline_mykbd(str)
          %Q(<kbd class="mykbd">#{escape(str)}</kbd>)
        end

        # Redefining a plain inline: the legacy path uses this, so must the AST.
        def inline_u(str)
          %Q(<span class="myu">#{escape(str)}</span>)
        end
      end

      class LATEXBuilder
        def mybox(lines, caption = nil)
          puts "\\begin{mybox}{#{compile_inline(caption.to_s)}}"
          lines.each { |line| puts line }
          puts '\end{mybox}'
        end

        def mymark(id)
          puts "\\label{#{id}}"
        end

        def inline_mykbd(str)
          macro('mykbd', escape(str))
        end
      end

      class IDGXMLBuilder
        def mybox(lines, caption = nil)
          print %Q(<mybox caption="#{escape(caption.to_s)}">)
          print lines.join
          puts '</mybox>'
        end

        def mymark(id)
          print %Q(<mark id="#{id}"/>)
        end

        def inline_mykbd(str)
          %Q(<kbd>#{escape(str)}</kbd>)
        end
      end
    end
  RUBY

  CHAPTER = <<~REVIEW
    = Extensions

    Press @<mykbd>{Ctrl & C} to stop, @<u>{underlined}.

    //mybox[A @<b>{bold} box]{
    first & line with @<mykbd>{K}
    //list is not nested here
    second
    //}

    //mymark[here]

    //mybox{
    //}

    Plain text.
  REVIEW

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, 'review-ext.rb'), REVIEW_EXT)
    File.write(File.join(@dir, 'catalog.yml'), "CHAPS:\n  - ch01.re\n")
    File.write(File.join(@dir, 'config.yml'), "review_version: 5.0\nlanguage: ja\nbookname: book\n")
    File.write(File.join(@dir, 'ch01.re'), CHAPTER)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def run_in_book(*command)
    env = { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile') }
    out, err, status = Open3.capture3(env, RbConfig.ruby, '-rbundler/setup', *command, chdir: @dir)
    [out, err, status]
  end

  def legacy(target)
    out, err, status = run_in_book(Gem.bin_path('review', 'review-compile'), "--target=#{target}", 'ch01.re')
    assert(status.success?, "review-compile --target=#{target} failed:\n#{err}")
    out
  end

  def ast(target)
    out, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-compile'), '--target', target, 'ch01.re')
    assert(status.success?, "review-ast-compile --target #{target} failed:\n#{err}")
    [out, err]
  end

  def assert_same_as_legacy(target, diff_class)
    expected = legacy(target)
    actual, = ast(target)
    diff = diff_class.new.compare(expected, actual)
    assert(diff.equal?, "#{target} diverges from review-compile:\n#{diff.pretty_diff}")
    actual
  end

  def test_html
    out = assert_same_as_legacy('html', ReVIEW::AST::Diff::Html)
    assert_include(out, '<kbd class="mykbd">Ctrl &amp; C</kbd>')
    assert_include(out, '<span class="myu">underlined</span>')
    assert_include(out, '<div class="mybox">')
  end

  def test_latex
    out = assert_same_as_legacy('latex', ReVIEW::AST::Diff::Latex)
    assert_include(out, '\\begin{mybox}{A \\reviewbold{bold} box}')
  end

  def test_idgxml
    assert_same_as_legacy('idgxml', ReVIEW::AST::Diff::ByteExact)
  end

  def test_a_command_the_builder_lacks_is_an_error_in_both_paths
    # plaintext: review-ext.rb gives PLAINTEXTBuilder no #mybox.
    _, err, status = run_in_book(Gem.bin_path('review', 'review-compile'), '--target=plaintext', 'ch01.re')
    assert_false(status.success?)
    assert_match(%r{builder does not support command: //mybox}, err)

    _, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-compile'), '--target', 'plaintext', 'ch01.re')
    assert_false(status.success?)
    assert_match(%r{builder does not support command: //mybox}, err)
  end

  def test_argument_count_is_checked
    File.write(File.join(@dir, 'ch01.re'), "= C\n\n//mymark\n")
    _, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-compile'), '--target', 'html', 'ch01.re')
    assert_false(status.success?)
    assert_match(/mymark/, err)
  end

  def test_redefined_builtin_block_is_reported
    File.write(File.join(@dir, 'review-ext.rb'), REVIEW_EXT.sub("  class HTMLBuilder\n", "  class HTMLBuilder\n    def note(lines, caption = nil); puts 'mine'; end\n"))
    _, err = ast('html')
    assert_match(/review-ext\.rb redefines HTMLBuilder#note, which the AST renderer does not call/, err)
  end

  def test_ast_native_renderer_method_wins
    File.write(File.join(@dir, 'review-ext.rb'), REVIEW_EXT + <<~'RUBY')
      require 'review/renderer/html_renderer'
      class ReVIEW::Renderer::HtmlRenderer
        def visit_block_mybox(node)
          %Q(<aside data-args="#{node.args.size}" data-lines="#{node.lines.size}"></aside>\n)
        end
      end
    RUBY
    out, = ast('html')
    assert_include(out, '<aside data-args="1" data-lines="3"></aside>')
  end

  def test_round_trip_keeps_the_extension_block
    json, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-dump'), 'ch01.re')
    assert(status.success?, err)
    File.write(File.join(@dir, 'ch01.json'), json)
    out, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-dump2re'), 'ch01.json')
    assert(status.success?, err)
    assert_include(out, "//mybox[A @<b>{bold} box]{\nfirst & line with @<mykbd>{K}\n//list is not nested here\nsecond\n//}")
    assert_include(out, '//mymark[here]')
  end
end
