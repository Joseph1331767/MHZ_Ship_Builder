# Complete Setup Documentation — Dual-Agent Godot Environment

Machine + repo setup as built and verified on **2026-07-08** (Windows 10 Pro). This is the reference
for how everything is installed, how the pieces connect, and how to work day-to-day.

---

## 1. System inventory (this machine)

| Tool | Version | Location / how installed |
|---|---|---|
| Godot | 4.7-stable | `C:\Users\Drope\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7-stable_win64.exe` (winget) — use the `_console.exe` variant for headless work |
| **`GODOT_BIN`** env var (User) | — | points at `Godot_v4.7-stable_win64_console.exe`; every skill/script uses it |
| Claude Code CLI | 2.1.205 | `C:\Users\Drope\.local\bin\claude.exe` (native installer); `~/.local/bin` added to User PATH 2026-07-08 |
| Antigravity IDE | 2.1.4 | `%LOCALAPPDATA%\Programs\Antigravity` — config tree at `~/.gemini/` |
| git / git-lfs | 2.53.0 / 3.7.1 | on PATH |
| Node.js / npm | 22.13.1 / 10.9.2 | on PATH |
| Python | 3.11.0 | `%LOCALAPPDATA%\Programs\Python\Python311` |
| gdtoolkit (gdlint/gdformat) | 4.5.0 | `pip install "gdtoolkit==4.*"` → `Python311\Scripts\` (installed 2026-07-08) |
| uv | latest | `winget install astral-sh.uv` (installed 2026-07-08) — runs the godot-ai MCP Python server |

Global agent config that is **outside** this repo:
- `~/.claude/settings.json` — minimal (theme, model). All project behavior lives in the repo.
- `~/.gemini/GEMINI.md` — the user's 3 global Antigravity rules (no browser testing of visuals; explain before acting; no write git commands unless asked). **Do not edit casually.**
- `~/.gemini/config/mcp_config.json` — global Antigravity MCP config, deliberately left empty; this repo uses workspace-scoped `.agents/mcp_config.json` instead.

## 2. How the pieces connect

```
                    ┌────────────────────────────────────────────┐
                    │              AGENTS.md  (repo root)         │
                    │   SINGLE SOURCE OF TRUTH for all rules      │
                    └──────────────┬───────────────┬─────────────┘
              read natively        │               │   imported via "@AGENTS.md"
        ┌──────────────────────────┘               └────────────────────────┐
        ▼                                                                   ▼
┌─────────────────────┐                                     ┌───────────────────────────┐
│ Antigravity 2.x     │                                     │ Claude Code CLI 2.1.x     │
│ + GEMINI.md extras  │                                     │ + CLAUDE.md extras        │
│ .agents/            │                                     │ .claude/                  │
│   mcp_config.json   │──── workspace MCP servers ────┐     │   settings.json (hooks)   │
│   rules/ skills/    │                               │     │   hooks/ skills/ agents/  │
│   workflows/        │                               │     │ .mcp.json (project MCP)───┤
└─────────┬───────────┘                               ▼     └───────────┬───────────────┘
          │                                 ┌──────────────────┐        │
          │                                 │ godot-ai MCP     │        │
          └── appends/reads ──────┐         │ http://127.0.0.1 │◄───────┘
                                  ▼         │ :8000/mcp        │   ┌──────────────────┐
                    ┌──────────────────┐    │ (Godot editor    │   │ Context7 MCP     │
                    │ docs/devlog/     │    │  plugin bridge)  │   │ (live Godot API  │
                    │ CHANGELOG.md     │    └──────────────────┘   │  docs, remote)   │
                    │ shared memory    │                           └──────────────────┘
                    └──────────────────┘
```

- **Rules**: one canonical `AGENTS.md`. Claude Code cannot read it natively (verified 2026-07-08, GitHub issue #6235 still open) so `CLAUDE.md` line 1 is `@AGENTS.md` — the officially documented pattern, preferred over symlinks on Windows. Antigravity reads it natively (since IDE 1.20.3). Tool-only extras: `CLAUDE.md` / `GEMINI.md` (workspace) — never duplicate shared rules.
- **MCP**: both agents get **godot-ai** (live editor bridge — scene tree, diagnostics, logs; requires the Godot editor open with the plugin enabled) and **Context7** (current Godot API docs). Claude Code config: `.mcp.json` (`type: "http"` + `url`). Antigravity config: `.agents/mcp_config.json` (`serverUrl` — Antigravity rejects `url`).
- **Shared memory**: append-only `docs/devlog/CHANGELOG.md` + `docs/adr/`. Claude Code's SessionStart hook injects the log tail + git state into every new session; Antigravity is instructed to read/append via `GEMINI.md` + its devlog skill.

## 3. Claude Code enforcement layer (hooks)

Deny rules alone are unreliable (open upstream issues) — hooks are the real guardrails. All are
PowerShell scripts in `.claude/hooks/`, wired in `.claude/settings.json`, exit 2 = block:

| Hook | Event | What it does |
|---|---|---|
| `guard.ps1` | PreToolUse (Read/Edit/Write/Bash/PowerShell) | Blocks secret access (`.env*`, `secrets/`, `*.pem`, `*.key`, credentials) and dangerous commands (force-push, `rm -rf /~/.git`, `--no-verify`) |
| `format-gd.ps1` | PostToolUse (Edit/Write) | Auto-runs `gdformat` on any edited `.gd` (best-effort, never blocks) |
| `session-start.ps1` | SessionStart | Injects devlog tail (25 lines) + `git status`/last 5 commits into context |
| `stop-lint.ps1` | Stop | `gdlint`s all changed `.gd` files; blocks finishing until clean. Pure Python — deliberately NO Godot process (headless Godot hangs as a Windows background task) |

Godot-process verification lives in **user-invoked skills** with hard timeouts instead:
`/godot-check` (parse/import check, 90s kill), `/godot-test` (gdUnit4 headless), `/godot-lint`,
plus `/devlog`, `/adr`, and the read-only `godot-reviewer` subagent (Sonnet).

## 4. First-run / per-project steps (GUI, can't be automated)

1. `powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1` — env check + confirms/downloads
   `addons/gdUnit4` and `addons/godot_ai`. In this template both addons are **committed** (vendored),
   so a fresh clone already has them; bootstrap only re-fetches if a copy/ZIP left them out.
   For a bare machine, run `scripts\setup-machine.ps1` first — see `docs/FRESH_MACHINE.md`.
2. Open the project in Godot 4.7 → Project Settings → Plugins → enable **gdUnit4** and **Godot AI**
   (the AI dock starts its MCP server on port 8000; it uses `uv` under the hood).
3. First `claude` run in the repo: approve the two project MCP servers (one-time prompt) and the
   workspace trust dialog. `claude mcp list` should then show both **connected** (godot-ai only
   while the editor is open).
4. Open the repo in Antigravity once and confirm it picked up `AGENTS.md` + the workspace MCP config.

## 5. Daily usage guide

**Lanes (AGENTS.md §6):** Antigravity = visual/scene/editor work · Claude Code = GDScript logic,
tests, refactors, tooling. Never both on the same files at once; the human commits between handoffs.

**Model routing (Claude Code):** default Sonnet for implementation; Opus/Fable-tier for hard
architecture/debugging; Haiku for mechanical bulk edits. Subagents: send review passes to
`godot-reviewer` so exploration stays out of your main context.

**Token discipline:**
- `/clear` between unrelated tasks; `/compact` only to continue the same long task.
- Keep model + MCP servers fixed within a task — changing either invalidates the prompt cache.
- Tool Search is default-on, so MCP tool definitions don't bloat context; check with `/context`.
- Use Context7 for Godot API questions instead of web search (massively cheaper input tokens).

**Both agents, every session:** read devlog tail (Claude: automatic via hook) → work in your lane →
verify (`/godot-check`, tests) → append devlog entry → remind the user to commit (agents never git-write).

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `godot-ai` MCP not connecting | Godot editor must be OPEN with the Godot AI plugin enabled (server = port 8000). Check the AI dock. |
| Headless Godot never returns | Known Windows behavior in background tasks. Always foreground + timeout — use `/godot-check` (kills at 90s), never `run_in_background`. |
| gdlint/gdformat "No terminal matches '﻿'" | File has a UTF-8 BOM. Godot and Claude Code write BOM-less; a PowerShell `Set-Content -Encoding utf8` (PS 5.1) adds BOM — rewrite with `[IO.File]::WriteAllText(path, text, [Text.UTF8Encoding]::new($false))`. |
| Hooks not firing | Session started before `.claude/settings.json` existed → restart `claude`. Also check the workspace trust dialog was accepted. |
| `claude`/`uv`/`gdlint` not found in a terminal | That terminal predates the PATH/env changes of 2026-07-08 — open a fresh one. |
| Stop hook keeps blocking | It's gdlint failing on a changed `.gd`. Run `/godot-lint`, fix findings; don't try to bypass. |
| Antigravity ignores MCP config | It requires `serverUrl` (not `url`) in `mcp_config.json`. Workspace file: `.agents/mcp_config.json`. |
| LFS files show as pointers after clone | Run `git lfs install` once per machine, then `git lfs pull`. |

## 7. Decisions & evidence

Architecture rationale: `docs/adr/0001-agent-architecture.md`.
Full verified research (2026-07-08, against official docs): `docs/research/agentic-godot-setup.md`
and `docs/research/antigravity-claude-compatibility.md`. Key verified facts snapshot:

- Claude Code reads only `CLAUDE.md`; `@AGENTS.md` import = official interop (max 4 hops; imports inside code fences are skipped).
- Hook exit 2 blocks; exit 1 does not. Windows default hook shell = Git Bash; scripts here are invoked explicitly via `powershell.exe -File`.
- Antigravity: rules `.agents/rules/`, skills `.agents/skills/<name>/SKILL.md` (frontmatter `description` mandatory), workflows `.agents/workflows/`, global rules `~/.gemini/GEMINI.md`, MCP global `~/.gemini/config/mcp_config.json` (shared IDE+CLI).
- godot-ai chosen per ADR 0001: MIT, most active free option (v2.9.1, 2026-07-06), needs Godot 4.5+; runner-up Fennara; `Coding-Solo/godot-mcp` if no editor can be open.
- gdUnit4 v6.1.3 supports Godot 4.3–4.7; headless: `& $env:GODOT_BIN --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`.

## 8. Verification record (2026-07-08)

All checks executed live during setup:

- ✅ guard.ps1: blocked `.env` read, `cat .env`, `git push --force`/`-f`; allowed normal edit/push/status.
- ✅ format-gd.ps1: auto-reformatted a misformatted `.gd` (`a:int,b:int)->int` → `a: int, b: int) -> int`).
- ✅ stop-lint.ps1: exit 0 on clean tree, exit 2 with the real gdlint message on a naming violation, exit 0 under `stop_hook_active` (loop guard).
- ✅ session-start.ps1: emitted devlog tail + git status (UTF-8).
- ✅ `check.ps1` headless project check: Godot 4.7 imported the skeleton, exit 0, no hang.
- ✅ `bootstrap.ps1`: env checks + fetched `addons/gdUnit4` and `addons/godot_ai` from GitHub.
- ✅ `claude mcp list`: both servers detected from `.mcp.json` (pending the expected one-time interactive approval).
- ✅ `@AGENTS.md` import: fresh `claude -p` session answered the typing + scratch rules verbatim from AGENTS.md.
- ⬜ Antigravity GUI check (user): open repo, confirm AGENTS.md rules + workspace MCP servers appear.
- ⬜ godot-ai live connection (user): open Godot with the plugin enabled, then `claude mcp list` → connected.
