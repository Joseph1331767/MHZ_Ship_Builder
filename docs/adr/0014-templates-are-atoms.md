# 0014 — Templates are atoms: a nucleus and its extremities

- **Date**: 2026-09-04
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Templates build documents; they are not part of one.
- **Amends**: the element templates of `data/templates.json`, which were a core plus one branch per
  VSEPR direction. `arrangement` is no longer stored on an element; it is derived.
- **Records**: FOLLOWUPS F26

## Context

> "remodel the procedual default ships to more closley match the atomic theme, hydrogen class ships
> should be a single central shape, and large like 8000 m^3, an helium class ship has 2 protons,
> agro 2 main pods and one connection tunnel. these pods are smaller but keep default total volume
> constant acrost all class ships ... as you moive vertically down the table it seeds nuclous count
> (1-8 for practicality all linked directly together with no tunnels) and a set of valence electron
> pods (the external pods linked by tunnels) ... these are just base classifications for default
> templates that users can use and all consist of a nucleus and extremities pretty much."

The old element templates were one core room with a ring of branches — the same shape for every
class, differing only in how many branches. Nothing about them said *atom*, and nothing tied a
class's size to anything.

## Decision

**Every class is a NUCLEUS plus EXTREMITIES, built to one constant volume.**

- **Nucleus** — one body per proton, `clamp(Z, 1, 8)`. They are **fused directly** into one
  another, no tunnels and no hatches, each sunk `FUSE_OVERLAP` of its own span into its neighbour
  so the cluster reads as one mass. Eight is the author's cap "for practicality", and it is also
  where the eight-children-per-parent rule runs out of berths.
- **Extremities** — one per valence electron, each on its own tunnel with a hatch. **Period 1 has
  none**: a closed first shell has nothing outside it, which is exactly what makes hydrogen a
  single module and helium a fused pair, as specified.
- **Volume** — `ShipConfig.template_volume_m3` (8000 m³) divided by the body count, for every
  class. Tunnels are structure between bodies and are not charged against it.
- **Geometry** — the PERIOD picks the arrangement the extremities take (row 2 trigonal, row 3
  tetrahedral, and so on up to cubic), stepped up automatically to a larger arrangement when a
  class has more extremities than that row's geometry has berths.

| class | Z | nucleus | extremities | bodies | each |
|---|---|---|---|---|---|
| hydrogen | 1 | 1 | 0 | 1 | 8000 m³ |
| helium | 2 | 2 | 0 | 2 | 4000 |
| carbon | 6 | 6 | 4 | 10 | 800 |
| neon | 10 | 8 | 8 | 16 | 500 |
| sodium | 11 | 8 | 1 | 9 | 889 |
| argon | 18 | 8 | 8 | 16 | 500 |

**The rules live in `core/`, the numbers live in `data/`.** An element entry carries `z`, `period`
and `valence`; a new `periods` section maps a row to its arrangement; the step-up is derived from
the arrangements' own direction counts. Adding an element or an arrangement still never requires
touching `core/` (AGENTS §3).

**The span is solved, not assumed.** A box and a sphere of the same span enclose very different
volumes, and these classes are defined by volume — so `_span_for_volume()` tessellates the family
once with `ShapeMesh` and scales from there, volume going as the cube of the span. The exact mesher
earns its keep in a second place.

## Consequences

**Measured: every one of the sixteen classes encloses 8000 m³**, from hydrogen's single module to
argon's twenty-four parts. That is the whole point — the classes differ in SHAPE, not in size.

**Helium has no tunnel.** The author described it as "2 main pods and one connection tunnel", and
also said nucleus bodies are "all linked directly together with no tunnels". Asked which governed,
they chose the general rule, so helium's two protons fuse directly. It is the only class with two
bodies and no corridor.

**A general rule fell out of this that should have been there already: a seam operation may never
open a solid that was closed.** A carbon nucleus is host to nine seams, and each is resolved
against the result of the last, so one broken boolean feeds the next and the damage compounds
rather than staying put. Measured: `small_native` left the nucleus centre open after its four
tunnels each subtracted from it in turn, and `big_flat_cutoff` did the same nine plane-cuts deep.
`MeshFlange.resolve()` and `ShipMeshBake._cut()` now both refuse a result that opens a solid that
arrived closed, which is the same guard `_add_stub()` already carried (ADR 0012). The cost is a
joint left overlapping instead of flush — a gap the author has allowed for — and it is a far better
answer than an open hull.

**Molecules are unchanged in structure** and now take their branch slots from the derived
arrangement instead of a stored one; they also share the volume budget across their nodes, so a
water-class ship is the same size as a carbon-class one.

**One test moved house.** `tests/core/test_shape_mesh.gd` built on `helium` and indexed `p_0002` as
a tunnel. Helium has no tunnel any more, so the suite builds `carbon` — which has both a fused
nucleus and tunnelled extremities — and looks the tunnel up by role rather than by id.
