# Every error code in API_CONTRACT.md section 14 must fire on some deliberately broken doc.
# Each test below starts from one minimal, otherwise-valid ShipDoc dict (SPEC section 5.1
# schema) and breaks exactly one thing. Incidental extra codes on the same crafted doc are
# not asserted against -- only that the target code appears.
class_name TestValidate
extends GdUnitTestSuite

var _data: ShipData
var _family_id: String
var _manufacturer_id: String
var _default_params: Dictionary


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
	_default_params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)


func _flush_attach() -> Dictionary:
	return {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "offset": 0.0}


func _part_dict(
	parent: String, family: String, manufacturer: String, params: Dictionary,
	attach: Dictionary, scale: Array, part_name: String
) -> Dictionary:
	return {
		"parent": parent,
		"kind": "primitive",
		"family": family,
		"manufacturer": manufacturer,
		"params": params,
		"attach": attach,
		"scale": scale,
		"blend": 0.0,
		"mirror": {"source": null, "plane": null},
		"name": part_name,
		"locked": false,
	}


func _base_doc_dict() -> Dictionary:
	var root_dict: Dictionary = _part_dict(
		"", _family_id, _manufacturer_id, _default_params, _flush_attach(),
		[1.0, 1.0, 1.0], "root"
	)
	return {
		"format": "mhz_ship",
		"version": 1,
		"ruleset_version": "1.0.0",
		"units": "metres",
		"root": "p_0001",
		"settings": {},
		"parts": {"p_0001": root_dict},
		"joints": {},
		"components": {},
	}


func _has_code(results: Array[Dictionary], code: String) -> bool:
	for entry: Dictionary in results:
		if String(entry.get("code", "")) == code:
			return true
	return false


func _assert_code_fires(results: Array[Dictionary], code: String) -> void:
	assert_bool(_has_code(results, code)).append_failure_message(
		"expected validate() to report code '%s', got: %s" % [code, str(results)]
	).is_true()


func test_valid_minimal_doc_reports_no_errors() -> void:
	var doc: ShipDoc = ShipDoc.from_dict(_base_doc_dict())
	var cfg: ShipConfig = ShipConfig.defaults()
	var results: Array[Dictionary] = ShipValidate.validate(doc, _data, cfg)
	var error_count: int = 0
	for entry: Dictionary in results:
		if String(entry.get("severity", "")) == "error":
			error_count += 1
	assert_int(error_count).append_failure_message(
		"minimal valid doc reported errors: %s" % str(results)
	).is_equal(0)


func test_no_root_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	d["parts"] = {}
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "no_root")


func test_orphan_part_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	parts["p_0002"] = _part_dict(
		"totally_missing_parent_id", _family_id, _manufacturer_id, _default_params,
		_flush_attach(), [1.0, 1.0, 1.0], "orphan"
	)
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "orphan_part")


func test_cycle_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	parts["p_0002"] = _part_dict(
		"p_0003", _family_id, _manufacturer_id, _default_params,
		_flush_attach(), [1.0, 1.0, 1.0], "cycle_a"
	)
	parts["p_0003"] = _part_dict(
		"p_0002", _family_id, _manufacturer_id, _default_params,
		_flush_attach(), [1.0, 1.0, 1.0], "cycle_b"
	)
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "cycle")


func test_unknown_family_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var root_dict: Dictionary = parts["p_0001"]
	root_dict["family"] = "definitely_not_a_real_family_xyz"
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "unknown_family")


func test_unknown_manufacturer_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var root_dict: Dictionary = parts["p_0001"]
	root_dict["manufacturer"] = "definitely_not_a_real_manufacturer_xyz"
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "unknown_manufacturer")


func test_param_out_of_range_fires() -> void:
	var bad_params: Dictionary = _default_params.duplicate(true)
	var numeric_keys: int = 0
	for key: String in bad_params.keys():
		var v: Variant = bad_params[key]
		if typeof(v) == TYPE_FLOAT:
			bad_params[key] = 1.0e9
			numeric_keys += 1
		elif typeof(v) == TYPE_INT:
			bad_params[key] = 1000000000
			numeric_keys += 1
	assert_int(numeric_keys).append_failure_message(
		"family '%s' has no numeric params to push out of range" % _family_id
	).is_greater(0)
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var root_dict: Dictionary = parts["p_0001"]
	root_dict["params"] = bad_params
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "param_out_of_range")


func test_scale_out_of_range_fires() -> void:
	var cfg: ShipConfig = ShipConfig.defaults()
	var too_big: float = cfg.part_scale_max + 1000.0
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var root_dict: Dictionary = parts["p_0001"]
	root_dict["scale"] = [too_big, too_big, too_big]
	var doc: ShipDoc = ShipDoc.from_dict(d)
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "scale_out_of_range")


func test_mirror_source_missing_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var mirror_dict: Dictionary = _part_dict(
		"p_0001", _family_id, _manufacturer_id, _default_params,
		_flush_attach(), [1.0, 1.0, 1.0], "broken_mirror"
	)
	mirror_dict["mirror"] = {"source": "totally_missing_source_id", "plane": "x"}
	parts["p_0002"] = mirror_dict
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "mirror_source_missing")


func test_mirror_of_mirror_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var mirror_b: Dictionary = _part_dict(
		"p_0001", _family_id, _manufacturer_id, _default_params,
		_flush_attach(), [1.0, 1.0, 1.0], "mirror_b"
	)
	mirror_b["mirror"] = {"source": "p_0001", "plane": "x"}
	parts["p_0002"] = mirror_b
	var mirror_c: Dictionary = _part_dict(
		"p_0001", _family_id, _manufacturer_id, _default_params,
		_flush_attach(), [1.0, 1.0, 1.0], "mirror_of_mirror"
	)
	mirror_c["mirror"] = {"source": "p_0002", "plane": "x"}
	parts["p_0003"] = mirror_c
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "mirror_of_mirror")


func test_joint_part_missing_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	d["joints"] = {
		"j_0001": {
			"a": "p_0001",
			"b": "totally_missing_joint_partner",
			"mode": "open",
			"hatch": {"family": "", "manufacturer": "", "params": {}},
		}
	}
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "joint_part_missing")


func test_joint_not_overlapping_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var far_attach: Dictionary = {"yaw": 0.0, "pitch": 0.0, "roll": 0.0, "offset": 1000.0}
	parts["p_0002"] = _part_dict(
		"p_0001", _family_id, _manufacturer_id, _default_params,
		far_attach, [1.0, 1.0, 1.0], "far_away"
	)
	d["joints"] = {
		"j_0001": {
			"a": "p_0001",
			"b": "p_0002",
			"mode": "open",
			"hatch": {"family": "", "manufacturer": "", "params": {}},
		}
	}
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "joint_not_overlapping")


func test_component_cycle_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var instance_a: Dictionary = _part_dict(
		"", "comp_b", "", {}, _flush_attach(), [1.0, 1.0, 1.0], "inst_a"
	)
	instance_a["kind"] = "component_instance"
	var instance_b: Dictionary = _part_dict(
		"", "comp_a", "", {}, _flush_attach(), [1.0, 1.0, 1.0], "inst_b"
	)
	instance_b["kind"] = "component_instance"
	d["components"] = {
		"comp_a": {"label": "A", "root": "cp_0001", "parts": {"cp_0001": instance_a}},
		"comp_b": {"label": "B", "root": "cp_0002", "parts": {"cp_0002": instance_b}},
	}
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "component_cycle")


func test_component_missing_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var parts: Dictionary = d["parts"]
	var instance_dict: Dictionary = _part_dict(
		"p_0001", "totally_missing_component_id", "", {},
		_flush_attach(), [1.0, 1.0, 1.0], "dangling_instance"
	)
	instance_dict["kind"] = "component_instance"
	parts["p_0002"] = instance_dict
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "component_missing")


func test_budget_exceeded_fires() -> void:
	var d: Dictionary = _base_doc_dict()
	var doc: ShipDoc = ShipDoc.from_dict(d)
	var cfg: ShipConfig = ShipConfig.defaults()
	cfg.max_bbox_m = Vector3(0.0001, 0.0001, 0.0001)
	cfg.max_internal_volume_m3 = 0.0000001
	cfg.max_weight_kg = 0.0000001
	cfg.max_cost = 0.0000001
	_assert_code_fires(ShipValidate.validate(doc, _data, cfg), "budget_exceeded")
