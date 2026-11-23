# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'optparse'
require 'stringio'
require 'review/book'
require 'review/ast/compiler'
require 'review/ast/chapter_registry_provider'
require 'review/version'
require 'review/configure'
require 'review/yamlloader'
require 'review/i18n'
require 'review/loggable'
require 'review/logger'

module ReVIEW
  module AST
    module Command
      # Compile - AST-based counterpart of `review-compile`.
      #
      # It accepts review-compile's options and resolves chapters the way it
      # does: the files named on the command line are looked up in the book
      # (so cross-chapter references resolve against the catalog), and with no
      # file argument every chapter and part of the book is compiled into
      # `<name><ext>` in the current directory. A file that is not part of the
      # book is still compiled, as a stand-alone chapter.
      #
      # One deliberate difference: options given on the command line override
      # the same keys from the YAML file. (review-compile sets them before
      # merging the YAML, so a value in config.yml silently wins.)
      class Compile
        include ReVIEW::Loggable

        class CompileError < StandardError; end
        class FileNotFoundError < CompileError; end
        class UnsupportedFormatError < CompileError; end
        class MissingTargetError < CompileError; end

        # Exit status codes
        EXIT_SUCCESS = 0
        EXIT_COMPILE_ERROR = 1
        EXIT_UNEXPECTED_ERROR = 2

        DEFAULT_CONFIG_FILENAME = 'config.yml'

        # target => [renderer require path, renderer class name, output extension]
        RENDERERS = {
          'html' => ['review/renderer/html_renderer', 'HtmlRenderer', '.html'],
          'latex' => ['review/renderer/latex_renderer', 'LatexRenderer', '.tex'],
          'idgxml' => ['review/renderer/idgxml_renderer', 'IdgxmlRenderer', '.xml'],
          'plaintext' => ['review/renderer/plaintext_renderer', 'PlaintextRenderer', '.txt'],
          'top' => ['review/renderer/top_renderer', 'TopRenderer', '.txt'],
          'typst' => ['review/renderer/typst_renderer', 'TypstRenderer', '.typ']
        }.freeze

        attr_reader :options, :logger

        def initialize
          @options = {
            target: nil,
            check_only: false,
            verbose: false,
            output_file: nil,
            config_file: nil,
            directory: nil
          }
          # Config values given as options; applied on top of the YAML.
          @config_overrides = {}
          @version_requested = false
          @help_requested = false

          @logger = ReVIEW.logger
        end

        def run(args)
          parse_arguments(args)

          # --version or --help already handled
          return EXIT_SUCCESS if @version_requested || @help_requested

          validate_options
          compile
          EXIT_SUCCESS
        rescue CompileError, ReVIEW::ApplicationError => e
          error_handler.handle(e)
          EXIT_COMPILE_ERROR
        rescue StandardError => e
          error_handler.handle_unexpected(e)
          EXIT_UNEXPECTED_ERROR
        end

        private

        def parse_arguments(args)
          parser = create_option_parser
          parser.parse!(args)
          @input_files = args.dup
        end

        def create_option_parser
          OptionParser.new do |opts|
            opts.banner = 'Usage: review-ast-compile --target FORMAT [options] [file ...]'
            opts.version = ReVIEW::VERSION

            opts.on('-t', '--target FORMAT', "Target format (#{RENDERERS.keys.join(', ')})") do |fmt|
              @options[:target] = fmt
            end
            opts.on('-o', '--output-file FILE', 'Write all results into FILE instead of stdout.') do |file|
              @options[:output_file] = file
            end
            opts.on('--config FILE', '--yaml FILE', 'Read configurations from YAML file (default: config.yml).') do |file|
              @options[:config_file] = file
            end
            opts.on('-c', '--check', 'Check manuscript only, no output.') { @options[:check_only] = true }
            opts.on('--directory DIR', 'Compile all chapters of the book in DIR.') { |dir| @options[:directory] = dir }
            opts.on('--catalogfile FILE', 'Set catalog file.') { |file| @config_overrides['catalogfile'] = file }

            opts.on('--level LVL', Integer, 'Section level to append number.') { |lvl| @config_overrides['secnolevel'] = lvl }
            opts.on('--toclevel LVL', Integer, 'Section level to show in the TOC.') { |lvl| @config_overrides['toclevel'] = lvl }
            opts.on('--tabwidth WIDTH', Integer, 'Tab width.') { |width| @config_overrides['tabwidth'] = width }
            opts.on('--chapterlink', 'Make chapref a hyperlink.') { @config_overrides['chapterlink'] = true }
            opts.on('--footnotetext', 'Use footnotemark and footnotetext (latex).') { @config_overrides['footnotetext'] = true }
            opts.on('--draft', 'Use draft mode (inline comment).') { @config_overrides['draft'] = true }

            opts.on('--structuredxml', 'Produce XML with structured sections (idgxml).') { @config_overrides['structuredxml'] = true }
            opts.on('--table WIDTH', 'Default table width (idgxml).') { |width| @config_overrides['tableopt'] = width }
            opts.on('--listinfo', 'Append listinfo tag to lists to indicate begin/end (idgxml).') { @config_overrides['listinfo'] = true }
            opts.on('--chapref DECORATION', 'Chapref decoration "before,middle,after" (idgxml).') { |dec| @config_overrides['chapref'] = dec }

            opts.on('--stylesheet FILES', 'Stylesheet file(s) for HTML (comma separated).') do |files|
              @config_overrides['stylesheet'] = files.split(/\s*,\s*/)
            end
            opts.on('--mathml', 'Use MathML for TeX equations in HTML.') { @config_overrides['math_format'] = 'mathml' }
            opts.on('--htmlversion VERSION', Integer, 'HTML version.') { |v| @config_overrides['htmlversion'] = v }
            opts.on('--epubversion VERSION', Integer, 'EPUB version.') { |v| @config_overrides['epubversion'] = v }

            opts.on('-v', '--verbose', 'Verbose output') { @options[:verbose] = true }

            opts.on_tail('--version', 'Show version') do
              puts opts.version
              @version_requested = true
            end

            opts.on_tail('-h', '--help', 'Show this help') do
              puts opts
              @help_requested = true
            end
          end
        end

        def validate_options
          # review-compile checks against html when no target is given.
          @options[:target] ||= 'html' if @options[:check_only]

          if @options[:target].nil?
            raise MissingTargetError, '--target option is required (use --target html or --target latex)'
          end

          unless RENDERERS.key?(@options[:target])
            raise UnsupportedFormatError, "Unsupported format: #{@options[:target]} (supported: #{RENDERERS.keys.join(', ')})"
          end

          if @input_files.empty? && @options[:directory].nil? && !File.exist?(catalog_path(Dir.pwd))
            raise CompileError, 'No input file specified. Use -h for help.'
          end
        end

        def compile
          if @input_files.empty?
            compile_directory(@options[:directory] || '.')
          else
            compile_files
          end
        end

        # review-compile's file mode: each file is compiled as the book's
        # chapter of that name; all results go to stdout (or -o).
        def compile_files
          @input_files.each { |file| validate_input_file(file) }
          files = @input_files.map { |file| File.expand_path(file) }
          book = load_book(File.dirname(files.first))

          results = in_book_dir(book) do
            files.map do |file|
              chapter = book_chapter(book, file) || standalone_chapter(book, file)
              render_chapter(chapter)
            end
          end
          return if @options[:check_only]

          output_content(results.join)
        end

        # review-compile's directory mode: every chapter and part of the book is
        # written to `<name><ext>` in the current directory.
        def compile_directory(dir)
          book = load_book(File.expand_path(dir))
          ext = RENDERERS.fetch(@options[:target])[2]
          outdir = Dir.pwd
          in_book_dir(book) do
            (book.chapters + book.parts_in_file).each do |chapter|
              output = render_chapter(chapter)
              next if @options[:check_only]

              File.write(File.join(outdir, "#{chapter.name}#{ext}"), output)
              log("Wrote #{chapter.name}#{ext}")
            end
          end
        end

        # Paths in the book's config (an index dictionary, a words file) are
        # relative to the book, as the makers -- which run there -- read them.
        def in_book_dir(book, &block)
          Dir.chdir(book.basedir, &block)
        end

        def validate_input_file(file)
          raise FileNotFoundError, "Input file not found: #{file}" unless File.exist?(file)
          raise CompileError, "Cannot read file: #{file}" unless File.readable?(file)
        end

        def load_book(basedir)
          config = load_configuration(basedir)
          I18n.setup(config['language'] || 'ja')
          book = ReVIEW::Book::Base.new(basedir, config: config)
          book.config['builder'] = @options[:target]
          book
        end

        # The chapter (or part) of the book whose file this is, if any.
        def book_chapter(book, file)
          basename = File.basename(file, '.*')
          return unless File.exist?(catalog_path(book.basedir, book.config['catalogfile']))

          book.chapters.find { |ch| ch.name == basename } ||
            book.parts_in_file.find { |part| part.name == basename }
        rescue ReVIEW::FileNotFound, KeyError
          nil
        end

        # A file outside the book's catalog is compiled on its own, numbered by
        # its file name (ch03.re -> 3) or as chapter 1.
        def standalone_chapter(book, file)
          basename = File.basename(file, '.*')
          log("#{file} is not in the catalog; compiling it as a stand-alone chapter")
          ReVIEW::Book::Chapter.new(
            book,
            extract_chapter_number_from_filename(basename) || 1,
            basename,
            file,
            StringIO.new(File.read(file))
          )
        end

        def extract_chapter_number_from_filename(basename)
          case basename
          when /^ch(?:ap)?(\d+)$/i, /^chapter(\d+)$/i, /^(\d+)$/
            $1.to_i
          end
        end

        def render_chapter(chapter)
          log("Compiling #{chapter.path} to #{@options[:target]}...")
          compiler = ReVIEW::AST::Compiler.for_chapter(chapter)
          ast = compiler.compile_to_ast(chapter, registry_provider: registry_provider)
          renderer_class.new(chapter).render(ast)
        rescue ReVIEW::ApplicationError, CompileError
          raise
        rescue StandardError => e
          raise CompileError, "#{chapter.path}: #{e.message}"
        end

        def registry_provider
          @registry_provider ||= ReVIEW::AST::ChapterRegistryProvider.new
        end

        def renderer_class
          path, name, = RENDERERS.fetch(@options[:target])
          require path
          ReVIEW::Renderer.const_get(name)
        end

        def catalog_path(basedir, catalogfile = nil)
          File.join(basedir, catalogfile || @config_overrides['catalogfile'] || 'catalog.yml')
        end

        # The Configure defaults, deep-merged with the YAML file (given, or
        # config.yml next to the manuscript / in the current directory), then
        # the command-line overrides.
        def load_configuration(basedir)
          config = ReVIEW::Configure.values
          yaml = @options[:config_file]
          if yaml
            raise CompileError, "Configuration file not found: #{yaml}" unless File.exist?(yaml)
          else
            yaml = [File.join(basedir, DEFAULT_CONFIG_FILENAME), DEFAULT_CONFIG_FILENAME].find { |f| File.exist?(f) }
          end

          if yaml
            log("Loading configuration: #{yaml}")
            begin
              config.deep_merge!(ReVIEW::YAMLLoader.new.load_file(yaml))
            rescue StandardError => e
              raise CompileError, "Failed to load configuration: #{e.message}"
            end
          end

          config.deep_merge!(@config_overrides)
          config
        end

        def output_content(content)
          if @options[:output_file]
            log("Writing to: #{@options[:output_file]}")
            File.write(@options[:output_file], content)
          else
            print content
          end
        rescue StandardError => e
          raise CompileError, "Failed to write output: #{e.message}"
        end

        def log(message)
          @logger.info(message) if @options[:verbose]
        end

        def error_handler
          @error_handler ||= ErrorHandler.new(@options[:verbose], logger: @logger)
        end

        # Internal class for error handling
        class ErrorHandler
          include ReVIEW::Loggable

          def initialize(verbose, logger:)
            @verbose = verbose
            @logger = logger
          end

          def handle(err)
            error err.message.to_s
            case err
            when FileNotFoundError
              error 'Please check the file path and try again.'
            when MissingTargetError
              error 'Example: review-ast-compile --target html chapter1.re'
            end

            if @verbose && err.backtrace
              error "\nBacktrace:"
              error err.backtrace.take(10).join("\n")
            end
          end

          def handle_unexpected(err)
            error "Unexpected error occurred: #{err.class}"
            error err.message

            if @verbose && err.backtrace
              error "\nBacktrace:"
              error err.backtrace.join("\n")
            else
              error "\nUse --verbose for more details."
            end
          end
        end
      end
    end
  end
end
