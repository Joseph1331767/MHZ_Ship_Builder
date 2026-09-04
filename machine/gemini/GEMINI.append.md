<!-- BEGIN godot-agent-template (managed by scripts/install-global-config.ps1 - do not edit between markers) -->
## Godot agentic template (dual-agent setup)

There is a reusable Godot base template at `Joseph1331767/godot-agent-template` (local checkout usually
`D:\soft\claude_adventures`). It defines the shared rules (AGENTS.md), hooks, skills, and the godot-ai +
context7 MCP servers that both you and Claude Code use.

- **New project from the template:** the template uses Git LFS so GitHub's one-click template button is
  unavailable; clone and reinit instead (template is a remote, so cloning never modifies it):
  `gh repo clone Joseph1331767/godot-agent-template <name>`, then `Remove-Item -Recurse -Force .git;
  git init -b main; git lfs install`. Rename placeholders (project.godot config/name, AGENTS.md section 1)
  and run `scripts\bootstrap.ps1`. The user makes the first commit / creates the GitHub repo, not you.
- **Adopt the setup into an existing project:** from that project's root, run the overlay script - it copies
  the agent config in non-destructively (skips files that already exist, merges .gitignore/.gitattributes,
  never touches game code or project.godot):
  `powershell -ExecutionPolicy Bypass -File D:\soft\claude_adventures\scripts\adopt-into.ps1`
  Then run `scripts\bootstrap.ps1`, enable the gdUnit4 + Godot AI plugins in Godot, and reopen the folder so
  you pick up AGENTS.md. Explain before acting; the human enables plugins and verifies visuals.
<!-- END godot-agent-template -->
