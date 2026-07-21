# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'

module ReVIEW
  module AST
    # Resolves the names in config.yml's stylesheet: to files on disk.
    #
    # The upstream makers only look in the book root, which forces every book
    # to carry copies of the stylesheets review-ast ships. The AST makers
    # search, in order:
    #
    #   1. the book root (upstream-compatible)
    #   2. the book's css/ directory
    #   3. the stylesheets bundled in this gem (templates/vivliostyle/css)
    #
    # so a book can keep its own CSS under css/ and use the bundled defaults
    # without copying them.
    #
    # Names must be bare filenames: the output (EPUB package, webroot) stays
    # flat, and the layout templates link each name verbatim, so a name with a
    # directory component would produce a dangling link.
    module StylesheetResolver
      BUNDLED_CSS_DIR = File.expand_path('../../../templates/vivliostyle/css', __dir__)

      def resolve_stylesheet(name)
        if name != File.basename(name)
          error! "stylesheet: #{name} must be a bare filename; " \
                 'files are searched for in ., css/ and the bundled stylesheets.'
        end
        [name, File.join('css', name), File.join(BUNDLED_CSS_DIR, name)].
          find { |path| File.exist?(path) }
      end

      # Copies each stylesheet in the config into +basetmpdir+, yielding the
      # name for maker-specific bookkeeping (the EPUB maker registers it in
      # the manifest).
      #
      # +preserve+ follows each upstream maker: the EPUB one preserves, the web
      # one does not. It matters for the bundled stylesheets, which an installed
      # gem holds read-only -- preserving that into a writable output tree would
      # be a change the web output never asked for.
      def copy_resolved_stylesheets(basetmpdir, preserve: true)
        (@config['stylesheet'] || []).each do |name|
          src = resolve_stylesheet(name)
          error! "stylesheet: #{name} is not found." unless src
          FileUtils.cp(src, File.join(basetmpdir, name), preserve: preserve)
          yield name if block_given?
        end
      end
    end
  end
end
