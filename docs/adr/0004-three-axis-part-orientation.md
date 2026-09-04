# 0004 — Three-axis part orientation, mount frame +Z = surface normal

- **Date**: 2026-08-31
- **Status**: Accepted
- **Supersedes**: parts of [0002 — attach model](0002-attach-model.md) (mount basis and stored
  angles only; the ray-from-centre anchor model and the snapped-attachment path are unchanged)
- **Ruleset**: `1.0.0` → `2.0.0` (`ShipDoc.RULESET_VERSION`, `ShapeGen.RULESET_VERSION`)

## Context

The brief has said the same thing since the first message, three times in the author's own words:

> "text input of angular positions of placement on the primative its being added to, **and
> orientation in 3d space of the object being added**"

> "a snaping system of .5 degrees (changeable) for **all 3 angular axises**"

> "iv been sauing 'rotation in 3d space' 'rotation in all 3 axises **with z aligned to the
> placement normal**'"

What was built gives a placed part **one** rotational degree of freedom. `ShipPart` stores
`(yaw, pitch, roll, offset)`, and of those only `roll` is an orientation: `yaw`/`pitch` choose
*where on the parent* the part lands (the azimuth/elevation of the ray from the parent's origin),
and `offset` slides it along the normal. So the three "angular axes" the snap setting claims to
serve are two placement angles and one spin — a part could be spun on the surface like a dial and
nothing else. It could not be tilted off the normal at all.

The mount frame was also built with **+Y** as the mount axis (`mount_basis` returns
`Basis(x, n, -tangent)`), which is a second, quieter mismatch with the stated convention.

Both are load-bearing enough that they cannot be patched around in the harness: the transform is
produced in exactly one place (`ShipAttach.mount_basis`), and it feeds resolve, metrics, the SDF
and the bake alike.

## Decision

### 1. A part stores a full orientation, not a spin

`ShipPart.roll: float` → `ShipPart.rot: Vector3`, degrees, applied **in the mount frame**:

| component | axis | reads as |
|---|---|---|
| `rot.x` | mount +X | tilt the part forward/back off the surface |
| `rot.y` | mount +Y | tilt the part left/right off the surface |
| `rot.z` | mount +Z = **the surface normal** | spin the part on the surface (the old `roll`) |

Composition is **`R = Rz · Ry · Rx`**, i.e. `Basis.from_euler(rot_radians, EULER_ORDER_ZYX)`.
`Rz` is applied last and therefore acts in the mount frame itself, so the "spin on the surface"
dial keeps working as a dial no matter how the part is already tilted. Tilts are applied first, in
the part's own frame, so `rot.x` and `rot.y` stay independent of the current spin.

### 2. The ROTATION frame is +Z = normal; the part still stands on its own +Y

`mount_basis` now builds an explicit mount frame

```
F = Basis(tangent x N, tangent, N)        // +Z = N, +Y = tangent, +X = Y x Z
```

and returns

```
F * Rz(rot.z) * Ry(rot.y) * Rx(rot.x + 90 deg)
```

The trailing fixed **+90 deg about X** is what keeps this from being a regression. Every primitive
in the catalogue is authored Y-major (`API_CONTRACT.md` section 6: cone apex +Y, cylinder and
capsule along Y, torus ring in XZ with axis +Y). If the child's *geometric* +Z were pinned to the
normal, a cone placed on a hull would point sideways along the surface instead of outward, and a
cylinder spar would lie flat against the plating rather than standing off it as a boom. That is
plainly not what "orientation in 3d space" was asking for.

So the alignment term maps the part's own +Y onto the frame's +Z, and the two readings of the
brief are both satisfied:

- the **rotation axes** are the mount frame's, whose **+Z is the placement normal** — `rot.z` is
  the dial that spins a part on the surface, exactly as asked;
- the **geometry** still stands up along the normal the way the shape conventions intend.

`Rx(rot.x)` and the alignment are about the same axis and therefore commute, which is why they
collapse into one `Rx(rot.x + 90)` rather than needing a separate multiply.

**At `rot == (0, 0, roll)` this is bit-for-bit the transform the old code produced.** The old
basis was `Basis(tangent x N, N, -tangent)` with `tangent` pre-rotated about `N` by `roll`;
expanding `F * Rz(roll) * Rx(90)` gives the same three columns. So no existing part moves, and the
ruleset bump below is about the canonical form, not about geometry.

### 3. Snapping applies per axis

`ShipConfig.snap_deg` (default 0.5) already existed and already defaulted to the value the brief
asks for; it now quantizes **each of the three components independently**, plus `yaw` and `pitch`
as before. One shared step, not three, because the brief says "a snaping system of .5 degrees
(changeable) for all 3 angular axises" — one system, three axes.

### 4. Ruleset 2.0.0 — for the canonical form, not for the geometry

The stored attach record changes shape: `"roll": 0.0` becomes `"rot": [0.0, 0.0, 0.0]`. That is
the input to `ShipCanonical` and therefore to `ShipHash`, so **every ship hashes differently**
even though none of them move. AGENTS section 8b makes that a ruleset bump regardless of intent,
so `RULESET_VERSION` goes to `2.0.0` in both places that carry it.

`ShipPart.from_dict` reads a legacy scalar `roll` into `rot.z` when no `rot` key is present, so a
1.0.0 document loads and renders **identically** — it simply re-hashes under the new ruleset. This
is the cheap kind of bump: recorded, not destructive.

## Alternatives considered

- **Add `tilt_x`/`tilt_y` beside `roll` and leave +Y as the mount axis.** Smaller diff, no rename
  across ~77 call sites, and it delivers three axes. Rejected: it leaves the stated convention
  ("z aligned to the placement normal") still false, and it splits one concept across a scalar and
  two scalars, so every caller has to remember the order. `Vector3` is the shape of the thing.
- **Store a quaternion or a full `Basis` per part.** Exact and order-free, but the brief is
  explicitly about *typed numeric fields* — "text input of ... orientation in 3d space" — and a
  player cannot type a quaternion. Euler degrees are the authored form; the basis is derived.
- **Keep the ruleset at 1.0.0 and call this a bug fix.** Rejected outright: AGENTS section 8b makes
  determinism a gate. A ship that hashed to X must hash to X forever *under its recorded ruleset
  version*, and the whole point of recording the version is to be able to change the rules.

## Consequences

- Every 1.0.0 document re-hashes on load; none of them move. Determinism tests that pin a literal
  hash have to be re-pinned, which is the intended cost of a version bump.
- `offset` stays measured along the surface normal via `ResolvedShape.mount_inset()`, which is the
  distance to the attach face along the part's own -Y. Once a part is TILTED off the normal that
  distance is no longer the flush distance, so a tilted part can graze or float slightly. This is
  inherent to tilting a solid off its mount face and is not corrected: correcting it would mean
  re-solving the contact point per frame, and Spore does not do that either.
- `ShipPlacement.set_values` / `values()` / `ghost_moved` carry a `Vector3` where they carried a
  `float`. `docs/API_CONTRACT.md` and `docs/API_CONTRACT_SPORE.md` are marked in place.
- The three rotation rings on the selection gizmo become genuinely independent — before this they
  all drove the same `roll`, which is why the advanced handles felt inert.
- The inspector grows two numeric fields, and the placement HUD gains something to report.
- Mirroring is unaffected in principle (`ShipMirror` reflects the resolved transform, not the
  stored angles) but its tests move, because the resolved transforms move.
