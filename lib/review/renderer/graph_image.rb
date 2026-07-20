# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'tempfile'

module ReVIEW
  module Renderer
    # Produces the image file a //graph block refers to, and returns its path.
    #
    # This is the part of //graph that touches the world: it writes a temporary
    # file, runs dot/gnuplot/blockdiag, and creates the image under the book's
    # imagedir. Keeping it out of the renderer leaves visit_graph deciding only
    # what markup to emit, and puts the process execution somewhere a test can
    # replace.
    #
    # Mermaid is different in kind -- ImgGraph defers those and renders them in
    # a browser at the end of the build -- so it stays with ImgGraph and only
    # passes through here.
    class GraphImage
      # Command name in the source => the generator to run.
      GENERATORS = {
        'graphviz' => :graphviz,
        'dot' => :graphviz,
        'gnuplot' => :gnuplot,
        'blockdiag' => :blockdiag,
        'seqdiag' => :blockdiag,
        'actdiag' => :blockdiag,
        'nwdiag' => :blockdiag
      }.freeze

      # @param imagedir [String] The book's image directory
      # @param target_name [String] Builder name, used as the subdirectory
      # @param image_ext [String] Extension this format wants ('eps', 'pdf', ...)
      def initialize(imagedir:, target_name:, image_ext:)
        @imagedir = imagedir
        @target_name = target_name
        @image_ext = image_ext
      end

      # @param id [String] The graph's id, which names the file
      # @param command [String] Generator named in the source
      # @param content [String] The graph description
      # @return [String] Path of the image the markup should point at
      def generate(id:, command:, content:)
        path = file_path(id)
        generator = GENERATORS[command]
        return path unless generator

        FileUtils.mkdir_p(File.dirname(path))
        with_temporary_source(content) do |source_path|
          send(generator, path, source_path, content, command)
        end
        path
      end

      # The path for a graph whose image is produced elsewhere (mermaid, or a
      # generator that is not installed).
      # @param id [String] The graph's id
      # @return [String] Path the markup should point at
      def file_path(id)
        File.join(@imagedir, @target_name, "#{id}.#{@image_ext}")
      end

      private

      def with_temporary_source(content)
        file = Tempfile.new('review_graph')
        file.puts content
        file.close
        begin
          yield(file.path)
        ensure
          file.unlink
        end
      end

      def graphviz(path, source_path, _content, _command)
        system('dot', "-T#{@image_ext}", "-o#{path}", source_path)
      end

      def gnuplot(path, source_path, content, _command)
        # gnuplot spells EPS "postscript eps"; every other format is its own
        # terminal name (Builder#graph_gnuplot does the same).
        terminal = @image_ext == 'eps' ? 'postscript eps' : @image_ext
        File.open(source_path, 'w') do |file|
          file.puts <<~GNUPLOT
            set terminal #{terminal}
            set output "#{path}"
            #{content}
          GNUPLOT
        end
        system('gnuplot', source_path)
      end

      def blockdiag(path, source_path, _content, command)
        system(command, '-a', '-T', @image_ext, '-o', path, source_path)
      end
    end
  end
end
