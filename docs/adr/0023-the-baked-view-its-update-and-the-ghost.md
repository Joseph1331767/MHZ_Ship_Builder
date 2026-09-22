# 0023 — The baked view, its update, and the ghost

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Template output changes (a carbon now carries open joints on its nucleus), which is
  not a hash move: the hash consumes a document, and these documents are new.
- **Amends**: ADR 0018 (what an atomic template builds), ADR 0020/0022 (what the engine bake
  returns and where it is shown)
- **Records**: FOLLOWUPS F35

## Context

> "carbon ships should have its proton pre resolved or set to resolve on load, with open rooms for
> the proton. infact some auto behavior is to always have open rooms by default on proton clumps.
> — also i load up a ship, carbon. i check interior render. i see all spheres overlapping.. so i
> click them all .. then i change them to open room.. and nothing changes in render .. so when the
> renderer needs to update because changes were made a button highlighted at top should say
> "update meshes" and next to it a toggle "auto update meshes" .. a loading bar so the user knows
> the renderer isnt frozen. — research a quick ghost renderer that ray marches the hull changes by
> the sdf info .. so the user can experience a instant visual result while they work"

The assembled scene drew the PREVIEW primitives — one solid per part, overlapping where parts
overlap — and only the exploded view drew the engine's pieces. A link change could not show
assembled because nothing assembled was baked. The INTERIOR mode made this visible.

## Decision

**A template's nucleus is one open room as built.** `ShipTemplates.build` puts an open joint on
every pair of nucleus bodies that meet (the root and the bodies fused into it, by
`ShipSeams.pairs_within`). A nucleus of one has no joint. Pods and tunnels keep their walls and
hatches. A user who wants a walled nucleus deletes the joints, as before.

**The assembled view is the BAKED view once a bake exists.** `ShipView3D.set_baked` shows every
finished piece where it stands — the same `ShipExplodeView`, told `assembled`: no offsets, no
halves, rooms whole or in pieces per the toggle — in place of the preview primitives. ASSEMBLE
from the exploded view lands here, not in the primitives. The primitives are what the builder
shows before its first bake and while a placement drag needs the handles (a placement leaves the
baked view; the next bake returns to it).

**UPDATE MESHES, AUTO, and a bar.** Every commit and every document swap marks the meshes STALE:
the button lights in the theme's warning role (`UPDATE MESHES *`). With AUTO on — the default,
so a loaded carbon resolves on load — the re-bake is queued for the next frame; several edits in
one frame are one bake, an edit during a bake is a bake after it, and a bake that arrives behind
the document is shown and immediately marked stale again. The engine bake reports its passes
(`ShipCsgBake.bake(..., progress)`), the view its placement, and a styled bar in the status row
moves with both — a ProgressBar has no boxes in this theme, so it is given fill and background by
hand; measured, the bare one was `visible` and drew nothing.

**The ghost.** `ShipGhostView` is a box round the ship wearing `shaders/ship_ghost.gdshader`,
which ray-marches the resolved shapes on the GPU: the same primitives and the same op order as
`ResolvedShape.sdf` (taper → twist → shear → base → inflate → rib → scallop), uploaded as
uniforms on every refresh of the view. It draws the union of the parts hollowed by the hull
thickness — the band `−t ≤ d ≤ 0` of the union field, which is exactly the shell the bake makes
when every seam is open — in the theme's warning colour at a grazing-angle alpha, writing its own
depth so it sorts against the stale pieces. It fades in when the meshes go stale (0.15 s) and out
when the update lands (0.6 s). It knows no walls and no hatches, and ghosts a ship's first 32
parts: those are the update's to show, and the reason the button exists.

**The research answer.** Yes: instant feedback is achievable with the fields alone, on the GPU,
with no bake and no mesh — the ghost is that. The exact pieces still take the engine seconds, so
the two coexist: the ghost for the moment of the edit, the update for the truth. The "update
meshes" mechanic is not a fallback but the other half.

## Consequences

**Measured.** Windowed check PASSED with a new stage: an edit in the baked view lights the button
and raises the ghost (frame saved to `reports/visual_ghost.png` — the red shell over the stale
pieces), the bar shows while the engine works, 14 of 14 modules land assembled at zero offset with
every primitive hidden, the button clears, the bar hides, and leaving the view brings 14 visuals
back. gdUnit4 281/281 with two new tests (the nucleus plans as one room of six on both families;
the bake's progress ticks are ordered). Selfcheck hash unchanged; validator 0 warnings.

**The demo ship bakes inside a dozen frames**, so its ghost is on screen for a blink; a carbon of
spheres bakes in 9–12 s and the ghost carries that whole wait. The check samples at frame 2.

**A packed array handed to a function is SHARED.** `ShipCheckViews` appended to the failures
list it was given and the caller saw every line; merging that list back doubled them. The earlier
belief that parameters copy came from the Dictionary-element case, which does copy. Both recorded
in the helper's docstring.

**Two tests changed meaning.** The CSG fixture's "walled" carbon now strips the template's open
joints; the pending-seam test does the same before laying its doorway on the nucleus seam (a
tunnel's seam already carries a hatch, which wins the collapse).
