# Dual Contouring, ADR 0009. "the mesh resolution of the seem between 2 objects is incorrect,
# its not flattened along the plane of intersection its all bumped out and weird looking."
#
# The naive centroid rule this replaced is exact on a plane - the centroid of coplanar crossings
# is on the plane - and rounds every SHARP feature by up to half a cell. So a flat seam face was
# never the problem in its middle; its RIM was, where the flat face meets the flank, and so was
# every box edge and cylinder cap in the builder. These tests measure sharpness, which is the
# only thing that changed, and they are written so a return to the centroid rule fails them.
class_name TestDualContouring
extends GdUnitTestSuite

## Grid spacing for the box. Coarse on purpose: rounding is a per-cell error, so a fine grid
## would hide the very thing under test.
const CELL_M: float = 0.25

## A box vertex may sit this far from the true box surface, as a fraction of a cell. Dual
## Contouring puts corner and edge vertices ON the feature; the centroid rule pulls them inward
## along the diagonal by roughly half a cell.
const CORNER_TOL_CELLS: float = 0.35

var _data: ShipData
var _box_family: String
var _box_mfr: String


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)
	for family_id: String in _data.family_ids():
		var mfrs: PackedStringArray = _data.manufacturers_for(family_id)
		if mfrs.is_empty():
			continue
		var probe: ResolvedShape = ShapeGen.resolve(
			_data,
			family_id,
			mfrs[0],
			ShapeGen.default_params(_data, family_id, mfrs[0]),
			Vector3.ONE
		)
		if probe.base == ResolvedShape.Base.BOX and _box_family.is_empty():
			_box_family = family_id
			_box_mfr = mfrs[0]
	assert_str(_box_family).append_failure_message("no BOX family in res://data").is_not_empty()


## A one-part document holding a box of half-extents `half`, with every micro-detail op zeroed
## so the true surface is an exact box and a deviation can only come from the extractor.
func _box_doc(half: Vector3) -> ShipDoc:
	var doc: ShipDoc = ShipDoc.create_new(_box_family, _box_mfr, _data)
	var root: ShipPart = doc.parts[doc.root]
	var params: Dictionary = ShapeGen.default_params(_data, _box_family, _box_mfr)
	for key: String in params.keys():
		if typeof(params[key]) == TYPE_FLOAT or typeof(params[key]) == TYPE_INT:
			params[key] = 0.0
	root.params = ShapeGen.clamp_params(_data, _box_family, _box_mfr, params)
	var base: ResolvedShape = ShapeGen.resolve(
		_data, _box_family, _box_mfr, root.params, Vector3.ONE
	)
	var size: Vector3 = base.local_aabb().size * 0.5
	root.scale = Vector3(half.x / size.x, half.y / size.y, half.z / size.z)
	return doc


func _cfg(cell: float) -> ShipConfig:
	var cfg: ShipConfig = ShipConfig.defaults()
	cfg.bake_cell_m = cell
	# Skin off: this suite is about where the OUTER surface's vertices land, and a second
	# isosurface would only add vertices that say nothing about that.
	cfg.hull_thickness_m = 0.0
	return cfg


## Signed distance to an axis-aligned box of half-extents `half` centred on the origin.
static func _box_sdf(p: Vector3, half: Vector3) -> float:
	var q: Vector3 = p.abs() - half
	var outside: Vector3 = Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	return outside.length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


func test_a_box_keeps_its_corners() -> void:
	var half: Vector3 = Vector3(1.0, 1.0, 1.0)
	var doc: ShipDoc = _box_doc(half)
	var cfg: ShipConfig = _cfg(CELL_M)
	var report: Dictionary = HullBake.bake(ShipSdf.build(doc, _data, cfg), cfg, 0.0)
	var cell: float = report["cell_m"]
	var mesh: ArrayMesh = report["mesh"]
	assert_int(mesh.get_surface_count()).is_greater(0)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(verts.size()).is_greater(0)

	# Every one of the eight true corners must have a vertex ON it, not inboard of it.
	var worst: float = 0.0
	var worst_corner: Vector3 = Vector3.ZERO
	for i: int in 8:
		var corner: Vector3 = Vector3(
			half.x if (i & 1) != 0 else -half.x,
			half.y if (i & 2) != 0 else -half.y,
			half.z if (i & 4) != 0 else -half.z
		)
		var nearest: float = INF
		for v: Vector3 in verts:
			nearest = minf(nearest, v.distance_to(corner))
		if nearest > worst:
			worst = nearest
			worst_corner = corner
	var allowed: float = cell * CORNER_TOL_CELLS
	(
		assert_float(worst)
		. append_failure_message(
			(
				(
					"the worst box corner %s is %.4f m from the nearest vertex, allowed %.4f "
					+ "(%.2f cells of %.3f m). The centroid rule rounds corners by about half a cell; "
					+ "this failing means vertex placement is back to averaging."
				)
				% [str(worst_corner), worst, allowed, CORNER_TOL_CELLS, cell]
			)
		)
		. is_less(allowed)
	)


func test_every_box_vertex_lies_on_the_box() -> void:
	# Sharpness must not have been bought with vertices that wander off the surface: the QEF is
	# clamped into its own cell precisely so this stays true.
	var half: Vector3 = Vector3(1.0, 1.0, 1.0)
	var cfg: ShipConfig = _cfg(CELL_M)
	var report: Dictionary = HullBake.bake(ShipSdf.build(_box_doc(half), _data, cfg), cfg, 0.0)
	var cell: float = report["cell_m"]
	var verts: PackedVector3Array = (report["mesh"] as ArrayMesh).surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX
	]
	var worst: float = 0.0
	for v: Vector3 in verts:
		worst = maxf(worst, absf(_box_sdf(v, half)))
	(
		assert_float(worst)
		. append_failure_message(
			(
				"a vertex sits %.4f m off the true box surface, more than one cell (%.3f m)"
				% [worst, cell]
			)
		)
		. is_less(cell)
	)


func test_box_volume_is_close_to_analytic() -> void:
	# Rounding corners and edges COSTS volume, so this is the same sharpness fact measured as a
	# quantity rather than a distance. A 2 m cube at 0.25 m cells loses several percent to the
	# centroid rule; Dual Contouring keeps it inside 2%.
	var half: Vector3 = Vector3(1.0, 1.0, 1.0)
	var cfg: ShipConfig = _cfg(CELL_M)
	var report: Dictionary = HullBake.bake(ShipSdf.build(_box_doc(half), _data, cfg), cfg, 0.0)
	var expected: float = 8.0 * half.x * half.y * half.z
	var got: float = report["volume_m3"]
	(
		assert_float(got)
		. append_failure_message(
			"a %.1f m cube baked to %.4f m3, analytic %.4f m3" % [2.0 * half.x, got, expected]
		)
		. is_equal_approx(expected, expected * 0.02)
	)


func test_a_thin_slab_survives_without_nan() -> void:
	# A slab thinner than a cell puts several crossings on nearly the same plane, which is the
	# rank-deficient case the regularisation exists for. Nothing here may be NaN or infinite,
	# and no vertex may escape the grid.
	var half: Vector3 = Vector3(1.0, 0.06, 1.0)
	var cfg: ShipConfig = _cfg(0.25)
	var sdf: ShipSdf = ShipSdf.build(_box_doc(half), _data, cfg)
	var report: Dictionary = HullBake.bake(sdf, cfg, 0.0)
	var mesh: ArrayMesh = report["mesh"]
	if mesh.get_surface_count() == 0:
		return
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bounds: AABB = sdf.aabb().grow(cfg.bake_cell_m * 2.0)
	for v: Vector3 in verts:
		(
			assert_bool(is_finite(v.x) and is_finite(v.y) and is_finite(v.z))
			. append_failure_message("a non-finite vertex %s came out of the extractor" % [str(v)])
			. is_true()
		)
		(
			assert_bool(bounds.has_point(v))
			. append_failure_message("vertex %s escaped the sample grid %s" % [str(v), str(bounds)])
			. is_true()
		)


func test_a_cut_face_is_flat_across_its_middle() -> void:
	# The seam case, measured where it is legitimate to measure it. A module cut at its seam is
	# a half-space intersection, so the face's MIDDLE is planar in the field and must be planar
	# in the mesh; its rim is where the surface genuinely turns and is excluded.
	var cfg: ShipConfig = ShipConfig.from_dict(_data.config.snapshot())
	cfg.bake_cell_m = 0.2
	# Skin OFF. The bake returns the closed shell - outer surface plus the reversed cavity wall -
	# and the cavity wall of a cut face sits exactly one hull thickness behind it, which any
	# distance-to-the-plane measure would read as a 0.15 m bulge. The question here is where the
	# OUTER face's vertices land.
	cfg.hull_thickness_m = 0.0
	var doc: ShipDoc = ShipDoc.create_new(_box_family, _box_mfr, _data, cfg.root_span_m)
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.family = _box_family
	child.manufacturer = _box_mfr
	child.params = ShapeGen.default_params(_data, _box_family, _box_mfr)
	child.pitch = 90.0
	child.scale = Vector3(2.0, 2.0, 2.0)
	child.offset = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, doc.parts[doc.root]),
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, child),
		child,
		cfg
	)
	var child_id: String = doc.add_part(child)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, cfg)
	var seam: Dictionary = {}
	for record: Dictionary in sdf.seams():
		if record[ShipSeams.SEAM_CHILD] == child_id:
			seam = record
	assert_bool(seam.is_empty()).is_false()
	var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
	var report: Dictionary = HullBake.bake(sdf.module_view(child_id), cfg, 0.0)
	var arrays: Array = (report["mesh"] as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cell: float = report["cell_m"]
	# TRIANGLES on the cut face, well inside its rim: centroid within a cell of the plane and no
	# further than 60% of the child's half-width from the seam axis.
	#
	# RETIRED(2026-09-03): counting VERTICES there instead. That reading assumed the mesh keeps a
	# vertex every cell across a flat face, which stopped being true when HullSimplify started
	# rebuilding a flat face as the few triangles it actually needs - a face whose middle is
	# perfectly flat now has no vertices in its middle at all, and the old form of this test would
	# have failed for exactly the reason it exists to reward. The property under test is unchanged
	# and the tolerance is unchanged; only the sampling moved from vertices to faces.
	var child_index: int = 0
	for i: int in sdf.part_count():
		if sdf.part_id_at(i) == child_id:
			child_index = i
	var box: Vector3 = sdf.part_aabb(child_index).size
	var reach: float = 0.6 * 0.5 * minf(box.x, box.z)
	var worst: float = 0.0
	var counted: int = 0
	var t: int = 0
	while t + 2 < idx.size():
		var a: Vector3 = verts[idx[t]]
		var b: Vector3 = verts[idx[t + 1]]
		var c: Vector3 = verts[idx[t + 2]]
		var d: Vector3 = (a + b + c) / 3.0 - frame.origin
		var along: float = d.dot(frame.basis.z)
		t += 3
		if absf(along) > cell:
			continue
		if (d - frame.basis.z * along).length() > reach:
			continue
		counted += 1
		for corner: Vector3 in [a, b, c]:
			worst = maxf(worst, absf((corner - frame.origin).dot(frame.basis.z)))
	assert_int(counted).append_failure_message("no triangles landed on the cut face").is_greater(0)
	(
		assert_float(worst)
		. append_failure_message(
			(
				"the cut face bulges %.4f m off its own plane over %d triangles (cell %.3f m)"
				% [worst, counted, cell]
			)
		)
		. is_less(cell * 0.25)
	)
