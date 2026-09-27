# ShipComplexity — API_CONTRACT_SPORE section 5. The load-bearing, deliberately-not-a-bug property
# here is the symmetry doubling: a part that currently generates a mirrored twin costs exactly
# twice an otherwise-identical asymmetric part. That is real, documented Spore behaviour (breaking
# symmetry halves the complexity/DNA bill) and a well-known player exploit that MUST remain
# possible, so it is asserted head-on rather than incidentally, per the class's own docs: "the test
# suite asserts the doubling on purpose so nobody quietly removes it."
class_name TestComplexity
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
	# Prefer a family with a nonzero authored complexity so the doubling assertion below is
	# actually meaningful (doubling 0.0 would pass trivially).
	for family_id: String in families:
		if ShipComplexity.base_cost(_data, family_id) > 0.0:
			_family_id = family_id
			break
	if _family_id == "":
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


func test_symmetric_part_costs_double_an_asymmetric_one() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()
	var base: float = ShipComplexity.base_cost(_data, _family_id)
	(
		assert_float(base)
		. append_failure_message(
			"family '%s' has zero base complexity -- doubling would pass trivially" % _family_id
		)
		. is_greater(0.0)
	)

	# doc.symmetry_plane defaults to "x" (on) and child.asymmetric defaults to false, so this
	# part currently pays the symmetry surcharge.
	var symmetric_cost: float = ShipComplexity.cost_of(doc, child.id, _data, cfg)
	assert_float(symmetric_cost).is_equal_approx(base * 2.0, 0.0001)

	child.asymmetric = true
	var asymmetric_cost: float = ShipComplexity.cost_of(doc, child.id, _data, cfg)
	assert_float(asymmetric_cost).is_equal_approx(base, 0.0001)

	# The doubling, stated as a ratio so the intent reads directly off the assertion.
	(
		assert_float(symmetric_cost)
		. append_failure_message(
			(
				(
					"a symmetric part must cost exactly double its asymmetric self -- this is a "
					+ "documented Spore exploit (breaking symmetry halves the bill) and must remain "
					+ "possible, symmetric=%f asymmetric=%f"
				)
				% [symmetric_cost, asymmetric_cost]
			)
		)
		. is_equal_approx(asymmetric_cost * 2.0, 0.0001)
	)


func test_cost_of_new_symmetric_is_double_asymmetric() -> void:
	var base: float = ShipComplexity.base_cost(_data, _family_id)
	var sym: float = ShipComplexity.cost_of_new(_data, _family_id, true)
	var asym: float = ShipComplexity.cost_of_new(_data, _family_id, false)
	assert_float(asym).is_equal_approx(base, 0.0001)
	assert_float(sym).is_equal_approx(base * 2.0, 0.0001)


func test_cost_of_new_agrees_with_cost_of_once_placed() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()

	# child.asymmetric == false, doc mirrors -> this part currently generates a twin, matching
	# what cost_of_new(..., symmetric = true) prices for a not-yet-placed part of this family.
	var placed_symmetric: float = ShipComplexity.cost_of(doc, child.id, _data, cfg)
	var quoted_symmetric: float = ShipComplexity.cost_of_new(_data, _family_id, true)
	(
		assert_float(placed_symmetric)
		. append_failure_message(
			(
				(
					"cost_of() once placed (%f) must agree with cost_of_new(symmetric=true) (%f) -- "
					+ "the palette's red-out test asks cost_of_new() the same question cost_of() "
					+ "answers afterwards"
				)
				% [placed_symmetric, quoted_symmetric]
			)
		)
		. is_equal_approx(quoted_symmetric, 0.0001)
	)

	child.asymmetric = true
	var placed_asymmetric: float = ShipComplexity.cost_of(doc, child.id, _data, cfg)
	var quoted_asymmetric: float = ShipComplexity.cost_of_new(_data, _family_id, false)
	(
		assert_float(placed_asymmetric)
		. append_failure_message(
			(
				(
					"cost_of() once placed and made asymmetric (%f) must agree with "
					+ "cost_of_new(symmetric=false) (%f)"
				)
				% [placed_asymmetric, quoted_asymmetric]
			)
		)
		. is_equal_approx(quoted_asymmetric, 0.0001)
	)


func test_per_part_sums_to_used() -> void:
	var doc: ShipDoc = _new_doc()
	var child_a: ShipPart = _add_child(doc, doc.root)
	var child_b: ShipPart = _add_child(doc, doc.root)
	child_b.asymmetric = true
	var cfg: ShipConfig = ShipConfig.defaults()

	var state: Dictionary = ShipComplexity.compute(doc, _data, cfg)
	var used: float = float(state["used"])
	var per_part: Dictionary = state["per_part"]
	assert_int(per_part.size()).is_equal(doc.parts.size())

	var summed: float = 0.0
	for part_id: String in per_part.keys():
		summed += float(per_part[part_id])
	(
		assert_float(summed)
		. append_failure_message(
			"sum of per_part values (%f) must equal 'used' (%f)" % [summed, used]
		)
		. is_equal_approx(used, 0.0001)
	)

	# Cross-check against cost_of() directly, so the two entry points can never quietly disagree.
	assert_float(float(per_part[child_a.id])).is_equal_approx(
		ShipComplexity.cost_of(doc, child_a.id, _data, cfg), 0.0001
	)
	assert_float(float(per_part[child_b.id])).is_equal_approx(
		ShipComplexity.cost_of(doc, child_b.id, _data, cfg), 0.0001
	)


func test_can_afford_false_exactly_when_used_plus_cost_exceeds_cap() -> void:
	var doc: ShipDoc = _new_doc()
	@warning_ignore("return_value_discarded")
	_add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()

	var used: float = float(ShipComplexity.compute(doc, _data, cfg)["used"])
	var add_symmetric: float = ShipComplexity.cost_of_new(_data, _family_id, true)
	assert_float(add_symmetric).is_greater(0.0)

	# Exactly at the cap: legal (the contract's own message format reads "used + add / cap", i.e.
	# the boundary <= cap is affordable).
	cfg.max_complexity = used + add_symmetric
	(
		assert_bool(ShipComplexity.can_afford(doc, _data, cfg, _family_id, true))
		. append_failure_message("adding a part that lands EXACTLY on the cap must be affordable")
		. is_true()
	)

	# A hair under what is needed: refused.
	cfg.max_complexity = used + add_symmetric - 0.0001
	(
		assert_bool(ShipComplexity.can_afford(doc, _data, cfg, _family_id, true))
		. append_failure_message("adding a part that would land just OVER the cap must be refused")
		. is_false()
	)

	# Comfortable headroom: legal.
	cfg.max_complexity = used + add_symmetric + 1000.0
	(
		assert_bool(ShipComplexity.can_afford(doc, _data, cfg, _family_id, true))
		. append_failure_message(
			"adding a part with plenty of headroom under the cap must be affordable"
		)
		. is_true()
	)


func test_unbounded_cap_never_refuses() -> void:
	var doc: ShipDoc = _new_doc()
	# Pile on enough parts that a finite cap would certainly refuse the next one.
	for i: int in 20:
		@warning_ignore("return_value_discarded")
		_add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()

	for cap: float in [INF, 0.0, -1.0]:
		cfg.max_complexity = cap
		(
			assert_bool(ShipComplexity.can_afford(doc, _data, cfg, _family_id, true))
			. append_failure_message("max_complexity=%s must mean unbounded and never refuse" % cap)
			. is_true()
		)
