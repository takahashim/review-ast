# frozen_string_literal: true

require_relative '../test_helper'
require 'review/ast/command/typst_maker'

# review-book is a Typst package (typst.toml) as well as a directory the gem
# copies into a build. These pin the manifest to the things it must agree with,
# since Ruby has no TOML parser to catch drift for us.
class TypstPackageTest < Test::Unit::TestCase
  LIBRARY = File.expand_path('../../templates/typst/review-book', __dir__)
  MANIFEST = File.read(File.join(LIBRARY, 'typst.toml'))

  def manifest(key)
    MANIFEST[/^#{Regexp.escape(key)}\s*=\s*"([^"]*)"/, 1]
  end

  def test_the_entrypoint_exists
    entrypoint = manifest('entrypoint')
    assert_equal 'lib.typ', entrypoint
    assert_path_exist(File.join(LIBRARY, entrypoint))
  end

  # lib.typ carries its own `version`; the two must not drift.
  def test_the_version_matches_lib_typ
    lib_version = File.read(File.join(LIBRARY, 'lib.typ'))[/#let version = "([^"]+)"/, 1]

    assert_equal lib_version, manifest('version'),
                 'typst.toml version and lib.typ version disagree'
  end

  # The manifest's minimum compiler must match the floor the maker enforces.
  def test_the_compiler_floor_matches_the_maker
    floor = ReVIEW::AST::Command::TypstMaker::SUPPORTED_TYPST.to_s

    assert_equal floor, manifest('compiler'),
                 'typst.toml compiler and TypstMaker::SUPPORTED_TYPST disagree'
  end
end
