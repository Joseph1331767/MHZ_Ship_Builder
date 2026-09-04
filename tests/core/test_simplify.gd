# HullSimplify, the CAD-shaped rebuild of the bake. "we cant have this messy resolutions with
# janky triangles all over the place... your mental model should be google sketchup solid tools
# type of resolution."
#
# The measurements these tests defend, taken before the pass existed: a lone 2 m box left Dual
# Contouring as 588 triangles at a 0.25 m cell, and a 3 m room module as 1568 with 65% of its
# area dead flat. What matters afterwards is not only that the counts fell but that nothing was
# lost doing it - so every test here is paired: one asserts the mesh got smaller, its partner
# asserts it stayed closed, stayed on the surface, or kept a hole it was supposed to keep.
class_name TestSimplify
extends GdUnitTestSuite

## Coarse on purpose. Simplification is a per-cell story, so a fine grid would hide it.
const CELL_M: float = 0.25

## Positional weld quantum for the watertightness check, in metres. Patches carry their own
## copies of a shared vertex - that is what gives a hard edge its two normals - so edges can
## only be counted after welding by POSITION. Snapping puts the copies at bit-identical
## coordinates, but the tolerance is kept real rather than exact so the test measures geometry
## rather than float equality.
const WELD_M: float = 0.0001

var _data: ShipData
var _box_family: String
var _box_mfr: String
var _tube_family: String
var _tube_mfr: String


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
		if probe.base == ResolvedShape.Base.CYLINDER and _tube_family.is_empty():
			_tube_family = family_id
			_tube_mfr = mfrs[0]
	assert_str(_box_family).append_failure_message("no BOX family in res://data").is_not_empty()
	assert_str(_tube_family).append_failure_message("no CYLINDER family in data").is_not_empty()


# --- the headline: a box is a box ------------------------------------------------------------


func test_a_plain_box_bakes_to_twelve_triangles() -> void:
	# The whole point of the file, and the number is not approximate: six faces, two triangles
	# each, eight corners once they are welded by position. Dual Contouring alone produced 588.
	var report: Dictionary = _bake_box(0.0, 0.0)
	var mesh: ArrayMesh = report["mesh"]
	var arrays: Array = mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	(
		assert_int(idx.size() / 3)
		. append_failure_message("a box should bake to 12 triangles, not %d" % [idx.size() / 3])
		. is_equal(12)
	)
	(
		assert_int(_weld(verts).size())
		. append_failure_message("a box has 8 corners once welded by position")
		. is_equal(8)
	)
	(
		assert_int(int(report.get("planar_patches", -1)))
		. append_failure_message("a box is six flat faces")
		. is_equal(6)
	)


func test_a_plain_box_keeps_its_exact_area_and_volume() -> void:
	# Straightening a staircase does not merely look better, it measures better: the grid
	# silhouette of a flat face is longer than the face, so the old mesh over-read its own area.
	var report: Dictionary = _bake_box(0.0, 0.0)
	var size: Vector3 = _box_size(0.0)
	var area: float = 2.0 * (size.x * size.y + size.y * size.z + size.z * size.x)
	var volume: float = size.x * size.y * size.z
	(
		assert_float(report["area_m2"])
		. append_failure_message("box surface area is wrong")
		. is_equal_approx(area, 0.01)
	)
	assert_float(report["volume_m3"]).append_failure_message("box volume is wrong").is_equal_approx(
		volume, 0.01
	)


func test_every_box_vertex_is_exactly_on_the_box() -> void:
	# Dual Contouring is allowed a third of a cell here (see TestDualContouring); after snapping
	# to the planes that meet at it, a corner is on the corner, not near it.
	var size: Vector3 = _box_size(0.0)
	var half: Vector3 = size * 0.5
	var report: Dictionary = _bake_box(0.0, 0.0)
	var verts: PackedVector3Array = (report["mesh"] as ArrayMesh).surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX
	]
	var worst: float = 0.0
	for v: Vector3 in verts:
		var d: Vector3 = v.abs() - half
		worst = maxf(worst, maxf(d.x, maxf(d.y, d.z)))
	(
		assert_float(worst)
		. append_failure_message("a box vertex sits %.5f m off the box surface" % [worst])
		. is_less(CELL_M * 0.02)
	)


# --- nothing was broken getting there ---------------------------------------------------------


func test_the_simplified_shell_is_closed() -> void:
	# The failure this whole design is arranged around. Per-patch vertex copies make an index
	# based edge count meaningless, so edges are counted after a positional weld: a closed
	# surface uses every edge exactly twice, once in each direction.
	for round_v: float in [0.0, 0.02]:
		for thickness: float in [0.0, 0.4]:
			var report: Dictionary = _bake_box(round_v, thickness)
			var counts: Dictionary = _edge_counts(report["mesh"] as ArrayMesh)
			(
				assert_int(counts["open"])
				. append_failure_message(
					(
						"round=%.2f T=%.2f left %d open edges - the shell has a hole in it"
						% [round_v, thickness, counts["open"]]
					)
				)
				. is_equal(0)
			)
			(
				assert_int(counts["unmatched"])
				. append_failure_message(
					(
						"round=%.2f T=%.2f left %d edges whose two uses wind the same way"
						% [round_v, thickness, counts["unmatched"]]
					)
				)
				. is_equal(0)
			)


func test_a_cylinder_is_not_flattened_into_a_box() -> void:
	# The guard on absorption. Sub-cell detail beside a face gets pulled into that face; a
	# genuinely curved surface must not be, and the honest way to ask is by volume - a cylinder
	# flattened onto its own bounding planes would gain about 27% of its volume.
	var doc: ShipDoc = ShipDoc.create_new(_tube_family, _tube_mfr, _data)
	var root: ShipPart = doc.parts[doc.root]
	root.scale = Vector3.ONE
	var cfg: ShipConfig = _cfg(0.0)
	var sdf: ShipSdf = ShipSdf.build(doc, _data, cfg)
	var size: Vector3 = sdf.aabb().abs().size
	var report: Dictionary = HullBake.bake(sdf, cfg, 0.0)
	var cylinder: float = PI * (size.x * 0.5) * (size.z * 0.5) * size.y
	var boxed: float = size.x * size.y * size.z
	(
		assert_float(report["volume_m3"])
		. append_failure_message(
			(
				(
					"a cylinder baked to %.3f m3; it should be near %.3f, and %.3f would mean it was "
					+ "absorbed into its own bounding planes"
				)
				% [report["volume_m3"], cylinder, boxed]
			)
		)
		. is_equal_approx(cylinder, cylinder * 0.12)
	)


func test_a_bored_doorway_survives_retriangulation() -> void:
	# The hole-bridging path, which is the riskiest code in the file: a face with a doorway is
	# retriangulated from an outer loop plus a hole, and a bridge that fails silently would
	# simply pave the opening over. Asked as a ray down the seam axis - it must pass through
	# the module without ever hitting the cut face.
	var built: Dictionary = _seam_doc()
	var sdf: ShipSdf = built["sdf"]
	var child_id: String = built["child"]
	var cfg: ShipConfig = built["cfg"]
	var seam: Dictionary = {}
	for record: Dictionary in sdf.seams():
		if record[ShipSeams.SEAM_CHILD] == child_id:
			seam = record
	assert_bool(seam.is_empty()).append_failure_message("the child made no seam").is_false()

	var report: Dictionary = HullBake.bake(sdf.module_view(child_id), cfg, 0.0)
	var mesh: ArrayMesh = report["mesh"]
	assert_int(mesh.get_surface_count()).is_greater(0)
	var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
	var axis: Vector3 = frame.basis.z.normalized()
	var through: int = _ray_hits(mesh, frame.origin - axis * 50.0, axis, frame.origin, CELL_M)
	(
		assert_int(through)
		. append_failure_message(
			(
				"the doorway was paved over: %d triangles block the seam axis at the opening"
				% [through]
			)
		)
		. is_equal(0)
	)
	# The other half of the claim. A bridge that failed by deleting the whole face would also
	# pass the test above, so the wall BESIDE the door - 0.6 m off axis, past the 0.4 m half
	# width of the opening - has to still be there.
	var beside: Vector3 = frame.origin + frame.basis.x.normalized() * 0.6
	var wall: int = _ray_hits(mesh, beside - axis * 50.0, axis, beside, CELL_M)
	(
		assert_int(wall)
		. append_failure_message("the cut face beside the doorway went missing entirely")
		. is_greater(0)
	)


func test_the_same_document_bakes_to_the_same_mesh() -> void:
	# Determinism is a gate, not a feature (AGENTS 8b). Simplification walks dictionaries and
	# grows patches from a seed order, either of which could drift between runs.
	var first: Dictionary = _bake_box(0.02, 0.4)
	var second: Dictionary = _bake_box(0.02, 0.4)
	var a: Array = (first["mesh"] as ArrayMesh).surface_get_arrays(0)
	var b: Array = (second["mesh"] as ArrayMesh).surface_get_arrays(0)
	(
		assert_bool(
			(
				(a[Mesh.ARRAY_VERTEX] as PackedVector3Array)
				== (b[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			)
		)
		. append_failure_message("two bakes of one document produced different vertices")
		. is_true()
	)
	(
		assert_bool(
			(a[Mesh.ARRAY_INDEX] as PackedInt32Array) == (b[Mesh.ARRAY_INDEX] as PackedInt32Array)
		)
		. append_failure_message("two bakes of one document produced different indices")
		. is_true()
	)


func test_an_empty_field_still_returns_an_empty_mesh() -> void:
	var out: Dictionary = HullSimplify.simplify(
		null, PackedVector3Array(), PackedInt32Array(), 0.0, CELL_M
	)
	assert_int((out["indices"] as PackedInt32Array).size()).is_equal(0)
	assert_int(int(out["planar_patches"])).is_equal(0)


# --- helpers ----------------------------------------------------------------------------------


func _cfg(thickness: float) -> ShipConfig:
	var cfg: ShipConfig = ShipConfig.from_dict(_data.config.snapshot())
	cfg.bake_cell_m = CELL_M
	cfg.hull_thickness_m = thickness
	return cfg


## A one-part box document with the given corner round, baked. Every other micro-detail op is
## zeroed so the true surface is an exact box and any deviation is the mesher's.
func _bake_box(round_v: float, thickness: float) -> Dictionary:
	var cfg: ShipConfig = _cfg(thickness)
	return HullBake.bake(_box_sdf(round_v, cfg), cfg, 0.0)


func _box_sdf(round_v: float, cfg: ShipConfig) -> ShipSdf:
	var doc: ShipDoc = ShipDoc.create_new(_box_family, _box_mfr, _data)
	var root: ShipPart = doc.parts[doc.root]
	var params: Dictionary = ShapeGen.default_params(_data, _box_family, _box_mfr)
	for key: String in params.keys():
		if typeof(params[key]) == TYPE_FLOAT or typeof(params[key]) == TYPE_INT:
			params[key] = 0.0
	params["round"] = round_v
	root.params = ShapeGen.clamp_params(_data, _box_family, _box_mfr, params)
	root.scale = Vector3.ONE
	return ShipSdf.build(doc, _data, cfg)


func _box_size(round_v: float) -> Vector3:
	return _box_sdf(round_v, _cfg(0.0)).aabb().abs().size


## A parent box with a child box standing on it, and the field they make - the seam case the
## doorway test bores through.
func _seam_doc() -> Dictionary:
	var cfg: ShipConfig = _cfg(0.4)
	var doc: ShipDoc = ShipDoc.create_new(_box_family, _box_mfr, _data, cfg.root_span_m)
	var child: ShipPart = ShipPart.new()
	child.parent = doc.root
	child.family = _box_family
	child.manufacturer = _box_mfr
	child.params = ShapeGen.default_params(_data, _box_family, _box_mfr)
	child.scale = Vector3(2.0, 2.0, 2.0)
	child.offset = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, doc.parts[doc.root]),
		ShipAttach.resolve_shapes_for_part(doc, _data, cfg, child),
		child,
		cfg
	)
	var child_id: String = doc.add_part(child)
	# A seam is a WALL unless a joint says otherwise, and a wall has no opening to preserve -
	# so the joint is authored explicitly. The thickness matters too: the puck bores the doorway
	# through the plate, and at zero thickness there is no plate, only a 0.02 m dimple.
	var joint: ShipJoint = ShipJoint.new()
	joint.id = doc.new_joint_id()
	joint.a = doc.root if doc.root <= child_id else child_id
	joint.b = child_id if doc.root <= child_id else doc.root
	joint.mode = ShipJoint.MODE_DOORWAY
	doc.joints[joint.id] = joint
	return {"sdf": ShipSdf.build(doc, _data, cfg), "child": child_id, "cfg": cfg}


## Distinct vertex positions, quantised to [constant WELD_M].
func _weld(verts: PackedVector3Array) -> Dictionary:
	var out: Dictionary = {}
	for v: Vector3 in verts:
		out[_weld_key(v)] = true
	return out


func _weld_key(v: Vector3) -> String:
	var q: float = 1.0 / WELD_M
	return "%d_%d_%d" % [roundi(v.x * q), roundi(v.y * q), roundi(v.z * q)]


## Edges of a mesh after a positional weld, as
## `{ "open": int, "unmatched": int }` - open edges are used once, unmatched ones are used twice
## the same way round rather than once each way.
func _edge_counts(mesh: ArrayMesh) -> Dictionary:
	if mesh.get_surface_count() == 0:
		return {"open": 0, "unmatched": 0}
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var ids: Dictionary = {}
	var wid: PackedInt32Array = PackedInt32Array()
	wid.resize(verts.size())
	for i: int in verts.size():
		var key: String = _weld_key(verts[i])
		if not ids.has(key):
			ids[key] = ids.size()
		wid[i] = ids[key]

	var n: int = maxi(ids.size(), 1)
	var undirected: Dictionary = {}
	var directed: Dictionary = {}
	var t: int = 0
	while t + 2 < idx.size():
		for e: int in 3:
			var a: int = wid[idx[t + e]]
			var b: int = wid[idx[t + (e + 1) % 3]]
			var uk: int = mini(a, b) * n + maxi(a, b)
			undirected[uk] = int(undirected.get(uk, 0)) + 1
			directed[a * n + b] = int(directed.get(a * n + b, 0)) + 1
		t += 3

	var open_edges: int = 0
	for k: Variant in undirected:
		if int(undirected[k]) == 1:
			open_edges += 1
	var unmatched: int = 0
	for k: Variant in directed:
		var a: int = int(k) / n
		var b: int = int(k) % n
		if int(directed.get(b * n + a, 0)) != int(directed[k]):
			unmatched += 1
	return {"open": open_edges, "unmatched": unmatched}


## How many triangles of [param mesh] the ray from [param origin] along [param dir] hits within
## [param radius] of [param target]. Moller-Trumbore, winding-agnostic.
func _ray_hits(
	mesh: ArrayMesh, origin: Vector3, dir: Vector3, target: Vector3, radius: float
) -> int:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var hits: int = 0
	var t: int = 0
	while t + 2 < idx.size():
		var a: Vector3 = verts[idx[t]]
		var e1: Vector3 = verts[idx[t + 1]] - a
		var e2: Vector3 = verts[idx[t + 2]] - a
		var p: Vector3 = dir.cross(e2)
		var det: float = e1.dot(p)
		t += 3
		if absf(det) < 1.0e-12:
			continue
		var tv: Vector3 = origin - a
		var u: float = tv.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q: Vector3 = tv.cross(e1)
		var v: float = dir.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var dist: float = e2.dot(q) / det
		if dist <= 0.0:
			continue
		if (origin + dir * dist - target).length() <= radius:
			hits += 1
	return hits
