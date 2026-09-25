# 0044 - A prebuilt class is symmetric left to right

- **Date**: 2026-09-25
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. A
  template BUILDS a document; it is not part of what one means.
- **Records**: dev note 2026-09-24 13:42, `docs/future/symmetry.md`; FOLLOWUPS F51 for what is left

## Context

> "after reviewing many of these, i realized that many of our presets are asemetrical in every
> direction. the rule i created now is we need symetry across at least 1 axis with reguards to our
> prebuilds. with a left-right being a min, top-bot, and frnt-back can be asymetrical if the themed
> part calls for it ... make it based on weight (mirrored weight) as thats really the only symetry we
> care about." - the author, dev note 2026-09-24

And, on scope: "not for player creation but for our procedual pre builds. player can build an
asymetric ship if they choose."

Nobody had measured which classes actually failed. That was the first piece of work.

## Decision

**X is a hard rule for a prebuilt class; Y and Z may fail.** Measured by WEIGHT, which in the shell
model the builder already uses (`surface_area_m2 * areal_density_kg_m2`, one placeholder density) is
a part's surface area - so a class's centre of mass is the area-weighted mean of its parts' centres,
and the offset is read as a fraction of the class's own half extent.

**`tools/ship_symmetry_check.gd` reports it**, per class, per axis. It does not gate yet, and says so
in its own output; the line to flip is one constant.

**Two causes were found and fixed.**

1. **Five arrangements were not mirror-closed on X.** `trigonal`, `pyramidal`, `tetrahedral`,
   `bipyramidal` and `pentagonal` are rotationally symmetric about Y, but their spokes did not pair
   across X - a sum of zero is not the same thing, which is why a tetrahedron passed that test and
   failed this one. Each is rotated about Y by half of its own step - 30, 30, 45, 30 and 18 degrees -
   which brings a mirror plane onto X **without changing the arrangement's shape at all**: every
   direction keeps its length and the set keeps its mutual angles.

2. **Arms were handed out in waist-first order and clustered on one side.** Measured, a silicon put
   all three of its arms at x = +6.4. They are now handed out in MIRROR PAIRS - a slot, then its
   reflection - so every prefix of the list is as balanced as it can be, and an odd count takes a
   berth that is its own mirror first where the arrangement has one. The waist-first preference is
   kept; pairing only reorders within it.

## Consequences

**Six classes failed X; two remain, and four were fixed.** Before: `lithium`, `fluorine`, `sodium`,
`silicon`, `phosphorus`, `chlorine`. After: `fluorine`, `sodium`, `phosphorus`, `chlorine`. Twelve of
sixteen are now balanced left to right, and `silicon`, `lithium`, `oxygen` and `sulphur` moved to
passing.

**The four that remain cannot be fixed by slot choice, and the reason is exact.** A class takes one
body per proton (clamped to eight, which is the CUBIC arrangement) and one arm per valence electron.
**A cube has no vertex on the X plane.** So an EVEN arm count pairs exactly and an ODD one is left
over by a single arm with nowhere on the plane to stand. All four have odd valence - 7, 1, 5, 7 - and
their residual is exactly one arm's weight. Fixing it is a decision about what a class IS: give the
odd arm a berth on the plane, use a nucleus that has one, pair the odd arm, or let those classes be
asymmetric. Recorded as FOLLOWUPS F51 rather than decided here.

**Every preset's geometry moves**, because the arrangements rotated. That is the point, and it is
visible: a trigonal class is turned 30 degrees about its own axis from where it stood.

**gdUnit4 340/340**; selfcheck PASSED with the hash unchanged; validator PASSED; resolve and visual
checks PASSED; gdformat and gdlint clean.
