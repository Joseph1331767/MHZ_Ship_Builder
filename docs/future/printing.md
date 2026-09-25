# The fundamental grid is the smallest printer

Design note, not built. Recorded 2026-09-24 from the author, after two misreadings on the agent's
part were corrected. `docs/future/` is not CONTRACT and no code reads it (AGENTS §3).

## The design, in the author's words

> "our main job here is to make the grid cuts fundamental for the max size of smallest printer, and
> stride those cuts when forming larger parts, so 1x2, 2x2, 1x3, 2x3, 3x3, 1x9, etc chunk grids for
> larger printers so no new slicing ever has to happen. lets say the smallest printer max print area
> is .5mx.5mx.5m. then in game i can make printer size upgradable in .5 increments in any axial
> direction."

> "there may be pieces that end up way too small due to their relative shape and location as the
> slicing. so there should be some sort of size measurement where if a piece is too small, we analyze
> what it can attach to naturally while maintaining the size constraints, and which ever surface
> accepts it it can hitch a permeant ride with it."

> "we cant define flatness alone theres a size constraint as well" - a standard box face is already
> bigger than the printer, so a box cannot be six panels.

So:

1. **The fundamental cell IS the smallest printer's build volume** - 0.5 m cubed, say.
2. **Every piece is cut on that grid once.** Every chunk fits the smallest printer by construction.
3. **A bigger printer STRIDES the grid**: 1x2, 2x2, 2x3, 3x3, 1x9. No new slicing, ever.
4. **The in-game upgrade is a stride**, one 0.5 m step per axis, which is an integer per axis.
5. **Runt chunks hitch a ride** with a neighbour that will have them.

## This is right, and it is better than what is built

**It is ADR 0032's rule with the cell size pinned to a physical constant instead of a fraction.**
Today every piece is cut 4x4x4, so the cell size is a fraction of the PIECE: a big piece gets big
cells and a small piece tiny ones, and nothing guarantees any of them fits a printer. Under this
rule the cell size is fixed and the COUNT varies, so every chunk is printable by definition. That is
the property the manufacturing fiction actually needs.

**It keeps the no-re-bake property and makes it stronger.** A stride is an exact integer grouping of
the fundamental grid, so every printer upgrade is a regrouping of chunks that already exist - the
same trick ADR 0032 uses for the slicer, extended to a thing the player upgrades. The agent's earlier
worry that bed size would force re-bakes was wrong, and this is why.

**And it answers the panel question by dissolving it.** A wall is 0.2 m thick and a cell is 0.5 m, so
a chunk of a flat wall IS a plate - 0.5 x 0.5 x 0.2. There is no separate panel system to build: the
orthogonal grid, sized to the printer, is the panelisation. That also settles the author's objection
to flatness as a criterion - flatness never decides anything, size does, and a flat face too big for
the bed is cut by the same grid as everything else.

## What it costs, and the one thing that has to be designed around it

**The chunk count goes up by roughly forty times.** Measured on a carbon this session: 656 cells
today, cut in about 12 s. At a 0.5 m grid the count is driven by SURFACE, since these are hollow
shells - a chunk exists wherever the shell passes through a cell, so roughly `area / 0.25 m2`:

| part | area | chunks at 0.5 m |
|---|---|---|
| nucleus piece (x6) | 538 m2 | ~2150 each |
| pod (x4) | 992 m2 | ~3970 each |

That is order **30,000 chunks for one carbon**, against 656. Extrapolating the measured rate, cutting
and reading them all back as separate solids would run into minutes rather than seconds. (Extrapolated,
not measured - the slab passes do not scale linearly, and it would be measured properly before anyone
committed to it.)

**So the grid has to be a DEFINITION, not thirty thousand baked meshes.** Store the piece, the grid
origin and the cell size; materialise a chunk's mesh when something actually needs it - the explode
view showing one module, an assembly animation, a print job. The player never needs all of them as
separate solids at once, and the ones they do need are a handful at a time. This is the one real
engineering consequence, and it is a change of shape rather than a difficulty: the cut is already
deterministic, so a chunk can be produced from its index on demand.

## Runts, and the headroom they imply

A fixed grid clips slivers wherever the shell meets a cell boundary at a glancing angle, so the runt
rule is needed rather than optional. Merge a chunk under some threshold into the neighbour it shares
the largest face with.

**But a chunk that already fills the bed cannot adopt anything.** If the fundamental cell IS the bed,
a full cell is at 100% and has no room for a runt. Two ways out, and one has to be picked:

- **Make the fundamental cell a little under the bed** - 0.45 m in a 0.5 m printer, say - so every
  chunk carries about a third of its volume as headroom for adopting runts.
- **Let runts merge only into PARTIAL neighbours**, which on a hollow shell is most of them, and
  accept that a runt surrounded by full cells stays a runt.

**And striding interacts with it**: once a runt has been adopted, the grid is no longer a clean
lattice, so a 2x2 stride over an adopted chunk can exceed two cells' worth. Either the runt rule runs
AFTER striding, per printer size - cheap, since it is a regrouping - or the stride rule has to check
the merged extent.

## How it sits with what exists

- **The seam split (ADR 0036) stays above it.** That decides which NODE a piece belongs to, for lore
  and texturing; this grid decides how that piece is manufactured. Two levels, and they do not fight.
- **Per-node axes (ADR 0041) are already right** - a chunk is printed and fitted in its own chunk's
  orientation, and the grid should be axis-aligned to the node, not the world.
- **The background pass (ADR 0042) is where it would run**, and on-demand materialisation fits it
  exactly: the definition is instant, the meshes come when asked.
- **`FINE_CUTS` is the thing that changes** - today a fixed array of fractions, and it would become a
  cell size in metres with a count derived per piece.

## Room size stays as it is - decided 2026-09-24

The chunk counts above are premised on rooms as they are actually built, which is NOT
`ShipConfig.room_span_m`. That lever is only read when `OPT_ROOM_SPAN` is passed; a default prebuild
sizes its rooms from a volume budget instead, `template_volume_m3` (8000) divided by the node count:

| class | nodes | room as built | area | with an explicit span |
|---|---|---|---|---|
| hydrogen | 1 | 20.0 m | 2400 m2 | 3.0 m, 54 m2 |
| helium | 1 | 15.9 m | 1512 m2 | 3.0 m, 54 m2 |
| lithium | 2 | 12.6 m | 952 m2 | 3.0 m, 54 m2 |
| carbon | 5 | 9.283 m | 517 m2 | 3.0 m, 54 m2 |
| neon | 9 | 7.937 m | 378 m2 | 3.0 m, 54 m2 |

Raised with the author because it makes `room_span_m: 3.0` dead on every default build and gives a
hydrogen a 20 m room. **Their answer: leave it, it is working nicely.** So the big chunk counts are
the real ones, and on-demand materialisation stays a requirement rather than a precaution. Recorded
here so nobody re-opens it from the config alone.
