# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    # Locations of the modern web-site assets review-ast ships for the AST
    # WebMaker (doc/refactor-webmaker.ja.md step 2). These replace the gem's aging
    # webmaker layout/CSS as the default, while the webmaker's existing
    # "layouts/layout-web.html.erb overrides" contract still lets a book supply its
    # own. Only the webmaker path uses these; EPUB/plain HTML keep the gem's
    # templates.
    module WebAssets
      # <repo>/templates/web/html (this file is at lib/review/ast).
      DIR = File.expand_path('../../../templates/web/html', __dir__)

      # The default full-page layout (semantic HTML5, responsive two-pane, dark
      # mode). Uses the same ERB binding variables as the gem's web layout, so it
      # is a drop-in.
      LAYOUT_HTML5 = File.join(DIR, 'layout-html5.html.erb')

      # The bundled stylesheet copied into the generated site and linked by the
      # layout under this fixed name (independent of the user's config stylesheet).
      STYLESHEET = File.join(DIR, 'review-ast-web.css')
      STYLESHEET_NAME = 'review-ast-web.css'
    end
  end
end
