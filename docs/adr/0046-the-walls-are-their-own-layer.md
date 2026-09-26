# 0046 - The walls are their own layer

- **Date**: 2026-09-25
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side.
  Naming a face changes no geometry and no stored value.
- **Builds on**: ADR 0034 (the link is the joint record), ADR 0036 (a room splits at its seams)
- **Records**: `docs/future/walls.md`

## Context

The author, 2026-09-25:

> "walls should be isolated from the shape its actually apart of, such that when walls layer is
> removed you see an open room"

One caveat was raised with them and stands: a chunk with its wall lifted out is **no longer
watertight on its own**. Watertightness becomes a property of the ASSEMBLY rather than of each
printed piece. That is fine for a layer you hide, which is this ADR; it is the thing to settle
before walls become separately printed panels, which is not.

**What a wall actually is here, and it is not a plate.** A walled seam authors no geometry of its
own: the two cavities simply do not merge. `ShipMeshBake`'s walled branch gives the INDENTED part a
socket the indenter's body punches through its outer surface, and retreats its inner surface from
the indenter's body GROWN by one wall thickness. So the wall is the indented part's **own cavity
face**, standing where its neighbour pushed in. There is nothing to "remove" - there is only a face
to stop drawing.

## Decision

**Every baked piece names that face `ShipCsgBake.SURFACE_WALL`**, a fourth named surface beside
`exterior`, `interior` and `cut`. It is found by asking the same grown field that made it: for each
cut the plan recorded for a member, the cut's `inner` cutter is the neighbour's grown body, and a
face all of whose corners sit on it is a wall.

**The wall is classified FIRST**, before body and before room. A wall is also a cavity face - it
bounds the room - so asking the cavity first would swallow every wall there is.

**`ShipView3D.set_walls_hidden(on)` is the layer switch**, and the INTERIOR mode defaults to
hidden: it is the mode that looks into rooms, so it is the mode that drops what stands between
them. Shown, a wall wears the CUT material - drawn on both sides, because a wall is the one surface
a camera can legitimately meet from either room. Every other display mode puts one
`material_override` on the whole piece, so walls draw there exactly as they always did.

On `ShipSceneBuilder` the switch is a **property with a private setter** rather than a method: that
class stands at gdlint's thirty-public-method cap, and assigning `walls_hidden` still rebuilds the
materials.

## Consequences

**The layer tracks the seams and nothing else.** Measured on a carbon with `box_hull` rooms:

| seams | wall layer |
|---|---|
| all 20 open | **0.00 m2** - the surface is not even emitted |
| as the template builds it (12 open, the arms sealed) | 18.17 m2 |
| nucleus dissolved, all 15 links sealed | 493.25 m2 |

**A test fixture was wrong, and it mattered.** `TestCsgBake._carbon(family, false)` claimed "walled
means walled" but **erased** the open joints. ADR 0034 settled that "THE LINK IS THE JOINT RECORD,
never mere contact", and a nucleus laid out side by side has no parent-child link either - so
erasing a joint does not wall a seam, it deletes it, and the six bodies read as separate rooms that
merely intersect, each uncut. The fixture now SEALS. Measured, the difference is not subtle: 5214 m2
of exterior unlinked against 4741 m2 sealed, and 18 m2 of wall against 493 m2. Every test that used
the fixture still passes on genuinely walled protons.

**Watertightness is untouched for now**, because nothing is lifted out of any solid - a hidden face
is still in the mesh. Step 2, lifting walls into their own solids so a panel can be printed on its
own, is the step that trades it away, and it is not taken here.

## Amended 2026-09-26: the toggle, and every mode

> "find it a home, add the toggl, make it work"

**A home: `ShipViewToggles`.** `ship_builder.gd` stood at gdlint's two-thousand-line cap AND its
thirty-public-method cap, and `.gdlintrc` asks for a real seam rather than a split at whatever line
the alarm fires on - "A good extraction is a self-contained, statically testable unit with no
reference back to the file it came from." DITHER and WALLS are exactly that: each forwards to the
theme or to the view and reads nothing of the builder's state. Moving both out took the builder
from 1999 lines to 1994, and the next such toggle costs it nothing. The view is handed over with
`use()` after `_build_layout()`, because `_build_header()` runs before the `ShipView3D` exists -
the same shape `ShipExplodeControl` uses.

**A switch: `WALLS`, a CheckButton beside DITHER**, starting OFF. `set_walls_shown()` moves the
button and the layer together, so a tool or a hotkey cannot leave the bar lying about what is on
screen.

**And it works in every mode, not only INTERIOR.** A `material_override` beats any per-surface
override, so `ShipExplodeView` dresses a piece PER SURFACE while there is a wall to drop and keeps
the single override otherwise. Measured on a sealed carbon, the same toggle changes 6,897 px in
INTERIOR and 24,729 px in X-RAY - far more in X-RAY, which is what a translucent hull should do.

**`tools/ship_check_views.gd` caught the one real regression**, which is the tool doing its job: it
asserted that switching the render type changes the module's material, and read
`solid.material_override` to do it. With the layer dropped that is null in every mode, so the
switch read as a no-op. It now reads the EFFECTIVE material - the surface override where there is
one, the override otherwise.

## Verified

`reports/visual_walls_compare.png`, looked at: the same sealed carbon in INTERIOR mode with the
layer on and off. On, panels close the nucleus and block the left arm; off, the rooms are open
through to the arms. A pixel diff isolates the change to a 248x129 box on the nucleus - 3300 px -
which is where the walls are.

**gdUnit4 344/344** including `test_the_wall_layer_is_named_and_tracks_the_seams` and the three
`TestViewToggles` cases; selfcheck PASSED with the hash unchanged; data validator PASSED (0
warnings); resolve check, explode check and visual check (5 modes) PASSED; gdformat and gdlint
clean.

Looked at `reports/visual_walls_modes.png`: the same sealed carbon baked and drawn in all six
render types with the layer dropped - FLAT, WIREFRAME, SHADED+WIRE, X-RAY, FRESNEL and INTERIOR all
come out as they should, so moving to per-surface materials cost none of them.
