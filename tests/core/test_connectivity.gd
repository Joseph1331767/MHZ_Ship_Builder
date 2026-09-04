# HullBake.connectivity() — API_CONTRACT_SPORE section 7. Report-only: Spore's vehicle/UFO editor
# requires no contiguity at all (bodies "require no base"), so this class never asserts a refusal
# for a disconnected ship -- only that the reported island structure is correct and stable.
#
# All parts here are FLOATING (parent == "") so their ship-space position is under direct test
# control. Note for anyone extending this file: ShipPart.absolute is documented as the mechanism
# that positions a floating part in ship space, but ShipAttach never reads it anywhere -- a
# parentless, non-root part is placed exactly like an attached part whose parent is treated as a
# point at the ship origin, i.e. by yaw/pitch/offset (see ShipAttach.local_transform()'s
# `parent_shape == null` branch). Positions below are therefore built with yaw = 90 (local +X) and
# an offset solved against the sphere's own mount_inset(), not with `absolute`.
#
# The probed family is normalised to a SPHERE (like test_bake.gd / test_metrics.gd do), and every
# position is expressed as a MULTIPLE OF THE ACTUAL RESULTING RADIUS (measured after resolving,
# never assumed) rather than an absolute metre count: ResolvedShape.bound_radius is a conservative
# AABB-corner bound (radius * sqrt(3) for a bare sphere, not the radius itself), so normalising
# against a target bound_radius and then assuming the result lands at some other target metre
# figure would be silently wrong. Reading the actual radius off the resolved shape and scaling
# every position from THAT makes the overlap/gap arithmetic exact regardless of which family the
# data pack happens to ship.
class_name TestConnectivity
extends GdUnitTestSuite

## Target bound_radius used only to pick a reasonably-sized scale -- not the actual sphere radius,
## see the file header.
const TARGET_BOUND_RADIUS: float = 3.0

var _data: ShipData
var _sphere_family: String
var _sphere_mfr: String
var _sphere_params: Dictionary
var _sphere_scale: Vector3
var _sphere_shape: ResolvedShape
var _radius: float = 0.0


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


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	assert_bool(ok).append_failure_message(
		"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
	).is_true()

	var found_sphere: bool = false
	for family_id: String in _data.family_ids():
		if found_sphere:
			break
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var mfr_id: String = mfrs[0]
		var defaults: Dictionary = ShapeGen.default_params(_data, family_id, mfr_id)
		var minimal: Dictionary = ShapeGen.clamp_params(_data, family_id, mfr_id, _zeroed(defaults))
		var probe: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr_id, minimal, Vector3.ONE)
		if probe.base != ResolvedShape.Base.SPHERE:
			continue
		var natural: float = maxf(probe.bound_radius, 0.001)
		var factor: float = TARGET_BOUND_RADIUS / natural
		_sphere_family = family_id
		_sphere_mfr = mfr_id
		_sphere_params = minimal
		_sphere_scale = Vector3(factor, factor, factor)
		_sphere_shape = ShapeGen.resolve(_data, family_id, mfr_id, minimal, _sphere_scale)
		# The real radius, measured -- see the file header for why this must not be assumed.
		_radius = _sphere_shape.size.x * _sphere_scale.x
		found_sphere = true

	assert_bool(found_sphere).append_failure_message(
		"no family in res://data resolves to a SPHERE base primitive with zeroed params -- " +
		"cannot build the exact-radius spheres this connectivity test relies on"
	).is_true()
	assert_float(_radius).is_greater(0.0)


func _sphere_root_doc() -> ShipDoc:
	var doc: ShipDoc = ShipDoc.create_new(_sphere_family, _sphere_mfr, _data)
	var root_part: ShipPart = doc.parts[doc.root] as ShipPart
	root_part.params = _sphere_params
	root_part.scale = _sphere_scale
	return doc


## Adds a floating (parentless) sphere centred at ship-space (center_x, 0, 0) and returns its id.
func _floating_sphere(doc: ShipDoc, center_x: float) -> String:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = ""
	part.kind = ShipPart.KIND_PRIMITIVE
	part.family = _sphere_family
	part.manufacturer = _sphere_mfr
	part.params = _sphere_params
	part.yaw = 90.0
	part.pitch = 0.0
	part.rot = Vector3.ZERO
	part.offset = center_x - _sphere_shape.mount_inset()
	part.scale = _sphere_scale
	part.blend = 0.0
	part.display_name = "floating " + part.id
	@warning_ignore("return_value_discarded")
	doc.add_part(part)
	return part.id


## Symmetry OFF for the island tests.
##
## Not a workaround - a scope fence. With symmetry on, every off-plane part also contributes a
## mirrored twin, so a fixture built to have exactly two islands has four, and the test would be
## asserting about mirroring rather than about connectivity. Twin generation has its own coverage
## in test_attach.gd.
func test_three_overlapping_plus_one_far_gives_two_islands_largest_holds_three() -> void:
	var doc: ShipDoc = _sphere_root_doc()
	doc.symmetry_plane = ""
	var root_id: String = doc.root
	# Centre distances vs. 2*_radius (the sum of two equal radii): root-b = 1.5R (overlap depth
	# 0.5R), b-c = 1.5R (overlap depth 0.5R), root-c = 3.0R (clear gap 1.0R, connected only
	# transitively through b), c-d = 4.0R (clear gap 2.0R, isolated).
	var b_id: String = _floating_sphere(doc, 1.5 * _radius)
	var c_id: String = _floating_sphere(doc, 3.0 * _radius)
	var d_id: String = _floating_sphere(doc, 7.0 * _radius)
	var cfg: ShipConfig = ShipConfig.defaults()

	var result: Dictionary = HullBake.connectivity(doc, _data, cfg)
	var islands: Array[PackedStringArray] = result["islands"]
	var largest: PackedStringArray = result["largest"]

	assert_int(islands.size()).append_failure_message(
		"expected exactly 2 islands (root+b+c connected, d isolated), got %d: %s"
		% [islands.size(), islands]
	).is_equal(2)
	assert_int(largest.size()).append_failure_message(
		"largest island should hold exactly the three overlapping parts, got %s" % [largest]
	).is_equal(3)
	assert_array(largest).contains(root_id, b_id, c_id)
	assert_array(largest).not_contains(d_id)

	var found_singleton: bool = false
	for island: PackedStringArray in islands:
		if island.has(d_id):
			assert_int(island.size()).append_failure_message(
				"the far-away part's island should contain only itself, got %s" % [island]
			).is_equal(1)
			found_singleton = true
	assert_bool(found_singleton).append_failure_message(
		"no island in %s contains the far-away part '%s'" % [islands, d_id]
	).is_true()


## Symmetry off - see the note on the two-island test above.
func test_fully_connected_ship_gives_one_island() -> void:
	var doc: ShipDoc = _sphere_root_doc()
	doc.symmetry_plane = ""
	var root_id: String = doc.root
	var b_id: String = _floating_sphere(doc, 1.5 * _radius)
	var c_id: String = _floating_sphere(doc, 3.0 * _radius)
	var cfg: ShipConfig = ShipConfig.defaults()

	var result: Dictionary = HullBake.connectivity(doc, _data, cfg)
	var islands: Array[PackedStringArray] = result["islands"]
	assert_int(islands.size()).append_failure_message(
		"a ship connected end-to-end (root-b-c) should report a single island, got %d: %s"
		% [islands.size(), islands]
	).is_equal(1)

	var only: PackedStringArray = islands[0]
	assert_int(only.size()).is_equal(3)
	assert_array(only).contains(root_id, b_id, c_id)

	var largest: PackedStringArray = result["largest"]
	assert_int(largest.size()).is_equal(3)
	assert_array(largest).contains(root_id, b_id, c_id)


func test_island_order_is_deterministic_across_repeated_calls() -> void:
	var doc: ShipDoc = _sphere_root_doc()
	# Symmetry off - see the note on the two-island test above.
	doc.symmetry_plane = ""
	@warning_ignore("return_value_discarded")
	_floating_sphere(doc, 1.5 * _radius)
	@warning_ignore("return_value_discarded")
	_floating_sphere(doc, 3.0 * _radius)
	@warning_ignore("return_value_discarded")
	_floating_sphere(doc, 7.0 * _radius)
	var cfg: ShipConfig = ShipConfig.defaults()

	var first: Dictionary = HullBake.connectivity(doc, _data, cfg)
	var second: Dictionary = HullBake.connectivity(doc, _data, cfg)
	# var_to_str() serialises the full nested Array[PackedStringArray] structure in order, so an
	# equal string covers both island membership and island/part ordering in one comparison.
	assert_str(var_to_str(second)).append_failure_message(
		"HullBake.connectivity() returned a different result on a second call over the same doc"
	).is_equal(var_to_str(first))


func test_connectivity_never_blocks_a_disconnected_ship() -> void:
	# Report-only, never a gate (API_CONTRACT_SPORE section 7 / SPEC section 5: bodies "require
	# no base"): a legal, if disconnected, document must still pass the ordinary save gate. This
	# test deliberately does NOT assert anything about connectivity()'s own return value refusing
	# -- it has no such thing to assert -- only that ShipGate is indifferent to island count.
	var doc: ShipDoc = _sphere_root_doc()
	# Symmetry off - see the note on the two-island test above.
	doc.symmetry_plane = ""
	@warning_ignore("return_value_discarded")
	_floating_sphere(doc, 1.5 * _radius)
	@warning_ignore("return_value_discarded")
	_floating_sphere(doc, 7.0 * _radius)
	var cfg: ShipConfig = ShipConfig.defaults()

	var connectivity_result: Dictionary = HullBake.connectivity(doc, _data, cfg)
	var islands: Array[PackedStringArray] = connectivity_result["islands"]
	assert_int(islands.size()).append_failure_message(
		"this doc is deliberately built as 2 islands (root+1 connected, 1 far away), got %d"
		% islands.size()
	).is_equal(2)

	var save_result: Dictionary = ShipGate.check_save(doc, _data, cfg)
	assert_bool(bool(save_result["ok"])).append_failure_message(
		(
			"a disconnected ship must not be refused for being disconnected -- connectivity " +
			"never blocks a save, got: %s"
		) % [save_result]
	).is_true()
