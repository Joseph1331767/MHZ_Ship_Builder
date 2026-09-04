class_name ShipAttach
extends RefCounted

## The attach model — SPEC section 3, API_CONTRACT section 12. Static only, no state.
##
## Every non-root part stores (yaw, pitch, rot, offset) plus a parent id, where `rot` is a
## Vector3 of degrees. This file is the only place that turns those numbers into a Transform3D,
## and it does it in the exact order SPEC 3 prescribes:
##
##   1. direction from (yaw, pitch) in parent-local space
##   2. sphere-trace that direction against the parent's resolved SDF -> anchor P
##   3. N = normalised SDF gradient at P (the mount axis)
##   4. reference tangent = parent-local -Z projected onto the tangent plane at P
##   5. mount frame F = Basis(tangent x N, tangent, N), i.e. +Z = N, and the child basis is
##      F * Rz(rot.z) * Ry(rot.y) * Rx(rot.x + MOUNT_ALIGN_DEG)
##   6. child origin = P + N * (offset + child support inset along -N)
##
## THE MOUNT FRAME'S +Z IS THE PLACEMENT NORMAL (ADR 0004). That is the author's stated
## convention and it is what makes `rot.z` the dial that spins a part on the surface. The part's
## own GEOMETRY still stands up along its +Y, because every family is authored Y-major
## (API_CONTRACT section 6: cone apex +Y, cylinder/capsule along Y, torus axis +Y) - pinning the
## child's geometric +Z to the normal would lay every cone and spar flat against the plating.
## MOUNT_ALIGN_DEG is the fixed term that reconciles the two, and at rot == (0, 0, roll) the
## result is bit-for-bit the pre-ADR-0004 transform.
##
## Angles are DEGREES at every boundary in this file. Radians exist only inside a function body.
## Distances are metres. Godot is Y-up, so yaw = 0, pitch = 0 points at parent-local +Z.
##
## THE SECOND PATH — SNAPPED ATTACHMENT (API_CONTRACT_SPORE sections 1-2, SPORE_CLONE_SPEC
## section 3 step 4). Spore never drops a part at the raw cursor: the drop is pulled to a TYPED
## target on the parent and the orientation is recomputed there. A part carrying a non-empty
## [member ShipPart.snap_id] therefore skips steps 1-3 entirely — there is nothing to ray-trace,
## because [SnapTargets] already knows the anchor and the outward normal — and enters at step 4
## through [method snap_transform]. Steps 4-6 are IDENTICAL for both paths, which is the point:
## a snapped child and a free child stand on their parent in exactly the same way, and only how
## the anchor was chosen differs.
##
## BOTH PATHS STAY LIVE. [member ShipPart.snap_id] == "" is the free-surface path this file was
## built around and is still what a typed yaw/pitch produces (SPEC section 3 is not retired).
## The router is [method local_transform], so every caller — [method resolve_all],
## [method resolve_all_from_shapes], the metrics pass, the baker — gets the right path for free
## and no caller needs to know which one it took.
##
## A SNAPPED PART STILL STORES yaw/pitch. They are DERIVED from the target by
## [method angles_for_target] rather than authored, and they are what the free path falls back to
## when a stored snap id is not found on the parent — which happens when a family is retuned so a
## target no longer exists, or when a snapped child is re-parented onto a family with a different
## target set. Falling back leaves the part near where it was instead of dropping it to the
## parent's nose, and it is why the derived angles are worth storing at all.

## Sphere-trace steps are divided by this at minimum. Taper and twist make a resolved field a
## *bound* rather than a true distance; an undivided step tunnels straight through the surface.
const MIN_LIPSCHITZ: float = 1.0

## |N dot -Z| above this counts as the pole where the -Z tangent reference degenerates (SPEC 3.4).
const POLE_DOT: float = 0.999

## Anything shorter than this is treated as a zero vector.
const MIN_LENGTH_SQ: float = 1e-20

## Floor for cfg.trace_epsilon, so a zeroed config cannot spin the tracer.
const MIN_TRACE_EPSILON: float = 1e-6

## Gradient step used only when a caller hands mount_basis() a degenerate normal.
const FALLBACK_GRADIENT_EPS: float = 0.001

## How close a traced point must be to the surface to count as a hit rather than a run-off. Loose
## on purpose: a warped field (taper, twist) is a distance BOUND, not a true distance, so an exact
## zero is not available and a tight epsilon would reject good contacts.
const SUPPORT_HIT_EPSILON: float = 0.05

## Fixed rotation about the mount frame's +X that stands a part's own +Y up along the frame's +Z.
## See the class docstring and ADR 0004: it is what lets the ROTATION frame be normal-aligned
## without laying the Y-major primitives on their sides. It commutes with rot.x (same axis), so it
## is folded into that term rather than multiplied separately.
const MOUNT_ALIGN_DEG: float = 90.0

## Below this |sin(a)| an aim direction handed to [method rot_xy_for_direction] is parallel to the
## child's own +Y and the spin about it is undetermined. A sine, not an angle, which is why it is
## 1e-6 rather than a degree count.
const MOUNT_AIM_EPSILON: float = 1.0e-6

## How far past the bounding radius an outward trace may march before giving up.
const TRACE_RANGE_SLACK: float = 1.5

## Bisection refinement steps used when a trace steps over a thin feature.
const BISECT_STEPS: int = 24

const KIND_COMPONENT_INSTANCE: String = "component_instance"

## default_offset(): the sole sample grid per footprint axis, the march steps up each column,
## the bisection steps refining each column's entry, and the bisection steps on the offset.
## 7 x 7 columns put one on the axis and one at each footprint edge, which is where a sphere's
## pole and a ring's rim are; 14 offset steps on a bracket of a few metres is under a millimetre.
## EMBED_GAIN is the share a rung must deepen the contact by to count as progress: a wide face
## pushed through a ring's tube reads the same depth for a metre, give or take the sole grid's
## pitch, and a tenth is above that noise while a genuine graze still gains it.
const EMBED_SOLE_GRID: int = 7
const EMBED_SOLE_STEPS: int = 16
const EMBED_SOLE_REFINE: int = 6
const EMBED_BISECT_STEPS: int = 14
const EMBED_GAIN: float = 0.1
## A parent scaled unevenly - every template tunnel - reads its SDF as a bound, short of the
## true distance by up to its min/max scale, and a room on a 1 m tube reads 0.375 m deep with
## its sole 0.45 m down the bore. The deepest sole points are re-measured on such a parent as
## the exit distance along the mount normal and along the field's gradient: this many marches
## of the bound (each safe, the bound never overshoots) then this many bisections.
const EMBED_EXIT_STEPS: int = 24
const EMBED_EXIT_REFINE: int = 8


## SPEC 3 step 1. Degrees in, unit direction in the parent's local frame out.
static func direction_from_angles(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw: float = deg_to_rad(yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	var cos_pitch: float = cos(pitch)
	var d: Vector3 = Vector3(cos_pitch * sin(yaw), sin(pitch), cos_pitch * cos(yaw))
	if d.length_squared() < MIN_LENGTH_SQ:
		return Vector3.BACK
	return d.normalized()


## The exact inverse of direction_from_angles(). Returns (yaw_deg, pitch_deg); yaw is normalised
## into [-180, 180) and pitch into [-90, 90]. At the poles yaw is undefined and comes back 0.
static func angles_from_direction(dir: Vector3) -> Vector2:
	if dir.length_squared() < MIN_LENGTH_SQ:
		return Vector2.ZERO
	var d: Vector3 = dir.normalized()
	var pitch_deg: float = rad_to_deg(asin(clampf(d.y, -1.0, 1.0)))
	var yaw_deg: float = rad_to_deg(atan2(d.x, d.z))
	return Vector2(wrap_yaw_deg(yaw_deg), clampf(pitch_deg, -90.0, 90.0))


## Normalise any angle in degrees into the stored yaw range [-180, 180).
static func wrap_yaw_deg(deg: float) -> float:
	return fposmod(deg + 180.0, 360.0) - 180.0


## SPEC 3 step 2. Returns the anchor P in SHAPE-LOCAL space. See trace_surface_hit() when the
## caller needs to know whether the ray actually found a surface.
## The (rot.x, rot.y) that aims a child part's own +Y along `target`, given in MOUNT-FRAME
## coordinates, while leaving `rot_z` - the player's spin on the surface - exactly where it is.
##
## This is what numpad 0 drives: "0 toggles z reference from placement vector to surface normal
## vector and snaps the part to the surface normal." The mount frame's +Z IS the surface normal
## (ADR 0004), so the normal is (0, 0, 1) here and a part standing square on its parent is
## rot == (0, 0, z). The PLACEMENT VECTOR - the ray from the parent's centre out through the
## anchor - is a different direction on anything that is not a sphere, and aiming at it is the
## other half of the toggle.
##
## Derivation, so the arithmetic below is checkable rather than magic. The child basis is
## `F * Rz(z) * Ry(y) * Rx(x + 90)`, so its own +Y in mount coordinates is
## [codeblock]
## Rz(z) * Ry(y) * Rx(a) * (0, 1, 0),  a = x + 90
##   = Rz(z) * (sin(y)sin(a), cos(a), cos(y)sin(a))
## [/codeblock]
## Undo the spin - (p, q) = Rz(-z) applied to (target.x, target.y) - and the three components read
## straight off: `cos(a) = q`, `sin(y)sin(a) = p`, `cos(y)sin(a) = target.z`. Hence
## `a = acos(q)` (taking sin(a) >= 0, which keeps x in the half-turn a player can reach with the
## rings) and `y = atan2(p, target.z)`.
##
## A target parallel to the child's own +Y leaves `y` undetermined - every spin about it is the
## same aim - so it is held at its current value instead of jumping to an arbitrary one.
static func rot_xy_for_direction(target: Vector3, rot_z: float, rot_y_now: float) -> Vector2:
	var d: Vector3 = target
	if d.length_squared() < MIN_LENGTH_SQ:
		return Vector2(0.0, rot_y_now)
	d = d.normalized()
	var z: float = deg_to_rad(rot_z)
	var cz: float = cos(z)
	var sz: float = sin(z)
	# Rz(-z) applied to (d.x, d.y).
	var p: float = d.x * cz + d.y * sz
	var q: float = -d.x * sz + d.y * cz
	var a: float = acos(clampf(q, -1.0, 1.0))
	if sin(a) <= MOUNT_AIM_EPSILON:
		return Vector2(rad_to_deg(a) - MOUNT_ALIGN_DEG, rot_y_now)
	var y: float = atan2(p, d.z)
	return Vector2(rad_to_deg(a) - MOUNT_ALIGN_DEG, rad_to_deg(y))


static func trace_surface(shape: ResolvedShape, dir: Vector3, cfg: ShipConfig) -> Vector3:
	var result: Dictionary = trace_surface_hit(shape, dir, cfg)
	var p: Vector3 = result["point"]
	return p


## trace_surface() plus the miss flag: { "point": Vector3, "hit": bool, "steps": int }.
##
## Two modes, selected by shape.origin_inside (SPEC 3, "Non-convex shapes"):
##   true  — march outward from the local origin, stepping abs(sdf) / lipschitz.
##   false — the origin sits in a hole (a torus), so march INWARD from the bounding sphere along
##           the ray and take the FIRST zero crossing. A ray can genuinely miss a torus; when it
##           does, "hit" is false and "point" falls back to the bounding-sphere point.
static func trace_surface_hit(shape: ResolvedShape, dir: Vector3, cfg: ShipConfig) -> Dictionary:
	var ray: Vector3 = direction_or_default(dir)
	if shape == null or cfg == null:
		return {"point": Vector3.ZERO, "hit": false, "steps": 0}
	if shape.origin_inside:
		return _trace_outward(shape, ray, cfg)
	return _trace_inward(shape, ray, cfg)


## SPEC 3 step 3. Central differences, 6 samples, normalised. A zero-length result (a perfectly
## flat patch of field, or a shape with no surface) falls back to +Y so callers never get NaN.
static func gradient(shape: ResolvedShape, p: Vector3, eps: float) -> Vector3:
	if shape == null:
		return Vector3.UP
	var h: float = maxf(absf(eps), MIN_TRACE_EPSILON)
	var dx: float = shape.sdf(p + Vector3(h, 0.0, 0.0)) - shape.sdf(p - Vector3(h, 0.0, 0.0))
	var dy: float = shape.sdf(p + Vector3(0.0, h, 0.0)) - shape.sdf(p - Vector3(0.0, h, 0.0))
	var dz: float = shape.sdf(p + Vector3(0.0, 0.0, h)) - shape.sdf(p - Vector3(0.0, 0.0, h))
	var g: Vector3 = Vector3(dx, dy, dz)
	if g.length_squared() < MIN_LENGTH_SQ:
		return Vector3.UP
	return g.normalized()


## SPEC 3 steps 4 and 5. The child's mount frame at anchor `p` with surface normal `normal`.
##
## `shape` and `p` are read only when `normal` is degenerate, in which case the normal is recovered
## from the shape itself rather than handing back a garbage basis.
## SPEC 3 steps 4-5. The child's basis in the parent's local frame.
##
## `rot` is degrees in the MOUNT FRAME, composed Rz * Ry * Rx so that Rz - the spin about the
## surface normal - is applied last and therefore acts in the frame itself. That is what keeps
## "spin the part on the surface" behaving like a dial after the part has already been tilted.
## SPEC 3 steps 4-5. The child's basis in the parent's local frame.
##
## `rot` is degrees in the MOUNT FRAME, composed Rz * Ry * Rx so that Rz - the spin about the
## surface normal - is applied last and therefore acts in the frame itself. That is what keeps
## "spin the part on the surface" behaving like a dial after the part has already been tilted.
static func mount_basis(shape: ResolvedShape, p: Vector3, normal: Vector3, rot: Vector3) -> Basis:
	var n: Vector3 = normal
	if n.length_squared() < MIN_LENGTH_SQ and shape != null:
		n = gradient(shape, p, FALLBACK_GRADIENT_EPS)
	if n.length_squared() < MIN_LENGTH_SQ:
		n = Vector3.UP
	var frame: Basis = mount_frame(n)

	# Composed by hand rather than through Basis.from_euler(..., EULER_ORDER_ZYX) so the order is
	# stated in the code instead of encoded in an enum whose composition and decomposition
	# conventions read in opposite directions. This is the one transform the whole document hangs
	# off; reviewing it should not need a docs lookup.
	var spun: Basis = Basis(Vector3.RIGHT, deg_to_rad(rot.x + MOUNT_ALIGN_DEG))
	spun = Basis(Vector3.UP, deg_to_rad(rot.y)) * spun
	spun = Basis(Vector3.BACK, deg_to_rad(rot.z)) * spun
	return (frame * spun).orthonormalized()


## The mount frame at a surface point whose outward normal is `normal`: +Z = N, +Y = the
## reference tangent, +X = Y cross Z.
##
## Split out of [method mount_basis] so "the frame's +Z IS the placement normal" - the convention
## the whole rotation UI is labelled against - is a claim a test can make directly, rather than
## one inferred from a basis that also carries the user rotation and the alignment term.
##
## The reference tangent is parent-local -Z projected onto the tangent plane. At the pole, where
## the normal is parallel to -Z, it falls back to parent-local +Y (SPEC 3 step 4).
static func mount_frame(normal: Vector3) -> Basis:
	var n: Vector3 = normal
	if n.length_squared() < MIN_LENGTH_SQ:
		n = Vector3.UP
	n = n.normalized()
	var reference: Vector3 = Vector3.FORWARD
	if absf(n.dot(reference)) > POLE_DOT:
		reference = Vector3.UP
	var tangent: Vector3 = reference - n * n.dot(reference)
	if tangent.length_squared() < MIN_LENGTH_SQ:
		tangent = _any_perpendicular(n)
	tangent = tangent.normalized()
	# Right-handed: (t x n) x t == n, so X cross Y == Z holds.
	return Basis(tangent.cross(n), tangent, n)


## How far `shape` reaches from its own origin along `dir_local`, in metres.
##
## THIS IS WHAT KEEPS A TILTED PART TOUCHING ITS PARENT. `offset == 0` is defined as "flush", and
## the flush distance is the extent of the child in the direction pointing back at the parent -
## which is the child's -Y only while the part is UNTILTED. [method ResolvedShape.mount_inset]
## measures exactly that fixed -Y extent, so once ADR 0004 let a part tilt, every tilt used the
## wrong number. Measured across the catalogue at 45 degrees: a torus_ring buried itself 0.81 m
## into its parent and a capsule_tank floated 0.31 m clear of it. The author reported the visible
## half: "also things are hovering they must be connected".
##
## Traced against a SMOOTH copy (see [method ResolvedShape.smooth_copy]) so a ribbed part seats on
## its mean surface rather than on a rib crest, which is the rule mount_inset already followed.
##
## Reduces to mount_inset() when `dir_local` is -Y, so an untilted part is unchanged.
static func support_inset(shape: ResolvedShape, dir_local: Vector3, cfg: ShipConfig) -> float:
	if shape == null:
		return 0.0
	if dir_local.length_squared() < MIN_LENGTH_SQ:
		return shape.mount_inset()
	var smooth: ResolvedShape = shape.smooth_copy()
	var dir: Vector3 = dir_local.normalized()
	var hit: Vector3 = trace_surface(smooth, dir, cfg)
	# THE TRACE CAN MISS, and a miss must not be read as a distance. A torus_ring has its origin
	# in its own HOLE, so a ray cast from there along -Y never meets the ring at all; the tracer
	# ran to its maximum range and the part was seated 3.5 m off its parent. Anything that does not
	# land ON the surface falls back to the fixed -Y extent, which is what this measured before
	# ADR 0004 and is correct for an untilted part of any family.
	if absf(smooth.sdf(hit)) > SUPPORT_HIT_EPSILON:
		return shape.mount_inset()
	return hit.length()


## The `offset` a NEWLY PLACED part starts at: a negative one, sinking the part into its parent
## until its lowest point is `cfg.attach_embed_m` below the parent's surface.
##
## `offset == 0` is flush and stays flush; this does not touch the attach model. But flush on a
## curved parent is a single point of contact - a pod on a sphere touches it at the tangent and
## nowhere else: "when attaching an object to a sphere surface obviously its at its tangent point
## and theres no real connection. ALL added parts must by default upon placement be deep enough
## such that there are no barely touching surfaces." So every creation path - the palette drag,
## add_part(), the templates - seeds the offset from here instead of from 0, and the player can
## still type 0 for flush or pull it further either way.
##
## MEASURED ON THE ACTUAL SURFACES, not read off the child's mount inset. The child's SOLE - the
## lowest point of each column of its -Y footprint - is sampled once, and the offset is bisected
## until the deepest sole point is the target depth inside the parent's SDF. That is what makes a
## ring on a sphere come out right: its axis passes through the hole, so an axis measure would
## call it seated while its rim floats half a metre clear of the sphere curving away beneath.
## The target is capped at `cfg.attach_embed_max_fraction` of the child's height, so a thin
## plate is sunk to a fraction of itself and not out of sight.
##
## `part` supplies the attach direction and rotation (its own offset is ignored); the transform
## comes from [method local_transform], so the embed is exact for the placement it seeds and
## does not chase a later drag or rotation - it is a starting value, not a constraint. With no
## parent surface to measure against the part is sunk by the target itself along the ray.
##
## Not every pair can reach the target: a ring's tube may be thinner than it, and a wide part
## on a narrow one can overhang the parent entirely. Those are sunk to the SHALLOWEST depth
## with (nearly) the most contact instead - the first seat, not the far side of the hole - or
## left flush when nothing ever touches; the attach model already allows a part to hover, and
## this is the same hover, not a new one.
static func default_offset(
	parent_shape: ResolvedShape, child_shape: ResolvedShape, part: ShipPart, cfg: ShipConfig
) -> float:
	if part == null or child_shape == null:
		return 0.0
	var conf: ShipConfig = cfg if cfg != null else ShipConfig.defaults()
	var height: float = child_shape.local_aabb().size.y
	var target: float = minf(conf.attach_embed_m, conf.attach_embed_max_fraction * height)
	if target <= 0.0:
		return 0.0
	var sole: PackedVector3Array = sole_points(child_shape)
	if parent_shape == null or sole.is_empty():
		return -target
	var probe: ShipPart = part.duplicate_part()
	probe.offset = 0.0
	var flush: Transform3D = local_transform(parent_shape, child_shape, probe, conf)
	probe.offset = -1.0
	var sunk: Transform3D = local_transform(parent_shape, child_shape, probe, conf)
	# local_transform() is affine in the offset: one unit of offset moves the part along the
	# mount normal and nothing else, so two placements give the axis the search runs along.
	var outward: Vector3 = flush.origin - sunk.origin
	if outward.length_squared() < MIN_LENGTH_SQ:
		return -target
	var best_offset: float = 0.0
	var best_depth: float = _sole_depth(parent_shape, sole, flush, outward, 0.0)
	if best_depth >= target:
		return 0.0
	# Walk in from flush half a target per rung, out to the part's own height plus the target -
	# sunk that far it has been swallowed whole. The first rung at or past the target is bisected
	# against the rung before it. When no rung gets there - a parent thinner than the target, a
	# footprint that overhangs it - the walk stops at the first rung that gains nothing on the
	# contact it has, because past that the part is coming out the parent's far side (on a ring,
	# into the hole), and the seat is the shallowest offset with nearly that much contact. When
	# nothing ever touches, it stays flush.
	var rung: float = target * 0.5
	var limit: float = height + child_shape.mount_inset() + target
	var shallow: float = 0.0
	var deep: float = 0.0
	var best_shallow: float = 0.0
	var reached: bool = false
	while deep > -limit and not reached:
		shallow = deep
		deep = maxf(deep - rung, -limit)
		var depth: float = _sole_depth(parent_shape, sole, flush, outward, deep)
		reached = depth >= target
		if depth > best_depth * (1.0 + EMBED_GAIN) + 0.001:
			best_depth = depth
			best_offset = deep
			best_shallow = shallow
		elif best_depth > 0.0:
			break
	var want: float = target
	if not reached:
		if best_depth <= 0.0:
			return 0.0
		want = best_depth - MIN_TRACE_EPSILON
		shallow = best_shallow
		deep = best_offset
	for _step: int in EMBED_BISECT_STEPS:
		var mid: float = (shallow + deep) * 0.5
		if _sole_depth(parent_shape, sole, flush, outward, mid) >= want:
			deep = mid
		else:
			shallow = mid
	return deep


## The child's SOLE, in its own scaled local frame: for each column of an EMBED_SOLE_GRID x
## EMBED_SOLE_GRID grid over the -Y footprint, the lowest point that is inside the shape.
## Columns that never enter the shape - a ring's hole - contribute nothing. Public so a
## diagnostic can draw what default_offset() measured.
static func sole_points(shape: ResolvedShape) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	if shape == null:
		return out
	var box: AABB = shape.local_aabb()
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return out
	var cell_x: float = box.size.x / float(EMBED_SOLE_GRID)
	var cell_z: float = box.size.z / float(EMBED_SOLE_GRID)
	var step_y: float = box.size.y / float(EMBED_SOLE_STEPS)
	for ix: int in EMBED_SOLE_GRID:
		var x: float = box.position.x + (float(ix) + 0.5) * cell_x
		for iz: int in EMBED_SOLE_GRID:
			var z: float = box.position.z + (float(iz) + 0.5) * cell_z
			var lowest: Vector3 = _column_sole(shape, x, z, box.position.y, step_y)
			if is_finite(lowest.y):
				out.append(lowest)
	return out


## March one footprint column upward from the bottom of the bounds until the shape is entered,
## then bisect the entry. Returns a point with y = INF when the column misses the shape.
static func _column_sole(
	shape: ResolvedShape, x: float, z: float, y_from: float, step_y: float
) -> Vector3:
	var outside: float = y_from
	var inside: float = INF
	for k: int in EMBED_SOLE_STEPS:
		var y: float = y_from + step_y * float(k + 1)
		if shape.sdf(Vector3(x, y, z)) <= 0.0:
			inside = y
			break
		outside = y
	if not is_finite(inside):
		return Vector3(x, INF, z)
	for _step: int in EMBED_SOLE_REFINE:
		var mid: float = (outside + inside) * 0.5
		if shape.sdf(Vector3(x, mid, z)) <= 0.0:
			inside = mid
		else:
			outside = mid
	return Vector3(x, inside, z)


## How far the deepest sole point sits inside the parent when the part is placed at `offset`:
## `flush` is its transform at offset 0 and `outward` the mount normal, so the part at `offset`
## is `flush` carried `outward * offset` (negative offsets sink).
##
## On an unevenly scaled parent the SDF is only a bound (see EMBED_EXIT_STEPS), so the points
## whose bound leaves them in contention for deepest are re-measured exactly enough: the exit
## distance along the mount normal, and along the gradient, whichever is shorter. That is the
## true depth wherever the nearest surface is a cap or a face, which in this catalogue is
## everywhere it matters.
static func _sole_depth(
	parent_shape: ResolvedShape,
	sole: PackedVector3Array,
	flush: Transform3D,
	outward: Vector3,
	offset: float
) -> float:
	var shift: Vector3 = outward * offset
	var bounds: PackedFloat64Array = PackedFloat64Array()
	var deepest: float = -INF
	for q: Vector3 in sole:
		var depth: float = -parent_shape.sdf(flush * q + shift)
		bounds.append(depth)
		if depth > deepest:
			deepest = depth
	var ratio: float = _scale_ratio(parent_shape)
	if deepest <= 0.0 or ratio >= 1.0:
		return deepest
	# A point's true depth is between its bound and its bound over the ratio, so only points
	# within that of the deepest bound can be the deepest.
	var floor_bound: float = deepest * ratio
	var axis: Vector3 = outward.normalized()
	for i: int in sole.size():
		if bounds[i] < floor_bound:
			continue
		var p: Vector3 = flush * sole[i] + shift
		var along_axis: float = _exit_distance(parent_shape, p, axis, bounds[i])
		var grad: Vector3 = gradient(parent_shape, p, FALLBACK_GRADIENT_EPS)
		var along_grad: float = _exit_distance(parent_shape, p, grad, bounds[i])
		deepest = maxf(deepest, minf(along_axis, along_grad))
	return deepest


## min / max of the absolute per-axis scale: 1.0 for a uniform scale, smaller the more the
## shape is stretched, and the factor an SDF reading can fall short of the true distance by.
static func _scale_ratio(shape: ResolvedShape) -> float:
	var s: Vector3 = shape.scale.abs()
	var hi: float = maxf(s.x, maxf(s.y, s.z))
	if hi <= 0.0:
		return 1.0
	return minf(s.x, minf(s.y, s.z)) / hi


## Distance from `p`, inside `shape`, to its surface along `dir`. Sphere-traced on the bound
## (`first` is the bound at `p`), then bisected; a point still inside after every step returns
## the distance covered, which is short of the truth and so only ever sinks a part deeper.
static func _exit_distance(shape: ResolvedShape, p: Vector3, dir: Vector3, first: float) -> float:
	var inside_t: float = 0.0
	var outside_t: float = INF
	var step: float = first
	for _k: int in EMBED_EXIT_STEPS:
		var t: float = inside_t + maxf(step, MIN_TRACE_EPSILON)
		step = -shape.sdf(p + dir * t)
		if step <= 0.0:
			outside_t = t
			break
		inside_t = t
	if not is_finite(outside_t):
		return inside_t
	for _step: int in EMBED_EXIT_REFINE:
		var mid: float = (inside_t + outside_t) * 0.5
		if shape.sdf(p + dir * mid) <= 0.0:
			inside_t = mid
		else:
			outside_t = mid
	return (inside_t + outside_t) * 0.5


## The snap target with id `snap_id` on `shape`, or {} when the shape has no such target.
##
## Linear over [method SnapTargets.for_shape], which is deliberate: the array is at most fifteen
## entries and generating it is what costs, so an index would buy nothing and would have to be
## invalidated every time a param changed the shape.
static func snap_target(shape: ResolvedShape, snap_id: String) -> Dictionary:
	if shape == null or snap_id == "":
		return {}
	for target: Dictionary in SnapTargets.for_shape(shape):
		if str(target.get("id", "")) == snap_id:
			return target
	return {}


## SPEC 3 steps 4-6 for a SNAPPED child: the child's transform in its PARENT's local space, with
## the anchor and the mount axis taken from `target` instead of from a sphere trace.
##
## `target` is an UNSCALED [SnapTargets] dictionary — exactly what [method SnapTargets.nearest]
## and [method snap_target] return — and is scaled into the parent's real frame here, because the
## parent's per-axis `scale` is a transform and not a size (a snap point on a stretched box has to
## stretch with it, and its normal has to tilt the other way).
##
## `offset` and the child's own mount_inset() mean what they mean on the free path: 0 is flush,
## positive floats the child off the surface along the target normal, negative embeds it.
static func snap_transform(
	parent_shape: ResolvedShape,
	child_shape: ResolvedShape,
	target: Dictionary,
	rot: Vector3,
	offset: float,
	cfg: ShipConfig = null
) -> Transform3D:
	if target.is_empty():
		return Transform3D.IDENTITY
	var scaled: Dictionary = SnapTargets.apply_scale(target, _shape_scale(parent_shape))
	var anchor: Vector3 = scaled["local_pos"]
	var normal: Vector3 = scaled["normal"]
	var frame: Basis = mount_basis(parent_shape, anchor, normal, rot)
	var inset: float = _contact_inset(child_shape, frame, normal, cfg)
	return Transform3D(frame, anchor + normal * (offset + inset))


## The (yaw, pitch) degrees a snapped child stores — DERIVED from the target, never authored.
##
## The angles are the ones that would ray-trace back to the same anchor: the direction from the
## parent's local origin to the SCALED target position. The `center` target sits AT that origin,
## where there is no such direction, so it reports the direction of its own mount normal instead
## (+Y, [member SnapTargets.CENTER_NORMAL]) — which is where a child snapped to a parent's centre
## actually stands.
static func angles_for_target(parent_shape: ResolvedShape, target: Dictionary) -> Vector2:
	if target.is_empty():
		return Vector2.ZERO
	var scaled: Dictionary = SnapTargets.apply_scale(target, _shape_scale(parent_shape))
	var pos: Vector3 = scaled["local_pos"]
	if pos.length_squared() < MIN_LENGTH_SQ:
		var normal: Vector3 = scaled["normal"]
		return angles_from_direction(normal)
	return angles_from_direction(pos)


## SPEC 3 steps 1-6 composed: the child's transform in its PARENT's local space.
##
## `offset == 0` puts the child's attach face tangent to the parent surface (flush), because
## mount_inset() is the distance from the child's own origin to that face along child -Y.
## Positive offset floats the child out along the normal, negative embeds it.
##
## THE ROUTER between the two attach paths (see the class docstring). A non-empty
## `part.snap_id` that names a target the parent actually has takes the snapped path; everything
## else - an empty id, an id the parent's family does not carry, a parent with no traceable
## shape — takes the free-surface path below on the part's stored yaw/pitch. Both paths are
## supported, permanently; neither is a migration state.
static func local_transform(
	parent_shape: ResolvedShape, child_shape: ResolvedShape, part: ShipPart, cfg: ShipConfig
) -> Transform3D:
	if part == null:
		return Transform3D.IDENTITY
	var anchor: Dictionary = anchor_for(parent_shape, part, cfg)
	var pos: Vector3 = anchor["pos"]
	var n: Vector3 = anchor["normal"]
	var frame: Basis = mount_basis(parent_shape, pos, n, part.rot)
	var inset: float = _contact_inset(child_shape, frame, n, cfg)
	return Transform3D(frame, pos + n * (part.offset + inset))


## SPEC 3 steps 1-3 alone: WHERE a part stands on its parent and the mount normal there, both in
## the PARENT's local frame:
##   { "pos": Vector3, "normal": Vector3 }   # normal is unit length
##
## The one anchor every consumer reads. [method local_transform] builds the placed transform on
## it, [ShipSeams] lays the seam plane through it (the plane SPEC 7 names: through P with normal
## N), and the selection gizmo draws its footprint ring on it - so the wall a hatch is cut into,
## the collar the player grabs, and the surface the part actually sits on are the same P and N by
## construction rather than three re-derivations that could drift.
##
## Same router as local_transform: a `snap_id` the parent carries takes the snapped anchor
## ([SnapTargets], scaled into the parent's frame); otherwise the ray from yaw/pitch is traced.
## A parent with no traceable shape is a point at its origin and the normal is the ray itself.
static func anchor_for(parent_shape: ResolvedShape, part: ShipPart, cfg: ShipConfig) -> Dictionary:
	if part == null:
		return {"pos": Vector3.ZERO, "normal": Vector3.UP}
	if part.snap_id != "" and parent_shape != null:
		var target: Dictionary = snap_target(parent_shape, part.snap_id)
		if not target.is_empty():
			var scaled: Dictionary = SnapTargets.apply_scale(target, _shape_scale(parent_shape))
			var snap_pos: Vector3 = scaled["local_pos"]
			var snap_normal: Vector3 = scaled["normal"]
			return {"pos": snap_pos, "normal": snap_normal}
	var dir: Vector3 = direction_from_angles(part.yaw, part.pitch)
	if parent_shape == null:
		# No traceable parent surface (an unresolved family, or a component instance with no
		# proxy shape): treat the parent as a point and mount straight out along the ray.
		return {"pos": Vector3.ZERO, "normal": dir}
	var traced: Vector3 = trace_surface(parent_shape, dir, cfg)
	var eps: float = FALLBACK_GRADIENT_EPS
	if cfg != null:
		eps = cfg.gradient_eps
	return {"pos": traced, "normal": gradient(parent_shape, traced, eps)}


## part_id -> ResolvedShape. Computed once per rebuild and reused by attach, sdf, metrics and bake.
##
## Component instances have no primitive family of their own; they get a proxy shape resolved from
## their definition's root part, so children can still attach to their surface. Parts whose family
## cannot be resolved are simply absent from the result.
##
## THE REST OF A DEFINITION IS EMITTED HERE TOO, under `"<instance>/<inner>"` (see
## [method _expand_instance_shapes]). Until it was, an instance resolved to its root alone: the
## scene builder, the SDF and the budgets all walk this map, so lifting a subtree into a
## component made every part but its head vanish from the view and the bake - "when i selected
## multiple parts and press make component they all dissapear". Derived ids are the mechanism
## a twin already uses, and every consumer that walks the map gets the whole component the
## same way it gets the mirrored half.
static func resolve_shapes(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary:
	var out: Dictionary = {}
	if doc == null or data == null:
		return out
	for id: String in ordered_part_ids(doc):
		var part: ShipPart = doc.parts[id]
		var shape: ResolvedShape = _shape_for_part(doc, data, cfg, part)
		if shape != null:
			out[id] = shape
			# A twin SHARES its source's shape - same object, deliberately: reflecting a part does
			# not reshape it, and the SDF, the metrics pass and the preview all look a shape up by
			# id. Aliased for anything that COULD twin rather than anything that DOES, because
			# whether a twin exists depends on where the part landed and only the transform pass
			# knows that.
			var twin: bool = _may_twin(doc, id)
			if twin:
				out[ShipSymmetry.twin_id(id)] = shape
			if part.kind == KIND_COMPONENT_INSTANCE:
				var scale: Vector3 = _safe_scale(part.scale, cfg)
				_expand_instance_shapes(doc, data, cfg, id, part, scale, 0, out, twin)
	return out


## True when symmetry is on for the document AND this part is not effectively asymmetric. Says
## nothing about WHERE the part is - the on-plane test needs a transform and lives in
## _add_symmetry_twins().
static func _may_twin(doc: ShipDoc, part_id: String) -> bool:
	if ShipSymmetry.plane_axis(doc.symmetry_plane) < 0:
		return false
	return not ShipSymmetry.is_effectively_asymmetric(doc, part_id)


## part_id -> Transform3D in SHIP space.
##
## Includes DERIVED symmetry twins under `"<source>~m"` (see _add_symmetry_twins) and legacy
## mirror derivatives, which are real doc parts.
static func resolve_all(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary:
	if doc == null:
		return {}
	return resolve_all_from_shapes(doc, resolve_shapes(doc, data, cfg), cfg)


## resolve_all() for callers that already hold the resolve_shapes() result.
##
## Parts are placed in dependency order rather than raw tree order: a derivative needs its mirror
## SOURCE resolved (which may sit anywhere in the tree), an ordinary part needs its parent. The
## loop repeats until nothing new can be placed, so a broken doc degrades instead of looping.
static func resolve_all_from_shapes(
	doc: ShipDoc, shapes: Dictionary, cfg: ShipConfig
) -> Dictionary:
	var out: Dictionary = {}
	if doc == null:
		return out
	var pending: Array[String] = []
	for id: String in ordered_part_ids(doc):
		pending.append(id)
	var guard: int = pending.size() + 1
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var blocked: Array[String] = []
		for id: String in pending:
			var part: ShipPart = doc.parts[id]
			if _can_place(doc, out, id, part):
				out[id] = _place_part(doc, shapes, cfg, out, id, part)
			else:
				blocked.append(id)
		if blocked.size() == pending.size():
			break
		pending = blocked
	# The inner parts of every placed instance, keyed like their shapes: hung from the
	# instance's transform with the same attach maths as the ship tree, so a definition is
	# placed exactly as the subtree it was lifted from would have been.
	for id: String in ordered_part_ids(doc):
		var part: ShipPart = doc.parts[id]
		if part.kind != KIND_COMPONENT_INSTANCE or not out.has(id):
			continue
		_expand_instance_transforms(doc, cfg, shapes, id, part, out[id], 0, out)
	_add_symmetry_twins(doc, cfg, out)
	return out


## Add a reflected transform for every part the document's symmetry plane duplicates.
##
## [b]NOTHING GENERATED A TWIN BEFORE THIS EXISTED.[/b] [ShipSymmetry] could say whether a part
## SHOULD have one, and [ShipComplexity] charged double for it, but no transform, no mesh and no
## SDF lobe was ever produced - so symmetry was a tax with nothing to show for it, and changing
## the mirror plane visibly did nothing at all. Reported as "i press mirror buttons and it appears
## nothing mirrors", which was exactly right.
##
## Twins are DERIVED, never stored: they exist only in this dictionary, they are keyed
## `"<source>~m"` ([method ShipSymmetry.twin_id]), and every consumer that walks the transform map
## rather than `doc.parts` gets them for free - the scene builder, the SDF union, the bake.
##
## Each part is reflected INDEPENDENTLY in ship space rather than by mirroring a subtree, because
## reflecting a rigid transform commutes with composing it: the reflection of a child's final
## ship-space transform IS its position in the mirrored subtree. No hierarchy walk, and a part
## whose parent sits on the plane still mirrors correctly.
static func _add_symmetry_twins(doc: ShipDoc, cfg: ShipConfig, out: Dictionary) -> void:
	if doc == null:
		return
	var plane: String = doc.symmetry_plane
	if ShipSymmetry.plane_axis(plane) < 0:
		return
	# Iterates the DOC, not `out`, so writing twins into `out` cannot feed itself.
	for id: String in ordered_part_ids(doc):
		var xform_v: Variant = out.get(id)
		if not (xform_v is Transform3D):
			continue
		var xform: Transform3D = xform_v
		if not ShipSymmetry.generates_twin(doc, id, xform, cfg):
			continue
		out[ShipSymmetry.twin_id(id)] = ShipMirror.reflect(xform, plane)
	# The expanded parts of a component instance ("<instance>/<inner>") mirror on their
	# instance's terms - its asymmetric flag - but each by its OWN position, exactly as the parts
	# of an ordinary subtree do: the half of a component that straddles the plane stays single.
	# A snapshot of the keys, so the twins written here cannot feed the loop.
	var keys: Array = out.keys()
	for key_v: Variant in keys:
		var key: String = str(key_v)
		if not ShipComponents.is_expanded_id(key) or ShipSymmetry.is_twin_id(key):
			continue
		var inner_xform: Transform3D = out[key]
		if not ShipSymmetry.generates_twin(doc, ShipComponents.instance_of(key), inner_xform, cfg):
			continue
		out[ShipSymmetry.twin_id(key)] = ShipMirror.reflect(inner_xform, plane)


## Every part id in a deterministic order: doc.part_order() first, then anything it left out
## (orphans, cycle members) sorted by id, so a broken doc still resolves what it can.
static func ordered_part_ids(doc: ShipDoc) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	if doc == null:
		return ids
	var seen: Dictionary = {}
	for id: String in doc.part_order():
		if doc.parts.has(id) and not seen.has(id):
			seen[id] = true
			ids.append(id)
	var rest: Array = doc.parts.keys()
	rest.sort()
	for id: String in rest:
		if not seen.has(id):
			seen[id] = true
			ids.append(id)
	return ids


## A unit ray, defaulting to parent-local +Z (yaw = 0, pitch = 0) for a degenerate input.
static func direction_or_default(dir: Vector3) -> Vector3:
	if dir.length_squared() < MIN_LENGTH_SQ:
		return Vector3.BACK
	return dir.normalized()


# --- private -------------------------------------------------------------------------------


# origin_inside == true: start at the local origin (inside the solid) and march out along the ray.
static func _trace_outward(shape: ResolvedShape, ray: Vector3, cfg: ShipConfig) -> Dictionary:
	var lipschitz: float = maxf(shape.lipschitz, MIN_LIPSCHITZ)
	var eps: float = maxf(cfg.trace_epsilon, MIN_TRACE_EPSILON)
	var limit: float = maxf(shape.bound_radius, eps) * TRACE_RANGE_SLACK
	var steps: int = maxi(cfg.trace_max_steps, 1)
	var t: float = 0.0
	var prev_t: float = 0.0
	var prev_d: float = 0.0
	var taken: int = steps
	for i: int in steps:
		var d: float = shape.sdf(ray * t)
		if absf(d) < eps:
			return {"point": ray * t, "hit": true, "steps": i}
		if i > 0 and (d > 0.0) != (prev_d > 0.0):
			# Stepped over a thin feature: the crossing lies between prev_t and t.
			return {"point": ray * _bisect(shape, ray, prev_t, t, eps), "hit": true, "steps": i}
		prev_t = t
		prev_d = d
		t += absf(d) / lipschitz
		if t > limit:
			t = limit
			taken = i + 1
			break
	return {"point": ray * t, "hit": false, "steps": taken}


# origin_inside == false (a torus): start outside on the bounding sphere and march inward toward
# the origin, taking the first zero crossing. Reaching the origin without one is a genuine miss.
static func _trace_inward(shape: ResolvedShape, ray: Vector3, cfg: ShipConfig) -> Dictionary:
	var lipschitz: float = maxf(shape.lipschitz, MIN_LIPSCHITZ)
	var eps: float = maxf(cfg.trace_epsilon, MIN_TRACE_EPSILON)
	var steps: int = maxi(cfg.trace_max_steps, 1)
	var start: float = maxf(shape.bound_radius, eps)
	var t: float = start
	var prev_t: float = start
	for i: int in steps:
		var d: float = shape.sdf(ray * t)
		if absf(d) < eps:
			return {"point": ray * t, "hit": true, "steps": i}
		if d < 0.0:
			return {"point": ray * _bisect(shape, ray, prev_t, t, eps), "hit": true, "steps": i}
		prev_t = t
		t -= absf(d) / lipschitz
		if t <= 0.0:
			break
	return {"point": ray * start, "hit": false, "steps": steps}


# Binary search for the sign change between two ray parameters. Used only when a step overshoots.
static func _bisect(
	shape: ResolvedShape, ray: Vector3, t_lo: float, t_hi: float, eps: float
) -> float:
	var lo: float = t_lo
	var hi: float = t_hi
	var d_lo: float = shape.sdf(ray * lo)
	for i: int in BISECT_STEPS:
		var mid: float = 0.5 * (lo + hi)
		var d_mid: float = shape.sdf(ray * mid)
		if absf(d_mid) < eps:
			return mid
		if (d_mid > 0.0) == (d_lo > 0.0):
			lo = mid
			d_lo = d_mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


# A shape's per-axis scale, defaulting to ONE for a parent with no resolvable shape, so the snap
# helpers can be handed a null parent without every caller null-checking first.
## Flush distance for a child standing in `frame` on a surface whose outward normal is `normal`.
##
## The contact direction is -normal, expressed in the CHILD's own frame - `frame` is orthonormal,
## so its transpose is its inverse and the rotation is one basis multiply.
static func _contact_inset(
	child_shape: ResolvedShape, frame: Basis, normal: Vector3, cfg: ShipConfig
) -> float:
	if child_shape == null:
		return 0.0
	if normal.length_squared() < MIN_LENGTH_SQ:
		return child_shape.mount_inset()
	var dir_local: Vector3 = frame.transposed() * (-normal.normalized())
	return support_inset(child_shape, dir_local, cfg)


static func _shape_scale(shape: ResolvedShape) -> Vector3:
	return shape.scale if shape != null else Vector3.ONE


static func _any_perpendicular(n: Vector3) -> Vector3:
	var candidate: Vector3 = Vector3.UP
	if absf(n.dot(candidate)) > POLE_DOT:
		candidate = Vector3.RIGHT
	return candidate - n * n.dot(candidate)


## Resolve ONE part's shape, for a caller holding a part that is not (yet) in the document - the
## placement ghost. Same routing as the batch pass, so a ghost cannot resolve differently from the
## part it becomes.
static func resolve_shapes_for_part(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, part: ShipPart
) -> ResolvedShape:
	if doc == null or data == null:
		return null
	return _shape_for_part(doc, data, cfg, part)


static func _shape_for_part(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, part: ShipPart
) -> ResolvedShape:
	if part == null:
		return null
	var scale: Vector3 = _safe_scale(part.scale, cfg)
	if part.kind == KIND_COMPONENT_INSTANCE:
		return _component_proxy_shape(doc, data, part, scale)
	if not data.has_family(part.family):
		return null
	return ShapeGen.resolve(data, part.family, part.manufacturer, part.params, scale)


# A component instance carries no family of its own. Its definition's root part stands in as the
# surface children attach to; the rest of the definition follows under "<instance>/<inner>" keys
# (see _expand_instance_shapes), and ShipComponents.expand() reads both back out of this pass.
static func _component_proxy_shape(
	doc: ShipDoc, data: ShipData, part: ShipPart, scale: Vector3
) -> ResolvedShape:
	if not doc.components.has(part.family):
		return null
	var definition: Dictionary = doc.components[part.family]
	var inner_parts: Dictionary = definition.get("parts", {})
	var root_id: String = definition.get("root", "")
	if not inner_parts.has(root_id):
		return null
	var raw: Variant = inner_parts[root_id]
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var raw_dict: Dictionary = raw
	var inner: ShipPart = ShipPart.from_dict(root_id, raw_dict)
	if not data.has_family(inner.family):
		return null
	var combined: Vector3 = inner.scale * scale
	return ShapeGen.resolve(data, inner.family, inner.manufacturer, inner.params, combined)


## The inner parts of a component instance, keyed `"<key>/<inner id>"` where `key` is the
## instance's own id - or, for an instance nested inside a definition, its own expanded key, so
## nesting chains keys ("outer/inner/deeper"). The definition ROOT is never emitted: the
## instance's own key already carries it, as the proxy shape children attach to, and a nested
## instance node carries ITS definition's root the same way. `scale_mul` is the instance's scale,
## carried down into every inner part the way [method ShipComponents.expand] always did.
## `twin` aliases each shape under the twin key too, on the instance's terms (see resolve_shapes).
static func _expand_instance_shapes(
	doc: ShipDoc,
	data: ShipData,
	cfg: ShipConfig,
	key: String,
	part: ShipPart,
	scale_mul: Vector3,
	depth: int,
	out: Dictionary,
	twin: bool
) -> void:
	var walk: Dictionary = _definition_walk(doc, part, depth)
	if walk.is_empty():
		return
	var inner: Dictionary = walk["parts"]
	for inner_id: String in walk["order"]:
		var inner_part: ShipPart = inner[inner_id]
		var inner_key: String = key + "/" + inner_id
		var scale: Vector3 = _safe_scale(inner_part.scale * scale_mul, cfg)
		var shape: ResolvedShape = null
		if inner_part.kind == KIND_COMPONENT_INSTANCE:
			shape = _component_proxy_shape(doc, data, inner_part, scale)
		elif data.has_family(inner_part.family):
			shape = ShapeGen.resolve(
				data, inner_part.family, inner_part.manufacturer, inner_part.params, scale
			)
		if shape == null:
			continue
		out[inner_key] = shape
		if twin:
			out[ShipSymmetry.twin_id(inner_key)] = shape
		if inner_part.kind == KIND_COMPONENT_INSTANCE:
			_expand_instance_shapes(
				doc, data, cfg, inner_key, inner_part, scale, depth + 1, out, twin
			)


## Ship-space transforms for the parts [method _expand_instance_shapes] keyed, hung from `world`,
## the placed instance's transform. Each inner part is attached to its parent within the
## definition through [method local_transform] - the root's frame is the instance's own - so the
## same four numbers place a part whether it sits in the ship tree or inside a component.
static func _expand_instance_transforms(
	doc: ShipDoc,
	cfg: ShipConfig,
	shapes: Dictionary,
	key: String,
	part: ShipPart,
	world: Transform3D,
	depth: int,
	out: Dictionary
) -> void:
	var walk: Dictionary = _definition_walk(doc, part, depth)
	if walk.is_empty():
		return
	var inner: Dictionary = walk["parts"]
	var root_id: String = walk["root"]
	var locals: Dictionary = {}
	locals[root_id] = Transform3D.IDENTITY
	for inner_id: String in walk["order"]:
		var inner_part: ShipPart = inner[inner_id]
		var inner_key: String = key + "/" + inner_id
		var parent_key: String = key
		if inner_part.parent != root_id:
			parent_key = key + "/" + inner_part.parent
		var parent_local: Transform3D = locals.get(inner_part.parent, Transform3D.IDENTITY)
		var parent_shape: ResolvedShape = shapes.get(parent_key)
		var child_shape: ResolvedShape = shapes.get(inner_key)
		var local: Transform3D = (
			parent_local * local_transform(parent_shape, child_shape, inner_part, cfg)
		)
		locals[inner_id] = local
		out[inner_key] = world * local
		if inner_part.kind == KIND_COMPONENT_INSTANCE:
			_expand_instance_transforms(
				doc, cfg, shapes, inner_key, inner_part, world * local, depth + 1, out
			)


## A definition's parts and the order the two expansions place them in: parents before children,
## the root left out because the instance's own key stands for it. Empty past the nesting limit
## or for a definition that is missing or has no root, which stops the expansion rather than
## degrading it - the validator reports both conditions.
static func _definition_walk(doc: ShipDoc, part: ShipPart, depth: int) -> Dictionary:
	if depth > ShipComponents.MAX_NESTING_DEPTH or not doc.components.has(part.family):
		return {}
	var definition: Dictionary = doc.components[part.family]
	var inner: Dictionary = ShipComponents.definition_parts(definition)
	var root_id: String = definition.get("root", "")
	if not inner.has(root_id):
		return {}
	var order: PackedStringArray = PackedStringArray()
	for inner_id: String in ShipComponents.definition_order(inner, root_id):
		if inner_id != root_id:
			order.append(inner_id)
	return {"parts": inner, "root": root_id, "order": order}


# Guard against a doc that stores a zero, negative or non-finite scale: those make the resolved
# field degenerate and the tracer spin. This is NOT budget enforcement — an over-limit but finite
# scale is left exactly as stored (SPEC 8: loading is never refused) and reported by ShipValidate.
static func _safe_scale(scale: Vector3, cfg: ShipConfig) -> Vector3:
	var floor_value: float = 0.001
	if cfg != null:
		floor_value = maxf(cfg.part_scale_min, 0.001)
	var out: Vector3 = scale
	if not is_finite(out.x) or out.x <= 0.0:
		out.x = floor_value
	if not is_finite(out.y) or out.y <= 0.0:
		out.y = floor_value
	if not is_finite(out.z) or out.z <= 0.0:
		out.z = floor_value
	return out


static func _can_place(doc: ShipDoc, placed: Dictionary, id: String, part: ShipPart) -> bool:
	if id == doc.root:
		return true
	if part.is_mirror() and doc.parts.has(part.mirror_source):
		return placed.has(part.mirror_source)
	if part.parent == "" or not doc.parts.has(part.parent):
		return true
	return placed.has(part.parent)


static func _place_part(
	doc: ShipDoc,
	shapes: Dictionary,
	cfg: ShipConfig,
	placed: Dictionary,
	id: String,
	part: ShipPart
) -> Transform3D:
	if id == doc.root:
		return Transform3D.IDENTITY
	if part.is_mirror() and placed.has(part.mirror_source):
		var source: Transform3D = placed[part.mirror_source]
		return ShipMirror.reflect(source, part.mirror_plane)
	var parent_xform: Transform3D = placed.get(part.parent, Transform3D.IDENTITY)
	var parent_shape: ResolvedShape = shapes.get(part.parent)
	var child_shape: ResolvedShape = shapes.get(id)
	return parent_xform * local_transform(parent_shape, child_shape, part, cfg)
