# SPEC section 4's core promise: params fully determine the shape. Manufacturer ranges gate
# input (clamp_params), the generator turns valid params into geometry (resolve), and
# resolve must be a pure function of (family, manufacturer, params, scale) -- nothing else.
class_name TestShapeGen
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


func _shape_diff_count(a: ResolvedShape, b: ResolvedShape) -> int:
	var diffs: int = 0
	if a.base != b.base:
		diffs += 1
	if not a.size.is_equal_approx(b.size):
		diffs += 1
	if not is_equal_approx(a.round_r, b.round_r):
		diffs += 1
	if not is_equal_approx(a.taper, b.taper):
		diffs += 1
	if not is_equal_approx(a.twist_deg, b.twist_deg):
		diffs += 1
	if a.rib_count != b.rib_count:
		diffs += 1
	if not is_equal_approx(a.rib_amp, b.rib_amp):
		diffs += 1
	if not is_equal_approx(a.rib_phase, b.rib_phase):
		diffs += 1
	if not is_equal_approx(a.scallop_amp, b.scallop_amp):
		diffs += 1
	if not is_equal_approx(a.scallop_freq, b.scallop_freq):
		diffs += 1
	if not is_equal_approx(a.scallop_phase, b.scallop_phase):
		diffs += 1
	if not is_equal_approx(a.lipschitz, b.lipschitz):
		diffs += 1
	if a.origin_inside != b.origin_inside:
		diffs += 1
	if not is_equal_approx(a.bound_radius, b.bound_radius):
		diffs += 1
	return diffs


func test_default_params_land_inside_effective_ranges() -> void:
	# Black-box check that does not need to know effective_ranges' internal Dictionary
	# shape: default params are valid by construction, so clamping them must be a no-op.
	var defaults: Dictionary = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	var clamped: Dictionary = ShapeGen.clamp_params(_data, _family_id, _manufacturer_id, defaults)
	assert_str(ShipCanonical.canonical_json(clamped)).append_failure_message(
		"default_params() produced a Dictionary that clamp_params() changed -- defaults are " +
		"not inside effective_ranges"
	).is_equal(ShipCanonical.canonical_json(defaults))


func test_effective_ranges_is_not_empty() -> void:
	var ranges: Dictionary = ShapeGen.effective_ranges(_data, _family_id, _manufacturer_id)
	assert_dict(ranges).is_not_empty()


func test_clamp_params_pulls_values_above_range_back_down() -> void:
	var defaults: Dictionary = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	var bad_params: Dictionary = {}
	var numeric_keys: int = 0
	for key: String in defaults.keys():
		var v: Variant = defaults[key]
		if typeof(v) == TYPE_FLOAT:
			bad_params[key] = 1.0e9
			numeric_keys += 1
		elif typeof(v) == TYPE_INT:
			bad_params[key] = 1000000000
			numeric_keys += 1
		else:
			bad_params[key] = v
	assert_int(numeric_keys).append_failure_message(
		"family '%s' exposes no numeric params -- clamp behaviour cannot be exercised" %
		_family_id
	).is_greater(0)
	var clamped: Dictionary = ShapeGen.clamp_params(_data, _family_id, _manufacturer_id, bad_params)
	for key: String in bad_params.keys():
		var v: Variant = bad_params[key]
		if typeof(v) == TYPE_FLOAT:
			assert_float(clamped[key] as float).append_failure_message(
				"param '%s' = 1e9 was not clamped down" % key
			).is_not_equal(1.0e9)
		elif typeof(v) == TYPE_INT:
			assert_int(clamped[key] as int).append_failure_message(
				"param '%s' = 1e9 was not clamped down" % key
			).is_not_equal(1000000000)


func test_clamp_params_pulls_values_below_range_back_up() -> void:
	var defaults: Dictionary = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	var bad_params: Dictionary = {}
	for key: String in defaults.keys():
		var v: Variant = defaults[key]
		if typeof(v) == TYPE_FLOAT:
			bad_params[key] = -1.0e9
		elif typeof(v) == TYPE_INT:
			bad_params[key] = -1000000000
		else:
			bad_params[key] = v
	var clamped: Dictionary = ShapeGen.clamp_params(_data, _family_id, _manufacturer_id, bad_params)
	for key: String in bad_params.keys():
		var v: Variant = bad_params[key]
		if typeof(v) == TYPE_FLOAT:
			assert_float(clamped[key] as float).append_failure_message(
				"param '%s' = -1e9 was not clamped up" % key
			).is_not_equal(-1.0e9)
		elif typeof(v) == TYPE_INT:
			assert_int(clamped[key] as int).append_failure_message(
				"param '%s' = -1e9 was not clamped up" % key
			).is_not_equal(-1000000000)


func test_resolve_is_pure_for_identical_inputs() -> void:
	var params_a: Dictionary = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	var params_b: Dictionary = params_a.duplicate(true)
	var scale: Vector3 = Vector3.ONE
	var shape_a: ResolvedShape = ShapeGen.resolve(
		_data, _family_id, _manufacturer_id, params_a, scale
	)
	var shape_b: ResolvedShape = ShapeGen.resolve(
		_data, _family_id, _manufacturer_id, params_b, scale
	)
	assert_int(_shape_diff_count(shape_a, shape_b)).append_failure_message(
		"resolve() must be pure: identical (family, manufacturer, params, scale) produced " +
		"a shape with differing fields"
	).is_equal(0)


func test_resolve_changes_shape_when_a_param_changes() -> void:
	var defaults: Dictionary = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	var scale: Vector3 = Vector3.ONE
	var base_shape: ResolvedShape = ShapeGen.resolve(
		_data, _family_id, _manufacturer_id, defaults, scale
	)
	var any_param_moved_the_shape: bool = false
	for key: String in defaults.keys():
		var v: Variant = defaults[key]
		var perturbed: Dictionary = defaults.duplicate(true)
		if typeof(v) == TYPE_FLOAT:
			perturbed[key] = (v as float) * 0.5 + 0.01
		elif typeof(v) == TYPE_INT:
			perturbed[key] = (v as int) + 1
		else:
			continue
		var clamped: Dictionary = ShapeGen.clamp_params(
			_data, _family_id, _manufacturer_id, perturbed
		)
		if ShipCanonical.canonical_json(clamped) == ShipCanonical.canonical_json(defaults):
			continue
		var perturbed_shape: ResolvedShape = ShapeGen.resolve(
			_data, _family_id, _manufacturer_id, clamped, scale
		)
		if _shape_diff_count(base_shape, perturbed_shape) > 0:
			any_param_moved_the_shape = true
	assert_bool(any_param_moved_the_shape).append_failure_message(
		"perturbing every numeric param of family '%s' individually never changed the " %
		_family_id + "resolved shape -- SPEC 4's param->shape promise is broken"
	).is_true()


func test_param_complexity_is_deterministic_and_non_negative() -> void:
	var defaults: Dictionary = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	var c1: float = ShapeGen.param_complexity(_data, _family_id, defaults)
	var c2: float = ShapeGen.param_complexity(_data, _family_id, defaults)
	assert_float(c1).is_equal_approx(c2, 0.0000001)
	assert_float(c1).is_greater_equal(0.0)


# --- ADR 0005: the end params, and what must NOT move because of them -----------------------


func _cylinder_family() -> String:
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var shape: ResolvedShape = ShapeGen.resolve(
			_data, family_id, mfrs[0], {}, Vector3.ONE
		)
		if shape.base == ResolvedShape.Base.CYLINDER:
			return family_id
	return ""


func test_a_shape_with_no_end_params_is_still_a_plain_cylinder() -> void:
	# The compatibility property the ADR turns on. `radius_b` defaults NEGATIVE, meaning "match
	# size.x"; a default of 0.0 would have turned every pre-ADR cylinder into a spike and nothing
	# would have errored.
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = ResolvedShape.Base.CYLINDER
	shape.size = Vector3(0.7, 2.0, 0.7)
	shape.refresh()
	assert_float(shape.radius_b).append_failure_message(
		"a hand-built CYLINDER resolved radius_b to %f instead of its size.x" % shape.radius_b
	).is_equal_approx(0.7, 0.000001)
	assert_float(shape.sdf(Vector3(0.7, 0.0, 0.0))).is_equal_approx(0.0, 0.0001)
	assert_float(shape.sdf(Vector3(0.7, 1.9, 0.0))).is_equal_approx(0.0, 0.0001)


func test_end_radius_ratio_zero_makes_a_point_tipped_cone() -> void:
	var family_id: String = _cylinder_family()
	assert_str(family_id).append_failure_message(
		"no family resolves to a CYLINDER base -- ADR 0005 put the cone and the capsule inside "
		+ "that one family, so losing it loses both"
	).is_not_empty()
	var mfr: String = _data.manufacturers_for(family_id)[0]
	var ranges: Dictionary = ShapeGen.effective_ranges(_data, family_id, mfr)
	assert_dict(ranges).append_failure_message(
		"family '%s' exposes no end_radius param, so a player cannot make a cone" % family_id
	).contains_keys(["end_radius"])

	# round (inflate) and taper both move the surface, and the first manufacturer in the pack
	# authors a non-zero default for round. Zeroing them isolates the one param under test --
	# without that this measures the inflate radius and calls it a cone.
	var params: Dictionary = ShapeGen.default_params(_data, family_id, mfr)
	params["end_radius"] = 0.0
	params["end_round"] = 0.0
	params["round"] = 0.0
	params["taper"] = 0.0
	var shape: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr, params, Vector3.ONE)
	assert_float(shape.radius_b).append_failure_message(
		"end_radius 0.0 left radius_b at %f -- the +Y end did not close to a point" % shape.radius_b
	).is_equal_approx(0.0, 0.000001)
	# The tip is ON the surface and the shape is genuinely narrower up there than down here.
	var h: float = absf(shape.size.y)
	assert_float(shape.sdf(Vector3(0.0, h, 0.0))).is_equal_approx(0.0, 0.001)
	var low_width: float = shape.sdf(Vector3(absf(shape.size.x) * 0.5, -h * 0.9, 0.0))
	var high_width: float = shape.sdf(Vector3(absf(shape.size.x) * 0.5, h * 0.9, 0.0))
	assert_float(high_width).append_failure_message(
		"the +Y end is not narrower than the -Y end, so end_radius did nothing"
	).is_greater(low_width)


func test_end_round_ratio_one_makes_a_capsule() -> void:
	var family_id: String = _cylinder_family()
	var mfr: String = _data.manufacturers_for(family_id)[0]
	var params: Dictionary = ShapeGen.default_params(_data, family_id, mfr)
	var ranges: Dictionary = ShapeGen.effective_ranges(_data, family_id, mfr)
	var round_range: Dictionary = ranges.get("end_round", {})
	params["end_radius"] = 1.0
	params["end_round"] = float(round_range.get("max", 1.0))
	params["round"] = 0.0
	params["taper"] = 0.0
	var shape: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr, params, Vector3.ONE)
	var r: float = absf(shape.size.x)
	var h: float = absf(shape.size.y)
	assert_float(shape.end_round).append_failure_message(
		"end_round resolved to %f, not the %f the family's own max ratio asks for"
		% [shape.end_round, r * float(round_range.get("max", 1.0))]
	).is_equal_approx(r * float(round_range.get("max", 1.0)), 0.000001)
	# The pole stays where a cylinder's pole was: rounding an end does not grow the part.
	assert_float(shape.sdf(Vector3(0.0, h, 0.0))).is_equal_approx(0.0, 0.001)


func test_a_plain_cylinder_scores_no_end_shaping_complexity() -> void:
	# end_radius is the one param whose NEUTRAL value sits mid-range. Scoring it from the range
	# minimum would have charged every plain tube for a cone it is not.
	var family_id: String = _cylinder_family()
	var mfr: String = _data.manufacturers_for(family_id)[0]
	var plain: Dictionary = ShapeGen.default_params(_data, family_id, mfr)
	plain["end_radius"] = 1.0
	var coned: Dictionary = plain.duplicate(true)
	coned["end_radius"] = 0.0
	var plain_cost: float = ShapeGen.param_complexity(_data, family_id, plain)
	var coned_cost: float = ShapeGen.param_complexity(_data, family_id, coned)
	assert_float(coned_cost).append_failure_message(
		"a cone (%f) does not cost more than the plain cylinder it was shaped from (%f)"
		% [coned_cost, plain_cost]
	).is_greater(plain_cost)


# --- ADR 0007: skew ------------------------------------------------------------------------


func test_shear_leans_the_part_without_moving_its_centre_or_its_height() -> void:
	# The three properties that make this a SKEW and not something else: the +Y end moves one way,
	# the -Y end moves the other, and the middle does not move at all. Measured on a bare box so
	# the expected offsets are exact rather than sampled off a curve.
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = ResolvedShape.Base.BOX
	shape.size = Vector3.ONE
	shape.shear = Vector2(0.5, 0.0)
	shape.refresh()

	# Centre: unchanged, so a sheared part does not walk away from its own origin.
	assert_float(shape.sdf(Vector3(1.0, 0.0, 0.0))).is_equal_approx(0.0, 0.0001)
	# Near the +Y end: the flank has slid +0.5 * y in X, so at y = 0.9 the surface is at x = 1.45
	# and x = 1.0 is 0.1 inside it. Sampled just short of the corner on purpose - exactly at
	# (1.5, 1.0) the point sits on the EDGE where the flank meets the top face, and both "on the
	# surface" and "inside" are true there, which would make the assertion prove nothing.
	assert_float(shape.sdf(Vector3(1.45, 0.9, 0.0))).is_equal_approx(0.0, 0.0001)
	assert_float(shape.sdf(Vector3(1.0, 0.9, 0.0))).is_equal_approx(-0.1, 0.0001)
	# -Y end: the same distance the other way.
	assert_float(shape.sdf(Vector3(-1.45, -0.9, 0.0))).is_equal_approx(0.0, 0.0001)
	assert_float(shape.sdf(Vector3(-1.0, -0.9, 0.0))).is_equal_approx(-0.1, 0.0001)
	# Height is untouched: a shear moves the domain sideways, never along Y.
	assert_float(shape.sdf(Vector3(0.5, 1.0, 0.0))).is_equal_approx(0.0, 0.0001)


func test_zero_shear_is_bit_identical_to_no_shear() -> void:
	# The compatibility property the whole ADR turns on: inserting an op into the WARP stage is
	# only safe because at its default it is the identity. Asserted exactly, not approximately.
	var plain: ResolvedShape = ResolvedShape.new()
	plain.base = ResolvedShape.Base.CYLINDER
	plain.size = Vector3(0.5, 1.5, 0.5)
	plain.taper = 0.2
	plain.twist_deg = 25.0
	plain.refresh()
	var sheared: ResolvedShape = ResolvedShape.new()
	sheared.base = ResolvedShape.Base.CYLINDER
	sheared.size = Vector3(0.5, 1.5, 0.5)
	sheared.taper = 0.2
	sheared.twist_deg = 25.0
	sheared.shear = Vector2.ZERO
	sheared.refresh()
	for x: float in [-2.0, -0.3, 0.0, 0.4, 1.7]:
		for y: float in [-2.2, -0.5, 0.0, 1.1, 2.4]:
			var p: Vector3 = Vector3(x, y, 0.6)
			assert_float(sheared.sdf(p)).append_failure_message(
				"a zero shear changed the field at %s" % p
			).is_equal(plain.sdf(p))


func test_shear_widens_the_bounds_it_leans_into() -> void:
	# A bound that did not grow would clip the leaning end straight out of the bake, and the bake
	# is the one place nobody would see it happen.
	var upright: ResolvedShape = ResolvedShape.new()
	upright.base = ResolvedShape.Base.BOX
	upright.size = Vector3.ONE
	upright.refresh()
	var leaning: ResolvedShape = ResolvedShape.new()
	leaning.base = ResolvedShape.Base.BOX
	leaning.size = Vector3.ONE
	leaning.shear = Vector2(0.5, 0.0)
	leaning.refresh()
	var grew: float = leaning.local_aabb().size.x - upright.local_aabb().size.x
	assert_float(grew).append_failure_message(
		"a 0.5 lean over a 1 m half-height should widen the X bound by 1.0 m, it grew %f" % grew
	).is_equal_approx(1.0, 0.0001)
	assert_float(leaning.local_aabb().size.y).is_equal_approx(upright.local_aabb().size.y, 0.0001)
	# And the bound must actually CONTAIN the leaning corner it grew for.
	assert_bool(leaning.local_aabb().has_point(Vector3(1.49, 0.99, 0.0))).append_failure_message(
		"the sheared bound does not contain the sheared part's own corner"
	).is_true()


func test_every_family_exposes_the_skew_params() -> void:
	# The handle drives a PARAM, and clamp_params() pins a disabled op's params to neutral - so a
	# family that forgot to list the op would give the player a handle that silently does nothing.
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var ranges: Dictionary = ShapeGen.effective_ranges(_data, family_id, mfrs[0])
		assert_dict(ranges).append_failure_message(
			"family '%s' exposes no skew params, so its skew handle would do nothing" % family_id
		).contains_keys(["skew_x", "skew_z"])
		var spec: Dictionary = ranges["skew_x"]
		assert_float(float(spec["max"]) - float(spec["min"])).append_failure_message(
			"family '%s' pins skew_x to a single value" % family_id
		).is_greater(0.0)

