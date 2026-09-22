# 0032 — The ship lives in its fundamental cells; every setting only moves them

- **Date**: 2026-09-21
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Nothing a document holds changed; `ShipSeams.explode_offsets` gains an optional
  argument.
- **Amends**: ADR 0031 (the slicer: per-setting engine cuts and APPLY SLICES are retired), ADR
  0030 (what the extras make)
- **Records**: FOLLOWUPS F44

## Context

> "no the animation doesnt work, it is like a slow pop in.. the mesh is already built, no reason it
> cant come back together. - also i noticed it bakes when i change a setting. this is incorrect.
> all nodes should be both bisected, and trisected leaving 4 total chunks after both bi and tri are
> dissected, in all orthogonal directions, including each node cluster chunks splicing.. and the
> ship should exist as all of those separate tiny mesh pieces.. so animating them apart or together,
> or changing a setting is simply relocating the positions of those fundamental pieces."
>
> "i dont care if the seams are shown in wireframe mode.. it reads correctly as 'these are my 3d
> pieces joined together' vibe" — the author, 2026-09-21.

ADR 0031 made the engine cut each piece to the slicer's settings, so every slicer change was a bake
behind APPLY. There was no animation: the exploded view built one module per frame, a queue left over
from when every module was a slow field bake, and that read as a pop-in.

## Decision

**Every piece is cut once into its fundamental cells.** Each piece, cluster chunks included, and each
room shown whole, is cut along all three axes of its own frame (Y the placement normal, ADR 0031) at
**1/3, 1/2 and 2/3** of its original body's extent (`ShipCsgBake.FINE_CUTS`). That gives four slabs
an axis and up to 64 cells a piece; a cell wholly inside the cavity is dropped. The extras depend on
no setting, so no setting ever bakes.

**Every slicer setting is a grouping of those cells** (`ShipExplodeView.GROUP_SIGN`). BISECT groups
the slabs as {0, 1 | 2, 3}, TRISECT as {0 | 1, 2 | 3}, and OFF keeps them all together. Each cell is
its own drawn piece, and a setting, a gap or the animation only moves it. The internal seams show in
the wireframe, which the author asked for: the ship reads as its pieces joined together.

**The explode is animated, in three stages.** An amount runs from 0 (assembled) to 1 (as the settings
say):
- **Stage 1**, the first third: modules part from modules. Every chunk held to another member of its
  room rides its host (`ShipSeams.explode_offsets(..., still)`), so a room leaves as one body.
- **Stage 2**, the second third: the chunks of each room separate at their seams.
- **Stage 3**, the last third: the slices part.

The run takes `EXPLODE_S` (2.4 s) divided by the player's SPEED. POSITION scrubs the amount and
follows the animation. EXPLODE builds every cell in one pass, where the pieces stand, then plays the
amount to 1. ASSEMBLE (`ShipExplodeView.collapse`) plays it back to 0, then lands on the whole baked
pieces. The camera frames the fully exploded bounds from the start, so it pulls back while the pieces
travel.

**Cells are read back welded, not merged into n-gons.** Each cell's wireframe comes from its feature
edges (`WIRE_FEATURE_DEG`, 10°): outlines, cuts, box corners and lathe rings stay, and the flat
triangulation diagonals go.

## Consequences

**Measured on the template carbon of spheres.** Fourteen pieces become 656 cells, plus 57 for the
nucleus shown whole, and every piece's cells sum to it exactly (worst error 0.0000). The fine-grid
extras take **9.6 s**, the same as the two-halves extras they replace (9.7 s). The engine's three
slicing passes took about 4 s; the n-gon merge on 713 read-backs had been 30.7 s of a 38 s first cut,
which is why cells are not merged. Building every cell's nodes took 474 ms. EXPLODE, from the press to
fully out, took 14 s the first time (the cut, the build, the 2.4 s run); after that, every setting,
POSITION and ASSEMBLE is a move. The windowed explode check drives:
- a slicer change, a POSITION scrub and wider gaps, each moving the pieces with no bake;
- separation off, putting every module back on its seam;
- ASSEMBLE, playing backwards and landing on the 14 whole pieces.

gdUnit4 309/309.

**Retired from ADR 0031**: the slicing argument to `bake_extras`, `EXTRAS_SLICING`, `slicing_key`,
`DEFAULT_SLICING`, `MAX_CUTS`, the `chunk*` report keys, APPLY SLICES and the panel's staleness, and
`ShipExplodeSettings.slicing()`. `ShipExplodeSettings.mode_for()` answers per axis instead.

**Known costs.** About 1,100 mesh nodes for a carbon, plus a wire node and a pick box for each cell;
cells pick by their boxes. The whole-room cells double a room's share. A cell's wireframe shows its
seams by design, and the translucent modes (X-RAY, FRESNEL, the INTERIOR ghost) show the internal cut
faces between touching cells.

**Next, in the author's order:** the room cache and its copy on disk, so the 9.6 s cut and the bake
before it are paid once per ship rather than once per session.
