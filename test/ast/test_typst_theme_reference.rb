# frozen_string_literal: true

require_relative '../test_helper'
require 'review/renderer/typst/theme_reference'

class TypstThemeReferenceTest < Test::Unit::TestCase
  ThemeReference = ReVIEW::Renderer::Typst::ThemeReference

  def expression(typst_config)
    @warnings = []
    ThemeReference.new(typst_config, warn: ->(m) { @warnings << m }).expression.to_s
  end

  def test_no_crop_is_the_plain_theme
    assert_equal 'theme', expression({})
    assert_empty(@warnings)
  end

  def test_crop_wraps_the_theme
    assert_equal 'book.with-crop(theme, true)', expression('crop' => true)
    assert_equal 'book.with-crop(theme, false)', expression('crop' => false)
  end

  def test_nikko_pc_hidden_folio_is_passed_with_crop
    assert_equal 'book.with-crop(theme, true, hiddenfolio: "nikko-pc")',
                 expression('crop' => true, 'hiddenfolio' => 'nikko-pc')
    assert_empty(@warnings)
  end

  def test_shippo_is_an_accepted_alias
    assert_include(expression('crop' => true, 'hiddenfolio' => 'shippo'),
                   'hiddenfolio: "shippo"')
  end

  def test_an_unknown_preset_warns_and_is_dropped
    result = expression('crop' => true, 'hiddenfolio' => 'acme')

    assert_equal 'book.with-crop(theme, true)', result
    assert_true(@warnings.any? { |m| m.include?('acme') })
  end

  # The hidden folio lives in the bleed, which only exists with crop marks.
  def test_hidden_folio_without_crop_warns_and_is_ignored
    result = expression('hiddenfolio' => 'nikko-pc')

    assert_equal 'theme', result
    assert_true(@warnings.any? { |m| m.include?('crop') })
  end
end
