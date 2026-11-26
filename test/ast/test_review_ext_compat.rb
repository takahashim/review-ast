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
    # The children run under the same bundle as this test process.
    env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
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
    # plaintext: review-ext.rb gives PLAINTEXTBuilder no #inline_mykbd and no
    # #mybox. The legacy compiler reports every error of the chapter, the AST
    # path stops at the first (the inline, on line 3).
    _, err, status = run_in_book(Gem.bin_path('review', 'review-compile'), '--target=plaintext', 'ch01.re')
    assert_false(status.success?)
    assert_match(/builder does not support inline op: @<mykbd>/, err)
    assert_match(%r{builder does not support command: //mybox}, err)

    _, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-compile'), '--target', 'plaintext', 'ch01.re')
    assert_false(status.success?)
    assert_match(/builder does not support inline op: @<mykbd>/, err)

    File.write(File.join(@dir, 'ch01.re'), "= C\n\n//mybox{\nx\n//}\n")
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

  def test_redefined_structural_hook_is_reported
    File.write(File.join(@dir, 'review-ext.rb'), REVIEW_EXT.sub("  class HTMLBuilder\n", "  class HTMLBuilder\n    def headline(level, label, caption); puts 'mine'; end\n"))
    _, err = ast('html')
    assert_match(/review-ext\.rb redefines HTMLBuilder#headline, which the AST renderer does not call/, err)
  end

  # A builder helper (here HTMLBuilder#table_begin, as a real book redefines
  # it to add a CSS class) is as unroutable as a structural hook; it was
  # ignored without a word. A helper Re:VIEW does not define is the book's own
  # and is not reported.
  def test_redefined_builder_helper_is_reported
    ext = REVIEW_EXT.sub("  class HTMLBuilder\n", "  class HTMLBuilder\n    def table_begin(_ncols); puts '<table class=\"x\">'; end\n    " \
                                                  "def my_own_helper; end\n")
    File.write(File.join(@dir, 'review-ext.rb'), ext)
    _, err = ast('html')
    assert_match(/review-ext\.rb redefines HTMLBuilder#table_begin, which the AST renderer does not call/, err)
    assert_not_match(/my_own_helper/, err)
    assert_not_match(/HTMLBuilder#(mybox|mymark|inline_mykbd|inline_u)\b/, err)
  end

  # Redefinitions of built-in commands: a block (emlist, list, table), a
  # minicolumn's ends (note_begin / note_end) and special inlines (ruby,
  # href, a reference). The legacy path uses them, so the AST path must too --
  # while still numbering the blocks itself (@<list> keeps resolving).
  BUILTIN_OVERRIDES = <<~'RUBY'
    module ReVIEW
      class HTMLBuilder
        def emlist(lines, caption = nil, _lang = nil)
          puts %Q(<pre class="myemlist" title="#{escape(caption.to_s)}">#{lines.join("\n")}</pre>)
        end

        def list(lines, id, caption, _lang = nil)
          puts %Q(<div class="mylist" id="#{id}">#{@chapter.list(id).number}: #{compile_inline(caption)}</div>)
          lines.each { |line| puts line }
        end

        # As the builder's own note_begin/note_end do, mark the minicolumn
        # open (the legacy compiler reads it to close the block).
        def note_begin(caption = nil)
          @doc_status[:minicolumn] = 'note'
          puts %Q(<aside class="mynote"><h5>#{compile_inline(caption.to_s)}</h5>)
        end

        def note_end
          puts '</aside>'
          @doc_status[:minicolumn] = nil
        end

        def inline_ruby(str)
          base, ruby = str.split(',', 2)
          %Q(<span class="myruby" data-ruby="#{escape(ruby.to_s.strip)}">#{escape(base)}</span>)
        end

        def inline_href(str)
          %Q(<span class="myhref">#{escape(str)}</span>)
        end

        def inline_list(id)
          %Q(<span class="mylistref">#{id}</span>)
        end
      end

      class LATEXBuilder
        def emlist(lines, caption = nil, _lang = nil)
          puts "\\begin{myemlist}{#{compile_inline(caption.to_s)}}"
          lines.each { |line| puts line }
          puts '\end{myemlist}'
        end

        def table(lines, id = nil, caption = nil)
          puts "\\mytable{#{id}}{#{lines.size}}"
        end

        def inline_ruby(str)
          macro('myruby', escape(str))
        end
      end
    end
  RUBY

  BUILTIN_CHAPTER = <<~REVIEW
    = Overrides

    See @<list>{l1}; @<ruby>{漢字, かんじ} and @<href>{http://example.com, Example}.

    Later@<fn>{f1}.

    //emlist[Code & caption]{
    a < b @<b>{bold}@<fn>{f2}
    //}

    //footnote[f2][Defined first, referred to from inside the redefined block]
    //footnote[f1][Defined second]

    //list[l1][The @<b>{list}]{
    puts 1
    //}

    //note[Note @<i>{title}]{
    A note with @<b>{markup}.

    //emlist{
    nested
    //}
    //}

    //table[t1][Table]{
    A	B
    ------------
    C	D
    //}
  REVIEW

  def test_redefined_builtin_commands_are_used_as_in_the_legacy_path
    File.write(File.join(@dir, 'review-ext.rb'), BUILTIN_OVERRIDES)
    File.write(File.join(@dir, 'ch01.re'), BUILTIN_CHAPTER)

    html = assert_same_as_legacy('html', ReVIEW::AST::Diff::Html)
    assert_include(html, '<pre class="myemlist" title="Code &amp; caption">')
    assert_include(html, '<div class="mylist" id="l1">1: The <b>list</b></div>')
    assert_include(html, '<aside class="mynote"><h5>Note <i>title</i></h5>')
    assert_include(html, '<span class="myruby" data-ruby="かんじ">漢字</span>')
    assert_include(html, '<span class="mylistref">l1</span>')

    latex = assert_same_as_legacy('latex', ReVIEW::AST::Diff::Latex)
    assert_include(latex, '\\begin{myemlist}{Code \\& caption}')
    assert_include(latex, '\\footnote{Defined first, referred to from inside')
    assert_include(latex, '\\mytable{t1}{3}')
    assert_include(latex, '\\myruby{漢字, かんじ}')
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

  # A review-ext.rb `render_inline_<name>` on a renderer renders the inline in
  # every format: on its own (plaintext, TOP and Typst, whose builders
  # review-ext.rb leaves without #inline_mykbd -- Typst has no builder at all)
  # and over a builder method (HTML, LaTeX, IDGXML). It used to be an error in
  # all six, or, in TOP, to drop the command silently.
  RENDERER_INLINE = <<~'RUBY'
    %w[html latex idgxml plaintext top typst].each { |f| require "review/renderer/#{f}_renderer" }
    [ReVIEW::Renderer::HtmlRenderer, ReVIEW::Renderer::LatexRenderer, ReVIEW::Renderer::IdgxmlRenderer,
     ReVIEW::Renderer::PlaintextRenderer, ReVIEW::Renderer::TopRenderer, ReVIEW::Renderer::TypstRenderer].each do |klass|
      klass.class_eval do
        def render_inline_mykbd(_type, content, node)
          "[kbd #{content}|#{node.args.first}]"
        end
      end
    end
  RUBY

  def test_renderer_inline_method_works_in_every_format
    File.write(File.join(@dir, 'review-ext.rb'), REVIEW_EXT + RENDERER_INLINE)
    File.write(File.join(@dir, 'ch01.re'), "= C\n\nPress @<mykbd>{K} now.\n")
    %w[html latex idgxml plaintext top typst].each do |target|
      out, = ast(target)
      assert_include(out, '[kbd K|K]', target)
    end
  end

  # Inside a block a builder method renders, the builder compiles the inlines
  # (doc/review-ext.md), so a renderer's `render_inline_<name>` does not apply
  # there and the op is an error without a builder method. The error says so,
  # and carries its location once: ReVIEW::Compiler#compile_inline and #text
  # each report it again on the way out.
  def test_error_inside_a_builder_rendered_block_is_located_once
    File.write(File.join(@dir, 'review-ext.rb'), REVIEW_EXT + <<~'RUBY')
      ReVIEW::Compiler.definline :mykey
      require 'review/renderer/html_renderer'
      class ReVIEW::Renderer::HtmlRenderer
        def render_inline_mykey(_type, content, _node)
          "[key #{content}]"
        end
      end
    RUBY
    File.write(File.join(@dir, 'ch01.re'), "= C\n\nPress @<mykey>{K}.\n")
    out, = ast('html')
    assert_include(out, '[key K]')

    File.write(File.join(@dir, 'ch01.re'), "= C\n\n//mybox{\nPress @<mykey>{K}.\n//}\n")
    _, err, status = run_in_book('-I', File.join(ROOT, 'lib'), File.join(ROOT, 'bin/review-ast-compile'), '--target', 'html', 'ch01.re')
    assert_false(status.success?)
    assert_include(err, 'ch01.re:3: builder does not support inline op: @<mykey> ' \
                        '(inside //mybox, which HTMLBuilder renders; define HTMLBuilder#inline_mykey in review-ext.rb)')
    assert_not_match(/ch01\.re:\d+: ch01\.re:\d+:/, err)
    assert_equal(1, err.scan('define HTMLBuilder#inline_mykey').size)
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
