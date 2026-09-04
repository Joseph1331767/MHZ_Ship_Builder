---
name: godot-check
description: Verify the Godot project (or one script) still parses after edits — headless syntax/type check with a hard timeout, safe on Windows. Use after any .gd change.
---

# Headless Godot parse check

Run the bundled script in the **foreground** (NEVER `run_in_background` — headless Godot hangs as a background task on Windows):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/check.ps1"
```

Single script only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_SKILL_DIR}/check.ps1" -File scripts/player.gd
```

- Uses `$env:GODOT_BIN` (Godot 4.7 console exe). Hard 90s timeout; process is killed on expiry (exit 124).
- Exit 0 = parse OK. Any errors: report them verbatim and fix before proceeding — warnings count as errors (AGENTS.md §2).
- When the Godot editor is open with the Godot AI plugin, ALSO query the `godot-ai` MCP diagnostics for editor-side errors.
