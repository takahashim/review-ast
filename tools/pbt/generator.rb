# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module PBT
    # A generated Re:VIEW document, represented as an ordered list of blocks.
    # Each block is an array of source lines. The structure is deliberately
    # block-granular so that shrinking can drop or simplify whole blocks.
    class Document
      attr_reader :blocks

      # @param blocks [Array<Array<String>>] each block is an array of .re lines
      def initialize(blocks)
        @blocks = blocks
      end

      def to_re
        # A leading level-1 headline so the chapter has a title; blocks are
        # separated by blank lines (the paragraph/block separator in Re:VIEW).
        blocks = @blocks
        # Endnotes require exactly one //printendnotes at the document level.
        if blocks.any? { |b| b.any? { |l| l.include?('@<endnote>') } }
          blocks += [['//printendnotes']]
        end
        (['= 生成された章', ''] + blocks.flat_map { |b| b + [''] }).join("\n") + "\n"
      end

      # Shrink candidates: documents that are strictly "smaller" than this one.
      # Order matters -- cheaper/bigger reductions first.
      def shrinks
        out = []
        # 1. drop each block
        @blocks.each_index do |i|
          out << Document.new(@blocks[0...i] + @blocks[(i + 1)..])
        end
        # 2. bisect: keep first / second half
        if @blocks.size > 2
          mid = @blocks.size / 2
          out << Document.new(@blocks[0...mid])
          out << Document.new(@blocks[mid..])
        end
        out
      end

      def size
        @blocks.sum(&:size)
      end
    end

    # Seed-deterministic generator of small, self-contained Re:VIEW documents.
    #
    # It favours the constructs where builder/renderer divergences have actually
    # been found: inline commands inside paragraphs (especially @<br>{}), code
    # blocks (tabs, blank lines), lists, and minicolumns with captions/footnotes.
    class Generator
      JA_WORDS = %w[文章 記法 見出し 段落 本文 命令 出力 変換 参照 例 表 図
                    番号 空行 改行 桁 幅 組版 一致 検証 生成 構造].freeze
      EN_WORDS = %w[Re:VIEW LaTeX Markdown code list table image ident value
                    foo_bar baz.qux 100% a<b c>d {x} $y a&b].freeze
      # Words free of LaTeX special characters, safe as inline-command arguments.
      SAFE_WORDS = %w[Re:VIEW LaTeX Markdown code list table image ident value].freeze

      # Self-contained inline decorations that wrap arbitrary text and are
      # implemented by BOTH LATEXBuilder and the AST renderer. Excluded:
      #   - ops unsupported by LATEXBuilder (big, dfn, hint, kbd, q, samp,
      #     small, var) -- we can only diff inputs both paths compile;
      #   - uchar, which takes a numeric codepoint rather than text, so feeding
      #     it words is invalid input (paths may disagree on garbage).
      DECOR_INLINES = %w[b i code tt kw em strong u ins del sup sub ttb tti
                         bou ami].freeze

      MINICOLUMNS = %w[note memo tip info warning important caution notice].freeze
      CODE_CMDS = %w[list emlist listnum emlistnum cmd source].freeze
      # Valid LaTeX math fragments (always typeset) for //texequation.
      MATH = ['x^2 + y^2', 'E = mc^2', '\\alpha + \\beta', '\\sum_{i=1}^{n} i',
              'a \\times b', '\\frac{1}{2}'].freeze
      # Brace-free math for inline @<m>{...}: a '}' inside would close the inline
      # command early, producing invalid input.
      MATH_INLINE = ['x^2 + y^2', 'E = mc^2', '\\alpha + \\beta', 'a \\times b',
                     '\\pi r^2', 'n - 1'].freeze

      BLOCK_GENERATORS = %i[
        paragraph_block headline_block headline_option_block list_like_block
        nested_list_block code_block code_lang_block minicolumn_block
        wrapper_block footnote_block table_block empty_cell_table_block
        texequation_block column_block noindent_block blankline_block
        beginchild_block comment_block cross_ref_block image_block indepimage_block
        numbered_equation_block embed_block endnote_block tsize_table_block imgtable_block
        firstlinenum_block inline_cell_table_block pagebreak_block caption_footnote_block
        olnum_block parasep_block
      ].freeze

      def initialize(seed)
        @r = Random.new(seed)
        @counter = 0
      end

      def document(n_blocks: nil)
        n = n_blocks || (2 + @r.rand(5))
        Document.new(Array.new(n) { random_block })
      end

      private

      def uid
        @counter += 1
        "g#{@counter}"
      end

      def pick(arr) = arr[@r.rand(arr.size)]
      def chance(p) = @r.rand < p
      def safe_word = chance(0.6) ? pick(JA_WORDS) : pick(SAFE_WORDS)

      # One inline command occurrence. Inline arguments use only "safe" words:
      # special characters inside fragile (underline-based) macros like
      # @<ins>/@<del>/@<u> produce LaTeX that neither path can typeset, which is
      # not a divergence -- just lost coverage. Special-char words still appear
      # as plain text elsewhere.
      # cell_safe excludes inlines that render to "" in HTML/IDGXML. An
      # empty-rendering *table cell* triggers a builder cell-shift quirk (see
      # doc/spec-questions.md #2) that the renderer deliberately does not match,
      # so feeding one into a cell produces a builder-only "divergence", not a
      # useful one. @<raw>{|latex|...} is non-empty for LaTeX (so the LaTeX sweep
      # keeps its cell coverage) but empty for HTML/IDGXML, so it is dropped only
      # from cell context.
      def inline_fragment(cell_safe: false)
        # NOTE: @<comment> is intentionally excluded. It renders to "" (non-draft),
        # and an empty-rendering *table cell* triggers a LATEXBuilder cell-shift
        # quirk (see doc/spec-questions.md), which is a builder bug, not a renderer
        # one -- feeding it here just produces builder-only failures, not useful
        # divergences.
        roll = @r.rand(16)
        roll = 17 if roll == 7 && cell_safe # route @<raw> to the decor default
        # TOP's @<balloon> writes a tab, which TOPBuilder then splits the row
        # on: an extra cell (doc/spec-questions.md #9). Not in cells either.
        roll = 17 if roll == 9 && cell_safe
        case roll
        when 0 then "@<m>{#{pick(MATH_INLINE)}}" # inline math (brace-free)
        when 1 then "@<ruby>{#{pick(JA_WORDS)},#{safe_word}}" # ruby
        when 2 then "@<idx>{#{safe_word}}"                    # index (invisible)
        when 3 then "@<kw>{#{safe_word},#{safe_word}}"        # keyword with reading
        when 4 then "@<hidx>{#{safe_word}}"                   # hidden index
        when 8 then "@<hidx>{#{safe_word}<<>>#{safe_word}}"   # hidden index, hierarchical (parent<<>>child)
        when 9 then "@<balloon>{#{safe_word}}"                # balloon annotation
        when 5 then "@<href>{https://example.com/#{safe_word}, #{safe_word}}" # link with text
        when 6 then '@<href>{https://example.com/}' # bare link
        # Raw LaTeX passthrough. Content must be a brace-free control *symbol*:
        #   - a '{' or '}' breaks the @<raw>{...} inline parser (a literal `{}`
        #     comes out as `{\}`, malformed for both paths), and
        #   - a bare control *word* (\TeX, \LaTeX) absorbs the following letter
        #     or kana into its name (upTeX scans `\TeXと`/`\LaTeXB` as one
        #     undefined control sequence), which neither path can typeset.
        # The thin-space control symbol \, is text-mode-valid, brace-free, and
        # never scans the next character, so it is safe before any text. It must
        # also have no *trailing* space: a control space `\ ` is rstripped to a
        # lone `\` by LATEXBuilder in table cells / at line ends, which then
        # escapes the following `}` and breaks the cell (the renderer keeps the
        # space, so only the builder fails). (@<tcy> is excluded -- it needs
        # vertical layout, which the horizontal jsbook harness can't typeset.)
        when 7 then '@<raw>{|latex|\\,}'
        else "@<#{pick(DECOR_INLINES)}>{#{safe_word}}"
        end
      end

      # A random run of text, optionally sprinkled with inline commands and
      # @<br>{}. Returns a single string (one logical line of content).
      def phrase(inlines: true, cell_safe: false)
        parts = Array.new(1 + @r.rand(4)) do
          if inlines && chance(0.4)
            inline_fragment(cell_safe: cell_safe)
          else
            chance(0.6) ? pick(JA_WORDS) : pick(EN_WORDS)
          end
        end
        s = parts.join(chance(0.5) ? '' : 'と')
        s += 'です。' if chance(0.5)
        s
      end

      def random_block
        # Weight paragraphs a bit so documents read like prose with structure.
        return paragraph_block if chance(0.25)

        send(pick(BLOCK_GENERATORS))
      end

      # A paragraph that may span multiple source lines and contain @<br>{}.
      def paragraph_block
        Array.new(1 + @r.rand(3)) do
          s = phrase
          s += '@<br>{}' if chance(0.35) # often at end of a source line
          s
        end
      end

      def headline_block
        level = 2 + @r.rand(4) # == .. =====
        # Headings may carry inline commands (@<b>, @<code>, ...); the builder
        # escapes/compiles heading text, so this stays typesettable.
        [('=' * level) + ' ' + phrase(inlines: chance(0.5))]
      end

      # Headline with a nonum/notoc/nodisp option.
      def headline_option_block
        level = 2 + @r.rand(4)
        opt = pick(%w[nonum notoc nodisp])
        ["#{'=' * level}[#{opt}] " + phrase(inlines: false)]
      end

      def list_like_block
        case @r.rand(3)
        when 0 # unordered, items may have continuation lines
          Array.new(2 + @r.rand(3)).flat_map { [' * ' + phrase, *item_continuation] }
        when 1 # ordered, items may have continuation lines
          Array.new(2 + @r.rand(3)).each_with_index.flat_map { |_, i| [" #{i + 1}. " + phrase, *item_continuation] }
        else # definition list
          Array.new(1 + @r.rand(2)).flat_map { [' : ' + phrase, "\t" + phrase] }
        end
      end

      # Zero or more continuation lines for a list item (indented lines that are
      # not new list markers). LATEXBuilder keeps their source newlines; a line
      # starting with an ASCII token exercises the ASCII-boundary space.
      def item_continuation
        return [] unless chance(0.4)

        Array.new(1 + @r.rand(2)) { '   ' + (chance(0.5) ? "#{pick(%w[a. b. i. ii.])} #{phrase}" : phrase) }
      end

      # Unordered/ordered list with nested sublists (**/*** depth).
      def nested_list_block
        if chance(0.5)
          # Unordered nesting up to 4 levels deep (*, **, ***, ****).
          [' * ' + phrase, ' ** ' + phrase, ' *** ' + phrase, ' **** ' + phrase,
           ' *** ' + phrase, ' ** ' + phrase, ' * ' + phrase]
        else
          [' 1. ' + phrase, ' 1. ' + phrase, ' 2. ' + phrase] # nested ordered via depth
        end
      end

      # //olnum sets the counter for the following ordered list, so its items
      # start at a custom number (exercises the \setcounter{enumi} path).
      def olnum_block
        start = 2 + @r.rand(20)
        [
          "//olnum[#{start}]", '',
          " #{start}. " + phrase,
          " #{start + 1}. " + phrase
        ]
      end

      def code_block
        cmd = pick(CODE_CMDS)
        id = %w[list listnum].include?(cmd) ? "[#{uid}]" : ''
        cap = "[#{phrase(inlines: false)}]"
        head = "//#{cmd}#{id}#{cap}{"
        body = Array.new(1 + @r.rand(4)) do
          # deliberately include tabs and blank lines -- both are whitespace
          # that only DVI-level comparison can see.
          if chance(0.3)
            ''
          elsif chance(0.4)
            "col1\tcol2\tcol3"
          else
            'code ' + pick(EN_WORDS)
          end
        end
        [head, *body, '//}']
      end

      # //list or //emlist with an explicit language argument. //list takes an
      # id ([id][caption][lang]); //emlist does not ([caption][lang]).
      def code_lang_block
        lang = pick(%w[ruby c java text])
        body = ['code ' + pick(EN_WORDS), '//}']
        if chance(0.5)
          ["//list[#{uid}][#{phrase(inlines: false)}][#{lang}]{", *body]
        else
          ["//emlist[#{phrase(inlines: false)}][#{lang}]{", *body]
        end
      end

      def minicolumn_block
        kind = pick(MINICOLUMNS)
        cap = if chance(0.7)
                "[#{phrase(inlines: false)}#{chance(0.3) ? '@<br>{}' : ''}]"
              else
                ''
              end
        body = [phrase, '']
        # sometimes nest a list or code block inside the minicolumn
        body += nested_inner if chance(0.4)
        body << phrase
        ["//#{kind}#{cap}{", *body, '//}']
      end

      # A small nested block (list or code) for embedding inside wrappers.
      def nested_inner
        if chance(0.5)
          [' * ' + phrase, ' * ' + phrase, '']
        else
          ['//emlist{', 'code ' + pick(EN_WORDS), '//}', '']
        end
      end

      # quote / centering / flushright / box / lead block wrappers. Content is a
      # mix of single- and multi-line paragraphs: a multi-line paragraph (two
      # adjacent lines, no blank between) exercises the :block line join, which
      # differs from an ordinary paragraph (LATEXBuilder joins these with "").
      def wrapper_block
        kind = pick(%w[quote centering flushright lead box])
        body = [phrase]
        body += [phrase] if chance(0.5) # second line of the same paragraph
        body << ''
        body << phrase
        ["//#{kind}{", *body, '//}']
      end

      # A footnote reference together with its definition (self-contained).
      def footnote_block
        id = uid
        [phrase + "@<fn>{#{id}}。", "//footnote[#{id}][#{phrase(inlines: false)}]"]
      end

      # A block whose caption carries a footnote (@<fn> in a //list/table/image
      # caption), with the definition appended. Exercises \footnotetext
      # placement for footnotes collected from captions.
      def caption_footnote_block
        fid = uid
        cap = "#{phrase(inlines: false)}@<fn>{#{fid}}"
        fn = "//footnote[#{fid}][#{phrase(inlines: false)}]"
        case @r.rand(3)
        when 0
          ["//list[#{uid}][#{cap}]{", 'code ' + pick(EN_WORDS), '//}', fn]
        when 1
          rows = [pick(JA_WORDS) + "\t" + pick(JA_WORDS), '------------',
                  pick(JA_WORDS) + "\t" + pick(JA_WORDS)]
          ["//table[#{uid}][#{cap}]{", *rows, '//}', fn]
        else
          ["//image[#{uid}][#{cap}]{", '//}', fn]
        end
      end

      # An //image (with optional metric) sometimes referenced via @<img>.
      # The image file need not exist: Re:VIEW emits a reviewdummyimage
      # placeholder, which typesets without a file.
      def image_block
        id = uid
        cap = phrase(inlines: false)
        head = if chance(0.4)
                 "//image[#{id}][#{cap}][scale=#{pick(%w[0.5 0.8 1.2])}]{"
               else
                 "//image[#{id}][#{cap}]{"
               end
        lines = [head, '//}']
        lines += ['', "#{phrase}@<img>{#{id}}参照。"] if chance(0.6)
        lines
      end

      # //indepimage or //numberlessimage -- both unnumbered (they go to
      # indepimage_index, not the numbered image_index), so neither is referenced
      # via @<img>. Renders as a reviewdummyimage placeholder when the file is
      # missing.
      def indepimage_block
        kind = chance(0.5) ? 'indepimage' : 'numberlessimage'
        ["//#{kind}[#{uid}][#{phrase(inlines: false)}]{", '//}']
      end

      # A forced page break (control command, no arguments).
      def pagebreak_block
        ['//pagebreak']
      end

      # A paragraph separator (control command, no arguments), between paragraphs.
      def parasep_block
        [phrase, '', '//parasep', '', phrase]
      end

      # An endnote reference plus its definition. A single //printendnotes is
      # appended by Document#to_re when any endnote is present.
      def endnote_block
        id = uid
        [phrase + "@<endnote>{#{id}}。", "//endnote[#{id}][#{phrase(inlines: false)}]"]
      end

      # A //table preceded by a //tsize column specification.
      def tsize_table_block
        id = uid
        spec = pick(['|latex||p{20mm}|p{20mm}|', '10,20', '|latex||l|c|r|'])
        cols = spec.include?('r') ? 3 : 2
        rows = [Array.new(cols) { pick(JA_WORDS) }.join("\t"), '------------',
                Array.new(cols) { pick(JA_WORDS) }.join("\t")]
        ["//tsize[#{spec}]", "//table[#{id}][#{phrase(inlines: false)}]{", *rows, '//}']
      end

      # An //imgtable (rendered as a dummy image when the file is missing).
      def imgtable_block
        ["//imgtable[#{uid}][#{phrase(inlines: false)}]{", '//}']
      end

      # A //listnum whose numbering starts at a custom first line via //firstlinenum.
      def firstlinenum_block
        ["//firstlinenum[#{1 + @r.rand(200)}]",
         "//listnum[#{uid}][#{phrase(inlines: false)}]{", 'code a', 'code b', '//}']
      end

      # A //table whose cells contain inline commands.
      def inline_cell_table_block
        rows = ["#{phrase(cell_safe: true)}\t#{phrase(cell_safe: true)}", '------------',
                "#{phrase(cell_safe: true)}\t#{phrase(cell_safe: true)}"]
        ["//table[#{uid}][#{phrase(inlines: false)}]{", *rows, '//}']
      end

      # Define a target (heading/list/table/column) and reference it, exercising
      # cross-reference resolution and number formatting.
      def cross_ref_block
        case @r.rand(6)
        when 0 # numbered section (level 2, within secnolevel) + @<hd>
          label = uid
          ["=={#{label}} " + phrase(inlines: false), '', "#{phrase}@<hd>{#{label}}を参照。"]
        when 1 # list + @<list>
          id = uid
          ["//list[#{id}][#{phrase(inlines: false)}]{", 'code ' + pick(EN_WORDS), '//}', '',
           "#{phrase}@<list>{#{id}}を参照。"]
        when 2 # table + @<table>
          id = uid
          rows = [pick(JA_WORDS) + "\t" + pick(JA_WORDS), '------------',
                  pick(JA_WORDS) + "\t" + pick(JA_WORDS)]
          ["//table[#{id}][#{phrase(inlines: false)}]{", *rows, '//}', '',
           "#{phrase}@<table>{#{id}}を参照。"]
        when 3 # unnumbered subsection (level 3, beyond default secnolevel) + @<hd>/@<secref>
          # @<hd>/@<secref> to an unnumbered heading must show the title alone,
          # not a spurious number -- matching LATEXBuilder#inline_hd_chap.
          child = uid
          op = pick(%w[hd secref sectitle])
          ['== ' + phrase(inlines: false), '',
           "==={#{child}} " + phrase(inlines: false), '',
           "#{phrase}@<#{op}>{#{child}}を参照。"]
        when 4 # numbered section referenced by @<sec>/@<secref>/@<sectitle>
          # @<sec> requires a numbered target (a level-2 section is numbered at
          # the default secnolevel=2), otherwise both paths error.
          label = uid
          op = pick(%w[sec secref sectitle])
          ["=={#{label}} " + phrase(inlines: false), '', "#{phrase}@<#{op}>{#{label}}を参照。"]
        else # labeled column + @<column>
          label = uid
          ["==[column]{#{label}} " + phrase(inlines: false), '', phrase, '',
           '==[/column]', '', "#{phrase}@<column>{#{label}}を参照。"]
        end
      end

      # A block or inline comment (invisible output).
      def comment_block
        if chance(0.5)
          ['//comment{', phrase(inlines: false), '//}']
        else
          ['#@# ' + phrase(inlines: false), phrase]
        end
      end

      def table_block
        id = uid
        rows = Array.new(2 + @r.rand(2)) do
          Array.new(2 + @r.rand(2)) { pick(JA_WORDS) }.join("\t")
        end
        ["//table[#{id}][#{phrase(inlines: false)}]{", rows.first, '------------', *rows[1..], '//}']
      end

      # Table exercising empty cells ('.') and ragged rows.
      def empty_cell_table_block
        rows = [
          %w[A B C].join("\t"),
          '------------',
          ['.', pick(JA_WORDS), '.'].join("\t"),
          [pick(JA_WORDS), '.', pick(JA_WORDS)].join("\t")
        ]
        ["//table[#{uid}][#{phrase(inlines: false)}]{", *rows, '//}']
      end

      # Display math. Content is drawn from a fixed pool so it always typesets.
      def texequation_block
        ['//texequation{', pick(MATH), '//}']
      end

      # A numbered equation referenced via @<eq>.
      def numbered_equation_block
        id = uid
        ["//texequation[#{id}][#{phrase(inlines: false)}]{", pick(MATH), '//}', '',
         "#{phrase}@<eq>{#{id}}参照。"]
      end

      # Embedded raw LaTeX (passthrough). Fixed safe fragments so it typesets.
      def embed_block
        ['//embed[latex]{', pick(['\\textbf{bold}', '\\emph{em}', '\\LaTeX{}', 'plain']), '//}']
      end

      # A column (==[column] .. ==[/column]) possibly with a subsection inside.
      def column_block
        body = [phrase, '']
        body += ['==== ' + phrase(inlines: false), '', phrase, ''] if chance(0.5)
        ['==[column] ' + phrase(inlines: false), '', *body, '==[/column]']
      end

      # A paragraph forced with //noindent.
      def noindent_block
        ['//noindent', phrase]
      end

      def blankline_block
        ['//blankline']
      end

      # A list item interrupted by //beginchild .. //endchild and continued.
      def beginchild_block
        [' 1. ' + phrase, ' 2. ' + phrase, '',
         '//beginchild', '', ' * ' + phrase, ' * ' + phrase, '', '//endchild', '',
         ' 3. ' + phrase]
      end
    end
  end
end
