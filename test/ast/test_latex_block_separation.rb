# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/review/test/latex_comparator'

# Fast regression tests for the LaTeX block-separation model
# (doc/design-improvements #2). These pin the exact inter-block whitespace that
# LatexRenderer#latex_block_gap produces -- the class of divergence that the
# canonical (whitespace-normalising) LaTeX comparator cannot see and that
# historically only the DVI oracle caught. They assert the exact boundary
# substring in the renderer output, and (where the builder agrees on document
# edges) that the renderer matches the builder byte-for-byte.
class TestLatexBlockSeparation < Test::Unit::TestCase
  def setup
    @conv = ReVIEW::Test::LatexComparator.new
    @conv_ft = ReVIEW::Test::LatexComparator.new(config: { 'footnotetext' => true })
  end

  # //raw content is verbatim: it abuts a following //raw (no gap) but flows
  # into a following paragraph with exactly one newline.
  def test_raw_to_paragraph_single_newline
    out = @conv.convert_with_renderer("//raw[|latex|RAWX]\n\nPara text\n")
    assert_include(out, "RAWX\nPara text")
    assert_not_include(out, "RAWX\n\nPara text")
  end

  def test_raw_to_raw_abuts
    out = @conv.convert_with_renderer("//raw[|latex|AAA]\n\n//raw[|latex|BBB]\n")
    assert_include(out, 'AAABBB')
  end

  def test_raw_to_block_environment_abuts
    out = @conv.convert_with_renderer("//raw[|latex|AAA]\n\n//list[l1][cap]{\nCODE\n//}\n")
    assert_include(out, 'AAA\begin{reviewlistblock}')
  end

  # A block //embed emits a single trailing newline; a following real paragraph
  # supplies its own leading blank (blank line), but a //raw successor abuts
  # with just that single newline.
  def test_block_embed_to_paragraph_blank_line
    out = @conv.convert_with_renderer("//embed[latex]{\nEMB\n//}\n\nPara\n")
    assert_include(out, "EMB\n\nPara")
  end

  def test_block_embed_to_raw_single_newline
    out = @conv.convert_with_renderer("//embed[latex]{\nEMB\n//}\n\n//raw[|latex|BBB]\n")
    assert_include(out, "EMB\nBBB")
    assert_not_include(out, "EMB\n\nBBB")
  end

  def test_block_embed_to_noindent_paragraph_single_newline
    out = @conv.convert_with_renderer("//embed[latex]{\nEMB\n//}\n\n//noindent\nPara\n")
    assert_include(out, "EMB\n\\noindent")
    assert_not_include(out, "EMB\n\n\\noindent")
  end

  # Consecutive minicolumns merge with a single newline (LATEXBuilder#solve_nest),
  # but a minicolumn followed by a real block keeps the blank line.
  def test_minicolumn_nesting_single_newline
    out = @conv.convert_with_renderer("//note{\nA\n//}\n\n//note{\nB\n//}\n")
    assert_include(out, "\\end{reviewnote}\n\\begin{reviewnote}")
    assert_not_include(out, "\\end{reviewnote}\n\n\\begin{reviewnote}")
  end

  def test_minicolumn_to_paragraph_blank_line
    out = @conv.convert_with_renderer("//note{\nA\n//}\n\nPara\n")
    assert_include(out, "\\end{reviewnote}\n\nPara")
  end

  def test_minicolumn_to_pagebreak_single_newline
    out = @conv.convert_with_renderer("//note{\nA\n//}\n\n//pagebreak\n")
    assert_include(out, "\\end{reviewnote}\n\\pagebreak")
    assert_not_include(out, "\\end{reviewnote}\n\n\\pagebreak")
  end

  # A deferred \footnotetext (footnote used in a heading's moving argument, or
  # global footnotetext mode) attaches to a preceding headline or minicolumn --
  # neither of which emits a trailing blank -- with a single newline. These
  # match the builder byte-for-byte.
  def test_headline_to_deferred_footnotetext
    src = "= Head@<fn>{f1}\n\n//footnote[f1][note text]\n\nPara\n"
    renderer = @conv_ft.convert_with_renderer(src)
    builder = @conv_ft.convert_with_builder(src)
    assert_include(renderer, '\\footnotetext[1]{note text}')
    assert_not_include(renderer, "}\n\n\\footnotetext[1]")
    assert_equal builder, renderer
  end

  def test_minicolumn_to_deferred_footnotetext
    src = "//note{\nBody @<fn>{f2}\n//}\n\n//footnote[f2][note2]\n\nPara\n"
    renderer = @conv_ft.convert_with_renderer(src)
    builder = @conv_ft.convert_with_builder(src)
    assert_include(renderer, "\\end{reviewnote}\n\\footnotetext[1]{note2}")
    assert_equal builder, renderer
  end
end
