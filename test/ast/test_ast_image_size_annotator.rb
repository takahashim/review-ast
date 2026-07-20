# frozen_string_literal: true

$LOAD_PATH.unshift(File.realpath('../../lib', __dir__))

require 'test/unit'
require 'fileutils'
require 'tmpdir'
require 'zlib'
require 'review/ast/image_size_annotator'
require 'review/ast/intrinsic_size'

# Builds real PNG/JPEG bytes so the readers are exercised end to end rather
# than against stubs.
module ImageFixtures
  module_function

  def png(path, width:, height:, dpi: nil)
    chunks = [chunk('IHDR', [width, height, 8, 2, 0, 0, 0].pack('N2C5'))]
    if dpi
      per_metre = (dpi / 0.0254).round
      chunks << chunk('pHYs', [per_metre, per_metre, 1].pack('N2C'))
    end
    chunks << chunk('IDAT', Zlib::Deflate.deflate("\0"))
    chunks << chunk('IEND', '')
    File.binwrite(path, "\x89PNG\r\n\x1a\n".b + chunks.join)
  end

  def chunk(type, body)
    [body.bytesize].pack('N') + type + body + [Zlib.crc32(type + body)].pack('N')
  end

  # Minimal JFIF: SOI, APP0 with density, SOF0 with the dimensions, EOI.
  def jpeg(path, width:, height:, dpi: nil)
    units, density = dpi ? [1, dpi] : [0, 0]
    app0 = "\xFF\xE0".b + [16].pack('n') + "JFIF\0".b +
           [1, 1, units, density, density, 0, 0].pack('C3n2C2')
    sof0 = "\xFF\xC0".b + [11].pack('n') + [8, height, width, 1, 1, 0x11, 0].pack('Cn2C4')
    File.binwrite(path, "\xFF\xD8".b + app0 + sof0 + "\xFF\xD9".b)
  end
end

class ImageSizeAnnotatorTest < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir('annotator')
    FileUtils.mkdir_p(File.join(@dir, 'images'))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def image(name, **opts)
    path = File.join(@dir, 'images', name)
    name.end_with?('.jpg') ? ImageFixtures.jpeg(path, **opts) : ImageFixtures.png(path, **opts)
    "images/#{name}"
  end

  def annotate(markup)
    ReVIEW::AST::ImageSizeAnnotator.new(@dir).annotate_source(markup, @dir)
  end

  def test_uses_the_embedded_resolution
    src = image('shot.png', width: 600, height: 400, dpi: 300)

    # 600px / 300dpi = 2in = 50.8mm
    assert_equal %Q(<img src="#{src}" style="--natural: 50.800mm" />),
                 annotate(%Q(<img src="#{src}" />))
  end

  def test_falls_back_to_72dpi_like_dvipdfmx
    src = image('plain.png', width: 144, height: 100)

    # 144px / 72dpi = 2in = 50.8mm
    assert_equal %Q(<img src="#{src}" style="--natural: 50.800mm" />),
                 annotate(%Q(<img src="#{src}" />))
  end

  def test_reads_jpeg_density
    src = image('photo.jpg', width: 600, height: 400, dpi: 150)

    # 600px / 150dpi = 4in = 101.6mm
    assert_equal %Q(<img src="#{src}" style="--natural: 101.600mm" />),
                 annotate(%Q(<img src="#{src}" />))
  end

  def test_keeps_other_attributes_and_annotates_each_image
    a = image('a.png', width: 144, height: 100)
    b = image('b.png', width: 288, height: 100)
    markup = %Q(<p><img src="#{a}" alt="x" class="width-050per" /><img src="#{b}" /></p>)

    result = annotate(markup)

    assert_include(result, %Q(alt="x" class="width-050per" style="--natural: 50.800mm"))
    assert_include(result, %Q(<img src="#{b}" style="--natural: 101.600mm" />))
  end

  def test_leaves_alone_what_it_cannot_measure
    [
      '<img src="https://example.com/remote.png" />',
      '<img src="" />',
      '<img alt="no-src" />'
    ].each do |markup|
      tag = markup.tr('\\', '').gsub('\ ', ' ')
      assert_equal tag, annotate(tag)
    end

    File.binwrite(File.join(@dir, 'images', 'broken.png'), 'not an image')
    tag = %Q(<img src="images/broken.png" />)
    assert_equal tag, annotate(tag)
  end

  def test_is_idempotent
    src = image('shot.png', width: 600, height: 400, dpi: 300)
    once = annotate(%Q(<img src="#{src}" />))

    assert_equal once, annotate(once)
  end

  def test_annotate_walks_documents_and_reports_changes
    src = image('shot.png', width: 600, height: 400, dpi: 300)
    File.write(File.join(@dir, 'chapter.xhtml'), %Q(<img src="#{src}" />))
    File.write(File.join(@dir, 'plain.xhtml'), '<p>no images</p>')

    assert_equal 1, ReVIEW::AST::ImageSizeAnnotator.new(@dir).annotate
    assert_include(File.read(File.join(@dir, 'chapter.xhtml')), '--natural: 50.800mm')
  end

  def test_property_name_is_configurable
    src = image('shot.png', width: 600, height: 400, dpi: 300)
    annotator = ReVIEW::AST::ImageSizeAnnotator.new(@dir, property: '--intrinsic')

    assert_include(annotator.annotate_source(%Q(<img src="#{src}" />), @dir),
                   'style="--intrinsic: 50.800mm"')
  end
end

class IntrinsicSizeTest < Test::Unit::TestCase
  def setup
    @dir = Dir.mktmpdir('intrinsic')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def path(name)
    File.join(@dir, name)
  end

  def test_png_pixel_dimensions_and_dpi
    ImageFixtures.png(path('a.png'), width: 1384, height: 708, dpi: 150)
    size = ReVIEW::AST::IntrinsicSize.of(path('a.png'))

    assert_equal 1384, size.width_px
    assert_equal 708, size.height_px
    # pHYs stores pixels per metre as an integer, so the dpi only round-trips
    # to within a fiftieth -- real files carry the same rounding.
    assert_in_delta(150.0, size.dpi, 0.02)
    assert_in_delta(234.35, size.width_mm, 0.05)
  end

  # A pHYs unit other than 1 states an aspect ratio, not a physical size.
  def test_png_without_physical_unit_falls_back
    body = [1000, 1000, 0].pack('N2C')
    chunks = [ImageFixtures.chunk('IHDR', [144, 100, 8, 2, 0, 0, 0].pack('N2C5')),
              ImageFixtures.chunk('pHYs', body),
              ImageFixtures.chunk('IEND', '')]
    File.binwrite(path('ratio.png'), "\x89PNG\r\n\x1a\n".b + chunks.join)

    assert_in_delta(72.0, ReVIEW::AST::IntrinsicSize.of(path('ratio.png')).dpi, 0.01)
  end

  def test_unknown_and_missing_files
    File.binwrite(path('x.bin'), 'GIF89a-ish but not really')

    assert_nil(ReVIEW::AST::IntrinsicSize.of(path('x.bin')))
    assert_nil(ReVIEW::AST::IntrinsicSize.of(path('nope.png')))
  end
end
