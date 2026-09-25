# Panels and printing: two decompositions, not one

Design note, not built. Recorded 2026-09-24 from the author, corrected the same day after two
misreadings on the agent's part. `docs/future/` is not CONTRACT and no code reads it (AGENTS §3).

## What the author actually asked for

Two separate things, and the first exchange ran them together.

**A printer-size rule:**

> "any surface primatave thats too big gets bisected untill all pieces fall under the 3d printer
> size requirements ... (different 3d printers will have different size capabilities in the future)"

**And panels, which is the real idea:**

> "i am perfectly fine with our orthognal dicing, just thought the low poly surfaces looked like they
> could be individual panels that the player could see assembled, one mesh per primative chunk
> basically) with some min and max size constraints, and some grouping and halfing type stuff."

## Two things the agent got wrong, corrected

**"Combine them in future when print beds are large enough" means ASSEMBLY, not mesh merging.** The
author was describing robots putting more panels together per trip, not a geometry operation that
welds baked pieces back into one. The objection raised against merging - that it would mean
re-welding caps and proving watertightness - was answering a proposal nobody made.

**There is no re-bake in this.** The agent argued that a bed size change would move the cut positions
and so force one. It does not: the pieces are cut ONCE, at the smallest printer's size, and are
separate from then on. A larger bed changes how many panels a robot carries, not where anything was
cut. Explode and assemble keep doing what they do - moving parts around. The tension claimed with
ADR 0032's fundamental cells was therefore imaginary as well.

## What stands from the first pass

**Cutting at existing mesh lines is not a speed win.** A boolean costs what the mesh's complexity
costs, not what the plane lands on, and a plane lying exactly ON existing geometry is the harder case
for an exact engine rather than the easier one (ADR 0039 had to place vertices on a plane
deliberately to get a coplanar band divided). This matters only if speed was the reason; it is not
an argument against panels, which are wanted for how they LOOK.

**`ceil(extent / bed)` beats repeated halving**, if a bed rule is ever built. Bisecting until it fits
gives powers of two, so a piece 1.05x the bed becomes two halves each using about half the bed.

**"Decimate" means reducing polygon count.** The operation described is splitting. Worth keeping the
words apart so nobody later builds a simplifier when a splitter was meant.

## Panels: one mesh per face of a chunk

The author's clarification - "flats" means faces too LARGE, not flats in general, and the ships are
low-poly so every primitive has them.

**This fits the codebase better than it might look.** `ShipCsgBake._tidy` already merges a piece's
coplanar triangles back into n-gons, so "one mesh per primitive face" is largely computed already: a
cube chunk comes out as a handful of big faces, and the drawn mesh already names them `exterior`,
`interior` and `cut` (`_grouped`). A panel run would be reading something that exists rather than
deriving it fresh.

**It is a SURFACE decomposition, and the cells are a VOLUME one.** They answer different questions
and should both exist:

| | question it answers | what it gives |
|---|---|---|
| cells (ADR 0032/0041) | how does this solid break into printable lumps | 4x4x4 chunks per piece |
| panels | how is this hull plated | one plate per face |

For "robots attach and build it", panels are what construction actually looks like - plates going on
a frame - and the author has said the seam work was for that reason and for texturing. Cells stay
for manufacturing; the orthogonal dicing is explicitly kept.

### The three questions that decide whether it is tractable

1. **Exterior only, or the whole shell?** A skin of plates over a frame is the readable version and
   the cheap one: take the `exterior` surface's n-gons and nothing else. Plating the cavity and the
   cut faces as well doubles the work and is mostly invisible, since the interior is only seen
   through a hatch.

2. **What happens on a curved family?** This is the real risk. A cube chunk has about six exterior
   faces; a `sphere_pod` piece measured in this session has **2254 to 3150 faces**. One panel per
   face is six plates on a box and three thousand on a sphere, which is not a decomposition, it is
   confetti. So the grouping the author mentions is not a refinement for curved families - it is the
   whole job. The rule wants to be "grow a panel over neighbouring faces while it stays within a
   flatness tolerance, and stop at the max size", which turns a sphere into a few dozen plates and
   leaves a box at six.

3. **Who owns the corner?** A face has no thickness; a panel needs one, and the obvious thickness is
   the hull wall. Two panels meeting at an edge both want the material in the corner, so the rule has
   to say which gets it - a mitre, or one square and one cut to fit. That is the same shape of
   question as the seam wall (`docs/future/walls.md`: wall ab / wall ba / wall flat), and the same
   answer would serve both.

### How it would be built, if it is

- **As a view computed from the bake**, like the cells: nothing until it is asked for, and it can
  ride the background pass that ADR 0042 put the dicing on.
- **Min and max as the author said**: over the max, split the panel; under the min, merge it into the
  neighbour it is most nearly coplanar with. Both are cheap on n-gons.
- **Per-node axes already suit it** (ADR 0041) - a panel is printed and fitted in its chunk's own
  orientation.
- **Nothing in `core/` needs to change.** This is a reading of a baked piece, and baked pieces are a
  harness concern.
