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

1. **The SURFACE half of a style is not yet distinguished in the geometry** — and, measured
   2026-09-25, only that half. Setting every joint of a lithium to each of the six styles in turn
   and baking gives **two distinct results, not six**:

   | styles | pieces | total volume | total area |
   |---|---|---|---|
   | `small_flat_insert`, `small_flat_cutoff`, `small_native` | 5 | 555.6307 m³ | 5617.2068 m² |
   | `big_flat_insert`, `big_flat_cutoff`, `big_native` | 5 | 554.9667 m³ | 5610.3840 m² |

   So **which solid indents which is honoured**; the three linkage surfaces are one surface. That
   corrects the older wording here, which said every style baked as the native one - the indent half
   has been working all along, and it is the `flat_insert` / `flat_cutoff` / `native` distinction
   that is the bulk of the work. RETIRED(2026-09-25): "Every style currently bakes as the native
   linkage surface".
2. **A style names the two solids by SIZE, and the author has confirmed that is what they want.**
   "naming by size can be one of the options in the list of options. so options of big indents
   small, and small indents big. just make the options approperate, some may be sub options idk"
   (2026-09-25). The menu already reads exactly that way and has since ADR 0013 - two headed groups,
   SMALL INDENTS BIG and BIG INDENTS SMALL, each with FLAT INSERTED / FLAT CUTOFF / NATIVE INSERTED
   beneath it - so the naming question recorded below is **settled, and no ADR amendment is needed**.
   RETIRED(2026-09-25): the paragraph that follows, which treated naming-by-chunk as the thing to
   build and ADR 0013 as the obstacle.

   A style names the two solids by SIZE, not by which chunk. `big_native` means "the larger one
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


## Built since: the walls are a LAYER (ADR 0046, 2026-09-25)

> "walls should be isolated from the shape its actually apart of, such that when walls layer is
> removed you see an open room"

**Step 1 is built.** Every baked piece names its wall faces `ShipCsgBake.SURFACE_WALL`, and
`ShipView3D.set_walls_hidden()` drops the layer - INTERIOR mode drops it by default. A walled seam
authors no plate, so the wall is the INDENTED part's own cavity face standing where its neighbour's
grown body pushed in; naming it is what makes it droppable. Measured on a carbon: 0.00 m2 with every
seam open, 493.25 m2 with all fifteen sealed.

**Step 2 is not, and it is the one with a cost.** Lifting walls into their own solids - so a panel
is printed on its own - makes each chunk **no longer watertight by itself**; watertightness becomes
a property of the assembly. Raised with the author and open.

Note that this is orthogonal to the three modes above: the layer is about what is DRAWN and
eventually what is PRINTED, the modes are about what SHAPE the seam takes.
