# 0029 — An opening is capped, collared and doored on both sides

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236`
  before and after. A preset's defaults are never written into a document; only what the player
  changes lands in `hatch_params`, and every existing file carries none of the new keys.
- **Amends**: ADR 0008 (a hatched or doorway seam was a wall with the opening "pending"),
  ADR 0020/0021 (the engine bake gains a third pass), ADR 0028 (the interior mesh now has holes
  with capped rims)
- **Records**: FOLLOWUPS F41

## Context

> "since both inner and outer meshes are separate, where we cut holes for hatches, and
> openings, we need those manifold meshes to cap the exposed open hole edges. we also need a
> hatch that can open or close shutter eye style, double hung door style, and single hinge door
> style. and we need the hatches/or frames to openings to be small enough to not protrude the
> inner mesh sides. have a dynamic thickness to account for the thickness of ship hulls they are
> attaching. each hatch will be a double hatch with one on each module such that they are
> aligned and both act as isolated doors covering the same opening on each module.. so one can
> be closed or both. also for doors going on weird topology the topology must resolve into a
> manifold shape that a hatch can go on (easiest way for those is a thin flat faced cylinder (or
> extrusion with the profile of the hatch shape itself) that extends into each module just
> enough to give a flat manifold gasket for the door) .. the user should be able to choose the
> general shape of the door/hatch, square, rect, circ, ellipse, rectangle, triangle, polygon,
> etc, and the dimensions of the door/hatch not exceeding max or min (min a person could
> squeeze through), and the style of the door/hatch."

Until now a hatched or doorway seam was counted as PENDING by the bake plan and fell through to
the same socket cut as a wall: no opening was bored on either executor, on any ship. The hatch
pack was authored, the joint stored a family, and nothing on screen answered to it.

## Decision

**The gasket plane.** A hatched seam stands between a child and the host it is seated in, and
each keeps its own wall there — the child's end cap and the host's socket wall, a hull thickness
each, pressed together at the indenting module's surface. `ShipDoors` puts a plane through the
point where the seam axis crosses the indenter's **tessellation** (cast onto the mesh, not read
off the field: a spar's field zero stood 0.094 m outside the cap the engine had built at one
end and 0.108 m at the other, F34), square to the axis.

**Collar, clear, bore — per module.** On its own side of that plane each module takes the
frame's outline (the hole grown by a frame width) extruded one wall in, or deeper where its
surface sags from the plane, UNIONED on; the same outline on the other side SUBTRACTED, so
nothing of it bulges past the gasket into its neighbour's door; and the hole's outline
extruded through both walls SUBTRACTED. The engine's booleans (a third pass in `ShipCsgBake`,
"DOORS") carry these out; a difference of closed solids is closed, so every rim comes out
**capped** — the ring of wall between the exterior and the interior — with no capping code at
all. The collar is the author's "thin flat-faced cylinder": on a flat cap it is buried and adds
nothing; on a curved surface it fills the sag to a flat ring the door seats on. Measured on a
carbon tunnel: a bore costs 0.0376 m³ of cap, the collar bridging the cap's 5 cm dome gives back
0.005 m³, and twelve pieces come out bored with zero open edges.

**Every field is read at its own mesh.** The fit and the sag are measured on the modules'
distance fields, calibrated to the field's value at the module's own tessellation
(`ShipDoors.Field`): a box sits inside its field by its fillet, a spar by its rounding, and the
doors go on what the engine builds. Before this the collar stood in the air beyond the cap and
the bore took mostly that collar back — a tunnel bored at both ends lost 0.015 m³.

**Sizes follow the wall.** Frame width, collar depth and leaf thickness are fractions of
`hull_thickness_m`, clamped; the leaf sits inside its module's wall, a gap off the plane, so
two closed leaves are back to back and never past an inner surface.

**A hole is clamped to what fits.** The frame's outline must stand inside BOTH modules'
cavities behind their walls — every sampled rim point enters the body along the axis and finds
the room within a few walls — or the hole is scaled down until it does; the largest scale the
seam takes is reported (`DOOR_MAX`) so a panel can bound its fields. Below
`ShipConfig.hatch_min_m` (0.5 m, a person's squeeze) a hole is still bored and reported TIGHT;
a seam nothing fits is a misfit, reported and left walled. A doorway asked at 0.8 × 1.9 on a
1.4 m tunnel scales to what the bore takes.

**Shape, style, size are the player's.** The hole kinds grow square, triangle and regular
polygon (`ShipSeams.KIND_*`); the door styles are none, single hinge, double leaves and iris
(`ShipSeams.DOOR_*`). A hatch FAMILY is a preset — the pack names each one's `shape` and
`style` — and a joint overrides shape, style, width/height, sides under `hatch_params`
(`ShipSeams.PARAM_*`); a doorway takes a shape and a size but never a door. The inspector's
HATCH section offers all of it for the seam the selection names, with width and height bounded
by the seam's own maximum and the squeeze minimum.

**Two doors, one opening.** The leaves are not booleans: `ShipDoors.leaves(door, side, open)`
builds a module's leaves at any amount open — a hinged leaf swung 100° into its own module,
two leaves swung apart from opposite hinges, or an iris of blades whose aperture is the hole
scaled by the amount (the shutter eye). The explode view draws them per piece and swings them
on a tween; the view keeps every door's amount across rebakes; the HATCH section's DOOR buttons
swing each module's door on its own.

## Consequences

**Measured.** gdUnit4 **300/300** (nine door tests, one boring test added); the engine boring
test: 8 doors planned on a carbon, 12 pieces bored, none failed, none open; the resolve check
PASSED with `reports/visual_resolved_doors.png` (one hatch, both doors open); the main windowed
check PASSED; selfcheck hash unchanged; validator 0 warnings.

**The merged reading is checked by volume.** The annular faces a bore leaves round a collar
defeated `MeshMerge` on three of twelve pieces of a box carbon — closed, and 0.4–0.5 m³ too big.
`ShipCsgBake._read` now keeps the merge only when its volume matches the engine's triangles
(`READ_VOLUME_REL`); those pieces draw their triangles' edges in WIRE.

**The pure executor keeps its walls** at doors (F41); the plan carries the door records for
both executors, and `report["bored"]` says which pieces actually were.

**The bake grows a pass**: about a fifth more time on a carbon of spheres.
