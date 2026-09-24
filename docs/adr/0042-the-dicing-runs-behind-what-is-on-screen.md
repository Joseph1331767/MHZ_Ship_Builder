# 0042 - The dicing runs behind what is on screen

- **Date**: 2026-09-24
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side.
- **Amends**: ADR 0030 (extras made on the first ASK), and sits under ADR 0028's rule rather than
  against it
- **Records**: dev note 2026-09-24 13:58

## Context

The author, from inside the builder:

> "the ship doesnt slice and dice untill after explode is pushed. thats incorrect it should exist
> like that from the initial bake. explode simply should seperate the pieces."

and, on how to pay for it:

> "you can slice in background and then do a seamless swap when its done"

ADR 0030 made the cells on the first ask, and `ShipBuilder._show_bake` RETURNED at that point - so
the screen waited for the cut. A ship was therefore undiced until EXPLODE was pressed, and pressing
it froze the view for the length of the cut: 12.9 s on a carbon.

## Decision

**A bake's pieces go on screen at once and the cells are cut behind them.** `_show_bake` asks for
the extras on every landing and does not wait: the pieces are drawn, and when the cells land the
session's `landed` runs `_show_bake` again and the view is rebuilt with them.

**The swap is seamless because nothing moves.** A piece and its cells stand in the same place, so
only the meshes change - there is no position to interpolate and no frame where the ship is
somewhere else.

**A stale cut is already thrown away.** `ShipBakeSession.request_extras` checks `is_same(last, from)`
before it keeps anything, so a cut belonging to a bake that has since been replaced is discarded -
which is what makes it safe to start one without knowing whether the document will move.

**This is not automatic heavy work** (ADR 0028, the author's standing rule). Nothing here starts a
BAKE; the dicing is the tail of a bake the author already asked for, it runs off-screen, and it
never blocks a frame.

## Consequences

**EXPLODE is four times faster**: 2.9 s on a carbon against 12.9, because by the time it is pressed
the cells exist. The work did not get cheaper - it moved off the button.

**A ship is diced from the moment it is baked**, which is what the note asked for. ROOMS: WHOLE and
EXPLODE now only arrange what is already there.

**The engine is busy for longer after a bake**, and the progress bar says so. An UPDATE MESHES during
that queues behind it exactly as it always has.

**gdUnit4 335/335**; selfcheck PASSED with the hash unchanged; resolve, explode and visual checks
PASSED; gdformat and gdlint clean.
