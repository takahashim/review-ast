# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require_relative '../support/review/test/text_comparator'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'review/ast/diff/text_lines'

# Every command Re:VIEW declares, in every format.
#
# test_command_parity_coverage.rb walks the AST's own command tables, in the
# three markup formats. This walks Re:VIEW's: ReVIEW::Compiler::SYNTAX and
# ::INLINE, which also hold the commands the builders declare themselves
# (//planning, //shoot, ... in htmlbuilder.rb), in all five formats. Each
# command is written once with simple arguments (both ends of its argument
# range, with a body when it takes one) and the two paths must agree: the
# same output, or both an error -- a command one path rejects and the other
# prints is a divergence too.
#
# What is left over is KNOWN_DIFFERENCES, each with its reason. An entry must
# keep diverging, so the list cannot go stale.
class TestReviewCommandSweep < Test::Unit::TestCase
  FORMATS = {
    html: [->(config) { ReVIEW::Test::HtmlComparator.new(config: config) }, ReVIEW::AST::Diff::Html],
    latex: [->(config) { ReVIEW::Test::LatexComparator.new(config: config) }, ReVIEW::AST::Diff::Latex],
    idgxml: [->(config) { ReVIEW::Test::IdgxmlComparator.new(config: config) }, ReVIEW::AST::Diff::ByteExact],
    plaintext: [->(config) { ReVIEW::Test::TextComparator.new(format: :plaintext, config: config) }, ReVIEW::AST::Diff::TextLines],
    top: [->(config) { ReVIEW::Test::TextComparator.new(format: :top, config: config) }, ReVIEW::AST::Diff::TextLines]
  }.freeze

  # The sweep runs under each; the settings that changed the most output when
  # they were first swept (Re:VIEW 2's older macros, English quotes).
  CONFIGS = {
    default: {},
    review_version2: { 'review_version' => 2.0 },
    language_en: { 'language' => 'en' }
  }.freeze

  # Targets for the reference commands, before each fragment; //printendnotes
  # after it.
  PROLOGUE = <<~RE
    == Sec{s1}

    //label[l1]

    //list[l1][LC]{
    x
    //}

    //table[t1][TC]{
    A\tB
    //}

    //image[i1][IC]{
    //}

    //texequation[e1][EC]{
    x
    //}

    //footnote[f1][F]

    //endnote[n1][N]

    ===[column] Col{c1}

    text

    ===[/column]

  RE
  EPILOGUE = "\n\n//printendnotes\n"

  INLINE_ARGS = Hash.new('abc & <d>').merge(
    'list' => 'l1', 'table' => 't1', 'img' => 'i1', 'imgref' => 'i1', 'icon' => 'i1', 'eq' => 'e1',
    'fn' => 'f1', 'endnote' => 'n1', 'bib' => 'b1', 'hd' => 'Sec', 'sec' => 's1', 'secref' => 's1',
    'sectitle' => 's1', 'column' => 'c1', 'chap' => 'test', 'chapref' => 'test', 'title' => 'test',
    'labelref' => 'l1', 'ref' => 'l1', 'pageref' => 'l1', 'href' => 'http://example.com, Ex',
    'ruby' => '漢字,かんじ', 'kw' => 'Word, desc', 'm' => 'x^2', 'uchar' => '2460', 'tcy' => '12', 'maru' => '1',
    'br' => '', 'raw' => '|html,latex,idgxml,plaintext,top|<r>\\nx', 'embed' => '|html,latex,idgxml,plaintext,top|<e>\\nx'
  )

  # command => { formats => reason }. Only where nothing can be compared, or
  # where the difference is understood and deliberately left.
  ALL = FORMATS.keys.freeze
  KNOWN_DIFFERENCES = {
    '@<bib>' => { ALL => 'needs a bib file; the one-chapter test book has none (the builder fails)' },
    '@<include>' => { %i[plaintext top] => 'needs the included file (the builder fails)' },
    '//bibpaper' => { ALL => 'needs a bib file; the one-chapter test book has none (the builder fails)' },
    '//imgtable' => {
      %i[latex idgxml plaintext top] => 'the builder fails without the image argument (ArgumentError)',
      %i[html latex idgxml] => 'an //imgtable body is table rows in the AST, not the dummy-image lines the builder prints'
    },
    '//indepimage' => { %i[html] => 'HTMLBuilder fails with a caption and metric and no image (nil#sub)' },
    '//numberlessimage' => { %i[html] => 'HTMLBuilder fails with a caption and metric and no image (nil#sub)' },
    '//table' => { %i[idgxml] => 'a row starting with a tab: an empty first cell in IDGXMLBuilder only (spec-questions #10)' },
    '//emtable' => { %i[idgxml] => 'a row starting with a tab: an empty first cell in IDGXMLBuilder only (spec-questions #10)' },
    '//noindent' => {
      %i[latex top] => 'LATEXBuilder/TOPBuilder print the marker where //noindent stands; the AST lowers it onto ' \
                       'the next paragraph, and here none follows'
    }
  }.freeze

  def known?(command, format)
    KNOWN_DIFFERENCES.fetch(command, {}).any? { |formats, _reason| formats.include?(format) }
  end

  # [command, source] for every declared command and argument count.
  def fragments
    inlines = ReVIEW::Compiler::INLINE.keys.map do |name|
      ["@<#{name}>", "Pre @<#{name}>{#{INLINE_ARGS[name.to_s]}} post.\n"]
    end
    blocks = ReVIEW::Compiler::SYNTAX.flat_map do |name, syntax|
      next [] if name == :include # reads a file

      argc = syntax.instance_variable_get(:@argc_spec)
      counts = [syntax.min_argc, argc.is_a?(Range) ? argc.end : argc].uniq
      counts.map do |count|
        args = (1..count).map { |i| "[a#{i}]" }.join
        body = syntax.block_allowed? ? "{\nline1 @<b>{bold} & <x>\n\tline2\n//}" : ''
        ["//#{name}", "//#{name}#{args}#{body}\n"]
      end
    end
    inlines + blocks
  end

  # nil when the two paths agree.
  def divergence(format, source, config)
    comparator_factory, diff_class = FORMATS.fetch(format)
    comparator = comparator_factory.call(Marshal.load(Marshal.dump(config)))
    builder = outcome { comparator.convert_with_builder(PROLOGUE + source + EPILOGUE) }
    renderer = outcome { comparator.convert_with_renderer(PROLOGUE + source + EPILOGUE) }
    return if builder.is_a?(Exception) && renderer.is_a?(Exception)
    return "only the builder fails: #{builder.message.lines.first}" if builder.is_a?(Exception)
    return "only the renderer fails: #{renderer.class}: #{renderer.message.lines.first}" if renderer.is_a?(Exception)

    diff = diff_class.new.compare(builder, renderer)
    diff.equal? ? nil : diff.pretty_diff.lines.first(6).join
  end

  def outcome
    yield
  rescue StandardError, ScriptError => e
    e
  end

  def sweep(config_name = :default)
    @sweep ||= {}
    @sweep[config_name] ||= fragments.flat_map do |command, source|
      FORMATS.each_key.filter_map do |format|
        problem = divergence(format, source, CONFIGS.fetch(config_name))
        [command, format, source, problem] if problem
      end
    end
  end

  CONFIGS.each_key do |config_name|
    define_method("test_every_declared_command_agrees_in_every_format_#{config_name}") do
      failures = sweep(config_name).reject { |command, format, _source, _problem| known?(command, format) }
      message = failures.map { |command, format, source, problem| "#{command} (#{format}) #{source.inspect}\n  #{problem}" }
      assert(failures.empty?, "the paths disagree under #{config_name}:\n#{message.join("\n")}")
    end
  end

  # The same commands with one argument written empty, as `[]`: most builders
  # take an empty caption for none (caption.present?), but some number a list
  # or an equation anyway, or write IDGXML's -t form of a //point. Review-
  # retrovert writes every captionless Re:VIEW Starter //list as
  # //list[starter_auto_id_list_N][]{.
  #
  # An empty id is left out: the builders index the block under the id '',
  # the AST takes it for no id (Node#id?).
  EMPTY_ID_COMMANDS = %i[list listnum table image texequation indepimage numberlessimage imgtable graph bibpaper].freeze

  def empty_argument_fragments
    ReVIEW::Compiler::SYNTAX.flat_map do |name, syntax|
      argc = syntax.instance_variable_get(:@argc_spec)
      max = argc.is_a?(Range) ? argc.end : argc
      next [] if name == :include || max.nil? || max == 0

      body = syntax.block_allowed? ? "{\nline1 @<b>{bold}\n//}" : ''
      (0...max).filter_map do |empty|
        next if empty == 0 && EMPTY_ID_COMMANDS.include?(name)

        args = (0...max).map { |i| i == empty ? '[]' : "[a#{i + 1}]" }.join
        ["//#{name}", "//#{name}#{args}#{body}\n"]
      end
    end
  end

  def test_an_empty_argument_agrees_in_every_format
    failures = empty_argument_fragments.flat_map do |command, source|
      FORMATS.each_key.filter_map do |format|
        next if known?(command, format)

        problem = divergence(format, source, {})
        "#{command} (#{format}) #{source.inspect}\n  #{problem}" if problem
      end
    end
    assert(failures.empty?, "the paths disagree on an empty argument:\n#{failures.join("\n")}")
  end

  # Checked under the default settings only: an entry needs to diverge
  # there, not under every configuration.
  def test_known_differences_still_differ
    diverging = sweep.to_set { |command, format, _source, _problem| [command, format] }
    stale = KNOWN_DIFFERENCES.flat_map do |command, by_formats|
      by_formats.keys.flatten.uniq.reject { |format| diverging.include?([command, format]) }.map { |format| "#{command} (#{format})" }
    end
    assert(stale.empty?, "KNOWN_DIFFERENCES entries that agree now -- remove them: #{stale.join(', ')}")
  end
end
