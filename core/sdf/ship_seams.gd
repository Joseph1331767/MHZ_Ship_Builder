class_name ShipSeams
extends RefCounted

## Seams - where a part meets the part it stands on, and what closes the gap. ADR 0008.
##
## SPEC section 7 wrote the construction down and left it unbuilt: "the partition is a plate of
## hull thickness lying in the joint plane (which the attach model already computes - the plane
## through P with normal N), clipped to where both solids are, with a seeded hatch SDF
## subtracted, unioned into the hull field." This file computes the plane, decides what is cut
## into it, and hands both to [ShipSdf], which does the field arithmetic. The author's words for
## the rest: "after all rooms are defined and hatches, the objects must be subtracted or added to
## each other, with a flat faced seam where they mate; that flat seam is where we will cut the
## hatch doors into, centered auto placed."
##
## ONE SEAM PER PLACED PART THAT STANDS ON ANOTHER. Every non-root doc part, every component
## instance (on its proxy shape), and every symmetry twin gets one; the inner parts of a
## component do not, because a component is one room (SPEC 6, "combining multiple into the same
## room removes all internal walls").
## RETIRED(ADR 0034, 2026-09-22): "Sibling overlaps that are not parent/child have no attach plane
## and therefore no seam" -> a JOINED pair that meets gets one wherever it stands, from the line
## between their centres ([method _sibling_seams] below). Two parts that merely intersect with no
## joint record between them still merge as they always did.
##
## THE PLANE IS THE ATTACH MODEL'S, NOT A NEW ONE. `frame.origin` is the anchor P the part was
## traced onto (or snapped to) and `frame.basis.z` is the mount normal N there, both carried
## into SHIP space by the host's transform - the same P and N [method ShipAttach.anchor_for]
## hands [method ShipAttach.local_transform], so the wall is where the part actually sits.
## `frame.basis` is [method ShipAttach.mount_frame], so a rectangular opening's height axis is
## the mount frame's +Y (toward the parent's nose at rot == 0), which is what "centred" means
## for a door: centred on the anchor, square to the seam.
##
## WHAT CLOSES THE SEAM is the joint record over the (child, host) pair, read through
## [method ShipDoc.joint_key_for]:
##   no record, or MODE_SEALED  -> MODE_WALL:    a solid plate, no opening (the author's default:
##                                               "if its 2 separate rooms, just a solid wall")
##   ShipJoint.MODE_DOORWAY     -> MODE_DOORWAY: the plate with a plain rectangular opening
##   ShipJoint.MODE_HATCHED     -> MODE_HATCHED: the plate with the hatch family's opening
##   ShipJoint.MODE_OPEN        -> MODE_OPEN:    no plate at all - the cavities merge, one room
##
## Static only, pure data in and out. Nothing here samples a field; [ShipSdf] does that with the
## records this returns. Deterministic: seams come out in [method ShipAttach.ordered_part_ids]
## order, each source immediately followed by its twin.

## Seam modes. Distinct from ShipJoint's stored vocabulary because "wall" is what the ABSENCE of a
## record means, and a stored `sealed` reads as the same thing.
const MODE_WALL: String = "wall"
const MODE_DOORWAY: String = "doorway"
const MODE_HATCHED: String = "hatched"
const MODE_OPEN: String = "open"

## Keys of a seam record.
const SEAM_CHILD: String = "child"  # String, the placed id standing on the host (may be a twin)
const SEAM_HOST: String = "host"  # String, the placed id it stands on
const SEAM_FRAME: String = "frame"  # Transform3D in SHIP space: origin = anchor, basis.z = N
const SEAM_MODE: String = "mode"  # one of MODE_*
const SEAM_HOLE: String = "hole"  # Dictionary, see HOLE_*; {} for MODE_WALL
const SEAM_STYLE: String = "style"  # one of STYLE_*

## Seam STYLES - what shape the seam is, as against SEAM_MODE, which is what closes it. The
## same three values [ShipJoint] stores (ADR 0009); named again here so nothing outside the
## core has to know that a style comes from a joint record.
## How many times [method explode_offsets] may push modules further apart before settling for
## what it managed. Each pass is cheap - a box test per pair - and a handful is plenty: travel only
## grows, so every pass strictly improves and the usual case is one or two.
const EXPLODE_RELAX_PASSES: int = 12

const STYLE_FLAT: String = ShipJoint.SEAM_FLAT
const STYLE_SMALL_FLAT_INSERT: String = ShipJoint.SEAM_SMALL_FLAT_INSERT
const STYLE_SMALL_FLAT_CUTOFF: String = ShipJoint.SEAM_SMALL_FLAT_CUTOFF
const STYLE_SMALL_NATIVE: String = ShipJoint.SEAM_SMALL_NATIVE
const STYLE_BIG_FLAT_INSERT: String = ShipJoint.SEAM_BIG_FLAT_INSERT
const STYLE_BIG_FLAT_CUTOFF: String = ShipJoint.SEAM_BIG_FLAT_CUTOFF
const STYLE_BIG_NATIVE: String = ShipJoint.SEAM_BIG_NATIVE
## RETIRED(ADR 0013, 2026-09-04): SEAM_PARENT / SEAM_CHILD, which named the two NATIVE-surface
## styles by the attach tree -> SEAM_BIG_NATIVE / SEAM_SMALL_NATIVE, which name them by which solid
## is actually bigger. The [ShipSdf] internals below still read "parent" and "child" and still mean
## the same two surfaces; only what decides which is which has moved from the tree to volume.
const STYLE_PARENT: String = ShipJoint.SEAM_BIG_NATIVE
const STYLE_CHILD: String = ShipJoint.SEAM_SMALL_NATIVE

## Keys of a hole record - the 2D profile cut through the plate, in the seam frame's XY.
const HOLE_KIND: String = "kind"  # KIND_*
const HOLE_SIZE: String = "size"  # Vector2, full width and height in metres
const HOLE_CORNER: String = "corner"  # float, corner radius of a KIND_RECT

const KIND_CIRCLE: String = "circle"
const KIND_RECT: String = "rect"
const KIND_ELLIPSE: String = "ellipse"
## The whole cross-section: no plate. Only MODE_OPEN produces it.
const KIND_ALL: String = "all"
## The other shapes a hole may take (ADR 0029): a square, an isosceles triangle (apex up the
## seam frame's Y) and a regular polygon of HOLE_SIDES sides, each drawn inside HOLE_SIZE. "the
## user should be able to choose the general shape of the door/hatch, square, rect, circ,
## ellipse, rectangle, triangle, polygon, etc."
const KIND_SQUARE: String = "square"
const KIND_TRIANGLE: String = "triangle"
const KIND_POLYGON: String = "polygon"
const VALID_HOLE_KINDS: Array = [
	KIND_CIRCLE, KIND_RECT, KIND_ELLIPSE, KIND_SQUARE, KIND_TRIANGLE, KIND_POLYGON
]
const HOLE_SIDES: String = "sides"  # int, a KIND_POLYGON's side count
const HOLE_STYLE: String = "style"  # String, one of DOOR_*: the hardware over the hole
const HOLE_BLADES: String = "blades"  # int, an iris door's blade count
const POLYGON_MIN_SIDES: int = 3
const POLYGON_MAX_SIDES: int = 12
## Points on a round hole's outline, and per rounded corner of a rectangle.
const HOLE_SEGMENTS: int = 24
const CORNER_SEGMENTS: int = 4

## DOOR STYLES (ADR 0029) - the hardware over a hole, carried under HOLE_STYLE. A doorway has
## none; a hatch has one of the three the author asked for: "a hatch that can open or close
## shutter eye style, double hung door style, and single hinge door style". [ShipDoors] builds
## them; a hatch family names its own under `style` in the pack, and a joint may override it.
const DOOR_NONE: String = "none"
const DOOR_SINGLE: String = "single"
const DOOR_DOUBLE: String = "double"
const DOOR_IRIS: String = "iris"
const VALID_DOORS: Array = [DOOR_NONE, DOOR_SINGLE, DOOR_DOUBLE, DOOR_IRIS]

## The keys a joint's `hatch_params` may carry OVER its family's preset (ADR 0029): a shape and
## a style by name, a size as width/height or as a radius, a corner radius, a side count, a
## blade count. Only what the player set is stored - a preset's defaults are never written into
## a document, which is what keeps every file hashing as it did.
const PARAM_SHAPE: String = "shape"
const PARAM_STYLE: String = "style"
const PARAM_WIDTH: String = "width"
const PARAM_HEIGHT: String = "height"
const PARAM_RADIUS: String = "radius"
const PARAM_CORNER: String = "corner_radius"
const PARAM_SIDES: String = "sides"
const PARAM_BLADES: String = "leaves"
const PARAM_PETALS: String = "petal_count"

## Corner rounding of a plain doorway, in metres. A doorway is a frame, not a cargo cutout.
const DOORWAY_CORNER_M: float = 0.1

## Hatch families whose opening is described by an oval rather than a rectangle or a circle.
const OVAL_FAMILIES: Array = ["sliding_oval"]

## Below this a Vector2 is treated as zero length.
const MIN_LENGTH_SQ: float = 1.0e-20

## Steps along the line between two siblings' centres when a seam is looked for there, and the
## bisections that sharpen each crossing afterwards. Coarse walk, exact finish: 48 steps cannot
## miss a solid the pair could plausibly share, and 20 bisections put the plane inside a
## ten-thousandth of the span (ADR 0034).
const SIBLING_WALK_STEPS: int = 48
const SIBLING_REFINE_STEPS: int = 20


## Every seam in the placed ship, in deterministic order. See the class docs for what a seam is.
## `shapes` and `xforms` are the attach pass's results ([method ShipAttach.resolve_shapes] and
## [method ShipAttach.resolve_all_from_shapes]); `data` supplies hatch family defaults and may be
## null, in which case every hatched seam falls back to a doorway-sized opening.
static func seams(
	doc: ShipDoc, shapes: Dictionary, xforms: Dictionary, cfg: ShipConfig, data: ShipData
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if doc == null or cfg == null:
		return out
	var plane: String = doc.symmetry_plane
	for id: String in ShipAttach.ordered_part_ids(doc):
		if id == doc.root:
			continue
		var part: ShipPart = doc.parts[id]
		var host: String = part.parent
		if host.is_empty() or not xforms.has(id) or not xforms.has(host):
			continue
		var host_shape_v: Variant = shapes.get(host)
		if not (host_shape_v is ResolvedShape):
			# A host with no traceable surface has no plane to lay a wall in.
			continue
		var host_shape: ResolvedShape = host_shape_v
		var anchor: Dictionary = ShipAttach.anchor_for(host_shape, part, cfg)
		var pos: Vector3 = anchor["pos"]
		var normal: Vector3 = anchor["normal"]
		var host_xform: Transform3D = xforms[host]
		var local: Transform3D = Transform3D(ShipAttach.mount_frame(normal), pos)
		var frame: Transform3D = host_xform * local
		var mode: String = mode_for(doc, id, host)
		var joint: ShipJoint = _joint_for(doc, id, host)
		var hole: Dictionary = hole_for(mode, joint, data, cfg)
		var style: String = joint.seam_style if joint != null else STYLE_FLAT
		out.append(_record(id, host, frame, mode, hole, style))
		var twin: String = ShipSymmetry.twin_id(id)
		if not xforms.has(twin):
			continue
		# The twin stands on the host's twin when the host has one; a host sitting on the
		# symmetry plane has none, and the twin stands on the host itself.
		var host_twin: String = ShipSymmetry.twin_id(host)
		var twin_host: String = host_twin if xforms.has(host_twin) else host
		out.append(_record(twin, twin_host, ShipMirror.reflect(frame, plane), mode, hole, style))
	# The INNER seams of every component instance (ADR 0024): each inner part on the inner part
	# it hangs from - the definition root's children on the instance itself, which stands for
	# that root. Their mode, hole and style come from the definition's own joints (ADR 0025),
	# exactly as a document part's come from the document's.
	var keys: Array = xforms.keys()
	keys.sort()
	for key_v: Variant in keys:
		var key: String = str(key_v)
		if not ShipComponents.is_expanded_id(key) or ShipSymmetry.is_twin_id(key):
			continue
		var inner_part: ShipPart = ShipComponents.inner_part(doc, key)
		var host: String = ShipComponents.inner_host_key(doc, key)
		if inner_part == null or host.is_empty() or not xforms.has(host):
			continue
		var host_shape_v: Variant = shapes.get(host)
		if not (host_shape_v is ResolvedShape):
			continue
		var anchor: Dictionary = ShipAttach.anchor_for(
			host_shape_v as ResolvedShape, inner_part, cfg
		)
		var local: Transform3D = Transform3D(
			ShipAttach.mount_frame(anchor["normal"]), anchor["pos"] as Vector3
		)
		var frame: Transform3D = (xforms[host] as Transform3D) * local
		var mode: String = mode_for(doc, key, host)
		var joint: ShipJoint = _joint_for(doc, key, host)
		var hole: Dictionary = hole_for(mode, joint, data, cfg)
		var style: String = joint.seam_style if joint != null else STYLE_FLAT
		out.append(_record(key, host, frame, mode, hole, style))
		var twin: String = ShipSymmetry.twin_id(key)
		if not xforms.has(twin):
			continue
		var host_twin: String = ShipSymmetry.twin_id(host)
		var twin_host: String = host_twin if xforms.has(host_twin) else host
		out.append(_record(twin, twin_host, ShipMirror.reflect(frame, plane), mode, hole, style))
	out.append_array(_sibling_seams(doc, shapes, xforms, cfg, data, out))
	return out


## SIBLING SEAMS (ADR 0034) - the seams of every JOINED PAIR that the two passes above cannot see,
## because neither part stands on the other. Anchored parts ring the beacon side by side (ADR 0033)
## and a nucleus laid out that way has no parent-child link to carry its links at all: without this,
## its bodies read as separate rooms that happen to intersect, each shelled and walled against the
## others. RESOLVES the limitation FOLLOWUPS F19 recorded as "seams only exist parent -> child".
##
## THE LINK IS THE JOINT RECORD, never mere contact: two parts that grew into each other with no
## joint between them stay as they were, so nothing any existing document holds changes meaning.
## The pairs come from the document's joints and from every placed instance's definition joints
## (ADR 0025), which is where a component's internal links live.
##
## THE FRAME sits in the MIDDLE OF THE OVERLAP, on the line between the two centres, its Z pointing
## at the child - the plane a wall would stand in, and the direction the explode pulls along. HOST
## IS THE ONE PLACED FIRST, so the explode's host chains stay acyclic (its walk would otherwise
## stall on a ring of sibling seams and leave the whole clump unmoved).
static func _sibling_seams(
	doc: ShipDoc,
	shapes: Dictionary,
	xforms: Dictionary,
	cfg: ShipConfig,
	data: ShipData,
	placed_seams: Array[Dictionary]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for seam: Dictionary in placed_seams:
		seen[ShipDoc.joint_key_for(str(seam[SEAM_CHILD]), str(seam[SEAM_HOST]))] = true
	var rank: Dictionary = _placement_rank(doc, xforms)
	var plane: String = doc.symmetry_plane
	for pair: PackedStringArray in _joined_pairs(doc, xforms):
		var a: String = pair[0]
		var b: String = pair[1]
		var host: String = a if int(rank.get(a, 0)) <= int(rank.get(b, 0)) else b
		var child: String = b if host == a else a
		if seen.has(ShipDoc.joint_key_for(child, host)):
			continue
		var found: Dictionary = _sibling_frame(shapes, xforms, child, host)
		if found.is_empty():
			continue
		var frame: Transform3D = found[SEAM_FRAME]
		seen[ShipDoc.joint_key_for(child, host)] = true
		var mode: String = mode_for(doc, child, host)
		var joint: ShipJoint = _joint_for(doc, child, host)
		var hole: Dictionary = hole_for(mode, joint, data, cfg)
		var style: String = joint.seam_style if joint != null else STYLE_FLAT
		out.append(_record(child, host, frame, mode, hole, style))
		var twin_child: String = ShipSymmetry.twin_id(child)
		var twin_host: String = ShipSymmetry.twin_id(host)
		if not xforms.has(twin_child):
			continue
		if not xforms.has(twin_host):
			twin_host = host
		out.append(
			_record(twin_child, twin_host, ShipMirror.reflect(frame, plane), mode, hole, style)
		)
	return out


## Every placed pair that carries a joint record, lowest id first, in deterministic order: the
## document's own joints, then the definition joints of every placed instance mapped onto its
## expanded keys (the definition's root is the instance itself - it has no key of its own).
static func _joined_pairs(doc: ShipDoc, xforms: Dictionary) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var seen: Dictionary = {}
	var ids: Array = doc.joints.keys()
	ids.sort()
	for jid: Variant in ids:
		var joint: ShipJoint = doc.joints[jid]
		_add_pair(out, seen, xforms, joint.a, joint.b)
	var keys: Array = xforms.keys()
	keys.sort()
	for key_v: Variant in keys:
		var key: String = str(key_v)
		if ShipSymmetry.is_twin_id(key):
			continue
		var part: ShipPart = doc.part_at(key)
		if part == null and ShipComponents.is_expanded_id(key):
			part = ShipComponents.inner_part(doc, key)
		if part == null or part.kind != ShipPart.KIND_COMPONENT_INSTANCE:
			continue
		var definition: Dictionary = doc.components.get(part.family, {})
		var root_inner: String = str(definition.get("root", ""))
		var stored: Dictionary = definition.get("joints", {})
		var joint_keys: Array = stored.keys()
		joint_keys.sort()
		for jkey: Variant in joint_keys:
			var record: Variant = stored[jkey]
			if not (record is Dictionary):
				continue
			var joint: ShipJoint = ShipJoint.from_dict(str(jkey), record)
			_add_pair(
				out,
				seen,
				xforms,
				_expanded_key(key, joint.a, root_inner),
				_expanded_key(key, joint.b, root_inner)
			)
	return out


## The placed key of the inner part [param inner] of the instance at [param key]: the instance
## itself for the definition's root, which has no key of its own.
static func _expanded_key(key: String, inner: String, root_inner: String) -> String:
	return key if inner == root_inner else key + "/" + inner


## Append the placed pair ([param a], [param b]) once, lowest id first - skipping a pair that is
## not placed, names one part twice, or has already been recorded.
static func _add_pair(
	out: Array[PackedStringArray], seen: Dictionary, xforms: Dictionary, a: String, b: String
) -> void:
	if a == b or not xforms.has(a) or not xforms.has(b):
		return
	var key: String = ShipDoc.joint_key_for(a, b)
	if seen.has(key):
		return
	seen[key] = true
	out.append(PackedStringArray([a, b]) if a <= b else PackedStringArray([b, a]))


## Where each placed id stands in the order the attach pass built it: doc parts in tree order,
## then the expanded inner parts. Only the ORDER matters - it decides which of two siblings is the
## host, and an instance always outranks its own inner parts.
static func _placement_rank(doc: ShipDoc, xforms: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var next: int = 0
	for id: String in ShipAttach.ordered_part_ids(doc):
		if xforms.has(id):
			out[id] = next
			next += 1
	var keys: Array = xforms.keys()
	keys.sort()
	for key_v: Variant in keys:
		var key: String = str(key_v)
		if not out.has(key):
			out[key] = next
			next += 1
	return out


## The seam frame between two parts that merely overlap: the middle of the overlap along the line
## from the host's centre to the child's, Z pointing at the child. An identity transform when the
## two do not share space at all, which is the caller's signal to emit nothing.
##
## Returns `{SEAM_FRAME: Transform3D}`, or `{}` for a pair that does not meet. A DICTIONARY rather
## than a sentinel transform: the identity IS a legal answer here - two bodies on the world Z axis
## whose seam falls on the origin, which a ship built around a beacon makes ordinary - and reporting
## it as "nothing found" would drop that seam silently.
##
## THE LINE OF CENTRES IS THE WHOLE MODEL. A pair with no attach between them has no mount normal
## to borrow, and the line between what they are built around is the one direction both agree on:
## it is the axis a wall would stand square to and the way the two come apart. It is also the
## overlap test - the walk finds the child's near surface and the host's far one, and a pair whose
## solids do not meet ALONG THAT LINE gets no seam rather than an invented plane, which is the
## honest answer for two arms that cross off-centre.
static func _sibling_frame(
	shapes: Dictionary, xforms: Dictionary, child: String, host: String
) -> Dictionary:
	var child_shape_v: Variant = shapes.get(child)
	var host_shape_v: Variant = shapes.get(host)
	if not (child_shape_v is ResolvedShape) or not (host_shape_v is ResolvedShape):
		return {}
	var child_shape: ResolvedShape = child_shape_v
	var host_shape: ResolvedShape = host_shape_v
	var child_xform: Transform3D = xforms[child]
	var host_xform: Transform3D = xforms[host]
	if not (child_xform * child_shape.local_aabb()).intersects(
		host_xform * host_shape.local_aabb()
	):
		return {}
	var from: Vector3 = host_xform.origin
	var axis: Vector3 = child_xform.origin - from
	if axis.length_squared() <= MIN_LENGTH_SQ:
		return {}
	# PAST THE CHILD'S CENTRE, not up to it: two bodies can be fused deeply enough that the host
	# still holds the child's centre - measured on a pair of pods a metre apart on a five metre
	# span - and the host's surface in the child's direction is then further out than the child
	# itself. The walk runs to the far side of the host's own bounds, where it must have left.
	var to: Vector3 = (
		from + axis.normalized() * (axis.length() + host_shape.local_aabb().size.length())
	)
	var enter: float = _crossing(child_shape, child_xform, from, to, false)
	var leave: float = _crossing(host_shape, host_xform, from, to, true)
	if enter < 0.0 or leave < 0.0 or leave <= enter:
		return {}
	return {
		SEAM_FRAME: Transform3D(ShipAttach.mount_frame(axis.normalized()), from.lerp(to, leave))
	}


## Where the surface of [param shape] crosses the segment [param from] -> [param to], as a
## fraction of it: the first EXIT when [param leaving] - the walk starts inside the host - and the
## first ENTRY otherwise, which is the child's near surface. -1.0 when there is no crossing.
static func _crossing(
	shape: ResolvedShape, xform: Transform3D, from: Vector3, to: Vector3, leaving: bool
) -> float:
	var inv: Transform3D = xform.affine_inverse()
	# THE WALK CAN START OR END INSIDE. Two bodies fused deep enough each hold the other's centre -
	# ordinary in a nucleus, where the neighbours overlap by more than half a body - and there is
	# then no crossing to find: the overlap simply runs to that end of the line.
	if leaving and shape.sdf(inv * to) < 0.0:
		return 1.0
	if not leaving and shape.sdf(inv * from) < 0.0:
		return 0.0
	var steps: int = SIBLING_WALK_STEPS
	var previous: float = shape.sdf(inv * from)
	for i: int in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var here: float = shape.sdf(inv * from.lerp(to, t))
		var crossed: bool = (previous < 0.0) != (here < 0.0)
		if crossed and (leaving == (previous < 0.0)):
			var lo: float = float(i - 1) / float(steps)
			var hi: float = t
			for _refine: int in SIBLING_REFINE_STEPS:
				var mid: float = (lo + hi) * 0.5
				if (shape.sdf(inv * from.lerp(to, mid)) < 0.0) == (previous < 0.0):
					lo = mid
				else:
					hi = mid
			return (lo + hi) * 0.5
		previous = here
	return -1.0


## The seam style over a (child, host) pair - see [ShipJoint]'s SEAM STYLES. A pair with no
## joint record is FLAT, which is the default and what every pre-ADR-0009 file means.
static func style_for(doc: ShipDoc, child: String, host: String) -> String:
	var joint: ShipJoint = _joint_for(doc, child, host)
	return joint.seam_style if joint != null else STYLE_FLAT


## The seam mode over a (child, host) pair, from the joint record between their DOC ids. Twin
## ids resolve to their sources first, so a twin's seam is closed the way its source's is.
static func mode_for(doc: ShipDoc, child: String, host: String) -> String:
	var joint: ShipJoint = _joint_for(doc, child, host)
	if joint == null:
		return MODE_WALL
	match joint.mode:
		ShipJoint.MODE_HATCHED:
			return MODE_HATCHED
		ShipJoint.MODE_DOORWAY:
			return MODE_DOORWAY
		ShipJoint.MODE_OPEN:
			return MODE_OPEN
	return MODE_WALL


## Every parent-to-child pair with BOTH ends inside [param ids], each as `[child, host]`.
##
## What a selection of parts means when it is linked as a group: the seams that are internal to it.
## A twin resolves to its source and a pair is emitted once, so selecting two mirrored parts names
## one seam rather than two contradictory records over the same joint.
##
## Lives here rather than in the panel that asks because it is a fact about the DOCUMENT, and both
## the panel (to decide what to refuse) and the builder (to apply the step) need the same answer to
## the same question.
## The link a fresh seam between [param a] and [param b] gets by default (ADR 0027): a HATCH
## wherever a tunnel meets a module - one a hallway and the other a room, by their roles; an
## instance answers with its definition root's role - and a WALL otherwise. "all default
## pre-made ships, and any future procedurally generated ones should have hatch connections
## between each and every tunnel and linked module by default."
static func default_link_for(doc: ShipDoc, a: String, b: String) -> String:
	var ra: String = role_of(doc, a)
	var rb: String = role_of(doc, b)
	var tunnel_to_room: bool = (
		(ra == ShipPart.ROLE_HALLWAY and rb == ShipPart.ROLE_ROOM)
		or (ra == ShipPart.ROLE_ROOM and rb == ShipPart.ROLE_HALLWAY)
	)
	return MODE_HATCHED if tunnel_to_room else MODE_WALL


## The role a key plays at a seam: a part's own, an instance's definition root's.
static func role_of(doc: ShipDoc, id: String) -> String:
	if doc == null:
		return ""
	var part: ShipPart = doc.part_at(ShipSymmetry.source_of_twin(id))
	if part == null:
		return ""
	if part.kind != ShipPart.KIND_COMPONENT_INSTANCE:
		return part.role
	var definition: Dictionary = doc.components.get(part.family, {})
	var inner: Dictionary = ShipComponents.definition_parts(definition)
	var root: Variant = inner.get(str(definition.get("root", "")), null)
	return (root as ShipPart).role if root is ShipPart else part.role


## True when [param a] and [param b] are parts of ONE definition - two inner parts of an
## instance, or one and the instance itself. Their link lives in that definition (ADR 0025).
static func within_one_instance(doc: ShipDoc, a: String, b: String) -> bool:
	return not ShipComponents.inner_pair(doc, a, b).is_empty()


static func pairs_within(doc: ShipDoc, ids: PackedStringArray) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	if doc == null:
		return out
	var inside: Dictionary = {}
	for raw: String in ids:
		var id: String = ShipSymmetry.source_of_twin(raw)
		if doc.parts.has(id) or ShipComponents.inner_exists(doc, id):
			inside[id] = true
	var seen: Dictionary = {}
	for id: String in inside:
		# An inner part of an instance hangs off its inner parent, or off the instance (ADR 0024).
		var parent: String = ""
		if doc.parts.has(id):
			parent = (doc.parts[id] as ShipPart).parent
		else:
			parent = ShipComponents.inner_host_key(doc, id)
		if parent.is_empty() or not inside.has(parent):
			continue
		var key: String = ShipDoc.joint_key_for(id, parent)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(PackedStringArray([id, parent]))
	# PARTS THAT STAND SIDE BY SIDE NAME THEIR OWN PAIRS. A joint is keyed over an unordered pair,
	# not over the attach tree, and two siblings that grew into each other meet just as truly as a
	# child meets its host - whether they do is the caller's job to check (ADR 0034 gave the seam
	# pass the geometry to answer it). Two parts always pair; past two, only parts that stand on
	# NOTHING do - the bodies of a nucleus ringing the beacon, or the members of one definition -
	# so an ordinary selection of seated parts still reports its tree links and nothing else.
	var members: PackedStringArray = PackedStringArray()
	for id: String in inside:
		members.append(id)
	members.sort()
	if out.is_empty() and members.size() == 2:
		out.append(members)
		return out
	for i: int in members.size():
		for j: int in range(i + 1, members.size()):
			var pair_key: String = ShipDoc.joint_key_for(members[i], members[j])
			if seen.has(pair_key) or not _stand_apart(doc, members[i], members[j]):
				continue
			seen[pair_key] = true
			out.append(PackedStringArray([members[i], members[j]]))
	return out


## Do [param a] and [param b] stand beside each other rather than one upon the other - two parts of
## one definition, or two parts anchored to the beacon (ADR 0034)? A pair where either stands on
## something is not one of these, whether or not it stands on the other.
static func _stand_apart(doc: ShipDoc, a: String, b: String) -> bool:
	if a == b:
		return false
	if not ShipComponents.inner_pair(doc, a, b).is_empty():
		return true
	# Past this point the answer is about parts anchored to the SHIP's beacon, so two inner parts of
	# two unrelated instances are not a pair: each is anchored inside its own definition, which is
	# not the same place, and `part_at` resolves an expanded id as readily as a document one.
	if ShipComponents.is_expanded_id(a) or ShipComponents.is_expanded_id(b):
		return false
	var pa: ShipPart = doc.part_at(a)
	var pb: ShipPart = doc.part_at(b)
	if pa == null or pb == null:
		return false
	return pa.parent.is_empty() and pb.parent.is_empty()


## The link mode every pair in [param pairs] carries, or [constant MODE_WALL] when they disagree.
##
## A MIXED SELECTION UNIFIES BEFORE IT CYCLES: reporting the wall means the next step lands on
## DOORWAY for all of them, which is predictable, where reporting whichever mode the walk happened
## to see first would make the result depend on dictionary order.
static func shared_mode(doc: ShipDoc, pairs: Array[PackedStringArray]) -> String:
	var mode: String = ""
	for pair: PackedStringArray in pairs:
		if pair.size() < 2:
			continue
		var here: String = mode_for(doc, pair[0], pair[1])
		if mode.is_empty():
			mode = here
		elif here != mode:
			return MODE_WALL
	return MODE_WALL if mode.is_empty() else mode


## The opening a seam of `mode` carries, as a hole record. `joint` is read only for
## MODE_HATCHED (its hatch family and params); `data` may be null.
static func hole_for(mode: String, joint: ShipJoint, data: ShipData, cfg: ShipConfig) -> Dictionary:
	match mode:
		MODE_OPEN:
			return {HOLE_KIND: KIND_ALL}
		MODE_DOORWAY:
			return _doorway_hole(joint, cfg)
		MODE_HATCHED:
			return _hatch_hole(joint, data, cfg)
	return {}


## A doorway's opening: the configured doorway, with the shape, size and side count the joint
## stored over it (ADR 0029) - but never a door; a doorway is an opening with no hardware.
static func _doorway_hole(joint: ShipJoint, cfg: ShipConfig) -> Dictionary:
	var hole: Dictionary = _doorway(cfg)
	if joint == null:
		return hole
	var stored: Dictionary = joint.hatch_params
	if _has_number(stored, PARAM_WIDTH) and _has_number(stored, PARAM_HEIGHT):
		hole[HOLE_SIZE] = Vector2(
			maxf(float(stored[PARAM_WIDTH]), 0.0), maxf(float(stored[PARAM_HEIGHT]), 0.0)
		)
	var kind: String = _hatch_text(stored, PARAM_SHAPE, "")
	if VALID_HOLE_KINDS.has(kind):
		hole[HOLE_KIND] = kind
	if _has_number(stored, PARAM_SIDES):
		hole[HOLE_SIDES] = clampi(int(stored[PARAM_SIDES]), POLYGON_MIN_SIDES, POLYGON_MAX_SIDES)
	return hole


## Signed 2D distance from `uv` (seam-frame X, Y) to the edge of `hole`: negative inside the
## opening. An empty record is no opening (+INF everywhere); KIND_ALL is all opening (-INF).
##
## The ellipse is a scaled circle - a bound, not a true distance - which is fine here: the plate
## only asks which side of the edge a sample is on, and the bake places its vertex by the sign
## change.
static func hole_distance(hole: Dictionary, uv: Vector2) -> float:
	if hole.is_empty():
		return INF
	var kind: String = str(hole.get(HOLE_KIND, ""))
	if kind == KIND_ALL:
		return -INF
	var size: Vector2 = hole.get(HOLE_SIZE, Vector2.ZERO)
	var half: Vector2 = size * 0.5
	if kind == KIND_CIRCLE:
		return uv.length() - half.x
	if kind == KIND_ELLIPSE:
		if half.x <= 0.0 or half.y <= 0.0:
			return INF
		var scaled: Vector2 = Vector2(uv.x / half.x, uv.y / half.y)
		return (scaled.length() - 1.0) * minf(half.x, half.y)
	if kind == KIND_TRIANGLE or kind == KIND_POLYGON:
		return polygon_distance(hole_profile(hole), uv)
	# KIND_RECT and KIND_SQUARE: the rounded box.
	var corner: float = clampf(float(hole.get(HOLE_CORNER, 0.0)), 0.0, minf(half.x, half.y))
	var q: Vector2 = uv.abs() - (half - Vector2(corner, corner))
	var outside: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var inside: float = minf(maxf(q.x, q.y), 0.0)
	return outside + inside - corner


## Signed distance from [param uv] to the edge of the simple polygon [param outline]: negative
## inside. Exact for any simple polygon (the winding-number form), which is what the polygon
## and triangle holes need and what a rounded rectangle's outline also satisfies.
static func polygon_distance(outline: PackedVector2Array, uv: Vector2) -> float:
	var n: int = outline.size()
	if n < 3:
		return INF
	var d: float = INF
	var sign: float = 1.0
	var j: int = n - 1
	for i: int in n:
		var e: Vector2 = outline[j] - outline[i]
		var w: Vector2 = uv - outline[i]
		var along: float = clampf(w.dot(e) / maxf(e.dot(e), MIN_LENGTH_SQ), 0.0, 1.0)
		var b: Vector2 = w - e * along
		d = minf(d, b.dot(b))
		var above: bool = uv.y >= outline[i].y
		var below: bool = uv.y < outline[j].y
		var left: bool = e.x * w.y > e.y * w.x
		if (above and below and left) or (not above and not below and not left):
			sign = -sign
		j = i
	return sign * sqrt(d)


## [param hole]'s outline in the seam frame's XY, counter-clockwise: a round hole at
## [param segments] points, a rectangle's corners (each rounded over CORNER_SEGMENTS when it has
## a radius), a triangle's three, a polygon's HOLE_SIDES on the ellipse of HOLE_SIZE. Empty for
## no hole and for KIND_ALL, which has no edge.
static func hole_profile(hole: Dictionary, segments: int = HOLE_SEGMENTS) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if hole.is_empty():
		return out
	var kind: String = str(hole.get(HOLE_KIND, ""))
	var half: Vector2 = (hole.get(HOLE_SIZE, Vector2.ZERO) as Vector2) * 0.5
	if kind == KIND_ALL or half.x <= 0.0 or half.y <= 0.0:
		return out
	match kind:
		KIND_CIRCLE, KIND_ELLIPSE:
			_append_ellipse(out, half, maxi(segments, 3), 0.0)
		KIND_TRIANGLE:
			out.append(Vector2(-half.x, -half.y))
			out.append(Vector2(half.x, -half.y))
			out.append(Vector2(0.0, half.y))
		KIND_POLYGON:
			var sides: int = clampi(
				int(hole.get(HOLE_SIDES, 6)), POLYGON_MIN_SIDES, POLYGON_MAX_SIDES
			)
			_append_ellipse(out, half, sides, PI * 0.5)
		_:
			_append_rounded_box(out, half, float(hole.get(HOLE_CORNER, 0.0)))
	return out


## [param hole] with its size (and a rectangle's corner radius) scaled by [param scale].
static func hole_scaled(hole: Dictionary, scale: float) -> Dictionary:
	var out: Dictionary = hole.duplicate(true)
	if out.has(HOLE_SIZE):
		out[HOLE_SIZE] = (out[HOLE_SIZE] as Vector2) * scale
	if out.has(HOLE_CORNER):
		out[HOLE_CORNER] = float(out[HOLE_CORNER]) * scale
	return out


static func _append_ellipse(
	out: PackedVector2Array, half: Vector2, count: int, phase: float
) -> void:
	for i: int in count:
		var a: float = phase + TAU * float(i) / float(count)
		out.append(Vector2(half.x * cos(a), half.y * sin(a)))


static func _append_rounded_box(out: PackedVector2Array, half: Vector2, corner: float) -> void:
	var r: float = clampf(corner, 0.0, minf(half.x, half.y))
	if r <= 1.0e-6:
		out.append(Vector2(-half.x, -half.y))
		out.append(Vector2(half.x, -half.y))
		out.append(Vector2(half.x, half.y))
		out.append(Vector2(-half.x, half.y))
		return
	# Four arcs, counter-clockwise from the lower-right corner.
	var centres: Array[Vector2] = [
		Vector2(half.x - r, -half.y + r),
		Vector2(half.x - r, half.y - r),
		Vector2(-half.x + r, half.y - r),
		Vector2(-half.x + r, -half.y + r),
	]
	for k: int in 4:
		var start: float = -PI * 0.5 + PI * 0.5 * float(k)
		for i: int in CORNER_SEGMENTS + 1:
			var a: float = start + PI * 0.5 * float(i) / float(CORNER_SEGMENTS)
			out.append(centres[k] + Vector2(cos(a), sin(a)) * r)


## Every placed id that is a module of its own - a doc part, a component instance, or a twin of
## either - in deterministic order. The expanded inner parts of a component belong to their
## instance's module and are not listed. Only ids the attach pass actually placed are returned.
static func module_ids(doc: ShipDoc, xforms: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		return out
	for id: String in ShipAttach.ordered_part_ids(doc):
		if xforms.has(id):
			out.append(id)
		var twin: String = ShipSymmetry.twin_id(id)
		if xforms.has(twin):
			out.append(twin)
	return out


## The module a placed id belongs to: itself, or for an expanded inner part its instance (a
## twin's inner part maps to the instance's twin). Delegates to [ShipComponents] so the answer
## is the same one the scene builder and the attach pass give.
static func module_of(id: String) -> String:
	return ShipComponents.instance_of(id)


## EXPLODE offsets: module id -> the ship-space translation that pulls it clear of what it
## stands on. Accumulated down the host chain, so a part on a part on the hull carries both
## gaps; the root, and any module with no seam, stays put.
##
## `gap = cfg.explode_gap_m + half the child's extent along its seam normal`, the extent read
## off `boxes` (module id -> ship-space AABB): a long spar pulls further than a stud, so no
## module ends up still overlapping the one it left.
##
## [param still] (id -> true) names modules that RIDE their host instead of leaving it: no travel
## of their own, and no part in the pass that pushes overlapping modules apart. The exploded
## view's first stage (ADR 0032) passes the chunks of every room of several, so a room parts from
## its neighbours as one body before its chunks separate.
static func explode_offsets(
	seams_list: Array[Dictionary], cfg: ShipConfig, boxes: Dictionary, still: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {}
	if cfg == null:
		return out
	var gap: float = maxf(cfg.explode_gap_m, 0.0)

	# Each seam contributes one CHILD, the direction it is pulled along, and how far. Kept as a
	# record rather than folded straight into a position, because the relaxation below has to be
	# able to push a module FURTHER along its own normal - and carry everything hanging off it.
	var order: PackedStringArray = PackedStringArray()
	var host_of: Dictionary = {}
	var dir_of: Dictionary = {}
	var travel: Dictionary = {}

	# Seams arrive host-before-child (ordered_part_ids is a root-first walk, and a twin follows
	# its source), so one pass settles every chain. The retry loop is the belt to that: a doc
	# whose order is broken still converges instead of leaving a module behind.
	var pending: Array[Dictionary] = seams_list.duplicate()
	var guard: int = pending.size() + 1
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var blocked: Array[Dictionary] = []
		for seam: Dictionary in pending:
			var host: String = seam[SEAM_HOST]
			var child: String = seam[SEAM_CHILD]
			if _has_seam(seams_list, host) and not travel.has(host):
				blocked.append(seam)
				continue
			var n: Vector3 = (seam[SEAM_FRAME] as Transform3D).basis.z.normalized()
			order.append(child)
			host_of[child] = host
			dir_of[child] = n
			travel[child] = (
				0.0 if still.has(child) else gap + 0.5 * _extent_along(boxes.get(child, AABB()), n)
			)
		if blocked.size() == pending.size():
			break
		pending = blocked

	out = _positions(order, host_of, dir_of, travel)
	return _relaxed(order, host_of, dir_of, travel, boxes, gap, out, still)


## Where every module sits, walking each chain from its host outward.
static func _positions(
	order: PackedStringArray, host_of: Dictionary, dir_of: Dictionary, travel: Dictionary
) -> Dictionary:
	var out: Dictionary = {}
	for child: String in order:
		var base: Vector3 = out.get(host_of[child], Vector3.ZERO)
		out[child] = base + (dir_of[child] as Vector3) * float(travel[child])
	return out


## [param placed] with every module pushed further along its OWN seam normal until no two of them
## overlap.
##
## WHY A SECOND PASS IS NEEDED AT ALL. The travel above is the distance that clears a module from
## its HOST, which is the only thing one seam knows about. Nothing in it separates SIBLINGS, and
## two of those can be pulled in almost the same direction: the atomic templates (ADR 0014) make
## that ordinary, because a nucleus body and an extremity take their directions from two different
## arrangements that are free to point the same way. Measured before this pass, a lithium class put
## a fused nucleus body 1.40 m inside a tunnel and 2.76 m inside a pod.
##
## Pushing along each module's own normal rather than apart along the line between them is what
## keeps the view meaning what it says - every module pulled off ITS OWN seam - instead of drifting
## into a general-purpose scatter. Travel only ever grows, so this converges; the cap is there for
## a configuration it cannot separate at all, where stopping with the best it managed beats looping.
static func _relaxed(
	order: PackedStringArray,
	host_of: Dictionary,
	dir_of: Dictionary,
	travel: Dictionary,
	boxes: Dictionary,
	gap: float,
	placed: Dictionary,
	still: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = placed
	var margin: float = maxf(gap, 0.05) * 0.25
	for _pass: int in EXPLODE_RELAX_PASSES:
		var moved: bool = false
		for i: int in order.size():
			for j: int in range(i + 1, order.size()):
				var a: String = order[i]
				var b: String = order[j]
				if still.has(a) or still.has(b):
					continue
				var deep: float = _overlap_depth(boxes, out, a, b)
				if deep <= 0.0:
					continue
				moved = true
				# ONE OF THE PAIR MOVES, NOT BOTH. Two siblings can be pulled in almost the same
				# direction - the atomic templates make that ordinary - and pushing both along
				# their own normals then moves them together and never separates them at all.
				# Sending the one that is already further out further still separates them ALONG
				# that shared direction, which reads as a stack rather than a scatter. The id
				# breaks the tie so the same ship always explodes the same way.
				#
				# A CHAINED PAIR IS THE EXCEPTION, AND IT HAS TO BE: everything hanging off a
				# module travels with it, so moving the one further UP the chain moves them both
				# and closes nothing. Only the descendant can open that gap. Measured, this is
				# what a valence pod's tunnel and the proton it grows out of are (ADR 0017), and
				# the further-out rule alone left four such pairs overlapped on a carbon class.
				var push: String = ""
				if _descends_from(host_of, b, a):
					push = b
				elif _descends_from(host_of, a, b):
					push = a
				else:
					push = a
					var ta: float = travel[a]
					var tb: float = travel[b]
					if tb > ta or (is_equal_approx(ta, tb) and b > a):
						push = b
				travel[push] = float(travel[push]) + deep + margin
		# The root carries no seam and never moves, so a module can also overlap IT.
		for id: String in order:
			if still.has(id):
				continue
			var root_deep: float = _overlap_depth(boxes, out, id, _root_of(host_of, id))
			if root_deep > 0.0:
				moved = true
				travel[id] = float(travel[id]) + root_deep + margin
		if not moved:
			break
		out = _positions(order, host_of, dir_of, travel)
	return out


## Does [param id] hang off [param ancestor], at any depth?
static func _descends_from(host_of: Dictionary, id: String, ancestor: String) -> bool:
	var walk: String = id
	var guard: int = 64
	while host_of.has(walk) and guard > 0:
		guard -= 1
		walk = host_of[walk]
		if walk == ancestor:
			return true
	return false


## How deep two placed modules interpenetrate, by their boxes. Zero when they do not.
static func _overlap_depth(boxes: Dictionary, placed: Dictionary, a: String, b: String) -> float:
	if a == b or not boxes.has(a) or not boxes.has(b):
		return 0.0
	var box_a: AABB = boxes[a]
	var box_b: AABB = boxes[b]
	var one: AABB = AABB(box_a.position + (placed.get(a, Vector3.ZERO) as Vector3), box_a.size)
	var two: AABB = AABB(box_b.position + (placed.get(b, Vector3.ZERO) as Vector3), box_b.size)
	if not one.intersects(two):
		return 0.0
	var shared: AABB = one.intersection(two)
	return minf(shared.size.x, minf(shared.size.y, shared.size.z))


## The module at the top of [param id]'s chain - the one that never moves.
static func _root_of(host_of: Dictionary, id: String) -> String:
	var walk: String = id
	var guard: int = 64
	while host_of.has(walk) and guard > 0:
		guard -= 1
		walk = host_of[walk]
	return walk


# --- internals -----------------------------------------------------------------------------


static func _record(
	child: String, host: String, frame: Transform3D, mode: String, hole: Dictionary, style: String
) -> Dictionary:
	return {
		SEAM_CHILD: child,
		SEAM_HOST: host,
		SEAM_FRAME: frame,
		SEAM_MODE: mode,
		SEAM_HOLE: hole.duplicate(true),
		SEAM_STYLE: style,
	}


## The joint over the (child, host) pair's DOC ids, or null.
static func _joint_for(doc: ShipDoc, child: String, host: String) -> ShipJoint:
	# Two parts of one definition: the definition's own joint (ADR 0025).
	if not ShipComponents.inner_pair(doc, child, host).is_empty():
		return ShipComponents.inner_joint_for(doc, child, host)
	var a: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(child))
	var b: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(host))
	var key: String = ShipDoc.joint_key_for(a, b)
	var ids: Array = doc.joints.keys()
	ids.sort()
	for jid: Variant in ids:
		var joint: ShipJoint = doc.joints[jid]
		# A joint may name an inner part of an instance (ADR 0024); it matches on the instance.
		var ja: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(joint.a))
		var jb: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(joint.b))
		if ShipDoc.joint_key_for(ja, jb) == key:
			return joint
	return null


static func _doorway(cfg: ShipConfig) -> Dictionary:
	var w: float = 0.8
	var h: float = 1.9
	if cfg != null:
		w = maxf(cfg.doorway_width_m, 0.0)
		h = maxf(cfg.doorway_height_m, 0.0)
	return {
		HOLE_KIND: KIND_RECT,
		HOLE_SIZE: Vector2(w, h),
		HOLE_CORNER: DOORWAY_CORNER_M,
		HOLE_STYLE: DOOR_NONE,
	}


## The hatch's opening (ADR 0029): its SIZE from what the joint stored (a width and height, or
## a radius) over the family's own (a radius, or a width and height); its SHAPE from the joint's
## `shape` over the family's, or failing both from the size's form (a radius is a circle, an
## oval family an ellipse, anything else a rectangle); its STYLE from the joint's over the
## family's, a single hinged door failing both; a polygon's sides and an iris's blades from the
## params. A family the pack does not know opens a doorway-sized hole with a single door rather
## than nothing - a hatch the player linked must open onto something.
static func _hatch_hole(joint: ShipJoint, data: ShipData, cfg: ShipConfig) -> Dictionary:
	var hole: Dictionary = _doorway(cfg)
	hole[HOLE_STYLE] = DOOR_SINGLE
	if joint == null:
		return hole
	var entry: Dictionary = {}
	if data != null and typeof(data.hatches.get(joint.hatch_family)) == TYPE_DICTIONARY:
		entry = data.hatches[joint.hatch_family]
	var stored: Dictionary = joint.hatch_params
	var params: Dictionary = _hatch_params(entry, stored)
	var round: bool = false
	if _has_number(stored, PARAM_WIDTH) and _has_number(stored, PARAM_HEIGHT):
		hole[HOLE_SIZE] = Vector2(
			maxf(float(stored[PARAM_WIDTH]), 0.0), maxf(float(stored[PARAM_HEIGHT]), 0.0)
		)
	elif _has_number(stored, PARAM_RADIUS) or params.has(PARAM_RADIUS):
		var r: float = maxf(float(params[PARAM_RADIUS]), 0.0)
		hole[HOLE_SIZE] = Vector2(2.0 * r, 2.0 * r)
		round = true
	elif params.has(PARAM_WIDTH) and params.has(PARAM_HEIGHT):
		hole[HOLE_SIZE] = Vector2(
			maxf(float(params[PARAM_WIDTH]), 0.0), maxf(float(params[PARAM_HEIGHT]), 0.0)
		)
	var kind: String = _hatch_text(stored, PARAM_SHAPE, str(entry.get("shape", "")))
	if not VALID_HOLE_KINDS.has(kind):
		if round:
			kind = KIND_CIRCLE
		elif OVAL_FAMILIES.has(joint.hatch_family):
			kind = KIND_ELLIPSE
		else:
			kind = KIND_RECT
	hole[HOLE_KIND] = kind
	hole[HOLE_CORNER] = maxf(float(params.get(PARAM_CORNER, 0.0)), 0.0)
	hole[HOLE_SIDES] = clampi(int(params.get(PARAM_SIDES, 6)), POLYGON_MIN_SIDES, POLYGON_MAX_SIDES)
	var style: String = _hatch_text(stored, PARAM_STYLE, str(entry.get("style", "")))
	hole[HOLE_STYLE] = style if VALID_DOORS.has(style) else DOOR_SINGLE
	var blades: float = float(params.get(PARAM_BLADES, params.get(PARAM_PETALS, 6)))
	hole[HOLE_BLADES] = int(blades)
	return hole


## The string [param stored] carries under [param key], lower-cased, or [param fallback].
static func _hatch_text(stored: Dictionary, key: String, fallback: String) -> String:
	var v: Variant = stored.get(key, null)
	if v is String and not (v as String).is_empty():
		return (v as String).to_lower()
	return fallback.to_lower()


static func _has_number(d: Dictionary, key: String) -> bool:
	return d.has(key) and _is_number(d[key])


## The family's parameter defaults with the joint's own values written over them. Only numeric
## values are taken from either side.
static func _hatch_params(entry: Dictionary, stored: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var specs_v: Variant = entry.get("params", {})
	if typeof(specs_v) == TYPE_DICTIONARY:
		var specs: Dictionary = specs_v
		for name: Variant in specs:
			var spec_v: Variant = specs[name]
			if typeof(spec_v) == TYPE_DICTIONARY:
				var spec: Dictionary = spec_v
				var def: Variant = spec.get("default", null)
				if _is_number(def):
					out[str(name)] = float(def)
	for name: Variant in stored:
		var v: Variant = stored[name]
		if _is_number(v):
			out[str(name)] = float(v)
	return out


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


static func _has_seam(seams_list: Array[Dictionary], id: String) -> bool:
	for seam: Dictionary in seams_list:
		if seam[SEAM_CHILD] == id:
			return true
	return false


## The full extent of `box` projected onto unit direction `n`.
static func _extent_along(box: AABB, n: Vector3) -> float:
	if box.size == Vector3.ZERO:
		return 0.0
	return absf(n.x) * box.size.x + absf(n.y) * box.size.y + absf(n.z) * box.size.z
