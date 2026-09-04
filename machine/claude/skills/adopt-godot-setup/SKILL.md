---
name: adopt-godot-setup
description: Retrofit an EXISTING Godot/VS Code project so it uses this machine's Godot agentic dev setup (AGENTS.md rules, hooks, skills, godot-ai + context7 MCP, strict typing). Use when the user is inside another project and says things like "use our main Godot agentic setup here", "adopt/godotize this repo", "wire this old project into my Claude+Antigravity+Godot environment".
---

# Adopt the Godot agentic setup into an existing project

There are two layers (see the template's mental model):
- **Machine layer** (Godot install, `GODOT_BIN`, gdtoolkit, uv, git/lfs/gh, the godot-ai MCP server) - set up
  once per PC via `setup-machine.ps1`. Shared by every project on this machine; nothing to do per-repo.
- **Repo layer** (`AGENTS.md`, `.claude/`, `.agents/`, `.mcp.json`, hooks, skills, `bootstrap.ps1`, docs) -
  this is what gets overlaid into the target repo.

This skill overlays the repo layer **non-destructively**: it never touches the target's game code,
`project.godot`, scenes, or addons, and it **skips** any repo-layer file the target already has (reporting
it so the user can merge by hand). `.gitignore`/`.gitattributes` are merge-appended.

## Steps

1. **Confirm** you are in the target repo root and it is a Godot project (has `project.godot`). Explain what
   the overlay will add before running (rule 9 - explain before acting).

2. **Run the overlay** from the target repo root. It auto-resolves the template source
   (`-Source` arg -> `$env:GODOT_TEMPLATE` -> `D:\soft\claude_adventures` -> `gh clone`):
   ```powershell
   powershell -ExecutionPolicy Bypass -File D:\soft\claude_adventures\scripts\adopt-into.ps1
   ```
   Add `-Force` only if the user wants to overwrite existing agent config (e.g. refreshing an older copy).
   Read the `[copy]/[skip]/[merge]/[warn]` report back to the user - the `[skip]` and the `project.godot`
   warnings are the items needing their attention.

3. **Machine layer check + addons**: run the just-copied `scripts\bootstrap.ps1`. If it reports `[MISS]`
   items, point the user at `scripts\setup-machine.ps1` (the one-command machine installer).

4. **project.godot**: it is never overwritten. If the report warned it lacks the strict-typing block, the
   user must add it (via Godot Project Settings -> Debug -> GDScript, or by pasting the printed block). The
   `Godot AI` autoload + enabled-plugins lines also get added when they enable the plugins in-editor.

5. **Enable + connect**: open the project in Godot 4.7, enable `gdUnit4` + `Godot AI` plugins (starts the MCP
   server on :8000), then in Claude Code run `/mcp` to approve `godot-ai` + `context7`. Reopen in Antigravity
   so it picks up `AGENTS.md`.

6. **Verify + log**: `/godot-check` to confirm the project still parses, then `/devlog` to record the adoption.

Do not run write-git commands unless the user asks (AGENTS.md section 5). If the target already had its own
`AGENTS.md`/`CLAUDE.md`, do NOT clobber it - the overlay skips it; help the user merge the two by hand.
