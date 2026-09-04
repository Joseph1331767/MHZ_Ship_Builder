# SketchUp-true definition + instances (SPEC section 6): make_component lifts parts into a
# shared definition, instantiate drops a live-linked copy, make_unique detaches exactly one
# instance from further definition edits, and check_cycles catches self-containment.
class_name TestComponents
extends GdUnitTestSuite

var _data: ShipData
var _family_id: String
var _manufacturer_id: String


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	assert_bool(ok).append_failure_message(
		"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
	).is_true()
	var families: PackedStringArray = _data.family_ids()
	assert_array(families).append_failure_message(
		"no families loaded from res://data"
	).is_not_empty()
	_family_id = families[0]
	var mfrs: PackedStringArray = _data.manufacturers_for(_family_id)
	assert_array(mfrs).append_failure_message(
		"no manufacturers for family '%s'" % _family_id
	).is_not_empty()
	_manufacturer_id = mfrs[0]


func _add_child(doc: ShipDoc, parent_id: String) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = parent_id
	part.kind = "primitive"
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = 15.0
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


func _flush_attach() -> Dictionary:
	return {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "offset": 0.0}


func _instance_dict(component_id: String) -> Dictionary:
	return {
		"parent": "",
		"kind": "component_instance",
		"family": component_id,
		"manufacturer": "",
		"params": {},
		"attach": _flush_attach(),
		"scale": [1.0, 1.0, 1.0],
		"blend": 0.0,
		"mirror": {"source": null, "plane": null},
		"name": "nested instance",
		"locked": false,
	}


func test_make_component_creates_a_definition() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(
		doc, PackedStringArray([child.id]), "Wing"
	)
	assert_str(comp_id).is_not_empty()
	assert_bool(doc.components.has(comp_id)).is_true()
	var def_dict: Dictionary = doc.components[comp_id] as Dictionary
	assert_str(String(def_dict.get("label", ""))).is_equal("Wing")


func test_instantiate_creates_a_component_instance_part() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(
		doc, PackedStringArray([child.id]), "Wing"
	)
	var instance_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)
	assert_str(instance_id).is_not_empty()
	assert_bool(doc.parts.has(instance_id)).is_true()
	var inst_part: ShipPart = doc.parts[instance_id] as ShipPart
	assert_str(inst_part.kind).is_equal("component_instance")
	assert_str(inst_part.family).is_equal(comp_id)
	assert_str(inst_part.parent).is_equal(doc.root)


func test_make_unique_detaches_one_instance_from_definition_edits() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(
		doc, PackedStringArray([child.id]), "Wing"
	)
	var instance_a_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)
	var instance_b_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)

	var new_def_id: String = ShipComponents.make_unique(doc, instance_b_id)
	assert_str(new_def_id).is_not_equal(comp_id)
	assert_bool(doc.components.has(new_def_id)).is_true()

	var part_a: ShipPart = doc.parts[instance_a_id] as ShipPart
	var part_b: ShipPart = doc.parts[instance_b_id] as ShipPart
	assert_str(part_a.family).append_failure_message(
		"make_unique() repointed an instance it was not asked to touch"
	).is_equal(comp_id)
	assert_str(part_b.family).append_failure_message(
		"make_unique() did not repoint the target instance to its cloned definition"
	).is_equal(new_def_id)

	var original_def: Dictionary = doc.components[comp_id] as Dictionary
	original_def["label"] = "Wing Mk2"
	doc.components[comp_id] = original_def
	var relabeled: String = String((doc.components[comp_id] as Dictionary).get("label", ""))
	var clone_label: String = String((doc.components[new_def_id] as Dictionary).get("label", ""))
	assert_str(relabeled).is_equal("Wing Mk2")
	assert_str(clone_label).append_failure_message(
		"editing the original definition leaked into the made-unique clone"
	).is_not_equal("Wing Mk2")


func test_check_cycles_detects_transitive_self_containment() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	doc.components["comp_a"] = {
		"label": "A", "root": "cp_0001", "parts": {"cp_0001": _instance_dict("comp_b")}
	}
	doc.components["comp_b"] = {
		"label": "B", "root": "cp_0002", "parts": {"cp_0002": _instance_dict("comp_a")}
	}
	var cycles: PackedStringArray = ShipComponents.check_cycles(doc)
	assert_array(cycles).is_not_empty()
	var flagged_a: bool = false
	var flagged_b: bool = false
	for id: String in cycles:
		if id == "comp_a":
			flagged_a = true
		if id == "comp_b":
			flagged_b = true
	assert_bool(flagged_a or flagged_b).append_failure_message(
		"check_cycles() did not flag either component in the cycle, got: %s" % [str(cycles)]
	).is_true()


func test_check_cycles_is_empty_for_an_acyclic_doc() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	assert_array(ShipComponents.check_cycles(doc)).is_empty()


func test_expand_flattens_component_instances() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var comp_id: String = ShipComponents.make_component(
		doc, PackedStringArray([child.id]), "Wing"
	)
	var instance_id: String = ShipComponents.instantiate(doc, comp_id, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()
	var expanded: Dictionary = ShipComponents.expand(doc, _data, cfg)
	assert_dict(expanded).is_not_empty()

	var found_prefixed_key: bool = false
	for key: String in expanded.keys():
		if key.begins_with(instance_id + "/"):
			found_prefixed_key = true
			var entry: Dictionary = expanded[key] as Dictionary
			assert_bool(entry.has("shape")).is_true()
			assert_bool(entry.has("xform")).is_true()
	assert_bool(found_prefixed_key).append_failure_message(
		"expand() produced no 'instance_id/inner_id' entry for instance '%s', got keys: %s" %
		[instance_id, str(expanded.keys())]
	).is_true()
