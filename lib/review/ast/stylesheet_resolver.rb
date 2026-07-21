# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'review/exception'

module ReVIEW
  module AST
    # Resolves the names in config.yml's stylesheet: to files on disk.
    #
    # The upstream makers only look in the book root, which forces every book to
    # carry copies of the stylesheets review-ast ships. This searches, in order:
    #
    #   1. the book root (upstream-compatible)
    #   2. the book's css/ directory
    #   3. the stylesheets bundled in this gem (templates/vivliostyle/css)
    #
    # so a book can keep its own CSS under css/ and use the bundled defaults
    # without copying them.
    #
    # Names must be bare filenames: the output (EPUB package, webroot) stays
    # flat and the layout templates link each name verbatim, so a name with a
    # directory component would produce a dangling link.
    class StylesheetResolver
      class Error < ReVIEW::ApplicationError; end

      BUNDLED_CSS_DIR = File.expand_path('../../../templates/vivliostyle/css', __dir__)

      def initialize(names, bundled_dir: BUNDLED_CSS_DIR)
        @names = Array(names)
        @bundled_dir = bundled_dir
      end

      # The file +name+ stands for, searched along the path above.
      def resolve(name)
        if name != File.basename(name)
          raise Error, "stylesheet: #{name} must be a bare filename; " \
                       'files are searched for in ., css/ and the bundled stylesheets.'
        end

        found = [name, File.join('css', name), File.join(@bundled_dir, name)].
                find { |path| File.exist?(path) }
        raise Error, "stylesheet: #{name} is not found." unless found

        found
      end

      # Copies every stylesheet into +dir+, yielding each name for the caller's
      # own bookkeeping (the EPUB maker registers it in the manifest).
      #
      # +preserve+ carries the timestamp and ownership over, which is what the
      # upstream EPUB maker does and the upstream web maker does not.
      #
      # The mode is a separate matter: FileUtils.cp creates the destination with
      # the source's mode either way, and an installed gem holds the bundled
      # stylesheets read-only. A generated tree has to stay writable -- the web
      # output is served and edited from where it lands -- so the copy is made
      # writable unless the caller asked for the source's metadata wholesale.
      def copy_to(dir, preserve: true)
        @names.each do |name|
          destination = File.join(dir, name)
          FileUtils.cp(resolve(name), destination, preserve: preserve)
          FileUtils.chmod('u+w', destination) unless preserve
          yield name if block_given?
        end
      end
    end
  end
end
