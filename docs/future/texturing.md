# Texturing — future notes

**Status:** not built. Captured 2026-09-21 for the procedural texturing phase. Not CONTRACT; see
[README](README.md) for how a note becomes a decision.

---

## 1. Seam bands

> "where primitive shape nodes join, we want a texturing band that follows the seam. we will
> dynamically add more and more styles and patterns throughout development so the seam type can be
> chosen by player in the builder later on in the texturing phase. rivets, bolts, welds, hidden
> fastener ribbons, etc. this will allow us to texture the surface of the primitive shape
> contribution later easier as it has an expected curve/surface topology and a known shape between
> its seams." — the author, 2026-09-21

Wherever two primitives join, the exterior has a **join line**: the curve where one part's surface
meets the other's. The bake already cuts it exactly (the engine's Manifold booleans, ADR 0020), and
`ShipSeams` already knows every join as a host/child pair with a style (`SEAM_HOST`, `SEAM_CHILD`,
`SEAM_STYLE`).

A **seam band** is a strip of surface running the whole length of that curve, a set width either
side of it, textured with a **band style** the player picks per seam in the builder:

- rivets, bolts, welds, hidden fastener ribbons to start;
- more styles and patterns added throughout development, as data.

A band has its own coordinates: **u** = arc length along the join curve, **v** = signed distance
across it (host side negative, child side positive). A style is a pattern in (u, v):

| style | in band coordinates |
|---|---|
| rivets | heads instanced at a pitch along u, in one or more rows at fixed v |
| bolts | as rivets, larger, wider pitch, optionally with a washer ring |
| weld | a bead centred on v = 0, rippled along u |
| hidden fastener ribbon | a flush strip across the full width, fasteners implied rather than shown |

## 2. Why: every panel has a known shape

Once the joins are covered by bands, what is left of each primitive between its seams is a
**panel** whose surface type is known in advance, because it came from a primitive family:

| family surface | natural coordinates |
|---|---|
| sphere cap | latitude / longitude |
| cylinder or tube barrel | angle x height |
| box face | planar, per face |
| torus section | two angles |

So each panel can be textured in **its own primitive's native coordinates**: an expected
curve/surface topology rather than an arbitrary mesh. The discontinuity where two parts'
coordinates meet falls **under the band**, where the band's pattern covers it, the way panel lines
and trim sheets hide UV seams in hard-surface art. A panel's boundary is its seams, known exactly,
so edge wear, panel-line insets and masks can come from distance-to-seam.

## 3. What this asks of the phases before it (do not preclude)

Links to the Phase One Hull Review recommendations 5, 6 and 7.

- **Face provenance through the bake (rec 7).** Today a baked face carries only its surface kind:
  `ShipCsgBake.SURFACE_EXTERIOR` / `SURFACE_INTERIOR` / `SURFACE_CUT`. Texturing needs, per exterior
  face, the **part it came from**. That also gives the band its curve for free: the join line is
  exactly the boundary between two parts' exterior faces.
- **A place on the seam for the choice (rec 5).** `ShipJoint` already stores per-seam `mode`,
  `seam_style` and `hatch_*`. A band choice (style id + params) sits beside them. Reserve it in the
  schema when rec 5 lands; write it only when not default, so no existing hash moves (the pattern
  `seam_style` set, F20).
- **Styles as a data pack.** A catalogue such as `data/finishes/seam_bands.json` (name open) with a
  schema, every entry carrying a real `description` (AGENTS §10b). Adding a style must never touch
  `core/`.
- **Every join gets a band, not only walled ones.** An `open` seam (one room) and a `hatched` seam
  still show a join line on the exterior. The band follows the **geometric join**, not the room
  partition. A hatch collar (ADR 0029) is its own ring: the band stops at it or wraps it.
- **Leash the warps (rec 6).** Twist, rib and scallop bend a primitive away from its native
  coordinates. Either the panel's coordinates are warped the same way (the warp is known; it is
  `ResolvedShape`'s op order, SPEC §4) or those ranges stay narrow.

## 4. Decided (the author, 2026-09-21)

- **Width is a range, and 0 is valid** — 0 means no band on that seam. The range should be
  appropriate to the style (a rivet row wants a narrower band than a weld plate); exact bounds are
  set when the styles pack is written.
- **No mesh change, for now.** A band is surface only: texture and normals. Nothing it does enters
  the bake or the truth layer.
- **A band is an edge function switched on or off per mesh chunk.** Each baked piece (one per
  original primitive) either runs the joining-edge function along its seams or does not.
- **Mirror follows the component path.** A mirrored seam takes its source's band the way an
  instance follows its definition — one choice, every copy. (Symmetry itself is being reworked:
  see [symmetry.md](symmetry.md).)
- **Textures are generated outside this repo.** The author's own SDK generates them with AI, maps
  them through the author's pipeline to specific surfaces, and caches them on the author's server
  for reuse. Out of scope here. What this builder owes that pipeline is geometry it can map
  reliably: per-primitive chunks with known panel shapes, face provenance, and the seam bands'
  (u, v) coordinates.

## 5. Keep the chunks: the bake already does

> "i was thinking of keeping it separate mesh chunks of its original primitive shapes, you know
> instead of union.. it will help with later dynamics anyway for texturing and component copy
> etc." — the author, 2026-09-21

This is how the bake already works, and it must stay that way. A room's shell is built whole and
then **cut back into one closed piece per original primitive** (ADR 0021). Each piece carries its
exterior, interior and cut faces as separate named surfaces, and the interior is drawn as its own
mesh (ADR 0028). The fused whole-room shell exists only for the `ROOMS: WHOLE` view toggle. Any
future optimisation of the bake must keep the per-primitive pieces as the output.

## 6. Still open

- **Crowded joins:** where several parts meet close together (a hub like `argon`'s eight branches),
  bands overlap. Priority, merge, or a hub plate?
- **Tight curves:** u by arc length handles a non-planar join curve; check that rivet pitch still
  reads right where the curve is tight.
- **Palette:** the builder quantizes everything to 16 colours (SPEC §11). The in-game textures come
  from the author's pipeline (section 4), so this is now only about how the builder previews them.
