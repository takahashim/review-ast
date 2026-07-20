# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/stylesheet_resolver'
require 'tmpdir'

class StylesheetResolverTest < Test::Unit::TestCase
  class Host
    include ReVIEW::AST::StylesheetResolver

    attr_reader :copied

    def initialize(config)
      @config = config
      @copied = []
    end

    def error!(msg)
      raise msg
    end
  end

  def with_book_dir
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def test_resolves_from_book_root
    with_book_dir do
      File.write('style.css', 'a')
      host = Host.new('stylesheet' => ['style.css'])
      assert_equal 'style.css', host.resolve_stylesheet('style.css')
    end
  end

  def test_resolves_from_css_dir
    with_book_dir do
      Dir.mkdir('css')
      File.write('css/style.css', 'a')
      host = Host.new('stylesheet' => ['style.css'])
      assert_equal 'css/style.css', host.resolve_stylesheet('style.css')
    end
  end

  def test_book_root_wins_over_css_dir
    with_book_dir do
      Dir.mkdir('css')
      File.write('style.css', 'root')
      File.write('css/style.css', 'css')
      host = Host.new('stylesheet' => ['style.css'])
      assert_equal 'style.css', host.resolve_stylesheet('style.css')
    end
  end

  def test_resolves_from_bundled_templates
    with_book_dir do
      host = Host.new('stylesheet' => ['style-vivliostyle.css'])
      resolved = host.resolve_stylesheet('style-vivliostyle.css')
      assert_equal File.join(ReVIEW::AST::StylesheetResolver::BUNDLED_CSS_DIR,
                             'style-vivliostyle.css'),
                   resolved
      assert File.exist?(resolved)
    end
  end

  def test_rejects_names_with_directory_component
    with_book_dir do
      host = Host.new('stylesheet' => [])
      assert_raise(RuntimeError) { host.resolve_stylesheet('css/style.css') }
    end
  end

  def test_copy_places_files_flat_and_yields_names
    with_book_dir do
      Dir.mkdir('css')
      Dir.mkdir('out')
      File.write('css/mine.css', 'mine')
      host = Host.new('stylesheet' => ['mine.css', 'style-vivliostyle.css'])
      yielded = []
      host.copy_resolved_stylesheets('out') { |name| yielded << name }
      assert_equal %w[mine.css style-vivliostyle.css], yielded
      assert_equal 'mine', File.read('out/mine.css')
      assert File.exist?('out/style-vivliostyle.css')
    end
  end

  def test_copy_reports_missing_stylesheet
    with_book_dir do
      Dir.mkdir('out')
      host = Host.new('stylesheet' => ['nope.css'])
      error = assert_raise(RuntimeError) { host.copy_resolved_stylesheets('out') }
      assert_match(/nope\.css is not found/, error.message)
    end
  end
end
