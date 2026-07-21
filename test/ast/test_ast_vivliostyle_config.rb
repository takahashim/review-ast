# frozen_string_literal: true

$LOAD_PATH.unshift(File.realpath('../../lib', __dir__))

require 'test/unit'
require 'review/ast/vivliostyle_config'

class VivliostyleConfigTest < Test::Unit::TestCase
  def config(section = nil)
    ReVIEW::AST::VivliostyleConfig.new(section)
  end

  def test_defaults_apply_to_a_book_with_no_vivliostyle_section
    c = config

    assert_true(c.cover?)
    assert_true(c.toc_titlepage?)
    assert_true(c.image_intrinsic_size?)
    assert_false(c.keep_workdir?)
    assert_equal 'mybook-vivliostyle.pdf', c.output_for('mybook')
    assert_equal({ outline: :toc, metadata: {} }, c.print_options(metadata: {}))
  end

  def test_switches_are_read_from_the_section
    c = config('cover' => false, 'toc_titlepage' => false,
               'image_intrinsic_size' => false, 'keep_workdir' => true)

    assert_false(c.cover?)
    assert_false(c.toc_titlepage?)
    assert_false(c.image_intrinsic_size?)
    assert_true(c.keep_workdir?)
  end

  def test_output_can_be_named
    assert_equal 'print.pdf', config('output' => 'print.pdf').output_for('mybook')
  end

  # Left out entirely rather than passed as nil, so vivlio-pdf's own defaults
  # apply to whatever the book does not set.
  def test_optional_print_options_are_omitted_when_unset
    options = config('outline' => 'headings').print_options(metadata: { title: 't' })

    assert_equal :headings, options[:outline]
    assert_equal({ title: 't' }, options[:metadata])
    assert_false(options.key?(:timeout))
    assert_false(options.key?(:browser_path))
    assert_false(options.key?(:viewer))
  end

  def test_print_options_carry_what_the_book_sets
    options = config('timeout' => 300, 'browser_path' => '/bin/chrome',
                     'viewer_path' => '/opt/viewer').print_options(metadata: {})

    assert_equal 300, options[:timeout]
    assert_equal '/bin/chrome', options[:browser_path]
    assert_equal '/opt/viewer', options[:viewer]
  end
end
