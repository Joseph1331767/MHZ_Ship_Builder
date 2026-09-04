# Project Rules — Single Source of Truth

All agents (Claude Code, Antigravity, and any future tool) working in this repo must follow these rules.
This file is the ONLY shared rules file. Claude Code loads it via the `@AGENTS.md` import in `CLAUDE.md`;
Antigravity reads it natively. Tool-specific extras live in `CLAUDE.md` / `GEMINI.md` — never duplicate
shared rules there.

Derived from `MHZ_Materials/AGENTS.md` (same numbered structure, ported almost verbatim where the two
projects share a shape) with the GPU-slot and Windows-gotcha rules ported from `MHZ_Origins/AGENTS.md`
§7c, because unlike Materials this module **does** render, and windowed runs compete for the same GPU.

## 1. Project Overview

**Project:** MHZ Ship Builder — a deterministic parametric hull builder (isolated scene, destined for
MHZ_Origins). **Engine:** Godot 4.7 (Forward Plus) — GDScript with strict static typing.

**Central design doc:** `docs/SHIP_BUILDER_SPEC.md` — the node of truth. Read it, especially §3 (attach
model), §4 (shape generation), §9 (the SDF and the bake) and §10 (render-to-texture), before changing
anything in `core/` or `data/`. Sections marked **CONTRACT** cannot be relitigated in code — a change to
one requires an ADR.

**The frozen interface:** `docs/API_CONTRACT.md` pins every `core/` and `harness/` class name and
signature for the duration of milestones M1–M6. See §9 below — this file does not get edited casually,
by anyone, ever, including the rule-writing session that produced this document.

**What this module is.** A CAD-style ship hull builder: parts are placed on the *surface* of other parts
by typed angular coordinates or by dragging, and the assembly resolves to an exact signed distance field
that can be baked into a solid hull shell. Every visible shape is fully determined by its stored
parameters — no rollable seed, no hidden dice the player cannot see the inputs to.

**What this module is not (yet).** No interior, no power/data/fuel routing, no working components
(thrusters, sensors), no material layers (that is MHZ_Materials' job once it plugs in), and the Phase 1
bake produces the all-open "studio" hull with **no walls** — joint geometry is authored in Phase 1 but not
built. That is by design (SPEC §7) and must never be read as a bug. Interior, routing, materials and
working components are Phase 2/3 and are only *reserved for* in the data model, not implemented.

## 2. GDScript Style — Strict Static Typing

- **All variables** explicitly typed: `var health: int = 10` or inferred `var name := "Hunter"`. Never `var health = 10`.
- **All function signatures** typed: `func take_damage(amount: int) -> void:` — parameters AND return.
- **Warnings are errors.** Do not bypass or ignore GDScript parser warnings (project enforces
  `untyped_declaration=2` etc.). If a warning is truly unavoidable, document why in a comment.
- **Node references:** `@onready var label: Label = $UI/Label` — always typed.
- **Modern APIs only:** Godot 4.3+ patterns. No deprecated/legacy patterns.
- **Angles are degrees at every API boundary** (per `API_CONTRACT.md` global rules); convert to radians
  inside a function, never across one. **Distances are metres.** Godot is Y-up. **Never mutate an
  argument — return new values.**

### Naming
| Thing | Convention | Example |
|---|---|---|
| Files & directories | `snake_case`, `ship_` prefix inside `harness/` and `tools/` for ship-doc-specific files | `ship_attach.gd`, `ship_selfcheck.gd` |
| Classes (`class_name`) | `PascalCase`, `Ship` prefix for anything that operates on a `ShipDoc` | `class_name ShipAttach` |
| Shape-generation math with no ship-doc dependency | no prefix — this split is already fixed by `API_CONTRACT.md`, do not rename it into consistency | `ResolvedShape`, `SdfPrims`, `SdfOps`, `ShapeGen`, `SurfaceNets`, `HullBake`, `OrbitCamera` |
| Variables & functions | `snake_case` | `part_count`, `resolve_all()` |
| Constants | `UPPER_SNAKE_CASE` | `RULESET_VERSION` |
| Signals | `snake_case`, past tense | `part_added`, `doc_changed` |
| Data IDs (JSON) | `snake_case`, globally unique, **immutable once created** (part ids are referenced by regions, damage state and routing later — SPEC §5.1) | `box_hull`, `p_0007`, `kessler` |

## 3. Directory Conventions

The layout is SPEC §12, verbatim:

| dir | contents | rule |
|---|---|---|
| `core/` | pure data — the truth layer: doc model, attach, SDF, shapes, metrics, bake, mirror, components | **Hard rule: no `Node`, no `SceneTree`, no `@onready`, no signals, no `await`, no `res://` file access outside `ShipData`.** Every class is `RefCounted` or static-only. Pure data in, pure data out. |
| `data/` | JSON packs — families, manufacturers, hatches, palette, tuning, schema, ships | Hand-editable and machine-generated. Every file conforms to a schema in `data/schema/`. Adding content must never require touching `core/`. Every catalogue entry carries a real `description` — see §10b. |
| `harness/` | the builder, `SubViewport`-rooted | May depend on `core/`. `core/` may **never** depend on it. |
| `tools/` | headless entry points: validate, selfcheck, bake, screenshot | Run via `$env:GODOT_BIN --headless --path . -s res://tools/<x>.gd`, or through `tools/ship_run.ps1` — see §8a. |
| `tests/` | gdUnit4 | Determinism tests are non-negotiable — see §8b. |
| `docs/` | this file, `adr/`, `devlog/` | |
| `scratch/` | throwaway (gitignored) | §4 |

**Isolation is the whole point of this repo.** `core/` + `data/` is the drop-in unit that lifts into
MHZ_Origins as-is. **Nothing in `core/` may reference anything outside `core/` and `data/`** — not
`harness/`, not `tools/`, not an autoload, nothing. If a `core/` file needs something from outside that
boundary, the design is wrong, not the import.

## 4. Scratch Rule — No Clutter

ALL throwaway files (test outputs, one-off scripts, logs, check dumps, patch scripts) go in `scratch/`
(gitignored). **Never** create `check.txt`, `test5.gd`, `patch_foo.py`, `output.log`, etc. in the repo root
or module directories. Tool output goes to `reports/` (create it if a tool needs it; gitignore it the same
way). If a temp file proves permanently useful, move it to its proper home and log it in the devlog.

## 5. Git Discipline

- **Agents do not run write git commands** (`commit`, `push`, `checkout`, `reset`, `rebase`, …) unless the
  user explicitly requests it in the current conversation. Read-only git is always fine.
- When the user does request commits: small units, **Conventional Commits** (`feat:`, `fix:`, `chore:`,
  `refactor:`, `test:`, `docs:`).

## 6. Agent Lanes

- **Antigravity:** scene composition and editor-centric work in `harness/`.
- **Claude Code:** `core/`, `data/`, `tools/`, `tests/`, headless verification.
- **Never both agents on the same files at the same time.** Finish + hand off between lanes.
- Both agents read this file and the devlog tail at session start, and append to the devlog before finishing.

## 7. Render-to-Texture — CONTRACT

SPEC §10. This is the rule most likely to be broken by accident, because it fails silently in the editor
(a window renders fine there) and only shows up once the builder is mapped onto a diegetic device — by
which point the mistake is buried under everything built on top of it.

- The **entire** builder — 3D viewport *and* all UI — lives under one `SubViewport` at a fixed virtual
  resolution of **1280x800**, nearest filtering. `harness/dev_host.tscn` is a thin `SubViewportContainer`
  wrapper for standalone runs; it is not the real host, which is a quad in MHZ_Origins.
- **Nothing in the builder may read window size or `DisplayServer`. Ever.** No `DisplayServer.window_*`,
  no `OS.get_window_*`, no sizing decision that assumes `get_viewport()` is the OS window rather than the
  builder's own `SubViewport`. `project.godot`'s `window/size/*` describes the *dev-host* window only —
  code inside `harness/` and `core/` must not depend on it.
- `embed_subwindows = true` (already set in `project.godot` — do not flip it) and **every dialog is an
  in-scene `Control`**, never a `Window`/`AcceptDialog`/`FileDialog` popped as a native window. A native
  file dialog simply will not exist on the texture the player sees in-game.
- Text entry in-game needs the device to supply focus and a keypad (Phase N) — design numeric fields so
  they can accept synthetic input later, but do not build the keypad now.

## 8. Verification Loop

1. **Align first:** before implementing a new feature/system, inspect relevant code, explain findings, and
   get explicit user alignment on the approach.
2. **After code changes:** verify the project parses — headless script check via `$env:GODOT_BIN`.
   ⚠️ Headless Godot can hang as a background task on Windows: always run in the foreground with a hard
   timeout, kill on expiry.
3. **Run tests** (gdUnit4) for logic changes; **lint** (gdlint/gdformat) before finishing.
4. **Validate the data packs** whenever `data/` changes:
   ```
   & $env:GODOT_BIN --headless --path . -s res://tools/ship_validate_data.gd
   ```
   Exit 0 = every pack is schema-clean, every manufacturer's family reference and narrowed param exists,
   and every catalogue entry has a real description. A `data/` change that does not pass is not finished.
5. **Visual/gameplay verification belongs to the human.** Never claim visual behavior works — prompt:
   > "Please open `harness/dev_host.tscn` in Godot and run it to verify."
6. Shader changes: always verify syntax/braces — a shader compile failure during `_ready` crashes the
   scene silently and blocks all downstream async work.

### 8a. A tool that throws is a tool that failed, whatever its exit code says

A GDScript runtime error aborts the function, prints to stderr, and lets the frame carry on — so a tool
can print its own PASSED banner and exit 0 while throwing on every call. Run tools through the wrapper,
which fails the run on any runtime error even when the exit code is 0:
```
./tools/ship_run.ps1 res://tools/ship_selfcheck.gd
./tools/ship_run.ps1 res://tools/ship_validate_data.gd
```
Pass `-Windowed` for anything that opens a display (claim the GPU slot first — §8c) and `-Quiet` to drop
a tool's own verbose trace from the output.

### 8b. Determinism is a gate, not a feature

A ship that hashed to `X` today must hash to `X` forever under its recorded ruleset version (SPEC §4,
`ShipDoc.RULESET_VERSION`). Any change to `core/util/ship_canonical.gd`, `core/ship_hash.gd`, or the op
order in `ResolvedShape.sdf()` (taper → twist → base → inflate → rib → scallop, SPEC §4) requires a
**ruleset version bump and an ADR — never a silent retune.** Retuning a manufacturer's *ranges* is safe
and free (SPEC §4: "ranges gate input, the hash consumes output"); changing what a param *means*
geometrically is the thing that moves every ship built under the old meaning.

Run `tools/ship_selfcheck.gd` after touching any of those three files — it hashes a doc twice and asserts
the hashes match before anything else is trusted.

### 8c. The GPU is a booked resource — one agent runs Godot at a time

Ported from `MHZ_Origins/AGENTS.md` §7c. This module renders (unlike MHZ_Materials, which does not and
correctly has no such rule) and shares one GPU with every other agent on the machine.

- Claim the slot **before any Godot invocation — headless counts, it still pins cores**:
  ```
  ../../MHZ_Origins/scripts/gpu_slot.ps1 -Action claim -Lane MHZ-SHIP-BUILDER -Reason "..."
  ```
- Release it **in the same message you finish** the run that needed it.
- The orchestrator running multiple agents in this repo is expected to serialize all Godot invocations
  through this slot, not just windowed ones.

### 8d. Windows gotchas

- **Never run headless Godot with `run_in_background` — it hangs on Windows.** Foreground + explicit
  timeout only.
- A new `class_name` is **invisible until `--import` runs**: `& $env:GODOT_BIN --headless --path . --import`,
  otherwise every reference fails with "Identifier not declared in the current scope."
- gdUnit4 refuses to run headless without `--ignoreHeadlessMode`; it then exits **103** with a message
  about `InputEvents`, which is **not a test failure**:
  ```
  & $env:GODOT_BIN --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests
  ```

## 9. API Contract Discipline

`docs/API_CONTRACT.md` states it plainly and it is repeated here because it is the rule most likely to be
broken by someone trying to be helpful: **it is frozen for the duration of M1–M6.** Every agent codes
against its exact names and signatures. **If a signature looks wrong, say so in a report — do not change
it unilaterally.** Several other agents may be compiling against that exact name at the same moment; a
unilateral rename breaks work nobody told you about.

The same applies to any section of `docs/SHIP_BUILDER_SPEC.md` marked **CONTRACT** — those decisions were
made explicitly with the author and are not to be relitigated in code. A change to a CONTRACT section
requires an ADR, not a diff.

The classes `core/` tools call (`ShipData`, `ShipDoc`, `ShipSdf`, `ShipAttach`, `ShipHash`, …) may not
exist on disk yet during early milestones while other agents are still writing them — that is expected.
Code the tool against `API_CONTRACT.md` exactly and let it fail to parse until the class lands; do not
invent a placeholder signature "to make it run now."

## 10. Documentation Duties

- **Dev log** (`docs/devlog/CHANGELOG.md`): append-only, chronological — new entries go at the END of the
  file. Every work session appends one entry: `## [YYYY-MM-DD] Title` + what changed, why, how verified.
- **ADRs** (`docs/adr/`): any architectural decision, any ruleset version bump, any change to the attach
  model or the SDF op order gets a numbered ADR.
- Keep `docs/SHIP_BUILDER_SPEC.md`'s milestone table (§13) current: `Not Started → In Progress → Testing →
  Completed`.

### 10a. A docstring is not evidence

Verify claims against the code, not against prose. When a comment contradicts the code, the code wins —
then fix the comment. Do not delete retired prose; mark it in place, on or within 3 lines of the mention:

```
RETIRED(<ADR or date>): <old thing> -> <live thing> (<where the live thing is>)
```

### 10b. The data packs are documentation

`data/` is read by humans and agents as the description of what the builder can produce. Every family,
manufacturer and hatch entry carries a `description` field written for a reader, not a parser (SPEC §5.3:
"An entry with a placeholder description is unfinished"). Unlike MHZ_Materials, where this is a
validator *warning*, here it is a hard gate: `tools/ship_validate_data.gd` **fails** any entry whose
description is missing, empty, or a placeholder (`TODO`, `TBD`, `Description`, or under 20 characters).
A `data/` change that trips this is not finished, full stop.

## 11. Communication

- If the user asks a question, seems confused, or raises a concern — **explain before acting**.
- For complex tasks, work phased: pin data contracts/names/IDs first, implement incrementally, verify each
  increment, purge stale context between phases.
