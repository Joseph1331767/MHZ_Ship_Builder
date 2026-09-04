class_name SdfPrims
extends RefCounted

## Analytic signed-distance primitives (the standard Inigo Quilez forms), Godot Y-up.
##
## Every function takes a SHAPE-LOCAL point `p` and returns a signed distance in metres:
## negative inside the solid, zero on the surface, positive outside. Each form is an exact
## Euclidean distance (Lipschitz 1) as long as the caller does not warp the domain first —
## `ResolvedShape` does warp it, which is why it also carries a `lipschitz` divisor.
##
## `core/` purity: static only, no state, no allocation, no engine objects.

## Smallest extent any primitive is allowed to collapse to, so degenerate authored data
## cannot divide by zero.
const MIN_EXTENT: float = 0.000001


## Axis-aligned box centred on the origin. `half` is the half-extent per axis.
static func box(p: Vector3, half: Vector3) -> float:
	var q: Vector3 = p.abs() - half
	var outside: float = Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
	return outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


## Sphere centred on the origin.
static func sphere(p: Vector3, r: float) -> float:
	return p.length() - r


## Capped cylinder, axis +Y, spanning [-half_h, +half_h].
static func cylinder(p: Vector3, r: float, half_h: float) -> float:
	var d: Vector2 = Vector2(Vector2(p.x, p.z).length(), absf(p.y)) - Vector2(r, half_h)
	return minf(maxf(d.x, d.y), 0.0) + Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


## Capped cone, axis +Y, spanning [-half_h, +half_h]: radius `r1` at the -Y end, `r2` at +Y.
## IQ's exact form. It is the GENERAL solid of revolution with straight sides, and the two
## shapes the catalogue used to carry as separate families are just points in its parameter
## space: `r1 == r2` is an exact cylinder, `r2 == 0` is a point-tipped cone. See ADR 0005.
static func capped_cone(p: Vector3, r1: float, r2: float, half_h: float) -> float:
	var h: float = maxf(half_h, MIN_EXTENT)
	var ra: float = maxf(r1, 0.0)
	var rb: float = maxf(r2, 0.0)
	var q: Vector2 = Vector2(Vector2(p.x, p.z).length(), p.y)
	var k1: Vector2 = Vector2(rb, h)
	var k2: Vector2 = Vector2(rb - ra, 2.0 * h)
	var cap_r: float = ra if q.y < 0.0 else rb
	var ca: Vector2 = Vector2(q.x - minf(q.x, cap_r), absf(q.y) - h)
	var k2_len_sq: float = maxf(k2.dot(k2), MIN_EXTENT)
	var t: float = clampf((k1 - q).dot(k2) / k2_len_sq, 0.0, 1.0)
	var cb: Vector2 = q - k1 + k2 * t
	var s: float = -1.0 if (cb.x < 0.0 and ca.y < 0.0) else 1.0
	return s * sqrt(minf(ca.dot(ca), cb.dot(cb)))


## A capped cone whose two end DISCS are rounded off by `e` metres — the one primitive the
## catalogue's cylinder family exposes, and the reason there is no longer a separate cone or
## capsule family (ADR 0005).
##
## Built by shrinking the cone by `e` on every side and inflating the result back out by `e`,
## which is the standard offset-surface trick and stays an exact distance because inflating a
## Euclidean distance field is exact. The corner cases fall out of the arithmetic rather than
## being special-cased:
## [codeblock]
## e == 0                      -> flat discs on both ends: a plain cylinder or frustum
## e == r1 == r2               -> both ends become hemispheres: EXACTLY a capsule
## r2 == 0, e == 0             -> a sharp-tipped cone
## r2 == 0, e > 0              -> a cone with a rounded nose
## [/codeblock]
## `e` is measured against the WIDER end, not the narrower one. Against the narrower end a cone
## could never be rounded at all - its narrow end is a point, so `min` is zero - and "a cone with
## a rounded nose" is one of the shapes this primitive exists to cover. Rounding past the narrow
## end is still well defined: `capped_cone` floors a negative radius at zero, so the shrunk solid
## becomes a sharp cone and inflating it back out puts a spherical cap on the tip, which is
## exactly the rounded nose. Push `e` all the way to the wide radius and any of these shapes
## converges on the capsule, continuously.
##
## The clamp therefore saturates rather than inverting: an over-large authored value lands on the
## capsule instead of turning the shape inside out.
static func rounded_cone(p: Vector3, r1: float, r2: float, half_h: float, e: float) -> float:
	var reach: float = maxf(maxf(r1, 0.0), maxf(r2, 0.0))
	var er: float = clampf(e, 0.0, minf(reach, maxf(half_h, 0.0)))
	if er <= 0.0:
		return capped_cone(p, r1, r2, half_h)
	return capped_cone(p, r1 - er, r2 - er, half_h - er) - er


## RETIRED(ADR 0005): cone() -> capped_cone(p, r, 0.0, half_h) (this file, just above).
## Kept because ResolvedShape.Base.CONE is pinned by API_CONTRACT section 6 and old documents
## may still name it; no family in data/shapes/families.json produces it any more.
## Cone with its apex at +half_h and a flat base of radius `r` at -half_h.
static func cone(p: Vector3, r: float, half_h: float) -> float:
	return capped_cone(p, r, 0.0, half_h)


## Capsule, axis +Y: a cylinder of radius `r` spanning [-half_h, +half_h] with hemispherical
## caps of the same radius on each end. Total height is 2 * (half_h + r).
static func capsule(p: Vector3, r: float, half_h: float) -> float:
	var h: float = maxf(half_h, 0.0)
	var q: Vector3 = Vector3(p.x, p.y - clampf(p.y, -h, h), p.z)
	return q.length() - r


## Torus: ring lying in the XZ plane, axis +Y. `major_r` is the ring radius, `minor_r` the tube.
static func torus(p: Vector3, major_r: float, minor_r: float) -> float:
	return Vector2(Vector2(p.x, p.z).length() - major_r, p.y).length() - minor_r
