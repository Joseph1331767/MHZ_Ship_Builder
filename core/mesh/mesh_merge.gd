class_name MeshMerge
## Puts a boolean result back into CAD shape: coplanar fragments become one n-gon face, holes
## included, and the points where nothing actually turns are dropped.
##
## WHY A BOOLEAN NEEDS THIS AT ALL. A BSP clips every polygon against every plane of the other
## solid, whether or not the two are anywhere near each other, so a box unioned with a 24-sided
## prism comes out with its faces shredded into ribbons. Measured: a 13-part assembly left
## [MeshCsg] as 8205 faces where about a hundred describe it. The geometry was exact the whole
## time — the boundary representation was not.
##
## TOPOLOGICAL, NOT GEOMETRIC, and that is the point. Faces are grouped by plane, then the
## directed edges of a group are cancelled in pairs: an edge interior to the group is walked once
## in each direction and disappears, and what survives is exactly the group boundary. No new
## vertex is computed and no existing one is moved, so a merge cannot introduce error — which
## matters, because [Vector3] is 32-bit float and every arithmetic step is a chance to lose a
## digit (see [constant MeshCsg.EPS_REL]). A 2D polygon-union library would have been the obvious
## alternative and would have re-quantised every coordinate to do it.
##
## T-JUNCTIONS FIRST, THOUGH. Cancellation only works if both sides of an edge are split the same
## way, and a boolean routinely splits one side and not the other: the result is geometrically
## closed but topologically torn, which is why a freshly cut mesh reports hundreds of open edges.
## [method repair_t_junctions] inserts the missing vertices before anything is cancelled.
##
## Pure data (SPEC §12): static-only, no [Node], no [SceneTree], no [code]res://[/code].
## Arguments are never mutated.

## Two faces share a plane when their normals agree to this and their offsets to
## [constant PLANE_DIST_REL] of the mesh extent.
const PLANE_COS: float = 0.9999
const PLANE_DIST_REL: float = 1.0e-5

## A vertex this close to an edge, relative to the mesh extent, is ON it and gets spliced in.
const ON_EDGE_REL: float = 1.0e-5

## A boundary vertex whose neighbours pass this close to it is not a corner, relative to the mesh
## extent. Kept tighter than a hair above [constant ON_EDGE_REL]: a point the T-junction pass just
## decided lies ON an edge is by definition not a corner of that edge, and the two tolerances
## disagreeing would put one back as fast as the other took it out.
const COLLINEAR_REL: float = 2.0e-5

## A merged group may cover a different area than the faces it replaced only by mistake, so the
## two are compared and a group that does not match is put back exactly as it came.
##
## THIS IS A TIDYING PASS AND MUST NEVER MAKE A SOLID WORSE. Merging is worth doing for the face
## count and the wireframe, and worth nothing at all if it can quietly open a hull; where the ring
## walk cannot reproduce a group faithfully, the honest answer is more faces. Falling back per
## GROUP rather than per mesh keeps the damage to the one face that could not be rebuilt instead
## of costing the whole part its n-gons.
const AREA_MATCH_REL: float = 1.0e-4

## Cells across the longest axis of the vertex grid the T-junction pass searches. Only a bucket
## size: too coarse costs time, too fine costs memory, neither changes the answer.
const GRID_STEPS: int = 48


## [param mesh] with every run of coplanar faces rebuilt as one n-gon, holes and all.
static func merge(mesh: PolyMesh) -> PolyMesh:
	if mesh == null or mesh.is_empty():
		return PolyMesh.new() if mesh == null else mesh.duplicate_mesh()
	var fixed: PolyMesh = repair_t_junctions(mesh)
	var extent: float = maxf(fixed.aabb().size.length(), 1.0e-6)

	# TWO PASSES, AND THE SECOND ONE IS WHY. Dropping a vertex where a boundary does not actually
	# turn is what stops a merged face carrying a corner at every point some neighbour happened to
	# be split at. But that decision CANNOT be taken per face: if this face finds a vertex
	# collinear and drops it while the face on the other side of that edge still uses it, the edge
	# spans a point its neighbour stops at, and the T-junction the repair above just fixed is put
	# straight back. Measured: a hull with two collars welded on repaired to 0 open edges and came
	# out of a per-face drop with 46. So every ring is collected first, and a vertex survives if
	# ANY ring that uses it actually turns there.
	# THREE PASSES, AND THE ORDER IS THE WHOLE DESIGN.
	#
	# 1. Walk each coplanar group into boundary rings, and CHECK each one by area against the
	#    faces it would replace. A group that does not match is rejected here, before anything
	#    else has been decided about it.
	# 2. Decide which vertices survive - globally. A merged face should not carry a corner at
	#    every point some neighbour happened to be split at, but that decision cannot be taken
	#    per face: drop a vertex here while the face across the edge keeps it and the T-junction
	#    the repair just fixed goes straight back in. Measured: a hull with two collars welded on
	#    repaired to 0 open edges and came out of a per-face drop with 46. So a vertex survives
	#    if ANY ring turns at it - and every vertex of a REJECTED group survives too, which is
	#    why rejection has to be settled first. A rejected group keeps its original faces, and
	#    those faces still have to meet their merged neighbours vertex for vertex.
	# 3. Emit.
	var tol: float = extent * COLLINEAR_REL
	var groups: Array = []
	for group: Variant in _coplanar_components(fixed, extent):
		var members: PackedInt32Array = group
		var plane: Plane = fixed.face_plane(members[0])
		var rings: Array = _rings_of(fixed, members)
		var ok: bool = not rings.is_empty() and _rings_match(fixed, rings, members, plane)
		groups.append({"rings": rings, "plane": plane, "members": members, "ok": ok})

	var keep: Dictionary = {}
	for entry: Variant in groups:
		var record: Dictionary = entry
		if bool(record["ok"]):
			for ring: Variant in record["rings"] as Array:
				_mark_corners(fixed, ring as PackedInt32Array, tol, keep)
			continue
		for index: int in record["members"] as PackedInt32Array:
			for loop: Variant in _loops_of(fixed, index):
				for id: int in loop as PackedInt32Array:
					keep[id] = true

	var out: PolyMesh = PolyMesh.new()
	out.vertices = fixed.vertices.duplicate()
	for entry: Variant in groups:
		var record: Dictionary = entry
		if bool(record["ok"]):
			_emit_rings(fixed, record["rings"] as Array, record["plane"] as Plane, keep, out)
			continue
		for index: int in record["members"] as PackedInt32Array:
			out.add_face(fixed.faces[index].duplicate(), fixed.holes_of(index).duplicate())
	return _compacted(out)


## [param mesh] with a vertex spliced into every edge that another vertex lies on.
##
## The repair a boolean always needs. Splitting a face against a plane puts a new vertex on the
## shared edge of one neighbour and not the other, so the two no longer agree about where that
## edge begins and ends — geometrically identical, topologically torn.
static func repair_t_junctions(mesh: PolyMesh) -> PolyMesh:
	var out: PolyMesh = PolyMesh.new()
	out.vertices = mesh.vertices.duplicate()
	var box: AABB = mesh.aabb()
	var extent: float = maxf(box.size.length(), 1.0e-6)
	var tol: float = extent * ON_EDGE_REL
	var cell: float = maxf(box.size[box.size.max_axis_index()] / float(GRID_STEPS), tol * 4.0)
	var grid: Dictionary = _vertex_grid(mesh.vertices, cell)

	for index: int in mesh.faces.size():
		var outer: PackedInt32Array = _split_edges(mesh, mesh.faces[index], grid, cell, tol)
		var holes: Array = []
		for hole: Variant in mesh.holes_of(index):
			holes.append(_split_edges(mesh, hole as PackedInt32Array, grid, cell, tol))
		if outer.size() >= 3:
			out.add_face(outer, holes)
	return out


# --- internals ---------------------------------------------------------------------------------


## Faces grouped into CONNECTED coplanar runs: a flood fill across shared edges that only
## crosses into a neighbour lying in the same plane.
##
## RETIRED(2026-09-03): _group_by_plane(), which collected faces by plane alone and found the
## plane by scanning a list of the planes seen so far. That is O(faces x distinct planes), and a
## boolean between two solids that meet tangentially produces thousands of both - measured, it was
## the reason a twelve-part assembly never finished, not the boolean it was blamed on.
##
## Connectivity is also the more correct question. Two faces that share a plane but sit at
## opposite ends of a ship are not one face and must not be merged into one; only faces that
## actually touch can become a single n-gon.
static func _coplanar_components(mesh: PolyMesh, extent: float) -> Array:
	var neighbours: Dictionary = _edge_faces(mesh)
	var dist_tol: float = extent * PLANE_DIST_REL
	var planes: Array[Plane] = []
	for index: int in mesh.faces.size():
		planes.append(mesh.face_plane(index))

	var seen: PackedInt32Array = PackedInt32Array()
	seen.resize(mesh.faces.size())
	seen.fill(0)
	var out: Array = []
	for start: int in mesh.faces.size():
		if seen[start] == 1 or planes[start].normal == Vector3.ZERO:
			continue
		var plane: Plane = planes[start]
		var group: PackedInt32Array = PackedInt32Array([start])
		seen[start] = 1
		var frontier: PackedInt32Array = PackedInt32Array([start])
		while not frontier.is_empty():
			var face: int = frontier[frontier.size() - 1]
			frontier.remove_at(frontier.size() - 1)
			for other: int in _neighbours_of(mesh, face, neighbours):
				if seen[other] == 1 or planes[other].normal == Vector3.ZERO:
					continue
				if (
					planes[other].normal.dot(plane.normal) <= PLANE_COS
					or absf(planes[other].d - plane.d) >= dist_tol
				):
					continue
				seen[other] = 1
				group.append(other)
				frontier.append(other)
		out.append(group)
	return out


## Undirected edge -> the faces using it.
static func _edge_faces(mesh: PolyMesh) -> Dictionary:
	var out: Dictionary = {}
	var stride: int = maxi(mesh.vertices.size(), 1)
	for index: int in mesh.faces.size():
		for loop: Variant in _loops_of(mesh, index):
			var ring: PackedInt32Array = loop
			for i: int in ring.size():
				var a: int = ring[i]
				var b: int = ring[(i + 1) % ring.size()]
				var key: int = mini(a, b) * stride + maxi(a, b)
				var list: PackedInt32Array = out.get(key, PackedInt32Array())
				list.append(index)
				out[key] = list
	return out


static func _neighbours_of(mesh: PolyMesh, index: int, edge_faces: Dictionary) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	# Deduplicated through a Dictionary rather than PackedInt32Array.has(), which is a linear
	# scan: a face on a shredded hub can touch dozens of neighbours and the scan is quadratic.
	var seen: Dictionary = {}
	var stride: int = maxi(mesh.vertices.size(), 1)
	for loop: Variant in _loops_of(mesh, index):
		var ring: PackedInt32Array = loop
		for i: int in ring.size():
			var a: int = ring[i]
			var b: int = ring[(i + 1) % ring.size()]
			var key: int = mini(a, b) * stride + maxi(a, b)
			for face: int in edge_faces.get(key, PackedInt32Array()) as PackedInt32Array:
				if face != index and not seen.has(face):
					seen[face] = true
					out.append(face)
	return out


## The boundary rings of one coplanar group, as vertex-id loops.
static func _rings_of(mesh: PolyMesh, group: PackedInt32Array) -> Array:
	if group.size() == 1 and mesh.holes_of(group[0]).is_empty():
		return [mesh.faces[group[0]].duplicate()]

	# Cancel directed edges: an edge interior to the group is walked once each way and vanishes.
	var count: Dictionary = {}
	var stride: int = mesh.vertices.size()
	for index: int in group:
		for loop: Variant in _loops_of(mesh, index):
			var ring: PackedInt32Array = loop
			for i: int in ring.size():
				var key: int = ring[i] * stride + ring[(i + 1) % ring.size()]
				count[key] = int(count.get(key, 0)) + 1
	var outgoing: Dictionary = {}
	for key: Variant in count:
		var a: int = int(key) / stride
		var b: int = int(key) % stride
		if count.has(b * stride + a):
			continue
		var list: PackedInt32Array = outgoing.get(a, PackedInt32Array())
		list.append(b)
		outgoing[a] = list

	return _chain(outgoing)


## True when [param rings] enclose the same area as the faces they would replace.
##
## THE MERGE IS A TIDYING PASS AND MUST NEVER MAKE A SOLID WORSE. It is worth doing for the face
## count and for the wireframe, and worth nothing at all if it can quietly open a hull, so a group
## the ring walk cannot reproduce faithfully keeps the faces it had. Area catches every way the
## walk can go wrong at once - a ring chained through the wrong branch at a pinch, a loop dropped,
## a hole taken for a boundary - and none of them can cancel out.
static func _rings_match(
	mesh: PolyMesh, rings: Array, members: PackedInt32Array, plane: Plane
) -> bool:
	var frame: Array = PolyMesh._plane_basis(plane.normal)
	var u: Vector3 = frame[0]
	var w: Vector3 = frame[1]
	var walked: float = 0.0
	for ring: Variant in rings:
		walked += _signed_area(mesh, ring as PackedInt32Array, u, w)
	var original: float = 0.0
	for index: int in members:
		for loop: Variant in _loops_of(mesh, index):
			original += _signed_area(mesh, loop as PackedInt32Array, u, w)
	return absf(walked - original) <= maxf(absf(original), 1.0) * AREA_MATCH_REL


## Marks in [param keep] every vertex of [param ring] where the boundary actually turns.
##
## A vertex is only ever ADDED here, never removed, so one ring finding a corner is enough to
## save it for every other ring that shares it.
static func _mark_corners(
	mesh: PolyMesh, ring: PackedInt32Array, tol: float, keep: Dictionary
) -> void:
	var n: int = ring.size()
	if n < 3:
		for id: int in ring:
			keep[id] = true
		return
	for i: int in n:
		var prev: Vector3 = mesh.vertices[ring[(i - 1 + n) % n]]
		var here: Vector3 = mesh.vertices[ring[i]]
		var next: Vector3 = mesh.vertices[ring[(i + 1) % n]]
		var span: Vector3 = next - prev
		var len: float = span.length()
		var off: float = (
			(here - prev).length() if len <= 1.0e-12 else span.cross(here - prev).length() / len
		)
		if off > tol:
			keep[ring[i]] = true


## Splits the surviving rings into outer boundaries and holes, and adds them to [param out].


static func _emit_rings(
	mesh: PolyMesh, rings: Array, plane: Plane, keep: Dictionary, out: PolyMesh
) -> void:
	var frame: Array = PolyMesh._plane_basis(plane.normal)
	var u: Vector3 = frame[0]
	var w: Vector3 = frame[1]
	var flat: Array = []
	var areas: PackedFloat32Array = PackedFloat32Array()
	var kept: Array = []
	for ring: Variant in rings:
		var ids: PackedInt32Array = ring
		var loop: PackedVector2Array = PackedVector2Array()
		for id: int in ids:
			loop.append(Vector2(mesh.vertices[id].dot(u), mesh.vertices[id].dot(w)))
		# Keep only the points some ring actually turns at - decided globally, above, so both
		# sides of every shared edge drop exactly the same vertices.
		var trimmed_ids: PackedInt32Array = PackedInt32Array()
		var trimmed: PackedVector2Array = PackedVector2Array()
		for i: int in ids.size():
			if keep.has(ids[i]):
				trimmed_ids.append(ids[i])
				trimmed.append(loop[i])
		if trimmed_ids.size() < 3:
			continue
		kept.append(trimmed_ids)
		flat.append(trimmed)
		areas.append(Poly2D.signed_area(trimmed))

	# Anticlockwise about the plane normal is an outer boundary; the other sense is a hole.
	for i: int in kept.size():
		if areas[i] <= 0.0:
			continue
		var holes: Array = []
		for j: int in kept.size():
			if j == i or areas[j] >= 0.0:
				continue
			if Poly2D.contains(flat[i], (flat[j] as PackedVector2Array)[0]):
				holes.append(kept[j])
		out.add_face(kept[i], holes)


## Twice the signed area of [param loop] projected into the ([param u], [param w]) frame, halved.
static func _signed_area(mesh: PolyMesh, loop: PackedInt32Array, u: Vector3, w: Vector3) -> float:
	var total: float = 0.0
	var n: int = loop.size()
	for i: int in n:
		var a: Vector3 = mesh.vertices[loop[i]]
		var b: Vector3 = mesh.vertices[loop[(i + 1) % n]]
		total += a.dot(u) * b.dot(w) - b.dot(u) * a.dot(w)
	return total * 0.5


## Walks the surviving directed edges into closed rings.
static func _chain(outgoing: Dictionary) -> Array:
	var out: Array = []
	var guard: int = 0
	for key: Variant in outgoing:
		while not (outgoing[key] as PackedInt32Array).is_empty() and guard < 1_000_000:
			var ring: PackedInt32Array = PackedInt32Array()
			var cur: int = key
			var closed: bool = false
			while guard < 1_000_000:
				guard += 1
				var nexts: PackedInt32Array = outgoing.get(cur, PackedInt32Array())
				if nexts.is_empty():
					break
				var nxt: int = nexts[0]
				nexts.remove_at(0)
				outgoing[cur] = nexts
				ring.append(cur)
				cur = nxt
				if cur == key:
					closed = true
					break
			if closed and ring.size() >= 3:
				out.append(ring)
	return out


static func _loops_of(mesh: PolyMesh, index: int) -> Array:
	var out: Array = [mesh.faces[index]]
	out.append_array(mesh.holes_of(index))
	return out


## [param loop] with every vertex that lies on one of its edges spliced into that edge.
static func _split_edges(
	mesh: PolyMesh, loop: PackedInt32Array, grid: Dictionary, cell: float, tol: float
) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var n: int = loop.size()
	for i: int in n:
		var ia: int = loop[i]
		var ib: int = loop[(i + 1) % n]
		out.append(ia)
		var a: Vector3 = mesh.vertices[ia]
		var b: Vector3 = mesh.vertices[ib]
		var span: Vector3 = b - a
		var len2: float = span.length_squared()
		if len2 <= 1.0e-18:
			continue
		var found: Array[float] = []
		var ids: Array[int] = []
		for id: int in _near_segment(grid, cell, a, b, tol):
			if id == ia or id == ib:
				continue
			var p: Vector3 = mesh.vertices[id]
			var t: float = (p - a).dot(span) / len2
			if t <= 0.0 or t >= 1.0:
				continue
			if (p - (a + span * t)).length() > tol:
				continue
			found.append(t)
			ids.append(id)
		# Along the edge, nearest first, so the loop keeps its order.
		for pass_i: int in found.size():
			for j: int in range(found.size() - 1 - pass_i):
				if found[j] > found[j + 1]:
					var ft: float = found[j]
					found[j] = found[j + 1]
					found[j + 1] = ft
					var fi: int = ids[j]
					ids[j] = ids[j + 1]
					ids[j + 1] = fi
		for id: int in ids:
			out.append(id)
	return out


## Vertex ids bucketed into a uniform grid, for the on-edge search.
static func _vertex_grid(vertices: PackedVector3Array, cell: float) -> Dictionary:
	var out: Dictionary = {}
	for i: int in vertices.size():
		var key: int = _cell_key(vertices[i], cell)
		var bucket: PackedInt32Array = out.get(key, PackedInt32Array())
		bucket.append(i)
		out[key] = bucket
	return out


## Candidate vertices near the segment [param a]-[param b]: everything in the grid cells its
## bounding box touches, grown by [param tol].
static func _near_segment(
	grid: Dictionary, cell: float, a: Vector3, b: Vector3, tol: float
) -> PackedInt32Array:
	var box: AABB = AABB(a, Vector3.ZERO).expand(b).grow(tol + cell)
	var lo: Vector3i = Vector3i(
		floori(box.position.x / cell), floori(box.position.y / cell), floori(box.position.z / cell)
	)
	var hi: Vector3i = Vector3i(
		floori((box.position.x + box.size.x) / cell),
		floori((box.position.y + box.size.y) / cell),
		floori((box.position.z + box.size.z) / cell)
	)
	var out: PackedInt32Array = PackedInt32Array()
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var key: int = PolyMesh.cell_hash(x, y, z)
				if grid.has(key):
					out.append_array(grid[key] as PackedInt32Array)
	return out


static func _cell_key(p: Vector3, cell: float) -> int:
	return PolyMesh.cell_hash(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))


## [param mesh] with vertices no face references any more removed.
static func _compacted(mesh: PolyMesh) -> PolyMesh:
	var remap: PackedInt32Array = PackedInt32Array()
	remap.resize(mesh.vertices.size())
	remap.fill(-1)
	var out: PolyMesh = PolyMesh.new()
	for index: int in mesh.faces.size():
		var loops: Array = []
		for loop: Variant in _loops_of(mesh, index):
			var ring: PackedInt32Array = PackedInt32Array()
			for id: int in loop as PackedInt32Array:
				if remap[id] < 0:
					remap[id] = out.vertices.size()
					out.vertices.append(mesh.vertices[id])
				ring.append(remap[id])
			loops.append(ring)
		out.add_face(loops[0], loops.slice(1))
	return out
