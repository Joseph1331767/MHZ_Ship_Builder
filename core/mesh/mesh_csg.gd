class_name MeshCsg
## Exact solid booleans on [PolyMesh]: union, difference, intersection, half-space clip.
##
## "we want exact mesh operations as our current method is not exact."
##
## WHAT "EXACT" MEANS HERE, precisely, because the word carries two meanings and only one of them
## is on offer. Every vertex this file produces is the ANALYTIC intersection of input planes,
## computed in floating point — never a sample of a grid. That is the sense in which SketchUp is
## exact too: a box stays a box at any size, a cut is a straight line, a bored hole is round, and
## no resolution parameter exists to be turned up. It is NOT exact arithmetic: coplanar decisions
## are made against [constant PLANE_EPS], and two faces closer together than that are treated as
## one. Exact-predicate CSG needs rational or adaptive-precision arithmetic and is a different
## project.
##
## THE ALGORITHM is the BSP formulation (Naylor-Amanatides-Thibault, as popularised by csg.js):
## build a tree per solid, clip each against the other, and reassemble. Its virtue for this
## project is that COINCIDENT FACES ARE A NAMED CASE rather than an accident — a polygon lying in
## a node's own plane is routed by whether its normal agrees with that plane — and coincident
## faces are exactly what this builder makes. Parts are placed flush ON the surface of other
## parts (SPEC §3), so every seam is a pair of faces sharing a plane. An algorithm that treats
## that as a degenerate edge case would fail on the most ordinary thing the player can do.
##
## POLYGONS STAY N-GONS through every operation. Splitting a hexagonal face against a plane
## yields two smaller n-gons, not a fan of triangles.
##
## WINDING IS CCW-OUTWARD, this file and [PolyMesh] both — a face's right-hand normal points out
## of the solid. Godot's clockwise front face is applied once, in [method PolyMesh.to_array_mesh].
## Do not introduce the render convention here: [method _invert] flips planes and reverses loops
## on every operation, and a second sign convention mixed into that is how a solid comes out
## inside out.
##
## Pure data (SPEC §12): static-only, no [Node], no [SceneTree], no [code]res://[/code].
## Arguments are never mutated.

## On-plane tolerance, RELATIVE to the size of the geometry being operated on, plus a floor.
##
## The single most consequential number in the file, and the first version of it — a flat 1e-7 m —
## was wrong for a reason worth writing down: GODOT'S [Vector3] IS 32-BIT FLOAT. Its relative
## resolution is about 1.2e-7, so at a coordinate magnitude of only 1.5 m the absolute noise is
## already 1.8e-7 — larger than that epsilon. Measured: a 24-sided cylinder at the origin built a
## correct 26-deep BSP, and the SAME cylinder at x=1.0 classified its own defining polygon as
## BEHIND its own plane, so no polygon was ever consumed and the tree recursed to its depth cap.
## A box unioned with it came back with the box missing entirely.
##
## Hence both halves of the fix. The epsilon scales with the extent actually in play, and every
## operation RECENTRES its inputs on their shared bounding box first (see [method _recentred]) so
## that extent is the size of the parts, never their distance from the ship origin.
##
## REL is about eight times the float32 epsilon: loose enough to absorb Newell summation error over
## a 24-gon, and at a 10 m working extent it is 10 µm — a thousandth of the finest authored feature
## (~0.01 m, SPEC §12), so nothing real can be swallowed by it.
const EPS_REL: float = 1.0e-6
const EPS_ABS: float = 1.0e-9

## Vertex classifications, and the polygon classes they combine into by bitwise OR: a polygon
## with both FRONT and BACK vertices is SPANNING and must be split.
const COPLANAR: int = 0
const FRONT: int = 1
const BACK: int = 2
const SPANNING: int = 3

## Ceiling on how many polygon SPLITS one operation may perform, as a base plus an allowance
## per input face.
##
## A HANG IS NEVER AN ACCEPTABLE ANSWER, and one is reachable without this. Two solids that meet
## exactly TANGENTIALLY - a round tube touching a flat face along a single line, rather than
## crossing it - give the BSP a cut with no width, and every polygon near it splits into a sliver
## and a remainder that split again. Measured: twelve tangential unions accumulated past 400
## seconds without finishing, where the same twelve placed to actually overlap took 158 ms.
##
## Past the budget the operation stops SPLITTING and routes each remaining polygon whole to the
## side most of it lies on. That is approximate, and it is reported rather than hidden: the result
## carries [member PolyMesh.truncated], so a caller can refuse it instead of shipping a hull that
## is subtly wrong. Generous on purpose - every ordinary operation measured here uses a small
## fraction of it, so reaching the budget means something genuinely degenerate.
const MAX_SPLITS_BASE: int = 20000
const MAX_SPLITS_PER_FACE: int = 500


## The split allowance for one operation, shared by every node of both trees.
##
## A [RefCounted] rather than an int threaded through the recursion, because it has to be shared
## and mutated: an int would be copied at every call and each branch would quietly get the whole
## budget to itself.
class Budget:
	extends RefCounted

	var remaining: int = 0
	var blown: bool = false

	func spend() -> bool:
		if remaining <= 0:
			blown = true
			return false
		remaining -= 1
		return true


## Ceiling on BSP recursion. A pathological polygon order can build a degenerate tree; rather
## than overflow the GDScript stack, deeper nodes keep their polygons unsplit, which costs
## accuracy in a way the caller can see (via [method PolyMesh.open_edges]) instead of crashing.
const MAX_DEPTH: int = 256

## RETIRED(2026-09-03): RESULT_WELD_M, a fixed 1e-11 weld for boolean results -> the operation
## own scale-relative epsilon, passed into _mesh(). A fixed tolerance is wrong in BOTH directions
## here and both were measured. At 1e-6 m it destroyed the sub-micron slivers a near-tangent cut
## leaves, and every destroyed sliver is a hole - a box unioned with a cylinder reported 5.75 cubic
## metres where 27 was owed. Tightened to 1e-11 it stopped destroying anything and started welding
## nothing: two vertices that are the SAME point reached by different split orders differ by
## float32 noise, so the shared edge between two faces came out with different indices on each
## side, and a closed solid reported 146 unmatched directed edges. The tolerance has to sit above
## the arithmetic noise and below the finest real feature, which is exactly what EPS_REL times the
## working extent already is.


## One polygon and its plane, carried together so the plane is computed once.
class Poly:
	extends RefCounted

	var pts: PackedVector3Array
	var normal: Vector3
	var d: float

	func _init(points: PackedVector3Array) -> void:
		pts = points
		var plane: Plane = PolyMesh.plane_of(points)
		normal = plane.normal
		d = plane.d

	func is_valid() -> bool:
		return normal != Vector3.ZERO and pts.size() >= 3

	func flipped() -> Poly:
		var reversed: PackedVector3Array = pts.duplicate()
		reversed.reverse()
		return Poly.new(reversed)


## A BSP node: a splitting plane, the polygons lying in it, and the two half-spaces.
##
## `BspNode` and not `Node`, which would shadow the engine class - GDScript rejects that outright
## ("Class \"Node\" hides a native class") rather than letting it through to confuse a reader later.
class BspNode:
	extends RefCounted

	var normal: Vector3 = Vector3.ZERO
	var d: float = 0.0
	var has_plane: bool = false
	var polys: Array = []
	var front: BspNode = null
	var back: BspNode = null
	## The on-plane tolerance for this whole operation. Set once by [method MeshCsg._tree] and
	## inherited by every child, so one tree cannot classify with two different epsilons.
	var eps: float = EPS_ABS
	## The split allowance, shared with every other node of both trees in this operation.
	var budget: Budget = null

	func build(list: Array, depth: int = 0) -> void:
		if list.is_empty():
			return
		if not has_plane:
			normal = (list[0] as Poly).normal
			d = (list[0] as Poly).d
			has_plane = true
		var front_list: Array = []
		var back_list: Array = []
		for poly: Variant in list:
			MeshCsg._split(
				poly as Poly, normal, d, polys, polys, front_list, back_list, eps, budget
			)
		if depth >= MeshCsg.MAX_DEPTH:
			# Out of depth: keep what is left rather than recurse. Recorded, not silent — the
			# caller's open_edges() will show it if this ever costs a closed solid.
			polys.append_array(front_list)
			polys.append_array(back_list)
			return
		if not front_list.is_empty():
			if front == null:
				front = BspNode.new()
				front.eps = eps
				front.budget = budget
			front.build(front_list, depth + 1)
		if not back_list.is_empty():
			if back == null:
				back = BspNode.new()
				back.eps = eps
				back.budget = budget
			back.build(back_list, depth + 1)

	## [param list] with everything inside this node's solid removed.
	func clip_polygons(list: Array) -> Array:
		if not has_plane:
			return list.duplicate()
		var front_list: Array = []
		var back_list: Array = []
		for poly: Variant in list:
			MeshCsg._split(
				poly as Poly, normal, d, front_list, back_list, front_list, back_list, eps, budget
			)
		if front != null:
			front_list = front.clip_polygons(front_list)
		# No back child means the back half-space is solid, so everything there is inside and
		# goes away. That single asymmetry is what makes the whole algorithm work.
		if back != null:
			back_list = back.clip_polygons(back_list)
		else:
			back_list = []
		front_list.append_array(back_list)
		return front_list

	func clip_to(other: BspNode) -> void:
		polys = other.clip_polygons(polys)
		if front != null:
			front.clip_to(other)
		if back != null:
			back.clip_to(other)

	func invert() -> void:
		normal = -normal
		d = -d
		var flipped: Array = []
		for poly: Variant in polys:
			flipped.append((poly as Poly).flipped())
		polys = flipped
		if front != null:
			front.invert()
		if back != null:
			back.invert()
		var swap: BspNode = front
		front = back
		back = swap

	func all_polygons() -> Array:
		var out: Array = polys.duplicate()
		if front != null:
			out.append_array(front.all_polygons())
		if back != null:
			out.append_array(back.all_polygons())
		return out


## Everything in [param a] or [param b].
static func union(a: PolyMesh, b: PolyMesh) -> PolyMesh:
	if a == null or a.is_empty():
		return b.duplicate_mesh() if b != null else PolyMesh.new()
	if b == null or b.is_empty():
		return a.duplicate_mesh()
	var work: Dictionary = _recentred(a, b)
	var na: BspNode = _tree(work["a"], work["eps"], work["budget"])
	var nb: BspNode = _tree(work["b"], work["eps"], work["budget"])
	na.clip_to(nb)
	nb.clip_to(na)
	# b's surface inside a is gone; what remains of b may still carry faces coplanar with a's,
	# and this triple is the standard way to drop that duplicate skin.
	nb.invert()
	nb.clip_to(na)
	nb.invert()
	na.build(nb.all_polygons())
	return _restore(na.all_polygons(), work)


## [param a] with [param b] removed.
static func subtract(a: PolyMesh, b: PolyMesh) -> PolyMesh:
	if a == null or a.is_empty():
		return PolyMesh.new()
	if b == null or b.is_empty():
		return a.duplicate_mesh()
	var work: Dictionary = _recentred(a, b)
	var na: BspNode = _tree(work["a"], work["eps"], work["budget"])
	var nb: BspNode = _tree(work["b"], work["eps"], work["budget"])
	na.invert()
	na.clip_to(nb)
	nb.clip_to(na)
	nb.invert()
	nb.clip_to(na)
	nb.invert()
	na.build(nb.all_polygons())
	na.invert()
	return _restore(na.all_polygons(), work)


## Everything in both [param a] and [param b].
static func intersect(a: PolyMesh, b: PolyMesh) -> PolyMesh:
	if a == null or a.is_empty() or b == null or b.is_empty():
		return PolyMesh.new()
	var work: Dictionary = _recentred(a, b)
	var na: BspNode = _tree(work["a"], work["eps"], work["budget"])
	var nb: BspNode = _tree(work["b"], work["eps"], work["budget"])
	na.invert()
	nb.clip_to(na)
	nb.invert()
	na.clip_to(nb)
	nb.clip_to(na)
	na.build(nb.all_polygons())
	na.invert()
	return _restore(na.all_polygons(), work)


## [param mesh] cut back to the half-space BEHIND [param plane] — the side its normal points away
## from — and capped so the result is a closed solid again.
##
## The cap is what makes this more than a clip: a module cut at its seam has to come out as a SOLID
## with a flat face, not as an open shell (ADR 0009's flat seam style, SPEC §3).
##
## DIRECT, NOT A BOOLEAN, and the difference is most of the bake's running time.
## RETIRED(2026-09-03d): building a slab large enough to contain the mesh and calling
## [method intersect]. That reused the boolean rather than writing a second cutter, which was the
## right instinct and the wrong trade: a BSP splits every face against every plane of the other
## solid, so cutting a 360-face sphere with a six-faced slab shredded it into hundreds of fragments
## that then had to be merged back — and the merge cost ten times the cut. Splitting against ONE
## plane touches only the faces that actually cross it, leaves every other face whole, and needs no
## merge afterwards at all. Measured on `argon`: 3.7 s to 0.5 s.
##
## Falls back to the slab boolean when the cut edges cannot be chained into closed loops, which is
## the honest answer for a mesh that was not a clean solid to begin with.
static func clip_to_plane(mesh: PolyMesh, plane: Plane) -> PolyMesh:
	if mesh == null or mesh.is_empty() or plane.normal == Vector3.ZERO:
		return mesh.duplicate_mesh() if mesh != null else PolyMesh.new()
	var normal: Vector3 = plane.normal
	var eps: float = maxf(EPS_ABS, EPS_REL * maxf(mesh.aabb().size.length() * 0.5, 1.0e-6))

	var kept: Array = []
	var cuts: Array = []
	for loop: Variant in mesh.polygons():
		_clip_loop(loop as PackedVector3Array, normal, plane.d, eps, kept, cuts)

	if kept.is_empty():
		return PolyMesh.new()
	var caps: Array = _cap_loops(cuts, normal, eps)
	if caps.is_empty() and not cuts.is_empty():
		return _slab_clip(mesh, plane)
	kept.append_array(caps)
	return PolyMesh.from_polygons(kept, eps)


## Routes one loop against the plane, appending what survives to [param kept] and any edge it
## leaves on the plane to [param cuts] as a `[Vector3, Vector3]` pair.
static func _clip_loop(
	loop: PackedVector3Array, normal: Vector3, d: float, eps: float, kept: Array, cuts: Array
) -> void:
	var n: int = loop.size()
	if n < 3:
		return
	var back: PackedVector3Array = PackedVector3Array()
	var on_plane: PackedVector3Array = PackedVector3Array()
	var any_front: bool = false
	for i: int in n:
		var here: Vector3 = loop[i]
		var next: Vector3 = loop[(i + 1) % n]
		var dh: float = normal.dot(here) - d
		var dn: float = normal.dot(next) - d
		if dh > eps:
			any_front = true
		else:
			back.append(here)
			if absf(dh) <= eps:
				on_plane.append(here)
		if (dh > eps and dn < -eps) or (dh < -eps and dn > eps):
			var t: float = (d - normal.dot(here)) / normal.dot(next - here)
			var cross: Vector3 = here.lerp(next, t)
			back.append(cross)
			on_plane.append(cross)
	if not any_front:
		kept.append(loop)
		return
	if back.size() >= 3:
		kept.append(back)
	# A face that crossed leaves exactly one edge lying in the plane; the cap is built from them.
	if on_plane.size() == 2:
		cuts.append([on_plane[0], on_plane[1]])


## Chains the cut edges into closed loops wound so their outward normal is [param normal].
##
## Returns an empty array when any chain fails to close, which tells the caller the mesh was not a
## clean solid across the plane and the boolean is the safer answer.
static func _cap_loops(cuts: Array, normal: Vector3, eps: float) -> Array:
	if cuts.is_empty():
		return []
	# Endpoints welded onto a grid so the two faces that share a cut point agree it is one point.
	var quant: float = maxf(eps * 4.0, 1.0e-9)
	var ids: Dictionary = {}
	# An Array, NOT a PackedVector3Array, and the difference is not stylistic. A packed array is a
	# VALUE type, so reps.append() inside the helper below appended to a copy and left this one
	# empty: every id came back 0, every segment looked degenerate, no links were ever recorded,
	# and clip_to_plane fell back to the slab boolean on every call without ever saying so. The
	# PolyMesh class docs warn about exactly this and it still got in here.
	var reps: Array[Vector3] = []
	var links: Dictionary = {}
	for pair: Variant in cuts:
		var seg: Array = pair
		var a: int = _cap_id(seg[0], quant, ids, reps)
		var b: int = _cap_id(seg[1], quant, ids, reps)
		if a == b:
			continue
		var from_a: PackedInt32Array = links.get(a, PackedInt32Array())
		from_a.append(b)
		links[a] = from_a
		var from_b: PackedInt32Array = links.get(b, PackedInt32Array())
		from_b.append(a)
		links[b] = from_b

	var seen: Dictionary = {}
	var out: Array = []
	for start: Variant in links:
		if seen.has(start):
			continue
		var loop: PackedVector3Array = PackedVector3Array()
		var cur: int = start
		var prev: int = -1
		var guard: int = 0
		var closed: bool = false
		while guard < 100000:
			guard += 1
			seen[cur] = true
			loop.append(reps[cur])
			var nexts: PackedInt32Array = links.get(cur, PackedInt32Array())
			var nxt: int = -1
			for cand: int in nexts:
				if cand != prev and not seen.has(cand):
					nxt = cand
					break
			if nxt < 0:
				for cand: int in nexts:
					if cand == int(start) and cand != prev:
						closed = true
				break
			prev = cur
			cur = nxt
		if not closed or loop.size() < 3:
			return []
		# The cap faces along the plane normal, so wind it that way.
		if PolyMesh.plane_of(loop).normal.dot(normal) < 0.0:
			loop.reverse()
		out.append(loop)
	return out


## The id of [param p] on the weld grid, adding it (and its representative point) if new.
## The id of [param p] on the weld grid, adding it (and its representative point) if new.
##
## Keyed by the quantised cell as a [Vector3i], NOT by a spatial hash of it. Godot hashes a
## Vector3i by value, so two different cells can never collide; a hash can, and here that is fatal
## rather than merely slow. Everywhere else in this pipeline a hash bucket is followed by an exact
## test - a distance for a weld, a point-on-segment for a T-junction - so a collision costs one
## comparison. This lookup has no such test: the key IS the identity. Measured with a hash: a cap
## of 24 crossing points came back as 18, six of them fused, six nodes left with four edges instead
## of two, and no ring could be chained at all - so every clip silently fell back to the slab
## boolean and the sphere joints came out open.
static func _cap_id(p: Vector3, quant: float, ids: Dictionary, reps: Array[Vector3]) -> int:
	var key: Vector3i = Vector3i(roundi(p.x / quant), roundi(p.y / quant), roundi(p.z / quant))
	if not ids.has(key):
		ids[key] = reps.size()
		reps.append(p)
	return ids[key]


## The slab boolean this used to be, kept as the fallback for a mesh the direct cut cannot close.
static func _slab_clip(mesh: PolyMesh, plane: Plane) -> PolyMesh:
	var box: AABB = mesh.aabb()
	var reach: float = box.size.length() + absf(plane.d) + 1.0
	var origin: Vector3 = plane.normal * plane.d
	var basis: Basis = _frame_for(plane.normal)
	var slab: PolyMesh = box_mesh(Vector3(reach, reach, reach))
	var placed: Transform3D = Transform3D(basis, origin - plane.normal * reach)
	return intersect(mesh, slab.transformed(placed))


## An axis-aligned box of half-extents [param half], centred on the origin, CCW-outward.
##
## Lives here rather than in a shape library because the boolean itself needs one: [method
## clip_to_plane] builds its cutting slab from it, and a primitive the operator depends on should
## not be able to drift away from it.
static func box_mesh(half: Vector3) -> PolyMesh:
	var h: Vector3 = half.abs()
	var corners: PackedVector3Array = PackedVector3Array()
	for i: int in 8:
		corners.append(
			Vector3(
				h.x if (i & 1) != 0 else -h.x,
				h.y if (i & 2) != 0 else -h.y,
				h.z if (i & 4) != 0 else -h.z
			)
		)
	# Each quad anticlockwise seen from outside.
	var quads: Array[PackedInt32Array] = [
		PackedInt32Array([1, 3, 7, 5]),  # +X
		PackedInt32Array([0, 4, 6, 2]),  # -X
		PackedInt32Array([2, 6, 7, 3]),  # +Y
		PackedInt32Array([0, 1, 5, 4]),  # -Y
		PackedInt32Array([4, 5, 7, 6]),  # +Z
		PackedInt32Array([0, 2, 3, 1]),  # -Z
	]
	var polys: Array = []
	for quad: PackedInt32Array in quads:
		var loop: PackedVector3Array = PackedVector3Array()
		for id: int in quad:
			loop.append(corners[id])
		polys.append(loop)
	return PolyMesh.from_polygons(polys)


# --- internals ---------------------------------------------------------------------------------


static func _tree(mesh: PolyMesh, eps: float, budget: Budget) -> BspNode:
	var list: Array = []
	for loop: Variant in mesh.polygons():
		var poly: Poly = Poly.new(loop)
		if poly.is_valid():
			list.append(poly)
	var node: BspNode = BspNode.new()
	node.eps = eps
	node.budget = budget
	node.build(list)
	return node


## Both operands moved so their shared bounding box is centred on the origin, with the on-plane
## tolerance that extent earns. Returns
## [code]{ "a": PolyMesh, "b": PolyMesh, "offset": Vector3, "eps": float }[/code].
##
## RECENTRING IS NOT AN OPTIMISATION, it is half of the precision fix (see [constant EPS_REL]).
## [Vector3] is 32-bit float, so absolute error grows with distance from the origin; a 2 m part
## sitting 200 m along a ship carries a hundred times the noise of the same part at the origin,
## for no reason other than where the ship's origin happens to be. Working in a local frame makes
## the boolean depend on the SIZE of what is being cut, never on where it is.
static func _recentred(a: PolyMesh, b: PolyMesh) -> Dictionary:
	var box: AABB = a.aabb().merge(b.aabb())
	var offset: Vector3 = box.position + box.size * 0.5
	var extent: float = maxf(box.size.length() * 0.5, 1.0e-6)
	var shift: Transform3D = Transform3D(Basis.IDENTITY, -offset)
	var budget: Budget = Budget.new()
	budget.remaining = MAX_SPLITS_BASE + MAX_SPLITS_PER_FACE * (a.face_count() + b.face_count())
	return {
		"a": a.transformed(shift),
		"b": b.transformed(shift),
		"offset": offset,
		"eps": maxf(EPS_ABS, EPS_REL * extent),
		"budget": budget,
	}


## A polygon soup welded and moved back out of the local frame [method _recentred] set up.
static func _restore(list: Array, work: Dictionary) -> PolyMesh:
	var local: PolyMesh = _mesh(list, work["eps"])
	var blown: bool = (work["budget"] as Budget).blown
	var offset: Vector3 = work["offset"]
	var out: PolyMesh = local
	if offset != Vector3.ZERO:
		out = local.transformed(Transform3D(Basis.IDENTITY, offset))
	out.truncated = blown
	return out


## The soup welded back into a mesh, at [constant RESULT_WELD_M] rather than PolyMesh's own
## default. MEASURED, not guessed: welding a boolean result at 1e-6 m destroyed the sub-micron
## slivers BSP splitting leaves along a near-tangent cut, and every destroyed sliver is a HOLE -
## a box unioned with a cylinder came back with a volume of 5.75 where 27 was owed. Welding only
## what is float-noise apart keeps the slivers, and a later merge pass is where they belong.
static func _mesh(list: Array, weld: float) -> PolyMesh:
	var loops: Array = []
	for poly: Variant in list:
		loops.append((poly as Poly).pts)
	return PolyMesh.from_polygons(loops, weld)


## Routes [param poly] against the plane ([param normal], [param d]) into the four output lists,
## splitting it when it spans. A polygon lying IN the plane goes to [param cofront] or
## [param coback] by whether it faces the same way — the case that makes flush seams work.
static func _split(
	poly: Poly,
	normal: Vector3,
	d: float,
	cofront: Array,
	coback: Array,
	front: Array,
	back: Array,
	eps: float,
	budget: Budget
) -> void:
	var n: int = poly.pts.size()
	var kinds: PackedInt32Array = PackedInt32Array()
	kinds.resize(n)
	var combined: int = 0
	for i: int in n:
		var dist: float = normal.dot(poly.pts[i]) - d
		var kind: int = COPLANAR
		if dist < -eps:
			kind = BACK
		elif dist > eps:
			kind = FRONT
		kinds[i] = kind
		combined |= kind

	match combined:
		COPLANAR:
			if normal.dot(poly.normal) > 0.0:
				cofront.append(poly)
			else:
				coback.append(poly)
		FRONT:
			front.append(poly)
		BACK:
			back.append(poly)
		_:
			if budget != null and not budget.spend():
				# Out of allowance: route it whole to the side that holds most of it. Wrong in
				# the small, bounded in the large, and flagged on the way out.
				var votes: int = 0
				for i: int in n:
					if kinds[i] == FRONT:
						votes += 1
					elif kinds[i] == BACK:
						votes -= 1
				if votes >= 0:
					front.append(poly)
				else:
					back.append(poly)
				return
			var front_pts: PackedVector3Array = PackedVector3Array()
			var back_pts: PackedVector3Array = PackedVector3Array()
			for i: int in n:
				var j: int = (i + 1) % n
				var ki: int = kinds[i]
				var kj: int = kinds[j]
				var vi: Vector3 = poly.pts[i]
				if ki != BACK:
					front_pts.append(vi)
				if ki != FRONT:
					back_pts.append(vi)
				if (ki | kj) != SPANNING:
					continue
				# The edge crosses: both halves gain the SAME interpolated point, so the two
				# new polygons share it exactly and the seam between them cannot open up.
				var vj: Vector3 = poly.pts[j]
				var t: float = (d - normal.dot(vi)) / normal.dot(vj - vi)
				var cut: Vector3 = vi.lerp(vj, t)
				front_pts.append(cut)
				back_pts.append(cut)
			if front_pts.size() >= 3:
				var fp: Poly = Poly.new(front_pts)
				if fp.is_valid():
					front.append(fp)
			if back_pts.size() >= 3:
				var bp: Poly = Poly.new(back_pts)
				if bp.is_valid():
					back.append(bp)


## An orthonormal basis whose +Y is [param axis], for orienting the clip slab.
static func _frame_for(axis: Vector3) -> Basis:
	var up: Vector3 = axis.normalized()
	var seed: Vector3 = Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var x: Vector3 = seed.cross(up).normalized()
	var z: Vector3 = x.cross(up)
	return Basis(x, up, z)
