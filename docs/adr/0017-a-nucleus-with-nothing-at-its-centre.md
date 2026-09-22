# 0017 — A nucleus with nothing at its centre, and an open seam that costs nothing

- **Date**: 2026-09-04
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Template CONTENT moves; nothing about how a document is read or hashed does.
- **Amends**: ADR 0014 (the nucleus arrangement), ADR 0016 (how an OPEN seam is built)
- **Records**: FOLLOWUPS F29

## Context

> "on the carbon class ship, (which has 5 protons around a central one which is wrong, the central
> one should be the singular top, and the 4 rim and lower added .. basically the valance electron
> count should be half or full resonant to the structure of protons at all times.) - big bug, i
> click the 6 protons and make them an open room .. when i explode it breaks apart and reveals that
> the central completely burried one still exists and thats incorrect as the only thisg that should
> exist for each module is their surface thickness only, no internal parts.. also most of them
> arent shelled out properly, i see one that is, the others just appear to have been walled along
> parent surface."

Three reports, and the first two turn out to be the same defect seen from two sides.

**The nucleus was a hub.** ADR 0014 laid the fused bodies out on the arrangement holding
`count - 1` and put the remaining body at the CENTRE of it. A carbon class was therefore five
protons around a sixth that nothing could see — and, worse, that body is host to five seams, so the
bake carved it down: measured, its hull went from 71.9 m³ walled to **5.9 m³** once the six were
made one room, a handful of slivers where its neighbours happened not to reach. That is the module
the author found in the exploded view.

**An open seam left one plate of two.** ADR 0016 built the wall between two cavities and bored it
out. On a fused pair only one of the two is ever cut — the flange leaves the other alone — so only
that one had a plate to find. The other kept its own full wall standing where its neighbour meets
it: two rooms still a hull apart, which is what "walled along parent surface" looks like.

## Decision

**The nucleus sits ON an arrangement; nothing sits at its centre.** The arrangement holding
`count` slots is chosen, the ROOT takes the slot nearest straight up, and every other slot becomes a
direction measured FROM the root's slot. A carbon class is six bodies on an octahedron: the root on
top, four rim at 45° down and out, one straight below — *"the central one should be the singular
top, and the 4 rim and lower added."* The body COUNT is unchanged; only where they point moves.

**Pods take slots of that same arrangement** — *"the valance electron count should be half or full
resonant to the structure of protons at all times"* — most perpendicular to the root's slot first,
which puts them around the waist. Carbon hangs its four valence pods on the four rim slots of the
octahedron its six protons sit on; neon fills all eight slots of its cube.

**A pod is built on the proton whose slot it shares**, and its tunnel continues straight out from
there. Hanging every pod off the root cannot work once the nucleus fills its own arrangement: the
pod's slot is occupied by a proton, so the tunnel would set off through it. Measured before this, a
rim proton had eaten the very face its own pod's tunnel was seated on, and that tunnel joint then
cut nothing at all.

**An OPEN seam is the seam the interior is NOT cut at.** Everywhere else the cavity is pushed back
by a wall so the module comes out sealed; at an open seam it is left running at full extent through
where the seam face would be. Both interiors do it, so neither grows a plate. **And the neighbour's
interior is taken out of this module's outer** (`_pierce`), which pierces the wall of whichever
module the seam did not cut. The two together are the whole of it.

**No module's hull may stand inside another module's room.** That is what the pierce enforces, and
it is *"the only thisg that should exist for each module is their surface thickness only, no
internal parts."* A module lying entirely inside a neighbour's room comes out empty and stops being
drawn, which is the right end for a module the cluster has swallowed.

## Consequences

**Measured.** A carbon class with its six protons made one room: no module below 43 m³ of hull
(the root, which carries five openings), the rim bodies at 86.7 and the pods at 99.0, and **every
module closed**. Helium's pair loses a full 0.20 m plate from BOTH sides — 294.8 → 246.9 and
220.1 → 172.2 — where ADR 0016 opened only one. Across all 22 shipped classes: 0 unmerged joints,
0 validator issues, 0 open parts, and the 8000 m³ volume budget still holds to within 24 m³.

**The bake got FASTER, by two orders of magnitude on the case that mattered.** ADR 0016's bore put
a thin passage against a finished SHELL — two nearly parallel surfaces a wall apart — and the BSP
split until the budget ran out, so `_cut` discarded the result and returned the shell it was given.
A carbon class whose protons were one room spent **52 seconds** there and opened nothing. Not making
the cut is exact and costs nothing: the same class is now **578 ms**, marginally faster than the
same ship walled, because a skipped cut is a cut not made. Argon shells in 3.0 s where ADR 0015
measured 7.6 s, and hollows 24 parts of 24 rather than 20.

**Two wrong shapes for the passage, both ruled out by measurement**, on top of the three ADR 0016
already records. A slab about the true seam plane — the flange knows where it cut, and it was
threaded through for this — is the right REGION and made no difference: 47 s. Boring the outer
solid rather than the shell, which is the same set by algebra and a far simpler operand, was 62 s.
The cost was never the operand; it was making the cut at all.

**`MeshFlange._footprint_cutter` gained a `drop`**, so the interior pass stands its prism on the
larger solid's side of the seam. Its own docstring already said "BOTH SIDES RETREAT BY THE INSET,
in opposite directions" and the insert path made the larger one ADVANCE. This is inert on every
shipped family — measured, all 26 seams of a carbon bake find no cap at all, because a flat host
face IS the deepest crossing and there is nothing to flange (which `test_a_flange_leaves_the_host_
alone_where_a_slice_cuts_it` has always asserted). It bites on a curved host.

**Two tests had baked in "the tunnel stands on the root".** They read `solids[doc.root]` while
styling the tunnel's joint, which was the other half of that seam until a pod moved onto its own
proton. They now ask the document what a part stands on. A test that assumes a topology is a test
that goes quiet when the topology moves.

**Explode's relaxation gained a chain rule.** Pushing the module that is already further out
separates two siblings, but not a pair on the same chain: everything hanging off a module travels
with it, so only the DESCENDANT can open that gap. A pod's tunnel and the proton it grows out of
are exactly such a pair, and the sibling rule alone left four of them overlapped on a carbon class.
