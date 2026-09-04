# The attach model, SPEC section 3, implemented "this order, exactly". Most of these tests
# build ResolvedShape instances directly (bypassing ShapeGen/ShipData) so every expected
# number can be hand-derived from the spec's algorithm text rather than guessed.
class_name TestAttach
extends GdUnitTestSuite

const TOL: float = 0.02
const TOL_V3: Vector3 = Vector3(0.02, 0.02, 0.02)

## Largest gap, in metres, that still counts as touching. The tracer works on a distance BOUND for
## warped shapes, so an exact zero is not available.
const CONTACT_TOL_M: float = 0.02

## Sampling resolution of the child's surface when measuring the gap.
##
## 24, not 10. At 10 the measurement itself was the failure: a torus_ring reported a 0.25 m gap it
## did not have, because no sample landed near the true contact point and a single Newton step
## from an AABB corner of a torus does not reach the surface. This test measures a shape it does
## not otherwise touch, so its own accuracy has to be established before its verdict means
## anything.
const CONTACT_SAMPLES: int = 24

## Newton projections applied to push a sample onto the child's real surface. Warped and concave
## fields need more than one step from a far starting point.
const CONTACT_PROJECT_STEPS: int = 4

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


func _make_sphere(r: float) -> ResolvedShape:
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = ResolvedShape.Base.SPHERE
	shape.size = Vector3(r, 0.0, 0.0)
	shape.round_r = 0.0
	shape.taper = 0.0
	shape.twist_deg = 0.0
	shape.rib_count = 0
	shape.rib_amp = 0.0
	shape.rib_phase = 0.0
	shape.scallop_amp = 0.0
	shape.scallop_freq = 0.0
	shape.scallop_phase = 0.0
	shape.lipschitz = 1.0
	shape.origin_inside = true
	shape.bound_radius = r
	return shape


func _make_box(half: Vector3) -> ResolvedShape:
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = ResolvedShape.Base.BOX
	shape.size = half
	shape.round_r = 0.0
	shape.taper = 0.0
	shape.twist_deg = 0.0
	shape.rib_count = 0
	shape.rib_amp = 0.0
	shape.rib_phase = 0.0
	shape.scallop_amp = 0.0
	shape.scallop_freq = 0.0
	shape.scallop_phase = 0.0
	shape.lipschitz = 1.0
	shape.origin_inside = true
	shape.bound_radius = half.length()
	return shape


func _make_part(yaw: float, pitch: float, spin: float, offset: float) -> ShipPart:
	return _make_part_rot(yaw, pitch, Vector3(0.0, 0.0, spin), offset)


func _make_part_rot(yaw: float, pitch: float, rot: Vector3, offset: float) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.yaw = yaw
	part.pitch = pitch
	part.rot = rot
	part.offset = offset
	part.scale = Vector3.ONE
	return part


func _is_orthonormal(basis: Basis, tol: float) -> bool:
	var ok: bool = true
	ok = ok and absf(basis.x.length() - 1.0) <= tol
	ok = ok and absf(basis.y.length() - 1.0) <= tol
	ok = ok and absf(basis.z.length() - 1.0) <= tol
	ok = ok and absf(basis.x.dot(basis.y)) <= tol
	ok = ok and absf(basis.y.dot(basis.z)) <= tol
	ok = ok and absf(basis.x.dot(basis.z)) <= tol
	return ok


func test_direction_from_angles_known_axes() -> void:
	# yaw=0, pitch=0 -> parent-local +Z (SPEC section 3, step 1).
	assert_vector(ShipAttach.direction_from_angles(0.0, 0.0)).is_equal_approx(
		Vector3(0.0, 0.0, 1.0), TOL_V3
	)
	# yaw=90 -> +X.
	assert_vector(ShipAttach.direction_from_angles(90.0, 0.0)).is_equal_approx(
		Vector3(1.0, 0.0, 0.0), TOL_V3
	)
	# pitch=90 -> +Y regardless of yaw (cos(pitch) collapses the x/z components to 0).
	assert_vector(ShipAttach.direction_from_angles(37.0, 90.0)).is_equal_approx(
		Vector3(0.0, 1.0, 0.0), TOL_V3
	)


func test_angles_from_direction_round_trips() -> void:
	var yaws: Array[float] = [0.0, 45.0, -90.0, 179.0, -179.0, 120.0, -45.0]
	var pitches: Array[float] = [0.0, 20.0, -45.0, 80.0, -80.0, -30.0, 60.0]
	var i: int = 0
	while i < yaws.size():
		var yaw: float = yaws[i]
		var pitch: float = pitches[i]
		var dir: Vector3 = ShipAttach.direction_from_angles(yaw, pitch)
		var back: Vector2 = ShipAttach.angles_from_direction(dir)
		(
			assert_float(back.x)
			. append_failure_message(
				(
					"yaw round-trip failed for (yaw=%f, pitch=%f), got back yaw=%f"
					% [yaw, pitch, back.x]
				)
			)
			. is_equal_approx(yaw, 0.05)
		)
		(
			assert_float(back.y)
			. append_failure_message(
				(
					"pitch round-trip failed for (yaw=%f, pitch=%f), got back pitch=%f"
					% [yaw, pitch, back.y]
				)
			)
			. is_equal_approx(pitch, 0.05)
		)
		i += 1


func test_trace_surface_sphere_lands_exactly_at_radius() -> void:
	var r: float = 4.0
	var shape: ResolvedShape = _make_sphere(r)
	var cfg: ShipConfig = ShipConfig.defaults()
	var yaws: Array[float] = [0.0, 30.0, 90.0, -60.0, 150.0]
	var pitches: Array[float] = [0.0, 45.0, -30.0, 10.0, -80.0]
	var i: int = 0
	while i < yaws.size():
		var dir: Vector3 = ShipAttach.direction_from_angles(yaws[i], pitches[i])
		var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
		(
			assert_float(p.length())
			. append_failure_message(
				(
					"trace at (yaw=%f, pitch=%f) landed at distance %f, expected %f"
					% [yaws[i], pitches[i], p.length(), r]
				)
			)
			. is_equal_approx(r, TOL)
		)
		i += 1


func test_trace_surface_box_lands_on_top_face() -> void:
	var half: Vector3 = Vector3(1.0, 1.0, 1.0)
	var shape: ResolvedShape = _make_box(half)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(0.0, 90.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	assert_vector(p).is_equal_approx(Vector3(0.0, 1.0, 0.0), TOL_V3)


func test_mount_inset_matches_known_primitives() -> void:
	# "origin -> attach face along local -Y": exact for a centered sphere (its radius) and
	# a centered box (its half-height), regardless of internal implementation.
	var sphere_shape: ResolvedShape = _make_sphere(3.0)
	assert_float(sphere_shape.mount_inset()).is_equal_approx(3.0, TOL)
	var box_shape: ResolvedShape = _make_box(Vector3(2.0, 1.5, 4.0))
	assert_float(box_shape.mount_inset()).is_equal_approx(1.5, TOL)


func test_gradient_is_unit_and_outward_on_sphere() -> void:
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(20.0, 15.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)
	assert_float(n.length()).is_equal_approx(1.0, TOL)
	assert_float(n.dot(p.normalized())).is_greater(0.99)


func test_gradient_is_unit_and_outward_on_box_top_face() -> void:
	var shape: ResolvedShape = _make_box(Vector3(1.0, 1.0, 1.0))
	var cfg: ShipConfig = ShipConfig.defaults()
	var p: Vector3 = Vector3(0.0, 1.0, 0.0)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)
	assert_vector(n).is_equal_approx(Vector3(0.0, 1.0, 0.0), TOL_V3)


func test_mount_basis_pole_fallback_is_exact() -> void:
	# yaw=0, pitch=0 on a sphere: N = +Z, which is exactly anti-parallel to the forward
	# reference -Z (SPEC's pole case, |N.-Z| > 0.999), so the tangent must fall back to +Y.
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(0.0, 0.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)
	var basis: Basis = ShipAttach.mount_basis(shape, p, n, Vector3.ZERO)
	assert_vector(basis.y).is_equal_approx(Vector3(0.0, 0.0, 1.0), TOL_V3)
	assert_vector(basis.z).is_equal_approx(Vector3(0.0, -1.0, 0.0), TOL_V3)
	assert_vector(basis.x).is_equal_approx(Vector3(1.0, 0.0, 0.0), TOL_V3)


func test_mount_basis_non_pole_case_is_exact() -> void:
	# yaw=90, pitch=0 on a sphere: N = +X, forward reference -Z projects onto the tangent
	# plane unchanged (already orthogonal to N), no pole fallback needed.
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(90.0, 0.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)
	var basis: Basis = ShipAttach.mount_basis(shape, p, n, Vector3.ZERO)
	assert_vector(basis.y).is_equal_approx(Vector3(1.0, 0.0, 0.0), TOL_V3)
	assert_vector(basis.z).is_equal_approx(Vector3(0.0, 0.0, 1.0), TOL_V3)
	assert_vector(basis.x).is_equal_approx(Vector3(0.0, -1.0, 0.0), TOL_V3)


func test_mount_basis_spin_preserves_axis_and_orthonormality() -> void:
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(90.0, 0.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)
	var basis_0: Basis = ShipAttach.mount_basis(shape, p, n, Vector3.ZERO)
	var basis_90: Basis = ShipAttach.mount_basis(shape, p, n, Vector3(0.0, 0.0, 90.0))
	var basis_360: Basis = ShipAttach.mount_basis(shape, p, n, Vector3(0.0, 0.0, 360.0))
	assert_bool(_is_orthonormal(basis_0, 0.01)).is_true()
	assert_bool(_is_orthonormal(basis_90, 0.01)).is_true()
	assert_vector(basis_0.y).is_equal_approx(n, TOL_V3)
	assert_vector(basis_90.y).is_equal_approx(n, TOL_V3)
	(
		assert_bool(basis_0.x.is_equal_approx(basis_90.x))
		. append_failure_message(
			"rot.z=0 and rot.z=90 produced the same tangent basis -- the spin axis has no effect"
		)
		. is_false()
	)
	assert_vector(basis_360.x).is_equal_approx(basis_0.x, TOL_V3)


func test_local_transform_offset_zero_is_flush() -> void:
	var parent_shape: ResolvedShape = _make_sphere(5.0)
	var child_shape: ResolvedShape = _make_sphere(1.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var part: ShipPart = _make_part(0.0, 0.0, 0.0, 0.0)
	var xform: Transform3D = ShipAttach.local_transform(parent_shape, child_shape, part, cfg)
	# Two spheres flush: origin separation is exactly the sum of the radii.
	assert_vector(xform.origin).is_equal_approx(Vector3(0.0, 0.0, 6.0), TOL_V3)


func test_local_transform_offset_moves_origin_exactly_along_normal() -> void:
	var parent_shape: ResolvedShape = _make_sphere(5.0)
	var child_shape: ResolvedShape = _make_sphere(1.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var flush_part: ShipPart = _make_part(0.0, 0.0, 0.0, 0.0)
	var offset_part: ShipPart = _make_part(0.0, 0.0, 0.0, 2.0)
	var flush_xform: Transform3D = ShipAttach.local_transform(
		parent_shape, child_shape, flush_part, cfg
	)
	var offset_xform: Transform3D = ShipAttach.local_transform(
		parent_shape, child_shape, offset_part, cfg
	)
	var delta: Vector3 = offset_xform.origin - flush_xform.origin
	assert_vector(delta).is_equal_approx(Vector3(0.0, 0.0, 2.0), TOL_V3)


func test_anchor_for_is_the_point_local_transform_stands_on() -> void:
	# ADR 0008: the seam plane and the footprint ring read anchor_for(); the placed transform is
	# built on the same call. On the free path the anchor is ON the parent surface, its normal
	# is the parent's gradient, and the child's origin sits on that normal.
	var parent_shape: ResolvedShape = _make_sphere(5.0)
	var child_shape: ResolvedShape = _make_sphere(1.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	for aim: Vector2 in [Vector2(0.0, 0.0), Vector2(90.0, 0.0), Vector2(-135.0, 40.0)]:
		var part: ShipPart = _make_part_rot(aim.x, aim.y, Vector3(20.0, -15.0, 70.0), 0.7)
		var anchor: Dictionary = ShipAttach.anchor_for(parent_shape, part, cfg)
		var pos: Vector3 = anchor["pos"]
		var normal: Vector3 = anchor["normal"]
		assert_float(parent_shape.sdf(pos)).is_equal_approx(0.0, TOL)
		assert_float(normal.length()).is_equal_approx(1.0, TOL)
		assert_vector(normal).is_equal_approx(pos.normalized(), TOL_V3)
		var xform: Transform3D = ShipAttach.local_transform(parent_shape, child_shape, part, cfg)
		var off: Vector3 = xform.origin - pos
		assert_float(off.cross(normal).length()).is_less(TOL)
		assert_float(off.dot(normal)).is_greater(0.0)
	# On the snapped path the anchor is the target itself, scaled into the parent's frame.
	var targets: Array[Dictionary] = SnapTargets.for_shape(parent_shape)
	assert_array(targets).is_not_empty()
	var target: Dictionary = targets[targets.size() - 1]
	var snapped: ShipPart = _make_part(0.0, 0.0, 0.0, 0.0)
	snapped.snap_id = str(target["id"])
	var snap_anchor: Dictionary = ShipAttach.anchor_for(parent_shape, snapped, cfg)
	var scaled: Dictionary = SnapTargets.apply_scale(target, Vector3.ONE)
	assert_vector(snap_anchor["pos"]).is_equal_approx(scaled["local_pos"], TOL_V3)
	assert_vector(snap_anchor["normal"]).is_equal_approx(scaled["normal"], TOL_V3)


func test_local_transform_spin_rotates_without_moving_origin() -> void:
	var parent_shape: ResolvedShape = _make_sphere(5.0)
	var child_shape: ResolvedShape = _make_sphere(1.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var part_a: ShipPart = _make_part(90.0, 0.0, 0.0, 0.0)
	var part_b: ShipPart = _make_part(90.0, 0.0, 123.0, 0.0)
	var xform_a: Transform3D = ShipAttach.local_transform(parent_shape, child_shape, part_a, cfg)
	var xform_b: Transform3D = ShipAttach.local_transform(parent_shape, child_shape, part_b, cfg)
	assert_vector(xform_b.origin).is_equal_approx(xform_a.origin, TOL_V3)
	(
		assert_bool(xform_a.basis.x.is_equal_approx(xform_b.basis.x))
		. append_failure_message("rot.z=0 and rot.z=123 produced the same basis")
		. is_false()
	)


func test_resolve_shapes_and_resolve_all_cover_every_part() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child_part: ShipPart = ShipPart.new()
	child_part.id = doc.new_part_id()
	child_part.parent = doc.root
	child_part.kind = "primitive"
	child_part.family = _family_id
	child_part.manufacturer = _manufacturer_id
	child_part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	child_part.yaw = 10.0
	child_part.pitch = 5.0
	child_part.rot = Vector3.ZERO
	child_part.offset = 0.0
	child_part.scale = Vector3.ONE
	child_part.blend = 0.0
	child_part.mirror_source = ""
	child_part.mirror_plane = ""
	child_part.display_name = "attach test child"
	@warning_ignore("return_value_discarded")
	doc.add_part(child_part)

	var cfg: ShipConfig = ShipConfig.defaults()
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, cfg)
	var transforms: Dictionary = ShipAttach.resolve_all(doc, _data, cfg)

	# Every STORED part resolves. The counts are >= doc.parts.size(), not ==, because symmetry is
	# on by default and the passes also emit DERIVED twins ("<id>~m") which are not doc parts:
	# resolve_shapes aliases a shape for anything that could twin, resolve_all emits a transform
	# only for the ones that actually do (a part on the mirror plane, like the root, does not).
	assert_int(shapes.size()).is_greater_equal(doc.parts.size())
	assert_int(transforms.size()).is_greater_equal(doc.parts.size())
	assert_dict(shapes).contains_keys(doc.root, child_part.id)
	assert_dict(transforms).contains_keys(doc.root, child_part.id)

	for id: Variant in doc.parts.keys():
		(
			assert_bool(transforms.has(str(id)))
			. append_failure_message("stored part %s got no transform" % str(id))
			. is_true()
		)

	# The root straddles the mirror plane, so it must NOT produce a twin - a part mirrored onto
	# itself would be drawn twice and billed twice.
	(
		assert_bool(transforms.has(ShipSymmetry.twin_id(doc.root)))
		. append_failure_message("the root sits on the mirror plane and must not generate a twin")
		. is_false()
	)

	var root_shape: ResolvedShape = shapes[doc.root] as ResolvedShape
	var sample: float = root_shape.sdf(Vector3.ZERO)
	(
		assert_bool(is_finite(sample))
		. append_failure_message("root shape sdf(ZERO) returned a non-finite value: %f" % sample)
		. is_true()
	)


func test_resolve_all_root_transform_is_identity() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var cfg: ShipConfig = ShipConfig.defaults()
	var transforms: Dictionary = ShipAttach.resolve_all(doc, _data, cfg)
	var root_xform: Transform3D = transforms[doc.root] as Transform3D
	assert_vector(root_xform.origin).is_equal_approx(Vector3.ZERO, TOL_V3)
	(
		assert_bool(root_xform.basis.is_equal_approx(Basis.IDENTITY))
		. append_failure_message(
			(
				"root part is never attached, so its basis should be identity, got %s"
				% root_xform.basis
			)
		)
		. is_true()
	)


# ---------------------------------------------------------------- ADR 0004: three-axis rotation


func test_mount_frame_z_is_the_placement_normal() -> void:
	# The author's stated convention, and the thing the rotation fields are labelled against:
	# the mount frame's +Z IS the outward surface normal at the anchor.
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	for angles: Vector2 in [Vector2(0.0, 0.0), Vector2(90.0, 0.0), Vector2(35.0, 40.0)]:
		var dir: Vector3 = ShipAttach.direction_from_angles(angles.x, angles.y)
		var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
		var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps).normalized()
		var frame: Basis = ShipAttach.mount_frame(n)
		(
			assert_vector(frame.z)
			. append_failure_message(
				(
					"mount frame +Z must be the surface normal at yaw=%.1f pitch=%.1f"
					% [angles.x, angles.y]
				)
			)
			. is_equal_approx(n, TOL_V3)
		)


func test_rot_zero_still_stands_the_part_up_along_the_normal() -> void:
	# The MOUNT_ALIGN_DEG term. Every family is authored Y-major, so at rot == 0 the part's own
	# +Y must lie along the normal -- otherwise cones point sideways and spars lie flat.
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(37.0, 21.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps).normalized()
	var basis: Basis = ShipAttach.mount_basis(shape, p, n, Vector3.ZERO)
	assert_vector(basis.y).is_equal_approx(n, TOL_V3)


func test_rot_x_and_rot_y_tilt_the_part_off_the_normal() -> void:
	# Before ADR 0004 these two axes did not exist and every rotation ring drove the same value.
	var parent_shape: ResolvedShape = _make_sphere(5.0)
	var child_shape: ResolvedShape = _make_sphere(1.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var flat: ShipPart = _make_part_rot(0.0, 0.0, Vector3.ZERO, 0.0)
	var flat_xform: Transform3D = ShipAttach.local_transform(parent_shape, child_shape, flat, cfg)
	for axis: int in [Vector3.AXIS_X, Vector3.AXIS_Y]:
		var rot: Vector3 = Vector3.ZERO
		rot[axis] = 30.0
		var tilted: ShipPart = _make_part_rot(0.0, 0.0, rot, 0.0)
		var xform: Transform3D = ShipAttach.local_transform(parent_shape, child_shape, tilted, cfg)
		(
			assert_bool(xform.basis.y.is_equal_approx(flat_xform.basis.y))
			. append_failure_message("rot[%d] = 30 did not tilt the part off the normal" % axis)
			. is_false()
		)
		(
			assert_vector(xform.origin)
			. append_failure_message("tilting must not move the anchor")
			. is_equal_approx(flat_xform.origin, TOL_V3)
		)


func test_rot_axes_are_independent() -> void:
	# The regression this ADR exists to prevent: three rings that all drive one number.
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(20.0, 10.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)
	var seen: Array[Basis] = []
	for axis: int in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		var rot: Vector3 = Vector3.ZERO
		rot[axis] = 40.0
		seen.append(ShipAttach.mount_basis(shape, p, n, rot))
	for a: int in range(seen.size()):
		for b: int in range(a + 1, seen.size()):
			(
				assert_bool(seen[a].is_equal_approx(seen[b]))
				. append_failure_message(
					"rotating about axis %d and axis %d produced the same basis" % [a, b]
				)
				. is_false()
			)


func test_legacy_roll_scalar_loads_into_rot_z() -> void:
	# A 1.0.0 document must load and render identically under ruleset 2.0.0.
	var legacy: Dictionary = {
		"parent": "p_0001",
		"kind": "primitive",
		"family": _family_id,
		"manufacturer": _manufacturer_id,
		"attach": {"yaw": 12.0, "pitch": 3.0, "roll": 47.5, "offset": 0.25},
	}
	var part: ShipPart = ShipPart.from_dict("p_0002", legacy)
	assert_float(part.rot.z).is_equal_approx(47.5, 0.0001)
	assert_float(part.rot.x).is_equal_approx(0.0, 0.0001)
	assert_float(part.rot.y).is_equal_approx(0.0, 0.0001)
	assert_float(part.offset).is_equal_approx(0.25, 0.0001)


# ---------------------------------------------------------------- contact: nothing may float


## A part at offset 0 must TOUCH its parent at every orientation, for every family.
##
## The regression this locks down: ADR 0004 let parts tilt, and the flush distance was still being
## measured along the child's fixed -Y. Measured across the catalogue at 45 degrees, a capsule_tank
## floated 0.31 m clear of its parent and a torus_ring buried itself 0.81 m into it. Reported as
## "also things are hovering they must be connected".
##
## Only FLOATING fails. Interpenetration is fine and is not asserted against: parts smooth-union in
## the SDF, a tilted solid genuinely overlaps the surface it leans on, and an embedded part is
## still a connected one. A gap is the defect.
func test_no_family_floats_off_its_parent_at_any_tilt() -> void:
	var cfg: ShipConfig = ShipConfig.defaults()
	# A BOX parent, deliberately. `offset == 0` seats a part by pushing it out along the surface
	# NORMAL by its own extent in that direction, which is exact on a locally flat surface and an
	# under-push on a CONVEX one: a part whose contact material is spread sideways - a torus_ring
	# is the extreme case, its lowest material sitting 1.5 m off its own axis - rides up the
	# curvature and lifts. Measured on a 5 m sphere parent, a torus floats 0.20 m. That is a real
	# limitation of normal-offset seating and is recorded in FOLLOWUPS F12; it is not what this
	# test is for, which is that TILTING a part must not lift it off a surface it was flush on.
	var parent_shape: ResolvedShape = _make_box(Vector3(6.0, 6.0, 6.0))
	for base: int in [
		ResolvedShape.Base.BOX,
		ResolvedShape.Base.SPHERE,
		ResolvedShape.Base.CYLINDER,
		ResolvedShape.Base.CONE,
		ResolvedShape.Base.CAPSULE,
		ResolvedShape.Base.TORUS,
	]:
		var child_shape: ResolvedShape = _make_base(base)
		for tilt: float in [0.0, 15.0, 30.0, 45.0, 90.0]:
			var part: ShipPart = _make_part_rot(35.0, 20.0, Vector3(tilt, 0.0, 0.0), 0.0)
			var xform: Transform3D = ShipAttach.local_transform(
				parent_shape, child_shape, part, cfg
			)
			var gap: float = _min_parent_distance(parent_shape, child_shape, xform, cfg)
			(
				assert_float(gap)
				. append_failure_message(
					(
						"base %d at tilt %.0f deg floats %.3f m off its parent at offset 0"
						% [base, tilt, gap]
					)
				)
				. is_less_equal(CONTACT_TOL_M)
			)


## Smallest value of the PARENT's field over the child's surface. Negative = overlapping,
## 0 = touching, positive = a gap.
func _min_parent_distance(
	parent_shape: ResolvedShape, child_shape: ResolvedShape, xform: Transform3D, cfg: ShipConfig
) -> float:
	var best: float = 1.0e30
	var box: AABB = child_shape.local_aabb()
	for i: int in CONTACT_SAMPLES:
		for j: int in CONTACT_SAMPLES:
			var u: float = float(i) / float(CONTACT_SAMPLES - 1)
			var v: float = float(j) / float(CONTACT_SAMPLES - 1)
			for face: int in 6:
				var p: Vector3 = _box_face_point(box, face, u, v)
				for _step: int in CONTACT_PROJECT_STEPS:
					var d: float = child_shape.sdf(p)
					var n: Vector3 = ShipAttach.gradient(child_shape, p, cfg.gradient_eps)
					if n.length_squared() < 1.0e-12:
						break
					p -= n.normalized() * d
				best = minf(best, parent_shape.sdf(xform * p))
	return best


## A point on one of the six faces of `box`, parameterised by (u, v) across THAT face.
##
## Each face varies the two axes it actually spans. The first version drove two axes from `u` on
## the +/-Y faces, so those faces were sampled along a diagonal LINE rather than a grid - and the
## -Y face is exactly where a part contacts its parent, so the measurement missed the contact
## point and reported gaps that were not there.
func _box_face_point(box: AABB, face: int, u: float, v: float) -> Vector3:
	var lo: Vector3 = box.position
	var hi: Vector3 = box.end
	var x: float = lerpf(lo.x, hi.x, u)
	var z: float = lerpf(lo.z, hi.z, v)
	match face:
		0:
			return Vector3(lo.x, lerpf(lo.y, hi.y, u), z)
		1:
			return Vector3(hi.x, lerpf(lo.y, hi.y, u), z)
		2:
			return Vector3(x, lo.y, z)
		3:
			return Vector3(x, hi.y, z)
		4:
			return Vector3(x, lerpf(lo.y, hi.y, v), lo.z)
		_:
			return Vector3(x, lerpf(lo.y, hi.y, v), hi.z)


func _make_base(base: int) -> ResolvedShape:
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = base
	shape.size = Vector3(0.8, 1.0, 0.8)
	if base == ResolvedShape.Base.TORUS:
		shape.size = Vector3(1.5, 0.5, 0.5)
	if base == ResolvedShape.Base.SPHERE:
		shape.size = Vector3(1.0, 1.0, 1.0)
	shape.scale = Vector3.ONE
	shape.round_r = 0.02
	shape.origin_inside = base != ResolvedShape.Base.TORUS
	shape.refresh()
	return shape


# ---------------------------------------------------------------- ADR 0004 follow-on: twins


func test_symmetry_emits_a_reflected_twin_for_an_off_plane_part() -> void:
	# Before this, ShipSymmetry could say a part SHOULD have a twin and ShipComplexity charged
	# double for it, but nothing ever produced one: changing the mirror plane visibly did nothing.
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	doc.symmetry_plane = "x"
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.kind = "primitive"
	child.family = _family_id
	child.manufacturer = _manufacturer_id
	child.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	child.yaw = 90.0
	child.pitch = 0.0
	child.rot = Vector3.ZERO
	child.scale = Vector3.ONE
	var child_id: String = doc.add_part(child)

	var cfg: ShipConfig = ShipConfig.defaults()
	var transforms: Dictionary = ShipAttach.resolve_all(doc, _data, cfg)
	var twin: String = ShipSymmetry.twin_id(child_id)
	(
		assert_bool(transforms.has(twin))
		. append_failure_message(
			(
				"an off-plane part under symmetry must emit a twin transform, got keys %s"
				% [transforms.keys()]
			)
		)
		. is_true()
	)

	var source_xf: Transform3D = transforms[child_id]
	var twin_xf: Transform3D = transforms[twin]
	# Reflected across x: the origin flips in x and the basis is handed the other way.
	assert_float(twin_xf.origin.x).is_equal_approx(-source_xf.origin.x, 0.0001)
	assert_float(twin_xf.origin.y).is_equal_approx(source_xf.origin.y, 0.0001)
	assert_float(twin_xf.origin.z).is_equal_approx(source_xf.origin.z, 0.0001)
	(
		assert_bool(twin_xf.basis.determinant() < 0.0)
		. append_failure_message("a reflected twin must have a negative-determinant basis")
		. is_true()
	)


func test_symmetry_off_emits_no_twins() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	doc.symmetry_plane = ""
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.kind = "primitive"
	child.family = _family_id
	child.manufacturer = _manufacturer_id
	child.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	child.yaw = 90.0
	child.scale = Vector3.ONE
	var child_id: String = doc.add_part(child)

	var cfg: ShipConfig = ShipConfig.defaults()
	var transforms: Dictionary = ShipAttach.resolve_all(doc, _data, cfg)
	(
		assert_int(transforms.size())
		. append_failure_message(
			"symmetry off must produce exactly the stored parts, got %s" % [transforms.keys()]
		)
		. is_equal(doc.parts.size())
	)
	assert_bool(transforms.has(ShipSymmetry.twin_id(child_id))).is_false()


func test_breaking_symmetry_removes_the_twin() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	doc.symmetry_plane = "x"
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.kind = "primitive"
	child.family = _family_id
	child.manufacturer = _manufacturer_id
	child.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	child.yaw = 90.0
	child.scale = Vector3.ONE
	var child_id: String = doc.add_part(child)
	var cfg: ShipConfig = ShipConfig.defaults()

	(
		assert_bool(ShipAttach.resolve_all(doc, _data, cfg).has(ShipSymmetry.twin_id(child_id)))
		. is_true()
	)

	@warning_ignore("return_value_discarded")
	ShipSymmetry.set_asymmetric(doc, child_id, true)
	(
		assert_bool(ShipAttach.resolve_all(doc, _data, cfg).has(ShipSymmetry.twin_id(child_id)))
		. append_failure_message("breaking symmetry must drop the twin")
		. is_false()
	)


# ---------------------------------------------------------------- gizmo honesty


## A rotation ring must turn the part about the axis it is DRAWN around.
##
## `ShipHandles` lives in harness/, but this is a statement about the mount-frame composition in
## `ShipAttach.mount_basis()` and it needs no scene, no camera and no nodes - only two bases and a
## quaternion. It belongs next to the composition it constrains.
##
## The regression: rings were drawn about the part's own local X/Y/Z while rot.x/y/z turn it about
## the MOUNT frame's axes, which differ by the fixed 90-degree alignment term. Measured, RING_Y
## was drawn about world (1,0,0) and turned the part about (0,0,-1). Two of the three circles
## rotated the part about something other than the circle you grabbed.
func test_every_rotation_ring_turns_about_the_axis_it_is_drawn_around() -> void:
	var shape: ResolvedShape = _make_sphere(5.0)
	var cfg: ShipConfig = ShipConfig.defaults()
	var dir: Vector3 = ShipAttach.direction_from_angles(35.0, 20.0)
	var p: Vector3 = ShipAttach.trace_surface(shape, dir, cfg)
	var n: Vector3 = ShipAttach.gradient(shape, p, cfg.gradient_eps)

	# From rest AND from an already-rotated pose: the axes only diverge once a part is turned,
	# which is exactly when a gizmo has to stay honest.
	for start: Vector3 in [Vector3.ZERO, Vector3(25.0, 40.0, 15.0), Vector3(-60.0, 10.0, 80.0)]:
		for handle: int in ShipHandles.ring_handles():
			var axis: int = ShipPlacement.axis_for_handle(handle)
			var after_rot: Vector3 = start
			after_rot[axis] = after_rot[axis] + 30.0

			var before: Basis = ShipAttach.mount_basis(shape, p, n, start)
			var after: Basis = ShipAttach.mount_basis(shape, p, n, after_rot)
			var drawn: Vector3 = (before * ShipHandles.ring_axis_local(handle, start)).normalized()

			var delta: Basis = after * before.inverse()
			var quat: Quaternion = delta.get_rotation_quaternion()
			var actual: Vector3 = Vector3(quat.x, quat.y, quat.z)
			(
				assert_bool(actual.length_squared() > 1.0e-9)
				. append_failure_message(
					"handle %d produced no rotation at all from %s" % [handle, str(start)]
				)
				. is_true()
			)

			var agreement: float = absf(drawn.dot(actual.normalized()))
			(
				assert_float(agreement)
				. append_failure_message(
					(
						"handle %d from rot %s is drawn about %s but turns the part about %s"
						% [handle, str(start), str(drawn), str(actual.normalized())]
					)
				)
				. is_greater(0.999)
			)
