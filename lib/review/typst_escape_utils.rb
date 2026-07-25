# frozen_string_literal: true

# Copyright (c) 2026 Masayoshi Takahashi
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.

module ReVIEW
  # Serialization helpers for Typst output.
  #
  # doc/design-typst.md keeps the four serialization paths of
  # the design manual  -- body content, string argument, label, raw source
  # -- but as helpers on the renderer rather than a separate emitter layer. A
  # value must go through the helper that matches where it lands; passing a body
  # string where a string literal is expected produces syntactically valid but
  # semantically wrong Typst.
  module TypstEscapeUtils
    # Characters that start markup in Typst content mode. Escaped with a
    # backslash, which Typst accepts before any ASCII punctuation.
    # Regexp.union rather than a character-class literal: "#$" inside a regex
    # literal is global-variable interpolation, not two characters.
    MARKUP_CHARS = Regexp.union(['\\', '#', '$', '*', '_', '`', '[', ']', '<', '>', '@', '~']).freeze

    # Line-leading characters that would start a list, heading or term item.
    # The trailing space is part of the marker: "1.5" is not an enum and
    # "-3" is not a bullet, so requiring it keeps ordinary text unescaped.
    LINE_LEAD = %r{^([=\-+/])(?=[ \t])}

    # "1. " at the start of a line starts a numbered list.
    LINE_LEAD_ENUM = /^([ \t]*)(\d+)\.(?=[ \t])/

    # Escape text for Typst content (markup) mode.
    #
    # Besides the markup characters this breaks the two shorthand ligatures that
    # would otherwise silently rewrite the author's text: "--" (en dash) and
    # ".." leading into "..." (ellipsis).
    #
    # @param str [String] Raw text
    # @return [String] Text safe to place in content mode
    def escape_typst(str)
      s = str.to_s.gsub(MARKUP_CHARS) { |c| "\\#{c}" }
      # Break dash and ellipsis shorthands by escaping the leading character of
      # the run, so "--" stays two hyphens instead of becoming an en dash.
      s = s.gsub(/-(?=-)/) { '\\-' }
      s = s.gsub(/\.(?=\.)/) { '\\.' }
      # "//" starts a line comment, in content mode as well as code mode.
      # Re:VIEW prose is full of "//list"-style references to block commands, so
      # this one is not an edge case. The block-comment opener "/*" needs no
      # rule of its own: "*" is already escaped above, which breaks it.
      s = s.gsub(%r{/(?=/)}) { '\\/' }
      s = s.gsub(LINE_LEAD) { "\\#{$1}" }
      s.gsub(LINE_LEAD_ENUM) { "#{$1}#{$2}\\." }
    end

    # A Typst string literal, for arguments typed as str (paths, languages,
    # labels, alt text). Never use this for body text: a string argument is not
    # content and loses inline markup.
    #
    # @param str [String] Raw string
    # @return [String] Quoted Typst string literal
    def typst_string(str)
      escaped = str.to_s.
                gsub('\\') { '\\\\' }.
                gsub('"') { '\\"' }.
                gsub("\n") { '\\n' }.
                gsub("\r") { '\\r' }.
                gsub("\t") { '\\t' }
      %Q("#{escaped}")
    end

    # A Typst content block holding already-escaped markup.
    #
    # @param markup [String] Escaped markup
    # @return [String] Content block
    def typst_content(markup)
      "[#{markup}]"
    end

    # Normalize a Re:VIEW id into a label string.
    #
    # Labels are passed to the library as plain strings and turned into real
    # labels with Typst's label() there, so the only characters that have to go
    # are whitespace (which label() rejects).
    #
    # @param str [String] Raw id
    # @return [String] Label string
    def typst_label(str)
      str.to_s.strip.gsub(/\s+/, '-')
    end

    # Usable both as a mixin (the renderer and its inline handler include it)
    # and directly as TypstEscapeUtils.escape_typst(...) from code that only
    # needs to escape a value or two.
    module_function :escape_typst, :typst_string, :typst_content, :typst_label
    public :escape_typst, :typst_string, :typst_content, :typst_label
  end
end
