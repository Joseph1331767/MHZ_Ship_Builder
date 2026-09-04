class_name SurfaceNets
## Dual Contouring — a welded triangle shell extracted from a [ShipSdf] (SPEC §9).
##
## Sample the field on a regular grid over [param bounds] at spacing [param cell]. Every
## cell whose eight corner samples are not all on the same side of [param iso] contains
## surface, and gets exactly ONE vertex, placed by [method _place_vertex]. Four such cells
## surround every sign-changing grid edge, and those four vertices are joined into a quad
## (two triangles). Vertex normals come from the SDF gradient at the final vertex position,
## never from face normals — on a 0.25 m grid that is the difference between a faceted lump
## and a readable hull.
##
## RETIRED(ADR 0009, 2026-09-02): the QEF-free CENTROID of the edge crossings, i.e. naive
## Surface Nets. SPEC §9 promised the upgrade and reserved this exact function for it — "replace
## only place_vertex() with a QEF solve over the gradients at the edge crossings, clamped to the
## cell ... and boxes get their sharp edges back. Do that when the rounding is a problem, not
## before." It became the problem the moment parts were cut flat at their seams: the centroid
## rounds every sharp feature by about half a cell, so a flat seam face came out domed and its
## rim melted into the flank ("its not flattened along the plane of intersection its all bumped
## out and weird looking"). Same grid, same loops, same quad pass, ONE function changed.
##
## That promise still holds going forward: [method _place_vertex] is the sole site that decides
## where a vertex goes, and no other function in this file may touch vertex placement.
##
## Pure data (SPEC §12): no [Node], no [SceneTree], no signals, no [code]res://[/code].
## Arguments are never mutated.

## Hard ceiling on grid cells. A 250 m hull at 0.01 m spacing would be 1.5e13 cells; rather
## than attempt an unbounded allocation the spacing is coarsened until the grid fits, and
## the spacing actually used is reported back as "cell_m".
const MAX_CELLS: int = 8_000_000

## Absolute floor on cell size, metres. Finest authored feature is ~0.01 m (SPEC §12), so
## anything below this is a caller mistake, not a resolution request.
const MIN_CELL_M: float = 1.0e-4

## Gradient central-difference epsilon, as a fraction of the cell size. [method extract]
## takes no [ShipConfig], so it cannot read [code]gradient_eps[/code]; deriving it from the
## grid is the honest alternative and keeps the sample local to one cell.
const NORMAL_EPS_FRAC: float = 0.25

## QEF regularisation (ADR 0009), per crossing plus a floor. The QEF matrix is rank-deficient
## wherever the surface is locally planar or a ridge — which is most cells — so a pull toward
## the centroid of the crossings is what makes it solvable at all. It is deliberately weak:
## on a plane it moves the answer nowhere (the centroid of coplanar crossings is already ON
## the plane), and at a corner it only breaks the tie between equally good solutions.
const QEF_REGULARIZATION: float = 0.01
const QEF_MIN_REGULARIZATION: float = 1.0e-6

## Below this determinant the 3x3 normal-equation solve is not trusted and the vertex falls
## back to the centroid — which is exactly what this file did before ADR 0009, so a degenerate
## cell degrades to the old behaviour rather than to a NaN.
const QEF_MIN_DET: float = 1.0e-12

## Shortest gradient treated as a usable normal.
const QEF_MIN_NORMAL: float = 1.0e-12


## Extracts the [param iso] level set of [param sdf] over [param bounds].
##
## Returns [code]{ "vertices": PackedVector3Array, "normals": PackedVector3Array,
## "indices": PackedInt32Array, "cells": int, "cell_m": float, "dims": Vector3i }[/code].
## [code]cells[/code] is the grid cell COUNT; [code]cell_m[/code] is the spacing actually
## used, which is [param cell] unless the grid had to be coarsened to fit [constant MAX_CELLS].
static func extract(sdf: ShipSdf, bounds: AABB, cell: float, iso: float) -> Dictionary:
	var box: AABB = bounds.abs()
	if sdf == null or not _finite_v3(box.position) or not _finite_v3(box.size):
		return _empty_result(maxf(cell, MIN_CELL_M))

	var c: float = _fit_cell(box.size, cell)
	var nx: int = maxi(1, ceili(box.size.x / c))
	var ny: int = maxi(1, ceili(box.size.y / c))
	var nz: int = maxi(1, ceili(box.size.z / c))
	var sx: int = nx + 1
	var sy: int = ny + 1
	var sz: int = nz + 1
	var sxy: int = sx * sy
	var org: Vector3 = box.position

	# --- 1. Sample the field ONCE per grid corner. --------------------------------------
	# The whole performance story. A cell needs 8 corners and every interior corner is
	# shared by 8 cells, so sampling per-cell would evaluate the SDF eight times over —
	# roughly an 8x cost on the single most expensive call in the project.
	# Layout: index = x + sx * (y + sy * z), x varying fastest.
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(sxy * sz)
	var si: int = 0
	for z: int in sz:
		var pz: float = org.z + float(z) * c
		for y: int in sy:
			var py: float = org.y + float(y) * c
			for x: int in sx:
				samples[si] = sdf.sample(Vector3(org.x + float(x) * c, py, pz))
				si += 1

	# --- 2. One dual vertex per sign-changing cell. -------------------------------------
	# Flat PackedInt32Array, NOT a Dictionary keyed by Vector3i: at millions of cells the
	# hashing and the boxed keys are the difference between seconds and minutes.
	var cell_vert: PackedInt32Array = PackedInt32Array()
	cell_vert.resize(nx * ny * nz)
	cell_vert.fill(-1)

	# Corner numbering: bit 0 = +X, bit 1 = +Y, bit 2 = +Z.
	var corner_off: PackedVector3Array = PackedVector3Array()
	corner_off.resize(8)
	for i: int in 8:
		corner_off[i] = Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)) * c

	# The twelve cell edges as corner pairs: four along X, then four along Y, then four
	# along Z. Each pair differs in exactly one bit.
	var edge_a: PackedInt32Array = PackedInt32Array([0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3])
	var edge_b: PackedInt32Array = PackedInt32Array([1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7])

	var verts: PackedVector3Array = PackedVector3Array()
	var cv: PackedFloat32Array = PackedFloat32Array()
	cv.resize(8)

	for cz: int in nz:
		var cell_z: float = org.z + float(cz) * c
		for cy: int in ny:
			var cell_y: float = org.y + float(cy) * c
			var s_row: int = sx * (cy + sy * cz)
			var c_row: int = nx * (cy + ny * cz)
			for cx: int in nx:
				var i0: int = s_row + cx
				var f0: float = samples[i0]
				var f1: float = samples[i0 + 1]
				var f2: float = samples[i0 + sx]
				var f3: float = samples[i0 + sx + 1]
				var f4: float = samples[i0 + sxy]
				var f5: float = samples[i0 + sxy + 1]
				var f6: float = samples[i0 + sxy + sx]
				var f7: float = samples[i0 + sxy + sx + 1]
				# "Inside" is strictly below iso, everywhere in this file. The quad pass
				# below uses the identical predicate, which is what keeps the two passes
				# from disagreeing about which cells hold a vertex.
				var mask: int = (
					int(f0 < iso)
					| (int(f1 < iso) << 1)
					| (int(f2 < iso) << 2)
					| (int(f3 < iso) << 3)
					| (int(f4 < iso) << 4)
					| (int(f5 < iso) << 5)
					| (int(f6 < iso) << 6)
					| (int(f7 < iso) << 7)
				)
				if mask == 0 or mask == 255:
					continue

				cv[0] = f0
				cv[1] = f1
				cv[2] = f2
				cv[3] = f3
				cv[4] = f4
				cv[5] = f5
				cv[6] = f6
				cv[7] = f7
				var cell_min: Vector3 = Vector3(org.x + float(cx) * c, cell_y, cell_z)
				var crossings: PackedVector3Array = PackedVector3Array()
				for e: int in 12:
					var ia: int = edge_a[e]
					var ib: int = edge_b[e]
					if ((mask >> ia) & 1) == ((mask >> ib) & 1):
						continue
					# Differing mask bits guarantee va != vb, so this cannot divide by zero.
					var va: float = cv[ia]
					var vb: float = cv[ib]
					var t: float = (iso - va) / (vb - va)
					var pa: Vector3 = cell_min + corner_off[ia]
					var pb: Vector3 = cell_min + corner_off[ib]
					crossings.push_back(pa.lerp(pb, t))
				if crossings.is_empty():
					continue

				cell_vert[c_row + cx] = verts.size()
				verts.push_back(_place_vertex(crossings, cv, cell_min, c))

	# --- 3. Quads across sign-changing grid edges. --------------------------------------
	#
	# WINDING. Godot's front face is CLOCKWISE, which means the right-hand-rule cross
	# product (v1 - v0) x (v2 - v0) of a front-facing triangle points AWAY from the outside
	# viewer. Two independent confirmations, both from engine source:
	#   * SurfaceTool.generate_normals() takes Plane(v0, v1, v2).normal, and that Plane
	#     constructor defaults to CLOCKWISE: (v0 - v2).cross(v0 - v1) == -((v1 - v0).cross(v2 - v0)).
	#   * PlaneMesh, which declares normal +Y, emits its first triangle as
	#     (1,0,1), (-1,0,1), (1,0,-1) — right-hand-rule normal (0,-4,0), i.e. -Y.
	# So: OUTWARD NORMAL n REQUIRES (v1 - v0).cross(v2 - v0) TO POINT ALONG -n.
	#
	# For each axis the four cells around a grid edge are listed below in the order whose
	# right-hand-rule normal is -axis. That is exactly the order wanted when the edge runs
	# inside -> outside along +axis (outward normal +axis); when it runs outside -> inside
	# the list is walked backwards. Getting this inverted yields an inside-out mesh that
	# back-face culling renders as a hole, so each ordering is spelled out rather than
	# derived at runtime.
	var indices: PackedInt32Array = PackedInt32Array()

	# X edges: sample (x,y,z) -> (x+1,y,z), shared by cells (x, y-1|y, z-1|z).
	# Order (y-1,z-1), (y-1,z), (y,z), (y,z-1) gives right-hand-rule normal -X.
	for z: int in range(1, nz):
		for y: int in range(1, ny):
			var xe_row: int = sx * (y + sy * z)
			var xq_lo: int = nx * ((y - 1) + ny * (z - 1))
			var xq_zh: int = nx * ((y - 1) + ny * z)
			var xq_yh: int = nx * (y + ny * (z - 1))
			var xq_hi: int = nx * (y + ny * z)
			for x: int in nx:
				var s0: int = xe_row + x
				var inside_a: bool = samples[s0] < iso
				if inside_a == (samples[s0 + 1] < iso):
					continue
				var q0: int = cell_vert[xq_lo + x]
				var q1: int = cell_vert[xq_zh + x]
				var q2: int = cell_vert[xq_hi + x]
				var q3: int = cell_vert[xq_yh + x]
				if q0 < 0 or q1 < 0 or q2 < 0 or q3 < 0:
					continue
				if inside_a:
					indices.push_back(q0)
					indices.push_back(q1)
					indices.push_back(q2)
					indices.push_back(q0)
					indices.push_back(q2)
					indices.push_back(q3)
				else:
					indices.push_back(q0)
					indices.push_back(q3)
					indices.push_back(q2)
					indices.push_back(q0)
					indices.push_back(q2)
					indices.push_back(q1)

	# Y edges: sample (x,y,z) -> (x,y+1,z), shared by cells (x-1|x, y, z-1|z).
	# Order (x-1,z-1), (x,z-1), (x,z), (x-1,z) gives right-hand-rule normal -Y.
	for z: int in range(1, nz):
		for y: int in ny:
			var ye_row: int = sx * (y + sy * z)
			var yq_zl: int = nx * (y + ny * (z - 1))
			var yq_zh: int = nx * (y + ny * z)
			for x: int in range(1, nx):
				var s0: int = ye_row + x
				var inside_a: bool = samples[s0] < iso
				if inside_a == (samples[s0 + sx] < iso):
					continue
				var q0: int = cell_vert[yq_zl + x - 1]
				var q1: int = cell_vert[yq_zl + x]
				var q2: int = cell_vert[yq_zh + x]
				var q3: int = cell_vert[yq_zh + x - 1]
				if q0 < 0 or q1 < 0 or q2 < 0 or q3 < 0:
					continue
				if inside_a:
					indices.push_back(q0)
					indices.push_back(q1)
					indices.push_back(q2)
					indices.push_back(q0)
					indices.push_back(q2)
					indices.push_back(q3)
				else:
					indices.push_back(q0)
					indices.push_back(q3)
					indices.push_back(q2)
					indices.push_back(q0)
					indices.push_back(q2)
					indices.push_back(q1)

	# Z edges: sample (x,y,z) -> (x,y,z+1), shared by cells (x-1|x, y-1|y, z).
	# Order (x-1,y-1), (x-1,y), (x,y), (x,y-1) gives right-hand-rule normal -Z.
	for z: int in nz:
		for y: int in range(1, ny):
			var ze_row: int = sx * (y + sy * z)
			var zq_yl: int = nx * ((y - 1) + ny * z)
			var zq_yh: int = nx * (y + ny * z)
			for x: int in range(1, nx):
				var s0: int = ze_row + x
				var inside_a: bool = samples[s0] < iso
				if inside_a == (samples[s0 + sxy] < iso):
					continue
				var q0: int = cell_vert[zq_yl + x - 1]
				var q1: int = cell_vert[zq_yh + x - 1]
				var q2: int = cell_vert[zq_yh + x]
				var q3: int = cell_vert[zq_yl + x]
				if q0 < 0 or q1 < 0 or q2 < 0 or q3 < 0:
					continue
				if inside_a:
					indices.push_back(q0)
					indices.push_back(q1)
					indices.push_back(q2)
					indices.push_back(q0)
					indices.push_back(q2)
					indices.push_back(q3)
				else:
					indices.push_back(q0)
					indices.push_back(q3)
					indices.push_back(q2)
					indices.push_back(q0)
					indices.push_back(q2)
					indices.push_back(q1)

	# --- 4. Normals from the SDF gradient at the FINAL vertex. --------------------------
	# SPEC §9. Face normals on a coarse grid read as facets; the analytic gradient does not
	# care how coarse the grid is. Vertex count is O(n^2) against the O(n^3) sample grid, so
	# six extra SDF evaluations each is cheap. The gradient of a distance field points from
	# inside to outside, which is the outward normal with no sign fixup.
	var normals: PackedVector3Array = PackedVector3Array()
	var vcount: int = verts.size()
	normals.resize(vcount)
	var eps: float = maxf(c * NORMAL_EPS_FRAC, 1.0e-5)
	for i: int in vcount:
		var g: Vector3 = sdf.gradient(verts[i], eps)
		var glen: float = g.length()
		if glen > 1.0e-12:
			normals[i] = g / glen
		else:
			normals[i] = Vector3.UP

	return {
		"vertices": verts,
		"normals": normals,
		"indices": indices,
		"cells": nx * ny * nz,
		"cell_m": c,
		"dims": Vector3i(nx, ny, nz),
	}


## THE ONLY PLACE A VERTEX POSITION IS DECIDED.
##
## Returns the centroid of a cell's edge crossings — plain Surface Nets. SPEC §9's
## documented upgrade to Dual Contouring is a QEF solve over the crossings and their
## gradients, clamped to the cell, and it is a one-function swap ONLY while this stays the
## sole vertex-placement site. Do not inline a "small adjustment" at the call site.
## WHERE ONE CELL'S VERTEX GOES. The only such site in this file (see the class docs).
##
## Dual Contouring (ADR 0009): the point minimising the sum of squared distances to the TANGENT
## PLANES at the cell's edge crossings — `min_x sum_i (n_i . (x - p_i))^2` — which is what puts a
## vertex on a corner or an edge instead of rounding it off. `corners` are the cell's own eight
## samples in the bit order the caller packs them (bit0 = +x, bit1 = +y, bit2 = +z), `cell_min`
## its low corner and `size` its edge length.
##
## THE NORMALS ARE FREE. They come from the gradient of the TRILINEAR INTERPOLANT of those eight
## corner samples, not from [method ShipSdf.gradient] — no extra field evaluations at all, where
## sampling would have cost six per crossing and the field is the expensive part of a bake
## (FOLLOWUPS F5). It is also the more faithful normal for this purpose: the QEF is being solved
## against the surface the grid actually represents, and where that surface is planar the
## trilinear gradient is the plane's exact normal, which is the flat-seam case this was built for.
##
## Regularised toward the centroid and CLAMPED STRICTLY INTO THE CELL. The clamp is not a
## nicety: the quad pass joins the four cells around each sign-changing edge on the assumption
## that each vertex is inside its own cell, and a QEF on a near-flat ridge can otherwise solve to
## a point far outside it, which self-intersects the shell.
static func _place_vertex(
	crossings: PackedVector3Array, corners: PackedFloat32Array, cell_min: Vector3, size: float
) -> Vector3:
	var n: int = crossings.size()
	if n == 0:
		return cell_min + Vector3(size, size, size) * 0.5
	var centroid: Vector3 = Vector3.ZERO
	for i: int in n:
		centroid += crossings[i]
	centroid /= float(n)
	if size <= 0.0 or corners.size() < 8:
		return centroid

	# Normal equations of the QEF: AtA (symmetric, six unique terms) and Atb.
	var a00: float = 0.0
	var a01: float = 0.0
	var a02: float = 0.0
	var a11: float = 0.0
	var a12: float = 0.0
	var a22: float = 0.0
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	for i: int in n:
		var p: Vector3 = crossings[i]
		var local: Vector3 = (p - cell_min) / size
		var g: Vector3 = _trilinear_gradient(corners, local.x, local.y, local.z)
		var glen: float = g.length()
		if glen <= QEF_MIN_NORMAL:
			continue
		var nrm: Vector3 = g / glen
		var d: float = nrm.dot(p)
		a00 += nrm.x * nrm.x
		a01 += nrm.x * nrm.y
		a02 += nrm.x * nrm.z
		a11 += nrm.y * nrm.y
		a12 += nrm.y * nrm.z
		a22 += nrm.z * nrm.z
		b0 += nrm.x * d
		b1 += nrm.y * d
		b2 += nrm.z * d

	var lam: float = QEF_REGULARIZATION * float(n) + QEF_MIN_REGULARIZATION
	a00 += lam
	a11 += lam
	a22 += lam
	b0 += lam * centroid.x
	b1 += lam * centroid.y
	b2 += lam * centroid.z

	var m00: float = a11 * a22 - a12 * a12
	var m01: float = a01 * a22 - a12 * a02
	var m02: float = a01 * a12 - a11 * a02
	var det: float = a00 * m00 - a01 * m01 + a02 * m02
	if absf(det) < QEF_MIN_DET:
		return centroid
	var x: float = (b0 * m00 - a01 * (b1 * a22 - a12 * b2) + a02 * (b1 * a12 - a11 * b2)) / det
	var y: float = (a00 * (b1 * a22 - a12 * b2) - b0 * m01 + a02 * (a01 * b2 - b1 * a02)) / det
	var z: float = (a00 * (a11 * b2 - b1 * a12) - a01 * (a01 * b2 - b1 * a02) + b0 * m02) / det
	if not (is_finite(x) and is_finite(y) and is_finite(z)):
		return centroid
	return Vector3(
		clampf(x, cell_min.x, cell_min.x + size),
		clampf(y, cell_min.y, cell_min.y + size),
		clampf(z, cell_min.z, cell_min.z + size)
	)


## Gradient of the trilinear interpolant of a cell's eight corner samples at local coordinates
## `(u, v, w)` in [0, 1], corners in the caller's bit order (bit0 = +x, bit1 = +y, bit2 = +z).
##
## Returned UNSCALED — the true gradient is this over the cell size, and every axis carries the
## same factor, so for a direction it cancels. [method _place_vertex] normalises it.
static func _trilinear_gradient(
	corners: PackedFloat32Array, u: float, v: float, w: float
) -> Vector3:
	var iu: float = 1.0 - u
	var iv: float = 1.0 - v
	var iw: float = 1.0 - w
	var gx: float = (
		iv * iw * (corners[1] - corners[0])
		+ v * iw * (corners[3] - corners[2])
		+ iv * w * (corners[5] - corners[4])
		+ v * w * (corners[7] - corners[6])
	)
	var gy: float = (
		iu * iw * (corners[2] - corners[0])
		+ u * iw * (corners[3] - corners[1])
		+ iu * w * (corners[6] - corners[4])
		+ u * w * (corners[7] - corners[5])
	)
	var gz: float = (
		iu * iv * (corners[4] - corners[0])
		+ u * iv * (corners[5] - corners[1])
		+ iu * v * (corners[6] - corners[2])
		+ u * v * (corners[7] - corners[3])
	)
	return Vector3(gx, gy, gz)


## The spacing [method extract] will actually sample [param size] at when asked for [param cell]:
## [param cell] itself, or the coarser spacing the [constant MAX_CELLS] cap forces. Public so a
## caller can size anything that must span at least one grid cell to be seen - the seam plates
## [HullBake] widens (ADR 0008) - against the grid that will really be used, not the one asked for.
static func fitted_cell(size: Vector3, cell: float) -> float:
	return _fit_cell(size.abs(), cell)


## Coarsens [param cell] upward until the grid over [param size] fits [constant MAX_CELLS].
##
## Returns [param cell] unchanged when it already fits. The continuous solve runs first so
## the iterative pass never has to evaluate an absurd cell count; the iterative pass then
## corrects for [code]ceil()[/code] rounding and for thin axes that pin to a single cell,
## which the cube root alone under-corrects.
static func _fit_cell(size: Vector3, cell: float) -> float:
	var ex: float = maxf(size.x, MIN_CELL_M)
	var ey: float = maxf(size.y, MIN_CELL_M)
	var ez: float = maxf(size.z, MIN_CELL_M)
	var c: float = maxf(cell, MIN_CELL_M)
	var ideal: float = pow(ex * ey * ez / float(MAX_CELLS), 1.0 / 3.0)
	if ideal > c:
		c = ideal
	var guard: int = 0
	while guard < 64:
		var count: float = _cell_count_f(ex, ey, ez, c)
		if count <= float(MAX_CELLS):
			break
		c *= maxf(pow(count / float(MAX_CELLS), 1.0 / 3.0), 1.001) * 1.01
		guard += 1
	# Upper clamp so pathological (non-finite-adjacent) input still yields finite positions.
	return clampf(c, MIN_CELL_M, 1.0e6)


## Cell count as a float, so a nonsense spacing cannot overflow an int on the way to being
## rejected by [method _fit_cell].
static func _cell_count_f(ex: float, ey: float, ez: float, c: float) -> float:
	return maxf(1.0, ceilf(ex / c)) * maxf(1.0, ceilf(ey / c)) * maxf(1.0, ceilf(ez / c))


static func _finite_v3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _empty_result(cell_m: float) -> Dictionary:
	return {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"indices": PackedInt32Array(),
		"cells": 0,
		"cell_m": cell_m,
		"dims": Vector3i.ZERO,
	}
