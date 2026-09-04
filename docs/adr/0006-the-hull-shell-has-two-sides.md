# 0006 — The hull shell has two sides; joint partitions still do not

- **Date**: 2026-09-01
- **Status**: Accepted
- **Ruleset**: unchanged. The bake is DERIVED, never stored, and nothing here touches
  `ShipDoc`'s canonical form or `ShapeGen`'s generator. No ship re-hashes and no ship moves.
- **Closes**: FOLLOWUPS F10 item 1

## Context

The author, in the first brief:

> "i certainly want to give it a thickness and an interior mesh, trach its volum and mass etc"

`HullBake` extracted one isosurface and returned it. That is a SKIN: infinitely thin, no inside,
nothing to weigh. Volume was reported, but it was the volume the hull DISPLACES, not the volume of
material anybody would have to build, and "mass" was an areal-density estimate over the outer area
with no wall behind it.

The reason it stayed that way is a conflation, recorded in F10 and worth naming because it is the
kind that survives review: **SPEC §7 says the Phase 1 bake produces the all-open "studio" hull with
no walls**, and that sentence was read as covering the hull shell. It does not. It is about
JOINTS — the partitions between two parts, whose geometry is authored in Phase 1 and deliberately
not built. The hull's own skin is a different surface with a different reason to exist, and
`ShipConfig.hull_thickness_m` had been sitting in the tuning pack the whole time with nothing
reading it at bake time.

The bake was already half-prepared for this: `bake()` pads its grid bounds by `hull_thickness_m`
with the comment "the Phase 2 interior shell at level -T has to fit inside the same grid". The
padding was there. The pass was not.

## Decision

**Extract a second isosurface at `iso - hull_thickness_m`, reverse it, and weld it to the first.**

The field is negative inside the solid, so `{sdf = -T}` is the locus T metres below the surface —
the cavity wall. Surface Nets produces it facing the same way the outer surface does, along the
gradient, so it is welded on with **both its winding and its normals reversed**. Both, not one:
flipping the winding fixes backface culling, flipping the normals fixes the lighting, and doing
either alone trades one artefact for another.

What comes back:

| key | meaning |
|---|---|
| `mesh` | the CLOSED SHELL — outer surface plus reversed cavity wall, one surface, one manifold |
| `interior_mesh` | the cavity wall alone, outward-facing, for a caller that wants to show the inside |
| `volume_m3` | unchanged: the OUTER volume, what the ship displaces and what the budgets mean |
| `interior_volume_m3` | the cavity — the habitable void |
| `shell_volume_m3` | `outer - interior`, the material actually built |
| `shell_mass_kg` | outer area × `areal_density_kg_m2` |

**`volume_m3` deliberately keeps its old meaning.** It is what the volume budget, the gauges and
the metrics pass have always read, and silently repointing it at the shell would have moved every
budget reading by an order of magnitude with nothing to notice it. The mesh's own signed volume is
now `shell_volume_m3`, and `tests/core/test_bake.gd` asserts against that instead — the old
assertion (mesh volume == `volume_m3`) was correct for a skin and became wrong the moment the bake
produced a wall.

**Zero thickness skips the second pass entirely.** The interior extraction costs as much as the
first one, so a caller who does not want it pays nothing, gets exactly the mesh the bake always
produced, and `interior_tris` reports 0 rather than a lie.

**Joint partitions are still not built.** SPEC §7 stands, unchanged and unrelitigated: joints are
authored, their connection data is tracked (`ShipJoints`, `ShipJoint.mode`, and since 2026-09-01
the LINK HATCH control and every stock template's hatched connections), and no partition geometry
is generated. This ADR narrows what that sentence covers; it does not overturn it.

## Consequences

- **The bake costs roughly twice what it did**, at the shipped 0.15 m thickness. FOLLOWUPS F5
  already records that a full-grid bake is minutes rather than seconds and lists the escalation
  path in order (coarsen the cell, chunk-and-thread, compute shader); this doubles the constant in
  front of that, it does not change the shape of the problem.
- **A hull thinner than its own wall has no cavity**, and correctly reports `interior_tris: 0`
  with `shell_volume_m3` equal to the whole outer volume. `shell_volume_m3` is floored at zero so
  a degenerate case can never put a negative mass on a gauge.
- **A shell is only closed where the cavity is closed.** Where the hull is thinner than `T` the
  inner surface simply does not exist there, and the shell is open at that spot — which is the
  honest depiction of a part too thin to have an inside, and is visible rather than silent.
- **The bake report the player sees now has six lines instead of four**, including the wall
  thickness it was built at, so the number is attributable rather than mysterious.

## Verification

- `tests/core/test_bake.gd`: the cavity exists and is strictly smaller than the hull; shell volume
  is exactly outer minus cavity; a 0.6 m wall in a scaled sphere leaves the closed-form cavity
  within 8%; zero thickness reproduces the bare skin exactly.
- The sphere in the offset test is scaled 3× on purpose. At the pack's own size the cavity is
  0.55 m across against a 0.3 m cell — under four cells — and Surface Nets under-fills a shape that
  small by about a third. Measuring the OFFSET through that error would have said nothing about
  whether the offset was right, so the test resolves the cavity properly instead of loosening its
  tolerance until it passed.
- gdUnit4 165/165 · selfcheck PASSED · validator PASSED · visual check PASSED · gdlint clean.
