# The default embed: a NEWLY PLACED part is sunk into its parent until its lowest point is
# attach_embed_m below the parent's surface, so the two interiors meet through the join. "when
# attaching an object to a sphere surface obviously its at its tangent point and theres no real
# connection. ALL added parts must by default upon placement be deep enough such that there are
# no barely touching surfaces." Measured with the validator's own interior-merge test at the
# configured hull thickness, not read off the offset.
class_name TestAttachEmbed
extends GdUnitTestSuite
const COMPACT: Array[String] = ["box_hull", "sphere_pod", "cylinder_spar"]
const DIRECTIONS: Array = [[0.0, 0.0], [0.0, 90.0], [45.0, 35.0]]

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


func _first_mfr(family: String) -> String:
	return _data.manufacturers_for(family)[0]


## A root of `parent_family` with one `child_family` part aimed (yaw, pitch) at `offset`:
## returns {depth, merges} - the deepest sole point's depth in the parent, and whether the
## validator finds the two interiors meeting at the hull thickness.
func _place(
	parent_family: String, child_family: String, yaw: float, pitch: float, offset: float
) -> Dictionary:
	var doc: ShipDoc = ShipDoc.create_new(
		parent_family, _first_mfr(parent_family), _data, _cfg.root_span_m
	)
	var part: ShipPart = ShipPart.new()
	part.parent = doc.root
	part.family = child_family
	part.manufacturer = _first_mfr(child_family)
	part.params = ShapeGen.default_params(_data, child_family, part.manufacturer)
	part.yaw = yaw
	part.pitch = pitch
	if is_nan(offset):
		part.offset = ShipAttach.default_offset(
			ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, doc.parts[doc.root]),
			ShipAttach.resolve_shapes_for_part(doc, _data, _cfg, part),
			part,
			_cfg
		)
	else:
		part.offset = offset
	var pid: String = doc.add_part(part)
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
	var parent_shape: ResolvedShape = shapes[doc.root]
	var child_shape: ResolvedShape = shapes[pid]
	var into_parent: Transform3D = (
		(xforms[doc.root] as Transform3D).affine_inverse() * (xforms[pid] as Transform3D)
	)
	var deepest: float = -INF
	for q: Vector3 in ShipAttach.sole_points(child_shape):
		deepest = maxf(deepest, -parent_shape.sdf(into_parent * q))
	var state: Dictionary = ShipValidate._solid_pair_state(
		child_shape, xforms[pid], parent_shape, xforms[doc.root], _cfg.hull_thickness_m
	)
	return {"offset": part.offset, "depth": deepest, "merges": bool(state["merges"])}


func test_flush_on_a_sphere_is_a_tangent_point() -> void:
	# The complaint, reproduced: offset 0 on a curved parent touches and nothing more.
	var flush: Dictionary = _place("sphere_pod", "box_hull", 0.0, 0.0, 0.0)
	(
		assert_bool(flush["merges"])
		. append_failure_message(
			"flush box on a sphere should not merge - depth %.3f" % [float(flush["depth"])]
		)
		. is_false()
	)


func test_default_embed_joins_every_compact_pair_in_every_direction() -> void:
	# READS THE SHIPPED DEFAULTS ON PURPOSE. `attach_embed_m` and `hull_thickness_m` are coupled -
	# ShipConfig says of the embed "keep it above twice hull_thickness_m so the two interiors meet
	# through the join" - and this is the test that holds them to it. When the wall moved to 0.20 m
	# for the mesh shell (ADR 0015) this failed on the two curved pairs, and the answer was to move
	# the embed with it rather than to pin the test to the wall it used to like.
	var target: float = _cfg.attach_embed_m
	for parent_family: String in COMPACT:
		for child_family: String in COMPACT:
			for d: Array in DIRECTIONS:
				var placed: Dictionary = _place(
					parent_family, child_family, float(d[0]), float(d[1]), NAN
				)
				var label: String = (
					"%s on %s yaw=%.0f pitch=%.0f: offset %.3f depth %.3f"
					% [child_family, parent_family, d[0], d[1], placed["offset"], placed["depth"]]
				)
				(
					assert_float(float(placed["depth"]))
					. append_failure_message(
						label + " - sole depth is off the target %.3f" % target
					)
					. is_equal_approx(target, 0.01)
				)
				(
					assert_bool(placed["merges"])
					. append_failure_message(
						label + " - interiors do not meet at the hull thickness"
					)
					. is_true()
				)


func test_embed_is_capped_at_a_fraction_of_the_part_height() -> void:
	var cfg: ShipConfig = ShipConfig.from_dict(_cfg.snapshot())
	cfg.attach_embed_max_fraction = 0.05
	var doc: ShipDoc = ShipDoc.create_new("box_hull", _first_mfr("box_hull"), _data, 5.0)
	var part: ShipPart = ShipPart.new()
	part.parent = doc.root
	part.family = "box_hull"
	part.manufacturer = _first_mfr("box_hull")
	part.params = ShapeGen.default_params(_data, "box_hull", part.manufacturer)
	var child: ResolvedShape = ShipAttach.resolve_shapes_for_part(doc, _data, cfg, part)
	var offset: float = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, doc.parts[doc.root]), child, part, cfg
	)
	var cap: float = 0.05 * child.local_aabb().size.y
	var height: float = child.local_aabb().size.y
	(
		assert_float(-offset)
		. append_failure_message(
			"a 5%% cap on a %.2f m part should sink it %.3f, got %.3f" % [height, cap, -offset]
		)
		. is_equal_approx(cap, 0.01)
	)


func test_a_part_that_never_touches_stays_flush() -> void:
	# A ring around a spar's cap: its tube overhangs the cap entirely, so nothing ever touches
	# and the part is left where the attach model put it.
	var placed: Dictionary = _place("cylinder_spar", "torus_ring", 0.0, 90.0, NAN)
	assert_float(float(placed["offset"])).is_equal(0.0)


func test_room_on_a_template_tube_reaches_the_target() -> void:
	# A template tunnel is a cylinder scaled unevenly, whose SDF reads short of the truth; the
	# embed must measure the real depth, or every template room sits shallow.
	var hall: String = "cylinder_spar"
	var open_scale: Vector3 = ShipTemplates._tube_scale(
		_data, hall, _first_mfr(hall), _cfg.tunnel_bore_m, _cfg.tunnel_length_m
	)
	var hall_shape: ResolvedShape = ShipTemplates._resolved(
		_data, hall, _first_mfr(hall), open_scale
	)
	(
		assert_bool(hall_shape.scale.x != hall_shape.scale.y)
		. append_failure_message(
			"the open tube should be scaled unevenly, got %s" % hall_shape.scale
		)
		. is_true()
	)
	var room_scale: Vector3 = ShipTemplates._uniform_span(
		_data, "box_hull", _first_mfr("box_hull"), _cfg.room_span_m
	)
	var room_shape: ResolvedShape = ShipTemplates._resolved(
		_data, "box_hull", _first_mfr("box_hull"), room_scale
	)
	var probe: ShipPart = ShipPart.new()
	var straight: Vector2 = ShipAttach.angles_from_direction(Vector3.UP)
	probe.yaw = straight.x
	probe.pitch = straight.y
	var offset: float = ShipAttach.default_offset(hall_shape, room_shape, probe, _cfg)
	(
		assert_float(-offset)
		. append_failure_message(
			"room on the tube's cap should sink %.3f, got %.3f" % [_cfg.attach_embed_m, -offset]
		)
		. is_equal_approx(_cfg.attach_embed_m, 0.01)
	)


func test_every_template_joint_merges() -> void:
	for tid: String in ShipTemplates.ids(_data):
		var doc: ShipDoc = ShipTemplates.build(_data, _cfg, tid, _linked())
		assert_object(doc).append_failure_message("template %s did not build" % tid).is_not_null()
		if doc == null:
			continue
		for issue: Dictionary in ShipValidate.validate(doc, _data, _cfg):
			(
				assert_str(str(issue["code"]))
				. append_failure_message("template %s: %s" % [tid, issue["message"]])
				. is_not_equal(ShipValidate.CODE_JOINT_NOT_OVERLAPPING)
			)
