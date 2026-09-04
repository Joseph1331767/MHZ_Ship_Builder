# 0002 — Attachment is a sphere-traced ray from the parent's centre, not per-primitive UV coordinates

- **Date**: 2026-08-31
- **Status**: Accepted

## Context

Every non-root part in a ship attaches to the *surface* of its parent. The builder needs exactly one
way to answer "given a child's angular placement, where does it sit and how is it oriented?" that works
identically across six primitive families today (box, sphere, cylinder, cone, capsule, torus) and any
family added later, without a mesh, a collider, or a physics query — the truth layer (`core/`) has no
`Node`, no `SceneTree`, and must be exactly reproducible headless.

Two alternatives were considered and rejected before settling on the current model:

1. **Per-primitive UV parametrization.** Each shape family defines its own 2D surface mapping (e.g. a
   box unwraps by face, a sphere by spherical coordinates, a torus by its two angles). This requires a
   bespoke, hand-verified parametrization per family forever — every new primitive is a new geometry
   problem before it is a new *feature* — and gives no principled way to attach a child to a shape whose
   surface is not analytically nice once ops (taper, twist, ribs, scallops) have deformed it.
2. **Mesh raycast against a triangulated proxy.** Requires a mesh to exist before attachment can
   resolve, which inverts the architecture's own ordering (SPEC §2: build → evaluate → bake, where the
   *editing* mesh is a view of the doc, never an input to it) and reintroduces a physics/collision
   dependency inside a module whose whole point is to stay pure data.

## Decision

Store each part's attachment as four numbers in the parent's local frame — `yaw`, `pitch`, `roll`,
`offset` (SPEC §3, CONTRACT) — and resolve the placement purely from the parent's own `ResolvedShape.sdf()`:

1. Build direction `d` from `(yaw, pitch)`: `d = (cos(pitch)*sin(yaw), sin(pitch), cos(pitch)*cos(yaw))`.
2. Sphere-trace `d` outward from the parent's local origin against the parent's SDF until it crosses
   zero, giving anchor point `P`. No mesh, no collider, no physics query — just repeated calls to a pure
   function.
3. Take the SDF's gradient at `P` (central differences) as the mount normal `N`.
4. Build a roll-relative tangent basis by projecting parent-local `-Z` onto the tangent plane at `P`
   (falling back to `+Y` at the poles) and rotating it about `N` by `roll`.
5. Non-convex shapes (a torus's local origin sits outside its own solid, so "march outward from the
   origin" has nothing to march from) get a second trace mode, declared per shape family via
   `origin_inside: bool`: march inward from the shape's bounding sphere instead, taking the first zero
   crossing.
6. Domain-warping ops (taper, twist) turn the SDF into a Lipschitz *bound* rather than a true distance;
   the tracer divides its step by the shape's `lipschitz` factor (>= 1.0) so it cannot overshoot and
   tunnel through thin geometry.

This lives in exactly one place, `core/attach/ship_attach.gd` (`class_name ShipAttach`), and is the
same code path for every family, present or future.

## Consequences

- **One universal rule for every shape.** Adding the torus and capsule families required zero
  special-casing beyond declaring `origin_inside` — no new parametrization, no new UI code for that
  family's attach controls.
- **Headless-testable with exact expectations.** Because resolution is pure math over
  `ResolvedShape.sdf()`, `tests/core/test_attach.gd` can assert known `(yaw, pitch, roll, offset)` inputs
  against known output `Transform3D`s per shape, with no scene, no viewport, no rendering.
- **Angular input is non-linear across a flat face.** Near a box corner, half a degree of yaw moves the
  anchor much further across the surface than it does mid-face. The stored record stays exact regardless
  — the cost lands entirely on the *UI*, which must map mouse-drag screen motion to surface arc-length
  and solve back to `(yaw, pitch)` for the drag to feel linear, rather than mapping screen delta directly
  to angle delta.
- **Non-convex shapes need a second trace mode.** This is a real added case to test and maintain (both
  trace directions, per family, per SPEC §3), not a free abstraction.
- **Domain-warped shapes require the Lipschitz safety factor.** Every `ResolvedShape` must expose a
  correct `lipschitz`, and getting it wrong (SPEC §4: non-uniform scale contributes
  `max(scale)/min(scale)`) produces a tracer that silently tunnels through geometry rather than an
  obvious crash — this is the sharpest edge in an otherwise simple model and the reason
  `ship_attach.gd` is called out in `API_CONTRACT.md` as "the most-tested code in the project."
