# 0041 - Every piece is diced in its own axes

- **Date**: 2026-09-24
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. Dicing
  is a view of a bake, not a property of a document.
- **Amends**: ADR 0033 (a room's chunks no longer share the keeper's grid)
- **Records**: dev note 2026-09-24 13:45

## Context

The author, from inside the builder:

> "the splitting/dicing system is using global world space alignemnt, id rather use local node
> alignment."

It was not world space - it was the ROOM KEEPER's frame, which ADR 0033 chose on 2026-09-21 after
the opposite was tried: "it kinda makes the modules out of alignment". But the keeper of a nucleus is
the component's root instance, and it stands at whatever angle the class puts it at, so one grid
through the room cuts every chunk DIAGONALLY. On the frame attached to the note, three cubes are
sliced corner to corner while the tunnel beside them - a room of one, and so always on its own axes -
is cut squarely along its length. The slicer panel has said "SLICES - EACH PART IN ITS OWN AXES"
throughout.

**And the grid was sized to the ROOM, not the chunk.** A chunk therefore occupied a corner of it:
measured on a cube carbon, a piece diced into 20 cells that used only two of the four indices on one
axis, the rest slivers or empty.

## Decision

**Every piece is diced in its own axes, across its own body's extent** - exactly as a piece standing
alone always was. The distinction between a room's member and a lone part disappears from the
dicing.

**A room shown WHOLE keeps one grid**, the keeper's frame across every member's extent, because
ROOMS: WHOLE draws the room as one body and one body takes one grid.

**The extent stays the NODE'S OWN BODY, not the chunk.** A cut must not move when a neighbour
changes what was carved off this piece, which is what `_slice_job` has always anchored against.

## Consequences

**A chunk is cut square to its own faces.** Measured on a cube carbon: every piece now dices into 44
cells using all four indices on every axis, summing to the piece exactly (52.650 of 52.650), where
before it was 20 cells bunched on two indices.

**A room no longer comes apart down one line**, and that is the trade the author chose knowingly: the
cuts of neighbouring chunks do not continue across a seam any more. That was ADR 0033's whole point,
and it is now the lesser of the two.

**Evenness went with it, and a test had to say so.** `test_every_piece_is_sliced_into_two_closed_halves`
asserted that neither half of a ROOM was a sliver - meaningless now, since each chunk has its own z
and a nucleus points them every way (summed per room a carbon reads 8.0 / 152.0). Asserting it per
PIECE fails too, and correctly: the grid is anchored to the node's body while the chunk is only part
of that body, so a sphere carbon's `p_0007` comes apart 1.55 / 19.75. The test now claims what is
actually claimed - that every piece comes apart in two non-empty halves, "in manufacturing they are
made in 2 pieces".

**It costs about a second.** A carbon explodes into 656 cells where it made 532, in 12.9 s against
12.0.

**gdUnit4 335/335**; selfcheck PASSED with the hash unchanged; explode check PASSED; gdformat and
gdlint clean.
