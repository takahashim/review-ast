# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'review/ast/epub_publication'
require 'review/ast/image_size_annotator'
require 'review/ast/vivliostyle_config'
require_relative 'epub_maker'

module ReVIEW
  module AST
    module Command
      # Builds a PDF through Vivliostyle (CSS paged media) instead of LaTeX.
      #
      # The pipeline reuses the AST EPUBMaker unchanged to produce
      # <bookname>.epub, then extracts it and hands the unzipped publication
      # (its OPF) to the vivlio-pdf gem, which drives a local Chrome through
      # the Vivliostyle Viewer and prints to PDF with bookmarks and metadata.
      #
      # vivlio-pdf is a soft dependency (AGPL, browser-driving), so it is
      # required lazily; everything in this file is plain LGPL Ruby.
      #
      # The publication itself is EpubPublication's business and the settings
      # are VivliostyleConfig's; what is left here is the order of the steps.
      #
      # config.yml:
      #   stylesheet: ["style-vivliostyle.css"]   # the CSS defines the page layout
      #   vivliostyle:                            # see VivliostyleConfig
      #     output: mybook-vivliostyle.pdf
      class VivliostyleMaker < EPUBMaker
        def produce(yamlfile, bookname = nil)
          require_vivlio_pdf
          super
          build_pdf(bookname || @config['bookname'])
        end

        private

        def build_pdf(bookname)
          vconfig = VivliostyleConfig.new(@config['vivliostyle'])

          epubfile = File.absolute_path("#{bookname}.epub")
          error! "#{epubfile} not found." unless File.exist?(epubfile)

          publication = extract_publication(epubfile, bookname)
          apply_frontmatter_overrides(publication, vconfig)
          # Sized like \includegraphics does, from the resolution embedded in
          # each image. //image's scale= is a multiplier on that natural size,
          # so the stylesheet needs it as a value; see ImageSizeAnnotator and
          # doc/vivliostyle-image-sizing.ja.md.
          ImageSizeAnnotator.new(publication.root).annotate if vconfig.image_intrinsic_size?

          result = print_pdf(publication, vconfig, bookname)
          @logger.success("built #{File.basename(result.path)} (#{result.pages} pages, " \
                          "#{result.bookmarks} bookmarks)")
        end

        def extract_publication(epubfile, bookname)
          EpubPublication.extract(epubfile, File.absolute_path("#{bookname}-vivliostyle"))
        rescue EpubPublication::Error => e
          error! e.message
        end

        def print_pdf(publication, vconfig, bookname)
          output = File.absolute_path(vconfig.output_for(bookname))
          Vivlio::PDF.print(source: publication.opf, output: output,
                            **vconfig.print_options(metadata: pdf_metadata))
        ensure
          # Also on failure: a half-printed run would otherwise leave the
          # extracted tree behind, and the next run starts by removing it anyway.
          publication.discard unless vconfig.keep_workdir?
        end

        def require_vivlio_pdf
          require 'vivlio/pdf'
        rescue LoadError
          error! <<~MSG
            vivlio-pdf is not available. Add it to your Gemfile:
              gem 'vivlio-pdf', github: 'takahashim/vivlio-pdf'
          MSG
        end

        # The base EPUB maker always emits a cover page and always lists the
        # title page in the navigation; neither can be switched off from
        # config.yml. Print output usually wants neither -- the cover is
        # submitted separately, and LaTeX's media=print drops it too
        # (review-jsbook.cls sets \@reclscoverfalse) -- so adjust the unpacked
        # publication before handing it to the renderer.
        def apply_frontmatter_overrides(publication, vconfig)
          from_spine = []
          from_toc = []

          unless vconfig.cover?
            from_spine << cover_document
            from_toc << cover_document
          end
          from_toc << "titlepage.#{@config['htmlext']}" unless vconfig.toc_titlepage?

          publication.remove_from_spine(from_spine)
          publication.remove_from_toc(from_toc)
        end

        # config.yml's cover: names the file; the producer only fills in
        # "<bookname>.<htmlext>" as its default, and the legacy coverfile path
        # renames it again. Reading it back is the only way to match the
        # manifest entry.
        def cover_document
          name = @config['cover'].to_s
          name = "#{@config['bookname']}.#{@config['htmlext']}" if name.empty?
          File.basename(name)
        end

        def pdf_metadata
          metadata = {}
          title = @config.name_of('booktitle')
          metadata[:title] = title if title
          authors = @config['aut'] ? @config.names_of('aut') : nil
          metadata[:author] = Array(authors).join(', ') unless Array(authors).empty?
          metadata
        end
      end
    end
  end
end
