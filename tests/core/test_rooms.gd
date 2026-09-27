# Rooms are the default, not a declaration (2026-09-02): "each and every primitave should by
# default be a room.. i should be able to add a hatch between any 2 connected shapes.. not adding
# one obv keeps internal door, and combining multiple into the same room removes all internal
# walls making it a component and defining it as a single room."
#
# Three facts under test: every part is a room unless it says otherwise (and a ship saved before
# the rule keeps its exact record); joining parts into one component keeps the joints to the
# outside and drops the walls inside; and a default placement sinks a part deep enough that the
# hatch test the tree panel runs - ShipJoints.solid_pair_state at the hull thickness - passes.
class_name TestRooms
extends GdUnitTestSuite
const COMPACT: Array[String] = ["box_hull", "sphere_pod", "cylinder_spar"]

var _data: ShipData
var _cfg: ShipConfig


## TEMPLATE LINKS ARE OPEN BY DEFAULT since 2026-09-26 ("by default in the prebuilds we dont want
## any walls in our prebuilds by default"). This suite is about what a ship with LINKS does - its
## walls, its doors, the rooms they bound or the meshes they cut - so it asks for the hatches the
## templates used to place, instead of resting on a default that no longer says that.
func _linked(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {ShipTemplates.OPT_LINK_MODE: ShipJoint.MODE_HATCHED}
	out.merge(extra)
	return out


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)
	_cfg = _data.config


func _first_mfr(family: String) -> String:
	return _data.manufacturers_for(family)[0]


func _new_doc(family: String = "box_hull") -> ShipDoc:
	return ShipDoc.create_new(family, _first_mfr(family), _data, _cfg.root_span_m)


## A primitive of `family` under `parent_id`, aimed (yaw, pitch), at `offset` - or at the default
## embed when `offset` is NAN. Returns its id.
func _add(
	doc: ShipDoc, parent_id: String, family: String, yaw: float, pitch: float, offset: float
) -> String:
	var part: ShipPart = ShipPart.new()
	part.parent = parent_id
	part.family = family
	part.manufacturer = _first_mfr(family)
	part.params = ShapeGen.default_params(_data, family, part.manufacturer)
	part.yaw = yaw
	part.pitch = pitch
	part.display_name = family
	if is_nan(offset):
		part.offset = ShipAttach.default_offset(
			ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, doc.parts[parent_id]),
			ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, part),
			part,
			_cfg
		)
	else:
		part.offset = offset
	return doc.add_part(part)


func _join(doc: ShipDoc, a: String, b: String, mode: String, hatch_family: String = "") -> String:
	var joint: ShipJoint = (
		ShipJoint
		. from_dict(
			doc.new_joint_id(),
			{
				"a": a,
				"b": b,
				"mode": mode,
				"hatch": {"family": hatch_family, "manufacturer": "", "params": {"seed_m": 0.5}},
			}
		)
	)
	doc.joints[joint.id] = joint
	return joint.id


func _instance_id(doc: ShipDoc, component_id: String) -> String:
	for pid: String in doc.parts:
		var part: ShipPart = doc.parts[pid]
		if part.kind == ShipPart.KIND_COMPONENT_INSTANCE and part.family == component_id:
			return pid
	return ""


func _joint_between(doc: ShipDoc, a: String, b: String) -> ShipJoint:
	var key: String = ShipDoc.joint_key_for(a, b)
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == key:
			return joint
	return null


func _pair_state(doc: ShipDoc, a: String, b: String) -> Dictionary:
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	return ShipJoints.solid_pair_state(
		shapes[a], xforms[a], shapes[b], xforms[b], _cfg.hull_thickness_m
	)


# ---------------------------------------------------------------- every part is a room


func test_a_doorway_joint_is_a_valid_mode_that_round_trips() -> void:
	# ADR 0008: the fourth way two rooms can link. Stored as "doorway", read back as itself, and
	# never folded into "open" by the unknown-mode fallback.
	assert_bool(ShipJoint.VALID_MODES.has(ShipJoint.MODE_DOORWAY)).is_true()
	var joint: ShipJoint = ShipJoint.from_dict(
		"j_0001", {"a": "p_0002", "b": "p_0001", "mode": ShipJoint.MODE_DOORWAY}
	)
	assert_str(joint.mode).is_equal(ShipJoint.MODE_DOORWAY)
	assert_str(str(joint.to_dict()["mode"])).is_equal("doorway")
	var again: ShipJoint = ShipJoint.from_dict("j_0001", joint.to_dict())
	assert_str(again.mode).is_equal(ShipJoint.MODE_DOORWAY)
	assert_str(ShipJoint.from_dict("j_0002", {"a": "x", "b": "y", "mode": "hinged"}).mode).is_equal(
		ShipJoint.MODE_OPEN
	)


func test_a_fresh_part_is_a_room() -> void:
	var part: ShipPart = ShipPart.new()
	assert_str(part.role).is_equal(ShipPart.ROLE_ROOM)
	assert_bool(part.is_room()).is_true()


func test_a_new_document_root_is_a_room_and_says_so_on_disk() -> void:
	var doc: ShipDoc = _new_doc()
	var root: ShipPart = doc.parts[doc.root]
	assert_bool(root.is_room()).is_true()
	assert_str(str(root.to_dict()["role"])).is_equal("room")


func test_a_placed_primitive_is_a_room_with_nothing_declared() -> void:
	var doc: ShipDoc = _new_doc("sphere_pod")
	var tunnel: String = _add(doc, doc.root, "cylinder_spar", 0.0, 0.0, NAN)
	(
		assert_bool((doc.parts[tunnel] as ShipPart).is_room())
		. append_failure_message("a tunnel dropped on a sphere must be a room without MAKE ROOM")
		. is_true()
	)


func test_a_part_saved_before_the_rule_is_a_room_and_keeps_its_record() -> void:
	# No "role" in the record: an old file. It loads as a room - and writes back the same "" it
	# was hashed with, so its hash does not move (AGENTS section 8b).
	var record: Dictionary = {
		"parent": "",
		"kind": "primitive",
		"family": "box_hull",
		"manufacturer": _first_mfr("box_hull"),
		"params": {},
		"attach": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "offset": 0.0},
		"scale": [1.0, 1.0, 1.0],
		"blend": 0.0,
		"mirror": {"source": null, "plane": null},
		"name": "old hull",
		"locked": false,
	}
	var part: ShipPart = ShipPart.from_dict("p_0001", record)
	assert_str(part.role).is_equal("")
	assert_bool(part.is_room()).is_true()
	assert_str(str(part.to_dict()["role"])).is_equal("")
	# And a record that does say "room" round-trips as "room".
	record["role"] = "room"
	var named: ShipPart = ShipPart.from_dict("p_0002", record)
	assert_str(named.role).is_equal(ShipPart.ROLE_ROOM)
	assert_str(str(named.to_dict()["role"])).is_equal("room")


func test_a_part_that_says_it_is_something_else_is_not_a_room() -> void:
	var part: ShipPart = ShipPart.new()
	part.role = ShipPart.ROLE_HALLWAY
	assert_bool(part.is_room()).is_false()
	part.role = "structural"
	assert_bool(part.is_room()).is_false()


func test_the_templates_agree_with_the_part_on_the_vocabulary() -> void:
	assert_str(ShipTemplates.ROLE_ROOM).is_equal(ShipPart.ROLE_ROOM)
	assert_str(ShipTemplates.ROLE_HALLWAY).is_equal(ShipPart.ROLE_HALLWAY)


func test_a_component_instance_is_one_room() -> void:
	var doc: ShipDoc = _new_doc()
	var arm: String = _add(doc, doc.root, "cylinder_spar", 0.0, 0.0, NAN)
	var component_id: String = ShipComponents.make_component(doc, PackedStringArray([arm]), "Arm")
	assert_str(component_id).is_not_empty()
	var lifted: String = _instance_id(doc, component_id)
	assert_str(lifted).is_not_empty()
	var instance: ShipPart = doc.parts[lifted]
	assert_str(instance.role).is_equal(ShipPart.ROLE_ROOM)
	assert_bool(instance.is_room()).is_true()
	assert_str(str(instance.to_dict()["role"])).is_equal("room")
	var copy: String = ShipComponents.instantiate(doc, component_id, doc.root)
	assert_str(copy).is_not_empty()
	assert_bool((doc.parts[copy] as ShipPart).is_room()).is_true()


# ---------------------------------------------------------------- joining parts into one room


func test_joining_parts_keeps_the_outside_joints_and_drops_the_inside_walls() -> void:
	var doc: ShipDoc = _new_doc()
	var arm: String = _add(doc, doc.root, "cylinder_spar", 0.0, 0.0, NAN)
	var hand: String = _add(doc, arm, "sphere_pod", 0.0, 0.0, NAN)
	var other: String = _add(doc, doc.root, "box_hull", 90.0, 0.0, NAN)
	var root_arm: String = _join(doc, doc.root, arm, ShipJoint.MODE_HATCHED, "iris_round")
	var arm_hand: String = _join(doc, arm, hand, ShipJoint.MODE_OPEN)
	var other_hand: String = _join(doc, other, hand, ShipJoint.MODE_HATCHED, "plug_square")
	assert_int(doc.joints.size()).is_equal(3)

	var component_id: String = ShipComponents.make_component(
		doc, PackedStringArray([arm, hand]), "Arm"
	)
	assert_str(component_id).is_not_empty()
	var instance: String = _instance_id(doc, component_id)
	assert_str(instance).is_not_empty()
	assert_bool(doc.parts.has(arm)).is_false()
	assert_bool(doc.parts.has(hand)).is_false()

	# Two outside joints survive, re-seated on the instance under their own ids with their hatch
	# fields intact; the link between arm and hand moves INTO the definition (ADR 0025).
	(
		assert_int(doc.joints.size())
		. append_failure_message("joints after the lift: %s" % [str(doc.joints.keys())])
		. is_equal(2)
	)
	var inside: Dictionary = (doc.components[component_id] as Dictionary).get("joints", {})
	assert_int(inside.size()).is_equal(1)
	assert_str(str((inside.values()[0] as Dictionary).get("mode", ""))).is_equal(
		ShipJoint.MODE_OPEN
	)
	assert_bool(doc.joints.has(arm_hand)).is_false()
	var to_root: ShipJoint = _joint_between(doc, doc.root, instance)
	assert_object(to_root).is_not_null()
	assert_str(to_root.id).is_equal(root_arm)
	assert_str(to_root.mode).is_equal(ShipJoint.MODE_HATCHED)
	assert_str(to_root.hatch_family).is_equal("iris_round")
	assert_float(float(to_root.hatch_params.get("seed_m", 0.0))).is_equal(0.5)
	var to_other: ShipJoint = _joint_between(doc, other, instance)
	assert_object(to_other).is_not_null()
	assert_str(to_other.id).is_equal(other_hand)
	assert_str(to_other.hatch_family).is_equal("plug_square")
	# The pair on every survivor is normalised a <= b, as from_dict would load it.
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		(
			assert_bool(joint.a <= joint.b)
			. append_failure_message(
				"joint %s stored (%s, %s) out of order" % [jid, joint.a, joint.b]
			)
			. is_true()
		)
		(
			assert_bool(doc.parts.has(joint.a) and doc.parts.has(joint.b))
			. append_failure_message(
				"joint %s references a part that is gone: (%s, %s)" % [jid, joint.a, joint.b]
			)
			. is_true()
		)


func test_two_joints_onto_one_neighbour_collapse_to_the_hatched_one() -> void:
	var doc: ShipDoc = _new_doc()
	var arm: String = _add(doc, doc.root, "cylinder_spar", 0.0, 0.0, NAN)
	var hand: String = _add(doc, arm, "sphere_pod", 0.0, 0.0, NAN)
	var root_arm: String = _join(doc, doc.root, arm, ShipJoint.MODE_OPEN)
	var root_hand: String = _join(doc, doc.root, hand, ShipJoint.MODE_HATCHED, "iris_round")

	var component_id: String = ShipComponents.make_component(
		doc, PackedStringArray([arm, hand]), "Arm"
	)
	assert_str(component_id).is_not_empty()
	var instance: String = _instance_id(doc, component_id)
	(
		assert_int(doc.joints.size())
		. append_failure_message("joints after the lift: %s" % [str(doc.joints.keys())])
		. is_equal(1)
	)
	assert_bool(doc.joints.has(root_arm)).is_false()
	var kept: ShipJoint = _joint_between(doc, doc.root, instance)
	assert_object(kept).is_not_null()
	assert_str(kept.id).is_equal(root_hand)
	assert_str(kept.mode).is_equal(ShipJoint.MODE_HATCHED)


func test_a_lift_with_no_joints_adds_none() -> void:
	var doc: ShipDoc = _new_doc()
	var arm: String = _add(doc, doc.root, "cylinder_spar", 0.0, 0.0, NAN)
	var component_id: String = ShipComponents.make_component(doc, PackedStringArray([arm]), "Arm")
	assert_str(component_id).is_not_empty()
	assert_int(doc.joints.size()).is_equal(0)


# ---------------------------------------------------------------- hatching two parts that meet


func test_a_default_placement_meets_its_parent_for_a_hatch() -> void:
	# The tree panel refuses a hatch unless ShipJoints.solid_pair_state says the interiors merge
	# at the hull thickness; a part dropped at the default embed must pass that on every compact
	# family, including the sphere the complaint was about.
	for parent_family: String in COMPACT:
		for child_family: String in COMPACT:
			var doc: ShipDoc = _new_doc(parent_family)
			var child: String = _add(doc, doc.root, child_family, 30.0, 20.0, NAN)
			var state: Dictionary = _pair_state(doc, doc.root, child)
			(
				assert_bool(bool(state["merges"]))
				. append_failure_message(
					(
						"%s on %s at the default embed does not merge at the hull thickness"
						% [child_family, parent_family]
					)
				)
				. is_true()
			)


func test_a_tangent_or_distant_part_does_not_meet() -> void:
	var doc: ShipDoc = _new_doc("sphere_pod")
	var flush: String = _add(doc, doc.root, "box_hull", 0.0, 0.0, 0.0)
	var flush_state: Dictionary = _pair_state(doc, doc.root, flush)
	(
		assert_bool(bool(flush_state["merges"]))
		. append_failure_message(
			"a box flush on a sphere touches at a point - it must not count as meeting"
		)
		. is_false()
	)
	# A positive offset floats the part out along the mount normal (a negative one sinks it).
	var far: String = _add(doc, doc.root, "box_hull", 0.0, 0.0, 4.0)
	var far_state: Dictionary = _pair_state(doc, doc.root, far)
	assert_bool(bool(far_state["overlaps"])).is_false()
	assert_bool(bool(far_state["merges"])).is_false()


func test_the_validator_and_the_panel_ask_the_same_question() -> void:
	var doc: ShipDoc = _new_doc("box_hull")
	var child: String = _add(doc, doc.root, "sphere_pod", 0.0, 0.0, NAN)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	var panel: Dictionary = ShipJoints.solid_pair_state(
		shapes[child], xforms[child], shapes[doc.root], xforms[doc.root], _cfg.hull_thickness_m
	)
	var validator: Dictionary = ShipValidate._solid_pair_state(
		shapes[child], xforms[child], shapes[doc.root], xforms[doc.root], _cfg.hull_thickness_m
	)
	assert_bool(bool(panel["overlaps"])).is_equal(bool(validator["overlaps"]))
	assert_bool(bool(panel["merges"])).is_equal(bool(validator["merges"]))
	assert_int(ShipValidate.JOINT_SAMPLE_STEPS).is_equal(ShipJoints.SOLID_SAMPLE_STEPS)


# ---------------------------------------------------------------- the nucleus layout (ADR 0017)


func test_the_nucleus_has_no_body_at_its_centre() -> void:
	# "which has 5 protons around a central one which is wrong, the central one should be the
	# singular top, and the 4 rim and lower added." A carbon class is six bodies on an octahedron:
	# the root takes the top slot and every other body is placed FROM it, so nothing is buried
	# under its own neighbours. The rim hangs 30 degrees below level, not 45: at one seating
	# depth that is what puts it halfway between the top body and the bottom one (ADR 0018), and
	# on a box root it strikes a side face rather than an edge.
	var dirs: Array[Vector3] = ShipTemplates.nucleus_dirs(_data, 6)
	assert_int(dirs.size()).is_equal(5)
	var rim: int = 0
	var lower: int = 0
	for dir: Vector3 in dirs:
		# Everything hangs BELOW the root: nothing is placed upward, or it would be the top.
		(
			assert_float(dir.y)
			. append_failure_message("a nucleus body was placed above the root: %s" % [str(dir)])
			. is_less(0.001)
		)
		if is_equal_approx(dir.y, -1.0):
			lower += 1
		elif absf(dir.y + 0.5) < 0.01:
			rim += 1
	(
		assert_int(rim)
		. append_failure_message("expected four rim bodies at 30 degrees below level, got %d" % rim)
		. is_equal(4)
	)
	assert_int(lower).append_failure_message("expected one body straight below").is_equal(1)


func test_the_pods_take_slots_of_the_nucleus_arrangement() -> void:
	# "the valance electron count should be half or full resonant to the structure of protons at
	# all times." Carbon's four pods take the four RIM slots of the same octahedron its six protons
	# sit on - the slots most perpendicular to the root's own.
	var carbon: Dictionary = ShipTemplates.entry(_data, "carbon")
	var pods: Array[Vector3] = ShipTemplates.extremity_dirs(_data, carbon)
	assert_int(pods.size()).is_equal(4)
	for dir: Vector3 in pods:
		(
			assert_float(absf(dir.y))
			. append_failure_message(
				"a carbon pod took a pole slot, not the waist: %s" % [str(dir)]
			)
			. is_less(0.001)
		)
	# Neon fills its whole cube: eight pods, eight slots, none repeated.
	var neon: Array[Vector3] = ShipTemplates.extremity_dirs(
		_data, ShipTemplates.entry(_data, "neon")
	)
	assert_int(neon.size()).is_equal(8)
	var seen: Dictionary = {}
	for dir: Vector3 in neon:
		seen[str(dir.snapped(Vector3.ONE * 0.001))] = true
	assert_int(seen.size()).append_failure_message("neon repeated a slot").is_equal(8)


func test_a_pod_is_built_on_the_proton_whose_slot_it_shares() -> void:
	# A pod's tunnel continues the line its proton is already on, rather than setting off from the
	# root straight through it. Read off the document: no tunnel on a carbon class stands on the
	# root, because every one of its four slots is occupied by a proton.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", _linked())
	var tunnels: int = 0
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.role != ShipPart.ROLE_HALLWAY:
			continue
		tunnels += 1
		(
			assert_str(part.parent)
			. append_failure_message("a carbon pod's tunnel still stands on the root")
			. is_not_equal(doc.root)
		)
	assert_int(tunnels).is_equal(4)


## "the proton should be classified as a component (by default)" (ADR 0024): a template's
## nucleus is the ship's ROOT COMPONENT - one instance whose definition holds the six protons -
## its tunnels hang off the inner protons they were laid out for, every part still places, the
## tree has nothing floating, and the definition's own OPEN joints (ADR 0025) plan it as ONE room.
func test_the_nucleus_is_the_root_component_and_one_room() -> void:
	for family: String in ["sphere_pod", "box_hull"]:
		var doc: ShipDoc = ShipTemplates.build(
			_data, _cfg, "carbon", _linked({ShipTemplates.OPT_ROOM_FAMILY: family})
		)
		var root: ShipPart = doc.parts[doc.root]
		assert_str(root.kind).append_failure_message(family).is_equal(
			ShipPart.KIND_COMPONENT_INSTANCE
		)
		var definition: Dictionary = doc.components[root.family]
		(
			assert_int((definition["parts"] as Dictionary).size())
			. append_failure_message(family)
			. is_equal(6)
		)
		var on_inner: int = 0
		for pid: String in doc.part_order():
			var part: ShipPart = doc.parts[pid]
			if part.role == ShipPart.ROLE_HALLWAY and part.parent.begins_with(doc.root + "/"):
				on_inner += 1
		(
			assert_int(on_inner)
			. append_failure_message("%s: tunnels hung off inner protons" % family)
			. is_greater_equal(4)
		)
		for jid: String in doc.joints:
			assert_str((doc.joints[jid] as ShipJoint).mode).is_not_equal(ShipJoint.MODE_OPEN)
		# OPEN by default, IN the definition (ADR 0025): every touching pair of the clump.
		var inner_joints: Dictionary = definition.get("joints", {})
		assert_int(inner_joints.size()).append_failure_message(family).is_greater_equal(5)
		for jid: String in inner_joints:
			assert_str(str((inner_joints[jid] as Dictionary).get("mode", ""))).is_equal(
				ShipJoint.MODE_OPEN
			)
		var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
		for pid: String in doc.part_order():
			(
				assert_bool(xforms.has(pid))
				. append_failure_message("%s: %s not placed" % [family, pid])
				. is_true()
			)
		assert_int(doc.floating_part_ids().size()).append_failure_message(family).is_equal(0)
		var rooms: Array = ShipMeshBake.plan(doc, _data, _cfg)["rooms"]
		var biggest: int = 0
		for members: PackedStringArray in rooms:
			biggest = maxi(biggest, members.size())
		(
			assert_int(biggest)
			. append_failure_message(
				"%s: the nucleus did not plan as one room: %s" % [family, str(rooms)]
			)
			. is_equal(6)
		)
	var lone: ShipDoc = ShipTemplates.build(_data, _cfg, "hydrogen", _linked())
	assert_str((lone.parts[lone.root] as ShipPart).kind).is_equal(ShipPart.KIND_PRIMITIVE)
