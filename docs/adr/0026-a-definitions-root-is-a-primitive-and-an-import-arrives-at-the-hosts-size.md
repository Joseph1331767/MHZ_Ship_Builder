# 0026 — A definition's root is a primitive; an import arrives at the host's size

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236`
  before and after.
- **Amends**: ADR 0024/0025 (what `import_from` produces; what `make_component` accepts)
- **Records**: FOLLOWUPS F38

## Context

> "importing components is freezing the system. i imported a carbon, and i see the proton, i see
> the entire atom, i dont see the tunnels used in the model, and i dont see the electrons .. i
> added the proton cluster and it came in way way too large, like 5x .. tried pulling in the
> entire carbon class ship as a component module and it basically froze .. adding any component
> as a single primitive, a wing, a proton cluster, or an entire ship should all act the exact
> same."

Measured headlessly, importing a carbon into a hydrogen and placing both: nothing in core takes
more than a few hundred milliseconds. The whole-ship definition's root was the nucleus
*instance*, and an instance has no shape of its own — so the ship instance had **no proxy shape**
and **no protons under it** (the root of a definition is never expanded; the instance's own entry
stands for it). The builder was handed a placed part with nothing to draw or hover. And the class
was built at its own default span — sized per class by a volume budget: a carbon's proton
11.8 m, a hydrogen's 25.5 m — nothing like a ship built from the start dialog's sliders.

## Decision

**A definition's root is a primitive.** `make_component` refuses a head that is an instance.
`import_from` flattens the source ship first — its root instance dissolved on a copy, as many
times as it nests — before it makes the ship's definition, so every definition it makes has a
proxy shape and expands whole. Measured after: the ship instance has a proxy, 19 keys under it,
29 parts in the field.

**An import offers the ship's ARMS.** Every subtree hanging off the source's root — off the root
component's inner parts too, which is where a class hangs its tunnels — becomes a definition,
identical arms once (`_subtree_signature`: every part's family, manufacturer, params, scale,
role, blend, its attach numbers except the head's, and the shape of the tree; ids and names are
not it). A carbon imports as its nucleus, `CARBON ARM 1` (a tunnel and its pod; the four
identical arms are one) and `CARBON` itself. A single primitive is the palette's own business.

**A class is built at the host ship's dimensions.** `ShipComponentImport.template_options`
reads the host's root family, manufacturer and span, and its first tunnel's family, bore and
length, off the host's resolved shapes; the class is rebuilt from those, so a nucleus dropped
into a ship of 8 m protons arrives as 8 m protons. Measured: a carbon built at span 8.0 / bore
2.2 hands back 8.0 / 2.2 and rebuilds to the same proton within a centimetre.

## Consequences

**Measured.** gdUnit4 **289/289** (new: the import's three definitions, the ship's primitive
root and full expansion, the refused instance head, the host-derived options). Windowed check
PASSED. Selfcheck hash unchanged; validator 0 warnings.

**The freeze is not reproduced in core**; it followed the shapeless instance into the builder,
which no longer exists. If it returns, the placement path is where to look (F36 item 1).

**A placed instance still mirrors part by part** across the symmetry plane — a nucleus placed
off-centre in a symmetric ship gets twins of its off-plane protons, as any placed subtree's parts
do. The rule predates components; a component-as-a-unit twin is F38.

**An arm's head keeps its own attach numbers only as a placed instance** — the definition's root
has none, by construction; the instance is placed with the four numbers like any part.
