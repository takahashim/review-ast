# frozen_string_literal: true

$LOAD_PATH.unshift(File.realpath('../../lib', __dir__))

require 'test/unit'
require 'fileutils'
require 'tmpdir'
require 'rexml/document'
require 'zip'
require 'review/ast/epub_publication'

class EpubPublicationTest < Test::Unit::TestCase
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
    @dir = Dir.mktmpdir('publication')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # An EPUB carrying the documents above, plus whatever +extra+ adds.
  def epub(name = 'book.epub', opf: OPF, nav: NAV)
    path = File.join(@dir, name)
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream('mimetype') { |io| io.write('application/epub+zip') }
      zip.get_output_stream('OEBPS/book.opf') { |io| io.write(opf) }
      zip.get_output_stream('OEBPS/book-toc.xhtml') { |io| io.write(nav) }
      zip.get_output_stream('OEBPS/ch01.xhtml') { |io| io.write('<html/>') }
      yield zip if block_given?
    end
    path
  end

  def extract(path = epub)
    ReVIEW::AST::EpubPublication.extract(path, File.join(@dir, 'work'))
  end

  def spine_refs(publication)
    doc = REXML::Document.new(File.read(publication.opf))
    REXML::XPath.match(doc, "//*[local-name()='itemref']").map { |ref| ref.attributes['idref'] }
  end

  def toc_links(publication)
    doc = REXML::Document.new(File.read(publication.nav))
    REXML::XPath.match(doc, "//*[local-name()='a']").map { |anchor| anchor.attributes['href'] }
  end

  def test_extract_unpacks_every_entry_and_finds_the_opf
    publication = extract

    assert_equal File.join(@dir, 'work', 'OEBPS', 'book.opf'), publication.opf
    assert_equal 'application/epub+zip', File.read(File.join(publication.root, 'mimetype'))
    assert_equal '<html/>', File.read(File.join(publication.root, 'OEBPS', 'ch01.xhtml'))
  end

  def test_extract_replaces_an_earlier_tree
    workdir = File.join(@dir, 'work')
    FileUtils.mkdir_p(workdir)
    File.write(File.join(workdir, 'stale.txt'), 'old')

    extract

    assert_path_not_exist(File.join(workdir, 'stale.txt'))
  end

  def test_extract_refuses_entries_pointing_outside_the_root
    path = epub('evil.epub') do |zip|
      zip.get_output_stream('../escaped.txt') { |io| io.write('escaped') }
    end

    publication = extract(path)

    assert_path_exist(File.join(publication.root, 'OEBPS', 'ch01.xhtml'))
    assert_path_not_exist(File.join(@dir, 'escaped.txt'))
  end

  def test_extract_without_an_opf_is_an_error
    path = File.join(@dir, 'bare.epub')
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream('mimetype') { |io| io.write('application/epub+zip') }
    end

    error = assert_raise(ReVIEW::AST::EpubPublication::Error) { extract(path) }
    assert_match(/OPF not found/, error.message)
  end

  def manifest_ids(publication)
    doc = REXML::Document.new(File.read(publication.opf))
    REXML::XPath.match(doc, "//*[local-name()='item']").map { |item| item.attributes['id'] }
  end

  # A dangling manifest entry is harmless, and keeping it avoids breaking
  # references from elsewhere in the publication.
  def test_remove_from_spine_drops_the_itemref_and_keeps_the_manifest_item
    publication = extract

    publication.remove_from_spine(['book.xhtml'])

    assert_equal %w[titlepage ch01], spine_refs(publication)
    assert_include(manifest_ids(publication), 'cover')
  end

  def test_remove_from_toc_drops_the_list_item
    publication = extract

    publication.remove_from_toc(['titlepage.xhtml'])

    assert_equal %w[book.xhtml ch01.xhtml], toc_links(publication)
  end

  def test_removing_nothing_leaves_the_publication_alone
    publication = extract
    before = File.read(publication.opf)

    publication.remove_from_spine([])
    publication.remove_from_toc([])

    assert_equal before, File.read(publication.opf)
    assert_equal %w[cover titlepage ch01], spine_refs(publication)
  end

  def test_nav_is_nil_when_the_package_declares_none
    without_nav = OPF.sub(' properties="nav"', '')
    publication = extract(epub('nonav.epub', opf: without_nav))

    assert_nil(publication.nav)
    assert_nothing_raised { publication.remove_from_toc(['book.xhtml']) }
  end

  def test_discard_removes_the_tree
    publication = extract

    publication.discard

    assert_path_not_exist(publication.root)
  end
end
