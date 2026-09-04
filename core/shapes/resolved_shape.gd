class_name ResolvedShape
extends RefCounted

## One fully resolved part shape: a base primitive plus the fixed op stack from SPEC section 4,
## evaluated inside a per-axis scale.
##
## This is THE hot path. `sdf()` is called millions of times per bake, so it is a concrete
## method on a concrete class — no virtual dispatch, no interfaces, no Dictionary lookups, no
## temporaries. Every op stage early-outs when its amplitude is zero, and the scale warp
## early-outs when the scale is (1, 1, 1).
##
## Built by `ShapeGen.resolve()`; consumed by `ShipAttach`, `ShipSdf`, metrics and the bake.
## A `ResolvedShape` is a value: nothing mutates one after it is resolved.
##
## `size` is the family's UNSCALED base size. Its layout by base (this is the contract other
## code, including the preview mesh generator, reads):
## [codeblock]
## BOX                      -> (half_x, half_y, half_z)
## SPHERE                   -> (radius, radius, radius)
## CYLINDER                 -> (radius_at_-Y, half_height, unused)   see `radius_b`, `end_round`
## CONE                     -> (radius, half_height, radius)         RETIRED, see below
## CAPSULE                  -> (radius, half_height_of_the_cylindrical_span, radius)  RETIRED
## TORUS                    -> (major_radius, minor_radius, unused)
## [/codeblock]
##
## RETIRED(ADR 0005): Base.CONE and Base.CAPSULE -> Base.CYLINDER with `radius_b` / `end_round`.
## A cone is a cylinder whose two ends have different radii; a capsule is a cylinder whose ends
## are rounded all the way to hemispheres. Both were separate FAMILIES, which meant a player
## could not turn a cylinder into either one, could not un-round a capsule, and met three
## palette entries for one primitive. The enum values stay (API_CONTRACT section 6 pins them)
## and still evaluate, so an old document loads; nothing in `data/` produces them.
## `size.y` is therefore the local half-height for every base, which is what the taper and rib
## ops are parameterised against.
##
## The part's per-axis `scale` is applied as a domain warp in `sdf()`, NOT folded into `size`:
## `d = min_component(scale) * base_sdf(p / scale)`. That is exact for a uniform scale and a
## conservative distance bound (never an overestimate) for a non-uniform one, so a stretched
## sphere is a real ellipsoid rather than a bigger sphere. It is also why `lipschitz` carries
## the `max(scale) / min(scale)` term.

enum Base { BOX, SPHERE, CYLINDER, CONE, CAPSULE, TORUS }

## Base primitive, a `Base` enum value (stored as int so `match` stays a plain integer switch).
var base: int = Base.BOX
## UNSCALED primitive dimensions in metres — see the class docs for the per-base layout.
var size: Vector3 = Vector3.ONE
## CYLINDER only: radius of the +Y end, in unscaled local metres, where `size.x` is the -Y end.
## Equal to `size.x` for a true cylinder, smaller for a frustum, and 0.0 for a point-tipped cone.
##
## NEGATIVE MEANS "same as size.x". `refresh()` resolves it, so a shape hand-built without this
## field is still a plain cylinder rather than a silent cone — which is exactly what a default of
## 0.0 would have made every existing caller produce.
var radius_b: float = -1.0
## CYLINDER only: how far the two end DISCS are rounded off, in unscaled local metres. 0.0 leaves
## both ends flat. At `max(size.x, radius_b)` every shape in this family converges on the capsule.
## `refresh()` clamps it to what the solid can absorb.
##
## Distinct from `round_r`, which inflates the WHOLE surface outward and therefore also grows the
## part. Rounding an end keeps the part's overall extent — the reason a player can round a
## cylinder into a capsule without the part changing size under them.
var end_round: float = 0.0
## Per-axis scale from the part record. Must be positive and non-zero; `refresh()` enforces it.
var scale: Vector3 = Vector3.ONE
## Inflate radius, in unscaled local metres: the surface is pushed outward by this, rounding
## every edge.
var round_r: float = 0.0
## Taper amount, unitless. POSITIVE NARROWS the shape toward +Y (see `SdfOps.taper`).
var taper: float = 0.0
## Twist in degrees per metre of local Y.
var twist_deg: float = 0.0
## SHEAR, in metres of sideways travel per metre of local Y, measured from the part's centre
## (ADR 0007). `shear.x` leans the part toward +X as Y rises, `shear.y` toward +Z. Zero is the
## identity, which is why adding this op moved nothing.
var shear: Vector2 = Vector2.ZERO
## Number of rib rings stacked along local Y. 0 disables the op.
var rib_count: int = 0
## Rib displacement amplitude in unscaled local metres. 0.0 disables the op.
var rib_amp: float = 0.0
## Rib phase in radians. Seed-derived micro-detail — never player-set.
var rib_phase: float = 0.0
## Scallop displacement amplitude in unscaled local metres. 0.0 disables the op.
var scallop_amp: float = 0.0
## Scallop spatial frequency in radians per unscaled metre.
var scallop_freq: float = 0.0
## Scallop phase in radians. Seed-derived micro-detail — never player-set.
var scallop_phase: float = 0.0
## Lipschitz divisor (>= 1.0). The sphere-tracer must step `abs(sdf()) / lipschitz` or the
## domain warps will let it overshoot and tunnel through the surface.
var lipschitz: float = 1.0
## True when the local origin is inside the solid, so ShipAttach can march outward from it.
## False (torus, and anything hollow at its centre) makes ShipAttach march inward from
## `bound_radius` and take the first crossing instead.
var origin_inside: bool = true
## Radius of a sphere about the local origin that fully contains the SCALED shape.
var bound_radius: float = 1.0


## Signed distance to this shape, in SHAPE-LOCAL space. Negative inside.
##
## The op order below is SPEC section 4 and it IS the ruleset: taper, twist, shear, base,
## inflate, ribs, scallops. New ops append to the END, never insert - EXCEPT a domain warp, which
## cannot be appended because everything after the base operates on a distance rather than on a
## point. Shear therefore sits last of the three warps (ADR 0007), and at its default of zero it
## is the identity, so nothing that predates it moved. Reordering is a ruleset bump.
## The scale warp wraps the whole stack, so every op is authored in unscaled units.
func sdf(p: Vector3) -> float:
	var pw: Vector3 = p
	var out_k: float = 1.0
	var s: Vector3 = self.scale
	if s.x != 1.0 or s.y != 1.0 or s.z != 1.0:
		pw = Vector3(p.x / s.x, p.y / s.y, p.z / s.z)
		out_k = minf(s.x, minf(s.y, s.z))
	var half_h: float = self.size.y
	if self.taper != 0.0:
		pw = SdfOps.taper(pw, self.taper, half_h)
	if self.twist_deg != 0.0:
		pw = SdfOps.twist(pw, self.twist_deg)
	if self.shear != Vector2.ZERO:
		pw = SdfOps.shear(pw, self.shear.x, self.shear.y)
	var d: float = 0.0
	match self.base:
		Base.BOX:
			d = SdfPrims.box(pw, self.size)
		Base.SPHERE:
			d = SdfPrims.sphere(pw, self.size.x)
		Base.CYLINDER:
			d = SdfPrims.rounded_cone(
				pw, self.size.x, self.radius_b, self.size.y, self.end_round
			)
		Base.CONE:
			d = SdfPrims.cone(pw, self.size.x, self.size.y)
		Base.CAPSULE:
			d = SdfPrims.capsule(pw, self.size.x, self.size.y)
		Base.TORUS:
			d = SdfPrims.torus(pw, self.size.x, self.size.y)
		_:
			d = SdfPrims.box(pw, self.size)
	if self.round_r != 0.0:
		d = SdfOps.inflate(d, self.round_r)
	if self.rib_count > 0 and self.rib_amp != 0.0:
		d += SdfOps.rib_disp(pw, self.rib_count, self.rib_amp, self.rib_phase, half_h)
	if self.scallop_amp != 0.0:
		d += SdfOps.scallop_disp(pw, self.scallop_amp, self.scallop_freq, self.scallop_phase)
	return d * out_k


## Conservative axis-aligned bounds of the SCALED shape in local space, centred on the origin.
func local_aabb() -> AABB:
	var ex: Vector3 = _warped_half_extents()
	ex = Vector3(ex.x * absf(self.scale.x), ex.y * absf(self.scale.y), ex.z * absf(self.scale.z))
	return AABB(-ex, ex * 2.0)


## The same bounds before the per-axis scale — the frame the ops are authored in. `ShapeGen`
## uses this to size the twist and taper Lipschitz terms; a preview mesh generator that applies
## `scale` as a node transform wants this one too.
func unscaled_aabb() -> AABB:
	var ex: Vector3 = _warped_half_extents()
	return AABB(-ex, ex * 2.0)


## Distance from the local origin to the attach face along local -Y, so that an `offset` of 0
## puts that face flush on the parent surface (SPEC section 3 step 6).
## Includes the inflate radius and the Y scale; ignores the rib and scallop displacements,
## which average to zero and would otherwise float every child off its parent by their
## amplitude.
func mount_inset() -> float:
	var h: float = 0.0
	match self.base:
		Base.SPHERE:
			h = absf(self.size.x)
		Base.CAPSULE:
			h = absf(self.size.y) + absf(self.size.x)
		_:
			h = absf(self.size.y)
	return maxf((h + self.round_r) * absf(self.scale.y), 0.0)


## A copy with the two DISPLACEMENT ops zeroed - ribs and scallops - and everything else intact.
##
## Used to measure how far a part reaches in a given direction (ShipAttach.support_inset). Ribs
## and scallops average to zero about the base surface, so measuring against a rib CREST would
## float every ribbed child off its parent by the rib amplitude - the same reasoning
## [method mount_inset] already documents for ignoring them. Measuring the smooth base surface
## seats the part on its mean surface, and the crests and troughs straddle the contact.
func smooth_copy() -> ResolvedShape:
	var out: ResolvedShape = ResolvedShape.new()
	out.base = self.base
	out.size = self.size
	out.radius_b = self.radius_b
	out.end_round = self.end_round
	out.scale = self.scale
	out.round_r = self.round_r
	out.taper = self.taper
	out.twist_deg = self.twist_deg
	out.shear = self.shear
	out.rib_count = 0
	out.rib_amp = 0.0
	out.rib_phase = self.rib_phase
	out.scallop_amp = 0.0
	out.scallop_freq = self.scallop_freq
	out.scallop_phase = self.scallop_phase
	out.origin_inside = self.origin_inside
	out.refresh()
	return out


## Sanitises `scale` (positive and non-zero — `sdf()` divides by it) and recomputes the derived
## cache (`bound_radius`) from the authored fields. `ShapeGen.resolve()` calls this; anything
## that hand-builds a shape should call it too.
func refresh() -> void:
	self.scale = Vector3(
		maxf(absf(self.scale.x), SdfOps.MIN_SCALE),
		maxf(absf(self.scale.y), SdfOps.MIN_SCALE),
		maxf(absf(self.scale.z), SdfOps.MIN_SCALE)
	)
	# A negative radius_b means "match size.x" — see the field docs. Resolved here, before
	# local_aabb() reads it, so the bound and the sdf() never disagree about the shape's width.
	if self.radius_b < 0.0:
		self.radius_b = absf(self.size.x)
	# The WIDER end sets how far an end can be rounded - see SdfPrims.rounded_cone. Measuring it
	# against the narrower end left a cone (narrow end = a point) unable to be rounded at all.
	self.end_round = clampf(
		self.end_round,
		0.0,
		minf(maxf(absf(self.size.x), self.radius_b), absf(self.size.y))
	)
	var b: AABB = local_aabb()
	self.bound_radius = maxf(b.position.length(), b.end.length())


## Half-extents in the unscaled op frame. Deliberately an overestimate: a negative taper flares
## the XZ domain, twist sweeps the XZ extents out to their circumradius, and inflate plus the
## displacements pad every axis. A bound that is too tight would clip real geometry out of the
## bake, and would start a torus trace inside its own solid.
func _warped_half_extents() -> Vector3:
	var ex: Vector3 = _base_half_extents()
	if self.taper < 0.0:
		# Positive taper only narrows the +Y end, so it never grows these bounds.
		var flare: float = 1.0 - self.taper
		ex = Vector3(ex.x * flare, ex.y, ex.z * flare)
	if self.twist_deg != 0.0:
		var radial: float = Vector2(ex.x, ex.z).length()
		ex = Vector3(radial, ex.y, radial)
	if self.shear != Vector2.ZERO:
		# A shear moves the ends sideways by k * half_h each way, so the bound has to grow by
		# that much on X and Z. Missed, this clips the leaning end straight out of the bake.
		ex += Vector3(absf(self.shear.x) * ex.y, 0.0, absf(self.shear.y) * ex.y)
	var pad: float = absf(self.round_r) + absf(self.rib_amp) + absf(self.scallop_amp)
	return ex + Vector3(pad, pad, pad)


## Half-extents of the bare primitive, before any op widening and before scale.
func _base_half_extents() -> Vector3:
	match self.base:
		Base.SPHERE:
			var r: float = absf(self.size.x)
			return Vector3(r, r, r)
		Base.CYLINDER:
			# The wider END governs: a frustum is as wide as its fat end, and end rounding
			# never reaches outside the straight sides it was cut from.
			var wide: float = maxf(absf(self.size.x), maxf(self.radius_b, 0.0))
			return Vector3(wide, absf(self.size.y), wide)
		Base.CONE:
			return Vector3(absf(self.size.x), absf(self.size.y), absf(self.size.x))
		Base.CAPSULE:
			var cr: float = absf(self.size.x)
			return Vector3(cr, absf(self.size.y) + cr, cr)
		Base.TORUS:
			var outer: float = absf(self.size.x) + absf(self.size.y)
			return Vector3(outer, absf(self.size.y), outer)
	return self.size.abs()
