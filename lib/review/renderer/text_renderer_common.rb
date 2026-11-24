# frozen_string_literal: true

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module Renderer
    # What the two plain-text renderers genuinely share.
    #
    # PlaintextRenderer and TopRenderer look like near-twins, but of the 36
    # methods they have in common only these produce identical output: TOP
    # wraps almost every block in "◆→開始:…←◆" markers that plaintext has no
    # equivalent for, so the rest differ in substance rather than in decoration.
    # Rather than force the pair under a template-method base class whose hooks
    # would each have one real implementation, this holds only the methods that
    # were byte-identical in both.
    module TextRendererCommon
      def visit_document(node)
        render_children(node)
      end

      def visit_text(node)
        node.content || ''
      end

      def visit_block_blankline(_node)
        "\n"
      end

      # Labels carry no text in either format.
      def visit_block_label(_node)
        ''
      end

      def visit_block_printendnotes(_node)
        # Print all endnotes collected from the AST (doc/design-improvements #7).
        return '' if endnote_nodes.empty?

        result = +''
        endnote_nodes.each do |en|
          # Format: (number) content -- the endnote's own node is its content.
          number = en.definition_number.number
          result += "(#{number}) #{render_children(en)}\n"
        end
        result
      end

      # An //endnote defines content that //printendnotes prints later, so the
      # definition itself renders as nothing where it stands. Without this both
      # text renderers printed each endnote twice: once as a footnote at the
      # point of definition, once in the //printendnotes block. The LaTeX and
      # HTML renderers already had this guard.
      def endnote_definition?(node)
        node.footnote_type == :endnote
      end

      # The section number an @<sec> names ("2.1.2"), chapter included.
      # Builder#inline_sec errors when the target has no number; here an
      # unnumbered target simply contributes nothing, which is what the rest of
      # the renderers do with a suppressed number.
      def section_number_of(node)
        data = resolved_data_of(node)
        number = data.headline_number
        chapter_number = text_formatter.format_chapter_number_short(data.chapter_number, data.chapter_type)
        return '' if number.nil? || number.empty? || chapter_number.to_s.empty?
        return '' unless text_formatter.over_secnolevel?(number)

        ([chapter_number] + number).join('.')
      end

      # The section title an @<sectitle> names, with no number and no quotes --
      # Builder#inline_sectitle. Both text renderers used to let @<sec> and
      # @<sectitle> fall through to the @<hd> form ("「2.1.2 図」"), so three
      # different commands printed the same thing.
      def section_title_of(node)
        data = resolved_data_of(node)
        data.caption_node ? render_children(data.caption_node) : data.caption_text.to_s
      end

      # An @<chapref>'s text.
      #
      # chapterlink is deliberately not honored: plain text has nowhere to put a
      # link. PLAINTEXTBuilder used to emit IDGXML's <link> tag here, carried
      # over with the rest of a copied method; that is fixed upstream on
      # fix-plaintext-chapterlink.
      def chapter_reference_text(data)
        return text_formatter.format_chapref_version2(data) if review_version2?

        text_formatter.format_reference(:chapter, data)
      end

      # The chapter title an @<title> names, alone -- no number, no quotes
      # (Builder#inline_title). Both text renderers used to let @<title> fall
      # through to the reference's own rendering, which is the @<chapref> form
      # ("第1章「章見出し」").
      def chapter_title_of(node)
        resolved_data_of(node).chapter_title || ''
      end

      # The ResolvedData behind an inline command that wraps a reference.
      # Builder#inline_imgref: the @<img> text, then the image's caption (as
      # written) in I18n 'image_quote' -- an empty caption too (「」), as the
      # legacy index item's caption is always a string.
      def image_reference_with_caption(node, content)
        "#{content}#{I18n.t('image_quote', resolved_data_of(node).caption_text.to_s)}"
      end

      def resolved_data_of(node)
        ref_node = node.children.first
        unless ref_node.reference_node? && ref_node.resolved?
          raise 'BUG: Reference should be resolved at AST construction time'
        end

        ref_node.resolved_data
      end
    end
  end
end
