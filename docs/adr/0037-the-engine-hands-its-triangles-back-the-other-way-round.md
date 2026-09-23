# 0037 - The engine hands its triangles back the other way round

- **Date**: 2026-09-23
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. Nothing
  here touches what a document means; it fixes how a baked solid is written down.
- **Amends**: ADR 0036 (its sphere limit is retired - spheres now split)
- **Records**: FOLLOWUPS F48

## Context

The author, on the exploded view of a cube nucleus:

> "that internal shelfing is NOT supposed to be there, its ISNT supposed to be apart of inner,
> exterior, or caps, it litewrally is sensless infill slabs that ARENT supposed to be there... the
> exterior surface is simply missing, the only thing visible is interioe, some exterior, with most
> exterior missing and welded to interior."

Both halves of that are one bug, and it had been there for the life of the project.

**Godot's front face is clockwise seen from outside.** `PolyMesh` is anticlockwise-outward, and
`PolyMesh.to_array_mesh` reverses every triangle on the way out to meet Godot. `ShipCsgBake._read_raw`
and `_read_cell` read the engine's triangles back **in the engine's own order**, with a comment
saying that order IS this class's outward winding. It is not. Every solid the bake produced - every
piece, every pod, every tunnel - was **inside out**.

**Nothing could see it.** `PolyMesh.volume()` returns an ABSOLUTE value, so a solid and its
inside-out twin measure the same, and this pipeline checks itself almost entirely by volume: the
pieces summed to their room, the halves summed to the piece, the read-back matched the input. Every
one of those checks passed on an inside-out solid. The retired comment's own measurement - "reading
them reversed breaks the merge, two of fourteen halves no longer summed to their piece" - was made
with that same blind instrument.

**What an inside-out solid does.** Handed back to the engine it is intersected as its own
COMPLEMENT. Measured: a hollow piece cut in half came back with a **solid lid over the cavity, 45.78
m2 where the ring is 3.95**, and the half was 23.3 m3 of 52.5 rather than 26.3. Those lids are the
author's slabs. Drawn, the double reversal points the front faces inward, so `CULL_BACK` throws the
outside away and leaves the cavity showing - the author's missing exterior. One cause, both symptoms.

**And a second, smaller one found on the way.** `PolyMesh.triangulate_face` took a fan from vertex
zero for any face with no holes. A fan is the polygon only when the polygon is convex, and merging
coplanar triangles back into n-gons makes concave ones routinely: **96 of a nucleus piece's 334
faces**, the worst beside the hatch. The stray triangles lay outside their own faces.

## Decision

**The read turns the engine's triangles round.** `_read_raw` and `_read_cell` reverse each triangle,
so a `PolyMesh` holds what it says it holds, whoever built it.

**`PolyMesh.signed_volume()` exists and is what to assert on** when the question is which way round a
solid is. `volume()` keeps its absolute answer for everything else.

**`triangulate_face` only fans a face it has checked is convex**, and sends the rest through
`Poly2D` - the path a holed face already took. A refused triangulation still falls back to the fan,
because a dropped face is a hole in a solid.

## Consequences

**Measured, on the author's own check.** A cube carbon: six pieces summing to **315.727 m3 against a
room of 315.727**, every cell of every piece summing to its piece exactly (52.659 of 52.659, where it
was 52.605), and **no cut face over 0.5 m2 anywhere** - the cut area of a piece's cells fell from
170.07 m2 to 61.74. The four cells around a hatch, which came back as three sails and one correct
chunk, are now four congruent chunks.

**A sphere carbon now splits**, which ADR 0036 recorded as its one open case: six closed pieces
summing to 250.809 m3 against a room of 250.821, no fallback. The non-manifold pieces that sent it to
the cut-back were an artefact of splitting an inside-out shell.

**Every solid the bake makes now reads positive**, from `p_0007` to the last pod, and two new tests
in `tests/harness/test_csg_bake.gd` hold it there: one asserts the sign on every baked solid, one
cuts a piece in half and demands half of it back. Two more in `tests/core/test_shape_mesh.gd` hold
the triangulator: a concave L covers its own 5 m2 and no more, and a solid knows itself from its
twin.

**gdUnit4 323/323 before the new tests and 42/42 on the two suites after**; selfcheck PASSED with the
hash unchanged; validator PASSED; gdformat and gdlint clean; the resolve, explode and visual checks
all PASSED.

**What this does NOT change.** No `core/` geometry decision, no ruleset, no data. A solid that was
inside out was the same shape all along - it is the operations on it that were wrong.
