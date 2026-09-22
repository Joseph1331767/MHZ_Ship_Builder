# 0019 — A shell is two nested surfaces, and a room is a union of surfaces

- **Date**: 2026-09-05
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after.
- **Amends**: ADR 0015 (how a shell is built), ADR 0016/0017/0018 (how an open seam is built —
  all three retired by this one)
- **Records**: FOLLOWUPS F31

## Context

> "nope, cuts are not correct they are all sliced flat like sclicing an apple. - and they are not
> shells with uniform thickness, infact the inner mesh looks like a sphere partially subtracted from
> another.. your techniques for making an inner and outer shell and closing it is 100% wrong. ive
> gotten the same result now 6-7 times in a row. so i feel like you arent listening to me."

> "if i had to make a shell... i would make a copy of the part, downsize or upsize slightly, then
> sub one fromn the other.. so whats the big deal here? ... humanity has figured out shells already"

The author was right on both counts, and the second quote is the whole decision.

**Every earlier verification was on the wrong shape.** `ShipTemplates.build(data, cfg, id, {})`
falls back to the alphabetically-first family — a box. The author builds with `sphere_pod`, chosen
in the start dialog. ADRs 0015 through 0018 measured boxes, reported them fixed, and on the
author's screen nothing changed six times. The screenshot that ended it shows a sphere with the
neighbour's body carved into a **solid**: no second concentric surface anywhere.

**On a sphere, the hollowing silently failed.** The shell was `outer − inner` through the BSP.
Measured on a lone hydrogen sphere: **742 open edges and the wrong volume** (235 m³ against a true
370.9), so the guard refused it and handed back the solid. Two concentric lathes of one tessellation
share every longitude plane, which is the one thing a csg.js-style BSP cannot split. Helium: one of
two solid. Carbon: four pods solid, the rest hollowed only because a seam cut happened to break the
coincidence first.

## Decision

**A shell is the outer surface plus the inner surface turned inside out. Nothing is computed.** The
inner surface is strictly inside the outer by construction — an inset primitive, cut a wall deeper
at every seam — so the two surfaces already bound exactly the solid a subtraction would produce.
This is Blender's Solidify. `ShipMeshBake._nest()`. Measured: hydrogen 370.9 m³ to the decimal,
576 faces, zero open edges, **12 ms** where the boolean took 628 to produce garbage.

**A room is a union of surfaces, not a union of solids.** Members joined by OPEN seams bake as one
solid under their first member: every member's outer polygons, less what lies inside any other
member's **body**; every member's interior polygons, less what lies inside any other member's
**room**; the two nested. "Inside" is a sign test on the primitive's distance field, and a polygon
the field crosses is trimmed along the zero crossing, bisected on its own edges the way the flange
finds where two surfaces meet. `_room_surface()`, `_clip_outside()`. Linear in the polygons, no
split cascade, exact to the tessellation. The other members are **absorbed**: present in the solids
as empty meshes, named in the report, and drawn by nothing — the exploded view treats present-but-
empty as "carried by the room" and only a part the bake never named at all falls back to the field.

**Each part is tessellated at its own azimuth phase** (`ShapeMesh.build(shape, segments, phase)`,
`PHASE_STRIDE` = the golden ratio, by sorted part index). The shape is the same shape; only where
its longitude lines fall moves, so no two lathes ever share a plane where a boolean still runs.

**The open seam is not cut, on either surface, and there is no pierce.** ADR 0016's bore, ADR 0017's
skip-and-pierce and ADR 0018's native asymmetric cut are all retired: a room's boundary is the
union, and the union has no seam faces to open.

**A room is one mesh on EXPLODE.** "combining multiple into the same room removes all internal
walls making it a component and defining it as a single room" — it moves as one module, under its
first member's offset.

## Consequences

**Measured on sphere pods.** Hydrogen hollowed, 30 ms. Helium 2 of 2, 211 ms. Carbon **14 of 14**,
2.6 s, zero open parts. Carbon with its six protons one room: **3.2 s** as one hollow mesh of 1977
faces — the chain of five BSP unions it replaced did not finish in 400 s.

**The room's seams are hairlines, and they are not closed.** Where two members' surfaces meet,
each side's boundary was found by bisection on its own edges, so the two polylines agree only to
the sagitta of a segment — about 6 cm on a 9 m sphere at 24 segments. The assembled room reports
**464 open edges** across six spheres and two surfaces. It renders as a faint lip, not a hole; it is
reported by `open_parts`, and the test that opens a nucleus allows the room itself and nothing else
to be open. Stitching both sides to one shared curve is the next piece of work.

**The BSP is now used only where two surfaces genuinely cross and a solid is genuinely needed**:
the flat footprint and the native walled styles. Hollowing never touches it; rooms never touch it.

**Three lessons are in memory, not only here**: verify on the author's family and look at an
image before calling a visual defect fixed; hollow by nesting, never by boolean; and a PowerShell
`Get-Content`/`Set-Content` round-trip destroys a UTF-8 source file.
