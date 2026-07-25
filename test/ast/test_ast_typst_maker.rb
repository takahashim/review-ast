# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

# End-to-end: .re -> AST -> Typst -> PDF.
#
# The renderer's unit tests check what it emits; this checks that what it emits
# is something Typst accepts. Without it a change to the library or to the
# generated call shape would only be caught by building a book by hand.
class TestAstTypstMaker < Test::Unit::TestCase
  BIN = File.expand_path('../../bin/review-ast-typstmaker', __dir__)

  def setup
    omit('typst command not found') unless system('typst', '--version', out: File::NULL, err: File::NULL)
  end

  def test_builds_a_pdf_from_a_book
    Dir.mktmpdir do |dir|
      write_book(dir)

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      pdf = File.join(dir, 'book-typst.pdf')

      assert(File.exist?(pdf), "typstmaker did not produce a PDF:\n#{output}")
      assert(File.size(pdf) > 1000, 'the PDF is suspiciously small')
    end
  end

  # A failed Typst compile must keep the generated sources, since the reported
  # position refers to them (doc/design-typst.md).
  def test_keep_workdir_retains_the_generated_sources
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")

      IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert(File.exist?(File.join(dir, 'book-typst', 'book.typ')))
      assert(File.exist?(File.join(dir, 'book-typst', 'chapters', 'ch01.typ')))
      assert(File.exist?(File.join(dir, 'book-typst', 'lib', 'review-book', 'lib.typ')))
    end
  end

  # toclevel decides how deep the table of contents goes, and both EPUB and the
  # LaTeX path honour it. Leaving it to the theme would give one manuscript a
  # different table of contents per format.
  def test_toclevel_sets_the_table_of_contents_depth
    Dir.mktmpdir do |dir|
      # 4, not the theme's own default of 2: the assertion has to fail if the
      # depth stops coming from the book's configuration.
      write_book(dir, extra_config: "toc: true\ntoclevel: 4\ntypst:\n  keep_workdir: true\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      root = File.read(File.join(dir, 'book-typst', 'book.typ'))

      assert_match(/#review\.toc\([^)]*depth: 4\)/, root, output)
    end
  end

  # serial_pagination / startpage reach the generated root (they mirror
  # review-jsbook's class options; doc/design-hanmen §4.4). The default is
  # roman front matter restarting at arabic 1, which the .with() args flip.
  def test_serial_pagination_reaches_the_generated_root
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n  serial_pagination: true\n  startpage: 3\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      root = File.read(File.join(dir, 'book-typst', 'book.typ'))

      assert_include(root, '#show: book.frontmatter.with(serial: true, start: 3)', output)
      assert_include(root, '#show: book.mainmatter.with(serial: true)', output)
    end
  end

  def test_default_pagination_is_roman_front_matter_from_page_one
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")

      IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      root = File.read(File.join(dir, 'book-typst', 'book.typ'))

      assert_include(root, '#show: book.frontmatter.with(serial: false, start: 1)')
      assert_include(root, '#show: book.mainmatter.with(serial: false)')
    end
  end

  # The hidden folio (隠しノンブル) the printer reads to collate signatures;
  # it rides with the crop marks, so the theme reference carries the preset.
  def test_nikko_pc_hidden_folio_reaches_the_generated_root
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n  crop: true\n  hiddenfolio: nikko-pc\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      root = File.read(File.join(dir, 'book-typst', 'book.typ'))

      assert(Dir[File.join(dir, '*-typst.pdf')].any?, output)
      assert_include(root, 'book.with-crop(theme, true, hiddenfolio: "nikko-pc")', output)
    end
  end

  # The book furniture the other makers get from a LaTeX class or the EPUB
  # pipeline is generated here instead, so its absence would be silent.
  def test_builds_front_and_back_matter
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "toc: true\ncolophon: true\npbl: 出版社\ndate: 2026-07-20\ntypst:\n  keep_workdir: true\n  index: true\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      root = File.read(File.join(dir, 'book-typst', 'book.typ'))

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      assert_include(root, '#review.titlepage(')
      assert_include(root, '#review.toc(')
      assert_include(root, '#review.print-index(')
      assert_include(root, '#review.colophon(')
      assert_include(root, '発行所')
    end
  end

  # A theme may restyle an element, but the structure around it -- heading
  # level, outline entry, label -- is applied by book.* and stays put.
  def test_theme_renderer_overrides_the_heading_layout
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")
      # The heading renderer styles the heading element; it does not compose the
      # body, because Typst reads that body for the PDF/UA tag tree.
      File.write(File.join(dir, 'theme.typ'), <<~THEME)
        #import "/lib/review-book/theme.typ": default-theme, merge-theme
        #let my-heading(it, theme) = block(above: 2em, [OVERRIDDEN #it.body])
        #let theme = merge-theme(default-theme, (
          renderers: (heading: my-heading),
        ))
      THEME

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
      pdf = File.join(dir, 'book-typst.pdf')
      assert(File.exist?(pdf), output)

      text = IO.popen(['pdftotext', pdf, '-'], &:read)
      assert_include(text, 'OVERRIDDEN')
    end
  end

  # A press file is larger than the book: the sheet carries the finished page
  # plus bleed plus the marks that say where to cut.
  def test_crop_marks_enlarge_the_sheet_around_the_trim_size
    Dir.mktmpdir do |dir|
      write_book(dir)
      plain = page_size_mm(build(dir))

      write_book(dir, extra_config: "typst:\n  crop: true\n")
      cropped = page_size_mm(build(dir))

      # Default bleed 3mm + marks 10mm on each of the four sides.
      assert_in_delta(plain[0] + 26, cropped[0], 0.5)
      assert_in_delta(plain[1] + 26, cropped[1], 0.5)
    end
  end

  # Registration black is CMYK, and Typst has no CMYK profile to satisfy a
  # conformance mode with, so the two would otherwise be mutually exclusive.
  def test_crop_marks_and_a_pdf_standard_can_be_combined
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  crop: true\n  pdf_standard: a-2b\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      assert_include(output, 'registration black')
    end
  end

  # A Typst error names the generated file; the author needs the manuscript.
  def test_typst_errors_are_traced_back_to_the_manuscript
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")
      File.write(File.join(dir, 'ch01.re'), <<~RE)
        = 章

        一つ目の段落。

        //embed[typst]{
        #this-function-does-not-exist()
        //}
      RE

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert_include(output, 'unknown variable')
      # The //embed block starts on line 5 of the manuscript.
      assert_match(%r{chapters/ch01\.typ:\d+:\d+\s+<- ch01\.re:5}, output,
                   "the diagnostic should name the manuscript position:\n#{output}")
      assert(File.exist?(File.join(dir, 'book-typst', 'source-map.json')))
    end
  end

  # //texequation and @<m> carry LaTeX, which Typst's own math syntax does not
  # accept; the mitex adapter is what bridges them.
  #
  # Guarded on the package cache rather than the network: fetching from the
  # registry during a test would make the suite depend on a remote service, and
  # a version that is not cached cannot be exercised anyway.
  def test_mitex_renders_latex_math
    version = File.read(File.expand_path('../../templates/typst/review-book/math-mitex.typ', __dir__))[
      %r{@preview/mitex:([\d.]+)}, 1
    ]
    cached = ['~/Library/Caches/typst/packages/preview/mitex',
              '~/.cache/typst/packages/preview/mitex'].
             any? { |d| File.directory?(File.join(File.expand_path(d), version.to_s)) }
    omit("mitex #{version} is not in the Typst package cache") unless cached

    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  math: mitex\n  keep_workdir: true\n")
      # A "}" inside an inline argument has to be escaped in Re:VIEW, or the
      # argument ends there; block equations are not parsed that way.
      File.write(File.join(dir, 'ch01.re'), <<~RE)
        = 数式

        インライン @<m>{x = \\frac{a\\}{b\\}} です。

        //texequation[sum][総和]{
        \\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}
        //}
      RE

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      chapter = File.read(File.join(dir, 'book-typst', 'chapters', 'ch01.typ'))
      assert_include(chapter, 'latex: "x = \\\\frac{a}{b}"')
      assert_include(File.read(File.join(dir, 'book-typst', 'lib', 'review-book', 'math.typ')), 'mitex')
    end
  end

  # //graph runs an external generator, so its image only exists once the
  # chapter has been rendered. Guarded on graphviz rather than the network,
  # for the same reason as the mitex test.
  def test_graph_image_is_generated_and_reaches_the_build
    omit('graphviz (dot) is not installed') unless system('dot', '-V', out: File::NULL, err: File::NULL)

    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")
      File.write(File.join(dir, 'ch01.re'), <<~RE)
        = グラフ

        図@<img>{flow}を参照します。

        //graph[flow][graphviz][処理の流れ]{
        digraph flow { rankdir=LR; a -> b; }
        //}
      RE

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      # The generated image has to be inside the Typst project root, or the
      # compile cannot read it.
      assert(File.exist?(File.join(dir, 'book-typst', 'images', 'typst', 'flow.svg')),
             "the //graph image did not reach the build directory:\n#{output}")
      chapter = File.read(File.join(dir, 'book-typst', 'chapters', 'ch01.typ'))
      assert_include(chapter, 'path: "/images/typst/flow.svg"')
    end
  end

  # PDF/A and PDF/UA are checked by Typst at export time, and then by veraPDF
  # against the actual file. Typst's own check is the one that catches the
  # mistakes this renderer can make -- a heading whose title cannot be resolved,
  # an image with no alt text -- so it runs even where veraPDF is absent.
  def test_pdf_a_and_ua_export
    %w[a-2b ua-1].each do |standard|
      Dir.mktmpdir do |dir|
        write_book(dir, extra_config: "typst:\n  pdf_standard: #{standard}\n")
        output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
        pdf = File.join(dir, 'book-typst.pdf')
        assert(File.exist?(pdf), "#{standard} export failed:\n#{output}")

        next unless system('verapdf', '--version', out: File::NULL, err: File::NULL)

        flavour = standard == 'a-2b' ? '2b' : 'ua1'
        report = IO.popen(['verapdf', '-f', flavour, '--format', 'text', pdf], err: %i[child out], &:read)
        assert_match(/^PASS /, report, "veraPDF rejected the #{standard} output:\n#{report}")
      end
    end
  end

  # An image needs alt text under PDF/UA. Re:VIEW has no alt syntax, so the
  # caption is what describes the image -- the same text HtmlRenderer puts in
  # the alt attribute.
  def test_image_alt_text_comes_from_the_caption
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")
      FileUtils.mkdir_p(File.join(dir, 'images', 'typst'))
      File.write(File.join(dir, 'images', 'typst', 'fig1.svg'),
                 '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"></svg>')
      File.write(File.join(dir, 'ch01.re'), "= 章\n\n//image[fig1][図の説明]{\n//}\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      chapter = File.read(File.join(dir, 'book-typst', 'chapters', 'ch01.typ'))
      # Also proves images/<builder>/ is searched: without the builder name the
      # path would not resolve and the figure would render as missing.
      assert_include(chapter, 'path: "/images/typst/fig1.svg"')
      assert_include(chapter, 'alt: "図の説明"')
    end
  end

  # A part named only in catalog.yml has no .re file to compile, so its page is
  # written straight from the catalog. That path runs nowhere else, which is how
  # it survived a namespace move with an unqualified constant in it.
  def test_part_without_a_source_file_is_generated
    Dir.mktmpdir do |dir|
      write_book(dir, extra_config: "typst:\n  keep_workdir: true\n")
      File.write(File.join(dir, 'catalog.yml'), <<~YAML)
        CHAPS:
          - ch01.re
          - 第I部:
            - ch02.re
      YAML
      File.write(File.join(dir, 'ch02.re'), "= 第二章\n\n本文。\n")

      output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)

      assert(File.exist?(File.join(dir, 'book-typst.pdf')), output)
      part = Dir[File.join(dir, 'book-typst', 'chapters', 'part-*.typ')].first
      assert_not_nil(part, "no part page was generated:\n#{output}")
      assert_include(File.read(part), '#review.part(')
      assert_include(File.read(part), 'title: [第I部]')
    end
  end

  private

  def build(dir)
    output = IO.popen([BIN, File.join(dir, 'config.yml'), { err: %i[child out] }], &:read)
    pdf = File.join(dir, 'book-typst.pdf')
    assert(File.exist?(pdf), output)
    pdf
  end

  # Page size in millimetres, read back from the PDF.
  def page_size_mm(pdf)
    info = IO.popen(['pdfinfo', pdf], &:read)
    omit('pdfinfo not available') unless info =~ /Page size:\s+([\d.]+) x ([\d.]+)/

    [Regexp.last_match(1).to_f * 25.4 / 72, Regexp.last_match(2).to_f * 25.4 / 72]
  end

  def write_book(dir, extra_config: '')
    File.write(File.join(dir, 'config.yml'), <<~YAML + extra_config)
      bookname: book
      booktitle: テスト書籍
      aut: [著者]
      language: ja
    YAML

    File.write(File.join(dir, 'catalog.yml'), <<~YAML)
      CHAPS:
        - ch01.re
    YAML

    File.write(File.join(dir, 'ch01.re'), <<~RE)
      = はじめに

      本文です。@<b>{太字}と@<code>{コード}、脚注@<fn>{f1}つき。

      //footnote[f1][脚注の本文]

      == 節

      //list[hello][Hello][ruby]{
      puts "hello"
      //}

      @<list>{hello}を参照します。

      //table[t1][比較]{
      A	B
      -------------
      1	2
      //}

      //note[注意]{
      注意の中身。
      //}

       * 箇条書き
       * 二つ目
    RE
  end
end
