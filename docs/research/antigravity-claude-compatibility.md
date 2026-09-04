# Two Agent Files or One? Configuring Claude Code + Antigravity on the Same Godot Repo

## TL;DR
- **Your mutual-mirroring / dual-write plan is technically viable but is the weakest of the available options, and the wider practitioner community has decisively converged on the opposite pattern: one canonical shared file (AGENTS.md) that each tool reads via symlink or import, plus small tool-private files for anything agent-specific.** The good news for your specific case: as of July 2026 you don't need to mirror anything, because both of your tools can already be pointed at a single `AGENTS.md`.
- **The counter-position you were arguing is correct in principle but overstated for your scale.** Mirroring two markdown blocks is a real dual-write-without-transaction and *will* drift, but for a solo dev the blast radius is tiny and a ~10-line pre-commit hook neutralizes it. The stronger objection is not "drift" — it's that mirroring relies on LLMs reliably executing an "also update the other file" instruction, and there is now quantified published evidence they do not, especially after context compaction.
- **Recommended for you (Godot, solo, Antigravity 2.0 + Claude Code, role isolation, tight time budget): single source of truth in `AGENTS.md` (read natively by Antigravity), a one-line `CLAUDE.md` containing `@AGENTS.md` plus Claude-only rules below it, and put the private per-agent material in `.claude/` and `GEMINI.md` / `.agents/rules/`.** This gives you real role separation without any mirroring, and it takes about ten minutes to set up.

## Key Findings

**1. Both your tools can read one AGENTS.md — this changes the whole debate.** AGENTS.md is now an open standard: the official site (agents.md) describes it as "a simple, open format for guiding coding agents, used by over 60k open-source projects. Think of AGENTS.md as a README for agents." It was launched by OpenAI/Google/Cursor/Factory/Sourcegraph in August 2025 and donated to the Linux Foundation's Agentic AI Foundation in December 2025 (arXiv 2604.21090: "As of December 2025, more than 60,000 open-source projects had adopted the format and more than twenty AI coding tools support it"). Google Antigravity added native `AGENTS.md` support in IDE v1.20.3 (March 5, 2026); it reads both `AGENTS.md` and `GEMINI.md` at session start, with `GEMINI.md` taking precedence on conflicts. Claude Code, per Anthropic's official docs, still reads **only `CLAUDE.md`, not `AGENTS.md`** — but the docs now explicitly document the fix: put `@AGENTS.md` inside `CLAUDE.md`. So a single shared `AGENTS.md` can serve both tools with zero duplication.

**2. Claude Code does NOT natively read AGENTS.md (verified against official docs, July 9, 2026).** The official memory docs ("How Claude remembers your project," code.claude.com/docs/en/memory) state plainly that Claude Code reads `CLAUDE.md`, not `AGENTS.md`. The widely-repeated claim that "Claude Code reads AGENTS.md as a fallback when no CLAUDE.md exists" is **false** and contradicted by the docs. GitHub feature requests #6235 (opened Aug 2025) and #34235 (Mar 2026, marked duplicate of #6235) are both still open with no roadmap commitment. This is a recent, fast-moving area — verify before you depend on it.

**3. The community's dominant pattern is single-source-of-truth, not mirroring.** Across dozens of blog posts, docs, and tools, the consensus is: keep everything shared in one file, and bridge to tool-specific filenames via **symlink** or **@import**. Mirroring/duplication is universally described as the thing to avoid ("the moment your project changes, those files drift out of sync").

**4. There is real tooling for this, and it does NOT do mutual mirroring — it generates from one source.** `rulesync` (161,458 weekly npm downloads per Socket.dev; current version 5.2.2 by dyoshikawa; supports 30+ tools including dedicated `antigravity-ide`/`antigravity-cli` targets), `ruler` (intellectronica/ruler), and `ai-rules-sync` all treat one directory/file as canonical and *generate* the rest. None implement "each agent updates every file."

**5. Mirroring's real weakness is instruction-following reliability, not just drift.** Published research ("Governance Decay," arXiv 2606.22528, Shiyang Chen) quantifies it: "Across 1,323 episodes, violation rises from 0% with the policy in full context to 30% after compaction, reaching 59% for some models; when the constraint survives the summary, violation remains 0%, but when it is dropped, violation reaches 38%." Anthropic's own docs warn CLAUDE.md is "context, not enforced configuration." So a rule that says "always also update the other shared block" is exactly the kind of low-salience standing instruction that gets silently dropped mid-session.

**6. File-based "privacy" between two agents that can both read the disk is a convention, not a boundary — and Claude Code's enforcement mechanisms are currently buggy.** Nothing stops Claude Code from reading `AGENTS.md` or `.agents/` if it decides to. Claude Code has `permissions.deny` rules and sandboxing, but multiple open bug reports (#8961, #6699, #27040, #3501) and a January 2026 Register investigation document that deny rules and `.claudeignore` are inconsistently enforced. Real isolation comes from not putting the material where the other agent looks, plus (imperfect) deny rules and PreToolUse hooks.

## Details

### The AGENTS.md landscape as it affects you

AGENTS.md is "a README for agents" — a plain-markdown file at the repo root. Its whole reason for existing is the exact problem you're wrestling with: before it, developers maintained `CLAUDE.md`, `.cursorrules`, `GEMINI.md`, `copilot-instructions.md` separately and they drifted. Tools that read `AGENTS.md` natively now include OpenAI Codex, Cursor, GitHub Copilot, Gemini/Antigravity, Jules, Factory, Zed, Aider, Amp, RooCode, Windsurf, Cline, OpenCode, and Continue. The one prominent holdout is Claude Code.

For your two tools specifically:
- **Google Antigravity 2.0**: reads `AGENTS.md` (native since IDE v1.20.3, March 5 2026), `GEMINI.md` (Antigravity-specific, highest user priority), and workspace rule files under `.agents/rules/` (note: default moved from `.agent/rules/` singular to `.agents/rules/` plural, with backward compat). Precedence: System rules (immutable) → `GEMINI.md` → `AGENTS.md` → `.agents/rules/`. Antigravity also supports `@filename` references *inside* rules files, resolved relative to the rule file or the repo root. Note Antigravity 2.0 split into `antigravity-ide` (desktop) and `antigravity-cli` (`agy`, the Gemini CLI successor; Gemini CLI shut down for consumer tiers June 18, 2026). Skills moved to `.agents/skills/`. There is a documented global-config path conflict (`~/.gemini/GEMINI.md`) if you also run the legacy Gemini CLI (tracked as gemini-cli issue #16058).
- **Claude Code**: reads `CLAUDE.md` at repo root, `.claude/rules/`, `~/.claude/CLAUDE.md` (user), and managed-policy CLAUDE.md. It supports `@path` imports inside CLAUDE.md: expanded at launch, relative to the importing file, recursive up to a documented four hops (some sources say five — treat as "a few, not unlimited"), skipping code blocks. Tilde imports (`@~/...`) are unreliable (issue #8765, closed not-planned) — use absolute paths for home-dir imports.

### Import/reference resolution — what's verified

- **Claude Code `@import`: verified working and officially documented.** Anthropic's docs: "CLAUDE.md files can import additional files using `@path/to/import` syntax. Imported files are expanded and loaded into context at launch... maximum depth of four hops." First external import triggers a one-time approval dialog (a gotcha in headless/CI runs). Imported files' heading levels are NOT re-nested, which can scramble document structure (issue #6321, won't-fix).
- **Antigravity `@filename` references inside rules files: verified in official docs.** Resolved relative to the rules file, or absolute, or repo-relative fallback.
- **Whether Antigravity resolves `@import` inside `AGENTS.md` itself (vs. inside its `.agents/rules/` files): not clearly documented — treat as uncertain.** Your safest cross-tool shared file is one that needs no imports to be complete.
- **The AGENTS.md standard itself has no import mechanism** — Codex, Copilot and the base spec rely on hierarchical/nested discovery, not file inclusion. So `shared_common.md` imported by both is reliable on the Claude side (via CLAUDE.md `@import`) and on the Antigravity side (via a `.agents/rules/` file with `@shared_common.md`), but is NOT guaranteed if you expect a bare root `AGENTS.md` to import it for every tool.

### The symlink approach and its real-world caveats

The single most popular pattern is `ln -s AGENTS.md CLAUDE.md`. Claude Code follows symlinks transparently and operates on the target file. Git tracks symlinks natively (mode 120000) so they survive clone on Unix. Caveats that matter for you:
- **Windows is the big one.** Git for Windows disables symlink support by default; it checks out symlinks as plain text stubs unless `core.symlinks=true` AND the OS permits creation (Developer Mode, or the "Create symbolic links" privilege, or admin/UAC elevation). Without Developer Mode, `CreateSymbolicLinkW` silently fails and git writes text stubs with exit code 0 — a silent failure. GitHub's own Copilot CLI hit this hard enough to rip out 185 symlinks (issue #2286).
- **Antigravity + symlinks is reportedly flaky.** One practitioner guide reports that symlinking `GEMINI.md`/`CLAUDE.md`/`AGENTS.md` "doesn't seem to work properly" in the Antigravity IDE and recommends a global rule that tells the agent to look for `AGENTS.md` instead. Since Antigravity reads `AGENTS.md` natively, you don't need a symlink on that side anyway.
- **For a solo dev on one machine, symlinks are fine** if you're on macOS/Linux or have Windows Developer Mode on. If you're on Windows without it, prefer the `@import` approach, which is OS-independent and needs no elevated permissions.

### What people actually do (surveyed patterns)

1. **Single canonical file + symlink** (most common): `AGENTS.md` is truth; `CLAUDE.md`, `.github/copilot-instructions.md`, etc. are symlinks to it.
2. **Single canonical file + @import** (Anthropic's own recommendation for the Claude side): one-line `CLAUDE.md` with `@AGENTS.md`.
3. **Generate-from-source tooling**: `rulesync`, `ruler`, `ai-rules-sync` — write once in a `.ruler/` or `.rulesync/` dir, generate all tool files, optionally check in a pre-commit hook (`rulesync generate`; `agentsync sync --check` fails CI if out of sync).
4. **Manual duplication / mirroring** (your plan): universally described as the drift-prone anti-pattern; nobody recommends it as a first choice, and the "each agent updates both" variant appears essentially nowhere as a documented, endorsed practice.

Named tools with specifics: `rulesync` (dyoshikawa, 161,458 weekly npm downloads, v5.2.2, targets include `antigravity-ide`/`antigravity-cli`, `claude`, `codex`, `cursor`, `copilot`, `gemini-cli`, `windsurf`, etc.); `ruler` (intellectronica); `ai-rules-sync`/AIS (lbb00, symlink-based, has a `.local.json` for private rules); `agentsync`/ai-rules-sync (PanisHandsome, zero-dep, `sync --check` for CI); `claude-md-symlinker` (dutifuldev, a Claude hook that auto-creates CLAUDE.md→AGENTS.md symlinks); `context-drift` (geekiyer, scans a CLAUDE.md for stale paths/scripts/deps and cross-file CLAUDE.md↔AGENTS.md conflicts). For Godot specifically there's `GodotPrompter` (jame581; 51 Godot 4.x skills for Claude Code/Copilot/Gemini/Cursor) and `godot-skills` (Randroids-Dojo; GdUnit4 + PlayGodot automation).

### Evidence for and against mirroring

**Against (the strong version):**
- *Drift is real but minor at your scale.* The generic critique — "duplicated instruction files drift out of sync the moment the project changes" — is repeated across essentially every AGENTS.md writeup. Tools like `context-drift` exist specifically to detect CLAUDE.md↔AGENTS.md conflicts, which tells you the failure mode is common enough to productize.
- *The real problem is instruction-following reliability.* Your plan's load-bearing assumption is "if both have the rule to update both shared blocks, I don't see the issue." The issue is that the rule lives in exactly the place that's least reliably followed. Anthropic's docs: both memory systems are "loaded at the start of every conversation. Claude treats them as context, not enforced configuration... The more specific and concise your instructions, the more consistently Claude follows them" — i.e., probabilistic, not guaranteed. Practitioners observe agents drop rules mid-session as context fills; an Antigravity field guide notes that a mid-chat exception "now outweighs the original prohibition on every subsequent retry," and that adherence "snaps back" only on a fresh session. The "Governance Decay" study (arXiv 2606.22528) formalizes and quantifies this: "violation rises from 0% with the policy in full context to 30% after compaction, reaching 59% for some models... when it is dropped, violation reaches 38%." A "remember to also edit the other file at end of task" rule is precisely this kind of low-salience standing policy. There's also an "instruction budget": frontier models reliably follow only on the order of 150–200 instructions, and Claude Code's system prompt already consumes some of that — so a mirroring rule competes for a scarce resource.
- *It's a genuine dual-write-without-transaction.* The distributed-systems literature is unambiguous: "you cannot atomically commit to two independent systems without a distributed transaction." Two files updated by two independent agents in two sessions is that pattern. The canonical fix is exactly single-source-of-truth (one authoritative copy) plus derived projections — which is what symlink/import/codegen give you.

**For (the honest steelman of your position):**
- *Blast radius is tiny.* You're a solo dev with two markdown files, not a fintech firm with Kafka. A drift event costs you a confused agent and a `git diff`, not a corrupted production database. "Overkill" is a fair charge against invoking Kafka outbox patterns here.
- *Drift is cheaply caught.* A pre-commit hook that byte-compares the two shared blocks converts "silent drift" into "commit blocked with a clear message" — turning the unbounded failure into a bounded, visible one, exactly as worktree advocates convert silent file-stomping into visible merge conflicts.
- *You retain per-tool tailoring.* Two files does let each agent have private instructions in the same file it already reads, with no import indirection. This is a real ergonomic benefit, and it's the one thing single-file loses — though import/symlink+private-dir recovers it.
- *Betting on convergence isn't crazy.* Manifold's market "Will Claude Code support AGENTS.md in 2026?" (bessarabov) is priced at ~60%, with the YES case citing "GitHub issue #6235 has 3,200+ upvotes and every major competitor (Codex, Cursor, Windsurf, Gemini CLI) already supports AGENTS.md." If native support lands, any bridging becomes moot.

### Role/context isolation — the nuance that matters most for you

You want Claude Code NOT to see everything you feed Antigravity. Two truths:

1. **There IS solid prior art for giving different agents different scopes.** The multi-agent literature (Vellum, Red Hat's supervisor pattern, Anthropic's own multi-agent research) treats context isolation as a core technique: each agent gets a scoped window, least-privilege tool access, and only the docs relevant to its lane (UI vs backend, metrics vs logs). The security rationale is concrete: a smaller context per agent shrinks the prompt-injection blast radius ("if a single agent gets compromised, what can it reach? If the answer is more than one system, split the work"). So wanting role isolation is well-founded.

2. **BUT file-topology "privacy" between two agents that both have filesystem read access is a convention, not an enforced boundary.** If Claude Code can read the repo, it *can* read `AGENTS.md`, `GEMINI.md`, or `.agents/rules/` any time it wants — those files simply aren't auto-loaded into its context. "Hiding" here means "not auto-injected," not "inaccessible." To make it a real boundary you need enforcement:
   - **Claude Code `permissions.deny`** (e.g. `"deny": ["Read(./.agents/**)", "Read(./GEMINI.md)"]`) — but be warned these are **buggy and inconsistently enforced today** (issues #8961, #6699, #27040, #3501; The Register, Jan 2026). Deny rules are also "best-effort" for built-in read tools and don't cover every path/tool.
   - **PreToolUse hooks** — the community's actual reliable workaround for hard blocks, since they intercept tool calls deterministically before execution. Anthropic's docs themselves say: "To block an action regardless of what Claude decides, use a PreToolUse hook instead."
   - **`.claudeignore`** — does NOT reliably block reads (Anthropic confirmed the intended mechanism is settings.json permissions, not `.claudeignore`).
   - The pragmatic honest answer for a solo dev: **isolation-by-convention is good enough for "I don't want to clutter Claude's context with Antigravity's persona instructions," but it is NOT a security control.** If the material is genuinely sensitive, don't put it in the repo the other agent operates in.

### Dual-agent coordination beyond rules files

If you ever run both agents at once on the same repo, the file-stomping problem is separate from the rules-file problem and much more dangerous. The established fix is **git worktrees**: one linked working directory + branch per agent, sharing one `.git`, so conflicts surface at merge time instead of live overwrites. Claude Code has a `--worktree` flag; `agy` (Antigravity CLI) runs in any directory so it works in a worktree too. Complements: lane/domain separation (agent A owns `scenes/`, agent B owns `scripts/`), a shared markdown task list / dev log both read, `.env.local` per worktree for ports/DB, and sequential (not simultaneous) merges. For a solo dev the simplest discipline is: don't run both agents on the same files at the same time; use worktrees if you want true parallelism. Practical ceiling reported by practitioners is ~3–5 parallel agents before merge/coordination overhead eats the gains (and note `agy`'s aggressive shared quota — one Pro user reportedly hit "individual quota reached" after two prompts).

## Recommendations

**Stage 1 — Set up single-source-of-truth (do this first; ~10 minutes).**
1. Put ALL shared project facts in `AGENTS.md` at the repo root. Antigravity reads it natively. Keep it under ~200 lines / ~150 instructions (both tools degrade with long files; Claude docs target "under 200 lines").
2. Create a minimal `CLAUDE.md`:
   ```markdown
   @AGENTS.md

   ## Claude Code–only instructions
   - (put anything Claude-specific here, below the import)
   ```
   This is Anthropic's officially documented pattern. No duplication, no drift, no symlink permissions issue.
3. Put Antigravity-only material in `GEMINI.md` (highest priority for Antigravity, and Claude never reads it) and/or `.agents/rules/` files.
4. Commit all of it. On Windows, if you prefer symlinks instead of the import, first run `git config core.symlinks true` and enable Developer Mode — otherwise stick with `@import`, which needs neither.

**Result:** you get exactly the role isolation you wanted — Claude sees `AGENTS.md` (shared) + `CLAUDE.md` extras; Antigravity sees `AGENTS.md` (shared) + `GEMINI.md`/`.agents/rules/` extras — with ONE shared block that physically cannot drift because it exists once.

**Stage 2 — If you insist on two separate files with mirrored shared blocks (your original plan), make drift impossible to commit.** Wrap the shared region in markers in BOTH files:
```markdown
<!-- SHARED:START -->
... identical shared project facts ...
<!-- SHARED:END -->
```
Then add a pre-commit hook (`.git/hooks/pre-commit`, `chmod +x`) that extracts the block from each file and byte-compares:
```bash
#!/usr/bin/env bash
extract() { awk '/<!-- SHARED:START -->/{f=1;next} /<!-- SHARED:END -->/{f=0} f' "$1"; }
if ! diff <(extract AGENTS.md) <(extract CLAUDE.md) >/dev/null; then
  echo "❌ SHARED block differs between AGENTS.md and CLAUDE.md. Sync them before committing."
  exit 1
fi
```
This converts silent drift into a blocked commit with a clear message. But note this defends against drift, not against an agent forgetting to update either file mid-session — so still do NOT rely on the "each agent updates both" rule as your primary mechanism.

**Stage 3 — Do NOT rely on the mutual-update rule at all.** Whichever layout you pick, treat the rules file as the single source you (the human) edit, and start a fresh agent session after editing it. Don't grant in-chat exceptions to standing rules; edit the file and restart. This directly counters the compaction/instruction-drop failure mode quantified above.

**Stage 4 — For genuine isolation, add (imperfect) enforcement and don't trust it blindly.** If you truly must keep something out of Claude's view, add `permissions.deny` in `.claude/settings.json` AND a PreToolUse hook, and verify by asking Claude to read the file (it should refuse) — because deny rules are currently buggy. Better: keep sensitive material out of the repo entirely.

**Benchmarks that would change this advice:**
- If Anthropic ships native `AGENTS.md` support (watch issue #6235): drop `CLAUDE.md` to a symlink or delete it; `AGENTS.md` alone serves both. Manifold currently prices this at ~60% for 2026.
- If you add a third or fourth tool, or a teammate: adopt `rulesync` or `ruler` (generate-from-source) rather than hand-managing bridges.
- If you start running both agents simultaneously: move to git worktrees before you lose work to file-stomping.

## Caveats
- **Fast-moving, recent versions.** Antigravity 2.0 (May 19, 2026) and its AGENTS.md support (v1.20.3, March 5, 2026) and the Gemini CLI→`agy` transition (June 18, 2026) are all recent; Claude Code's AGENTS.md stance could flip at any time. Every version-specific claim here should be re-verified against `code.claude.com/docs` and `antigravity.google/docs` before you depend on it.
- **Claude Code does NOT read AGENTS.md natively as of July 9, 2026** (verified against official docs); the "fallback when no CLAUDE.md" claim circulating on some SEO sites is false.
- **Several third-party sources are marketing/SEO content** (agentpedia.codes, antigravity.md, morphllm, deployhq, etc.). Where they agree with official docs I've relied on them; version numbers and dates from them (e.g. "v1.20.3") should be treated as community-reported, not vendor-confirmed. The Antigravity official docs page I fetched did not expose version history directly.
- **Deny-rule bugs are real but may be patched.** The isolation-enforcement advice assumes current buggy behavior; if Anthropic fixes deny rules, `permissions.deny` becomes more trustworthy.
- **Reaction counts on GitHub issues #6235/#34235 are third-party estimates** ("thousands" / "3,200+" / "5,200+"); GitHub didn't render live counts on fetch. Both issues are confirmed OPEN.
- **Your Fable 5 time budget:** Stage 1 is the entire minimum viable setup and takes ~10 minutes. Stages 2–4 are optional hardening; skip them until you actually need them.