# Spec questions: builder-derived behaviours that may or may not be intended

review-ast reproduces the output of Re:VIEW's legacy builders bit-for-bit (see
[differential-testing.md](differential-testing.md)). The builder is the oracle,
so wherever we align with it we inherit its behaviour *whether that behaviour is
an intended feature or an accident of the implementation*.

Most of the time this is fine. But some behaviours are **not documented in the
Re:VIEW format spec** and look questionable. We match the builder anyway (that is
the whole point of parity), but we should not pretend they are "correct" — they
are open questions for the Re:VIEW maintainers.

This file is that list. It exists so that:

- a future reader does not "fix" an intentional builder-matching quirk, mistaking
  it for an AST bug;
- when the AST path is ready to become the source of truth, each entry can be
  triaged: **spec it** (document the behaviour and keep it), or **fix it** (change
  the builder *and* the renderer together, updating the oracle).

Prefer adding an entry here over sprinkling `# matches builder, spec unclear`
comments through the code.

## How to use

- Add an entry when you match the builder on something undocumented/surprising.
- Keep it short: what the builder does, why it's suspicious, where it lives.
- Resolve an entry by either documenting the behaviour in the Re:VIEW format spec
  (and linking it) or fixing builder + renderer together, then delete the entry.

## Open questions

### 1. TOC sectioning name for a Part differs by path (`part` vs `chapter`)

For an unnumbered Part, the `\addcontentsline{toc}{...}` sectioning name depends
on *how* the Part is rendered:

- a starred Part (`secnolevel: 0`, the normal numbered path) records its TOC entry
  under **`part`**;
- a `[nonum]` Part records it under **`chapter`**.

Both match LATEXBuilder (and both are pinned by existing tests:
`test_visit_headline_part_with_secnolevel0` → `part`,
`test_visit_headline_part_nonum` → `chapter`). There is no obvious reason the two
paths should disagree, and the format spec does not describe Part TOC entries.

- Renderer: `LatexRenderer#visit_headline` (regular path, uses
  `get_base_section_name`) vs `#generate_nonum_headline` (uses `HEADLINE[level]`).
- Question: is the `part`/`chapter` split intended, or an accident? If intended,
  document it; if not, unify (in the builder and the renderer together).
