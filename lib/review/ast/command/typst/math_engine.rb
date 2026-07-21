# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'review/ast/typst_assets'

module ReVIEW
  module AST
    module Command
      module Typst
        # Which adapter typesets the LaTeX in //texequation and @<m>.
        #
        # The library reaches math through one file, so the engine can be
        # swapped without the chapters knowing
        # (doc/design-typst.md). Choosing it, and warning when
        # the choice needs something the machine does not have, is this object's
        # business rather than the installer's.
        class MathEngine
          MITEX = 'mitex'

          # Where Typst keeps downloaded packages.
          PACKAGE_CACHES = [
            '~/Library/Caches/typst/packages/preview',
            '~/.cache/typst/packages/preview'
          ].freeze

          def initialize(name, warn: nil)
            @name = name.to_s
            @warn = warn
          end

          # Overwrite the bundled adapter when the book asked for another one.
          # @param library_dir [String] The installed copy of review-book
          def install_into(library_dir)
            return unless mitex?

            warn_unless_cached
            FileUtils.cp(ReVIEW::AST::TypstAssets::MATH_MITEX, File.join(library_dir, 'math.typ'))
          end

          private

          def mitex?
            @name == MITEX
          end

          # mitex comes from the Typst package registry, which needs network
          # access on first use. Say so before the compile stalls on a fetch.
          #
          # The pinned version has to be the one present: another version in
          # the cache does not help, since the import in math-mitex.typ names
          # the exact version.
          def warn_unless_cached
            version = pinned_version
            return if version.nil? || cached?(version)

            @warn&.call("typst.math is \"#{MITEX}\" but #{MITEX} #{version} is not in the Typst " \
                        'package cache; the first build needs network access to fetch it.')
          end

          def cached?(version)
            PACKAGE_CACHES.any? do |dir|
              File.directory?(File.join(File.expand_path(dir), MITEX, version))
            end
          end

          # Read from the adapter itself, so the check and the import it guards
          # cannot drift apart.
          def pinned_version
            File.read(ReVIEW::AST::TypstAssets::MATH_MITEX)[%r{@preview/#{MITEX}:([\d.]+)}o, 1]
          end
        end
      end
    end
  end
end
