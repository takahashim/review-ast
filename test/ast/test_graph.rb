# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require_relative '../support/review/test/text_comparator'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'tmpdir'

# //graph in every format. Builder#graph runs the generator the block names,
# writes the image under <imagedir>/<builder>/<id>.<image_ext>, and then
# renders the block as that image; the renderers do the same.
#
# The parity test needs dot and gnuplot and is omitted without them; the rest
# only checks what the markup refers to, which does not depend on the tools.
class TestGraph < Test::Unit::TestCase
  SOURCE = <<~RE
    See @<img>{g1} and @<img>{g2}.

    //graph[g1][graphviz][Graph @<b>{one}]{
    digraph { a -> b }
    //}

    //graph[g2][gnuplot][Plot]{
    plot sin(x)
    //}
  RE

  FORMATS = {
    html: [-> { ReVIEW::Test::HtmlComparator.new }, ReVIEW::AST::Diff::Html, 'images/html/g1.png'],
    latex: [-> { ReVIEW::Test::LatexComparator.new }, ReVIEW::AST::Diff::Latex, 'images/latex/g1.pdf'],
    idgxml: [-> { ReVIEW::Test::IdgxmlComparator.new }, ReVIEW::AST::Diff::ByteExact, 'images/idgxml/g1.eps'],
    top: [-> { ReVIEW::Test::TextComparator.new(format: :top) }, nil, 'images/top/g1.png']
  }.freeze

  def in_tmpdir(&block)
    Dir.mktmpdir { |dir| Dir.chdir(dir, &block) }
  end

  def tool?(name)
    ENV['PATH'].split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) }
  end

  def test_graph_renders_as_a_numbered_image_in_every_format
    in_tmpdir do
      FORMATS.each do |format, (comparator, _diff, path)|
        output = comparator.call.convert_with_renderer(SOURCE)
        assert_include(output, path, "#{format} should refer to the generated image")
      end
      plain = ReVIEW::Test::TextComparator.new(format: :plaintext).convert_with_renderer(SOURCE)
      assert_include(plain, '図1.1　Graph one')
      assert_include(plain, 'See 図1.1 and 図1.2.')
    end
  end

  def test_unknown_graph_command_is_an_error
    in_tmpdir do
      source = "//graph[g1][nosuchtool][Cap]{\nx\n//}\n"
      FORMATS.each do |format, (comparator, _diff, _path)|
        error = assert_raise(ReVIEW::CompileError, ReVIEW::ApplicationError) { comparator.call.convert_with_renderer(source) }
        assert_match(/unknown graph command: nosuchtool/, error.message, format.to_s)
      end
    end
  end

  # Through the real commands: review-compile and review-ast-compile on the
  # same one-chapter book. (The comparators' throwaway book is not enough
  # here -- Builder#graph registers the image with the chapter's image
  # finder, which only finds it in a book laid out on disk.)
  def test_parity_with_the_builders
    omit('needs dot and gnuplot') unless tool?('dot') && tool?('gnuplot')

    %w[html latex idgxml plaintext top].each do |target|
      legacy = build_with('review-compile', target)
      ast = build_with('review-ast-compile', target)
      case target
      when 'html', 'latex', 'idgxml'
        diff_class = { 'html' => ReVIEW::AST::Diff::Html, 'latex' => ReVIEW::AST::Diff::Latex,
                       'idgxml' => ReVIEW::AST::Diff::ByteExact }.fetch(target)
        result = diff_class.new.compare(legacy, ast)
        assert(result.equal?, "#{target} diverges from the builder:\n#{result.pretty_diff}")
      else
        # Text formats are compared without blank lines (layout only).
        normalize = ->(text) { text.lines.reject { |line| line.strip.empty? }.join }
        assert_equal normalize.call(legacy), normalize.call(ast), target
      end
    end
  end

  ROOT = File.expand_path('../..', __dir__)

  def build_with(command, target)
    require 'open3'
    require 'rbconfig'
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'ch01.re'), "= C\n\n#{SOURCE}")
      File.write(File.join(dir, 'catalog.yml'), "CHAPS:\n  - ch01.re\n")
      File.write(File.join(dir, 'config.yml'), "review_version: 5.0\nlanguage: ja\nbookname: book\n")
      bin = if command == 'review-compile'
              [Gem.bin_path('review', 'review-compile'), "--target=#{target}"]
            else
              [File.join(ROOT, 'bin', 'review-ast-compile'), '--target', target]
            end
      env = { 'BUNDLE_GEMFILE' => ENV.fetch('BUNDLE_GEMFILE', File.join(ROOT, 'Gemfile')) }
      out, err, status = Open3.capture3(env, RbConfig.ruby, '-rbundler/setup', *bin, 'ch01.re', chdir: dir)
      assert(status.success?, "#{command} --target #{target} failed:\n#{err}")
      ext = { 'html' => 'png', 'latex' => 'pdf', 'idgxml' => 'eps' }.fetch(target, 'png')
      assert_path_exist(File.join(dir, 'images', target, "g1.#{ext}"), "#{command} #{target}: no image generated")
      out.force_encoding('UTF-8')
    end
  end
end
