#!/usr/bin/env ruby
# frozen_string_literal: true

# Three-engine page-design (版面) comparison — doc/design-hanmen.ja.md §7.3, R3.
#
# Builds one solid-set (べた組み) page of a single full-width kanji from the
# *shipped* design values and cross-checks the type area across the three
# engines review-ast targets:
#
#   Typst        review-book (templates/typst/review-book) + default-theme
#   Vivliostyle  design.css + style-vivliostyle.css, printed by vivlio-pdf
#   LaTeX        review-jlreq (the review gem's class), design values as options
#
# The probe glyph is the only thing measured, so running heads and folios are
# excluded automatically. From each PDF's first full page it reports lines per
# page, characters per line, and the four edges of the type area (mm), then
# checks that the engines agree.
#
# Why forced options for LaTeX: review-ast's jlreq configs do not pin
# line_length / number_of_lines / margins, so jlreq would auto-size the type
# area. To compare the *same design* we pass the design values as class options
# (this is what a book pinning them would produce). Horizontal parity here is
# the design's; whether the default jlreq config reproduces it is a separate
# wiring question (noted in §7.3).
#
# Engines whose toolchain is absent are skipped, so this runs anywhere and is
# never a hard gate.
#
#   ruby tools/hanmen-compare/compare.rb          # temp dir, cleaned up
#   ruby tools/hanmen-compare/compare.rb out/     # keep the PDFs in out/ to open
#   rake hanmen:compare        /  rake 'hanmen:compare[out]'

require 'fileutils'
require 'tmpdir'

ROOT = File.expand_path('../..', __dir__)
CSS_DIR = File.join(ROOT, 'templates/vivliostyle/css')
DESIGN_CSS = File.join(CSS_DIR, 'style-vivliostyle-design.css')
MAIN_CSS = File.join(CSS_DIR, 'style-vivliostyle.css')
REVIEW_BOOK = File.join(ROOT, 'templates/typst/review-book')
GLYPH = '田'
PT2MM = 25.4 / 72.0
# Agreement thresholds: counts are exact; the edge positions allow a little
# slack, but the line pitch is held tight so a leading drift (e.g. jlreq's
# default 1.7zw vs the design's) is caught rather than waved through.
POS_TOL_MM = 0.5
PITCH_TOL_MM = 0.05

# The shipped design values, read once from design.css so this tool has a
# single source and drifts with the file it is checking.
def design_values
  css = File.read(DESIGN_CSS)
  num = ->(name) { css[/--#{name}:\s*([^;]+);/, 1].to_s[/[\d.]+/].to_f }
  {
    fontsize_q: num.call('fontsize'),
    baselineskip_q: num.call('baselineskip'),
    line_length: num.call('line-length').to_i,
    lines: num.call('number-of-lines').to_i,
    head_space: num.call('head-space'),
    gutter: num.call('gutter'),
    paper_w: num.call('papersize-width'),
    paper_h: num.call('papersize-height')
  }
end

# The type area of the first full page: only rows that are runs of the probe
# glyph count, so page furniture never leaks in. Returns nil for a blank page.
# pdftotext -bbox emits one <word> per line here (solid-set has no spaces); a
# regex keeps this free of any XML-library dependency.
WORD_RE = %r{<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</word>}

def measure(pdf, page = 1)
  bbox = IO.popen(['pdftotext', '-bbox', '-f', page.to_s, '-l', page.to_s, pdf, '-'], &:read)
  rows = bbox.scan(WORD_RE).filter_map do |x0, y0, x1, y1, text|
    next unless text.length > 1 && text.chars.uniq == [GLYPH]

    [x0.to_f, y0.to_f, x1.to_f, y1.to_f, text.length]
  end
  return nil if rows.empty?

  tops = rows.map { |r| r[1] }.sort
  diffs = tops.each_cons(2).map { |a, b| b - a }
  pitch = diffs.empty? ? 0.0 : diffs.sort[diffs.size / 2] * PT2MM # median row spacing
  { lines: rows.size, chars: rows.map { |r| r[4] }.max, pitch: pitch,
    left: rows.map { |r| r[0] }.min * PT2MM, right: rows.map { |r| r[2] }.max * PT2MM,
    top: rows.map { |r| r[1] }.min * PT2MM, bottom: rows.map { |r| r[3] }.max * PT2MM }
end

def tool?(*cmd)
  system(*cmd, out: File::NULL, err: File::NULL)
end

def vivlio?
  require 'vivlio/pdf'
  true
rescue LoadError
  false
end

# The review gem ships review-jlreq.cls; without it the LaTeX arm is skipped.
def review_gem_dir
  Gem::Specification.find_by_name('review').gem_dir
rescue Gem::MissingSpecError
  nil
end

# Enough glyphs to overfill one page, so page 1 is a full body page.
def probe_text(dv)
  GLYPH * (dv[:line_length] * dv[:lines] * 2)
end

def build_typst(dir, dv)
  return nil unless tool?('typst', '--version')

  FileUtils.mkdir_p(dir)
  FileUtils.cp_r(REVIEW_BOOK, File.join(dir, 'review-book'))
  src = File.join(dir, 'probe.typ')
  File.write(src, <<~TYP)
    #import "/review-book/lib.typ": book, default-theme
    #show: book.document.with(metadata: (title: [probe], language: "ja"), theme: default-theme)
    #set par(first-line-indent: 0pt)
    #("#{GLYPH}" * #{dv[:line_length] * dv[:lines] * 2})
  TYP
  pdf = File.join(dir, 'typst.pdf')
  ok = system('typst', 'compile', '--root', dir, src, pdf, out: File::NULL, err: File::NULL)
  ok ? pdf : nil
end

def build_vivliostyle(dir, dv)
  return nil unless vivlio?

  FileUtils.mkdir_p(dir)
  css = File.join(dir, 'css')
  FileUtils.mkdir_p(css)
  FileUtils.cp(DESIGN_CSS, css)
  FileUtils.cp(MAIN_CSS, css)
  html = File.join(dir, 'probe.html')
  File.write(html, <<~HTML)
    <!DOCTYPE html><html lang="ja"><head><meta charset="utf-8"><title>probe</title>
    <link rel="stylesheet" href="css/#{File.basename(DESIGN_CSS)}">
    <link rel="stylesheet" href="css/#{File.basename(MAIN_CSS)}">
    <style>p{ text-indent: 0 }</style></head>
    <body><p>#{probe_text(dv)}</p></body></html>
  HTML
  pdf = File.join(dir, 'vivliostyle.pdf')
  Vivlio::PDF.print(source: html, output: pdf, outline: :none)
  File.exist?(pdf) ? pdf : nil
rescue StandardError => e
  warn "  Vivliostyle build failed: #{e.message}"
  nil
end

def build_latex(dir, dv)
  return nil unless tool?('uplatex', '--version') && tool?('dvipdfmx', '--version')

  gem_dir = review_gem_dir or return nil
  FileUtils.mkdir_p(dir)
  cls_dir = File.join(gem_dir, 'templates/latex/review-jlreq')
  hanmen_w = dv[:line_length] * dv[:fontsize_q] * 0.25 # Q = 0.25mm
  # baselineskip is pinned too: jlreq's default line gap is 1.7zw (22.1Q for a
  # 13Q body), not the design's 21.65Q, so without this the LaTeX line pitch
  # would drift from the other two.
  opts = "media=ebook,paper={#{dv[:paper_w]}mm,#{dv[:paper_h]}mm}," \
         "fontsize=#{dv[:fontsize_q]}Q,baselineskip=#{dv[:baselineskip_q]}Q," \
         "line_length=#{hanmen_w}mm,number_of_lines=#{dv[:lines]}," \
         "head_space=#{dv[:head_space]}mm,gutter=#{dv[:gutter]}mm"
  src = File.join(dir, 'probe.tex')
  File.write(src, "\\documentclass[#{opts}]{review-jlreq}\\pagestyle{plain}" \
                  "\\begin{document}\\noindent #{probe_text(dv)}\\end{document}\n")
  env = { 'TEXINPUTS' => ".:#{cls_dir}:" }
  Dir.chdir(dir) do
    return nil unless system(env, 'uplatex', '-interaction=nonstopmode', '-halt-on-error',
                             'probe.tex', out: File::NULL, err: File::NULL)
    return nil unless system('dvipdfmx', '-q', 'probe.dvi', out: File::NULL, err: File::NULL)
  end
  File.join(dir, 'probe.pdf')
end

def format_row(name, m)
  return sprintf('  %-12s (skipped — toolchain not available)', name) unless m

  sprintf('  %-12s lines=%2d chars=%2d pitch=%.2f | left=%5.1f right=%5.1f | top=%5.1f bottom=%6.1f | W=%5.1f',
          name, m[:lines], m[:chars], m[:pitch], m[:left], m[:right], m[:top], m[:bottom],
          m[:right] - m[:left])
end

def spread(values)
  values.max - values.min
end

def report(results)
  present = results.compact
  puts
  results.each { |name, m| puts format_row(name, m) }
  puts
  if present.size < 2
    puts 'Need at least two engines to compare; install more toolchains.'
    return true
  end

  ok = true
  %i[lines chars].each do |key|
    vals = present.map { |_, m| m[key] }
    same = vals.uniq.size == 1
    ok &&= same
    puts sprintf('  %-8s %s  (%s)', key, same ? 'MATCH' : 'DIFFER', vals.join(', '))
  end
  # Left/right edges and the line pitch are font-independent (CJK advance is the
  # em, and pitch is the leading), so these are gated. Pitch is held tighter.
  { left: POS_TOL_MM, right: POS_TOL_MM, pitch: PITCH_TOL_MM }.each do |key, tol|
    vals = present.map { |_, m| m[key] }
    same = spread(vals) <= tol
    ok &&= same
    puts sprintf('  %-8s %s  spread=%.2fmm  (%s)', key, same ? 'MATCH' : 'DRIFT',
                 spread(vals), vals.map { |v| sprintf('%.2f', v) }.join(', '))
  end
  # top/bottom are the glyph box pdftotext reports. Vivliostyle's Chrome-made
  # PDF embeds CJK as Type 3, whose box reads ~2.6x the em regardless of the
  # font, while Typst/LaTeX (CID fonts) report a tight per-glyph box — verified
  # by feeding both the same Hiragino and getting 3.25mm vs 8.45mm. So this is
  # an engine encoding artifact, not a layout difference; shown, not gated. The
  # em grid itself is what pitch / lines / left / right verify.
  %i[top bottom].each do |key|
    vals = present.map { |_, m| m[key] }
    puts sprintf('  %-8s spread=%.2fmm  (%s)  [informational: engine glyph box]',
                 key, spread(vals), vals.map { |v| sprintf('%.1f', v) }.join(', '))
  end
  puts
  puts ok ? 'Horizontal type area agrees across engines.' : 'Horizontal type area DIFFERS — investigate the design files.'
  ok
end

# Build every engine into +dir+, report, and return [ok, {name => pdf|nil}].
def run(dir, dv)
  pdfs = {
    'Typst' => build_typst(File.join(dir, 'typst'), dv),
    'Vivliostyle' => build_vivliostyle(File.join(dir, 'vivlio'), dv),
    'LaTeX' => build_latex(File.join(dir, 'latex'), dv)
  }
  ok = report(pdfs.transform_values { |pdf| pdf && File.exist?(pdf) ? measure(pdf) : nil })
  [ok, pdfs]
end

dv = design_values
puts "Design (design.css): #{dv[:line_length]}字 × #{dv[:lines]}行, #{dv[:fontsize_q]}Q, " \
     "天#{dv[:head_space]}mm ノド#{dv[:gutter]}mm, 用紙#{dv[:paper_w]}×#{dv[:paper_h]}mm"

# With an output directory the builds (PDF and probe sources) are kept there for
# inspection; without one they go to a temp dir that is cleaned up.
outdir = ARGV[0]
if outdir
  FileUtils.mkdir_p(outdir)
  ok, pdfs = run(File.expand_path(outdir), dv)
  puts
  puts 'Generated PDFs (kept):'
  pdfs.each { |name, pdf| puts sprintf('  %-12s %s', name, pdf) if pdf && File.exist?(pdf) }
  exit(ok ? 0 : 1)
else
  Dir.mktmpdir('hanmen-compare') { |dir| exit(run(dir, dv).first ? 0 : 1) }
end
