# Mirror: live-linked reflection across the ship root's X/Y/Z plane. Reflection must negate
# exactly the mirrored component and flip winding (negative basis determinant); a broken
# link must materialize independent parts with fresh ids; a mirror of a mirror is rejected.
class_name TestMirror
extends GdUnitTestSuite

const TOL_V3: Vector3 = Vector3(0.0001, 0.0001, 0.0001)

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


func _add_child(doc: ShipDoc, parent_id: String) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = parent_id
	part.kind = "primitive"
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = 20.0
	part.pitch = 10.0
	part.rot = Vector3.ZERO
	part.offset = 0.0
	part.scale = Vector3.ONE
	part.blend = 0.0
	part.mirror_source = ""
	part.mirror_plane = ""
	part.display_name = "part " + part.id
	@warning_ignore("return_value_discarded")
	doc.add_part(part)
	return part


func test_plane_normal_returns_unit_axis() -> void:
	assert_vector(ShipMirror.plane_normal("x")).is_equal_approx(Vector3(1.0, 0.0, 0.0), TOL_V3)
	assert_vector(ShipMirror.plane_normal("y")).is_equal_approx(Vector3(0.0, 1.0, 0.0), TOL_V3)
	assert_vector(ShipMirror.plane_normal("z")).is_equal_approx(Vector3(0.0, 0.0, 1.0), TOL_V3)


func test_reflect_negates_only_the_mirrored_component() -> void:
	var origin: Vector3 = Vector3(2.0, 3.0, 4.0)
	var t: Transform3D = Transform3D(Basis.IDENTITY, origin)
	var rx: Transform3D = ShipMirror.reflect(t, "x")
	assert_vector(rx.origin).is_equal_approx(Vector3(-2.0, 3.0, 4.0), TOL_V3)
	var ry: Transform3D = ShipMirror.reflect(t, "y")
	assert_vector(ry.origin).is_equal_approx(Vector3(2.0, -3.0, 4.0), TOL_V3)
	var rz: Transform3D = ShipMirror.reflect(t, "z")
	assert_vector(rz.origin).is_equal_approx(Vector3(2.0, 3.0, -4.0), TOL_V3)


func test_reflect_flips_winding_determinant() -> void:
	var t: Transform3D = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var planes: Array[String] = ["x", "y", "z"]
	for plane: String in planes:
		var reflected: Transform3D = ShipMirror.reflect(t, plane)
		assert_float(reflected.basis.determinant()).append_failure_message(
			"reflecting across plane '%s' should flip winding (negative determinant)" % plane
		).is_less(0.0)


func test_mirror_subtree_creates_linked_derivatives() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var created: PackedStringArray = ShipMirror.mirror_subtree(doc, child.id, "x")
	assert_array(created).is_not_empty()
	var mirror_id: String = created[0]
	assert_bool(doc.parts.has(mirror_id)).is_true()
	var mirror_part: ShipPart = doc.parts[mirror_id] as ShipPart
	assert_bool(mirror_part.is_mirror()).append_failure_message(
		"part created by mirror_subtree() does not report is_mirror() == true"
	).is_true()
	assert_array(ShipMirror.derivative_ids(doc)).contains(mirror_id)


func test_break_link_materializes_independent_parts_with_fresh_ids() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var created: PackedStringArray = ShipMirror.mirror_subtree(doc, child.id, "x")
	var mirror_id: String = created[0]

	var broken: PackedStringArray = ShipMirror.break_link(doc, mirror_id)
	assert_array(broken).append_failure_message(
		"break_link() produced no new parts"
	).is_not_empty()
	assert_array(broken).append_failure_message(
		"break_link() must materialize fresh ids, not reuse the derivative's own id"
	).not_contains(mirror_id)
	for new_id: String in broken:
		assert_bool(doc.parts.has(new_id)).is_true()
		var new_part: ShipPart = doc.parts[new_id] as ShipPart
		assert_bool(new_part.is_mirror()).append_failure_message(
			"part '%s' produced by break_link() is still reported as a mirror" % new_id
		).is_false()


func test_mirror_of_mirror_is_rejected() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var child: ShipPart = _add_child(doc, doc.root)
	var first: PackedStringArray = ShipMirror.mirror_subtree(doc, child.id, "x")
	var mirror_id: String = first[0]
	var second: PackedStringArray = ShipMirror.mirror_subtree(doc, mirror_id, "y")
	assert_array(second).append_failure_message(
		"mirror_subtree() must refuse to mirror an existing mirror derivative, got: %s" %
		[str(second)]
	).is_empty()
