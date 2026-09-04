# MHZ Ship Builder

A deterministic, parametric ship hull builder — CAD-kernel determinism with the interaction feel of the
Spore spaceship editor. Parts attach to the *surface* of other parts by typed angular coordinates, the
whole assembly resolves to an exact signed distance field, and that field can be baked into a welded
hull shell (Surface Nets, with a documented one-function upgrade path to Dual Contouring).

This is an **isolated Godot 4.7 scene**, developed standalone and destined to lift into MHZ_Origins as a
drop-in unit once Phase 1 is done. It is not a standalone game.

## Status

**Phase 1, milestone M0** (see `docs/SHIP_BUILDER_SPEC.md` §13 for the full milestone table). Phase 1
builds a hull: shape generation, attachment, the SDF, budgets, mirroring/components, joint *authoring*
(not joint geometry — see the spec §7), and the bake. Interior routing, materials and working components
are Phase 2/3 and are only reserved for in the data model right now, not implemented.

## Start here

| If you want to... | read |
|---|---|
| Understand *why* the builder works the way it does | `docs/SHIP_BUILDER_SPEC.md` — the node of truth |
| Know the exact class names and signatures to code against | `docs/API_CONTRACT.md` — frozen during implementation |
| Know the rules every agent in this repo follows | `AGENTS.md` |
| See what happened and why, chronologically | `docs/devlog/CHANGELOG.md` |
| Understand a specific architectural decision | `docs/adr/` |

## Layout

```
core/     pure data - no Node, no SceneTree, no signals, no res:// outside ShipData
data/     JSON packs - families, manufacturers, hatches, palette, tuning, schema, ships
harness/  the builder, SubViewport-rooted; may depend on core/, never the reverse
tools/    headless: validate, selfcheck, bake, screenshot
tests/    gdUnit4
docs/     spec, API contract, adr/, devlog/
scratch/  gitignored
```

`core/` + `data/` is the unit that eventually drops into MHZ_Origins whole. Nothing in `core/` may
reference anything outside `core/` and `data/` — see `AGENTS.md` §3.

## Running the headless tools

Once `core/` and `data/` exist (they are being written in parallel with this document — see the devlog
for current status), the two gates are:

```powershell
./tools/ship_run.ps1 res://tools/ship_selfcheck.gd        # parse + determinism smoke
./tools/ship_run.ps1 res://tools/ship_validate_data.gd    # data/ packs are schema-clean and described
```

Use the wrapper, not a bare `-s` invocation — a GDScript runtime error can print a PASSED banner and
still exit 0 (`AGENTS.md` §8a). `$env:GODOT_BIN` must point at the Godot 4.7 console executable.

**The whole builder renders to one `SubViewport`** — nothing in it may read window size or
`DisplayServer`, and every dialog is an in-scene `Control` (`AGENTS.md` §7). This is the rule most likely
to be broken by accident because it looks fine in the editor and only fails once the builder is mapped
onto a diegetic device in the real game.

## Working in this repo

This project is developed by two coding agents side by side (Claude Code and Antigravity) plus a human
author. `AGENTS.md` is the single source of truth for how they coexist, how the GPU is shared for
headless/windowed Godot runs, and what "done" means for a `data/` change or a `core/` change. Read it
before touching anything.
