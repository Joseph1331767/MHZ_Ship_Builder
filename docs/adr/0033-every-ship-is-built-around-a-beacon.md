# 0033 — Every ship is built around a beacon, and a room is cut as one body

- **Date**: 2026-09-22
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. A document written before this carries `absolute` as identity on every part (it has
  always been serialized), so it resolves exactly as it did; what moves is what the TEMPLATES build,
  which is new documents rather than a reading of old ones (the ADR 0023 precedent).
- **Amends**: SPEC §3 (the attach model: the root is anchored, not pinned), SPEC §5.1
  (`absolute` is live), ADR 0017 (a nucleus with nothing at its centre — it now rings the beacon),
  ADR 0032 (a room's cells are cut in one frame)
- **Records**: FOLLOWUPS F45; RESOLVES F9

## Context

> "the carbon atom (and other ship) that dont have a central node, end up with an initial parent
> thats non central, and to add central placed shapes to that shape require a weird downward or
> upward angle. and it kinda makes the modules out of alignment. the proper way would be to use a
> beacon or reference node thats invisible but still there where things can grow away from that, or
> provide an option for the slicer to stay in alignment as thats where the issue shows." — the
> author, 2026-09-21

Measured before deciding anything. A carbon's nucleus is six protons on an octahedron with nothing
at its centre (ADR 0017), and `ShipAttach._place_part` pinned the ROOT to `Transform3D.IDENTITY`. So
the ship's origin was wherever its first module happened to be: **3.56 m** off the nucleus centre on
a carbon, **6.24 m** on helium, **3.89 m** on neon. Everything else is placed on a host's surface by
four numbers measured from there, so anything wanted at the middle had to be reached from an outer
body at a steep angle. And the slicer cuts each piece in its own frame, whose Y is the direction it
was placed from its host: the six protons of one nucleus were cut on six differently tilted grids
(0°, four at 118°, one at 180°), which is where the author saw it.

Answered the same day: every class gets the beacon, even where a body lands on it; the anchor is the
`absolute` field; surface placement hangs off it; no legacy path and no option in the harness; the
docs that describe how ships are built are updated; the beacon is internal and drawn as a dot.

## Decision

**The beacon is the ship's origin, and the root is anchored to it.** `_place_part` returns the
part's own `absolute` for the root and for any part with no parent, instead of pinning the root to
identity. Everything else still stands on its host's surface exactly as SPEC §3 prescribes, so the
whole chain hangs off the anchored one. F9's dead field has a meaning at last, and a part floating
free keeps the place it was given.

**Every class is laid out around the beacon.** `ShipTemplates._centre_on_the_beacon` shifts the
root's anchor by the centroid of the ship's core — its root module and whatever the nucleus
component expanded under it — so the core rings the beacon whatever the arrangement holds at its
middle. A one-module ship lays that module over it.

**The anchor travels with the root.** `make_component` copies it onto the instance that replaces the
head, and `dissolve` copies it back onto the part that becomes the root again — with the head's
`asymmetric` flag, which belongs to it for the same reason.

**A template's root module stands outside symmetry**, like every other part a template makes. It did
not need to while it sat on the mirror plane at the origin; centred, the plane would duplicate it —
measured on helium, whose twin landed exactly on its other proton.

**A room is cut as one body** (amending ADR 0032): the cells of a room of several are cut in the
KEEPER's frame across the whole room's extent, so one grid of planes runs through all of its chunks.
RETIRED(ADR 0041): every piece is diced in its OWN axes across its own body's extent. The keeper
of a nucleus stands at whatever angle its class puts it at, so one grid through the room cut every
chunk diagonally - "id rather use local node alignment" (2026-09-24). A room shown WHOLE still
takes one grid, being one body.
A piece standing alone keeps its own frame, so a tunnel still cuts lengthways along itself. The
extras report the frame each piece was cut in (`cell_frames`).

**The beacon is drawn as a dot** at the origin — three short arms, in the accent role, with no depth
test so it reads through the hull it is inside.

## Consequences

**Measured.** Carbon, helium, neon and hydrogen now centre their cores on the beacon to within
0.01 m (they were 3.56, 6.24 and 3.89 m off). A carbon's cells fall from 656 to 534, because one
shared grid through the nucleus cuts fewer empty cells than six fanned-out ones. gdUnit4 **314/314**
with a new suite (`tests/core/test_beacon.gd`, five tests); selfcheck hash unchanged; validator
clean; the visual, resolve and explode checks all pass.

**Two tests were asserting on accidents, and centring exposed both.**
- `test_the_pure_bake_plans_an_open_seam_as_a_pair_of_cuts` failed because a dissolved helium grew a
  mirror twin of its root — the template flag above is the fix, and the test was right all along.
- `test_in_and_out_bump_put_the_plane_in_different_places` compared the SUM of part volumes, where
  the two styles nearly cancel: measured, twelve parts differ by 0.95 to 1.95 m³ each while the sum
  differs by 0.0055 m³ on a 6287 m³ ship — and by 0.00006 once the ship moved. It now asserts on the
  parts, which is what it meant.
- `test_three_overlapping_plus_one_far_gives_two_islands` built its floating spheres by tracing them
  out of the origin, which is the behaviour F9 recorded as wrong; the fixture anchors them now.

**One hardening with no measured effect, recorded as such.** `MeshFlange._footprint_cutter` matched
the cap face by comparing plane distances within a fixed 1e-4. A plane's `d` is measured from the
world origin and a `PolyMesh` holds 32-bit floats, so that tolerance tightens as a ship moves away
from the origin. It is relative to the distance now. It changed no measured number here; the epsilon
was wrong in principle and ships now routinely sit off-origin.

**What this does not do.** There is no UI yet for dropping a part onto the beacon: a central module
is placed by giving a part no parent and an `absolute`, which the harness does not expose. That is
the next piece if the author wants it.
