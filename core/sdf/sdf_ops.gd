class_name SdfOps
extends RefCounted

## Domain warps, displacements and combinators applied on top of the base primitives.
##
## SPEC section 4 fixes the order these are applied in (taper, twist, SHEAR, base, inflate, ribs,
## scallops) and that order IS the ruleset — see `ResolvedShape.sdf()`, the only place it is
## implemented. Changing any formula here moves every saved ship and needs a ruleset bump.
##
## Shear was inserted before the base rather than appended (ADR 0007). A domain warp CANNOT be
## appended: everything after the base operates on a distance, not on a point. It is placed last
## of the three warps, which is as close to appending as the stage allows, and at its default of
## zero it is the identity — so no shape that predates it moves by so much as a float.
##
## Angles cross this API in DEGREES (API_CONTRACT global rules); radians only live inside a
## function body.
##
## `core/` purity: static only, no state, no allocation, no engine objects.

## The taper warp is never allowed to collapse the XZ plane completely: the factor is clamped
## up to this, so a taper of 1.0 pinches to 5% instead of to a degenerate zero-width sliver.
const MIN_TAPER_FACTOR: float = 0.05

## Guards divisions by an authored half-height of zero.
const MIN_HALF_H: float = 0.000001

## Guards divisions by a zero scale component.
const MIN_SCALE: float = 0.000001

## Ceiling on the returned Lipschitz divisor. Without it a pathological part could stall the
## sphere-tracer (step size -> 0) instead of merely making it slower.
const MAX_LIPSCHITZ: float = 64.0


## Domain warp along Y. The taper factor is `1.0 - amount * ((p.y / half_h) * 0.5 + 0.5)`:
## 1.0 at the -Y end, `1.0 - amount` at the +Y end.
##
## CONVENTION — ruleset-visible, do not flip without a ruleset bump: the SOLID is scaled by
## that factor, so a POSITIVE amount NARROWS the shape toward +Y (taper 0.3 pinches the +Y end
## to 70% of its width) and a negative amount flares it. That is why the domain coordinates are
## DIVIDED by the factor rather than multiplied: warping the domain inward widens the solid.
##
## The factor is clamped up to MIN_TAPER_FACTOR, so it can never reach zero or go negative and
## the division is always safe.
static func taper(p: Vector3, amount: float, half_h: float) -> Vector3:
	if is_zero_approx(amount):
		return p
	var h: float = maxf(half_h, MIN_HALF_H)
	var f: float = 1.0 - amount * ((p.y / h) * 0.5 + 0.5)
	if f < MIN_TAPER_FACTOR:
		f = MIN_TAPER_FACTOR
	return Vector3(p.x / f, p.y, p.z / f)


## Domain warp: rotates the XZ components about +Y by `deg_per_m` degrees for every metre of Y.
static func twist(p: Vector3, deg_per_m: float) -> Vector3:
	if is_zero_approx(deg_per_m):
		return p
	var a: float = deg_to_rad(deg_per_m) * p.y
	var c: float = cos(a)
	var s: float = sin(a)
	return Vector3(c * p.x - s * p.z, p.y, s * p.x + c * p.z)


## Domain warp: SHEAR. Slides the XZ plane sideways in proportion to Y, so the part leans without
## its ends changing shape — a parallelogram out of a box, a slanted cylinder out of a straight one.
##
## The fourth of the four morph verbs the author named: "spore has handles that reveal after
## placement that lets you stretch, skew, twist, rotate etc". Stretch is the per-axis scale, twist
## and rotate already existed; this is skew.
##
## `kx` and `kz` are metres of sideways travel per metre of Y, measured from the CENTRE — so the
## +Y end moves `+k * half_h` and the -Y end `-k * half_h`, and the part leans about its own middle
## rather than pivoting on its foot. Leaning about the foot would drag every child mounted near
## +Y through the air on a control that is supposed to be a shape edit.
##
## The domain is sheared by the INVERSE of the shear you want to see, exactly as `taper` divides
## rather than multiplies: warping the domain one way moves the solid the other.
static func shear(p: Vector3, kx: float, kz: float) -> Vector3:
	if is_zero_approx(kx) and is_zero_approx(kz):
		return p
	return Vector3(p.x - kx * p.y, p.y, p.z - kz * p.y)


## Lipschitz cost of a shear. A shear is linear, so its exact cost is the largest singular value of
## the inverse map, which for a shear of magnitude k is `sqrt(1 + k*k/4) + k/2`. Cheap, exact, and
## not an estimate — used rather than a padded guess because underestimating here tunnels the
## sphere-tracer straight through a leaning part.
static func shear_lipschitz(kx: float, kz: float) -> float:
	var k: float = Vector2(kx, kz).length()
	if k <= 0.0:
		return 1.0
	return sqrt(1.0 + k * k * 0.25) + k * 0.5


## Inflate (round): pushes the whole surface outward by `r`. Exact — it costs no Lipschitz.
static func inflate(d: float, r: float) -> float:
	return d - r


## Displacement: `count` rings of amplitude `amp` stacked along the local Y span [-half_h, half_h].
## Returns exactly 0.0 when the op is inactive so the caller can add unconditionally.
static func rib_disp(p: Vector3, count: int, amp: float, phase: float, half_h: float) -> float:
	if count <= 0 or is_zero_approx(amp):
		return 0.0
	var span: float = maxf(2.0 * half_h, MIN_HALF_H)
	return amp * sin(float(count) * TAU * (p.y / span) + phase)


## Displacement: a cheap deterministic cross-ripple in the XZ plane. Not noise, not seeded here —
## the phase is derived from the shape seed by ShapeGen and passed in.
static func scallop_disp(p: Vector3, amp: float, freq: float, phase: float) -> float:
	if is_zero_approx(amp) or is_zero_approx(freq):
		return 0.0
	return amp * sin(freq * p.x + phase) * sin(freq * p.z + phase)


## Polynomial smooth minimum (quadratic, IQ). `k` is the blend radius in metres.
## `k <= 0.0` returns `minf(a, b)` EXACTLY — a hard union must be bit-exact, not approximated.
static func smooth_min(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h: float = clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


## Conservative Lipschitz bound (>= 1.0) for a shape carrying these warps and this scale.
## The sphere-tracer steps `abs(sdf) / lipschitz`; overestimating costs extra trace steps,
## underestimating tunnels through surfaces, so every term errs high and they multiply.
##
## - non-uniform scale contributes `max(scale) / min(scale)` (SPEC section 3),
## - twist contributes `1 + abs(rad(twist)) * max_radius`, approximated here by the largest
##   scale component; ShapeGen re-tightens this against the resolved `bound_radius`,
## - taper contributes `1 / (1 - abs(amount))`, the worst-case expansion of the XZ domain
##   (the warp divides by the taper factor, so distances there are stretched by its inverse).
static func lipschitz_for(taper_amt: float, twist_deg: float, scale: Vector3) -> float:
	var sx: float = maxf(absf(scale.x), MIN_SCALE)
	var sy: float = maxf(absf(scale.y), MIN_SCALE)
	var sz: float = maxf(absf(scale.z), MIN_SCALE)
	var hi: float = maxf(sx, maxf(sy, sz))
	var lo: float = minf(sx, minf(sy, sz))
	var l: float = hi / lo
	l *= 1.0 + absf(deg_to_rad(twist_deg)) * hi
	l *= 1.0 / maxf(1.0 - absf(taper_amt), MIN_TAPER_FACTOR)
	return clampf(l, 1.0, MAX_LIPSCHITZ)
