# 0010 — The mesh is not the extractor: a simplification pass between them

- **Date**: 2026-09-03
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: `ShipHash.doc_hash` of the selfcheck doc is
  `5536787c6c35d236` before and after. Nothing in this ADR touches a field.
- **Amends**: `docs/SHIP_BUILDER_SPEC.md` §9 (the bake now has a second stage), and
  `tests/core/test_dual_contouring.gd`'s cut-face test, which sampled vertices where it must now
  sample faces. Both marked in place.
- **Records**: FOLLOWUPS F21

## Context

Third playtest of the exploded view:

> "the parts are not being handled properly! when exploding you can see it takes the pieces and
> does very weird things to them, including placing a bunch of unnecessary triangles in the
> scene.. perhaps theres some bad architecture decisions along the way, but we cant have this
> messy resolutions with janky triangles all over the place.. just figure out a way to make it
> right dude... clearly our surface nets are failing or something.. your mental model should be
> google sketchup solid tools type of resolution."

"Clearly our surface nets are failing" is the natural reading and it is wrong, which is why this
ADR exists rather than a patch to `SurfaceNets`. Measured before anything was changed:

| what was asked | measurement |
|---|---|
| Is the field bumpy where the parts look bumpy? | A room's `+X` face is planar to **0.0000 m** over 441 bisections of `ShipSdf.sample()` — in the assembled field and in a module view alike. |
| Are the extracted vertices off the surface? | **0.31 cells** worst case on a room module's outer surface, 0.0094 mean. Fine. |
| Then where do the triangles come from? | A 3 m room module: **1568 triangles** on its outer surface, **65% of the area dead flat**. A lone 2 m box: **588 triangles** where 12 describe it exactly. |

So the extractor was doing its job and the shapes were exact. The defect was that **nothing ever
turned the extractor's output into a mesh.** Dual Contouring emits one quad per sign-changing grid
edge; that is a faithful sampling of a surface and it is not a model of one. There was no stage
between "here is the isosurface, sampled" and "here is what the GPU draws".

Two further measurements shaped the design:

- **Sub-cell detail shatters every edge.** The room family carries `round: 0.02`, about a 6 cm
  fillet, against a 0.25 m bake cell. The grid cannot represent that fillet, so it produces a band
  of noise around all twelve edges of every box — 52 of a module's 72 patches were that band.
  This is the "janky triangles"; it is not fixable by resolution, because the authored radius
  scales with the part and the cell does not.
- **The interior shell was welded in whatever state it came out.** A room module's cavity surface
  landed up to **2.19 cells** off with 6 vertices escaping outside the hull; the tunnel module got
  **zero** interior triangles. Those escapees are the tears visible on the exploded pieces.

## Decision

**A new stage, `core/bake/hull_simplify.gd` — `class_name HullSimplify` — between `SurfaceNets`
and the `ArrayMesh`. The extractor is not changed at all.**

`HullBake.bake()` now runs it over the outer surface and over the interior surface separately,
before the two are welded into the shell. Five steps, in order:

1. **Project** every vertex onto the exact isosurface, Newton along the analytic gradient, clamped
   to ¾ of a cell so a vertex cannot leave the neighbourhood the quad pass assumed it was in.
   Not cosmetic: at a third of a cell out, the facets of a flat face are tilted enough to fail any
   coplanarity test. This step alone took a room module from 130 patches to 72.
2. **Grow** planar patches across edge-adjacent triangles, against a plane fixed from the seed —
   a plane that moves as the patch grows will creep around a cylinder one facet at a time.
3. **Absorb** the fragment rings beside a face into that face, bounded to **two rings**. That
   bound is the whole safety argument: an unresolvable fillet is a band one or two triangles wide
   against a big flat patch, and a genuinely curved surface is fragments all the way through, so
   ring-bounding takes the first and cannot take the second whatever the tolerances say.
4. **Snap** every vertex onto the planes meeting at it — one plane projects it, two put it on
   their line, three or more on their point. One regularised normal-equation solve covers all
   three cases, which is the same shape of solve `SurfaceNets._place_vertex()` already does for
   its QEF, over patch planes instead of crossing tangents. This is what makes an edge exactly
   straight and a corner exactly sharp.
5. **Straighten** each patch boundary (Douglas-Peucker) and **retriangulate** the patch from its
   loops, bridging holes so a bored doorway keeps its opening.

### What it deliberately does not do

**Curved regions keep every triangle they arrived with**, smooth-shaded from the analytic
gradient. A cylinder showing its tessellation is what CAD looks like; decimating it needs an error
metric this pass does not carry. Left to a later one, and named in F21 as a limit rather than
hidden.

### Why not exact polygon CSG

It was considered and rejected, and the author was given the choice explicitly. Exact booleans on
tessellated parts are the true SketchUp answer and would make a box 12 triangles by construction
with no resolution parameter at all. Against that: coincident faces are *exactly* what a seam is,
and robust booleans there need exact predicates; the `-T` interior shell — which is the entire
reason the exploded view can show a wall — has no good polygon equivalent; and the SDF is CONTRACT
(SPEC §4, §9) with metrics, snapping, joints and seams all built on it. That is a Phase-scale
rewrite to fix a meshing bug. The field was never the problem.

## Consequences

**Measured, at a 0.25 m cell.**

| | before | after |
|---|---|---|
| Lone 2 m box | 588 tris | **12 tris, 6 patches, 8 welded vertices** |
| Lone box surface area | — | **23.999 m² against an exact 24.000** |
| Lone box volume | — | **8.000 m³ against an exact 8.000** |
| Whole 5-part ship | 8308 tris | **700 tris** |
| 3 m room module | 2444 tris | **274 tris** |
| Flat share of area, room module | 55% | **92%** |
| Vertices escaping the hull, room modules | 52 / 14 / 8 | **10 / 0 / 0** |

**The shell is still closed.** Patches carry their own copies of a shared vertex — that is what
gives a hard edge its two normals — so edges can only be counted after a positional weld. Welded:
**0 open edges and 0 unmatched windings** on a plain box, a rounded box, both with and without a
hull thickness, on every module of a five-part ship, and on the whole ship. The lone box welds to
exactly 8 vertices.

**Cracks were the design's whole risk**, and the two places they would have appeared are handled
by construction rather than by tolerance: snapping is global and runs before any patch is
triangulated, and boundary straightening runs over chains keyed by the planes meeting along them,
once, not once per patch.

**Bake cost rose about 35%** (a five-part ship: 724 ms → 980 ms) — the projection step is four
field samples and four gradients per vertex. Vertices are O(n²) against the O(n³) sample grid, so
this is the cheap axis, and the exploded view still bakes a module in 100–400 ms.

**The tunnel module has no cavity, and that is correct.** It survived investigation as a suspected
bug: at `hull_thickness_m` 0.4 against a tunnel bore of 1.0 m there is 0.1 m of cavity radius left,
so the tunnel really is solid. Confirmed by re-baking it at a 0.16 m cell, where it is still solid.
Not a resolution failure, and `ShipExplodeView` was left alone on the strength of that.

**A GDScript trap worth recording, because it silently emptied the first draft of the file.**
`PackedInt32Array` and its siblings are **value types**: a function that appends to one it received
as an argument is appending to its own copy. `Array` and `Dictionary` are references and behave the
way one expects. Every private function in `HullSimplify` therefore returns its arrays rather than
filling them through an out-parameter, and the class docs say so, because the failure mode is a
silent empty result rather than an error.
