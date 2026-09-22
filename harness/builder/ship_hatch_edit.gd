class_name ShipHatchEdit
extends RefCounted
## The hatch panel's model side (ADR 0029): which seam a selection names, what its hatch is,
## what the seam can take, and how a choice is written back - so the inspector's HATCH section
## holds nothing but widgets and [ShipBuilder] gains no public method for it (the facade is at
## its budget; see harness/builder/ship_component_import.gd for the same arrangement).
##
## "the user should be able to choose the general shape of the door/hatch, square, rect, circ,
## ellipse, rectangle, triangle, polygon, etc, and the dimensions of the door/hatch not
## exceeding max or min (min a person could squeeze through), and the style of the door/hatch."
##
## A HATCH IS A PRESET PLUS OVERRIDES. The family (`ShipJoint.hatch_family`) is the preset: its
## shape, its style and its size come from the pack. Whatever the player then changes is stored
## in `hatch_params` under ShipSeams' PARAM_* keys and wins over the preset; choosing another
## family clears them, because a preset chosen is a preset wanted. A pair inside one component
## keeps its joint in the definition (ADR 0025), exactly as LINK does.

## The keys [method state] answers with and [method write] accepts.
const KEY_MODE: String = "mode"  # ShipSeams.MODE_*
const KEY_FAMILY: String = "family"  # hatch family id
const KEY_SHAPE: String = "shape"  # ShipSeams.KIND_*
const KEY_STYLE: String = "style"  # ShipSeams.DOOR_*
const KEY_WIDTH: String = "width"  # float, metres
const KEY_HEIGHT: String = "height"  # float, metres
const KEY_SIDES: String = "sides"  # int
const KEY_LIMITS: String = "limits"  # Dictionary, ShipDoors.limits
const KEY_HOLE: String = "hole"  # Dictionary, the resolved hole record

## The size a field may reach when the seam gives no answer of its own.
const SIZE_CEILING_M: float = 4.0


## The seam a selection names, as `[child, host]`: the one pair joined within it, or the one
## part selected and what it stands on. Empty when it names none, or several.
static func pair_for(doc: ShipDoc, selected: PackedStringArray) -> PackedStringArray:
	var none: PackedStringArray = PackedStringArray()
	if doc == null or selected.is_empty():
		return none
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(doc, selected)
	if pairs.size() == 1:
		var pair: PackedStringArray = pairs[0]
		# The "two parts name their own pair" case comes in any order: the child first here.
		if _host_of(doc, pair[1]) == pair[0]:
			return PackedStringArray([pair[1], pair[0]])
		return pair
	if pairs.size() > 1 or selected.size() != 1:
		return none
	var id: String = ShipSymmetry.source_of_twin(selected[0])
	var host: String = _host_of(doc, id)
	if host.is_empty():
		return none
	return PackedStringArray([id, host])


## What the seam between [param child] and [param host] carries and can take - see the KEY_*
## constants. `limits` is only measured for a doorway or a hatch.
static func state(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, child: String, host: String
) -> Dictionary:
	var mode: String = ShipSeams.mode_for(doc, child, host)
	var joint: ShipJoint = joint_for(doc, child, host)
	var hole: Dictionary = ShipSeams.hole_for(mode, joint, data, cfg)
	var size: Vector2 = hole.get(ShipSeams.HOLE_SIZE, Vector2.ZERO)
	var out: Dictionary = {
		KEY_MODE: mode,
		KEY_FAMILY: joint.hatch_family if joint != null else "",
		KEY_SHAPE: str(hole.get(ShipSeams.HOLE_KIND, ShipSeams.KIND_RECT)),
		KEY_STYLE: str(hole.get(ShipSeams.HOLE_STYLE, ShipSeams.DOOR_NONE)),
		KEY_WIDTH: size.x,
		KEY_HEIGHT: size.y,
		KEY_SIDES: int(hole.get(ShipSeams.HOLE_SIDES, 6)),
		KEY_HOLE: hole,
		KEY_LIMITS: {},
	}
	if is_bounded(mode):
		out[KEY_LIMITS] = ShipDoors.limits(doc, data, cfg, child, host)
	return out


## Writes [param changes] (KEY_FAMILY, KEY_SHAPE, KEY_STYLE, KEY_WIDTH, KEY_HEIGHT, KEY_SIDES)
## onto the seam's joint. False when the pair has no joint to write - a wall carries nothing.
## The caller brackets this with the edit protocol.
static func write(doc: ShipDoc, child: String, host: String, changes: Dictionary) -> bool:
	var joint: ShipJoint = joint_for(doc, child, host)
	if joint == null or doc == null:
		return false
	var params: Dictionary = joint.hatch_params.duplicate(true)
	if changes.has(KEY_FAMILY):
		joint.hatch_family = str(changes[KEY_FAMILY])
		# A preset chosen is a preset wanted: the overrides of the last one go.
		params = {}
	if changes.has(KEY_SHAPE):
		params[ShipSeams.PARAM_SHAPE] = str(changes[KEY_SHAPE])
	if changes.has(KEY_STYLE):
		params[ShipSeams.PARAM_STYLE] = str(changes[KEY_STYLE])
	if changes.has(KEY_WIDTH) or changes.has(KEY_HEIGHT):
		# A size is stored whole, so a width typed over a radius preset does not leave the
		# height to the preset's radius.
		var hole: Dictionary = ShipSeams.hole_for(
			(
				ShipSeams.MODE_HATCHED
				if joint.mode == ShipJoint.MODE_HATCHED
				else ShipSeams.MODE_DOORWAY
			),
			joint,
			null,
			null
		)
		var size: Vector2 = hole.get(ShipSeams.HOLE_SIZE, Vector2.ZERO)
		params[ShipSeams.PARAM_WIDTH] = float(changes.get(KEY_WIDTH, size.x))
		params[ShipSeams.PARAM_HEIGHT] = float(changes.get(KEY_HEIGHT, size.y))
	if changes.has(KEY_SIDES):
		params[ShipSeams.PARAM_SIDES] = int(changes[KEY_SIDES])
	joint.hatch_params = params
	if ShipSeams.within_one_instance(doc, child, host):
		return ShipComponents.set_inner_joint(doc, child, host, joint)
	return true


## The joint over the pair: the definition's for two chunks of one component (ADR 0025), the
## document's otherwise. Null for a wall.
static func joint_for(doc: ShipDoc, child: String, host: String) -> ShipJoint:
	if doc == null:
		return null
	if ShipSeams.within_one_instance(doc, child, host):
		return ShipComponents.inner_joint_for(doc, child, host)
	var key: String = ShipDoc.joint_key_for(
		ShipSymmetry.source_of_twin(child), ShipSymmetry.source_of_twin(host)
	)
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == key:
			return joint
	return null


## The hatch families of the pack, each `{id, label, shape, style}`, in id order.
static func families(data: ShipData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if data == null:
		return out
	var ids: Array = data.hatches.keys()
	ids.sort()
	for id: Variant in ids:
		var entry: Variant = data.hatches[id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		(
			out
			. append(
				{
					"id": str(id),
					"label": str(d.get("label", id)),
					"shape": str(d.get("shape", "")),
					"style": str(d.get("style", "")),
				}
			)
		)
	return out


## The key the view files a door under (ShipDoors.DOOR_KEY): the joint key over the sources.
static func door_key(child: String, host: String) -> String:
	return ShipDoc.joint_key_for(
		ShipSymmetry.source_of_twin(child), ShipSymmetry.source_of_twin(host)
	)


## A doorway or a hatch: a seam with an opening to size.
static func is_bounded(mode: String) -> bool:
	return mode == ShipSeams.MODE_DOORWAY or mode == ShipSeams.MODE_HATCHED


## What [param id] stands on: a document part's parent, an inner part's inner host (ADR 0024).
static func _host_of(doc: ShipDoc, id: String) -> String:
	if doc.parts.has(id):
		return (doc.parts[id] as ShipPart).parent
	if ShipComponents.inner_exists(doc, id):
		return ShipComponents.inner_host_key(doc, id)
	return ""
