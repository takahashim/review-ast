# frozen_string_literal: true

require_relative '../test_helper'

# Cross-checks the page-design values (doc/design-hanmen.ja.md §3 / §2.6)
# against the two design-value files review-ast owns:
#   C = templates/vivliostyle/css/style-vivliostyle-design.css
#   T = templates/typst/review-book/theme.typ
#
# The LaTeX (L) defaults live in the review gem's class files, not here, so they
# are out of scope. For each vocabulary item the values in whichever of {doc,
# CSS, Typst} carry it must agree once normalised to a plain number; a drift in
# any one source fails the test (design-hanmen §8: the files are authoritative,
# the document must match them).
class HanmenDesignValuesTest < Test::Unit::TestCase
  ROOT = File.expand_path('../..', __dir__)
  DOC = File.read(File.join(ROOT, 'doc/design-hanmen.ja.md'))
  CSS = File.read(File.join(ROOT, 'templates/vivliostyle/css/style-vivliostyle-design.css'))
  THEME = File.read(File.join(ROOT, 'templates/typst/review-book/theme.typ'))

  # name, CSS custom property, Typst dict block + key, doc §3 name, cell index
  # in a combined "A / B" default cell. nil source = not defined there.
  GEOMETRY = [
    ['fontsize',        '--fontsize',        %w[text size],           'fontsize',        0],
    ['baselineskip',    '--baselineskip',    %w[text baselineskip],   'baselineskip',    0],
    ['line-length',     '--line-length',     %w[text line-length],    'line-length',     0],
    ['number-of-lines', '--number-of-lines', %w[text number-of-lines], 'number-of-lines', 0],
    ['head-space',      '--head-space',      %w[margins head-space],  'head-space',      0],
    ['gutter',          '--gutter',          %w[margins gutter],      'gutter',          0],
    ['headheight',      '--headheight',      %w[margins headheight],  'headheight',      0],
    ['headsep',         '--headsep',         %w[margins headsep],     'headsep',         0],
    ['footskip',        '--footskip',        %w[margins footskip],    'footskip',        0],
    ['float-sep',       '--float-sep',       %w[spacing float-sep],   'float-sep',       0],
    ['caption-sep',     '--caption-sep',     %w[spacing caption-sep], 'caption-sep',     0],
    ['box-pad-x',       '--box-pad-x',       %w[box pad-x],           'box-pad-x / pad-y', 0],
    ['box-pad-y',       '--box-pad-y',       %w[box pad-y],           'box-pad-x / pad-y', 1],
    ['box-rule',        '--box-rule',        %w[box rule],            'box-rule / arc',  0],
    ['box-arc',         '--box-arc',         %w[box arc],             'box-rule / arc',  1],
    # crop.bleed is Typst + doc only; design.css has no crop block.
    ['crop.bleed',      nil,                 %w[crop bleed],          'crop.bleed',      0]
  ].freeze

  # The size ladder: CSS carries the multiplier inside calc(), Typst as a bare
  # number, and the doc's §2.6 table (not §3) holds it in the 倍率 column.
  LADDER = %w[xxlarge xlarge large medium small xsmall].freeze

  def css_value(prop)
    return nil unless prop

    raw = CSS[/^\s*#{Regexp.escape(prop)}:\s*([^;]+);/, 1]
    raise "CSS: #{prop} not found" unless raw

    number(raw)
  end

  # The value of +key+ inside the +block+ sub-dict of default-theme.
  def theme_value(block, key)
    body = THEME[/#{block}:\s*\(\n(.*?)\n  \),/m, 1]
    raise "theme.typ: block #{block} not found" unless body

    raw = body[%r{^\s*#{Regexp.escape(key)}:\s*(.+?),?\s*(?://.*)?$}, 1]
    raise "theme.typ: #{block}.#{key} not found" unless raw

    number(raw)
  end

  # The cells of the §3 row named +name+ (leading/trailing empties dropped):
  # [区分, 名前, 意味, 既定値, 定義, L, C, T].
  def doc_section3_cells(name)
    line = DOC.lines.find { |l| l =~ /^\|[^|]*\|\s*#{Regexp.escape(name)}\s*\|/ }
    raise "doc §3: row #{name} not found" unless line

    line.split('|')[1..].map(&:strip)
  end

  # The 既定値 cell of the §3 row named +name+, split on "/" at +index+.
  def doc_section3_value(name, index)
    cell = doc_section3_cells(name)[3].split('/')[index].to_s.strip
    number(cell)
  end

  def doc_section3_marked?(name, column)
    doc_section3_cells(name)[{ 'C' => 6, 'T' => 7 }.fetch(column)] == '✓'
  end

  # The 倍率 of a §2.6 ladder row, e.g. "2.5 (2.488)" -> 2.5.
  def doc_ladder_value(name)
    row = DOC[/^\|\s*#{Regexp.escape(name)}\s*\|([^|]*)\|/, 1]
    raise "doc §2.6: ladder row #{name} not found" unless row

    number(row.split('(').first)
  end

  # Strips the unit shared across sources for one item (Q, mm, H, Q(n), bare)
  # and returns a Float, or nil for a non-literal cell (導出, auto, 本文と同寸,
  # a section reference like 2.6).
  def number(raw)
    text = raw.to_s.strip
    return nil if text.empty?

    if (m = text.match(/\AQ\((\d+(?:\.\d+)?)\)\z/)) # Typst Q(13)
      return m[1].to_f
    end
    if (m = text.match(/\Acalc\(var\(--fontsize\)\s*\*\s*(\d+(?:\.\d+)?)\)\z/)) # CSS ladder
      return m[1].to_f
    end
    return 1.0 if text == 'var(--fontsize)' # CSS --size-normal
    return nil unless (m = text.match(/\A(\d+(?:\.\d+)?)\s*(?:Q|H|mm)?\z/))

    m[1].to_f
  end

  data(GEOMETRY.to_h { |row| [row[0], row] })
  def test_geometry_value_agrees_across_sources(row)
    name, css_prop, (block, key), doc_name, index = row
    sources = {
      'CSS' => css_value(css_prop),
      'Typst' => theme_value(block, key),
      'doc' => doc_section3_value(doc_name, index)
    }.compact

    assert_operator(sources.size, :>=, 2, "#{name}: fewer than two sources carry a value")
    reference = sources.values.first
    sources.each do |where, value|
      assert_in_delta(reference, value, 1e-6,
                      "#{name}: #{where}=#{value} disagrees with #{sources.keys.first}=#{reference}")
    end

    # The §3 presence markers must match which files actually carry the value.
    assert_true(doc_section3_marked?(doc_name, 'T'),
                "#{name}: theme.typ defines it but §3 marks T empty")
    assert_equal !css_prop.nil?, doc_section3_marked?(doc_name, 'C'),
                 "#{name}: §3 C marker disagrees with design.css"
  end

  data(LADDER.to_h { |name| [name, name] })
  def test_size_ladder_multiplier_agrees(name)
    css = css_value("--size-#{name}")
    typst = theme_value('text', name)
    doc = doc_ladder_value(name)

    assert_in_delta(css, typst, 1e-6, "#{name}: CSS=#{css} vs Typst=#{typst}")
    assert_in_delta(css, doc, 1e-6, "#{name}: CSS=#{css} vs doc §2.6=#{doc}")
  end
end
