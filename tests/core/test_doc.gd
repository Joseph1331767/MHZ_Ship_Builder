# ShipDoc tree operations: id monotonicity, subtree removal, joint cleanup, deterministic
# ordering, and lossless JSON round-tripping. This is the structural backbone every other
# part of the builder mutates through.
class_name TestDoc
extends GdUnitTestSuite

var _data: ShipData
var _family_id: String
var _manufacturer_id: String


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	(
		assert_bool(ok)
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)
	var families: PackedStringArray = _data.family_ids()
	(
		assert_array(families)
		. append_failure_message("no families loaded from res://data")
		. is_not_empty()
	)
	_family_id = families[0]
	var mfrs: PackedStringArray = _data.manufacturers_for(_family_id)
	(
		assert_array(mfrs)
		. append_failure_message("no manufacturers for family '%s'" % _family_id)
		. is_not_empty()
	)
	_manufacturer_id = mfrs[0]


func _new_doc() -> ShipDoc:
	return ShipDoc.create_new(_family_id, _manufacturer_id, _data)


func _add_child(doc: ShipDoc, parent_id: String) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = parent_id
	part.kind = "primitive"
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = 0.0
	part.pitch = 0.0
	part.rot = Vector3.ZERO
	part.offset = 0.0
	part.scale = Vector3.ONE
	part.blend = 0.0
	part.mirror_source = ""
	part.mirror_plane = ""
	part.display_name = "part " + part.id
	@warning_ignore("return_value_discarded")
	doc.add_part(part)
	return part


func _add_joint(doc: ShipDoc, a: String, b: String) -> ShipJoint:
	var joint: ShipJoint = ShipJoint.new()
	joint.id = doc.new_joint_id()
	if a < b:
		joint.a = a
		joint.b = b
	else:
		joint.a = b
		joint.b = a
	joint.mode = "open"
	joint.hatch_family = ""
	joint.hatch_manufacturer = ""
	joint.hatch_params = {}
	doc.joints[joint.id] = joint
	return joint


func test_new_part_id_is_monotonic_and_unique() -> void:
	var doc: ShipDoc = _new_doc()
	var id1: String = doc.new_part_id()
	var id2: String = doc.new_part_id()
	var id3: String = doc.new_part_id()
	assert_str(id1).starts_with("p_")
	assert_str(id2).is_not_equal(id1)
	assert_str(id3).is_not_equal(id1)
	assert_str(id3).is_not_equal(id2)


func test_new_part_id_never_reused_after_delete() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var removed_id: String = child.id
	@warning_ignore("return_value_discarded")
	doc.remove_part(removed_id)
	var seen: Dictionary = {removed_id: true}
	var i: int = 0
	while i < 5:
		var new_id: String = doc.new_part_id()
		(
			assert_str(new_id)
			. append_failure_message(
				"new_part_id() produced '%s', which was already used and removed" % new_id
			)
			. is_not_equal(removed_id)
		)
		(
			assert_bool(seen.has(new_id))
			. append_failure_message("new_part_id() reused a previously seen id: %s" % new_id)
			. is_false()
		)
		seen[new_id] = true
		i += 1


func test_remove_part_removes_whole_subtree() -> void:
	var doc: ShipDoc = _new_doc()
	var child_a: ShipPart = _add_child(doc, doc.root)
	var grandchild: ShipPart = _add_child(doc, child_a.id)
	var other_child: ShipPart = _add_child(doc, doc.root)
	var removed: PackedStringArray = doc.remove_part(child_a.id)
	assert_array(removed).contains(child_a.id, grandchild.id)
	assert_bool(doc.parts.has(child_a.id)).is_false()
	assert_bool(doc.parts.has(grandchild.id)).is_false()
	assert_bool(doc.parts.has(other_child.id)).is_true()


func test_remove_part_drops_referencing_joints() -> void:
	var doc: ShipDoc = _new_doc()
	var child_a: ShipPart = _add_child(doc, doc.root)
	var child_b: ShipPart = _add_child(doc, doc.root)
	var doomed_joint: ShipJoint = _add_joint(doc, doc.root, child_a.id)
	var surviving_joint: ShipJoint = _add_joint(doc, doc.root, child_b.id)
	@warning_ignore("return_value_discarded")
	doc.remove_part(child_a.id)
	(
		assert_bool(doc.joints.has(doomed_joint.id))
		. append_failure_message("joint referencing a removed part was not dropped")
		. is_false()
	)
	assert_bool(doc.joints.has(surviving_joint.id)).is_true()


func test_children_descendants_and_ancestors() -> void:
	var doc: ShipDoc = _new_doc()
	var child_a: ShipPart = _add_child(doc, doc.root)
	var grandchild: ShipPart = _add_child(doc, child_a.id)
	var child_b: ShipPart = _add_child(doc, doc.root)

	assert_array(doc.children_of(doc.root)).contains(child_a.id, child_b.id)
	assert_array(doc.children_of(child_a.id)).contains(grandchild.id)
	assert_array(doc.descendants_of(doc.root)).contains(child_a.id, grandchild.id, child_b.id)
	assert_array(doc.descendants_of(doc.root)).not_contains(doc.root)
	assert_array(doc.ancestors_of(grandchild.id)).contains(child_a.id, doc.root)


func test_part_order_starts_at_root_and_respects_parent_before_child() -> void:
	var doc: ShipDoc = _new_doc()
	var child_a: ShipPart = _add_child(doc, doc.root)
	@warning_ignore("return_value_discarded")
	_add_child(doc, child_a.id)
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)

	var order: PackedStringArray = doc.part_order()
	assert_str(order[0]).is_equal(doc.root)

	var index_of: Dictionary = {}
	var i: int = 0
	while i < order.size():
		index_of[order[i]] = i
		i += 1
	for part_id: String in doc.parts.keys():
		var part: ShipPart = doc.parts[part_id] as ShipPart
		if part.parent != "":
			(
				assert_int(index_of[part_id] as int)
				. append_failure_message(
					(
						"part '%s' appears before its parent '%s' in part_order()"
						% [part_id, part.parent]
					)
				)
				. is_greater(index_of[part.parent] as int)
			)


func test_part_order_is_stable_across_a_dict_rebuild() -> void:
	var doc: ShipDoc = _new_doc()
	var child_a: ShipPart = _add_child(doc, doc.root)
	@warning_ignore("return_value_discarded")
	_add_child(doc, child_a.id)
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)

	var order_before: String = "|".join(doc.part_order())
	var rebuilt: ShipDoc = ShipDoc.from_dict(doc.to_dict())
	var order_after: String = "|".join(rebuilt.part_order())
	assert_str(order_after).is_equal(order_before)


func test_to_dict_from_dict_round_trip_is_lossless() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	@warning_ignore("return_value_discarded")
	_add_joint(doc, doc.root, child.id)

	var rebuilt: ShipDoc = ShipDoc.from_dict(doc.to_dict())
	var json_before: String = ShipCanonical.canonical_json(doc.to_dict())
	var json_after: String = ShipCanonical.canonical_json(rebuilt.to_dict())
	assert_str(json_after).is_equal(json_before)


func test_joint_key_for_sorts_lexicographically() -> void:
	assert_str(ShipDoc.joint_key_for("b", "a")).is_equal("a|b")
	assert_str(ShipDoc.joint_key_for("a", "b")).is_equal("a|b")
