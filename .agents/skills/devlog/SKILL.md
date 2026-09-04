---
name: devlog
description: Use this skill at the end of every work session, or when the user says "log this" — appends a structured entry to the shared dev log both agents read.
---

# Append a dev log entry

Append (never rewrite earlier entries) to `docs/devlog/CHANGELOG.md`, at the END of the file:

```markdown
## [YYYY-MM-DD] <Short action title>
- **Author**: Antigravity
- **Status**: Completed | Testing | In Progress

### Changes Made:
1. <file/system>: <what and why>

### Verification:
- <how it was verified: headless check, tests, or "awaiting user visual verification">
```

Keep it factual and specific — this log is the shared memory between Antigravity and Claude Code.
