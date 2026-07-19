# frozen_string_literal: true

require 'nokogiri'
require 'diff/lcs'
require 'digest'
require 'unicode/eaw'
require_relative 'result'

# Copyright (c) 2025 Kenshi Muto, Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  module AST
    module Diff
      # Html comparator: compares two HTML fragments for *rendered* equivalence,
      # following the HTML parsing spec (via Nokogiri's HTML5 / WHATWG parser) and
      # the CSS Text 3 white-space processing model.
      #
      # The point of being spec-compliant is that whitespace is compared the way a
      # browser would render it, rather than being blindly normalized away:
      #
      # - Whitespace inside an inline formatting context is COLLAPSIBLE: runs of
      #   spaces/tabs/newlines collapse to a single space, and leading/trailing
      #   whitespace of a block's inline content (and around forced <br> breaks) is
      #   trimmed. Crucially, a single space BETWEEN inline elements is significant
      #   -- `<b>a</b> <b>b</b>` ("a b") must NOT compare equal to `<b>a</b><b>b</b>`
      #   ("ab").
      # - A newline (segment break) is transformed per CSS Text 3 §4.1.2: it is
      #   REMOVED (no space) when the characters on both sides are CJK
      #   (East Asian Width Fullwidth/Wide/Halfwidth, non-Hangul), otherwise it
      #   becomes a space. This matches how browsers lay out Japanese text.
      # - Whitespace between block-level elements is not rendered, so it is dropped.
      # - Whitespace inside a preformatted element (pre/textarea/...) is preserved
      #   verbatim.
      #
      # Block vs inline is decided from the HTML rendering spec's default UA
      # stylesheet display roles (both compared documents share the same CSS, so
      # any author overrides apply symmetrically).
      class Html
        # Elements whose text content is preserved verbatim (not collapsed):
        # white-space: pre display (pre/textarea/...) and raw-text elements whose
        # content is code, where every space matters (script/style).
        PRESERVE_TEXT_ELEMENTS = %w[pre textarea xmp listing plaintext script style].freeze

        # Elements whose default display is block-level / table-model / list-item
        # (HTML rendering spec UA stylesheet). They establish block boundaries:
        # collapsible whitespace does not flow across them and is trimmed at their
        # edges. Everything not listed here (and not a <br>) is treated as inline.
        BLOCK_ELEMENTS = %w[
          html body address article aside blockquote center details dialog dd div dl dt
          fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hgroup hr li
          main menu nav ol p pre section summary ul
          table caption colgroup col thead tbody tfoot tr td th
        ].freeze

        VOID_ELEMENTS = %w[area base br col embed hr img input link meta param source track wbr].freeze

        PreparedData = Struct.new(:tokens, :signature, keyword_init: true)

        def initialize
        end

        # @param left [String] First HTML content
        # @param right [String] Second HTML content
        # @return [Result]
        def compare(left, right)
          left_data = prepare(left)
          right_data = prepare(right)
          changes = ::Diff::LCS.sdiff(left_data.tokens, right_data.tokens)
          Result.new(left_data.signature, right_data.signature, changes)
        end

        # @return [Boolean]
        def equal?(left, right)
          compare(left, right).equal?
        end

        # @return [String]
        def diff(left, right)
          compare(left, right).pretty_diff
        end

        private

        def prepare(html)
          doc = Nokogiri::HTML5.parse(html)
          doc.xpath('//comment()').remove
          tokens = Serializer.new.run(doc)
          signature = Digest::SHA1.hexdigest(tokens.map { |t| Array(t).join('␟') }.join('␞'))
          PreparedData.new(tokens: tokens, signature: signature)
        end

        # Walks a parsed document and emits a canonical token stream applying the
        # CSS Text 3 white-space model. Token shapes match the previous comparator
        # so Result#pretty_diff keeps working:
        #   [:start, name, [[attr, val], ...]] / [:end, name]
        #   [:void, name, [[attr, val], ...]] / [:text, "content"]
        class Serializer
          def initialize
            @tokens = []
            @buf = +'' # committed inline text not yet flushed as a :text token
            @pending_newline = false # the collapsed whitespace run being held contained a segment break
            @pending_space = false   # a collapsible whitespace run is held, awaiting the next character
            @at_line_start = true    # suppress a leading collapsible space (block start / after <br>)
            @last_char = nil         # last emitted non-space character (for the segment-break rule)
          end

          def run(node)
            walk(node, pre: false)
            flush_buf
            @tokens
          end

          private

          def walk(node, pre:)
            node.children.each do |child|
              if child.text?
                pre ? emit_pre_text(child.text) : consume_collapsible(child.text)
              elsif child.element?
                visit_element(child, pre: pre)
              end
            end
          end

          def visit_element(el, pre:)
            name = el.name
            if name == 'br'
              # Forced line break: trims collapsible whitespace on both sides.
              @pending_space = @pending_newline = false
              flush_buf
              @tokens << [:void, name, attrs_of(el)]
              @at_line_start = true
            elsif VOID_ELEMENTS.include?(name)
              # Inline replaced/void element (img, wbr, ...): it is content, so a
              # held space before it is significant and must be committed.
              commit_pending
              flush_buf
              @tokens << [:void, name, attrs_of(el)]
              @at_line_start = false
              @last_char = nil
            elsif BLOCK_ELEMENTS.include?(name)
              enter_block_boundary
              @tokens << [:start, name, attrs_of(el)]
              walk(el, pre: pre || PRESERVE_TEXT_ELEMENTS.include?(name))
              enter_block_boundary
              @tokens << [:end, name]
            else
              # Inline element: whitespace flows through it. Keep any held space
              # pending (it will attach to the next character, wherever it sits).
              flush_buf
              @tokens << [:start, name, attrs_of(el)]
              walk(el, pre: pre || PRESERVE_TEXT_ELEMENTS.include?(name))
              flush_buf
              @tokens << [:end, name]
            end
          end

          # A block boundary: trailing collapsible whitespace is trimmed and the
          # next content starts a fresh line (leading whitespace suppressed).
          def enter_block_boundary
            @pending_space = @pending_newline = false
            flush_buf
            @at_line_start = true
            @last_char = nil
          end

          # Consume a text node under white-space: normal. Runs of collapsible
          # whitespace are held (not emitted immediately) so the following
          # character can decide whether a held run becomes a single space, is
          # removed (CJK segment break), or is trimmed (line edge).
          def consume_collapsible(text)
            text.each_char do |ch|
              if whitespace?(ch)
                next if @at_line_start # leading trim

                @pending_space = true
                @pending_newline ||= ch == "\n" || ch == "\r"
              else
                resolve_pending(ch)
                @buf << ch
                @last_char = ch
                @at_line_start = false
              end
            end
          end

          # Decide what a held collapsible whitespace run contributes right before
          # the character `ch`: nothing (CJK segment break), or a single space.
          def resolve_pending(ch)
            return unless @pending_space

            unless @pending_newline && segment_break_removed?(@last_char, ch)
              @buf << ' '
            end
            @pending_space = @pending_newline = false
          end

          # Commit a held space as an actual space (used before an inline void
          # element, which is content but carries no character of its own).
          def commit_pending
            return unless @pending_space

            @buf << ' '
            @pending_space = @pending_newline = false
          end

          # CSS Text 3 §4.1.2 segment break transformation (browser rule): a
          # segment break is removed when the East Asian Width of both surrounding
          # characters is Fullwidth/Wide/Halfwidth and neither side is Hangul;
          # otherwise it becomes a space. (Re:VIEW's join_lines_by_lang adds extra
          # ja/zh heuristics at build time, but browsers apply only this rule.)
          def segment_break_removed?(before, after)
            return false if before.nil? || after.nil?

            cjk?(before) && cjk?(after)
          end

          def cjk?(char)
            %i[F W H].include?(Unicode::Eaw.property(char)) && char !~ /\p{Hangul}/
          end

          def whitespace?(ch)
            ch == ' ' || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\f"
          end

          def emit_pre_text(text)
            resolve_pending(text[0]) if @pending_space && text[0]
            flush_buf
            @tokens << [:text, text] unless text.empty?
            @at_line_start = false
            @pending_space = @pending_newline = false
            @last_char = text[-1]
          end

          def flush_buf
            return if @buf.empty?

            @tokens << [:text, @buf]
            @buf = +''
          end

          def attrs_of(el)
            attrs = el.attribute_nodes.filter_map do |a|
              value = normalize_attr(a.name, a.value)
              # An empty class="" selects nothing, so it is equivalent to having
              # no class attribute at all -- drop it.
              next if a.name == 'class' && value.empty?

              [a.name, value]
            end
            attrs.sort_by { |k, _| k }
          end

          # class is an unordered set of tokens; sort+dedup so token order and
          # duplicate classes don't cause spurious differences.
          def normalize_attr(name, value)
            return value unless name == 'class'

            value.to_s.split(/\s+/).reject(&:empty?).uniq.sort.join(' ')
          end
        end
      end
    end
  end
end
