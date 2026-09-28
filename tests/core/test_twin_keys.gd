# THE SHAPE MAP AND THE TRANSFORM MAP MUST AGREE ABOUT TWIN IDS.
#
# ADR 0043 widened `ShipDoc.symmetry_plane` from a letter to a SET and taught the transform pass
# and the seam pass to key a twin `id~mx` / `id~my` / `id~mxy`. `ShipAttach.resolve_shapes` was
# missed and went on aliasing the bare `id~m` - and every consumer pairs the two maps by key and
# skips anything present in only one, so on a two-plane ship not one twin mesh was ever built.
#
# The author saw it exactly: "mirroring works across 1 axis until actual clicked placement, when
# the mirror part dissapears" - the ghost's twin is computed from `planes_of()` and needs no shape
# lookup, so it drew a twin the commit could not.
#
# `tests/core/test_symmetry.gd` asserted the transform pass's keys and nothing asserted that the
# shape pass keyed the same set. That is the hole this closes.
class_name TestTwinKeys
extends GdUnitTestSuite

var _data: ShipData
var _cfg: ShipConfig


func before() -> void:
	_data = ShipData.new()
	assert_bool(_data.load_all()).is_true()
	_cfg = ShipConfig.defaults()


## A two-part ship whose child is off every plane, so it twins across all of them.
func _doc(planes: String) -> ShipDoc:
	var doc: ShipDoc = ShipDoc.create_new(_data.family_ids()[0], "", _data, 4.0)
	doc.symmetry_plane = planes
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.kind = ShipPart.KIND_PRIMITIVE
	child.family = _data.family_ids()[0]
	child.yaw = 35.0
	child.pitch = 20.0
	doc.add_part(child)
	return doc


func test_every_twin_transform_has_a_shape() -> void:
	for planes: String in ["x", "xy", "xyz", "yz", "z"]:
		var doc: ShipDoc = _doc(planes)
		var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
		var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
		var twins: int = 0
		for key: String in xforms:
			if not ShipSymmetry.is_twin_id(key):
				continue
			twins += 1
			(
				assert_bool(shapes.has(key))
				. append_failure_message(
					(
						"planes '%s': %s has a transform and NO shape, so no mesh is ever built"
						% [planes, key]
					)
				)
				. is_true()
			)
		(
			assert_int(twins)
			. append_failure_message("planes '%s' produced no twins at all to check" % planes)
			. is_greater(0)
		)


## The count is the point: 2^n - 1 twins per mirrored part, so two planes is three and not one.
func test_a_two_plane_ship_makes_three_twins_per_part() -> void:
	var doc: ShipDoc = _doc("xy")
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	var per_source: Dictionary = {}
	for key: String in xforms:
		if ShipSymmetry.is_twin_id(key):
			var src: String = ShipSymmetry.source_of_twin(key)
			per_source[src] = int(per_source.get(src, 0)) + 1
	assert_int(per_source.size()).is_greater(0)
	for src: String in per_source:
		(
			assert_int(int(per_source[src]))
			. append_failure_message("%s should mirror across x, y and xy" % src)
			. is_equal(3)
		)


## A ONE-PLANE SHIP KEYS EXACTLY AS IT ALWAYS HAS - the bare `~m`, no axis suffix. This is what
## makes the fix free: every ship anyone has ever saved uses one plane by default.
func test_one_plane_still_uses_the_bare_id() -> void:
	var doc: ShipDoc = _doc("x")
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	for key: String in shapes:
		if ShipSymmetry.is_twin_id(key):
			(
				assert_str(key)
				. append_failure_message("a one-plane doc must not gain axis-suffixed keys")
				. is_equal(ShipSymmetry.twin_id(ShipSymmetry.source_of_twin(key)))
			)


func test_possible_twin_ids_matches_the_plane_count() -> void:
	assert_int(ShipSymmetry.possible_twin_ids(_doc(""), "p_0001").size()).is_equal(0)
	assert_int(ShipSymmetry.possible_twin_ids(_doc("x"), "p_0001").size()).is_equal(1)
	assert_int(ShipSymmetry.possible_twin_ids(_doc("xy"), "p_0001").size()).is_equal(3)
	assert_int(ShipSymmetry.possible_twin_ids(_doc("xyz"), "p_0001").size()).is_equal(7)


## For DESTRUCTION: turning a plane off has to remove the visuals its twins left behind, and by
## then the document no longer names the planes they were made under.
func test_all_twin_ids_covers_every_subset() -> void:
	var ids: PackedStringArray = ShipSymmetry.all_twin_ids("p_0001")
	assert_int(ids.size()).is_equal(8)
	assert_bool(ids.has(ShipSymmetry.twin_id("p_0001"))).is_true()
	for axes: String in ["x", "y", "z", "xy", "xz", "yz", "xyz"]:
		(
			assert_bool(ids.has(ShipSymmetry.twin_id("p_0001", axes)))
			. append_failure_message("a ~m%s visual could be left behind" % axes)
			. is_true()
		)
