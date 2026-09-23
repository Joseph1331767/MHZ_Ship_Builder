# 0035 - Equal members of a room divide down the middle, and a body on nothing explodes outward

- **Date**: 2026-09-22
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. Nothing
  here touches what a document means; it changes how a room is cut into its pieces and where those
  pieces travel.
- **Amends**: ADR 0021 (a room's pieces are cut back by the members BEFORE them -> two members that
  are equal divide on the plane between them), ADR 0032 (the explode's first stage), ADR 0034
- **Records**: FOLLOWUPS F47

## Context

> "6 cubes overlaping about the center should not be leaving messy edges between their seams and
> all should be exact copies of one another, thats my verification ive been running so i know
> something is off here. also when i press explode its [not] about the axis, hell the entire ship
> moves down from the top node which it should not, the top node piece should move away from
> center" - the author, 2026-09-22, on ADR 0034's nucleus

Both halves of that are one thing: the clump was still being read as a CHAIN with a first member,
when ADR 0034 had made it six equal bodies about a centre.

**The pieces.** ADR 0021 cuts a room back into its pieces as "the room's shell within the member's
own body, less the bodies of the members before it" - a priority order. On a clump of equal bodies
it is wrong twice: the first member keeps everything and the last is bitten by all of them, so no
two pieces are alike; and the bite is the neighbour's ROUNDED body, which leaves a curved groove
where a face belongs. Measured on a cube carbon: six pieces from 18.9 to 29.2 m³.

**The travel.** `ShipSeams.explode_offsets` pulls each module along the seam it leaves and hangs
everything else off it. A body that stands on NOTHING has no such seam, so the one body of the
clump that was nobody's child stayed put and the other five travelled away from IT - the whole
nucleus sliding off its top body, which is what the author saw.

## Decision

**Two members of one room that are neither larger than the other divide on the plane where their
fields read alike** - for a pair of the same solid, the perpendicular bisector of the line between
their centres. `ShipMeshBake.plan` bisects for that point and reports it under `room_splits`; the
engine executor subtracts a half-space there instead of the neighbour's whole body. Where one body
IS larger the priority order stands, because that is the truer statement of a tunnel sunk into a
hull: the tunnel keeps its own body.

**A module that stands on nothing travels away from the beacon.** Radially, from the ship's build
centre, which is the point it was laid out around (ADR 0034). A module that stands on a host still
leaves along its seam, and anything hanging off either follows.

**In the explode's first stage a room holds still unless something outside it carries it.** Every
member rides; the one standing on something OUTSIDE the room is the one that pulls the room off its
own seam. A nucleus has no such member, so a class holds its core where it is and pulls its pods
off it - then, in the second stage, the core comes apart radially.

## Consequences

**Measured.** A cube carbon's six nucleus pieces come out 26.64 to 26.68 m³ - 0.15% apart, and that
0.15% is the four of them that carry a tunnel socket, which is real geometry. They were 18.9 to
29.2 m³ (over 20%). The cut faces are flat: the top piece reads back as 20 faces where it used to
be a rounded bite. The six travel out along their own axes, the two on the Y axis included.

**gdUnit4 322/322** with two new (`test_equal_members_of_a_room_divide_on_the_plane_between_them`,
`test_a_clump_of_equal_bodies_comes_out_as_pieces_of_one_size` - the author's own check, asserted);
selfcheck PASSED, hash unchanged; validator PASSED; gdformat and gdlint clean; the windowed visual,
resolve and explode checks PASSED.

**One test was asserting the old staging.** `test_in_the_first_stage_a_rooms_chunks_ride_it` built
its riders as "every chunk whose SEAM host is in the same room" and asserted each sat exactly where
that host sat. With a clump that stands on nothing there is no such host to sit on; it asserts what
the stage means instead - every member of the room holds still together, and each one travels away
from the centre in the full explode.

**AMENDED the same day: the plane is confined to the box the two bodies share.** A plane is
infinite and a body is not. Where two bodies meet at anything but a right angle the half-space ran
on past the one it was dividing from and took a corner of the member with it - material no
neighbour ever stood in. Measured on a BORON class, whose three equatorial bodies sit 120 degrees
apart: the plane reached 0.39 m into each body over its whole height, and the pieces came out with
notches cut out of them. "when a cube collides non-orthognally it doesnt bite and seam along all
geodesics, its just a flat cut and leaves cornerns and stuff cut out and unresolved" (2026-09-22).
The cutter is now ONE box standing on the plane and covering only what the pair's two bodies have
in common. Boron's axial pieces went from 30.45 to 30.88 m³ and its equatorial three from 4% apart
to 1.6%.

The bound is a BOX rather than the neighbour's own solid, which would be the exact answer: that
surface IS the room shell's surface there, and a cutter standing on the surface it cuts is a
coincidence the boolean engine will not resolve - measured, clipping to the solid gave a sphere
nucleus an open piece and cells that would not close.

**Known limits, recorded rather than hidden.**

1. **The pure executor does not cut on the planes.** `ShipMeshBake.bake` keeps its per-part rule and
   ignores `room_splits`; the engine bake is what the player sees (ADR 0020's "one plan, two
   executors"), and this is one more way the two differ.
2. **The plane is a plane.** For two bodies that are equal in volume but differently shaped, the
   true equidistant surface curves; what is used is the plane through the equidistant point on the
   line between their centres, square to that line.
3. **A mixed clump could strand a sliver.** Where some pairs of one room are equal and others are
   not, the plane rule and the priority rule meet, and a point in a triple overlap could fall
   outside every member's claim. No class in the pack builds one; a room of equal bodies (every
   nucleus) and a room of a hull and its tunnels (every other room) are each wholly one rule.
4. **The division inside the overlap is still a PLANE, and the seam is not flat.** The surface that
   divides two fused bodies from the inner seam curve to the outer one is the surface where their
   two fields read alike - flat only when the two are mirror images across it, which is why a
   carbon of cubes comes out right and a boron of cubes does not. The plane is confined to what the
   pair share, so it no longer takes corners off; within that box it is still an approximation, and
   the material it divides is the wall-thick ring around the seam.
5. **A clump of cubes on a THREE-fold arrangement cannot have identical pieces.** A cube has no
   three-fold symmetry about a face axis, so boron's three equatorial bodies necessarily meet its
   two axial ones differently: measured, 34.29 against 34.85 m³, and no cut can make them equal.
   Carbon's octahedron lines up with the cube's own four-fold axes, which is why its six match.
6. **A radial travel needs a centre to be radial FROM.** A module whose box is centred on the beacon
   gets no direction and stays where it is, which is right for a body laid over the centre and is
   also what a caller that merges a component's inner parts into their instance sees.
