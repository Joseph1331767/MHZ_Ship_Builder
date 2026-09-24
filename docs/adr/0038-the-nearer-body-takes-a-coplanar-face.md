# 0038 - Where two surfaces share a plane, the nearer body takes the face

- **Date**: 2026-09-23
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side.
- **Amends**: ADR 0036 (its known limit 3, the coplanar case)
- **Records**: FOLLOWUPS F50

## Context

ADR 0036 splits a room by asking each face which member's surface it lies on. Where two members'
surfaces **share a plane**, every face of the shared band lies on BOTH of them and both answers are
right. The rule was "the nearest surface takes it whole", and with both surfaces at the same
distance that resolves to whichever member the fields happened to name first: the whole band went to
one of them.

**Measured, and the premise checked first.** A helium's two bodies are not merely similar - they are
**identical and mirrored**: 4000.001 m3 each, span (22.27, 22.27, 15.87) each, centred at x = +-5.84.
Symmetry really does say halve. It divided **247.956 m3 against 225.963, 8.9% apart**.

## Decision

**A face both members claim goes to the body it stands NEARER.** Two surfaces in one plane hold no
seam curve to follow, so the only divider left is the plane between the two bodies - and the nearer
body centre IS that plane, without one ever being constructed.

**Confined, deliberately.** It applies only where the two readings agree to within
`MeshSeamSplit.COPLANAR_TIE_M` (2 mm) - two surfaces in one plane read a face identically up to
float noise - and only **like for like**, body against body and cavity against cavity. A face that
lies on one surface and merely passes near another is decided exactly as before, and every real seam
still follows its own curve.

**This is not ADR 0035 coming back.** That retired plane divided two whole bodies and cut corners off
them wherever they met at anything but a right angle. This one decides the OWNER of a face that is
already on both surfaces, and cuts nothing.

## Consequences

**The coplanar imbalance halves**: a cube helium divides **242.458 against 231.461, 4.5% apart**,
from 8.9%. Every band face now lands on the correct side of the bisector.

**The rest cannot be had without inventing vertices, and that is the finding.** The shell of a cube
helium is **64 faces** - an exact boolean has no reason to split a coplanar band, so it comes back as
a handful of triangles averaging 74 m2 apiece. A face can only be given WHOLE, so a face straddling
the bisector takes its whole area to one side: the 110 m2 of area that separates the two pieces is
about one such face. Halving it exactly means CUTTING the band at the plane, which means new
vertices - the one thing ADR 0036's construction refuses to do ("the seam loops are already vertices
of the shell ... this file reads what the engine already computed and never invents a point").
Recorded as F50 rather than decided here.

**Sphere classes gain too**, though they have no coplanar surfaces: a carbon of spheres closes from
0.012 to 0.004 m3 against its room, a neon of spheres from 0.975 to 0.262. Two curved surfaces
meeting read a face nearly alike, and the nearer body is the better answer there as well.

**One case goes the other way**: a neon of CUBES drifts from 0.717 to 1.097 m3 of overlap against a
room of 284.622 - 0.25% to 0.39%. Moving a face between members moves the loops its neighbours cap
against, and on eight members that trade did not come out in favour. Recorded, not hidden.

**gdUnit4 328/328**; selfcheck PASSED with the hash unchanged; validator PASSED; gdformat and gdlint
clean; resolve and explode checks PASSED. A cube carbon still divides exactly - 315.727 m3 of pieces
against a room of 315.727 - and every room in the sweep still splits with no fallback.
