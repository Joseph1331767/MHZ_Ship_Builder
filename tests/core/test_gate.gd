# ShipGate — API_CONTRACT_SPORE section 6. Two hard-blocking gates share one Reason enum and one
# refusal shape; the whole mitigation for stacking two gates is that a refusal always NAMES the
# quantity that failed ("WEIGHT 5.01Mkg / 5.00Mkg - OVER BUDGET"), so every Reason value is driven
# to fire at least once here, and every refusal message is checked for the specific token a player
# would look for, not just checked for non-emptiness.
class_name TestGate
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


func _new_doc() -> ShipDoc:
	return ShipDoc.create_new(_family_id, _manufacturer_id, _data)


func _add_child(doc: ShipDoc, parent_id: String) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = parent_id
	part.kind = ShipPart.KIND_PRIMITIVE
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = 0.0
	part.pitch = 0.0
	part.rot = Vector3.ZERO
	part.offset = 0.0
	part.scale = Vector3.ONE
	part.blend = 0.0
	part.display_name = "part " + part.id
	@warning_ignore("return_value_discarded")
	doc.add_part(part)
	return part


## A budget config with every cap generously large, so a caller can tighten exactly ONE and be
## sure the others cannot accidentally also fire.
func _lenient_cfg() -> ShipConfig:
	var cfg: ShipConfig = ShipConfig.defaults()
	cfg.max_bbox_m = Vector3(1.0e6, 1.0e6, 1.0e6)
	cfg.max_internal_volume_m3 = 1.0e12
	cfg.max_weight_kg = 1.0e12
	cfg.max_cost = 1.0e12
	return cfg


func _lenient_metrics() -> ShipMetrics:
	var m: ShipMetrics = ShipMetrics.new()
	m.bbox = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	m.internal_volume_m3 = 0.0
	m.weight_kg = 0.0
	m.cost = 0.0
	return m


func test_ok_reason_on_a_legal_check() -> void:
	var doc: ShipDoc = _new_doc()
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)
	var cfg: ShipConfig = _lenient_cfg()
	var result: Dictionary = ShipGate.check_save(doc, _data, cfg)
	assert_bool(bool(result["ok"])).append_failure_message(
		"a 3-part doc with lenient budgets should pass check_save(), got: %s" % [result]
	).is_true()
	assert_int(int(result["reason"])).is_equal(ShipGate.Reason.OK)
	assert_str(String(result["message"])).is_equal("")


func test_complexity_reason_fires_and_names_complexity() -> void:
	var doc: ShipDoc = _new_doc()
	var cfg: ShipConfig = _lenient_cfg()
	var base: float = ShipComplexity.base_cost(_data, _family_id)
	assert_float(base).append_failure_message(
		"family '%s' has zero base complexity -- a tiny cap below it would not be a real test"
		% _family_id
	).is_greater(0.0)
	cfg.max_complexity = 0.5 * base

	var add_result: Dictionary = ShipGate.check_add(doc, _data, cfg, _family_id, true)
	assert_bool(bool(add_result["ok"])).append_failure_message(
		"adding a part over a tiny complexity cap must be refused, got: %s" % [add_result]
	).is_false()
	assert_int(int(add_result["reason"])).is_equal(ShipGate.Reason.COMPLEXITY)
	assert_str(String(add_result["message"])).append_failure_message(
		"a COMPLEXITY refusal message must name COMPLEXITY, got: '%s'" % [add_result["message"]]
	).contains("COMPLEXITY")

	# The palette's exploit-preserving hint differs by whether the caller is asking about a
	# symmetric (mirrored) placement or not -- both hints must still name COMPLEXITY.
	var symmetric_msg: String = String(add_result["message"])
	assert_str(symmetric_msg).contains("BREAK SYMMETRY")
	var asym_result: Dictionary = ShipGate.check_add(doc, _data, cfg, _family_id, false)
	assert_bool(bool(asym_result["ok"])).is_false()
	assert_str(String(asym_result["message"])).contains("COMPLEXITY")


func test_complexity_reason_fires_from_check_doc_when_already_over() -> void:
	var doc: ShipDoc = _new_doc()
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)
	var cfg: ShipConfig = _lenient_cfg()
	var used: float = float(ShipComplexity.compute(doc, _data, cfg)["used"])
	assert_float(used).is_greater(0.0)
	cfg.max_complexity = used * 0.5

	var result: Dictionary = ShipGate.check_doc(doc, _data, cfg)
	assert_bool(bool(result["ok"])).append_failure_message(
		"a doc already over its complexity cap must fail check_doc(), got: %s" % [result]
	).is_false()
	assert_int(int(result["reason"])).is_equal(ShipGate.Reason.COMPLEXITY)
	assert_str(String(result["message"])).contains("COMPLEXITY")


func test_min_parts_reason_refuses_below_three_and_passes_at_exactly_three() -> void:
	var doc: ShipDoc = _new_doc()
	var cfg: ShipConfig = _lenient_cfg()
	assert_int(cfg.min_parts_to_save).is_equal(3)

	# 1 part (root only).
	var one_part: Dictionary = ShipGate.check_save(doc, _data, cfg)
	assert_bool(bool(one_part["ok"])).is_false()
	assert_int(int(one_part["reason"])).is_equal(ShipGate.Reason.MIN_PARTS)
	assert_str(String(one_part["message"])).append_failure_message(
		"a MIN_PARTS refusal must name the part count, got: '%s'" % [one_part["message"]]
	).contains("3")

	# 2 parts.
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)
	var two_parts: Dictionary = ShipGate.check_save(doc, _data, cfg)
	assert_bool(bool(two_parts["ok"])).append_failure_message(
		"a 2-part doc must still be refused (min is 3), got: %s" % [two_parts]
	).is_false()
	assert_int(int(two_parts["reason"])).is_equal(ShipGate.Reason.MIN_PARTS)

	# Exactly 3 parts: passes.
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)
	assert_int(doc.parts.size()).is_equal(3)
	var three_parts: Dictionary = ShipGate.check_save(doc, _data, cfg)
	assert_bool(bool(three_parts["ok"])).append_failure_message(
		"a doc with exactly the minimum part count must pass check_save(), got: %s"
		% [three_parts]
	).is_true()
	assert_int(int(three_parts["reason"])).is_equal(ShipGate.Reason.OK)


func test_budget_bbox_reason_fires_and_names_the_worst_axis() -> void:
	var cfg: ShipConfig = _lenient_cfg()
	cfg.max_bbox_m = Vector3(100.0, 1.0, 100.0)
	var m: ShipMetrics = _lenient_metrics()
	# Only Y is over its cap; X and Z are tiny relative to their (also lenient) caps. Picking Y
	# (not X) as the worst axis matters: the literal word "BBOX" already contains an "X", so
	# asserting the message contains "X" would pass even if axis-naming were broken.
	m.bbox = AABB(Vector3(-0.5, -2.5, -0.5), Vector3(1.0, 5.0, 1.0))

	var result: Dictionary = ShipGate.check_metrics(m, cfg)
	assert_bool(bool(result["ok"])).append_failure_message(
		"a bbox over its per-axis cap must be refused, got: %s" % [result]
	).is_false()
	assert_int(int(result["reason"])).is_equal(ShipGate.Reason.BUDGET_BBOX)
	var message: String = String(result["message"])
	assert_str(message).append_failure_message(
		"a BUDGET_BBOX refusal must name BBOX, got: '%s'" % [message]
	).contains("BBOX")
	assert_str(message).append_failure_message(
		"a BUDGET_BBOX refusal must name the worst axis (Y here), got: '%s'" % [message]
	).contains("Y")


func test_budget_volume_reason_fires_and_names_volume() -> void:
	var cfg: ShipConfig = _lenient_cfg()
	cfg.max_internal_volume_m3 = 1.0
	var m: ShipMetrics = _lenient_metrics()
	m.internal_volume_m3 = 100.0

	var result: Dictionary = ShipGate.check_metrics(m, cfg)
	assert_bool(bool(result["ok"])).is_false()
	assert_int(int(result["reason"])).is_equal(ShipGate.Reason.BUDGET_VOLUME)
	assert_str(String(result["message"])).append_failure_message(
		"a BUDGET_VOLUME refusal must name VOLUME, got: '%s'" % [result["message"]]
	).contains("VOLUME")


func test_budget_weight_reason_fires_and_names_weight() -> void:
	var cfg: ShipConfig = _lenient_cfg()
	cfg.max_weight_kg = 1.0
	var m: ShipMetrics = _lenient_metrics()
	m.weight_kg = 100.0

	var result: Dictionary = ShipGate.check_metrics(m, cfg)
	assert_bool(bool(result["ok"])).is_false()
	assert_int(int(result["reason"])).is_equal(ShipGate.Reason.BUDGET_WEIGHT)
	assert_str(String(result["message"])).append_failure_message(
		"a BUDGET_WEIGHT refusal must name WEIGHT, got: '%s'" % [result["message"]]
	).contains("WEIGHT")


func test_budget_cost_reason_fires_and_names_cost() -> void:
	var cfg: ShipConfig = _lenient_cfg()
	cfg.max_cost = 1.0
	var m: ShipMetrics = _lenient_metrics()
	m.cost = 100.0

	var result: Dictionary = ShipGate.check_metrics(m, cfg)
	assert_bool(bool(result["ok"])).is_false()
	assert_int(int(result["reason"])).is_equal(ShipGate.Reason.BUDGET_COST)
	assert_str(String(result["message"])).append_failure_message(
		"a BUDGET_COST refusal must name COST, got: '%s'" % [result["message"]]
	).contains("COST")


func test_every_reason_value_is_reachable() -> void:
	# Documents, in one place, that this suite actually drives every Reason enum member at least
	# once -- checked against ShipGate.Reason.values() itself (not a hardcoded count) so that
	# adding a new Reason without a test for it fails HERE instead of going unnoticed.
	var covered: Array[int] = [
		ShipGate.Reason.OK,
		ShipGate.Reason.COMPLEXITY,
		ShipGate.Reason.BUDGET_BBOX,
		ShipGate.Reason.BUDGET_VOLUME,
		ShipGate.Reason.BUDGET_WEIGHT,
		ShipGate.Reason.BUDGET_COST,
		ShipGate.Reason.MIN_PARTS,
	]
	var all_values: Array = ShipGate.Reason.values()
	assert_int(covered.size()).append_failure_message(
		(
			"ShipGate.Reason has %d members but this suite's 'covered' list only names %d -- " +
			"a new Reason was added without a test driving it"
		) % [all_values.size(), covered.size()]
	).is_equal(all_values.size())
	for value: int in all_values:
		assert_bool(covered.has(value)).append_failure_message(
			"Reason value %d is not covered by any test in this suite" % value
		).is_true()
