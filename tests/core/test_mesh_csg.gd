# Exact solid booleans — PolyMesh and MeshCsg. "we want exact mesh operations as our current
# method is not exact."
#
# Volume is the assertion of choice throughout, because it is the one number that catches every
# way a boolean can go wrong at once: a dropped face, a face left inside, an inverted winding and
# a lost operand all move it, and none of them can cancel out. Where a shape is a polygon
# approximation of a curve the expected value is computed from the POLYGON, not from pi, so the
# tolerance stays exact rather than becoming a fudge factor.
class_name TestMeshCsg
extends GdUnitTestSuite

## Volumes are compared this tightly on purpose: these are analytic operations, and anything
## looser would let a real defect through as "close enough".
const EXACT_M3: float = 1.0e-5


func test_a_box_is_six_faces_and_eight_corners() -> void:
	var box: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	assert_int(box.face_count()).is_equal(6)
	assert_int(box.vertices.size()).is_equal(8)
	assert_int(box.open_edges()).append_failure_message("a box is a closed solid").is_equal(0)
	assert_float(box.volume()).is_equal_approx(8.0, EXACT_M3)
	assert_float(box.area()).is_equal_approx(24.0, EXACT_M3)


func test_two_flush_boxes_union_into_one_solid() -> void:
	# THE case this builder makes constantly: parts are placed flush ON the surface of other
	# parts (SPEC section 3), so a seam is a pair of faces sharing a plane exactly. An algorithm
	# that treated coincident faces as a degenerate accident would fail here first.
	var lower: PolyMesh = MeshCsg.box_mesh(Vector3.ONE).transformed(
		Transform3D(Basis.IDENTITY, Vector3(0, -1, 0))
	)
	var upper: PolyMesh = MeshCsg.box_mesh(Vector3.ONE).transformed(
		Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	)
	var out: PolyMesh = MeshCsg.union(lower, upper)
	(
		assert_float(out.volume())
		. append_failure_message("two flush 2 m cubes are one 2x4x2 solid")
		. is_equal_approx(16.0, EXACT_M3)
	)
	assert_int(out.open_edges()).append_failure_message("the union left the solid open").is_equal(0)
	# The shared faces are gone rather than buried inside: four sides doubled, plus a cap each end.
	assert_int(out.face_count()).is_equal(10)


func test_overlapping_boxes_do_not_double_count() -> void:
	var a: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	var b: PolyMesh = MeshCsg.box_mesh(Vector3.ONE).transformed(
		Transform3D(Basis.IDENTITY, Vector3(1, 0, 0))
	)
	var out: PolyMesh = MeshCsg.union(a, b)
	assert_float(out.volume()).is_equal_approx(12.0, EXACT_M3)
	assert_int(out.open_edges()).is_equal(0)


func test_a_union_is_position_independent() -> void:
	# THE REGRESSION TEST FOR THE PRECISION BUG, and the reason MeshCsg recentres its operands.
	# Godot's Vector3 is 32-bit float, so an absolute on-plane epsilon that works at the origin
	# is below the noise a few metres out. Measured before the fix: a 24-gon cylinder at the
	# origin built a correct BSP, the same cylinder at x=1.0 classified its own defining polygon
	# as behind its own plane, the tree recursed to its depth cap, and the box it was unioned
	# with vanished — 27 m3 of solid reported as 1.24. The same shape must behave the same way
	# wherever the ship's origin happens to be.
	var expected: float = 8.0 + _prism_volume(0.4, 1.0, 16)
	for distance: float in [0.0, 1.0, 4.0, 50.0]:
		var box: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
		var stub: PolyMesh = _prism(0.4, 1.0, 16).transformed(
			Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0))
		)
		var shift: Transform3D = Transform3D(Basis.IDENTITY, Vector3(distance, 0, 0))
		var out: PolyMesh = MeshCsg.union(box.transformed(shift), stub.transformed(shift))
		(
			assert_float(out.volume())
			. append_failure_message(
				"a disjoint union %.0f m from the origin lost an operand" % [distance]
			)
			. is_equal_approx(expected, EXACT_M3)
		)


func test_subtracting_a_prism_bores_a_hole() -> void:
	var cube: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	var drill: PolyMesh = _prism(0.4, 3.0, 32)
	var out: PolyMesh = MeshCsg.subtract(cube, drill)
	# The bore is a 32-gon, so the expected volume is the PRISM's, not a cylinder's.
	var removed: float = _prism_volume(0.4, 2.0, 32)
	(
		assert_float(out.volume())
		. append_failure_message("the bore removed the wrong amount of material")
		. is_equal_approx(8.0 - removed, EXACT_M3)
	)


func test_subtracting_something_disjoint_changes_nothing() -> void:
	var cube: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	var away: PolyMesh = MeshCsg.box_mesh(Vector3.ONE).transformed(
		Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	)
	var out: PolyMesh = MeshCsg.subtract(cube, away)
	assert_float(out.volume()).is_equal_approx(8.0, EXACT_M3)
	assert_int(out.open_edges()).is_equal(0)


func test_a_clip_cuts_flat_and_caps() -> void:
	# A module cut at its seam has to come out a SOLID with a flat face, not an open shell.
	var cube: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	var out: PolyMesh = MeshCsg.clip_to_plane(cube, Plane(Vector3.UP, 0.0))
	assert_float(out.volume()).is_equal_approx(4.0, EXACT_M3)
	assert_int(out.open_edges()).append_failure_message("the cut face was not capped").is_equal(0)
	assert_int(out.face_count()).is_equal(6)
	for v: Vector3 in out.vertices:
		(
			assert_bool(v.y <= 1.0e-5)
			. append_failure_message("a vertex survived above the cut")
			. is_true()
		)


func test_faces_stay_planar_through_a_boolean() -> void:
	var cube: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	var out: PolyMesh = MeshCsg.subtract(cube, _prism(0.4, 3.0, 16))
	(
		assert_float(out.worst_planarity())
		. append_failure_message("a boolean produced a face whose vertices are not coplanar")
		. is_less(1.0e-4)
	)


func test_the_array_mesh_faces_outward() -> void:
	# PolyMesh works CCW-outward; Godot's front face is clockwise. That single flip happens in
	# to_array_mesh() and nowhere else, so it is worth an explicit test: get it backwards and
	# every baked hull renders inside out, which back-face culling shows as an invisible ship.
	var mesh: ArrayMesh = MeshCsg.box_mesh(Vector3.ONE).to_array_mesh()
	assert_int(mesh.get_surface_count()).is_equal(1)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var checked: int = 0
	var t: int = 0
	while t + 2 < idx.size():
		var a: Vector3 = verts[idx[t]]
		var rh: Vector3 = (verts[idx[t + 1]] - a).cross(verts[idx[t + 2]] - a)
		var outward: Vector3 = normals[idx[t]]
		# Godot winds a front face clockwise, so the right-hand normal opposes the shading normal.
		(
			assert_float(rh.normalized().dot(outward))
			. append_failure_message("triangle %d is wound the wrong way" % [t / 3])
			. is_less(0.0)
		)
		# And the shading normal must point away from the centre of a box centred on the origin.
		assert_float(outward.dot(a)).is_greater(0.0)
		checked += 1
		t += 3
	assert_int(checked).is_equal(12)


func test_boundary_edges_are_model_edges_only() -> void:
	# A box has twelve edges. A wireframe drawn from triangles would show eighteen - the six
	# face diagonals are triangulation artefacts, and showing them is half of what "janky" meant.
	var edges: PackedInt32Array = MeshCsg.box_mesh(Vector3.ONE).boundary_edges()
	(
		assert_int(edges.size() / 2)
		. append_failure_message("a box has 12 edges, not %d" % [edges.size() / 2])
		. is_equal(12)
	)


func test_an_empty_operand_is_handled() -> void:
	var cube: PolyMesh = MeshCsg.box_mesh(Vector3.ONE)
	var empty: PolyMesh = PolyMesh.new()
	assert_float(MeshCsg.union(cube, empty).volume()).is_equal_approx(8.0, EXACT_M3)
	assert_float(MeshCsg.union(empty, cube).volume()).is_equal_approx(8.0, EXACT_M3)
	assert_float(MeshCsg.subtract(cube, empty).volume()).is_equal_approx(8.0, EXACT_M3)
	assert_bool(MeshCsg.subtract(empty, cube).is_empty()).is_true()
	assert_bool(MeshCsg.intersect(cube, empty).is_empty()).is_true()


# --- helpers ------------------------------------------------------------------------------------


## An n-sided prism about +Y, CCW-outward: side quads plus an n-gon cap at each end.
func _prism(radius: float, height: float, segments: int) -> PolyMesh:
	var h: float = height * 0.5
	var bottom: PackedVector3Array = PackedVector3Array()
	var top: PackedVector3Array = PackedVector3Array()
	for i: int in segments:
		var a: float = TAU * float(i) / float(segments)
		bottom.append(Vector3(cos(a) * radius, -h, sin(a) * radius))
		top.append(Vector3(cos(a) * radius, h, sin(a) * radius))
	var polys: Array = []
	for i: int in segments:
		var j: int = (i + 1) % segments
		polys.append(PackedVector3Array([bottom[i], top[i], top[j], bottom[j]]))
	var cap: PackedVector3Array = top.duplicate()
	cap.reverse()
	polys.append(cap)
	polys.append(bottom.duplicate())
	return PolyMesh.from_polygons(polys)


## Exact volume of that prism - the regular polygon's area times the height.
func _prism_volume(radius: float, height: float, segments: int) -> float:
	return 0.5 * float(segments) * radius * radius * sin(TAU / float(segments)) * height
