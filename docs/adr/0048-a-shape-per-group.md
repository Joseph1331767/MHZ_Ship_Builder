# 0048 - A shape per group, a blended cluster, and a cylinder node sized as a room

- **Date**: 2026-09-27
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. What a
  template AUTHORS is not what a document MEANS.
- **Answers**: dev note 2026-09-24 13:57 (the last of the five still open)
- **Builds on**: ADR 0034 (a body stands in its arrangement's slot), ADR 0044 (a prebuilt class is
  symmetric)

## Context

The author, in a SHIFT+F note taken while testing:

> "the player options for the prebuilt structures need expanding with options for outter/electron
> node shapes, tunnel shapes, proton shapes. the new shaper should cater to multi shape clusters,
> so a protons shapes can be shape1 and shape2, and the system will try to keep everything
> semetrical and even as normal, so a proton cluster can exist with cubes and spheres blended. /
> also torids are broken and dont fit well in this builder as an individual node so we need special
> rules for it that i havnt thought of yet. also when cylinder nodes (not linkage tunnels) is
> selected in pre built options, it should have the length and diameter equal and set to room size
> not tunnel bore, as an earlier test indicated that it made tiny bore rooms."

Three asks and one deferral. Until now `OPT_ROOM_FAMILY` drove BOTH node groups: a proton and an
electron were always the same shape, and there was no way to say otherwise.

## Decision

**A SHAPE PER GROUP.** `OPT_PROTON_FAMILY` and `OPT_ELECTRON_FAMILY` beside the existing
`OPT_HALL_FAMILY`, both falling back to `OPT_ROOM_FAMILY` - so a caller that names only the one
still builds the ship it always did. The picker lists PROTON SHAPE, ELECTRON SHAPE and TUNNEL SHAPE.

**A BLEND PER CLUSTER.** `OPT_PROTON_FAMILY_B` and `OPT_ELECTRON_FAMILY_B`, each a second shape run
through its group, with a `+ BLEND` row in the picker that leads with NONE.

**THE BLEND ALTERNATES PAIR BY PAIR, NOT BODY BY BODY**, and that is the whole of "the system will
try to keep everything semetrical and even as normal". A node and its mirror always take the SAME
shape, found through the very `_mirror_slot` the arm ordering uses (ADR 0044), so one rule decides
both. Alternating body by body would put a cube opposite a sphere and walk the centre of mass off
the plane - the thing ADR 0044 and ADR 0045 exist to keep straight.

**A NODE'S SPAN SQUARES ITS BOX.** `_node_span` scales a room to `span` on every axis, where
`_uniform_span` made the WIDEST axis the span. `cylinder_spar` is authored three to one
(`base_size [0.5, 1.5]`, "a slim three-to-one tube"), so a uniform scale gave a 4 m room a 1.33 m
bore - measured, and exactly the "tiny bore rooms" the note reports. Squared, it comes out 4 x 4 x 4:
length and diameter equal and both the room size. For a shape whose box is already cubic - a sphere,
a box - the two rules agree exactly, so nothing that was right before moves. `_span_for_volume`
measures the same way, or the volume budget would be a budget for a shape nothing builds.

**TORUS STAYS DEFERRED**, as asked: "we need special rules for it that i havnt thought of yet."

## Consequences

**A non-uniformly scaled SDF is not a true distance, and the fuse solve had to learn that.**
`_nucleus_radius` binary-searches the depth at which a body still overlaps its neighbour, comparing
a TRACER reading against an SDF one. Under a uniform scale those agree. Under a non-uniform one the
SDF's deepest reading anywhere is bounded by the SMALLEST scale factor, whatever the tracer finds -
measured on a squared cylinder, a deepest of 0.667 against a wanted of 0.680, which starves the
search and collapses the whole clump onto the beacon.

`_solvable_depth` trusts the tracer where the field can be trusted and caps it where it cannot,
**keyed on whether `ResolvedShape.scale` is uniform**. A first attempt capped unconditionally with
`minf(reach, deepest)` and moved box_hull, because the chord direction is off-axis and a box's reach
along a diagonal legitimately exceeds its half extent - caught by
`test_an_open_nucleus_explodes_into_holed_pieces`, which is the test doing its job.

**The blend is a lever on F51.** The four classes symmetric on no axis are unbalanced by one arm on a
cube corner; a second shape is a second density, so a blend may be able to cancel it. Not attempted
here, and the check still reports the same four.

## Verified

`reports/visual_shapes.png`, looked at: a blended carbon with box and sphere protons standing
symmetric, and a cylinder-node carbon whose rooms are drums rather than spars.
`reports/visual_picker.png`: the picker with PROTON SHAPE, + BLEND, ELECTRON SHAPE, + BLEND, TUNNEL
SHAPE, the three sizes and LINKS.

**gdUnit4 351/351**, including a test per ask - each group takes its own shape, a blended cluster
still balances above 0.97, and a cylinder node comes out `span` cubed within 2%. Selfcheck PASSED
with the hash unchanged; data validator PASSED (0 warnings); resolve, explode and visual (5 modes)
checks PASSED; the symmetry check reports the same four classes as before; gdformat and gdlint clean.
