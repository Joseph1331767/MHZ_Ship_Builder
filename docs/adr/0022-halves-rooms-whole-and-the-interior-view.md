# 0022 — Halves, rooms whole, and the interior view

- **Date**: 2026-09-05
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after.
- **Amends**: ADR 0021 (what the engine bake returns), ADR 0020 (the exploded view's modules)
- **Records**: FOLLOWUPS F34

## Context

> "now for any module (proton or electron as users ships may not follow that theme) need to get
> sliced down the middle in the explode group. (in manufacturing they are made in 2 pieces. (also
> an explode control toggle to choose to explode rooms or keep them whole.) - and a special render
> mode that renders the faces of the interior mesh, and the backs of the exterior mesh only. the
> rest should become translucent/holographic wireframe, so no matter the viewing angle the
> interior of the ship and its back, camera facing wall is always visible."

## Decision

**Every module is sliced down the middle in the exploded view.** The plan names each part's
manufacturing plane — through its own origin, normal its local Z, so a tunnel or a hull comes
apart lengthways as a clamshell and never across its bore. The engine bake's third pass
intersects every finished solid with a box on either side of that plane; the exploded view
places the two halves pulled apart along the normal by `HALF_GAP_FRACTION` of the explode gap,
each with its own wireframe and pick body under the module's doc id.

**Rooms explode as pieces or whole, at a toggle.** `ROOMS: PIECES` / `ROOMS: WHOLE` on the
toolbar. The bake returns both: the room's pieces (ADR 0021) and its whole shell, each with its
halves; the view shows one or the other under the room's first member and rebuilds on the spot
when the toggle changes.

**An INTERIOR display mode.** Every mesh the bake hands the view carries its faces in three named
surfaces — `exterior`, `interior`, `cut` — and the mode draws them apart: the interior surface and
the cuts as ordinary lit solids, the exterior as one two-pass material whose back faces are opaque
(the far wall, seen from inside) and whose front faces are a translucent ghost, with the wireframe
over all of it. Whatever the angle, the near wall gives way and the far cavity wall and the sliced
wall thickness face the camera. The assembled preview, whose parts have one surface, wears the
exterior's two passes whole.

**Faces are classified by their corners against the distance fields, not by planes.** A lathe's
quads are not planar, so a "plane" for one depends on which three corners are used, and the engine
re-triangulates them its own way: measured, the input quads reported d = 12.63 and the baked faces
12.48 and 12.26, and not one matched. The tessellation's corners are what the engine keeps, so a
face is exterior when every corner sits on a member's body field, interior when every corner sits
on a member's room field, and a cut otherwise.

**…and the test is calibrated to each surface's own offset.** A box's tessellation is the fillet's
core — its half-extent less `round_r` — while its field is the full rounded envelope, so every
corner, edge midpoint and face centre of a box reads the same constant below zero: measured,
**−0.200 m** on a carbon box, 0 on a sphere. Each surface's offset is read off its own corners
first (the median of sixteen) and the classification is made relative to it.

## Consequences

**Measured, carbon on sphere pods and on boxes, walled and as one room.** 14 of 14 parts split,
every half closed, every pair summing to its piece, and 14 of 14 drawn meshes naming their
exterior and interior; the room's whole shell present with its halves. Zero open parts. Bake times
9.0 s / 12.3 s on spheres and 4.8 s / 6.0 s on boxes — the third pass roughly doubles a bake.

**Two engine facts, recorded.** `ArrayMesh.surface_find_by_name` is the method (there is no
`surface_find_name`). And the engine's triangle order IS this project's outward winding: reading
it reversed breaks the merge (two of fourteen halves stopped summing to their piece).

**The box mesh sits inside its own field by the fillet** — `ShapeMesh` builds `size − round_r`,
the field is the rounded envelope. A systematic 1% on a 20 m hull; invisible, real, and now
compensated for rather than fixed. F34.
