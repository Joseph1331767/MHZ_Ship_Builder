# 0028 — A ship arrives resolved, and the interior is its own mesh

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236`
  before and after. Nothing here touches a document.
- **Amends**: ADR 0023 (the baked view is the assembled view from the moment a ship arrives),
  ADR 0022/0024 (the INTERIOR mode's materials and meshes)
- **Records**: FOLLOWUPS F40

## Context

> "i loaded the system, picked a carbon .. switched to wire mode so i can see the internals (as
> the interior view is still not working and only shows the outer shell filled solid). and to my
> surprise i see 6 individual overlapping proton clusters .. the damn ships should be fully
> resolved .. when i load it its like that and i dont have to do anything."

> "it appears you have the inner mesh and outer mesh of the hull as a single mesh. i was told
> the correct way is for the exterior mesh and the interior mesh to be separate."

The document was resolved — an open nucleus with hatched tunnels since ADR 0025 — and the
screen was not: the assembled scene drew the preview primitives, six whole spheres over one
another, until UPDATE MESHES was pressed. From the player's chair that is "not resolved".

## Decision

**A ship that arrives resolves itself.** `found_from_template`, `found_document` and
`_open_named` end in `_resolve_on_load`: one bake, the bar showing, the baked pieces on screen
when it lands. Nothing re-bakes on its own afterwards (ADR 0024 stands): edits light the button.
Measured on the user's scenario — the start chooser dismissed, `carbon` on sphere pods, no
press: 14 baked modules for 14 placed ids, the nucleus one room of six, eight hatched joints,
zero primitives showing (`tools/ship_resolve_check.gd`, windowed, with frames).

**The resolved ship stays on screen while the player works.** `ShipSceneBuilder.set_exploded`
takes the ids the bake COVERS: only those primitives hide. A part placed since the bake shows as
its primitive beside the baked pieces rather than vanishing until the next bake, and a placement
no longer drops the view to primitives.

**One bake at a time, and a bake for a replaced document is discarded.** A request during a
bake queues one more; a result whose document is no longer the current one is thrown away and
the current one baked. Measured: the chooser's blank ship was baking when the class replaced it,
and its one-module bake was shown for the carbon.

**Godot's front face is clockwise.** The engine's pieces wind by the right-hand rule (normals
out of the material), so from the side a surface faces, Godot sees its BACK faces. The faceted
shader hid this (cull_disabled, FRONT_FACING flip); the INTERIOR mode did not. Its materials are
now the right way round: the exterior keeps its Godot fronts (the inner side of the far wall),
the interior keeps its Godot backs (the cavity side), the cuts both. Measured the wrong way
round: the near outer wall drew as a solid blob and the far cavity as a black hole.

**The interior is its own mesh.** `ShipExplodeView._split_interior` gives every placed piece
two nodes — the exterior with its cuts, and the interior alone — from the bake's named surfaces,
so each can be culled, hidden or picked on its own. No surface is drawn double-sided.

**A cavity is shaded as a hollow.** The interior material shades hard with a low floor
(`INTERIOR_CAVITY_AMBIENT`), the far outer wall keeps a higher floor so the wall thickness
reads at the rim. Measured before: a bowl lit flat reads as a ball.

**A cut plane exists and is not used.** The shader carries `cut_plane`; the scene pushes it to
the INTERIOR set; the view pushes `NO_CUT`. A section through the orbit focus was built and
measured: it threw away half the ship the mode is meant to show. It stays for a SECTION mode.

## Consequences

**Measured.** gdUnit4 **290/290**; the resolve check PASSED with the frames
`reports/visual_resolved_{wire,shaded,interior}.png`; the main windowed check PASSED; selfcheck
hash unchanged; validator 0 warnings.

**The load costs the bake** — 1.5 s on the demo, 9–12 s on a carbon of spheres — with the bar
up. The room cache of the phase-one review is what makes this cheap.

**The visual check captures primitives**, so it turns the resolve off for its build
(`_resolve_on_load_enabled`); the resolve check covers the resolve.
