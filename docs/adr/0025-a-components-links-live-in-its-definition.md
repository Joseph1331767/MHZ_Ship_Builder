# 0025 — A component's links live in its definition

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236`
  before and after. A definition gains an optional `joints` map; documents without one read
  as before.
- **Amends**: ADR 0024 — "a component instance is one room by membership" is WITHDRAWN. Rooms
  come from OPEN seams alone again, and a component's inner seams carry the modes its definition
  holds.
- **Records**: FOLLOWUPS F37

## Context

> "i click into the proton component, highlight all chunks, try to make them a open room/change
> their link, and it says 'they are a room already, dissolve the room to change link' this doesnt
> make any sense and makes the system unusable. i dont care if they are already a room, they are a
> room made of chunks and i should be able to change their internal chunk link types. (AND I
> SHOULD BE SET TO OPEN ROOM BY DEFAULT and its not). - i try to import components but it says
> 'theres no ships' yet we have an entire fleet of default ships made? .. going into a component
> shouldnt block me from doing anything."

ADR 0024 made "one room" a rule of membership with no joint behind it — so there was nothing for
LINK to change, and it refused. That was the wrong abstraction: the player's mental model is a
room made of chunks whose links they own, inside a component or not.

## Decision

**A definition holds the joints between its own parts.** `doc.components[id].joints` maps joint
ids to joint records whose ends are inner ids (`cp_NNNN`). `ShipComponents.inner_pair` says when
two keys are parts of one definition (two inner parts of an instance, or one and the instance
itself — its proxy is the definition's root; nested instances are their own definitions);
`inner_joint_for` reads that definition's joint for the pair, `set_inner_joint` writes or erases
it. `ShipSeams._joint_for` routes such a pair to the definition, so `mode_for`, `style_for` and
`hole_for` answer for inner seams exactly as they do for the document's — and the SDF, the plan,
the engine bake and the exploded view follow without knowing.

**The links move with the parts.** `make_component` moves the joints between lifted parts INTO
the definition (previously they were dropped as "inside walls"); `dissolve` brings them back as
document joints; `import_from` carries a ship's joints into the ship's definition, so an imported
ship keeps its walls and hatches. Every instance of a definition shares its links, as it shares
its parts.

**OPEN by default for the nucleus.** `ShipTemplates._lift_nucleus` writes an open joint into the
definition for every pair of the clump that meets. The player sees it as OPEN and can change it.

**LINK and seam styles work on a component's chunks, in isolation or out.** `cycle_link` and
`_apply_seam_style` write to the definition when the pair is inner (`within_one_instance`); the
tree's LINK no longer refuses; `_meet_for_hatch` and the labels read inner parts through
`part_at`. The instance row reads `(N PARTS)` — what the links say is the links' business.

**IMPORT COMPONENTS lists the fleet.** `ShipComponentImport.sources` lists every atomic class the
templates build (`CLASS: carbon`, …) before the saved files; a class is built in the importing
ship's own room family (a sphere ship imports sphere classes). The builder's inline flow and its
bake HUD moved into `ShipComponentImport` and `ShipBakeHud` to stay under the facade's line cap.

## Consequences

**Measured.** gdUnit4 **287/287** (changed: the nucleus definition carries ≥5 OPEN joints and no
document joint is open; a component's inner pairs read their definition's joints and an erased
one is a wall again; the lift moves the inside joint into the definition; dissolve brings the
open links back; the imported ship keeps its joints). Windowed check PASSED — five modes,
explode, update with the interior frame, isolation. Selfcheck hash unchanged; validator 0
warnings.

**The bake HUD is made twice.** The status row (and its bar) is built before the toolbar (and
its button); the HUD is remade after the button exists. Measured: the first attempt handed the
HUD a null button and nothing would have lit.

**A dissolved nucleus with its open links back baked 8 open pieces** in the walled fixture
before that fixture stripped them — the same open links that bake closed through the component.
Recorded as F37: not on the player's path (dissolve has no verb yet), and not understood.
