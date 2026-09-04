# SnapTargets — API_CONTRACT_SPORE section 1. Covers the four properties the contract actually
# promises: for_shape() is deterministic and ids are unique within one shape's array; a box's
# axis-aligned face sits at the exact analytic point (the Newton projection early-outs before it
# takes a step, so there is no projection noise to tolerate); every generated point really lies on
# the resolved (possibly warped) surface; a cylinder/cone/capsule rim is always the frozen 8 points
# and every shape carries a "center"; nearest() and apply_scale() behave as documented.
#
# Base primitives for the geometric/statistical tests are discovered dynamically from whatever
# res://data ships (AGENTS: never hardcode a family id), the same pattern test_bake.gd and
# test_metrics.gd already use for "find me a family that resolves to base X". The two exactness
# tests build a ResolvedShape BY HAND instead: "a box of half-extent 1" is a property of the test
# (SnapTargets.for_shape() takes a ResolvedShape, not a family — no ShipData is needed to call it
# at all), and pulling that half-extent from whichever family happens to be BOX-based would smuggle
# an assumption about the data pack's base_size back in, which is exactly what dynamic discovery
# exists to avoid.
class_name TestSnapTargets
extends GdUnitTestSuite

const TOL_TIGHT: Vector3 = Vector3(1e-9, 1e-9, 1e-9)
const TOL_NORMAL: Vector3 = Vector3(1e-5, 1e-5, 1e-5)

var _data: ShipData


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	assert_bool(ok).append_failure_message(
		"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
	).is_true()


func _zeroed(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in d.keys():
		var v: Variant = d[key]
		if typeof(v) == TYPE_FLOAT:
			out[key] = 0.0
		elif typeof(v) == TYPE_INT:
			out[key] = 0
		else:
			out[key] = v
	return out


## First family whose zeroed-param shape resolves to `base`, at unit scale.
##
## Falls back to a synthetic unwarped primitive when no family produces that base. Since ADR 0005
## no family produces CONE or CAPSULE -- both are cylinder params now -- but both enum values are
## still pinned by API_CONTRACT section 6, still evaluate in ResolvedShape.sdf(), and are still
## reachable from a document written before the ADR. Skipping them because the PACK stopped
## producing them would quietly retire the only coverage the code path has.
func _find_shape(base: int) -> ResolvedShape:
	var from_pack: ResolvedShape = _find_shape_in_pack(base)
	if from_pack != null:
		return from_pack
	return _synthetic(base)


## A bare primitive with every op off, for a base the data pack no longer ships.
func _synthetic(base: int) -> ResolvedShape:
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = base
	# The size layout is per-base (see ResolvedShape's class docs). (1, 1, 1) is a legal reading
	# for every base except TORUS, whose major radius must exceed its minor or the hole closes.
	shape.size = Vector3(1.5, 0.5, 1.5) if base == ResolvedShape.Base.TORUS else Vector3.ONE
	shape.scale = Vector3.ONE
	shape.origin_inside = base != ResolvedShape.Base.TORUS
	shape.refresh()
	return shape


func _find_shape_in_pack(base: int) -> ResolvedShape:
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var mfr_id: String = mfrs[0]
		var defaults: Dictionary = ShapeGen.default_params(_data, family_id, mfr_id)
		var minimal: Dictionary = ShapeGen.clamp_params(_data, family_id, mfr_id, _zeroed(defaults))
		var shape: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr_id, minimal, Vector3.ONE)
		if shape.base == base:
			return shape
	return null


## A synthetic, perfectly unwarped unit box: round = taper = twist = ribs = scallop = 0, scale 1.
## Not resolved through any family -- see the file header for why.
func _unit_box() -> ResolvedShape:
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = ResolvedShape.Base.BOX
	shape.size = Vector3.ONE
	shape.scale = Vector3.ONE
	shape.refresh()
	return shape


func _by_id(targets: Array[Dictionary], id: String) -> Dictionary:
	for target: Dictionary in targets:
		if String(target.get("id", "")) == id:
			return target
	return {}


func test_for_shape_is_deterministic_same_shape_same_order() -> void:
	var shape: ResolvedShape = _find_shape(ResolvedShape.Base.BOX)
	assert_object(shape).append_failure_message(
		"no family in res://data resolves to a BOX base primitive -- cannot test determinism"
	).is_not_null()
	var first: Array[Dictionary] = SnapTargets.for_shape(shape)
	var second: Array[Dictionary] = SnapTargets.for_shape(shape)
	# var_to_str() serialises the whole nested Array[Dictionary] (ids, Vector3s, kinds) in order,
	# so an equal string is both "same content" and "same order" in one assertion.
	assert_str(var_to_str(second)).append_failure_message(
		"SnapTargets.for_shape() returned a different array (or order) for the same shape " +
		"on a second call -- determinism is the whole contract (section 1)"
	).is_equal(var_to_str(first))


func test_ids_are_unique_within_every_base_shape() -> void:
	var bases: Array[int] = [
		ResolvedShape.Base.BOX,
		ResolvedShape.Base.SPHERE,
		ResolvedShape.Base.CYLINDER,
		ResolvedShape.Base.CONE,
		ResolvedShape.Base.CAPSULE,
		ResolvedShape.Base.TORUS,
	]
	for base: int in bases:
		var shape: ResolvedShape = _find_shape(base)
		assert_object(shape).append_failure_message(
			"no family in res://data resolves to base enum %d -- cannot test id uniqueness for it"
			% base
		).is_not_null()
		var seen: Dictionary = {}
		for target: Dictionary in SnapTargets.for_shape(shape):
			var id: String = String(target.get("id", ""))
			assert_bool(seen.has(id)).append_failure_message(
				"duplicate snap id '%s' within one shape's for_shape() array (base enum %d)"
				% [id, base]
			).is_false()
			seen[id] = true


func test_unit_box_face_plus_x_is_exact_position_and_normal() -> void:
	var shape: ResolvedShape = _unit_box()
	var target: Dictionary = _by_id(SnapTargets.for_shape(shape), "face_+x")
	assert_dict(target).append_failure_message(
		"SnapTargets.for_shape() produced no 'face_+x' target for a unit BOX"
	).is_not_empty()

	var pos: Vector3 = target.get("local_pos", Vector3.ZERO)
	var normal: Vector3 = target.get("normal", Vector3.ZERO)
	# For an unwarped box the seed (half.x, 0, 0) IS the analytic surface point: SdfPrims.box()
	# there is exactly 0.0, well under SURFACE_EPS (1e-9), so _project_to_surface() returns it
	# untouched before taking a single Newton step. There is no projection error to tolerate, so
	# the position tolerance is float-noise-tight rather than geometry-tolerant.
	assert_vector(pos).append_failure_message(
		"face_+x of a half-extent-1 box should sit at exactly (1, 0, 0), got %s" % pos
	).is_equal_approx(Vector3(1.0, 0.0, 0.0), TOL_TIGHT)
	# The normal comes from a 6-sample central-difference gradient (GRADIENT_EPS = 1e-4), which is
	# exact in direction here (a flat axis-aligned face has zero cross-axis curvature) but carries
	# float rounding from the finite-difference division, hence the looser 1e-5 band.
	assert_vector(normal).append_failure_message(
		"outward normal at face_+x of a box should be exactly (1, 0, 0), got %s" % normal
	).is_equal_approx(Vector3(1.0, 0.0, 0.0), TOL_NORMAL)


func test_every_snap_target_lies_on_the_resolved_surface() -> void:
	# Real families, real (non-zeroed) authored defaults: several ship a nonzero default round,
	# so this is the test that actually exercises the damped-Newton projection against a warped
	# field, not just an already-exact analytic seed.
	var checked_any: bool = false
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var mfr_id: String = mfrs[0]
		var params: Dictionary = ShapeGen.default_params(_data, family_id, mfr_id)
		var shape: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr_id, params, Vector3.ONE)
		for target: Dictionary in SnapTargets.for_shape(shape):
			# "center" is the ONE kind that is deliberately not on the surface: it is the shape's
			# origin, cloning Spore's SnapToParentCenter flag, and asserting it lies on the hull
			# asserts the opposite of what it is for. Every other kind is a surface point.
			if String(target.get("kind", "")) == "center":
				continue
			checked_any = true
			var pos: Vector3 = target.get("local_pos", Vector3.ZERO)
			var d: float = absf(shape.sdf(pos))
			# 1e-3 is the contract's own figure (API_CONTRACT_SPORE task brief). It is also what
			# the implementation actually promises: _project_to_surface() runs SURFACE_STEPS
			# damped-Newton iterations, each closing roughly 1/lipschitz of the residual. That
			# constant was raised from 6 to 24 because 6 left torus_ring's rim targets 1.8 mm out —
			# the damping that keeps a sphere-trace from overshooting also slows a projection.
			# Tripping this now means the projection genuinely failed, not that the bar is tight.
			assert_float(d).append_failure_message(
				(
					"family '%s' manufacturer '%s': snap target '%s' sits %f m off the " +
					"resolved surface (local_pos=%s)"
				) % [family_id, mfr_id, String(target.get("id", "")), d, pos]
			).is_less(1e-3)
	assert_bool(checked_any).append_failure_message(
		"no family/manufacturer pair in res://data produced any snap target to check"
	).is_true()


func test_cylinder_has_exactly_eight_rim_points() -> void:
	var shape: ResolvedShape = _find_shape(ResolvedShape.Base.CYLINDER)
	assert_object(shape).append_failure_message(
		"no family in res://data resolves to a CYLINDER base primitive"
	).is_not_null()
	var rim_count: int = 0
	for target: Dictionary in SnapTargets.for_shape(shape):
		if String(target.get("id", "")).begins_with("rim_"):
			rim_count += 1
	# RIM_SEGMENTS is FIXED at 8 by API_CONTRACT_SPORE section 1 because the count generates the
	# ids -- asserting against the literal 8 (not just the constant) catches an accidental change
	# to the constant itself, which would be a silent contract break.
	assert_int(rim_count).append_failure_message(
		"cylinder rim ring should have exactly 8 points, got %d" % rim_count
	).is_equal(8)
	assert_int(SnapTargets.RIM_SEGMENTS).is_equal(8)


func test_every_shape_carries_a_center_target_first() -> void:
	var bases: Array[int] = [
		ResolvedShape.Base.BOX,
		ResolvedShape.Base.SPHERE,
		ResolvedShape.Base.CYLINDER,
		ResolvedShape.Base.CONE,
		ResolvedShape.Base.CAPSULE,
		ResolvedShape.Base.TORUS,
	]
	for base: int in bases:
		var shape: ResolvedShape = _find_shape(base)
		assert_object(shape).append_failure_message(
			"no family in res://data resolves to base enum %d" % base
		).is_not_null()
		var targets: Array[Dictionary] = SnapTargets.for_shape(shape)
		assert_array(targets).append_failure_message(
			"for_shape() returned no targets at all for base enum %d" % base
		).is_not_empty()
		var first: Dictionary = targets[0]
		assert_str(String(first.get("id", ""))).append_failure_message(
			"the 'center' target must be element 0 of for_shape() (base enum %d)" % base
		).is_equal("center")
		assert_str(String(first.get("kind", ""))).is_equal("center")
		var pos: Vector3 = first.get("local_pos", Vector3.ONE)
		assert_vector(pos).is_equal_approx(Vector3.ZERO, TOL_TIGHT)


func test_nearest_returns_empty_beyond_tolerance_and_finds_close_target() -> void:
	var shape: ResolvedShape = _unit_box()
	var far_point: Vector3 = Vector3(50.0, 50.0, 50.0)
	var miss: Dictionary = SnapTargets.nearest(shape, far_point, 0.5)
	assert_dict(miss).append_failure_message(
		"nearest() should return {} for a point far outside tolerance, got %s" % miss
	).is_empty()

	# Scale is ONE here, so the scaled and unscaled frames coincide and a point just off the
	# analytic face_+x target should be picked up well inside a generous 0.5 m tolerance.
	var near_point: Vector3 = Vector3(1.05, 0.0, 0.0)
	var hit: Dictionary = SnapTargets.nearest(shape, near_point, 0.5)
	assert_dict(hit).append_failure_message(
		"nearest() should find 'face_+x' for a point 0.05 m off it within a 0.5 m tolerance"
	).is_not_empty()
	assert_str(String(hit.get("id", ""))).is_equal("face_+x")


func test_apply_scale_scales_position_and_keeps_normal_unit_length() -> void:
	var shape: ResolvedShape = _unit_box()
	var face: Dictionary = _by_id(SnapTargets.for_shape(shape), "face_+x")
	assert_dict(face).is_not_empty()

	var scale: Vector3 = Vector3(2.0, 3.0, 4.0)
	var scaled: Dictionary = SnapTargets.apply_scale(face, scale)
	var pos: Vector3 = scaled.get("local_pos", Vector3.ZERO)
	var normal: Vector3 = scaled.get("normal", Vector3.ZERO)
	# Position scales componentwise: (1, 0, 0) * (2, 3, 4) = (2, 0, 0).
	assert_vector(pos).append_failure_message(
		"apply_scale() should scale local_pos componentwise, got %s" % pos
	).is_equal_approx(Vector3(2.0, 0.0, 0.0), TOL_TIGHT)
	# The normal is axis-aligned with the only nonzero scale component it touches (x), so dividing
	# by scale and renormalising leaves its direction unchanged; the property under test is that it
	# is still unit length after the divide-then-renormalise.
	assert_float(normal.length()).append_failure_message(
		"apply_scale() must leave the normal unit-length, got length=%f (normal=%s)"
		% [normal.length(), normal]
	).is_equal_approx(1.0, 1e-6)
	assert_vector(normal).is_equal_approx(Vector3(1.0, 0.0, 0.0), TOL_NORMAL)

	# A non-axis-aligned normal (a box corner) exercises the general divide-then-renormalise path
	# rather than the degenerate single-nonzero-component case above.
	var corner: Dictionary = _by_id(SnapTargets.for_shape(shape), "corner_+x+y+z")
	assert_dict(corner).is_not_empty()
	var corner_scaled: Dictionary = SnapTargets.apply_scale(corner, scale)
	var corner_normal: Vector3 = corner_scaled.get("normal", Vector3.ZERO)
	assert_float(corner_normal.length()).append_failure_message(
		"apply_scale() must leave a non-axis-aligned normal unit-length too, got length=%f"
		% corner_normal.length()
	).is_equal_approx(1.0, 1e-6)
