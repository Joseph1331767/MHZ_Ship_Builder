# 0008 — Seams, walls, and the exploded view

- **Date**: 2026-09-02
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — nothing that feeds `ShipHash` moves; see Consequences
- **Amends**: `docs/SHIP_BUILDER_SPEC.md` §7 (not a CONTRACT section) — the Phase 2 construction
  it recorded is built, with two refinements; §13 M6
- **Records**: FOLLOWUPS F19 (the additive contract extensions)

## Context

The author, after a playtest:

> "after all rooms are defined and hatches, the objects must be subtracted or added to
> eachother, with a flat faced seem where they mate that flat seem is where we will cut the
> hatch doors into, centered auto placed - we want an auto explode btn that explodes all the
> modules apart revealing their internal hatch walls."

and, asked what the seam between two rooms should be when nothing has been linked:

> "if its 2 separate rooms, just a solid wall no door. by default. but it should have dynamic
> options for how 2 rooms link."

SPEC §7 had written the construction down and deferred it: "the partition is a plate of hull
thickness lying in the joint plane (which the attach model already computes — the plane through
P with normal N), clipped to where both solids are, with a seeded hatch SDF subtracted, unioned
into the hull field." Two of those clauses turned out to be wrong in the building, and the
exploded view needs a construction of its own. This ADR is the geometry, so it is not reinvented
the next time someone reads `ShipSdf.sample()` and wonders why it takes a `max`.

## Decision

### The seam is the attach model's plane

A **seam** is laid wherever a placed part stands on another: every non-root doc part, every
component instance (on its proxy shape), every symmetry twin. Its plane is `P`, the anchor the
part was traced or snapped onto, with normal `N`, the mount normal there — the pair
`ShipAttach.anchor_for()` returns, which is also what `local_transform()` seats the part with and
what the gizmo's footprint collar is drawn on. One anchor, three consumers, no drift.

The inner parts of a component get no seam: a component is one room (SPEC §6). Two siblings
that merely overlap get no seam either: there is no attach plane between them, and a plane
invented from their centres would cut things the author never placed. They merge as before.

### What closes it — the four link modes

| joint record over the pair | seam mode | geometry |
|---|---|---|
| none, or `sealed` | `wall` | a solid plate — **the default** |
| `doorway` (new, F19) | `doorway` | the plate with a plain rounded-rectangle opening, `doorway_width_m x doorway_height_m` |
| `hatched` | `hatched` | the plate with the hatch family's opening: circle from `radius`, oval or rounded rectangle from `width x height` (`corner_radius`), pack defaults under the joint's stored params |
| `open` | `open` | no plate — the cavities merge, one room |

Every opening is **centred on the anchor and square to the seam** ("centered auto placed"): the
hole's 2D profile lives in the mount frame's XY at `P`, height along the frame's +Y. The tree
panel's LINK button cycles WALL → DOORWAY → HATCH → OPEN → WALL, and the meet test the validator
uses gates every step that opens the seam wider; closing back to a wall is never refused.

### The plate, in the assembled field

The plate is the host's own skin continued across the opening the union removed: a slab of hull
thickness `T` on the **inner** side of the plane, `[P - T, P]` along `N`, clipped to the
**child's** cross-section (`max(slab, child_d)`), with the opening subtracted
(`max(..., -hole_2d)`). Not "clipped to where both solids are": on a flat host face the plane
*is* the face, and the intersection of the two solids at the plane is half a slab.

It cannot be *unioned* in. A `min()` union is already deep inside at the seam, and `min()` with
a plate changes nothing. The plate enters as

    f = max(union_d, -T - plate_d)

Inside the plate that is `[-T, -T/2]` — solid, never cavity — so the outer surface (level 0) is
untouched and the interior isosurface (level `-T`, the one the bake extracts for the cavity)
gains the plate's two faces, which close against the cavity wall exactly where `union_d = -T`.
Outside the plate the term is below `-T` and can only distort distances no isosurface reads.
Plates need `T > 0`; a skinless hull has no walls.

**A plate thinner than a grid cell is a bump the grid steps over.** The hull skin is found by
interpolation however thin it is because the field crosses it monotonically; a plate is
cavity–wall–cavity, and with no sample inside it, it is not there. `HullBake` therefore extracts
from `sdf.with_min_wall_m(fitted_cell * 1.05)`: the plate is widened *into the host* to at least
one cell of the spacing the extractor will really use (`SurfaceNets.fitted_cell`, after the
`MAX_CELLS` cap), and its field value is scaled so it still peaks at `-T/2`. A coarse bake gets a
thicker bulkhead rather than none. The default bake (0.25 m cells, 0.15 m hull) widens every
wall to 0.26 m; the metrics grid (0.5 m) does not see plates at all and the interior-volume
gauge reads the studio cavity — recorded in F19, not hidden.

### The module, for the exploded view

`ShipSdf.module_view(id)` is the same class with clips and pucks instead of plates:

- the module's own entries are clipped to the **outer** half-space of its seam — the face it
  stood on comes out flat ("subtracted");
- for every seam whose host it is, the child's entry is clipped to the **inner** half-space and
  kept — the collar of the child that was sunk into it stays with the host ("added");
- a **puck** bores the opening through the module's own flat face (`[-ε, T + ε]` along `N`), and
  down through each collar and the skin beneath it (`[-(stub + T + ε), +ε]`); an `open` seam's
  puck is the child's whole cross-section, so the face is left off and the cavity shows.

No plates: the flat face gets its `T`-thick wall from the interior isosurface for free, and
baking a module at levels 0 and `-T` gives a closed shell whose seam face is a wall with the
door in it. `ShipExplodeView` bakes one module per frame at
`max(bake_cell_m, longest_axis / explode_cells_per_axis)` and places it at
`ShipSeams.explode_offsets()`: each module moves along its seam normal by
`explode_gap_m + half its extent along that normal`, accumulated down the host chain. Every part
visual hides meanwhile; any document edit assembles first.

## Consequences

- **Every bake with more than one part changes.** The interior mesh gains wall faces and the
  interior volume falls where walls are. `volume_m3`, `area_m2` and the shell numbers keep their
  meanings; the report gains a SEAMS line. `test_bake.gd` gates that a sealed seam adds interior
  triangles and leaves the outer area alone.
- **No ruleset bump.** `ShipHash` consumes the doc — parts and their params — and no stored
  field changes meaning; a doc that never uses `doorway` is byte-identical on disk. The bake is
  not hashed and never was.
- **The attach model is untouched.** `anchor_for()` is a refactor of `local_transform()`'s first
  three steps; `tests/core/test_attach.gd` asserts the anchor is on the surface, the normal is the
  gradient, and the placed origin sits on that normal.
- **Rooms are real now, at a cost.** Sinking a part into another used to be free; it now makes a
  wall the bake and the explode view show, and LINK is how the player opens it. Templates already
  hatch every connection they make.
- **Two limits are named, not fixed.** Sibling overlaps have no seam. The metrics grid does not
  see plates. Both are F19 entries and both have an obvious next step if they matter (a mid-plane
  seam for siblings; a finer metrics cell or a plate-aware volume).
- **The fitted-cell widening is a rendering fact leaking into the field.** It is confined to
  `HullBake` and `with_min_wall_m()`, and `ShipSdf.build()` still lays the geometric truth;
  anything that samples the field directly (the seam tests, the validator) sees `T`.
