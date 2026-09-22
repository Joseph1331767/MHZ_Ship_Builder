class_name MeshClip
extends RefCounted
## Polygon clipping against signed distance functions, and the cut faces that go with it.
##
## THE SEAM PIPELINE'S ONLY GEOMETRIC PRIMITIVE. A cutter is a signed distance function - negative
## inside - and the surface that bounds it. Clipping a polygon against one keeps the part where the
## function is not negative, cut along the zero crossing, each crossing found by bisection on its
## own edge. That is the whole of it: no tree, no split cascade, no classification of one solid's
## polygons against another's tree. It is linear in the polygons, it cannot hang, and it is exact
## to the tessellation and the bisection.
##
## WHY NOT THE BSP (ADR 0019, ADR 0020). csg.js-style booleans meet coplanar faces everywhere two
## tessellations of one primitive lie on the same planes - a shell's own two surfaces, two lathes
## on one axis - and fail them: measured, `outer - inner` on one hydrogen sphere gave 742 open
## edges and a solid module, and a chain of five unions did not finish in 400 s. A distance field
## has no planes to coincide with.
##
## Every function here is static and pure. Polygons are [PackedVector3Array] loops wound
## counter-clockwise seen from outside, which is what [PolyMesh.polygons] hands out.

## Bisection steps per crossing. Twenty halvings of a metre-long edge is a micron.
const BISECT_STEPS: int = 20

## A point this close to a surface is ON it, for the strict-inside tests a rim needs.
const ON_SURFACE_M: float = 1.0e-5

## How close two points have to be to count as one, when the segments a seam is made of are
## chained end to end. Relative to the polygon size a caller hands in.
const CHAIN_REL: float = 1.0e-4

## A segment shorter than this fraction of the polygon size is a touch, not a crossing.
const SEGMENT_REL: float = 1.0e-3


## A signed distance function with the surface that bounds it.
class Cutter:
	extends RefCounted

	## Negative inside, zero on the surface, positive outside.
	var field: Callable
	## The bounding surface, wound outward, for the faces a cut leaves exposed.
	var surface: PolyMesh = null

	static func make(field_in: Callable, surface_in: PolyMesh) -> Cutter:
		var out: Cutter = Cutter.new()
		out.field = field_in
		out.surface = surface_in
		return out

	func distance(p: Vector3) -> float:
		return field.call(p)

	## A cutter over a placed primitive: the distance is the shape's own, in its own frame,
	## scaled back to metres by the transform's smallest axis - the same as [MeshFlange.Piece].
	static func of_shape(shape: ResolvedShape, xform: Transform3D, surface_in: PolyMesh) -> Cutter:
		var inv: Transform3D = xform.affine_inverse()
		var b: Basis = xform.basis
		var scale: float = minf(b.x.length(), minf(b.y.length(), b.z.length()))
		if scale <= 0.000001:
			scale = 1.0
		return make(func(p: Vector3) -> float: return shape.sdf(inv * p) * scale, surface_in)

	## A cutter that is everything BEYOND a plane - the half-space its normal points into.
	static func of_half_space(plane: Plane, extent: float, centre: Vector3) -> Cutter:
		var n: Vector3 = plane.normal.normalized()
		var on: Vector3 = centre - n * plane.distance_to(centre)
		var u: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var w: Vector3 = n.cross(u)
		var quad: PackedVector3Array = PackedVector3Array(
			[
				on - u * extent - w * extent,
				on - u * extent + w * extent,
				on + u * extent + w * extent,
				on + u * extent - w * extent,
			]
		)
		# Outside the half-space is behind the plane, so the surface faces AGAINST the normal.
		var face: PackedVector3Array = quad
		if PolyMesh.plane_of(quad).normal.dot(n) > 0.0:
			face = quad.duplicate()
			face.reverse()
		var mesh: PolyMesh = PolyMesh.from_polygons([face])
		return make(func(p: Vector3) -> float: return -plane.distance_to(p), mesh)

	## A cutter over a CONVEX polyhedron: the greatest of its face-plane distances. Its surface is
	## the polyhedron itself.
	static func of_convex(mesh: PolyMesh) -> Cutter:
		var planes: Array[Plane] = []
		for i: int in mesh.face_count():
			planes.append(mesh.face_plane(i))
		return make(
			func(p: Vector3) -> float:
				var best: float = -INF
				for plane: Plane in planes:
					best = maxf(best, plane.distance_to(p))
				return best,
			mesh
		)


## The polygons of a surface, hashed by where they are, for putting a crossing vertex exactly onto
## the plane of the polygon it crossed.
##
## WHY A CROSSING HAS TO BE SNAPPED. A crossing is found by bisection against a distance field, so
## it lies on the cutter's TRUE surface; the cutter's polygons are chords of that surface, inside
## it by the sagitta of a segment - 6 mm on a tunnel's cylinder, 6 cm on a 9 m sphere. The cutter's
## own side of the seam lies on the chords. Two boundaries that disagree by millimetres never meet
## a repair tolerance of a fifth of one, and every seam came out as hundreds of open edges: "where
## seams exist i can see a gap to the exterior of the hull, very small" (2026-09-05).
##
## The crossing was found ON ITS OWN EDGE, and it stays there: it is slid along that edge onto the
## plane of the nearest polygon of the other surface. It is then on both of its own polygons'
## planes and on the other polygon's plane at once - on the line where the two faces meet - and so
## is every crossing the other side finds by the same rule. Two polylines on one line, and the
## T-junction repair joins them.
class PlaneFinder:
	extends RefCounted

	var _planes: Array[Plane] = []
	var _polys: Array = []
	var _cells: Dictionary = {}
	var _cell: float = 1.0

	## Over [param polys], with a hash cell of about the polygon size.
	static func make(polys: Array) -> PlaneFinder:
		var out: PlaneFinder = PlaneFinder.new()
		var longest: float = 0.0
		for poly: PackedVector3Array in polys:
			for i: int in poly.size():
				longest = maxf(longest, poly[i].distance_to(poly[(i + 1) % poly.size()]))
		out._cell = maxf(longest, 0.05)
		for index: int in polys.size():
			var poly: PackedVector3Array = polys[index]
			if poly.size() < 3:
				continue
			out._polys.append(poly)
			out._planes.append(PolyMesh.plane_of(poly))
			var lo: Vector3 = poly[0]
			var hi: Vector3 = poly[0]
			for v: Vector3 in poly:
				lo = lo.min(v)
				hi = hi.max(v)
			var a: Vector3i = out._key(lo)
			var b: Vector3i = out._key(hi)
			for x: int in range(a.x, b.x + 1):
				for y: int in range(a.y, b.y + 1):
					for z: int in range(a.z, b.z + 1):
						var k: Vector3i = Vector3i(x, y, z)
						var list: PackedInt32Array = out._cells.get(k, PackedInt32Array())
						list.append(out._polys.size() - 1)
						out._cells[k] = list
		return out

	func _key(p: Vector3) -> Vector3i:
		return Vector3i(int(floor(p.x / _cell)), int(floor(p.y / _cell)), int(floor(p.z / _cell)))

	## The plane of the polygon nearest [param p], or a zero plane when none is near.
	func nearest_plane(p: Vector3) -> Plane:
		var k: Vector3i = _key(p)
		var best: int = -1
		var best_d: float = INF
		for x: int in range(k.x - 1, k.x + 2):
			for y: int in range(k.y - 1, k.y + 2):
				for z: int in range(k.z - 1, k.z + 2):
					var list: Variant = _cells.get(Vector3i(x, y, z))
					if list == null:
						continue
					for index: int in list as PackedInt32Array:
						var d: float = _distance_to_polygon(p, index)
						if d < best_d:
							best_d = d
							best = index
		if best < 0:
			return Plane()
		return _planes[best]

	## [param crossing], found on the edge [param a]-[param b], slid along that edge onto the plane
	## of the nearest polygon here. Left where it is when that plane is nowhere near or the slide
	## would leave the edge.
	func onto_line(a: Vector3, b: Vector3, crossing: Vector3) -> Vector3:
		var plane: Plane = nearest_plane(crossing)
		if plane.normal == Vector3.ZERO:
			return crossing
		var dir: Vector3 = b - a
		var denom: float = plane.normal.dot(dir)
		if absf(denom) < 1.0e-9:
			return crossing
		var t: float = (plane.d - plane.normal.dot(a)) / denom
		if t < -1.0e-4 or t > 1.0 + 1.0e-4:
			return crossing
		var snapped: Vector3 = a + dir * clampf(t, 0.0, 1.0)
		# A slide longer than the polygon is not a snap, it is a different crossing.
		if snapped.distance_to(crossing) > _cell:
			return crossing
		return snapped

	func _distance_to_polygon(p: Vector3, index: int) -> float:
		var poly: PackedVector3Array = _polys[index]
		var plane: Plane = _planes[index]
		var foot: Vector3 = p - plane.normal * plane.distance_to(p)
		if _contains(poly, plane.normal, foot):
			return absf(plane.distance_to(p))
		var best: float = INF
		for i: int in poly.size():
			var q: Vector3 = Geometry3D.get_closest_point_to_segment(
				p, poly[i], poly[(i + 1) % poly.size()]
			)
			best = minf(best, p.distance_to(q))
		return best

	static func _contains(poly: PackedVector3Array, normal: Vector3, foot: Vector3) -> bool:
		# Inside a convex-enough polygon when the foot is on the left of every edge.
		for i: int in poly.size():
			var e: Vector3 = poly[(i + 1) % poly.size()] - poly[i]
			if normal.dot(e.cross(foot - poly[i])) < -1.0e-9:
				return false
		return true


## [param poly] cut down to where [param keep] is not negative: the whole polygon, nothing, or the
## polygon trimmed along the zero crossing. A polygon the surface crosses twice comes back as one
## loop with a chord across the removed part, which is right for the small polygons a tessellation
## makes and is the price of not building a tree.
static func clip(poly: PackedVector3Array, keep: Callable, snap: PlaneFinder = null) -> Array:
	var n: int = poly.size()
	if n < 3:
		return []
	var d: PackedFloat64Array = PackedFloat64Array()
	var dropped: int = 0
	for p: Vector3 in poly:
		var v: float = keep.call(p)
		d.append(v)
		if v < 0.0:
			dropped += 1
	if dropped == 0:
		return [poly]
	if dropped == n:
		return []
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in n:
		var j: int = (i + 1) % n
		if d[i] >= 0.0:
			out.append(poly[i])
		if (d[i] < 0.0) != (d[j] < 0.0):
			var crossing: Vector3 = zero_crossing(poly[i], poly[j], keep)
			if snap != null:
				crossing = snap.onto_line(poly[i], poly[j], crossing)
			out.append(crossing)
	if out.size() < 3:
		return []
	return [out]


## Every polygon of [param polys], each clipped by [param keep], each crossing snapped by
## [param snap] when one is given.
static func clip_all(polys: Array, keep: Callable, snap: PlaneFinder = null) -> Array:
	var out: Array = []
	for poly: PackedVector3Array in polys:
		out.append_array(clip(poly, keep, snap))
	return out


## The point on [param a]-[param b] where [param keep] changes sign, by bisection. The two ends are
## on opposite sides by contract.
static func zero_crossing(a: Vector3, b: Vector3, keep: Callable) -> Vector3:
	var lo: Vector3 = a
	var hi: Vector3 = b
	var lo_kept: bool = float(keep.call(a)) >= 0.0
	for _step: int in BISECT_STEPS:
		var mid: Vector3 = (lo + hi) * 0.5
		if (float(keep.call(mid)) >= 0.0) == lo_kept:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## [param polys] with every loop reversed, so the surface faces the other way.
static func flipped(polys: Array) -> Array:
	var out: Array = []
	for poly: PackedVector3Array in polys:
		var back: PackedVector3Array = poly.duplicate()
		back.reverse()
		out.append(back)
	return out


## Not inside any of [param cutters]: the least of their distances, so it is negative exactly when
## some cutter has the point.
static func outside_all(cutters: Array) -> Callable:
	return func(p: Vector3) -> float:
		var least: float = INF
		for c: Cutter in cutters:
			least = minf(least, c.distance(p))
		return least


## Inside [param cutter]: its distance negated.
static func inside(cutter: Cutter) -> Callable:
	return func(p: Vector3) -> float: return -cutter.distance(p)


## Both of [param a] and [param b]: the lesser.
static func both(a: Callable, b: Callable) -> Callable:
	return func(p: Vector3) -> float: return minf(float(a.call(p)), float(b.call(p)))


## Either of [param a] or [param b]: the greater.
static func either(a: Callable, b: Callable) -> Callable:
	return func(p: Vector3) -> float: return maxf(float(a.call(p)), float(b.call(p)))


## Strictly inside [param cutter], by [constant ON_SURFACE_M]: a point ON its surface does not
## count. A rim that must not include the cutter's own surface asks this.
static func strictly_inside(cutter: Cutter) -> Callable:
	return func(p: Vector3) -> float: return -cutter.distance(p) - ON_SURFACE_M


## [param polys] with every polygon whose longest edge exceeds [param max_edge] cut into a grid of
## smaller ones. A quad becomes an n-by-m grid; any other polygon is fanned into triangles that are
## quartered until they fit.
##
## WHY CLIPPING NEEDS THIS. A polygon is classified by its VERTICES, so a cutter that lands wholly
## within one polygon - a tunnel's mouth in the middle of a 9 m box face - touches no vertex and is
## never seen: the face survives whole and the socket is simply not there. Measured on a carbon
## class of boxes: sockets cut in 0 of 4 pods, and five protons out of six came out SOLID because
## their inner faces never met a cutter either. A lathe's polygons are already small enough; a
## box's are one face each. Gridding them to the size a lathe's are makes the two families behave
## alike, which is what "all shaped hull versions should look the same" asks for.
static func subdivided(polys: Array, max_edge: float) -> Array:
	var out: Array = []
	var limit: float = maxf(max_edge, 0.01)
	for poly: PackedVector3Array in polys:
		_subdivide_into(poly, limit, out)
	return out


static func _longest_edge(poly: PackedVector3Array) -> float:
	var longest: float = 0.0
	for i: int in poly.size():
		longest = maxf(longest, poly[i].distance_to(poly[(i + 1) % poly.size()]))
	return longest


static func _subdivide_into(poly: PackedVector3Array, limit: float, out: Array) -> void:
	if poly.size() < 3:
		return
	if _longest_edge(poly) <= limit:
		out.append(poly)
		return
	if poly.size() == 4:
		# A bilinear grid over the quad, fine enough on both axes.
		var cols: int = maxi(
			int(ceil(maxf(poly[0].distance_to(poly[1]), poly[3].distance_to(poly[2])) / limit)), 1
		)
		var rows: int = maxi(
			int(ceil(maxf(poly[0].distance_to(poly[3]), poly[1].distance_to(poly[2])) / limit)), 1
		)
		for r: int in rows:
			var v0: float = float(r) / float(rows)
			var v1: float = float(r + 1) / float(rows)
			for c: int in cols:
				var u0: float = float(c) / float(cols)
				var u1: float = float(c + 1) / float(cols)
				(
					out
					. append(
						PackedVector3Array(
							[
								_bilinear(poly, u0, v0),
								_bilinear(poly, u1, v0),
								_bilinear(poly, u1, v1),
								_bilinear(poly, u0, v1),
							]
						)
					)
				)
		return
	if poly.size() == 3:
		# Quarter it: the three edge midpoints make four triangles of half the edge.
		var m01: Vector3 = (poly[0] + poly[1]) * 0.5
		var m12: Vector3 = (poly[1] + poly[2]) * 0.5
		var m20: Vector3 = (poly[2] + poly[0]) * 0.5
		_subdivide_into(PackedVector3Array([poly[0], m01, m20]), limit, out)
		_subdivide_into(PackedVector3Array([m01, poly[1], m12]), limit, out)
		_subdivide_into(PackedVector3Array([m20, m12, poly[2]]), limit, out)
		_subdivide_into(PackedVector3Array([m01, m12, m20]), limit, out)
		return
	# Any other polygon: a fan from its centroid, then each triangle on its own.
	var centre: Vector3 = Vector3.ZERO
	for v: Vector3 in poly:
		centre += v
	centre /= float(poly.size())
	for i: int in poly.size():
		_subdivide_into(
			PackedVector3Array([centre, poly[i], poly[(i + 1) % poly.size()]]), limit, out
		)


static func _bilinear(q: PackedVector3Array, u: float, v: float) -> Vector3:
	var bottom: Vector3 = q[0].lerp(q[1], u)
	var top: Vector3 = q[3].lerp(q[2], u)
	return bottom.lerp(top, v)


## Two surfaces split along the curve where they cross, each polygon of one cut wherever a polygon
## of the other passes through it, as `[a_split, b_split]`.
##
## THE SEAM IS COMPUTED ONCE AND SHARED. For every pair of polygons whose boxes overlap, the line
## where their two planes meet is clipped to both polygons; what is left is one straight segment of
## the seam, and BOTH polygons are cut along it. Its two endpoints are then vertices on both sides,
## so the surfaces meet edge to edge with nothing to repair. Chains of such segments cross a
## polygon from edge to edge, and the polygon is split along the chain.
##
## WHY NOT CLIP EACH SIDE AGAINST THE OTHER'S FIELD. A crossing found by bisection on a polygon's
## own edge makes ONE chord across that polygon; where a curved surface passes through it, the true
## seam is a polyline, one segment per polygon of the other surface it crosses. The other side has
## the polyline. The two can never coincide, and sliding the chord's ends onto the other surface
## does not change that: measured, 313 open edges on a rim proton before snapping and 321 after.
## Only a segment computed once from the PAIR is the same on both sides.
##
## Polygons are taken as convex, which everything [method subdivided] hands out is, and which a
## split of a convex polygon along a chain stays. A polygon whose chain cannot be assembled is left
## whole rather than torn, and the caller's field decides its side.
static func seam_split(a_polys: Array, b_polys: Array) -> Array:
	var size: float = 0.0
	for poly: PackedVector3Array in a_polys:
		size = maxf(size, _longest_edge(poly))
	for poly: PackedVector3Array in b_polys:
		size = maxf(size, _longest_edge(poly))
	if size <= 0.0:
		return [a_polys, b_polys]
	var weld: float = size * CHAIN_REL
	var least: float = size * SEGMENT_REL

	var grid: Dictionary = {}
	var cell: float = size
	for index: int in b_polys.size():
		for key: Vector3i in _cells_of(b_polys[index], cell):
			var list: PackedInt32Array = grid.get(key, PackedInt32Array())
			list.append(index)
			grid[key] = list

	var a_segments: Array = []
	var b_segments: Array = []
	a_segments.resize(a_polys.size())
	b_segments.resize(b_polys.size())
	for i: int in a_polys.size():
		var pa: PackedVector3Array = a_polys[i]
		var plane_a: Plane = PolyMesh.plane_of(pa)
		if plane_a.normal == Vector3.ZERO:
			continue
		var seen: Dictionary = {}
		for key: Vector3i in _cells_of(pa, cell):
			var list: Variant = grid.get(key)
			if list == null:
				continue
			for j: int in list as PackedInt32Array:
				if seen.has(j):
					continue
				seen[j] = true
				var pb: PackedVector3Array = b_polys[j]
				var plane_b: Plane = PolyMesh.plane_of(pb)
				var segment: PackedVector3Array = _crossing_segment(pa, plane_a, pb, plane_b, least)
				if segment.is_empty():
					continue
				if a_segments[i] == null:
					a_segments[i] = []
				if b_segments[j] == null:
					b_segments[j] = []
				(a_segments[i] as Array).append(segment)
				(b_segments[j] as Array).append(segment)

	return [_split_all(a_polys, a_segments, weld), _split_all(b_polys, b_segments, weld)]


static func _cells_of(poly: PackedVector3Array, cell: float) -> Array:
	var lo: Vector3 = poly[0]
	var hi: Vector3 = poly[0]
	for v: Vector3 in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	var a: Vector3i = Vector3i(
		int(floor(lo.x / cell)), int(floor(lo.y / cell)), int(floor(lo.z / cell))
	)
	var b: Vector3i = Vector3i(
		int(floor(hi.x / cell)), int(floor(hi.y / cell)), int(floor(hi.z / cell))
	)
	var out: Array = []
	for x: int in range(a.x, b.x + 1):
		for y: int in range(a.y, b.y + 1):
			for z: int in range(a.z, b.z + 1):
				out.append(Vector3i(x, y, z))
	return out


## The one straight piece of seam two convex planar polygons share: the line their planes meet on,
## clipped to both. Empty when the planes are parallel or the pieces do not overlap.
static func _crossing_segment(
	pa: PackedVector3Array, plane_a: Plane, pb: PackedVector3Array, plane_b: Plane, least: float
) -> PackedVector3Array:
	var dir: Vector3 = plane_a.normal.cross(plane_b.normal)
	if dir.length_squared() < 1.0e-10:
		return PackedVector3Array()
	dir = dir.normalized()
	# A point on both planes: solve in the plane spanned by the two normals.
	var n1: Vector3 = plane_a.normal
	var n2: Vector3 = plane_b.normal
	var n1n2: float = n1.dot(n2)
	var det: float = 1.0 - n1n2 * n1n2
	if absf(det) < 1.0e-10:
		return PackedVector3Array()
	var c1: float = (plane_a.d - plane_b.d * n1n2) / det
	var c2: float = (plane_b.d - plane_a.d * n1n2) / det
	var origin: Vector3 = n1 * c1 + n2 * c2
	var span_a: Vector2 = _line_span(origin, dir, pa, plane_a.normal)
	if span_a.x > span_a.y:
		return PackedVector3Array()
	var span_b: Vector2 = _line_span(origin, dir, pb, plane_b.normal)
	if span_b.x > span_b.y:
		return PackedVector3Array()
	var t0: float = maxf(span_a.x, span_b.x)
	var t1: float = minf(span_a.y, span_b.y)
	if t1 - t0 < least:
		return PackedVector3Array()
	return PackedVector3Array([origin + dir * t0, origin + dir * t1])


## The parameter interval of the line [param origin] + t [param dir] inside the convex polygon
## [param poly] lying in the plane with [param normal]. Empty (x > y) when it misses.
static func _line_span(
	origin: Vector3, dir: Vector3, poly: PackedVector3Array, normal: Vector3
) -> Vector2:
	var lo: float = -INF
	var hi: float = INF
	for i: int in poly.size():
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % poly.size()]
		# Inward half-plane of this edge, within the polygon's plane.
		var inward: Vector3 = normal.cross(b - a)
		var denom: float = inward.dot(dir)
		var value: float = inward.dot(a - origin)
		if absf(denom) < 1.0e-12:
			if value > 0.0:
				return Vector2(1.0, -1.0)
			continue
		var t: float = value / denom
		if denom > 0.0:
			lo = maxf(lo, t)
		else:
			hi = minf(hi, t)
	return Vector2(lo, hi)


static func _split_all(polys: Array, segments: Array, weld: float) -> Array:
	var out: Array = []
	for i: int in polys.size():
		if segments[i] == null:
			out.append(polys[i])
			continue
		out.append_array(_split_polygon(polys[i], segments[i], weld))
	return out


## [param poly] cut along every chain its [param segments] form. A chain that does not reach the
## polygon's boundary at both ends, or that cannot be assembled, leaves the polygon whole.
static func _split_polygon(poly: PackedVector3Array, segments: Array, weld: float) -> Array:
	var pending: Array = segments.duplicate()
	var pieces: Array = [poly]
	var guard: int = 16
	while not pending.is_empty() and guard > 0:
		guard -= 1
		var chain: PackedVector3Array = _take_chain(pending, weld)
		if chain.size() < 2:
			break
		var next: Array = []
		var used: bool = false
		for piece: PackedVector3Array in pieces:
			if used:
				next.append(piece)
				continue
			var halves: Array = _split_along(piece, chain, weld)
			if halves.is_empty():
				next.append(piece)
			else:
				next.append_array(halves)
				used = true
		pieces = next
	return pieces


## Pulls one chain of connected segments out of [param pending], end to end.
static func _take_chain(pending: Array, weld: float) -> PackedVector3Array:
	var first: PackedVector3Array = pending.pop_back()
	var chain: PackedVector3Array = PackedVector3Array([first[0], first[1]])
	var grew: bool = true
	while grew and not pending.is_empty():
		grew = false
		for k: int in pending.size():
			var seg: PackedVector3Array = pending[k]
			var head: Vector3 = chain[0]
			var tail: Vector3 = chain[chain.size() - 1]
			if seg[0].distance_to(tail) <= weld:
				chain.append(seg[1])
			elif seg[1].distance_to(tail) <= weld:
				chain.append(seg[0])
			elif seg[1].distance_to(head) <= weld:
				chain.insert(0, seg[0])
			elif seg[0].distance_to(head) <= weld:
				chain.insert(0, seg[1])
			else:
				continue
			pending.remove_at(k)
			grew = true
			break
	return chain


## [param poly] split along [param chain], whose two ends lie on the polygon's boundary, as two
## polygons - or nothing when they do not.
static func _split_along(poly: PackedVector3Array, chain: PackedVector3Array, weld: float) -> Array:
	var n: int = poly.size()
	var head: Vector3 = chain[0]
	var tail: Vector3 = chain[chain.size() - 1]
	var e0: int = _edge_holding(poly, head, weld)
	var e1: int = _edge_holding(poly, tail, weld)
	if e0 < 0 or e1 < 0:
		return []
	# Walk the boundary from the tail's edge round to the head's edge, then back down the chain.
	var one: PackedVector3Array = PackedVector3Array()
	one.append(tail)
	var i: int = (e1 + 1) % n
	var steps: int = 0
	while steps < n:
		one.append(poly[i])
		if i == e0:
			break
		i = (i + 1) % n
		steps += 1
	if steps >= n and e0 != e1:
		return []
	for k: int in chain.size():
		one.append(chain[k])
	# And the other way round.
	var two: PackedVector3Array = PackedVector3Array()
	two.append(head)
	i = (e0 + 1) % n
	steps = 0
	while steps < n:
		two.append(poly[i])
		if i == e1:
			break
		i = (i + 1) % n
		steps += 1
	for k: int in range(chain.size() - 1, -1, -1):
		two.append(chain[k])
	var out: Array = []
	for piece: PackedVector3Array in [one, two]:
		var clean: PackedVector3Array = _dedup(piece, weld)
		if clean.size() >= 3:
			out.append(clean)
	return out if out.size() == 2 else []


static func _edge_holding(poly: PackedVector3Array, point: Vector3, weld: float) -> int:
	var best: int = -1
	var best_d: float = weld * 4.0
	for i: int in poly.size():
		var q: Vector3 = Geometry3D.get_closest_point_to_segment(
			point, poly[i], poly[(i + 1) % poly.size()]
		)
		var d: float = q.distance_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


static func _dedup(poly: PackedVector3Array, weld: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in poly:
		if out.is_empty() or out[out.size() - 1].distance_to(v) > weld:
			out.append(v)
	while out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= weld:
		out.remove_at(out.size() - 1)
	return out


## Every polygon of [param polys] on the side of [param keep] its centre falls on - for polygons
## that have already been split along every seam and so lie wholly on one side.
static func take(polys: Array, keep: Callable) -> Array:
	var out: Array = []
	for poly: PackedVector3Array in polys:
		var centre: Vector3 = Vector3.ZERO
		for v: Vector3 in poly:
			centre += v
		centre /= float(poly.size())
		if float(keep.call(centre)) >= 0.0:
			out.append(poly)
	return out


## Always kept.
static func everything() -> Callable:
	return func(_p: Vector3) -> float: return 1.0
