---
name: godot-test
description: Run the gdUnit4 test suite headlessly and report failures only. Use after logic changes or when the user asks to run tests.
---

# Run gdUnit4 tests (headless)

Requires the gdUnit4 addon in `addons/gdUnit4` (run `scripts/bootstrap.ps1` if missing). Run in the **foreground** with a timeout (never background — Windows hang risk):

```powershell
& $env:GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

- Tests live under `tests/` (mirror `scripts/` structure, files named `*_test.gd`).
- Summarize: total run, passed, and each failure with file, test name, and assertion message. Do not paste full passing output.
- A non-zero exit or any failure means the work is NOT done — fix and re-run.
- Note: UI/input tests cannot run headless; flag them for the user to run in-editor instead.
