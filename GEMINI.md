# Antigravity — workspace notes

Authoritative shared rules live in `AGENTS.md` (read it first). This file only adds Antigravity-specific guidance — do not duplicate shared rules here.

- Your lane: visual/scene composition and editor-centric tasks (see AGENTS.md §6). Hand off GDScript-logic/test work to Claude Code via a devlog entry.
- Workspace skills live in `.agents/skills/` (`godot-check`, `devlog`); workflows in `.agents/workflows/` (`/new-feature`).
- MCP servers for this workspace are configured in `.agents/mcp_config.json` (godot-ai on `http://127.0.0.1:8000/mcp` — requires the Godot editor open with the Godot AI plugin enabled — and Context7 for current Godot API docs).
- At session start: read the tail of `docs/devlog/CHANGELOG.md`. Before finishing: append your entry (AGENTS.md §8).
- Remember the global rules (`~/.gemini/GEMINI.md`): no browser testing of game visuals — the human verifies; explain before acting; no write git commands unless the user asks.
