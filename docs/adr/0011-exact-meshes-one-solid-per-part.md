# 0011 — Exact meshes, one solid per part

- **Date**: 2026-09-03
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: `ShipHash.doc_hash` of the selfcheck doc is
  `5536787c6c35d236` before and after. No field is touched.
- **Amends**: `docs/SHIP_BUILDER_SPEC.md` §9 — the bake is no longer *only* an isosurface
  extraction. ADR 0010's simplification pass stays where it is and still serves the SDF bake.
- **Records**: FOLLOWUPS F22

## Context

ADR 0010 made the Surface Nets bake produce far better meshes — a box became 12 triangles with an
exact area — and it was still not what the author wanted:

> "this test confirms that this is not what we want at all, its not accurate enough.. we will have
> to do it the slow exact way.. its ok its not like the ship builder needs to run at warp speed
> and once these parts are baked for the player they can render as reg meshes no need for all of
> the sdf stuff. lets just get a single layer shell meshes figured out before we make interior
> thicknesses and such. so yea same exact exactness as sketchup is needed."

Two constraints came with it and both narrow the problem usefully. **Single-layer shells only** —
no interior offset yet — which removes the one thing polygons genuinely cannot do well, since
offsetting a polygon mesh inward by `T` is a hard problem and offsetting an SDF is one subtraction.
And later, decisively:

> "all primatives can be their own mesh, we arent trying to create a single ship mesh, they can
> remain in parts as in space they will have detach capabilities."

## Decision

**A second, exact bake path in `core/mesh/`, producing ONE CLOSED SOLID PER PART.** The SDF stays
exactly where it is and keeps its jobs; this replaces only how a visible mesh is made.

| file | what it is |
|---|---|
| `poly_mesh.gd` — `PolyMesh` | Boundary representation: welded vertices, n-gon faces, holes. |
| `poly2d.gd` — `Poly2D` | Triangulating a face with holes; bridging, corner keeping. |
| `mesh_csg.gd` — `MeshCsg` | BSP booleans: union, difference, intersection, clip-and-cap. |
| `mesh_merge.gd` — `MeshMerge` | T-junction repair, then coplanar fragments back into n-gons. |
| `shape_mesh.gd` — `ShapeMesh` | `ResolvedShape` → `PolyMesh`. |
| `bake/ship_mesh_bake.gd` — `ShipMeshBake` | Every placed part, tessellated and placed. |

### What "exact" means here, precisely

Every vertex is the **analytic** intersection of planes or a point on a parametric surface —
never a sample of a grid. A box is six faces at any size, a cut is a straight line, a bored hole
is round, and no resolution parameter exists to be turned up. That is the sense in which SketchUp
is exact too. It is **not** exact arithmetic: coplanarity is decided against a tolerance, and a
circle is a 24-gon because a polygon mesh has no other way to be a circle.

### The ops are inverted, not re-derived

`ResolvedShape.sdf()` warps the DOMAIN and then asks a primitive:
`prim(shear(twist(taper(p / scale))))`. So the surface is the base primitive's surface carried
**backwards** through those warps, and `ShapeMesh` places a vertex with
`scale * taper⁻¹(twist⁻¹(shear⁻¹(q)))`. All three warps leave `y` alone and act only on `x` and
`z`, which is what makes every inverse a closed form. This is why the mesh and the field agree by
construction rather than by luck, and the test suite asserts it: **every baked vertex samples to
zero in the field it came from**, across every family, under taper, twist, shear and non-uniform
scale.

**Taper and shear keep a face flat** — both are linear in `y`, so a plane goes to a plane and a
box stays six faces. **Twist does not**: rotating by an angle that grows with `y` makes a
helicoid, so a twisted shape is subdivided along `y` and triangulated. That is the one place the
file trades n-gons for honesty rather than emitting quads that lie about being planar.

### One solid per part, and no *accumulated* union

A module that can detach in flight has to be a closed solid on its own, so it is built as one and
never merged into its neighbours.

RETIRED(2026-09-03c): "`ShipMeshBake` runs no boolean whatsoever" / "trimming that is seam work,
which is next". It resolves seams now, because leaving them out silently dropped a feature that
already worked through `ShipSdf.module_view` — *"i right click 2 selected solids, i press the
option i want ... and then after i press explode and it does not show the created manifolds."*
The three ADR 0009 styles reach the mesh: FLAT cuts the child back to the seam plane, PARENT
subtracts the host from the child, CHILD subtracts the child from the host. The style is read from
the joint and never baked into a part, so switching it is non-destructive.

RETIRED(2026-09-03d): FLAT also handed the host a COLLAR — the child's half below the plane, unioned
on, mirroring `module_view`. It was wrong twice. The seam plane is the TANGENT at the attach point,
so on a curved host or a box corner the collar protruded past the host as a spike; and a union is the
only operation that grows a mesh, so a hub host to eight seams (`argon`) never finished — 13442 faces
and a 24-second union by the fifth collar. Where the host is flat the collar sat inside it and added
nothing, so dropping it costs nothing there and removes an artefact everywhere else. **Nothing in the
bake unions any more.** See FOLLOWUPS F23 for the tangent-plane question that remains.

What still holds is the part that mattered: **no boolean result is ever a cutter for the next
one.** Every cut is a single pairwise operation between two parts that share a seam, taken against
the parts as tessellated, on meshes of a few dozen faces. Both defects the whole-ship union had —
fragments accumulating across a dozen operations, and the cost of near-coplanar solids unioned
repeatedly — are properties of ACCUMULATION, and nothing accumulates.

## Consequences

**Measured.** A `helium` template (5 parts) tessellates in **35 ms** — 738 faces, 1380 triangles,
every part closed — and about **1.1 s** once its seams are resolved, which is the boolean and the
merge. Worst disagreement with the field, measured on the UNSEAMED parts, is `0.083334 m` — which is exactly that part's deferred
`round` (0.1) times its 0.833 minimum scale component, and nothing else. `carbon` (9 parts): 71 ms.

**A box is a box.** Six faces, eight vertices, **twelve model edges**. `PolyMesh.to_wire_mesh()`
draws `boundary_edges()`, so a wireframe shows only real edges — a box is twelve lines, not the
eighteen a triangle-derived wireframe shows. Half of what "janky triangles all over the place"
described was those diagonals.

**Two arithmetic findings, both measured, both now load-bearing.**

1. **`Vector3` is 32-bit float**, ~1.2e-7 relative. A flat 1e-7 m plane epsilon is *below the
   noise floor*: a 24-gon at the origin built a correct BSP, and the same prism at `x = 1.0`
   classified its own defining polygon as behind its own plane, recursed to the depth cap, and
   the box it was unioned with vanished — 27 m³ read as 1.24. Fixed with a scale-relative epsilon
   **and** recentring every operation on its operands, so precision depends on the size of the
   parts and not on where the ship's origin is.
2. **The weld tolerance was wrong in both directions.** At 1e-6 m it destroyed the sub-micron
   slivers a near-tangent cut leaves and every destroyed sliver was a hole (27 m³ read as 5.75).
   At 1e-11 it welded nothing, so a shared edge got different indices on each side and a closed
   solid reported 146 unmatched directed edges. It now uses the operation's own relative epsilon.

**`MeshMerge` grouping is a flood fill, not a plane scan.** The first version collected faces by
plane by scanning the planes seen so far — O(faces × distinct planes), and a boolean between
tangential solids makes thousands of both. That, not the boolean, was why a twelve-part assembly
never finished; connectivity is also the more correct question, since two faces sharing a plane at
opposite ends of a ship are not one face.

**`MeshCsg` cannot hang.** A split budget bounds the work and sets `PolyMesh.truncated` when it is
reached, so a caller can refuse an approximate solid rather than ship one silently.

**What is deferred, by decision rather than oversight** (FOLLOWUPS F22): `round`, ribs and
scallops. Those are offset and displacement ops, not domain warps, so no amount of moving a base
vertex reaches them — a rounded box needs real fillet geometry on twelve edges and eight corners.
A part carrying one bakes with sharp edges and reads very slightly larger than its field says, by
exactly `round_r × min(scale)`, which the tests assert as a budget rather than tolerate as slack.

**The SDF is untouched and still the truth layer** for attach, snapping, joints, metrics and the
budget gates. The Surface Nets bake and ADR 0010's simplification remain in place and still serve
the BAKE report and any module the exact path does not cover.
