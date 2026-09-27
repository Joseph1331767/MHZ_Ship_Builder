# 0047 - A prebuild has no walls, and the layers are an explorer

- **Date**: 2026-09-26
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. What a
  TEMPLATE authors is not what a document MEANS; no stored ship changes.
- **Extends**: ADR 0046 (the walls are their own layer)
- **Amends**: the template brief's "a hatch between each hallway/tunnel and room and room to room
  connection" - now what the picker's LINKS option selects, not what it forces
- **Records**: FOLLOWUPS F52

## Context

The author, 2026-09-26:

> "i click on carbon, and i explode it, and all the proton chunks have walls between them, and the
> walls dont even seperate in the explosion, and they arent even supposed to be there by default.
> by default in the prebuilds we dont want any walls in our prebuilds by default."

> "because of hatches i cannot tell if the walls are being built and overriding the hatches
> visually. so i thought a layers explorer that lets the player hide hatches, walls, [expandable
> later] type of stuff."

**MEASURED FIRST, because the report and the geometry did not agree.** A carbon straight out of the
picker carried:

| | |
|---|---|
| nucleus links (in the definition, ADR 0025) | **15, all OPEN** |
| arm links (core to tunnel, tunnel to pod) | **8, all HATCHED** |
| wall surface on the baked ship | **12.5 m2** |
| cut surface on the baked ship | **552.3 m2** |

So there were no walls between the protons at all - the protons were already open to each other -
and the flat faces the author was looking at are **CUT** faces: where a room is split back into its
members (ADR 0036) and where a piece is diced for printing (ADR 0032/0041). Dropping the WALL layer
on a hatched carbon changes **131 px**; dropping the CUT layer changes **105,233 px**. That is a
factor of eight hundred, and it is why "the walls dont even seperate in the explosion" - the slice
and chunk gaps are 0.00 m by default, so diced chunks sit flush and read as internal walls.

The ask stands on its own regardless, and is unambiguous: a prebuild should carry no walls.

## Decision

**`ShipTemplates.OPT_LINK_MODE`, defaulting to `MODE_OPEN`.** Every template connection is linked
open, so a prebuild bakes with no wall face anywhere on it.

**THE HATCH IS STILL AUTHORED** on every one of those links - its family and its params are written
in whatever the mode says. Turning one link into a wall with a door is a single edit and nothing has
to be chosen again, which is the whole of "for user ease, when they are adding walls to their proton
chunk".

**The picker gets a LINKS row**: OPEN (one room, no walls) / HATCHED (a wall with a door) / SEALED
(a solid wall). The old behaviour is one click away and is no longer the default.

**`ShipLayersControl` is the layers explorer** - a panel over the 3D view, top left, one checkbox per
layer: **WALLS**, **CUTS**, **DOORS**. A layer is one row of `LAYERS` (key, label, help) and nothing
else, because "expandable later" is the requirement: a new one costs one entry plus whatever honours
the key, and for a named surface of a baked piece that is already written.

**`ShipSceneBuilder.walls_hidden` becomes `hidden_layers`**, a `PackedStringArray` assigned whole.
Doors are whole nodes rather than a named surface, so they are hidden rather than dressed
transparent, and the door leaf keeps its own `cut_solid` shading base so dropping CUTS does not take
the doors with it.

**WALLS left the top bar**, one day after arriving there (ADR 0046). Three more check buttons in a
bar that already holds eleven is not an explorer. DITHER stays in `ShipViewToggles`: it is a render
setting, not a layer.

## Consequences

**41 tests and two tools failed, and every one of them was right to.** They had all been written
against the old hatched default and assert things about walls, doors, rooms and the meshes they cut.
The fix was to make each say so - one `_linked()` helper per suite carrying the premise, and the
same two lines in `ship_resolve_check.gd` and `ship_explode_check.gd` - rather than to weaken an
assertion. The premise is now stated where it is relied on instead of resting on a default that no
longer says it.

**A carbon of either family bakes with 0.00 m2 of wall**, asserted in
`test_a_prebuild_bakes_with_no_wall_anywhere`, and the link option brings the hatches back, asserted
in `test_the_link_mode_option_brings_the_hatches_back`.

**An all-open prebuild is ONE room** of fourteen members rather than a nucleus of six plus arms.
That is what "no walls" means, and it is why `ship_explode_check.gd` - which probes a `SEP_PARTS`
cell of a module carrying an offset - now asks for linked rooms.

## Verified

`reports/visual_layers.png`, looked at: a prebuild carbon exploded (whole pods, no plates), then the
same class linked hatched with each layer dropped in turn. With the explode settled so the numbers
are the layers and not the animation, inside the 3D view: WALLS off **131 px**, DOORS off **318 px**,
CUTS off **105,233 px**.

**gdUnit4 348/348**; selfcheck PASSED with the hash unchanged; data validator PASSED (0 warnings);
resolve, explode and visual (5 modes) checks PASSED; gdformat and gdlint clean.
