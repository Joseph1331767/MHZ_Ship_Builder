# 0003 — The SDF is the model of truth; Surface Nets now, with Dual Contouring as a one-function swap

- **Date**: 2026-08-31
- **Status**: Accepted

## Context

The builder needs two things at once that no single representation does well:

1. **Crisp, immediately-responsive CAD primitives** while a part is being dragged, scaled or tuned —
   the interaction has to feel like the Spore ship editor, which means feedback every frame with no
   visible lag or wobble.
2. **A genuinely volumetric hull** underneath that assembly, exact enough to compute mass, internal
   volume and budget usage now, and to later support a shelled interior, per-layer damage, and routing
   (Phase 2/3) — none of which is answerable from a pile of discrete meshes with no shared ground truth.

Meshing every primitive fresh each frame is fine for (1) but throws away (2) — there is no volume, no
interior, nothing to shell. A pure voxel/SDF representation is exact everywhere but is far too slow to
remesh live during a drag at interactive frame rates. Neither representation alone satisfies both
requirements, and picking one as "the" representation and deriving the other from it on demand, in the
wrong direction, breaks whichever need was not chosen.

## Decision

**The SDF is the model of truth. Discrete meshes are only a view of it, never the reverse.** Concretely,
three views of one JSON document (SPEC §2):

- **build** → one editor mesh per part for the live scene view. Crisp, and never remeshed while
  dragging — this is what makes the drag interaction cheap regardless of ship complexity, because
  regenerating one part's preview mesh is O(1 part), not O(whole ship).
- **evaluate** → `ResolvedShape.sdf()` / `ShipSdf`, sampled on demand for volume, mass, attach-point
  resolution and validity. Never converted to a mesh; always queried as a pure function of position.
- **bake** → **Surface Nets** over a voxel grid at `bake_cell_m`, producing the welded shell, only when
  the player explicitly asks for it (or a headless tool does, via `tools/ship_bake_cli.gd`) — not every
  frame, not even every edit.

Surface Nets was chosen over Marching Cubes specifically because vertex placement is isolated in one
function, `_place_vertex()` (`core/bake/surface_nets.gd`, per `API_CONTRACT.md` §17): "one vertex per
sign-changing cell at the centroid of its edge crossings." The documented upgrade path — replacing only
that function with a QEF solve over the gradients at the edge crossings, clamped to the cell — turns
Surface Nets into Dual Contouring using the *same grid, same traversal, same quad-stitching loop*. That
upgrade is deferred deliberately (SPEC §9: "do that when the rounding is a problem, not before"), but the
architecture is chosen now specifically so that deferral does not cost a rewrite later.

## Consequences

- **Dragging stays interactive at any ship complexity**, because the live scene view never touches the
  SDF or a voxel grid — it only rebuilds the one part that changed.
- **The SDF ground truth is always exact** regardless of what happens to be on screen, so volume, mass
  and budget numbers (SPEC §8) never drift from what the bake will eventually produce.
- **The Phase 1 → Phase 2 path is designed in, not bolted on.** The Phase 1 bake deliberately produces
  the all-open "studio" hull with no interior walls (joint SDF partition geometry is authored but not
  built — SPEC §7), and that is legible as a known, bounded limitation rather than a broken bake, because
  the representation underneath it already supports the eventual interior shell, hull-material volume,
  and UV-atlas-per-texel damage/routing layer (SPEC §9's Phase 2 hooks) without redesign.
- **The Dual Contouring upgrade (sharp box edges back) is a single documented function swap**, not a
  rewrite — this is the whole point of isolating `_place_vertex()`, and it is why this ADR exists instead
  of just leaving the note in the spec: choosing Surface Nets *because* of this property is an
  architectural commitment, not an implementation detail.
- **Two honest, bounded costs, both accepted rather than solved away (SPEC §9):**
  - `min()`-union of per-part SDFs is not an exact interior distance — only exact outside. Near joints
    the `-T` level set sits too far out, so the shell reads slightly thick. The fix (a grid plus an
    eikonal sweep) is known and deferred until it actually matters for gameplay or the Phase 2 interior
    shell.
  - Non-uniform part scale turns an SDF into a *bound*, not a true distance (conservatively corrected by
    dividing by the max scale component). This is harmless for meshing and only matters if something
    ever sphere-traces the baked hull for speed rather than sampling it directly.
