---
name: godot-check
description: Use this skill after editing any GDScript to verify the project still parses — runs a headless Godot syntax/type check safely on Windows.
---

# Headless Godot parse check

Run in a FOREGROUND terminal command (never a background task — headless Godot hangs as a background process on Windows):

```powershell
powershell -ExecutionPolicy Bypass -File .claude/skills/godot-check/check.ps1
```

To check a single script only:

```powershell
powershell -ExecutionPolicy Bypass -File .claude/skills/godot-check/check.ps1 -File scripts/player.gd
```

The script uses `$env:GODOT_BIN`, enforces a hard 90-second timeout, and kills the process on expiry. Exit code 0 = parse OK. Report any errors verbatim and fix them before proceeding. Also query the godot-ai MCP server's diagnostics when the editor is open.
