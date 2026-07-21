# frozen_string_literal: true

$LOAD_PATH.unshift(File.realpath('../../lib', __dir__))

require 'test/unit'
require 'fileutils'
require 'tmpdir'
require 'rexml/document'
require 'zip'
require 'review/ast/command/vivliostyle_maker'

# The parts of VivliostyleMaker that shape the publication before it is handed
# to the renderer: unpacking the EPUB and dropping front matter print does not
# want. Driving the renderer itself needs a browser, so it stays out of here.
class VivliostyleMakerTest < Test::Unit::TestCase
  OPF = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <manifest>
        <item id="cover" href="book.xhtml" media-type="application/xhtml+xml"/>
        <item id="titlepage" href="titlepage.xhtml" media-type="application/xhtml+xml"/>
        <item id="ch01" href="ch01.xhtml" media-type="application/xhtml+xml"/>
        <item id="nav" href="book-toc.xhtml" properties="nav" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="cover"/>
        <itemref idref="titlepage"/>
        <itemref idref="ch01"/>
      </spine>
    </package>
  XML

  NAV = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
      <body>
        <nav epub:type="toc" xmlns:epub="http://www.idpf.org/2007/ops">
          <ol>
            <li><a href="book.xhtml">Cover</a></li>
            <li><a href="titlepage.xhtml">Title</a></li>
            <li><a href="ch01.xhtml">Chapter</a></li>
          </ol>
        </nav>
      </body>
    </html>
  XML

  def setup
    @dir = Dir.mktmpdir('vivliostyle')
    @maker = ReVIEW::AST::Command::VivliostyleMaker.new
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # The maker reads @config directly; a Hash carries every key these paths use.
  def config(**overrides)
    { 'bookname' => 'book', 'htmlext' => 'xhtml' }.merge(overrides)
  end

  def publication
    File.write(File.join(@dir, 'book.opf'), OPF)
    File.write(File.join(@dir, 'book-toc.xhtml'), NAV)
    File.join(@dir, 'book.opf')
  end

  def apply(vconfig, config_overrides = {})
    @maker.instance_variable_set(:@config, config(**config_overrides))
    opf = publication
    @maker.send(:apply_frontmatter_overrides, opf, vconfig)
    [File.read(opf), File.read(File.join(@dir, 'book-toc.xhtml'))]
  end

  def spine_refs(opf_source)
    REXML::XPath.match(REXML::Document.new(opf_source), "//*[local-name()='itemref']").
      map { |ref| ref.attributes['idref'] }
  end

  def toc_links(nav_source)
    REXML::XPath.match(REXML::Document.new(nav_source), "//*[local-name()='a']").
      map { |anchor| anchor.attributes['href'] }
  end

  def test_leaves_the_publication_alone_by_default
    opf, nav = apply({})

    assert_equal %w[cover titlepage ch01], spine_refs(opf)
    assert_equal %w[book.xhtml titlepage.xhtml ch01.xhtml], toc_links(nav)
  end

  def test_cover_false_drops_the_cover_from_spine_and_toc
    opf, nav = apply('cover' => false)

    assert_equal %w[titlepage ch01], spine_refs(opf)
    assert_equal %w[titlepage.xhtml ch01.xhtml], toc_links(nav)
  end

  # config.yml's cover: names the file. Assuming "<bookname>.<htmlext>" would
  # match nothing here and drop the cover silently.
  def test_cover_false_honors_a_configured_cover_name
    File.write(File.join(@dir, 'book.opf'), OPF.sub('book.xhtml', 'mycover.xhtml'))
    File.write(File.join(@dir, 'book-toc.xhtml'), NAV.sub('book.xhtml', 'mycover.xhtml'))
    @maker.instance_variable_set(:@config, config('cover' => 'mycover.xhtml'))
    opf_path = File.join(@dir, 'book.opf')

    @maker.send(:apply_frontmatter_overrides, opf_path, 'cover' => false)

    assert_equal %w[titlepage ch01], spine_refs(File.read(opf_path))
    assert_equal %w[titlepage.xhtml ch01.xhtml],
                 toc_links(File.read(File.join(@dir, 'book-toc.xhtml')))
  end

  def test_toc_titlepage_false_keeps_the_page_but_drops_its_toc_entry
    opf, nav = apply('toc_titlepage' => false)

    assert_equal %w[cover titlepage ch01], spine_refs(opf)
    assert_equal %w[book.xhtml ch01.xhtml], toc_links(nav)
  end

  def test_extract_epub_unpacks_every_entry
    epub = File.join(@dir, 'book.epub')
    Zip::File.open(epub, create: true) do |zip|
      zip.get_output_stream('mimetype') { |io| io.write('application/epub+zip') }
      zip.get_output_stream('OEBPS/ch01.xhtml') { |io| io.write('<html/>') }
    end
    workdir = File.join(@dir, 'work')

    @maker.send(:extract_epub, epub, workdir)

    assert_equal 'application/epub+zip', File.read(File.join(workdir, 'mimetype'))
    assert_equal '<html/>', File.read(File.join(workdir, 'OEBPS', 'ch01.xhtml'))
  end

  def test_extract_epub_refuses_entries_pointing_outside_the_workdir
    epub = File.join(@dir, 'evil.epub')
    Zip::File.open(epub, create: true) do |zip|
      zip.get_output_stream('ok.txt') { |io| io.write('ok') }
      zip.get_output_stream('../escaped.txt') { |io| io.write('escaped') }
    end
    workdir = File.join(@dir, 'work')

    @maker.send(:extract_epub, epub, workdir)

    assert_path_exist(File.join(workdir, 'ok.txt'))
    assert_path_not_exist(File.join(@dir, 'escaped.txt'))
  end
end
