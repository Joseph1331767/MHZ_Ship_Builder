# 0009 — Dual Contouring, and the three seam styles

- **Date**: 2026-09-02
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: `ShipHash.doc_hash` of the selfcheck doc is
  `5536787c6c35d236` before and after. See Consequences.
- **Amends**: `docs/SHIP_BUILDER_SPEC.md` §9 (the "upgrade path" paragraph — carried out) and
  ADR 0008's single flat plate; both marked RETIRED in place.
- **Records**: FOLLOWUPS F20

## Context

Second playtest of the ADR 0008 seam work:

> "exploded view does not let part selection, and doesnt render it anything other then flat. -
> i dont see Fresnel node under the render types. - the mesh resolution of the seem between 2
> objects is incorrect, its not flattened along the plane of intersection its all bumped out and
> weird looking. aside from that id like to be able to select 2 shapes, right click them and have
> 3 options for seem, parent indents child > child indents parent > and flat plane at
> intersection."

The first two are plain omissions and are recorded in the devlog, not here. The other two are
decisions.

## Decision 1 — Dual Contouring

**`SurfaceNets._place_vertex()` solves a QEF instead of averaging.** SPEC §9 wrote this down and
reserved that exact function for it: *"replace only place_vertex() with a QEF solve over the
gradients at the edge crossings, clamped to the cell ... and boxes get their sharp edges back. Do
that when the rounding is a problem, not before."* Cutting parts flat at their seams made it the
problem.

The centroid rule is exact on a plane — the centroid of coplanar crossings is on the plane — so a
seam face was never wrong in its middle. It was wrong at every SHARP feature, by up to half a
cell: the rim where the flat face meets the flank, every box edge, every cylinder cap. That reads
exactly as "bumped out and weird looking", and it is why the fix is about corners even though the
complaint was about a flat face.

Three details worth keeping:

- **The normals are free.** The gradient at each crossing comes from the trilinear interpolant of
  the cell's own eight corner samples, which the loop already holds — not from
  `ShipSdf.gradient()`, which would have cost six field evaluations per crossing, and the field is
  the expensive half of a bake (FOLLOWUPS F5). It is also the *better* normal here: the QEF is
  being solved against the surface the grid actually represents, and where that surface is planar
  the trilinear gradient is the plane's exact normal.
- **Regularised toward the centroid** (`(AtA + λI)x = Atb + λc`, λ ≈ 0.01·crossings). The QEF
  matrix is rank-deficient wherever the surface is locally planar or a ridge, which is most cells.
  The pull is weak enough to move nothing on a plane and only to break ties at a corner. A
  degenerate determinant falls back to the centroid — i.e. to exactly the old behaviour.
- **Clamped strictly into its own cell.** The quad pass joins the four cells around each
  sign-changing edge assuming each vertex is inside its own cell; a QEF on a near-flat ridge can
  otherwise solve to a point far outside it and self-intersect the shell.

## Decision 2 — three seam styles

`ShipJoint.seam_style` is `flat` (default) | `parent` | `child`. The MODE (ADR 0008) says whether
a seam is open, walled or doored; the STYLE says what SHAPE it is. Confirmed with the author
against a diagram before implementing:

| style | seam surface | the overlap volume | the child | the host |
|---|---|---|---|---|
| `flat` | the plane through the attach anchor | split at the plane | keeps the outer half | keeps the inner half as a collar |
| `parent` | the **parent's** surface | the parent's | dented to fit the parent | untouched |
| `child` | the **child's** surface | the child's | untouched | socketed to fit the child |

**All three are exact partitions of the same union** — every point where the two solids overlap
belongs to exactly one module, never both and never neither. That invariant is the test
(`test_every_style_partitions_the_overlap_between_exactly_one_module`) and it is what makes the
choice purely a matter of taste rather than of correctness.

**One rule serves all three.** The plate is the shell of hull thickness lying just inside the seam
SURFACE, clipped to the other solid, with the opening subtracted:

    plate = max( shell(surface_d), other_d, -hole_2d )
    field = max( union, -T - plate )

where `surface_d` is `q.z` (flat), the host's distance (parent) or the child's distance (child),
and `other_d` is the solid the shell is trimmed to. ADR 0008's slab is the flat case of it.

**FLAT is a plane, with what that implies on a curved host.** Its plate is a tangent plane through
the anchor, so on a sphere the two cavities can still meet around its rim. That is what "flat
plane at intersection" means, it is exactly why the other two styles were asked for, and it is
recorded rather than silently corrected. The default stays `flat` because it is what every
existing document means.

## Consequences

- **No ruleset bump, and it was measured, not argued.** `to_dict()` writes the `seam` key only
  when the style is not `flat`, so every joint ever saved serialises byte-identically and
  `doc_hash` is unmoved (`5536787c6c35d236` before and after). Same technique the `role` default
  used (F18).
- **Every bake changes shape slightly**, and for the better: box corners and cylinder rims come
  out sharp. `test_bake.gd`'s existing tolerances all still pass — Dual Contouring is strictly
  more accurate — and a 2 m cube now bakes within 2% of analytic volume where the centroid rule
  lost several percent to rounded edges.
- **Cost is one 3×3 solve per surface cell and zero extra field evaluations.** The bake is no
  slower in the part that dominates it.
- **The exploded view previews walls at 1.6 cells thick** (`ShipExplodeView.WALL_PREVIEW_CELLS`).
  A cavity thinner than a grid cell is not a thinner wall, it is noise welded onto the outer
  surface — which is what the coarse explode grid was producing. Same "widen it until the grid can
  see it" rule `HullBake` already applies to plates, and it is honest as a preview: it shows
  where the walls are, not how thick they are.
- **A module's pick collider is a convex hull, not a trimesh.** The trimesh was the obvious
  choice and did not work: measured, a body in the tree, on the right layer, holding 1652
  triangles was passed through by every ray with backface collision both on and off, in a space
  where a part's convex body was hit from the same camera in the same frame. Convex is what parts
  already use, and it costs only a click into a module's open cavity.
