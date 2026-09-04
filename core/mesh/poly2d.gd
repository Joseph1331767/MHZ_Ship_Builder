class_name Poly2D
## Planar polygon helpers for the exact mesh pipeline: triangulating a face that has holes, and
## dropping vertices that sit on a straight line.
##
## WHY THIS IS SEPARATE. A boundary-representation face is an outer loop plus any number of hole
## loops — a wall with a doorway bored through it is exactly that — and nothing in Godot
## triangulates one. [method Geometry2D.triangulate_polygon] is an ear clipper and takes a SIMPLE
## polygon only. So the hole is bridged into the outer loop first, by Eberly's construction, and
## the ear clipper then sees one simple polygon with a zero-width slit in it.
##
## THE BRIDGE IS AN ARTEFACT OF TRIANGULATION, NOT A MODEL EDGE. It exists only inside the index
## list this file returns; [method PolyMesh.boundary_edges] draws loops, never triangles, so a
## wireframe never shows it. That separation is the reason faces keep their holes rather than
## being pre-split into a fan of bridged simple polygons.
##
## Pure data (SPEC §12): static-only, no [Node], no [SceneTree], no [code]res://[/code].
## Arguments are never mutated.

## A point this far off a segment still counts as on it, relative to the loop's own extent.
## Relative because [Vector3] is 32-bit float and an absolute tolerance is meaningless at ship
## scale — the same reasoning as [constant MeshCsg.EPS_REL], for the same arithmetic.
const COLLINEAR_REL: float = 1.0e-5


## Triangulates a face given as [param loops] — [code]loops[0][/code] the outer boundary, the rest
## holes — each a [PackedVector2Array] in the face's own plane.
##
## Returns triangle indices into the CONCATENATION of the loops, so index `i` of `loops[1]` is
## `loops[0].size() + i`. Returns an empty array when the face cannot be triangulated safely,
## which the caller must treat as "leave this face alone" rather than as an empty face.
static func triangulate(loops: Array) -> PackedInt32Array:
	if loops.is_empty():
		return PackedInt32Array()
	var outer: PackedVector2Array = loops[0]
	if outer.size() < 3:
		return PackedInt32Array()

	# Working polygon, and where each of its points came from in the concatenation.
	var poly: PackedVector2Array = outer.duplicate()
	var src: PackedInt32Array = PackedInt32Array()
	for i: int in outer.size():
		src.append(i)

	var base: int = outer.size()
	# Holes are bridged rightmost-first: a bridge always runs to the right, so taking the hole
	# that reaches furthest right first keeps later bridges from crossing an earlier one.
	var order: Array[int] = []
	for h: int in range(1, loops.size()):
		order.append(h)
	order.sort_custom(func(x: int, y: int) -> bool: return _max_x(loops[x]) > _max_x(loops[y]))

	var offsets: Dictionary = {}
	var running: int = base
	for h: int in range(1, loops.size()):
		offsets[h] = running
		running += (loops[h] as PackedVector2Array).size()

	for h: int in order:
		var hole: PackedVector2Array = loops[h]
		if hole.size() < 3:
			continue
		var hole_src: PackedInt32Array = PackedInt32Array()
		for i: int in hole.size():
			hole_src.append(int(offsets[h]) + i)
		# A hole must wind against the outer loop or the bridge reopens it instead of closing it.
		var fixed: PackedVector2Array = hole.duplicate()
		if _signed_area(fixed) * _signed_area(outer) > 0.0:
			fixed.reverse()
			hole_src.reverse()
		var bridged: Dictionary = _bridge(poly, src, fixed, hole_src)
		if bridged.is_empty():
			return PackedInt32Array()
		poly = bridged["poly"]
		src = bridged["src"]

	if poly.size() < 3:
		return PackedInt32Array()
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	# The ear clipper returns nothing on a polygon it cannot handle, and a wrong count means it
	# handled a different polygon than the one asked about. Either way, do not trust it.
	if tri.size() != (poly.size() - 2) * 3:
		return PackedInt32Array()
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in tri.size():
		out.append(src[tri[i]])
	return out


## Which vertices of [param loop] survive when runs of collinear points are dropped, as indices
## into it. Never drops below three.
##
## Not cosmetic: after a boolean, a face's boundary is littered with points where a neighbouring
## face happened to be split, and every one is a vertex the wireframe would draw a corner at.
static func keep_corners(loop: PackedVector2Array, extent: float) -> PackedInt32Array:
	var n: int = loop.size()
	var out: PackedInt32Array = PackedInt32Array()
	if n < 3:
		for i: int in n:
			out.append(i)
		return out
	var tol: float = maxf(extent, 1.0e-6) * COLLINEAR_REL
	for i: int in n:
		var prev: Vector2 = loop[(i - 1 + n) % n]
		var here: Vector2 = loop[i]
		var next: Vector2 = loop[(i + 1) % n]
		var span: Vector2 = next - prev
		var len: float = span.length()
		var off: float = 0.0
		if len <= 1.0e-12:
			off = (here - prev).length()
		else:
			off = absf(span.cross(here - prev)) / len
		if off > tol:
			out.append(i)
	if out.size() < 3:
		out = PackedInt32Array()
		for i: int in n:
			out.append(i)
	return out


## Twice the signed area of [param loop]: positive anticlockwise.
static func signed_area(loop: PackedVector2Array) -> float:
	return _signed_area(loop) * 0.5


## True when [param p] is inside [param loop], by the crossing-number rule.
static func contains(loop: PackedVector2Array, p: Vector2) -> bool:
	var inside: bool = false
	var n: int = loop.size()
	for i: int in n:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % n]
		if (a.y > p.y) == (b.y > p.y):
			continue
		if p.x < a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x):
			inside = not inside
	return inside


# --- internals ---------------------------------------------------------------------------------


static func _signed_area(loop: PackedVector2Array) -> float:
	var total: float = 0.0
	var n: int = loop.size()
	for i: int in n:
		var a: Vector2 = loop[i]
		var b: Vector2 = loop[(i + 1) % n]
		total += a.x * b.y - b.x * a.y
	return total


static func _max_x(loop: PackedVector2Array) -> float:
	var best: float = -INF
	for p: Vector2 in loop:
		best = maxf(best, p.x)
	return best


## [param hole] spliced into [param poly] along a bridge, as
## [code]{ "poly": PackedVector2Array, "src": PackedInt32Array }[/code]. Empty when no bridge
## exists, which tells the caller to leave the face alone rather than emit a wrong triangulation.
##
## Eberly's construction: take the hole's rightmost vertex, cast a ray to the right, and join it
## to the outer vertex that ray reaches — or, where the polygon folds back over that segment, to
## the reflex vertex inside it closest in angle to the ray.
static func _bridge(
	poly: PackedVector2Array,
	src: PackedInt32Array,
	hole: PackedVector2Array,
	hole_src: PackedInt32Array
) -> Dictionary:
	var m: int = 0
	for i: int in hole.size():
		if hole[i].x > hole[m].x or (hole[i].x == hole[m].x and hole[i].y > hole[m].y):
			m = i
	var origin: Vector2 = hole[m]

	var best_x: float = INF
	var best_edge: int = -1
	var n: int = poly.size()
	for i: int in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		if (a.y > origin.y) == (b.y > origin.y):
			continue
		var x: float = a.x + (origin.y - a.y) / (b.y - a.y) * (b.x - a.x)
		if x >= origin.x and x < best_x:
			best_x = x
			best_edge = i
	if best_edge < 0:
		return {}

	var i0: int = best_edge
	var i1: int = (best_edge + 1) % n
	var bridge: int = i0 if poly[i0].x > poly[i1].x else i1
	var hit: Vector2 = Vector2(best_x, origin.y)
	var best_angle: float = INF
	for i: int in n:
		if i == bridge or not _in_triangle(poly[i], origin, hit, poly[bridge]):
			continue
		var angle: float = absf(atan2(poly[i].y - origin.y, poly[i].x - origin.x))
		if angle < best_angle:
			best_angle = angle
			bridge = i

	var out_poly: PackedVector2Array = PackedVector2Array()
	var out_src: PackedInt32Array = PackedInt32Array()
	for i: int in range(bridge + 1):
		out_poly.append(poly[i])
		out_src.append(src[i])
	for k: int in hole.size():
		var j: int = (m + k) % hole.size()
		out_poly.append(hole[j])
		out_src.append(hole_src[j])
	out_poly.append(hole[m])
	out_src.append(hole_src[m])
	out_poly.append(poly[bridge])
	out_src.append(src[bridge])
	for i: int in range(bridge + 1, poly.size()):
		out_poly.append(poly[i])
		out_src.append(src[i])
	return {"poly": out_poly, "src": out_src}


static func _in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1: float = (p - a).cross(b - a)
	var d2: float = (p - b).cross(c - b)
	var d3: float = (p - c).cross(a - c)
	var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)
