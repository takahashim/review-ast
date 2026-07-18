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
        (["= 生成された章", ''] + @blocks.flat_map { |b| b + [''] }).join("\n") + "\n"
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
      CODE_CMDS = %w[list emlist listnum cmd source].freeze
      # Valid LaTeX math fragments (always typeset) for //texequation.
      MATH = ['x^2 + y^2', 'E = mc^2', '\\alpha + \\beta', '\\sum_{i=1}^{n} i',
              'a \\times b', '\\frac{1}{2}'].freeze
      # Brace-free math for inline @<m>{...}: a '}' inside would close the inline
      # command early, producing invalid input.
      MATH_INLINE = ['x^2 + y^2', 'E = mc^2', '\\alpha + \\beta', 'a \\times b',
                     '\\pi r^2', 'n - 1'].freeze

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
      def inline_fragment
        case @r.rand(10)
        when 0 then "@<m>{#{pick(MATH_INLINE)}}"             # inline math (brace-free)
        when 1 then "@<ruby>{#{pick(JA_WORDS)},#{safe_word}}" # ruby
        when 2 then "@<idx>{#{safe_word}}"                    # index (invisible)
        else "@<#{pick(DECOR_INLINES)}>{#{safe_word}}"
        end
      end

      # A random run of text, optionally sprinkled with inline commands and
      # @<br>{}. Returns a single string (one logical line of content).
      def phrase(inlines: true)
        parts = Array.new(1 + @r.rand(4)) do
          if inlines && chance(0.4)
            inline_fragment
          else
            chance(0.6) ? pick(JA_WORDS) : pick(EN_WORDS)
          end
        end
        s = parts.join(chance(0.5) ? '' : 'と')
        s += 'です。' if chance(0.5)
        s
      end

      BLOCK_GENERATORS = %i[
        paragraph_block headline_block headline_option_block list_like_block
        nested_list_block code_block code_lang_block minicolumn_block
        wrapper_block footnote_block table_block empty_cell_table_block
        texequation_block column_block noindent_block blankline_block
        beginchild_block comment_block cross_ref_block image_block indepimage_block
      ].freeze

      def random_block
        # Weight paragraphs a bit so documents read like prose with structure.
        return paragraph_block if chance(0.25)

        send(pick(BLOCK_GENERATORS))
      end

      # A paragraph that may span multiple source lines and contain @<br>{}.
      def paragraph_block
        lines = Array.new(1 + @r.rand(3)) do
          s = phrase
          s += '@<br>{}' if chance(0.35) # often at end of a source line
          s
        end
        lines
      end

      def headline_block
        level = 2 + @r.rand(4) # == .. =====
        ['=' * level + ' ' + phrase(inlines: false)]
      end

      # Headline with a nonum/notoc/nodisp option.
      def headline_option_block
        level = 2 + @r.rand(4)
        opt = pick(%w[nonum notoc nodisp])
        ["#{'=' * level}[#{opt}] " + phrase(inlines: false)]
      end

      def list_like_block
        case @r.rand(3)
        when 0 # unordered
          Array.new(2 + @r.rand(3)) { ' * ' + phrase }
        when 1 # ordered
          Array.new(2 + @r.rand(3)).each_with_index.map { |_, i| " #{i + 1}. " + phrase }
        else # definition list
          Array.new(1 + @r.rand(2)).flat_map { [' : ' + phrase, "\t" + phrase] }
        end
      end

      # Unordered/ordered list with a nested sublist (** / continuation).
      def nested_list_block
        if chance(0.5)
          [' * ' + phrase, ' ** ' + phrase, ' ** ' + phrase, ' * ' + phrase]
        else
          [' 1. ' + phrase, ' 1. ' + phrase, ' 2. ' + phrase] # nested ordered via depth
        end
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
        cap = chance(0.7) ? "[#{phrase(inlines: false)}#{chance(0.3) ? '@<br>{}' : ''}]" : ''
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

      # quote / centering / flushright / box / lead block wrappers.
      def wrapper_block
        kind = pick(%w[quote centering flushright lead box])
        ["//#{kind}{", phrase, '', phrase, '//}']
      end

      # A footnote reference together with its definition (self-contained).
      def footnote_block
        id = uid
        [phrase + "@<fn>{#{id}}。", "//footnote[#{id}][#{phrase(inlines: false)}]"]
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

      def indepimage_block
        ["//indepimage[#{uid}][#{phrase(inlines: false)}]{", '//}']
      end

      # Define a target (heading/list/table) and reference it, exercising
      # cross-reference resolution and number formatting.
      def cross_ref_block
        case @r.rand(3)
        when 0 # heading label + @<hd>
          label = uid
          ["=={#{label}} " + phrase(inlines: false), '', "#{phrase}@<hd>{#{label}}を参照。"]
        when 1 # list + @<list>
          id = uid
          ["//list[#{id}][#{phrase(inlines: false)}]{", 'code ' + pick(EN_WORDS), '//}', '',
           "#{phrase}@<list>{#{id}}を参照。"]
        else # table + @<table>
          id = uid
          rows = [pick(JA_WORDS) + "\t" + pick(JA_WORDS), '------------',
                  pick(JA_WORDS) + "\t" + pick(JA_WORDS)]
          ["//table[#{id}][#{phrase(inlines: false)}]{", *rows, '//}', '',
           "#{phrase}@<table>{#{id}}を参照。"]
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
        ["//texequation{", pick(MATH), '//}']
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
