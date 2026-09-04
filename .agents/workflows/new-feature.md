# /new-feature — phased feature implementation

Follow these steps strictly, in order (AGENTS.md §7 and §9 apply):

1. **Align**: inspect the relevant scenes/scripts, summarize findings, ask the user targeted questions about intent, physics/visual expectations, and how it fits the design doc. Wait for explicit alignment.
2. **Pin contracts**: write the data models, class names, signals, and file layout into the plan BEFORE any implementation. Confirm with the user.
3. **Implement incrementally**: one checklist item at a time, strictly typed GDScript, self-contained module directory.
4. **Verify each increment**: run the godot-check skill (foreground, hard timeout); query godot-ai MCP diagnostics if the editor is open. Fix all warnings.
5. **Hand off visuals**: prompt the user to run the scene in Godot; never claim visual behavior works.
6. **Log**: run the devlog skill; update the node-of-truth status table. Remind the user to commit (agents do not run git writes).
