# 0007 — Shear: the fourth morph verb, and the one op that had to be inserted

- **Date**: 2026-09-01
- **Status**: Accepted
- **Ruleset**: `3.0.0` → `4.0.0` (`ShipDoc.RULESET_VERSION`, `ShapeGen.RULESET_VERSION`)
- **Amends**: `docs/SHIP_BUILDER_SPEC.md` §4, the op order — a CONTRACT section
- **Closes**: FOLLOWUPS F10 item 3

## Context

The author, listing what Spore's post-placement handles do:

> "spor has handles that reveal after placement that lets you stretch, skew, twist, rotate etc"

Three of the four were there. Stretch is the per-axis `scale`, driven by the six morph handles;
twist is the `twist_deg` param; rotate is the three rings (ADR 0004). **Skew was not**, and could
not be added as a handle because there was nothing for a handle to drive: `ResolvedShape` had no
shear term and `SdfOps` had no shear warp. FOLLOWUPS F10 recorded it as "needs a ruleset decision
before it needs a handle". This is that decision.

## Decision

**`SdfOps.shear(p, kx, kz)` slides the XZ plane in proportion to Y**, so a part leans without its
ends changing shape — a parallelogram out of a box, a slanted spar out of a straight one. `kx` and
`kz` are metres of sideways travel per metre of Y, and they are measured **from the centre**: the
+Y end moves `+k · half_h`, the -Y end `-k · half_h`. Leaning about the foot instead would drag
every child mounted near the +Y end through the air on a control that is supposed to be a shape
edit.

The domain is sheared by the **inverse** of the lean you want to see, exactly as `taper` divides
rather than multiplies: warping the domain one way moves the solid the other.

### It had to be inserted, and that is the interesting part

SPEC §4 says, and has always said: *"Adding an op appends to the END of this list, never inserts.
Reordering is a ruleset bump."* A domain warp **cannot** be appended. Everything after `base_sdf`
operates on a distance, not on a point; there is no position left to warp. Shear sits last of the
three warps — as close to appending as the stage allows — and the SPEC now carries that exception
with the reasoning attached, so the next domain warp faces the same argument rather than
rediscovering it.

**The insertion is only safe because the default is the identity.** At `shear == (0, 0)` the warp
is skipped by an equality test and the field is bit-identical to what it was, which
`test_zero_shear_is_bit_identical_to_no_shear` asserts with `is_equal`, not `is_equal_approx`,
across a grid of sample points on a shape carrying taper AND twist. No saved ship moves. The bump
is for the canonical form — every part now carries `skew_x` and `skew_z` — and for the op order
itself, which AGENTS §8b makes a version event whatever its visible effect.

### The Lipschitz cost is exact, not padded

A shear is linear, so the largest singular value of its inverse is available in closed form:
`sqrt(1 + k²/4) + k/2` for a shear of magnitude `k`. It multiplies the other warps' bound rather
than competing with it in a `max`, because a part that is both sheared and twisted is genuinely
harder to trace than either alone. An estimate would have been the wrong kind of cheap here:
underestimating a Lipschitz bound does not make the tracer slightly wrong, it makes it tunnel
straight through the part.

### The preview gets it exactly, for free

A shear is a matrix, so `ShipMeshGen.mesh_basis()` folds it into the instance basis beside the
scale and the preview reproduces it **perfectly** — the only warp of the three that the preview
does not have to approximate. Order matters and follows the SDF: the field divides by the scale
first and shears second, so the matrix is `Shear · Scale`. The other way round scales the lean
instead of leaning the scaled part, which is a different shape everywhere the scale is non-uniform.

`_scaled_convex()` became `_transformed_convex()` at the same time: a `Vector3` cannot carry a
lean, so a sheared part's pick body would have stayed upright while the part leaned out of it.

### The handle is the top and bottom arrows, pushed sideways

Pulled along their own axis they stretch, as they always did; pushed sideways they lean. The other
four morph handles only stretch — a side handle pushed sideways is already its own stretch, and
overloading it would make one gesture mean two things on one handle.

**Which lean a sideways push drives is decided by the camera, not by a fixed mapping.** The part's
local +X and +Z are projected to screen and the drag goes to whichever runs more nearly
left-to-right, signed so that pushing right always leans the part right. A fixed mapping would send
a rightward drag to +X even after the player has orbited round to where +X points at them, and a
handle that leans away from the pointer reads as broken rather than as a convention.

### Skew is a PARAM, not a field on the part record

Unlike scale, rotation and offset, the lean lives in `ShipPart.params` as `skew_x` / `skew_z`,
because a shear is a domain warp in the generator: it belongs where taper and twist live, it clamps
through the family's own authored range like they do, and it appears in the inspector's SHAPE
section for free with no per-param UI code. All four families expose it at ±0.8.

## Consequences

- **Ruleset 4.0.0.** Nothing moves; every ship re-hashes. `data/ships/` is empty, so nothing is
  invalidated in practice.
- **`ResolvedShape.local_aabb()` grows with the lean** — by `|k| · half_h` on each of X and Z. A
  bound that did not grow would clip the leaning end straight out of the bake, which is the one
  place nobody would see it happen. Gated.
- **Two more params in the canonical form** for every part, on every family.
- **The preview mesh cache key gained the shear**, even though the shear rides in the basis and two
  parts differing only in lean legitimately share one mesh — because `collision_for()` keys off the
  same signature and its hull IS pre-transformed. Sharing that would have left one part's pick body
  wearing another's lean.

## Verification

- `tests/core/test_shape_gen.gd`: the +Y end moves one way, the -Y end the other, the centre and
  the height do not move; zero shear is bit-identical to no shear on a taper+twist shape; the
  bound grows by exactly `k · half_h` and contains the sheared corner; every family exposes the
  params with a non-degenerate range.
- `scratch/diag_primitives.gd` renders a sheared spar through the real console and measures its
  on-axis pole at +0.625 outside the solid — which is what a lean means and what an upright part
  cannot produce.
- gdUnit4 169/169 · selfcheck PASSED · validator PASSED · visual check PASSED · gdlint clean.
