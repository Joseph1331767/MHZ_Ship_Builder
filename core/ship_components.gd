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
	# A definition's root is a PRIMITIVE - it is the instance's proxy shape, and an instance has
	# none of its own. Measured: a ship whose root was an instance imported with no proxy and no
	# nucleus, and the builder had nothing to draw or hover (ADR 0026).
	if (doc.parts[head] as ShipPart).kind == KIND_INSTANCE:
		push_warning("ShipComponents.make_component: the head of the selection is an instance.")
		return ""
	var ids: PackedStringArray = ShipMirror.subtree_ids(doc, head)
	if not _selection_is_whole_subtree(chosen, ids):
		push_warning("ShipComponents.make_component: select the whole subtree, children included.")
		return ""
	if not _selection_mirror_safe(doc, chosen, ids):
		return ""
	var component_id: String = _unique_component_id(doc, label)
	doc.components[component_id] = _build_definition(doc, ids, head, label)
	_move_inside_joints(doc, ids, component_id)
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
## The inner id each lifted part gets: its position in [param ids], one-based.
static func _inner_id_map(ids: PackedStringArray) -> Dictionary:
	var id_map: Dictionary = {}
	var index: int = 0
	for id: String in ids:
		index += 1
		id_map[id] = "%s%04d" % [INNER_ID_PREFIX, index]
	return id_map


## The joints between two lifted parts go INTO the definition, keyed by inner ids, so a
## component keeps the links between its own chunks and they stay editable (ADR 0025). Joints
## reaching outside are reseated on the instance by [method _swap_in_instance].
static func _move_inside_joints(doc: ShipDoc, ids: PackedStringArray, component_id: String) -> void:
	var id_map: Dictionary = _inner_id_map(ids)
	var definition: Dictionary = doc.components[component_id]
	var inner_joints: Dictionary = {}
	var keys: Array = doc.joints.keys()
	keys.sort()
	for key: Variant in keys:
		var joint: ShipJoint = doc.joints[key]
		if not id_map.has(joint.a) or not id_map.has(joint.b):
			continue
		var moved: ShipJoint = ShipJoint.from_dict(str(key), joint.to_dict())
		moved.a = id_map[joint.a]
		moved.b = id_map[joint.b]
		if moved.a > moved.b:
			var swap: String = moved.a
			moved.a = moved.b
			moved.b = swap
		inner_joints[str(key)] = moved.to_dict()
		doc.joints.erase(key)
	definition["joints"] = inner_joints


static func _build_definition(
	doc: ShipDoc, ids: PackedStringArray, head: String, label: String
) -> Dictionary:
	var id_map: Dictionary = _inner_id_map(ids)
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
# wholly inside the selection is dropped, which WALLS it - a wall is the absence of a record
# (ShipSeams.mode_for returns MODE_WALL when there is none), and a definition has nowhere to keep
# a joint anyway: it is {label, root, parts}.
# RETIRED(ADR 0016, 2026-09-04): "...because joining parts into one room removes the walls between
# them" -> it does the opposite, and making a room no longer comes through here at all. Rooms are
# LINK OPEN over a selection (PartTreePanel._on_link); this is MAKE COMP only, where losing an
# internal joint costs a hatch the player has to place again rather than a wall they did not ask
# for. ShipDoc.remove_part() erases every
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
	# THE ANCHOR TRAVELS WITH THE HEAD (ADR 0033). The head's four attach numbers are copied above;
	# its anchor to the beacon is the fifth thing that places it, and a root that lost it would move
	# the whole ship to the centre the moment a selection became a component.
	part.absolute = root_part.absolute
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


## The inner part an expanded id names, built fresh from its definition's record; null when the
## instance, the definition or the inner id is missing. Edits to the returned object are not
## stored until [method store_inner_part] (or [method ShipDoc.store_inner]) writes them back.
static func inner_part(doc: ShipDoc, expanded_id: String) -> ShipPart:
	var location: Dictionary = _locate_inner(doc, expanded_id)
	if location.is_empty():
		return null
	var record: Variant = location["record"]
	if record is ShipPart:
		return (record as ShipPart).duplicate_part()
	if record is Dictionary:
		return ShipPart.from_dict(location["inner"], record)
	return null


## Write [param part] back as the record of the inner part [param expanded_id] names.
static func store_inner_part(doc: ShipDoc, expanded_id: String, part: ShipPart) -> void:
	var location: Dictionary = _locate_inner(doc, expanded_id)
	if location.is_empty() or part == null:
		return
	var definition: Dictionary = doc.components[location["component"]]
	var inner: Dictionary = definition.get("parts", {})
	var stored: ShipPart = part.duplicate_part()
	stored.id = location["inner"]
	inner[location["inner"]] = stored.to_dict()
	definition["parts"] = inner


## True when [param id] is an expanded id whose instance exists and whose inner id is in that
## instance's definition (nested instances walk the chain).
static func inner_exists(doc: ShipDoc, id: String) -> bool:
	return not _locate_inner(doc, id).is_empty()


## The key an inner part hangs from: its parent's expanded key, or the instance's own key when
## its parent is the definition's root (the instance stands for that root). "" when the id is
## not an inner part or its parent is not in the definition.
static func inner_host_key(doc: ShipDoc, expanded_id: String) -> String:
	var location: Dictionary = _locate_inner(doc, expanded_id)
	if location.is_empty():
		return ""
	var definition: Dictionary = doc.components[location["component"]]
	var record: Variant = location["record"]
	var parent: String = ""
	if record is ShipPart:
		parent = (record as ShipPart).parent
	elif record is Dictionary:
		parent = str((record as Dictionary).get("parent", ""))
	if parent.is_empty():
		return ""
	var head: String = expanded_id.substr(0, expanded_id.rfind("/"))
	if parent == str(definition.get("root", "")):
		return head
	return head + "/" + parent


## Where an expanded id lives: {"component": definition id, "inner": inner id, "record": the
## stored record}. Empty when any link of the chain is missing.
static func _locate_inner(doc: ShipDoc, expanded_id: String) -> Dictionary:
	if doc == null or not is_expanded_id(expanded_id):
		return {}
	var chain: PackedStringArray = expanded_id.split("/")
	var head: String = ShipSymmetry.source_of_twin(chain[0])
	var part: Variant = doc.parts.get(head, null)
	if not (part is ShipPart) or (part as ShipPart).kind != KIND_INSTANCE:
		return {}
	var component_id: String = (part as ShipPart).family
	var record: Variant = null
	var inner_id: String = ""
	for i: int in range(1, chain.size()):
		if not doc.components.has(component_id):
			return {}
		var definition: Dictionary = doc.components[component_id]
		var inner: Dictionary = definition.get("parts", {})
		inner_id = ShipSymmetry.source_of_twin(chain[i])
		if not inner.has(inner_id):
			return {}
		record = inner[inner_id]
		if i < chain.size() - 1:
			var kind: String = ""
			var family: String = ""
			if record is ShipPart:
				kind = (record as ShipPart).kind
				family = (record as ShipPart).family
			elif record is Dictionary:
				kind = str((record as Dictionary).get("kind", ""))
				family = str((record as Dictionary).get("family", ""))
			if kind != KIND_INSTANCE:
				return {}
			component_id = family
	return {"component": component_id, "inner": inner_id, "record": record}


## Bring every component of [param other] into [param doc] - definitions, the definitions
## those reference, all of them - then every ARM of the ship (each subtree hanging off its root,
## identical arms once) and the whole ship as one more, named [param ship_label] (ADR 0024/0026).
## A ship whose root is an instance is flattened first (the instance dissolved on a copy), so
## every definition made here has a primitive root. Ids are remapped to stay unique here;
## nothing in [param other] is touched. Returns the new definition ids, the whole ship's last.
static func import_from(doc: ShipDoc, other: ShipDoc, ship_label: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null or other == null:
		return out
	var id_map: Dictionary = {}
	var keys: Array = other.components.keys()
	keys.sort()
	for key: Variant in keys:
		var old_id: String = str(key)
		var definition: Variant = other.components[old_id]
		if not (definition is Dictionary):
			continue
		var label: String = str((definition as Dictionary).get("label", old_id))
		id_map[old_id] = _unique_component_id(doc, label)
	for key: Variant in keys:
		var old_id: String = str(key)
		if not id_map.has(old_id):
			continue
		var copy: Dictionary = (other.components[old_id] as Dictionary).duplicate(true)
		copy["parts"] = _remapped_parts(copy.get("parts", {}), id_map)
		doc.components[id_map[old_id]] = copy
		out.append(id_map[old_id])
	if other.parts.is_empty() or other.root.is_empty() or not other.parts.has(other.root):
		return out
	# The ship, flat: a root that is an instance is dissolved on a copy until it is a primitive.
	var flat: ShipDoc = other.duplicate_doc()
	var guard: int = MAX_NESTING_DEPTH
	while guard > 0 and (flat.parts[flat.root] as ShipPart).kind == KIND_INSTANCE:
		guard -= 1
		if dissolve(flat, flat.root).is_empty():
			break
	# Its arms: each subtree hanging off the root - off the root component's inner parts too,
	# which is where a class hangs its tunnels - identical arms once, numbered as they come.
	var seen: Dictionary = {}
	var arm_count: int = 0
	for arm: String in other.children_of(other.root):
		var ids: PackedStringArray = ShipMirror.subtree_ids(other, arm)
		var signature: String = _subtree_signature(other, ids, arm)
		if seen.has(signature):
			continue
		seen[signature] = true
		arm_count += 1
		var arm_label: String = "%s ARM %d" % [ship_label, arm_count]
		var arm_id: String = _unique_component_id(doc, arm_label)
		doc.components[arm_id] = _definition_from(other, ids, arm, arm_label, id_map)
		out.append(arm_id)
	# The ship itself.
	var all_ids: PackedStringArray = flat.part_order()
	var ship_id: String = _unique_component_id(doc, ship_label)
	doc.components[ship_id] = _definition_from(flat, all_ids, flat.root, ship_label, id_map)
	out.append(ship_id)
	return out


## A definition made of [param ids] of [param source] rooted at [param head]: parts under fresh
## inner ids (a parent that is an inner part of an instance keeps its tail), instances inside
## repointed through [param id_map], and every joint between two of the parts carried along.
static func _definition_from(
	source: ShipDoc, ids: PackedStringArray, head: String, label: String, id_map: Dictionary
) -> Dictionary:
	var inner_of: Dictionary = _inner_id_map(ids)
	var inner: Dictionary = {}
	for id: String in ids:
		var part: ShipPart = (source.parts[id] as ShipPart).duplicate_part()
		part.id = inner_of[id]
		if id == head:
			part.parent = ""
			part.yaw = 0.0
			part.pitch = 0.0
			part.rot = Vector3.ZERO
			part.offset = 0.0
		else:
			var parent_head: String = instance_of(part.parent)
			var tail: String = part.parent.substr(parent_head.length())
			part.parent = str(inner_of.get(parent_head, "")) + tail
		if part.kind == KIND_INSTANCE and id_map.has(part.family):
			part.family = id_map[part.family]
		inner[part.id] = part.to_dict()
	var joints: Dictionary = {}
	var joint_keys: Array = source.joints.keys()
	joint_keys.sort()
	for key: Variant in joint_keys:
		var joint: ShipJoint = source.joints[key]
		var a: String = _imported_end(joint.a, inner_of)
		var b: String = _imported_end(joint.b, inner_of)
		if a.is_empty() or b.is_empty():
			continue
		var copy: ShipJoint = ShipJoint.from_dict(str(key), joint.to_dict())
		copy.a = a if a <= b else b
		copy.b = b if a <= b else a
		joints[str(key)] = copy.to_dict()
	return {"label": label, "root": inner_of[head], "parts": inner, "joints": joints}


## What makes two arms the same arm: every part's family, manufacturer, params, scale, role and
## blend, its attach numbers (the head's excluded - that is where it sits, not what it is), and
## the shape of the tree. Ids and names are not it.
static func _subtree_signature(source: ShipDoc, ids: PackedStringArray, head: String) -> String:
	var index_of: Dictionary = {}
	for i: int in ids.size():
		index_of[ids[i]] = i
	var lines: PackedStringArray = PackedStringArray()
	for id: String in ids:
		var part: ShipPart = source.parts[id]
		var attach: String = ""
		if id != head:
			attach = (
				"%s|%.4f|%.4f|%s|%.4f"
				% [
					str(index_of.get(instance_of(part.parent), -1)),
					part.yaw,
					part.pitch,
					str(part.rot.snapped(Vector3.ONE * 0.0001)),
					part.offset
				]
			)
		lines.append(
			(
				(
					"%s|%s|%s|%s|%s|%.4f|%s"
					% [
						part.kind,
						part.family,
						part.manufacturer,
						JSON.stringify(part.params, "", true),
						str(part.scale.snapped(Vector3.ONE * 0.0001)),
						part.blend,
						part.role
					]
				)
				+ "|"
				+ attach
			)
		)
	return "\n".join(lines)


## A joint end of a source ship as an inner id of the definition being made: a part becomes its
## inner id, an inner part of one of its instances keeps its tail behind that instance's inner
## id; "" when the end is not among the lifted parts.
static func _imported_end(end: String, inner_of: Dictionary) -> String:
	var head: String = instance_of(end)
	if not inner_of.has(head):
		return ""
	return str(inner_of[head]) + end.substr(head.length())


static func _remapped_parts(parts: Variant, id_map: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not (parts is Dictionary):
		return out
	for key: Variant in parts:
		var record: Variant = parts[key]
		if record is Dictionary:
			var copy: Dictionary = (record as Dictionary).duplicate(true)
			if (
				str(copy.get("kind", "")) == KIND_INSTANCE
				and id_map.has(str(copy.get("family", "")))
			):
				copy["family"] = id_map[str(copy.get("family", ""))]
			out[key] = copy
		elif record is ShipPart:
			var part: ShipPart = (record as ShipPart).duplicate_part()
			if part.kind == KIND_INSTANCE and id_map.has(part.family):
				part.family = id_map[part.family]
			out[key] = part.to_dict()
	return out


## The inverse of [method make_component] for one instance: its inner parts become document
## parts again (fresh ids), the definition's root taking the instance's place, attach numbers
## and all; parts hung off its inner parts and joints naming them follow. The definition stays
## for the palette. Returns the new ids, the root's first; empty when refused.
static func dissolve(doc: ShipDoc, instance_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null or not doc.parts.has(instance_id):
		return out
	var instance: ShipPart = doc.parts[instance_id]
	if instance.kind != KIND_INSTANCE or not doc.components.has(instance.family):
		return out
	var definition: Dictionary = doc.components[instance.family]
	var inner: Dictionary = definition_parts(definition)
	var root_inner: String = str(definition.get("root", ""))
	if not inner.has(root_inner):
		return out
	var new_id: Dictionary = {}
	for inner_id: String in definition_order(inner, root_inner):
		var part: ShipPart = (inner[inner_id] as ShipPart).duplicate_part()
		part.id = doc.new_part_id()
		new_id[inner_id] = part.id
		if inner_id == root_inner:
			part.parent = instance.parent
			part.yaw = instance.yaw
			part.pitch = instance.pitch
			part.rot = instance.rot
			part.offset = instance.offset
			part.blend = instance.blend
			# And its anchor to the beacon (ADR 0033), for when the instance was the ship's root,
			# and whether the instance stood outside symmetry - a flag that belongs to the head.
			part.absolute = instance.absolute
			part.asymmetric = part.asymmetric or instance.asymmetric
			if instance.display_name != "":
				part.display_name = instance.display_name
		else:
			part.parent = str(new_id.get(part.parent, ""))
		doc.parts[part.id] = part
		doc._bump_part_counter(part.id)
		out.append(part.id)
	var prefix: String = instance_id + "/"
	for key: Variant in doc.parts:
		var part: ShipPart = doc.parts[key]
		if part.parent == instance_id:
			part.parent = new_id[root_inner]
		elif part.parent.begins_with(prefix):
			part.parent = str(new_id.get(part.parent.substr(prefix.length()), part.parent))
	# The links between its chunks come back as document joints under fresh ids.
	var stored: Dictionary = definition.get("joints", {})
	var stored_keys: Array = stored.keys()
	stored_keys.sort()
	for key: Variant in stored_keys:
		var record: Variant = stored[key]
		if not (record is Dictionary):
			continue
		var joint: ShipJoint = ShipJoint.from_dict(doc.new_joint_id(), record)
		joint.a = str(new_id.get(joint.a, joint.a))
		joint.b = str(new_id.get(joint.b, joint.b))
		if joint.a > joint.b:
			var swap_end: String = joint.a
			joint.a = joint.b
			joint.b = swap_end
		doc.joints[joint.id] = joint
	for key: Variant in doc.joints:
		var joint: ShipJoint = doc.joints[key]
		joint.a = _dissolved_end(joint.a, instance_id, prefix, new_id, root_inner)
		joint.b = _dissolved_end(joint.b, instance_id, prefix, new_id, root_inner)
		if joint.a > joint.b:
			var swap: String = joint.a
			joint.a = joint.b
			joint.b = swap
	var was_root: bool = doc.root == instance_id
	doc.parts.erase(instance_id)
	if was_root:
		doc.root = new_id[root_inner]
	doc.drop_inner_cache()
	return out


static func _dissolved_end(
	end: String, instance_id: String, prefix: String, new_id: Dictionary, root_inner: String
) -> String:
	if end == instance_id:
		return new_id[root_inner]
	if end.begins_with(prefix):
		return str(new_id.get(end.substr(prefix.length()), end))
	return end


## Two keys that are parts of ONE definition - two inner parts of an instance, or one of them
## and the instance itself (its proxy is the definition's root): {"prefix": the instance key,
## "a", "b": their inner ids, sorted}. Empty otherwise. Nested instances are their own
## definitions: "x/cp_1/cp_2" pairs with "x/cp_1/cp_3" and with "x/cp_1", not with "x/cp_4".
static func inner_pair(doc: ShipDoc, child: String, host: String) -> Dictionary:
	if doc == null:
		return {}
	var c: String = ShipSymmetry.source_of_twin(child)
	var h: String = ShipSymmetry.source_of_twin(host)
	if not is_expanded_id(c) and not is_expanded_id(h):
		return {}
	var prefix: String = ""
	var a: String = ""
	var b: String = ""
	if is_expanded_id(c) and is_expanded_id(h):
		var pc: String = c.substr(0, c.rfind("/"))
		var ph: String = h.substr(0, h.rfind("/"))
		if pc != ph:
			return {}
		prefix = pc
		a = c.substr(pc.length() + 1)
		b = h.substr(ph.length() + 1)
	else:
		var inner: String = c if is_expanded_id(c) else h
		var proxy: String = h if is_expanded_id(c) else c
		if inner.substr(0, inner.rfind("/")) != proxy:
			return {}
		prefix = proxy
		var located: Dictionary = _locate_inner(doc, inner)
		if located.is_empty():
			return {}
		a = inner.substr(proxy.length() + 1)
		b = str((doc.components[located["component"]] as Dictionary).get("root", ""))
	if a.is_empty() or b.is_empty():
		return {}
	return {"prefix": prefix, "a": a if a <= b else b, "b": b if a <= b else a}


## The definition id the instance at [param prefix] (an instance key, possibly nested) uses.
static func definition_of(doc: ShipDoc, prefix: String) -> String:
	if doc == null:
		return ""
	if not is_expanded_id(prefix):
		var part: Variant = doc.parts.get(ShipSymmetry.source_of_twin(prefix), null)
		if part is ShipPart and (part as ShipPart).kind == KIND_INSTANCE:
			return (part as ShipPart).family
		return ""
	var located: Dictionary = _locate_inner(doc, prefix)
	if located.is_empty():
		return ""
	var record: Variant = located["record"]
	if record is ShipPart and (record as ShipPart).kind == KIND_INSTANCE:
		return (record as ShipPart).family
	if record is Dictionary and str((record as Dictionary).get("kind", "")) == KIND_INSTANCE:
		return str((record as Dictionary).get("family", ""))
	return ""


## The joint a definition holds between two of its parts, by their keys; null when none.
static func inner_joint_for(doc: ShipDoc, child: String, host: String) -> ShipJoint:
	var pair: Dictionary = inner_pair(doc, child, host)
	if pair.is_empty():
		return null
	var component_id: String = definition_of(doc, pair["prefix"])
	if component_id.is_empty() or not doc.components.has(component_id):
		return null
	var stored: Dictionary = (doc.components[component_id] as Dictionary).get("joints", {})
	var keys: Array = stored.keys()
	keys.sort()
	for key: Variant in keys:
		var record: Variant = stored[key]
		if not (record is Dictionary):
			continue
		var joint: ShipJoint = ShipJoint.from_dict(str(key), record)
		if joint.a == pair["a"] and joint.b == pair["b"]:
			return joint
	return null


## Store [param joint] as the definition's joint between the two keys (its ends are rewritten
## to their inner ids; a null joint erases). Every instance of the definition reads it. Returns
## false when the two keys are not parts of one definition.
static func set_inner_joint(doc: ShipDoc, child: String, host: String, joint: ShipJoint) -> bool:
	var pair: Dictionary = inner_pair(doc, child, host)
	if pair.is_empty():
		return false
	var component_id: String = definition_of(doc, pair["prefix"])
	if component_id.is_empty() or not doc.components.has(component_id):
		return false
	var definition: Dictionary = doc.components[component_id]
	var stored: Dictionary = definition.get("joints", {})
	var keys: Array = stored.keys()
	keys.sort()
	for key: Variant in keys:
		var record: Variant = stored[key]
		if (
			record is Dictionary
			and str(record.get("a", "")) == pair["a"]
			and str(record.get("b", "")) == pair["b"]
		):
			stored.erase(key)
	if joint != null:
		var copy: ShipJoint = ShipJoint.from_dict(joint.id, joint.to_dict())
		copy.a = pair["a"]
		copy.b = pair["b"]
		var jid: String = (
			joint.id if not joint.id.is_empty() else "j_inner_%04d" % (stored.size() + 1)
		)
		while stored.has(jid):
			jid += "_"
		copy.id = jid
		stored[jid] = copy.to_dict()
	definition["joints"] = stored
	return true
