# MAKE COMP on a multi-selection must leave every lifted part where it stood - drawn, baked and
# budgeted (2026-09-02: "when i selected multiple parts and press make component they all
# dissapear"). The attach pass emits every inner part but the definition root under
# "<instance>/<inner>" (the root is the instance's own entry), so the geometry an attach pass
# places is identical before and after a lift, twins included, and ShipComponents.expand() reads
# the same entries back out. Compared as GEOMETRY, not by id: a lift renames every part it takes.
class_name TestComponentExpansion
extends GdUnitTestSuite

var _data: ShipData
var _cfg: ShipConfig
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
	_cfg = _data.config
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


func _add_child(doc: ShipDoc, parent_id: String, yaw: float, pitch: float) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.parent = parent_id
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = yaw
	part.pitch = pitch
	part.offset = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, doc.parts[parent_id]),
		ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, part),
		part,
		_cfg
	)
	part.display_name = "part"
	part.id = doc.add_part(part)
	return part


func _sole_instance(doc: ShipDoc) -> String:
	var found: String = ""
	for id: String in doc.parts:
		if (doc.parts[id] as ShipPart).kind == ShipPart.KIND_COMPONENT_INSTANCE:
			assert_str(found).append_failure_message("more than one instance in the doc").is_empty()
			found = id
	return found


## Every placed entry of an attach pass - twins or solids - as origin plus shape AABB size.
func _placed_geometry(shapes: Dictionary, xforms: Dictionary, twins: bool) -> Array:
	var out: Array = []
	for key: Variant in xforms.keys():
		var id: String = str(key)
		if ShipSymmetry.is_twin_id(id) != twins or not shapes.has(id):
			continue
		var shape: ResolvedShape = shapes[id]
		var xform: Transform3D = xforms[id]
		out.append({"id": id, "origin": xform.origin, "size": shape.local_aabb().size})
	return out


## Each entry of `before` must have a match in `after` (same origin, same AABB size) and the
## counts must agree, so nothing vanished and nothing was invented.
func _assert_same_geometry(before: Array, after: Array, label: String) -> void:
	(
		assert_int(after.size())
		. append_failure_message(
			(
				"%s: %d placed before, %d after - before=%s after=%s"
				% [label, before.size(), after.size(), str(before), str(after)]
			)
		)
		. is_equal(before.size())
	)
	for want: Dictionary in before:
		var found: bool = false
		for got: Dictionary in after:
			var same_origin: bool = (got["origin"] as Vector3).is_equal_approx(want["origin"])
			var same_size: bool = (got["size"] as Vector3).is_equal_approx(want["size"])
			if same_origin and same_size:
				found = true
				break
		(
			assert_bool(found)
			. append_failure_message(
				(
					"%s: %s at %s (aabb %s) has no counterpart after the lift; after=%s"
					% [label, want["id"], want["origin"], want["size"], str(after)]
				)
			)
			. is_true()
		)


func test_lifting_a_subtree_moves_nothing() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data, _cfg.root_span_m)
	var arm: ShipPart = _add_child(doc, doc.root, 15.0, 0.0)
	var hand: ShipPart = _add_child(doc, arm.id, 60.0, 30.0)
	var finger: ShipPart = _add_child(doc, hand.id, 0.0, -45.0)
	# A bystander outside the lift: it only has to exist, so the record itself is not needed.
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root, 200.0, 10.0)
	var shapes_before: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms_before: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes_before, _cfg)
	var solid_before: Array = _placed_geometry(shapes_before, xforms_before, false)
	var twins_before: Array = _placed_geometry(shapes_before, xforms_before, true)
	assert_int(solid_before.size()).is_equal(5)
	(
		assert_array(twins_before)
		. append_failure_message(
			"the fixture generated no twin, so the mirrored half of a component is untested"
		)
		. is_not_empty()
	)
	var cost_before: float = ShipMetrics.compute_cost(doc, _data)
	var bbox_before: AABB = ShipMetrics.compute_bbox(doc, _data, _cfg)

	var comp_id: String = ShipComponents.make_component(
		doc, PackedStringArray([arm.id, hand.id, finger.id]), "Arm"
	)
	assert_str(comp_id).is_not_empty()
	var instance_id: String = _sole_instance(doc)
	assert_str(instance_id).is_not_empty()
	assert_int(doc.parts.size()).is_equal(3)

	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	_assert_same_geometry(solid_before, _placed_geometry(shapes, xforms, false), "solid")
	_assert_same_geometry(twins_before, _placed_geometry(shapes, xforms, true), "twins")
	# Two inner parts follow the instance under derived keys; the root is the instance itself.
	var derived: int = 0
	for key: Variant in xforms.keys():
		var id: String = str(key)
		if id.begins_with(instance_id + "/") and not ShipSymmetry.is_twin_id(id):
			derived += 1
			assert_bool(ShipComponents.is_expanded_id(id)).is_true()
			assert_str(ShipComponents.instance_of(id)).is_equal(instance_id)
	assert_int(derived).append_failure_message("keys: %s" % [str(xforms.keys())]).is_equal(2)

	# expand() is the same geometry in the flattened form, the root included.
	var expanded: Dictionary = ShipComponents.expand(doc, _data, _cfg)
	assert_int(expanded.size()).is_equal(3)
	for key: Variant in expanded.keys():
		var id: String = str(key)
		var entry: Dictionary = expanded[id]
		var source: String = id if xforms.has(id) else instance_id
		assert_bool((entry["xform"] as Transform3D).is_equal_approx(xforms[source])).is_true()
		# expand() runs its own attach pass, so the shape is an equal object, not the same one.
		var shape: ResolvedShape = entry["shape"]
		var placed: ResolvedShape = shapes[source]
		assert_bool(shape.local_aabb().is_equal_approx(placed.local_aabb())).is_true()
		assert_bool(shape.scale.is_equal_approx(placed.scale)).is_true()

	# A lift changes no budget: the definition costs what its parts cost, at the same size.
	assert_float(ShipMetrics.compute_cost(doc, _data)).is_equal_approx(cost_before, 0.0001)
	var bbox: AABB = ShipMetrics.compute_bbox(doc, _data, _cfg)
	(
		assert_bool(bbox.position.is_equal_approx(bbox_before.position))
		. append_failure_message("bbox moved: %s -> %s" % [bbox_before, bbox])
		. is_true()
	)
	(
		assert_bool(bbox.size.is_equal_approx(bbox_before.size))
		. append_failure_message("bbox resized: %s -> %s" % [bbox_before, bbox])
		. is_true()
	)


## A definition that itself contains an instance chains its keys ("outer/inner/deeper") and is
## still placed exactly where the parts stood before either lift.
func test_lifting_a_nested_instance_moves_nothing() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data, _cfg.root_span_m)
	var post: ShipPart = _add_child(doc, doc.root, 15.0, 0.0)
	var cap: ShipPart = _add_child(doc, post.id, 0.0, 40.0)
	var inner_comp: String = ShipComponents.make_component(
		doc, PackedStringArray([post.id, cap.id]), "Post"
	)
	assert_str(inner_comp).is_not_empty()
	var post_instance: String = _sole_instance(doc)
	var base: ShipPart = _add_child(doc, doc.root, 120.0, 0.0)
	(doc.parts[post_instance] as ShipPart).parent = base.id
	var shapes_before: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms_before: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes_before, _cfg)
	var solid_before: Array = _placed_geometry(shapes_before, xforms_before, false)
	(
		assert_int(solid_before.size())
		. append_failure_message("keys: %s" % [str(xforms_before.keys())])
		. is_equal(4)
	)

	var outer_comp: String = ShipComponents.make_component(
		doc, PackedStringArray([base.id, post_instance]), "Tower"
	)
	assert_str(outer_comp).is_not_empty()
	var tower: String = _sole_instance(doc)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	_assert_same_geometry(solid_before, _placed_geometry(shapes, xforms, false), "nested")
	var deepest: int = 0
	for key: Variant in xforms.keys():
		var id: String = str(key)
		if id.begins_with(tower + "/") and id.count("/") == 2 and not ShipSymmetry.is_twin_id(id):
			deepest += 1
			assert_str(ShipComponents.instance_of(id)).is_equal(tower)
	assert_int(deepest).append_failure_message("keys: %s" % [str(xforms.keys())]).is_equal(1)
	var expanded: Dictionary = ShipComponents.expand(doc, _data, _cfg)
	(
		assert_int(expanded.size())
		. append_failure_message("expand keys: %s" % [str(expanded.keys())])
		. is_equal(3)
	)


func test_instance_of_resolves_expanded_ids_to_their_instance() -> void:
	assert_str(ShipComponents.instance_of("p_0005/cp_0002")).is_equal("p_0005")
	assert_str(ShipComponents.instance_of("p_0005/cp_0002/cp_0003")).is_equal("p_0005")
	assert_str(ShipComponents.instance_of("p_0005/cp_0002~m")).is_equal("p_0005~m")
	assert_str(ShipComponents.instance_of("p_0005")).is_equal("p_0005")
	assert_str(ShipComponents.instance_of("p_0005~m")).is_equal("p_0005~m")
	assert_bool(ShipComponents.is_expanded_id("p_0005/cp_0002")).is_true()
	assert_bool(ShipComponents.is_expanded_id("p_0005/cp_0002~m")).is_true()
	assert_bool(ShipComponents.is_expanded_id("p_0005")).is_false()
	assert_bool(ShipComponents.is_expanded_id("p_0005~m")).is_false()
