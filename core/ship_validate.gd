class_name ShipValidate
extends RefCounted

## Document validation — API_CONTRACT section 14. Static only, no state.
##
## Returns a flat report: one Dictionary per finding, in a stable order (tree, parts, mirrors,
## components, joints, budgets), so two runs over the same doc produce the same list.
##
##     { "severity": "error"|"warn", "code": String, "part": String, "message": String }
##
## `part` is the part id the finding is about, or "" for a finding about the document as a whole.
## Messages are written for a person reading a report, not for a parser to match on — match on
## `code`, which is stable, and show `message` to the player.
##
## This is the CHEAP pass: it runs on every edit, so it uses the resolved shapes and transforms the
## builder already has, plus a coarse SDF sample for joints. It checks the bounding-box budget,
## which is cheap and exact enough from the resolved AABBs; the internal-volume, weight and cost
## budgets need the sampled metrics pass and belong to ShipMetrics / ShipBudgets, which report them
## from the numbers they actually computed rather than having this file guess at them.

const SEVERITY_ERROR: String = "error"
const SEVERITY_WARN: String = "warn"

const CODE_NO_ROOT: String = "no_root"
const CODE_ORPHAN_PART: String = "orphan_part"
## Legal, reported, never blocking — see _unreachable_issue.
const CODE_FLOATING_PART: String = "floating_part"
const CODE_CYCLE: String = "cycle"
const CODE_UNKNOWN_FAMILY: String = "unknown_family"
const CODE_UNKNOWN_MANUFACTURER: String = "unknown_manufacturer"
const CODE_PARAM_OUT_OF_RANGE: String = "param_out_of_range"
const CODE_SCALE_OUT_OF_RANGE: String = "scale_out_of_range"
const CODE_MIRROR_SOURCE_MISSING: String = "mirror_source_missing"
const CODE_MIRROR_OF_MIRROR: String = "mirror_of_mirror"
const CODE_JOINT_PART_MISSING: String = "joint_part_missing"
const CODE_JOINT_NOT_OVERLAPPING: String = "joint_not_overlapping"
const CODE_COMPONENT_CYCLE: String = "component_cycle"
const CODE_COMPONENT_MISSING: String = "component_missing"
const CODE_BUDGET_EXCEEDED: String = "budget_exceeded"

## Not in the API_CONTRACT list, added because the case is real and silent otherwise: a derivative
## whose plane is not x/y/z reflects across nothing and lands exactly on top of its source.
const CODE_MIRROR_PLANE_INVALID: String = "mirror_plane_invalid"

const KIND_INSTANCE: String = "component_instance"

## Grid resolution per axis for the joint overlap sample. Coarse on purpose — this runs per joint,
## per edit (SPEC 7: "a cheap SDF sample, no meshing"). The sample itself lives in
## [method ShipJoints.solid_pair_state] now, so the tree panel can ask the same question before
## it opens a hatch; this is the same number under the name this file always had.
const JOINT_SAMPLE_STEPS: int = ShipJoints.SOLID_SAMPLE_STEPS

## Slack on a param range comparison, so a value stored at the bound does not trip on float noise.
const RANGE_EPSILON: float = 1e-6


static func validate(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if doc == null:
		out.append(_issue(SEVERITY_ERROR, CODE_NO_ROOT, "", "There is no document to validate."))
		return out
	var ids: PackedStringArray = ShipAttach.ordered_part_ids(doc)
	_check_tree(doc, ids, out)
	_check_parts(doc, data, cfg, ids, out)
	_check_mirrors(doc, ids, out)
	_check_components(doc, ids, out)
	if data == null:
		return out
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	_check_joints(doc, shapes, xforms, cfg, out)
	_check_budgets(shapes, xforms, cfg, out)
	return out


# --- private -------------------------------------------------------------------------------


static func _issue(severity: String, code: String, part: String, message: String) -> Dictionary:
	return {"severity": severity, "code": code, "part": part, "message": message}


static func _error(code: String, part: String, message: String) -> Dictionary:
	return _issue(SEVERITY_ERROR, code, part, message)


static func _warn(code: String, part: String, message: String) -> Dictionary:
	return _issue(SEVERITY_WARN, code, part, message)


# "p_0007 (dorsal fin)" when the part is named, "p_0007" when it is not.
static func _label(doc: ShipDoc, id: String) -> String:
	if not doc.parts.has(id):
		return id
	var part: ShipPart = doc.parts[id]
	if part.display_name == "":
		return id
	return "%s (%s)" % [id, part.display_name]


static func _check_tree(doc: ShipDoc, ids: PackedStringArray, out: Array[Dictionary]) -> void:
	if doc.root == "" or not doc.parts.has(doc.root):
		var text: String = (
			"The document names no root part, so nothing can be placed in ship space. "
			+ "Every ship is one tree hanging off a single root."
		)
		out.append(_error(CODE_NO_ROOT, "", text))
	var reachable: Dictionary = {}
	if doc.parts.has(doc.root):
		reachable[doc.root] = true
		for id: String in doc.descendants_of(doc.root):
			reachable[id] = true
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if id == doc.root:
			_check_root_parent(doc, part, out)
			continue
		if reachable.has(id):
			continue
		out.append(_unreachable_issue(doc, id, part))


static func _check_root_parent(doc: ShipDoc, part: ShipPart, out: Array[Dictionary]) -> void:
	if part.parent == "":
		return
	var text: String = (
		"The root part %s names a parent ('%s'). The root is the one part that must not have one."
		% [_label(doc, part.id), part.parent]
	)
	out.append(_error(CODE_ORPHAN_PART, part.id, text))


## An unreachable part is not automatically broken.
##
## RETIRED(2026-08-31): this used to return `orphan_part` as an ERROR in all three cases.
## Research settled that Spore's vehicle/ship editor has NO contiguity requirement whatsoever —
## bodies "require no base", cockpits "are considered independent shapes and do not have to be
## attached", no editor emits a disconnected-parts error, and a creation with pieces floating free
## of the hull still saves (SPORE_CLONE_SPEC section 5). The author chose to match that and to
## report islands at BAKE time instead (`HullBake.connectivity`).
##
## So the three cases are now distinguished by whether the document is actually INCOHERENT or
## merely disconnected:
##   * a parent chain that loops         -> cycle, ERROR (the resolver cannot terminate)
##   * a parent id that names nothing    -> orphan_part, ERROR (a dangling reference is corruption)
##   * no parent at all, or a chain that ends at a parentless part -> floating_part, WARNING (legal)
static func _unreachable_issue(doc: ShipDoc, id: String, part: ShipPart) -> Dictionary:
	if _in_cycle(doc, id):
		var loop_text: String = (
			"The parent chain above %s loops back on itself and never reaches the root. "
			+ "Re-parent one of the parts in that loop."
		)
		return _error(CODE_CYCLE, id, loop_text % _label(doc, id))
	if part.parent == "":
		var free_text: String = (
			"%s is not attached to anything. That is allowed — it saves and bakes as its own "
			+ "island. The bake report lists it under `floating`."
		)
		return _warn(CODE_FLOATING_PART, id, free_text % _label(doc, id))
	if not doc.parts.has(part.parent):
		var missing_text: String = (
			"%s names parent '%s', which is not in the document. It cannot be placed until it "
			+ "is re-parented onto a part that exists."
		)
		return _error(CODE_ORPHAN_PART, id, missing_text % [_label(doc, id), part.parent])
	var stray_text: String = (
		"%s hangs off a part that is itself unattached, so it is a second island rather than "
		+ "part of the main hull. That is allowed; the bake reports it."
	)
	return _warn(CODE_FLOATING_PART, id, stray_text % _label(doc, id))


static func _in_cycle(doc: ShipDoc, id: String) -> bool:
	var current: String = id
	var limit: int = doc.parts.size() + 1
	for i: int in limit:
		var part: ShipPart = doc.parts[current]
		var next: String = part.parent
		if next == "" or not doc.parts.has(next):
			return false
		if next == id:
			return true
		current = next
	return true


static func _check_parts(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, ids: PackedStringArray, out: Array[Dictionary]
) -> void:
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		_check_scale(doc, cfg, part, out)
		if data == null or part.kind == KIND_INSTANCE:
			continue
		if not data.has_family(part.family):
			var text: String = (
				"%s is built from shape family '%s', which is not in the loaded data pack, "
				+ "so it cannot be resolved to geometry."
			)
			out.append(_error(CODE_UNKNOWN_FAMILY, id, text % [_label(doc, id), part.family]))
			continue
		if _check_manufacturer(doc, data, part, out):
			_check_params(doc, data, part, out)


static func _check_scale(
	doc: ShipDoc, cfg: ShipConfig, part: ShipPart, out: Array[Dictionary]
) -> void:
	if cfg == null:
		return
	var axes: PackedStringArray = PackedStringArray(["X", "Y", "Z"])
	for axis: int in 3:
		var value: float = part.scale[axis]
		if not is_finite(value):
			var nan_text: String = (
				"%s has a scale on %s that is not a number, so no shape can be built from it."
				% [_label(doc, part.id), axes[axis]]
			)
			out.append(_error(CODE_SCALE_OUT_OF_RANGE, part.id, nan_text))
			continue
		if value >= cfg.part_scale_min and value <= cfg.part_scale_max:
			continue
		var text: String = (
			"%s is scaled %.3f on %s, outside the allowed %.3f - %.3f."
			% [_label(doc, part.id), value, axes[axis], cfg.part_scale_min, cfg.part_scale_max]
		)
		out.append(_error(CODE_SCALE_OUT_OF_RANGE, part.id, text))


## Returns whether the manufacturer is a known id, so the caller knows the effective parameter
## ranges can be trusted enough to check the params against.
static func _check_manufacturer(
	doc: ShipDoc, data: ShipData, part: ShipPart, out: Array[Dictionary]
) -> bool:
	if part.manufacturer == "":
		var none_text: String = (
			"%s has no manufacturer. A manufacturer narrows the family's parameter ranges and "
			+ "prices the part, so every part needs one."
		)
		out.append(_error(CODE_UNKNOWN_MANUFACTURER, part.id, none_text % _label(doc, part.id)))
		return false
	if not data.manufacturer_ids().has(part.manufacturer):
		var unknown_text: String = (
			"%s is made by '%s', which is not in the loaded data pack."
			% [_label(doc, part.id), part.manufacturer]
		)
		out.append(_error(CODE_UNKNOWN_MANUFACTURER, part.id, unknown_text))
		return false
	if data.manufacturers_for(part.family).has(part.manufacturer):
		return true
	var text: String = (
		"%s is made by '%s', who does not offer the '%s' family. The part still builds, but it "
		+ "is outside that company's catalogue."
	)
	var filled: String = text % [_label(doc, part.id), part.manufacturer, part.family]
	out.append(_warn(CODE_UNKNOWN_MANUFACTURER, part.id, filled))
	return true


# Stored params are the truth (SPEC 4: ranges gate input, the hash consumes output), so a value
# outside its range is a warning about an edit that should not have been possible, not a failure.
static func _check_params(
	doc: ShipDoc, data: ShipData, part: ShipPart, out: Array[Dictionary]
) -> void:
	var ranges: Dictionary = ShapeGen.effective_ranges(data, part.family, part.manufacturer)
	if ranges.is_empty():
		return
	var keys: Array = part.params.keys()
	keys.sort()
	for key: String in keys:
		if not ranges.has(key):
			continue
		var raw: Variant = part.params[key]
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			continue
		var value: float = raw
		var bounds: Vector2 = _range_bounds(ranges[key])
		if bounds.x > bounds.y:
			continue
		if value >= bounds.x - RANGE_EPSILON and value <= bounds.y + RANGE_EPSILON:
			continue
		var text: String = (
			"%s stores %s = %.3f, outside the %.3f - %.3f that '%s' allows for the '%s' family. "
			+ "The value is kept exactly as saved; retune it if that was not deliberate."
		)
		var filled: String = (
			text
			% [_label(doc, part.id), key, value, bounds.x, bounds.y, part.manufacturer, part.family]
		)
		out.append(_warn(CODE_PARAM_OUT_OF_RANGE, part.id, filled))


# A range entry from the data pack, in whichever shape it was authored: {min, max}, [lo, hi] or a
# Vector2. Returns (lo, hi), or a reversed pair when the entry is not a usable range.
static func _range_bounds(entry: Variant) -> Vector2:
	var unusable: Vector2 = Vector2(1.0, -1.0)
	if typeof(entry) == TYPE_VECTOR2:
		var v: Vector2 = entry
		return v
	if typeof(entry) == TYPE_DICTIONARY:
		var d: Dictionary = entry
		if not d.has("min") or not d.has("max"):
			return unusable
		var lo: float = d["min"]
		var hi: float = d["max"]
		return Vector2(lo, hi)
	if typeof(entry) == TYPE_ARRAY:
		var a: Array = entry
		if a.size() < 2:
			return unusable
		var lo_a: float = a[0]
		var hi_a: float = a[1]
		return Vector2(lo_a, hi_a)
	return unusable


static func _check_mirrors(doc: ShipDoc, ids: PackedStringArray, out: Array[Dictionary]) -> void:
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if not part.is_mirror():
			continue
		if not doc.parts.has(part.mirror_source):
			var missing_text: String = (
				"%s mirrors '%s', which is no longer in the document. A derivative has no "
				+ "geometry of its own, so this part cannot be built: break the link or delete it."
			)
			var filled: String = missing_text % [_label(doc, id), part.mirror_source]
			out.append(_error(CODE_MIRROR_SOURCE_MISSING, id, filled))
			continue
		var source: ShipPart = doc.parts[part.mirror_source]
		if source.is_mirror():
			var loop_text: String = (
				"%s mirrors %s, which is itself a mirror. A mirror of a mirror is not allowed: "
				+ "break the first link before mirroring again."
			)
			var loop_filled: String = loop_text % [_label(doc, id), _label(doc, part.mirror_source)]
			out.append(_error(CODE_MIRROR_OF_MIRROR, id, loop_filled))
		if ShipMirror.is_valid_plane(part.mirror_plane):
			continue
		var plane_text: String = (
			"%s mirrors across plane '%s', which is not one of x, y or z. It reflects across "
			+ "nothing and lands on top of its source."
		)
		out.append(
			_error(CODE_MIRROR_PLANE_INVALID, id, plane_text % [_label(doc, id), part.mirror_plane])
		)


static func _check_components(doc: ShipDoc, ids: PackedStringArray, out: Array[Dictionary]) -> void:
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if part.kind != KIND_INSTANCE or doc.components.has(part.family):
			continue
		var text: String = (
			"%s is an instance of component '%s', which this document does not define, so "
			+ "nothing can be drawn for it."
		)
		out.append(_error(CODE_COMPONENT_MISSING, id, text % [_label(doc, id), part.family]))
	var component_ids: Array = doc.components.keys()
	component_ids.sort()
	for component_id: String in component_ids:
		_check_definition(doc, component_id, out)
	for component_id: String in ShipComponents.check_cycles(doc):
		var cycle_text: String = (
			"Component '%s' contains itself, directly or through another component. "
			+ "Expanding it would never terminate."
		)
		out.append(_error(CODE_COMPONENT_CYCLE, "", cycle_text % component_id))


static func _check_definition(doc: ShipDoc, component_id: String, out: Array[Dictionary]) -> void:
	var definition: Dictionary = doc.components[component_id]
	var inner: Dictionary = ShipComponents.definition_parts(definition)
	var root_id: String = definition.get("root", "")
	if not inner.has(root_id):
		var root_text: String = (
			"Component '%s' names root part '%s', which is not among its own parts. "
			+ "The definition is unusable until that is fixed."
		)
		out.append(_error(CODE_COMPONENT_MISSING, "", root_text % [component_id, root_id]))
	var inner_ids: Array = inner.keys()
	inner_ids.sort()
	for inner_id: String in inner_ids:
		var part: ShipPart = inner[inner_id]
		if part.kind != KIND_INSTANCE or doc.components.has(part.family):
			continue
		var text: String = (
			"Component '%s' contains an instance of '%s', which this document does not define."
			% [component_id, part.family]
		)
		out.append(_error(CODE_COMPONENT_MISSING, "", text))


static func _check_joints(
	doc: ShipDoc, shapes: Dictionary, xforms: Dictionary, cfg: ShipConfig, out: Array[Dictionary]
) -> void:
	var joint_ids: Array = doc.joints.keys()
	joint_ids.sort()
	var thickness: float = 0.0
	if cfg != null:
		thickness = maxf(cfg.hull_thickness_m, 0.0)
	for joint_id: String in joint_ids:
		var joint: ShipJoint = doc.joints[joint_id]
		if not _joint_endpoints_exist(doc, joint, joint_id, out):
			continue
		var shape_a: ResolvedShape = shapes.get(joint.a)
		var shape_b: ResolvedShape = shapes.get(joint.b)
		if shape_a == null or shape_b == null:
			continue
		var xform_a: Transform3D = xforms.get(joint.a, Transform3D.IDENTITY)
		var xform_b: Transform3D = xforms.get(joint.b, Transform3D.IDENTITY)
		var state: Dictionary = _solid_pair_state(shape_a, xform_a, shape_b, xform_b, thickness)
		var overlaps: bool = state["overlaps"]
		var merges: bool = state["merges"]
		if merges:
			continue
		out.append(_joint_issue(doc, joint, joint_id, overlaps, thickness))


static func _joint_issue(
	doc: ShipDoc, joint: ShipJoint, joint_id: String, overlaps: bool, thickness: float
) -> Dictionary:
	if not overlaps:
		var apart_text: String = (
			"Joint %s connects %s and %s, but the two parts do not share any space. "
			+ "A joint between parts that never meet does nothing."
		)
		var apart: String = apart_text % [joint_id, _label(doc, joint.a), _label(doc, joint.b)]
		return _warn(CODE_JOINT_NOT_OVERLAPPING, joint.a, apart)
	var touch_text: String = (
		"Joint %s connects %s and %s, but they only touch: at a hull thickness of %.3f m their "
		+ "interiors never meet, so a hatch here would open onto solid hull."
	)
	var touch: String = (
		touch_text % [joint_id, _label(doc, joint.a), _label(doc, joint.b), thickness]
	)
	return _warn(CODE_JOINT_NOT_OVERLAPPING, joint.a, touch)


static func _joint_endpoints_exist(
	doc: ShipDoc, joint: ShipJoint, joint_id: String, out: Array[Dictionary]
) -> bool:
	var missing: PackedStringArray = PackedStringArray()
	if not doc.parts.has(joint.a):
		missing.append(joint.a)
	if not doc.parts.has(joint.b):
		missing.append(joint.b)
	if not missing.is_empty():
		var text: String = (
			"Joint %s refers to part(s) %s, which are no longer in the document. "
			+ "Delete the joint or restore the parts."
		)
		out.append(_error(CODE_JOINT_PART_MISSING, "", text % [joint_id, ", ".join(missing)]))
		return false
	if joint.a != joint.b:
		return true
	var self_text: String = (
		"Joint %s connects %s to itself. A joint is an unordered pair of two different parts."
		% [joint_id, _label(doc, joint.a)]
	)
	out.append(_error(CODE_JOINT_PART_MISSING, joint.a, self_text))
	return false


# Do two placed solids share space, and do their interiors merge at `thickness`? Kept as the
# name this file's callers use; the sample is ShipJoints.solid_pair_state.
static func _solid_pair_state(
	shape_a: ResolvedShape,
	xform_a: Transform3D,
	shape_b: ResolvedShape,
	xform_b: Transform3D,
	thickness: float
) -> Dictionary:
	return ShipJoints.solid_pair_state(shape_a, xform_a, shape_b, xform_b, thickness)


# SPEC 8: max_bbox is per-axis, not diagonal. A 200 m x 20 m hull is legal where a 78 m cube is not.
static func _check_budgets(
	shapes: Dictionary, xforms: Dictionary, cfg: ShipConfig, out: Array[Dictionary]
) -> void:
	if cfg == null or shapes.is_empty():
		return
	var box: AABB = _ship_bbox(shapes, xforms)
	var axes: PackedStringArray = PackedStringArray(["X", "Y", "Z"])
	for axis: int in 3:
		var limit: float = cfg.max_bbox_m[axis]
		if limit <= 0.0 or not is_finite(limit):
			continue
		var extent: float = box.size[axis]
		if extent <= limit:
			continue
		var text: String = (
			"The ship measures %.3f m along %s; the bounding-box budget for that axis is "
			+ "%.3f m. The cap is per-axis, so a long thin hull is fine — this one is too big "
			+ "across %s."
		)
		var filled: String = text % [extent, axes[axis], limit, axes[axis]]
		out.append(_error(CODE_BUDGET_EXCEEDED, "", filled))


static func _ship_bbox(shapes: Dictionary, xforms: Dictionary) -> AABB:
	var box: AABB = AABB()
	var started: bool = false
	var ids: Array = shapes.keys()
	ids.sort()
	for id: String in ids:
		var shape: ResolvedShape = shapes[id]
		var xform: Transform3D = xforms.get(id, Transform3D.IDENTITY)
		var part_box: AABB = xform * shape.local_aabb()
		if started:
			box = box.merge(part_box)
		else:
			box = part_box
			started = true
	return box
