# Dicing for the printer, not for a grid

Design note, not built. Recorded 2026-09-24 from the author, so the shape of it is on paper before
anyone starts. `docs/future/` is not CONTRACT and no code reads it (AGENTS §3).

## The author's words

> "would it be faster to slice at existing mesh liness? so long as huge flat surfaces still slice?
> so any surface primitave thats too big gets bisected untill all pieces fall under the 3d printer
> size requirements and double or multi mesh faces can be joined when 3d printer bed is increased
> past that threshold? ... (different 3d printers will have different size capabilities in the
> future) so this may be a good thing: slice all poly surfaces seperate >> combine them in future
> when print beds are large enough to handle 2+ pieces >> ensure flats or polys that are too large
> (larger then biggest size smallest printer handles) then it needs to be bisected"

Asked as "does this make sense?", not as a directive. Mostly yes. Three things would change.

## What is right about it

**Cut because a piece does not fit, not because a grid says so.** Today every piece is cut into 64
fundamental cells (4x4x4, ADR 0032) whether it needs them or not - a carbon comes to 656 cells. Under
a bed rule, a piece that already fits the bed takes **no cuts at all**, which is most parts on most
ships. That is the real saving, and it is large.

**Recursive splitting against a build volume is how the trade actually does it.** Every
print-preparation tool works this way. It is simple, deterministic, and gives the fewest pieces.

**A bed size is a real constraint that will change**, and designing for it now costs nothing.

## Where the speed actually comes from - not from the mesh lines

Cutting along an existing edge loop does **not** make a boolean cheaper. The cost is in the mesh's
complexity, not in where the plane lands; the engine evaluates the same intersection either way. If
anything a plane that lies exactly ON existing geometry is the HARDER case for an exact engine, not
the easier one - coincident faces are the classic degeneracy, and ADR 0039 had to put vertices on a
plane deliberately to get a boolean to divide a coplanar band the way we wanted.

So: **the saving is in cutting less often, not in cutting somewhere cleverer.** The bed rule gets
that; the mesh-line part does not add to it.

**But cutting at a flat region is still worth preferring, for a different reason.** A cut that lands
on a flat face leaves two flat mating surfaces: better bed adhesion for the print, and a larger
bonded area for the robots putting it together. A cut through a curved region leaves two curved
mating faces that touch along less of themselves. So "prefer a flat" belongs in the rule as a
HEURISTIC FOR WHERE, once the bed has decided THAT.

## The three changes

1. **`ceil(extent / bed)` equal slabs, not repeated halving.** Bisecting until it fits gives powers
   of two: a piece 1.05x the bed becomes two halves each using about half the bed. Dividing the
   offending axis into `ceil(extent / bed)` equal slabs is the same amount of code and packs far
   better - that same piece stays two pieces, but each fills the bed.

2. **Do not combine pieces back; make the bed an INPUT.** Merging baked pieces means re-welding
   their caps and proving the result is still watertight - a whole second construction to maintain,
   and a new way to produce a non-manifold solid, which this project has spent real time on already
   (ADR 0037). If the cut is a deterministic function of (piece, bed size), then "a bigger bed" is
   just a different argument that produces fewer, larger pieces directly. Nothing to undo.

3. **"Decimate" is the wrong word for it.** Decimation means REDUCING POLYGON COUNT - simplifying a
   mesh. What is being described is splitting, or subdivision. Worth keeping straight so nobody
   later writes a decimator when they meant a splitter.

## The one thing that has to be decided with it

**It breaks the fundamental-cells trick, and that is a real cost.** ADR 0032 cuts a fixed 4x4x4 so
that every slicing the player picks is a REGROUPING of cells that already exist - which is why no
slicer setting ever re-bakes. Bed-driven cuts cannot be expressed that way in general: a 2.3 m bed
does not land on quarters of a piece's extent, so changing the bed changes where the cuts are.

That is probably fine - a bed size is a manufacturing constant, not a view toggle, and it will change
rarely. But it makes bed size a RE-BAKE trigger, so it belongs behind the button that lights when
stale, never on every edit (ADR 0028, the author's standing rule).

## How it sits with what exists

- **The seam split (ADR 0036) is a different subdivision and should stay separate.** That one is
  design and lore: "each ship part in game lore gets 3d printed individually and robots attach and
  build it". Printer dicing is manufacturing, underneath it. A piece comes from the seam split; the
  bed rule then decides whether that piece needs breaking further.
- **Per-node axes (ADR 0041) are already the right frame for printing** - a chunk is printed in its
  own orientation, so its own axes are the ones the bed cares about.
- **The capping machinery already exists.** Cutting further and closing the result is largely solved.
- **The background pass (ADR 0042) is where this would run**, and it would usually run faster than
  what it replaces, because most pieces would need no cut at all.
