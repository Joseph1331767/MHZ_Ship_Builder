# 0027 — A tunnel meeting a module is hatched by default

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236`
  before and after. A placed part gains a joint the player could have added by hand.
- **Amends**: ADR 0025 (where LINK and the seam menu find their pairs)
- **Records**: FOLLOWUPS F39

## Context

> "i added the carbon ship to the carbon ship and double clicked into the carbon ship component,
> then selected a tunnel and the main proton room, and tried to change their link to hatch and
> the system crashed .. all default pre-made ships, and any future procedurally generated ones
> should have hatch connections between each and every tunnel and linked module by default, and
> all electron clusters and proton clusters set to open rooms."

`PartTreePanel._on_link` wrote its status line through `doc.parts[...]` with a pair that was an
inner part of the open component — the one lookup on that path that had not been moved to
`part_at`. The "400 warnings" before it were the shapeless whole-ship instance of ADR 0026,
already gone.

## Decision

**A fresh seam between a tunnel and a module is HATCHED.** `ShipSeams.default_link_for(doc, a,
b)` answers HATCHED when one key is a hallway and the other a room, by role — an instance
answering with its definition root's role, so an imported arm placed on a proton hatches too —
and WALL otherwise. The builder applies it when a placement commits
(`_default_link_for_placed`): a seam that already has a link keeps it; the hatch is its own undo
step after the placement's. The templates already hatch every tunnel at both ends and open every
nucleus; this makes a placed or generated tunnel behave the same.

**LINK and the seam menu see inner parts.** The tree's status line reads parts through
`part_at`; the seam menu's pairs come from `ShipSeams.pairs_within`, which knows what hangs off
what inside a component, instead of a walk over `doc.parts`.

## Consequences

**Measured.** gdUnit4 **290/290** (new: the default link rule on a carbon's tunnel, pod and root,
and on an imported arm instance). Windowed check PASSED. Selfcheck hash unchanged; validator 0
warnings.

**Two tests moved** from the seams suite to the components suite: the seams suite was at the
30-public-method cap.

**"Electron clusters" have no meaning in the templates yet** — every electron is one tunnel and
one pod, hatched at both ends. When a class places pods together, the nucleus rule (open joints
written into the definition) is the one to reuse. F39.
