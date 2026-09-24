# The doors of the hatched seams (ADR 0029): the hole outlines, the gasket plane, the collar
# and the bore each module takes, the fit against both rooms, and the leaves a view swings.
#
# Every number here is read off the PLAN - pure data, no engine - on the carbon the author builds
# with (sphere pods, tunnels hatched at both ends by ADR 0027). The engine's boring is the
# harness suite's claim (test_csg_bake.gd).
class_name TestDoors
extends GdUnitTestSuite

const TOL: float = 1.0e-3
const HATCH_R: float = 0.35

var _data: ShipData
var _cfg: ShipConfig


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message("ShipData.load_all() failed: %s" % [str(_data.load_errors)])
		. is_true()
	)
	_cfg = ShipConfig.defaults()


func _carbon() -> ShipDoc:
	return ShipTemplates.build(_data, _cfg, "carbon", {ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"})


static func _signed_area(outline: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in outline.size():
		total += outline[i].cross(outline[(i + 1) % outline.size()])
	return total * 0.5


static func _width(outline: PackedVector2Array) -> float:
	var lo: float = INF
	var hi: float = -INF
	for p: Vector2 in outline:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return hi - lo


static func _centroid(mesh: PolyMesh) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	for v: Vector3 in mesh.vertices:
		sum += v
	return sum / float(maxi(mesh.vertices.size(), 1))


# ---------------------------------------------------------------- outlines


func test_every_shape_has_a_counter_clockwise_outline_of_its_size() -> void:
	var cases: Array = [
		[ShipSeams.KIND_CIRCLE, 24],
		[ShipSeams.KIND_ELLIPSE, 24],
		[ShipSeams.KIND_SQUARE, 4],
		[ShipSeams.KIND_RECT, 4],
		[ShipSeams.KIND_TRIANGLE, 3],
		[ShipSeams.KIND_POLYGON, 6],
	]
	for pair: Array in cases:
		var hole: Dictionary = {
			ShipSeams.HOLE_KIND: pair[0],
			ShipSeams.HOLE_SIZE: Vector2(1.2, 0.8),
			ShipSeams.HOLE_CORNER: 0.0,
			ShipSeams.HOLE_SIDES: 6,
		}
		var outline: PackedVector2Array = ShipSeams.hole_profile(hole)
		assert_int(outline.size()).append_failure_message(str(pair[0])).is_equal(int(pair[1]))
		assert_float(_signed_area(outline)).append_failure_message(str(pair[0])).is_greater(0.0)
		if pair[0] != ShipSeams.KIND_POLYGON:
			assert_float(_width(outline)).append_failure_message(str(pair[0])).is_equal_approx(
				1.2, TOL
			)
	var rounded: Dictionary = {
		ShipSeams.HOLE_KIND: ShipSeams.KIND_RECT,
		ShipSeams.HOLE_SIZE: Vector2(0.8, 1.9),
		ShipSeams.HOLE_CORNER: 0.1,
	}
	var rim: PackedVector2Array = ShipSeams.hole_profile(rounded)
	assert_int(rim.size()).is_equal(4 * (ShipSeams.CORNER_SEGMENTS + 1))
	assert_float(_width(rim)).is_equal_approx(0.8, TOL)
	assert_int(ShipSeams.hole_profile({ShipSeams.HOLE_KIND: ShipSeams.KIND_ALL}).size()).is_equal(0)


func test_a_polygon_hole_reads_inside_negative_and_outside_positive() -> void:
	var tri: Dictionary = {
		ShipSeams.HOLE_KIND: ShipSeams.KIND_TRIANGLE, ShipSeams.HOLE_SIZE: Vector2(1.0, 1.0)
	}
	assert_float(ShipSeams.hole_distance(tri, Vector2(0.0, -0.2))).is_less(0.0)
	assert_float(ShipSeams.hole_distance(tri, Vector2(0.0, -0.5))).is_equal_approx(0.0, TOL)
	assert_float(ShipSeams.hole_distance(tri, Vector2(2.0, 0.0))).is_greater(1.0)
	var hex: Dictionary = {
		ShipSeams.HOLE_KIND: ShipSeams.KIND_POLYGON,
		ShipSeams.HOLE_SIZE: Vector2(1.0, 1.0),
		ShipSeams.HOLE_SIDES: 6,
	}
	assert_float(ShipSeams.hole_distance(hex, Vector2.ZERO)).is_less(-0.4)
	# The hexagon starts at the top, so its top vertex is at (0, 0.5).
	assert_float(ShipSeams.hole_distance(hex, Vector2(0.0, 0.5))).is_equal_approx(0.0, TOL)


func test_a_joint_overrides_its_familys_shape_style_and_size() -> void:
	var preset: ShipJoint = ShipJoint.from_dict(
		"j_0001", {"a": "a", "b": "b", "mode": "hatched", "hatch": {"family": "crawlway_round"}}
	)
	var hole: Dictionary = ShipSeams.hole_for(ShipSeams.MODE_HATCHED, preset, _data, _cfg)
	assert_str(str(hole[ShipSeams.HOLE_KIND])).is_equal(ShipSeams.KIND_CIRCLE)
	assert_str(str(hole[ShipSeams.HOLE_STYLE])).is_equal(ShipSeams.DOOR_SINGLE)
	assert_float((hole[ShipSeams.HOLE_SIZE] as Vector2).x).is_equal_approx(2.0 * HATCH_R, TOL)
	var iris: ShipJoint = ShipJoint.from_dict(
		"j_0002", {"a": "a", "b": "b", "mode": "hatched", "hatch": {"family": "iris_round"}}
	)
	var eye: Dictionary = ShipSeams.hole_for(ShipSeams.MODE_HATCHED, iris, _data, _cfg)
	assert_str(str(eye[ShipSeams.HOLE_STYLE])).is_equal(ShipSeams.DOOR_IRIS)
	assert_int(int(eye[ShipSeams.HOLE_BLADES])).is_equal(6)
	var custom: ShipJoint = ShipJoint.from_dict(
		"j_0003",
		{
			"a": "a",
			"b": "b",
			"mode": "hatched",
			"hatch":
			{
				"family": "crawlway_round",
				"params":
				{"shape": "polygon", "sides": 5, "style": "double", "width": 0.9, "height": 0.7}
			}
		}
	)
	var five: Dictionary = ShipSeams.hole_for(ShipSeams.MODE_HATCHED, custom, _data, _cfg)
	assert_str(str(five[ShipSeams.HOLE_KIND])).is_equal(ShipSeams.KIND_POLYGON)
	assert_int(int(five[ShipSeams.HOLE_SIDES])).is_equal(5)
	assert_str(str(five[ShipSeams.HOLE_STYLE])).is_equal(ShipSeams.DOOR_DOUBLE)
	assert_vector(five[ShipSeams.HOLE_SIZE] as Vector2).is_equal_approx(
		Vector2(0.9, 0.7), Vector2(TOL, TOL)
	)
	var doorway: Dictionary = ShipSeams.hole_for(ShipSeams.MODE_DOORWAY, null, _data, _cfg)
	assert_str(str(doorway[ShipSeams.HOLE_STYLE])).is_equal(ShipSeams.DOOR_NONE)


# ---------------------------------------------------------------- the plan


func test_a_carbon_plans_a_door_at_every_tunnel_end_on_the_childs_surface() -> void:
	var doc: ShipDoc = _carbon()
	var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
	var doors: Array = plan["doors"]
	assert_int(doors.size()).append_failure_message(str(plan["door_misfits"])).is_equal(8)
	assert_int(int(plan["pending_seams"])).is_equal(0)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	var t: float = _cfg.hull_thickness_m
	for door: Dictionary in doors:
		var child: String = door[ShipDoors.DOOR_CHILD]
		var frame: Transform3D = door[ShipDoors.DOOR_FRAME]
		# The gasket plane passes through the indenting module's surface on the seam axis: the
		# tunnel's end cap where a tunnel stands on a pod, and a pod's surface where the pod is
		# the smaller one (the template seats pods on tunnel ends both ways).
		# Against the MESH the engine builds, not the field's zero (F34): a spar's tessellated cap
		# sits 0.094 m inside its field, and the door goes on the cap.
		var host: String = door[ShipDoors.DOOR_HOST]
		var on_child: float = absf(_body_field(plan, shapes, xforms, child).d(frame.origin))
		var on_host: float = absf(_body_field(plan, shapes, xforms, host).d(frame.origin))
		(
			assert_float(minf(on_child, on_host))
			. append_failure_message("%s: gasket origin off both meshes" % child)
			. is_less(0.01)
		)
		assert_float(frame.basis.x.dot(frame.basis.y)).is_equal_approx(0.0, TOL)
		assert_float(frame.basis.z.length()).is_equal_approx(1.0, TOL)
		assert_float(float(door[ShipDoors.DOOR_FIT])).is_equal_approx(1.0, TOL)
		assert_bool(bool(door[ShipDoors.DOOR_TIGHT])).is_false()
		# Frame and leaf follow the wall.
		assert_float(float(door[ShipDoors.DOOR_FRAME_W])).is_equal_approx(
			t * ShipDoors.FRAME_FRACTION, TOL
		)
		assert_float(float(door[ShipDoors.DOOR_LEAF_T])).is_equal_approx(
			t * ShipDoors.LEAF_FRACTION, TOL
		)
		# Every solid the engine will take is closed; each collar half is a wall deep at least;
		# the bore runs through both walls with room to spare.
		var collar: Dictionary = door[ShipDoors.DOOR_COLLAR]
		var clear: Dictionary = door[ShipDoors.DOOR_CLEAR]
		for side: String in ShipDoors.SIDES:
			assert_int((collar[side] as PolyMesh).open_edges()).is_equal(0)
			assert_int((clear[side] as PolyMesh).open_edges()).is_equal(0)
			assert_float(float(door[ShipDoors.DOOR_DEPTH][side])).is_greater_equal(t - TOL)
		var bore: PolyMesh = door[ShipDoors.DOOR_BORE]
		assert_int(bore.open_edges()).is_equal(0)
		var along: float = 0.0
		for v: Vector3 in bore.vertices:
			along = maxf(along, absf((v - frame.origin).dot(frame.basis.z)))
		assert_float(along * 2.0).is_greater(2.0 * t)
		var area: float = absf(_signed_area(door[ShipDoors.DOOR_PROFILE]))
		assert_float(area).is_greater(0.9 * PI * HATCH_R * HATCH_R)
		assert_float(bore.volume() / area).is_greater(2.0 * t)


func _body_field(
	plan: Dictionary, shapes: Dictionary, xforms: Dictionary, id: String
) -> ShipDoors.Field:
	return ShipDoors.field_of(
		MeshClip.Cutter.of_shape(shapes[id], xforms[id], null), plan["outer"][id]
	)


func test_the_plan_is_deterministic() -> void:
	var a: Array = ShipMeshBake.plan(_carbon(), _data, _cfg)["doors"]
	var b: Array = ShipMeshBake.plan(_carbon(), _data, _cfg)["doors"]
	assert_int(a.size()).is_equal(b.size())
	for i: int in a.size():
		var fa: Transform3D = a[i][ShipDoors.DOOR_FRAME]
		var fb: Transform3D = b[i][ShipDoors.DOOR_FRAME]
		assert_vector(fa.origin).is_equal(fb.origin)
		assert_str(str(a[i][ShipDoors.DOOR_KEY])).is_equal(str(b[i][ShipDoors.DOOR_KEY]))
		assert_float((a[i][ShipDoors.DOOR_BORE] as PolyMesh).volume()).is_equal(
			(b[i][ShipDoors.DOOR_BORE] as PolyMesh).volume()
		)


func test_a_doorway_too_tall_for_a_tunnel_is_clamped_to_what_fits() -> void:
	# A 0.8 x 1.9 doorway asked for on a 1.4 m tunnel: the frame has to stand inside the 1.0 m
	# clear bore, so the hole is scaled down and comes out under the person-passable minimum.
	var doc: ShipDoc = _carbon()
	var tunnel: String = ""
	var pod: String = ""
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.role == ShipPart.ROLE_HALLWAY and tunnel.is_empty():
			tunnel = pid
	for pid: String in doc.part_order():
		if (doc.parts[pid] as ShipPart).parent == tunnel:
			pod = pid
	assert_str(tunnel).is_not_empty()
	assert_str(pod).is_not_empty()
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == ShipDoc.joint_key_for(tunnel, pod):
			joint.mode = ShipJoint.MODE_DOORWAY
	var limits: Dictionary = ShipDoors.limits(doc, _data, _cfg, pod, tunnel)
	assert_bool(bool(limits["ok"])).append_failure_message(str(limits["reason"])).is_true()
	assert_float(float(limits["fit"])).is_less(1.0)
	var biggest: Vector2 = limits["max"]
	assert_float(biggest.y).is_less(1.9)
	assert_float(biggest.x / biggest.y).is_equal_approx(0.8 / 1.9, 0.01)
	assert_bool(bool(limits["tight"])).is_true()
	assert_float(float(limits["min"])).is_equal_approx(_cfg.hatch_min_m, TOL)
	# The crawlway that was there fits as asked, with room to grow toward the tunnel's bore.
	var whole: Dictionary = ShipDoors.limits(_carbon(), _data, _cfg, pod, tunnel)
	assert_bool(bool(whole["ok"])).is_true()
	assert_float(float(whole["fit"])).is_equal_approx(1.0, TOL)
	assert_float((whole["max"] as Vector2).x).is_greater(2.0 * HATCH_R)
	assert_float((whole["max"] as Vector2).x).is_less(_cfg.tunnel_bore_m)


# ---------------------------------------------------------------- leaves


func _first_door(style: String) -> Dictionary:
	var doc: ShipDoc = _carbon()
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if joint.mode == ShipJoint.MODE_HATCHED:
			joint.hatch_params[ShipSeams.PARAM_STYLE] = style
	var doors: Array = ShipMeshBake.plan(doc, _data, _cfg)["doors"]
	assert_int(doors.size()).is_greater(0)
	return doors[0]


func test_a_single_leaf_covers_the_seat_and_swings_into_its_own_module() -> void:
	var door: Dictionary = _first_door(ShipSeams.DOOR_SINGLE)
	var seat_area: float = absf(_signed_area(door[ShipDoors.DOOR_SEAT]))
	var leaf_t: float = float(door[ShipDoors.DOOR_LEAF_T])
	var frame: Transform3D = door[ShipDoors.DOOR_FRAME]
	for side: String in ShipDoors.SIDES:
		var sign: float = 1.0 if side == ShipDoors.SIDE_CHILD else -1.0
		var shut: Array[PolyMesh] = ShipDoors.leaves(door, side, 0.0)
		assert_int(shut.size()).is_equal(1)
		assert_int(shut[0].open_edges()).is_equal(0)
		assert_float(shut[0].volume()).is_equal_approx(
			seat_area * leaf_t, seat_area * leaf_t * 0.05
		)
		# Closed, the leaf sits just off the plane on its own side, inside the wall.
		var shut_z: float = (_centroid(shut[0]) - frame.origin).dot(frame.basis.z) * sign
		assert_float(shut_z).is_greater(0.0)
		assert_float(shut_z).is_less(float(door[ShipDoors.DOOR_THICKNESS]))
		# Open, it has swung further into its module and kept its volume.
		var open: Array[PolyMesh] = ShipDoors.leaves(door, side, 1.0)
		var open_z: float = (_centroid(open[0]) - frame.origin).dot(frame.basis.z) * sign
		assert_float(open_z).is_greater(shut_z + leaf_t)
		assert_float(open[0].volume()).is_equal_approx(shut[0].volume(), TOL)


func test_double_leaves_are_two_halves_that_swing_apart() -> void:
	var door: Dictionary = _first_door(ShipSeams.DOOR_DOUBLE)
	var frame: Transform3D = door[ShipDoors.DOOR_FRAME]
	var shut: Array[PolyMesh] = ShipDoors.leaves(door, ShipDoors.SIDE_CHILD, 0.0)
	assert_int(shut.size()).is_equal(2)
	assert_float(shut[0].volume()).is_equal_approx(shut[1].volume(), TOL)
	var open: Array[PolyMesh] = ShipDoors.leaves(door, ShipDoors.SIDE_CHILD, 1.0)
	# The left leaf's centre stays left of the axis and the right leaf's right of it, both
	# further from the plane than when shut.
	var left_x: float = (_centroid(open[0]) - frame.origin).dot(frame.basis.x)
	var right_x: float = (_centroid(open[1]) - frame.origin).dot(frame.basis.x)
	assert_float(left_x).is_less(0.0)
	assert_float(right_x).is_greater(0.0)
	for i: int in 2:
		var shut_z: float = (_centroid(shut[i]) - frame.origin).dot(frame.basis.z)
		var open_z: float = (_centroid(open[i]) - frame.origin).dot(frame.basis.z)
		assert_float(open_z).is_greater(shut_z)


func test_an_iris_closes_to_a_full_disc_and_opens_toward_the_frame() -> void:
	var door: Dictionary = _first_door(ShipSeams.DOOR_IRIS)
	var blades: int = int(door[ShipDoors.DOOR_BLADES])
	assert_int(blades).is_equal(6)
	var seat_area: float = absf(_signed_area(door[ShipDoors.DOOR_SEAT]))
	var leaf_t: float = float(door[ShipDoors.DOOR_LEAF_T])
	var shut: Array[PolyMesh] = ShipDoors.leaves(door, ShipDoors.SIDE_HOST, 0.0)
	assert_int(shut.size()).is_equal(blades)
	var shut_volume: float = 0.0
	for blade: PolyMesh in shut:
		assert_int(blade.open_edges()).is_equal(0)
		shut_volume += blade.volume()
	# Six wedges of a 24-gon seat: the disc, less the chords a coarser blade arc takes.
	assert_float(shut_volume).is_greater(seat_area * leaf_t * 0.9)
	var open: Array[PolyMesh] = ShipDoors.leaves(door, ShipDoors.SIDE_HOST, 1.0)
	var open_volume: float = 0.0
	for blade: PolyMesh in open:
		open_volume += blade.volume()
	# Open, only the ring between the hole and the seat is left of the blades.
	assert_float(open_volume).is_less(shut_volume * 0.6)
	assert_float(open_volume).is_greater(0.0)


## A PREBUILT SHIP'S HATCHES PASS A SUITED PERSON (ADR 0040). The floor is only worth what the
## geometry honours: `hatch_min_m` clamps what a panel may ASK for and says nothing about whether
## the seam can give it, so before this the floor was 0.5 and every prebuilt hole came out 0.568 -
## or 0.380 on the ship the author was holding when they wrote "the hatches on here are visually
## only about .33m acrost, i want to maintain our smallest hatches will be .66 of a meter so a
## human can fit through with a suit on" (2026-09-24).
func test_a_prebuilt_ships_hatches_pass_a_suited_person() -> void:
	for element: String in ["lithium", "carbon", "neon"]:
		for family: String in ["box_hull", "sphere_pod", "cylinder_spar"]:
			var doc: ShipDoc = ShipTemplates.build(
				_data, _cfg, element, {ShipTemplates.OPT_ROOM_FAMILY: family}
			)
			assert_object(doc).is_not_null()
			var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
			var doors: Array = plan.get("doors", [])
			(
				assert_int(doors.size())
				. append_failure_message("%s of %s planned no doors at all" % [element, family])
				. is_greater(0)
			)
			for door: Dictionary in doors:
				var profile: PackedVector2Array = door[ShipDoors.DOOR_PROFILE]
				var box: Rect2 = Rect2(profile[0], Vector2.ZERO)
				for at: Vector2 in profile:
					box = box.expand(at)
				var narrowest: float = minf(box.size.x, box.size.y)
				(
					assert_float(narrowest)
					. append_failure_message(
						(
							"%s of %s: a hole %.3f m across, under the %.3f m floor"
							% [element, family, narrowest, _cfg.hatch_min_m]
						)
					)
					. is_greater_equal(_cfg.hatch_min_m - TOL)
				)


## AND THE TUNNEL IS WIDE ENOUGH TO BE THE REASON. A hallway narrower than the hole plus its frame
## and its two walls cannot pass one, whatever the floor says.
func test_a_tunnel_is_sized_to_pass_its_smallest_hatch() -> void:
	var needed: float = ShipDoors.bore_for_hatch(_cfg.hatch_min_m, _cfg.hull_thickness_m)
	assert_float(needed).is_greater(_cfg.hatch_min_m)
	var doc: ShipDoc = _carbon()
	var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
	var frames: Dictionary = plan["frames"]
	var outer: Dictionary = plan["outer"]
	var checked: int = 0
	for pid: String in plan["ids"] as PackedStringArray:
		var part: ShipPart = doc.parts.get(pid, null)
		if part == null or part.role != ShipPart.ROLE_HALLWAY or not outer.has(pid):
			continue
		checked += 1
		var into: Transform3D = (frames[pid] as Transform3D).affine_inverse()
		var box: Vector3 = (outer[pid] as PolyMesh).transformed(into).aabb().size
		(
			assert_float(minf(box.x, box.z))
			. append_failure_message(
				(
					"%s is %.3f m across, under the %.3f a hatch needs"
					% [pid, minf(box.x, box.z), needed]
				)
			)
			. is_greater_equal(needed - TOL)
		)
	assert_int(checked).is_greater(0)
