# 0039 - A shared plane is cut in the PLAN, so the split still invents nothing

- **Date**: 2026-09-23
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side.
- **Amends**: ADR 0036 (its known limit 3 closes), ADR 0038 (which halved the same case)
- **Records**: FOLLOWUPS F50

## Context

ADR 0038 gave a face both members claim to the body it stands nearer, and a helium of cubes went
from 8.9% apart to 4.5%. The rest would not go, and F50 said why: **an exact boolean has no reason
to subdivide a band where two surfaces share a plane**, so it comes back as a few enormous faces -
the whole shell of a cube helium is 64 faces, about 74 m2 apiece - and a face straddling the
bisector can only be given WHOLE. The 110 m2 separating the two pieces was about one such face.

Halving it exactly means a vertex on the bisector, and ADR 0036 is built on never making one: "the
seam loops are already vertices of the shell, because that is what an exact union puts there ...
this file reads what the engine already computed and never invents a point."

## Decision

**The vertex is put in the PLAN, not in the split.** Where two members of a room have faces lying in
the same plane, both bodies and both cavities are cut along the plane between them
(`PolyMesh.sliced_at`) before anything is unioned. The solid is untouched - same volume, same area,
same faces everywhere else - and only the tessellation changes. The engine keeps those vertices and
does not triangulate across them, so the shell arrives with the band already divided, and
`MeshSeamSplit` reads a division it did not invent. **The principle is intact, not bent.**

**Only a pair that actually shares a plane.** Faces must face the same way to within
`COPLANAR_FACING` and their planes lie within `COPLANAR_PLANE_M`. Every curved family fails that and
is never touched; so is every cube pair that merely meets at an angle.

**A crossing is keyed by its EDGE, not by where it lands.** The two faces either side of an edge each
work the crossing out for themselves, and the same arithmetic in a different order lands a hair
apart: keyed by position, the two make two vertices and tear the edge open. Measured while building
this - 16 open edges on one body of a mirrored pair and none on the other, which is exactly what a
tie broken on float noise looks like.

## Consequences

**The coplanar case is closed.** A helium of cubes divides **236.960 against 236.959 m3 - 0.0%
apart**, from 4.5% under ADR 0038 and 8.9% before it. Both pieces sound.

**Proved before it was built.** The pre-split was measured on the shell first: straddling faces went
from 4 faces carrying 234.40 m2 to **none**, with the shell otherwise identical - 64 faces, 4739.50
m2, the same as without it. Manifold keeps what it is given.

**Nothing else moves.** Across the sweep - helium, boron, carbon and neon in `box_hull` and
`sphere_pod` - every other room measures the same to three decimals, because no other pair shares a
plane. A cube carbon still divides exactly, 315.727 against 315.727.

**And it recovers what ADR 0038 cost.** That ADR traded a neon of cubes from 0.25% to 0.39% of
overlap; with the band divided properly it reads **0.26%**, and the other way round (short of the
room rather than over it). The one class that lost by the tie-break is back where it started.

**gdUnit4 328/328**; selfcheck PASSED with the hash unchanged; validator PASSED; gdformat and gdlint
clean; resolve, explode and visual checks PASSED.
