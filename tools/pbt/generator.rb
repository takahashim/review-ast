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

      # A random run of text, optionally sprinkled with inline commands and
      # @<br>{}. Returns a single string (one logical line of content).
      def phrase(inlines: true)
        parts = Array.new(1 + @r.rand(4)) do
          if inlines && chance(0.4)
            cmd = pick(DECOR_INLINES)
            # Inline arguments use only "safe" words: special characters inside
            # fragile (underline-based) macros like @<ins>/@<del>/@<u> produce
            # LaTeX that neither path can typeset, which is not a divergence,
            # just lost coverage. Special-char words still appear as plain text.
            "@<#{cmd}>{#{safe_word}}"
          else
            chance(0.6) ? pick(JA_WORDS) : pick(EN_WORDS)
          end
        end
        s = parts.join(chance(0.5) ? '' : 'と')
        s += 'です。' if chance(0.5)
        s
      end

      def random_block
        case @r.rand(9)
        when 0 then paragraph_block
        when 1 then headline_block
        when 2 then list_like_block
        when 3 then code_block
        when 4 then minicolumn_block
        when 5 then quote_block
        when 6 then footnote_block
        when 7 then table_block
        else paragraph_block
        end
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

      def list_like_block
        case @r.rand(3)
        when 0 # unordered
          Array.new(2 + @r.rand(3)) { ' * ' + phrase }
        when 1 # ordered
          Array.new(2 + @r.rand(3)).each_with_index.map { |_, i| " #{i + 1}. " + phrase }
        else # definition list
          Array.new(1 + @r.rand(2)).flat_map { [' : ' + phrase, '    ' + phrase] }
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

      def minicolumn_block
        kind = pick(MINICOLUMNS)
        cap = chance(0.7) ? "[#{phrase(inlines: false)}#{chance(0.3) ? '@<br>{}' : ''}]" : ''
        ["//#{kind}#{cap}{", phrase, '', phrase, '//}']
      end

      def quote_block
        ['//quote{', phrase, '', phrase, '//}']
      end

      # A footnote reference together with its definition (self-contained).
      def footnote_block
        id = uid
        [phrase + "@<fn>{#{id}}。", "//footnote[#{id}][#{phrase(inlines: false)}]"]
      end

      def table_block
        id = uid
        rows = Array.new(2 + @r.rand(2)) do
          Array.new(2 + @r.rand(2)) { pick(JA_WORDS) }.join("\t")
        end
        ["//table[#{id}][#{phrase(inlines: false)}]{", rows.first, '------------', *rows[1..], '//}']
      end
    end
  end
end
