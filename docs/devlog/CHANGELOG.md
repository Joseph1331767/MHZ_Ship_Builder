# Dev Log — MHZ Ship Builder

Append-only, chronological. New entries go at the END of this file. Every work session appends one
entry: `## [YYYY-MM-DD] Title` + what changed, why, how verified.

## [2026-08-31] Project rules and headless tooling, ahead of the truth layer

**What changed.** The repo was freshly scaffolded from the agent base template and still carried
generic template prose (a placeholder `AGENTS.md` project-overview section, a template README about
the reusable template itself rather than this project). Rewrote the three rules/orientation
documents for MHZ Ship Builder specifically:

- `AGENTS.md` — rewritten from `MHZ_Materials/AGENTS.md`'s section structure (GDScript style, scratch
  rule, git discipline, agent lanes, documentation duties incl. "a docstring is not evidence" and "the
  data packs are documentation" carried over near-verbatim), with three things this project needs that
  Materials does not: a **render-to-texture** section (SPEC §10 — nothing may read window size or
  `DisplayServer`, every dialog is an in-scene `Control`), the **GPU-slot-booking rule** ported from
  `MHZ_Origins/AGENTS.md` §7c (this module renders, unlike Materials, so it competes for the same GPU
  as every other agent on the machine), and an **API Contract Discipline** section — `docs/API_CONTRACT.md`
  is frozen for M1–M6 and multiple agents are coding against its exact signatures right now.
- `CLAUDE.md` — kept the `@AGENTS.md` import on line 1, added Claude-Code-specific command
  cheat-sheet (headless invocations, `--import` for new `class_name`s, gdUnit4's `--ignoreHeadlessMode`
  / exit-103 gotcha).
- `README.md` — rewritten from a generic template README into an orientation doc for this specific
  project: what it is, current milestone, where to read what, how to run the headless tools.
- `.gdlintrc` — ported the `max-file-lines: 2000` override and its "diff against defaults, smoke alarm
  not an order to split" reasoning from `MHZ_Materials/.gdlintrc`, honestly noting that (unlike
  Materials at the time it wrote that file) there is no code in this repo yet to measure, so the number
  is inherited rather than re-derived.
- `docs/adr/0002-attach-model.md` and `docs/adr/0003-sdf-and-bake.md` — recorded the two decisions SPEC
  §3 and §9 already state as CONTRACT, so they exist as ADRs rather than only as spec prose: attachment
  resolves by sphere-tracing a ray from the parent's local origin against the parent's own SDF (not
  per-primitive UV coordinates), and the SDF is the model of truth with Surface Nets chosen over
  Marching Cubes specifically because the vertex-placement step is isolated in one function, making the
  future Dual Contouring upgrade a one-function swap rather than a rewrite.
- `tools/ship_selfcheck.gd`, `tools/ship_validate_data.gd`, `tools/ship_run.ps1` — written against
  `docs/API_CONTRACT.md` exactly, ahead of `core/`, `data/` and `harness/` existing on disk (other
  agents are writing those in parallel — AGENTS §9). The self-check builds a doc via
  `ShipDoc.create_new()`, attaches a couple of parts across two different families, resolves transforms,
  samples the SDF at a handful of points including one deliberately far outside the ship's own AABB, and
  hashes the doc twice plus once more after `duplicate_doc()` plus once more after mutating a param -
  asserting equal/equal/different in that order, which is the actual shape of the determinism guarantee
  (AGENTS §8b), not just "hash it twice." The data validator loads every catalogue pack through
  `ShipData`, fails (not warns - AGENTS §10b) on any family/manufacturer/hatch entry with a missing or
  placeholder `description`, checks manufacturer-to-family cross-references against a documented (not
  contract-pinned) guess at `manufacturers.json`'s shape, and validates each raw pack against a matching
  `data/schema/*.schema.json` through a small hand-written JSON-Schema subset when one exists, warning
  rather than failing when it does not - schemas are being authored in parallel with everything else.
  `ship_run.ps1` ports the "a tool that throws is a tool that failed" wrapper from
  `MHZ_Materials/tools/mat_run.ps1`, with its own timeout implemented via a directly-launched process
  handle rather than a background job, specifically so a timeout kills the real `godot.exe` rather than
  orphaning it - the same hazard AGENTS §8d already warns about for `run_in_background`.

**Why.** The user's instructions for this session were explicit that no Godot process may be started
(the GPU slot is a single-agent resource and the orchestrator runs verification separately, once) and
that `core/`, `data/` and `harness/` belong to other agents running concurrently. Writing the tools
against the frozen API contract now, rather than waiting for the classes to exist, means the first
headless run - whenever it happens - has something real to run rather than starting from a blank
`tools/` directory.

**How verified.** `tools/ship_run.ps1` was parsed (not executed) with
`[System.Management.Automation.Language.Parser]::ParseFile()` and reports zero syntax errors. Neither
`.gd` tool could be run (no Godot invocation permitted this session), but `core/` and `data/` landed
from other agents partway through this session, which made a stronger check possible than a bare parse:
every class both tools call (`ShipData`, `ShipDoc`, `ShipPart`, `ShipHash`, `ShipConfig`, `ShipAttach`,
`ShipSdf`, `ResolvedShape`, `ShapeGen`, `ShipCanonical`) and the real `data/shapes/families.json` +
`data/shapes/manufacturers.json` + their schemas were read (read-only, per this session's constraints)
and checked by hand against every call site in both tools. Two real gaps turned up and were fixed before
this entry was written, not after:

1. `ship_validate_data.gd`'s "documented guess" at `manufacturers.json`'s shape turned out to match the
   real pack on its primary path (`<manufacturer>.families.<family_id>.params`), which the real
   `manufacturers.schema.json` also confirms — its own description says this tool "checks that every
   'families' key resolves to a real family id and that every narrowed param key and disabled op exists
   on that family," which named a check (`ops_disabled` validity) this tool did not yet have. Added it.
2. The schema-validation half was a bigger gap: both real schema files build every reusable shape once
   under `$defs` and reference it everywhere via `$ref` (`"additionalProperties": {"$ref":
   "#/$defs/family"}` and similar), and the original lite validator had no `$ref` resolution at all — it
   would have silently stopped checking anything past the first `$ref` it met, passing nearly everything
   without complaint. Added JSON-pointer `$ref`/`$defs` resolution, `propertyNames` (recursing through
   the general validator rather than special-casing `pattern`, since `param_key`'s `propertyNames` is
   enum-based, not pattern-based), `additionalProperties: false` enforcement, `exclusiveMinimum`/
   `exclusiveMaximum`, `minProperties`/`maxProperties`, and `uniqueItems`.

**Not verified**: an actual headless run of either `.gd` tool (still not permitted this session) and
gdlint conformance. The manual code-reading check above is real but is not a substitute for running it.

## [2026-08-31] First engine gate: M1 verified, 108/108 tests green, five silent defects fixed

First session in which Godot actually ran. Everything before this was written against the frozen
`docs/API_CONTRACT.md` by nine parallel agents and verified only by gdtoolkit (`gdparse`/`gdlint`,
pure Python, no engine). The GPU slot was claimed once for the whole gate and held 15.4 min
(`MHZ-SHIPBUILDER` lane), then released.

**What now passes, for real, in the engine.**

- `--import` clean, no parse errors project-wide; 27 project classes registered.
- `tools/ship_validate_data.gd` PASSED: 6 families, 6 manufacturers, 6 hatch families, 18 descriptions,
  21 manufacturer/family cross-refs, all five packs schema-clean.
- `tools/ship_selfcheck.gd` PASSED: doc creation, 3/3 parts resolved through the ray-trace attach model,
  SDF sign correct far outside the hull, and the determinism gate — hash stable across repeat calls
  (`a14392e366b4d55c`), preserved by `duplicate_doc()`, and sensitive to a single param change.
- gdUnit4: **108 test cases, 11/11 suites, 0 errors, 0 failures, 828 ms.**

**Five defects the engine caught that static checking could not.** Recorded because each was silent —
none of them threw, and four of them would have produced plausible-looking wrong numbers.

1. **Every tuning lever was ignored** (`docs/FOLLOWUPS.md` F0). `data/tuning.json` stores levers as
   `{"value": X, "description": ..., "min": ..., "max": ...}`; `ShipConfig._as_float()` accepted only
   float/int/String and returned the caller's default when handed a Dictionary. All 17 levers silently
   fell back to code defaults — `hull_thickness_m` 0.15 read as 0.40, `max_internal_volume_m3` 200000
   read as 60000. Root cause was a contract omission, not an agent error: the contract pinned lever
   NAMES and never their VALUE SHAPE. Fixed by `ShipConfig._unwrap()`.
2. **`ship_run.ps1` discarded every tool's exit code.** `Start-Process -PassThru` returns an empty
   `$proc.ExitCode` on this machine even after a parameterless `WaitForExit()` with `HasExited` true;
   `exit $null` became 0. `ship_validate_data.gd` printed "FAILED (18 errors)" and called `quit(1)`, and
   the wrapper reported success. Verified Godot's own exit code was always correct (call operator and
   `cmd /c` both return 1). Rewritten onto `System.Diagnostics.Process` with async stream draining, which
   keeps the kill-by-PID timeout the wrapper exists for. **This was the gate itself being broken — every
   earlier "pass" through the wrapper was worth nothing.**
3. **The schema validator rejected valid data.** No `patternProperties` support, so `hatches.json` — whose
   schema declares hatch ids via `"patternProperties": {"^[a-z][a-z0-9_]*$": ...}` alongside
   `"additionalProperties": false`, the ordinary JSON Schema idiom — failed on all six ids. The reference
   Python `jsonschema` library passes the same pack. A validator that rejects valid data is worse than
   none: it trains people to ignore it. Added pattern support.
4. **`base_size` was missing from every shape family**, so `ShapeGen._base_size()` fell through to
   `Vector3.ONE`. For `torus_ring` that made major radius == minor radius, closing the hole entirely —
   and a torus is the one shape whose origin sits OUTSIDE its solid (`origin_inside: false`), so the
   attach tracer would have started from a point exactly on the surface. Added real per-family sizes and
   the matching schema entry.
5. **`inferred_declaration` warnings are errors, and gdtoolkit cannot see that.** Three `var x := <Variant>`
   sites in `ship_validate_data.gd` passed `gdparse` and `gdlint` cleanly and failed to load in Godot.
   Static tooling is a fast pre-filter here, never the gate.

**Two test failures that were the test's fault, not the code's.** Both worth writing down because the
instinct in each case is to "fix" working code.

- Sphere/box analytic volume read ~5x high. Cause: mid-session I changed `ResolvedShape` so `size` is the
  UNSCALED base size and per-axis `scale` is separate (so a stretched sphere is a real ellipsoid). The
  tests were written against the old semantics and computed `r = size.x`, ignoring scale. The measurement
  was right; the expectation was stale. Fixed the expectations.
- Box volume then held at exactly 42.875 = 3.5^3 at cell 0.5 AND cell 0.1 — which looked like a bug
  precisely because it did not move with resolution. It is phase alignment: the metrics domain is padded
  by a whole number of cells, so 3.4641 m of box lands on 7 centres at 0.5 and 35 at 0.1, giving 3.5 m
  both times. Cell-counting is first-order and quantises the recovered extent to the sampling phase, so a
  flat 2% tolerance asserted a precision the estimator never promised (the sphere passed it by luck).
  Tolerance is now DERIVED: `3 * cell / (2 * min_half_extent)`, the one-cell-per-axis bound.

**Also fixed:** `HullBake.bake()` never propagated `dims` from `SurfaceNets.extract()` into its report;
ADR numbering collided (template `0001` plus two new `0001`/`0002`) and was renumbered to 0002/0003 with
the stale devlog reference updated; `.gdlintrc` `max-public-methods` raised 20 -> 30 with the reasoning
recorded in the file, because the cap was forcing `ShipBuilder`'s facade to delete accessors and push
callers around the edit protocol.

**Not verified:** anything requiring a window. No harness scene has been opened, so the UI, the palette
post-process, the orbit camera, picking and the whole M3 interaction layer are UNRUN. `harness/panels/`
and `harness/builder/ship_placement.gd` were still being written when this gate ran. Per AGENTS, visual
verification belongs to the human — but nothing here has even been rendered once yet, which is a weaker
position than that rule assumes.

## [2026-08-31] First windowed render. Four bugs only a screenshot could find.

All nine agents finished; `harness/panels/`, `harness/builder/ship_placement.gd` and
`harness/diegetic/` landed. Second GPU slot claim, 15.6 min, released. Repo is lint-clean
(49 files, `gdlint` reports no problems), 108/108 tests green, both headless tools PASSED.

Added `tools/ship_shot.gd` — loads a scene windowed, settles it, writes a PNG to `reports/`, and
reports the count of distinct sampled colours so a frame that failed to draw is flagged SUSPECT
rather than silently saved. Every other gate in this repo proves the code parses, loads and
computes correct numbers. None of them proved a single pixel.

**The render worked first try — no script errors — and was wrong in four ways.**

1. **The Bayer dither destroyed all text.** `dither_enabled` defaulted true. Ordered dithering and
   10-12 px type are incompatible under a 16-entry quantizer: a glyph whose colour falls between
   two entries gets its stroke scattered across the Bayer pattern and stops being a letterform.
   The first frame was 99.61% background with labels rendered as isolated dots. SPEC section 11
   calls the dither *optional*; it now defaults OFF in both the shader and `ShipTheme`. Text
   coverage went up 15x and the console became legible.
2. **`internal_volume_m3` read a flat 0.000 m3.** `_choose_cell()` treated `metrics_cell_m` as a
   hard floor — coarsen only, never refine. Right for a 250 m hull, wrong for a 2 m starter part:
   the cavity is the region `sdf < -hull_thickness`, so a 0.5 m cell cannot resolve a 0.15 m
   shell and every sample centre missed it. Area and weight were correct at the same time, so it
   read as a measurement rather than a resolution failure. The shell now sets a resolution floor
   (half the thickness), still subject to the sample budget. Volume reads 5.133 m3 at cell 0.075,
   and area improved 22.333 -> 24.172 m2 against an analytic 24.97.
3. **The cost gauge printed `141.943 / -1.000`.** `-1` is the documented "unbounded" sentinel
   (JSON has no Infinity literal) and was being rendered through `format_number()`, so it read as
   a cap of minus one. Now `UNCAPPED`.
4. **The ship was invisible** — see FOLLOWUPS F7. Shaded materials render black in the 3D
   SubViewport. Root cause NOT found; ruled out mesh, normals, visibility, world, viewport,
   camera aim, framing, light presence/energy/cull mask, environment config, and the palette
   shader's colour matching, each verified in-engine. Workaround: unshaded solids with
   `SHADED_WIRE` as the default mode so the wireframe carries the form. Recorded as a workaround,
   not a fix, because Phase 2 will want shading and will hit this again.

**A wrapper miss worth recording.** While wrapping long lines I introduced a `%`-vs-`+`
precedence bug (`%` binds tighter, so `"...literal..." % args` formatted a string with no
placeholders). The validator threw `String formatting error`, printed its own PASSED banner, and
`ship_run.ps1` reported success — AGENTS §8a's exact failure mode, one layer in. Fixed the five
sites, and added an ANCHORED `^ERROR:` to the wrapper's patterns: the engine logs runtime errors
at column 0 while the tools indent their own findings, so the anchor catches the engine without
failing every run that legitimately reports data problems.

Also: `.gdlintrc` gained `max-public-methods: 30` with its reasoning; `_matches_type`/`_type_name`
were split via a new `_is_json_type()` so both have a single exit rather than suppressing the
rule; `HullBake` now propagates `dims`.

**Still unverified: everything interactive.** Nothing has been clicked. Placement, drag-on-surface
to numeric binding, snapping, undo/redo, mirror, components, joint authoring, the bake button and
the diegetic host have never been exercised by a human or a driver. The screenshot proves the
console draws and the numbers are live; it proves nothing about behaviour under input.

## [2026-08-31] Rendering root causes, three-axis part orientation (ADR 0004), and the dead panels

Prompted by two reports: "this cube isnt even rendering entirely, thats besides not being shaded
revealing depth at all", and, from the round before, "iv been sauing 'rotation in 3d space'
'rotation in all 3 axises with z aligned to the placement normal'".

### The cube. Three separate bugs, all found by measurement, none by reading code.

Method that finally worked: render, read the PNG back, and compare colour histograms against what
the palette says should be on screen. Every previous "verification" of this looked at a frame and
agreed with itself.

1. **The palette quantizer was not doing a nearest-colour search.** Painted a strip of known
   swatches under `shaders/palette_post.gdshader` and read them back: every colour that WAS a
   palette entry mapped to itself, and every colour that was not - including `#ffffff` and
   `#808080` - mapped to `#081216`, the background. The branchless `step()`/`mix()` selection loop
   was the cause; the plain `if (d < best_d)` loop that replaced it gives `#ffffff -> #daf1e0`,
   `#808080 -> #277c79`, `#ba8936 -> #e4a944`. This was not only a 3D bug: every antialiased glyph
   edge in the whole console was being erased to the background, which is a large part of why the
   type read badly.

2. **Shading by multiplying an albedo cannot survive a 16-entry LUT.** The two shaded bands of a
   selected amber part measured as `#9f752d` and `#ba8936`; the quantizer put one on the warning
   RED and the other on the background, so a box rendered as one lit face with no sides.
   `part_faceted.gdshader` now picks a LUT ENTRY per band from `data/palette.json`'s new `"ramps"`
   section, so every shaded face is already an exact palette colour and the quantizer is a no-op
   on parts. Indices 3, 7 and 11 became a WARM ramp (`#4d3311`, `#8a5f22`, `#bd8734`) so the
   selection amber at 14 finally has something to shade into; the cool ramp keeps 11 steps.

3. **Writing `ALPHA` made parts transparent, so they stopped writing depth.** Even a constant
   `ALPHA = 1.0` moves a spatial material onto the transparent pipeline. The box rendered as a
   hollow shell - interior walls and the orbit rings visible straight through the front faces. The
   write is gone and documented in place.

Plus a fourth, found while fixing 2: a bare `vec3` uniform carries no `source_color` hint, so the
sRGB ramp was consumed as LINEAR and gamma-encoded on output. Predicted `#4d3311/#8a5f22/#bd8734/
#e4a944` would display as `#bd8734/#e4a944/#e4a944/#daf1e0` - two bands collapsing onto one entry
and the brightest landing on pale mint - and the render matched exactly. `_apply_ramp` now uploads
`Color.srgb_to_linear()`.

The distance cue the report asked for ("farther back is darker and closer is lighter") is in,
measured PER PART rather than per fragment: per fragment it drew curved iso-distance contours
across flat faces and a cube came out looking bowed.

### `tools/ship_visual_check.gd` - a screenshot gate that asserts

`ship_shot.gd` proves a frame was drawn and nothing else, which is exactly how a box rendered as a
single flat quad in three consecutive "verified" screenshots. The new tool builds a four-family
demo ship, renders all four display modes, and FAILS on: fewer than three ramp bands on screen
(the shading collapsed), any 3D pixel that is not a palette entry (a colour the quantizer is free
to move), two modes producing identical frames (a toggle that is not wired), and implausible ink
coverage (nothing rendered / camera inside the hull).

`tools/ship_run.ps1` gained `-ToolArgs`. Without it there was no way to pass a scene or a display
mode through the wrapper, so **every screenshot ever taken in this repo bypassed the runtime-error
gate** - the one check that looks at pixels was the one running outside the harness.

### ADR 0004 - three-axis part orientation

`ShipPart.roll: float` -> `ShipPart.rot: Vector3`, degrees in a mount frame whose **+Z is the
placement normal**. `rot.z` is the old spin-on-the-surface dial; `rot.x`/`rot.y` tilt off it.
Ruleset `1.0.0` -> `2.0.0`.

The mount frame is `F = Basis(tangent x N, tangent, N)` and the child basis is
`F * Rz(rot.z) * Ry(rot.y) * Rx(rot.x + 90)`. The fixed +90 about X is load-bearing: every family
is authored Y-major (cone apex +Y, cylinder along Y), so pinning the child's GEOMETRIC +Z to the
normal would lay every cone and spar flat against the plating. Verified numerically over 2000
random normals and rolls that at `rot == (0, 0, roll)` the new basis is the old one to 5e-15, so
**no existing ship moves** - the version bump is for the canonical form only, and a legacy scalar
`roll` still loads into `rot.z`.

Consequence worth naming: the three rotation rings on the selection gizmo were all driving the
same number, which is why the advanced handles felt inert however they were dragged.
`rotate_selected()` takes an axis now.

### Clicking a part selected nothing

`_do_pick()` read `_viewport.world_3d` - the explicit OVERRIDE slot, which is null under
`own_world_3d = true`. It returned before it raycast. This is the same bug already found and
documented at length on `_space_state()`; the fix there was never applied to the second call site,
and it fails silently for the same reason: an early return on a null world is indistinguishable
from "the ray hit nothing".

### Things that were built, complete, and unreachable

- **PaintPanel** (765 lines) had no slot in `PANEL_CANDIDATES` and no click routing. Both wired;
  `PaintMode.click()` returns false when inactive, so BUILD behaviour is unchanged by construction.
- **SaveDialog** (633 lines, name/description/tags plus the `min_parts_to_save` gate) was never
  called - SAVE opened a bare filename prompt. Wired, with the prompt kept as a fallback.

### Asked for, and missing until now

- **The nine part categories are gone** (UI, `families.json`, the schema, and API_CONTRACT_SPORE
  section 9 marked RETIRED). Author, verbatim: "they are simple shapes and need no classification.
  the player classifies this later in the game". Six procedural primitives do not need a filing
  system, and the tabs were assigning roles Phase 1 cannot express.
- **UI scale.** Font metrics were raw pixel constants authored for the 1280x800 device, so a
  maximised 2560-wide window rendered 10px labels. `ShipTheme.ui_scale` now scales fonts, layout
  minimums, stylebox padding and theme spacing together, driven from the console's OWN rect (never
  DisplayServer - SPEC section 10 holds).
- **On-screen key legend**, bottom-left of the 3D view, rewritten as the state changes. It lives
  INSIDE the inner SubViewport: a `SubViewportContainer` overrides its children's rects, so anchors
  are ignored there and the first attempt vanished entirely.
- **Axis-lock hotkeys** (X / Y / Z, Escape clears) pinning any rotation gesture to one mount-frame
  axis. Spore has no such thing; it is the SketchUp affordance asked for by name, and it layers on
  the Spore grammar cleanly because Spore spends Ctrl/Shift on drag constraint.
- **MIRROR X / Y / Z / OFF** is back in the inspector, setting `ShipDoc.symmetry_plane`. The row
  retired on 2026-08-31 was the per-part `ShipMirror` command, and removing it took the axis choice
  with it - but the axis choice was in the brief from the first message and was never the part that
  was wrong.

### Verified

`--import` clean; `ship_selfcheck` PASSED (hash stable, sensitivity confirmed); `ship_validate_data`
PASSED, 0 warnings; gdUnit4 **147/147**, 0 errors, 0 orphans (was 142 - five new tests cover the
mount frame's +Z, `rot == 0` still standing a part up, the two new axes tilting, the three axes
being independent, and the legacy `roll` load); `ship_visual_check` PASSED across all four display
modes. gdparse/gdlint clean.

**Still unverified: everything interactive.** Every fix above was driven in code or read off a
pixel. Nobody has dragged a part onto a hull, spun a rotation ring, held X to lock an axis, or
clicked BUILD/PAINT. The visual gate proves the console draws what the palette says it should; it
proves nothing about behaviour under a real pointer.

## [2026-08-31b] Symmetry never mirrored anything; paint removed from scope; components placeable

Six reports, five of them defects.

### 1. Nothing in the codebase had ever generated a mirrored twin

> "also i press mirror buttons and it appears nothing mirrors"

Exactly right, and worse than a UI bug. `ShipSymmetry` could say whether a part *should* have a
twin, `ShipComplexity` **charged double for it**, and `ShipAttach.resolve_all()` only ever emitted
transforms for STORED parts - so symmetry was a tax with nothing to show for it, on every ship,
since the model was introduced. `grep` for a consumer of `twin_id()` returned one hit, in paint.

Twins are generated in `resolve_all_from_shapes()`, which is the single choke point every
consumer already goes through, so the scene builder, the SDF union and the bake all picked them up
without changes. They are DERIVED, never stored: keyed `"<source>~m"`, reflected with
`ShipMirror.reflect()` on the finished ship-space transform (exact for any orientation), and each
part reflected independently - reflection commutes with composition, so no subtree walk is needed
and a child of an on-plane parent still mirrors correctly. `resolve_shapes()` aliases the source's
shape onto the twin id. Clicking a twin selects its source (`ShipBuilder.select_part`), or the
selection would contain an id nothing can resolve.

### 2. `_islands_of` probed part boxes on a grid spanning the whole ship

Turning symmetry on doubled the scene width, which made the fixed 10-step probe grid coarser,
which made every part vanish from its own box - a 7-part ship reported as 7 separate islands.
Resolution-dependent geometry in a connectivity test is a bug waiting for a big enough ship.
`ShipSdf.part_aabb()` now hands back the exact box `build()` already computed from the part's own
transform; `ISLAND_BOX_STEPS` is retired.

### 3. Tilted parts did not stay connected

> "also things are hovering they must be connected"

`offset == 0` means flush, and the flush distance was measured along the child's fixed local -Y -
correct until ADR 0004 let parts tilt. Measured across the catalogue at 45 degrees: capsule_tank
floated **0.31 m** clear, torus_ring buried itself **0.81 m**. `ShipAttach.support_inset()` traces
the child's own field along the actual contact direction instead, against a rib/scallop-free copy
so a ribbed part still seats on its mean surface. Re-measured: **nothing floats at any tilt.**

Two traps found on the way. The trace can MISS - a torus has its origin in its own hole, so a ray
down -Y never meets the ring, and the tracer's run-off distance seated it 3.5 m out; a miss now
falls back to the fixed extent. And the first version of the *measurement* sampled the +/-Y faces
of the child's AABB along a diagonal line rather than a grid, which is precisely where a part
contacts, so it reported gaps that were not there. Gated now by
`test_no_family_floats_off_its_parent_at_any_tilt` - six families x five tilts.

Known limitation, recorded as FOLLOWUPS F12: a laterally-spread part still lifts off a CONVEX
parent (torus on a 5 m sphere, 0.20 m). Normal-offset seating cannot express that; a real contact
solve would be a root-find per part inside `resolve_all` and would enter the hash.

### 4. Paint is out of scope

> "what is this paint stuff... thats not in the scope... i have an AI texturing pipeline. we are
> only building geometry here."

Mounted it one day, unmounted it the next - my scope error, not a discovery. `PaintSlot` is gone
from `PANEL_CANDIDATES` and no click reaches `PaintMode`. The files stay on disk and still
validate: `ShipPart.paint` is reserved in the data model (SPEC section 5.1) and the panel is a
usable dev tool for auditing palette colours, which is the one use the author allowed for. The
seam in `ShipView3D.set_paint_mode()` is kept so re-mounting is two lines.

### 5. Components could be created and never placed

> "selecting 2 or more things and pressing make comp does not add it to its own section of
> addable shapes above (also doesnt let player name it)"

Both true. `ShipComponents.instantiate()` had no caller anywhere in the harness, and MAKE COMP
derived a label from whichever part happened to be selected.

- MAKE COMP prompts for a name (`ShipBuilder.prompt()`, previously private).
- The palette grew a COMPONENTS list under the shape grid, refreshed from `doc.components` on
  every doc change so MAKE COMP / MAKE UNIQUE / undo all keep it honest.
- Clicking one arms a real placement ghost: `ShipPlacement.begin()` takes a `kind`, and a
  component instance resolves its ghost shape through its definition's root part rather than
  through `ShapeGen`, which has no such family and would have returned an invisible ghost.

Driven end to end in `scratch/diag_component.gd`: name stored, palette lists "PORT NACELLE  (2)",
ghost resolves, commit lands a `component_instance` pointing at the right definition.

### 6. Handles were drawn only while Tab was held

> "also i see no handles that stretch and pull offset and rotate etc etc etc"

Accurate. Spore gates the rings and morph handles behind holding Tab, and cloning that literally
meant a selected part showed one plain ball. Everything is drawn now - ball, three rotation rings,
six stretch ticks - and **Tab declutters** instead. A new OFFSET handle (a stalk along the mount
axis) was added because `offset` had no handle at all: it was reachable only by typing a number or
by holding Ctrl mid-placement.

### Also: Ctrl now re-centres the orbit

> "when selecting an object while holding ctrl it should make that object the center of orbit
> attention"

Ctrl was a second additive-select modifier, i.e. a duplicate of Shift. Shift extends the
selection; Ctrl+click re-centres the orbit on what was clicked, keeping distance and angles.

### And one the runtime-error gate caught

`ShipView3D._on_ghost_moved` still had the pre-ADR-0004 `roll: float` signature, so the
`ghost_moved` connection failed on every emit. Invisible in normal use - the ghost simply did not
refresh from that path - and it only surfaced because `ship_run.ps1` fails a run on a runtime
error regardless of exit code.

### Verified

`--import` clean; `ship_selfcheck` PASSED; `ship_validate_data` PASSED, 0 warnings; gdUnit4
**151/151**, 0 errors, 0 orphans (was 147: +1 contact gate, +3 twin generation/suppression);
`ship_visual_check` PASSED across all four modes, with twins visible in the frame. gdlint clean
across `core/`, `harness/`, `tools/`, `tests/`.

**Still unverified: everything interactive.** The component flow and the contact geometry were
driven in code; the handles, the axis lock and Ctrl-to-focus have been rendered but never
dragged.

## [2026-08-31c] Mirroring did not reach the screen on the edit path; my previous verification was wrong

> "i dont understand, i have x selected as a mirror. i add a piece to the base cube and only 1
> piece is added... didnt you make a test script and verify with screen shots or do you keep
> skipping that step?"

Fair, and the verification was the actual failure. The previous entry claimed twins render on the
strength of a screenshot of the demo ship - four DIFFERENT families placed at 0/90/180/270
degrees, i.e. parts on opposite sides of the hull BY CONSTRUCTION. It looked mirrored. Nothing
counted anything. The unit test added alongside it asserts the twin TRANSFORM exists and says
nothing about a mesh.

Reproducing the reported sequence exactly (`scratch/diag_mirror.gd`) gave the answer in one run.

### The bug: `refresh_parts()` never carried the twin

`ShipBuilder._commit()` takes an incremental path for every ordinary edit - it hands
`ShipSceneBuilder.refresh_parts()` the ids the caller says changed. A twin is DERIVED, so its
`"<id>~m"` is never in anyone's changed-id list, and `refresh_parts` only synced the ids it was
given. Measured, moving a part off the mirror plane:

```
resolve_all keys : 3  ["p_0001", "p_0002", "p_0002~m"]     <- transform exists
scene visuals    : 2  ["p_0001", "p_0002"]                 <- mesh does not
```

A twin therefore appeared only when something else happened to force a full `sync()` - which is
what my earlier diagnostic did by accident, and why it looked fine. `refresh_parts` now syncs each
id AND its twin, creating or DESTROYING as the resolve result dictates: dragging a part back onto
the centre line has to remove the twin, and a stale mirrored mesh is the same bug wearing the
other hat.

### The other half: a part added to the base cube lands ON the mirror plane

`yaw = 0, pitch = 0` is the parent's local +Z, so a fresh part sits at `origin (0, 0, 2.82)` -
`|x| = 0.0000` against a `symmetry_plane_epsilon` of `0.01`. `generates_twin()` correctly says no:
a twin there would coincide with the original. So the FIRST part anyone adds never mirrors, which
is exactly the report, and the rule is right.

What was missing is any way to know that. Two fixes:

- **The inspector was lying.** It reported every symmetric part as "MIRRORED ACROSS X - COSTS n,
  DOUBLED", including one sitting on the centre line with no twin. It now says "ON THE X MIRROR
  PLANE - NO TWIN. MOVE IT OFF THE CENTRE LINE TO MIRROR.", and it decides by asking the attach
  pass whether a twin id was actually emitted rather than re-deriving the test.
- **The ghost now shows its mirrored half** while dragging, so crossing the centre line visibly
  turns mirroring on before the click. Computed in `ShipSceneBuilder`, which already holds the doc
  and config, rather than as a new accessor on `ShipPlacement` - that class is already at the
  public-method budget `.gdlintrc` sets, and that file's own comment says a second wide class means
  fix the facade, not raise the number.

### The gate that should have existed

`tools/ship_visual_check.gd` now asserts that every twin TRANSFORM has a corresponding mesh in the
scene, and fails the run if the demo ship generates no twin at all (a ship with everything on the
centre line proves nothing about mirroring). Output: `twins: 2 expected, 2 drawn`.

### Verified

`scratch/diag_mirror.gd` A/B, with the frames stacked and looked at: default placement gives ONE
capsule on the centre line; the same part moved off-plane gives TWO - the amber selected original
and its teal mirrored twin. `--import` clean; gdUnit4 151/151; selfcheck PASSED; validator PASSED,
0 warnings; visual check PASSED with the new twin assertion; gdlint clean.

**Still unverified: everything interactive.** All of the above was driven in code. Nobody has
dragged a part across the centre line and watched the second ghost appear.

## [2026-08-31d] The rotation rings were drawn on the wrong axes

> "i see 3 circles that im guessing are handles, but instead of rotating the connected piece
> around each of 3 axis, they ALL spin the part around its placement vector"

Measured before touching anything (`scratch/diag_handles.gd`), by comparing the axis each ring is
DRAWN around against the axis the part actually turns about when that ring is driven:

```
RING_X : drawn about (0,-1,0)  turns about (0,-1,0)   MATCHES
RING_Y : drawn about (1,0,0)   turns about (0,0,-1)   MISMATCH
RING_Z : drawn about (0,0,1)   turns about (1,0,0)    MISMATCH
```

Rings were drawn about the part's own local X/Y/Z; `rot.x/y/z` turn the part about the MOUNT
frame's axes. Those differ by the fixed 90-degree alignment term that stands a Y-major primitive
up along the surface normal (ADR 0004), so two of the three circles rotated the part about
something other than the circle you grabbed.

`ShipHandles.ring_axis_local(handle, rot)` derives the axis each component really turns about,
expressed in the part's local frame. Because the composition is intrinsic (`Rz * Ry * Rx'`) each
component turns about a different world axis, and pushing them back through the part basis
collapses to:

```
X : e_x                        Y : Rx'^-1 * e_y                Z : Rx'^-1 * Ry^-1 * e_z
```

Both the drawn loop and the hit test call it, so they cannot drift apart again. Re-measured, from
rest and from two already-rotated poses, all three rings report |dot| = 1.000.

Gated by `test_every_rotation_ring_turns_about_the_axis_it_is_drawn_around` - pure basis maths, no
scene or camera, sitting next to the composition it constrains.

### Also measured, and NOT a bug

The offset and stretch handles are grabbable and do work: driving them moved `offset` 0.000 ->
0.250 and `scale` per axis. The author cannot see them because they are drawn as tiny crosses.
That is a legibility problem, and the ask - "all handles should be visible as they are in spore
tiny 3d arrows that you grab and pull" - is queued as its own piece of work, not closed here.

### Verified

gdUnit4 **152/152**; selfcheck PASSED; visual check PASSED (twins 2 expected, 2 drawn); gdlint
clean.

## [2026-08-31e] The handle set was modal, the flag lived in three places, and the ball ate every grab

> "tab doesnt show any usable handles. cant click them and if i hold tab they disapear."
> "grabing the rotation rings still only rotate the part about its placement vector"

Both true, and the previous entry's fix was real but unreachable. The ring-axis maths was right;
the app never used it, because a grab never reached a ring.

### Root cause: one flag, three owners, different defaults

`ShipView3D._advanced = true`, `ShipSceneBuilder._advanced_handles = true`,
`ShipPlacement._advanced = **false**`. Nothing reconciled them at init, and
`ShipPlacement.set_advanced_handles()` re-broadcast its own copy through `handles_changed`, which
`ShipView3D` fed straight back into the scene builder. On top of that,
`NOTIFICATION_FOCUS_EXIT` called `_set_advanced(false)` - so clicking a palette cell, or any panel
at all, silently dropped a selected part to the ball-only gizmo.

With the set off, `hit_test()` returns `Handle.BALL_ROTATE`, and `axis_for_handle()` maps the ball
to `AXIS_Z` - the mount normal. **So every grab spun the part about its placement vector, from
three circles that were the ball's great circles rather than the rings.** That is the report,
exactly, and the Tab inversion added the previous round made it worse: pressing Tab turned the
handles OFF.

### Fix: no modal state, no ball

The `advanced` flag is gone from all three classes, along with `handles_changed`,
`set_advanced_handles`, the Tab binding and the focus-exit reset. Every handle - three rings, six
stretch ticks, one offset stalk - is always drawn and always grabbable. The ball's three great
circles are gone too: they were three more concentric circles that swallowed every grab.
`Handle.BALL_ROTATE` keeps its enum number (the contract pins it) and is never produced.

### Why the test did not catch it, and what replaces it

`test_every_rotation_ring_turns_about_the_axis_it_is_drawn_around` passed throughout. It calls
`ShipHandles.hit_test(..., advanced: true, ...)` - **the flag supplied by hand**. It was asserting
about a code path the application does not take.

`tools/ship_visual_check.gd` now drives the gizmo through `ShipView3D`'s OWN press and drag
handlers, after deliberately firing a focus-exit round trip first. It computes a pixel on each
drawn handle, hands it to `_try_begin_handle_drag`, drags with `_drive_handle`, and asserts:
every ring turns the part about the circle that was grabbed, and every point handle both grabs and
moves the state it owns. Output: `gizmo: 10 handles driven through the real press/drag path`.

One more measurement error worth recording: the first version of that check read the preview
TRANSFORM to decide whether a stretch handle did anything, and reported the X and Z handles as
dead. A sideways stretch moves neither the origin nor the (rigid) preview basis - scale lives in
the ResolvedShape. Reading `_part_scale` instead shows all six moving their own axis.

### Verified

Ring axes, driven through the real path from a rotated pose after a focus-exit round trip:
`|dot| = 1.000` on all three. Offset `+0.500 m`. Six stretch handles each scaling their own axis
`1.0 -> 1.2` / `1.0 -> 0.8`. gdUnit4 152/152; selfcheck PASSED; validator PASSED, 0 warnings;
visual check PASSED (twins 2/2, gizmo 10 handles); gdlint clean.

**Still outstanding from the same report, and NOT done:** handles as pullable 3D arrows rather
than crosses; handles on the PARENT for the placement vector; attached-pivot vs floating rotation
modes; numpad and arrow-key rotation snapping; the cylinder-with-two-radii primitive rework that
subsumes cone and capsule; 5 m default root; max bounding box display; rooms and hatch linkage;
tutorial.

## [2026-09-01] Could not reproduce the vanish; the cylinder was hiding behind its own icon

### Rotation: confirmed fixed, by the author and by the gate

> "rotation is now correct."

### The vanishing part: NOT REPRODUCED, and not guessed at

> "after some rotations it just disappears. and after some offsets it disappears."

Drove 14 rotation drags and 14 offset drags through ShipView3D's own press/drag/release path
(`scratch/diag_vanish.gd`), framing the camera once at the start so a part that flew out of shot
would stay out of shot. After every release: still in the document, still has a visual, placement
not left live, nothing suppressed, gate valid throughout. Offset ran to 7.00 m and rotation through
a full 360 degrees.

Then measured what a player would actually see - the fraction of the frame wearing the selected
part's warm ramp, which reads ~zero whether the part flew off screen, shrank to nothing, or buried
itself in its parent. It never dropped below **1.13%** of the view.

So the failure is real but its trigger is not in that path, and guessing at a fix would be the
third time this month a "fix" shipped for something that was never measured. Recorded as
FOLLOWUPS F13 with the specific questions that would locate it.

**A measurement bug found on the way, worth recording.** The first version of that sweep ran all
28 steps inside ONE `_process()` call and read the viewport texture after each. The SubViewport had
not re-rendered, so every read returned the same frame: the pixel count came back identical to
three decimal places across a sweep that moved the part seven metres. A number that cannot change
is not evidence. The sweep is frame-driven now, one step per four frames, and the readings vary
between 1.13% and 2.03% as they should.

### "i dont see a cylinder add just the modified cylinder"

The plain cylinder was in the palette the whole time, wearing the wrong face. Its glyph was a
rectangle with two horizontal lines across it; at a 40 px cell, through the 16-colour quantizer,
that is indistinguishable from the capsule beside it. The cone was a flat triangle - the only
glyph in the set with no rim, so it read as a 2D wedge rather than a solid of revolution.

Both now draw as solids of revolution: an elliptical top rim, the front half of the bottom rim,
and straight sides. `_draw_closed()` and `_cone_points()` went with the change rather than being
left behind as dead code.

This does NOT answer the real request - "the capsule shouldnt be there, a cylinder is more
appropriate with capsule end options ... cone is also a cylinder with one end radius 0". That is a
primitive-model rework (one parametric cylinder with two end radii and an end-rounding term
subsuming cone and capsule), which needs an ADR and a ruleset bump, and is the next piece of work.

### Verified

gdUnit4 152/152; selfcheck PASSED; validator PASSED, 0 warnings; visual check PASSED (twins 2/2,
gizmo 10 handles driven through the real path); gdlint clean.

## [2026-09-01] The primitive rework, the start choice, the stock templates, rooms, and the shell

Everything below traces to a sentence the author wrote. Where one turned out to be two requests
wearing one name, both halves are recorded.

### One primitive instead of three (ADR 0005, ruleset 2.0.0 -> 3.0.0)

> "the capsule shouldnt be there, a cylinder is more appropriate with capsule end options via round
> edge or fillet edge shapes on primitives. - cone is also a cylinder with oine end radius 0 and one
> larger.. remember these are primitives'"

`SdfPrims` gained `capped_cone()` and `rounded_cone()`. A `ResolvedShape` CYLINDER now carries
`radius_b` (the +Y end radius) and `end_round` (how far the end discs are rounded), exposed to the
player as the `end_radius` and `end_round` params on `cylinder_spar`. Every shape the three
families produced is a point in that one parameter space; `cone_nose` and `capsule_tank` are gone
from the pack. `Base.CONE` and `Base.CAPSULE` stay in the enum (API_CONTRACT pins them) and still
evaluate, so an old document loads.

Three decisions inside it each had a wrong answer that looked right, all written up in the ADR:
`radius_b` defaults NEGATIVE meaning "match size.x" (a default of 0 would have turned every
hand-built cylinder into a spike, silently); `end_round` measures against the WIDER end (against
the narrower one a cone can never be rounded at all, and "a cone with a rounded nose" is one of the
shapes this exists to produce); and `end_round` is a separate field from `round_r` because rounding
an END must not GROW the part.

`cylinder_spar` also lost its non-zero `round` default - it starts as a crisp tube now - and its
`base_size` is a slim `[0.5, 1.5]` rather than a 2 m x 2 m drum, which is both the tunnel scale the
templates want and the silhouette the word "spar" promises.

The preview mesh for a CYLINDER is LATHED now rather than a `CylinderMesh`, because no Godot
primitive spans that family and `CylinderMesh` cannot round an end at all. `round_r` folds into it
exactly rather than being approximated: inflating a rounded cone by rho is exactly a rounded cone
with all four parameters raised by rho.

Measured through the real console, six configurations, all six distinct on screen and each one's
own +Y pole exactly on its surface: tube 47886 px, frustum 37191, cone 29776, capsule 42928,
rounded nose 37504, bell mouth 55644.

### The player picks the starting module

> "it auto started with a block again instead of letting player choose starting choice"

It was founding every ship on `family_ids()[0]`, so the starting primitive was decided by key order
in `families.json`. NEW now raises `ShipStartDialog` and nothing exists until a choice is made. The
root is scaled so its widest bounding-box axis is `ShipConfig.root_span_m` (5 m, a new tuning
lever) - without that, founding on a sphere gave a 2 m ship and founding on a torus a 4 m one.

The first version of that dialog rendered in the top-left corner with no dim behind it.
`set_anchors_preset()` PRESERVES a control's current rect by recomputing its offsets, so a node
anchored after it was already parented at zero size stays at zero size. Diagnosed by printing the
rect - `StartLayer: rect=[P: (0,0), S: (0,0)] anchors=(0,0,1,1)` - not by staring at the
screenshot. `set_anchors_and_offsets_preset()` is the fix.

### Stock templates: atoms and molecules

> "id like some pre configured procedural ships made, i want them to model atoms and inhearit atoms
> names ... a hatch between each hallway/tunnel and room and room to room connection"

`data/templates.json` plus `core/templates/ship_templates.gd`. Sixteen elements and six molecules,
22 templates. An element is a core room plus one branch per direction of that element's real VSEPR
geometry - carbon is four berths at 109.5 degrees, water's oxygen is two at 104.5 - so walking the
periodic list really is walking different ways to arrange rooms around a centre. A molecule wires
several element cores together, each child hanging off a named slot of its parent's arrangement.

The chain is ROOM -> TUNNEL -> ROOM, never room -> tunnel and room -> room in parallel: a branch
would otherwise cost the core two children, and an eight-branch core would need sixteen against a
family cap of eight.

Nothing in the pack fixes a size. Room diameter, tunnel bore and tunnel length are three new tuning
levers, defaulted to the author's own numbers - "skinny tunnels like 3ft and the rooms like 9f (but
1m and 3m really)". Room shape and hallway shape are chosen in the chooser, which is the other half
of "controllable parameters are what shape for rooms, what shape for hallways/tunnels".

All 22 built and measured: exact bores, exact tunnel lengths, exact room spans, a hatched joint at
every connection (two per tunnel), and a worst room-to-tunnel gap of 0.000 m. Driven again with the
four levers turned - box rooms, 2 m bore, 6 m tunnels, 5 m rooms - and again through the chooser's
own buttons, because calling the builder directly proves the builder works and proves nothing about
whether a player can reach it.

### Rooms and hatch linkage

> "id like to be able to select a component and classify it as a single room, name it. i'd then like
> to be able to select 2 rooms and toggle a hatch linkage"

MAKE ROOM and LINK HATCH in the tree panel. A room is a PART with `role == "room"` and a name, not
a new document field: `ShipPart.role` already existed, already round-trips and is already part of
the canonical form, so classifying a part as a room needs no new schema and no ruleset bump. LINK
HATCH toggles - pressing it again takes the hatch out - and refuses, out loud, on a part that has
not been named a room.

### The keyboard the brief asked for

> "arrow keys to snap across parent placement vectors. - num pad, 7-9 controls rotation about x,
> 4-6 rotation snaps about y, 1-3 rotation about z ... 0 toggles z reference from placement vector
> to surface normal vector and snaps the part to the surface normal."

Arrows walk the selection across its parent's SnapTargets (left/right one, up/down a row of eight).
Numpad 7/8/9, 4/5/6, 1/2/3 turn about mount X/Y/Z with the middle key zeroing that axis, stepping
by the document's own snap increment and repeating when held; Shift is a coarse detent. Numpad 0
aims the part at the surface normal or at the placement vector and toggles between them, preserving
`rot.z`. The aim has a closed form (`ShipAttach.rot_xy_for_direction`), derived in the docstring
rather than fitted - measured aim error against the placement vector: 0.0000 degrees.

Keyboard scaling moved from UP/DOWN to PAGE UP / PAGE DOWN to free the arrows. The legend says so.

### Handles: arrows, the parent side, and two pivot modes

> "all handles should be visible as they are in spore tiny 3d arrows that you grab and pull"
> "i dont see the handles for the placement vector on the parent"
> "we also need attached pivot, and floating connection"

The six stretch handles and the offset handle are 3D arrows now, not crosses - a cross marks a
spot, an arrow says which way to pull. A new PLACEMENT handle draws from the PARENT's origin out to
the part and, when grabbed, slides the part over its parent through the same solve an ordinary drag
uses. P toggles FLOATING (rings spin the part in place) against ATTACHED (rings swing the placement
vector, so the part travels across its parent). Both are gated: FLOATING moves rot 45.000 and the
placement 0.000; ATTACHED moves rot 0.000 and the placement 45.000.

### The max bounding box, and a tutorial

> "i dont see the max bounding box" / "theres no game style tutorial"

The bbox cage is eight corner brackets at `ShipConfig.max_bbox_m`, turning to the warning role when
the ship reaches outside it. Gated against the config value, not against "a node exists" - it
measures (250, 120, 250) m and the budget is (250, 120, 250) m. Worth saying plainly: at that
budget the cage sits far outside a 5 m hull, which is what the shipped numbers mean. The author has
already said the maxima are for later.

`ShipTutorial` is eight cards that clear themselves when the DOCUMENT shows the step was done - a
part appeared, a rotation is non-zero, a hatch exists. NEXT is disabled until then, so it cannot get
ahead of the player, and it never writes the document: a tutorial that builds the ship for you is a
cutscene. HELP re-opens it at the first unfinished step.

### The hull has two sides now (ADR 0006)

> "i certainly want to give it a thickness and an interior mesh, trach its volum and mass etc"

`HullBake` extracts a second isosurface at `iso - hull_thickness_m`, reverses its winding AND its
normals, and welds it to the outer surface. The report gained `interior_mesh`, `interior_tris`,
`interior_volume_m3`, `shell_volume_m3` and `shell_mass_kg`. `volume_m3` deliberately keeps its old
meaning - the OUTER volume, which is what every budget reads.

FOLLOWUPS F10 had this open because SPEC section 7's "the Phase 1 bake produces the all-open studio
hull with no walls" had been read as covering the hull's own skin. It does not: it is about JOINT
partitions, which remain unbuilt as designed. The bake had been padding its grid by the thickness
for exactly this pass the whole time.

### Two measurement mistakes made and corrected, both mine

1. `diag_primitives` read the viewport in the same `_process()` that mutated the document, so every
   number was one row stale and two identical configurations looked different. The same class of
   error as the one the previous entry documents, made one function lower down.
2. The visual gate probed ONE pixel per rotation ring and reported "ring 3 returned handle 5" as a
   gizmo fault. It was the probe: that pixel happened to sit on a morph tick, which legitimately
   wins. The gate now walks the whole ring and requires at least a fifth of its visible circle to
   answer - which is a real usability property, and something the single-pixel probe could not see
   either way.

### Still open, and named rather than buried

F12 (a laterally-spread part lifts 0.20 m off a strongly convex parent) stays open with the two
cheap fixes it proposed now worked through and shown to be wrong - recorded so nobody re-derives
them. F13 (the vanishing part) is still not reproduced and still needs four details from the
author. F14 and F15 record the additive extensions made to the frozen contract.

### Verified

gdUnit4 165/165; selfcheck PASSED; data validator PASSED, 0 warnings; visual check PASSED (4 modes,
bbox cage matches the budget, both pivot modes separate, 11 handles driven through the real
press/drag path); gdlint clean across core/harness/tools/tests. Diagnostics: primitives PASSED,
templates PASSED (22/22), rooms PASSED, keys PASSED.

Still the human's to check: open `harness/dev_host.tscn` and run it.

### Addendum, same day: skew (ADR 0007, ruleset 3.0.0 -> 4.0.0)

The fourth morph verb, and the last item left in the original brief's list of what Spore's
post-placement handles do. `SdfOps.shear()` slides the XZ plane in proportion to Y about the part's
CENTRE - leaning about the foot would drag every child near the +Y end through the air on what is
supposed to be a shape edit. Exposed as `skew_x` / `skew_z` params on all four families, driven by
the top and bottom morph arrows pushed sideways, with the camera deciding which local axis a
sideways push means so the part always leans toward the pointer.

The interesting part is that it had to be INSERTED into the op order. SPEC section 4 has always
said an op appends and never inserts - but a domain warp cannot append, because everything after
the base operates on a distance rather than a point. It goes last of the three warps, the SPEC now
carries that exception with the reasoning attached, and the insertion is only safe because at zero
the warp is the identity: asserted with `is_equal`, not `is_equal_approx`, across a sample grid on
a shape carrying taper AND twist.

Its Lipschitz cost is exact rather than padded - a shear is linear, so the largest singular value
of the inverse is `sqrt(1 + k*k/4) + k/2` in closed form. Underestimating a Lipschitz bound does
not make the tracer slightly wrong, it makes it tunnel through the part.

The preview reproduces it EXACTLY, the only warp of the three that does not have to be
approximated, because a shear is a matrix: `mesh_basis()` folds it into the instance basis beside
the scale as `Shear * Scale` - the order the SDF implies. `_scaled_convex()` became
`_transformed_convex()` with it, since a Vector3 cannot carry a lean and a sheared part's pick body
would otherwise have stayed upright while the part leaned out of it.

gdUnit4 169/169 after the change; everything else still green.

## [2026-09-02] The vanishing part, the embed, MAKE COMP, every part a room, and NEXT

One message from the author, five faults in it, all five measured before being called done:

> "undo brings it back. it happens with random rotation (try in every direction around all axises)
> and also when sinking a part into its parent. - also your default modles do not overlap enough,
> when attaching an object to a sphere surface obviously its at its tangent point and theres no
> real connection. ALL added parts must by default upon placement be deep enough such that there
> are no barely touching surfaces. - also when i selected multiple parts and press make component
> they all dissapear. - when trying to link my tunnel with my sphere it sys "tunnel isnt a room
> yet". each and every primitave should by default be a room.. i should be able to add a hatch
> between any 2 connected shapes.. not adding one obv keeps internal door, and combining multiple
> into the same room removes all internal walls making it a component and defining it as a single
> room. - also tutorial next btn doesnt work so i couldnt test."

### The vanishing part (F13, resolved)

"Undo brings it back" was the detail the previous entry asked for: it meant a DOCUMENT edit, and
the only edit a release makes on its own is `ShipPlacement.remove_if_dragged_off()` - the very
candidate the earlier diagnostic had ruled out, because that drive never let a release stray off
the parent's silhouette. Four things stacked to make an ordinary rotation delete a part: the
placement arrow won hit-test ties against the rings it crosses (`ship_handles.gd` - the rings are
tested first now); a gizmo release was treated as an ordinary drag and re-solved the ghost from
the pointer (`ship_view3d.gd` records `_release_may_remove` before the handle is cleared, and only
a plain surface drag may remove); the off-ship probe ignored the moving part, so the ray "missed"
whenever the pointer was over the part being dragged, which is most of the time
(`ShipPlacement._pointer_off_ship` tests the ship's bounds with the ghost included, and the
VERTICAL / HORIZONTAL modifier drags never count); and `remove_if_dragged_off()` deleted on any
collider miss, which is how sinking a part into its parent deleted it.

The gate that should have existed is a release-survival stage in `tools/ship_visual_check.gd`:
five releases driven through the real input path, verdict read frames later once the release has
landed. Placement-arrow drag, G-move released over the part's own body, Ctrl-drag sinking the
part, ring drag released off the silhouette - all KEPT; G-move released in empty space - GONE,
which is Spore's drag-off and the only one that should be.

### Every part starts sunk

`ShipAttach.default_offset()` seeds the offset of every new part - palette drop, `add_part()`,
the stock templates - so that its SOLE sits `attach_embed_m` (0.45 m, capped at half the part's
own height by `attach_embed_max_fraction`) inside its parent. Measured on the surfaces, not read
off the mount inset: `sole_points()` samples the lowest point of each column of the child's -Y
footprint, and the offset is bisected until the deepest one is the target depth inside the
parent's field. That is what seats a ring on a sphere by its rim rather than by its axis - an axis
measure calls a torus seated while its rim floats clear of the sphere curving away beneath it.
The attach model itself is untouched: `offset == 0` is still flush, the hash still consumes the
stored offset, and a player can still type 0. F12's 0.20 m torus gap is thereby mitigated at
placement and still open at flush; F16 records the two levers and two functions as additive to
the frozen contract. `tests/core/test_attach_embed.gd` gates the pairs.

### MAKE COMP no longer empties the screen

An instance resolved to its definition's root alone, and the scene builder, the SDF and the
budgets all walk the attach pass - so lifting three parts into a component drew one. The attach
pass now emits every inner part under `"<instance>/<inner>"` (`ShipAttach._expand_instance_shapes`,
nesting chains keys), hangs their transforms from the instance's own with the same attach maths
as the ship tree, twins them on the instance's terms, and `ShipComponents.expand()` reads those
entries back out - the contract's `expand()` returns exactly what it always did, from a different
source. `ShipMetrics.compute_cost()` now sums a definition's parts for each instance; the
`_max_blend` walk does not need to, because an expanded part inherits its instance's blend
(`ShipSdf._blend_for`), which is now written where the next reader will look.

Gated twice: `tests/core/test_component_expansion.gd` compares the geometry an attach pass places
before and after a lift AS GEOMETRY (a lift renames every part it takes), and the visual check's
MAKE COMP stage lifts three parts and counts meshes: 10 before, 10 after, 2 of them inner, origins
unchanged, undo restores the parts.

The review that followed found three things worth fixing and two worth writing down. Fixed: the
budget ghost box only carried the expanded parts of the moving instance itself, not of an
instance among its descendants (`_build_ghost_boxes` now partitions by owning doc id, the same
way `_build_base_bbox` decides what stays behind, so the two never disagree about a part); a
re-placed instance's expanded parts hid, but their symmetry twins stayed drawn beside the ghost's
own twin (`_apply_visibility` resolves the twin to its source before comparing); and a discarded
return in the test now says why. Refuted with evidence: `_max_blend` not recursing into
definitions is not a bug, for the reason above. Deferred and recorded in F17: a definition whose
root family cannot be resolved draws and bakes as nothing for the whole instance while its
transforms still exist - raised by review, not reproduced.

### Every primitive is a room, and any two parts that meet can be hatched

The 2026-09-01 entry's "refuses, out loud, on a part that has not been named a room" is retired
in place (`part_tree.gd`, RETIRED(2026-09-02)). A part is a room by default: `ShipPart.role`
defaults to `ROLE_ROOM`, and `is_room()` is true for `"room"` and for `""` alike, because `""` is
what every part saved before this rule reads back as - `from_dict()` keeps it and `to_dict()`
writes it back unchanged, so an old file's canonical form and hash are untouched and no ruleset
bump is needed. A new document records `"room"` on every part. The stock templates use the same
vocabulary through `ShipTemplates`' aliases, and a component instance is one room.

LINK HATCH takes any two parts and asks one question: do their interiors meet at the hull
thickness, so the hatch opens onto air? `ShipJoints.solid_pair_state()` answers it, and it is the
SAME function the validator asks (`ShipValidate._solid_pair_state` delegates to it), so the panel
and the validator cannot disagree. Two parts that only touch are refused with "SINK ONE DEEPER
INTO THE OTHER, THEN LINK"; two that do not meet with "MOVE ONE INTO THE OTHER, THEN LINK"; a
hatched pair toggles off; an open joint upgrades to hatched. Not linking keeps the internal door,
as asked.

MAKE ROOM on one part names it. MAKE ROOM on several is the "combining multiple into the same
room" the author described: they become one component and one room, and THE JOINTS FOLLOW THE
LIFT. `ShipDoc.remove_part()` erases every joint touching a removed part, so `_swap_in_instance`
snapshots the joint records before it runs and `_reseat_joints` puts the survivors back
afterwards: a joint between a lifted part and an outside part is kept under its own id against
the instance (the outside room is still hatched to what is now one room, hatch fields and
`seed_m` intact); a joint wholly inside the lift is dropped, which is the internal walls going;
two joints landing on one pair collapse to the hatched one, and between equals the lower id, in
sorted order, so the result never depends on dictionary order.

Thirteen new tests in `tests/core/test_rooms.gd` - a fresh part is a room, a pre-rule file keeps
its record, a hallway is not a room, an instance is one room, the outside joints survive a lift
and the inside walls do not, two joints onto one neighbour collapse to the hatched one, every
compact pair at a default placement meets, a flush box on a sphere and a part floated 4 m out do
not (the first draft floated it -4 m, which SINKS: negative embeds, positive floats, and the test
now says so), and the validator and the panel ask the same question. The visual check's new
rooms stage drives the tree panel's own buttons and the builder's own in-scene dialog: 10 parts
all rooms; hatch toggled on/off/on between hull and tunnel with no dialog; a far pair refused
with "DO NOT MEET" and no joint written; MAKE ROOM on one part named it; MAKE ROOM on tunnel,
child and grandchild produced one instance that is a room, kept every mesh where it stood, carried
the hull hatch, left exactly one joint, hatches as a whole, and three undos brought back the
parts, the hatch and all 14 meshes.

### NEXT always advances, and the five headers

The tutorial's NEXT was disabled until the step's predicate held, so a player who could not do a
step could not skip it either, and a card that cannot be moved past blocks the panel it sits
over. NEXT now always advances; the card still clears itself the moment the document shows a step
done, and the DONE mark still only tells the truth. The visual check opens the card and presses
NEXT through to FINISH: opened at step 5 of 8, 2 presses to finish - the first on an unfinished
step, which is the retired bug.

Found on the way: gdformat duplicates a file's leading comment block into every multi-line
lambda it meets inside a literal, and `tutorial.gd` carried five copies of its own header before
anyone noticed. The step checks are methods now, and the header says why.

### Contract, recorded not changed

`docs/API_CONTRACT.md` is not edited. F18 lists every addition - `ShipPart.ROLE_*` / `is_room()`
and the changed `role` default, `ShipJoints.solid_pair_state()`, the three `ShipComponents`
helpers and the joint re-seating rule, the `ShipAttach` embed functions, and the `ShipTutorial`
read-back - with what each section should absorb if the contract is ever unfrozen. SPEC section
13 is unchanged: M5 Completed, M6 Testing.

### Verified

gdUnit4 191/191 (0 errors, 0 failures, 11 s); selfcheck PASSED (hash stable across repeat calls);
data validator PASSED, 0 warnings; visual check PASSED (4 modes; bbox cage (250, 120, 250) m
matching the budget; 11 handles driven through the real press/drag path; 5 releases - 4 kept, 1
gone, as expected; make component 10 meshes before / 10 after, 2 inner; rooms and tutorial as
above); gdformat and gdlint clean on every touched file, no duplicated headers.

Still the human's to check: open `harness/dev_host.tscn` and run it - rotate a part every way
round every axis, Ctrl-drag one into its parent, MAKE COMP a multi-selection, LINK HATCH a tunnel
to a sphere, and press NEXT on a step you have not done.

## [2026-09-02b] Arrow keys that step, handles you can see, the Fresnel rim, seam walls, and EXPLODE

The author's playtest list, five items, all five landed and gated (ADR 0008, FOLLOWUPS F19):

> "pressing arrow keys doesnt work properly, moves the object almost randomly at large 90
> degree snaps ... the correct mechanical response should be the child part - parent part
> placement vector should change angle, smallest snap ammount ... - i really want a frenzal
> node ... - the visual handle system is baraly visible, it goes through the part rather then
> being visible outside the part ... - after all rooms are defined and hatches, the objects must
> be subtracted or added to eachother, with a flat faced seem where they mate that flat seem is
> where we will cut the hatch doors into, centered auto placed - we want an auto explode btn
> that explodes all the modules apart revealing their internal hatch walls."

Three questions were put to the author before anything was written, and the answers are what
this entry builds: "frenzal" is Fresnel, on every part; the seam between two separate rooms is
"just a solid wall no door. by default. but it should have dynamic options for how 2 rooms
link"; and the arrows step in the PARENT's frame with a fixed sign, not screen-relative.

### The arrows walked a list

`ShipReseat.step_snap_target()` stepped the parent's `SnapTargets` - centre, faces, poles, rim
points - by one entry for LEFT/RIGHT and eight for UP/DOWN. The list is typed, not spatial, so
each press teleported the part to whichever face or pole came next in it. Replaced by
`step_placement()`: LEFT/RIGHT is yaw minus/plus one `snap_deg`, UP/DOWN is pitch plus/minus
one, Shift makes the step `NUMPAD_COARSE` (15 degrees), the result is put on the snap lattice
(so a drag-snapped part's unquantized angles land on the grid at the first press), and
`snap_id` is cleared - `ShipAttach.local_transform()` reads the snapped anchor whenever the id
names a live target, and the angles would not be read at all. The tutorial's step 5 said the old
thing and now says the new one (`_check_stepped`, a method rather than a multi-line lambda, for
the header-duplication reason recorded on 2026-09-02).

### The handles were one pixel wide and drawn in the wrong queue

Two faults under "barely visible, goes through the part". The gizmo was 1-px `PRIMITIVE_LINES`
through a 16-colour quantizer and a Bayer dither, with morph arrows 18% of the gizmo radius and
no screen floor - ten pixels on a distant part. And its material was OPAQUE with
`no_depth_test`: opaque draw order is not depth-sorted, so whether a handle showed through a
part depended on which mesh the renderer drew first. Now (`ShipHandles`, `ShipSceneBuilder`):

- SOLID geometry - tubes for the three rings, prisms with cone heads for the six stretch arrows
  and the offset stalk - every thickness and length floored in inner-viewport pixels
  (`SHAFT_PX` 1.5, `HEAD_PX` 4.5, `ARROW_PX` 26, `TUBE_PX` 1.5). `ShipView3D` pushes
  metres-per-pixel at the selected part's distance on every camera move and selection change,
  from its own SubViewport's height and the camera's fov - never the window (SPEC section 10).
- TWO PASSES in the transparent queue, which draws after every opaque part and sorts by
  `render_priority`: a dim pass (no depth test, priority 90, the role's second ramp band) under
  a bright pass (depth-tested, priority 100). Behind the part reads dim, in front reads bright,
  nothing is ever hidden.
- The offset stalk starts on the part's +Y face rather than at its origin.
- THE PLACEMENT HANDLE IS A COLLAR. It was a line from the parent's origin to the part's, i.e.
  entirely inside two solids. It is now `ShipHandles.footprint_loop()`: a ring in the seam plane
  (below) just wider than the part's footprint, at the base of the part on the parent's skin,
  hit-tested as a loop like the rotation rings, in the accent role. `Handle.PLACEMENT` keeps its
  number; the old ray is a dim reference line that grabs nothing.

### Fresnel

`shaders/part_faceted.gdshader` gains a rim term - `pow(1 - dot(N, VIEW), rim_power)` pushed
INTO the band parameter rather than added as a colour, so the rim is the ramp's top band and
the quantizer stays a no-op on parts (the shader's standing rule). Plain parts rim in pale mint,
the selected part in amber. `rim_strength` 0.55, `rim_power` 2.5, set by `ShipSceneBuilder`.

### Seams and walls

SPEC section 7 had written the Phase 2 construction down and left it unbuilt. Built, with two
refinements the building found (ADR 0008 has the derivation):

- `ShipAttach.anchor_for()` - SPEC 3 steps 1-3 alone, both paths - and `local_transform()`
  refactored onto it (bit-identical: the same calls in the same order), so the placed transform,
  the seam plane and the gizmo collar share one P and N.
- `core/sdf/ship_seams.gd` (`ShipSeams`, new): one seam per placed part that stands on another
  - doc parts, component instances on their proxy shape, symmetry twins by reflection; not the
  inner parts of a component, which is one room; not sibling overlaps, which have no attach
  plane. Mode from the joint record over the pair: none or `sealed` is a WALL (the default);
  the new `ShipJoint.MODE_DOORWAY` is the wall with a plain rounded-rectangle opening
  (`doorway_width_m` 0.8 x `doorway_height_m` 1.9); `hatched` is the wall with the hatch
  family's opening (circle from `radius`, oval or rounded rectangle from `width x height`, pack
  defaults under the joint's stored params); `open` is no wall. Every opening is centred on the
  anchor and square to the seam.
- `ShipSdf` lays the plates: a slab `[P - T, P]` on the INNER side of the plane - the host's
  own skin continued across the opening the union removed - clipped to the child's
  cross-section, opening subtracted, entering the field as `f = max(union, -T - plate)`. That is
  the only way to add a wall to a `min()` union, which is already deep inside at the seam:
  inside the plate the value sits in `[-T, -T/2]`, solid but never cavity, so the outer surface
  is untouched and the interior isosurface gains the plate's two faces. Pinned API unchanged;
  `sample()` now carries walls for every multi-part doc.
- A plate thinner than a grid cell is a bump the grid steps over - found by the bake test, whose
  first run baked 2848 interior triangles with and without a wall. The hull skin survives any
  cell because the field crosses it monotonically; a plate is cavity-wall-cavity. `HullBake`
  now extracts from `sdf.with_min_wall_m(fitted_cell * 1.05)`, widening the plate INTO the host
  to the spacing `SurfaceNets.fitted_cell()` says the extractor will really use, with the value
  scaled so it still peaks at -T/2. The default bake gets 0.26 m bulkheads for a 0.15 m hull;
  the field itself, and every direct sampler, still sees T.
- The tree panel's LINK HATCH became LINK, cycling WALL -> DOORWAY -> HATCH -> OPEN -> WALL
  through `ShipBuilder.cycle_link()`; the meet test gates every step that opens the seam wider
  and never the step back to a wall. The bake report gains a SEAMS line. `toggle_hatch_link()`
  had no callers left and is gone; `ShipBuilder` is at gdlint's 30-public-method cap, so
  `_set_exploded` is private and driven by the button, the E key and the check.

### EXPLODE

`ShipSdf.module_view(id)` is the same class with clips and pucks instead of plates: the
module's own entries clipped to the OUTER side of its seam (the face it stood on comes out
flat - "subtracted"), each child's entry clipped to the INNER side and kept with the host (the
collar - "added"), and pucks boring the opening through the flat face and down through each
collar and the skin beneath it; an `open` seam's puck is the whole cross-section. No plates:
the flat face gets its T-thick wall from the interior isosurface for free, so a module bakes
as a closed shell whose seam face is a wall with the door in it.

`ShipExplodeView` (new, beside the scene builder under the view's SubViewport) bakes one module
per frame at `max(bake_cell_m, longest / explode_cells_per_axis)` - 32 cells, a preview, not
the bake - and places it at `ShipSeams.explode_offsets()`: along its seam normal by
`explode_gap_m` plus half its extent, accumulated down the host chain. It borrows the scene
builder's faceted material so a module shades like the part it came from. EXPLODE / ASSEMBLE
in the header and `E`; the parts hide meanwhile, the view owns only the camera, and any edit
assembles first. The demo ship's 13 modules explode in 1.8 s.

### Contract, recorded not changed

`docs/API_CONTRACT.md` is not edited. F19 lists every addition - the fourth joint mode,
`anchor_for`, `ShipSeams`, the `ShipSdf` and `SurfaceNets` methods, the four `ShipConfig`
levers, `hit_test`'s changed optional parameter, the harness classes - and what each section
should absorb if the contract is unfrozen, plus two limits named rather than hidden: sibling
overlaps have no seam, and the 0.5 m metrics grid does not see plates, so the interior-volume
gauge reads the studio cavity while the bake report does not. SPEC section 7 is retired in
place, section 13's M6 row names the work; no ruleset bump - nothing the hash consumes moved.

### Verified

`--import` clean; selfcheck PASSED (hash stable, `5536787c6c35d236`); data validator PASSED,
0 warnings (tuning.json and its schema carry the four levers); gdUnit4 212/212 (0 errors, 0
failures, 7 s), among them the new `tests/core/test_seams.gd` (18: the seam is on the face it
stands on; a wall samples above -T where the union samples below it; sealed is a wall; open
lays no plate; a doorway and a crawlway hatch open the wall at their centre and not beside it;
a stored hatch param overrides the pack; zero thickness lays no plate; a twin seams on the
mirror; a component is one room with one seam; a part on an instance seams on the instance;
a module view is cut flat, gains its collar, bores its door through both sides, and leaves an
open face off; explode offsets accumulate; seams are deterministic; hole signs), the attach
test that `anchor_for` is what `local_transform` stands on, the doorway round-trip, and the
bake test that a sealed seam adds interior triangles and leaves the outer area alone. The
windowed visual check PASSED: 4 modes; gizmo solid (4 triangle surfaces, arrow head 5.5 px,
arrow 26 px); 11 handles driven through the real press/drag path, the collar among them;
arrows RIGHT +0.5 yaw, UP +0.5 pitch, SHIFT+LEFT -15 yaw, all undone; 5 releases as expected;
make component 9/9 meshes; rooms - seam cycled WALL/DOORWAY/HATCH/OPEN on hull+tunnel, far
pair refused, three parts joined with the hatch carried and cycled on round, undo restored 13
meshes; tutorial NEXT to FINISH; explode 13 modules from 12 seams, parts hidden meanwhile,
`reports/visual_explode.png` at 9.0% ink, 13 visuals back after ASSEMBLE. gdformat and gdlint
clean on every touched file, no duplicated headers. Harness scripts were also parse-checked
headlessly with `--script X --check-only` before the windowed run, which is worth repeating.

Still the human's to check: open `harness/dev_host.tscn` and run it - press the arrows on a
child (and with Shift), grab the amber rings and the collar ring at a part's base, look for the
rim on every silhouette, LINK a tunnel to a sphere through all four states, press EXPLODE and
orbit the pieces, then BAKE and read the SEAMS line.


## [2026-09-02c] Dual Contouring, three seam styles on a right click, FRESNEL, and a clickable exploded view

The second playtest of the ADR 0008 work, four items:

> "exploded view does not let part selection, and doesnt render it anything other then flat. - i
> dont see Fresnel node under the render types. - the mesh resolution of the seem between 2
> objects is incorrect, its not flattened along the plane of intersection its all bumped out and
> weird looking. aside from that id like to be able to select 2 shapes, right click them and have
> 3 options for seem, parent indents child > child indents parent > and flat plane at
> intersection."

Two of them were plain omissions; two were decisions, and those are ADR 0009. Both decisions were
put to the author first - the seam semantics against a diagram, and what "Fresnel under the render
types" meant. The answer to the second settled it: "i mean i wanted that rendering effect/node to
be listed among wire, flat, shaded options."

### The bumpy seam was the centroid rule, and SPEC section 9 had already named the fix

`SurfaceNets._place_vertex()` returned the centroid of the cell's edge crossings. That is EXACT on
a plane - the centroid of coplanar points is on the plane - so a seam face was never wrong in its
middle. It was wrong at every sharp feature, by up to half a cell: the rim where the flat face
meets the flank, every box edge, every cylinder cap. Which is why the complaint was about a flat
face and the fix is about corners.

SPEC section 9 reserved that one function for this and said to do it "when the rounding is a
problem, not before". It solves a QEF now - the point minimising the squared distance to the
tangent planes at the crossings. Three things worth keeping: the crossing normals come from the
trilinear gradient of the cell's OWN eight corner samples, so the whole upgrade costs zero extra
field evaluations (six per crossing would have been the alternative, and the field is the
expensive half of a bake); it is regularised toward the centroid, because the QEF matrix is
rank-deficient wherever the surface is locally planar, which is most cells; and it is clamped
strictly into its own cell, because the quad pass assumes that and a near-flat ridge otherwise
solves to a point far outside it.

`tests/core/test_dual_contouring.gd` measures sharpness, since that is the only thing that
changed: every one of a box's eight true corners must have a vertex within 0.35 of a cell (the
centroid rule misses by about half a cell), no vertex may leave the true surface by more than a
cell, a 2 m cube must bake within 2% of its analytic volume, a slab thinner than a cell must not
produce a NaN or escape the grid, and a module's cut face must be flat across its middle. The
existing bake tolerances all still pass - Dual Contouring is strictly more accurate.

Two further causes of "bumped out and weird looking", both in the exploded preview: the modules
baked at 32 cells across their longest axis (now 48), and - the real one - at that grid the 0.15 m
hull is about one cell thick, so the interior isosurface dipped in and out of resolvability and
welded noise onto the outer surface. A module now previews at a wall of 1.6 cells, never thinner
than the real one. It shows where the walls are, not how thick they are, which is the same trade
`HullBake` already makes for plates and is recorded as a limit in F20.

### Three seam styles

`ShipJoint.seam_style` is `flat` (default) | `parent` | `child`. The MODE says whether a seam is
open, walled or doored; the STYLE says what shape it is. `parent` follows the PARENT's surface, so
the child ends up dented and the overlap volume stays with the parent; `child` is the mirror, a
socket in the parent; `flat` is ADR 0008's plane through the anchor.

One rule serves all three - the plate is the shell of hull thickness just inside the seam SURFACE,
clipped to the other solid - and all three partition the overlap exactly: a point where the two
solids meet belongs to exactly one module, never both and never neither. That invariant is a test,
and it is what makes the choice taste rather than correctness. `flat` on a CURVED host is a
tangent plane and the two cavities can still meet around its rim; that is what a flat plane means,
it is why the other two were asked for, and it is written down rather than quietly fixed.

Right-clicking two selected parts opens the menu. A right DRAG still orbits, untouched - only a
press and release within the click slop asks for it. The menu is an in-scene Control
(`harness/panels/ship_context_menu.gd`), not a PopupMenu, for the reason every dialog in this
project is: SPEC section 10 is a contract, and a native popup is a Window that would not exist on
the texture the player sees in-game.

NO RULESET BUMP, and it was measured rather than argued: `to_dict()` writes the `seam` key only
when the style is not flat, so every joint ever saved serialises byte-identically and the
selfcheck doc still hashes `5536787c6c35d236`.

### FRESNEL is a render type now

Not an always-on term folded into the shading, which is what shipped last time and is why it could
not be pointed at. It is the fifth entry in the dropdown, appended so no existing mode index
moves, and it is a genuinely different render: the body drops to the palette's dark `grid` entry
and the silhouette climbs to the ramp's top.

That took two goes. Turning `ambient` down alone changed 2% of the ship, because a lit face still
climbed to the top band on the lambert term and the rim had nowhere left to go; the shader gained
a `lambert_strength` uniform so a mode can stand the shading down entirely. Then the body was
still a mid-teal, because the `part` ramp's own darkest band is one - so FRESNEL uses a two-entry
ramp whose body is the `grid` role. A selected part keeps its own ramp's darkest band, which is
already dark and warm, so the selection still reads as amber. Measured: 45% of the ship's pixels
differ from SHADED+WIRE, against 2% at the first attempt.

### The exploded view answers clicks and the dropdown

Each module carries a pick body on the same layer with the same `PART_META` a part's body carries,
so the view's ordinary pick path selects the part it was baked from with no special case, and it
wears the display mode's materials and its own wireframe. The left button is no longer swallowed
while exploded; everything that edits geometry still is, because what is on screen is a set of
bakes and not the document.

The collider is a CONVEX hull, and the reason is worth recording: a trimesh built from the shell
was the obvious choice and could not be hit at all. The diagnostic that settled it reported a body
in the tree, on layer 1, holding 1652 triangles, passed through by both a screen ray and a ray
aimed straight at it, with backface collision on and off, in a space where a part's convex body
was hit from the same camera in the same frame. Convex is what parts already use; it costs a click
into an open cavity and buys a click everywhere else.

### Contract, recorded not changed

`docs/API_CONTRACT.md` is not edited. F20 lists every addition - the `_place_vertex()` signature
(private, but section 17 names it), the seam-style vocabulary, `DisplayMode.FRESNEL`, the shader
uniform, the harness classes - along with four limits named rather than hidden: the convex module
collider, the preview wall thickness, flat-on-curved, and the metrics grid still not seeing plates.
SPEC section 9's upgrade path is marked done in place and section 7 gains the styles.

Also: `tools/ship_visual_check.gd` reached gdlint's 2000-line file cap, so the four new view
checks moved to `tools/ship_check_views.gd`, sharing the failures array by reference so a run
still reports one list.

### Verified

`--import` clean; selfcheck PASSED with the hash unchanged at `5536787c6c35d236` (the proof that
the seam-style field costs no ruleset bump); data validator PASSED, 0 warnings; gdUnit4 223/223
(0 errors, 0 failures), including the five new Dual Contouring tests and six new seam-style tests
- each style puts its wall on its own surface and nowhere else, every style partitions the overlap
between exactly one module, parent dents the child and leaves the host whole, child is the mirror,
and a flat joint writes no `seam` key. The windowed visual check PASSED with five modes: fresnel
45.4% different from shaded+wire; clicking an exploded module selected p_0006 and stayed exploded;
modules follow the render type; the seam menu opened on a real right-click release and applied
parent, child and flat in turn, read back off the document. gdformat and gdlint clean on every
touched file, no duplicated headers.

Two of the seam tests were wrong before they were right, and both corrections are in the file: a
point half a wall inside ANY surface is shallower than -T whatever the plate does, so "is this
cavity" cannot be asked as "is it deeper than -T"; and a plate is a max() term over its whole seam
box, so outside its own slab it can raise the distance (measured: -0.377 to -0.293) without ever
reaching hull. The claim that is exactly true is that the plate turns cavity into HULL at its own
seam surface and nowhere else.

Still the human's to check: open `harness/dev_host.tscn` and run it - pick FRESNEL from the render
dropdown, look at a seam face for flatness, right-click two parts and try all three seam styles,
then EXPLODE and click the pieces.

## [2026-09-03] The extractor was never the mesh: a simplification stage, and a box that is a box

> "the parts are not being handled properly! ... including placing a bunch of unnecessary triangles
> in the scene .. we cant have this messy resolutions with janky triangles all over the place ..
> clearly our surface nets are failing or something .. your mental model should be google sketchup
> solid tools type of resolution."

Surface Nets was not failing. That was worth establishing before writing anything, because the
obvious fix — go at the extractor again — would have been the second consecutive rework of a file
that was already doing its job.

### What the measurements said

A room's `+X` face is planar to **0.0000 m** over 441 bisections of `ShipSdf.sample()`, in the
assembled field and in a module view alike. The extracted vertices sit **0.31 cells** off that
surface at worst. So the shapes were exact and the extraction was accurate, and a 3 m room module
still shipped **1568 triangles** on its outer surface with **65% of the area dead flat**, and a
lone 2 m box shipped **588** where 12 describe it exactly.

The defect was an absent stage. Dual Contouring emits one quad per sign-changing grid edge — a
faithful sampling of a surface, not a model of one — and nothing stood between it and the GPU.

Two more findings came out of the same pass. The room family carries `round: 0.02`, about a 6 cm
fillet, against a 0.25 m cell: the grid cannot represent that, so it lays a band of noise around
all twelve edges of every box. 52 of a module's 72 patches were that band, and no amount of
resolution fixes it because the authored radius scales with the part and the cell does not. And
the interior shell was welded in whatever state it arrived: a room's cavity landed up to 2.19
cells off with six vertices escaping outside the hull, which is what the tears on the exploded
pieces were.

### The stage

`core/bake/hull_simplify.gd`, between `SurfaceNets` and the `ArrayMesh`, run over the outer and
interior surfaces separately. Project every vertex onto the exact isosurface along the analytic
gradient; grow planar patches against a plane fixed from the seed; absorb the fragment rings
beside a face into it; snap every vertex onto the planes meeting at it; straighten the boundaries
and retriangulate, bridging holes. `SurfaceNets` is not touched.

Two of those steps are load-bearing in ways that are not obvious. **Projection is not cosmetic**:
at a third of a cell out, the facets of a flat face are tilted enough to fail any coplanarity
test, and that step alone took a room module from 130 patches to 72. **Absorption is bounded by
RINGS, not by tolerance**: an unresolvable fillet is a band one or two triangles wide beside a big
flat patch, and a curved surface is fragments all the way through, so a two-ring bound takes the
first and cannot take the second whatever the angles say. The tolerance had to be loose (~57°)
because fillet facets sit at roughly 45° to both faces they join, and a tighter gate refuses
exactly what the step exists to collect.

**Snapping is one solve for three cases.** A vertex on one plane is projected onto it, on two onto
their line, on three or more onto their point — a regularised normal-equation solve does all three
with no special case, which is the same shape `SurfaceNets._place_vertex()` already uses for its
QEF, over patch planes instead of crossing tangents. That is what makes an edge exactly straight
and a corner exactly sharp rather than nearly so.

Cracks were the whole risk of the design, and both places they would appear are closed by
construction rather than by tolerance: snapping is global and runs before any patch is
triangulated, and boundary straightening runs over chains keyed by the planes meeting along them,
once, not once per patch. Patches carry their own copies of a shared vertex — that is what gives a
hard edge its two normals — so the shell can only be checked for holes after a positional weld.

### Verified

`--import` clean; selfcheck PASSED with the hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdUnit4 **231/231** (0 errors, 0 failures), including eight new simplification
tests; gdformat and gdlint clean on every touched file. The windowed visual check PASSED with five
modes, and its exploded screenshot is the actual answer to the complaint.

Measured at a 0.25 m cell: a lone 2 m box goes from 588 triangles to **12**, in **6 patches**,
welding to **8 vertices**, with a surface area of **23.999 m² against an exact 24.000** and a
volume of **8.000 against an exact 8.000**. A five-part ship goes 8308 → **700** triangles; a 3 m
room module 2444 → **274**; the flat share of a module's area 55% → **92%**. Vertices escaping the
hull across three room modules: 52/14/8 → **10/0/0**. Watertightness after a positional weld: **0
open edges and 0 unmatched windings** on a plain box, a rounded box, with and without a hull
thickness, on every module of a five-part ship, and on the whole ship. Bake cost rose about 35%
(724 → 980 ms for that ship), which is the projection step and is on the cheap axis.

### Two things that were investigated and left alone

The tunnel module bakes **solid**, and that is correct: at `hull_thickness_m` 0.4 against a 1.0 m
bore there is 0.1 m of cavity radius left. Re-baked at a 0.16 m cell it is still solid, so it is
geometry and not resolution, and `ShipExplodeView` was not changed on the strength of that. Its
1.6-cell wall preview was also measured to be **inert at default settings** — `max(0.4, 0.25*1.6)`
is 0.4, the real thickness — and only bites above 8 m, where it is the only thing keeping a large
module's walls visible at all. Removing it on suspicion would have been a regression.

`tests/core/test_dual_contouring.gd`'s cut-face test had to move from sampling VERTICES on the cut
face to sampling FACES: it asserted that more than four vertices land there, which assumed a mesh
keeps a vertex every cell across a flat face. A face whose middle is perfectly flat now has no
vertices in its middle at all, so the old form would have failed for exactly the reason it exists
to reward. Same property, same tolerance, different sampling; marked RETIRED in place.

### Recorded, not hidden

Curved regions are **not** decimated — a cylinder or torus keeps every triangle it arrived with,
smooth-shaded from the gradient. That is deliberate (a cylinder showing its tessellation is what
CAD looks like) and it means the win is concentrated on flat-faced parts; a curved pass needs an
error metric this one does not carry. Absorption squares off any fillet the grid cannot resolve,
so the baked hull reads very slightly larger than its field. A patch that cannot be retriangulated
safely keeps its original triangles rather than risk a torn face. ADR 0010 and FOLLOWUPS F21 carry
all four, along with a GDScript trap worth knowing: `PackedInt32Array` and its siblings are VALUE
types, so a helper that appends to one it was passed appends to a copy and the caller sees
nothing. That silently emptied the first draft of the file.

### Still the human's to check

Open `harness/dev_host.tscn` and run it: press EXPLODE and look at the pieces — the boxes should
read as boxes with clean straight edges rather than dimpled lumps, the rings should still curve,
and no piece should have triangles poking out of it. Then BAKE the assembled ship and check the
wireframe.


## [2026-09-03b] Exact meshes: one closed solid per part, and two arithmetic bugs worth the trip

> "we will have to do it the slow exact way .. so yea same exact exactness as sketchup is needed.
> im a noob so maybe analytically you want it as a sdf but all i know for sure is we want exact
> mesh operations as our current method is not exact."

Yesterday's simplification pass made the Surface Nets bake much better and still lost the argument,
which was the right call: a grid can be refined but never made exact, and every flat face was a
staircase underneath.

Two constraints came with the decision and both narrowed it usefully. **Single-layer shells only**
removed the one thing polygons are genuinely bad at, since offsetting a mesh inward by `T` is hard
where offsetting a field is one subtraction. And then, decisively: **parts stay separate** — "all
primatives can be their own mesh ... they can remain in parts as in space they will have detach
capabilities."

That second one is what made the whole thing tractable. Both defects the whole-ship union had were
properties of ACCUMULATING unions, and nothing is accumulated any more. `ShipMeshBake` runs no
boolean whatsoever.

### What was built

`core/mesh/` — `PolyMesh` (n-gon boundary rep with holes), `Poly2D` (triangulating a face with
holes), `MeshCsg` (BSP booleans), `MeshMerge` (T-junction repair, coplanar fragments back into
n-gons), `ShapeMesh` (`ResolvedShape` to mesh) — and `core/bake/ship_mesh_bake.gd`.

The tessellator does not re-derive the shapes; it INVERTS them. `ResolvedShape.sdf()` warps the
domain and then asks a primitive, so the surface is the base primitive carried backwards through
those warps, and a vertex is placed by `scale * taper⁻¹(twist⁻¹(shear⁻¹(q)))`. All three warps leave
`y` alone, which is what makes every inverse a closed form. Taper and shear are LINEAR in `y` so a
plane stays a plane and a box stays six faces; twist is not, so a twisted shape is subdivided and
triangulated rather than emitting quads that lie about being flat.

### Verified

`--import` clean; **gdUnit4 252/252**; selfcheck PASSED with the hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean on all ten touched
files; the windowed visual check PASSED with five modes.

The assertion that matters: **every baked vertex samples to zero in the field it came from**, over
every family, under taper, twist, shear and non-uniform scale. Where it does not, the gap is
exactly the deferred `round` op — `cylinder_spar` reads 0.050000 m out unscaled and 0.030000 at a
0.6 minimum scale, which is `round_r * min(scale)` to the digit. The test computes that budget
rather than tolerating slack, so it tightens by itself the day fillets get built.

A `helium` template bakes in 35 ms, `carbon` in 71 ms, every part closed. A box is six faces, eight
vertices and TWELVE model edges: the wireframe now draws `boundary_edges()`, so it shows real edges
only. Half of what "janky triangles all over the place" meant was triangulation diagonals, and they
are simply not in the model any more.

### Two arithmetic bugs, and neither was where it looked

**Godot's `Vector3` is 32-bit float.** A flat 1e-7 m plane epsilon is BELOW the noise floor at ship
scale. A 24-gon prism at the origin built a correct 26-deep BSP; the identical prism at `x = 1.0`
classified its own defining polygon as behind its own plane, so nothing was ever consumed, the tree
recursed to its depth cap, and the box it was unioned with vanished — 27 m³ reported as 1.24. The
threshold sat between `x = 0.5` (worked) and `x = 1.0` (failed), which is what fingered float32
rather than the algorithm. Fixed twice over: a scale-relative epsilon, and recentring every
operation on its operands so precision depends on the size of the parts rather than on where the
ship's origin happens to be.

**The weld tolerance was wrong in BOTH directions**, and both were measured before either was
believed. At 1e-6 m it destroyed the sub-micron slivers a near-tangent cut leaves, and every
destroyed sliver is a hole — a box unioned with a cylinder read 5.75 m³ where 27 was owed. Tightened
to 1e-11 it stopped destroying anything and started welding nothing: two vertices that are the same
point reached by different split orders differ by float noise, so a shared edge came out with
different indices on each side and a closed solid reported 146 unmatched directed edges. It uses the
operation's own relative epsilon now.

There was a third, cheaper lesson too. A twelve-part assembly that never finished was blamed on the
boolean; it was `MeshMerge` grouping faces by scanning the planes seen so far, which is O(faces ×
distinct planes). A coplanar FLOOD FILL is linear and is also the more correct question — two faces
sharing a plane at opposite ends of a ship are not one face. Tangential placement now runs nine
parts in about 1.5 seconds, linearly.

### Recorded, not hidden

`round`, ribs and scallops are not built (they are offset and displacement ops, not domain warps).
A circle is a 24-gon, and that is a constant rather than a lever. Parts overlap where they meet and
are not trimmed. A module made of several placed ids still uses the Surface Nets path. Repeated
unions of near-coplanar solids are still slow, though unreachable today since nothing unions. ADR
0011 and FOLLOWUPS F22 carry all six, with the numbers.

### Still the human's to check

Open `harness/dev_host.tscn` and press EXPLODE. The boxes should be boxes — crisp edges, twelve
wireframe lines each, no diagonals across a flat face — and the tubes should show their 24 facets
and nothing else. Next up, per the author: interior shell, hatch cutouts and connections.


## [2026-09-03c] The seam styles reach the mesh, and a merge that must never make a solid worse

> "i noticed that i dcnt see the overlapped meshes resolved to the (parent indents child/child
> indents parent/flat at intersection) for the mesh deformation actually happen. i right click 2
> selected solids, i press the option i want ... and then after i press explode and it does not
> show the created manifolds."

Correct, and self-inflicted. Wiring EXPLODE to the exact per-part bake replaced a path that ran
`ShipSdf.module_view` - which applies the ADR 0009 seam styles as clips and subtractions in the
FIELD - with one that ran no boolean at all. The styles were still stored, still switchable, and
had nothing left to act on.

### What the styles mean, in meshes

FLAT splits the overlap at the seam plane: the child keeps its outer half and gets a flat mating
face, and the host GAINS the inner half as a collar, so the two still fit when assembled. PARENT
subtracts the host from the child - the host presses a dent. CHILD subtracts the child from the
host - the child sockets in. Exactly `clip_to_plane`, `union` and `subtract`, all of which were
already built and tested.

Two properties are worth stating because they were designed for rather than discovered. The style
is read from the JOINT and never baked into a part, so switching one is non-destructive and
switching back lands bit-for-bit where it started (there is a test). And every cut is taken against
the parts AS TESSELLATED, never against a partly-cut one, so a part that is the child of one seam
and the host of another gets both cuts and gets the same two whichever seam is walked first - which
matters, because seam order is a Dictionary walk.

### The merge had to be rebuilt around an ordering

Adding collars put unions back, and that exposed a real bug. Measured on the hull: union left 669
open edges (T-junctions, expected), `repair_t_junctions` took it to 0, and then the MERGE opened it
back up to 46. The cause was corner-dropping - a merged face should not carry a corner at every
point some neighbour happened to be split at - being decided PER FACE. Drop a vertex on one side of
an edge while the face across it still uses that vertex, and the T-junction the repair just fixed
goes straight back in.

The fix is to decide globally: a vertex survives if ANY ring turns at it. That took the hull to 0
open edges on one collar and 3 on two. The remaining 3 came from the second thing a merge needs,
which is the honesty to refuse: a group whose ring walk does not reproduce the area of the faces it
replaces keeps those faces. But bolting that on AFTER the keep set was chosen made it worse (7 open
edges), because a rejected group then held vertices its merged neighbours had already dropped.

So the pass is three ordered phases, and the order is the design: walk and CHECK every group, then
choose the surviving corners globally - counting every vertex of a rejected group as surviving -
then emit. All three styles now come out closed.

Along the way, the twelve-part assembly that never finished turned out not to be the boolean at
all: `MeshMerge` was grouping faces by scanning the planes it had seen, which is O(faces x distinct
planes). A coplanar FLOOD FILL is linear, and is the more correct question anyway - two faces
sharing a plane at opposite ends of a ship are not one face.

### Verified

`--import` clean; **gdUnit4 254/254**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data
validator PASSED, 0 warnings; gdformat and gdlint clean; the windowed visual check PASSED with five
modes and its screenshot now shows the socket cut into the hub face where a tunnel lands.

Measured, on a `helium` template, per style - child volume, host volume, open edges:
FLAT `4.7592 / 25.4744 / 0`, PARENT `1.2446 / 25.4427 / 0`, CHILD `1.2440 / 25.1750 / 0`. Three
distinct results, all closed. Under FLAT the child reads LARGER than under PARENT because it is
itself the host of the next seam along and carries that collar - which is the collar doing its job.
A seamed bake of that ship is about 1.1 s against 35 ms unseamed; the difference is the booleans and
the merge, and the author has already said this need not run at warp speed.

The agreement test moved to `ShipMeshBake.bake_part()`, which tessellates and places without the
seam booleans. That is not a weakening: a flat mating face is deliberately NOT on the part own
primitive surface any more, so asking the old question of a seamed part would have been asking the
wrong one.

### Still the human's to check

Open `harness/dev_host.tscn`, select two parts, right-click and set a seam style, then EXPLODE. The
three options should now give three visibly different pieces, and switching back should restore
exactly what was there. Hatch and doorway OPENINGS are still not bored into the exact mesh - that is
the next piece, along with the interior shell.


## [2026-09-03d] The collar was the hang and the artefact both; a clip that is not a boolean

Two reports, one cause between them.

> "when it separated upon explode, somehow it cut the upper sphere way into the sphere, and short of
> the lower sphere. so the cuts arent happening at intersection. - pressing explode on argon freezes
> the system, and it so-far never resolves running 16 mins now (if sketch up can resolve these low
> poly count meshes very quickly so can we, if thats the issue)"

The author is right about the second one on principle, which is the useful part: these are meshes of
a few hundred faces and nothing about them justifies minutes. A hang at this size is an algorithm
being wrong, not work being hard.

### What the trace said

Tracing the bake to a file - because the run wrapper swallows output when it kills a run, so a hang
leaves no evidence otherwise - `argon` reads plainly. Its hub is host to EIGHT seams. Under FLAT
each one handed the hub a COLLAR, unioned on:

```
7 union p_0001 ->  1262 f,   236 ms   ... merge -> 987 f, open=3
9 union p_0001 -> 13442 f, 23911 ms   ... merge -> 9308 f, open=938
11 union p_0001 -> 28056 f, 39604 ms
```

A union is the only operation that GROWS a mesh, and the merge that was supposed to bring it back
down was itself failing (open=3 becoming open=938), so each collar was unioned into the shredding of
the last. That is the freeze.

### The collar was the visual artefact too

The seam frame sits at the ATTACH POINT on the host's surface, so the FLAT plane is the tangent
there. `argon` attaches at the corners of a box: measured, the host reaches -0.029 along the seam
normal while the child reaches -0.659, so the collar was a chunk of tunnel protruding diagonally
past a corner it was supposed to be flush with. On the sphere pair in the report it is the same
thing - a cap handed to one part and missing from the other, which reads exactly as "way into the
upper, short of the lower".

So the collar went. It was wrong in the case it was meant to serve, and in the case it was NOT meant
to serve - a flat host face - it sat entirely inside the host and added nothing at all. Dropping it
changes nothing where the host is flat and removes a spike everywhere else, and the author had
already allowed for the gap it leaves: "if a thin unseen buffer of space is needed between modules
thats fine". **Nothing in the bake unions any more.** FLAT cuts the child and leaves the host; PARENT
and CHILD subtract, which shrinks.

### Then the speed, which was three separate things

**`clip_to_plane` was a boolean and did not need to be.** It built a slab big enough to contain the
mesh and called `intersect`, which reuses the tested operator - the right instinct, the wrong trade.
A BSP splits every face against every plane of the other solid, so cutting a 360-face sphere with a
six-faced slab shredded it into hundreds of fragments that then cost ten times the cut to merge
back. Splitting against ONE plane touches only the faces that cross it, leaves the rest whole, and
needs no merge at all. The slab version is kept as the fallback for a mesh whose cut edges will not
chain into closed loops.

**String keys.** Every spatial hash in the pipeline built a `"%d_%d_%d"` key, and `PolyMesh._intern`
probes 27 neighbouring cells per vertex - thirteen thousand strings for a 500-vertex result. They
are integer hashes now (Teschner's three primes); collisions are harmless because every lookup ends
in an exact test, a distance for a weld or a point-on-segment for a T-junction.

**A linear scan inside a flood fill.** `_neighbours_of` deduplicated with `PackedInt32Array.has()`,
which is quadratic in the neighbour count on a shredded hub. It uses a Dictionary now.

### Verified

`--import` clean; **gdUnit4 254/254**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data
validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED, five modes.

Measured, whole-ship bake, every part closed:

| | before | after |
|---|---|---|
| `helium` (5 parts) | 1100 ms | **216 ms** |
| `carbon` (9 parts) | 5567 ms | **320 ms** |
| `argon` (17 parts) | never finished | **667 ms** |

The seam styles, on `helium` - child volume / host volume / open edges: FLAT `1.2287 / 25.4427 / 0`,
PARENT `1.2446 / 25.4427 / 0`, CHILD `1.2440 / 25.1750 / 0`. FLAT and PARENT now leave the host
identical, which is a stronger statement than the old test made and is asserted as such; they differ
on the CHILD because one cuts on a plane and the other on the host's real surface.

### Recorded, not hidden

The FLAT plane is still the TANGENT at the attach point, so on a curved host or a box corner it is
not the host's surface and the fit is approximate. `parent` and `child` cut on the other solid's real
surface and are exact there. Two spheres meet in a circle and that circle IS planar, so a flat plane
could be fitted to the actual intersection instead - that would make FLAT mean what it says on a
curved host, and it changes what an existing authored setting produces, so it is written up as F23
and left as a decision rather than taken.


## [2026-09-03e] Flat means the real crossing now, and a hash used as an identity

> "flat will be defined in the following ways: we must first classify which part is inside of which
> part, probably based on size and if they are overlapping. - next is a bit complex but will create
> flat flanges, 2 styles of flat flanges, out bumped and in bumped."

F23 asked where a flat plane should sit and this answers it. The old `flat` cut on the tangent
plane through the ATTACH ANCHOR, which is the host's surface only when the host is flat there; on a
sphere or a box corner it is a tangent and nothing more.

### What it does now

Both meshes' edges are walked, every edge that changes side of the other solid's field is bisected
onto it, and the crossing points are projected onto the joint axis. The plane goes through the
extreme one - deepest for in-bump, outermost for out-bump. For two spheres the crossing curve is a
circle and already planar, so the plane lands on it: measured 1.4136 against an analytic 1.4132.
Larger and smaller are decided by VOLUME, not by the attach tree, exactly as specified, because a
small part can perfectly well be the parent of a large one.

The author asked for both cut extents, so `flat` became four styles: the plane sits at the deepest
crossing or the outermost, and the cut reaches only across the smaller part's cross-section (a
FLANGE) or straight through the larger solid (a SLICE). `parent` and `child` are untouched. The old
string still loads, as `flat_in`, and since it was the default it was never written to a file.

Worth recording the author's own reading of the result: "flat is equivalent to flat ended child
shapes inserted into parent shapes with child-indents-parent selection.. the redundancy is ok
however because this lets people quickly switch linkage manifolds without changing base shapes".
That is exactly right, and it is why the overlap is a feature rather than something to design away.

### Verified

`--import` clean; **gdUnit4 259/259**; selfcheck PASSED with the hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual
check PASSED, five modes.

Whole-ship bake, every part closed: `helium` 70 faces / 46 ms, `carbon` 426 / 277 ms, `argon` 846 /
594 ms. The face counts FALLING is the joint working - a tube seated between two rooms is cut flush
at both ends, so it drops from 360 faces to 26, twenty-four side quads and two caps, while the boxes
are untouched because on a flat face the deepest crossing IS that face.

### Two bugs, both mine, both in code written the same hour

`_cap_id` took a `PackedVector3Array` and appended to it. Packed arrays are VALUE types - the trap
this repo has a memory about and that `PolyMesh`'s own class docs warn about - so every append went
to a copy.

The worse one: it used a spatial HASH as an identity. Collisions had been justified as harmless
"because every lookup ends in an exact test", which is true of the weld and of the T-junction probe
and false here, where the key IS the answer. A 24-point cap came back as 18 points with six nodes
fused, no ring could be chained, and `clip_to_plane` had been silently falling back to the slow slab
boolean on EVERY call - including in the timings reported for ADR 0011 the same day. Keyed by exact
`Vector3i` now, and helium's bake went from 216 ms to 27 ms once the direct path actually ran.

The lesson worth carrying: a hash bucket is safe when something exact follows it and is a bug when
nothing does. Both uses were in the same file and only one of them was safe.

### Out-bump degrades, safely, and it is written down

Out-bump needs a UNION, the only operation that grows a mesh. On `argon`, whose hub takes eight of
them, the first union came out closed at 101 faces and the second left 60 open edges - after which
every union was fed a broken mesh: 5263 open edges by the fifth, 11049 and 73 seconds by the
seventh. A union whose result is not closed is now refused and the host keeps what it had, which
stops the compounding dead. `argon` finishes in 24 s with every part closed and seven stubs not
added, leaving a gap the author had already allowed for. In-bump has no union and does the same ship
in 594 ms.

### Still the human's to check

Right-click two parts: the menu now offers IN-BUMP FLANGE, OUT-BUMP FLANGE, IN-BUMP SLICE, OUT-BUMP
SLICE, PARENT INDENTS CHILD, CHILD INDENTS PARENT. On a sphere host the in-bump options should now
cut where the shapes actually meet rather than short of it. Out-bump on a hub with many branches
will be slow and will quietly leave some joints unbridged - F24 limit 1.


## [2026-09-04] Six names from two schemes become one grid, and a PASSED banner that was not

> "i see a structure where instead of saying child-indents-parent, or parent-indents-child, i think
> its more appropriate to classify it as big indents small, or small indents big. then to append on
> the toggles with that of flat inserted, flat cutoff, or native inserted. for the linkage surface..
> what im describing changes nothing but the naming and input scheme."

Correct, and it had been true for two ADRs without anyone naming it. `parent` and `child` came from
ADR 0009 and were named after the ATTACH TREE; `flat_in`, `flat_out`, `slice_in` and `slice_out`
came from ADR 0012 and were named after a plane position and a cut extent. Six entries in one menu,
drawn from two schemes that had nothing to do with each other.

They are one grid: which solid indents the other, times what the linkage surface is.

|                       | flat inserted       | flat cutoff         | native inserted |
|-----------------------|---------------------|---------------------|-----------------|
| **small indents big** | `small_flat_insert` | `small_flat_cutoff` | `small_native`  |
| **big indents small** | `big_flat_insert`   | `big_flat_cutoff`   | `big_native`    |

`ShipJoint.indent_of()` and `surface_of()` read the axes back off an id and `style_for_axes()`
rebuilds one, which is what lets the menu offer two toggles over a single stored value; there is a
round-trip test. The menu is grouped under two headings now rather than being a flat six, and
`ShipContextMenu` learned to draw a `header` row.

Every id this project has ever written still loads - `flat`, `flat_in`, `flat_out`, `slice_in`,
`slice_out`, `parent`, `child` - and there is a test that walks all seven. The names have changed
twice and the behaviours never have; a saved file should not have to know that.

### One thing genuinely changed, and it is the point

`parent` and `child` decided who lost material from the attach TREE. `big` and `small` decide it
from VOLUME. Where the tree parent is the larger solid, which is most joints, the two agree. Where
it is not, they differ - and measured on `helium`, whose tunnel is the tree parent of a room ten
times its volume, the old `parent` dented the ROOM and `big_native` dents the TUNNEL. A hab module
should not be hollowed out by the corridor bolted to it just because the corridor was placed first.
Worth flagging rather than burying under "nothing changed but the naming": a ship built before this
can bake differently at a joint like that.

### The verification that nearly passed while failing

The windowed check printed `=== visual check PASSED (5 modes) ===` and exited 1. `_seam_style_label`
walked the menu items reading `item["id"]`, and a heading row has no id. Two things caught it:
`tools/ship_run.ps1` fails a run on any runtime error whatever the banner says (AGENTS section 8a,
working exactly as designed), and then the exit code being noticed at all - because the first look
at that run had been piped through a `Select-String` that kept the PASSED line and dropped the error
report. Filtering a verification's output is how a green result gets manufactured; the filter went.

### Verified

`--import` clean; **gdUnit4 260/260**; selfcheck PASSED with the hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual
check PASSED, five modes, exit 0 - and its seam-menu step now drives four of the six new ids through
the real right-click path: `["big_native", "small_native", "small_flat_insert", "big_flat_cutoff"]`.

Six behaviours in, six out. On `helium`, every part closed: `small_flat_insert` 70 faces,
`small_flat_cutoff` 70, `big_flat_insert` 176, `big_flat_cutoff` 176, `big_native` 70,
`small_native` 1417.

### Still the human's to check

Right-click two parts: the menu now reads as two groups, SMALL INDENTS BIG and BIG INDENTS SMALL,
each offering FLAT INSERTED / FLAT CUTOFF / NATIVE INSERTED. Nothing should look different from
yesterday except at a joint where the tree parent is the smaller solid, where it should now look
BETTER.


## [2026-09-04b] Seam styling over any selection, and templates that are actually atoms

Two things, and the second turned up a rule the first half of the week should have had.

### Any number of parts, one sweep

> "add ability to select as many modules as desired, right click and change the connection surfaces
> for all at same time even if they differed before."

The menu took exactly two parts. It now takes any number and offers every connection with BOTH ends
inside the selection - which generalises the old behaviour exactly rather than replacing it: two
parts still means their one seam, a chain means every seam along it. Where the chosen connections
do not already agree, nothing is marked as current, because none of them is. It is ONE edit, so a
dozen seams is one undo.

The windowed check drives it for real: two seams deliberately set to different styles, swept
together in one press, and one undo putting both back. That check found the first bug too - the
VIEW was gating the right-click on `selection().size() == 2` before the builder ever saw it.

### The templates are atoms now

> "hydrogen class ships should be a single central shape, and large like 8000 m^3 ... as you moive
> vertically down the table it seeds nuclous count (1-8 for practicality all linked directly
> together with no tunnels) and a set of valence electron pods (the external pods linked by
> tunnels)."

Every class is a NUCLEUS - one body per proton, capped at eight, fused directly with no tunnels and
no hatches - plus one EXTREMITY per valence electron, each on its own tunnel. Period 1 has no
extremities at all, which is what makes hydrogen one module and helium a fused pair. The PERIOD
picks the geometry the extremities take and steps up when a class has more of them than that row's
arrangement has berths.

The measurement that matters, all sixteen classes:

```
hydrogen   1 nucleus,  0 ext,  1 part  -> 8000 m3 in one module
helium     2 nucleus,  0 ext,  2 parts -> 4000 each
carbon     6 nucleus,  4 ext, 14 parts ->  800 each
argon      8 nucleus,  8 ext, 24 parts ->  500 each
```

Every one of them totals **8000 m3**. That was the point - "keep default total volume constant
acrost all class ships" - so the classes differ in SHAPE rather than in size.

The span is solved rather than assumed. A box and a sphere of the same span are nowhere near the
same volume and these classes are defined BY volume, so `_span_for_volume()` tessellates the family
once with `ShapeMesh` and scales from there, volume going as the cube of the span. The exact mesher
earning its keep somewhere other than the bake.

Asked which rule governed helium - the author had described it as two pods and a tunnel, and also
said nucleus bodies link directly with no tunnels - they chose the general rule. Helium is the only
class with two bodies and no corridor.

### The rule that should already have existed

A carbon nucleus is host to NINE seams, and each is resolved against the result of the last. So one
broken boolean does not stay put: it feeds the next one. Measured, `small_native` left the nucleus
centre open after its four tunnels each subtracted from it in turn, and `big_flat_cutoff` did the
same nine plane-cuts deep.

`MeshFlange.resolve()` and `ShipMeshBake._cut()` now both refuse any result that opens a solid which
arrived closed - the same guard `_add_stub()` has carried since ADR 0012, generalised to every seam
operation instead of the one where it first bit. The cost is a joint left overlapping instead of
flush, which is a gap the author allowed for weeks ago, and it is a far better answer than an open
hull.

### Verified

`--import` clean; **gdUnit4 260/260**; selfcheck PASSED with the hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings - schema, `periods`, and sixteen rewritten
element descriptions all clean; gdformat and gdlint clean; windowed visual check PASSED, five modes,
exit 0.

Also committed: the repository had no commits at all, so `fd2579a` is the initial one - the whole
builder through M6. There is no git remote configured, so nothing was pushed.

### Still the human's to check

Open the START dialog and build a few classes. Hydrogen should be one big room you can cross
without a hatch; helium two fused halves with no corridor; carbon a six-body core with four arms;
argon the full sixteen. They should all feel like the same amount of ship.


## [2026-09-04c] The interior shell, and three levers that turned out to be one lever

> "now we need the inner shell surfaces made .. the hatch and seam surfaces remain solid seems ..
> about 20 cm thick hull by default. after each inner shape is created we need to subtract it from
> the outer shape to get our approx 20cm thick hull."

ADR 0011 named this as the one thing polygons were bad at, and used it as the reason to keep the
SDF bake around: offsetting a mesh inward by a constant is genuinely hard, and offsetting a field is
one subtraction. That is true of a mesh with no provenance, and this one has plenty. Every part
comes from a PARAMETRIC primitive, so the interior surface is the same primitive with smaller
numbers, carried through the same warps and the same transform. Exact for a box; correct to the
tessellation for everything round.

Both surfaces are seam-cut, and the interior's cuts are INSET - every plane pushed inward by the
wall, every neighbouring cutter fattened by it. That is what keeps the cavity off the seam faces, so
a module comes out a sealed shell rather than a tube with the ends open.

Measured on a hydrogen class: outer half-width 10.0000 m, inner 9.8000 m, **a wall of 0.2000 m**,
twelve faces - six outer and six inner - and zero open edges. Its 8000 m3 becomes 470 m3 of hull
around a 7530 m3 cavity. Carbon hollows all fourteen parts; argon twenty of twenty-four, the other
four being tunnels too narrow to have an interior at all, which is the honest answer.

### The part that took the time

The shipped wall was **0.15 m**, not the 0.4 the code default said - `data/tuning.json` had been
overriding it, which is why the tests had been passing against a number nobody had read lately.
Moving it to 0.20 m broke the invariant that two joined modules' interiors meet, and pulling that
thread turned up a chain of three:

- `attach_embed_m` 0.45 -> **0.60**. Two 0.20 m walls need more than 0.40 m of overlap before the
  cavities touch; 0.50 is the first value where every compact pair merges, and it leaves a
  connection a tenth of a metre deep that the validator sampled straight through.
- `tunnel_bore_m` 1.0 -> **1.4**. A tunnel cannot be seated into more deeply than its own radius -
  measured, a room on a 1.0 m bore reaches 0.503 however deep it is asked to go - so a 0.60 embed
  needs a 1.2 m bore at least. 1.4 leaves a 1.0 m clear corridor inside the walls.
- `SOLID_SAMPLE_STEPS` 10 -> **16**. What that probe looks for is a CAVITY, and a cavity shrinks
  with the wall. The giveaway that it was sampling rather than geometry: the answer was NOT
  MONOTONIC in the embed depth, flipping from eight unmerged joints to none and back as the overlap
  slid between grid lines.

Two wrong turns are worth recording because both were reasoned and both were wrong. The first was
pinning the embed test to a 0.4 m wall "because that is what it was tuned at" - it was tuned at
0.15, and a probe sweep showed thinner walls merge MORE easily, the opposite of what I had assumed.
The second was lengthening the tunnel to let it take a deeper embed, when the limit was the BORE:
0.503 was not half a length, it was a radius. Measuring first would have been faster than either.

### Verified

`--import` clean; **gdUnit4 264/264**; selfcheck PASSED with the hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual
check PASSED, five modes, exit 0.

Two tests now NAME the thickness they assert against rather than reading whatever the default is. A
seam plate's field lift is proportional to the wall, so a 0.05 threshold is the wrong question at
0.20 m. And every test about tessellation or seams builds with no wall at all, because a shell
changes every volume in the ship - a test asking "did this style cut differently" would otherwise be
reading the wall and the cut added together. Six times faster, too.

### Still the human's to check

Build a class and EXPLODE it. Each module should be a closed shell about 20 cm thick, with its seam
faces solid - no cavity showing through where two modules meet. Nothing has a way in yet; hatch
cutting and the frame between linked modules are next.


## [2026-09-04d] LINK is one command now, and an open seam finally opens

> "explode failed, and thats because i believe the link, and makeroom arent working properly.
> infact they shouldn't really be separate options, as when making a room it defines open
> structures at their link.. but i guess more is happening there as well so ill let you hash that
> out. - explode has some parts overlapping and thats incorrect."

Three defects, and all three were confirmed by measurement before a line changed. ADR 0016.

**Explode.** The offset cleared each module from its HOST, which is all one seam knows about, and
nothing separated SIBLINGS - which the atomic templates make ordinary, because a nucleus body and
an extremity draw their directions from two different arrangements that may point the same way.
The relaxation pushes overlapping modules further along their OWN normals, so the view still means
what it says. One thing had to be learnt the hard way: pushing BOTH of a near-parallel pair moves
them together and never separates them. Sending only the one already further out turns that pair
into a stack. All five classes now report zero overlapping pairs, with the exploded span 1.7-2x the
assembled one.

**Link.** `ShipSdf` honours the seam mode; `ShipMeshBake` - the exact path EXPLODE shows - read only
the seam STYLE. Sealed, doorway, hatched and open all baked to the same 24 faces and the same
514.89 m3. The pipeline swap had dropped the link modes and nothing noticed.

**Make room.** Its multi-part branch lifted the selection into a component, and the lift DROPS a
joint whose two ends are both inside it - which the comment there calls "removing the walls
between them". A wall is the ABSENCE of a record, so that walled every internal seam. 2 joints
before the lift, 0 after, none of them open: the exact opposite of what the button promised.

### Boring the wall out

An open seam leaves a plate of hull on each side - each interior stops the wall short of the
linkage surface, which is what keeps a module sealed. `_wall_between(cavity, body, other)` names
that plate without needing to know where the seam surface ended up: what one cavity reaches into
the other body and does not find cavity there. Taken from both sides, bored out of both shells.
Helium's protons go 294.83 -> 246.94 and 220.06 -> 172.17 m3 - a full 0.20 m plate off each - and
both stay CLOSED. An opened module is a cup, not a torn shell, so nothing downstream needs a case
for it.

Three shapes for that plate were tried and measured away first, each of them reasonable:

- **A zero inset at the seam pass.** Opens one side only. The interior pass computes its own
  crossing plane from the interior surfaces, which is not where the outer surfaces crossed.
- **The smaller part's whole interior.** Needs a "which is smaller" test, and helium's two protons
  are the same size to within float noise - the tie fell to the host and the bore did nothing. It
  would also have opened every other seam on that part at once.
- **The lens where the two interiors overlap.** For a fused pair that is most of the host's cavity
  and misses the plate entirely.

The reach is two walls rather than one because the hulls do not always touch: measured, the flange
put helium's cut 0.16 m past the host surface, and a one-wall reach took 0.04 m off a 0.20 m plate.

### What the accounting turned up

Of argon's 23 seams, 9 open and **14 were already one room**. The fused nucleus bodies overlap by a
third of their span, so their interiors interpenetrate by 97-159 m3 and were never separated at
all. That is a real gap against "the hatch and seam surfaces remain solid" - it holds per module,
not between two fused ones - and it belongs with the hatch work rather than here. One seam in one
class is a genuine miss: lithium's tunnel-to-nucleus joint, whose plates are 0.2 and 1.1 m3 and lie
outside both shells.

### Verified

`--import` clean; **gdUnit4 270/270** (six new: explode separation, `pairs_within`, the two-part
pair, `shared_mode`, the open bore, the pending count); selfcheck PASSED with the hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean over all seven
changed files; windowed visual check PASSED, five modes.

One self-inflicted detour worth recording: the first edit to `ship_visual_check.gd` cut from a
docstring to the next function I happened to name, which swallowed 344 lines of unrelated helpers.
The file was restored from HEAD with `git show` (a read command writing to disk, not a checkout)
and the edit redone against exact boundaries. Anchoring a deletion on "the next thing that looks
like the end" is how a patch takes more than it was pointed at.

### Still the human's to check

Select two modules that meet and press LINK four times: WALL, DOORWAY, HATCH, OPEN, and back. At
OPEN, explode and look into the pair - the hull between their interiors should be gone and a ring
of hull left around the opening. Select three or more and the same press should move every seam
between them at once. DOORWAY and HATCH still look like walls on purpose; that is the next piece.


## [2026-09-04e] A nucleus with nothing in the middle, and the fifty-two seconds that bought nothing

> "on the carbon class ship, (which has 5 protons around a central one which is wrong, the central
> one should be the singular top, and the 4 rim and lower added..) .. i click the 6 protons and make
> them an open room .. it reveals that the central completely burried one still exists .. also most
> of them arent shelled out properly, i see one that is, the others just appear to have been walled
> along parent surface."

Three reports; the first two are one defect seen from two sides. ADR 0017.

**The nucleus was a hub.** ADR 0014 laid the fused bodies on the arrangement holding `count - 1`
and put the last one at its CENTRE. So a carbon class had a sixth proton nobody could see, host to
five seams, which the bake then carved down to 5.9 m3 of slivers once the six were made one room -
71.9 m3 walled. That is the module in the exploded view. The fix is to sit the nucleus ON an
arrangement instead: six bodies on an octahedron, the root taking the slot nearest straight up and
the rest measured from it. Four rim at 45 degrees down and out, one straight below, and the root's
whole upper half in the open air.

The pods take slots of the SAME arrangement, most perpendicular to the root's first, so they land
around the waist - and each is built on the proton whose slot it shares rather than on the root.
That last part is not decoration: once the nucleus fills its own arrangement, a pod's slot is
occupied by a proton, and a tunnel from the root would set off straight through it. Measured before
that change, a rim proton had eaten the very face its own pod's tunnel was seated on.

**An open seam left one plate of two.** The bore from ADR 0016 built the wall between two cavities
and subtracted it - but on a fused pair only ONE of the two is ever cut by the flange, so only that
one had a plate to find. The other kept its own wall standing exactly where its neighbour meets it.

### The fifty-two seconds

Opening the five nucleus seams of a carbon class took **52 seconds**, and opened nothing. The bore
put a thin passage against a finished SHELL - two nearly parallel surfaces a wall apart - and the
BSP split until the split budget ran out, at which point `_cut` did the right thing and returned the
shell it had been given. Fifty-two seconds of work, discarded, and the report cheerfully said five
seams were open because the object identity had changed.

Two fixes were tried and measured before the right one. A slab about the true seam plane - the
flange knows where it cut, and I threaded it through for this - is the right REGION and made no
difference: 47 s. Boring the plain outer solid instead of the shell, which is the same set by
algebra and a much simpler operand, was 62 s. **The cost was never the operand. It was making the
cut at all.**

An open seam is the seam the interior is NOT cut at. Leave the cavity running at full extent through
where the seam face would be, and no plate is ever built to remove; take the neighbour's interior out
of this module's outer, and the wall on the other side is pierced too. Carbon went from 52 s to
**578 ms** - marginally faster than the same ship walled, because a skipped cut is a cut not made.
Argon shells in 3.0 s where ADR 0015 measured 7.6, and hollows all 24 parts rather than 20.

### Verified

`--import` clean; **gdUnit4 275/275** (five new: the nucleus has no centre, pods take nucleus slots,
a pod stands on its own proton, an open seam leaves no hull in the other room, and a nucleus made
one room stays closed and stays under a cliff-detector budget); selfcheck PASSED with the hash
unchanged at `5536787c6c35d236`; data validator PASSED, 0 warnings; all 22 classes bake with **0
unmerged joints, 0 validator issues, 0 open parts** and the 8000 m3 budget holding to within 24 m3;
gdformat and gdlint clean; windowed visual check PASSED, five modes.

Two tests had "the tunnel stands on the root" baked into them - they read `solids[doc.root]` while
styling the tunnel's joint. True until a pod moved onto its own proton, and then quietly measuring
the wrong part. They ask the document now.

### Still the human's to check

Build a carbon class and look at it assembled: a proton on top, four at 45 degrees below it, one
underneath, and a valence pod continuing out from each of the four rim protons. Select all six
protons, press LINK to OPEN, then EXPLODE - each module should be a cup, open where it meets its
neighbours, with no slab of hull left floating inside anyone's room and nothing buried in the
middle. DOORWAY and HATCH still look like walls on purpose; that is the next and last piece.


## [2026-09-04f] An open seam that meets on the real curve, and a rim that hangs where it should

> "the only correct one was the parent node .. the other 5 are not cut at intersection lines they
> are cut flat .. very shalow indents .. not a prooper uniforme thickness shell .. the 4 rim protons
> are not vertically centered .. the extending electrons are all pointed 45 degrees downward"

ADR 0018. Two of the five were the layout, three the seam, and the thickness one is a number: a
carbon proton is a 9.28 m cube and the wall is 0.20 m - 2.2% of its side. It is unchanged.

**The layout.** A child sits where the ray from its parent's centre strikes the surface and sinks
along the NORMAL there, taking that normal as its own +Y. The 45-degree rim ray of ADR 0017 struck
a box root exactly on an EDGE, where the normal is diagonal - so the rim tilted, the pods followed
it down, and at one seating depth 45 degrees can never be halfway to the bottom. A body now keeps
its slot's bearing and takes its fall from where the slot sits between the top of the arrangement
and its bottom: the rim hangs 30 degrees below level, lands 48% of the way down, mounts on a side
face, and its pod reaches straight out.

**The seam.** ADR 0017 skipped the interior cut and subtracted each module's room from the other's
outer. On a fused pair only one side is ever cut by the flange, so the root came out right and its
five neighbours came out cut flat with a shallow dent. An open seam is now resolved NATIVELY and
ASYMMETRICALLY off the bodies as built: the indented module loses the indenter's whole body - a
hole bounded by the true crossing curve - and the indenter loses what lies inside the indented
room, so its walls plug that hole for one skin's depth and stop. No gap, no double hull. And every
overlapping pair within a room is resolved, not only the tree's edges: a fused cluster has far
more neighbours than the attach tree has parents.

### What it took to get there

- **The tie.** Six protons of one class differ in the last bits, and a plain `>=` sent some of the
  root's children to each side of it - the root came out at 247 m3, one child at 528. One tie rule
  now, with a tolerance, for the flange, the native branch and the pierce alike.
- **The clearance, twice.** A millimetre off exact coincidence was measured in isolation as the
  right move (body grown, room shrunk); in the full bake it and a centimetre both put the cutter
  near-coplanar with the target and the BSP split into sliver cascades - 400 s and no finish. The
  other direction leaves a sliver that the merge welds open. It is held at zero.
- **A packed array is a value.** `(members[room] as PackedStringArray).append(id)` appended to a
  copy, every room came out empty, and six protons baked as six sealed shells. My own memory note.
- **PowerShell ate the docstrings.** A `Get-Content`/`Set-Content` round-trip on a BOM-less UTF-8
  file decoded it as the ANSI codepage: every em-dash became U+FFFD, and six docstrings I had
  never touched failed the line-length lint. Restored verbatim from HEAD by their ASCII skeleton;
  the whole tree scanned clean afterwards. Memory note saved: edit files with python only.

### What is still not right

Two of the six sibling cuts on a carbon nucleus are REFUSED. Same-size boxes centred on each
other's faces put faces on exactly the same planes everywhere, and once a target already carries
faces from an earlier cut on those planes, the BSP's coplanar path fails the guard. In isolation
every cut is right; accumulated, two rim protons keep 30 m3 of skin standing in the room beside
them. Robust coplanar handling in `MeshCsg` is the next piece of work, and it is now the only thing
between this and a nucleus that comes out entirely right.

### Verified

`--import` clean; **gdUnit4 275/275**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`;
data validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED, five
modes. Carbon with its six protons one room bakes in **640 ms**, every module closed: root 38.1 m3
with five passages and nothing in anyone's room.

### Still the human's to check

Build carbon: the rim should sit level halfway between the top and bottom proton, with a pod
reaching straight out from each rim proton. Select the six protons, LINK to OPEN, EXPLODE: the root
is a shell with five holes at the real crossing curves; four of the five around it are cut on the
curve too, two of them still carry a flat sibling face - that is the coplanar limit above.


## [2026-09-05] Humanity has figured out shells already

> "your techniques for making an inner and outer shell and closing it is 100% wrong. ive gotten the
> same result now 6-7 times in a row. so i feel like you arent listening to me."

> "if i had to make a shell... i would make a copy of the part, downsize or upsize slightly, then
> sub one fromn the other.. so whats the big deal here?"

They were right, twice, and the second line is the fix. ADR 0019.

**I was measuring the wrong shape.** `ShipTemplates.build(data, cfg, id, {})` builds boxes; the
author picks `sphere_pod` in the start dialog. Six rounds of "fixed and measured" on boxes changed
nothing on the author's screen, and it took a screenshot of a sphere with a bowl carved into a
SOLID to end it. On that shape the hollowing had failed every time: `outer - inner` through the
BSP on two concentric spheres of one tessellation gave 742 open edges and the wrong volume, the
guard refused it, and the module stayed solid - silently. Two lathes on one axis share every
longitude plane, the one thing a csg.js-style BSP cannot split.

**The big deal was that there is none.** The inner surface is strictly inside the outer by
construction, so the shell is the outer surface plus the inner turned inside out - Blender's
Solidify, no boolean. Hydrogen: 370.9 m3 to the decimal, zero open edges, 12 ms. Every class on
spheres now hollows every part (carbon 14 of 14, zero open).

**A room is a union of surfaces, not of solids.** A chain of five BSP unions to fuse six protons
did not finish in 400 s. Each member's surface clipped against the other members' distance fields
- keep what is outside, bisect the crossings on each edge - is linear, cannot hang, and is exact to
the tessellation: the same room in 3.2 s, one hollow mesh, five members absorbed into it. The bore,
the skip-and-pierce and the native asymmetric cut of the last three ADRs are all gone; a union has
no seam faces to open.

What is not right: the room's seams are hairlines, each side bisected on its own edges, agreeing
only to a segment's sagitta - about 6 cm on a 9 m sphere. 464 open edges on the carbon room, a
faint lip on screen. Stitching them to one shared curve is next.

### Verified

`--import` clean; **gdUnit4 275/275** (two per-part open-seam tests replaced by a room test and a
sphere-shell test that builds hydrogen, helium and carbon on `sphere_pod` - the first tests ever to);
selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat
and gdlint clean; windowed visual check PASSED, five modes. A PowerShell text round-trip destroyed
six docstrings' em-dashes along the way (restored verbatim from HEAD); memory notes saved for that,
for the family, and for nesting.

### Still the human's to check

Build carbon ON SPHERE PODS. Explode: every module a hollow shell of uniform wall. Select the six
protons, LINK to OPEN, explode again: the room is one hollow mesh, its members meeting on their
real crossing curves, with a faint seam line where two spheres join.


## [2026-09-05b] The engine does the booleans

> "the assembled room doesnt explode into its pieces .. the sphere one has the electron pods all
> angled down below the craft making a pyrimid. all shaped hull versions should look the same .. only
> half of the tunnel-to-module connections cut .. we need the shell to be about 10-20cm .. where seams
> exist i can see a gap to the exterior of the hull, very small."

Five reports; ADR 0020 answers all five, and the answer is the one the author gave: "humanity has
figured out shells already". Godot 4.4+ backs its CSG nodes with Manifold, an exact mesh-boolean
engine, and it was sitting unused because core/ keeps clear of Nodes. Four generations of hand-built
booleans were tried in this session - a BSP, nested shells with BSP unions, distance-field clipping,
a shared-segment seam splitter - and each fixed the previous failure and exposed the next. The last
two could not make the two sides of a curved seam share a vertex: hundreds of open edges per sphere
piece, the "very small gap". Measured, the engine built a helium shell, a hole and a wall-stop
closed, in under 80 ms.

**The split:** core/ PLANS (`ShipMeshBake.plan()` - every part's three surfaces, and which cutter
takes which surface at every seam) and `ShipCsgBake` in harness/ EXECUTES with CSG nodes, awaiting
the frames the engine takes. The pure bake carries the same plan out with its own clipping and is
the tree-less fallback. One plan, two executors, no second reading of the seams.

**Measured on both families.** Carbon on spheres and on boxes, walled and as one room: every part a
closed shell, every tunnel's pod with its socket (967 faces where a plain shell has 576), the open
room six separate pieces with the root holed five times - zero open parts in all four cases, 2-4 s.
Pods reach level on both families now (their direction is named in ship space and converted into
the proton's frame at build time; a sphere's mount normal is the 30-degree ray itself, which is
where the pyramid came from). The rim sits 49% of the way down. The wall is 0.10 m.

### The detours, so they are not taken again

- Every probe before this day measured boxes; the author builds with sphere pods. Memory note.
- The first engine bake of a run came back empty: CSG computes on a deferred call, and one frame
  was not enough. `ShipCsgBake` now waits until every combiner has a mesh.
- A `PackedStringArray` appended through a Dictionary is a copy. My own memory note, hit again.
- A PowerShell `Get-Content`/`Set-Content` round-trip destroyed six docstrings' em-dashes.

### Verified

`--import` clean; **gdUnit4 278/278** (three new in `tests/harness/test_csg_bake.gd`, building on
sphere_pod AND box_hull; five pure-path tests re-scoped to what that path promises); selfcheck
PASSED, hash unchanged at `5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint
clean; windowed visual check PASSED, five modes, with EXPLODE now on the engine bake ("13 modules
baked from 12 seams .. 13 visuals back after ASSEMBLE").

### Still the human's to check

Build carbon on sphere pods, and again on boxes: rim level and halfway down, pods straight out on
both. Explode: every module a hollow shell of 10 cm, every pod with a socket where its tunnel meets
it. Link the six protons OPEN and explode again: six pieces, each with holes on the real curves,
nothing left inside anyone's room. Flat versus native styles look the same for now - F32 item 1.


## [2026-09-05c] A room is built whole and cut back into its pieces

> "the central proton doesnt resolve correctly. - to fix this we need to union all proton chunks ..
> then make the interior mesh by .. down sizing them slightly, unioning all those smaller chunks ..
> subtracting .. then we re cut the single mesh using orignal data .. this should make perfect shell
> chunks. and yea use godots stuff or existing stuff no need to reinvent the wheel."

Built exactly as written, in two engine passes (ADR 0021): the room's shell as the union of its
members' bodies less the union of their interiors - each member's walled sockets cut in first - and
then each piece as that shell intersected with the member's original body, less the bodies of the
members before it, so the shell is partitioned rather than counted twice where chunks overlap. The
per-part rule it replaces was right for a pair and wrong for a hub: the root kept slabs of its own
skin inside its neighbours' walls, which is the central proton in the author's picture.

One thing bit on the way: pass one's shell has to go back into pass two as the ENGINE's mesh. Read
back as merged n-gons with holed faces and re-triangulated, it is not a manifold the engine accepts,
and a box nucleus came back with a 348 m3 "piece" of a 50 m3 shell. The engine's own triangles are
the operand; the merge is for the wireframe only.

**Measured.** Carbon on spheres and on boxes, one room of six: every piece closed, zero open parts;
sphere root 14.6 m3, rims 24.0, bottom 15.3; box 18.9 / 29.3 / 19.0. And, measured by the engine
itself, every piece intersected with every other member's interior body has no volume - the test
that pins the complaint.

### Verified

**gdUnit4 279/279** (one new, engine-measured, both families); selfcheck PASSED, hash unchanged at
`5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual
check PASSED, five modes.

### Still the human's to check

Six protons linked OPEN, exploded: six shell pieces from one shell, the central one hollow with
five holes and nothing of it left inside its neighbours.


## [2026-09-05d] Halves, rooms whole, and the interior view

> "any module .. need to get sliced down the middle in the explode group (in manufacturing they
> are made in 2 pieces) .. an explode control toggle to choose to explode rooms or keep them whole
> .. a special render mode that renders the faces of the interior mesh, and the backs of the
> exterior mesh only. the rest should become translucent/holographic wireframe"

ADR 0022. The plan names each part's manufacturing plane (through its origin, normal its local Z -
a clamshell, never across a bore); the engine bake's third pass halves every finished solid, and
every room's whole shell too, so the `ROOMS: PIECES / WHOLE` toggle has both to show. Every mesh
the view draws now carries its faces in three named surfaces, and the INTERIOR mode draws them
apart: interior and cuts lit and opaque, the exterior's backs opaque and its fronts a ghost in one
two-pass material, wire over the lot. The far wall faces the camera whatever the angle.

### What the classification taught

- **Not by planes.** A lathe's quads are not planar; the engine re-triangulates them its own way;
  measured, no baked face matched an input plane. By corners against the distance fields instead.
- **Not on the field's zero either.** A box's mesh is the fillet's CORE and its field the rounded
  envelope: every corner, edge and face centre of a carbon box read -0.200 m. Calibrated per
  surface off its own corners. Recorded as F34 item 1 - it is a real, small, systematic error.
- `ArrayMesh.surface_find_by_name`, not `surface_find_name` - a runtime error that also masqueraded
  as a probe timeout. And the engine's triangle order is the project's outward winding: reversed,
  the merge tore two halves.
- A tail-replace that took every helper after the classifier with it; restored from what was
  written, not from memory of it.

### Verified

**gdUnit4 281/281**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED, five modes. Measured on
carbon, both families, walled and one room: 14 of 14 parts halved, every half closed, every pair
summing to its piece, 14 of 14 meshes naming exterior and interior, zero open parts.

### Still the human's to check

Explode: every module in two halves, pulled a little apart. Toggle ROOMS to WHOLE with a linked
nucleus: one shell in two halves. Switch the mode to INTERIOR: the near wall goes to ghost and
wire, the far cavity wall and the sliced wall thickness stay solid, from any angle.


## [2026-09-06] The baked view, its update, and the ghost

> "carbon ships should have its proton pre resolved .. open rooms by default on proton clumps ..
> i change them to open room.. and nothing changes in render .. a button highlighted at top should
> say update meshes and next to it a toggle auto update meshes .. a loading bar .. research a
> quick ghost renderer that ray marches the hull changes by the sdf info"

ADR 0023. The assembled scene was the preview primitives; only the exploded view had ever drawn
the engine's pieces, so no link change could show assembled. Now: a template's nucleus is one open
room as built; the assembled view is the baked pieces once a bake exists (ASSEMBLE lands there);
every edit lights UPDATE MESHES and, with AUTO on (default - a carbon resolves on load), queues the
re-bake; a bar in the status row moves with the engine's passes and the view's placement; and a
GPU ray-marcher - the resolved shapes as uniforms, ResolvedShape.sdf op for op in GLSL - ghosts
the hull in the warning colour the frame the document changes, writing its own depth so it sorts
against the stale pieces, and fades once the update lands.

### The research, answered

Instant feedback off the fields alone is achievable and now exists: no bake, no mesh, one box
with a shader, on screen the same frame. It cannot know walls (that is the bake's), so the two
halves stay: the ghost for the moment, the update for the truth.

### Measured on the way

- The demo ship's bake lands inside a dozen frames, so its ghost is a blink and the check samples
  at frame 2; a carbon of spheres bakes in 9-12 s and the ghost carries the wait.
- A ProgressBar in this theme has no boxes: `visible` on, nothing drawn. Styled by hand.
- A `PackedStringArray` handed to `ShipCheckViews._init` is SHARED: merging it back at the report
  doubled every failure line. The earlier "value type" note was the Dictionary-element case;
  memory corrected.
- The nudge in the update stage sits a part on the mirror plane: its twin appeared and the module
  count went 13 to 14. The stage counts after its edit now.

### Verified

**gdUnit4 281/281** (two new tests); selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data
validator PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED, five modes
plus the explode and update stages; `reports/visual_ghost.png` shows the ghost over the stale
pieces, `reports/visual_update.png` the baked view after.

### Still the human's to check

Open a carbon: the primitives, then the baked pieces landing with the bar; the nucleus already one
room in INTERIOR. Change a link: the button lights, the red ghost, the re-bake. Flip AUTO off and
edit: the ghost stays until UPDATE MESHES is pressed.


## [2026-09-06b] Components are rooms, the nucleus is the root component, the ghost withdrawn

> "the proton should be classified as a component (by default) .. double clicking like in
> sketchup we can wash out the rest .. import components .. including the ship as a component
> itself, and components containing more components .. fix our bakes to be component based ..
> just kill the ghost view .. we force the update button"

ADR 0024. Five asks, one model change underneath them: a part may hang off an INNER part of a
component instance. With that, the template lifts the six protons into the ship's root component
and hangs the tunnels off the protons they were laid out for; a component instance is one room by
membership (no joints), its inner seams are open, and the engine bake keys every piece - inner
parts included - so the exploded and baked views draw a module per piece. Click a proton and the
nucleus lights; double-click and it opens - the rest washed out, its parts picked one by one and
edited through the inspector, every instance following; ESC closes it. IMPORT COMPONENTS on the
palette brings every definition of another saved ship across, references remapped, and the ship
itself as one more. INTERIOR draws the interior's fronts and the exterior's backs and nothing
else. The ghost ray-marcher and AUTO are gone: nothing bakes by itself, the button lights.

### Measured on the way

- `make_component` already lifts the root (the instance becomes the root) and already allows
  nesting; the missing piece was a parent that is an inner part. `ShipAttach` expands an instance
  when it is placed, not after the loop, and everything that walks parents normalises through
  `ShipComponents.instance_of`.
- The nucleus instance had no `asymmetric` flag, so its rim protons grew mirror twins (`~m`) and
  the root itself overlapped its own twin on explode. The template marks it asymmetric as it does
  every part.
- The room join written after the rooms were assembled joined nothing; the assembly is a loop
  one screen above `var rooms`.
- gdUnit stops a suite at its first failure: "Executed (8/8)" is not a crash.
- A `ProgressBar` in this theme has no boxes; a bar with `visible` on drew nothing. Styled by
  hand (ADR 0023's bar, kept).

### Verified

**gdUnit4 286/286**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED - five modes, explode
(13 modules), update (14 baked assembled, button lit then cleared), isolation (a two-part
component opened: 10 washed, 4 kept, inner pick `p_0012/cp_0002`, closed on ESC).

### Still the human's to check

Open a carbon: one row for the nucleus in the tree, tunnels under it; click a proton and all six
light; double-click and the ship washes out around them; click one proton, change its scale in
the inspector, watch every instance follow; ESC. UPDATE MESHES, then INTERIOR: the near wall
gone, the far cavity wall solid. Save the carbon, NEW a hydrogen, IMPORT COMPONENTS -> the
carbon's nucleus and the carbon itself in the palette; place the carbon on the hydrogen.

## [2026-09-06c] INTERIOR on the baked pieces, and LINK inside a component

> "after bake interior render doesnt work right. - the default proton pieces arent defaulted to a
> room link. so i double clicked the component so i could select all the sub components and link
> as room and that wouldnt let me either."

Two causes, both plain once measured. The INTERIOR mode dressed the interior surface in the
faceted shader, which is `cull_disabled` by design - so the interior drew both its sides and the
ship read solid from outside, exactly as before the mode existed. It now wears two variants of
that shader built at load by editing the one render_mode word (interior: back-culled, exterior:
front-culled), and `reports/visual_interior.png` shows the baked demo with its near walls gone and
its far cavity walls and sockets facing the camera. And `ShipSeams.pairs_within` knew only
`doc.parts`, so the six protons - inner parts of the root component since ADR 0024 - never paired
and LINK answered "nothing in the selection is joined". Inner parts pair with what they hang from
now, `mode_for` reads OPEN for two parts of one instance without a joint, and LINK on them says
why it will not cycle: they are one room already; dissolve the component to wall them. The tree's
instance row reads `(6 PARTS, ONE ROOM)` so the default is visible without a bake.

### Verified

gdUnit4 **287/287** (new: a component's inner parts pair, read open, and a tunnel on an inner
proton keeps its hatch); selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED with the interior
frame saved from the baked view.

### Still the human's to check

UPDATE MESHES, then INTERIOR: the near wall gone, the far cavity wall solid and shaded, the
sockets cut through. Double-click the nucleus, select two protons, LINK: the refusal names the
reason. The tree row: `C NUCLEUS (6 PARTS, ONE ROOM)`.


## [2026-09-06d] A component's links live in its definition

> "i dont care if they are already a room, they are a room made of chunks and i should be able
> to change their internal chunk link types. (AND I SHOULD BE SET TO OPEN ROOM BY DEFAULT and its
> not). - i try to import components but it says 'theres no ships' yet we have an entire fleet of
> default ships made? .. going into a component shouldnt block me from doing anything."

ADR 0025. The membership rule of ADR 0024 - a component is one room, no joint behind it - was
the wrong abstraction and it showed as a refusal. Now a definition holds the joints between its
own parts, exactly as the document holds those between its own: `ShipSeams` routes an inner
pair to its definition, so LINK, the seam styles, the SDF, the plan and the engine bake all read
the same answer; the nucleus is lifted with OPEN joints written in, so it IS an open room by
default and says so; the links move with the parts at lift, at dissolve and at import (an
imported ship keeps its walls and hatches). IMPORT COMPONENTS lists the fleet - every atomic
class, built in the importing ship's own room family - ahead of the saved files. The builder's
import flow and bake HUD moved into two small classes to stay under its line cap; measured on the
way, the first HUD was handed a null button because the status row is built before the toolbar.

### Verified

**gdUnit4 287/287**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED (five modes, explode,
update with the interior frame, isolation).

### Still the human's to check

Double-click the nucleus, select two protons, LINK: it cycles (wall / doorway / hatched / open)
and the status names the pair; the seam menu on two protons styles their seam. New carbon: the
protons are open already - UPDATE MESHES, INTERIOR, the cavities run through. IMPORT COMPONENTS
on any ship: the list starts with `CLASS: hydrogen` and the rest of the fleet.


## [2026-09-06e] Imports: a primitive root, the arms, and the host's size

> "importing components is freezing the system .. i dont see the tunnels used in the model, and
> i dont see the electrons .. the proton cluster came in way way too large, like 5x .. the entire
> carbon class ship as a component module .. basically froze .. adding any component as a single
> primitive, a wing, a proton cluster, or an entire ship should all act the exact same."

ADR 0026. Measured headlessly first: nothing in core takes more than half a second, but the
whole-ship definition's root was the nucleus instance - and an instance has no shape of its own,
so the ship instance had no proxy shape and no protons under it, and the builder was handed a
part with nothing to draw. `import_from` now flattens the source ship before making its
definition, and `make_component` refuses an instance head: every definition's root is a
primitive. An import offers the ship's arms too - each subtree off the root, identical arms
once - so a carbon arrives as its nucleus, `CARBON ARM 1` (tunnel and pod) and `CARBON`. And a
class is built at the host ship's own span, bore and length, read off its shapes: the class
defaults are sized per class by a volume budget (a carbon's proton 11.8 m, a hydrogen's
25.5 m), which is the "5x".

### Verified

**gdUnit4 289/289**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED. Headless probe:
the ship instance has a proxy, 19 keys under it, 29 parts in the field; the carbon rebuilt from
a host built at span 8.0 / bore 2.2 has the same proton within a centimetre.

### Still the human's to check

IMPORT COMPONENTS -> `CLASS: carbon` into your ship: three entries - nucleus, ARM 1, CARBON.
Place each: the nucleus at your protons' size, the arm as a tunnel with its pod, the whole ship
as one part that drops onto a surface like a primitive.


## [2026-09-06f] Default hatches, the LINK crash, and the phase-one review

> "selected a tunnel and the main proton room, and tried to change their link to hatch and the
> system crashed .. all default pre-made ships, and any future procedurally generated ones should
> have hatch connections between each and every tunnel and linked module by default"

ADR 0027. The crash was the one `doc.parts[...]` left on the LINK path - the tree's status line
- fed an inner part of the open component; it reads through `part_at` now, and the seam menu's
pairs come from `pairs_within`, which knows what hangs off what inside a component. The "400
warnings" before it were ADR 0026's shapeless whole-ship instance, already gone. Hatches by
default: `ShipSeams.default_link_for` answers HATCHED wherever a hallway meets a room by role
(an instance by its definition root's role, so an imported arm hatches onto a proton), and the
builder applies it when a placement commits. The templates already did both ends of every
tunnel; placed and generated tunnels now behave the same.

The Phase One Hull Review was written as an artifact: state measured, strains named, eight
ranked recommendations (room-keyed bake cache first), a tooltip contract, four risks, and the
phase-1 scope stated - deliver, do not preclude, do not build.

### Verified

**gdUnit4 290/290**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED.

### Still the human's to check

Open the carbon component, select a tunnel and the main proton, LINK: it cycles and names the
pair, no crash. Place a tunnel on a proton, or an imported ARM: the seam reads HATCHED without
a click.


## [2026-09-06g] A ship arrives resolved; the interior is its own mesh

> "the damn ships should be fully resolved .. when i load it its like that and i dont have to do
> anything" / "the inner mesh and outer mesh of the hull as a single mesh .. the correct way is
> for the exterior mesh and the interior mesh to be separate"

ADR 0028. The document had been resolved since ADR 0025; the screen showed six primitive spheres
over one another until a button was pressed. A ship now bakes itself on arrival - class, file or
blank - with the bar up, and the baked pieces stay on screen while the player works (only the
primitives the bake covers hide). Measured on the exact scenario, no press: 14 modules, one room
of six, eight hatches, zero primitives. On the way: a bake landing for a document since replaced
was shown for the new ship (the chooser's blank ship under the carbon) - discarded now.

INTERIOR was wrong the whole time for one reason: Godot's front face is CLOCKWISE, the engine's
pieces wind by the right-hand rule, and the faceted shader's `cull_disabled` had hidden that
from every other mode. The culls are the right way round now, the interior is a separate mesh
node per piece as asked, nothing is double-sided, and the cavity shades as a hollow. The frame:
one continuous cavity across the six protons, tunnel mouths open into the pods, wall thickness at
the rims. A cutaway plane was built and measured on the way - it hid half the ship - and is
plumbed but unused.

### Verified

**gdUnit4 290/290**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED; resolve check PASSED
with `reports/visual_resolved_{wire,shaded,interior}.png`.

### Still the human's to check

Pick a carbon, wait for the bar: one fused nucleus, no press. WIRE, then INTERIOR: the cavity
runs through all six protons and out the tunnels into the pods.


## [2026-09-06h] An opening is capped, collared and doored on both sides

> "where we cut holes for hatches, and openings, we need those manifold meshes to cap the
> exposed open hole edges .. a hatch that can open or close shutter eye style, double hung door
> style, and single hinge door style .. each hatch will be a double hatch with one on each
> module .. a thin flat faced cylinder .. that extends into each module just enough to give a
> flat manifold gasket .. the user should be able to choose the general shape .. the dimensions
> .. and the style"

ADR 0029. A hatched seam had never been bored: the plan counted it PENDING and cut a wall. Now
`ShipDoors` (core) puts a gasket plane where the seam axis crosses the indenting module's mesh
and gives each module, on its own side, a collar to union, a clearing prism and the bore to
subtract; the engine's third pass carries them out and Manifold caps every rim by construction.
The leaves - single hinge, double, iris - are built per module at any amount open and swung on
a tween; the inspector's HATCH section chooses family, shape, style, width and height within
the seam's own maximum and the 0.5 m squeeze, sides for a polygon, and swings each door.

Three things were measured on the way and are written into the code. A spar's field zero sits
0.094 m outside the cap the engine builds (F34 again): every field is now read at its own mesh,
and the plane is cast onto the tessellation. A bore through a 0.1 m cap costs 0.0376 m3 and the
collar bridging the cap's dome gives back 0.005. And the merge that reads the engine's triangles
back as n-gons bridged three annular faces into closed solids 0.4-0.5 m3 too big - so a merge is
kept only when its volume matches the triangles.

### Verified

**gdUnit4 300/300**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator
PASSED, 0 warnings; gdformat and gdlint clean; windowed visual check PASSED; resolve check PASSED
with `reports/visual_resolved_{wire,shaded,interior,doors}.png` - 8 doors planned, 12 pieces
bored, none open, a leaf on every piece.

### Still the human's to check

Pick a carbon, wait for the bar. Select a tunnel: the HATCH section shows CRAWLWAY, CIRCLE,
SINGLE, 0.70 x 0.70 M and the seam's maximum; press a DOOR button and the leaf swings into its
module. INTERIOR: the hole through each tunnel cap with its rim capped. Change the shape to
POLYGON and the style to IRIS, UPDATE MESHES, and press DOOR again.


## [2026-09-21] Commits, the godot-ai updater, the MCP back, and a home for future phases

> "the mcp must be working for advanced accurate development ... it claims i cannot update it"

Everything from ADR 0016 to 0029 had never been committed; it is now (`bf17455`, one unit, the
ADRs overlap hunk by hunk). The stop-lint hook was linting the vendored `addons/` tree after the
godot-ai plugin self-updated there; it skips `addons/` now.

The dock's Update refused godot-ai 4.1.0 for a reason in the plugin, not this repo: GitHub
redirects a release download to `release-assets.githubusercontent.com/github-production-release-asset/...`
and the plugin's allow-list expects `/github-production-release-asset-...`. Measured with the
plugin's own `_is_trusted_download_url`: first hop true, redirect false. Still so on upstream main
and in 4.1.0, and unreported. 4.1.0 was installed by hand: the plugin's `ReleaseVerifier` passed
the signed manifest and archive, all 293 files matched the inventory, 4.0.0 kept in
`addons/.godot_ai_update/backup/4.0.0` (`8785742`).

The MCP had been failing with `TRANSPORT_AUTH_REQUIRED`: v4 authenticates HTTP with a capability
that changes per server instance, so `.mcp.json`'s plain HTTP entry could never connect. It is
removed; the dock's Configure registered the `godot-ai attach` stdio bridge at user scope.

`docs/future/` is new: design notes for phases not built yet, not CONTRACT, read by no code, and
promoted to SPEC + ADR when their phase starts. First note, `texturing.md`: seam bands (rivets,
bolts, welds, hidden fastener ribbons, a growing catalogue the player picks per seam) and panels
textured in their primitive's own coordinates, with what it asks of earlier phases - face
provenance through the bake, a band field on the joint, a styles pack.

### Verified

Bridge driven over stdio: 46 tools, `editor_state` answered from the live editor; the same calls
from this session's own tools; the editor error log empty after the plugin swap. No `core/`,
`data/` or `harness/` change, so no test run was needed.


## [2026-09-21b] The bake makes what is on screen; the exploded extras wait for the first ask

> "we will take off from the top and continue" / "1) yes 2) yes 3) now, go ahead with step 1"

ADR 0030, step 1 of the Phase One Hull Review's first recommendation. Measured first: a carbon of
spheres baked in 19.0 s and a second bake of the same ship cost the same. 7.6 s of it was the
n-gon merge on read-back, and the bake read back 58 times, of which 14 are the ship on screen.
`ShipCsgBake.bake()` now makes the assembled ship only, reading each piece once after its doors;
`bake_extras()` makes the halves and whole rooms from that report on the first EXPLODE or
ROOMS: WHOLE. The builder's bake state moved into `ShipBakeSession` (`ShipBuilder` 1997 -> 1985
lines). On the way: the view had always read `room_shell_halves`, which no bake wrote, so a whole
room exploded unhalved; the extras write it.

The author's answers to the texturing questions went into `docs/future/texturing.md`: band width a
range with 0 for none, surface only, an edge function per mesh chunk, mirror follows the component
path, textures from the author's own pipeline. The bake's per-primitive chunks are recorded there as
load-bearing. `docs/future/symmetry.md` is new: mirror on any combination of X, Y and Z, and radial,
point and repeat symmetry for later.

### Verified

Identical geometry: both families of the template carbon, before and after, field by field (every
piece, surface, half, whole room, bored set): **zero differences**. Assembled bake 19.3 -> 6.0 s on
spheres and 8.9 -> 2.9 s on boxes; extras 9.7 s and 4.0 s. **gdUnit4 301/301**; selfcheck PASSED,
hash unchanged at `5536787c6c35d236`; data validator PASSED, 0 warnings; gdformat and gdlint clean;
windowed visual check PASSED (EXPLODE, ASSEMBLE, UPDATE); resolve check PASSED (14 modules, a room of
6, 8 doors, 12 pieces bored, 16 leaves).

### Still the human's to check

Pick a carbon of spheres: the bar should finish in about a third of the old time. Press EXPLODE:
"HALVING THE PIECES..." and the bar again, then every module in two. ASSEMBLE and EXPLODE again:
instant. Toggle ROOMS: WHOLE while exploded: the nucleus shows as one shell, now also in two halves.


## [2026-09-21c] Explode options: separations, and a slicer in each part's own axes

> "explode looks cool, but i want to make it AAA ... a part separation toggle with a slider ... 3
> orthogonal slices, and offer single slice or double slice in each orthogonal direction ... a
> nodecluster bisector includer toggle ... " / "exact slow bake, then cache and animations"

ADR 0031. An EXPLODE OPTIONS panel docks over the 3D view while it is exploded. SEPARATE MODULES
with its gap; a slicer with X, Y RADIAL and Z each OFF, BISECT or TRISECT, and a slice gap; SLICE
CLUSTER CHUNKS with its own three axes and gap; APPLY SLICES. Every part is cut in its own frame, Y
its placement normal, at equal divisions of its original body's extent, by the engine, one axis at a
time. The gaps move what is on screen at once with no rebake; the slicer lights APPLY, which re-cuts.
The settings live in `user://explode_settings.json`, never in a ship file. The default is the old
single cut across Z.

Found by looking at the frames, not by the tests: with the clusters cut on X and the parts on Y,
every standalone piece came out whole. The slicer re-read every job after each axis, and a job not
cut on that axis lost its cells. Fixed, and the test and the check now assert the slices made rather
than the counts asked for.

### Verified

**gdUnit4 307/307** (six new in `test_explode_slicing.gd`); selfcheck PASSED, hash unchanged at
`5536787c6c35d236`; data validator PASSED; gdformat and gdlint clean; windowed visual check and
resolve check PASSED; the new windowed explode check PASSED: default 14 of 14 pieces bisected;
parts trisected on Y and cluster chunks bisected on X, 8 and 6, 72 nodes; a wider gap moved a piece
3.4 m with no rebake; separation off put every module back on its seam. Frames:
`reports/visual_explode_{default,sliced,spread}.png`.

### Still the human's to check

Pick a carbon and press EXPLODE: the panel in the top right. Drag GAP and SLICE GAP: the pieces
follow live. Set Y RADIAL to TRISECT: APPLY SLICES lights; press it and wait for the bar: every pod
in three bands along the way it points. Turn SLICE CLUSTER CHUNKS off and APPLY: the nucleus chunks
whole, the pods still sliced. Close the builder and reopen: the settings are as you left them.


## [2026-09-21d] The ship lives in its fundamental cells; the explode is animated

> "no the animation doesnt work, it is like a slow pop in ... it bakes when i change a setting.
> this is incorrect. all nodes should be both bisected, and trisected leaving 4 total chunks ...
> changing a setting is simply relocating the positions of those fundamental pieces" / "i dont care
> if the seams are shown in wireframe mode"

ADR 0032, amending ADR 0031 the same day. Every piece, cluster chunks and whole rooms included, is
cut once at 1/3, 1/2 and 2/3 along each axis of its own frame: 64 fundamental cells, independent of
every setting. BISECT and TRISECT are groupings of those cells, APPLY SLICES is gone, and every
setting only moves them. The explode is animated in the author's three stages: modules part, then a
room's chunks, then the slices. It has SPEED and POSITION sliders, and ASSEMBLE plays it backwards
before handing back to the whole pieces. The one-module-a-frame queue that read as a pop-in now only
serves the field fallback.

Measured first, so the cost was known before it was built. On the carbon the engine cut 713 cells in
about 4 s, but reading them back with the n-gon merge took 30.7 s. Cells are read back welded
instead, with a feature-edge wireframe: 9.6 s in all, the same as the two-halves extras.

One slip, caught and fixed: a PowerShell `Set-Content -Encoding utf8` wrote a BOM into
`ship_csg_bake.gd`; stripped with python, and the memory note now says so.

### Verified

**gdUnit4 309/309** (`test_explode_slicing.gd` rewritten, eight tests); selfcheck PASSED, hash
unchanged at `5536787c6c35d236`; data validator PASSED; gdformat and gdlint clean; windowed visual
check and resolve check PASSED; the windowed explode check PASSED: 14 pieces in 656 cells built in
474 ms and carried out; a slicer change, a POSITION scrub and wider gaps each moved the pieces with
no bake; separation off; ASSEMBLE played back and landed on the 14 whole pieces. Frames:
`reports/visual_explode_{default,sliced,half,spread}.png`.

### Still the human's to check

Pick a carbon and press EXPLODE: after the cut, the pieces fly apart in three beats. Drag POSITION
back and forth. Change the slicer axes: the pieces regroup at once, no bar. Drag SPEED down and press
ASSEMBLE: it comes back together slowly, then shows the whole pieces.


## [2026-09-22] Every ship is built around a beacon, and a room is cut as one body

> "the carbon atom (and other ship) that dont have a central node, end up with an initial parent
> thats non central .. the proper way would be to use a beacon or reference node thats invisible but
> still there where things can grow away from that" / "all should have this central build beacon,
> even if a module lays simply over it with no offset .. it can be entirely internal and viewable as
> a dot"

ADR 0033. Measured first: `ShipAttach` pinned the ROOT to the origin, so a class whose arrangement
has nothing at its middle put its first module there instead of its centre - a carbon 3.56 m off,
helium 6.24 m, neon 3.89 m - and the slicer, which cuts each piece in its own frame, then cut one
nucleus on six differently tilted grids (0°, four at 118°, one at 180°). That is what the author saw.

The root is anchored to the beacon by its own `absolute` now, which is F9's dead field given a job,
and every class is laid out so its core rings the beacon. The anchor travels with whatever becomes
the root through MAKE COMP and dissolve. A room's cells are cut in one shared frame across the whole
room, so a nucleus slices like the single body it is. The beacon is drawn as a dot that reads through
the hull.

Two tests turned out to be asserting on accidents, and centring exposed both: a dissolved helium grew
a mirror twin of its root (the template's root module now stands outside symmetry, like every other
part it makes), and the in/out bump test compared the SUM of part volumes, where the two styles
nearly cancel - twelve parts differ by 0.95 to 1.95 m³ each while the sum differed by 0.0055 on a
6287 m³ ship. It asserts on the parts now.

### Verified

Carbon, helium, neon and hydrogen centre their cores to within 0.01 m; a carbon's cells fall from 656
to 534 on one shared grid. **gdUnit4 314/314** (`tests/core/test_beacon.gd`, five new); selfcheck
PASSED, hash unchanged at `5536787c6c35d236`; data validator PASSED; gdformat and gdlint clean;
windowed visual, resolve and explode checks PASSED. Frame: `reports/visual_beacon.png` - the dot at
the centre of the nucleus it is built around.

### Still the human's to check

Load a carbon: the teal dot sits at the middle of the nucleus, and the nucleus rings it rather than
hanging below its top proton. Explode and set SLICES Y RADIAL to TRISECT with SLICE CLUSTER CHUNKS
on: the nucleus chunks now cut on one grid instead of six.


## [2026-09-22] The nucleus rings the beacon, and parts side by side have seams

> "i built a carbon with cube rooms and the center proton was not centered top and bottom etc, and
> when i exploded it it did not yeild parts that were expected, which in this exact case would be 6
> little square slabs, theoretically speaking."

ADR 0034. The beacon (ADR 0033) put the ship's centre at the origin and it was there - the carbon's
core centroid measured 0.00 - but ADR 0017 still hung each nucleus body off the one before it, on
the surface, and a surface seat lands along the host's NORMAL. On a sphere that is the direction it
was aimed; on a CUBE a 45 degree ray strikes a side face and the body slides sideways. Measured: a
cube carbon's root at +2.76, its four rim bodies at y = 0 and its bottom at -2.88, 10.28 m wide and
7.40/-7.52 tall, with six pieces of 18.9 to 29.2 m3. And it cannot be tuned out - there is no face
of a box whose normal reaches a neighbouring slot of an octahedron.

So the bodies are ANCHORED in their arrangement's own slots now, at one radius, facing outward. The
radius is solved against the field rather than derived: the walk goes out along the chord between
the tightest pair until the shape's own SDF reads the fuse depth, which means the same thing on a
box, a sphere and a spar (sized by one axial distance instead, a spar nucleus came out as six rooms
that never touched). A component may hold members that stand on nothing, and the anchor travels
through MAKE COMP and dissolve with them.

That leaves a nucleus with no parent-child links at all, so seams had to grow the other half they
never had: a JOINED pair that MEETS has a seam wherever the two stand, its plane on the host's
surface along the line between the centres. That is FOLLOWUPS F19's limitation lifted - a doorway
between two fused siblings plans and bores now, where a joint between siblings used to do nothing
at all, silently.

A review of the diff caught two silent-wrong-answer bugs before the commit, both fixed and now
asserted: `definition_order` left an anchored member's subtree to the id sort (right only because
`make_component` hands out ids in subtree order - a hand-edited pack would have placed a child
before its parent, where the attach pass falls back to the instance's frame without a word), and a
seam whose frame IS the identity was dropped, which is exactly the pair on the world Z axis whose
seam lands on the beacon at the origin.

### Verified

A cube carbon's six bodies stand at 4.94 m on their own axes, a symmetric plus of +/-9.58 m, and its
six pieces come out 26.46 to 27.01 m3 - within 2% of each other. Every class on every room family
centres to 0.01 m and bakes its nucleus as ONE room of exactly its body count. **gdUnit4 320/320**
(six new); selfcheck PASSED, hash unchanged at `5536787c6c35d236`; data validator PASSED; gdformat
and gdlint clean; windowed visual, resolve and explode checks PASSED. Frames:
`reports/visual_box_carbon.png` and `reports/visual_box_carbon_explode.png`.

Three tests were asserting on the tree the nucleus used to be - every part hanging off another, the
first part with a parent, every piece coming apart in the middle - and they assert on what was meant
instead: a part may stand on nothing, a pair is named, and it is the ROOM that comes apart.

### Still the human's to check

Build a carbon with CUBE rooms: the nucleus is a symmetric 3D plus about the dot, the same top and
bottom. EXPLODE it - six equal bodies pull apart instead of the lopsided lumps. Then try a spar
carbon, which is the family this could have quietly broken.


## [2026-09-22] Six equal bodies, six of the same piece - and they explode off the centre

> "6 cubes overlaping about the center should not be leaving messy edges between their seams and all
> should be exact copies of one another, thats my verification ive been running so i know something
> is off here. also when i press explode .. the entire ship moves down from the top node which it
> should not, the top node piece should move away from center"

ADR 0035, and both halves were the same mistake: the clump was still being read as a CHAIN with a
first member after ADR 0034 made it six equal bodies about a centre.

A room is cut into its pieces by taking each member's own body and subtracting the members BEFORE it
(ADR 0021) - a priority order, so the first member kept everything and the last was bitten by all of
them, and the bite was the neighbour's ROUNDED body rather than a face. Measured: six pieces from
18.9 to 29.2 m3 with curved grooves between them. Two members that are neither larger than the other
now divide on the plane where their fields read alike - the perpendicular bisector, for a pair of the
same solid. Where one IS larger the priority order stands, because that is what a tunnel sunk into a
hull actually is.

And a module that stands on nothing now travels away from the BEACON, radially, instead of being the
one thing in the clump with nothing to leave - which is why the nucleus slid off its top body. In the
first stage a room holds still unless something outside it carries it off, so a class keeps its core
where it is, pulls its pods off, and only then comes apart.

### Verified

A cube carbon's six pieces come out 26.64 to 26.68 m3 - 0.15% apart, and that 0.15% is the four of
them carrying a tunnel socket, which is real geometry. The cut faces are flat (the top piece reads
back as 20 faces). **gdUnit4 322/322**, two new - one of them the author's own check, asserted;
selfcheck PASSED, hash unchanged at `5536787c6c35d236`; validator PASSED; gdformat and gdlint clean;
windowed visual, resolve and explode checks PASSED. Frames: `reports/visual_box_carbon.png` and
`reports/visual_box_carbon_explode.png`.

### Still the human's to check

A carbon with CUBE rooms, exploded: six pieces of one shape, flat faces between them, each pulling
away from the centre along its own axis - the top one included.


## [2026-09-22] The dividing plane stops at the body it is dividing from

> "when i tried boron with 3 radial nodes and cubes the proton does not come out correctly .. it
> looks as if theres a simple flat cut with missing corner pieces and such. so when a cube collides
> non-orthognally it doesnt bite and seam along all geodesics, its just a flat cut and leaves
> cornerns and stuff cut out and unresolved"

ADR 0035 amended. The plane two equal members divide on was carried by an INFINITE half-space, and a
body is not infinite: where two of them meet at anything but a right angle the plane ran on past the
neighbour and took a corner off the member, which is material no neighbour ever stood in. Measured on
boron, whose three equatorial bodies sit 120 degrees apart: 0.39 m into each body, over its whole
height. Carbon never showed it because an octahedron of axis-aligned cubes puts the plane exactly
through the corner it grazes.

The cutter is one box now, standing on the plane and covering only what the pair's two bodies have in
common. Clipping to the neighbour's own SOLID would be exact and cannot be used: that surface is the
room shell's surface there, and a cutter standing on the surface it cuts is the coincidence the
boolean engine will not resolve - measured, it gave a sphere nucleus an open piece and cells that
would not close.

Two things were measured and NOT changed. Framing each body on the arrangement's pole, so a ring of
them would be exact rotations of each other, made no difference to boron's numbers and broke a sphere
carbon's cells; it was dropped. And a clump of CUBES on a three-fold arrangement cannot have
identical pieces at all - a cube has no three-fold symmetry about a face axis - so boron's three
equatorial protons stay 1.6% apart whatever the cut does.

### Verified

Boron's axial pieces 30.45 -> 30.88 m3, its equatorial three from 4% apart to 1.6%. **gdUnit4
322/322**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; gdformat and gdlint clean.

### Still open - FOLLOWUPS F48, proposed and awaiting the author's go

Inside the shared box the division is a PLANE, and the seam between two fused bodies is not flat: a
plane is the right divider only where the two bodies are mirror images across it, which is why a
carbon of cubes comes out right and a boron of cubes does not.

The author's answer, and it is the right one: split the room at its seams and CAP - "the cut shapes
inner seams all have vertexes, and the outter shell has vertexes, their end caps would be the
capping of inner seam verticies to outter seam verticies". No marching and no surface nets: "weve
already decided on excat mesh cfg stuff". Measured the same day, and it is what makes it buildable:
the seam loops are ALREADY in the baked mesh - a helium of cubes has exactly 4 vertices of its shell
lying on both bodies' surfaces, the rectangle where they cross.

**F48 carries the whole of it**: what was measured, the four steps, the one wrinkle (the inner and
outer loops have their own vertex counts, so the cap zips by arc-length rather than by index), the
two things it will NOT fix, and the hazard it must respect. It replaces the mechanism ADR 0021 set,
so it needs an ADR and the author's go before anyone builds it.


## [2026-09-22] A room is finished whole, then split at its seams

> "the cut shapes inner seams all have vertexes, and the outter shell has vertexes, their end caps
> would be the capping of inner seam verticies to outter seam verticies, independantly for each
> piece .. so a face between i,a,b,j would be the cap" / "we will never marsh cubes or use surface
> nets. weve already decided on excat mesh cfg stuff."

ADR 0036, and it is the author's construction start to finish. A room's hatches are bored while it
is still one body; the shell is then read as the engine's own triangles and split at its SEAMS -
each member keeps the faces on its own surfaces, and the loop where its faces meet another's is
capped from the inner seam to the outer one. Nothing is marched and nothing is sampled on a grid:
the seam loops are already vertices of the shell, because that is what an exact union puts there.

The ORDER was half the bug, and the author named that too - every CAD pipeline unions, hollows, cuts
its openings while the body is one, separates, then dices, and this one separated first and bored
the fragments. The dicing was innocent all along: a split piece with no tunnel diced perfectly.

### Verified

A carbon of CUBE rooms: six pieces of 26.64 and 26.68 m3 - the 0.3% is the four that carry a hatch -
summing to **159.99 against a room of 159.99**. Every piece closed, every edge shared by exactly two
faces, every one dicing into its cells. **gdUnit4 322/322** with one new; selfcheck PASSED, hash
unchanged at `5536787c6c35d236`; validator PASSED; gdformat and gdlint clean; windowed visual,
resolve and explode checks PASSED. Frame: `reports/visual_box_carbon_explode.png`.

A carbon of SPHERES does not split yet - its pieces come out closed and the right size but
non-manifold - so the gate sends that room to the older cut-back and it keeps the pieces it has
always had. F48 carries what was measured.

### Still the human's to check

A carbon with CUBE rooms, exploded: six pieces of one shape, flat faces where they part, each with
its own hatch opening in it. Then a sphere carbon, which should look exactly as it always has.


## [2026-09-23] The engine hands its triangles back the other way round

> "that internal shelfing is NOT supposed to be there ... it litewrally is sensless infill slabs that
> ARENT supposed to be there... the exterior surface is simply missing, the only thing visible is
> interioe, some exterior, with most exterior missing and welded to interior."

ADR 0037. Both halves of that are one bug, and it had been there for the life of the project: Godot's
front face is clockwise, `PolyMesh.to_array_mesh` reverses on the way out to meet it, and
`ShipCsgBake._read_raw` read the engine's triangles back in the engine's own order. Every baked solid
- every piece, every pod, every tunnel - was INSIDE OUT.

Handed back to the engine, an inside-out solid is intersected as its own complement, so a cut through
a hollow piece came back with a solid lid over the cavity instead of a ring: those are the slabs.
Drawn, the double reversal turns the front faces inward and CULL_BACK throws the outside away: that
is the missing exterior. One cause, both symptoms.

**Nothing could see it** because `PolyMesh.volume()` returns an absolute value, and this pipeline
checks itself by volume - pieces summing to their room, halves summing to their piece. A solid and
its inside-out twin measure the same. `signed_volume()` now exists and is what to assert on.

Found on the way and fixed with it: `triangulate_face` fanned any face with no holes from vertex
zero, which is the polygon only when the polygon is convex. Merging coplanar triangles into n-gons
makes concave ones routinely - 96 of a nucleus piece's 334 faces.

### Verified

A cube carbon: six pieces summing to **315.727 m3 against a room of 315.727**, every piece's cells
summing to it exactly, and **no cut face over 0.5 m2 anywhere** (the cut area of a piece's cells fell
from 170.07 m2 to 61.74). A sphere carbon now SPLITS - six closed pieces, 250.809 against a room of
250.821 - which was ADR 0036's one open case, closed without touching `MeshSeamSplit`.

**gdUnit4 323/323**, plus four new guards (42/42 on their two suites): every baked solid reads
positive, a piece cut in half gives half of it back, a concave L covers its own 5 m2, and a solid
knows itself from its inside-out twin. Selfcheck PASSED, hash unchanged at `5536787c6c35d236`;
validator PASSED; gdformat and gdlint clean; resolve, explode and visual checks PASSED.

### The one thing that had to change with it

The INTERIOR mode is the only place in the builder that culls by side, and so the only place the
inversion ever showed. It drew the exterior's FRONT faces and the interior's BACKS, which was right
only while every piece was inside out; with the read turned round it drew the hull as a solid blob
again - the exact symptom ADR 0028 spent two sessions on. Swapped to what ADR 0022 literally asks
for: the interior surface draws its fronts, the exterior its backs. Checked by looking at the frame
(`reports/visual_resolved_interior.png`) - near walls gone, the six cavities and their tunnel mouths
open. Nothing else in the builder culls by side: the faceted shader is `cull_disabled` and flips its
normal on `!FRONT_FACING`, which is why no other mode moved.

### Still the human's to check

A cube carbon, exploded: the wedges beside each hatch are gone and the pieces read as hollow chunks
with their openings. Then a sphere carbon, which takes the split for the first time. And the INTERIOR
mode, which now shows cavities rather than a blob.


## [2026-09-23] What the split actually does now, measured across eight rooms

Follow-on to ADR 0037. Every limit ADR 0036 recorded had been measured against inside-out solids, so
none of them could be trusted; swept helium, boron, carbon and neon in both `box_hull` and
`sphere_pod` and re-stated them from what came back.

- **Eight rooms, eight splits, no fallback.** The cut-back is no longer reached by anything swept.
- **The pieces come to their room**: exactly on a cube helium and a cube carbon, 0.005% on a sphere
  carbon (ADR 0036 recorded 0.4%), 0.25% and 0.40% on the neons.
- **The coplanar case stands** and is the one real limit left: a cube helium's pair divides 247.956
  against 225.963, 8.9% apart, where symmetry says halve. A SPHERE helium divides 0.1% apart, so it
  is coplanar surfaces specifically, not size.
- **The lump at the core is not a split fault.** A cube nucleus leaves a 1 m hollow box of material
  at the ship's centre, where six cavities each inset by their own wall fail to meet. The split
  gives each member one face slab of it, 0.1310 m3 each, six coming to 0.7858 - the lump's net
  volume to the last digit. Correct, and detached from the piece that owns it. Written up as F49
  with three ways out, for the author to pick: it is a question about the cavity model.

### And a hazard worth naming

`scratch/keep_csg.gd` and `scratch/keep_templates.gd` - backups a session took - each declared a
`class_name` the real tree declares. Godot registers global classes from EVERY `.gd` in the project
and `scratch/` is gitignored, so git showed nothing while `ShipCsgBake` resolved to a copy that
predated ADR 0036, and which copy won flipped between runs. Renamed to `.bak` and re-imported.
Anything kept in `scratch/` for reference belongs under a suffix Godot does not parse.


## [2026-09-23] A merge that breaks a piece is refused

Caught by the sweep above: a piece can pass `MeshSeamSplit.is_sound` and be handed on non-manifold
anyway, because the gate runs on the RAW split and `ShipCsgBake._tidy` merges its coplanar fragments
into n-gons AFTERWARDS. Where fragments meet a third surface along the same line, the merged face
can end up sharing an edge with two others. `_tidy` already refused a merge that tore an edge open
or moved the volume; it now refuses one that makes the solid non-manifold, which is the same guard
said properly.

Measured on a NEON of cube rooms - the class the sweep caught, and now the class the test uses:
`p_0009/cp_0002` passed the gate at 1388 faces with every edge on two faces, and came out of the
merge at 507 faces with **two edges on three**. With the guard it keeps its 1388 fragments, which
is worth more than a tidy wireframe: a non-manifold solid is exactly what the engine mis-cuts
(ADR 0037), so this is that fault caught one step earlier.

`p_0024` on a sphere neon came clean the same way. One non-manifold solid is left across the whole
sweep - `p_0022`, a 1.741 m3 tunnel on a cube neon - and it is not the merge: it comes back that way
from the engine, so it is a different thing and is still open.

### Verified

**gdUnit4 328/328** with one new (`test_the_merge_never_breaks_a_piece_the_gate_passed`), which
fails without the guard. Resolve and explode checks PASSED; gdformat and gdlint clean; the sweep
re-run shows eight rooms, eight splits, no fallback, and the piece sums unchanged.


## [2026-09-23] Where two surfaces share a plane, the nearer body takes the face

ADR 0038, the coplanar case ADR 0036 left open. Where two members' surfaces lie in one plane every
face of the band lies on BOTH, both answers are right, and the old rule resolved that to whichever
member the fields named first - so the whole band went to one of them.

The premise was checked before anything was changed: a helium's two bodies are identical and
mirrored, 4000.001 m3 each, centred at x = +-5.84, so symmetry really does say halve. It divided
247.956 against 225.963.

A face both members claim now goes to the body it stands NEARER - the plane between them, without
one being constructed. Confined to readings that agree within 2 mm, and like for like, body against
body and cavity against cavity. It is not ADR 0035's plane returning: that one divided whole bodies
and cut corners off them; this decides the owner of a face already on both surfaces and cuts nothing.

### Verified

The cube helium divides **242.458 against 231.461, 4.5% apart**, from 8.9%. Sphere classes gain too
though they have no coplanar surfaces - a carbon of spheres closes from 0.012 to 0.004 m3 against its
room, a neon of spheres from 0.975 to 0.262. A neon of CUBES goes the other way, 0.25% to 0.39% of
overlap, and that is recorded rather than hidden. A cube carbon still divides exactly, 315.727
against 315.727, and every room in the sweep splits with no fallback.

**gdUnit4 328/328**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; validator PASSED;
gdformat and gdlint clean; resolve and explode checks PASSED.

### And why the other half will not go quietly

The shell of a cube helium is **64 faces**, about 74 m2 each: an exact boolean has no reason to split
a coplanar band, so it arrives whole. A face can only be given whole, so one straddling the bisector
takes all its area to one side - the 110 m2 between the two pieces is about one such face. Halving it
exactly means cutting the band and putting NEW VERTICES in the shell, which is the one thing ADR
0036's construction refuses. F50 has it, with a cheaper half-answer that keeps the refusal intact:
split the two bodies along their bisector in the PLAN, so the engine puts the vertices there itself.


## [2026-09-23] A shared plane is cut in the plan, so the split still invents nothing

ADR 0039, and it closes the coplanar case ADR 0036 opened and ADR 0038 halved.

The obstacle was never the rule, it was the tessellation: an exact boolean has no reason to
subdivide a band where two surfaces share a plane, so it comes back as a few enormous faces - the
whole shell of a cube helium is 64 of them, about 74 m2 each - and a face straddling the bisector can
only be given WHOLE. Halving it exactly needs a vertex on that line, and ADR 0036 is built on never
making one.

So the vertex is made somewhere else: both bodies and both cavities are sliced along the plane
between them IN THE PLAN, before anything is unioned. Same solids, more faces. The engine keeps those
vertices and does not triangulate across them, so the shell arrives with the band already divided and
the split reads a division it did not invent. The principle is intact rather than bent.

It was proved on the shell before being built: straddling faces went from 4 carrying 234.40 m2 to
NONE, with the shell otherwise identical - 64 faces, 4739.50 m2, the same either way.

### Verified

A helium of cubes divides **236.960 against 236.959 m3 - 0.0% apart**, from 4.5% under ADR 0038 and
8.9% before it, both pieces sound. Nothing else in the sweep moves to three decimals, because no
other pair shares a plane - every curved family is left alone by construction. A cube carbon still
divides exactly, 315.727 against 315.727. And the 0.39% overlap ADR 0038 cost a neon of cubes is back
to **0.26%**, the other side of its room.

**gdUnit4 328/328**; selfcheck PASSED, hash unchanged at `5536787c6c35d236`; validator PASSED;
gdformat and gdlint clean; resolve, explode and visual checks PASSED.

### One thing worth keeping

`PolyMesh.sliced_at` keys a crossing by its EDGE, never by where the point lands. The two faces
either side of an edge each work it out for themselves and the same arithmetic in a different order
lands a hair apart; keyed by position, the two make two vertices and tear the edge open. Measured
while building it: 16 open edges on one body of a mirrored pair and none on the other - a tie broken
on float noise, which is the same shape of bug as a spatial hash used as an identity.


## [2026-09-23] A developer note, taken in the moment

> "id like a future-hideable/removable developer feature quick feedback note prompt using the f key,
> where while im testing i can press f, enter in my observation in the moment, the system will take
> my observation and a snapshot of the state and any logs and save it in a developer feedback file
> that you can read the entire compilation of feedback notes in"

`harness/builder/ship_dev_feedback.gd`. **SHIFT+F** while testing: the frame is grabbed as it
stands, a prompt asks what was noticed, and the note is appended to `reports/feedback/notes.jsonl`
with the whole document, the last bake's report, what the view was showing and the tail of the
engine log. `notes.md` beside it is the same list without the document blob, for a human skimming.

**SHIFT, not F alone.** `F` is `ShipView3D.frame_all()` and has been since the beginning. Taking it
would have broken framing silently, so the chord is SHIFT+F - `ShipDevFeedback.CHORD` changes it,
and a test asserts that plain F is still left to FRAME.

**The document is the field that earns it.** A note about a shape is worth little without the ship
that made it; a `ShipDoc` is small and exact, and an agent can rebuild the exact ship the remark was
about. That is not hypothetical - this session reproduced the author's ship from a dumped doc twice,
and both times it was the difference between measuring the right thing and the wrong one.

**Hideable and removable, which is the point.** `ENABLED = false` and nothing arms; it never arms in
a release build regardless (`OS.is_debug_build()`); and removing it is deleting one file and three
lines in `ship_builder.gd`. Nothing else in the project refers to it.

**In-scene, like everything else** (SPEC section 10). It borrows `ShipBuilder.prompt()`, the app's
own modal Control, so no native dialog is opened and it will work just as well once the builder is a
texture on a quad. Typing needs a real keyboard, which is the other reason it is a developer feature.

### Verified

Driven end to end the way a finger drives it - the chord through `_handle_view_hotkey`, the text into
the prompt's own line, OK - and the file read back: the note, a frame, and a document that rebuilt
into its 9 parts, with the bake report beside it (14 pieces, rooms `[6, 1, 1, 1, 1, 1, 1, 1, 1]`,
split 1, fell back 0). **gdUnit4 333/333** with five new; gdformat and gdlint clean.
