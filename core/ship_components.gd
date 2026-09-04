class_name ShipComponents
extends RefCounted

## Components — SPEC section 6, API_CONTRACT section 20. Static only, no state.
##
## SketchUp semantics, deliberately: a *definition* holds the parts, an *instance* is a part in the
## ship tree that points at a definition. Edit the definition and every instance updates at the
## next rebuild. "Make Unique" clones the definition and repoints one instance. An instance
## attaches with the same four numbers as a primitive, so it drops into the palette with no
## special-casing anywhere else.
##
## A definition lives in `doc.components[id]` as `{ label, root, parts }`, where `parts` maps its
## own private inner ids (`cp_0001`, ...) to part records. Inner ids are a separate namespace from
## `doc.parts`, so a definition can be instanced any number of times without id collisions.
##
## Nesting is allowed. `check_cycles()` catches a definition that contains itself, transitively.

const KIND_PRIMITIVE: String = "primitive"
## A fresh instance sits on its parent's nose, square to the surface, flush.
const DEFAULT_ATTACH: Dictionary = {
	"yaw": 0.0,
	"pitch": 0.0,
	"rot": Vector3.ZERO,
	"offset": 0.0,
}

const KIND_INSTANCE: String = "component_instance"
const INNER_ID_PREFIX: String = "cp_"
const COMPONENT_ID_PREFIX: String = "comp_"

## How deep instances of instances may nest before expand() stops descending. A cycle is caught by
## check_cycles(), this is the belt to that pair of braces.
const MAX_NESTING_DEPTH: int = 8


## Lift a selected subtree into a new component definition and replace it with a single instance.
## Returns the new component definition id, or "" if the operation was refused.
##
## The selection must be a COMPLETE subtree — one topmost part plus every one of its descendants.
## The UI has "Select All Children" for exactly this; a partial selection is refused rather than
## silently orphaning the parts that were left out. Mirror derivatives cannot be lifted (their
## source would end up outside the definition), and neither can a part that something outside the
## selection mirrors.
static func make_component(doc: ShipDoc, part_ids: PackedStringArray, label: String) -> String:
	if doc == null or part_ids.is_empty():
		return ""
	var chosen: Dictionary = {}
	for id: String in part_ids:
		if not doc.parts.has(id):
			push_warning("ShipComponents.make_component: no part '%s'." % id)
			return ""
		chosen[id] = true
	var head: String = _selection_root(doc, chosen)
	if head == "":
		push_warning("ShipComponents.make_component: the selection is not a single subtree.")
		return ""
	var ids: PackedStringArray = ShipMirror.subtree_ids(doc, head)
	if not _selection_is_whole_subtree(chosen, ids):
		push_warning("ShipComponents.make_component: select the whole subtree, children included.")
		return ""
	if not _selection_mirror_safe(doc, chosen, ids):
		return ""
	var component_id: String = _unique_component_id(doc, label)
	doc.components[component_id] = _build_definition(doc, ids, head, label)
	return _swap_in_instance(doc, head, component_id, label)


## Place another instance of an existing definition under `parent_id`. Returns the new part id.
static func instantiate(doc: ShipDoc, component_id: String, parent_id: String) -> String:
	if doc == null or not doc.components.has(component_id):
		push_warning("ShipComponents.instantiate: no component '%s'." % component_id)
		return ""
	if not doc.parts.has(parent_id):
		push_warning("ShipComponents.instantiate: no parent part '%s'." % parent_id)
		return ""
	var definition: Dictionary = doc.components[component_id]
	var label: String = definition.get("label", component_id)
	var record: Dictionary = _instance_dict(component_id, parent_id, DEFAULT_ATTACH, 0.0, label)
	var part: ShipPart = ShipPart.from_dict(doc.new_part_id(), record)
	var added: String = doc.add_part(part)
	if added == "":
		added = part.id
	return added


## Clone the definition behind one instance and repoint that instance at the clone, so it can be
## edited without touching its siblings. Returns the new component definition id.
static func make_unique(doc: ShipDoc, instance_id: String) -> String:
	if doc == null or not doc.parts.has(instance_id):
		return ""
	var part: ShipPart = doc.parts[instance_id]
	if part.kind != KIND_INSTANCE or not doc.components.has(part.family):
		push_warning("ShipComponents.make_unique: '%s' is not a component instance." % instance_id)
		return ""
	var definition: Dictionary = doc.components[part.family]
	var label: String = definition.get("label", part.family)
	var component_id: String = _unique_component_id(doc, label)
	doc.components[component_id] = definition.duplicate(true)
	part.family = component_id
	return component_id


## Flatten every instance in the doc into renderable/sampleable geometry:
##   "instance_id/inner_id" -> { "shape": ResolvedShape, "xform": Transform3D }
##
## Nested instances chain their keys ("outer_id/inner_id/deeper_id"). Instance nodes themselves are
## not emitted — only the primitives they resolve to, since those are what the renderer and the SDF
## consume. The doc is not modified.
##
## READ BACK OUT OF THE ATTACH PASS, not placed here: [method ShipAttach.resolve_shapes] and
## [method ShipAttach.resolve_all] emit every inner part but the definition root under these same
## keys (the root is the instance's own entry, as its proxy), so the renderer and the SDF already
## hold the whole component without calling this. This is the same geometry in the flattened
## form the contract promises, and it cannot disagree with what is drawn because it IS what is
## drawn. Derived symmetry twins are not included, as before.
static func expand(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary:
	var out: Dictionary = {}
	if doc == null or data == null:
		return out
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	for id: String in ShipAttach.ordered_part_ids(doc):
		var part: ShipPart = doc.parts[id]
		if part.kind != KIND_INSTANCE:
			continue
		_collect_expanded(doc, id, part.family, shapes, xforms, out, 0)
	return out


## True for a key the attach pass derived from a component instance: "<instance>/<inner>". A
## twin of one ("<instance>/<inner>~m") counts too.
static func is_expanded_id(id: String) -> bool:
	return id.find("/") > 0


## The doc-level id an expanded key belongs to: "p_0005/cp_0002" -> "p_0005". A twin's expanded
## key keeps the twin suffix, so it still resolves to the mirrored side and then, through
## [method ShipSymmetry.source_of_twin], to the instance: "p_0005/cp_0002~m" -> "p_0005~m". Any
## other id comes back unchanged, so a caller never has to test [method is_expanded_id] first.
static func instance_of(id: String) -> String:
	var slash: int = id.find("/")
	if slash <= 0:
		return id
	var owner: String = id.substr(0, slash)
	if ShipSymmetry.is_twin_id(id):
		return ShipSymmetry.twin_id(owner)
	return owner


## Component definition ids that contain themselves, directly or transitively. Sorted.
static func check_cycles(doc: ShipDoc) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		return out
	var ids: Array = doc.components.keys()
	ids.sort()
	var edges: Dictionary = {}
	for component_id: String in ids:
		edges[component_id] = referenced_components(doc, component_id)
	for component_id: String in ids:
		if _reaches(edges, component_id, component_id, 0):
			out.append(component_id)
	return out


## The component definition ids instanced directly inside one definition, sorted and de-duplicated.
static func referenced_components(doc: ShipDoc, component_id: String) -> PackedStringArray:
	var refs: PackedStringArray = PackedStringArray()
	if doc == null or not doc.components.has(component_id):
		return refs
	var definition: Dictionary = doc.components[component_id]
	var inner: Dictionary = definition_parts(definition)
	var inner_ids: Array = inner.keys()
	inner_ids.sort()
	for inner_id: String in inner_ids:
		var part: ShipPart = inner[inner_id]
		if part.kind == KIND_INSTANCE and not refs.has(part.family):
			refs.append(part.family)
	return refs


## A definition's parts as ShipPart records keyed by inner id. Accepts either raw dictionaries (the
## on-disk form) or already-built ShipPart objects, so it does not care how ShipDoc parsed them.
static func definition_parts(definition: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = definition.get("parts", {})
	var keys: Array = raw.keys()
	keys.sort()
	for key: String in keys:
		var value: Variant = raw[key]
		if value is ShipPart:
			var part: ShipPart = value
			out[key] = part
		elif typeof(value) == TYPE_DICTIONARY:
			var record: Dictionary = value
			out[key] = ShipPart.from_dict(key, record)
	return out


# --- private -------------------------------------------------------------------------------


# The one selected part whose parent is outside the selection; "" if there is not exactly one.
static func _selection_root(doc: ShipDoc, chosen: Dictionary) -> String:
	var head: String = ""
	var ids: Array = chosen.keys()
	ids.sort()
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if chosen.has(part.parent):
			continue
		if head != "":
			return ""
		head = id
	return head


static func _selection_is_whole_subtree(chosen: Dictionary, ids: PackedStringArray) -> bool:
	if chosen.size() != ids.size():
		return false
	for id: String in ids:
		if not chosen.has(id):
			return false
	return true


static func _selection_mirror_safe(
	doc: ShipDoc, chosen: Dictionary, ids: PackedStringArray
) -> bool:
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		if part.is_mirror():
			push_warning("ShipComponents: '%s' is a mirror derivative and cannot be lifted." % id)
			return false
	var all_ids: Array = doc.parts.keys()
	all_ids.sort()
	for id: String in all_ids:
		if chosen.has(id):
			continue
		var part: ShipPart = doc.parts[id]
		if part.is_mirror() and chosen.has(part.mirror_source):
			push_warning("ShipComponents: '%s' mirrors a part inside the selection." % id)
			return false
	return true


# Copy the subtree into definition form: inner ids, the root re-seated at the component origin.
static func _build_definition(
	doc: ShipDoc, ids: PackedStringArray, head: String, label: String
) -> Dictionary:
	var id_map: Dictionary = {}
	var index: int = 0
	for id: String in ids:
		index += 1
		id_map[id] = "%s%04d" % [INNER_ID_PREFIX, index]
	var inner: Dictionary = {}
	for id: String in ids:
		var part: ShipPart = doc.parts[id]
		var copy: ShipPart = part.duplicate_part()
		var inner_id: String = id_map[id]
		copy.id = inner_id
		if id == head:
			# The instance carries the placement; the definition root sits at its own origin.
			copy.parent = ""
			copy.yaw = 0.0
			copy.pitch = 0.0
			copy.rot = Vector3.ZERO
			copy.offset = 0.0
		else:
			var mapped_parent: String = id_map.get(part.parent, "")
			copy.parent = mapped_parent
		inner[inner_id] = copy.to_dict()
	var root_inner: String = id_map[head]
	return {"label": label, "root": root_inner, "parts": inner}


# Replace the lifted subtree with one instance that keeps the subtree root's placement.
#
# THE JOINTS FOLLOW THE LIFT. A joint between a lifted part and a part outside the selection is
# re-seated on the instance: the outside room is still hatched to what is now one room. A joint
# wholly inside the selection is dropped, because joining parts into one room removes the walls
# between them ("combining multiple into the same room removes all internal walls making it a
# component and defining it as a single room", 2026-09-02). ShipDoc.remove_part() erases every
# joint touching a removed part, so the records are taken before it runs and the survivors are
# put back afterwards, under their own ids, against the instance.
static func _swap_in_instance(
	doc: ShipDoc, head: String, component_id: String, label: String
) -> String:
	var root_part: ShipPart = doc.parts[head]
	var attach: Dictionary = {
		"yaw": root_part.yaw,
		"pitch": root_part.pitch,
		"rot": root_part.rot,
		"offset": root_part.offset,
	}
	var name: String = root_part.display_name
	if name == "":
		name = label
	var record: Dictionary = _instance_dict(
		component_id, root_part.parent, attach, root_part.blend, name
	)
	var was_root: bool = head == doc.root
	var joints_before: Dictionary = _joint_records(doc)
	doc.remove_part(head)
	var part: ShipPart = ShipPart.from_dict(doc.new_part_id(), record)
	var added: String = doc.add_part(part)
	if added == "":
		added = part.id
	if was_root:
		doc.root = added
	_reseat_joints(doc, joints_before, added)
	return component_id


# Every joint in the doc as its serialized record, keyed by id - a snapshot that survives the
# removal about to erase some of them.
static func _joint_records(doc: ShipDoc) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in doc.joints:
		var joint: ShipJoint = doc.joints[key]
		out[str(key)] = joint.to_dict()
	return out


# Put back each joint the lift erased that still has one endpoint in the doc, re-seated on the
# instance. Two such joints can land on the same pair - an outside part that was joined to two of
# the lifted parts - and a pair carries one joint, so the hatched one wins and, between equals,
# the lower id: hatched records are re-seated first, and each pass walks ids in sorted order, so
# the outcome never depends on dictionary order.
static func _reseat_joints(doc: ShipDoc, before: Dictionary, instance_id: String) -> void:
	var ids: Array = before.keys()
	ids.sort()
	var seated: Dictionary = {}
	for hatched_pass: bool in [true, false]:
		for joint_id: String in ids:
			if doc.joints.has(joint_id):
				continue
			var joint: ShipJoint = ShipJoint.from_dict(joint_id, before[joint_id])
			if (joint.mode == ShipJoint.MODE_HATCHED) != hatched_pass:
				continue
			var a_alive: bool = doc.parts.has(joint.a)
			var b_alive: bool = doc.parts.has(joint.b)
			if a_alive == b_alive:
				# Both gone: a wall inside the new room, removed. Both present: not this lift's.
				continue
			var survivor: String = joint.a if a_alive else joint.b
			var pair: String = ShipDoc.joint_key_for(survivor, instance_id)
			if seated.has(pair):
				continue
			joint.a = survivor if survivor <= instance_id else instance_id
			joint.b = instance_id if survivor <= instance_id else survivor
			doc.joints[joint_id] = joint
			seated[pair] = true


# A part record in the SPEC 5.1 on-disk shape, so ShipPart.from_dict() is the only constructor
# this file needs to know about. `attach` carries yaw/pitch/offset (degrees, metres) plus the
# Vector3 `rot` (ADR 0004).
static func _instance_dict(
	component_id: String, parent_id: String, attach: Dictionary, blend: float, name: String
) -> Dictionary:
	return {
		"parent": parent_id,
		"kind": KIND_INSTANCE,
		"family": component_id,
		"manufacturer": "",
		"params": {},
		"attach":
		{
			"yaw": attach["yaw"],
			"pitch": attach["pitch"],
			"rot": _rot_array(attach["rot"]),
			"offset": attach["offset"],
		},
		"scale": [1.0, 1.0, 1.0],
		"blend": blend,
		"mirror": {"source": null, "plane": null},
		"name": name,
		"locked": false,
		# One room: the parts inside it share their air, and it hatches to its neighbours as a
		# whole. Explicit rather than left to ShipPart.from_dict, whose fallback is "".
		"role": ShipPart.ROLE_ROOM,
	}


## A Vector3 of degrees as the three-element array ShipPart.from_dict expects on disk.
static func _rot_array(v: Variant) -> Array:
	var r: Vector3 = v if v is Vector3 else Vector3.ZERO
	return [r.x, r.y, r.z]


static func _unique_component_id(doc: ShipDoc, label: String) -> String:
	var slug: String = _slugify(label)
	if slug == "":
		slug = "component"
	var candidate: String = COMPONENT_ID_PREFIX + slug
	var index: int = 2
	while doc.components.has(candidate):
		candidate = "%s%s_%d" % [COMPONENT_ID_PREFIX, slug, index]
		index += 1
	return candidate


static func _slugify(label: String) -> String:
	var out: String = ""
	var lower: String = label.to_lower()
	for i: int in lower.length():
		var c: String = lower[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif out.length() > 0 and not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")


# Gather one instance's expanded entries from the attach pass. The instance node's own key holds
# its definition root (the proxy), emitted here under "<key>/<root id>" so the flattened form
# lists every primitive; a nested instance node recurses the same way instead of being emitted.
static func _collect_expanded(
	doc: ShipDoc,
	key: String,
	component_id: String,
	shapes: Dictionary,
	xforms: Dictionary,
	out: Dictionary,
	depth: int
) -> void:
	if depth > MAX_NESTING_DEPTH or not doc.components.has(component_id):
		return
	var definition: Dictionary = doc.components[component_id]
	var inner: Dictionary = definition_parts(definition)
	var root_id: String = definition.get("root", "")
	if not inner.has(root_id):
		return
	_emit_expanded(out, key + "/" + root_id, shapes.get(key), xforms.get(key))
	for inner_id: String in definition_order(inner, root_id):
		if inner_id == root_id:
			continue
		var inner_key: String = key + "/" + inner_id
		var inner_part: ShipPart = inner[inner_id]
		if inner_part.kind == KIND_INSTANCE:
			_collect_expanded(doc, inner_key, inner_part.family, shapes, xforms, out, depth + 1)
		else:
			_emit_expanded(out, inner_key, shapes.get(inner_key), xforms.get(inner_key))


static func _emit_expanded(
	out: Dictionary, key: String, shape_v: Variant, xform_v: Variant
) -> void:
	if shape_v is ResolvedShape and xform_v is Transform3D:
		out[key] = {"shape": shape_v, "xform": xform_v}


## Definition root first, then depth first by inner id; anything unreachable is appended sorted.
## The order [ShipAttach] places a definition's parts in, so a parent always precedes its child.
static func definition_order(inner: Dictionary, root_id: String) -> PackedStringArray:
	var children: Dictionary = {}
	var ids: Array = inner.keys()
	ids.sort()
	for inner_id: String in ids:
		var part: ShipPart = inner[inner_id]
		var bucket: PackedStringArray = children.get(part.parent, PackedStringArray())
		bucket.append(inner_id)
		children[part.parent] = bucket
	var order: PackedStringArray = PackedStringArray()
	var stack: Array[String] = [root_id]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var current: String = stack.pop_back()
		if seen.has(current) or not inner.has(current):
			continue
		seen[current] = true
		order.append(current)
		var kids: PackedStringArray = children.get(current, PackedStringArray())
		for i: int in range(kids.size() - 1, -1, -1):
			stack.append(kids[i])
	for inner_id: String in ids:
		if not seen.has(inner_id):
			order.append(inner_id)
	return order


# Can `from_id` reach `target` by following instance references? Used for cycle detection.
static func _reaches(edges: Dictionary, from_id: String, target: String, depth: int) -> bool:
	if depth > edges.size():
		return true
	var refs: PackedStringArray = edges.get(from_id, PackedStringArray())
	for ref: String in refs:
		if ref == target:
			return true
		if _reaches(edges, ref, target, depth + 1):
			return true
	return false
