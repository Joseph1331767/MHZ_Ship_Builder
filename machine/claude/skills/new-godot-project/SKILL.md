---
name: new-godot-project
description: Scaffold a brand-new Godot project from the godot-agent-template WITHOUT altering the template. Use when the user says "start/create a new Godot game/project", "spin up a new project from my template", etc. Creates a fresh repo (clean history) via GitHub's template mechanism, then renames the placeholders.
---

# Create a new Godot project from the template

The template lives at `Joseph1331767/godot-agent-template` (local checkout usually `D:\soft\claude_adventures`).
Confirm the target folder/name and (private/public) with the user first.

> NOTE: The template uses Git LFS, so GitHub's one-click "Use this template" button is unavailable
> (GitHub forbids LFS content in template repos). The clone-and-reinit flow below keeps the template just as
> pristine - the template is a remote, so cloning never modifies it - and it preserves LFS for real assets.

## Steps

1. **Clone the template** (this also pulls the LFS binaries into the working tree):
   ```powershell
   gh repo clone Joseph1331767/godot-agent-template <name>
   ```

2. **Sever it from the template's history** so the new project starts clean (template untouched - it's remote):
   ```powershell
   cd <name>
   Remove-Item -Recurse -Force .git
   git init -b main
   git lfs install
   ```
   The user makes the first commit (`chore: scaffold from agent-base-template`) and creates the GitHub repo
   themselves when they ask (`gh repo create <name> --private --source . --push`) - do not run write-git unasked.

3. **Rename the placeholders** (edit, do not regenerate):
   - `project.godot` -> `config/name="<Project Name>"`.
   - `AGENTS.md` section 1: project name, one-paragraph vision, target platforms, current milestone.
   - `README.md`: replace template text with the project's own.
   - Create `docs/PROJECT_NODE_OF_TRUTH.md` (vision, systems registry, feature-status table).

4. **Bootstrap** (fetches addons, checks the machine layer):
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
   ```

5. **Verify**: `/godot-check` should parse clean. Remind the user to open Godot once to enable the
   `gdUnit4` + `Godot AI` plugins and approve MCP (`/mcp`) - the machine-side steps a headless agent can't do.

6. **First devlog entry**: run `/devlog` recording the project's creation.

The full human checklist is `NEW_PROJECT.md` in the new repo - defer to it for anything not covered here.
Do not run write-git commands (commit/push) unless the user asks (AGENTS.md section 5).
