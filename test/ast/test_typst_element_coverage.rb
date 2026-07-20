# frozen_string_literal: true

require_relative '../test_helper'
require 'review'
require 'review/ast'
require 'review/ast/block_processor'
require 'review/ast/inline_processor'
require 'review/renderer/typst_renderer'
require 'yaml'

# schema/review-elements.yml must describe every Re:VIEW element, and describe it
# truthfully.
#
# The renderer refuses unknown nodes and inlines, so nothing is lost silently at
# run time (doc/design-typst.md). What that does not tell
# anyone is which elements are deliberately not drawn: an element whose method
# returns "" is indistinguishable from one nobody thought about. The table is
# where that difference is written down, and this test is what keeps the table
# from drifting away from the code.
class TestTypstElementCoverage < Test::Unit::TestCase
  TABLE = YAML.load_file(File.expand_path('../../schema/review-elements.yml', __dir__)).freeze
  RENDERER = ReVIEW::Renderer::TypstRenderer
  HANDLER = ReVIEW::Renderer::Typst::InlineElementHandler

  def setup
    @blocks = TABLE.fetch('blocks')
    @inlines = TABLE.fetch('inlines')
  end

  # ------------------------------------------------------------------ blocks

  def test_table_lists_exactly_the_compiler_block_commands
    known = ReVIEW::AST::BlockProcessor::BLOCK_COMMAND_TABLE.keys.map(&:to_s).sort

    assert_equal(known, @blocks.keys.sort,
                 'schema/review-elements.yml is out of step with BLOCK_COMMAND_TABLE')
  end

  def test_every_block_the_table_calls_rendered_has_a_renderer_method
    @blocks.each do |name, entry|
      next if entry['status'] == 'lowered'

      method = entry['renderer']
      assert_not_nil(method, "//#{name} has no renderer recorded")
      assert(renderer_defines?(method), "//#{name} claims #{method}, which does not exist")
    end
  end

  # A directive is removed before rendering, so it must NOT have a method: one
  # would be dead code, which is how visit_block_endnote survived until this
  # table was written.
  def test_lowered_blocks_have_no_renderer_method
    @blocks.each do |name, entry|
      next unless entry['status'] == 'lowered'

      assert_nil(entry['renderer'], "//#{name} is lowered but records a renderer")
      assert(!renderer_defines?("visit_block_#{name}"),
             "//#{name} is lowered but visit_block_#{name} exists and is unreachable")
    end
  end

  # ----------------------------------------------------------------- inlines

  def test_table_lists_exactly_the_implemented_inlines
    implemented = methods_of(HANDLER, /\Arender_inline_/).map { |m| m.sub('render_inline_', '') }.sort

    assert_equal(implemented, @inlines.keys.sort,
                 'schema/review-elements.yml is out of step with the inline handler')
  end

  # Every inline the compiler routes through a dedicated handler has to be
  # renderable; the rest arrive as decoration inlines and are covered by the
  # comparison above.
  def test_compiler_inline_handlers_are_all_covered
    known = ReVIEW::AST::InlineProcessor::DEFAULT_INLINE_HANDLERS.keys.map(&:to_s)
    missing = known - @inlines.keys

    assert_empty(missing, "inline commands with no Typst rendering: #{missing.join(', ')}")
  end

  def test_every_inline_the_table_calls_rendered_has_a_handler_method
    @inlines.each do |name, entry|
      assert(handler_defines?(entry['renderer']),
             "@<#{name}> claims #{entry['renderer']}, which does not exist")
    end
  end

  # -------------------------------------------------------------- statuses

  def test_statuses_are_from_the_documented_set
    @blocks.merge(@inlines).each do |name, entry|
      assert_include(%w[render ignore lowered], entry['status'], "#{name} has an unknown status")
    end
  end

  # An element that produces nothing needs a stated reason. Without one the
  # table would record the omission but not justify it, which is the thing the
  # design manual  rules out.
  def test_ignored_elements_state_a_reason
    @blocks.merge(@inlines).each do |name, entry|
      next unless entry['status'] == 'ignore'

      assert_not_nil(entry['reason'], "#{name} is ignored without a reason")
      assert(!entry['reason'].to_s.strip.empty?, "#{name} has an empty reason")
    end
  end

  # And it has to actually produce nothing, or the table is lying about it.
  def test_ignored_blocks_really_render_nothing
    renderer = build_renderer

    @blocks.each do |name, entry|
      next unless entry['status'] == 'ignore'

      node = ReVIEW::AST::BlockNode.new(
        location: ReVIEW::AST::SourceLocation.new('ch.re', 1),
        block_type: name.to_sym
      )
      assert_equal('', renderer.visit(node), "//#{name} is recorded as ignored but emits output")
    end
  end

  def test_ignored_inlines_really_render_nothing
    renderer = build_renderer

    @inlines.each do |name, entry|
      next unless entry['status'] == 'ignore'

      node = ReVIEW::AST::InlineNode.new(
        location: ReVIEW::AST::SourceLocation.new('ch.re', 1),
        inline_type: name
      )
      assert_equal('', renderer.render_inline_element(name, 'content', node),
                   "@<#{name}> is recorded as ignored but emits output")
    end
  end

  private

  def build_renderer
    config = ReVIEW::Configure.values
    ReVIEW::I18n.setup(config['language'])
    book = ReVIEW::Book::Base.new(config: config)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'ch', 'ch.re', StringIO.new(''))
    RENDERER.new(chapter)
  end

  def methods_of(klass, pattern)
    (klass.instance_methods + klass.private_instance_methods).grep(pattern).map(&:to_s)
  end

  def renderer_defines?(method)
    methods_of(RENDERER, /\A#{Regexp.escape(method)}\z/).any?
  end

  def handler_defines?(method)
    methods_of(HANDLER, /\A#{Regexp.escape(method)}\z/).any?
  end
end
