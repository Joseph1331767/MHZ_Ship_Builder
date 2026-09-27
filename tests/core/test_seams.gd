# Seams and walls, ADR 0008. "after all rooms are defined and hatches, the objects must be
# subtracted or added to each other, with a flat faced seam where they mate; that flat seam is
# where we will cut the hatch doors into, centered auto placed."
#
# Every number here is read off the field, not off a mesh: a wall is a point that samples above
# -T where the plain union samples below it, a door is that point sampling below -T again, and a
# module's flat face is the sign flipping across the seam plane. The bake test in test_bake.gd
# checks that the walls reach the mesh.
class_name TestSeams
extends GdUnitTestSuite
## How thick a hull this test asserts against, and it is NOT the shipped default.
##
## A seam plate is a slab of the hull thickness, so how far it can lift the field depends on it: at
## the 0.20 m wall the lift is about 0.01 and the 0.05 threshold below is simply the wrong question
## to ask. 0.15 is the wall this threshold was tuned at, named here so the two move together or not
## at all - a test that reads whatever the default happens to be is a test that changes meaning
## when someone retunes a lever.
const WALL_M: float = 0.15

const TOL: float = 0.01
const TOL_V3: Vector3 = Vector3(0.01, 0.01, 0.01)

## A child wide enough that a doorway (0.8 m) and a crawlway hatch (0.7 m) both leave wall on
## either side of them, and tall enough that the default embed is not capped.
const CHILD_SCALE: Vector3 = Vector3(3.0, 1.0, 3.0)

var _data: ShipData
var _cfg: ShipConfig


## TEMPLATE LINKS ARE OPEN BY DEFAULT since 2026-09-26 ("by default in the prebuilds we dont want
## any walls in our prebuilds by default"). This suite is about what a ship with LINKS does - its
## walls, its doors, the rooms they bound or the meshes they cut - so it asks for the hatches the
## templates used to place, instead of resting on a default that no longer says that.
func _linked(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {ShipTemplates.OPT_LINK_MODE: ShipJoint.MODE_HATCHED}
	out.merge(extra)
	return out


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)
	_cfg = _data.config
	assert_float(_cfg.hull_thickness_m).is_greater(0.0)


# ---------------------------------------------------------------- fixtures


func _first_mfr(family: String) -> String:
	return _data.manufacturers_for(family)[0]


func _new_doc(family: String = "box_hull") -> ShipDoc:
	return ShipDoc.create_new(family, _first_mfr(family), _data, _cfg.root_span_m)


## A primitive under `parent_id` aimed (yaw, pitch), at the default embed. Returns its id.
func _add(doc: ShipDoc, parent_id: String, family: String, yaw: float, pitch: float) -> String:
	var part: ShipPart = ShipPart.new()
	part.parent = parent_id
	part.family = family
	part.manufacturer = _first_mfr(family)
	part.params = ShapeGen.default_params(_data, family, part.manufacturer)
	part.yaw = yaw
	part.pitch = pitch
	part.scale = CHILD_SCALE
	part.display_name = family
	part.offset = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, doc.parts[parent_id]),
		ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, part),
		part,
		_cfg
	)
	return doc.add_part(part)


func _join(doc: ShipDoc, a: String, b: String, mode: String, hatch_family: String = "") -> String:
	var joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(),
		{"a": a, "b": b, "mode": mode, "hatch": {"family": hatch_family, "params": {}}}
	)
	doc.joints[joint.id] = joint
	return joint.id


func _seam_for(sdf: ShipSdf, child: String) -> Dictionary:
	for seam: Dictionary in sdf.seams():
		if seam[ShipSeams.SEAM_CHILD] == child:
			return seam
	return {}


## A point in the seam frame: (u, v) across the plane, `depth` metres INTO the host (along -N).
func _at(seam: Dictionary, u: float, v: float, depth: float) -> Vector3:
	var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
	return frame.origin + frame.basis.x * u + frame.basis.y * v - frame.basis.z * depth


func _plate_centre(seam: Dictionary) -> Vector3:
	return _at(seam, 0.0, 0.0, _cfg.hull_thickness_m * 0.5)


func _index_of(sdf: ShipSdf, id: String) -> int:
	for i: int in sdf.part_count():
		if sdf.part_id_at(i) == id:
			return i
	return -1


## The plain min() union at `p`, with no plate: what the field was before ADR 0008.
func _union_at(sdf: ShipSdf, p: Vector3) -> float:
	var d: float = INF
	for i: int in sdf.part_count():
		d = minf(d, sdf.sample_part(i, p))
	return d


# ---------------------------------------------------------------- where the seam is


func test_a_child_on_a_box_face_seams_on_that_face() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	assert_int(sdf.seam_count()).is_equal(1)
	var seam: Dictionary = _seam_for(sdf, child)
	assert_bool(seam.is_empty()).is_false()
	assert_str(seam[ShipSeams.SEAM_HOST]).is_equal(doc.root)
	assert_str(seam[ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_WALL)
	assert_bool((seam[ShipSeams.SEAM_HOLE] as Dictionary).is_empty()).is_true()
	var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
	# The root box spans root_span_m; +Y aim lands on its top face, normal straight up.
	var half: float = _cfg.root_span_m * 0.5
	assert_vector(frame.origin).is_equal_approx(Vector3(0.0, half, 0.0), TOL_V3)
	assert_vector(frame.basis.z).is_equal_approx(Vector3.UP, TOL_V3)
	# The plane is the one the part actually sits on: the child's transform is on its normal.
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	var child_origin: Vector3 = (xforms[child] as Transform3D).origin
	var off: Vector3 = child_origin - frame.origin
	assert_float(off.cross(frame.basis.z).length()).is_less(TOL)


# ---------------------------------------------------------------- what closes it


func test_no_joint_is_a_solid_wall() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	var t: float = _cfg.hull_thickness_m
	var centre: Vector3 = _plate_centre(seam)
	# The plain union is cavity here - the child's interior merges into the box's.
	assert_float(_union_at(sdf, centre)).is_less(-t)
	# The wall is solid and never cavity: inside the slab the field sits in [-T, -T/2].
	var d: float = sdf.sample(centre)
	assert_float(d).is_greater(-t)
	assert_float(d).is_less(0.0)
	# The child's room above the wall is still a room.
	assert_float(sdf.sample(_at(seam, 0.0, 0.0, -2.0 * t))).is_less(-t)


func test_sealed_is_the_same_wall() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	_join(doc, doc.root, child, ShipJoint.MODE_SEALED)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	assert_str(seam[ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_WALL)
	assert_float(sdf.sample(_plate_centre(seam))).is_greater(-_cfg.hull_thickness_m)


func test_open_lays_no_plate() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	_join(doc, doc.root, child, ShipJoint.MODE_OPEN)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	assert_str(seam[ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_OPEN)
	assert_str(str((seam[ShipSeams.SEAM_HOLE] as Dictionary).get("kind", ""))).is_equal(
		ShipSeams.KIND_ALL
	)
	var centre: Vector3 = _plate_centre(seam)
	assert_float(sdf.sample(centre)).is_equal_approx(_union_at(sdf, centre), TOL)


func test_a_doorway_opens_the_wall_at_its_centre_only() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	_join(doc, doc.root, child, ShipJoint.MODE_DOORWAY)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	assert_str(seam[ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_DOORWAY)
	var hole: Dictionary = seam[ShipSeams.SEAM_HOLE]
	assert_str(str(hole[ShipSeams.HOLE_KIND])).is_equal(ShipSeams.KIND_RECT)
	assert_vector(hole[ShipSeams.HOLE_SIZE]).is_equal_approx(
		Vector2(_cfg.doorway_width_m, _cfg.doorway_height_m), Vector2(TOL, TOL)
	)
	var t: float = _cfg.hull_thickness_m
	var depth: float = t * 0.5
	# Centred on the seam: through the door it is cavity again ...
	assert_float(sdf.sample(_at(seam, 0.0, 0.0, depth))).is_less(-t)
	# ... and beside the door, still inside the child's footprint, it is wall.
	var beside: float = _cfg.doorway_width_m * 0.5 + 0.4
	assert_float(sdf.sample(_at(seam, beside, 0.0, depth))).is_greater(-t)
	assert_float(sdf.sample(_at(seam, -beside, 0.0, depth))).is_greater(-t)


func test_a_hatch_opens_the_hatch_families_hole() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	_join(doc, doc.root, child, ShipJoint.MODE_HATCHED, "crawlway_round")
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	assert_str(seam[ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_HATCHED)
	var hole: Dictionary = seam[ShipSeams.SEAM_HOLE]
	assert_str(str(hole[ShipSeams.HOLE_KIND])).is_equal(ShipSeams.KIND_CIRCLE)
	# crawlway_round's pack default radius is 0.35 m: the hole is 0.7 m across.
	var radius: float = (hole[ShipSeams.HOLE_SIZE] as Vector2).x * 0.5
	assert_float(radius).is_equal_approx(0.35, TOL)
	var t: float = _cfg.hull_thickness_m
	var depth: float = t * 0.5
	assert_float(sdf.sample(_at(seam, radius * 0.5, 0.0, depth))).is_less(-t)
	assert_float(sdf.sample(_at(seam, radius + 0.3, 0.0, depth))).is_greater(-t)


func test_a_stored_hatch_param_overrides_the_pack_default() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var jid: String = _join(doc, doc.root, child, ShipJoint.MODE_HATCHED, "crawlway_round")
	(doc.joints[jid] as ShipJoint).hatch_params = {"radius": 0.5}
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var hole: Dictionary = _seam_for(sdf, child)[ShipSeams.SEAM_HOLE]
	assert_float((hole[ShipSeams.HOLE_SIZE] as Vector2).x).is_equal_approx(1.0, TOL)


func test_zero_thickness_lays_no_plate() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var thin: ShipConfig = ShipConfig.from_dict(_cfg.snapshot())
	thin.hull_thickness_m = 0.0
	var sdf: ShipSdf = ShipSdf.build(doc, _data, thin)
	assert_int(sdf.seam_count()).is_equal(1)
	var seam: Dictionary = _seam_for(sdf, child)
	var p: Vector3 = _at(seam, 0.0, 0.0, _cfg.hull_thickness_m * 0.5)
	assert_float(sdf.sample(p)).is_equal_approx(_union_at(sdf, p), 1.0e-6)


# ---------------------------------------------------------------- twins, components


func test_the_twin_of_a_child_seams_on_the_mirror() -> void:
	var doc: ShipDoc = _new_doc()
	doc.symmetry_plane = "x"
	var child: String = _add(doc, doc.root, "cylinder_spar", 90.0, 0.0)
	_join(doc, doc.root, child, ShipJoint.MODE_DOORWAY)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	assert_int(sdf.seam_count()).is_equal(2)
	var source: Dictionary = _seam_for(sdf, child)
	var twin: Dictionary = _seam_for(sdf, ShipSymmetry.twin_id(child))
	assert_bool(twin.is_empty()).is_false()
	assert_str(twin[ShipSeams.SEAM_HOST]).is_equal(doc.root)
	assert_str(twin[ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_DOORWAY)
	var a: Transform3D = source[ShipSeams.SEAM_FRAME]
	var b: Transform3D = twin[ShipSeams.SEAM_FRAME]
	assert_float(b.origin.x).is_equal_approx(-a.origin.x, TOL)
	assert_float(b.origin.y).is_equal_approx(a.origin.y, TOL)
	assert_float(b.basis.z.x).is_equal_approx(-a.basis.z.x, TOL)
	# And the twin's wall is a wall too.
	var t: float = _cfg.hull_thickness_m
	assert_float(sdf.sample(_at(twin, 0.0, 0.0, t * 0.5))).is_less(-t)
	assert_float(sdf.sample(_at(twin, _cfg.doorway_width_m * 0.5 + 0.4, 0.0, t * 0.5))).is_greater(
		-t
	)


func test_a_component_is_one_room_with_one_seam() -> void:
	var doc: ShipDoc = _new_doc()
	var arm: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var hand: String = _add(doc, arm, "sphere_pod", 0.0, 90.0)
	# Arm and hand linked open BEFORE the lift: the link travels into the definition (ADR 0025).
	var open_joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(), {"a": arm, "b": hand, "mode": ShipJoint.MODE_OPEN}
	)
	doc.joints[open_joint.id] = open_joint
	var before: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	assert_int(before.seam_count()).is_equal(2)
	var component_id: String = ShipComponents.make_component(
		doc, PackedStringArray([arm, hand]), "Arm"
	)
	assert_str(component_id).is_not_empty()
	var instance: String = ""
	for pid: String in doc.parts:
		if (doc.parts[pid] as ShipPart).kind == ShipPart.KIND_COMPONENT_INSTANCE:
			instance = pid
	assert_str(instance).is_not_empty()
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	# Three entries - the root, the instance's proxy, the inner sphere - and TWO seams: the
	# instance's on the root, walled, and the inner sphere's on the instance, OPEN as the
	# definition's joint says (ADR 0025); the exploded view pulls the pieces apart along it.
	assert_int(sdf.part_count()).is_equal(3)
	assert_int(sdf.seam_count()).is_equal(2)
	assert_str(sdf.seams()[0][ShipSeams.SEAM_CHILD]).is_equal(instance)
	assert_str(sdf.seams()[0][ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_WALL)
	assert_str(sdf.seams()[1][ShipSeams.SEAM_HOST]).is_equal(instance)
	assert_str(sdf.seams()[1][ShipSeams.SEAM_MODE]).is_equal(ShipSeams.MODE_OPEN)
	(
		assert_array(ShipSeams.module_ids(doc, ShipAttach.resolve_all(doc, _data, _cfg)))
		. contains_exactly([doc.root, instance])
	)


func test_a_part_on_an_instance_seams_on_the_instance() -> void:
	var doc: ShipDoc = _new_doc()
	var arm: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var component_id: String = ShipComponents.make_component(doc, PackedStringArray([arm]), "Arm")
	assert_str(component_id).is_not_empty()
	var instance: String = ""
	for pid: String in doc.parts:
		if (doc.parts[pid] as ShipPart).kind == ShipPart.KIND_COMPONENT_INSTANCE:
			instance = pid
	var stud: String = _add(doc, instance, "sphere_pod", 0.0, 90.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, stud)
	assert_bool(seam.is_empty()).is_false()
	assert_str(seam[ShipSeams.SEAM_HOST]).is_equal(instance)


# ---------------------------------------------------------------- module views


func test_module_view_cuts_the_child_flat_at_its_seam() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	var view: ShipSdf = sdf.module_view(child)
	assert_int(view.part_count()).is_equal(1)
	assert_int(view.seam_count()).is_equal(0)
	# The whole part is inside itself on both sides of the plane ...
	var child_index: int = _index_of(sdf, child)
	assert_float(sdf.sample_part(child_index, _at(seam, 0.0, 0.0, 0.05))).is_less(0.0)
	# ... but the module stops at the plane: outside just below it, inside just above.
	assert_float(view.sample(_at(seam, 0.0, 0.0, 0.05))).is_greater(0.0)
	assert_float(view.sample(_at(seam, 0.0, 0.0, -0.05))).is_less(0.0)
	# The flat face's wall is solid at half depth, and the face itself is on the plane.
	var t: float = _cfg.hull_thickness_m
	assert_float(view.sample(_at(seam, 0.0, 0.0, -t * 0.5))).is_less(0.0)
	assert_float(view.sample(_at(seam, 0.0, 0.0, 0.0))).is_equal_approx(0.0, 1.0e-4)


func test_module_view_adds_the_collar_to_a_curved_host() -> void:
	var doc: ShipDoc = _new_doc("sphere_pod")
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	# Off the pole, just under the tangent plane: outside the sphere, inside the sunk child.
	var p: Vector3 = _at(seam, 1.0, 0.0, 0.02)
	var root_index: int = _index_of(sdf, doc.root)
	assert_float(sdf.sample_part(root_index, p)).is_greater(0.0)
	assert_float(sdf.sample_part(_index_of(sdf, child), p)).is_less(0.0)
	var host: ShipSdf = sdf.module_view(doc.root)
	assert_int(host.part_count()).is_equal(2)
	assert_float(host.sample(p)).is_less(0.0)
	# And the collar stops at the plane, where the child module begins.
	assert_float(host.sample(_at(seam, 1.0, 0.0, -0.05))).is_greater(0.0)


func test_module_view_bores_the_door_through_both_sides() -> void:
	var doc: ShipDoc = _new_doc("sphere_pod")
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var t: float = _cfg.hull_thickness_m
	var walled: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(walled, child)
	var into_host: Vector3 = _at(seam, 0.0, 0.0, t * 0.5)
	var into_child: Vector3 = _at(seam, 0.0, 0.0, -t * 0.5)
	assert_float(walled.module_view(doc.root).sample(into_host)).is_less(0.0)
	assert_float(walled.module_view(child).sample(into_child)).is_less(0.0)
	_join(doc, doc.root, child, ShipJoint.MODE_DOORWAY)
	var doored: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	assert_float(doored.module_view(doc.root).sample(into_host)).is_greater(0.0)
	assert_float(doored.module_view(child).sample(into_child)).is_greater(0.0)
	# Beside the door both faces are still wall.
	var beside: float = _cfg.doorway_width_m * 0.5 + 0.4
	assert_float(doored.module_view(doc.root).sample(_at(seam, beside, 0.0, t * 0.5))).is_less(0.0)
	assert_float(doored.module_view(child).sample(_at(seam, beside, 0.0, -t * 0.5))).is_less(0.0)


func test_an_open_seam_leaves_the_module_face_off() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	_join(doc, doc.root, child, ShipJoint.MODE_OPEN)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var seam: Dictionary = _seam_for(sdf, child)
	var t: float = _cfg.hull_thickness_m
	var view: ShipSdf = sdf.module_view(child)
	# Anywhere across the face, at half the wall's depth, is air.
	assert_float(view.sample(_at(seam, 0.0, 0.0, -t * 0.5))).is_greater(0.0)
	assert_float(view.sample(_at(seam, 1.0, 0.0, -t * 0.5))).is_greater(0.0)
	# Deeper in, the module is still solid where its side wall is.
	assert_float(view.sample(_at(seam, 1.45, 0.0, -1.0))).is_less(0.0)


# ---------------------------------------------------------------- explode


func test_explode_offsets_accumulate_down_the_chain() -> void:
	var doc: ShipDoc = _new_doc()
	var child: String = _add(doc, doc.root, "cylinder_spar", 0.0, 90.0)
	var grandchild: String = _add(doc, child, "sphere_pod", 0.0, 90.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var boxes: Dictionary = {}
	for i: int in sdf.part_count():
		boxes[sdf.part_id_at(i)] = sdf.part_aabb(i)
	var offsets: Dictionary = ShipSeams.explode_offsets(sdf.seams(), _cfg, boxes)
	assert_bool(offsets.has(doc.root)).is_false()
	var c: Vector3 = offsets[child]
	var g: Vector3 = offsets[grandchild]
	assert_float(c.y).is_greater_equal(_cfg.explode_gap_m)
	assert_float(absf(c.x) + absf(c.z)).is_less(TOL)
	assert_float(g.y).is_greater(c.y + _cfg.explode_gap_m - TOL)


func test_explode_leaves_no_two_modules_overlapping() -> void:
	# "explode has some parts overlapping and thats incorrect." Clearing a module from its HOST is
	# all one seam knows about, and nothing in it separates SIBLINGS - which the atomic templates
	# make ordinary, since a nucleus body and an extremity take their directions from two different
	# arrangements that are free to point the same way.
	for name: String in ["lithium", "carbon", "argon"]:
		var doc: ShipDoc = ShipTemplates.build(_data, _cfg, name, _linked())
		var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
		var boxes: Dictionary = {}
		var order: PackedStringArray = PackedStringArray()
		for i: int in sdf.part_count():
			var module: String = ShipSeams.module_of(sdf.part_id_at(i))
			if boxes.has(module):
				boxes[module] = (boxes[module] as AABB).merge(sdf.part_aabb(i))
			else:
				order.append(module)
				boxes[module] = sdf.part_aabb(i)
		var offsets: Dictionary = ShipSeams.explode_offsets(sdf.seams(), _cfg, boxes)

		var placed: Dictionary = {}
		for id: String in order:
			var box: AABB = boxes[id]
			placed[id] = AABB(box.position + (offsets.get(id, Vector3.ZERO) as Vector3), box.size)
		for i: int in order.size():
			for j: int in range(i + 1, order.size()):
				var one: AABB = placed[order[i]]
				var two: AABB = placed[order[j]]
				if not one.intersects(two):
					continue
				var shared: AABB = one.intersection(two)
				var deep: float = minf(shared.size.x, minf(shared.size.y, shared.size.z))
				(
					assert_float(deep)
					. append_failure_message(
						"%s exploded: %s and %s still overlap" % [name, order[i], order[j]]
					)
					. is_less_equal(TOL)
				)


func test_seams_are_deterministic() -> void:
	var doc: ShipDoc = _new_doc()
	doc.symmetry_plane = "x"
	var child: String = _add(doc, doc.root, "cylinder_spar", 90.0, 0.0)
	_add(doc, child, "sphere_pod", 0.0, 90.0)
	_join(doc, doc.root, child, ShipJoint.MODE_HATCHED, "iris_round")
	var a: Array[Dictionary] = ShipSdf.build(doc, _data, _cfg).seams()
	var b: Array[Dictionary] = ShipSdf.build(doc, _data, _cfg).seams()
	assert_int(a.size()).is_equal(b.size())
	assert_int(a.size()).is_equal(4)
	for i: int in a.size():
		assert_str(a[i][ShipSeams.SEAM_CHILD]).is_equal(b[i][ShipSeams.SEAM_CHILD])
		assert_str(a[i][ShipSeams.SEAM_MODE]).is_equal(b[i][ShipSeams.SEAM_MODE])
		var fa: Transform3D = a[i][ShipSeams.SEAM_FRAME]
		var fb: Transform3D = b[i][ShipSeams.SEAM_FRAME]
		assert_bool(fa.is_equal_approx(fb)).is_true()


func test_hole_distance_signs() -> void:
	var rect: Dictionary = {
		ShipSeams.HOLE_KIND: ShipSeams.KIND_RECT,
		ShipSeams.HOLE_SIZE: Vector2(1.0, 2.0),
		ShipSeams.HOLE_CORNER: 0.1,
	}
	assert_float(ShipSeams.hole_distance(rect, Vector2.ZERO)).is_less(0.0)
	assert_float(ShipSeams.hole_distance(rect, Vector2(0.45, 0.0))).is_less(0.0)
	assert_float(ShipSeams.hole_distance(rect, Vector2(0.55, 0.0))).is_greater(0.0)
	assert_float(ShipSeams.hole_distance(rect, Vector2(0.0, 1.05))).is_greater(0.0)
	var circle: Dictionary = {
		ShipSeams.HOLE_KIND: ShipSeams.KIND_CIRCLE, ShipSeams.HOLE_SIZE: Vector2(1.0, 1.0)
	}
	assert_float(ShipSeams.hole_distance(circle, Vector2(0.3, 0.3))).is_less(0.0)
	assert_float(ShipSeams.hole_distance(circle, Vector2(0.4, 0.4))).is_greater(0.0)
	var oval: Dictionary = {
		ShipSeams.HOLE_KIND: ShipSeams.KIND_ELLIPSE, ShipSeams.HOLE_SIZE: Vector2(1.0, 2.0)
	}
	assert_float(ShipSeams.hole_distance(oval, Vector2(0.0, 0.9))).is_less(0.0)
	assert_float(ShipSeams.hole_distance(oval, Vector2(0.0, 1.1))).is_greater(0.0)
	assert_float(ShipSeams.hole_distance(oval, Vector2(0.6, 0.0))).is_greater(0.0)
	assert_bool(ShipSeams.hole_distance({}, Vector2.ZERO) == INF).is_true()
	(
		assert_bool(
			ShipSeams.hole_distance({ShipSeams.HOLE_KIND: ShipSeams.KIND_ALL}, Vector2.ZERO) == -INF
		)
		. is_true()
	)


# ---------------------------------------------------------------- seam styles (ADR 0009)
#
# "id like to be able to select 2 shapes, right click them and have 3 options for seem, parent
# indents child > child indents parent > and flat plane at intersection."
#
# The fixture below is a BOX ON A SPHERE, chosen because it is the case where the three answers
# visibly differ: the sphere curves away from the flat tangent plane, so the parent's surface,
# the child's surface and the plane are three different places to put the wall. Probe points are
# found by bisecting the field itself rather than hand-computed, so a retuned data pack cannot
# quietly turn these into assertions about nothing.


## A box sunk into the sphere root, returned as [child_id, joint_id]. `style` is written onto the
## joint, whose mode is SEALED so the seam carries a plain wall.
func _styled_pair(doc: ShipDoc, style: String) -> String:
	var child: String = _add(doc, doc.root, "box_hull", 0.0, 90.0)
	var jid: String = _join(doc, doc.root, child, ShipJoint.MODE_SEALED)
	(doc.joints[jid] as ShipJoint).seam_style = style
	return child


## The y where part `index`'s surface crosses the vertical line at `x`, bisected between a y
## known inside and one known outside.
func _surface_y(sdf: ShipSdf, index: int, x: float, y_in: float, y_out: float) -> float:
	var lo: float = y_in
	var hi: float = y_out
	for _i: int in 40:
		var mid: float = (lo + hi) * 0.5
		if sdf.sample_part(index, Vector3(x, mid, 0.0)) < 0.0:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _index_of_part(sdf: ShipSdf, id: String) -> int:
	for i: int in sdf.part_count():
		if sdf.part_id_at(i) == id:
			return i
	return -1


## The three probe points on the vertical line one metre off the seam axis, where the parent's
## surface, the plane and the child's surface are all in different places:
##   { "host": half a thickness inside the SPHERE's surface,
##     "plane": half a thickness below the seam PLANE,
##     "child": half a thickness above the BOX's underside,
##     "overlap": a point inside both solids }
func _probes(sdf: ShipSdf, child: String, seam: Dictionary) -> Dictionary:
	var host_i: int = _index_of_part(sdf, "p_0001")
	var child_i: int = _index_of_part(sdf, child)
	var t: float = _cfg.hull_thickness_m
	var x: float = 1.0
	var y_host: float = _surface_y(sdf, host_i, x, 0.0, 6.0)
	var y_child: float = _surface_y(
		sdf, child_i, x, (seam[ShipSeams.SEAM_FRAME] as Transform3D).origin.y, 0.0
	)
	var y_plane: float = (seam[ShipSeams.SEAM_FRAME] as Transform3D).origin.y
	return {
		"host": Vector3(x, y_host - t * 0.5, 0.0),
		"plane": Vector3(x, y_plane - t * 0.5, 0.0),
		"child": Vector3(x, y_child + t * 0.5, 0.0),
		"overlap": Vector3(x, (y_host + y_child) * 0.5, 0.0),
		"y_host": y_host,
		"y_child": y_child,
		"y_plane": y_plane,
	}


func test_the_three_probe_points_are_actually_different_places() -> void:
	# The fixture has to discriminate before any verdict built on it means anything.
	var doc: ShipDoc = _new_doc("sphere_pod")
	var child: String = _styled_pair(doc, ShipJoint.SEAM_FLAT)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var p: Dictionary = _probes(sdf, child, _seam_for(sdf, child))
	var t: float = _cfg.hull_thickness_m
	(
		assert_float(float(p["y_plane"]) - float(p["y_host"]))
		. append_failure_message(
			(
				"the sphere's surface and the seam plane are within a wall of each other one metre "
				+ "off axis, so this fixture cannot tell the styles apart"
			)
		)
		. is_greater(t)
	)
	assert_float(float(p["y_host"]) - float(p["y_child"])).is_greater(t)


func test_each_style_puts_its_wall_on_its_own_surface() -> void:
	_cfg.hull_thickness_m = WALL_M
	var t: float = _cfg.hull_thickness_m
	# style -> the probe that must be WALL under it; under the other two styles that same probe
	# must stay cavity. That is what makes this a statement about WHERE the wall is rather than
	# merely that one exists.
	#
	# HOW "WALL" IS ASKED. Not "is the field shallower than -T": every one of these probes sits
	# half a wall inside some real surface, so all three are shallower than -T whatever the plate
	# does. And not "is the field unchanged" either - a plate is a max() term over its whole seam
	# box, so outside its own slab it can still raise the distance (measured: the parent style
	# lifts the plane probe from -0.377 to -0.293) without ever reaching hull, which is the
	# harmless distance distortion ADR 0008 records. The claim that is exactly true: the plate
	# turns cavity into HULL at its own seam surface and nowhere else.
	var expected: Dictionary = {
		ShipJoint.SEAM_FLAT: "plane",
		ShipJoint.SEAM_BIG_NATIVE: "host",
		ShipJoint.SEAM_SMALL_NATIVE: "child",
	}
	for style: String in expected:
		var doc: ShipDoc = _new_doc("sphere_pod")
		var child: String = _styled_pair(doc, style)
		var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
		var p: Dictionary = _probes(sdf, child, _seam_for(sdf, child))
		for probe: String in ["host", "plane", "child"]:
			var at: Vector3 = p[probe]
			var d: float = sdf.sample(at)
			var bare: float = _union_at(sdf, at)
			if probe == expected[style]:
				(
					assert_float(d - bare)
					. append_failure_message(
						(
							(
								"style '%s': the %s probe %s should be WALL - the plate must raise the field "
								+ "there. sampled %.4f, bare union %.4f"
							)
							% [style, probe, str(at), d, bare]
						)
					)
					. is_greater(t * 0.25)
				)
				# Solid: never cavity, and never outside the hull either.
				assert_float(d).is_greater(-t)
				assert_float(d).is_less(0.0)
			else:
				# Still cavity - or still exactly as deep as the bare union was, where the probe was
				# already within a wall of some real skin.
				var ceiling: float = maxf(bare, -t)
				(
					assert_float(d)
					. append_failure_message(
						(
							(
								"style '%s': the %s probe %s must not become hull, but sample %.4f rose above "
								+ "%.4f (bare union %.4f, wall thickness %.3f)"
							)
							% [style, probe, str(at), d, ceiling, bare, t]
						)
					)
					. is_less_equal(ceiling + 0.001)
				)


func test_every_style_partitions_the_overlap_between_exactly_one_module() -> void:
	# The invariant that makes all three honest: whichever surface the seam follows, a point where
	# the two solids overlap belongs to exactly one module. Two would double-count its volume;
	# none would leave a hole between the pieces.
	for style: String in [
		ShipJoint.SEAM_FLAT, ShipJoint.SEAM_BIG_NATIVE, ShipJoint.SEAM_SMALL_NATIVE
	]:
		var doc: ShipDoc = _new_doc("sphere_pod")
		var child: String = _styled_pair(doc, style)
		var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
		var seam: Dictionary = _seam_for(sdf, child)
		var p: Dictionary = _probes(sdf, child, seam)
		var host_view: ShipSdf = sdf.module_view(doc.root)
		var child_view: ShipSdf = sdf.module_view(child)
		# Several points across the overlap, not just one: a partition that only holds on the
		# axis is not a partition.
		for frac: float in [0.2, 0.5, 0.8]:
			var y: float = lerpf(float(p["y_child"]), float(p["y_host"]), frac)
			var probe: Vector3 = Vector3(1.0, y, 0.0)
			var in_host: bool = host_view.sample(probe) < 0.0
			var in_child: bool = child_view.sample(probe) < 0.0
			(
				assert_bool(in_host != in_child)
				. append_failure_message(
					(
						(
							"style '%s': the overlap point %s is inside %s - it must belong to exactly "
							+ "one module"
						)
						% [style, str(probe), "both modules" if in_host else "neither module"]
					)
				)
				. is_true()
			)


func test_parent_indents_child_dents_the_child_and_leaves_the_host_whole() -> void:
	var doc: ShipDoc = _new_doc("sphere_pod")
	var child: String = _styled_pair(doc, ShipJoint.SEAM_BIG_NATIVE)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var p: Dictionary = _probes(sdf, child, _seam_for(sdf, child))
	var probe: Vector3 = p["overlap"]
	# The overlap is the parent's: its module keeps it, the child's module has it carved out.
	assert_float(sdf.module_view(doc.root).sample(probe)).is_less(0.0)
	assert_float(sdf.module_view(child).sample(probe)).is_greater(0.0)
	# And the host is not cut anywhere by this: a point deep inside the sphere and clear of the
	# child is still solid host.
	assert_float(sdf.module_view(doc.root).sample(Vector3(0.0, -1.0, 0.0))).is_less(0.0)


func test_child_indents_parent_is_the_mirror_of_it() -> void:
	var doc: ShipDoc = _new_doc("sphere_pod")
	var child: String = _styled_pair(doc, ShipJoint.SEAM_SMALL_NATIVE)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var p: Dictionary = _probes(sdf, child, _seam_for(sdf, child))
	var probe: Vector3 = p["overlap"]
	assert_float(sdf.module_view(child).sample(probe)).is_less(0.0)
	assert_float(sdf.module_view(doc.root).sample(probe)).is_greater(0.0)


func test_a_seam_style_round_trips_and_flat_writes_no_key() -> void:
	# The hash argument: a flat joint - which is every joint ever saved before ADR 0009 - must
	# serialize exactly as it did, or the canonical form of every existing file moves and with it
	# its doc_hash.
	var joint: ShipJoint = ShipJoint.from_dict("j_0001", {"a": "p_0001", "b": "p_0002"})
	assert_str(joint.seam_style).is_equal(ShipJoint.SEAM_FLAT)
	assert_bool(joint.to_dict().has("seam")).is_false()
	for style: String in [ShipJoint.SEAM_BIG_NATIVE, ShipJoint.SEAM_SMALL_NATIVE]:
		joint.seam_style = style
		var written: Dictionary = joint.to_dict()
		assert_str(str(written["seam"])).is_equal(style)
		assert_str(ShipJoint.from_dict("j_0001", written).seam_style).is_equal(style)
	# An unrecognised style is flat, not a crash and not a silently different geometry.
	var odd: ShipJoint = ShipJoint.from_dict("j_0002", {"a": "x", "b": "y", "seam": "bevelled"})
	assert_str(odd.seam_style).is_equal(ShipJoint.SEAM_FLAT)


# ---------------------------------------------------------------- linking a selection


func test_pairs_within_names_the_seams_inside_a_selection() -> void:
	# What LINK acts on when several parts are selected: the seams internal to the selection, and
	# not the one that leaves it.
	var doc: ShipDoc = _new_doc()
	var a: String = _add(doc, doc.root, "box_hull", 0.0, 90.0)
	var b: String = _add(doc, a, "box_hull", 0.0, 90.0)
	var outside: String = _add(doc, doc.root, "box_hull", 0.0, -90.0)

	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(
		doc, PackedStringArray([doc.root, a, b])
	)
	assert_int(pairs.size()).is_equal(2)
	var keys: PackedStringArray = PackedStringArray()
	for pair: PackedStringArray in pairs:
		keys.append(ShipDoc.joint_key_for(pair[0], pair[1]))
	keys.sort()
	var wanted: PackedStringArray = PackedStringArray(
		[ShipDoc.joint_key_for(a, doc.root), ShipDoc.joint_key_for(b, a)]
	)
	wanted.sort()
	assert_array(keys).is_equal(wanted)

	# The part left out of the selection contributes no seam, however joined it is.
	for pair: PackedStringArray in pairs:
		assert_bool(pair.has(outside)).is_false()

	# One part on its own names nothing; a part and a stranger name nothing either.
	assert_int(ShipSeams.pairs_within(doc, PackedStringArray([a])).size()).is_equal(0)
	assert_int(ShipSeams.pairs_within(doc, PackedStringArray()).size()).is_equal(0)


func test_two_parts_are_a_pair_even_when_neither_stands_on_the_other() -> void:
	# Two siblings that grew into each other meet as truly as a child meets its host, and a joint
	# is keyed over an unordered pair rather than over the attach tree. LINK on exactly two parts
	# must reach them.
	var doc: ShipDoc = _new_doc()
	var one: String = _add(doc, doc.root, "box_hull", 0.0, 90.0)
	var two: String = _add(doc, doc.root, "box_hull", 0.0, -90.0)
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(doc, PackedStringArray([one, two]))
	assert_int(pairs.size()).is_equal(1)
	assert_str(ShipDoc.joint_key_for(pairs[0][0], pairs[0][1])).is_equal(
		ShipDoc.joint_key_for(one, two)
	)


func test_shared_mode_reports_the_wall_when_a_selection_disagrees() -> void:
	# A mixed selection unifies before it cycles: reporting the wall makes the next step land on
	# DOORWAY for all of them, where reporting whichever mode came first would make the result
	# depend on dictionary order.
	var doc: ShipDoc = _new_doc()
	var a: String = _add(doc, doc.root, "box_hull", 0.0, 90.0)
	var b: String = _add(doc, a, "box_hull", 0.0, 90.0)
	var ids: PackedStringArray = PackedStringArray([doc.root, a, b])
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(doc, ids)

	assert_str(ShipSeams.shared_mode(doc, pairs)).is_equal(ShipSeams.MODE_WALL)
	_join(doc, doc.root, a, ShipJoint.MODE_OPEN)
	assert_str(ShipSeams.shared_mode(doc, pairs)).is_equal(ShipSeams.MODE_WALL)
	_join(doc, a, b, ShipJoint.MODE_OPEN)
	assert_str(ShipSeams.shared_mode(doc, pairs)).is_equal(ShipSeams.MODE_OPEN)
