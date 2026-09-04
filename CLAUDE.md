@AGENTS.md

## Claude Code–specific notes

- `$env:GODOT_BIN` points at the Godot 4.7 **console** executable — use it for all headless runs.
- ⚠️ **Never run headless Godot with `run_in_background`** — it hangs on Windows. Foreground + explicit
  timeout only.
- **Claim the GPU slot before touching Godot at all** — headless included, it still pins cores. See
  AGENTS §8c. `../../MHZ_Origins/scripts/gpu_slot.ps1 -Action claim -Lane MHZ-SHIP-BUILDER -Reason "..."`,
  release in the same message you finish.
- The headless entry points, once `core/` and `data/` exist:
  ```
  & $env:GODOT_BIN --headless --path . -s res://tools/ship_selfcheck.gd        # parse + determinism smoke
  & $env:GODOT_BIN --headless --path . -s res://tools/ship_validate_data.gd    # data/ is schema-clean
  ```
  Run both through the wrapper instead of bare `-s` so a runtime error actually fails the run
  (AGENTS §8a):
  ```
  ./tools/ship_run.ps1 res://tools/ship_selfcheck.gd
  ./tools/ship_run.ps1 res://tools/ship_validate_data.gd
  ```
- Adding a new `class_name` requires one `& $env:GODOT_BIN --headless --path . --import` before any tool
  can see it, otherwise every reference fails with "Identifier not declared in the current scope."
- gdUnit4 refuses to run headless without `--ignoreHeadlessMode`; it exits 103 with a message about
  `InputEvents`, which is not a test failure:
  ```
  & $env:GODOT_BIN --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests
  ```
- `docs/API_CONTRACT.md` is frozen for M1–M6 (AGENTS §9). If a signature you need looks wrong, report it —
  do not change it. Other agents may be compiling against that exact name right now.
- Read `docs/SHIP_BUILDER_SPEC.md` before touching `core/` or `data/` — the attach model (§3) and the SDF
  op order (§4) are load-bearing and look arbitrary if you meet them in the code first instead of the spec.
- `core/` classes referenced by `tools/` may not exist on disk yet in early milestones while other agents
  are still writing them. That is expected — a tool that fails to parse against a not-yet-written class is
  not a bug in the tool.
- Prefer plan mode for multi-file or architectural changes.
