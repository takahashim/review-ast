# frozen_string_literal: true

require_relative '../test_helper'
require 'review/renderer/typst/pagination'

class TypstPaginationTest < Test::Unit::TestCase
  Pagination = ReVIEW::Renderer::Typst::Pagination

  def test_defaults_to_non_serial_from_page_one
    p = Pagination.new({})

    assert_false(p.serial?)
    assert_equal 1, p.start
  end

  def test_reads_serial_pagination_and_start_page
    p = Pagination.new('serial_pagination' => true, 'startpage' => 3)

    assert_true(p.serial?)
    assert_equal 3, p.start
  end

  def test_serial_is_a_boolean_not_the_raw_value
    assert_true(Pagination.new('serial_pagination' => 'yes').serial?)
    assert_false(Pagination.new('serial_pagination' => nil).serial?)
  end

  def test_a_non_integer_start_page_falls_back_to_one
    assert_equal 1, Pagination.new('startpage' => 'oops').start
    assert_equal 5, Pagination.new('startpage' => '5').start
  end
end
