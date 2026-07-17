#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

# Differential DVI sweep over a Re:VIEW book.
#
# For every chapter it renders the LaTeX body twice -- once via the legacy
# LATEXBuilder and once via the AST LatexRenderer, with full book context --
# then typesets both under an identical preamble and compares the DVI output.
# Any chapter whose DVI differs indicates a real, visible divergence between
# the two code paths.
#
# Usage:
#   BUNDLE_GEMFILE=Gemfile bundle exec ruby tools/compare_book.rb <book_src_dir>
#
# Exit status is non-zero if any chapter differs or fails to build.

require 'review'

root = File.expand_path('..', __dir__)
$LOAD_PATH.unshift File.join(root, 'test', 'support')
$LOAD_PATH.unshift File.join(root, 'tools', 'compare')
require 'review/test/latex_comparator'
require 'dvi_comparator'

book_dir = ARGV[0] or abort "usage: compare_book.rb <book_src_dir>"
book_dir = File.expand_path(book_dir)

template_dir = File.join(ReVIEW::Book.const_defined?(:Base) ? Gem.loaded_specs['review'].gem_dir : '',
                         'templates', 'latex')

puts "Setting up preamble/sty from #{book_dir} ..."
dvi = ReVIEW::Compare::DviComparator.from_book(
  book_dir,
  template_dir: template_dir,
  bundle_gemfile: ENV['BUNDLE_GEMFILE']
)

comparator = ReVIEW::Test::LatexComparator.new
book = ReVIEW::Book::Base.new(book_dir)
chapter_names = book.chapters.map(&:name)

puts "Comparing #{chapter_names.size} chapters (DVI level)\n\n"

results = chapter_names.map do |name|
  begin
    bodies = comparator.convert_chapter_with_book_context(book_dir, name)
    r = dvi.compare(bodies[:builder], bodies[:renderer])
  rescue StandardError => e
    # A chapter that only one path can even compile is itself a divergence.
    r = ReVIEW::Compare::DviComparator::Result.new(
      identical: false, status: :compile_error, pages: nil,
      diff: { error: "#{e.class}: #{e.message}" }
    )
  end
  mark = case r.status
         when :equal then "OK   "
         when :differ then "DIFF "
         when :compile_error then "CERR "
         else "BUILD"
         end
  line = format('  %-6s %-16s', mark, name)
  line += " page=#{r.diff[:page]} @dvi-line #{r.diff[:first_diff_line]} (-#{r.diff[:removed_count]}/+#{r.diff[:added_count]})" if r.status == :differ
  line += " #{r.diff[:error]}" if r.status == :compile_error
  line += " (#{r.status})" unless %i[equal differ compile_error].include?(r.status)
  puts line
  [name, r]
end

puts
n_diff = results.count { |_, r| !r.identical? }
equal = results.count { |_, r| r.identical? }
puts "Summary: #{equal}/#{results.size} chapters DVI-identical, #{n_diff} divergent"

# Show the first divergence in detail to aid investigation.
first = results.find { |_, r| r.status == :differ }
if first
  name, r = first
  puts "\nFirst divergence: #{name} (#{r.diff[:page]})"
  puts "--- builder"
  puts r.diff[:removed].map { |l| "  #{l}" }.join
  puts "+++ renderer"
  puts r.diff[:added].map { |l| "  #{l}" }.join
end

exit(n_diff.zero? ? 0 : 1)
