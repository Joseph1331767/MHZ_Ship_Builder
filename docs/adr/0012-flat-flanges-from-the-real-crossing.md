# 0012 — Flat flanges, from the real crossing

- **Date**: 2026-09-03
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. `seam_style` is still written only when it is not the default, and the default is
  still the flat family, so no saved document's canonical form moves.
- **Amends**: ADR 0009's `flat` seam style, retired in place; FOLLOWUPS F23, which asked this
  question, is answered by it.
- **Records**: FOLLOWUPS F24

## Context

ADR 0009's `flat` cut both solids on the plane through the **attach anchor**. On a flat host face
that plane IS the host's surface and the joint is exact. On a sphere, or at a box corner, it is
only the tangent there — and the exact meshes of ADR 0011 made that plainly visible:

> "somehow it cut the upper sphere way into the sphere, and short of the lower sphere. so the cuts
> arent happening at intersection."

The author then specified what it should be instead: classify which part is inside which by size;
find the plane through the extreme point of the actual intersection, normal along the parent's
radial vector; cut the larger solid there; flatten and if necessary extend the smaller one to meet
it. Two variants — **in-bumped** at the radially lowest crossing, **out-bumped** at the furthest
out, where the larger solid instead *gains* material from the smaller to reach the plane.

## Decision

**`core/mesh/mesh_flange.gd` — `class_name MeshFlange`**, and `flat` becomes four styles.

**The plane comes from where the surfaces actually cross.** Both meshes' edges are walked; any edge
that changes side of the other solid's field is bisected onto it; those crossing points are
projected onto the joint axis, and the plane goes through the extreme one. For two spheres the
crossing curve is a circle and already planar, so the plane lands on it — measured, 1.4136 against
an analytic 1.4132.

**Larger and smaller by VOLUME, not by the attach tree**, exactly as specified: a small part is
perfectly able to be the parent of a large one.

**Two independent choices, so four styles**, the author having asked for both:

| style | plane at | the larger solid |
|---|---|---|
| `flat_in` | deepest crossing | recessed only across the smaller one's cross-section |
| `slice_in` | deepest crossing | cut by the whole plane — a facet across the solid |
| `flat_out` | outermost crossing | gains the smaller one's material as a raised pad |
| `slice_out` | outermost crossing | cut by the plane *and* gains the pad |

`parent` and `child` are unchanged. `flat` is retired as a name; the string still LOADS, mapping to
`flat_in`, and since it was the default it was never written to a file anyway.

**The author's own reading, which is worth recording**: *"flat is equivalent to flat ended child
shapes inserted into parent shapes with child-indents-parent selection.. the redundancy is ok
however because this lets people quickly switch linkage manifolds without changing base shapes"*.
That is right, and it is why the overlap is a feature: on a flat host `flat_in` and `child` reach
the same shape by different routes, and either can be switched to without touching the parts.

## Consequences

**Measured**, whole-ship bake, every part closed:

| | faces | time |
|---|---|---|
| `helium` (5 parts), `flat_in` | 70 | 46 ms |
| `carbon` (9 parts), `flat_in` | 426 | 277 ms |
| `argon` (17 parts), `flat_in` | 846 | 594 ms |

The face counts falling is the joint working: a tube seated between two rooms is cut flush at both
ends, so it goes from 360 faces to **26** — twenty-four side quads and two caps — and the boxes are
untouched, because on a flat face the deepest crossing IS that face and there is nothing of the
host above it to remove.

**Two bugs found on the way, both mine, both in code I had just written.**

1. `_cap_id` took a `PackedVector3Array` and appended to it. Packed arrays are VALUE types — the
   trap this repo's own class docs warn about — so every append went to a copy.
2. Worse, it used a **spatial hash as an identity**. Hash collisions had been justified as harmless
   "because every lookup ends in an exact test", which is true of the weld and the T-junction probe
   and false here, where the key *is* the answer. A 24-point cap came back as 18 with six nodes
   fused, no ring could be chained, and **`clip_to_plane` had been silently falling back to the slow
   slab boolean on every call** — including in the timings reported for ADR 0011. Exact `Vector3i`
   keys now; helium's bake went from 216 ms to 27 ms once the direct path actually ran.

**Out-bump degrades on a many-branch hub, and does so safely.** It needs a union, and a union is the
only operation that grows a mesh. On `argon`, whose hub takes eight of them, the first union came
out closed at 101 faces and the second left 60 open edges — after which each union was fed a broken
mesh, reaching 11049 open edges and 73 seconds by the seventh. A union whose result is not closed is
now REFUSED and the host keeps what it had, which stops the compounding dead: `argon` completes in
24 s with every part closed, at the cost of seven stubs not added. The author had allowed for that
gap — *"if a thin unseen buffer of space is needed between modules thats fine"* — and it is a far
better answer than a hull with eleven thousand open edges. See FOLLOWUPS F24.

**The SDF still knows only the old three.** `ShipSdf.style_code()` maps anything it does not
recognise to its own flat, so `module_view` treats all four flat styles as the ADR 0009 tangent cut.
Nothing renders from that path any more — the exact mesh bake is what the exploded view draws — so
the divergence is currently cosmetic, and it is recorded rather than papered over.
