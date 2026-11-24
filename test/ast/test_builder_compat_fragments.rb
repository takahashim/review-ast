# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/idgxml_comparator'
require_relative '../support/review/test/html_comparator'
require_relative '../support/review/test/latex_comparator'
require_relative '../support/review/test/text_comparator'
require 'review/ast/diff/byte_exact'
require 'review/ast/diff/html'
require 'review/ast/diff/latex'
require 'review/ast/compiler'
require 'review/ast/review_generator'
require 'review/ast/json_serializer'
require 'tmpdir'
require 'review/img_math'

# Builder parity for behaviours the corpora do not exercise: settings and
# argument forms that a real book uses but syntax-book/debug-book do not.
# Each case is compared against the legacy builder of every format it applies
# to, so the expectation is the builder's own output, not a hand-written one.
class TestBuilderCompatFragments < Test::Unit::TestCase
  FORMATS = {
    html: ->(config) { [ReVIEW::Test::HtmlComparator.new(config: config), ReVIEW::AST::Diff::Html.new] },
    idgxml: ->(config) { [ReVIEW::Test::IdgxmlComparator.new(config: config), ReVIEW::AST::Diff::ByteExact.new] },
    latex: ->(config) { [ReVIEW::Test::LatexComparator.new(config: config), ReVIEW::AST::Diff::Latex.new] }
  }.freeze

  def assert_parity(source, formats: FORMATS.keys, config: {})
    formats.each do |format|
      comparator, diff = FORMATS.fetch(format).call(Marshal.load(Marshal.dump(config)))
      builder = comparator.convert_with_builder(source)
      renderer = comparator.convert_with_renderer(source)
      result = diff.compare(builder, renderer)
      assert(result.equal?, "#{format} diverges for #{source.inspect} #{config.inspect}:\n#{result.pretty_diff}")
    end
  end

  def assert_text_parity(source, config: {})
    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format, config: config)
      assert_equal comparator.convert_with_builder(source), comparator.convert_with_renderer(source),
                   "#{format} diverges for #{source.inspect} #{config.inspect}"
    end
  end

  # -- @<href> / @<ruby>: Builder splits on unescaped commas, `\,` is a comma

  def test_href_label_with_escaped_comma
    assert_parity("@<href>{http://example.com/?a=1&b, X\\, Y}\n")
    assert_parity("@<href>{http://example.com/?a=1&b, X\\, Y}\n", formats: [:html], config: { 'externallink' => false })
  end

  def test_href_extra_fields_are_dropped_like_the_builder
    assert_parity("@<href>{http://example.com, A, B}\n")
  end

  def test_ruby_with_escaped_comma
    assert_parity("@<ruby>{漢字, かん\\,じ}\n")
    assert_parity("@<ruby>{a\\,b, c, d}\n")
  end

  def test_href_and_ruby_commas_survive_a_round_trip
    source = "= C\n\n@<href>{http://example.com/a\\,b, X\\, Y} @<ruby>{a\\,b, c\\,d}\n"
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(source))
    ast = ReVIEW::AST::Compiler.new.compile_to_ast(chapter)
    regenerated = ReVIEW::AST::ReVIEWGenerator.new.generate(ast)
    assert_include(regenerated, '@<href>{http://example.com/a\\,b, X\\, Y}')
    assert_include(regenerated, '@<ruby>{a\\,b, c\\,d}')
  end

  # -- footnotes and endnotes are numbered in definition order, as
  #    IndexBuilder numbers them, whatever order they are referred to in

  FOOTNOTES_OUT_OF_ORDER = <<~RE
    A@<fn>{a} B@<fn>{b}.

    //emlist[Caption@<fn>{c}]{
    body@<fn>{d}
    //}

    //footnote[b][B]
    //footnote[a][A]
    //footnote[c][C]
    //footnote[d][D]
  RE

  def test_footnotes_are_numbered_in_definition_order
    assert_parity(FOOTNOTES_OUT_OF_ORDER)
    assert_parity(FOOTNOTES_OUT_OF_ORDER, formats: [:latex], config: { 'footnotetext' => true })
    # The text renderers' blank-line layout differs; the numbers must not.
    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format)
      lines = ->(text) { text.lines.reject { |line| line.strip.empty? } }
      assert_equal lines.call(comparator.convert_with_builder(FOOTNOTES_OUT_OF_ORDER)),
                   lines.call(comparator.convert_with_renderer(FOOTNOTES_OUT_OF_ORDER)), format.to_s
    end
  end

  def test_endnotes_are_numbered_in_definition_order
    assert_parity("A@<endnote>{a} B@<endnote>{b}.\n\n//endnote[b][B]\n//endnote[a][A]\n\n//printendnotes\n")
  end

  # -- externallink: false prints the URL instead of linking it

  def test_externallink_off
    ["@<href>{http://example.com, Example}\n", "@<href>{http://example.com}\n", "@<href>{#anchor, Here}\n"].each do |source|
      assert_parity(source, formats: [:html], config: { 'externallink' => false })
    end
  end

  # -- tabwidth applies to every code block, numbered ones counting the prefix

  def test_tabwidth
    %W[//emlist{\n\tA\tB\n//}\n //emlistnum{\na\tb\n\tc\n//}\n //listnum[l][cap]{\na\tb\n//}\n].each do |source|
      assert_parity(source, config: { 'tabwidth' => 4 })
    end
  end

  # -- caption_position: bottom

  CAPTIONS_BOTTOM = { 'caption_position' => { 'image' => 'bottom', 'table' => 'bottom', 'list' => 'bottom', 'equation' => 'bottom' } }.freeze

  def test_captions_bottom
    ["//table[t][cap]{\nA\tB\n------------\nC\tD\n//}\n", "//emtable[cap]{\nA\n//}\n",
     "//list[l][cap]{\nputs 1\n//}\n", "//listnum[l][cap]{\nputs 1\n//}\n"].each do |source|
      assert_parity(source, config: CAPTIONS_BOTTOM)
    end
  end

  def test_text_table_caption_follows_caption_position
    plaintext = ReVIEW::Test::TextComparator.new(format: :plaintext, config: CAPTIONS_BOTTOM).
                convert_with_renderer("//table[t][cap]{\nA\tB\n//}\n")
    assert_operator(plaintext.index("A\tB"), :<, plaintext.index('cap'))
    top = ReVIEW::Test::TextComparator.new(format: :top, config: CAPTIONS_BOTTOM).
          convert_with_renderer("//table[t][cap]{\nA\tB\n//}\n")
    assert_operator(top.index("A\tB"), :<, top.index('cap'))
  end

  # -- @<tcy> in IDGXML (inherited Builder#inline_tcy)

  def test_tcy
    assert_parity("縦@<tcy>{12}横\n")
  end

  # -- @<w>/@<wb>: words_file, and a missing word degrades instead of failing

  def test_words_file_and_missing_words
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'words.csv'), "rails,Ruby on Rails\napi,A & <P>\n")
      # Builder#load_words opens the path relative to the working directory.
      Dir.chdir(dir) do
        source = "A @<w>{rails} B @<wb>{api} C @<w>{nope} D @<wb>{nope2}\n"
        config = { 'words_file' => 'words.csv' }
        assert_parity(source, config: config)
        assert_text_parity(source, config: config)
      end
    end
  end

  # -- block commands the text builders implement and the text renderers did
  #    not (they raised "Unknown block type"). Compared without blank lines:
  #    the text renderers do not reproduce the builders' blank-line layout.

  TEXT_BLOCKS = ["//box[Cap]{\nline1 @<b>{x}\nline2\n//}\n", "//box{\nno caption\n//}\n", "//insn[Cap]{\nA\n//}\n",
                 "//point[P]{\npara1\nstill1\n\npara2\n//}\n", "//term{\nT1\n//}\n", "//bpo{\nb1\n//}\n",
                 "//comment[c]{\nhidden\n//}\n"].freeze

  def test_text_formats_render_every_block_their_builders_do
    [{}, { 'caption_position' => { 'list' => 'bottom' } }, { 'draft' => true }].each do |config|
      TEXT_BLOCKS.each do |source|
        %i[plaintext top].each do |format|
          comparator = ReVIEW::Test::TextComparator.new(format: format, config: config)
          assert_equal text_lines(comparator.convert_with_builder(source)), text_lines(comparator.convert_with_renderer(source)),
                       "#{format} #{config.inspect}: #{source.inspect}"
        end
      end
    end
  end

  def text_lines(text)
    text.lines.map { |line| line.sub(/\A\t+/, '') }.reject { |line| line.strip.empty? }.join
  end

  # -- text formats: what the PBT runner's text modes found

  def assert_text_lines_parity(source, config: {})
    %i[plaintext top].each do |format|
      comparator = ReVIEW::Test::TextComparator.new(format: format, config: config)
      assert_equal text_lines(comparator.convert_with_builder(source)), text_lines(comparator.convert_with_renderer(source)),
                   "#{format} #{config.inspect}: #{source.inspect}"
    end
  end

  def test_a_newline_an_inline_writes_survives_the_paragraph_join
    # The builders join a paragraph's source lines; the text renderers folded
    # every newline, the one @<br> writes included.
    [{}, { 'join_lines_by_lang' => true }].each do |config|
      assert_text_lines_parity("A@<br>{}\nB and\nC@<br>{}D\n", config: config)
      assert_text_lines_parity("A@<raw>{|plaintext,top|x\\ny}B\n", config: config)
      # |text| names no builder (target_name is plaintext / top).
      assert_text_lines_parity("A@<raw>{|text|x}B\n//raw[|text|y]\n\n//embed[text]{\nz\n//}\n", config: config)
      assert_text_lines_parity(" * item@<br>{}more\n continued\n\n 1. one@<br>{}two\n", config: config)
    end
  end

  def test_tabs_are_expanded_in_a_list_body_only
    # Builder#list_body detabs; emlist, the numbered blocks, cmd and source
    # print their tabs as written.
    source = %w[list[l1][L] emlist[E] listnum[l2][N] emlistnum cmd source[S]].map { |cmd| "//#{cmd}{\na\tb\n//}\n" }.join("\n")
    [{}, { 'tabwidth' => 4 }].each { |config| assert_text_lines_parity(source, config: config) }
  end

  def test_ordered_items_keep_their_written_numbers
    assert_text_lines_parity(" 3. a\n 3. b\n 7. c\n\n//olnum[10]\n\n 1. d\n 2. e\n")
  end

  def test_trailing_empty_lines_of_a_numbered_block_are_numbered
    ["//emlistnum{\ncode\n\n\n//}\n", "//listnum[l1][C]{\ncode\n\n//}\n", "//emlistnum{\n\n//}\n"].each do |source|
      assert_text_lines_parity(source)
    end
  end

  # -- a block command the format's builder does not implement is an error,
  #    as in ReVIEW::Compiler#compile_command; some renderers printed it

  UNSUPPORTED = { plaintext: %w[blockquote pagebreak hr parasep], top: %w[pagebreak hr parasep],
                  html: %w[blockquote], latex: %w[talk address blockquote bpo] }.freeze

  def test_a_command_the_builder_lacks_is_an_error
    UNSUPPORTED.each do |format, commands|
      comparator = if FORMATS.key?(format)
                     FORMATS.fetch(format).call({}).first
                   else
                     ReVIEW::Test::TextComparator.new(format: format)
                   end
      commands.each do |command|
        source = ReVIEW::Compiler::SYNTAX.fetch(command.to_sym).block_allowed? ? "//#{command}{\nx\n//}\n" : "//#{command}\n"
        assert_raise(ReVIEW::ApplicationError, "builder: #{format} //#{command}") { comparator.convert_with_builder(source) }
        error = assert_raise(ReVIEW::CompileError, "renderer: #{format} //#{command}") { comparator.convert_with_renderer(source) }
        assert_match(%r{builder does not support command: //#{command}}, error.message)
      end
    end
  end

  def test_a_markdown_thematic_break_is_still_a_rule_in_text
    # The check is for commands written in Re:VIEW source; the Markdown
    # adapter's hr is not one.
    require 'review/ast/markdown_compiler'
    require 'review/renderer/plaintext_renderer'
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.md', StringIO.new("# C\n\nA\n\n---\n\nB\n"))
    ast = ReVIEW::AST::MarkdownCompiler.new.compile_to_ast(chapter)
    assert_nothing_raised { ReVIEW::Renderer::PlaintextRenderer.new(chapter).render(ast) }
  end

  # -- @<raw> / //raw turn \n into a newline, @<embed> / //embed print it as
  #    written (Builder#inline_raw vs #inline_embed); //embed[] names no
  #    format; a newline @<raw> writes survives the HTML paragraph join

  def test_raw_and_embed
    %i[html latex idgxml].each do |format|
      source = "A@<raw>{|#{format}|x\\ny}B@<embed>{|#{format}|p\\nq}C@<embed>{r\\ns}\n\n" \
               "//raw[|#{format}|t\\nu]\n\n//embed[]{\nnone\n//}\n\n//embed[||]{\nnone\n//}\n\n//embed{\nall\n//}\n"
      assert_parity(source, formats: [format])
    end
    assert_text_lines_parity("A@<embed>{|plaintext,top|p\\nq}B\n\n//embed[]{\nnone\n//}\n")
  end

  def test_raw_and_embed_survive_a_round_trip
    source = "= C\n\nA@<raw>{|html|x\\ny}B@<embed>{|latex|\\textbf{z\\}}C@<raw>{w}@<embed>{e}\n\n" \
             "//raw[|html|<hr>\\n<a>\\]x]\n\n//raw[plain]\n\n//embed[html]{\n<p>\n//}\n\n//embed{\nall\n//}\n\n//embed[]{\nnone\n//}\n"
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    compile = lambda do |text|
      chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(text))
      ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
    end
    embeds = lambda do |node|
      own = node.is_a?(ReVIEW::AST::EmbedNode) ? [[node.embed_type, node.target_builders, node.content]] : []
      own + node.children.flat_map { |child| embeds.call(child) }
    end
    original = compile.call(source)
    regenerated = ReVIEW::AST::ReVIEWGenerator.new.generate(original)
    assert_equal embeds.call(original), embeds.call(compile.call(regenerated)), regenerated
    assert_include(regenerated, '//raw[|html|<hr>\\n<a>\\]x]')
    assert_include(regenerated, '@<raw>{|html|')
    assert_include(regenerated, '@<embed>{|latex|')
  end

  # -- what the every-command sweep found

  # The body of an image block is what the builders print when the image is
  # not found (Builder#image_dummy), inline-compiled and detabbed.
  def test_an_unbound_image_prints_its_body
    source = "//image[i1][Cap]{\nart @<b>{x} & <y>\n\tart2\n//}\n\n" \
             "//indepimage[i2][Cap2]{\nindep @<i>{z}\n//}\n\n//numberlessimage[i3]{\nnone\n//}\n"
    assert_parity(source)
    assert_parity(source, config: CAPTIONS_BOTTOM)
    assert_text_lines_parity(source)
  end

  def test_an_inline_op_the_builder_lacks_is_an_error
    { plaintext: %w[abbr kbd var], top: %w[abbr samp] }.each do |format, ops|
      comparator = ReVIEW::Test::TextComparator.new(format: format)
      ops.each do |op|
        source = "A @<#{op}>{x} B\n"
        assert_raise(ReVIEW::ApplicationError, "builder: #{format} @<#{op}>") { comparator.convert_with_builder(source) }
        error = assert_raise(ReVIEW::CompileError, "renderer: #{format} @<#{op}>") { comparator.convert_with_renderer(source) }
        assert_match(/builder does not support inline op: @<#{op}>/, error.message)
      end
    end
  end

  def test_text_imgref_quotes_the_caption_and_dtp_is_dropped
    # An empty caption is still quoted (「」): the legacy index item's caption
    # is a string, so Builder#inline_imgref's `if caption` holds.
    assert_parity("//image[i2][][scale=0.5]{\n//}\n\nSee @<imgref>{i2}.\n")
    assert_text_lines_parity("//image[i1][The caption]{\n//}\n\n//image[i2][]{\n//}\n\nSee @<imgref>{i1}, @<imgref>{i2} @<dtp>{x}.\n")
  end

  def test_bpo_body_is_inline_compiled_line_by_line
    source = "//bpo{\nline1 @<b>{bold} & <x>\n\n\tline3\n//}\n"
    assert_parity(source, formats: %i[html idgxml])
    assert_text_lines_parity(source)
  end

  # //planning, //shoot and the other captionblocks are declared by the
  # builders themselves and written by them; IDGXML used to render them with
  # methods that found no content (and crashed on //shoot[caption]).
  def test_builder_declared_captionblocks
    source = "//planning[Plan @<b>{x}]{\nline1 @<b>{bold}\nline2\n\npara2\n//}\n\n//shoot[Shot]{\ns\n//}\n\n//shoot{\nt\n//}\n\n" \
             "//security[Sec]{\nu\n//}\n\n//best{\nv\n//}\n"
    assert_parity(source, formats: %i[html idgxml])
    assert_text_lines_parity(source)
    assert_parity("//expert{\ne\n//}\n\n//reference{\nr\n//}\n\n//practice{\np\n//}\n\n//link[L]{\nl\n//}\n", formats: [:idgxml])
  end

  # IDGXMLBuilder prints raw content (//embed, //raw, //rawblock), so its
  # newlines -- and none before it -- reach the output under nolf.
  def test_idgxml_raw_content_keeps_its_newlines
    ["== S\n\n//raw[a1]\n", "//list[l1][LC]{\nx\n//}\n\n//embed{\n<a/>\n<b/>\nline\n//}\n\nafter\n",
     "===[column] C\n\ntext\n\n===[/column]\n\n//embed[idgxml]{\nline1\n//}\n",
     "para\n\n//rawblock{\nline1 @<b>{bold} &lt;x&gt;\nline2\n//}\n\nafter\n"].each do |source|
      assert_parity(source, formats: [:idgxml])
    end
  end

  # The builders never look a label up: @<labelref>/@<ref> print a
  # placeholder with the id, whether it names a //label, a numbered item or
  # nothing at all. The AST failed with "Label not found" on every //label.
  def test_label_references_need_no_target
    source = "//label[l1]\n\n//list[li][C]{\nx\n//}\n\nSee @<labelref>{l1} @<ref>{li} @<labelref>{nothing}.\n"
    assert_parity(source, formats: %i[html idgxml])
    assert_text_lines_parity(source)
    assert_text_lines_parity("See @<pageref>{l1}.\n")
    assert_parity("See @<pageref>{l1}.\n", formats: %i[idgxml latex])
  end

  # A short row is padded out to the table width; the padding cell is th or
  # td by its position (Builder#table_rows), not a copy of the row's first
  # cell -- which made HTML print <th> padding in a table without a header.
  def test_ragged_table_padding
    ["//table[t1][C]{\nA\tB\tC\nx\n//}\n", "//table[t2][C]{\nA\tB\n------------\nx\n//}\n",
     "//table[t3][C]{\nA\n------------\nx\ty\n//}\n"].each do |source|
      assert_parity(source)
      assert_text_lines_parity(source)
    end
  end

  # An inline @<raw>/@<embed> in a list item is part of the item's text; the
  # plaintext renderer printed it after the item, like a nested block.
  def test_inline_raw_in_a_list_item
    source = " * a@<embed>{|html,idgxml,plaintext,top|p\\nq}b @<raw>{|html,idgxml,plaintext,top|r}\n   cont\n * next\n\n " \
             "1. one@<raw>{|html,idgxml,plaintext,top|s}\n"
    assert_parity(source, formats: %i[html idgxml])
    assert_text_lines_parity(source)
  end

  # Found by running FirstStepReVIEW-v3 through both paths.
  #
  # LATEXBuilder writes a heading's and a //label's id into \\label as given
  # (macro('label', ...)); escaping "_" made a different label.
  def test_latex_labels_keep_an_underscore
    assert_parity("= C\n\n=={sec_label} Section\n\n//label[my_label]\n\ntext\n", formats: [:latex])
  end

  # A table cell that is just dashes is content; TOP dropped it, as if it
  # were the header separator line.
  def test_a_dash_cell_is_kept
    source = "//table[t1][C]{\nA\t\t-\t\tB\nC\t---\tD\n//}\n"
    assert_parity(source)
    assert_text_lines_parity(source)
  end

  # A //comment in draft mode: its lines inline-compiled, as the builders
  # print them. HTML and LaTeX read a node.content a BlockNode lacks, and so
  # crashed on every //comment{ ... //} (found on FirstStepReVIEW-v3).
  def test_draft_comment
    ["para\n\n//comment{\n  indented & <x> @<b>{y}\nline2\n//}\n\nafter\n", "//comment[arg & <a>]\n\nx\n",
     "//comment[arg]{\nbody\n//}\n", "//comment{\n//}\n"].each do |source|
      assert_parity(source, config: { 'draft' => true })
      assert_text_lines_parity(source, config: { 'draft' => true })
    end
  end

  # review_version 2 compatibility mode (Configure#check_version('2')):
  # LATEXBuilder's older macros. The corpora under it are in
  # test_corpus_config_parity.rb; these are the constructs they lack.
  REVIEW_V2 = { 'review_version' => 2.0 }.freeze

  def test_review_version2_latex
    sources = [
      "@<b>{b} @<i>{i} @<tt>{tt} @<code>{c} @<ttb>{tb} @<tti>{ti} @<m>{x^2}\n",
      "//note[Cap @<b>{x}]{\nbody\n//}\n\n//memo{\nno caption\n//}\n",
      "===[column] Col @<b>{x}\n\nbody\n\n===[/column]\n",
      "//list[l1][C]{\nx\n//}\n\n//emlist{\ny\n//}\n\n//cmd[C]{\nz\n//}\n",
      "//tsize[|latex|p{2cm}l]\n//table[t1][C]{\nA@<br>{}B\tC\n------------\nD@<br>{}E\tF\n//}\n\n//table[t2][]{\nA\tB\n//}\n",
      "//image[i1][Cap]{\nart\n//}\n\n//indepimage[i2][Cap2]\n"
    ]
    sources.each { |source| assert_parity(source, formats: [:latex], config: REVIEW_V2) }
    # Version 2's @<m> pads with spaces; the builder strips the compiled row,
    # so a row's first and last cells lose them (found by the PBT).
    assert_parity("//table[t1][C]{\n@<m>{x}\tB @<m>{y}\n------------\nC\t@<m>{z}\n//}\n", formats: [:latex], config: REVIEW_V2)
    listings = REVIEW_V2.merge('highlight' => { 'latex' => 'listings' })
    assert_parity("//emlist{\nno title\n//}\n\n//emlist[T]{\ntitle\n//}\n\n//list[l1][C]{\nx\n//}\n", formats: [:latex], config: listings)
  end

  # HTML imgmath in version 2: the image is made right away (make_math_image)
  # and the <img> carries no class or alt. ImgMath is stubbed (no latex/dvipng
  # needed) only while the block runs.
  module StubImgMath
    def make_math_image(_str, key, _fontsize = 12)
      Thread.current[:stub_img_math] ? "images/_review_math/_now_#{key[0, 8]}.png" : super
    end

    def defer_math_image(_str, key)
      Thread.current[:stub_img_math] ? "images/_review_math/_later_#{key[0, 8]}.png" : super
    end
  end
  ReVIEW::ImgMath.prepend(StubImgMath)

  def test_review_version2_html_imgmath
    Thread.current[:stub_img_math] = true
    config = { 'math_format' => 'imgmath', 'imgmath_options' => { 'fontsize' => 12, 'lineheight' => 14.4, 'format' => 'png' } }
    source = "A @<m>{E = mc^2} B.\n\n//texequation{\nx^2\n//}\n"
    [config, config.merge(REVIEW_V2)].each { |c| assert_parity(source, formats: [:html], config: c) }
  ensure
    Thread.current[:stub_img_math] = nil
  end

  # Found on youten/howto-create-vr-contents2: an item starting with "["
  # gets \\lbrack{}, or \\item would take "[...]" as its label.
  def test_latex_item_starting_with_a_bracket
    assert_parity(" * [C-1-2] @<code>{x} item\n * normal [x]\n\n 1. [A] one\n", formats: [:latex])
  end

  # A definition runs, as ReVIEW::Compiler#compile_dlist reads it, until a
  # line in column 1, the next term or a list item -- across blank and
  # whitespace-only lines (found on engineers-lt/rooting-book-1). Its blank
  # lines split it into paragraphs in LaTeX and the text formats.
  DEFINITIONS = [" : t1\n    a\u3000\n    \u3000\n     \n    b\n\n : t2\n    c\n\npara\n",
                 " : t1\n\tx\n\n\ty\n\nafter\n", " : t1\n\tx\n\n : t2\n\ty\n", " : t1\n\tx\n * item\n\nafter\n",
                 " : t1\n\tx\n\n  indented para\n\nafter\n", " : t1\n\tx\n\#@ comment\n\ty\n"].freeze

  def test_definition_runs_across_blank_lines
    DEFINITIONS.each do |source|
      [{}, { 'join_lines_by_lang' => true }].each do |config|
        assert_parity(source, config: config)
        assert_text_lines_parity(source, config: config)
      end
    end
  end

  # Found on youten/howto-create-vr-contents2, keymakers/neoJPbook and
  # engineers-lt/rooting-book-1.
  def test_idgxml_footnote_item_and_block_paragraph_details
    # IDGXMLBuilder#inline_fn strips the footnote's text; #ol_item/#ul_item
    # chomp the item, the newline an @<br>{} at its end writes included; only
    # #paragraph turns a leading tab into inlist -- a block's lines keep it.
    ["A@<fn>{f1}.\n\n//footnote[f1][@<href>{http://x.example/} ]\n", " 1. one@<br>{}\n 2. two\n\n * u1@<br>{}\n * u2\n",
     "//lead{\n\tthis line\n\tthe next\n//}\n\n\ttop para\n", "//quote{\n\tq\n//}\n\n//note[N]{\n\ttabbed\n//}\n"].each do |source|
      assert_parity(source, formats: [:idgxml])
    end
  end

  def test_plaintext_item_keeps_an_inline_trailing_space
    # PLAINTEXTBuilder#inline_fn writes " 注1 "; at the end of an item the
    # space stays.
    assert_text_lines_parity(" * item@<fn>{f1}\n\n//footnote[f1][F]\n")
  end

  GENERATOR_ROUND_TRIP = ["//image[i1][Cap]{\nart @<b>{x}\n  art2\n//}\n", "//image[i1][][scale=0.5]{\n//}\n",
                          "//indepimage[i1]{\nart\n//}\n", "//bpo{\nline1 @<b>{bold}\n\nline3\n//}\n",
                          "//box[Cap]{\nline1\n\nline3\n//}\n", "//insn[Cap]{\nline1\n//}\n",
                          "//comment[c]{\nline1\nline2\n//}\n", "//blockquote{\npara1\n\npara2\n//}\n",
                          "//point[P]{\npara1\n//}\n", "//term{\nT1\n//}\n", "//rawblock{\nraw @<b>{x}\n\nline3\n//}\n",
                          "//comment{\n  indented @<b>{x}\n\nline3\n//}\n"].freeze

  def test_blocks_survive_a_round_trip
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    compile = lambda do |text|
      chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new(text))
      ReVIEW::AST::Compiler.new.compile_to_ast(chapter, reference_resolution: false)
    end
    options = ReVIEW::AST::JSONSerializer::Options.new(include_location: false)
    GENERATOR_ROUND_TRIP.each do |block|
      original = compile.call("= C\n\npara\n\n#{block}\nafter\n")
      regenerated = ReVIEW::AST::ReVIEWGenerator.new.generate(original)
      assert_equal original.serialize_to_hash(options), compile.call(regenerated).serialize_to_hash(options), "#{block.inspect} -> #{regenerated.inspect}"
    end
  end

  # -- an inline op nobody declared is an error in every format, as in
  #    ReVIEW::Compiler#compile_inline (the text renderers used to print it)

  def test_undeclared_inline_op_is_an_error
    book = ReVIEW::Book::Base.new(config: ReVIEW::Configure.values)
    chapter = ReVIEW::Book::Chapter.new(book, 1, 'test', 'test.re', StringIO.new("= C\n\nA @<bb>{typo} B\n"))
    error = assert_raise(ReVIEW::CompileError) { ReVIEW::AST::Compiler.new.compile_to_ast(chapter) }
    assert_match(/no such inline op: bb at line 3/, error.message)

    builder_error = assert_raise(ReVIEW::ApplicationError) do
      ReVIEW::Compiler.new(ReVIEW::PLAINTEXTBuilder.new).compile(chapter)
    end
    assert_match(/cannot be compiled/, builder_error.message)
  end

  # -- htmlversion 4 (EPUB2): <tt> instead of <code class="tt">

  def test_html4_monospace
    assert_parity("@<tt>{a} @<ttb>{b} @<tti>{c} @<code>{d}\n", formats: [:html], config: { 'htmlversion' => 4, 'epubversion' => 2 })
  end
end
