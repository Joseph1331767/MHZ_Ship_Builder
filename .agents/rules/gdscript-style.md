# GDScript style (pointer)

The authoritative style rules are in the repo root `AGENTS.md`, sections 2 (strict static typing + naming) and 3 (directory conventions). Follow them exactly. Key non-negotiables:

- Every variable and function signature explicitly typed; warnings are errors.
- `snake_case` files/functions/variables, `PascalCase` classes, `UPPER_SNAKE_CASE` constants, past-tense `snake_case` signals.
- Modern Godot 4.3+ APIs only (`TileMapLayer`, not `TileMap`).
- Throwaway files go in `scratch/` only (AGENTS.md §4).
