# 0015 — Every module is a shell

- **Date**: 2026-09-04
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Nothing here touches a field or a document.
- **Amends**: ADR 0011's claim that a polygon pipeline could not carry an interior shell; three
  coupled tuning levers, retuned together.
- **Records**: FOLLOWUPS F27

## Context

> "now we need the inner shell surfaces made.. we will not worry about the link between 2 modules
> yet. the hatch and seam surfaces remain solid seems. we will be crafting the inner surface for
> every module individually. about 20 cm thick hull by default. after each inner shape is created
> we need to subtract it from the outer shape to get our approx 20cm thick hull."

ADR 0011 named the interior shell as the one thing polygons were bad at, and used it as the reason
to keep the SDF bake: *"offsetting a polygon mesh inward by `T` is a hard problem and offsetting an
SDF is one subtraction."* That is true of a mesh with no provenance. It is not true here.

## Decision

**The interior surface is derived ANALYTICALLY from the same parametric primitive, not offset from
the mesh.** `ShapeMesh.inset(shape, thickness)` returns the shape with its primitive shrunk —
a box's half-extents, a sphere's radius, a cylinder's radius and half-height — and that goes through
the same domain warps and the same transform as the outer surface. Exact for a box, and correct to
the tessellation for everything round.

**The shrink is per axis, divided by the scale.** `scale` is applied after the primitive, so a local
shrink of `d` becomes a wall of `d · scale` in the world. Where one number serves a whole primitive
— a sphere's single radius — the smallest scale component is used, which errs toward walls that are
too thick rather than too thin.

**Both surfaces are seam-cut, and the interior's cuts are INSET.** The outer is cut by the seams as
before; the interior is cut by the same seams with every plane pushed inward by the wall and every
neighbouring cutter fattened by it. That is what keeps the cavity clear of the seam faces — *"the
hatch and seam surfaces remain solid"* — so a module comes out a closed shell with no way in until
a hatch is cut. Then `shell = outer − interior`.

**A part thinner than two walls stays solid.** `inset()` collapses its primitive, `build()` returns
an empty mesh, and the subtraction has nothing to take out. That is the honest answer rather than a
wall turned inside out.

## Consequences

**Measured.** A hydrogen class: outer half-width 10.0000 m, inner 9.8000 m — **a wall of 0.2000 m**,
twelve faces (six outer, six inner), zero open edges. Its 8000 m³ becomes 470 m³ of hull around a
7530 m³ cavity. Carbon hollows all fourteen parts, argon twenty of twenty-four — the four it leaves
solid are tunnels too narrow to have an interior, which is correct.

**Three levers were coupled all along, and moving one exposed it.** The shipped wall was 0.15 m —
`data/tuning.json` overrode the code default of 0.4, which is why the tests had been passing against
a number nobody had read lately. Moving it to 0.20 m broke the invariant that two joined modules'
interiors meet, and chasing that turned up a chain:

- `attach_embed_m` 0.45 → **0.60**. Two 0.20 m walls need more than 0.40 m of overlap before the
  cavities touch at all; 0.50 is the first value where every compact pair merges, and it leaves a
  connection 0.10 m deep that the validator sampled straight through. 0.60 leaves 0.20 m.
- `tunnel_bore_m` 1.0 → **1.4**. A tunnel cannot be seated into more deeply than its own radius —
  measured, a room on a 1.0 m bore reaches 0.503 however deep it is asked to go — so a 0.60 embed
  needs at least a 1.2 m bore. 1.4 m leaves a 1.0 m clear corridor inside the walls.
- `ShipJoints.SOLID_SAMPLE_STEPS` 10 → **16**. The thing being sampled for is a CAVITY, and a cavity
  shrinks with the wall. The giveaway that this was sampling and not geometry: the answer was **not
  monotonic** in the embed depth, going from eight unmerged joints to none and back as the overlap
  slid between grid lines.

None of these was a free choice; each is the smallest value that satisfies a stated invariant at a
0.20 m wall, and each carries that reasoning at its declaration.

**Two tests now name the thickness they assert against** instead of reading whatever the default
happens to be. A seam plate's field lift is proportional to the wall, so a 0.05 threshold is simply
the wrong question at 0.20 m; `test_seams` pins 0.15, the wall it was tuned at. And every test in
`test_shape_mesh` that is about tessellation or seams builds with **no wall at all**, because a
shell changes every volume in the ship — a test asking "did this style cut differently" would
otherwise be reading the wall and the cut added together. It is also six times faster.

**Cost.** Hollowing roughly doubles the bake: an argon class goes from about 0.6 s to 7.6 s, since
every part is now two tessellations, two seam passes and a subtraction. The author has said twice
that this need not run at warp speed.
