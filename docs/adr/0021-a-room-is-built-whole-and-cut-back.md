# 0021 — A room is built whole and cut back into its pieces

- **Date**: 2026-09-05
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after.
- **Amends**: ADR 0020 (how an open room's pieces are made)
- **Records**: FOLLOWUPS F33

## Context

> "the central proton doesnt resolve correctly. - to fix this we need to [union all proton chunks
> = 1 single solid mesh = exterior mesh], then make the interior mesh by taking all the [orignal
> proton chunks, down sizing them slightly, unioning all those smaller chunks]. then we make the
> shell by taking the big proton mesh and subtracting the small proton mass.] then we re cut the
> single mesh using orignal data, such that each sub chunk shell is created by cutting the single
> mesh (the closed shell) intersection with the orignal chunks. this should make perfect shell
> chunks. and yea use godots stuff or existing stuff no need to reinvent the wheel."

ADR 0020 made an open room's pieces with a per-part rule: the indented part loses the indenter's
body on both surfaces, the indenter loses the indented part's room. It is a correct rule for a
PAIR. On a nucleus whose root is indenter to five neighbours at once it leaves the root with slabs
of its own skin lying inside those neighbours' *walls* — the band between a neighbour's outer and
inner surface, which no per-part rule ever names — and that is the central proton the author saw.

## Decision

**A room's shell is made once, from all its members, and then cut back into pieces along the
members' original bodies.** Exactly the author's construction, in two engine passes
(`ShipCsgBake`):

1. **Shell** = (union of every member's body) − (union of every member's interior). Each member's
   *walled* cuts are applied to its body and interior before the unions, so a tunnel's socket
   survives into the room.
2. **Piece i** = shell ∩ member i's original body − the bodies of members before it (in sorted
   order). The subtraction is what makes it a partition: where two chunks overlap the shell, the
   hull is counted once.

Pass one's result goes back into pass two **as the engine made it** — its own manifold triangles —
not as this project's merged n-gons re-triangulated.

**The plan names rooms.** `ShipMeshBake.plan()` now returns `rooms` (every part in exactly one,
members sorted), `cuts` (the walled seams) and `open_cuts` (the per-part reading of the open seams,
which the tree-less pure executor still uses because it has no union).

## Consequences

**Measured, carbon on sphere pods and on boxes.** One room of six: every piece closed, zero open
parts; sphere root 14.6 m³, rims 24.0, bottom 15.3; box root 18.9, rims 29.3, bottom 19.0. And the
engine's own answer to the complaint: every piece intersected with every *other* member's interior
body has **no volume** — `test_no_room_piece_keeps_hull_inside_another_member`, both families.
4.7 s for the sphere room, 2.4 s for the box room.

**Feeding my merged n-gons back into the engine was the box family's failure.** A shell read back
as faces with holes, bridged and re-triangulated by `PolyMesh`, is not a manifold the engine
accepts; pass two returned 348 m³ for a piece of a 50 m³ shell. The engine's mesh is the operand.

**Walled sibling overlaps are unchanged**: two protons that touch but are not linked still have no
seam between them, and their skins interpenetrate. Linking them OPEN is now the answer to that.
