class_name SnapTargets
extends RefCounted

## Typed snap targets derived from a resolved SDF shape — API_CONTRACT_SPORE section 1.
##
## Spore never places a part at the raw cursor. A drop is pulled to a TYPED target: the parent's
## centre (`SnapToParentCenter`), an authored snap vector on the parent mesh (a model bone
## literally named `csnap`, `mCSnapBoneIndex`), or the editor centreline (`SnapToCenterOfEditor`).
## See SPORE_CLONE_SPEC section 3 step 4 and section 1. Spore authors those points by hand into
## hundreds of meshes; we have six procedural SDF families instead, so we DERIVE the equivalent
## set from each family's own geometry and get the mechanic without a mesh catalog.
##
## A target is a Dictionary with EXACTLY these four keys, and nothing else:
## [codeblock]
## "id":        String   # stable within a family; IMMUTABLE once shipped - it is stored in the doc
## "local_pos": Vector3  # on the UNSCALED shape surface, in shape-local space
## "normal":    Vector3  # unit, outward - the mount axis a snapped child stands on
## "kind":      String   # "face" | "pole" | "rim" | "center"
## [/codeblock]
##
## DETERMINISM IS THE CONTRACT. `for_shape()` returns the same array, in the same order, for the
## same shape, every time. The ids ARE that order, and saved documents refer to them by id, so:
## a new target for an existing family appends to the END of that family's block, and an existing
## id is never renamed, never moved, and never repointed at different geometry.
##
## THE TWO FRAMES — stated explicitly, because an unstated value shape is precisely the silent
## cross-module bug FOLLOWUPS F0 was written about:
##
## - `for_shape()` works in the UNSCALED shape frame: the frame the SPEC section 4 op stack is
##   authored in. The part's per-axis `scale` is deliberately NOT applied, so the array depends
##   only on the shape's geometry and never on how big the player made it.
## - `apply_scale()` maps one target into the SCALED local frame — the frame `ResolvedShape.sdf()`
##   and `ShipAttach.trace_surface()` speak, and the only frame in which distances are true metres.
##   Positions scale componentwise; normals take the inverse-transpose (divide, then renormalise),
##   because a stretched surface's normal does not stretch with it.
## - `nearest()` takes its query point in the SCALED frame — its `tolerance` is in metres, and a
##   picked surface point comes from `ShipAttach.trace_surface()`, which is scaled — and returns
##   the UNSCALED target, so the caller can store `id` and hand the dictionary straight to
##   `ShipAttach.snap_transform()`.
##
## POSITIONS ARE ON THE REAL SURFACE, not on the bare primitive. Each target starts from an
## analytic seed on the base primitive and is then pulled onto the resolved surface by a damped
## Newton projection (`_project_to_surface`), so inflate, taper, twist, ribs and scallops all move
## their snap points with them. A seed that is already exact — an unwarped box face, a torus ring —
## is left bit-for-bit where it is, because the projection early-outs on `SURFACE_EPS` before it
## takes its first step.
##
## NORMALS COME FROM THE FIELD, not from the axis the seed was built on: `ShipAttach.gradient()` at
## the projected point. A tapered box's `face_+x` therefore tilts with the taper and a twisted
## cylinder's `rim_3` rotates with the twist, instead of confidently reporting a normal the shape
## does not have. The one hardcoded normal is `center`, which sits at the origin where there is no
## surface and the gradient is degenerate by construction.
##
## `core/` purity: static only, no state, no engine objects beyond the value types. The calls into
## `ShipAttach` are all inside FUNCTION BODIES and never in a signature, a const or a default
## argument — `ShipAttach` calls back into this class, and body-only references are the form of
## mutual `class_name` reference that resolves cleanly (compare `ShapeGen.RULESET_VERSION`, which
## exists to avoid exactly this hazard at const level).

## Rim points around the widest circumference of a cylinder, cone or capsule, and around a torus's
## major ring. FIXED AT 8 by API_CONTRACT_SPORE section 1: the count generates the ids.
const RIM_SEGMENTS: int = 8

## Two of a cylinder's end radii closer than this are the SAME radius, so its rim stays at
## mid-height (ADR 0005). Well under the 0.01 m finest feature the spec cares about, and well
## above single-precision noise in a ratio multiply - without it, noise in an authored 1.0 could
## flip a rim from the middle of a tube to its bottom edge and move every part snapped there.
const RIM_TIE_EPS: float = 1.0e-5

## Central-difference step handed to `ShipAttach.gradient()`. Mirrors `ShipConfig.gradient_eps`'s
## default; `for_shape()` takes no config by contract, so the value is pinned here instead.
const GRADIENT_EPS: float = 1.0e-4

## A seed nearer the surface than this is already on it and is returned untouched, so an exact
## analytic point stays exact rather than picking up projection noise.
const SURFACE_EPS: float = 1.0e-9

## Damped-Newton projections used to pull an analytic seed onto the real, op-warped surface.
## One step is exact for a true distance field; the rest absorb the warped field's Lipschitz error.
# 6 was not enough. The step is damped by the shape's Lipschitz bound, which is right for
# sphere-tracing TOWARD a surface (it prevents overshoot) but merely slows a Newton
# PROJECTION onto one: with k > 1 each iteration closes only d/k of the gap. On torus_ring —
# the highest-curvature family — 6 steps left the rim targets 1.8 mm off the surface against
# a 1 mm tolerance. This runs once per shape and the result is cached, so the extra
# iterations are free; the SURFACE_EPS early-out means well-conditioned shapes still exit
# after one or two.
const SURFACE_STEPS: int = 24

## Anything shorter than this is treated as a zero vector.
const MIN_LENGTH_SQ: float = 1e-20

## Floor for a scale component in `apply_scale()`, so a zeroed scale cannot divide by zero.
const MIN_SCALE: float = 1.0e-6

## Mount axis of the `center` target. The origin has no surface, so there is no gradient to read;
## +Y matches `ShipAttach.gradient()`'s own degenerate fallback and stands a snapped child upright.
const CENTER_NORMAL: Vector3 = Vector3.UP

const KIND_FACE: String = "face"
const KIND_POLE: String = "pole"
const KIND_RIM: String = "rim"
const KIND_CENTER: String = "center"

## The one id every family carries — Spore's `SnapToParentCenter`.
const ID_CENTER: String = "center"


## Snap targets for a resolved shape, in shape-local space, UNSCALED.
##
## Deterministic: same shape in, same array out, same order. Order is part of the contract
## because ids are generated from it. `center` is always element 0; the family block follows.
##
## [codeblock]
## BOX      center, face_+x, face_-x, face_+y, face_-y, face_+z, face_-z,
##          corner_+x+y+z, corner_+x+y-z, corner_+x-y+z, corner_+x-y-z,
##          corner_-x+y+z, corner_-x+y-z, corner_-x-y+z, corner_-x-y-z      (15)
## SPHERE   center, pole_+x, pole_-x, pole_+y, pole_-y, pole_+z, pole_-z    (7)
## CYLINDER center, pole_+y, pole_-y, rim_0 .. rim_7                        (11)
## CONE     center, pole_+y (apex), pole_-y (base centre), rim_0 .. rim_7   (11)
## CAPSULE  center, pole_+y, pole_-y, rim_0 .. rim_7                        (11)
## TORUS    center, rim_0 .. rim_7                                          (9)
## [/codeblock]
##
## The rim ring sits on the WIDEST circumference: mid-height for a cylinder whose two ends match
## and for a capsule, where every height is equally wide, and the fat end for a frustum or a cone,
## which is the only place it is (ADR 0005 - a CYLINDER can now be any of those).
## Rim `i` starts at local +X and sweeps toward +Z, `TAU * i / RIM_SEGMENTS`.
static func for_shape(shape: ResolvedShape) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if shape == null:
		return out
	# The op stack is authored unscaled, so the field is sampled unscaled too. Without this the
	# whole array would move with the player's scale and every stored id would mean something new.
	var field: ResolvedShape = _unscaled_twin(shape)
	var half: Vector3 = shape.size.abs()
	out.append(_target(ID_CENTER, Vector3.ZERO, CENTER_NORMAL, KIND_CENTER))
	match shape.base:
		ResolvedShape.Base.BOX:
			_append_box(out, field, half)
		ResolvedShape.Base.SPHERE:
			_append_sphere(out, field, half.x)
		ResolvedShape.Base.CYLINDER:
			# ADR 0005: the two ends may differ, so the widest circumference is no longer always
			# at mid-height. It is the fat END for a frustum, and mid-height only when the ends
			# match - which is what the class docs have always promised a rim means.
			_append_axial(out, field, half.y, _rim_radius(shape), _rim_height(shape))
		ResolvedShape.Base.CONE:
			# Apex at +size.y, base disc at -size.y (SdfPrims.cone), so the widest ring is the base.
			_append_axial(out, field, half.y, half.x, -half.y)
		ResolvedShape.Base.CAPSULE:
			# size.y is the cylindrical span only; the hemispherical cap adds the radius on top.
			_append_axial(out, field, half.y + half.x, half.x, 0.0)
		ResolvedShape.Base.TORUS:
			_append_ring(out, field, half.x + half.y, 0.0)
		_:
			# Unknown base resolves as a box, exactly as ResolvedShape.sdf() does.
			_append_box(out, field, half)
	return out


## Nearest target to a shape-local point, or {} when none is within `tolerance` metres.
##
## `local_point` is in the SCALED local frame — the frame `ShipAttach.trace_surface()` returns and
## the only one where `tolerance` is metres — but the returned target is the UNSCALED one, ready
## for `ShipAttach.snap_transform()`. Ties go to the earlier target in `for_shape()` order, so the
## result is deterministic even when two points are equidistant.
static func nearest(shape: ResolvedShape, local_point: Vector3, tolerance: float) -> Dictionary:
	if shape == null:
		return {}
	var limit_sq: float = absf(tolerance) * absf(tolerance)
	var best: Dictionary = {}
	var best_sq: float = INF
	for target: Dictionary in for_shape(shape):
		var scaled: Dictionary = apply_scale(target, shape.scale)
		var pos: Vector3 = scaled["local_pos"]
		var d_sq: float = pos.distance_squared_to(local_point)
		if d_sq > limit_sq:
			continue
		if d_sq < best_sq:
			best_sq = d_sq
			best = target
	return best


## Scale a target's local_pos/normal into the part's scaled local frame.
##
## Positions scale componentwise. Normals take the inverse-transpose — divide by the scale, then
## renormalise — because stretching a surface tilts its normal the opposite way to its tangents.
## Returns a NEW dictionary; the argument is never touched.
static func apply_scale(target: Dictionary, scale: Vector3) -> Dictionary:
	if target.is_empty():
		return {}
	var s: Vector3 = Vector3(
		maxf(absf(scale.x), MIN_SCALE),
		maxf(absf(scale.y), MIN_SCALE),
		maxf(absf(scale.z), MIN_SCALE)
	)
	var id: String = target.get("id", "")
	var kind: String = target.get("kind", "")
	var pos: Vector3 = target.get("local_pos", Vector3.ZERO)
	var normal: Vector3 = target.get("normal", CENTER_NORMAL)
	var warped: Vector3 = Vector3(normal.x / s.x, normal.y / s.y, normal.z / s.z)
	if warped.length_squared() < MIN_LENGTH_SQ:
		warped = CENTER_NORMAL
	return _target(id, Vector3(pos.x * s.x, pos.y * s.y, pos.z * s.z), warped.normalized(), kind)


# --- private -------------------------------------------------------------------------------


# The four contract keys, in one place, so no caller can invent a fifth or misspell one.
# `normal` is normalised here rather than at every call site.
static func _target(id: String, pos: Vector3, normal: Vector3, kind: String) -> Dictionary:
	var n: Vector3 = normal
	if n.length_squared() < MIN_LENGTH_SQ:
		n = CENTER_NORMAL
	return {"id": id, "local_pos": pos, "normal": n.normalized(), "kind": kind}


# 6 face centres then 8 corners. A corner is filed as "pole" and not as "face": it is an extremal
# point of the solid exactly like a sphere pole or a cylinder cap, and the contract's four kinds
# have no "corner" of their own, so a family that wants flat faces only can ask for `face` and get
# the six it meant. The `corner_` id prefix keeps them unambiguous regardless.
static func _append_box(out: Array[Dictionary], field: ResolvedShape, half: Vector3) -> void:
	out.append(_resolved(field, "face_+x", Vector3(half.x, 0.0, 0.0), KIND_FACE))
	out.append(_resolved(field, "face_-x", Vector3(-half.x, 0.0, 0.0), KIND_FACE))
	out.append(_resolved(field, "face_+y", Vector3(0.0, half.y, 0.0), KIND_FACE))
	out.append(_resolved(field, "face_-y", Vector3(0.0, -half.y, 0.0), KIND_FACE))
	out.append(_resolved(field, "face_+z", Vector3(0.0, 0.0, half.z), KIND_FACE))
	out.append(_resolved(field, "face_-z", Vector3(0.0, 0.0, -half.z), KIND_FACE))
	var signs: PackedFloat32Array = PackedFloat32Array([1.0, -1.0])
	for sx: float in signs:
		for sy: float in signs:
			for sz: float in signs:
				var id: String = (
					"corner_%sx%sy%sz" % [_sign_tag(sx), _sign_tag(sy), _sign_tag(sz)]
				)
				var seed: Vector3 = Vector3(sx * half.x, sy * half.y, sz * half.z)
				out.append(_resolved(field, id, seed, KIND_POLE))


# The six axis poles of a sphere, +x -x +y -y +z -z.
static func _append_sphere(out: Array[Dictionary], field: ResolvedShape, r: float) -> void:
	out.append(_resolved(field, "pole_+x", Vector3(r, 0.0, 0.0), KIND_POLE))
	out.append(_resolved(field, "pole_-x", Vector3(-r, 0.0, 0.0), KIND_POLE))
	out.append(_resolved(field, "pole_+y", Vector3(0.0, r, 0.0), KIND_POLE))
	out.append(_resolved(field, "pole_-y", Vector3(0.0, -r, 0.0), KIND_POLE))
	out.append(_resolved(field, "pole_+z", Vector3(0.0, 0.0, r), KIND_POLE))
	out.append(_resolved(field, "pole_-z", Vector3(0.0, 0.0, -r), KIND_POLE))


# Two end poles on the local Y axis, then the rim ring. Every Y-axis primitive shares this shape;
# only where the widest circumference sits differs, which is why `rim_y` is a parameter.
## Widest radius a CYLINDER reaches, over both of its ends (ADR 0005).
static func _rim_radius(shape: ResolvedShape) -> float:
	return maxf(absf(shape.size.x), maxf(shape.radius_b, 0.0))


## Local Y of that widest circumference: the fat end of a frustum, or mid-height when the two ends
## match within RIM_TIE_EPS.
static func _rim_height(shape: ResolvedShape) -> float:
	var r1: float = absf(shape.size.x)
	var r2: float = maxf(shape.radius_b, 0.0)
	if absf(r1 - r2) <= RIM_TIE_EPS:
		return 0.0
	return -absf(shape.size.y) if r1 > r2 else absf(shape.size.y)


static func _append_axial(
	out: Array[Dictionary], field: ResolvedShape, pole_h: float, rim_r: float, rim_y: float
) -> void:
	out.append(_resolved(field, "pole_+y", Vector3(0.0, pole_h, 0.0), KIND_POLE))
	out.append(_resolved(field, "pole_-y", Vector3(0.0, -pole_h, 0.0), KIND_POLE))
	_append_ring(out, field, rim_r, rim_y)


# `RIM_SEGMENTS` points on the circle of radius `radius` at height `y`, starting at local +X and
# sweeping toward +Z. Ids are rim_0 .. rim_7 and the count is frozen, so the angles are frozen too.
static func _append_ring(
	out: Array[Dictionary], field: ResolvedShape, radius: float, y: float
) -> void:
	for i: int in RIM_SEGMENTS:
		var angle: float = TAU * float(i) / float(RIM_SEGMENTS)
		var seed: Vector3 = Vector3(radius * cos(angle), y, radius * sin(angle))
		out.append(_resolved(field, "rim_%d" % i, seed, KIND_RIM))


# Seed -> real surface -> field normal. The whole per-target pipeline, in one place.
static func _resolved(
	field: ResolvedShape, id: String, seed: Vector3, kind: String
) -> Dictionary:
	var pos: Vector3 = _project_to_surface(field, seed)
	var normal: Vector3 = ShipAttach.gradient(field, pos, GRADIENT_EPS)
	return _target(id, pos, normal, kind)


# Damped Newton onto the zero level set. For a true distance field `p - sdf(p) * grad` lands on the
# surface in one step; the resolved field is only a BOUND once taper or twist warp the domain, so
# the step is divided by the same Lipschitz constant the sphere-tracer uses and repeated. The
# early-out fires before the first step for a seed that is already exact, which is what keeps an
# unwarped box face at exactly (half.x, 0, 0) instead of one epsilon off it.
static func _project_to_surface(field: ResolvedShape, seed: Vector3) -> Vector3:
	var p: Vector3 = seed
	var k: float = maxf(field.lipschitz, 1.0)
	for i: int in SURFACE_STEPS:
		var d: float = field.sdf(p)
		if not is_finite(d) or absf(d) < SURFACE_EPS:
			return p
		var g: Vector3 = ShipAttach.gradient(field, p, GRADIENT_EPS)
		p -= g * (d / k)
	return p


# A copy of `shape` with the per-axis scale removed, so the field can be sampled in the frame the
# ops were authored in. Never mutates the argument. `lipschitz` is carried over rather than
# recomputed: `ShapeGen` folds the scale ratio into it, so the inherited value is an overestimate
# for the unscaled twin, and an overestimate only damps the projection step - it is never unsafe.
static func _unscaled_twin(shape: ResolvedShape) -> ResolvedShape:
	var out: ResolvedShape = ResolvedShape.new()
	out.base = shape.base
	out.size = shape.size
	# ADR 0005: without these two the twin resolves radius_b to size.x and every snap point on a
	# cone would be projected onto the surface of the CYLINDER it is not.
	out.radius_b = shape.radius_b
	out.end_round = shape.end_round
	out.round_r = shape.round_r
	out.taper = shape.taper
	out.twist_deg = shape.twist_deg
	out.rib_count = shape.rib_count
	out.rib_amp = shape.rib_amp
	out.rib_phase = shape.rib_phase
	out.scallop_amp = shape.scallop_amp
	out.scallop_freq = shape.scallop_freq
	out.scallop_phase = shape.scallop_phase
	out.lipschitz = shape.lipschitz
	out.origin_inside = shape.origin_inside
	out.scale = Vector3.ONE
	out.refresh()
	return out


# Zero counts as positive so a degenerate half-extent still produces the full, stable id set.
static func _sign_tag(v: float) -> String:
	return "-" if v < 0.0 else "+"
