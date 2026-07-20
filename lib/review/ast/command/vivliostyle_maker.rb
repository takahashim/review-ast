# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'rexml/document'
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
      # config.yml:
      #   stylesheet: ["style-vivliostyle.css"]   # the CSS defines the page layout
      #   vivliostyle:
      #     output: mybook-vivliostyle.pdf  # default: <bookname>-vivliostyle.pdf
      #     outline: toc                    # toc (default) / headings / none
      #     timeout: 300
      #     browser_path: ~                 # default: auto-detect Chrome/Chromium
      #     viewer_path: ~                  # default: viewer bundled in vivlio-pdf
      #     keep_workdir: false             # keep the extracted EPUB tree
      class VivliostyleMaker < EPUBMaker
        def produce(yamlfile, bookname = nil)
          super
          build_pdf(bookname || @config['bookname'])
        end

        private

        def build_pdf(bookname)
          require_vivlio_pdf
          vconfig = @config['vivliostyle'] || {}

          epubfile = File.absolute_path("#{bookname}.epub")
          error! "#{epubfile} not found." unless File.exist?(epubfile)

          workdir = File.absolute_path("#{bookname}-vivliostyle")
          extract_epub(epubfile, workdir)
          opf = Dir.glob(File.join(workdir, '**', '*.opf')).min
          error! "OPF not found under #{workdir}." unless opf

          apply_frontmatter_overrides(opf, vconfig)

          # NOTE: not <bookname>.pdf — that would overwrite pdfmaker's output.
          output = File.absolute_path(vconfig['output'] || "#{bookname}-vivliostyle.pdf")

          options = { outline: (vconfig['outline'] || 'toc').to_sym,
                      metadata: pdf_metadata }
          options[:timeout] = vconfig['timeout'] if vconfig['timeout']
          options[:browser_path] = vconfig['browser_path'] if vconfig['browser_path']
          options[:viewer] = vconfig['viewer_path'] if vconfig['viewer_path']

          result = Vivlio::PDF.print(source: opf, output: output, **options)

          FileUtils.remove_entry_secure(workdir) unless vconfig['keep_workdir']
          @logger.success("built #{File.basename(result.path)} (#{result.pages} pages, " \
                          "#{result.bookmarks} bookmarks)")
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
        # (review-jsbook.cls sets \@reclscoverfalse) -- so adjust the unzipped
        # publication before handing it to the renderer.
        #
        #   vivliostyle:
        #     cover: false          # 表紙ページを出力しない
        #     toc_titlepage: false  # 目次に大扉を載せない
        def apply_frontmatter_overrides(opf, vconfig)
          from_spine = []
          from_toc = []

          unless vconfig.fetch('cover', true)
            cover = "#{@config['bookname']}.#{@config['htmlext']}"
            from_spine << cover
            from_toc << cover
          end
          unless vconfig.fetch('toc_titlepage', true)
            from_toc << "titlepage.#{@config['htmlext']}"
          end
          return if from_spine.empty? && from_toc.empty?

          package = read_xml(opf)
          remove_spine_items(package, from_spine)
          nav = nav_file(opf, package)
          write_xml(opf, package)

          return unless nav && File.exist?(nav)

          toc = read_xml(nav)
          remove_toc_items(toc, from_toc)
          write_xml(nav, toc)
        end

        def read_xml(path)
          REXML::Document.new(File.read(path))
        end

        def write_xml(path, doc)
          File.write(path, doc.to_s)
        end

        # Drop <itemref>s whose manifest entry points at one of +hrefs+.
        # The manifest item itself stays: dangling manifest entries are
        # harmless, and keeping them avoids breaking other references.
        def remove_spine_items(package, hrefs)
          return if hrefs.empty?

          ids = each_element(package, 'item').
                select { |item| hrefs.include?(item.attributes['href']) }.
                map { |item| item.attributes['id'] }
          each_element(package, 'itemref').each do |itemref|
            itemref.parent.delete_element(itemref) if ids.include?(itemref.attributes['idref'])
          end
        end

        # Drop the <li> wrapping each link to one of +hrefs+.
        def remove_toc_items(toc, hrefs)
          return if hrefs.empty?

          each_element(toc, 'a').each do |anchor|
            next unless hrefs.include?(anchor.attributes['href'])

            item = anchor.parent
            item = item.parent while item && item.name != 'li'
            item&.parent&.delete_element(item)
          end
        end

        def nav_file(opf, package)
          item = each_element(package, 'item').
                 find { |i| i.attributes['properties'].to_s.split.include?('nav') }
          item && File.join(File.dirname(opf), item.attributes['href'])
        end

        # OPF and XHTML both use default namespaces, which REXML's XPath does
        # not resolve by element name alone; match on the local name instead.
        def each_element(doc, name)
          REXML::XPath.match(doc, "//*[local-name()='#{name}']")
        end

        # Extract with rubyzip (a dependency of the review gem). Reading each
        # entry avoids the Zip::Entry#extract signature differences between
        # rubyzip 2 and 3.
        def extract_epub(epubfile, workdir)
          require 'zip'
          FileUtils.rm_rf(workdir)
          Zip::File.open(epubfile) do |zip|
            zip.each do |entry|
              next if entry.directory?

              dest = File.join(workdir, entry.name)
              FileUtils.mkdir_p(File.dirname(dest))
              File.binwrite(dest, entry.get_input_stream.read)
            end
          end
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
