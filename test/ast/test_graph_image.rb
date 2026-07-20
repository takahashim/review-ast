# frozen_string_literal: true

require_relative '../test_helper'
require 'review/renderer/graph_image'
require 'tmpdir'

# GraphImage is the part of //graph that touches the world, split out of the
# renderer so that visit_graph only decides what markup to emit.
#
# The generators shell out to dot/gnuplot/blockdiag, which are not present on
# every machine, so what is checked here is the part that does not need them:
# the path a graph resolves to, and that an unknown generator is a no-op rather
# than an error.
class TestGraphImage < Test::Unit::TestCase
  def build(image_ext: 'eps', imagedir: 'images')
    ReVIEW::Renderer::GraphImage.new(imagedir: imagedir, target_name: 'idgxml', image_ext: image_ext)
  end

  def test_path_uses_the_format_extension
    assert_equal 'images/idgxml/g1.eps', build.file_path('g1')
    assert_equal 'images/idgxml/g1.pdf', build(image_ext: 'pdf').file_path('g1')
  end

  def test_generate_returns_the_same_path_it_would_be_referenced_by
    Dir.mktmpdir do |dir|
      graph = build(imagedir: File.join(dir, 'images'))

      # 'mermaid' is not one of this class's generators: ImgGraph defers those.
      # The path still has to come back so the markup can point at it.
      assert_equal graph.file_path('g1'), graph.generate(id: 'g1', command: 'mermaid', content: 'graph TD;')
    end
  end

  def test_unknown_generator_writes_nothing
    Dir.mktmpdir do |dir|
      graph = build(imagedir: File.join(dir, 'images'))
      path = graph.generate(id: 'g1', command: 'nosuchtool', content: 'x')

      assert_path_not_exist(path)
    end
  end

  # dot is common enough to check when it is there; the assertion is that the
  # file is really EPS, which is what the extension fix was about -- the
  # generator used to be told -Tpdf while the file was named .eps.
  def test_graphviz_writes_the_format_it_names
    omit('graphviz is not installed') unless system('which dot > /dev/null 2>&1')

    Dir.mktmpdir do |dir|
      graph = build(imagedir: File.join(dir, 'images'))
      path = graph.generate(id: 'g1', command: 'graphviz', content: 'digraph g { a -> b; }')

      assert_path_exist(path)
      assert_match(/\A%!PS-Adobe.*EPSF/, File.read(path, 200), 'the generated file should be EPS')
    end
  end
end
