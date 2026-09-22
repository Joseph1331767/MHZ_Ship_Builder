# 0034 - The nucleus rings the beacon, and parts that stand side by side have seams

- **Date**: 2026-09-22
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. What moves is what the TEMPLATES build, which is new documents rather than a reading
  of old ones (the ADR 0023 precedent, as ADR 0033).
- **Amends**: ADR 0017 (the nucleus hangs off the root body -> it stands in its arrangement's own
  slots), ADR 0024 (a component may hold members that stand on nothing), SPEC §3 (an anchored part
  inside a definition), SPEC §7 (a seam is no longer only parent -> child)
- **Records**: FOLLOWUPS F46; RESOLVES F19's sibling limitation and F30 limit 4

## Context

> "i dont think its working, i built a carbon with cube rooms and the center proton was not
> centered top and bottom etc, and when i exploded it it did not yeild parts that were expected,
> which in this exact case would be 6 little square slabs, theoretically speaking." - the author,
> 2026-09-21, on the beacon of ADR 0033

Measured first. ADR 0033 put the ship's CENTRE on the beacon, and it is there: the carbon's core
centroid was 0.00. What it did not touch is how the nucleus is LAID OUT - ADR 0017 hangs each body
off the one before it, on the surface, and the attach model seats a child along the host's surface
NORMAL. On a sphere the normal is the ray, so a body lands where it was aimed; on a CUBE a 45
degree ray strikes a side face and the normal is level, so the body slides sideways. Measured on a
cube carbon: the root sat at +2.76, the four rim bodies at y = 0 and ±5.64, the bottom at -2.88 -
a nucleus 10.28 m wide and 7.40/-7.52 tall, leaning. Its six pieces came out 18.9 to 29.2 m³, not
six of anything. That is what the author was looking at.

**A ring of bodies around a centre cannot be built by surface attachment at all.** It is not a
tuning problem: on a box of half-span `h` the neighbouring slots of an octahedron sit about `1.3 h`
away diagonally, and there is no face of the host whose normal reaches that point - the transverse
coordinates fall off every face. A body at the middle is what ADR 0017 removed deliberately ("the
central completely burried one still exists and thats incorrect"), so the only thing left to stand
on is the beacon.

## Decision

**Every nucleus body is ANCHORED in its arrangement's own slot**, at one radius from the beacon,
turned to face its slot. The arrangement's directions are what the class actually means - a carbon
is six bodies on an octahedron - and the old hang directions could only ever approximate them.

**The radius is solved against the field, not derived.** `ShipTemplates._nucleus_radius` finds the
tightest pair of the arrangement and walks out along the chord between them until
`ResolvedShape.sdf` reads exactly `FUSE_OVERLAP` of the body's own reach that way, then converts
that chord to a radius. The sink means what it always meant - a third of the body - on a shape of
any proportions. Measured: sized by one axial distance instead, a spar nucleus came out as six
rooms that never touched.

**A component may hold members that stand on nothing.** `make_component` accepts a selection of one
head plus anchored RIDERS with their subtrees, each rider's anchor stored relative to the head, so
the clump moves as one and `dissolve` puts them back on the beacon. The head must be anchored too,
because where a seated head stands is a question only the attach pass can answer. `ShipAttach`
places a parentless inner part by its own `absolute` in the instance's frame, exactly as ADR 0033
places a parentless doc part in the ship's.

**A JOINED pair that MEETS has a seam wherever the two stand.** `ShipSeams` emits one for every
pair with a joint record - the document's joints and every instance's definition joints - that is
not already a parent and child: the frame stands on the HOST's surface where the line between the
two centres leaves it, its Z pointing at the child, which is what a seam's frame means everywhere
else. The host is the one placed first, so the chain the explode walks cannot close on itself. A
pair whose solids do not meet along that line gets NO seam rather than an invented plane, and a
pair with no joint record merges exactly as it always did - nothing any existing document holds
changes meaning.

**Parts that stand side by side name their own pairs.** `ShipSeams.pairs_within` returns them, so
the tree panel's LINK opens a room across a nucleus the same way it always has; the templates use
the geometric version (`_clump_pairs`) and write an OPEN joint for every pair that actually meets.

## Consequences

**Measured, on the author's case.** A cube carbon's six bodies now stand at 4.94 m on their own
axes - a symmetric 3D plus, ±9.58 m in every direction - and its six pieces come out 26.46 to
27.01 m³, within 2% of each other, where they were 18.9 to 29.2. Twenty seams: twelve between
neighbouring bodies, eight on the tunnels. The three pairs ACROSS the nucleus are 9.88 m apart on
a 9.47 m body and do not meet, so their joints are inert, which is the right answer.

**Every class on every family.** carbon, helium, neon, hydrogen and water on `box_hull`,
`sphere_pod` and `cylinder_spar`: the core centres on the beacon to 0.01 m and the nucleus comes
out as ONE room of exactly its body count, which is the thing that was broken on a spar before the
chord measurement.

**F19 is lifted, not only for rooms.** A doorway between two fused siblings plans and bores
(`doors=1, pending=0`, measured on a dissolved helium); before this, a joint between siblings did
nothing at all, silently.

**gdUnit4 320/320**, six new (three in `tests/core/test_sibling_seams.gd`, two in `test_beacon.gd`,
one in `test_components.gd`);
selfcheck PASSED with the hash unchanged; the data validator PASSED; gdformat and gdlint clean;
the windowed visual, resolve and explode checks PASSED. Frames:
`reports/visual_box_carbon.png` and `reports/visual_box_carbon_explode.png`.

**Three tests were asserting on the tree the nucleus used to be.**
- `test_dissolve_puts_the_inner_parts_back` required every part to hang off another; a part may
  stand on nothing since ADR 0033, and a dissolved nucleus does.
- Two `test_shape_mesh` tests looked for "the first part with a parent" to make a pair, and a
  dissolved nucleus has none. They name the pair now.
- `test_every_piece_is_sliced_into_two_closed_halves` asserted every PIECE comes apart in the
  middle; a room is cut as one body (ADR 0033) and a member standing to one side of the room's
  middle keeps all its cells there - which a nucleus ringing the beacon guarantees. It asserts on
  the room now, over every placed piece rather than the document's own parts.

**A review of the diff found two silent-wrong-answer bugs, both fixed here, both now asserted.**
- **`definition_order` left an anchored member to the id sort.** A rider is unreachable from the
  definition's root, so it fell into the trailing "unreached, sorted by id" bucket with its own
  children - which is right only because `make_component` hands out ids in subtree order. A
  hand-edited pack (`data/` is hand-editable by rule) or any tool that renumbers would have put a
  child before its parent, where `ShipAttach._expand_instance_transforms` silently falls back to
  the instance's frame and `dissolve` cannot tell that child from a rider. It walks each anchored
  member's subtree now (`test_definition_order_walks_an_anchored_members_subtree`).
- **A seam whose frame IS the identity was dropped.** `_sibling_frame` reported "no seam" by
  returning `Transform3D()`, and a pair on the world Z axis whose seam falls on the origin produces
  exactly that - `mount_frame(Vector3.BACK)` is the identity basis, and a ship built around a
  beacon AT the origin is where such a pair turns up. It returns a dictionary now
  (`test_a_seam_that_lands_on_the_origin_is_still_a_seam`).

Two narrower guards came from the same review: `_stand_apart` no longer pairs inner parts of two
unrelated instances (each is anchored inside its own definition, which is not the same place), and
`_nucleus_radius` skips a degenerate chord rather than returning a zero radius that would pile the
whole clump on the beacon.

**Known limits, recorded rather than hidden.**

1. **A sibling seam needs the pair's solids to meet ALONG THE LINE BETWEEN THEIR CENTRES.** Two
   arms that cross off-centre overlap without meeting there, and get no seam. Inventing a plane
   for them would put a wall in open space; the honest answer is the one that is given.
2. **`dissolve` resolves a rider against the instance's own anchor**, which is exact while the
   instance is anchored - the ship's root, where a nucleus lives - and wrong for an instance
   SEATED on a host, whose world transform this layer cannot resolve. No caller does that today.
3. **The radius is solved for the tightest pair only.** A wildly irregular arrangement could fuse
   that pair and leave a looser one merely touching. Every arrangement in the pack is regular.
4. **Nothing places a part on the beacon from the UI yet** (ADR 0033 limit 1, unchanged), and the
   riders are still only made by the templates.
