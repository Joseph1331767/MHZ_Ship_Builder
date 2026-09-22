# 0030 — The bake makes what is on screen; the exploded extras wait for the first ask

- **Date**: 2026-09-21
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Nothing in `core/` changed; the geometry the engine makes is identical (below).
- **Amends**: ADR 0020/0021/0022/0029 (what one engine bake makes and returns), ADR 0023/0028 (how
  the builder asks for a bake)
- **Records**: FOLLOWUPS F42
- **First step of**: Phase One Hull Review recommendation 1, "bake by room, cache by room"

## Context

> "we will take off from the top and continue" — the author, 2026-09-21, meaning the review's
> first recommendation. And to the plan: "1) yes 2) yes 3) now, go ahead with step 1".

A carbon of spheres took **19.0 s** to bake, and a second bake of the same ship cost exactly the
same. Measured headless, per pass and then by part:

| where | time |
|---|---|
| the n-gon merge on every read-back (GDScript, presentation only) | 7.6 s |
| the engine's booleans, all passes | ~5–6 s |
| weld, surface classification, report, plan | ~2 s |

A bake read the engine's result back **58 times**. Fourteen of those are the ship on screen. About
twelve were pieces read before their doors were bored and thrown away when the bored piece was read.
The remaining ~31 were halves and whole-room shells that only the exploded view and ROOMS: WHOLE
draw.

## Decision

**`ShipCsgBake.bake()` makes the assembled ship and nothing it does not show.** Passes one and two
and the doors run as before, with no read-back between them: each piece stays in the engine as the
combiner that made it until its doors are through it, then is read **once**. The report keeps what
the extras need under `EXTRAS_INPUT` (the plan, each piece's engine mesh, each room's shell mesh)
and says `EXTRAS_READY: false`.

**`ShipCsgBake.bake_extras(host, bake)` makes the rest when first asked:** every room of several as
one shell bored with all its members' doors, and every piece and whole room halved on its
manufacturing plane. It returns a copy of the report with them in; the report it was given is not
touched. The engine's meshes are Resources, so they outlive the stage they were made on and serve as
the extras' operands.

**The builder asks through `ShipBakeSession`** (harness), which owns the last bake, the stale flag,
one engine job at a time with one update queued behind it, the discard of a bake for a replaced
document (ADR 0028), and the extras. The builder keeps what is on screen. EXPLODE, or ROOMS: WHOLE
over the baked view, asks for the extras when the last bake has none and shows them when they land.
Nothing starts a bake on its own: the author's no-automatic-heavy-work rule stands.

## Consequences

**Identical geometry, measured.** Both families of the template carbon, before and after, compared
field by field: every piece's volume, face count, vertex count and open edges; every drawn mesh's
named surfaces and their triangle counts; every half; the whole-room shell and its halves; the bored
set and the door failures. **Zero differences.**

**Timings (headless):**

| ship | before | assembled | extras, on first EXPLODE / ROOMS: WHOLE |
|---|---|---|---|
| carbon, sphere pods | 19.3 s | **6.0 s** | 9.7 s |
| carbon, box hulls | 8.9 s | **2.9 s** | 4.0 s |

The first EXPLODE after an update now takes its own time, with the bar. The author accepted that
trade. Later EXPLODEs of the same bake cost nothing.

**A latent bug fixed on the way.** The exploded view has always read `room_shell_halves` to draw a
whole room in two, and the bake never wrote it, so a whole room exploded unhalved. The extras write
it.

**`ShipBuilder` is lighter by twelve lines**, down to 1985 of 2000, with the bake state behind
`_bake_session`. The visual and resolve checks read `_bake_session.busy` and `.last` where they read
`_explode_baking` and `_last_bake`.

**What this does not do yet — steps 2 and 3 of the same plan.** A room-keyed cache, so an edit
rebakes only the rooms whose inputs changed, and that cache kept on disk so a ship reopens without
rebaking. Step 2 first needs each part's tessellation phase keyed on its own id rather than its
position in the sorted list: today, deleting one part re-tessellates every part after it.
