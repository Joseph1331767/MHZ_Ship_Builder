# 0024 — Components are rooms; the nucleus is the root component

- **Date**: 2026-09-06
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236`
  before and after. The attach model gains a legal parent (an inner part of an instance);
  every document that could be placed before places the same way.
- **Amends**: SPEC §3 (attach: a parent may be `"<instance>/<inner>"`), ADR 0018 (what a
  template builds), ADR 0020/0021 (rooms), ADR 0022 (the INTERIOR mode's materials),
  ADR 0023 (the ghost and AUTO are withdrawn; the update button stays)
- **Records**: FOLLOWUPS F36

## Context

> "interior view isnt showing only the inner mesh faces (excluding their back faces) and show the
> exterior mesh back faces (excluding their outward facing faces) .. the ghost view is forcing the
> mesh update at each change auto and its freezing the system .. just kill the ghost view ..
> instead we force the update button .. when i click on the proton module they all should
> highlight as the proton should be classified as a component (by default) when double clicking
> like in sketchup we can wash out the rest of model and show the individual parts of that
> component .. we need an import components button that can import the components from another
> ship, including the ship as a component itself, and components containing more components ..
> youll have to fix our bakes to be component based."

## Decision

**A component instance is one room.** `ShipMeshBake.plan` joins every placed member of an
instance into one room by membership, joint or none — the definition's inner walls were dropped
when it was lifted, and a ship dropped in as a component is one open hull. `ShipSeams.seams`
emits the inner seams of every instance (each inner part on the inner part it hangs from, the
definition root's children on the instance itself) as OPEN, flat, hole-less seams: the SDF has no
wall there, and the exploded view has a seam to pull each piece off. The engine bake keys every
piece by its placed id — inner parts included — so a component bakes as its pieces from one
shell, and the exploded and baked views draw one module per piece.

**The nucleus is the ship's root component.** `ShipTemplates.build` lifts the root and the
bodies fused into it (`ShipComponents.make_component` — the root can be lifted; the instance
becomes the root) before anything hangs off it, and every tunnel keeps the proton it was laid out
for by attaching to that proton's inner key. Clicking any proton selects the instance (every
inner visual highlights, the rule the scene already had); the nucleus is in the palette to place
again. The open joints of ADR 0023 are gone: membership does what they did.

**A part may hang off an inner part of an instance** — `parent = "<instance>/<inner>"`. The
attach pass expands an instance the moment it is placed, so its inner keys are there for later
parents; `ShipDoc`'s walks (children, descendants, ancestors, order, the delete cascade, the
dead-joint sweep) treat such a child as the instance's; the validator accepts the parent and a
joint end that is an inner part; `ShipSeams._joint_for` collapses stored ends to the instance as
it always did the queried ones. The tree lists the child under the instance's row.

**Double-click opens a component (isolation).** `ShipView3D` reports a double-click with what it
landed on; on an instance the builder isolates it: the scene and the exploded view wear a washed
material (dim, translucent) on everything outside, and a pick inside resolves to the INNER part
rather than the instance, so the component's own parts select one by one. `ShipDoc.part_at`
hands the inspector a cached inner part; `commit_edit` writes it back into the definition
(`store_inner`) and re-syncs — every instance follows, SketchUp's semantics. ESC, or a
double-click on empty space or on anything outside, closes it.

**IMPORT COMPONENTS.** The palette's button lists the saved ships; `ShipComponents.import_from`
copies every definition of the chosen ship under a fresh id with the references between them
remapped, and adds the ship itself as one more definition rooted at its root (its own instances
repointed at the copies; its joints left behind — a component is one open room). Nested
definitions were already legal (`MAX_NESTING_DEPTH`, `check_cycles`); the palette lists every one.
`ShipComponents.dissolve` is the inverse for one instance — its inner parts back as parts, the
children hung off them and the joints naming them following — used by the tests for a walled
nucleus and available for a tree verb.

**The INTERIOR mode draws two surfaces only.** The interior surface's front faces, the exterior
surface's back faces, and the cuts (the wall thickness at every opening) both-sided; nothing
translucent, no wire. The near wall is not there; the far cavity wall faces the camera. The
faceted shader is `cull_disabled` by design (mirrored twins, F7), so the mode wears two variants
of it built at load by editing that one render_mode word (`_faceted_shader("back" | "front")`);
the shader already flips its normal on back faces, so both variants shade alike. Measured before
this: the interior surface drew both its sides and the ship read solid again — "after bake
interior render doesnt work right".

**Inside a component every pair is open, and LINK says so.** `ShipSeams.pairs_within` pairs an
inner part with what it hangs from; `mode_for` answers OPEN for two parts of one instance, joint
or none (`within_one_instance`); `cycle_link` and the tree's LINK refuse such a selection with
the reason — the parts are one room already; dissolve the component to wall them. The tree's
instance row reads `(N PARTS, ONE ROOM)`.

**The ghost and AUTO are withdrawn.** The ray-marcher answered the research (instant, off the
fields, no bake) but its automatic re-bake froze the builder for the bake's seconds and the
ghost read flat. Nothing bakes by itself now: every edit lights `UPDATE MESHES *`, the bar
shows while the engine works, and the baked view is the assembled view once a bake exists.

## Consequences

**Measured.** gdUnit4 **287/287** (new: the nucleus as root component and one room on both
families; `import_from`; `dissolve`; `part_at`/`store_inner`; the component's inner seam as open;
the bake's progress ticks). Windowed check PASSED with an isolation stage: a two-part component
lifted, opened — 10 visuals washed, 4 kept, a pick inside resolving to `p_0012/cp_0002` — and
closed on ESC; explode 13 modules, update 14 baked assembled. Selfcheck hash unchanged; validator
0 warnings.

**What the tests had to give up.** "A component has one seam" — it has its walled seam and its
inner open ones. Counts of `doc.parts` as "everything that bakes" — the placed map is the count,
inner parts included. The joint-mechanics tests dissolve the nucleus first, because they are
about joints between plain parts.

**Interactive placement onto a component attaches to the instance**, not to the inner part
under the cursor: `ShipPlacement` keeps `doc.parts.has(parent)` in a dozen places. The model
allows the finer attach; the drag does not yet use it. F36.

**gdUnit stops a suite at its first failure** — the "Executed (8/8)" that looked like a crash
was the runner's count of what ran. Fix the first failure to see the next.
