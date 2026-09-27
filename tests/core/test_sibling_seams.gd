# SIBLING SEAMS (ADR 0034): a seam between two parts that stand SIDE BY SIDE rather than one upon
# the other. Every other seam borrows the attach model's own plane - the anchor P on the host and
# the normal N there - and two parts anchored to the beacon (ADR 0033) have none to borrow, so the
# line between their centres stands in: it finds the host's surface on the way to the child, and it
# is the way the two come apart. FOLLOWUPS F19 recorded the limitation this lifts.
class_name TestSiblingSeams
extends GdUnitTestSuite
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
		. append_failure_message("ShipData.load_all() failed: %s" % [str(_data.load_errors)])
		. is_true()
	)
	_cfg = ShipConfig.defaults()


## SIBLING SEAMS (ADR 0034): two parts that stand side by side and MEET have a seam wherever a joint
## says so - the plane on the host's surface, the normal along the line between their centres. This
## is FOLLOWUPS F19's limitation lifted; without it a nucleus ringing the beacon carries no links at
## all and every body bakes as a room of its own.
func test_two_anchored_parts_that_meet_get_a_seam() -> void:
	var doc: ShipDoc = ShipDoc.create_new("sphere_pod", "", _data, 0.0)
	# Far enough apart to overlap like two fused bodies rather than to sit inside each other.
	var radius: float = (
		(ShipAttach.resolve_shapes(doc, _data, _cfg)[doc.root] as ResolvedShape).local_aabb().size.x
		* 0.5
	)
	var beside: ShipPart = ShipPart.new()
	beside.kind = ShipPart.KIND_PRIMITIVE
	beside.family = "sphere_pod"
	beside.params = ShapeGen.default_params(_data, "sphere_pod", "")
	beside.absolute = Transform3D(Basis.IDENTITY, Vector3(radius * 1.4, 0.0, 0.0))
	# No mirror twin: this test is about the seam between these two and nothing else.
	beside.asymmetric = true
	var other: String = doc.add_part(beside)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	# Neither stands on the other, and nothing joins them: they merge, exactly as they always did.
	assert_int(ShipSeams.seams(doc, shapes, xforms, _cfg, _data).size()).is_equal(0)
	var joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(), {"a": doc.root, "b": other, "mode": ShipJoint.MODE_OPEN}
	)
	doc.joints[joint.id] = joint
	var seams: Array[Dictionary] = ShipSeams.seams(doc, shapes, xforms, _cfg, _data)
	assert_int(seams.size()).is_equal(1)
	var seam: Dictionary = seams[0]
	assert_str(str(seam[ShipSeams.SEAM_MODE])).is_equal(ShipSeams.MODE_OPEN)
	# The host is the one placed first, so the chain the explode walks cannot close on itself.
	assert_str(str(seam[ShipSeams.SEAM_HOST])).is_equal(doc.root)
	var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
	# The normal runs from the host to the child, and the plane stands ON THE HOST'S SURFACE, which
	# on a sphere is its own radius away along that line - the face a wall would be built on.
	assert_vector(frame.basis.z.normalized()).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.01)
	assert_float(frame.origin.x).is_equal_approx(radius, radius * 0.02)
	assert_float(absf(frame.origin.y) + absf(frame.origin.z)).is_less(0.01)


## Far enough apart and the same joint is inert: a record over two solids that never meet describes
## nothing, and inventing a plane for it would put a wall in open space.
func test_two_anchored_parts_that_miss_each_other_get_none() -> void:
	var doc: ShipDoc = ShipDoc.create_new("sphere_pod", "", _data, 0.0)
	var away: ShipPart = ShipPart.new()
	away.kind = ShipPart.KIND_PRIMITIVE
	away.family = "sphere_pod"
	away.params = ShapeGen.default_params(_data, "sphere_pod", "")
	away.absolute = Transform3D(Basis.IDENTITY, Vector3(500.0, 0.0, 0.0))
	away.asymmetric = true
	var other: String = doc.add_part(away)
	var joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(), {"a": doc.root, "b": other, "mode": ShipJoint.MODE_OPEN}
	)
	doc.joints[joint.id] = joint
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	assert_int(ShipSeams.seams(doc, shapes, xforms, _cfg, _data).size()).is_equal(0)


## A seam whose frame IS the identity - two parts on the world Z axis meeting at the origin - is a
## seam like any other. It was dropped while "no seam" was reported as an identity transform, and a
## ship built around a beacon at the origin is exactly where that pair turns up.
func test_a_seam_that_lands_on_the_origin_is_still_a_seam() -> void:
	var doc: ShipDoc = ShipDoc.create_new("sphere_pod", "", _data, 0.0)
	var root: ShipPart = doc.parts[doc.root]
	root.asymmetric = true
	var radius: float = (
		(ShipAttach.resolve_shapes(doc, _data, _cfg)[doc.root] as ResolvedShape).local_aabb().size.z
		* 0.5
	)
	# The host one radius BACK of the origin, so its surface toward the child crosses exactly there.
	root.absolute = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -radius))
	var ahead: ShipPart = ShipPart.new()
	ahead.kind = ShipPart.KIND_PRIMITIVE
	ahead.family = "sphere_pod"
	ahead.params = ShapeGen.default_params(_data, "sphere_pod", "")
	ahead.absolute = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, radius * 0.5))
	ahead.asymmetric = true
	var other: String = doc.add_part(ahead)
	var joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(), {"a": doc.root, "b": other, "mode": ShipJoint.MODE_OPEN}
	)
	doc.joints[joint.id] = joint
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	var seams: Array[Dictionary] = ShipSeams.seams(doc, shapes, xforms, _cfg, _data)
	assert_int(seams.size()).is_equal(1)
	var frame: Transform3D = seams[0][ShipSeams.SEAM_FRAME]
	(
		assert_float(frame.origin.length())
		. append_failure_message("the seam did not land on the origin: %s" % str(frame.origin))
		. is_less(0.01)
	)
	assert_bool(frame.is_equal_approx(Transform3D())).is_true()


## TWO EQUAL MEMBERS OF A ROOM DIVIDE DOWN THE MIDDLE (ADR 0035). The plan says where, and for a
## pair of the same solid the plane is the perpendicular bisector - equidistant from both centres,
## square to the line between them. Cutting each piece back by the whole of its neighbours instead
## is a priority order, and a clump of equal bodies came out as that many different pieces.
func test_equal_members_of_a_room_divide_on_the_plane_between_them() -> void:
	var doc: ShipDoc = ShipTemplates.build(
		_data, _cfg, "carbon", _linked({ShipTemplates.OPT_ROOM_FAMILY: "box_hull"})
	)
	var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	var splits: Dictionary = plan["room_splits"]
	var nucleus: PackedStringArray = PackedStringArray()
	for members: PackedStringArray in plan["rooms"]:
		if members.size() > nucleus.size():
			nucleus = members
	assert_int(nucleus.size()).is_equal(6)
	for id: String in nucleus:
		var list: Array = splits.get(id, [])
		# Four neighbours each, on an octahedron: the body across the nucleus does not meet it.
		assert_int(list.size()).append_failure_message(id).is_equal(4)
		for entry: Dictionary in list:
			var other: String = str(entry["other"])
			var at: Vector3 = entry["origin"]
			var normal: Vector3 = entry["normal"]
			var here: Vector3 = (xforms[id] as Transform3D).origin
			var there: Vector3 = (xforms[other] as Transform3D).origin
			(
				assert_float(at.distance_to(here) - at.distance_to(there))
				. append_failure_message("%s | %s: the plane is not between them" % [id, other])
				. is_equal_approx(0.0, 0.01)
			)
			(
				assert_float(normal.normalized().dot((there - here).normalized()))
				. append_failure_message("%s | %s: the plane is not square to them" % [id, other])
				. is_greater(0.999)
			)
