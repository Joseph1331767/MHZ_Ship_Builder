class_name PolyMesh
extends RefCounted
## A boundary representation: welded vertices and N-GON faces, the currency of the exact bake.
##
## WHY N-GONS AND NOT TRIANGLES. A box has six faces. Storing it as twelve triangles throws that
## away immediately and there is no honest way to get it back — which is the whole complaint the
## exact bake exists to answer. So a face here is a loop of any length, its edges are the model's
## real edges, and triangulation happens once, at the very end, on the way to an [ArrayMesh].
## [method boundary_edges] is what a wireframe should draw: real edges only, no triangle diagonals.
##
## WINDING IS CCW-OUTWARD IN HERE, and that is NOT the project's rendering convention. Godot's
## front face is clockwise, so [SurfaceNets] and [HullBake] wind a front face so that its
## right-hand normal points INWARD. Carrying that inversion through a BSP tree — where planes are
## flipped and polygons reversed constantly — is how sign errors get in. So this class and
## [MeshCsg] use the mathematical convention throughout (a face's vertices run anticlockwise seen
## from outside; its right-hand normal points OUT) and [method to_array_mesh] performs the single
## flip, in one place, on the way out.
##
## Pure data (SPEC §12): [RefCounted], no [Node], no [SceneTree], no [code]res://[/code].

## Vertices closer than this are the same vertex. Ships are up to 250 m and the finest authored
## feature is ~0.01 m (SPEC §12), so a micrometre is far below anything real and far above the
## float noise that CSG splitting leaves on a coincident face.
const WELD_M: float = 1.0e-6

## A face's vertices must lie within this of its own plane to be believed.
const PLANAR_TOL_M: float = 1.0e-5

## Spatial-hash multipliers. The classic Teschner triple: three large primes mixed with XOR, which
## scatters neighbouring cells into unrelated buckets instead of adjacent ones.
##
## COLLISIONS ARE HARMLESS HERE and that is why a hash is safe where a unique key is not. Every
## lookup that uses one finishes with an exact test - a distance for a weld, a point-on-segment for
## a T-junction - so a collision costs one extra comparison and can never change an answer. What it
## replaces is a formatted STRING key, which is correct too and was the single largest cost in the
## bake: interning one vertex probes 27 neighbouring cells, so a 500-vertex boolean result was
## building thirteen thousand strings.
const HASH_X: int = 73856093
const HASH_Y: int = 19349663
const HASH_Z: int = 83492791

## Vertices in ship-space metres.
var vertices: PackedVector3Array = PackedVector3Array()

## Faces as index loops into [member vertices], anticlockwise seen from outside.
var faces: Array[PackedInt32Array] = []

## Hole loops, keyed by face index - a face absent from here is simply solid. Sparse on purpose:
## almost every face is a plain loop, and making holes a parallel array would put an empty entry
## beside each one and invite callers to forget the distinction.
##
## A face with holes is what a wall with a doorway bored through it IS (SPEC section 3, ADR 0008).
## Splitting such a face into a fan of simple pieces instead throws away the model real edges -
## the very loss the exact pipeline exists to avoid.
var face_holes: Dictionary = {}

## Set when a [MeshCsg] operation ran out of its split allowance and stopped being exact.
##
## Never true for ordinary geometry. When it is true the mesh is APPROXIMATE - some polygon was
## routed whole to one side of a plane it actually straddles - and a caller that needs a
## trustworthy solid should refuse it rather than bake it.
var truncated: bool = false

## How many loops [method from_polygons] threw away as degenerate. NOT diagnostic noise: a
## dropped loop is a HOLE in a solid that was closed a moment ago, and welding a sliver narrower
## than the weld tolerance is exactly how one appears. Any caller that cares whether its result
## is still a solid has to read this.
var dropped: int = 0


## A mesh welded from a polygon soup — an [Array] of [PackedVector3Array] loops, each already
## wound anticlockwise-outward. Degenerate loops (fewer than three distinct vertices) are dropped
## rather than carried, because every consumer below assumes a face has a plane.
static func from_polygons(polygons: Array, weld_m: float = WELD_M) -> PolyMesh:
	var out: PolyMesh = PolyMesh.new()
	var lookup: Dictionary = {}
	for poly: Variant in polygons:
		var loop: PackedVector3Array = poly
		var face: PackedInt32Array = PackedInt32Array()
		for p: Vector3 in loop:
			var id: int = out._intern(p, lookup, weld_m)
			# Drop a vertex that just repeats the one before it, and the one that closes the loop.
			if face.size() > 0 and face[face.size() - 1] == id:
				continue
			face.append(id)
		while face.size() > 1 and face[0] == face[face.size() - 1]:
			face.remove_at(face.size() - 1)
		if face.size() >= 3:
			out.faces.append(face)
		else:
			out.dropped += 1
	return out


## This mesh as a polygon soup, the form [MeshCsg] works in.
func polygons() -> Array:
	var out: Array = []
	for index: int in faces.size():
		if holes_of(index).is_empty():
			var loop: PackedVector3Array = PackedVector3Array()
			for id: int in faces[index]:
				loop.append(vertices[id])
			out.append(loop)
			continue
		# A BSP polygon has to be SIMPLE, so a face with holes is handed over as triangles. That
		# costs nothing lasting: the boolean fragments faces anyway and MeshMerge rebuilds the
		# n-gons and their holes afterwards.
		var tri: PackedInt32Array = triangulate_face(index)
		var k: int = 0
		while k + 2 < tri.size():
			var corners: PackedVector3Array = PackedVector3Array()
			corners.append(vertices[tri[k]])
			corners.append(vertices[tri[k + 1]])
			corners.append(vertices[tri[k + 2]])
			out.append(corners)
			k += 3
	return out


func duplicate_mesh() -> PolyMesh:
	var out: PolyMesh = PolyMesh.new()
	out.vertices = vertices.duplicate()
	for face: PackedInt32Array in faces:
		out.faces.append(face.duplicate())
	out.face_holes = face_holes.duplicate(true)
	return out


## Every loop of face [param index]: the outer boundary first, then any holes.
func _all_loops(index: int) -> Array:
	var out: Array = [faces[index]]
	out.append_array(holes_of(index))
	return out


func face_count() -> int:
	return faces.size()


func is_empty() -> bool:
	return faces.is_empty()


## The outward plane of face [param index], by Newell's method.
##
## Newell rather than a cross product of the first three vertices: a merged face can easily open
## with three nearly-collinear vertices, where a cross product is numerical noise, and Newell
## averages the whole loop instead.
func face_plane(index: int) -> Plane:
	return plane_of(face_points(index))


## The hole loops of face [param index], or an empty array. Never null.
func holes_of(index: int) -> Array:
	return face_holes.get(index, [])


## Adds a face and returns its index. [param holes] are inner loops, wound against [param outer].
func add_face(outer: PackedInt32Array, holes: Array = []) -> int:
	var index: int = faces.size()
	faces.append(outer)
	if not holes.is_empty():
		face_holes[index] = holes
	return index


## Face [param index] as triangles, given as GLOBAL vertex indices in triples.
##
## The single triangulation path: [method area], [method volume] and [method to_array_mesh] all
## come through here, so a face with a hole cannot be measured one way and drawn another. A face
## with no holes still takes the fan shortcut, which is most faces.
func triangulate_face(index: int) -> PackedInt32Array:
	var outer: PackedInt32Array = faces[index]
	var holes: Array = holes_of(index)
	var out: PackedInt32Array = PackedInt32Array()
	if holes.is_empty():
		for k: int in range(1, outer.size() - 1):
			out.append(outer[0])
			out.append(outer[k])
			out.append(outer[k + 1])
		return out

	var plane: Plane = face_plane(index)
	if plane.normal == Vector3.ZERO:
		return out
	var frame: Array = _plane_basis(plane.normal)
	var u: Vector3 = frame[0]
	var w: Vector3 = frame[1]
	var loops: Array = []
	var flat: PackedInt32Array = PackedInt32Array()
	loops.append(_to_2d_loop(outer, u, w))
	flat.append_array(outer)
	for hole: Variant in holes:
		var ring: PackedInt32Array = hole
		loops.append(_to_2d_loop(ring, u, w))
		flat.append_array(ring)
	var tri: PackedInt32Array = Poly2D.triangulate(loops)
	for i: int in tri.size():
		out.append(flat[tri[i]])
	return out


## An orthonormal (u, w) pair for [param normal], with u cross w = normal, so a loop wound
## anticlockwise about the normal is anticlockwise in the 2D frame too.
static func _plane_basis(normal: Vector3) -> Array:
	var axis: Vector3 = Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	var u: Vector3 = normal.cross(axis).normalized()
	return [u, normal.cross(u)]


func _to_2d_loop(loop: PackedInt32Array, u: Vector3, w: Vector3) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for id: int in loop:
		out.append(Vector2(vertices[id].dot(u), vertices[id].dot(w)))
	return out


func face_points(index: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for id: int in faces[index]:
		out.append(vertices[id])
	return out


## The outward plane of a loop, by Newell's method. Returns a zero-normal plane for a degenerate
## loop, which every caller must treat as "no plane" rather than as a direction.
static func plane_of(loop: PackedVector3Array) -> Plane:
	var n: int = loop.size()
	if n < 3:
		return Plane(Vector3.ZERO, 0.0)
	var normal: Vector3 = Vector3.ZERO
	var centre: Vector3 = Vector3.ZERO
	for i: int in n:
		var a: Vector3 = loop[i]
		var b: Vector3 = loop[(i + 1) % n]
		normal += Vector3(
			(a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)
		)
		centre += a
	var len: float = normal.length()
	if len < 1.0e-20:
		return Plane(Vector3.ZERO, 0.0)
	normal /= len
	return Plane(normal, normal.dot(centre / float(n)))


## Enclosed volume in cubic metres, by the divergence theorem over a fan of each face.
##
## MEANINGLESS ON AN OPEN MESH, exactly as [method HullBake.mesh_volume] is — the sign of an
## unclosed shell's missing cap has nowhere to come from. Ask [method open_edges] first.
func volume() -> float:
	var total: float = 0.0
	for i: int in faces.size():
		var tri: PackedInt32Array = triangulate_face(i)
		var k: int = 0
		while k + 2 < tri.size():
			total += vertices[tri[k]].dot(vertices[tri[k + 1]].cross(vertices[tri[k + 2]]))
			k += 3
	return absf(total / 6.0)


## Total surface area in square metres. Winding-independent.
func area() -> float:
	var total: float = 0.0
	for i: int in faces.size():
		var tri: PackedInt32Array = triangulate_face(i)
		var k: int = 0
		while k + 2 < tri.size():
			var a: Vector3 = vertices[tri[k]]
			total += (vertices[tri[k + 1]] - a).cross(vertices[tri[k + 2]] - a).length()
			k += 3
	return total * 0.5


## How many directed edges have no opposite twin. Zero on a closed, consistently wound solid,
## which is the only state in which [method volume] means anything.
##
## Counts DIRECTED edges on purpose. An undirected count cannot tell a closed solid from one
## whose two halves are wound the same way and would meet back to back.
func open_edges() -> int:
	var directed: Dictionary = {}
	for index: int in faces.size():
		for loop: Variant in _all_loops(index):
			var ring: PackedInt32Array = loop
			var n: int = ring.size()
			for i: int in n:
				var key: int = ring[i] * vertices.size() + ring[(i + 1) % n]
				directed[key] = int(directed.get(key, 0)) + 1
	var unmatched: int = 0
	for key: Variant in directed:
		var a: int = int(key) / vertices.size()
		var b: int = int(key) % vertices.size()
		if int(directed.get(b * vertices.size() + a, 0)) != int(directed[key]):
			unmatched += 1
	return unmatched


## Every real model edge, once, as vertex-index pairs — what a wireframe draws. Triangulation
## diagonals do not exist at this level, which is the point of keeping faces as n-gons.
func boundary_edges() -> PackedInt32Array:
	var seen: Dictionary = {}
	var out: PackedInt32Array = PackedInt32Array()
	for index: int in faces.size():
		for loop: Variant in _all_loops(index):
			var ring: PackedInt32Array = loop
			var n: int = ring.size()
			for i: int in n:
				var a: int = ring[i]
				var b: int = ring[(i + 1) % n]
				var key: int = mini(a, b) * vertices.size() + maxi(a, b)
				if seen.has(key):
					continue
				seen[key] = true
				out.append(a)
				out.append(b)
	return out


## Furthest any face vertex strays from its own face's plane. A sanity number: a CSG result whose
## faces are not planar has a split bug, and no amount of downstream cleanup will fix it.
func worst_planarity() -> float:
	var worst: float = 0.0
	for i: int in faces.size():
		var plane: Plane = face_plane(i)
		if plane.normal == Vector3.ZERO:
			continue
		for loop: Variant in _all_loops(i):
			for id: int in loop as PackedInt32Array:
				worst = maxf(worst, absf(plane.distance_to(vertices[id])))
	return worst


func aabb() -> AABB:
	if vertices.is_empty():
		return AABB()
	var box: AABB = AABB(vertices[0], Vector3.ZERO)
	for v: Vector3 in vertices:
		box = box.expand(v)
	return box


## Every face transformed by [param xform]. A mirroring transform reverses each loop, so the
## result is still wound anticlockwise-outward rather than inside out.
func transformed(xform: Transform3D) -> PolyMesh:
	var out: PolyMesh = PolyMesh.new()
	out.vertices = PackedVector3Array()
	for v: Vector3 in vertices:
		out.vertices.append(xform * v)
	var flip: bool = xform.basis.determinant() < 0.0
	for index: int in faces.size():
		var copy: PackedInt32Array = faces[index].duplicate()
		if flip:
			copy.reverse()
		var holes: Array = []
		for hole: Variant in holes_of(index):
			var ring: PackedInt32Array = (hole as PackedInt32Array).duplicate()
			if flip:
				ring.reverse()
			holes.append(ring)
		out.add_face(copy, holes)
	return out


## A [Mesh.PRIMITIVE_TRIANGLES] [ArrayMesh], with the single winding flip from this class's
## CCW-outward convention to Godot's clockwise front face. Normals are per-face, so every edge
## of the model is a hard edge — which is what a CAD solid looks like and what the whole exact
## pipeline is for. An empty mesh comes back with no surfaces.
func to_array_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var out_v: PackedVector3Array = PackedVector3Array()
	var out_n: PackedVector3Array = PackedVector3Array()
	var out_i: PackedInt32Array = PackedInt32Array()
	for i: int in faces.size():
		var plane: Plane = face_plane(i)
		if plane.normal == Vector3.ZERO:
			continue
		var tri: PackedInt32Array = triangulate_face(i)
		var local: Dictionary = {}
		var k: int = 0
		while k + 2 < tri.size():
			# Reversed on the way out: this class is CCW-outward, Godot front face is clockwise.
			for slot: int in [0, 2, 1]:
				var id: int = tri[k + slot]
				if not local.has(id):
					local[id] = out_v.size()
					out_v.append(vertices[id])
					out_n.append(plane.normal)
				out_i.append(int(local[id]))
			k += 3
	if out_v.is_empty() or out_i.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_INDEX] = out_i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A [Mesh.PRIMITIVE_LINES] [ArrayMesh] of this mesh MODEL edges - the outline a CAD viewport
## draws.
##
## The whole reason faces are kept as n-gons. A wireframe built from triangles shows every
## triangulation diagonal, so a plain box comes out with eighteen lines instead of twelve and a
## flat face looks criss-crossed for no reason the model can explain. That was half of what
## "janky triangles all over the place" described. This draws [method boundary_edges] instead, so
## a box is twelve lines however it happens to be triangulated on the way to the screen.
func to_wire_mesh() -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	var edges: PackedInt32Array = boundary_edges()
	if edges.is_empty():
		return mesh
	var points: PackedVector3Array = PackedVector3Array()
	for id: int in edges:
		points.append(vertices[id])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


## The index of [param p], adding it if no vertex within [constant WELD_M] exists yet.
##
## Buckets by a quantised key and checks the 27 neighbouring buckets, so two vertices either side
## of a bucket boundary still weld. A plain quantised-key dictionary — the obvious version — welds
## only when both land in the same bucket, which is precisely the case CSG splitting does not
## guarantee.
func _intern(p: Vector3, lookup: Dictionary, weld_m: float = WELD_M) -> int:
	var q: float = 1.0 / maxf(weld_m, 1.0e-12)
	var kx: int = roundi(p.x * q)
	var ky: int = roundi(p.y * q)
	var kz: int = roundi(p.z * q)
	for dx: int in [0, -1, 1]:
		for dy: int in [0, -1, 1]:
			for dz: int in [0, -1, 1]:
				var key: int = cell_hash(kx + dx, ky + dy, kz + dz)
				if not lookup.has(key):
					continue
				for id: int in lookup[key] as PackedInt32Array:
					if vertices[id].distance_squared_to(p) <= weld_m * weld_m:
						return id
	var home: int = cell_hash(kx, ky, kz)
	var bucket: PackedInt32Array = lookup.get(home, PackedInt32Array())
	var index: int = vertices.size()
	vertices.append(p)
	bucket.append(index)
	lookup[home] = bucket
	return index


## Bucket key for integer cell coordinates. See [constant HASH_X].
static func cell_hash(x: int, y: int, z: int) -> int:
	return (x * HASH_X) ^ (y * HASH_Y) ^ (z * HASH_Z)
