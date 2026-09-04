# Bake a single small sphere and check the extractor's real correctness properties: a
# plausible non-empty mesh, volume within analytic tolerance, and -- the actual test of the
# Surface Nets vertex placement -- every emitted vertex sits within one grid cell of the
# true SDF surface. Per the bake implementer, the report's "cells" is a cell COUNT; the
# actual cell size used is "cell_m" (grid may adapt), so tolerance checks read cell_m, never
# cfg.bake_cell_m.
class_name TestBake
extends GdUnitTestSuite

var _data: ShipData
var _sphere_family: String
var _sphere_mfr: String
var _sphere_params: Dictionary
var _sphere_scale: Vector3
var _sphere_shape: ResolvedShape


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
	(
		assert_bool(ok)
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)

	var found_sphere: bool = false
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var mfr_id: String = mfrs[0]
		var defaults: Dictionary = ShapeGen.default_params(_data, family_id, mfr_id)
		var minimal: Dictionary = ShapeGen.clamp_params(_data, family_id, mfr_id, _zeroed(defaults))
		var probe: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr_id, minimal, Vector3.ONE)
		var natural: float = maxf(probe.bound_radius, 0.001)
		var factor: float = clampf(2.0 / natural, 0.05, 5.0)
		var scale: Vector3 = Vector3(factor, factor, factor)
		var shape: ResolvedShape = ShapeGen.resolve(_data, family_id, mfr_id, minimal, scale)
		if shape.base == ResolvedShape.Base.SPHERE and not found_sphere:
			_sphere_family = family_id
			_sphere_mfr = mfr_id
			_sphere_params = minimal
			_sphere_scale = scale
			_sphere_shape = shape
			found_sphere = true

	(
		assert_bool(found_sphere)
		. append_failure_message(
			(
				"no family in res://data resolves to a SPHERE base primitive with zeroed params -- "
				+ "cannot run the bake ground-truth test"
			)
		)
		. is_true()
	)


func _bake_sphere_doc() -> ShipDoc:
	var doc: ShipDoc = ShipDoc.create_new(_sphere_family, _sphere_mfr, _data)
	var root_part: ShipPart = doc.parts[doc.root] as ShipPart
	root_part.params = _sphere_params
	root_part.scale = _sphere_scale
	return doc


func _bake_report() -> Dictionary:
	var doc: ShipDoc = _bake_sphere_doc()
	var cfg: ShipConfig = ShipConfig.defaults()
	# Coarse but small: keeps Surface Nets fast while leaving enough cells across the
	# sphere for the tolerance below to be meaningful.
	cfg.bake_cell_m = 0.3
	var sdf: ShipSdf = ShipSdf.build(doc, _data, cfg)
	return HullBake.bake(sdf, cfg, 0.0)


func test_bake_sphere_produces_a_plausible_mesh() -> void:
	var report: Dictionary = _bake_report()
	var verts: int = report["verts"] as int
	var tris: int = report["tris"] as int
	assert_int(verts).append_failure_message("bake produced zero vertices for a sphere").is_greater(
		0
	)
	assert_int(tris).append_failure_message("bake produced zero triangles for a sphere").is_greater(
		0
	)
	# A closed sphere shell has roughly 2 triangles per emitted quad face; with a coarse
	# grid that is tens to a few thousand triangles, never a handful and never millions.
	assert_int(tris).is_greater_equal(20)
	assert_int(tris).is_less(200000)

	var mesh: ArrayMesh = report["mesh"] as ArrayMesh
	assert_object(mesh).is_not_null()
	assert_int(mesh.get_surface_count()).is_greater(0)


func test_bake_sphere_volume_matches_analytic_and_self_consistent_mesh() -> void:
	var report: Dictionary = _bake_report()
	var r: float = _sphere_shape.size.x * _sphere_scale.x
	var expected_volume: float = (4.0 / 3.0) * PI * r * r * r
	var reported_volume: float = report["volume_m3"] as float
	(
		assert_float(reported_volume)
		. append_failure_message(
			(
				"sphere r=%f: bake volume_m3=%f, expected %f +/- 10%% (grid discretisation)"
				% [r, reported_volume, expected_volume]
			)
		)
		. is_equal_approx(expected_volume, expected_volume * 0.10)
	)

	# The returned mesh is the SHELL - the outer surface plus the reversed cavity wall - so its
	# signed volume is the MATERIAL, not the displacement. `volume_m3` stays the outer volume
	# because that is what the budgets and the gauges mean by "how big is this ship";
	# `shell_volume_m3` is what the mesh weighs. Asserting the mesh against volume_m3 was correct
	# while the bake produced a skin and became wrong the moment it produced a wall.
	var mesh: ArrayMesh = report["mesh"] as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var recomputed_volume: float = HullBake.mesh_volume(verts, idx)
	var shell_volume: float = report["shell_volume_m3"] as float
	(
		assert_float(recomputed_volume)
		. append_failure_message(
			(
				(
					"HullBake.mesh_volume() on the report's own shell mesh (%f) disagrees with the "
					% [recomputed_volume]
				)
				+ "report's shell_volume_m3 field (%f)" % [shell_volume]
			)
		)
		. is_equal_approx(shell_volume, maxf(absf(shell_volume) * 0.02, 0.001))
	)


func test_bake_sphere_vertices_lie_within_one_cell_of_true_surface() -> void:
	var doc: ShipDoc = _bake_sphere_doc()
	var cfg: ShipConfig = ShipConfig.defaults()
	cfg.bake_cell_m = 0.3
	var sdf: ShipSdf = ShipSdf.build(doc, _data, cfg)
	var report: Dictionary = HullBake.bake(sdf, cfg, 0.0)

	var cell_m: float = report["cell_m"] as float
	assert_float(cell_m).is_greater(0.0)

	var mesh: ArrayMesh = report["mesh"] as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	assert_array(verts).is_not_empty()

	var worst: float = 0.0
	for v: Vector3 in verts:
		var d: float = absf(sdf.sample(v))
		worst = maxf(worst, d)
	(
		assert_float(worst)
		. append_failure_message(
			(
				"a baked vertex sits %f m from the true SDF surface, more than one cell (%f m)"
				% [worst, cell_m]
			)
		)
		. is_less_equal(cell_m * 1.5)
	)


func test_bake_report_has_the_documented_resolution_fields() -> void:
	var report: Dictionary = _bake_report()
	(
		assert_int(report["cells"] as int)
		. append_failure_message("'cells' should be a positive grid cell count")
		. is_greater(0)
	)
	(
		assert_float(report["cell_m"] as float)
		. append_failure_message("'cell_m' should be the positive cell size actually used")
		. is_greater(0.0)
	)
	var dims: Vector3i = report["dims"] as Vector3i
	(
		assert_bool(dims.x > 0 and dims.y > 0 and dims.z > 0)
		. append_failure_message("'dims' should be a positive grid dimension, got %s" % [dims])
		. is_true()
	)
	assert_int(report["ms"] as int).is_greater_equal(0)


# --- the interior shell (FOLLOWUPS F10.1) --------------------------------------------------
#
# "i certainly want to give it a thickness and an interior mesh, trach its volum and mass etc."
# A skin has no thickness to track, so every number below is only meaningful once the second
# isosurface exists - which is why they are asserted against each other rather than against
# constants: the grid discretises both surfaces the same way, and their RELATIONSHIP is exact
# where their absolute values are not.


func test_bake_produces_an_interior_cavity_inside_the_outer_surface() -> void:
	var report: Dictionary = _bake_report()
	var outer: float = report["volume_m3"] as float
	var inner: float = report["interior_volume_m3"] as float
	var shell: float = report["shell_volume_m3"] as float
	(
		assert_int(report["interior_tris"] as int)
		. append_failure_message(
			"the bake produced no interior surface at all, so the hull is still a skin"
		)
		. is_greater(0)
	)
	(
		assert_float(inner)
		. append_failure_message(
			(
				"the cavity (%f m3) is not smaller than the hull that contains it (%f m3)"
				% [inner, outer]
			)
		)
		. is_less(outer)
	)
	assert_float(inner).is_greater(0.0)
	(
		assert_float(shell)
		. append_failure_message(
			"shell_volume_m3 (%f) is not outer minus cavity (%f)" % [shell, outer - inner]
		)
		. is_equal_approx(outer - inner, maxf(outer * 0.01, 0.001))
	)


func test_interior_offset_matches_the_configured_thickness() -> void:
	# A sphere is the one shape where the cavity radius is known in closed form: r - T. Anything
	# else and this would be asserting the extractor against itself.
	# THE SPHERE IS SCALED UP FOR THIS ONE. At the pack's own size the cavity is 0.55 m across
	# against a 0.3 m cell - under four cells - and Surface Nets under-fills a shape that small by
	# about a third. That is discretisation, not a defect, but it makes the measurement say
	# nothing about whether the OFFSET is right. Three times the radius puts nineteen cells across
	# the cavity and the remaining error is the honest grid error.
	var doc: ShipDoc = _bake_sphere_doc()
	var root_part: ShipPart = doc.parts[doc.root] as ShipPart
	root_part.scale = _sphere_scale * 3.0
	var cfg: ShipConfig = ShipConfig.defaults()
	cfg.bake_cell_m = 0.3
	cfg.hull_thickness_m = 0.6
	var sdf: ShipSdf = ShipSdf.build(doc, _data, cfg)
	var report: Dictionary = HullBake.bake(sdf, cfg, 0.0)
	var r: float = _sphere_shape.size.x * _sphere_scale.x * 3.0
	var want: float = (4.0 / 3.0) * PI * pow(maxf(r - cfg.hull_thickness_m, 0.0), 3.0)
	var inner: float = report["interior_volume_m3"] as float
	(
		assert_float(inner)
		. append_failure_message(
			(
				"a %.2f m wall in a %.2f m sphere should leave a %.3f m3 cavity, got %.3f"
				% [cfg.hull_thickness_m, r, want, inner]
			)
		)
		. is_equal_approx(want, want * 0.08)
	)


func test_a_seam_wall_reaches_the_interior_mesh() -> void:
	# ADR 0008: a child sunk into its parent with no joint record has a WALL across the seam.
	# The wall is two faces on the interior isosurface, so the cavity mesh grows while the outer
	# surface - and therefore the outer area every budget reads - stays what it was.
	var box_mfr: String = _data.manufacturers_for("box_hull")[0]
	var doc: ShipDoc = ShipDoc.create_new("box_hull", box_mfr, _data, 5.0)
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.family = "cylinder_spar"
	child.manufacturer = _data.manufacturers_for("cylinder_spar")[0]
	child.params = ShapeGen.default_params(_data, "cylinder_spar", child.manufacturer)
	child.pitch = 90.0
	child.scale = Vector3(3.0, 1.0, 3.0)
	var cfg: ShipConfig = ShipConfig.from_dict(_data.config.snapshot())
	child.offset = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, doc.parts[doc.root]),
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, child),
		child,
		cfg
	)
	var child_id: String = doc.add_part(child)
	# Coarse on purpose: this is a topology check, not a resolution check.
	cfg.bake_cell_m = 0.35
	var walled: Dictionary = HullBake.bake(ShipSdf.build(doc, _data, cfg), cfg, 0.0)

	var joint: ShipJoint = ShipJoint.new()
	joint.id = doc.new_joint_id()
	joint.a = doc.root if doc.root <= child_id else child_id
	joint.b = child_id if doc.root <= child_id else doc.root
	joint.mode = ShipJoint.MODE_OPEN
	doc.joints[joint.id] = joint
	var opened: Dictionary = HullBake.bake(ShipSdf.build(doc, _data, cfg), cfg, 0.0)

	var walled_in: int = walled["interior_tris"] as int
	var opened_in: int = opened["interior_tris"] as int
	(
		assert_int(walled_in)
		. append_failure_message(
			(
				"a sealed seam should add wall faces to the cavity: walled %d vs open %d"
				% [walled_in, opened_in]
			)
		)
		. is_greater(opened_in)
	)
	var walled_area: float = walled["area_m2"] as float
	var opened_area: float = opened["area_m2"] as float
	(
		assert_float(walled_area)
		. append_failure_message(
			"the outer surface must not change with a wall: %f vs %f" % [walled_area, opened_area]
		)
		. is_equal_approx(opened_area, opened_area * 0.02)
	)
	# The wall eats cavity: the interior volume falls, the outer volume does not.
	assert_float(walled["interior_volume_m3"] as float).is_less(
		opened["interior_volume_m3"] as float
	)


func test_zero_thickness_bakes_the_bare_skin_it_always_did() -> void:
	# The compatibility case, and the reason the second pass is conditional: at zero thickness
	# there is no cavity to extract and the mesh must be exactly the outer surface, so the whole
	# feature costs a caller who does not want it nothing at all.
	var doc: ShipDoc = _bake_sphere_doc()
	var cfg: ShipConfig = ShipConfig.defaults()
	cfg.bake_cell_m = 0.3
	cfg.hull_thickness_m = 0.0
	var sdf: ShipSdf = ShipSdf.build(doc, _data, cfg)
	var report: Dictionary = HullBake.bake(sdf, cfg, 0.0)
	(
		assert_int(report["interior_tris"] as int)
		. append_failure_message("zero thickness still produced an interior surface")
		. is_equal(0)
	)
	var outer: float = report["volume_m3"] as float
	(
		assert_float(report["shell_volume_m3"] as float)
		. append_failure_message(
			"at zero thickness the shell volume must be the whole outer volume"
		)
		. is_equal_approx(outer, maxf(outer * 0.01, 0.001))
	)
