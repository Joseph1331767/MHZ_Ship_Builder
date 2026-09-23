# Walls between chunks — three modes, with the hatch on top

Design note, not built. Recorded 2026-09-22 from the author, so the shape of it is on paper before
anyone starts. `docs/future/` is not CONTRACT and no code reads it (AGENTS §3).

## The author's words

> "we will be handling walls via 3 modes (chunk a stays solid chunk b cuts to fit = wall ab, chunk b
> stays solid, and a is cut to fit it = wall ba, and lastly a and b cut and a solid straight wall is
> made between them = wall flat) ... also a hatch should be layered ontop of the wall choice."

So, for a pair of chunks that meet:

| mode | what happens |
|---|---|
| **wall ab** | A keeps its own surface; B is cut back to fit against it |
| **wall ba** | B keeps its own surface; A is cut back to fit against it |
| **wall flat** | both are cut, and one straight wall is built between them |

And the hatch is a LAYER over whichever of those three is chosen — not a fourth mode. A wall with a
hatch is still that wall; the hatch is a hole through it with its hardware.

## Most of this vocabulary already exists

`ShipJoint` separates two things already, which is exactly the "layered on top" the author asks for:

- **`mode`** — what CLOSES the seam: `open` (one room, no wall), `doorway`, `hatched`, `sealed`.
- **`seam_style`** — what SHAPE the seam is: `small_native`, `big_native`, and four flat variants
  (`small_flat_insert`, `small_flat_cutoff`, `big_flat_insert`, `big_flat_cutoff`).

`ShipJoint.indent_of(style)` already answers "which of the two indents the other". So the three
modes map onto the styles like this:

- **wall ab / wall ba** → the two NATIVE styles. One solid keeps its surface, the other is cut to it.
- **wall flat** → the FLAT styles, a plate between the two.

## What is missing, precisely

1. **The styles are not yet distinguished in the geometry.** Every style currently bakes as the
   native linkage surface — recorded as a known limit under FOLLOWUPS F32/F33, "flat and native
   styles are still one surface". This is the bulk of the work.
2. **A style names the two solids by SIZE, not by which chunk.** `big_native` means "the larger one
   keeps its surface", not "this one does". ADR 0013 chose that deliberately, replacing a naming by
   the attach tree (parent/child) which broke when the tree said one thing and the geometry another.
   But the author's `wall ab` / `wall ba` names a CHUNK, and for two chunks of equal size - which is
   every fused nucleus body - size cannot tell them apart: `MeshFlange.first_is_larger` calls it a
   tie and hands it to the child by convention. **Naming the winner needs a way to say which chunk,
   not which size.** That is the one real addition, and it needs an ADR because it amends ADR 0013.
3. **A sibling seam has no "parent" to fall back on** either (ADR 0034): two fused bodies stand side
   by side. Whatever names the winner has to work for a pair with no tree relation at all.

## What it does NOT touch

The CAP (ADR 0036) is a different thing and is already built: it closes each piece at the seam so
that every printed chunk is its own solid and the chunks fit back together. Whichever wall mode a
pair carries, each side still gets capped - the cap follows whatever surface the wall leaves behind.
The author's phrase for the two together: the walls "get capped and closed individually to fit
perfectly back together but be seperate".
