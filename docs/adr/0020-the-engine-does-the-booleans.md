# 0020 — The engine does the booleans

- **Date**: 2026-09-05
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after.
- **Amends**: ADR 0011 (the hand-rolled BSP as THE exact bake), ADR 0019 (rooms as surface unions,
  members absorbed), ADR 0017 (the 45° rim), ADR 0015 (the 0.20 m wall)
- **Records**: FOLLOWUPS F32

## Context

> "the assembled room doesnt explode into its pieces so i cant inspect the interior - building a
> square primitive carbon vs a sphere one yeilds different results, the sphere one has the electron
> pods all angled down below the craft making a pyrimid. all shaped hull versions should look the
> same.. - only half of the tunnel-to-module connections cut as described. also the distance
> between meshes is or appears to be way way more then the 40cm we described. i dont care what
> tricks need to be used we need the shell to be about 10-20cm for now ... where seams exist i can
> see a gap to the exterior of the hull, very small."

And, from the same day, the question that decided this:

> "if i had to make a shell... i would make a copy of the part, downsize or upsize slightly, then
> sub one from the other.. so whats the big deal here? why not union all protons, downsize slightly
> centered, and play the same tactic... or you know standard 3d software and blender type stuff ...
> humanity has figured out shells already"

It has. **Godot 4.4 and later back their CSG nodes with the Manifold library** — an exact, robust
mesh-boolean engine that handles coincident faces and concentric surfaces correctly — and it was
sitting unused in this engine because `core/` is kept free of Nodes. Four generations of boolean
machinery were built in this session instead: a csg.js-style BSP (ADR 0011), nested shells with BSP
unions (ADR 0019), polygon clipping against distance fields, and a shared-segment seam splitter.
Each fixed the previous one's failure and exposed a new one; the last two could not make the two
sides of a curved seam share a vertex, and left every sphere piece with hundreds of open edges —
the "very small gap to the exterior."

Measured, the engine's CSG built a helium sphere's shell, a hole through it, and a wall stopped at
a neighbour's room — every one closed, zero open edges, all three in under 80 ms.

## Decision

**`core/` plans; the engine executes.** `ShipMeshBake.plan()` is pure data: every placed part's
three surfaces (outer, interior inset by the wall, body grown by the wall), tessellated at its own
azimuth phase, and for each part the list of cuts its seams ask for — which cutter takes its outer
surface and which its inner. `ShipCsgBake.bake()` in `harness/` carries that plan out with
`CSGCombiner3D` / `CSGMesh3D` nodes: each part is *outer, less every outer cutter, less (interior,
less every inner cutter)*. It awaits the frames the engine takes and reads the result back as a
[PolyMesh] of merged n-gons. `ShipMeshBake.bake()` carries the same plan out with its own
distance-field clipping, exact on planes and approximate on curves; it remains for a caller with no
scene tree, and its tests are held to what it promises.

**The seam rules are unchanged, and now they work.** Open: the indented part loses the indenter's
body on both surfaces, the indenter loses the indented part's room on both; the two pieces mate
face to face and each explodes on its own. Walled: the indented part loses the indenter's body on
its outer surface and the indenter's body *grown by a wall* on its inner, so the wall follows the
socket at its own thickness; the indenter is untouched. Which side indents is the style's axis,
with a tie to the child.

**A room is its pieces again.** ADR 0019's absorbed members are retired: a room explodes into its
protons, each a closed piece with its holes, which is what "so i can inspect the interior" asks.

**Pods point along their slot in ship space.** A part's +Y is the mount normal where it landed,
and that is level on a box face and radial — 30° down — on a sphere. Naming the pod's direction in
ship space and converting it into the proton's frame at build time is what makes both families lay
out alike.

**The wall is 0.10 m.** Two walls meet at every seam, so a seam reads as 0.20. It is configurable
in `data/tuning.json`.

## Consequences

**Measured, carbon on sphere pods and on box pods, walled and as one room.** Every part a closed
shell of about one shell's worth of hull; every tunnel's pod carries its socket (967 faces where a
plain shell has 576); the open room is six pieces, the root with five holes (14.6 m³ against a
39.9 m³ shell), every rim with its own; zero open parts in all four cases; 2.2–4.1 s a bake. The
rim sits 49% of the way from top to bottom on spheres and 48% on boxes, and every pod reaches level.

**The engine is asynchronous.** A CSG node computes on a deferred call, and one frame was enough
for the second bake of a run and not for the first. `ShipCsgBake` waits until every combiner has a
mesh (up to `READY_FRAMES`); the builder's EXPLODE awaits it and raises `_explode_baking` for the
frames it takes; the visual check waits on that flag as well as the view's own.

**Merging the engine's triangles into n-gons can tear an edge**, and the merge is presentation
only, so a piece it tears is returned as the triangles it came in as.

**Flat and native styles are one surface for now.** Every walled seam takes the native socket.
The flat styles' plane cut and footprint prism are straightforward as CSG operands — a box beyond
the plane, the prism the flange already builds — and are the next piece of work (F32).

**Three memory notes** carry the lessons out of this session: verify on the author's family and
look at an image before calling a visual defect fixed; hollow by nesting, and let the engine do the
booleans; a PowerShell text round-trip destroys a UTF-8 source file.
