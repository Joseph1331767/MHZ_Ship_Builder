---
name: devlog
description: Append a structured entry to the shared dev log (docs/devlog/CHANGELOG.md) — run at the end of every work session or when the user says "log this".
---

# Append a dev log entry

Append to the **END** of `docs/devlog/CHANGELOG.md` (append-only — never rewrite earlier entries):

```markdown
## [YYYY-MM-DD] <Short action title>
- **Author**: Claude Code
- **Status**: Completed | Testing | In Progress

### Changes Made:
1. `<file/system>`: <what and why>

### Verification:
- <headless check / test results / "awaiting user visual verification">
```

- Use today's real date. Be factual and specific — this log is the shared memory between Claude Code and Antigravity, and it is injected into every new session.
- If an architectural decision was made, also write an ADR (`/adr`).
