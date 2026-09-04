# Starting a New Project from this Template

Work through this checklist top to bottom. ~10 minutes.

> 🆕 **Brand-new PC?** Do **[docs/FRESH_MACHINE.md](docs/FRESH_MACHINE.md)** first (it installs Godot,
> git, the agents' tooling, etc.), then come back here.

## 1. Copy & rename
- [ ] Get the template into a new folder:
      - GitHub → **"Use this template"** → clone your new repo, **or**
      - `git clone https://github.com/<your-username>/godot-agent-template.git my-game`
- [ ] `cd` into it and run `git lfs pull` (pulls the plugin/binary files).
- [ ] `project.godot`: change `config/name`.
- [ ] `AGENTS.md` §1: fill in project name, vision paragraph, platforms, milestone.
- [ ] Create `docs/PROJECT_NODE_OF_TRUTH.md` (vision, systems registry, feature status table).
- [ ] `README.md`: replace template text with the project's own readme.

## 2. Bootstrap
- [ ] `powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1`
      (verifies GODOT_BIN/git/lfs/uv/gdtoolkit; confirms the `gdUnit4` + `godot_ai` addons are present,
      and re-downloads them if a copy/ZIP left them out).
- [ ] Then follow **[docs/FIRST_RUN.md](docs/FIRST_RUN.md)** for the per-app clicks:
      enable the Godot plugins, approve MCP in Claude Code, open the repo in Antigravity.

## 3. Git
- [ ] If you **copied** the folder instead of cloning: `git init -b main` then `git lfs install`.
- [ ] First commit: `chore: scaffold from agent-base-template`.
- [ ] Create the GitHub repo and push (you, not the agents):
      `gh repo create my-game --private --source . --push`.

## 4. Agent smoke test
- [ ] `claude` in the repo → ask "what are the typing rules here?" → it must answer from AGENTS.md.
- [ ] In Claude, `/mcp` → context7 **connected**; godot-ai **connected** while the Godot editor is open.
- [ ] Open the repo in Antigravity → confirm it picked up AGENTS.md and shows the MCP servers.
- [ ] Edit any `.gd` file via Claude → confirm gdformat auto-ran (PostToolUse hook).

## 5. First devlog entry
- [ ] Run `/devlog` (either agent) recording the project's creation.

## Daily discipline (both agents)
- One agent per lane (AGENTS.md §6); commit between handoffs; agents never run write-git.
- `/clear` between unrelated tasks; keep MCP servers/model fixed during a task (prompt caching).
- Everything throwaway goes to `scratch/`.
