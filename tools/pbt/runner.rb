#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

# Property-based differential testing of the AST renderers.
#
# It generates random self-contained Re:VIEW documents, renders each through
# both a legacy builder and the matching AST renderer, and asserts they
# agree. On a counterexample it shrinks the document to a minimal reproducer
# and prints it.
#
# For LaTeX the property defaults to DVI equivalence (--mode dvi), which sees
# the whitespace-level differences that matter; --mode canonical is faster but
# blind to whitespace (use it only for a quick structural pass). --mode html,
# idgxml, plaintext and top compare those formats instead.
#
# Usage:
#   BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/pbt/runner.rb \
#       [--seeds N] [--start S] [--blocks N] \
#       [--mode dvi|canonical|html|idgxml|plaintext|top]
#
# Seeds are deterministic: a reported failing seed reproduces exactly. Fold a
# real finding into a permanent regression test rather than relying on the seed.

require 'optparse'
require 'yaml'

opts = { seeds: 50, start: 1, mode: 'dvi', blocks: nil, config: {},
         book_config: 'config.yml',
         book: File.expand_path('../../samples/sample-book/src', __dir__) }
OptionParser.new do |o|
  o.on('--seeds N', Integer) { |v| opts[:seeds] = v }
  o.on('--start S', Integer) { |v| opts[:start] = v }
  o.on('--mode M', %w[dvi canonical html idgxml plaintext top]) { |v| opts[:mode] = v }
  o.on('--blocks N', Integer) { |v| opts[:blocks] = v }
  o.on('--book DIR') { |v| opts[:book] = File.expand_path(v) }
  # Config filename (relative to --book) that review-pdfmaker uses to harvest the
  # DVI preamble/sty. Use a highlight-enabled config to typeset listings blocks.
  o.on('--book-config FILE') { |v| opts[:book_config] = v }
  # Override a book-config key for the whole sweep, e.g.
  #   --config secnolevel=0 --config caption_position/list=bottom
  # Values are parsed as YAML scalars so true/false/0 keep their types. A
  # slash in the key denotes a nested config hash (config['a']['b']).
  o.on('--config K=V') do |kv|
    key, val = kv.split('=', 2)
    parsed = YAML.safe_load(val.to_s)
    if key.include?('/')
      outer, inner = key.split('/', 2)
      (opts[:config][outer] ||= {})[inner] = parsed
    else
      opts[:config][key] = parsed
    end
  end
end.parse!(ARGV)

require 'review'
root = File.expand_path('../..', __dir__)
$LOAD_PATH.unshift(File.join(root, 'test', 'support'))
$LOAD_PATH.unshift(File.join(root, 'tools', 'compare'))
$LOAD_PATH.unshift(File.join(root, 'tools', 'pbt'))
require 'dvi_comparator'
require 'generator'

# Select the format's comparator (renders a *.re through builder + AST renderer)
# and its structural diff. LaTeX uses DVI or a canonical text diff; HTML and
# IDGXML use spec-aware DOM/XML diffs (Diff::Html follows the CSS Text 3
# white-space model so significant whitespace is not lost); the text formats
# compare their non-blank lines (Diff::TextLines).
case opts[:mode]
when 'html'
  require 'review/test/html_comparator'
  require 'review/ast/diff/html'
  comparator = ReVIEW::Test::HtmlComparator.new(config: opts[:config])
  canonical = ReVIEW::AST::Diff::Html.new
when 'idgxml'
  require 'review/test/idgxml_comparator'
  require 'review/ast/diff/byte_exact'
  comparator = ReVIEW::Test::IdgxmlComparator.new(config: opts[:config])
  # IDGXML is compared byte-for-byte: it is compact (no formatting whitespace)
  # and InDesign imports text literally, so there is no whitespace-collapsing
  # model to normalize -- any byte difference is a real one.
  canonical = ReVIEW::AST::Diff::ByteExact.new
when 'plaintext', 'top'
  require 'review/test/text_comparator'
  require 'review/ast/diff/text_lines'
  comparator = ReVIEW::Test::TextComparator.new(format: opts[:mode].to_sym, config: opts[:config])
  canonical = ReVIEW::AST::Diff::TextLines.new
else
  require 'review/test/latex_comparator'
  require 'review/ast/diff/latex'
  comparator = ReVIEW::Test::LatexComparator.new(config: opts[:config])
  canonical = ReVIEW::AST::Diff::Latex.new
end
puts "config override: #{opts[:config].inspect}" unless opts[:config].empty?

dvi = nil
if opts[:mode] == 'dvi'
  puts "Setting up DVI preamble/sty from #{opts[:book]} ..."
  dvi = ReVIEW::Compare::DviComparator.from_book(
    opts[:book],
    template_dir: File.join(Gem.loaded_specs['review'].gem_dir, 'templates', 'latex'),
    bundle_gemfile: ENV['BUNDLE_GEMFILE'],
    config: opts[:book_config]
  )
end

# Render a document both ways and classify the result.
# => [:equal | :differ | :builder_error | :renderer_error | :both_error, detail]
def check(doc, comparator:, canonical:, dvi:)
  begin
    builder_tex = comparator.convert_with_builder(doc.to_re)
  rescue StandardError, ScriptError => e # ScriptError catches NotImplementedError
    be = e
  end
  begin
    renderer_tex = comparator.convert_with_renderer(doc.to_re)
  rescue StandardError, ScriptError => e
    re = e
  end

  return [:both_error, be&.message.to_s] if be && re
  return [:builder_error, be.message] if be
  return [:renderer_error, re.message] if re

  if dvi
    r = dvi.compare(builder_tex, renderer_tex)
    # Propagate the DVI status faithfully. :build_error_both means the (identical
    # or not) LaTeX cannot be typeset standalone under the harness preamble --
    # that is a harness/generator limitation, not a builder-vs-renderer bug.
    return [:equal, nil] if r.status == :equal

    return [r.status, r.diff]
  else
    r = canonical.compare(builder_tex, renderer_tex)
    return [:equal, nil] if r.equal?

    return [:differ, r.pretty_diff]
  end
end

# A divergence is a genuine builder-vs-renderer disagreement: different output,
# or only one path able to compile/typeset. "both fail" (compile or typeset)
# just means the input was invalid or un-typesettable for both -- not a bug.
def divergent?(status)
  %i[differ builder_error renderer_error build_error_a build_error_b].include?(status)
end

def both_failed?(status)
  %i[both_error build_error_both].include?(status)
end

def shrink(doc, comparator:, canonical:, dvi:)
  current = doc
  loop do
    smaller = current.shrinks.find do |cand|
      status, = check(cand, comparator: comparator, canonical: canonical, dvi: dvi)
      divergent?(status)
    end
    break unless smaller

    current = smaller
  end
  current
end

failures = []
skipped = []
range = (opts[:start]...(opts[:start] + opts[:seeds]))
range.each do |seed|
  doc = ReVIEW::PBT::Generator.new(seed).document(n_blocks: opts[:blocks])
  status, detail = check(doc, comparator: comparator, canonical: canonical, dvi: dvi)
  if divergent?(status)
    print 'X'
    failures << [seed, status, detail, doc]
  elsif both_failed?(status)
    print '!' # neither path could typeset/compile this input (not a divergence)
    skipped << [seed, detail]
  else
    print '.'
  end
  $stdout.flush
end
puts "\n"
unless skipped.empty?
  puts "#{skipped.size} input(s) neither path could typeset/compile (skipped):"
  skipped.each do |seed, detail|
    first_line = detail.to_s.lines.first&.strip
    puts "  seed=#{seed}: #{first_line}"
  end
end

if failures.empty?
  puts "No divergence in seeds #{range.first}..#{range.last} (mode=#{opts[:mode]})."
  exit 0
end

puts "#{failures.size} divergent seed(s). Shrinking the first...\n\n"
seed, status, _detail, doc = failures.first
minimal = shrink(doc, comparator: comparator, canonical: canonical, dvi: dvi)
mstatus, mdetail = check(minimal, comparator: comparator, canonical: canonical, dvi: dvi)

puts "seed=#{seed} status=#{status} -> minimal status=#{mstatus}"
puts "other divergent seeds: #{failures[1..].map(&:first).join(', ')}" if failures.size > 1
puts "\n===== minimal reproducer (.re) ====="
puts minimal.to_re
puts '===== detail ====='
pp mdetail
exit 1
