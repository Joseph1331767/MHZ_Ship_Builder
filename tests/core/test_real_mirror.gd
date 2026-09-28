# MIRRORING PLACES REAL PARTS.
#
# "if it were me id just place 2 parts and mirror their placement, rather then have 1 part"
# (2026-09-27). Every copy is an ordinary part with no link back, so it can be selected, made
# unique, linked, or merged into a composite room - which is what three SHIFT+F notes asked for.
class_name TestRealMirror
extends GdUnitTestSuite

var _data: ShipData
var _cfg: ShipConfig


func before() -> void:
	_data = ShipData.new()
	assert_bool(_data.load_all()).is_true()
	_cfg = ShipConfig.defaults()


func _doc(planes: String) -> ShipDoc:
	var doc: ShipDoc = ShipDoc.create_new(_data.family_ids()[0], "", _data, 4.0)
	doc.symmetry_plane = planes
	return doc


func _child(doc: ShipDoc, yaw: float, pitch: float) -> String:
	var part: ShipPart = ShipPart.new()
	part.parent = doc.root
	part.kind = ShipPart.KIND_PRIMITIVE
	part.family = _data.family_ids()[0]
	part.display_name = "POD"
	part.yaw = yaw
	part.pitch = pitch
	return doc.add_part(part)


## 2^n - 1 copies for n planes, and every one of them a REAL part in doc.parts.
func test_one_real_part_per_reflection() -> void:
	for planes: String in ["x", "xy", "xyz"]:
		var doc: ShipDoc = _doc(planes)
		var pid: String = _child(doc, 40.0, 20.0)
		var before: int = doc.parts.size()
		var made: PackedStringArray = ShipMirror.place_reflections(doc, _data, _cfg, pid)
		var want: int = (1 << planes.length()) - 1
		(
			assert_int(made.size())
			. append_failure_message("planes '%s' should lay %d copies" % [planes, want])
			. is_equal(want)
		)
		assert_int(doc.parts.size()).is_equal(before + want)
		for id: String in made:
			(
				assert_bool(doc.parts.has(id))
				. append_failure_message("%s is not a real part" % id)
				. is_true()
			)


## NOTHING IS MARKED A DERIVATIVE, so nothing regenerates it and nothing refuses to select it.
func test_a_copy_is_an_ordinary_part() -> void:
	var doc: ShipDoc = _doc("x")
	var pid: String = _child(doc, 40.0, 20.0)
	var made: PackedStringArray = ShipMirror.place_reflections(doc, _data, _cfg, pid)
	var copy: ShipPart = doc.parts[made[0]]
	assert_bool(copy.is_mirror()).is_false()
	assert_str(copy.mirror_source).is_empty()
	assert_str(copy.parent).is_equal(doc.parts[pid].parent)
	assert_str(copy.family).is_equal(doc.parts[pid].family)


## AND NO DERIVED TWIN STACKS ON TOP. Both the source and its copies are asymmetric, or a
## mirrored placement would put a real sibling AND a solve-time twin in the same place.
func test_the_solve_adds_no_twin_on_top() -> void:
	var doc: ShipDoc = _doc("xy")
	var pid: String = _child(doc, 40.0, 20.0)
	ShipMirror.place_reflections(doc, _data, _cfg, pid)
	assert_bool((doc.parts[pid] as ShipPart).asymmetric).is_true()
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	for key: String in xforms:
		(
			assert_bool(ShipSymmetry.is_twin_id(key))
			. append_failure_message("%s is a derived twin standing on a real copy" % key)
			. is_false()
		)


## THE COPY LANDS WHERE THE REFLECTION PUTS IT. Measured on the resolved transform, not on the
## angles, because the angles are the thing under test.
func test_a_copy_stands_at_the_reflection() -> void:
	var doc: ShipDoc = _doc("x")
	var pid: String = _child(doc, 40.0, 20.0)
	var before: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	var source_at: Vector3 = (before[pid] as Transform3D).origin
	var made: PackedStringArray = ShipMirror.place_reflections(doc, _data, _cfg, pid)
	var after: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	var copy_at: Vector3 = (after[made[0]] as Transform3D).origin
	(
		assert_float(copy_at.x)
		. append_failure_message(
			"the x mirror must cross the plane: %s vs %s" % [source_at, copy_at]
		)
		. is_equal_approx(-source_at.x, 0.01)
	)
	assert_float(copy_at.y).is_equal_approx(source_at.y, 0.01)
	assert_float(copy_at.z).is_equal_approx(source_at.z, 0.01)


## A part ON the plane has no other side to stand on, so nothing is laid.
func test_a_part_on_the_plane_lays_nothing() -> void:
	var doc: ShipDoc = _doc("x")
	# yaw 0 points straight down +Z, so x stays 0 and the x reflection is the part itself.
	var pid: String = _child(doc, 0.0, 0.0)
	assert_int(ShipMirror.place_reflections(doc, _data, _cfg, pid).size()).is_equal(0)


## Reflecting a direction is exact, whatever the angles - the inverse pair it is built on says so.
func test_the_placement_reflection_is_exact() -> void:
	for yaw: float in [0.0, 35.0, 90.0, 150.0, -70.0]:
		for pitch: float in [0.0, 25.0, -40.0]:
			var m: Dictionary = ShipMirror.mirrored_placement(yaw, pitch, Vector3.ZERO, "x")
			var want: Vector3 = ShipAttach.direction_from_angles(yaw, pitch)
			want.x = -want.x
			var got: Vector3 = ShipAttach.direction_from_angles(float(m["yaw"]), float(m["pitch"]))
			(
				assert_float(got.distance_to(want))
				. append_failure_message(
					"yaw %s pitch %s reflected to %s, want %s" % [yaw, pitch, got, want]
				)
				. is_less(0.001)
			)


## An even number of reflections composes back to a rotation, so the spin comes home.
func test_the_spin_reverses_once_per_reflection() -> void:
	var spin: Vector3 = Vector3(0.0, 0.0, 30.0)
	(
		assert_float(float(ShipMirror.mirrored_placement(40.0, 0.0, spin, "x")["rot"].z))
		. is_equal_approx(-30.0, 0.001)
	)
	(
		assert_float(float(ShipMirror.mirrored_placement(40.0, 0.0, spin, "xy")["rot"].z))
		. is_equal_approx(30.0, 0.001)
	)
	(
		assert_float(float(ShipMirror.mirrored_placement(40.0, 0.0, spin, "xyz")["rot"].z))
		. is_equal_approx(-30.0, 0.001)
	)
