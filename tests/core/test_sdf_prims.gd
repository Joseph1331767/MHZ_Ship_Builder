# Known point -> known distance, per primitive in core/sdf/sdf_prims.gd, plus the property
# that actually matters for a correct SDF: abs(sdf(p)) must never exceed the true distance
# from p to the surface (an SDF may underestimate near a warp, but a raw analytic primitive
# must be exact). Reference distances below are hand-derived from the same textbook
# analytic forms the contract calls "standard analytic forms" (box/sphere/cylinder/capsule/
# torus formulas used throughout SDF literature), independent of SdfPrims' own code, so a
# broken primitive is caught rather than rubber-stamped.
class_name TestSdfPrims
extends GdUnitTestSuite

const TOL: float = 0.0001


func _ref_box(p: Vector3, half: Vector3) -> float:
	var q: Vector3 = Vector3(absf(p.x) - half.x, absf(p.y) - half.y, absf(p.z) - half.z)
	var outside: Vector3 = Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	var inside: float = minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
	return outside.length() + inside


func _ref_sphere(p: Vector3, r: float) -> float:
	return p.length() - r


func _ref_cylinder(p: Vector3, r: float, half_h: float) -> float:
	var d_radial: float = Vector2(p.x, p.z).length() - r
	var d_axial: float = absf(p.y) - half_h
	var outside: Vector2 = Vector2(maxf(d_radial, 0.0), maxf(d_axial, 0.0))
	var inside: float = minf(maxf(d_radial, d_axial), 0.0)
	return outside.length() + inside


func _ref_capsule(p: Vector3, r: float, half_h: float) -> float:
	var cy: float = clampf(p.y, -half_h, half_h)
	var q: Vector3 = p - Vector3(0.0, cy, 0.0)
	return q.length() - r


func _ref_torus(p: Vector3, major_r: float, minor_r: float) -> float:
	var q: Vector2 = Vector2(Vector2(p.x, p.z).length() - major_r, p.y)
	return q.length() - minor_r


func test_sphere_known_points() -> void:
	assert_float(SdfPrims.sphere(Vector3(3.0, 0.0, 0.0), 2.0)).is_equal_approx(1.0, TOL)
	assert_float(SdfPrims.sphere(Vector3.ZERO, 2.0)).is_equal_approx(-2.0, TOL)
	assert_float(SdfPrims.sphere(Vector3(2.0, 0.0, 0.0), 2.0)).is_equal_approx(0.0, TOL)


func test_sphere_matches_reference_distance_everywhere_sampled() -> void:
	var r: float = 2.0
	var points: Array[Vector3] = [
		Vector3(3.0, 0.0, 0.0),
		Vector3(0.0, -4.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 1.0, 1.0),
		Vector3(10.0, 0.0, 0.0),
	]
	for p: Vector3 in points:
		var expected: float = _ref_sphere(p, r)
		var actual: float = SdfPrims.sphere(p, r)
		assert_float(absf(actual)).append_failure_message(
			"sphere(%s) = %f must not exceed true surface distance %f" % [p, actual, absf(expected)]
		).is_less_equal(absf(expected) + TOL)
		assert_float(actual).is_equal_approx(expected, TOL)


func test_box_known_points() -> void:
	var half: Vector3 = Vector3(1.0, 1.0, 1.0)
	assert_float(SdfPrims.box(Vector3(2.0, 0.0, 0.0), half)).is_equal_approx(1.0, TOL)
	assert_float(SdfPrims.box(Vector3(2.0, 2.0, 2.0), half)).is_equal_approx(sqrt(3.0), TOL)
	assert_float(SdfPrims.box(Vector3(0.5, 0.0, 0.0), half)).is_equal_approx(-0.5, TOL)
	assert_float(SdfPrims.box(Vector3(1.0, 0.0, 0.0), half)).is_equal_approx(0.0, TOL)


func test_box_matches_reference_distance_everywhere_sampled() -> void:
	var half: Vector3 = Vector3(1.0, 1.0, 1.0)
	var points: Array[Vector3] = [
		Vector3(1.0, 1.0, 2.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(-3.0, 0.0, 0.0),
		Vector3(0.9, 0.9, 0.9),
	]
	for p: Vector3 in points:
		var expected: float = _ref_box(p, half)
		var actual: float = SdfPrims.box(p, half)
		assert_float(absf(actual)).append_failure_message(
			"box(%s) = %f must not exceed true surface distance %f" % [p, actual, absf(expected)]
		).is_less_equal(absf(expected) + TOL)
		assert_float(actual).is_equal_approx(expected, TOL)


func test_cylinder_known_points() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	assert_float(SdfPrims.cylinder(Vector3(3.0, 0.0, 0.0), r, half_h)).is_equal_approx(2.0, TOL)
	assert_float(SdfPrims.cylinder(Vector3(0.0, 4.0, 0.0), r, half_h)).is_equal_approx(2.0, TOL)
	assert_float(SdfPrims.cylinder(Vector3.ZERO, r, half_h)).is_equal_approx(-1.0, TOL)


func test_cylinder_matches_reference_distance_everywhere_sampled() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	var points: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(2.0, 3.0, 0.0),
	]
	for p: Vector3 in points:
		var expected: float = _ref_cylinder(p, r, half_h)
		var actual: float = SdfPrims.cylinder(p, r, half_h)
		assert_float(absf(actual)).append_failure_message(
			"cylinder(%s) = %f must not exceed true surface distance %f" % [
				p, actual, absf(expected)
			]
		).is_less_equal(absf(expected) + TOL)
		assert_float(actual).is_equal_approx(expected, TOL)


func test_capsule_known_points() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	assert_float(SdfPrims.capsule(Vector3(3.0, 0.0, 0.0), r, half_h)).is_equal_approx(2.0, TOL)
	assert_float(SdfPrims.capsule(Vector3(0.0, 5.0, 0.0), r, half_h)).is_equal_approx(2.0, TOL)
	assert_float(SdfPrims.capsule(Vector3.ZERO, r, half_h)).is_equal_approx(-1.0, TOL)


func test_capsule_matches_reference_distance_everywhere_sampled() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	var points: Array[Vector3] = [
		Vector3(0.0, -5.0, 0.0),
		Vector3(1.0, 2.0, 0.0),
	]
	for p: Vector3 in points:
		var expected: float = _ref_capsule(p, r, half_h)
		var actual: float = SdfPrims.capsule(p, r, half_h)
		assert_float(absf(actual)).append_failure_message(
			"capsule(%s) = %f must not exceed true surface distance %f" % [
				p, actual, absf(expected)
			]
		).is_less_equal(absf(expected) + TOL)
		assert_float(actual).is_equal_approx(expected, TOL)


func test_torus_known_points() -> void:
	var major_r: float = 3.0
	var minor_r: float = 1.0
	assert_float(SdfPrims.torus(Vector3(3.0, 0.0, 0.0), major_r, minor_r)).is_equal_approx(
		-1.0, TOL
	)
	assert_float(SdfPrims.torus(Vector3(6.0, 0.0, 0.0), major_r, minor_r)).is_equal_approx(
		2.0, TOL
	)
	assert_float(SdfPrims.torus(Vector3(3.0, 3.0, 0.0), major_r, minor_r)).is_equal_approx(
		2.0, TOL
	)
	assert_float(SdfPrims.torus(Vector3.ZERO, major_r, minor_r)).is_equal_approx(2.0, TOL)


func test_torus_matches_reference_distance_everywhere_sampled() -> void:
	var major_r: float = 3.0
	var minor_r: float = 1.0
	var on_ring: float = major_r / sqrt(2.0)
	var points: Array[Vector3] = [
		Vector3(on_ring, 0.5, on_ring),
	]
	for p: Vector3 in points:
		var expected: float = _ref_torus(p, major_r, minor_r)
		var actual: float = SdfPrims.torus(p, major_r, minor_r)
		assert_float(absf(actual)).append_failure_message(
			"torus(%s) = %f must not exceed true surface distance %f" % [p, actual, absf(expected)]
		).is_less_equal(absf(expected) + TOL)
		assert_float(actual).is_equal_approx(expected, TOL)


func test_cone_apex_and_base_are_exact_corners() -> void:
	# apex +Y, base -Y (SPEC/contract). Apex is the sole topmost point of a convex solid,
	# and the base cap is a filled disk at y = -half_h, so distance from any point directly
	# above the apex, or directly below the base center, is exact regardless of the taper
	# profile between them -- this holds for any faithful right-circular-cone SDF.
	var r: float = 1.0
	var half_h: float = 2.0
	assert_float(SdfPrims.cone(Vector3(0.0, half_h, 0.0), r, half_h)).is_equal_approx(0.0, TOL)
	assert_float(SdfPrims.cone(Vector3(0.0, -half_h, 0.0), r, half_h)).is_equal_approx(0.0, TOL)
	assert_float(SdfPrims.cone(Vector3(0.0, half_h + 3.0, 0.0), r, half_h)).is_equal_approx(
		3.0, TOL
	)
	assert_float(SdfPrims.cone(Vector3(0.0, -half_h - 3.0, 0.0), r, half_h)).is_equal_approx(
		3.0, TOL
	)


func test_cone_base_rim_corner_is_exact() -> void:
	# A point level with the base plane, outside the rim: the closest boundary point is
	# provably the rim corner itself (both the flat base cap and the receding lateral
	# surface get monotonically farther away in every other direction), so the distance is
	# exactly (query radius - base radius) regardless of the interior taper formula.
	var r: float = 1.0
	var half_h: float = 2.0
	assert_float(SdfPrims.cone(Vector3(5.0, -half_h, 0.0), r, half_h)).is_equal_approx(4.0, TOL)


func test_cone_interior_point_is_negative() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	assert_float(SdfPrims.cone(Vector3.ZERO, r, half_h)).is_less(0.0)


# --- ADR 0005: one primitive, three shapes -------------------------------------------------
#
# The whole claim of the ADR is that a cone and a capsule are POINTS IN THE CYLINDER'S PARAMETER
# SPACE, not shapes of their own. That claim is only worth what it is measured against, so each
# test below drives the general form to the corresponding special case and compares it against
# the dedicated primitive that used to be the only way to get there, over a spread of points
# inside, outside, on the flank and past both ends.


func _probe_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x: float in [0.0, 0.35, 1.0, 2.4]:
		for y: float in [-3.1, -1.0, -0.25, 0.0, 0.6, 1.0, 2.9]:
			for z: float in [0.0, 0.8, -1.7]:
				out.append(Vector3(x, y, z))
	return out


func test_capped_cone_with_equal_radii_is_exactly_the_cylinder() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	for p: Vector3 in _probe_points():
		var general: float = SdfPrims.capped_cone(p, r, r, half_h)
		var special: float = SdfPrims.cylinder(p, r, half_h)
		assert_float(general).append_failure_message(
			"capped_cone(%s, %f, %f, %f) = %f but cylinder() there is %f -- ADR 0005 claims a "
			% [p, r, r, half_h, general, special] +
			"cylinder is just a capped cone with equal ends"
		).is_equal_approx(special, TOL)


func test_capped_cone_with_a_zero_end_is_exactly_the_cone() -> void:
	var r: float = 1.0
	var half_h: float = 2.0
	for p: Vector3 in _probe_points():
		var general: float = SdfPrims.capped_cone(p, r, 0.0, half_h)
		var special: float = SdfPrims.cone(p, r, half_h)
		assert_float(general).append_failure_message(
			"capped_cone(%s, %f, 0, %f) = %f but cone() there is %f"
			% [p, r, half_h, general, special]
		).is_equal_approx(special, TOL)


func test_rounded_cone_at_full_rounding_is_exactly_the_capsule() -> void:
	# e == r on both ends turns the two end discs into hemispheres, which IS a capsule. Note the
	# half-height convention differs: rounded_cone's half_h is the TOTAL half height, while
	# SdfPrims.capsule's is the cylindrical span only, so the reference takes half_h - r.
	var r: float = 0.9
	var half_h: float = 2.5
	for p: Vector3 in _probe_points():
		var general: float = SdfPrims.rounded_cone(p, r, r, half_h, r)
		var special: float = SdfPrims.capsule(p, r, half_h - r)
		assert_float(general).append_failure_message(
			"rounded_cone(%s, %f, %f, %f, %f) = %f but the capsule of the same extent is %f"
			% [p, r, r, half_h, r, general, special]
		).is_equal_approx(special, TOL)


func test_rounded_cone_with_no_rounding_is_the_bare_capped_cone() -> void:
	for p: Vector3 in _probe_points():
		assert_float(SdfPrims.rounded_cone(p, 1.2, 0.4, 2.0, 0.0)).is_equal_approx(
			SdfPrims.capped_cone(p, 1.2, 0.4, 2.0), TOL
		)


func test_rounded_cone_keeps_its_total_extent_when_the_ends_are_rounded() -> void:
	# The reason end_round is a separate field from round_r: rounding an END must not GROW the
	# part. A player rounding a cylinder into a capsule should watch the ends curve, not watch
	# the part swell and shove its neighbours apart.
	var r: float = 1.0
	var half_h: float = 2.0
	for e: float in [0.0, 0.25, 0.6, 1.0]:
		var top: float = SdfPrims.rounded_cone(Vector3(0.0, half_h, 0.0), r, r, half_h, e)
		var side: float = SdfPrims.rounded_cone(Vector3(r, 0.0, 0.0), r, r, half_h, e)
		assert_float(top).append_failure_message(
			"end_round %f moved the +Y extreme off y = half_h (sdf there = %f)" % [e, top]
		).is_equal_approx(0.0, TOL)
		assert_float(side).append_failure_message(
			"end_round %f moved the widest flank off r (sdf there = %f)" % [e, side]
		).is_equal_approx(0.0, TOL)


func test_rounded_cone_saturates_instead_of_inverting_on_an_over_large_round() -> void:
	# An authored e larger than the solid can absorb must clamp to the capsule, never turn the
	# shape inside out. Guards the arithmetic that subtracts e from the radii.
	var r: float = 0.8
	var half_h: float = 1.4
	for p: Vector3 in _probe_points():
		assert_float(SdfPrims.rounded_cone(p, r, r, half_h, 99.0)).is_equal_approx(
			SdfPrims.rounded_cone(p, r, r, half_h, r), TOL
		)
