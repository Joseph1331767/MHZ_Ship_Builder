class_name HullSimplify
## Turns a [SurfaceNets] triangle soup into a CAD-shaped shell: flat faces become a handful of
## triangles with straight, exact edges, and curved surfaces keep their tessellation (SPEC §9).
##
## WHY THIS EXISTS. Dual Contouring emits one quad per sign-changing grid edge and nothing ever
## merged them, so a 3 m room module shipped 1568 triangles for its outer surface with 65% of
## them dead flat, and every box edge wore a band of sub-cell wobble. Measured on a lone box at
## a 0.25 m cell: 588 triangles in, 6 planar patches out, 12 triangles, surface area exactly
## 24.00 m² against an analytic 24.00. That ratio is the whole point of the file.
##
## THE FIELD WAS NEVER THE PROBLEM. A room's +X face is planar to 0.0000 m over 441 probes of
## [method ShipSdf.sample], in the assembled field and in a module view alike. So nothing here
## touches the SDF, the op order (SPEC §4) or the seam model (ADR 0008) — the shapes were always
## exact and only their MESH was coarse. Consequently this changes no hash and needs no ruleset
## bump (AGENTS §8b): [ShipHash] canonicalises the document, [ShipMetrics] runs its own co-area
## grid, and the bake feeds only the BAKE report and the exploded view.
##
## THE PIPELINE, in the order [method simplify] runs it:
##   1. PROJECT every vertex onto the exact isosurface by Newton steps along the analytic
##      gradient. Dual Contouring leaves them up to a third of a cell out, which tilts the
##      facets of a flat face past any coplanarity test — measured, this alone took a room
##      module from 130 patches to 72.
##   2. GROW planar patches across edge-adjacent triangles that share a plane.
##   3. ABSORB the sub-cell fragments ringing a patch into it. This is what squares off an
##      edge whose authored round (`round: 0.02`, ~6 cm) is far below the 0.25 m bake cell —
##      the grid cannot represent that fillet, so a band of noise is all it ever produces.
##      Bounded to [constant ABSORB_ROUNDS] rings so a genuinely curved surface, which is
##      fragments all the way through, is never flattened into a neighbouring plane.
##   4. SNAP each vertex to the planes meeting at it: one plane projects it, two put it on
##      their line of intersection, three or more on their common point. That is what makes an
##      edge exactly straight and a corner exactly sharp, and it is the same regularised
##      normal-equation solve [SurfaceNets] uses for its QEF, over patch planes instead of
##      crossing tangents.
##   5. STRAIGHTEN each patch boundary with Douglas-Peucker, then RETRIANGULATE the patch from
##      its loops, bridging any holes so a bored doorway keeps its opening.
##
## CRACKS ARE THE FAILURE MODE THIS FILE IS BUILT AROUND. A vertex on the boundary between two
## patches belongs to both, so anything decided per-patch — which vertices to keep, where to
## move them — must be decided IDENTICALLY by both or the shell tears along the seam. Hence:
## snapping is global and runs before any patch is triangulated, and boundary straightening runs
## over CHAINS keyed by the set of planes that meet along them, once, not once per patch.
##
## EVERY ARRAY HERE IS RETURNED, NEVER FILLED THROUGH AN ARGUMENT. GDScript passes a
## [PackedInt32Array] and its siblings BY VALUE — a callee that appends to one is appending to
## its own copy, and the caller sees nothing. That silently emptied this file's first draft, so
## the shape of every private function below is a deliberate guard against it: [Array] and
## [Dictionary] are references and may be filled in place, packed arrays never are.
##
## WHAT IT DELIBERATELY DOES NOT DO. Curved regions keep every triangle they came with, smooth-
## shaded from the analytic gradient. A cylinder showing its tessellation is what CAD looks like;
## decimating it needs an error metric this pass does not carry, and is left to a later one.
##
## Pure data (SPEC §12): static-only, no [Node], no [SceneTree], no [code]res://[/code].
## Arguments are never mutated.

## Newton iterations pulling a vertex onto the isosurface, and the gradient epsilon as a
## fraction of the cell. Four is empirically past convergence: on a lone box the residual falls
## from 4.85 mm to 0.15 mm and stops moving.
const PROJECT_STEPS: int = 4
const PROJECT_EPS_FRAC: float = 0.02

## Furthest a vertex may travel while being projected, in cells. The quad pass in [SurfaceNets]
## joined the four cells around each sign-changing edge on the assumption that every vertex sits
## in its own cell; a Newton step that escapes that neighbourhood self-intersects the shell.
const PROJECT_LIMIT_CELLS: float = 0.75

## Coplanarity: a triangle joins a patch when its face normal is within ~5° of the patch plane
## and all three of its vertices lie within [constant PLANE_TOL_CELLS] of it.
const PLANAR_COS: float = 0.9962
const PLANE_TOL_CELLS: float = 0.30

## Below this a patch is a FRAGMENT, not a face — it gets absorbed or left as curved geometry.
## Area is in cells squared so the test does not change meaning when the grid does.
const MIN_PATCH_TRIS: int = 4
const MIN_PATCH_AREA_CELLS: float = 1.5

## Absorbing fragments into a face, and the reason for every one of these numbers.
##
## ROUNDS is the load-bearing one. A fillet the grid cannot resolve produces a band one or two
## triangles wide against a big flat patch; a curved surface produces fragments that go on for
## ever. Growing only this many rings inward from a planar patch takes the first and cannot take
## the second, whatever the tolerances say.
##
## COS is deliberately loose (~57°) because the facets of an unresolvable fillet sit at roughly
## 45° to both faces it joins — a tighter gate refuses exactly the triangles this exists to
## collect. It stays safe because it is measured against the TARGET patch's plane: the first
## ring of a cylinder wall stands at ~90° to the cap it meets and is rejected on that alone.
const ABSORB_ROUNDS: int = 2
const ABSORB_COS: float = 0.55
const ABSORB_TOL_CELLS: float = 0.60

## Vertex snapping. The regularisation is what makes a one-plane or two-plane solve well posed
## at all: it pulls the answer toward where the vertex already is, so the unconstrained
## directions keep their tangential position instead of drifting. Weak enough that on a corner
## it only breaks ties between equally good solutions.
const SNAP_REGULARIZATION: float = 0.02
const SNAP_MIN_DET: float = 1.0e-10

## Furthest a snap may move a vertex, in cells. A near-degenerate three-plane solve can other-
## wise fling a vertex across the model; clamping degrades it to a slightly soft corner, which
## is a blemish rather than a hole.
const SNAP_LIMIT_CELLS: float = 0.90

## Two patch planes count as the SAME plane at a vertex when they agree to this. Without the
## merge, two patches that grew apart on one flat face would present as two constraints and
## pin a vertex that should still be free to slide.
const PLANE_SAME_COS: float = 0.999
const PLANE_SAME_DIST_CELLS: float = 0.05

## Douglas-Peucker tolerance for a patch boundary, in cells. Tight on purpose: after snapping,
## the vertices along an edge between two planes lie EXACTLY on their line of intersection, so
## a small tolerance already removes all of them, and anything larger would start cutting
## corners off real curves.
const DP_TOL_CELLS: float = 0.08


## Rebuilds [param verts]/[param idx] as a CAD-shaped shell of the [param iso] level set of
## [param field], extracted at spacing [param cell].
##
## Returns [code]{ "vertices": PackedVector3Array, "normals": PackedVector3Array,
## "indices": PackedInt32Array, "patches": int, "planar_patches": int, "flat_tris": int,
## "curved_tris": int }[/code]. [param field] may be null, in which case vertices are not
## projected and normals come from the faces around them — everything else is geometry and
## runs unchanged.
##
## Falls back to the input, patch by patch, wherever one cannot be retriangulated safely: an
## unbridgeable hole or an ear-clip that returns the wrong triangle count keeps its original
## tessellation rather than risking a torn face.
static func simplify(
	field: ShipSdf, verts: PackedVector3Array, idx: PackedInt32Array, iso: float, cell: float
) -> Dictionary:
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	if verts.is_empty() or tri_count == 0 or cell <= 0.0:
		return {
			"vertices": verts.duplicate(),
			"normals": PackedVector3Array(),
			"indices": idx.duplicate(),
			"patches": 0,
			"planar_patches": 0,
			"flat_tris": 0,
			"curved_tris": 0,
		}

	var v: PackedVector3Array = _project(field, verts, iso, cell)
	var faces: Dictionary = _face_data(v, idx)
	var fnorm: PackedVector3Array = faces["normals"]
	var farea: PackedFloat32Array = faces["areas"]

	var edges: Dictionary = _edge_map(idx, v.size())
	var grown: Dictionary = _grow(v, idx, fnorm, farea, edges, cell)
	var planes: Array[Plane] = grown["planes"]
	var patch_of: PackedInt32Array = grown["patch_of"]

	var is_face: PackedInt32Array = _classify(idx, farea, patch_of, planes.size(), cell)
	# Planes are fitted BEFORE absorption and never refitted: the fragments a face collects are
	# tilted by definition, and letting them vote would tip the plane they were collected onto.
	patch_of = _absorb(v, idx, fnorm, edges, patch_of, planes, is_face, cell)

	var vplanes: Dictionary = _vertex_planes(idx, patch_of, is_face)
	v = _snap(v, vplanes, planes, cell)

	return _emit(field, v, idx, fnorm, patch_of, planes, is_face, vplanes, cell)


# --- 1. onto the real surface ----------------------------------------------------------------


## Newton-steps every vertex onto the [param iso] level set along the analytic gradient.
static func _project(
	field: ShipSdf, verts: PackedVector3Array, iso: float, cell: float
) -> PackedVector3Array:
	var out: PackedVector3Array = verts.duplicate()
	if field == null:
		return out
	var eps: float = maxf(cell * PROJECT_EPS_FRAC, 1.0e-6)
	var limit: float = cell * PROJECT_LIMIT_CELLS
	for i: int in out.size():
		var start: Vector3 = out[i]
		var p: Vector3 = start
		for _step: int in PROJECT_STEPS:
			var d: float = field.sample(p) - iso
			if absf(d) < 1.0e-6:
				break
			var g: Vector3 = field.gradient(p, eps)
			var l2: float = g.length_squared()
			if l2 < 1.0e-12:
				break
			p -= g * (d / l2)
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			p = start
		var move: Vector3 = p - start
		if move.length() > limit:
			p = start + move.normalized() * limit
		out[i] = p
	return out


# --- 2. planar patches -----------------------------------------------------------------------


## Per-triangle normals and areas, as
## [code]{ "normals": PackedVector3Array, "areas": PackedFloat32Array }[/code].
##
## The normals are right-hand-rule, so they point AWAY from the outside: [SurfaceNets] winds a
## front face clockwise. Everything downstream keeps that sense and flips only at the very end,
## where a shading normal is written.
static func _face_data(verts: PackedVector3Array, idx: PackedInt32Array) -> Dictionary:
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	var normals: PackedVector3Array = PackedVector3Array()
	var areas: PackedFloat32Array = PackedFloat32Array()
	normals.resize(tri_count)
	areas.resize(tri_count)
	for t: int in tri_count:
		var a: Vector3 = verts[idx[t * 3]]
		var cr: Vector3 = (verts[idx[t * 3 + 1]] - a).cross(verts[idx[t * 3 + 2]] - a)
		var len: float = cr.length()
		areas[t] = len * 0.5
		normals[t] = cr / len if len > 1.0e-12 else Vector3.UP
	return {"normals": normals, "areas": areas}


## Undirected edge -> the triangles on it. Key is `lo * vertex_count + hi`, which is collision
## free by construction where a hash of the pair would not be.
static func _edge_map(idx: PackedInt32Array, vcount: int) -> Dictionary:
	var out: Dictionary = {}
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	for t: int in tri_count:
		for e: int in 3:
			var a: int = idx[t * 3 + e]
			var b: int = idx[t * 3 + (e + 1) % 3]
			var key: int = mini(a, b) * vcount + maxi(a, b)
			var list: PackedInt32Array = out.get(key, PackedInt32Array())
			list.append(t)
			out[key] = list
	return out


## Flood-fills coplanar triangles into patches, as
## [code]{ "patch_of": PackedInt32Array, "planes": Array[Plane] }[/code].
##
## The plane is fixed from the SEED triangle while the patch grows and refitted, area-weighted,
## once it has stopped. Growing against a plane that moves as it goes lets a patch creep around
## a cylinder one facet at a time; growing against a fixed one cannot.
static func _grow(
	verts: PackedVector3Array,
	idx: PackedInt32Array,
	fnorm: PackedVector3Array,
	farea: PackedFloat32Array,
	edges: Dictionary,
	cell: float
) -> Dictionary:
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	var vcount: int = verts.size()
	var tol: float = cell * PLANE_TOL_CELLS
	var patch_of: PackedInt32Array = PackedInt32Array()
	patch_of.resize(tri_count)
	patch_of.fill(-1)
	var planes: Array[Plane] = []

	for seed: int in tri_count:
		if patch_of[seed] >= 0:
			continue
		var pid: int = planes.size()
		var normal: Vector3 = fnorm[seed]
		var origin: Vector3 = verts[idx[seed * 3]]
		patch_of[seed] = pid
		var nsum: Vector3 = normal * farea[seed]
		var psum: Vector3 = _centroid(verts, idx, seed) * farea[seed]
		var asum: float = farea[seed]
		var frontier: PackedInt32Array = PackedInt32Array([seed])
		while not frontier.is_empty():
			var t: int = frontier[frontier.size() - 1]
			frontier.remove_at(frontier.size() - 1)
			for e: int in 3:
				var a: int = idx[t * 3 + e]
				var b: int = idx[t * 3 + (e + 1) % 3]
				var key: int = mini(a, b) * vcount + maxi(a, b)
				for other: int in edges[key] as PackedInt32Array:
					if patch_of[other] >= 0 or fnorm[other].dot(normal) < PLANAR_COS:
						continue
					if not _within(verts, idx, other, normal, origin, tol):
						continue
					patch_of[other] = pid
					nsum += fnorm[other] * farea[other]
					psum += _centroid(verts, idx, other) * farea[other]
					asum += farea[other]
					frontier.append(other)
		var fit: Vector3 = nsum.normalized() if nsum.length() > 1.0e-12 else normal
		var point: Vector3 = psum / asum if asum > 1.0e-12 else origin
		planes.append(Plane(fit, fit.dot(point)))
	return {"patch_of": patch_of, "planes": planes}


static func _centroid(verts: PackedVector3Array, idx: PackedInt32Array, t: int) -> Vector3:
	return (verts[idx[t * 3]] + verts[idx[t * 3 + 1]] + verts[idx[t * 3 + 2]]) / 3.0


## True when all three vertices of triangle [param t] sit within [param tol] of the plane
## through [param origin] with normal [param normal].
static func _within(
	verts: PackedVector3Array,
	idx: PackedInt32Array,
	t: int,
	normal: Vector3,
	origin: Vector3,
	tol: float
) -> bool:
	var ok: bool = true
	for k: int in 3:
		if absf(normal.dot(verts[idx[t * 3 + k]] - origin)) > tol:
			ok = false
			break
	return ok


## 1 for every patch big enough to be a FACE, 0 for a fragment. Indexed by patch id.
static func _classify(
	idx: PackedInt32Array,
	farea: PackedFloat32Array,
	patch_of: PackedInt32Array,
	patch_count: int,
	cell: float
) -> PackedInt32Array:
	var tris: PackedInt32Array = PackedInt32Array()
	var area: PackedFloat32Array = PackedFloat32Array()
	tris.resize(patch_count)
	area.resize(patch_count)
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	for t: int in tri_count:
		var p: int = patch_of[t]
		tris[p] += 1
		area[p] += farea[t]
	var min_area: float = cell * cell * MIN_PATCH_AREA_CELLS
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(patch_count)
	for p: int in patch_count:
		out[p] = 1 if tris[p] >= MIN_PATCH_TRIS and area[p] >= min_area else 0
	return out


## Pulls the rings of unresolvable detail around a face into that face, returning the updated
## patch assignment. See [constant ABSORB_ROUNDS] for why this is bounded by rings.
static func _absorb(
	verts: PackedVector3Array,
	idx: PackedInt32Array,
	fnorm: PackedVector3Array,
	edges: Dictionary,
	patch_of: PackedInt32Array,
	planes: Array[Plane],
	is_face: PackedInt32Array,
	cell: float
) -> PackedInt32Array:
	var out: PackedInt32Array = patch_of.duplicate()
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	var vcount: int = verts.size()
	var tol: float = cell * ABSORB_TOL_CELLS
	for _round: int in ABSORB_ROUNDS:
		# Assignments are collected and applied together so a triangle absorbed early in the
		# sweep cannot recruit its neighbours in the same sweep — that is what would let a
		# curved surface be eaten one ring per triangle instead of one ring per round.
		var claim: PackedInt32Array = PackedInt32Array()
		claim.resize(tri_count)
		claim.fill(-1)
		var claimed: bool = false
		for t: int in tri_count:
			if is_face[out[t]] == 1:
				continue
			var best: int = -1
			var best_dist: float = tol
			for e: int in 3:
				var a: int = idx[t * 3 + e]
				var b: int = idx[t * 3 + (e + 1) % 3]
				var key: int = mini(a, b) * vcount + maxi(a, b)
				for other: int in edges[key] as PackedInt32Array:
					var target: int = out[other]
					if other == t or is_face[target] == 0:
						continue
					var plane: Plane = planes[target]
					if fnorm[t].dot(plane.normal) < ABSORB_COS:
						continue
					var worst: float = 0.0
					for k: int in 3:
						worst = maxf(worst, absf(plane.distance_to(verts[idx[t * 3 + k]])))
					if worst < best_dist:
						best_dist = worst
						best = target
			if best >= 0:
				claim[t] = best
				claimed = true
		if not claimed:
			break
		for t: int in tri_count:
			if claim[t] >= 0:
				out[t] = claim[t]
	return out


# --- 3. snapping vertices to the planes that meet at them ------------------------------------


## Vertex -> the ids of the FACE patches touching it, deduplicated.
static func _vertex_planes(
	idx: PackedInt32Array, patch_of: PackedInt32Array, is_face: PackedInt32Array
) -> Dictionary:
	var out: Dictionary = {}
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	for t: int in tri_count:
		var p: int = patch_of[t]
		if is_face[p] == 0:
			continue
		for k: int in 3:
			var v: int = idx[t * 3 + k]
			var list: PackedInt32Array = out.get(v, PackedInt32Array())
			if not list.has(p):
				list.append(p)
				out[v] = list
	return out


## Every vertex moved onto the planes meeting at it. One plane projects it, two put it on their
## line, three or more on their point — one regularised normal-equation solve covers all three,
## which is why there is no special case here for edges or corners.
static func _snap(
	verts: PackedVector3Array, vplanes: Dictionary, planes: Array[Plane], cell: float
) -> PackedVector3Array:
	var out: PackedVector3Array = verts.duplicate()
	var limit: float = cell * SNAP_LIMIT_CELLS
	var same_dist: float = cell * PLANE_SAME_DIST_CELLS
	for key: Variant in vplanes:
		var v: int = key
		var start: Vector3 = out[v]
		var used: Array[Plane] = []
		for pid: int in vplanes[key] as PackedInt32Array:
			var plane: Plane = planes[pid]
			var seen_before: bool = false
			for seen: Plane in used:
				if (
					seen.normal.dot(plane.normal) > PLANE_SAME_COS
					and absf(seen.d - plane.d) < same_dist
				):
					seen_before = true
					break
			if not seen_before:
				used.append(plane)
		var solved: Vector3 = _solve_planes(used, start)
		var move: Vector3 = solved - start
		if move.length() > limit:
			solved = start + move.normalized() * limit
		out[v] = solved
	return out


## The point minimising the sum of squared distances to [param planes], pulled toward
## [param toward] by [constant SNAP_REGULARIZATION] so the directions no plane constrains keep
## the position they had. Returns [param toward] unchanged if the system is degenerate.
static func _solve_planes(planes: Array[Plane], toward: Vector3) -> Vector3:
	var a00: float = SNAP_REGULARIZATION
	var a01: float = 0.0
	var a02: float = 0.0
	var a11: float = SNAP_REGULARIZATION
	var a12: float = 0.0
	var a22: float = SNAP_REGULARIZATION
	var b0: float = SNAP_REGULARIZATION * toward.x
	var b1: float = SNAP_REGULARIZATION * toward.y
	var b2: float = SNAP_REGULARIZATION * toward.z
	for plane: Plane in planes:
		var n: Vector3 = plane.normal
		a00 += n.x * n.x
		a01 += n.x * n.y
		a02 += n.x * n.z
		a11 += n.y * n.y
		a12 += n.y * n.z
		a22 += n.z * n.z
		b0 += n.x * plane.d
		b1 += n.y * plane.d
		b2 += n.z * plane.d

	var m00: float = a11 * a22 - a12 * a12
	var m01: float = a01 * a22 - a12 * a02
	var m02: float = a01 * a12 - a11 * a02
	var det: float = a00 * m00 - a01 * m01 + a02 * m02
	if absf(det) < SNAP_MIN_DET:
		return toward
	var x: float = (b0 * m00 - a01 * (b1 * a22 - a12 * b2) + a02 * (b1 * a12 - a11 * b2)) / det
	var y: float = (a00 * (b1 * a22 - a12 * b2) - b0 * m01 + a02 * (a01 * b2 - b1 * a02)) / det
	var z: float = (a00 * (a11 * b2 - b1 * a12) - a01 * (a01 * b2 - b1 * a02) + b0 * m02) / det
	if not (is_finite(x) and is_finite(y) and is_finite(z)):
		return toward
	return Vector3(x, y, z)


# --- 4. boundaries, straightening, retriangulation --------------------------------------------


## Builds the output arrays: every FACE patch retriangulated from its straightened boundary,
## every remaining triangle carried over as it was.
static func _emit(
	field: ShipSdf,
	verts: PackedVector3Array,
	idx: PackedInt32Array,
	fnorm: PackedVector3Array,
	patch_of: PackedInt32Array,
	planes: Array[Plane],
	is_face: PackedInt32Array,
	vplanes: Dictionary,
	cell: float
) -> Dictionary:
	@warning_ignore("integer_division")
	var tri_count: int = idx.size() / 3
	var members: Array[PackedInt32Array] = []
	for _p: int in planes.size():
		members.append(PackedInt32Array())
	for t: int in tri_count:
		var list: PackedInt32Array = members[patch_of[t]]
		list.append(t)
		members[patch_of[t]] = list

	# Which vertices no patch may drop: anything a curved triangle also uses, and anything
	# where more or fewer than two planes meet. Dropping either tears the shell.
	var pinned: Dictionary = {}
	for t: int in tri_count:
		if is_face[patch_of[t]] == 0:
			for k: int in 3:
				pinned[idx[t * 3 + k]] = true
	for key: Variant in vplanes:
		if (vplanes[key] as PackedInt32Array).size() != 2:
			pinned[key] = true

	var keep: Dictionary = {}
	var chains: Dictionary = {}
	var loops_by_patch: Array = []
	for p: int in planes.size():
		var loops: Array[PackedInt32Array] = []
		if is_face[p] == 1:
			loops = _loops(idx, members[p], verts.size())
			for loop: PackedInt32Array in loops:
				_straighten(verts, loop, pinned, vplanes, keep, chains, cell)
		loops_by_patch.append(loops)

	var out_v: PackedVector3Array = PackedVector3Array()
	var out_n: PackedVector3Array = PackedVector3Array()
	var out_i: PackedInt32Array = PackedInt32Array()
	var flat_tris: int = 0
	var face_count: int = 0

	for p: int in planes.size():
		var built: Dictionary = {}
		if is_face[p] == 1:
			built = _build_patch(verts, loops_by_patch[p], keep, planes[p])
		var rebuilt: bool = built.has("indices")
		if not rebuilt:
			# No safe triangulation: this patch keeps exactly the triangles it arrived with.
			built = _build_raw(field, verts, idx, fnorm, members[p], cell)
		# Welded here rather than in a helper: the three accumulators are packed arrays, which
		# GDScript passes BY VALUE, so a helper would append to copies and drop every patch.
		var base: int = out_v.size()
		out_v.append_array(built["vertices"] as PackedVector3Array)
		out_n.append_array(built["normals"] as PackedVector3Array)
		var local: PackedInt32Array = built["indices"]
		for i: int in local.size():
			out_i.append(base + local[i])
		if rebuilt:
			@warning_ignore("integer_division")
			var made: int = local.size() / 3
			flat_tris += made
			face_count += 1

	@warning_ignore("integer_division")
	var total_tris: int = out_i.size() / 3
	return {
		"vertices": out_v,
		"normals": out_n,
		"indices": out_i,
		"patches": planes.size(),
		"planar_patches": face_count,
		"flat_tris": flat_tris,
		"curved_tris": total_tris - flat_tris,
	}


## Closed boundary loops of one patch, as vertex ids in winding order.
##
## Walks DIRECTED edges: an edge of a member triangle is on the boundary when the same edge
## does not come back the other way from another member. That gives loops already oriented with
## the patch's winding, so an outer loop and a hole come out with opposite signed area and the
## triangulator can tell them apart without a point-in-polygon test.
static func _loops(
	idx: PackedInt32Array, members: PackedInt32Array, vcount: int
) -> Array[PackedInt32Array]:
	var directed: Dictionary = {}
	for t: int in members:
		for e: int in 3:
			directed[idx[t * 3 + e] * vcount + idx[t * 3 + (e + 1) % 3]] = true

	var outgoing: Dictionary = {}
	for t: int in members:
		for e: int in 3:
			var a: int = idx[t * 3 + e]
			var b: int = idx[t * 3 + (e + 1) % 3]
			if directed.has(b * vcount + a):
				continue
			var list: PackedInt32Array = outgoing.get(a, PackedInt32Array())
			list.append(b)
			outgoing[a] = list

	var out: Array[PackedInt32Array] = []
	var guard: int = 0
	for key: Variant in outgoing:
		while not (outgoing[key] as PackedInt32Array).is_empty() and guard < 1_000_000:
			var loop: PackedInt32Array = PackedInt32Array()
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
				loop.append(cur)
				cur = nxt
				if cur == key:
					closed = true
					break
			# An unclosed walk means the patch was not edge-manifold; dropping it costs one
			# patch its merge and leaves the raw triangles, which is the safe direction.
			if closed and loop.size() >= 3:
				out.append(loop)
	return out


## Marks the vertices of [param loop] that survive straightening, into [param keep].
##
## Runs over CHAINS — maximal runs between pinned vertices — and each chain is processed ONCE,
## under a canonical key, because the patch on the other side walks the identical chain
## backwards and must reach the identical answer or the two faces tear apart along it.
static func _straighten(
	verts: PackedVector3Array,
	loop: PackedInt32Array,
	pinned: Dictionary,
	vplanes: Dictionary,
	keep: Dictionary,
	chains: Dictionary,
	cell: float
) -> void:
	var n: int = loop.size()
	var anchors: PackedInt32Array = PackedInt32Array()
	for i: int in n:
		if pinned.has(loop[i]):
			anchors.append(i)
			keep[loop[i]] = true
	if anchors.is_empty():
		# Nothing to straighten against: keep the loop whole rather than guess a start.
		for i: int in n:
			keep[loop[i]] = true
		return

	var tol: float = cell * DP_TOL_CELLS
	for a: int in anchors.size():
		var i0: int = anchors[a]
		var i1: int = anchors[(a + 1) % anchors.size()]
		var span: int = (i1 - i0 + n) % n
		if span < 2:
			continue
		var chain: PackedInt32Array = PackedInt32Array()
		for s: int in range(span + 1):
			chain.append(loop[(i0 + s) % n])
		if chain[0] > chain[chain.size() - 1]:
			chain.reverse()
		var sig: PackedInt32Array = vplanes.get(chain[1], PackedInt32Array())
		var key: String = "%d:%d:%d:%s" % [chain[0], chain[chain.size() - 1], span, str(sig)]
		if chains.has(key):
			continue
		chains[key] = true
		_dp(verts, chain, 0, chain.size() - 1, tol, keep)


## Douglas-Peucker over an open chain, marking the vertices it keeps.
static func _dp(
	verts: PackedVector3Array,
	chain: PackedInt32Array,
	i0: int,
	i1: int,
	tol: float,
	keep: Dictionary
) -> void:
	if i1 - i0 < 2:
		return
	var a: Vector3 = verts[chain[i0]]
	var b: Vector3 = verts[chain[i1]]
	var ab: Vector3 = b - a
	var len2: float = ab.length_squared()
	var worst: float = -1.0
	var worst_i: int = -1
	for i: int in range(i0 + 1, i1):
		var p: Vector3 = verts[chain[i]]
		var d: float = 0.0
		if len2 <= 1.0e-12:
			d = (p - a).length()
		else:
			d = (p - (a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0))).length()
		if d > worst:
			worst = d
			worst_i = i
	if worst <= tol or worst_i < 0:
		return
	keep[chain[worst_i]] = true
	_dp(verts, chain, i0, worst_i, tol, keep)
	_dp(verts, chain, worst_i, i1, tol, keep)


## One face patch retriangulated from its straightened loops, as
## [code]{ "vertices", "normals", "indices" }[/code] with indices local to the chunk. Returns an
## EMPTY dictionary to say the patch could not be rebuilt safely and must keep its own triangles.
static func _build_patch(
	verts: PackedVector3Array, loops: Array[PackedInt32Array], keep: Dictionary, plane: Plane
) -> Dictionary:
	if loops.is_empty():
		return {}
	var normal: Vector3 = plane.normal
	var axis: Vector3 = Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	var u: Vector3 = normal.cross(axis).normalized()
	var w: Vector3 = normal.cross(u)

	var rings: Array[PackedInt32Array] = []
	var areas: PackedFloat32Array = PackedFloat32Array()
	var outer: int = 0
	var best: float = -1.0
	for loop: PackedInt32Array in loops:
		var kept: PackedInt32Array = PackedInt32Array()
		for id: int in loop:
			if keep.has(id):
				kept.append(id)
		if kept.size() < 3:
			return {}
		var signed: float = _ring_area(verts, kept, u, w)
		if absf(signed) > best:
			best = absf(signed)
			outer = rings.size()
		rings.append(kept)
		areas.append(signed)

	var poly: PackedVector2Array = PackedVector2Array()
	var src: PackedInt32Array = PackedInt32Array()
	for id: int in rings[outer]:
		poly.append(_to_2d(verts[id], u, w))
		src.append(id)
	for r: int in rings.size():
		if r == outer:
			continue
		var hole: PackedVector2Array = PackedVector2Array()
		var hole_src: PackedInt32Array = PackedInt32Array()
		for id: int in rings[r]:
			hole.append(_to_2d(verts[id], u, w))
			hole_src.append(id)
		# A hole must wind against the outer ring for the bridge to close it rather than
		# reopen it; the directed-loop walk already gives opposite signs, so only fix it up.
		if signf(areas[r]) == signf(areas[outer]):
			hole.reverse()
			hole_src.reverse()
		var bridged: Dictionary = _bridge(poly, src, hole, hole_src)
		if bridged.is_empty():
			return {}
		poly = bridged["poly"]
		src = bridged["src"]

	if poly.size() < 3:
		return {}
	var tri: PackedInt32Array = Geometry2D.triangulate_polygon(poly)
	if tri.size() != (poly.size() - 2) * 3:
		return {}

	var out_v: PackedVector3Array = PackedVector3Array()
	var out_n: PackedVector3Array = PackedVector3Array()
	var outward: Vector3 = -normal
	for i: int in poly.size():
		out_v.append(verts[src[i]])
		out_n.append(outward)

	var out_i: PackedInt32Array = PackedInt32Array()
	var k: int = 0
	while k + 2 < tri.size():
		var a: int = tri[k]
		var b: int = tri[k + 1]
		var c: int = tri[k + 2]
		# Match the extractor's winding: the right-hand normal of a front face points along the
		# FACE normal, which is the inward one, so the 2D triangle must come out anticlockwise
		# in a (u, w) basis built to satisfy u x w = normal.
		var cross: float = (poly[b] - poly[a]).cross(poly[c] - poly[a])
		out_i.append(a)
		if cross < 0.0:
			out_i.append(c)
			out_i.append(b)
		else:
			out_i.append(b)
			out_i.append(c)
		k += 3
	return {"vertices": out_v, "normals": out_n, "indices": out_i}


static func _to_2d(p: Vector3, u: Vector3, w: Vector3) -> Vector2:
	return Vector2(p.dot(u), p.dot(w))


static func _ring_area(
	verts: PackedVector3Array, ring: PackedInt32Array, u: Vector3, w: Vector3
) -> float:
	var total: float = 0.0
	var n: int = ring.size()
	for i: int in n:
		var a: Vector2 = _to_2d(verts[ring[i]], u, w)
		var b: Vector2 = _to_2d(verts[ring[(i + 1) % n]], u, w)
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## [param hole] spliced into [param poly] along a bridge, as
## [code]{ "poly": PackedVector2Array, "src": PackedInt32Array }[/code], so an ear-clipper that
## knows nothing about holes can triangulate the result. Eberly's construction: take the hole's
## rightmost vertex, cast a ray to the right, and join it to the outer vertex that ray reaches —
## or, where the polygon folds back over that segment, to the nearest reflex vertex inside it.
##
## Returns an EMPTY dictionary when no bridge exists, which leaves the patch alone.
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
		var t: float = (origin.y - a.y) / (b.y - a.y)
		var x: float = a.x + t * (b.x - a.x)
		if x >= origin.x and x < best_x:
			best_x = x
			best_edge = i
	if best_edge < 0:
		return {}

	var i0: int = best_edge
	var i1: int = (best_edge + 1) % n
	var bridge: int = i0 if poly[i0].x > poly[i1].x else i1
	# Any vertex inside the triangle (origin, hit, bridge) would make that bridge cross the
	# polygon; the one closest in angle to the ray is the safe target instead.
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


## A patch's original triangles, unchanged, smooth-shaded from the analytic gradient where there
## is a field to ask and from the faces around them where there is not.
static func _build_raw(
	field: ShipSdf,
	verts: PackedVector3Array,
	idx: PackedInt32Array,
	fnorm: PackedVector3Array,
	members: PackedInt32Array,
	cell: float
) -> Dictionary:
	var out_v: PackedVector3Array = PackedVector3Array()
	var out_n: PackedVector3Array = PackedVector3Array()
	var out_i: PackedInt32Array = PackedInt32Array()
	var remap: Dictionary = {}
	var eps: float = maxf(cell * PROJECT_EPS_FRAC, 1.0e-6)
	for t: int in members:
		for k: int in 3:
			var v: int = idx[t * 3 + k]
			if not remap.has(v):
				remap[v] = out_v.size()
				out_v.append(verts[v])
				var n: Vector3 = -fnorm[t]
				if field != null:
					var g: Vector3 = field.gradient(verts[v], eps)
					if g.length() > 1.0e-12:
						n = g.normalized()
				out_n.append(n)
			out_i.append(int(remap[v]))
	return {"vertices": out_v, "normals": out_n, "indices": out_i}
