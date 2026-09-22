# 0031 — Explode options: separations, and a slicer in each part's own axes

- **Date**: 2026-09-21
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. The plan gains a `frames` key; the document and its hash are untouched, and the
  explode settings are view state that never enters a ship file.
- **Amends**: ADR 0022 (every module "sliced down the middle" → a slicing grid the player sets),
  ADR 0030 (what the extras make)
- **Records**: FOLLOWUPS F43

## Context

> "explode looks cool, but i want to make it AAA. so we will have explode specific options/toggles
> to configure as a player. we will have a part separation toggle with a slider that dictates how
> far it separates ... next is the slicer settings, currently slices in a single half, but now ill
> offer 3 orthogonal slices, and offer single slice or double slice in each orthogonal direction
> for bisection vs trisection. and a separation value for those pieces as well. - and a nodecluster
> bisector includer toggle that lets chunks from nodes get sliced with its own isolated slicing
> settings. - also we now want it to show an animation of the parts coming apart" — the author,
> 2026-09-21.

Decided with the author the same day: exact engine slices rather than GPU clip-plane chunks ("exact
slow bake, then cache and animations"); the cluster toggle slices a room's chunks with their own
settings; the axes are "orthogonal axes where one points radially with the parts placement, so
alignment is preserved to the part itself"; the settings are remembered between sessions.

## Decision

**Every part has a slicing frame** (`ShipMeshBake.plan`, `frames`): its own axes, orthonormal and
right-handed, at its origin, with Y its placement normal. A mirrored twin's frame has one axis turned
back so the engine is never handed a reflected box.

**The extras cut every piece into the cells of a slicing grid** (`ShipCsgBake.bake_extras(host,
bake, slicing)`), with each axis set to off, one cut (bisect) or two (trisect). The cuts sit at
equal divisions of the part's ORIGINAL body extent in its frame, so a cut does not move when a
neighbour changes what was carved off the piece. `slicing` is `{"parts", "clusters"}`: a piece
standing alone and a room shown whole take the parts' counts; a chunk of a room of several takes the
clusters' counts, or none when the player does not include them. The grid is cut one axis at a time
(X slabs, then Y slabs of those, then Z), with engine meshes handed between passes and only the
leaves read back. An empty cell, one wholly inside a cavity, is dropped. The report names the slicing
its extras were made with (`EXTRAS_SLICING`), and the default is the old single cut across Z, so
nothing changes for a player who never opens the panel.

**The player's settings** (`ShipExplodeSettings`, saved to `user://explode_settings.json`):
- separate modules on or off, and the gap;
- the slicer's three axes and the slice gap;
- the cluster toggle, with its own three axes and its own gap.

**The panel** (`ShipExplodePanel`) is an in-scene control docked top-right over the 3D view while it
is exploded. **The glue** (`ShipExplodeControl`) keeps `ShipBuilder` inside its size budget.

**Two costs, two behaviours.** A separation only moves what is on screen: every visual remembers
the module it hangs off, its slice direction and which gap scales it, and
`ShipExplodeView.relayout()` repositions them with no rebuild and no bake. A slicer change decides
what the engine cuts, so it lights APPLY SLICES, and APPLY asks the session for extras made with the
new slicing. That follows the author's no-automatic-heavy-work rule (ADR 0028).

## Consequences

**Measured on the template carbon of spheres.** Default slicing: 14 of 14 pieces in two. Parts
trisected along Y and cluster chunks bisected across X: 8 parts in three slices each that sum to the
piece (a pod 13.7 + 13.5 + 12.8 m³ of 40.0), 6 cluster chunks in two, 72 nodes on screen. A wider
gap moved a piece 3.4 m with no rebake; separation off put every module back on its seam. gdUnit4
307/307 with a new suite (`test_explode_slicing.gd`, six tests).

**A bug found by looking, not by the tests.** The first cut re-read every slicing job after each
axis pass, so a job not cut on that axis lost its cells: every standalone piece came out whole
whenever the clusters were cut on a different axis. Both the unit test and the windowed check had
asserted the counts asked for rather than the slices made; both now assert the slices that exist,
across mixed axes.

**Cost grows with the grid.** Each cell is an engine combiner and a read-back. Three axes trisected
is 27 cells a piece; on a carbon that is minutes. The room cache (the next step) makes a re-slice cost
only the pieces whose inputs or slicing changed.

**Still to come, in the author's order:** the cache (steps 2 and 3 of ADR 0030's plan), then the
animation: modules part from modules, then a cluster's chunks separate, then the slices, with a speed
setting and a position override. `ShipBuilder` is at 1997 of 2000 lines, so the animation needs the
facade split (Phase One Hull Review recommendation 8) before it can add anything there.
