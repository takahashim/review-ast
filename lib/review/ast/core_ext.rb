# frozen_string_literal: true

# Compatibility shims for running the AST subsystem against the released
# `review` gem.
#
# No monkey patches on Re:VIEW classes remain. The AST now owns every piece of
# state it used to smuggle through the gem's objects (doc/design-improvements
# #7): reference data lives in the AST-owned ChapterIndexRegistry, definition
# numbers and image paths are stamped on the nodes, and endnotes are collected
# from the tree -- so the former Index::Item#caption_node prepend,
# BookUnit#ast_indexes= adapter, and SnapshotLocation#to_h/#format_for_error
# patch have all been retired. Only a soft optional-dependency require is left.

# Re:VIEW's TextUtils references Unicode::Eaw for join_lines_by_lang but does
# not require it itself; ensure it is loaded when available. Mirrors Re:VIEW's
# own soft handling (join_lines_by_lang is disabled when the gem is absent).
begin
  require 'unicode/eaw'
rescue LoadError
  # join_lines_by_lang feature will be unavailable
end
