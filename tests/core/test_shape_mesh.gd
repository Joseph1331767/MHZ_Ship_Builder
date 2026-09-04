# ShapeMesh and ShipMeshBake — the exact bake. "we want exact mesh operations as our current
# method is not exact."
#
# The assertion that matters most is the agreement one. The SDF is still the truth layer for
# attach, snapping, joints and metrics, so a mesh that drifts from it is not merely ugly, it is a
# second and disagreeing definition of where the hull is. ShapeMesh earns the word "exact" by
# INVERTING the very domain warps ResolvedShape.sdf applies, and the way to check that is to feed
# every vertex it produces back into the field and demand a zero.
class_name TestShapeMesh
extends GdUnitTestSuite

## How far a baked vertex may sit from the surface it was baked from. Tight: this is analytic
## geometry on both sides, so anything beyond float noise means a warp was inverted wrongly.
const ON_SURFACE_M: float = 1.0e-5

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


# --- the shapes themselves ----------------------------------------------------------------------


func test_a_box_tessellates_to_six_faces() -> void:
	# No resolution parameter exists to get this wrong at: a box is six faces at any size.
	var shape: ResolvedShape = _shape("box_hull", _bare("box_hull"), Vector3.ONE)
	var mesh: PolyMesh = ShapeMesh.build(shape)
	assert_int(mesh.face_count()).is_equal(6)
	assert_int(mesh.vertices.size()).is_equal(8)
	assert_int(mesh.open_edges()).is_equal(0)
	(
		assert_int(mesh.boundary_edges().size() / 2)
		. append_failure_message("a box has 12 model edges")
		. is_equal(12)
	)


func test_every_baked_vertex_lies_on_the_field() -> void:
	# The agreement test, over every family the pack ships and every warp that is a DOMAIN warp.
	# `round`, ribs and scallops are excluded on purpose - they are offset and displacement ops,
	# deferred by decision (FOLLOWUPS F22), and a part carrying one bakes sharp.
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var bare: Dictionary = _bare(family_id)
		var cases: Dictionary = {"bare": bare, "scaled": bare}
		for op: String in ["taper", "twist_deg", "skew_x", "skew_z"]:
			if bare.has(op):
				var one: Dictionary = bare.duplicate()
				one[op] = 30.0 if op == "twist_deg" else 0.4
				cases[op] = one
		for label: String in cases:
			var scale: Vector3 = Vector3(1.7, 0.6, 2.3) if label == "scaled" else Vector3.ONE
			var shape: ResolvedShape = _shape(family_id, cases[label], scale)
			var mesh: PolyMesh = ShapeMesh.build(shape)
			(
				assert_bool(mesh.is_empty())
				. append_failure_message("%s/%s tessellated to nothing" % [family_id, label])
				. is_false()
			)
			var worst: float = 0.0
			for v: Vector3 in mesh.vertices:
				worst = maxf(worst, absf(shape.sdf(v)))
			# The deferred `round` op is the whole allowance, and it is a KNOWN quantity rather
			# than slack: the field inflates by `round_r` and then multiplies the result by the
			# smallest scale component, so the mesh reads exactly that far inside. Measured on
			# cylinder_spar, whose manufacturer clamps `round` up to 0.05 however it is authored:
			# 0.050000 unscaled and 0.030000 at a 0.6 minimum scale. Anything ABOVE this budget is
			# a warp inverted wrongly, which is what the test is really watching for.
			var allowance: float = (
				absf(shape.round_r) * minf(absf(scale.x), minf(absf(scale.y), absf(scale.z)))
			)
			(
				assert_float(worst)
				. append_failure_message(
					(
						(
							"%s with %s: a baked vertex sits %.6f m off its own SDF surface, past the "
							+ "%.6f m the deferred round op accounts for"
						)
						% [family_id, label, worst, allowance]
					)
				)
				. is_less(allowance + ON_SURFACE_M)
			)


func test_every_family_bakes_a_closed_solid() -> void:
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var mesh: PolyMesh = ShapeMesh.build(_shape(family_id, _bare(family_id), Vector3.ONE))
		(
			assert_int(mesh.open_edges())
			. append_failure_message("%s did not close" % [family_id])
			. is_equal(0)
		)
		(
			assert_float(mesh.volume())
			. append_failure_message("%s has no volume" % [family_id])
			. is_greater(0.0)
		)


func test_a_twisted_box_is_triangulated_rather_than_left_non_planar() -> void:
	# Taper and shear are linear in y and carry a plane to a plane, so a box stays six faces
	# through both. Twist rotates by an angle that GROWS with y, which turns a flat side into a
	# helicoid - there is no quad that describes one, so those faces get triangulated instead of
	# being emitted as n-gons that lie about being flat.
	var params: Dictionary = _bare("box_hull")
	params["twist_deg"] = 40.0
	var mesh: PolyMesh = ShapeMesh.build(_shape("box_hull", params, Vector3.ONE))
	(
		assert_float(mesh.worst_planarity())
		. append_failure_message("a twisted box emitted a face whose corners are not coplanar")
		. is_less(1.0e-5)
	)
	assert_int(mesh.open_edges()).is_equal(0)


func test_a_sheared_box_is_still_six_faces() -> void:
	# The counterpart to the test above: shear is linear, so it must NOT cost the n-gons.
	var params: Dictionary = _bare("box_hull")
	if not params.has("skew_x"):
		return
	params["skew_x"] = 0.5
	var mesh: PolyMesh = ShapeMesh.build(_shape("box_hull", params, Vector3.ONE))
	assert_int(mesh.face_count()).is_equal(6)
	assert_float(mesh.worst_planarity()).is_less(1.0e-5)


func test_a_box_volume_survives_non_uniform_scale() -> void:
	var scale: Vector3 = Vector3(1.7, 0.6, 2.3)
	var plain: PolyMesh = ShapeMesh.build(_shape("box_hull", _bare("box_hull"), Vector3.ONE))
	var scaled: PolyMesh = ShapeMesh.build(_shape("box_hull", _bare("box_hull"), scale))
	(
		assert_float(scaled.volume())
		. append_failure_message("scale is a transform, so volume scales by its product")
		. is_equal_approx(plain.volume() * scale.x * scale.y * scale.z, 1.0e-4)
	)


# --- the bake ------------------------------------------------------------------------------------


func test_a_template_ship_bakes_every_part_closed() -> void:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	assert_object(doc).is_not_null()
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	var order: PackedStringArray = report["order"]
	assert_int(order.size()).append_failure_message("nothing was baked").is_greater(0)
	(
		assert_int((report["open_parts"] as PackedStringArray).size())
		. append_failure_message("parts came out open: %s" % [str(report["open_parts"])])
		. is_equal(0)
	)
	assert_int(int(report["tris"])).is_greater(0)
	for id: String in order:
		var solid: PolyMesh = (report["solids"] as Dictionary)[id]
		assert_bool(solid.truncated).append_failure_message("%s was truncated" % [id]).is_false()


func test_the_bake_agrees_with_the_ship_field() -> void:
	# End to end: the placement transform is applied to the mesh here and inverted inside the
	# field, so this checks the whole chain rather than the tessellator alone.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var index_of: Dictionary = {}
	for i: int in sdf.part_count():
		index_of[sdf.part_id_at(i)] = i
	var checked: int = 0
	for id: String in report["order"] as PackedStringArray:
		if not index_of.has(id):
			continue
		# UNSEAMED on purpose: bake() cuts a part back at its seams, and a flat mating face is
		# deliberately NOT on that part own primitive surface any more. What is under test here is
		# the tessellation and the placement transform, so the part is rebuilt without the seam
		# booleans - which is exactly what bake_part() gives.
		var shape_round: float = _round_of(doc, id)
		var solid: PolyMesh = ShipMeshBake.bake_part(doc, _data, _cfg, id)
		if solid == null:
			continue
		var worst: float = 0.0
		for v: Vector3 in solid.vertices:
			worst = maxf(worst, absf(sdf.sample_part(int(index_of[id]), v)))
		checked += 1
		(
			assert_float(worst)
			. append_failure_message(
				"placed part %s sits %.6f m off its own field surface" % [id, worst]
			)
			. is_less(shape_round + ON_SURFACE_M)
		)
	assert_int(checked).append_failure_message("no placed part was checked").is_greater(0)


func test_the_bake_is_deterministic() -> void:
	# Determinism is a gate (AGENTS 8b), and this walks a Dictionary to find its part order.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	var first: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	var second: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	assert_array(Array(first["order"] as PackedStringArray)).is_equal(
		Array(second["order"] as PackedStringArray)
	)
	assert_int(int(first["faces"])).is_equal(int(second["faces"]))
	for id: String in first["order"] as PackedStringArray:
		var a: PolyMesh = (first["solids"] as Dictionary)[id]
		var b: PolyMesh = (second["solids"] as Dictionary)[id]
		(
			assert_bool(a.vertices == b.vertices)
			. append_failure_message("%s baked to different vertices twice" % [id])
			. is_true()
		)


func test_baking_nothing_is_not_an_error() -> void:
	var report: Dictionary = ShipMeshBake.bake(null, _data, _cfg)
	assert_int((report["order"] as PackedStringArray).size()).is_equal(0)
	assert_int(int(report["tris"])).is_equal(0)


# --- helpers --------------------------------------------------------------------------------------


func _first_mfr(family_id: String) -> String:
	var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
	return mfrs[0] if not mfrs.is_empty() else ""


## Default params with every number zeroed, so only the base primitive and the named op are live.
func _bare(family_id: String) -> Dictionary:
	var out: Dictionary = ShapeGen.default_params(_data, family_id, _first_mfr(family_id))
	for key: String in out.keys():
		if typeof(out[key]) == TYPE_FLOAT or typeof(out[key]) == TYPE_INT:
			out[key] = 0.0
	return out


func _shape(family_id: String, params: Dictionary, scale: Vector3) -> ResolvedShape:
	var mfr: String = _first_mfr(family_id)
	return ShapeGen.resolve(
		_data, family_id, mfr, ShapeGen.clamp_params(_data, family_id, mfr, params), scale
	)


## The inflate radius a placed part carries, scaled the way the field scales it — the exact
## amount the deferred `round` op is allowed to differ by.
func _round_of(doc: ShipDoc, id: String) -> float:
	var source: String = ShipSymmetry.source_of_twin(id)
	if not doc.parts.has(source):
		return 0.0
	var part: ShipPart = doc.parts[source]
	var shape: ResolvedShape = ShapeGen.resolve(
		_data, part.family, part.manufacturer, part.params, part.scale
	)
	return (
		absf(shape.round_r) * minf(absf(part.scale.x), minf(absf(part.scale.y), absf(part.scale.z)))
	)


# --- seam styles reach the mesh (ADR 0009 through ADR 0011) --------------------------------------


func test_each_seam_style_deforms_the_meshes_differently() -> void:
	# The regression this exists for: the first exact bake ran no boolean at all, which silently
	# dropped a feature that already worked - "i right click 2 selected solids, i press the option
	# i want ... and then after i press explode and it does not show the created manifolds."
	#
	# Asked by VOLUME, because that is what tells the three styles apart without caring how the
	# mesh is triangulated: FLAT splits the overlap and hands the host a collar, PARENT dents the
	# child, CHILD sockets the host.
	var base: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	assert_object(base).is_not_null()
	var child_volume: Dictionary = {}
	var host_volume: Dictionary = {}
	for style: String in [
		ShipJoint.SEAM_FLAT, ShipJoint.SEAM_BIG_NATIVE, ShipJoint.SEAM_SMALL_NATIVE
	]:
		var doc: ShipDoc = base.duplicate_doc()
		for jid: String in doc.joints:
			(doc.joints[jid] as ShipJoint).seam_style = style
		var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
		var solids: Dictionary = report["solids"]
		(
			assert_int((report["open_parts"] as PackedStringArray).size())
			. append_failure_message(
				"style %s left parts open: %s" % [style, str(report["open_parts"])]
			)
			. is_equal(0)
		)
		child_volume[style] = (solids["p_0002"] as PolyMesh).volume()
		host_volume[style] = (solids["p_0001"] as PolyMesh).volume()

	# CHILD is the only style that takes anything out of the HOST.
	(
		assert_float(host_volume[ShipJoint.SEAM_SMALL_NATIVE])
		. append_failure_message("the child style did not socket the host")
		. is_less(float(host_volume[ShipJoint.SEAM_FLAT]) - 0.01)
	)
	# ...and FLAT and PARENT both leave the host exactly alone. RETIRED(2026-09-03d): this used to
	# assert the host GREW under FLAT, by the collar it was handed. The collar is gone - on a
	# curved host or a box corner the seam plane is a tangent, so the collar came out as a spike
	# protruding past the host, and it was the only operation in the bake that GREW a mesh, which
	# is what made a hub host to eight seams never finish.
	(
		assert_float(host_volume[ShipJoint.SEAM_FLAT])
		. append_failure_message("flat and parent must both leave the host untouched")
		. is_equal_approx(float(host_volume[ShipJoint.SEAM_BIG_NATIVE]), 1.0e-6)
	)
	# FLAT cuts the child on a PLANE; PARENT cuts it on the host's real surface. Same intent,
	# different surface, so the two must not agree.
	var flat_vs_parent: float = absf(
		float(child_volume[ShipJoint.SEAM_FLAT]) - float(child_volume[ShipJoint.SEAM_BIG_NATIVE])
	)
	(
		assert_float(flat_vs_parent)
		. append_failure_message("flat and parent cut the child identically - one of them is wrong")
		. is_greater(1.0e-3)
	)
	# Under CHILD the child keeps its whole shape at its own seam, so it is the largest of the three.
	(
		assert_float(child_volume[ShipJoint.SEAM_SMALL_NATIVE])
		. append_failure_message("the child style should not cut the child at its own seam")
		. is_greater(float(child_volume[ShipJoint.SEAM_FLAT]))
	)


func test_the_seam_style_is_read_not_baked_in() -> void:
	# Non-destructive by construction: the style lives on the joint and the mesh is derived, so
	# switching away and back has to land exactly where it started.
	var base: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	var before: float = _host_volume(base, ShipJoint.SEAM_FLAT)
	var detour: float = _host_volume(base, ShipJoint.SEAM_SMALL_NATIVE)
	var after: float = _host_volume(base, ShipJoint.SEAM_FLAT)
	assert_float(detour).append_failure_message("the detour changed nothing").is_not_equal(before)
	(
		assert_float(after)
		. append_failure_message("switching seam style and back did not restore the mesh")
		. is_equal_approx(before, 1.0e-6)
	)


func _host_volume(base: ShipDoc, style: String) -> float:
	var doc: ShipDoc = base.duplicate_doc()
	for jid: String in doc.joints:
		(doc.joints[jid] as ShipJoint).seam_style = style
	var solids: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)["solids"]
	return (solids["p_0001"] as PolyMesh).volume()


# --- the four flat styles (ADR 0012) --------------------------------------------------------------


func test_every_seam_style_bakes_closed_solids() -> void:
	# Six styles now, and the only universal promise is the one that matters: whatever the author
	# picks, every part comes out a closed solid.
	var base: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	for style: String in ShipJoint.VALID_SEAM_STYLES:
		var doc: ShipDoc = base.duplicate_doc()
		for jid: String in doc.joints:
			(doc.joints[jid] as ShipJoint).seam_style = style
		var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
		(
			assert_int((report["open_parts"] as PackedStringArray).size())
			. append_failure_message(
				"style %s left parts open: %s" % [style, str(report["open_parts"])]
			)
			. is_equal(0)
		)
		(
			assert_int(int(report["faces"]))
			. append_failure_message("%s baked nothing" % style)
			. is_greater(0)
		)


func test_in_and_out_bump_put_the_plane_in_different_places() -> void:
	# IN takes the deepest point where the two surfaces cross, OUT the outermost. On a flat host
	# face they coincide - the face IS both - so the difference is asked of the host, which OUT
	# gives a raised pad and IN does not.
	var flat_host: float = _host_volume_for("helium", ShipJoint.SEAM_SMALL_FLAT_INSERT)
	var raised: float = _host_volume_for("helium", ShipJoint.SEAM_BIG_FLAT_INSERT)
	(
		assert_float(raised)
		. append_failure_message("out-bump did not raise a pad on the host")
		. is_greater(flat_host)
	)


func test_a_flange_leaves_the_host_alone_where_a_slice_cuts_it() -> void:
	# A tube landing on a flat box face: the deepest crossing IS that face, so neither style has
	# anything of the host to remove and the two must agree. The distinction only bites on a
	# curved host, which is exactly why both exist.
	var flange: float = _host_volume_for("helium", ShipJoint.SEAM_SMALL_FLAT_INSERT)
	var slice: float = _host_volume_for("helium", ShipJoint.SEAM_SMALL_FLAT_CUTOFF)
	(
		assert_float(flange)
		. append_failure_message("on a flat host face a flange and a slice must agree")
		. is_equal_approx(slice, 1.0e-6)
	)


func test_the_child_is_cut_flush_at_the_host_surface() -> void:
	# The whole point of the rework. A tube seated into a box should come out ENDING at the box's
	# face - not short of it, and not through it.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	for jid: String in doc.joints:
		(doc.joints[jid] as ShipJoint).seam_style = ShipJoint.SEAM_SMALL_FLAT_INSERT
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	var solids: Dictionary = report["solids"]
	var hull: PolyMesh = solids["p_0001"]
	var tube: PolyMesh = solids["p_0002"]
	# No tube vertex may sit meaningfully inside the hull's box.
	var half: Vector3 = hull.aabb().size * 0.5
	var centre: Vector3 = hull.aabb().get_center()
	var worst: float = 0.0
	for v: Vector3 in tube.vertices:
		var d: Vector3 = half - (v - centre).abs()
		worst = maxf(worst, minf(d.x, minf(d.y, d.z)))
	(
		assert_float(worst)
		. append_failure_message("the tube still reaches %.4f m inside the hull" % [worst])
		. is_less(0.01)
	)


func test_a_ship_saved_before_the_rework_still_loads() -> void:
	# The names have changed twice and the behaviours never did, so EVERY id this project has
	# written must still load onto the style that carries the same behaviour today.
	var expected: Dictionary = {
		"flat": ShipJoint.SEAM_SMALL_FLAT_INSERT,
		"flat_in": ShipJoint.SEAM_SMALL_FLAT_INSERT,
		"slice_in": ShipJoint.SEAM_SMALL_FLAT_CUTOFF,
		"child": ShipJoint.SEAM_SMALL_NATIVE,
		"flat_out": ShipJoint.SEAM_BIG_FLAT_INSERT,
		"slice_out": ShipJoint.SEAM_BIG_FLAT_CUTOFF,
		"parent": ShipJoint.SEAM_BIG_NATIVE,
	}
	for legacy: String in expected:
		var joint: ShipJoint = ShipJoint.from_dict(
			"j1", {"a": "p_0001", "b": "p_0002", "seam": legacy}
		)
		(
			assert_str(joint.seam_style)
			. append_failure_message("a saved seam of '%s' no longer loads" % [legacy])
			. is_equal(expected[legacy])
		)
	var unknown: ShipJoint = ShipJoint.from_dict(
		"j2", {"a": "p_0001", "b": "p_0002", "seam": "nope"}
	)
	assert_str(unknown.seam_style).is_equal(ShipJoint.SEAM_FLAT)


func test_the_two_axes_round_trip_through_a_style_id() -> void:
	# The id is the pair, so reading the axes back off it and rebuilding must be the identity -
	# that is what lets the menu offer two toggles over one stored value.
	for style: String in ShipJoint.VALID_SEAM_STYLES:
		var indent: String = ShipJoint.indent_of(style)
		var surface: String = ShipJoint.surface_of(style)
		(
			assert_str(ShipJoint.style_for_axes(indent, surface))
			. append_failure_message("%s -> (%s, %s) did not round trip" % [style, indent, surface])
			. is_equal(style)
		)


func _host_volume_for(template: String, style: String) -> float:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, template, {})
	for jid: String in doc.joints:
		(doc.joints[jid] as ShipJoint).seam_style = style
	var solids: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)["solids"]
	return (solids["p_0001"] as PolyMesh).volume()
