# 0005 — One parametric body of revolution: the cone and the capsule are cylinder params

- **Date**: 2026-09-01
- **Status**: Accepted
- **Supersedes**: nothing structurally; retires two entries in `data/shapes/families.json` and
  two `ResolvedShape.Base` values from the pack's reach
- **Ruleset**: `2.0.0` → `3.0.0` (`ShipDoc.RULESET_VERSION`, `ShapeGen.RULESET_VERSION`)

## Context

The author, verbatim:

> "the capsule shouldnt be there, a cylinder is more appropriate with capsule end options via
> round edge or fillet edge shapes on primitives. - cone is also a cylinder with oine end radius 0
> and one larger.. remember these are primitives', we can have special capsule options but
> crucially needs to come from the primitives' parameters and surface noise and surface functions."

And, the report that exposed it:

> "i dont see a cylinder add just the modified cylinder. and when i add that i cant see teh
> parameters to un bevel the ends of the cylinder, meaning im stuck with a capsule. came for cone,
> i dont see how its a cylinder with dif dia ends."

The catalogue shipped six families, three of which were the same solid of revolution seen from
three angles: `cylinder_spar` (CYLINDER), `cone_nose` (CONE) and `capsule_tank` (CAPSULE). Each was
a separate palette entry with its own base primitive, its own cost, its own param ranges — and no
path between them. A player who wanted a nose fairing could not narrow a cylinder into one; a
player who wanted a flat-ended tank could not un-round a capsule, because the roundness was not a
parameter, it was the family's identity. There was no `end_radius` and no `end_round` to look for,
which is exactly what "i cant see teh parameters to un bevel the ends" describes.

Two smaller faults fell out of the same root:

- `cylinder_spar` shipped `round` (the whole-surface inflate) with a **non-zero default**, so the
  first cylinder a player placed already had softened edges and the only control that could
  sharpen them was doing a different job than its name suggested.
- The palette drew `cone_nose` as a flat triangle and `cylinder_spar` as a rectangle with two
  horizontal lines. Through the 16-colour quantizer at a 40 px cell, the cylinder glyph and the
  capsule glyph were indistinguishable — the plain cylinder the author went looking for was
  sitting in the palette wearing the wrong face. (Fixed 2026-08-31; recorded here because it is
  half of why the family was reported missing rather than merely inflexible.)

## Decision

**One primitive, parameterised.** `SdfPrims` gains the general form and the catalogue keeps a
single cylinder family:

```
capped_cone(p, r1, r2, half_h)          exact IQ capped cone: r1 at -Y, r2 at +Y
rounded_cone(p, r1, r2, half_h, e)      the same solid with both end DISCS rounded by e
```

`rounded_cone` is built by eroding the cone by `e` and inflating the result back out by `e`, which
is the standard offset-surface construction and stays an exact Euclidean distance. Every shape the
three retired families produced is a point in its parameter space, and the corner cases fall out
of the arithmetic instead of being special-cased:

| want | `r2` | `e` |
|---|---|---|
| cylinder / spar / corridor | `r1` | 0 |
| frustum, nozzle, bell mouth | `< r1` or `> r1` | 0 |
| sharp cone, bow fairing | 0 | 0 |
| rounded nose | 0 | `> 0` |
| capsule, pressure tank | `r1` | `r1` |

`ResolvedShape` carries two new fields: `radius_b` (the +Y end radius, unscaled metres) and
`end_round` (how far the end discs are rounded, unscaled metres). The family exposes them as
RATIOS — `end_radius` against `size.x`, `end_round` against the wider end — so retuning a family's
`base_size` cannot silently turn its cones back into cylinders.

**Three decisions inside the decision, each of which had a wrong answer that looked right:**

1. **`radius_b` defaults to −1, meaning "match `size.x`", resolved in `refresh()`.** A default of
   `0.0` is the obvious choice and it turns every hand-built cylinder — including the ones in
   `tests/` and in `SnapTargets._unscaled_twin()` — into a spike, silently, with nothing to error
   on. The negative sentinel makes "nobody set this" mean "a plain cylinder", which is the only
   safe reading.
2. **`end_round` is measured against the WIDER end, not the narrower one.** Against the narrower
   end a cone can never be rounded at all, because its narrow end is a point and `min` is zero —
   and "a rounded nose" is one of the shapes this primitive exists to produce. Rounding past the
   narrow end is still well defined: `capped_cone` floors a negative radius at zero, so the eroded
   solid becomes a sharp cone and inflating it puts a spherical cap on the tip. Pushed all the way
   to the wide radius, every shape in the family converges continuously on the capsule.
3. **`end_round` is a separate field from `round_r`, not a reuse of it.** `round_r` inflates the
   whole surface and therefore GROWS the part; `end_round` keeps the part's extent exactly where it
   was. A player rounding a cylinder into a capsule must watch the ends curve, not watch the part
   swell and shove its neighbours apart. `tests/core/test_sdf_prims.gd` gates that as a property:
   for every `e`, the +Y pole and the widest flank stay exactly on the surface.

**Two families are removed from the pack.** `cone_nose` and `capsule_tank` are gone from
`data/shapes/families.json` and from every manufacturer's narrowing block. `ResolvedShape.Base.CONE`
and `.CAPSULE` **stay in the enum** — API_CONTRACT section 6 pins them and an old document may name
them — and both still evaluate; nothing in `data/` produces them. `SdfPrims.cone()` is now a
one-line wrapper over `capped_cone`.

**Two manufacturers get their voice back.** Halcyon and Obelisk expressed themselves almost
entirely through the two retired families, so removing them would have left Halcyon narrowing one
family and Obelisk two. Both now narrow `cylinder_spar` instead — Obelisk pins `end_round` high
(a certified pressure vessel IS a capsule), Halcyon rounds generously and disables all tooling,
Meridian's default `end_radius` is 0.45 because their catalogue is full of wound nose cones.

**The preview mesh is lathed.** No Godot primitive spans this family and `CylinderMesh` cannot
round an end at all, so `ShipMeshGen` builds the CYLINDER preview as a surface of revolution from
an exact profile. `round_r` folds into it for free rather than being approximated, because
inflating a rounded cone by ρ is exactly a rounded cone with all four parameters raised by ρ:
both sides reduce to `capped_cone(r1-e, r2-e, h-e) - (e+ρ)`. This is the one place the preview is
MORE honest than the rest of it, and it is deliberate: `radius_b` and `end_round` are not ornaments
like ribs, they are which part this is, and a preview that smoothed them away would be showing the
player a different part rather than a simplified one.

**`cylinder_spar`'s shape defaults change.** `round` now defaults to `0.0` (a crisp tube, not a
pre-softened one) and `base_size` is `[0.5, 1.5]` — a slim 1 m × 3 m tube rather than a 2 m × 2 m
drum, which is both the tunnel scale the ship templates want and the silhouette the word "spar"
promises.

## Consequences

- **Ruleset 3.0.0.** Every catalogue entry a document may name has changed, and a newly placed
  cylinder carries two params that did not exist, so the canonical form and the micro-detail seed
  both move. AGENTS section 8b makes that a bump whatever its visible effect. `data/ships/` is
  empty, so no saved ship is invalidated in practice.
- **The palette is four entries, not six.** Box, sphere, cylinder, torus. That is the honest count
  of primitives; the catalogue did not shrink, it stopped listing one primitive three times.
- **Cost moves through the model, not the catalogue.** The two retired families carried complexity
  2.5 and 3.5. A shaped cylinder now reaches the same band through `cylinder_spar`'s 3.0 base times
  the `param_complexity` multiplier its two new params feed.
- **`param_complexity` learned that neutral is not always the minimum.** `end_radius`'s neutral
  value is 1.0, mid-range; scored from the range minimum, every plain tube would have been billed
  for a cone it is not. The scoring is now distance-from-neutral over the longer half-span, which
  is arithmetically IDENTICAL for every pre-existing param (their neutral is their minimum), so no
  existing part's cost moved.
- **A cylinder's snap rim can move.** The rim ring sits on the widest circumference, which is now
  the fat END of a frustum rather than always mid-height. Ends within `RIM_TIE_EPS` count as equal
  so floating-point noise in an authored `1.0` cannot flip a rim from the middle of a tube to its
  bottom edge and take every part snapped there with it.
- **`SnapTargets._unscaled_twin()` had to learn the two new fields.** Without them the twin
  resolves `radius_b` to `size.x` and projects every snap point of a cone onto the surface of the
  cylinder it is not. This is the same class of bug as F0: a copy constructor that silently omits a
  field added later.

## Verification

- `tests/core/test_sdf_prims.gd` drives the general form to each special case over a 84-point
  spread and compares against the dedicated primitive that used to be the only way there:
  equal radii ≡ `cylinder()`, a zero end ≡ `cone()`, full rounding ≡ `capsule()`. Plus the
  extent-preservation property and the over-large-`e` saturation.
- `tests/core/test_shape_gen.gd` gates the compatibility default (a hand-built CYLINDER is a
  cylinder), both ratios producing the shapes they name, and a plain cylinder scoring no
  end-shaping complexity.
- `scratch/diag_primitives.gd` renders tube / frustum / cone / capsule / rounded nose / bell mouth
  through the real console and asserts all six differ on screen and that each one's own +Y pole
  lands exactly on its surface.
- gdUnit4 162/162 · selfcheck PASSED · data validator PASSED (0 warnings) · visual check PASSED.
