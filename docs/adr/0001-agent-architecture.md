# 0001 — Dual-agent architecture: AGENTS.md single source of truth

- **Date**: 2026-07-08
- **Status**: Accepted

## Context
Two agents (Claude Code CLI, Google Antigravity) work on the same repos. Duplicated/mirrored rules
files drift and rely on agents remembering to dual-write — quantified as unreliable (rules dropped
after context compaction). Claude Code does not read `AGENTS.md` natively (issue #6235 open as of
2026-07-08); Antigravity does. Windows symlinks are unreliable without Developer Mode.

## Decision
1. **One canonical `AGENTS.md`** at repo root holds all shared rules. Claude Code loads it via the
   officially documented `@AGENTS.md` import on line 1 of `CLAUDE.md` (chosen over symlinks per
   Anthropic's Windows guidance). Tool-private extras go in `CLAUDE.md` / `GEMINI.md` only.
2. **Godot MCP = hi-godot/godot-ai** (MIT, most active free option, HTTP transport, auto-configure
   for both agents; needs Godot 4.5+). Context7 for current API docs. Workspace-scoped configs
   (`.mcp.json`, `.agents/mcp_config.json`) — global Antigravity config untouched.
3. **Hooks over deny rules** for enforcement (deny rules documented as unreliable): PreToolUse
   guard (secrets/dangerous commands, exit 2), PostToolUse gdformat, SessionStart devlog injection,
   Stop gdlint. Blocking hooks run **pure-Python tools only** — headless Godot hangs as a Windows
   background task (observed in MHZ_Origins), so Godot-process checks live in user-invoked skills
   with hard timeouts.
4. **Shared memory = append-only dev log** (`docs/devlog/CHANGELOG.md`) + ADRs, injected at
   session start; lanes: Antigravity = visual/scene, Claude Code = logic/tests/refactors.

## Consequences
- Shared rules physically cannot drift (one file). Tool extras stay small.
- godot-ai requires the Godot editor open; headless-only sessions fall back to CLI checks + Context7.
- Skills are duplicated (small) between `.claude/skills/` and `.agents/skills/` — accepted cost on
  Windows; revisit if a sync tool becomes worth it or Claude Code ships native AGENTS.md support.
