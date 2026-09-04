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
## room removes all internal walls"). Sibling overlaps that are not parent/child have no attach
## plane and therefore no seam: two children of one hull that happen to intersect merge as they
## always did.
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

## Corner rounding of a plain doorway, in metres. A doorway is a frame, not a cargo cutout.
const DOORWAY_CORNER_M: float = 0.1

## Hatch families whose opening is described by an oval rather than a rectangle or a circle.
const OVAL_FAMILIES: Array = ["sliding_oval"]

## Below this a Vector2 is treated as zero length.
const MIN_LENGTH_SQ: float = 1.0e-20


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
	return out


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


## The opening a seam of `mode` carries, as a hole record. `joint` is read only for
## MODE_HATCHED (its hatch family and params); `data` may be null.
static func hole_for(mode: String, joint: ShipJoint, data: ShipData, cfg: ShipConfig) -> Dictionary:
	match mode:
		MODE_OPEN:
			return {HOLE_KIND: KIND_ALL}
		MODE_DOORWAY:
			return _doorway(cfg)
		MODE_HATCHED:
			return _hatch_hole(joint, data, cfg)
	return {}


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
	# KIND_RECT: the rounded box.
	var corner: float = clampf(float(hole.get(HOLE_CORNER, 0.0)), 0.0, minf(half.x, half.y))
	var q: Vector2 = uv.abs() - (half - Vector2(corner, corner))
	var outside: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var inside: float = minf(maxf(q.x, q.y), 0.0)
	return outside + inside - corner


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
static func explode_offsets(
	seams_list: Array[Dictionary], cfg: ShipConfig, boxes: Dictionary
) -> Dictionary:
	var out: Dictionary = {}
	if cfg == null:
		return out
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
			var host_seamed: bool = _has_seam(seams_list, host)
			if host_seamed and not out.has(host):
				blocked.append(seam)
				continue
			var frame: Transform3D = seam[SEAM_FRAME]
			var n: Vector3 = frame.basis.z.normalized()
			var base: Vector3 = out.get(host, Vector3.ZERO)
			var extent: float = _extent_along(boxes.get(child, AABB()), n)
			out[child] = base + n * (maxf(cfg.explode_gap_m, 0.0) + 0.5 * extent)
		if blocked.size() == pending.size():
			break
		pending = blocked
	return out


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
	var a: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(child))
	var b: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(host))
	var key: String = ShipDoc.joint_key_for(a, b)
	var ids: Array = doc.joints.keys()
	ids.sort()
	for jid: Variant in ids:
		var joint: ShipJoint = doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == key:
			return joint
	return null


static func _doorway(cfg: ShipConfig) -> Dictionary:
	var w: float = 0.8
	var h: float = 1.9
	if cfg != null:
		w = maxf(cfg.doorway_width_m, 0.0)
		h = maxf(cfg.doorway_height_m, 0.0)
	return {HOLE_KIND: KIND_RECT, HOLE_SIZE: Vector2(w, h), HOLE_CORNER: DOORWAY_CORNER_M}


## The hatch family's opening: a circle from `radius`, an oval or a rounded rectangle from
## `width` / `height` (`corner_radius` when it has one). Pack defaults first, then whatever the
## joint stored on top. A family the pack does not know opens a doorway-sized hole rather than
## nothing - a hatch the player linked must open onto something.
static func _hatch_hole(joint: ShipJoint, data: ShipData, cfg: ShipConfig) -> Dictionary:
	if joint == null or data == null or not data.hatches.has(joint.hatch_family):
		return _doorway(cfg)
	var entry_v: Variant = data.hatches[joint.hatch_family]
	if typeof(entry_v) != TYPE_DICTIONARY:
		return _doorway(cfg)
	var entry: Dictionary = entry_v
	var params: Dictionary = _hatch_params(entry, joint.hatch_params)
	if params.has("radius"):
		var r: float = maxf(float(params["radius"]), 0.0)
		return {HOLE_KIND: KIND_CIRCLE, HOLE_SIZE: Vector2(2.0 * r, 2.0 * r), HOLE_CORNER: 0.0}
	if params.has("width") and params.has("height"):
		var size: Vector2 = Vector2(
			maxf(float(params["width"]), 0.0), maxf(float(params["height"]), 0.0)
		)
		if OVAL_FAMILIES.has(joint.hatch_family):
			return {HOLE_KIND: KIND_ELLIPSE, HOLE_SIZE: size, HOLE_CORNER: 0.0}
		var corner: float = maxf(float(params.get("corner_radius", 0.0)), 0.0)
		return {HOLE_KIND: KIND_RECT, HOLE_SIZE: size, HOLE_CORNER: corner}
	return _doorway(cfg)


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
