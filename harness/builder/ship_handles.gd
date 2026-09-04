## ShipHandles - the selection gizmo: geometry in a part's local frame, plus screen-space
## hit-testing. Static only - no state, no nodes, no signals, no allocation beyond the arrays
## it returns.
##
## RETIRED(2026-08-31): the Tab-gated "advanced" handle set, and the free-rotation BALL.
##
## Spore gates its rings and morph handles behind holding Tab and offers a ball for free rotation.
## Cloning that produced a builder in which a selected part showed THREE CIRCLES - the ball's great
## circles - and every grab returned Handle.BALL_ROTATE, which spins about the mount normal. So all
## three circles rotated the part about its placement vector, which is exactly what was reported,
## twice. Worse, the flag lived in three places at once with different defaults, and a focus change
## silently turned the rings off.
##
## There is now no modal state and no ball: the three rings, the six morph handles and the offset
## handle are always drawn and always grabbable. Handle.BALL_ROTATE stays in the enum (the contract
## pins its number) and is never produced.
##
## HISTORICAL: Spore's own reverse-engineered source calls these `mRotationRingHandle*` and
## `mMorphHandles` and caps the morph set at 8 per part - MORPH_MAX below. We generate 6 of
## handles. Spore's own reverse-engineered source calls these `mRotationRingHandle*` and
## that maximum: our SDF families expose exactly six axis-aligned deform directions (the six
## face centres of the part's local AABB), so handles 7 and 8 would have nothing to drive.
##
## HIT-TESTING IS SCREEN-SPACE, NOT PHYSICS. Every handle is projected with
## Camera3D.unproject_position() and compared to the pointer IN PIXELS, so a distant part's
## gizmo is exactly as grabbable as a near one and the gizmo never enters the physics world -
## no colliders to add, and no chance of a handle body being returned by the part picker.
## unproject_position() yields inner-viewport coordinates and ShipView3D's container stretches
## 1:1, so a position taken straight off an InputEvent is already in the right frame. Nothing
## here reads DisplayServer, get_window() or a global mouse position (SPEC section 10).
##
## THE GIZMO IS HIT-TESTED AGAINST ITS OWN WIREFRAME LOOPS, not against a filled disc. The
## ball surrounds the part, so a filled disc would swallow every click on the part inside it
## and the part would become unselectable the moment it was selected once. Distance is
## measured to the projected line SEGMENTS, not to their vertices, so a large ring stays
## grabbable between vertices.
##
## The handle codes returned here are `ShipPlacement.Handle` values (API_CONTRACT_SPORE
## section 8). This file deliberately depends on ShipPlacement and ShipPlacement deliberately
## does NOT depend on this one: the gizmo knows the interaction vocabulary, the interaction
## state machine does not need to know the geometry. ShipView3D, which knows both, resolves a
## morph index to its axis here and hands the axis to ShipPlacement.
##
## SOLID, NOT LINES, AND NEVER SMALLER THAN THE POINTER (2026-09-02). "the visual handle system
## is barely visible, it goes through the part rather than being visible outside the part." One
## pixel of line through a 16-colour quantizer and a Bayer dither is barely a line, and a morph
## arrow 18% of the gizmo radius long was ten pixels on a distant part. The rings are drawn as
## tubes and the arrows as prisms with cone heads ([method ring_solid], [method arrow_solid]),
## and every thickness and length has a SCREEN floor: the caller passes metres-per-pixel at the
## part's distance and the geometry is never thinner than SHAFT_PX or shorter than ARROW_PX
## whatever the zoom. The hit test is unchanged - it was always screen-space with its own slop -
## so what got bigger is what you see, and it now matches what you could already grab.
##
## THE PLACEMENT HANDLE IS A COLLAR ON THE PARENT'S SURFACE. It was a line from the parent's
## origin to the part's, i.e. entirely inside two solids. It is now [method footprint_loop]: a
## ring in the SEAM plane (the plane the part stands on, [method ShipAttach.anchor_for]) just
## wider than the part's footprint, so it sits at the base of the part on the parent's skin,
## outside the silhouette from every angle a player looks from. Grabbing it does what grabbing
## the line did - slides the part over its parent. RETIRED(2026-09-02): the parent-origin line
## as the hit region; it is drawn dim, for reference, and grabs nothing.
class_name ShipHandles
extends RefCounted

## Segments per drawn loop. 32 is enough that the projected polyline is within a pixel of the
## true circle at any framing this builder uses, and the hit test measures to segments anyway.
const RING_SEGMENTS: int = 32

## Spore's `mMorphHandles` cap. See the class docstring for why we emit six of them.
const MORPH_MAX: int = 8
const MORPH_COUNT: int = 6

## Gizmo radii as multiples of the part's own bounding radius. The ball sits just outside the
## part; the rings sit outside the ball so both can be distinguished when Tab is held.
const BALL_FACTOR: float = 1.12
const RING_FACTOR: float = 1.42

## Morph handles sit just off the part's AABB faces.
const MORPH_FACTOR: float = 1.08

## Where the offset handle sits along the part's mount axis (+Y), as a multiple of the gizmo
## radius. Outside the rings so it does not compete with them for a click.
const OFFSET_FACTOR: float = 1.72

## Arm length of a morph handle's marker, as a fraction of the gizmo radius.
const MORPH_TICK_FACTOR: float = 0.09

## Arrowhead proportions, as fractions of the shaft length. "all handles should be visible as
## they are in spore tiny 3d arrows that you grab and pull" - a cross says "a point is here", an
## arrow says "pull me, this way", and the difference is the whole reason to draw one.
const ARROW_HEAD_FRACTION: float = 0.34
const ARROW_HEAD_WIDTH: float = 0.34
## Barbs per arrowhead. Four, arranged as two crossed pairs, so the head reads as a head from any
## viewing angle instead of vanishing when the camera lines up with a flat one.
const ARROW_BARBS: int = 4

## A degenerate shape still gets a grabbable gizmo.
const MIN_RADIUS_M: float = 0.02

## The footprint collar's radius as a multiple of the part's footprint radius in the seam plane:
## just outside the part, never on its skin.
const FOOTPRINT_FACTOR: float = 1.12

## Solid gizmo proportions, as fractions of the gizmo radius, and their SCREEN floors in
## inner-viewport pixels. The larger of the two wins, so a big part gets a gizmo in proportion
## and a small or distant one still gets something a pointer can find.
const SHAFT_FRACTION: float = 0.015
const HEAD_FRACTION: float = 0.05
const ARROW_FRACTION: float = 0.22
const TUBE_FRACTION: float = 0.012
const SHAFT_PX: float = 1.5
const HEAD_PX: float = 4.5
const ARROW_PX: float = 26.0
const TUBE_PX: float = 1.5

## Facets round a shaft, a cone head and a ring tube. Few: the console is 1280x800 through a
## 16-colour quantizer, and a hexagonal prism reads as a rod at that size.
const SHAFT_SIDES: int = 6
const HEAD_SIDES: int = 8
const TUBE_SIDES: int = 6
## The cone head's length, as a multiple of its radius.
const HEAD_LENGTH_FACTOR: float = 2.2

## Pointer slop, in pixels of the inner viewport.
const HIT_PX: float = 9.0
## Morph handles are points rather than loops, so they get a slightly wider target.
const MORPH_HIT_PX: float = 11.0

## Keys of the hit_test() result. Stated here because a dictionary whose NAME is pinned and
## whose SHAPE is not is the one contract defect that has already cost this project time
## (docs/FOLLOWUPS.md F0).
##   handle:      int, a ShipPlacement.Handle value
##   index:       int, the morph handle index for Handle.MORPH, else -1
##   distance_px: float, pointer distance in inner-viewport pixels, INF on a miss
const HIT_HANDLE: String = "handle"
const HIT_INDEX: String = "index"
const HIT_DISTANCE: String = "distance_px"

## Below this a projected segment is a point.
const MIN_SEGMENT_SQ: float = 1.0e-9


## A 3D ARROW as line-segment pairs: a shaft from `tail` to `tip`, plus barbs swept back from
## the tip. In whatever frame the caller is drawing in - this is pure geometry.
##
## The barbs are built against an arbitrary perpendicular rather than a fixed world axis, so an
## arrow pointing straight up gets a head exactly as wide as one pointing sideways.
static func arrow_lines(tail: Vector3, tip: Vector3) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var shaft: Vector3 = tip - tail
	var length: float = shaft.length()
	if length <= 0.0:
		return out
	out.append(tail)
	out.append(tip)
	var dir: Vector3 = shaft / length
	var u: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	u = (u - dir * dir.dot(u)).normalized()
	var v: Vector3 = dir.cross(u)
	var back: Vector3 = tip - dir * (length * ARROW_HEAD_FRACTION)
	var width: float = length * ARROW_HEAD_WIDTH * 0.5
	for i: int in ARROW_BARBS:
		var t: float = TAU * float(i) / float(ARROW_BARBS)
		out.append(tip)
		out.append(back + (u * cos(t) + v * sin(t)) * width)
	return out


## A solid 3D arrow as a TRIANGLE list (three vertices per triangle, for an ImmediateMesh
## PRIMITIVE_TRIANGLES surface): a SHAFT_SIDES prism from `tail` to the neck, a HEAD_SIDES cone
## from the neck to `tip`, both capped. `shaft_r` and `head_r` are metres; see
## [method shaft_radius] and [method head_radius] for the screen-floored values.
static func arrow_solid(
	tail: Vector3, tip: Vector3, shaft_r: float, head_r: float
) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var shaft: Vector3 = tip - tail
	var length: float = shaft.length()
	if length <= 0.0:
		return out
	var dir: Vector3 = shaft / length
	var head_len: float = minf(head_r * HEAD_LENGTH_FACTOR, length * 0.6)
	var neck: Vector3 = tip - dir * head_len
	var frame: Array[Vector3] = _perpendicular_frame(dir)
	var u: Vector3 = frame[0]
	var v: Vector3 = frame[1]
	# The shaft, with a cap at the tail so a stalk seen end-on is a disc and not a hole.
	var tail_ring: PackedVector3Array = _ring_points(tail, u, v, shaft_r, SHAFT_SIDES)
	var neck_ring: PackedVector3Array = _ring_points(neck, u, v, shaft_r, SHAFT_SIDES)
	_append_band(out, tail_ring, neck_ring)
	_append_fan(out, tail, tail_ring, true)
	# The head: a cone on a base disc wider than the shaft.
	var base_ring: PackedVector3Array = _ring_points(neck, u, v, head_r, HEAD_SIDES)
	_append_fan(out, neck, base_ring, true)
	_append_fan(out, tip, base_ring, false)
	return out


## A closed loop of points as a solid TUBE of radius `tube_r`, as a triangle list. The tube's
## cross-section frame is taken from the loop's own plane, so a ring's tube never twists.
static func tube_solid(loop: PackedVector3Array, tube_r: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var n: int = loop.size()
	if n < 3:
		return out
	var plane_n: Vector3 = (loop[1] - loop[0]).cross(loop[2] - loop[0])
	if plane_n.length_squared() <= MIN_SEGMENT_SQ:
		plane_n = Vector3.UP
	plane_n = plane_n.normalized()
	var rings: Array[PackedVector3Array] = []
	for i: int in n:
		var tangent: Vector3 = loop[(i + 1) % n] - loop[(i - 1 + n) % n]
		if tangent.length_squared() <= MIN_SEGMENT_SQ:
			tangent = Vector3.BACK
		tangent = tangent.normalized()
		# u = the plane normal, which is perpendicular to every tangent of a planar loop; v
		# closes the frame. Both vary smoothly round the loop, so adjacent rings line up.
		var u: Vector3 = plane_n
		var v: Vector3 = tangent.cross(u).normalized()
		rings.append(_ring_points(loop[i], u, v, tube_r, TUBE_SIDES))
	for i: int in n:
		_append_band(out, rings[i], rings[(i + 1) % n])
	return out


## One rotation ring as a solid tube in the part's local frame.
static func ring_solid(
	shape: ResolvedShape, handle: int, rot: Vector3, tube_r: float
) -> PackedVector3Array:
	return tube_solid(ring_loop(shape, handle, rot), tube_r)


## Screen-floored gizmo dimensions. `m_per_px` is metres per inner-viewport pixel at the part's
## distance from the camera (0 disables the floor, e.g. before the first camera frame).
static func shaft_radius(shape: ResolvedShape, m_per_px: float) -> float:
	return maxf(gizmo_radius(shape) * SHAFT_FRACTION, SHAFT_PX * maxf(m_per_px, 0.0))


static func head_radius(shape: ResolvedShape, m_per_px: float) -> float:
	return maxf(gizmo_radius(shape) * HEAD_FRACTION, HEAD_PX * maxf(m_per_px, 0.0))


static func arrow_length(shape: ResolvedShape, m_per_px: float) -> float:
	return maxf(gizmo_radius(shape) * ARROW_FRACTION, ARROW_PX * maxf(m_per_px, 0.0))


static func tube_radius(shape: ResolvedShape, m_per_px: float) -> float:
	return maxf(gizmo_radius(shape) * TUBE_FRACTION, TUBE_PX * maxf(m_per_px, 0.0))


## The part's bounding radius in its own local frame, SCALED. Taken from local_aabb() rather
## than from ResolvedShape.bound_radius so the gizmo tracks a stretched part exactly the way
## the preview mesh does - the instance basis carries `scale`, and so must the gizmo.
static func gizmo_radius(shape: ResolvedShape) -> float:
	if shape == null:
		return MIN_RADIUS_M
	return maxf(shape.local_aabb().size.length() * 0.5, MIN_RADIUS_M)


static func ball_radius(shape: ResolvedShape) -> float:
	return gizmo_radius(shape) * BALL_FACTOR


static func ring_radius(shape: ResolvedShape) -> float:
	return gizmo_radius(shape) * RING_FACTOR


## Arm length of the cross drawn at each morph handle.
static func morph_tick(shape: ResolvedShape) -> float:
	return gizmo_radius(shape) * MORPH_TICK_FACTOR


## The axis a rotation ring spins about, in the PART's local frame. Vector3.ZERO for a handle
## code that is not a ring.
## The MOUNT-frame axis a ring handle drives. Not the axis it is drawn around - see
## [method ring_axis_local], which is the one geometry must use.
static func ring_axis(handle: int) -> Vector3:
	if handle == ShipPlacement.Handle.RING_X:
		return Vector3.RIGHT
	if handle == ShipPlacement.Handle.RING_Y:
		return Vector3.UP
	if handle == ShipPlacement.Handle.RING_Z:
		return Vector3.BACK
	return Vector3.ZERO


## The axis a ring handle ACTUALLY turns the part about, expressed in the PART's local frame.
##
## [b]THE RINGS USED TO LIE.[/b] They were drawn about the part's own local X/Y/Z while `rot.x/y/z`
## turn the part about the MOUNT frame's axes, and those differ by the fixed 90-degree alignment
## term that stands a Y-major primitive up along the surface normal (ADR 0004). Measured: RING_Y
## was drawn about world (1,0,0) and turned the part about (0,0,-1); RING_Z was drawn about
## (0,0,1) and turned it about (1,0,0). Two of the three circles rotated the part about something
## other than the circle you grabbed. Reported as "they ALL spin the part around its placement
## vector".
##
## THE DERIVATION. The part's basis is `F * Rz * Ry * Rx'`, where F is the mount frame and
## `Rx' = Rx(rot.x + 90)`. Because the composition is intrinsic, each component turns about a
## different world axis - `rot.z` about `F*e_z`, `rot.y` about `F*Rz*e_y`, `rot.x` about
## `F*Rz*Ry*e_x`. Pushing each back through the part basis collapses almost everything:
##
##   local X axis = e_x                     (unchanged)
##   local Y axis = Rx'^-1 * e_y
##   local Z axis = Rx'^-1 * Ry^-1 * e_z
##
## which is what this returns. Both the drawn loop and the hit test use it, so they cannot drift
## apart again.
static func ring_axis_local(handle: int, rot: Vector3) -> Vector3:
	var inv_x: Basis = Basis(Vector3.RIGHT, -deg_to_rad(rot.x + ShipAttach.MOUNT_ALIGN_DEG))
	if handle == ShipPlacement.Handle.RING_X:
		return Vector3.RIGHT
	if handle == ShipPlacement.Handle.RING_Y:
		return (inv_x * Vector3.UP).normalized()
	if handle == ShipPlacement.Handle.RING_Z:
		var inv_y: Basis = Basis(Vector3.UP, -deg_to_rad(rot.y))
		return (inv_x * (inv_y * Vector3.BACK)).normalized()
	return Vector3.ZERO


## The three ring handle codes, in draw order.
static func ring_handles() -> PackedInt32Array:
	return PackedInt32Array(
		[ShipPlacement.Handle.RING_X, ShipPlacement.Handle.RING_Y, ShipPlacement.Handle.RING_Z]
	)


## A closed circle of RING_SEGMENTS points about `axis`, in the part's local frame. The caller
## closes the loop (last point back to first); no duplicate vertex is emitted.
static func circle_points(axis: Vector3, radius: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var n: Vector3 = axis
	if n.length_squared() <= 0.0:
		return out
	n = n.normalized()
	var u: Vector3 = Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	u = (u - n * n.dot(u)).normalized()
	var v: Vector3 = n.cross(u)
	for i: int in RING_SEGMENTS:
		var t: float = TAU * float(i) / float(RING_SEGMENTS)
		out.append(u * (cos(t) * radius) + v * (sin(t) * radius))
	return out


## The ball handle's three great circles, in the part's local frame, as three loops.
static func ball_loops(shape: ResolvedShape) -> Array[PackedVector3Array]:
	var r: float = ball_radius(shape)
	var out: Array[PackedVector3Array] = []
	out.append(circle_points(Vector3.RIGHT, r))
	out.append(circle_points(Vector3.UP, r))
	out.append(circle_points(Vector3.BACK, r))
	return out


## One rotation ring's loop, in the part's local frame. Empty for a non-ring handle code.
## A ring's drawn circle, in the part's local frame. `rot` is the part's stored orientation and
## is what makes the circle sit on the axis the handle really turns (see ring_axis_local).
static func ring_loop(shape: ResolvedShape, handle: int, rot: Vector3) -> PackedVector3Array:
	return circle_points(ring_axis_local(handle, rot), ring_radius(shape))


## The direction a morph handle deforms along, in the part's local frame. Vector3.ZERO when
## `index` is outside [0, MORPH_COUNT).
static func morph_axis(index: int) -> Vector3:
	var axes: Array[Vector3] = [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
	]
	if index < 0 or index >= axes.size():
		return Vector3.ZERO
	return axes[index]


## Where the morph handles sit, in the part's local frame: the six face centres of the SCALED
## local AABB, pushed out by MORPH_FACTOR so they read as handles rather than as surface dirt.
## Deterministic and index-aligned with morph_axis().
static func morph_points(shape: ResolvedShape) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	if shape == null:
		return out
	var half: Vector3 = shape.local_aabb().size * 0.5 * MORPH_FACTOR
	for i: int in MORPH_COUNT:
		var axis: Vector3 = morph_axis(i)
		out.append(Vector3(axis.x * half.x, axis.y * half.y, axis.z * half.z))
	return out


## The offset handle's position in the part's local frame: straight out along +Y, which is the
## axis the part stands on (ADR 0004 - the mount frame's +Z is the surface normal, and the fixed
## alignment term puts the part's own +Y along it). Dragging it slides the part along that normal.
static func offset_point(shape: ResolvedShape) -> Vector3:
	return Vector3(0.0, gizmo_radius(shape) * OFFSET_FACTOR, 0.0)


## Where the offset stalk STARTS: on the part's +Y face rather than at its origin, so the drawn
## arrow is the part of the stalk that is outside the part. RETIRED(2026-09-02): the stalk from
## the origin, most of which was inside the solid.
static func offset_tail(shape: ResolvedShape) -> Vector3:
	if shape == null:
		return Vector3.ZERO
	return Vector3(0.0, shape.local_aabb().size.y * 0.5 * MORPH_FACTOR, 0.0)


## The placement handle: a closed loop in the SEAM plane, in the part's local frame.
##
## `seam_local` is the seam frame carried into the part's frame - origin on the parent's
## surface where the part stands, `basis.z` the mount normal there. The loop is a circle about
## that axis, FOOTPRINT_FACTOR wider than the part's footprint ([method footprint_radius]), so it
## reads as a collar round the base of the part on the parent's skin. Drawn and hit-tested from
## this one function.
static func footprint_loop(shape: ResolvedShape, seam_local: Transform3D) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	var axis: Vector3 = seam_local.basis.z
	if shape == null or axis.length_squared() <= MIN_SEGMENT_SQ:
		return out
	var r: float = footprint_radius(shape, seam_local)
	var circle: PackedVector3Array = circle_points(axis, r)
	for p: Vector3 in circle:
		out.append(seam_local.origin + p)
	return out


## The part's footprint radius in the seam plane: how far its scaled AABB reaches from the seam
## axis, measured across the plane. Never below MIN_RADIUS_M.
static func footprint_radius(shape: ResolvedShape, seam_local: Transform3D) -> float:
	if shape == null:
		return MIN_RADIUS_M
	var axis: Vector3 = seam_local.basis.z
	if axis.length_squared() <= MIN_SEGMENT_SQ:
		return gizmo_radius(shape)
	axis = axis.normalized()
	var box: AABB = shape.local_aabb()
	var reach: float = 0.0
	for i: int in 8:
		var d: Vector3 = box.get_endpoint(i) - seam_local.origin
		var across: Vector3 = d - axis * d.dot(axis)
		reach = maxf(reach, across.length())
	return maxf(reach * FOOTPRINT_FACTOR, MIN_RADIUS_M)


## Which handle is under `pointer`?
##
## `xform` is the part's ship-space transform (rigid - the scale lives in the geometry this
## file derives from local_aabb()), `pointer` an inner-viewport position straight off an
## InputEvent.
##
## Order of precedence when several handles overlap on screen: the offset handle first, then the
## morph handles (small and specific), then the rings (large targets that would otherwise swallow
## everything inside them).
##
## Returns the HIT_* dictionary above; HIT_HANDLE is Handle.NONE and HIT_DISTANCE is INF on a
## miss, so a caller can compare distances without branching on a sentinel.
static func hit_test(
	camera: Camera3D,
	xform: Transform3D,
	shape: ResolvedShape,
	pointer: Vector2,
	rot: Vector3 = Vector3.ZERO,
	seam_local: Transform3D = Transform3D.IDENTITY,
	has_seam: bool = false
) -> Dictionary:
	var miss: Dictionary = {HIT_HANDLE: ShipPlacement.Handle.NONE, HIT_INDEX: -1, HIT_DISTANCE: INF}
	if camera == null or shape == null:
		return miss
	var offset: Dictionary = _hit_offset(camera, xform, shape, pointer)
	if float(offset[HIT_DISTANCE]) <= MORPH_HIT_PX:
		return offset
	var morph: Dictionary = _hit_morph(camera, xform, shape, pointer)
	if float(morph[HIT_DISTANCE]) <= MORPH_HIT_PX:
		return morph
	# The rings are tested BEFORE the placement collar. When the old placement ARROW won ties
	# against the rings it crossed, a grab on a ring at the crossing became a placement drag,
	# and a "rotation" that then wandered off the silhouette deleted the part (F13). The collar
	# sits at the base of the part and only meets a ring where a ring dips to the surface, so
	# the tie is rarer now - and still decided the same way.
	var ring: Dictionary = _hit_rings(camera, xform, shape, pointer, rot)
	if float(ring[HIT_DISTANCE]) <= HIT_PX:
		return ring
	var placement: Dictionary = _hit_placement(camera, xform, shape, pointer, seam_local, has_seam)
	return placement if float(placement[HIT_DISTANCE]) <= HIT_PX else miss


## The placement handle: the footprint collar on the parent's surface ([method footprint_loop]),
## tested as a loop exactly like a rotation ring. The root has no seam and misses.
## RETIRED(2026-09-02): the parent-origin -> part-origin segment as the hit region.
static func _hit_placement(
	camera: Camera3D,
	xform: Transform3D,
	shape: ResolvedShape,
	pointer: Vector2,
	seam_local: Transform3D,
	has_seam: bool
) -> Dictionary:
	var miss: Dictionary = {HIT_HANDLE: ShipPlacement.Handle.NONE, HIT_INDEX: -1, HIT_DISTANCE: INF}
	if not has_seam:
		return miss
	var d: float = _loop_distance(camera, xform, footprint_loop(shape, seam_local), pointer)
	if d == INF:
		return miss
	return {HIT_HANDLE: ShipPlacement.Handle.PLACEMENT, HIT_INDEX: -1, HIT_DISTANCE: d}


## The offset handle is a single point and is tested FIRST: it sits outside the rings, so on a
## near-edge-on view its projection can land on one, and the more specific target should win.
static func _hit_offset(
	camera: Camera3D, xform: Transform3D, shape: ResolvedShape, pointer: Vector2
) -> Dictionary:
	var world: Vector3 = xform * offset_point(shape)
	if camera.is_position_behind(world):
		return {HIT_HANDLE: ShipPlacement.Handle.NONE, HIT_INDEX: -1, HIT_DISTANCE: INF}
	var screen: Vector2 = camera.unproject_position(world)
	return {
		HIT_HANDLE: ShipPlacement.Handle.OFFSET,
		HIT_INDEX: 0,
		HIT_DISTANCE: screen.distance_to(pointer),
	}


# ---------------------------------------------------------------- internals


static func _hit_ball(
	camera: Camera3D, xform: Transform3D, shape: ResolvedShape, pointer: Vector2
) -> Dictionary:
	var best: float = INF
	for loop: PackedVector3Array in ball_loops(shape):
		best = minf(best, _loop_distance(camera, xform, loop, pointer))
	return {HIT_HANDLE: ShipPlacement.Handle.BALL_ROTATE, HIT_INDEX: -1, HIT_DISTANCE: best}


static func _hit_rings(
	camera: Camera3D, xform: Transform3D, shape: ResolvedShape, pointer: Vector2, rot: Vector3
) -> Dictionary:
	var best_handle: int = ShipPlacement.Handle.NONE
	var best: float = INF
	for handle: int in ring_handles():
		var d: float = _loop_distance(camera, xform, ring_loop(shape, handle, rot), pointer)
		if d < best:
			best = d
			best_handle = handle
	return {HIT_HANDLE: best_handle, HIT_INDEX: -1, HIT_DISTANCE: best}


static func _hit_morph(
	camera: Camera3D, xform: Transform3D, shape: ResolvedShape, pointer: Vector2
) -> Dictionary:
	var best_index: int = -1
	var best: float = INF
	var points: PackedVector3Array = morph_points(shape)
	for i: int in points.size():
		var world: Vector3 = xform * points[i]
		if camera.is_position_behind(world):
			continue
		var d: float = camera.unproject_position(world).distance_to(pointer)
		if d < best:
			best = d
			best_index = i
	return {HIT_HANDLE: ShipPlacement.Handle.MORPH, HIT_INDEX: best_index, HIT_DISTANCE: best}


## Pointer distance to a closed local-space loop, in pixels. A loop with ANY vertex behind the
## camera is reported as a miss rather than projected: unproject_position() returns a mirrored
## garbage position for such a point and would otherwise invent a hit on the wrong side of the
## screen.
static func _loop_distance(
	camera: Camera3D, xform: Transform3D, loop: PackedVector3Array, pointer: Vector2
) -> float:
	var count: int = loop.size()
	if count < 2:
		return INF
	var screen: PackedVector2Array = PackedVector2Array()
	for p: Vector3 in loop:
		var world: Vector3 = xform * p
		if camera.is_position_behind(world):
			return INF
		screen.append(camera.unproject_position(world))
	var best: float = INF
	for i: int in count:
		best = minf(best, _segment_distance(screen[i], screen[(i + 1) % count], pointer))
	return best


static func _segment_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < MIN_SEGMENT_SQ:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- solid geometry helpers ------------------------------------------------------------------


## Two unit vectors perpendicular to `dir` and to each other, chosen the way arrow_lines()
## chooses its barb frame so a solid arrow and a line arrow face the same way.
static func _perpendicular_frame(dir: Vector3) -> Array[Vector3]:
	var u: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	u = (u - dir * dir.dot(u)).normalized()
	var v: Vector3 = dir.cross(u)
	return [u, v]


## `sides` points on a circle of radius `r` about `centre` in the (u, v) plane.
static func _ring_points(
	centre: Vector3, u: Vector3, v: Vector3, r: float, sides: int
) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in sides:
		var t: float = TAU * float(i) / float(sides)
		out.append(centre + (u * cos(t) + v * sin(t)) * r)
	return out


## The side wall between two rings of equal count, as two triangles per side.
static func _append_band(
	out: PackedVector3Array, a: PackedVector3Array, b: PackedVector3Array
) -> void:
	var n: int = mini(a.size(), b.size())
	for i: int in n:
		var j: int = (i + 1) % n
		out.append(a[i])
		out.append(b[i])
		out.append(b[j])
		out.append(a[i])
		out.append(b[j])
		out.append(a[j])


## A fan of triangles from `apex` over `ring` - a cap (apex in the ring's plane) or a cone.
## `reverse` flips the winding; the gizmo materials cull nothing, so it only matters for
## consistency.
static func _append_fan(
	out: PackedVector3Array, apex: Vector3, ring: PackedVector3Array, reverse: bool
) -> void:
	var n: int = ring.size()
	for i: int in n:
		var j: int = (i + 1) % n
		out.append(apex)
		if reverse:
			out.append(ring[j])
			out.append(ring[i])
		else:
			out.append(ring[i])
			out.append(ring[j])
