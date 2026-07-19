# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

require 'review/compiler'
require 'review/plaintextbuilder'
require 'review/topbuilder'
require 'review/renderer/plaintext_renderer'
require 'review/renderer/top_renderer'
require 'review/ast'
require 'review/ast/compiler'
require 'review/book'
require 'review/configure'
require 'review/i18n'
require 'stringio'
require 'yaml'

module ReVIEW
  module Test
    # Compares plain-text output from the legacy builders (PLAINTEXTBuilder,
    # TOPBuilder) with the AST renderers (PlaintextRenderer, TopRenderer).
    #
    # LaTeX, HTML and IDGXML each had a comparator against the legacy builder;
    # these two formats did not, so nothing held them to the builders' output.
    # Text is compared byte for byte -- unlike HTML there is no rendered
    # equivalence to fall back on, and unlike LaTeX no typesetting step that
    # would absorb whitespace differences.
    class TextComparator
      # @param format [Symbol] :plaintext or :top
      # @param config [Hash] Extra book configuration
      def initialize(format:, config: {})
        raise ArgumentError, "unknown text format: #{format}" unless FORMATS.key?(format)

        @format = format
        @config = config
      end

      FORMATS = {
        plaintext: { builder: 'PLAINTEXTBuilder', renderer: 'PlaintextRenderer', target: 'plaintext' },
        top: { builder: 'TOPBuilder', renderer: 'TopRenderer', target: 'top' }
      }.freeze

      def builder_class
        ReVIEW.const_get(FORMATS.fetch(@format)[:builder])
      end

      def renderer_class
        ReVIEW::Renderer.const_get(FORMATS.fetch(@format)[:renderer])
      end

      def target_name
        FORMATS.fetch(@format)[:target]
      end

      # Convert Re:VIEW source with the legacy builder.
      # @param source [String] Re:VIEW source content
      # @param chapter [Book::Chapter, nil] Chapter context (optional)
      # @return [String] Generated text
      def convert_with_builder(source, chapter: nil)
        chapter ||= create_temporary_chapter(create_temporary_book, source)

        builder = builder_class.new
        compiler = Compiler.new(builder)
        builder.bind(compiler, chapter, Location.new('test', nil))
        compiler.compile(chapter)

        # result, not raw_result: the text builders post-process the buffer
        # (check_printendnotes and solve_nest for nested lists), and that is what
        # TEXTMaker writes out.
        builder.result
      end

      # Convert Re:VIEW source with the AST renderer.
      # @param source [String] Re:VIEW source content
      # @param chapter [Book::Chapter, nil] Chapter context (optional)
      # @return [String] Generated text
      def convert_with_renderer(source, chapter: nil)
        chapter ||= create_temporary_chapter(create_temporary_book, source)

        ast = ReVIEW::AST::Compiler.for_chapter(chapter).compile_to_ast(chapter)
        renderer_class.new(chapter).render(ast)
      end

      # Convert both ways and return the pair.
      # @param source [String] Re:VIEW source content
      # @return [Hash] :builder and :renderer output
      def convert_both(source)
        {
          builder: convert_with_builder(source),
          renderer: convert_with_renderer(source)
        }
      end

      # Convert one chapter of a real book with both paths, each on its own book
      # instance so neither sees state the other left behind.
      # @param book_dir [String] Path to book project directory
      # @param chapter_name [String] Chapter filename, with or without .re
      # @return [Hash] :builder and :renderer output
      def convert_chapter_with_book_context(book_dir, chapter_name)
        book_dir = File.expand_path(book_dir)
        chapter_name = chapter_name.sub(/\.re$/, '')

        outputs = {}
        { builder: :convert_with_builder, renderer: :convert_with_renderer }.each do |key, method|
          book = load_book(book_dir)
          chapter = book.chapters.find { |ch| ch.name == chapter_name }
          raise "Chapter '#{chapter_name}' not found in book at #{book_dir}" unless chapter

          # Run inside the book directory: imagedir resolves relative to cwd, so
          # image paths only come out right there (as in a production build).
          outputs[key] = Dir.chdir(book_dir) { send(method, nil, chapter: chapter) }
        end
        outputs
      end

      private

      def create_temporary_book
        book_config = Configure.values
        book_config.merge!(@config)
        book_config['language'] = 'ja'
        # Converter#initialize sets this from the builder's target_name, and the
        # AST side reads it for target-specific handling (//tsize, @<embed>).
        book_config['builder'] = target_name

        I18n.setup(book_config['language'])
        Book::Base.new('.', config: book_config)
      end

      def create_temporary_chapter(book, source = '')
        Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(source))
      end

      def load_book(book_dir)
        Dir.chdir(book_dir) do
          book_config = Configure.values
          book_config.merge!(@config)

          config_file = File.join(book_dir, 'config.yml')
          if File.exist?(config_file)
            yaml_config = YAML.safe_load_file(config_file, permitted_classes: [Date, Time, Symbol])
            book_config.merge!(yaml_config) if yaml_config
          end

          book_config['language'] ||= 'ja'
          book_config['builder'] = target_name

          I18n.setup(book_config['language'])

          book = Book::Base.new(book_dir, config: book_config)
          book.generate_indexes
          book
        end
      end
    end
  end
end
