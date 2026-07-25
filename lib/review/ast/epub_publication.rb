# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'rexml/document'
require 'review/exception'

module ReVIEW
  module AST
    # An unpacked EPUB, addressed by its OPF.
    #
    # A renderer that speaks HTML wants the publication as files, not as a zip,
    # and print output usually wants a document or two left out of it. Both are
    # EPUB-level operations rather than build-pipeline ones, so they live here
    # instead of in the maker that drives them.
    #
    # The editing is minimal on purpose: entries are dropped from the spine and
    # from the navigation, never renamed or reordered.
    class EpubPublication
      class Error < ReVIEW::ApplicationError; end

      attr_reader :root, :opf

      # Unpacks +epubfile+ into +root+, replacing whatever was there.
      def self.extract(epubfile, root)
        unpack(epubfile, root)
        opf = Dir.glob(File.join(root, '**', '*.opf')).min
        raise Error, "OPF not found under #{root}." unless opf

        new(root, opf)
      end

      # Extracts with rubyzip (a dependency of the review gem). Reading each
      # entry avoids the Zip::Entry#extract signature differences between
      # rubyzip 2 and 3.
      def self.unpack(epubfile, root)
        require 'zip'
        FileUtils.rm_rf(root)
        prefix = "#{root}#{File::SEPARATOR}"
        Zip::File.open(epubfile) do |zip|
          zip.each do |entry|
            next if entry.directory?

            dest = File.join(root, entry.name)
            # An entry named ../x would otherwise be written outside root.
            next unless File.expand_path(dest).start_with?(prefix)

            FileUtils.mkdir_p(File.dirname(dest))
            File.binwrite(dest, entry.get_input_stream.read)
          end
        end
      end
      private_class_method :unpack

      def initialize(root, opf)
        @root = root
        @opf = opf
      end

      # Drops the <itemref>s whose manifest entry points at one of +hrefs+.
      # The manifest item itself stays: dangling manifest entries are harmless,
      # and keeping them avoids breaking other references.
      def remove_from_spine(hrefs)
        return if hrefs.empty?

        package = read_xml(opf)
        ids = each_element(package, 'item').
              select { |item| hrefs.include?(item.attributes['href']) }.
              map { |item| item.attributes['id'] }
        each_element(package, 'itemref').each do |itemref|
          itemref.parent.delete_element(itemref) if ids.include?(itemref.attributes['idref'])
        end
        write_xml(opf, package)
      end

      # Drops the <li> wrapping each navigation link to one of +hrefs+.
      def remove_from_toc(hrefs)
        return if hrefs.empty? || nav.nil? || !File.exist?(nav)

        toc = read_xml(nav)
        each_element(toc, 'a').each do |anchor|
          next unless hrefs.include?(anchor.attributes['href'])

          item = anchor.parent
          item = item.parent while item && item.name != 'li'
          item&.parent&.delete_element(item)
        end
        write_xml(nav, toc)
      end

      # The navigation document, or nil when the package declares none.
      def nav
        return @nav if defined?(@nav)

        item = each_element(read_xml(opf), 'item').
               find { |i| i.attributes['properties'].to_s.split.include?('nav') }
        @nav = item && File.join(File.dirname(opf), item.attributes['href'])
      end

      # Removes the unpacked tree.
      def discard
        FileUtils.remove_entry_secure(root) if File.directory?(root)
      end

      private

      def read_xml(path)
        REXML::Document.new(File.read(path))
      end

      def write_xml(path, doc)
        File.write(path, doc.to_s)
      end

      # OPF and XHTML both use default namespaces, which REXML's XPath does not
      # resolve by element name alone; match on the local name instead.
      def each_element(doc, name)
        REXML::XPath.match(doc, "//*[local-name()='#{name}']")
      end
    end
  end
end
