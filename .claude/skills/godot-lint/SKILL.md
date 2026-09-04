---
name: godot-lint
description: Lint and format all GDScript with gdlint/gdformat. Use before finishing a task or when the user asks for a style pass.
---

# Lint + format GDScript

```powershell
# 1. Lint (report problems)
gdlint scripts/ scenes/ tests/

# 2. Check formatting
gdformat --check scripts/ scenes/ tests/

# 3. Auto-fix formatting
gdformat scripts/ scenes/ tests/
```

- Fix every gdlint finding — warnings are errors in this repo (AGENTS.md §2). If a rule genuinely conflicts with a deliberate pattern, discuss with the user before adding any ignore.
- Skip directories that don't exist yet; `addons/` is third-party — never lint or reformat it.
- The Stop hook runs gdlint automatically on changed files; running this skill first avoids being blocked at the end.
