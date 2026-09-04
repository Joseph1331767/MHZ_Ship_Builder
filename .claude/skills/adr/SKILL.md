---
name: adr
description: Record an architectural decision as a numbered ADR in docs/adr/. Use whenever a significant design, dependency, or pattern choice is made.
---

# Write an Architecture Decision Record

1. Find the next number: list `docs/adr/` and increment the highest `NNNN`.
2. Create `docs/adr/NNNN-short-kebab-title.md` from `docs/adr/template.md`:

```markdown
# NNNN — <Title>

- **Date**: YYYY-MM-DD
- **Status**: Accepted | Superseded by NNNN

## Context
<the problem / forces at play>

## Decision
<what was decided, concretely>

## Consequences
<what becomes easier, harder, or constrained>
```

3. Mention the new ADR in the devlog entry for the session.
