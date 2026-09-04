# Technical Setup Report: An Agentic, AAA-Grade Godot Workspace for Claude Fable 5 + Antigravity 2.0

## PART A — THE RESEARCH REPORT

### TL;DR
- **Primary Godot MCP recommendation: dlight's "Godot AI" (open-source, MIT, hi-godot/godot-ai on PyPI as `godot-ai`), with Fennara as runner-up.** There is NO official Godot Foundation MCP server, and the Foundation is explicitly AI-skeptical (its June 30, 2026 policy states "No use of AI to generate substantial pieces of code. We require all code to be human authored"), so every option is third-party.
- **The two agents coexist by sharing ONE source of truth (`AGENTS.md`) plus a shared append-only dev log; Claude Code does NOT read AGENTS.md natively — you must symlink or `@import` it into `CLAUDE.md`.** Antigravity reads `AGENTS.md` and `.agents/`; Claude Code reads `CLAUDE.md` and `.claude/`.
- **Time-box the Fable 5 setup: use Fable 5 as the orchestrator to scaffold everything, delegate bulk work to cheaper subagents, freeze MCP/tools for prompt caching, and control MCP tool bloat (Tool Search + disabling unused servers).** Fable 5 output is priced ~$50/M tokens vs ~$10/M input, and the whole conversation is re-sent every turn, so keeping context lean and caching intact is what preserves a limited Fable budget.

### Key Findings

1. **No official Godot MCP exists; pick a maintained third-party server.** Godot MCP Pro is the most capable but is paid/proprietary; dlight's Godot AI is the best free/open option; Fennara is the best "feedback-loop" option (Godot 4.5+).
2. **Caveman token-saving is real but modest.** Its own README reports an average 65% *output* reduction (range 22–87%) and warns it "only shrinks output tokens. Input and reasoning tokens are untouched, and the skill itself adds ~1–1.5k input tokens per turn." Real whole-session savings are small because most tokens are input. The bigger wins are prompt caching, `/clear`, Tool Search, and disabling unused MCP servers.
3. **Graphiti ("graphifyy") is real** — Zep's temporal knowledge-graph engine with an official MCP server — but is likely overkill for a solo dev. A simpler memory stack (official Memory MCP + a Markdown/Obsidian dev log) is recommended.
4. **The dual-agent dev log is the linchpin of cross-agent visibility.** Both agents append to a structured Markdown changelog; Claude Code hooks (SessionStart/Stop/PostToolUse) automate the writes.
5. **Godot has real headless feedback loops** (`--headless --script`, GUT/gdUnit4, gdlint/gdformat, LSP on 6005) that should be wired into Claude Code hooks/skills.

### Details

#### 1. Godot MCP Servers — Comparison & Recommendation

Model Context Protocol (MCP) lets an AI client call tools inside or against Godot. The field exploded in 2025–2026. Current metrics (as of July 2026):

| Server | Stars | Last activity | Godot | Tools | License / Cost | Notes |
|---|---|---|---|---|---|---|
| **dlight "Godot AI"** (hi-godot/godot-ai, PyPI `godot-ai`) | ~4 (repo new; the "9,500-star" figure is the team's *Unity* MCP, not this) | Early July 2026 (PyPI Jul 3; Asset Store Jul 5) | 4.3+ (4.4+ rec.) | ~25 concrete (120–150 marketed) across ~41 tools | MIT (fully open) | FastMCP Python server (port 8000) + WebSocket (9500) to editor plugin; one-click setup for ~18 MCP clients incl. Claude Code & Antigravity; live editor feedback |
| **Fennara** (fennaraOfficial/fennara-godot-ai) | 187 | Jul 3 2026 | **4.5+ only** | Focused set (feedback-loop centric) | MIT | Diagnostics, scene validation, runtime logs, screenshots, patch-and-rerun; C# via `--csharp`; one-click for Claude/Codex/Cursor/Antigravity |
| **Godot MCP Pro** (youichi-uda) | 383 | May 18 2026 (v1.14.0) | 4.x | **172** across 23 categories | Proprietary, **paid (~$15 one-time)**; public repo is addon-only | Most capable technically; WebSocket:6505, UndoRedo, editor+game screenshots, runtime (19 tools), input sim |
| **Coding-Solo/godot-mcp** | ~4.1k | ~2025 (stale; no releases) | 4.4+ | ~13 | MIT | Most popular but least capable; headless-CLI (launch/run/capture output); no live scene-tree inspection |
| **IvanMurzak/Godot-MCP** | ~5 | Jun 12 2026 (v0.5.0) | 4.3+ **C#/mono only** | 36 across 10 families | Apache-2.0 | Clean architecture; blocks pure-GDScript projects; shares server with Unity-MCP |

**RECOMMENDATION (exactly one primary): dlight's "Godot AI" (`godot-ai`).** Justification: it is the only option that is simultaneously (a) free and fully open-source (MIT), (b) actively maintained into July 2026, (c) explicitly one-click-installable for Claude Code AND Antigravity, and (d) architected around a live editor feedback loop (create/edit scenes and scripts, inspect scene tree, run tests, read logs). For a "noob-ish" solo dev this maximizes capability-per-dollar and avoids vendor lock-in.

- **Runner-up #1: Fennara** — pick this instead if the user is on Godot 4.5+ and wants the most mature runtime-diagnostics/patch-and-rerun loop.
- **Runner-up #2: Godot MCP Pro** — pick this if a ~$15 one-time cost and a closed server are acceptable in exchange for the largest tool surface (172 tools).
- **Avoid as primary: Coding-Solo/godot-mcp** despite its star count — it is stale and cannot inspect the live scene tree.
- **C# projects only: IvanMurzak/Godot-MCP.**

> **Verify at runtime:** star counts and last-commit dates shift; Fable 5 should re-check the repo/PyPI/Asset Store before installing, and confirm the chosen server's one-click installer supports the user's exact Claude Code and Antigravity versions. Godot MCP Pro's price/tool-count vary by listing ($5 vs $15; 162 vs 172 tools).

**Why this matters:** File-level MCPs (or pasting code into chat) leave the AI blind to your scene tree, signals, and runtime errors. An editor-integrated MCP creates a feedback loop where the agent sees what actually broke and can fix it — the single biggest quality multiplier for AI-assisted Godot work.

#### 2. Other High-Value MCP Servers

Prioritize the small set of **official reference servers** maintained by the MCP steering group (github.com/modelcontextprotocol/servers), and add a couple of high-value community servers.

- **Filesystem** (`@modelcontextprotocol/server-filesystem`) — official; secure file ops with allow-listed directories. Point it at the project root only.
- **Git** (`uvx mcp-server-git`) — official; read/search/manipulate the repo.
- **GitHub** (github/github-mcp-server, hosted at `https://api.githubcopilot.com/mcp/`) — issues, PRs, repo management. Note the original `@modelcontextprotocol/server-github` was superseded by GitHub's own server.
- **Context7** (Upstash) — up-to-date, version-specific library/API docs injected as focused slices. Strongly recommended for current Godot API docs. Per Upstash's Context7-vs-Claude-Code-Web-Search benchmark, it "cut fresh input tokens by about 99%, which fed through to a 34.56% cost reduction and 36.81% fewer total tokens" (and reduced output tokens ~52.97% on average). Runs as an MCP server.
- **Sequential Thinking** (`@modelcontextprotocol/server-sequential-thinking`) — official; structured multi-step reasoning. Optional; adds tokens.
- **Memory** (`@modelcontextprotocol/server-memory`) — official knowledge-graph persistent memory. Good default memory layer (see §8).
- **Fetch** (official) — web content fetching/conversion.

**Deprecated/archived — flag and avoid:** the archived reference servers (AWS KB Retrieval, Brave Search [replaced], older `server-github`, `server-postgres` as a reference) now live in `servers-archived` and are for historical reference only.

**Asset pipeline:** a Blender MCP exists in the ecosystem but is optional and heavy; only add it if doing 3D asset generation. Meshy-integrated Godot MCP forks exist but require an API key.

**Tool-count discipline:** Antigravity itself recommends keeping total enabled tools under ~50 for performance. Don't enable everything at once.

#### 3. Claude Code Skills

Skills are folders with a `SKILL.md` (YAML frontmatter `name` + `description`, then Markdown body). They use **progressive disclosure**: only name+description load at startup; the body loads on demand; bundled scripts execute without their code entering context. This makes skills the most token-efficient way to give the agent Godot expertise.

- **Locations:** project `.claude/skills/<name>/SKILL.md` (committed, team-shared) and personal `~/.claude/skills/`. Precedence: enterprise > personal > project. Custom slash commands (`.claude/commands/*.md`) have merged into skills — both create `/name`.
- **Official repos:** Anthropic's `github.com/anthropics/skills` (document skills, skill-creator, example skills). Install via `/plugin marketplace add anthropics/skills` then `/plugin install`. The open standard lives at agentskills.io. Community directories: claudeskills.info, skillsmp.com — treat community skills as untrusted code and audit before use.
- **Bundled skills** in Claude Code include `/code-review`, `/debug`, `/loop`, `/batch`.
- **Author custom Godot skills** (the user will need these from scratch): create `.claude/skills/<name>/SKILL.md`, write a tight description (front-load the use case; >250 chars gets truncated in the listing), keep the body focused, split rarely-used content into referenced files, and bundle scripts (e.g., a headless test runner). Recommended custom skills: `godot-run-scene`, `godot-test` (GUT/gdUnit4), `godot-lint` (gdlint/gdformat), `gdscript-style` (the official style guide), `godot-debug`, `devlog` (writes the shared dev log), `adr` (writes Architecture Decision Records).

**Why this matters:** For a Godot-specific workflow, no off-the-shelf skill knows your project. Custom skills capture your build/run/test recipes once so every future session (and every agent) follows the same steps instead of rediscovering them.

#### 4. Claude Code Configuration & Rules

- **CLAUDE.md / hierarchical memory:** Claude Code loads memory hierarchically — enterprise, then user (`~/.claude/CLAUDE.md`), then project (`./CLAUDE.md` and parent dirs). Keep CLAUDE.md short and stable (durable rules only); put procedures in skills. Write facts as declarative statements ("This repo uses gdUnit4"), not imperative system commands (which can trip prompt-injection defenses).
- **AGENTS.md standard:** the cross-tool convention read natively by Cursor, Codex, Copilot, Gemini/Antigravity, etc. **Claude Code does NOT read AGENTS.md** — official docs say it reads CLAUDE.md only, with no fallback. Interop options: (1) put `@AGENTS.md` on the first line of CLAUDE.md (the `@import` works on all OSes, is recursive up to ~4 hops), or (2) symlink `ln -s AGENTS.md CLAUDE.md` (Unix; Windows needs admin/Developer Mode). The `@import` is the recommended cross-platform choice.
- **settings.json:** hierarchy is `.claude/settings.json` (project, committed) → `.claude/settings.local.json` (personal, gitignored) → `~/.claude/settings.json` (user). Holds hooks, permissions, model config, `disableBundledSkills`, etc.
- **Hooks:** deterministic shell/HTTP/prompt/MCP commands fired on lifecycle events. Key events: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStop, PreCompact/PostCompact (the event list expanded significantly in recent versions — 20+ events). Exit 0 = allow; **exit 2 = block** (stderr fed back to Claude); other exits = non-blocking error (note: exit 1 does NOT block — a common footgun). Stdout from SessionStart/UserPromptSubmit is injected as context. Hooks fire even under `--dangerously-skip-permissions`, so they're the reliable guardrail layer.
- **Subagents (`.claude/agents/*.md`):** Markdown + YAML frontmatter (`name`, `description`, `tools`, `model`). Run in isolated context windows; only the final result returns to the parent — the key context-isolation mechanism. Built-ins: Explore (read-only search), Plan, general-purpose. Restrict subagents to read-only tools and defer writes to the parent. Route cheap tasks to Haiku.
- **Slash commands / output styles:** custom commands merged into skills; output styles control verbosity/format.
- **Permissions:** allow/deny/ask rules. A bare tool-name deny (e.g., `Bash`) removes the tool from context entirely. Deny reading `.env` via a PreToolUse hook or deny rule.

**CLAUDE.md ↔ AGENTS.md interoperation:** Keep AGENTS.md as the single source of truth (shared with Antigravity); CLAUDE.md contains only `@AGENTS.md` plus a handful of Claude-specific overrides. Running `/init` will fold an existing AGENTS.md into a generated CLAUDE.md.

#### 5. Dual-Agent Coexistence (Antigravity 2.0 + Claude Code)

This is the critical integration. Findings:

- **What each reads:** Antigravity 2.0 reads `AGENTS.md` (root) and workspace rules in `.agents/rules/`, plus global `~/.gemini/GEMINI.md`; skills/workflows live in `.agents/skills/` and `.agents/workflows/`. Configuration priority is AGENTS.md → GEMINI.md → built-in defaults. Claude Code reads `CLAUDE.md`, `.claude/skills/`, `.claude/agents/`, `.claude/settings.json`.
- **Shared rules:** AGENTS.md is shareable to both — Antigravity natively, Claude Code via `@import`/symlink. Skills directories differ (`.agents/skills/` vs `.claude/skills/`); symlink one to the other if you want shared skills.
- **File locking / race conditions:** neither tool provides cross-tool file locking. The real risk is two agents editing the same files simultaneously. **Mitigation: domain isolation** — never run both agents on the same files at the same time; give each a lane (e.g., Antigravity for browser-verified UI tasks, Claude Code for GDScript/logic/testing), and use git commits as checkpoints between handoffs.
- **Git conflicts:** commit frequently and in small units; use the shared dev log (see §6) so each agent sees what the other changed; consider git worktrees if truly parallel work is needed.
- **.gitignore considerations:** commit `.claude/` (skills, agents, settings.json) and `AGENTS.md`/`CLAUDE.md`; gitignore `.claude/settings.local.json` and any secrets. If you use the symlink-CLAUDE.md-to-AGENTS.md pattern, some teams gitignore the generated CLAUDE.md symlink. Antigravity's per-user config lives in `~/.gemini/` (not in the repo).
- **Antigravity MCP config:** central shared config at `~/.gemini/config/mcp_config.json` (2.0 shares across IDE + CLI); per-surface at `~/.gemini/antigravity/mcp_config.json`. **Antigravity uses `serverUrl` (not `url`) for HTTP MCP servers** — a common gotcha. Claude Code uses `.mcp.json` (project) or `claude mcp add`.

**Why this matters:** Two autonomous agents on one repo will corrupt each other's work if they edit the same files blindly. Shared rules + a shared dev log + lane discipline + frequent commits turn potential chaos into a coordinated hand-off.

#### 6. Shared Dev Log / Cross-Agent Visibility

The pattern: a single **append-only, structured Markdown dev log** both agents read at session start and append to at session end/after significant changes.

- **Structure:** `docs/devlog/` with a `CHANGELOG.md` (append-only, reverse-chronological), plus session handoff notes and `docs/adr/` for Architecture Decision Records (one file per decision: context, decision, consequences).
- **Conventional Commits:** adopt `feat:`, `fix:`, `chore:`, `refactor:`, `test:` etc. so commit history is machine-parseable and both agents (and any CI changelog tooling) can read intent.
- **Claude Code automation via hooks:**
  - **SessionStart** hook: `cat docs/devlog/CHANGELOG.md | tail -n 50` piped to stdout → injected as context so Claude sees recent history (SessionStart stdout is added to context).
  - **Stop** hook: append a timestamped entry (session summary, files touched, `last_assistant_message`) to the changelog. Use `async` for non-blocking.
  - **PostToolUse** (matcher `Write|Edit`): optionally log each file edit.
- **Antigravity side:** a `.agents/workflows/` step or rule instructs the agent to read and append to the same `docs/devlog/CHANGELOG.md`. Because Antigravity resets context between sessions, this shared log is also its own memory.
- **Existing tooling:** ClaudeKit logs task completions to `.claude/logs/tasks.log`; the official Memory MCP can hold a knowledge graph; but a plain committed Markdown log is the most portable, both-agents-can-read solution and is recommended as the baseline.

**Why this matters:** Antigravity forgets everything between sessions and Claude Code compacts context; a committed, human-readable log is the durable shared brain that survives both, and it's diffable in git.

#### 7. Token / Context Saving

- **Caveman style — verdict: real, modestly useful, not magic.** The `caveman` plugin (JuliusBrussee/caveman) is a genuine, heavily-adopted project — **82,796 stars / 4,618 forks, v1.9.1, last commit Jul 3 2026, MIT** (per its GitHub repo and ClaudePluginHub). It strips filler from Claude's *output* while preserving code/commands/errors byte-for-byte. Its own README is honest about limits: "Average 65% output reduction across 10 prompts (range 22–87%)… Output tokens only," and it warns "Caveman only shrinks output tokens. Input and reasoning tokens are untouched, and the skill itself adds ~1–1.5k input tokens per turn… on already-terse workloads they can go net-negative." It auto-reverts to full prose for security warnings and destructive-action confirmations. Install: `claude plugin marketplace add JuliusBrussee/caveman` then `claude plugin install caveman@caveman`; trigger `/caveman` (lite/full/ultra). `caveman-compress` rewrites CLAUDE.md into terse form to cut input tokens. **Recommendation: worth the two-minute install at `lite`/`full`; the three-line CLAUDE.md version ("Respond like a caveman. No articles, no filler, no pleasantries. Code speaks for itself.") is a good, dependency-free alternative.** Turn it off when debugging something you don't fully understand.
- **The bigger levers (prioritize these):**
  - **`/clear`** when switching to unrelated work (drops old context entirely); **`/compact`** when continuing the same task past the context limit; auto-compaction near the limit. Context editing (API/SDK) clears stale tool results.
  - **Prompt caching** is "everything" — freeze the model, MCP servers, tools, system prompt, and CLAUDE.md *before* a task; changing any of them mid-task invalidates the cache. Don't switch models mid-task (caches are per-model). Prepare MCP servers up front (adding one mid-session invalidates the cache when its tools load into the prefix).
  - **MCP tool bloat is the #1 hidden cost.** Developer Scott Spence documented MCP tools consuming 82K tokens (41% of a 200K window), leaving only ~12K free (5.8%); a separate GitHub issue reported 144,802 tokens from MCP tools alone, with one Docker MCP consuming 125,964 across 135 tools. **Tool Search** (deferred tool loading) is the fix: per Anthropic Engineering's "Introducing advanced tool use," it reduced tool-definition overhead by ~85% — from ~77K tokens (with 50+ MCP tools) down to ~8.7K, "preserving 95% of the context window," while the Tool Search tool itself adds only ~500 tokens and "doesn't break prompt caching." It's enabled by default and auto-activates when MCP tool descriptions exceed 10% of context (Claude Code v2.1.7+). Also mitigate by disabling unused servers (`/mcp`), scoping servers per-project, and using `/context` to inspect.
  - **Subagents** isolate context — deep search/log analysis stays in the subagent; only the summary returns.
  - **Efficient CLAUDE.md sizing + progressive disclosure via skills** — keep CLAUDE.md short; move procedures to skills.
  - **Context7** for docs (huge input-token savings vs open-web fetching — see §2).
  - **Model routing:** Haiku for light/high-volume, Sonnet for workhorse, Opus/Fable for hardest reasoning; tune the `effort` parameter per task.

**Why this matters for Fable 5:** Per Upstash's "How to Keep Claude Fable 5 Costs Under Control," Fable 5 output is priced $50/M vs $10/M input, and "the whole conversation is re-sent on every turn, so a ten-step task reprocesses the same context ten times… each documentation query ran 80,000 to 140,000 tokens, only one to three thousand of them output." Keeping caching intact and context lean is what keeps a time-limited Fable 5 budget from evaporating.

#### 8. Memory Frameworks

- **Graphiti ("graphifyy"):** Zep's open-source (Apache-2.0) temporal knowledge-graph engine; bi-temporal (tracks when a fact was true and when ingested), hybrid retrieval (semantic + BM25 + graph), official MCP server (v1.0, Nov 2025) for Claude/Cursor. Powerful for evolving facts over time — but requires Neo4j/FalkorDB and is **overkill for a solo game dev.**
- **mem0:** vector + optional graph; broadest OSS community; good for personalization.
- **Obsidian integration:** the **Local REST API plugin** (coddingtonbear) now ships a **built-in MCP server** (`https://127.0.0.1:27124/mcp/`, bearer-token auth) — the maintainer says third-party servers are no longer necessary. Community alternatives: `mcp-obsidian` (MarkusPfundstein, `uvx mcp-obsidian`) and `obsidian-mcp-server` (cyanheads). Simplest of all: the official **Filesystem MCP pointed at the vault folder** (a vault is just Markdown) — covers ~90% of use, works when Obsidian is closed, no plugin dependency.
- **Anthropic's official Memory MCP** (`@modelcontextprotocol/server-memory`): knowledge-graph persistent memory, zero external DB. The lowest-friction "real" memory layer.
- **RECOMMENDED STACK for this solo dev (avoid overkill):**
  1. **Committed Markdown dev log + ADRs** (§6) — the primary, portable, both-agents memory.
  2. **Official Memory MCP** — optional lightweight knowledge graph for cross-session facts.
  3. **Obsidian via Local REST API MCP OR Filesystem MCP on the vault** — only if the user already lives in Obsidian; start with Filesystem MCP.
  - **Skip Graphiti/mem0/Neo4j** unless the project grows to need temporal reasoning across a large fact base.

#### 9. Godot-Specific Debugging Workflows

- **Headless / CLI:** `godot --headless --script <script.gd>` runs logic without a window; `godot --headless --path <project> <scene>` runs a scene; capture stdout/stderr for the agent. Great for CI and agent feedback loops.
- **Testing:** **GUT** (bitwes/Gut, MIT, Godot 4) and **gdUnit4** (godot-gdunit-labs/gdUnit4, GDScript + C#, embedded inspector, CLI runner, JUnit XML + HTML reports, GitHub Action). gdUnit4 can run headless via `--headless --ignoreHeadlessMode` (headless is disabled by default because UI tests can't process input headlessly — fine for non-UI tests). Recommendation: **gdUnit4** for its CLI/CI story and C# support; GUT if the user prefers a lighter GDScript-only tool.
- **Static analysis:** **gdlint / gdformat** (from Scony's godot-gdscript-toolkit) for linting and auto-formatting GDScript. Wire `gdformat` into a PostToolUse hook (matcher `Write|Edit`) so every AI edit is auto-formatted, and `gdlint` into a Stop hook that blocks on lint errors (exit 2).
- **LSP:** Godot's built-in language server runs on **port 6005** (Godot 4 default; the VS Code "Godot Tools" default is 6008 — a known mismatch). Launch headless LSP: `godot --editor --headless --lsp-port 6005 --path <project>`. Community bridges exist (e.g., opencode-godot-lsp). JetBrains Rider can auto-start a headless LSP. There is an open proposal to add a dedicated `--gdscript-lsp` flag.
- **Debugger protocol:** Godot exposes debugger signals (used by editor-integrated MCPs like Ziva/Godot MCP Pro to read runtime errors). For CLI agents, capturing stdout/stderr from headless runs is the pragmatic feedback channel.
- **Wire into hooks/skills:** create a `godot-test` skill that runs gdUnit4 headless and returns only failures; a PostToolUse `gdformat` hook; a Stop hook that runs `gdlint` + the test suite and blocks (exit 2) on failure so the agent must fix before finishing.

#### 10. "AAA Game Studio" Practices for a Solo Dev + Agents (things the user should have asked for)

- **Version control for large binaries:** Git LFS with a Godot `.gitattributes` (track `*.png *.jpg *.wav *.ogg *.mp3 *.glb *.fbx *.blend *.ttf` etc. via `filter=lfs diff=lfs merge=lfs -text`) and `eol=lf` normalization. Use the official `github/gitignore` **Godot.gitignore** as the base (`.godot/`, `.import/`, exported binaries, `*.translation`).
- **File locking for binaries:** Git LFS `--lockable` (or a tool like Anchorpoint) prevents two people/agents clobbering un-mergeable binaries.
- **CI/CD:** GitHub Actions for automated Godot exports (headless export templates) and running gdUnit4 (there's a marketplace `gdunit4-action`). Even solo, CI catches regressions the agents introduce.
- **Project structure:** follow Godot's official project-organization docs — a directory per scene grouping its `.tscn`, script, and assets; use `snake_case` for files/dirs (Godot 4 default); name scripts/scenes after the root node.
- **GDScript style:** the **official GDScript style guide** (PEP 8-inspired): tabs, LF, snake_case functions/vars, PascalCase classes/nodes, CONSTANT_CASE constants; member order Signals → Enums → Constants → Variables → Methods → Inner Classes; prefer static typing consistently. Encode this in a `gdscript-style` skill + `AGENTS.md` so both agents comply.
- **Scene/script separation, unique names (`%NodeName`), autoloads sparingly** — per Godot best-practices docs.
- **Addon management:** keep third-party addons in `addons/`; track which are LFS/binary; document versions in the dev log.
- **Performance profiling:** Godot's built-in profiler/monitors; MCPs like Godot MCP Pro expose profiling tools.
- **Security / permissions hygiene (critical when agents have shell + file access):** deny reading `.env` and secrets via PreToolUse hooks; block `rm -rf`, `DROP TABLE`, force-push via PreToolUse pattern matches; use `ask`/`deny` permission rules; keep API keys in environment variables, never in committed files (Antigravity sends file context to Google's cloud, so keep secrets outside the project dir). Add `disable-model-invocation: true` to any skill/command with side effects.
- **Cost management:** model routing (Haiku/Sonnet/Fable), prompt caching, `/context` audits, disabling unused MCP servers, and time-boxing.

#### 11. Things the user forgot — explicit extrapolation

- **`/init`** — run it first to bootstrap CLAUDE.md from the existing repo (and fold in AGENTS.md).
- **MCP scope:** local (this machine), project (`.mcp.json`, checked into the repo — shareable), user (`~`, all projects). Commit a `.mcp.json` with the Godot + Context7 + git servers so the setup travels; scope secret-bearing servers to user scope.
- **Secrets for MCP servers needing API keys** (GitHub PAT, Meshy, Obsidian): use `env` blocks referencing environment variables, never hardcode; keep out of committed `.mcp.json`.
- **Model selection strategy:** Fable 5 (or Opus-tier) as orchestrator/hardest reasoning; Sonnet for bulk implementation; Haiku for classification/search/formatting. Use **plan mode** for anything destructive or large before executing.
- **Time-boxing (Fable 5 access ends July 13):** use Fable 5's limited window to *scaffold and verify* the environment (it's the highest-leverage use), then let cheaper models run day-to-day. Do the setup in one or two focused sessions with caching intact.

### Recommendations (staged)

**Stage 0 — Before touching Fable 5 (do now):**
- Install Godot 4.x, git, git-lfs, Node.js ≥18, and `uv`. Confirm Antigravity 2.0 and Claude Code are installed and authenticated.
- Decide the memory scope: start minimal (Markdown dev log + Memory MCP).

**Stage 1 — Foundation (Fable 5, session 1):**
- Run `/init`. Create `AGENTS.md` (source of truth) + `CLAUDE.md` (`@AGENTS.md` + Claude-specific overrides). Add Godot .gitignore/.gitattributes + Git LFS. Scaffold `.claude/` (skills, agents, settings.json, hooks) and `.agents/` (rules, workflows). Create `docs/devlog/CHANGELOG.md` and `docs/adr/`.
- Install MCP servers: Godot AI (dlight), Context7, Filesystem, Git, GitHub. Commit `.mcp.json` (secret-free). Configure Antigravity's `~/.gemini/config/mcp_config.json` (remember `serverUrl` for HTTP).

**Stage 2 — Feedback loops & skills (Fable 5, session 1–2):**
- Install gdUnit4 + gdlint/gdformat. Author custom skills: `godot-run-scene`, `godot-test`, `godot-lint`, `gdscript-style`, `godot-debug`, `devlog`, `adr`.
- Wire hooks: PostToolUse `gdformat`; Stop runs `gdlint` + tests (exit 2 on fail) and appends dev log; SessionStart injects recent dev log + git status; PreToolUse blocks `.env` reads and dangerous commands.

**Stage 3 — Coexistence & polish:**
- Symlink `.claude/skills/` ↔ `.agents/skills/` if sharing skills. Define agent lanes in AGENTS.md. Install `caveman` (optional). Set up a GitHub Actions workflow for exports + gdUnit4.

**Stage 4 — Ongoing (post-Fable 5):**
- Day-to-day on Sonnet; reserve Opus/Fable-tier for hard problems. Audit `/context` and `/mcp` regularly; disable unused servers.

**Benchmarks that change the plan:**
- If `/context` shows MCP tools >25k tokens → disable servers or rely on Tool Search.
- If both agents keep hitting git conflicts → move to git worktrees or stricter lane separation.
- If the project grows a large evolving fact base → reconsider Graphiti.
- If Godot MCP Pro's 172 tools prove worth $15 for scene-heavy work → switch primary.

### Caveats
- **Antigravity 2.0 and Fable 5 are recent;** exact file paths, config keys, and one-click installer support should be verified at runtime — treat every version-specific detail here as "verify."
- **Godot MCP metrics move fast;** the recommendation assumes current maintenance holds. dlight's Godot AI has strong momentum but low GitHub star traction and a README tool set still smaller than marketing claims.
- **The Godot Foundation is AI-skeptical** (its June 30, 2026 "Changes to our Contribution Policies" post bans AI-generated substantial code and autonomous AI-agent PRs to the engine) — no official MCP is coming, and this signals community tooling is the only path. This policy governs contributions to the *engine itself*, not your use of these MCPs on your own project.
- **Antigravity sends file context to Google's cloud** and (in preview) requires a personal Gmail — keep proprietary secrets out of the project directory.
- **Caveman savings are output-only** (~65% of prose output on average, per its README), and it adds ~1–1.5k input tokens/turn — real whole-session savings are small.
- **Two agents on the same files simultaneously will conflict** — lane discipline and frequent commits are mandatory, not optional.
- Some cited figures come from vendor blogs (Ziva, Summer Engine, Upstash) — used for context, not authority.

---

## PART B — HANDOFF PROMPT FOR CLAUDE FABLE 5

> Paste everything below into Claude Fable 5.

---

You are setting up my agentic development environment for **Godot 4.x game development**. I am a ~3-year dev, somewhat new to advanced agent tooling. I use **Google Antigravity 2.0** (agentic VS Code fork) and I'm adding **Claude Code** alongside it. Both agents must work on the same repo without conflicting. I only have access to you (Fable 5) until **July 13**, so be efficient and thorough in this window. Work in **plan mode** before any destructive step, and keep MCP servers and the model fixed within each work phase to preserve prompt caching.

**PHASE 0 — VERIFY FIRST (do not skip).** Before installing anything, verify these because they change fast and I may be on a recent version:
1. The current best **Godot MCP server**. My research recommends **dlight's "Godot AI"** (open-source, MIT; PyPI `godot-ai`; from the "MCP for Unity" team), runner-ups **Fennara** (Godot 4.5+) and **Godot MCP Pro** (paid ~$15). Re-check each repo's last-commit date, Godot 4.x support, and whether its one-click installer supports MY Claude Code and Antigravity versions. Confirm my Godot version to choose correctly (Fennara needs 4.5+). Pick ONE; tell me your choice and why before installing.
2. Whether **Claude Code still reads only CLAUDE.md (not AGENTS.md)** — confirm the `@import`/symlink interop is still required.
3. Current **Claude Code hook events and exit-code semantics** (esp. that exit 2 blocks, exit 1 does not), **Tool Search / deferred MCP tool loading** availability (default-on; auto-activates when MCP tool descriptions exceed ~10% of context), and the **Antigravity MCP config path** (`~/.gemini/config/mcp_config.json`) and that HTTP servers use `serverUrl` not `url`.
4. Current **gdUnit4** and **gdlint/gdformat** install methods and Godot LSP port (6005).
Report what you verified and any deltas from the above, then proceed.

**PHASE 1 — FOUNDATION.**
5. Run `/init` to bootstrap. Create **`AGENTS.md`** as the single source of truth (project overview, Godot version, GDScript style rules from the official style guide, project structure conventions, agent "lanes", testing/commit rules). Create **`CLAUDE.md`** whose first line is `@AGENTS.md`, plus any Claude-only overrides.
6. Add Git version control hygiene: the official Godot `.gitignore`, a `.gitattributes` with Git LFS tracking for binary asset types (`*.png *.jpg *.wav *.ogg *.mp3 *.glb *.fbx *.blend *.ttf` …) and `eol=lf` normalization. Initialize Git LFS.
7. Scaffold directories: `.claude/skills/`, `.claude/agents/`, `.claude/settings.json`, `.claude/hooks/`; `.agents/rules/`, `.agents/workflows/`; `docs/devlog/CHANGELOG.md`; `docs/adr/`.

**PHASE 2 — MCP SERVERS.**
8. Install and configure (for BOTH agents where possible): the chosen **Godot MCP**, **Context7** (up-to-date Godot API docs), official **Filesystem** (scoped to project root), **Git**, and **GitHub** (`serverUrl https://api.githubcopilot.com/mcp/`, PAT via env var). Optionally the official **Memory** MCP.
9. Create a **project-scoped `.mcp.json`** (committed, secret-free) for the shareable servers. Put any API-key-bearing servers in user scope with `env` referencing environment variables — NEVER hardcode secrets.
10. Configure Antigravity's `~/.gemini/config/mcp_config.json` to match (use `serverUrl` for HTTP servers). Keep total enabled tools under ~50; confirm Tool Search is active.

**PHASE 3 — SKILLS, SUBAGENTS, HOOKS (the feedback loops).**
11. Install gdUnit4 (testing) and gdlint/gdformat (lint/format).
12. Author these custom **skills** (each `.claude/skills/<name>/SKILL.md`, tight description, body + bundled scripts): `godot-run-scene` (headless `godot --headless`), `godot-test` (run gdUnit4 headless, return only failures), `godot-lint` (gdlint + gdformat), `gdscript-style` (official style guide), `godot-debug`, `devlog` (append structured entry to `docs/devlog/CHANGELOG.md`), `adr` (write an ADR).
13. Author read-only **subagents** in `.claude/agents/`: a `godot-reviewer` (code review, Sonnet), a `test-runner` (runs tests, returns failures only, Haiku/Sonnet). Restrict them to read-only tools.
14. Configure **hooks** in `.claude/settings.json`:
    - **PostToolUse** (matcher `Write|Edit`): run `gdformat` on the edited file.
    - **Stop**: run `gdlint` + gdUnit4; **exit 2** (block) on failure; on success, append a dated summary (files touched, `last_assistant_message`) to `docs/devlog/CHANGELOG.md` (async).
    - **SessionStart**: echo `tail -n 50 docs/devlog/CHANGELOG.md` + `git status`/branch to stdout (injected as context).
    - **PreToolUse** (matcher `Read`/`Bash`): block reading `.env`/secrets and dangerous commands (`rm -rf`, force-push) via exit 2.
15. Mirror the shared dev-log convention into Antigravity: add a `.agents/rules/devlog.md` rule instructing Antigravity to read and append to the SAME `docs/devlog/CHANGELOG.md`, and add the GDScript style + lane rules to `.agents/rules/`.

**PHASE 4 — DUAL-AGENT COEXISTENCE.**
16. Ensure ONE source of truth: AGENTS.md shared; CLAUDE.md imports it. If I want shared skills, symlink `.claude/skills/` ↔ `.agents/skills/` (note Windows symlink caveat — prefer `@import` where possible).
17. Write explicit **agent lanes** into AGENTS.md (e.g., Antigravity = browser-verified UI/scene visual tasks; Claude Code = GDScript logic, tests, refactors) and a rule that **the two must not edit the same files simultaneously**; commit (Conventional Commits) between hand-offs.
18. Set `.gitignore` to commit `.claude/`, `.agents/`, `AGENTS.md`, `CLAUDE.md`, `.mcp.json`, `docs/`; ignore `.claude/settings.local.json` and any secrets.
19. (Optional) Install `caveman` (`claude plugin marketplace add JuliusBrussee/caveman` → `claude plugin install caveman@caveman`) at `lite`/`full`, OR add the three-line terse-style rule to CLAUDE.md.

**PHASE 5 — CI/CD & AAA polish.**
20. Add a GitHub Actions workflow: run gdUnit4 (headless) on push/PR and (optionally) automated Godot headless exports. Add the official style guide reference and naming conventions to AGENTS.md.

**PHASE 6 — VERIFY & TEST (do all of these and report results):**
21. `claude mcp list` (or `/mcp`) shows all servers **connected**; `/context` shows MCP tools using a reasonable token budget (flag if >25k).
22. Trigger the Godot MCP: ask it to report the connected project and inspect the scene tree.
23. Create a trivial gdUnit4 test; confirm the `godot-test` skill runs it headless and reports pass/fail; confirm the Stop hook blocks on a deliberately failing test.
24. Edit a `.gd` file; confirm the PostToolUse `gdformat` hook fired.
25. Start a new session; confirm the SessionStart hook injected the dev log + git status.
26. Confirm both agents can read `AGENTS.md` (Antigravity natively; Claude Code via the `@AGENTS.md` import) and both can read/append `docs/devlog/CHANGELOG.md`.
27. Attempt to read a `.env` file; confirm the PreToolUse hook blocks it.
28. Print a final summary: what was installed, every file/dir created, which MCP server was chosen and why, and a short "how to use this daily" guide (which model for which task, when to `/clear` vs `/compact`, lane discipline).

If anything is ambiguous, verify via web/docs rather than guessing.