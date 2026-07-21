# frozen_string_literal: true

$LOAD_PATH.unshift(File.realpath('../../lib', __dir__))

require 'test/unit'
require 'review/ast/command/vivliostyle_maker'

# What the maker itself decides: which documents print does not want, and which
# file the cover actually is. Carrying that out belongs to EpubPublication and
# is tested there, so a recorder stands in for it here.
class VivliostyleMakerTest < Test::Unit::TestCase
  class PublicationRecorder
    attr_reader :dropped_from_spine, :dropped_from_toc

    def initialize
      @dropped_from_spine = []
      @dropped_from_toc = []
    end

    def remove_from_spine(hrefs)
      @dropped_from_spine.concat(hrefs)
    end

    def remove_from_toc(hrefs)
      @dropped_from_toc.concat(hrefs)
    end
  end

  def setup
    @maker = ReVIEW::AST::Command::VivliostyleMaker.new
    @publication = PublicationRecorder.new
  end

  # The maker reads @config directly; a Hash carries every key these paths use.
  def apply(vconfig, config = {})
    @maker.instance_variable_set(:@config,
                                 { 'bookname' => 'book', 'htmlext' => 'xhtml' }.merge(config))
    @maker.send(:apply_frontmatter_overrides, @publication,
                ReVIEW::AST::VivliostyleConfig.new(vconfig))
    @publication
  end

  def test_keeps_the_frontmatter_by_default
    apply({})

    assert_empty(@publication.dropped_from_spine)
    assert_empty(@publication.dropped_from_toc)
  end

  def test_cover_false_drops_the_cover_from_spine_and_toc
    apply('cover' => false)

    assert_equal ['book.xhtml'], @publication.dropped_from_spine
    assert_equal ['book.xhtml'], @publication.dropped_from_toc
  end

  # config.yml's cover: names the file. Assuming "<bookname>.<htmlext>" would
  # match nothing and leave the cover in place without saying so.
  def test_cover_false_honors_a_configured_cover_name
    apply({ 'cover' => false }, 'cover' => 'mycover.xhtml')

    assert_equal ['mycover.xhtml'], @publication.dropped_from_spine
  end

  def test_cover_false_uses_only_the_basename_of_a_configured_path
    apply({ 'cover' => false }, 'cover' => 'OEBPS/mycover.xhtml')

    assert_equal ['mycover.xhtml'], @publication.dropped_from_spine
  end

  # The title page stays in the reading order; only its navigation entry goes.
  def test_toc_titlepage_false_touches_the_toc_only
    apply('toc_titlepage' => false)

    assert_empty(@publication.dropped_from_spine)
    assert_equal ['titlepage.xhtml'], @publication.dropped_from_toc
  end
end
