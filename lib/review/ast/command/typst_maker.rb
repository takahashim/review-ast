# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'fileutils'
require 'open3'
require 'optparse'

require 'review/configure'
require 'review/book'
require 'review/i18n'
require 'review/loggable'
require 'review/makerhelper'
require 'review/version'
require 'review/ast'
require 'review/ast/typst_assets'
require 'review/renderer/typst_renderer'
require_relative 'typst/chapter_set'
require 'review/renderer/typst/erb_template'
require_relative 'typst/math_engine'
require 'review/renderer/typst/part_document'
require 'review/renderer/typst/root_document'
require 'review/renderer/typst/source_map'

module ReVIEW
  module AST
    module Command
      # Builds a PDF with Typst.
      #
      # Unlike the other AST makers this does NOT subclass its counterpart in
      # the review gem. PDFMaker#generate_pdf hard-wires a LATEXBuilder
      # converter, ImgGraph(..., 'latex'), the .tex master file and the sty/
      # copying into one method, so a Typst subclass would have to override
      # essentially all of it and would gain nothing from the inheritance
      # (doc/design-typst.md). What is reused from the gem are
      # the parts that are genuinely shared: Configure, Book::Base, I18n,
      # Loggable and MakerHelper.
      #
      # config.yml:
      #   typst:
      #     command: typst        # CLI name; detected and version-checked
      #     pdf_standard: ~       # e.g. "ua-1", passed to --pdf-standard
      #     math: ~               # "mitex" to typeset LaTeX math with mitex
      #     crop: ~               # true to add crop marks and bleed
      #     serial_pagination: false  # one arabic counter across the whole book
      #     startpage: 1          # the number the first page carries
      #     keep_workdir: false   # keep the generated .typ tree
      #     output: ~             # default <bookname>-typst.pdf
      class TypstMaker
        include ReVIEW::Loggable

        # The oldest Typst the review-book library is known to compile against.
        # Typst has changed syntax between minor versions, so this is a floor the
        # preflight enforces, not a pin: newer releases work too (CI builds
        # against a current one -- see .github/workflows/typst.yml).
        SUPPORTED_TYPST = Gem::Version.new('0.13.0')

        attr_reader :config, :basedir

        def initialize
          @logger = ReVIEW.logger
          @compile_errors = []
          @buildonly = nil
        end

        def self.execute(*args)
          new.execute(*args)
        end

        def execute(*args)
          cmd_config, yamlfile = parse_opts(args)
          error! "#{yamlfile} not found." unless File.exist?(yamlfile)

          begin
            @config = ReVIEW::Configure.create(maker: 'typstmaker',
                                               yamlfile: yamlfile,
                                               config: cmd_config)
          rescue ReVIEW::ConfigError => e
            error! e.message
          end

          ReVIEW::I18n.setup(@config['language'])
          @basedir = File.absolute_path(File.dirname(yamlfile))

          begin
            @config.check_version(ReVIEW::VERSION)
          rescue ReVIEW::ConfigError => e
            warn e.message
          end

          generate_pdf
        end

        private

        def parse_opts(args)
          cmd_config = {}
          opts = OptionParser.new
          opts.banner = 'Usage: review-ast-typstmaker configfile'
          opts.version = ReVIEW::VERSION
          opts.on('--help', 'Prints this message and quit.') do
            puts opts.help
            exit 0
          end
          opts.on('--[no-]debug', 'Keep temporary files.') { |debug| cmd_config['debug'] = debug }
          opts.on('--ignore-errors', 'Ignore compile errors.') { cmd_config['ignore-errors'] = true }
          opts.on('-y', '--only file1,file2,...', 'Build only specified files.') do |v|
            @buildonly = v.split(/\s*,\s*/).map { |m| m.strip.sub(/\.re\Z/, '') }
          end

          opts.parse!(args)
          if args.size != 1
            puts opts.help
            exit 0
          end

          [cmd_config, args[0]]
        end

        def typst_config
          @config['typst'] || {}
        end

        def build_dir
          @build_dir ||= File.join(@basedir, "#{@config['bookname']}-typst")
        end

        def output_path
          File.absolute_path(typst_config['output'] || "#{@config['bookname']}-typst.pdf", @basedir)
        end

        # ------------------------------------------------------------ build

        def generate_pdf
          check_typst_command

          # Everything from here on is done with the book as the working
          # directory.
          #
          # Re:VIEW resolves several paths against the process's working
          # directory rather than the book's: Book::Part reads its .re through
          # config['contentdir'], and //graph writes its image under
          # config['imagedir']. Passing an absolute basedir does not help --
          # Book::Base.new('/path/to/book') still returns an empty part body
          # when called from elsewhere, and it does so silently.
          #
          # That assumption holds for every maker, not just this one; the others
          # simply are not run from anywhere but the book directory. This build
          # is, by the integration tests, so it states the assumption instead of
          # relying on it.
          Dir.chdir(@basedir) { build_book }
        end

        def build_book
          book = ReVIEW::Book::Base.new(@basedir, config: @config)
          # ImageFinder searches <imagedir>/<builder>/ before <imagedir>, so
          # without this a book that keeps Typst-specific artwork under
          # images/typst/ would silently fall back to the shared image (or to
          # none at all). AstHtmlConverter does the same for the HTML path.
          book.config['builder'] = ReVIEW::Renderer::TypstRenderer::BUILDER_NAME

          prepare_build_dir
          install_library
          write_theme

          chapters = collect_chapters(book)
          render_chapters(chapters)
          check_compile_status

          # After rendering, not before: a //graph block produces its image
          # while the chapter is being rendered, so copying earlier would leave
          # those files out of the build directory.
          copy_images

          write_root(chapters)
          source_map.write(build_dir)
          run_typst

          FileUtils.remove_entry_secure(build_dir) unless keep_workdir?
          @logger.success("built #{File.basename(output_path)}")
        end

        def keep_workdir?
          typst_config['keep_workdir'] || @config['debug']
        end

        # ----------------------------------------------------- preflight

        def check_typst_command
          command = typst_config['command'] || 'typst'
          out, status = Open3.capture2e(command, '--version')
          error! "failed to run #{command}. Install Typst or set typst.command." unless status.success?

          version = out[/\d+\.\d+\.\d+/]
          unless version
            warn "could not read the version from `#{command} --version`; continuing."
            return
          end

          if Gem::Version.new(version) < SUPPORTED_TYPST
            error! "Typst #{version} is too old; review-book needs #{SUPPORTED_TYPST} or later."
          end
        rescue Errno::ENOENT
          error! "#{command} not found. Install Typst or set typst.command in config.yml."
        end

        # ------------------------------------------------- build layout

        # Everything the compile reads lives under one directory, which is also
        # the Typst project root. Typst refuses to read outside that root, so
        # fixing the layout here is what makes the generated paths resolvable
        # (doc/design-typst.md).
        def prepare_build_dir
          FileUtils.rm_rf(build_dir)
          FileUtils.mkdir_p(File.join(build_dir, 'chapters'))
        end

        def install_library
          target = File.join(build_dir, ReVIEW::AST::TypstAssets::LIBRARY_DIR)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp_r(ReVIEW::AST::TypstAssets::LIBRARY, target)
          math_engine.install_into(target)
        end

        def math_engine
          Typst::MathEngine.new(typst_config['math'], warn: method(:warn))
        end

        # The theme the book is built with.
        #
        # An author customizes the look by putting theme.typ next to config.yml;
        # it is copied in as-is. Without one, a starter theme is generated. Note
        # that the build directory is rebuilt from scratch every run, so editing
        # the copy inside it has no lasting effect -- the source-directory file
        # is the one to edit.
        def write_theme
          target = File.join(build_dir, 'theme.typ')
          source = File.join(@basedir, 'theme.typ')

          if File.exist?(source)
            FileUtils.cp(source, target)
            return
          end

          # Typst names the JIS B series separately from the ISO one, and a
          # Japanese book's "B5" is the JIS size.
          paper = (@config['texdocumentclass'] && @config['texdocumentclass'][1].to_s.include?('b5')) ? 'jis-b5' : 'a5'
          template = File.read(File.join(ReVIEW::AST::TypstAssets::DIR, 'theme.typ.erb'))
          File.write(target, ReVIEW::Renderer::Typst::ErbTemplate.render(template, paper: %Q("#{paper}")))
        end

        def copy_images
          imagedir = @config['imagedir'] || 'images'
          from = File.join(@basedir, imagedir)
          return unless File.directory?(from)

          to = File.join(build_dir, imagedir)
          FileUtils.mkdir_p(to)
          ReVIEW::MakerHelper.copy_images_to_dir(from, to)
        end

        # --------------------------------------------------- rendering

        # Chapter buckets in catalog order, matching how PDFMaker#make_input_files
        # walks parts and chapters, but without inheriting from it.
        def collect_chapters(book)
          chapters = Typst::ChapterSet.new

          book.parts.each do |part|
            add_part(chapters, part)
            part.chapters.each do |chapter|
              basename = File.basename(chapter.path, '.*')
              next unless build?(basename)

              chapters.add(Typst::ChapterSet.group_for(chapter),
                           Typst::ChapterSet::Entry.new(basename, chapter, nil))
            end
          end

          chapters
        end

        # A part with its own .re file is compiled like a chapter, since a
        # cross-reference can point at it; a part named only in catalog.yml has
        # no source, and is written out as its title alone.
        def add_part(chapters, part)
          return if part.name.to_s == ''

          @config['use_part'] = true
          unless part.file?
            source = ReVIEW::Renderer::Typst::PartDocument.source(
              part, ReVIEW::Renderer::TypstRenderer::LIBRARY_IMPORT
            )
            return chapters.add(:chaps, Typst::ChapterSet::Entry.new("part-#{part.number}", nil, source))
          end

          basename = File.basename(part.path, '.*')
          return unless build?(basename)

          chapters.add(:chaps, Typst::ChapterSet::Entry.new(basename, part, nil))
        end

        def build?(basename)
          @buildonly.nil? || @buildonly.include?(basename)
        end

        # The whole build already runs in the book directory (see generate_pdf),
        # which is what keeps //graph's images inside it.
        def render_chapters(chapters)
          chapters.each do |file|
            if file.chapter
              render_chapter(file.chapter, file.basename)
            else
              write_chapter(file.basename, file.source)
            end
          end
        end

        def write_chapter(basename, source)
          File.write(File.join(build_dir, 'chapters', "#{basename}.typ"), source)
        end

        def render_chapter(chapter, basename)
          compiler = ReVIEW::AST::Compiler.for_chapter(chapter)
          ast = compiler.compile_to_ast(chapter, registry_provider: registry_provider)
          renderer = ReVIEW::Renderer::TypstRenderer.new(chapter)
          typst = renderer.render(ast)
          write_chapter(basename, typst)
          source_map.record("chapters/#{basename}.typ", renderer.source_map)
        # Every failure is recorded the same way and the build carries on to the
        # next chapter, so one bad file yields one error rather than hiding the
        # rest. NotImplementedError is in here deliberately: that is how an
        # unsupported node or inline reaches the surface.
        rescue ReVIEW::CompileError, ReVIEW::SyntaxError, ReVIEW::AST::InlineTokenizeError,
               NotImplementedError, StandardError => e
          record_error(basename, e)
        end

        def record_error(basename, error)
          message = "#{basename}: #{error.class.name} - #{error.message}"
          @compile_errors << message
          @logger.error("Compilation error in #{basename}: #{error.message}")
          if error.respond_to?(:location) && error.location
            @logger.error("  at line #{error.location.lineno} in #{error.location.filename}")
          end
          return unless @config['debug']

          @logger.debug('Backtrace:')
          error.backtrace.first(10).each { |line| @logger.debug("  #{line}") }
        end

        def check_compile_status
          return if @compile_errors.empty?

          summary = ["Compilation errors occurred in #{@compile_errors.length} file(s):"]
          @compile_errors.each_with_index { |e, i| summary << "  #{i + 1}. #{e}" }
          @logger.error(summary.join("\n"))

          if @config['ignore-errors']
            warn 'compile error, but try to generate the PDF file'
          else
            error! 'compile error, aborting.'
          end
        end

        # Generated-file line -> manuscript position, per chapter file.
        def source_map
          @source_map ||= ReVIEW::Renderer::Typst::SourceMap.new
        end

        # One provider per book build, so a chapter referenced from several
        # chapters is compiled and indexed once.
        def registry_provider
          @registry_provider ||= ReVIEW::AST::ChapterRegistryProvider.new
        end

        # ------------------------------------------------------- root file

        def write_root(buckets)
          template = File.read(ReVIEW::AST::TypstAssets::ROOT_TEMPLATE)
          File.write(File.join(build_dir, 'book.typ'), root_document.render(template, buckets))
        end

        # Every config.yml value that reaches the root document is converted
        # there, so this class does not grow a method per config key.
        def root_document
          @root_document ||= ReVIEW::Renderer::Typst::RootDocument.new(
            config: @config,
            basedir: @basedir,
            typst_config: typst_config,
            warn: method(:warn)
          )
        end

        # --------------------------------------------------------- compile

        def run_typst
          command = typst_config['command'] || 'typst'
          args = [command, 'compile', '--root', build_dir]
          if typst_config['pdf_standard']
            args << '--pdf-standard' << typst_config['pdf_standard'].to_s
          end
          args << File.join(build_dir, 'book.typ') << output_path

          out, status = Open3.capture2e(*args)
          return if status.success?

          # Typst reports positions in the generated .typ, which is not what the
          # author wrote: the source map turns each of them into a manuscript
          # position alongside (doc/design-typst.md). The generated tree is kept
          # on failure either way, since only it can be read by line number.
          @logger.error("typst compile failed:\n#{source_map.annotate(out)}")
          error! "Typst build failed. The generated sources are kept at #{build_dir}."
        end
      end
    end
  end
end
