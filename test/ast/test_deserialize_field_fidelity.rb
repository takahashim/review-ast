# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast'
require 'review/ast/compiler'
require 'review/ast/json_serializer'
require 'review/book'
require 'review/book/chapter'
require 'review/configure'

# Systematic guard for the deserialize bug class fixed for inline_type /
# code_type / minicolumn_type: a scalar field that is a Symbol (or Integer, …) on
# the freshly compiled tree but comes back as a different type after a JSON round
# trip. JSON hides Symbol-vs-String, so the byte-identity round-trip test cannot
# see it; this walks a comprehensive fixture's fresh and reloaded trees in
# parallel and asserts every scalar field keeps its value and class.
class TestDeserializeFieldFidelity < Test::Unit::TestCase
  # (node class short name, ivar) pairs whose compiled value is intentionally not
  # reconstructed, so they are exempt from the equality check:
  #   - ListNode @start_number: a default start of 1 is omitted from the dump.
  #   - ListItemNode @item_number: an absolute number stamped by a compile-time
  #     pass that renderers do not read (they number by position).
  ALLOWLIST = [
    %w[ListNode @start_number],
    %w[ListItemNode @item_number]
  ].freeze

  STRUCTURAL = %i[@children @parent @location].freeze

  FIXTURE = <<~RE
    = 章タイトル

    段落テキスト @<b>{強調} と @<hd>{節1} 参照。@<br>{}
    次行。

    == 節1

    //list[l1][リスト]{
    code line
    //}

    //image[img1][画像]

    //table[t1][表]{
    a\tb
    ------------
    c\td
    //}

    //texequation[eq1]{
    E=mc^2
    //}

    //footnote[fn1][脚注]

    //note[ノート]{
    ノート本文。
    //}

    ===[column]{col1} コラム

    コラム本文。

    ===[/column]

     1. ol item
     2. ol two

     : 定義語
    \t定義説明

    //bibpaper[bib1][文献]

    //embed[html]{
    <div>raw</div>
    //}
  RE

  def compile
    config = ReVIEW::Configure.values
    book = ReVIEW::Book::Base.new(config: config)
    ReVIEW.logger = ReVIEW::Logger.new(StringIO.new)
    ReVIEW::I18n.setup('ja')
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'c', 'c.re', StringIO.new)
    chapter.content = FIXTURE
    ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
  end

  def flatten(node, acc = [])
    acc << node
    node.children.each { |c| flatten(c, acc) } if node.respond_to?(:children)
    acc
  end

  # A value that is (or contains) a Node is structure the parallel walk / the
  # byte-identity test already cover; only genuine scalars are compared here.
  def scalar?(value)
    return false if value.is_a?(ReVIEW::AST::Node)
    return false if value.is_a?(Array) && value.any?(ReVIEW::AST::Node)

    true
  end

  def test_scalar_fields_keep_value_and_class_across_round_trip
    root = compile
    reloaded = ReVIEW::AST::JSONSerializer.deserialize(ReVIEW::AST::JSONSerializer.serialize(root))

    fresh_nodes = flatten(root)
    reloaded_nodes = flatten(reloaded)
    assert_equal fresh_nodes.size, reloaded_nodes.size, 'tree shape changed across round trip'

    problems = []
    fresh_nodes.zip(reloaded_nodes).each do |f, r|
      name = f.class.name.split('::').last
      f.instance_variables.each do |ivar|
        next if STRUCTURAL.include?(ivar)
        next if ALLOWLIST.include?([name, ivar.to_s])

        fv = f.instance_variable_get(ivar)
        next unless scalar?(fv)

        rv = r.instance_variable_get(ivar)
        if fv != rv || fv.class != rv.class
          problems << "#{name}#{ivar}: fresh=#{fv.inspect}(#{fv.class}) reloaded=#{rv.inspect}(#{rv.class})"
        end
      end
    end

    assert_empty(problems, "deserialize changed a scalar field:\n  #{problems.join("\n  ")}")
  end
end
