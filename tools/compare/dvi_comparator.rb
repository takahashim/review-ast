# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'open3'
require 'tmpdir'
require 'fileutils'

module ReVIEW
  module Compare
    # DviComparator typesets two LaTeX *bodies* under an identical Re:VIEW
    # preamble and compares the resulting DVI output. Because the preamble and
    # the TeX toolchain are held fixed, any difference in the DVI reflects a
    # difference in how the two bodies typeset -- i.e. a real, visible
    # divergence between the LATEXBuilder and the AST LatexRenderer.
    #
    # This is the strict oracle for differential testing (broad book sweeps)
    # and for confirming property-based-testing findings. It is intentionally
    # decoupled from *how* the bodies are produced.
    class DviComparator
      # dviasm ships with TeXLive; used to turn the binary DVI into a stable,
      # diffable textual dump.
      DVIASM = ENV['DVIASM'] ||
               Dir.glob('/usr/local/texlive/*/texmf-dist/scripts/dviasm/dviasm.py').max

      # A fixed comment removes the only nondeterministic part of the DVI
      # (the build timestamp in the preamble).
      OUTPUT_COMMENT = 'review-ast-dvi-compare'

      Result = Struct.new(:identical, :status, :pages, :diff, keyword_init: true) do
        def identical? = identical
        # :equal | :differ | :build_error_a | :build_error_b | :build_error_both
      end

      # @param preamble [String] LaTeX preamble up to (not including) \begin{document}
      # @param sty_dir  [String] directory containing review-jsbook.cls and the review *.sty
      # @param texcommand [String] the (u)platex command to run
      # @param assets_dir [String, nil] directory of book assets (e.g. processed
      #   images with .xbb) to make available to each typeset run
      def initialize(preamble:, sty_dir:, assets_dir: nil, texcommand: 'uplatex')
        @preamble = preamble
        @sty_dir = sty_dir
        @assets_dir = assets_dir
        @texcommand = texcommand
        raise 'dviasm not found (set DVIASM=)' unless DVIASM && File.exist?(DVIASM)
      end

      # Harvest a reusable preamble + sty set by building a real Re:VIEW book
      # once with review-pdfmaker. The book's config decides paper size etc.;
      # for comparison purposes any fixed config works, as long as both bodies
      # share it.
      #
      # @param book_src_dir [String] a buildable Re:VIEW project (config.yml + catalog.yml)
      # @param template_dir [String] review gem's templates/latex dir (for cls/sty)
      # @return [DviComparator]
      def self.from_book(book_src_dir, template_dir:, bundle_gemfile: nil, config: 'config.yml')
        work = Dir.mktmpdir('review-ast-dvi-setup')
        src = File.join(work, 'src')
        FileUtils.cp_r(book_src_dir, src)
        # Provide the review-jsbook cls/sty, but never overwrite the book's own
        # sty (which may carry customizations and match the book's config).
        FileUtils.mkdir_p(File.join(src, 'sty'))
        Dir.glob(File.join(template_dir, 'review-jsbook', '*')).each do |f|
          dest = File.join(src, 'sty', File.basename(f))
          FileUtils.cp(f, dest) unless File.exist?(dest)
        end

        env = {}
        env['BUNDLE_GEMFILE'] = bundle_gemfile if bundle_gemfile
        out, status = Open3.capture2e(env, 'bundle', 'exec', 'review-pdfmaker', '--debug', config, chdir: src)
        raise "setup build failed:\n#{out}" unless status.success?

        pdfdir = Dir.glob(File.join(src, '*-pdf')).first
        raise 'setup build produced no -pdf dir' unless pdfdir

        master = File.read(File.join(pdfdir, '__REVIEW_BOOK__.tex'))
        preamble = master[/\A.*?(?=^\\begin\{document\})/m] or
          raise 'could not locate \\begin{document} in master tex'

        images = File.join(pdfdir, 'images')
        new(preamble: preamble, sty_dir: pdfdir,
            assets_dir: (Dir.exist?(images) ? images : nil))
      end

      # Typeset a single body and return its normalized dviasm dump.
      # @return [Array(String or nil, String)] [dump_or_nil, build_log]
      def typeset(body)
        Dir.mktmpdir('review-ast-dvi') do |dir|
          # sty files must be visible to (u)platex
          Dir.glob(File.join(@sty_dir, '*.{cls,sty,fd}')).each { |f| FileUtils.cp(f, dir) }
          # book assets (images with .xbb) referenced by //image etc.
          FileUtils.cp_r(@assets_dir, File.join(dir, 'images')) if @assets_dir
          tex = "#{@preamble}\\begin{document}\n#{body}\n\\end{document}\n"
          File.write(File.join(dir, 'doc.tex'), tex)

          log = +''
          2.times do # two passes so intra-document references resolve
            out, = Open3.capture2e(
              { 'TEXINPUTS' => "#{dir}:" },
              @texcommand, '-interaction=nonstopmode', '-halt-on-error',
              "-output-comment=#{OUTPUT_COMMENT}", 'doc.tex', chdir: dir
            )
            log = out
          end

          dvi = File.join(dir, 'doc.dvi')
          return [nil, log] unless File.exist?(dvi)

          dump, = Open3.capture2('python3', DVIASM, dvi)
          [strip_nondeterminism(dump), log]
        end
      end

      # Compare two LaTeX bodies at the DVI level.
      # @return [Result]
      def compare(body_a, body_b)
        dump_a, = typeset(body_a)
        dump_b, = typeset(body_b)

        if dump_a.nil? || dump_b.nil?
          status = if dump_a.nil? && dump_b.nil? then :build_error_both
                   elsif dump_a.nil? then :build_error_a
                   else
                     :build_error_b
                   end
          return Result.new(identical: false, status: status, pages: nil, diff: nil)
        end

        if dump_a == dump_b
          Result.new(identical: true, status: :equal, pages: page_count(dump_a), diff: nil)
        else
          Result.new(identical: false, status: :differ, pages: page_count(dump_a),
                     diff: unified_diff(dump_a, dump_b))
        end
      end

      private

      def strip_nondeterminism(dump)
        dump.to_s.lines.reject { |l| l.start_with?('comment:') }.join
      end

      def page_count(dump)
        dump.scan(/^\[page /).size
      end

      # Small dependency-free unified-ish diff (only the changed lines).
      def unified_diff(a, b)
        al = a.lines
        bl = b.lines
        i = 0
        i += 1 while i < al.size && i < bl.size && al[i] == bl[i]
        # trim common suffix
        j = 0
        j += 1 while j < (al.size - i) && j < (bl.size - i) && al[-1 - j] == bl[-1 - j]
        removed = al[i...(al.size - j)]
        added = bl[i...(bl.size - j)]
        context_page = al[0...i].reverse.find { |l| l.start_with?('[page ') }
        {
          first_diff_line: i + 1,
          page: context_page&.strip,
          removed: removed.first(20),
          added: added.first(20),
          removed_count: removed.size,
          added_count: added.size
        }
      end
    end
  end
end
