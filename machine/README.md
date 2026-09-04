# `machine/` - vendored machine-global agent config (source of truth)

Most of this template's agent config is the **repo layer** - it lives at the repo root (`AGENTS.md`,
`.claude/`, `.agents/`, hooks, skills) and travels with every project. But a few pieces are **machine-global**:
they live in your home directory (`~/.claude`, `~/.gemini`), outside any repo, so a fresh machine has none of
them. This folder is the version-controlled source of truth for those pieces, so they can be replicated.

| Vendored here | Installs to | What it is |
|---|---|---|
| `claude/skills/new-godot-project/` | `~/.claude/skills/` | `/new-godot-project` - scaffold a new game from the template |
| `claude/skills/adopt-godot-setup/` | `~/.claude/skills/` | `/adopt-godot-setup` - retrofit an existing project |
| `gemini/GEMINI.append.md` | appended to `~/.gemini/GEMINI.md` | Antigravity's copy of the new/adopt guidance |
| `gemini/mcp_config.json` | `~/.gemini/config/mcp_config.json` | Antigravity global MCP servers (godot-ai + context7) |

## Install / replicate on a machine

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-global-config.ps1
```

Idempotent - safe to re-run. `scripts\setup-machine.ps1` calls it automatically at the end of a fresh-machine
setup. Full context: **[docs/MACHINE_AGENT_SETUP.md](../docs/MACHINE_AGENT_SETUP.md)**.

## Editing

Edit the copies **here** (they are the source of truth), then re-run the installer to push changes to your home
dir. Don't edit `~/.claude/skills/...` directly - those changes aren't version-controlled and get overwritten.
