# THE BEACON (ADR 0033): the ship's build centre is the origin, every class is laid out around it,
# and the root - or any part floating free - is anchored to it by its own `absolute` transform
# rather than pinned to identity. "the proper way would be to use a beacon or reference node thats
# invisible but still there where things can grow away from that" (2026-09-21).
class_name TestBeacon
extends GdUnitTestSuite

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


## The centre of a doc's core: its root module and whatever is expanded under it.
func _core_centre(doc: ShipDoc) -> Vector3:
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	var centre: Vector3 = Vector3.ZERO
	var count: int = 0
	for key: Variant in xforms.keys():
		var id: String = str(key)
		if ShipSymmetry.is_twin_id(id):
			continue
		if id != doc.root and not id.begins_with(doc.root + "/"):
			continue
		centre += (xforms[id] as Transform3D).origin
		count += 1
	return centre / float(maxi(count, 1))


## Every class is built around the beacon, whatever its arrangement holds at the middle: a carbon's
## six protons ring an empty centre, helium's pair straddles it, neon fills a cube.
func test_every_class_is_built_around_the_beacon() -> void:
	for element: String in ["carbon", "helium", "neon", "hydrogen"]:
		var doc: ShipDoc = ShipTemplates.build(
			_data, _cfg, element, {ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"}
		)
		assert_object(doc).append_failure_message(element).is_not_null()
		(
			assert_float(_core_centre(doc).length())
			. append_failure_message("%s: its core is not on the beacon" % element)
			. is_less(0.01)
		)


## A single-module ship lays that module over the beacon - "even if a module lays simply over it
## with no offset" (2026-09-21).
func test_a_new_ship_lays_its_one_module_over_the_beacon() -> void:
	var family: String = _data.family_ids()[0]
	var doc: ShipDoc = ShipDoc.create_new(family, _data.manufacturers_for(family)[0], _data, 6.0)
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	assert_vector((xforms[doc.root] as Transform3D).origin).is_equal_approx(
		Vector3.ZERO, Vector3.ONE * 1.0e-6
	)


## The root is placed by its anchor, not pinned to the origin, and the anchor survives the file.
func test_the_root_is_placed_by_its_anchor() -> void:
	var family: String = _data.family_ids()[0]
	var doc: ShipDoc = ShipDoc.create_new(family, _data.manufacturers_for(family)[0], _data, 6.0)
	var anchored: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.5, -2.0, 0.25))
	(doc.parts[doc.root] as ShipPart).absolute = anchored
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	assert_vector((xforms[doc.root] as Transform3D).origin).is_equal_approx(
		anchored.origin, Vector3.ONE * 1.0e-6
	)
	var back: ShipDoc = ShipDoc.from_dict(doc.to_dict())
	assert_vector((back.parts[back.root] as ShipPart).absolute.origin).is_equal_approx(
		anchored.origin, Vector3.ONE * 1.0e-6
	)


## F9, at last: a part floating free of any parent keeps the position it was given, instead of
## being traced onto a parent that is not there.
func test_a_floating_part_keeps_where_it_was_put() -> void:
	var family: String = _data.family_ids()[0]
	var doc: ShipDoc = ShipDoc.create_new(family, _data.manufacturers_for(family)[0], _data, 6.0)
	var floater: ShipPart = ShipPart.new()
	floater.kind = ShipPart.KIND_PRIMITIVE
	floater.family = family
	floater.manufacturer = (doc.parts[doc.root] as ShipPart).manufacturer
	floater.params = ShapeGen.default_params(_data, family, floater.manufacturer)
	floater.absolute = Transform3D(Basis.IDENTITY, Vector3(9.0, 3.0, -4.0))
	var id: String = doc.add_part(floater)
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	(
		assert_vector((xforms[id] as Transform3D).origin)
		. append_failure_message("a floating part did not keep its place")
		. is_equal_approx(Vector3(9.0, 3.0, -4.0), Vector3.ONE * 1.0e-6)
	)


## A class whose nucleus becomes the ship's root component stays where it is, and so does the same
## ship dissolved again: the anchor travels with whatever becomes the root.
func test_the_anchor_travels_with_the_root() -> void:
	var doc: ShipDoc = ShipTemplates.build(
		_data, _cfg, "carbon", {ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"}
	)
	var before: Vector3 = _core_centre(doc)
	assert_float(before.length()).is_less(0.01)
	var ids: PackedStringArray = ShipComponents.dissolve(doc, doc.root)
	assert_int(ids.size()).is_equal(6)
	# Dissolved, the six bodies are plain parts again, so the core is measured over them.
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	var after: Vector3 = Vector3.ZERO
	for id: String in ids:
		after += (xforms[id] as Transform3D).origin
	(
		assert_float((after / float(ids.size())).length())
		. append_failure_message("dissolving the nucleus moved the ship off the beacon")
		. is_less(0.01)
	)


## THE NUCLEUS RINGS THE BEACON (ADR 0034): every body stands in its arrangement's own slot at one
## radius, so a class comes out symmetric about the centre instead of leaning off its first module.
## On a CUBE family this is what the author was looking at - "the center proton was not centered top
## and bottom .. when i exploded it it did not yeild parts that were expected, which in this exact
## case would be 6 little square slabs" (2026-09-21).
func test_the_nucleus_stands_in_its_arrangements_slots() -> void:
	for family: String in ["box_hull", "sphere_pod", "cylinder_spar"]:
		var doc: ShipDoc = ShipTemplates.build(
			_data, _cfg, "carbon", {ShipTemplates.OPT_ROOM_FAMILY: family}
		)
		var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
		var places: Array[Vector3] = []
		for key: Variant in xforms.keys():
			var id: String = str(key)
			if ShipSymmetry.is_twin_id(id):
				continue
			if id == doc.root or id.begins_with(doc.root + "/"):
				places.append((xforms[id] as Transform3D).origin)
		assert_int(places.size()).append_failure_message(family).is_equal(6)
		# One radius, and an octahedron: each body on an axis, each with its opposite number.
		var radius: float = places[0].length()
		assert_float(radius).append_failure_message(family).is_greater(0.1)
		for at: Vector3 in places:
			(
				assert_float(at.length())
				. append_failure_message("%s: %s is not on the ring" % [family, str(at)])
				. is_equal_approx(radius, radius * 0.01)
			)
			var opposite: bool = false
			for other: Vector3 in places:
				opposite = opposite or (at + other).length() < radius * 0.01
			(
				assert_bool(opposite)
				. append_failure_message("%s: %s has nothing across from it" % [family, str(at)])
				. is_true()
			)


## And the clump is still ONE ROOM, on every family: the bodies stand side by side with nothing to
## hang a seam off, so their links come from the joints the template writes between them (ADR 0034).
func test_the_nucleus_is_one_room_on_every_family() -> void:
	for family: String in ["box_hull", "sphere_pod", "cylinder_spar"]:
		for element: String in ["helium", "carbon", "neon"]:
			var doc: ShipDoc = ShipTemplates.build(
				_data, _cfg, element, {ShipTemplates.OPT_ROOM_FAMILY: family}
			)
			var biggest: int = 0
			for members: PackedStringArray in ShipMeshBake.plan(doc, _data, _cfg)["rooms"]:
				biggest = maxi(biggest, members.size())
			(
				assert_int(biggest)
				. append_failure_message("%s %s: the nucleus is not one room" % [family, element])
				. is_equal(ShipTemplates.nucleus_count(ShipTemplates.entry(_data, element)))
			)
