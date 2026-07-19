# frozen_string_literal: true

require_relative '../test_helper'

# Lint-level guard for doc/design-improvements #5: a shared AST node class must
# not carry a field named after an output format (latex_*, html_*, idgxml_*,
# top_*, epub_*). Such a name records a builder's decision rather than a source
# fact; format-named members belong in a renderer's namespace. Regressions here
# (e.g. re-introducing TableNode#col_spec or ListItemNode#latex_line_breaks) are
# invisible to the parity suites, so pin them structurally.
class TestNoFormatNamedFields < Test::Unit::TestCase
  AST_DIR = File.expand_path('../../lib/review/ast', __dir__)

  FORMAT_PREFIXES = %w[latex html idgxml top epub markdown].freeze

  # Fields that name a format but record a genuine source fact (the input itself
  # is that format), with the rationale. Keyed by "file.rb:field". Currently
  # empty: raw HTML embedded in Markdown will be modeled with EmbedNode (whose
  # field is the format-neutral +content+), not a dedicated html_* field.
  ALLOWED = {}.freeze

  def test_no_format_named_attr_fields
    pattern = /attr_(?:reader|accessor|writer)\s+(.+)/
    field_re = /:(#{FORMAT_PREFIXES.join('|')})_[a-z_]+/

    offenders = []
    Dir.glob(File.join(AST_DIR, '**', '*.rb')).sort.each do |path|
      rel = path.sub("#{AST_DIR}/", '')
      File.readlines(path).each do |line|
        next unless (m = line.match(pattern))

        m[1].scan(field_re) do
          field = Regexp.last_match(0).delete_prefix(':')
          key = "#{File.basename(path)}:#{field}"
          offenders << "#{rel}: #{field}" unless ALLOWED.key?(key)
        end
      end
    end

    assert_empty(offenders,
                 'Shared AST nodes must not have output-format-named fields ' \
                 "(move them to a renderer, or allowlist a genuine source fact):\n  " +
                 offenders.join("\n  "))
  end
end
