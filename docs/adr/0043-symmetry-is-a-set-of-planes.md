# 0043 - Symmetry is a SET of planes, not one

- **Date**: 2026-09-25
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side, and so
  does every saved ship. See "the field was widened" below; this is the whole reason it was done
  that way.
- **Amends**: nothing retired; `ShipDoc.symmetry_plane` gains values it could not hold before
- **Records**: `docs/future/symmetry.md` section 1, now built

## Context

> "mirror is kinda been out of alignment for a minute.. as i can only select x, y, or z, when it
> should be x, and/or, y, and/or z, where reflections can happen across all 3 axis at once. there
> are also other forms of symmetry that we can implement later, but keep them in mind. the idea is
> that its a game and not really software, and i want it easy for a player to make a symmetrical
> ship if they wish." - the author, 2026-09-21

A document carried ONE plane. The inspector's MIRROR row was four buttons picking one of x, y, z or
off, and everything downstream - the attach pass's twins, the seams' twins, the complexity bill, the
ghost's mirrored half - asked `plane_axis(doc.symmetry_plane)` and got a single answer.

## Decision

**`ShipDoc.symmetry_plane` holds a SET, written as axis letters in x-y-z order**: `"x"`, `"xz"`,
`"xyz"`, or `""` for off.

**The field was WIDENED, not replaced, and that is the load-bearing choice.** A document written
before this carries one letter, which spells the same in the new form, so it serialises the same,
hashes the same and means the same. No ruleset bump, no migration, no saved ship touched. A second
field would have changed the canonical form of every document for the sake of a feature most of them
do not use.

**A part off n of the document's planes has 2^n - 1 twins** - one per non-empty subset of the axes it
is off. `ShipSymmetry.reflections_of()` returns them and is now the one place that decides; the old
`generates_twin()` keeps its signature and answers "any at all".

**An axis the part sits ON is left out of the reckoning entirely**, rather than producing a twin on
top of the original. That is what keeps a part on the centre line single whatever the planes say, and
it is why a root never doubles.

**Twin ids keep the bare `~m` for a document with one plane** and take their axes for a document with
several - `p_0007~mxy`. The bare form is what every saved ship, every consumer and every test has
always seen, and a document with one plane must not change because the field can now hold more. Twin
ids are DERIVED and never stored, so the longer form breaks no file.

**Reflections compose.** `ShipMirror.reflect_axes()` applies them in turn, so mirroring across x and
then y IS the "xy" twin, and `ShipMirror` stays the only place that knows what a reflection is.

**The MIRROR row toggles.** X, Y and Z are independent; OFF is not a fourth plane, it clears them.

## Consequences

**A player can mirror across any combination**, which is what was asked for.

**Every saved ship is untouched** - selfcheck hash `5536787c6c35d236` before and after, and 340
tests green including the ones that assert the old twin-id format verbatim.

**One known partial: the placement GHOST shows a single twin** even when the commit will make three
or seven. It is a single node, and a ghost per reflection is a view change worth doing on its own.
It under-promises, which is the safe direction - the preview never shows a twin the commit will not
make.

**gdUnit4 340/340** with five new; selfcheck PASSED with the hash unchanged; validator PASSED;
gdformat and gdlint clean; resolve and visual checks PASSED.
