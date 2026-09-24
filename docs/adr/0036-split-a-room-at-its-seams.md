# 0036 - A room is finished whole, then split at its seams and capped

- **Date**: 2026-09-22
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side.
  Nothing here touches what a document means; it changes how one room becomes its pieces.
- **Amends**: ADR 0021 (a room cut back by the members' own bodies), ADR 0035 (and, for a pair of
  equals, by a plane between them) - both retired where the split holds
- **Records**: FOLLOWUPS F48

## Context

The author's design, given twice and then in full:

> "the proper way is to union all primatave shapes together, then cut them along the shape of
> interior seam to exterior seam."

> "the cut shapes inner seams all have vertexes, and the outter shell has vertexes, their end caps
> would be the capping of inner seam verticies to outter seam verticies, independantly for each
> piece right? think of a cuve in a cube, and think of the cubes edges as the "seams" of 2 joined
> shapes. the inner cube line between verticies i,j exist, and the outter cubes a,b exists, so a
> face between i,a,b,j would be the cap .. yeilding 4 thick square faces with champered edges."

And, ruling out what had been floated in reply: **"we will never marsh cubes or use surface nets.
weve already decided on excat mesh cfg stuff."**

**Why the old constructions cannot do it.** ADR 0021 cuts a room back into pieces with SOLID
cutters and ADR 0035 divides two equal members on a PLANE. A solid cutter is a priority order - the
first member keeps everything, the last is bitten by all of them, and the bite is the neighbour's
rounded surface. A plane is the right divider only where the two bodies mirror across it, which is
why a carbon of cubes came out right and a boron of cubes came out notched. Neither follows the
seam.

**And the order was wrong.** The author named that too:

> "use standard 3d software pipelines, what would i do in blender, sketchup, autocad, etc.. the
> workflows are almost always a pattern we can repeat" / "dicing is a simple cut, no weird caps,
> simple slice all the way through so i dont see how it could be failing"

Every CAD pipeline unions, hollows, **cuts every opening while the body is still one**, separates,
then dices. This one separated first and bored the hatches into the fragments. The author was right
about the dicing too: a split piece with no tunnel diced perfectly, and only a piece bored AFTER
separation was refused.

## Decision

**A room is finished as one body and only then broken into its pieces.** Its hatches are bored
while it is whole; the shell is then read as the engine's own triangles and SPLIT AT ITS SEAMS by
`MeshSeamSplit`: each member takes the faces that lie on its own surfaces, and the boundary between
one member's faces and another's - which is the seam, and is already a loop of real vertices,
because that is what an exact union puts there - is capped from the inner loop to the outer one,
the author's `(i, a, b, j)` quad per segment. Both members of a pair share those loops, so their
caps are the same surface: the pieces meet exactly, with no overlap, no gap and no plane anywhere.

**Whose a face is, is asked of the surfaces a member is made of** - its body, its cavity, and the
SOCKETS cut into it, each as a calibrated field (F34). A hatch has no field at all: a collar, a
clearance and a bore are plain meshes, so a door says whose they are by naming its two modules, and
the split takes them by their bounds.

**A boundary is where the MEMBER changes, and nowhere else.** A member's own two surfaces meet
wherever a hatch bores through its wall, and the bore closes that hole itself.

**A room the split cannot divide soundly falls back to ADR 0021's cut-back, whole.** The two
constructions disagree about who owns the wall at a seam and are not meant to agree, so a room takes
one or the other, and the report says which (`split_rooms`, `cut_back_rooms`).

## Consequences

**Measured, on the author's own check.** A carbon of CUBE rooms splits: six pieces of 26.64 and
26.68 m³ - within 0.3%, and that 0.3% is the four that carry a hatch - summing to **159.99 m³
against a room of 159.99**. Every piece closed, every edge shared by exactly two faces, and every
one of them dices into its cells. Its boron equivalent no longer notches.

**A carbon of SPHERES does not split yet** and keeps the pieces it has always had. Its pieces come
out closed and the right size but non-manifold, so the gate sends the room to the cut-back. That is
the remaining work, and F48 has what was measured.
RETIRED(ADR 0037): it splits. See the known limits below.

**gdUnit4 322/322** with one new (`test_a_cube_nucleus_divides_at_its_seams`); selfcheck PASSED with
the hash unchanged; validator clean; the windowed visual, resolve and explode checks all pass.

**The resolve check reads a different number now, and it is the truer one.** A piece carries its
hatches whether they were bored into it alone or into the room it was split from, so the report's
`bored` says twelve where it said eight - twelve is the number of pieces that actually have an
opening.

**Five things had to be right, each paid for in a measurement.**

1. **Read the shell BEFORE the n-gon merge.** A merged face spanning two bodies' coplanar surfaces
   lies wholly on neither: a helium left 2188 m² - most of its area - claimed by nobody.
2. **Classify by VERTICES, not centroids.** A centroid sits inside a curved surface by its own
   sagitta, centimetres on a 9 m sphere.
3. **Calibrate every field** (F34), or nothing is found on any surface at all.
4. **Count the sockets** as part of a member's surface, or every room falls back.
5. **WALK the boundary, do not chain it.** Where three bodies meet, one vertex carries two seams'
   edges and a chain hops between them: a sphere carbon's four room seams came back as one loop of
   149.

**Known limits, recorded rather than hidden.**

1. **Spheres fall back** (above). The gate makes that safe rather than wrong.
   RETIRED(ADR 0037): spheres split. The pieces were non-manifold because the shell they were
   split from was read INSIDE OUT; with the read turned round a sphere carbon comes out as six
   closed pieces summing to 250.809 m3 against a room of 250.821.
2. **A lone boundary loop is capped flat.** Where the two surfaces bound a different number of
   holes - a tiny triangle where three cavities meet - the loop is closed by one face of its own.
   Small, and measured as small; on a sphere carbon it costs 0.4% of the room.
3. **Coplanar bodies divide arbitrarily.** Two members whose surfaces share a plane - helium's
   pair - have no seam curve there to follow, and the shared band goes to whichever member the
   fields name first: measured, 125.4 against 114.1 m³ where symmetry says they should halve.
   STANDS (re-measured 2026-09-23, ADR 0037): a helium of BOXES divides 247.956 against 225.963,
   **8.9% apart**. It is the coplanar case only - a helium of SPHERES, whose surfaces touch at a
   curve rather than share a plane, divides 195.701 against 195.843, 0.1% apart.
   HALVED(ADR 0038): a face both members claim now goes to the body it stands nearer, and the cube
   helium divides 242.458 against 231.461, **4.5% apart**. The rest is a face that STRADDLES the
   bisector and can only be given whole - the shell is 64 faces of about 74 m2 each - so halving it
   exactly means cutting the band and inventing vertices. FOLLOWUPS F50.
   CLOSED(ADR 0039): the band is cut in the PLAN instead - both bodies sliced on the plane between
   them before the union, so the ENGINE puts the vertices there and this file still invents none.
   The cube helium divides **236.960 against 236.959, 0.0% apart**.
4. **The split is all-or-nothing per room**, by design (above).
   NOTE(ADR 0037): no room falls back any more. Measured across helium, boron, carbon and neon in
   both `box_hull` and `sphere_pod`: **eight rooms, eight splits, no fallback**.

5. **A room's core can carry a lump no piece is joined to** - NOT a fault of the split, which
   divides it correctly. Where the nucleus bodies meet at the ship's centre their cavities, each
   inset by its own wall, stop short of the middle and leave a little hollow box of material there:
   on a cube carbon, 1.0028 m3 of shell around a -0.2170 m3 void. The split gives each of the six
   members one face slab of it, 0.1310 m3 each, coming to 0.7858 m3 - the lump's net volume to the
   last digit. Each slab is real material belonging to that member and is detached from it, because
   cavity surrounds it. Recorded as FOLLOWUPS F49; it is a question about the cavity model, not
   about the split.
