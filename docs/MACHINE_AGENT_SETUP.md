# Machine Agent Setup - the global layer

This documents everything about the dual-agent Godot dev environment that is **not** inside a project repo -
the machine-wide state a fresh Windows PC needs before any project works. Pair it with
[FRESH_MACHINE.md](FRESH_MACHINE.md) (the step-by-step installer walkthrough); this file is the reference for
*what* the global layer is and *how it's reproduced*.

## The two layers

| Layer | Where it lives | Scope | Reproduced by |
|---|---|---|---|
| **Repo layer** | project root (`AGENTS.md`, `.claude/`, `.agents/`, hooks, skills, `.mcp.json`, `bootstrap.ps1`) | per project | shipped in every clone; `adopt-into.ps1` overlays it onto existing projects |
| **Machine layer** | home dir + system (`~/.claude`, `~/.gemini`, env vars, installed tools) | per PC, once | `scripts/setup-machine.ps1` + `scripts/install-global-config.ps1` |

Everything below is the **machine layer**.

## 1. Installed command-line tools

Installed by `scripts/setup-machine.ps1` (winget + pip):

| Tool | winget id / source | Used for |
|---|---|---|
| Git | `Git.Git` | version control |
| Git LFS | `GitHub.GitLFS` | binary assets (art, audio, addon icons) |
| GitHub CLI (`gh`) | `GitHub.cli` | create/clone repos, template flow |
| Node.js | `OpenJS.NodeJS` | Claude Code (npm install path) + tooling |
| Python 3.12 | `Python.Python.3.12` | runs gdtoolkit |
| uv | `astral-sh.uv` | runs the godot-ai MCP server |
| Godot 4.x | `GodotEngine.GodotEngine` | the engine (console exe used for headless checks) |
| gdtoolkit (`gdlint`/`gdformat`) | `pip install "gdtoolkit==4.*"` | lint + autoformat GDScript |

Not winget packages - install by hand (see FRESH_MACHINE.md step 0):
- **Claude Code CLI** - <https://code.claude.com/docs> (lands at `~/.local/bin/claude.exe`).
- **Google Antigravity** - <https://antigravity.google>.

## 2. Environment variables & PATH

| Name | Value | Set by |
|---|---|---|
| `GODOT_BIN` (User) | full path to `Godot_v*_console.exe` | `setup-machine.ps1` (auto-discovered under `%LOCALAPPDATA%\Microsoft\WinGet\Packages`) |
| `PATH` += `~/.local/bin` | Claude Code's install dir | `setup-machine.ps1` |
| `GODOT_TEMPLATE` (optional) | path to the template checkout, e.g. `D:\soft\claude_adventures` | you, if the template isn't at the default path - lets `adopt-into.ps1` find the source without cloning |

## 3. MCP servers

Both agents use the same two servers:

| Server | Endpoint | Requires |
|---|---|---|
| `godot-ai` | `http://127.0.0.1:8000/mcp` | the Godot editor open with the **Godot AI** plugin enabled (it starts the server on :8000) |
| `context7` | `https://mcp.context7.com/mcp` | network only |

- **Claude Code** reads these per-project from the repo's `.mcp.json`; approve them once with `/mcp`.
- **Antigravity** reads them from the global `~/.gemini/config/mcp_config.json` (Antigravity 2.0 didn't reliably
  surface the workspace `.agents/mcp_config.json`, so the global file is authoritative).

## 4. Global agent config (the part that isn't in any repo)

These live in your home dir and are the reason `install-global-config.ps1` exists - without it a fresh machine
has the tools but not the skills/rules:

| Home-dir location | Source of truth in repo | Contents |
|---|---|---|
| `~/.claude/skills/new-godot-project/` | `machine/claude/skills/new-godot-project/` | `/new-godot-project` skill |
| `~/.claude/skills/adopt-godot-setup/` | `machine/claude/skills/adopt-godot-setup/` | `/adopt-godot-setup` skill |
| `~/.gemini/GEMINI.md` (template block) | `machine/gemini/GEMINI.append.md` | Antigravity new/adopt guidance |
| `~/.gemini/config/mcp_config.json` | `machine/gemini/mcp_config.json` | Antigravity global MCP servers |

`~/.gemini/GEMINI.md` also holds your three personal base rules (no browser testing, explain before acting,
no write-git unasked) - the installer only appends the template block below them, it never touches your rules.

## 5. Reproduce the machine layer (fresh PC)

```powershell
# 1. tools + env vars + PATH (see FRESH_MACHINE.md for the full walkthrough)
powershell -ExecutionPolicy Bypass -File scripts\setup-machine.ps1
#    ... open a NEW shell so PATH/GODOT_BIN take effect ...

# 2. global skills + Antigravity rules/MCP (also invoked at the end of setup-machine.ps1)
powershell -ExecutionPolicy Bypass -File scripts\install-global-config.ps1
```

Then per project: `scripts\bootstrap.ps1`, enable the Godot plugins, approve MCP. See
[FIRST_RUN.md](FIRST_RUN.md).

## 6. The two workflows the global skills enable

- **New project** - `/new-godot-project` (Claude) or the manual [../NEW_PROJECT.md](../NEW_PROJECT.md) checklist:
  clone the template, reinit history, rename placeholders. Template stays pristine.
- **Adopt an existing project** - `/adopt-godot-setup` (Claude): from a foreign project's root, runs
  `scripts/adopt-into.ps1` to overlay the repo layer non-destructively.
