# 0018 — An open seam is resolved natively, and a body hangs at its slot's height

- **Date**: 2026-09-04
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after.
- **Amends**: ADR 0017 (how the nucleus hangs, how an open seam is built)
- **Records**: FOLLOWUPS F30

## Context

> "the only correct one was the parent node. its fully hollowed out, and cut at its intersection
> points. the other 5 are not cut at intersection lines they are cut flat. incorrect when they are
> all linked as one central room.. also the other 5 also have very shalow indents in them and is
> not a prooper uniforme thickness shell. - also acrost the board it appears the thickness is to
> much .. also in the carbon design the 4 rim protons are not vertically centered between the top
> and bottom proton. also the extending electrons are all pointed 45 degrees downward instead of
> some symmetric configuration."

Five observations. Two are the layout, three are the seam, and the thickness one is answered with a
number.

**The layout.** A child sits on the point where the ray from its parent's centre strikes the
parent's surface, sinks along the surface NORMAL there, and takes that normal as its own +Y. ADR
0017 hung the octahedron's rim slots straight from the top vertex — 45° down — and on a box root
that ray strikes an **edge**, where the normal is diagonal. So the rim protons tilted 45°, their
pods followed, and every fused body sits the same distance from the root, so a 45° rim could never
be halfway to the bottom either.

**The seam.** ADR 0017 opened a seam by skipping the interior cut and subtracting each module's
room from the other's outer. On a fused pair only one of the two is ever cut by the flange — the
child, at a plane — so the root came out right (it is the indenter, and losing five rooms is its
correct cut) and its five neighbours came out cut flat, with a shallow dent where the root's room
reached past the plane.

## Decision

**A body takes its height from its slot.** `_hang_direction()` keeps the slot's bearing and takes
the fall from where the slot sits between the top of the arrangement and its bottom: a rim slot at
the equator is halfway down, so it hangs at the direction whose fall is half its length — **30°
below level**. Measured: the rim sits **48%** of the way from top to bottom (50% is centred), the
rim protons mount level on the root's side faces, and every valence pod reaches straight out
along ±x / ±z. A slot at the very bottom AND off to one side — a cube's far corners — has no
direction that is right at one seating depth, and keeps its plain bearing.

**An open seam is resolved natively, and asymmetrically.** Neither surface is cut at it in
`_apply_seams` — the styles there build a mating face, and an open seam has none to mate. Instead
`_pierce()` resolves it off the bodies as built: the **indented** module loses the indenter's whole
**body**, which punches a hole through its skin bounded by the true crossing curve; the **indenter**
loses what lies inside the indented module's **room**, so its walls run in through that hole, plug
it for one skin's depth, and stop at the far inner surface. That asymmetry is what makes the join
exact with no gap and no double hull. Which side indents is the style's own axis (ADR 0013), with a
tie going to the child.

**Every overlapping pair in a room is resolved, not only the tree's edges.** The open seams are
first joined into rooms (union-find), then every pair within a room whose bodies share a bounding
box is resolved the same way. A cluster fused around one root has far more neighbours than the
attach tree has edges: each of carbon's rim protons overlaps the two beside it and the one below.

**One tie rule, with a tolerance.** `MeshFlange.first_is_larger()` decides "which is larger" for
the flange, the native branch and the pierce alike, to within `TIE_REL = 1e-4`. Six protons of one
class are one solid under six transforms and differ in the last bits; a plain `>=` sent some of the
root's children to one side of the tie and some to the other, and the root came out at 247 m³ —
two and a half sealed shells' worth — with one child at 528.

**The wall stays 0.20 m.** A carbon proton is 800 m³, a **9.28 m** cube; the wall is **2.2%** of
its side. What reads as thick in the exploded view is the cut rims, each of which shows the wall's
full 0.20 m face — and, until this ADR, the flat plates and shallow dents.

## Consequences

**Measured, carbon with its six protons one room.** Root **38.1 m³** — a shell with five passages,
nothing standing in anyone's room. Rim protons 57.6 m³ where their sibling cuts took, 56.8 where
they were refused (see below); bottom 37.1. Every module closed. Bake **640 ms**.

**Two sibling cuts of the six are refused, and the reason is precise.** Six protons of one size,
each centred on a face of another, put faces on EXACTLY the same planes everywhere — side faces,
top and bottom faces, and the faces earlier cuts left behind. A cutter whose faces lie in the
planes of the solid it cuts goes down the BSP's coplanar path, and that path is not reliable here:
in isolation every cut comes out right (measured, all six orderings and clearances on the root/
bottom and root/rim pairs), but once a target already carries faces from a previous cut on the same
planes, the guard refuses the next one and the seam quietly stays shut. Two rim protons therefore
still pass 30 m³ of skin through the room beside them.

**Offsetting the cutters does not escape it; it is worse.** Both a 1 mm and a 1 cm clearance —
body grown, room shrunk — put the cutter's faces near-coplanar with the target's, and the BSP split
into sliver cascades: the same bake did not finish in 400 s. The other direction (body shrunk)
leaves a millimetre sliver of skin around the hole that the merge welds into an open edge.
`OPEN_SEAM_CLEARANCE_M` is therefore held at **0** — exact coincidence is the one configuration the
coplanar path handles most of the time — and kept as the knob, with that history at its declaration.

**Robust coplanar handling in `MeshCsg` is the next piece of work**, and it is now the ONLY thing
between this and a nucleus that comes out entirely right. It is the same class of defect as the
spatial-hash identity (ADR 0011) and the 32-bit epsilon (ADR 0011): a geometric predicate that is
usually right.

**The intrusion metric can lie about a heavily carved shell.** `MeshCsg.intersect` returned 252 m³
for a 37 m³ shell with zero open edges — more than the shell itself. The probe now flags that
rather than reporting it; the shell's own volume and closure are the numbers to trust.

**Bake cost is unchanged in the large.** Carbon open 640 ms (walled 448); helium 54; lithium 183.
