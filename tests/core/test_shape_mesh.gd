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

## The class these tests build. Carbon has BOTH a fused nucleus and tunnelled extremities
## (ADR 0014), which is what makes it able to exercise every seam style; helium, which these tests
## used before, is now two fused bodies with no tunnel and no extremity anywhere on it.
const TEMPLATE: String = "carbon"

## Positional weld quantum for the watertightness check

var _data: ShipData
var _cfg: ShipConfig


## A config with NO hull wall, for the tests that are about tessellation and seams rather than
## shells. A shell changes every volume in the ship, so a test asking "did this style cut
## differently" would otherwise be reading the wall and the cut added together - and hollowing a
## carbon class six times over took 35 seconds on its own. The shell has its own tests below.
func _seam_cfg() -> ShipConfig:
	var out: ShipConfig = ShipConfig.from_dict(_cfg.snapshot())
	out.hull_thickness_m = 0.0
	return out


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


func test_a_template_ship_bakes_every_part() -> void:
	# The pure bake carries the plan out with its own polygon clipping, which is exact on planes
	# and approximate on curves; every part comes out, nothing is truncated. RETIRED(ADR 0020):
	# "every part closed" - that is the engine bake's promise now, held in
	# tests/harness/test_csg_bake.gd on both families, and the pure path is the fallback for a
	# caller with no scene tree.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	assert_object(doc).is_not_null()
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())
	var order: PackedStringArray = report["order"]
	# Every PLACED id bakes: the document's parts and the inner parts of its root component
	# (ADR 0024), which the attach pass places under their expanded ids.
	var placed: int = ShipAttach.resolve_all(doc, _data, _seam_cfg()).size()
	assert_int(order.size()).append_failure_message("nothing was baked").is_equal(placed)
	assert_int(int(report["tris"])).is_greater(0)
	for id: String in order:
		var solid: PolyMesh = (report["solids"] as Dictionary)[id]
		assert_bool(solid.truncated).append_failure_message("%s was truncated" % [id]).is_false()


func test_the_bake_agrees_with_the_ship_field() -> void:
	# End to end: the placement transform is applied to the mesh here and inverted inside the
	# field, so this checks the whole chain rather than the tessellator alone.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())
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
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	var first: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())
	var second: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())
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
	# The placed shape itself - an inner part of the root component, or the instance whose
	# proxy is its definition's root, answers the same way as a plain part (ADR 0024).
	var shape: ResolvedShape = ShipAttach.resolve_shapes(doc, _data, _cfg).get(id, null)
	if shape == null:
		return 0.0
	return (
		absf(shape.round_r)
		* minf(absf(shape.scale.x), minf(absf(shape.scale.y), absf(shape.scale.z)))
	)


# --- seam styles reach the mesh (ADR 0009 through ADR 0011) --------------------------------------


func test_the_indent_axis_of_a_style_decides_which_part_is_cut() -> void:
	# The half of a seam style that the plan carries out today (ADR 0020): WHICH part indents the
	# other. Under "small indents big" the tunnel is the indenter and the pod takes the socket;
	# under "big indents small" it is the other way round. Read off the PLAN, which both executors
	# carry out; what the cuts look like is the engine bake's test.
	#
	# RETIRED(ADR 0020): the same test on the pure bake's meshes, asserting closure and that the
	# flat and native surfaces differ. Closure is now the engine suite's claim
	# (tests/harness/test_csg_bake.gd), and every walled seam takes the native linkage surface for
	# now - FOLLOWUPS F32 - so flat and native do not yet differ.
	var base: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	var tunnel: String = _a_tunnel(base)
	var pod: String = ""
	for pid: String in base.part_order():
		if (base.parts[pid] as ShipPart).parent == tunnel:
			pod = pid
	assert_str(pod).is_not_empty()
	var cut_parts: Dictionary = {}
	for style: String in [ShipJoint.SEAM_SMALL_NATIVE, ShipJoint.SEAM_BIG_NATIVE]:
		var doc: ShipDoc = base.duplicate_doc()
		for jid: String in doc.joints:
			(doc.joints[jid] as ShipJoint).seam_style = style
		var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
		var cuts: Dictionary = plan["cuts"]
		cut_parts[style] = [cuts.has(pod), cuts.has(tunnel)]
	# Small indents big: the pod (big) is cut, the tunnel (small) is not.
	assert_bool(cut_parts[ShipJoint.SEAM_SMALL_NATIVE][0]).is_true()
	assert_bool(cut_parts[ShipJoint.SEAM_SMALL_NATIVE][1]).is_false()
	# Big indents small: the tunnel is cut by the pod, and the pod is left alone by that seam.
	assert_bool(cut_parts[ShipJoint.SEAM_BIG_NATIVE][1]).is_true()


func test_the_seam_style_is_read_not_baked_in() -> void:
	# Non-destructive by construction: the style lives on the joint and the mesh is derived, so
	# switching away and back has to land exactly where it started.
	# The detour is through the OTHER indent axis: under "big indents small" the pod is left alone
	# by the tunnel's seam, so its volume moves. RETIRED(ADR 0020): a detour through SMALL_NATIVE,
	# which no longer differs from the flat default - FOLLOWUPS F32.
	var base: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	var before: float = _host_volume(base, ShipJoint.SEAM_FLAT)
	var detour: float = _host_volume(base, ShipJoint.SEAM_BIG_NATIVE)
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
	var solids: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())["solids"]
	return (solids[_host_of(doc, _a_tunnel(doc))] as PolyMesh).volume()


# --- the four flat styles (ADR 0012) --------------------------------------------------------------


func test_every_seam_style_bakes_every_part() -> void:
	# Six styles, and the pure bake's promise for each is that every part comes out and none is
	# truncated. RETIRED(ADR 0020): "bakes closed solids" - closure is the engine bake's claim
	# (tests/harness/test_csg_bake.gd); the pure clipping is exact on planes and approximate on
	# curves, and this ship has curves.
	var base: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	for style: String in ShipJoint.VALID_SEAM_STYLES:
		var doc: ShipDoc = base.duplicate_doc()
		for jid: String in doc.joints:
			(doc.joints[jid] as ShipJoint).seam_style = style
		var report: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())
		var placed: int = ShipAttach.resolve_all(doc, _data, _seam_cfg()).size()
		(
			assert_int((report["order"] as PackedStringArray).size())
			. append_failure_message("style %s lost a part" % style)
			. is_equal(placed)
		)
		for id: String in report["order"]:
			var solid: PolyMesh = (report["solids"] as Dictionary)[id]
			assert_bool(solid.truncated).append_failure_message("%s truncated" % id).is_false()


func test_in_and_out_bump_put_the_plane_in_different_places() -> void:
	# IN takes the deepest point where the two surfaces cross, OUT the outermost, so the two must
	# not produce the same ship. Asked of the WHOLE bake rather than of the host alone: out-bump
	# raises a pad by unioning a stub on, and a union that would open a solid is refused (ADR
	# 0014), so on a class whose nucleus carries many seams the host can legitimately come out
	# unchanged while the extremities still differ.
	#
	# PER PART, NOT THE SUM (2026-09-22). The two styles move hull from one side of a seam to the
	# other, so the SHIP's total volume barely moves: measured on a carbon, twelve parts differ by
	# 0.95 to 1.95 m3 each while the sum differs by 0.0055 - and by 0.00006 once the ship is centred
	# on the beacon (ADR 0033) rather than pinned by its first module, which is what the sum had
	# been reading. The sum was a near-cancellation; the parts are the answer.
	var inward: Dictionary = _bake_with_style(ShipJoint.SEAM_SMALL_FLAT_INSERT)
	var outward: Dictionary = _bake_with_style(ShipJoint.SEAM_BIG_FLAT_INSERT)
	var moved: float = 0.0
	var count: int = 0
	for id: String in inward["order"]:
		var a: PolyMesh = inward["solids"][id]
		var b: Variant = (outward["solids"] as Dictionary).get(id)
		if not (b is PolyMesh):
			continue
		var apart: float = absf(a.volume() - (b as PolyMesh).volume())
		if apart > 0.1:
			count += 1
		moved = maxf(moved, apart)
	(
		assert_int(count)
		. append_failure_message(
			"in-bump and out-bump baked the same ship (biggest part apart by %.4f m3)" % [moved]
		)
		. is_greater_equal(4)
	)
	# ...and both must still be solid.
	for report: Dictionary in [inward, outward]:
		# ...and every part must still come out. RETIRED(ADR 0020): closure of the pure bake.
		assert_int((report["order"] as PackedStringArray).size()).is_greater(0)


func _bake_with_style(style: String) -> Dictionary:
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	for jid: String in doc.joints:
		(doc.joints[jid] as ShipJoint).seam_style = style
	return ShipMeshBake.bake(doc, _data, _seam_cfg())


func test_a_flange_leaves_the_host_alone_where_a_slice_cuts_it() -> void:
	# A tube landing on a flat box face: the deepest crossing IS that face, so neither style has
	# anything of the host to remove and the two must agree. The distinction only bites on a
	# curved host, which is exactly why both exist.
	var flange: float = _host_volume_for(TEMPLATE, ShipJoint.SEAM_SMALL_FLAT_INSERT)
	var slice: float = _host_volume_for(TEMPLATE, ShipJoint.SEAM_SMALL_FLAT_CUTOFF)
	(
		assert_float(flange)
		. append_failure_message("on a flat host face a flange and a slice must agree")
		. is_equal_approx(slice, 1.0e-6)
	)


func test_the_child_is_cut_flush_at_the_host_surface() -> void:
	# The whole point of the rework. A tube seated into a box should come out ENDING at the box's
	# face - not short of it, and not through it.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	for jid: String in doc.joints:
		(doc.joints[jid] as ShipJoint).seam_style = ShipJoint.SEAM_SMALL_FLAT_INSERT
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())
	var solids: Dictionary = report["solids"]
	var hull: PolyMesh = solids[doc.root]
	var tube: PolyMesh = solids[_a_tunnel(doc)]
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
	var solids: Dictionary = ShipMeshBake.bake(doc, _data, _seam_cfg())["solids"]
	return (solids[_host_of(doc, _a_tunnel(doc))] as PolyMesh).volume()


## What a part stands on. ASKED, NOT ASSUMED TO BE THE ROOT: since ADR 0017 a valence pod's tunnel
## is built on the PROTON whose arrangement slot it shares, not on the root, so a test that reads
## the root is no longer reading the other half of the tunnel's own seam.
func _host_of(doc: ShipDoc, pid: String) -> String:
	var part: ShipPart = doc.parts.get(pid, null) as ShipPart
	if part == null or part.parent.is_empty():
		return doc.root
	return part.parent


## The first TUNNEL in a template ship - an extremity's hallway, which is a child seated flush on
## the nucleus. Looked up rather than assumed: which part id that is depends on how many nucleus
## bodies the class fused first.
func _a_tunnel(doc: ShipDoc) -> String:
	for pid: String in doc.part_order():
		if (doc.parts[pid] as ShipPart).role == ShipPart.ROLE_HALLWAY:
			return pid
	return doc.root


# --- the interior shell (ADR 0015) ----------------------------------------------------------------


func test_every_module_is_hollowed_to_the_wall_thickness() -> void:
	# A box module is the case where the answer is exact and checkable: its interior is the same
	# box with the wall taken off every face, so the gap between the outer and inner surfaces IS
	# the wall. Measured off the mesh rather than assumed from the config.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "hydrogen", {})
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	var hull: PolyMesh = (report["solids"] as Dictionary)[doc.root]
	(
		assert_int(int(report["hollowed_parts"]))
		. append_failure_message("a hydrogen class is one module and it should be hollow")
		. is_equal(1)
	)
	assert_int(hull.open_edges()).append_failure_message("hollowing opened the hull").is_equal(0)
	# Six outer faces and six inner ones.
	assert_int(hull.face_count()).is_equal(12)

	var box: AABB = hull.aabb()
	var centre: Vector3 = box.get_center()
	var outer_half: float = box.size.x * 0.5
	var inner_half: float = 0.0
	for v: Vector3 in hull.vertices:
		var d: float = absf(v.x - centre.x)
		if d < outer_half - 0.001:
			inner_half = maxf(inner_half, d)
	(
		assert_float(outer_half - inner_half)
		. append_failure_message(
			(
				"wall measured %.4f m, asked for %.4f"
				% [outer_half - inner_half, _cfg.hull_thickness_m]
			)
		)
		. is_equal_approx(_cfg.hull_thickness_m, 1.0e-4)
	)


func test_a_hollow_module_encloses_less_than_a_solid_one() -> void:
	# The cavity is real volume, not a surface trick: the same ship with no wall weighs the whole
	# budget, and with one it weighs only what the walls are made of.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "hydrogen", {})
	var solid: float = ShipMeshBake.bake(doc, _data, _seam_cfg())["parts_volume_m3"]
	var shell: float = float(ShipMeshBake.bake(doc, _data, _cfg)["parts_volume_m3"])
	assert_float(shell).append_failure_message("hollowing removed nothing").is_less(solid * 0.5)
	assert_float(shell).append_failure_message("hollowing removed everything").is_greater(0.0)


func test_a_part_thinner_than_two_walls_stays_solid() -> void:
	# The honest answer for a part with no room for an interior. ShapeMesh.inset() collapses its
	# primitive and build() hands back nothing, so the subtraction has nothing to take out.
	var shape: ResolvedShape = _shape("box_hull", _bare("box_hull"), Vector3.ONE)
	var wall: float = shape.size.x * 2.0
	(
		assert_bool(ShapeMesh.build(ShapeMesh.inset(shape, wall)).is_empty())
		. append_failure_message("a part thinner than two walls should have no interior at all")
		. is_true()
	)


func test_the_interior_is_built_for_every_seam_cut_part() -> void:
	# Every part of a seam-cut ship is hollowed - the interior is planned and carried out for each.
	# RETIRED(ADR 0020): "does not open onto a seam face", asserted as closure of the pure bake's
	# meshes; that is the engine bake's claim now (tests/harness/test_csg_bake.gd).
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	var placed: int = ShipAttach.resolve_all(doc, _data, _cfg).size()
	(
		assert_int(int(report["hollowed_parts"]))
		. append_failure_message("not every part was hollowed on a seam-cut ship")
		. is_equal(placed)
	)


func test_the_pure_bake_plans_an_open_seam_as_a_pair_of_cuts() -> void:
	# The PLAN is core's and is what both executors carry out (ADR 0020): an open seam asks for the
	# indented part to lose the indenter's body on both surfaces, and the indenter to lose the
	# indented part's room on both. What the cuts LOOK like is the engine bake's test
	# (tests/harness/test_csg_bake.gd); this one holds the plan to its meaning.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	# The joint mechanics between PLAIN parts: the nucleus component is dissolved first (ADR 0024).
	ShipComponents.dissolve(doc, doc.root)
	# The definition's open links come back with it (ADR 0025); this test wants plain walls.
	for jid: String in doc.joints.keys():
		if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_OPEN:
			doc.joints.erase(jid)
	# The first pair of the dissolved nucleus: its bodies ring the beacon and stand on nothing
	# (ADR 0034), so the pair is the root and the body beside it rather than a parent and a child.
	var pair: PackedStringArray = PackedStringArray()
	for pid: String in doc.part_order():
		if pid == doc.root:
			continue
		var part: ShipPart = doc.parts[pid]
		pair = PackedStringArray([part.parent if not part.parent.is_empty() else doc.root, pid])
		break
	var joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(), {"a": pair[0], "b": pair[1], "mode": ShipJoint.MODE_OPEN}
	)
	doc.joints[joint.id] = joint
	var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
	assert_int(int(plan["open_seams"])).is_equal(1)
	# The open cuts are the pure executor's reading; the engine reads the room instead (ADR 0021).
	var cuts: Dictionary = plan["open_cuts"]
	assert_int(cuts.size()).is_equal(2)
	assert_int((plan["rooms"] as Array).size()).is_equal(1)
	assert_int((plan["rooms"][0] as PackedStringArray).size()).is_equal(2)
	for id: String in pair:
		var list: Array = cuts.get(id, [])
		assert_int(list.size()).is_equal(1)
		# One room: the same cutter takes both surfaces.
		assert_str(str(list[0]["outer"])).is_equal(str(list[0]["inner"]))


func test_a_bounded_opening_is_planned_as_a_door_the_pure_bake_does_not_bore() -> void:
	# DOORWAY and HATCHED are bounded openings. Since ADR 0029 the plan carries a door for each
	# (ShipDoors) and the ENGINE bores it; this pure executor still keeps its wall, and the
	# report says so (`bored` empty) rather than let a seam the player asked to open look done.
	# PENDING is now a seam nothing could be bored for.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, "helium", {})
	# A bounded opening between PLAIN parts on an otherwise walled ship: the nucleus component
	# is dissolved first (ADR 0024), so the doorway is the only joint on the nucleus seam. (A
	# tunnel's seam already carries a hatch, which would win the collapse.)
	ShipComponents.dissolve(doc, doc.root)
	# The definition's open links come back with it (ADR 0025); this test wants plain walls.
	for jid: String in doc.joints.keys():
		if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_OPEN:
			doc.joints.erase(jid)
	# The first pair of the dissolved nucleus: its bodies ring the beacon and stand on nothing
	# (ADR 0034), so the pair is the root and the body beside it rather than a parent and a child.
	var pair: PackedStringArray = PackedStringArray()
	for pid: String in doc.part_order():
		if pid == doc.root:
			continue
		var part: ShipPart = doc.parts[pid]
		pair = PackedStringArray([part.parent if not part.parent.is_empty() else doc.root, pid])
		break
	var joint: ShipJoint = ShipJoint.from_dict(
		doc.new_joint_id(), {"a": pair[0], "b": pair[1], "mode": ShipJoint.MODE_DOORWAY}
	)
	doc.joints[joint.id] = joint
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	assert_int((report["doors"] as Array).size()).is_equal(1)
	assert_int(int(report["pending_seams"])).is_equal(0)
	assert_int((report["bored"] as PackedStringArray).size()).is_equal(0)
	assert_int(int(report["open_seams"])).is_equal(0)


func test_a_lone_sphere_is_two_nested_surfaces_exactly() -> void:
	# The pure bake's one unconditional promise: a part with no seam is the outer surface plus the
	# inner turned inside out - no boolean - and on the family the author builds with it is exact.
	# RETIRED(ADR 0020): the same claim for seam-cut spheres, which belongs to the engine bake.
	var one: ShipDoc = ShipTemplates.build(
		_data, _cfg, "hydrogen", {ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"}
	)
	var shapes: Dictionary = ShipAttach.resolve_shapes(one, _data, _cfg)
	var outer: float = ShapeMesh.build(shapes[one.root]).volume()
	var inner: float = (
		ShapeMesh.build(ShapeMesh.inset(shapes[one.root], _cfg.hull_thickness_m)).volume()
	)
	var shell: PolyMesh = ShipMeshBake.bake(one, _data, _cfg)["solids"][one.root]
	assert_float(shell.volume()).is_equal_approx(outer - inner, 0.01)
	assert_int(shell.open_edges()).is_equal(0)


func test_a_class_with_many_open_seams_still_bakes_quickly_and_closed() -> void:
	# The bore this replaced put a thin passage against a finished SHELL and split until the budget
	# ran out: a carbon class whose six protons were one room took 52 SECONDS and opened nothing.
	# Not cutting the interior at an open seam is exact AND cheaper than cutting it.
	var doc: ShipDoc = ShipTemplates.build(_data, _cfg, TEMPLATE, {})
	# Open seams by JOINT between plain protons: the nucleus component is dissolved first (ADR 0024).
	ShipComponents.dissolve(doc, doc.root)
	# The definition's open links come back with it (ADR 0025); this test wants plain walls.
	for jid: String in doc.joints.keys():
		if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_OPEN:
			doc.joints.erase(jid)
	var protons: PackedStringArray = PackedStringArray([doc.root])
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		var on_the_core: bool = part.parent == doc.root or part.parent.is_empty()
		if on_the_core and pid != doc.root and part.role == ShipPart.ROLE_ROOM:
			protons.append(pid)
	# EVERY pair of the clump. The dissolved bodies are ANCHORED to the beacon (ADR 0034) rather
	# than hung off each other, and parts that stand side by side name their own pairs.
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(doc, protons)
	assert_int(pairs.size()).is_greater(1)
	for pair: PackedStringArray in pairs:
		var joint: ShipJoint = ShipJoint.from_dict(
			doc.new_joint_id(), {"a": pair[0], "b": pair[1], "mode": ShipJoint.MODE_OPEN}
		)
		doc.joints[joint.id] = joint
	var report: Dictionary = ShipMeshBake.bake(doc, _data, _cfg)
	# Not every named pair is a seam: a pair has one where the two solids MEET, and the bodies
	# across the nucleus from each other do not (ADR 0034). What matters is that they all end up
	# in ONE room, which is the thing this test is timing.
	assert_int(int(report["open_seams"])).is_greater(1)
	var biggest: int = 0
	for members: PackedStringArray in ShipMeshBake.plan(doc, _data, _cfg)["rooms"]:
		biggest = maxi(biggest, members.size())
	assert_int(biggest).append_failure_message("the nucleus did not come out as one room").is_equal(
		protons.size()
	)
	# One room of six: five absorbed, one solid carrying them all. The room's own surfaces are
	# unions computed from two sides and may carry seam hairlines (ADR 0019 records the sagitta);
	# what may NOT happen is any module OTHER than the room coming out open.
	# RETIRED(ADR 0020): only the room's own pieces may be open. The pure clipping leaves seam
	# hairlines on every curved seam; closure is the engine bake's claim.
	assert_int((report["order"] as PackedStringArray).size()).is_equal(
		ShipAttach.resolve_all(doc, _data, _cfg).size()
	)
	# Generous by design - this is a cliff detector, not a benchmark. The measured figure is about
	# two seconds; the bore it replaced was fifty-two.
	(
		assert_int(int(report["ms"]))
		. append_failure_message("a nucleus made one room took %d ms" % [int(report["ms"])])
		. is_less(20000)
	)
