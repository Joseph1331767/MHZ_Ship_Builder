class_name MeshFlange
## Flat flanges: two solids that overlap, resolved into a flush flat joint on a plane taken from
## where their SURFACES ACTUALLY CROSS.
##
## WHY THE OLD FLAT WAS WRONG. It cut on the plane through the ATTACH POINT — the tangent to the
## host there. On a flat host face that is the host's surface and the fit is exact; on a sphere, or
## at a box corner, it is a tangent and nothing else, so the cut landed nowhere near where the two
## solids meet: "somehow it cut the upper sphere way into the sphere, and short of the lower sphere.
## so the cuts arent happening at intersection."
##
## WHERE THE PLANE COMES FROM NOW. The two surfaces cross along a curve. Every point of that curve
## is projected onto the joint axis, and the plane is put through the extreme one — the DEEPEST for
## an in-bump, the OUTERMOST for an out-bump — with its normal along that axis. For two spheres the
## crossing curve is a circle and is already planar, so the plane lands exactly on it and the joint
## is exact. For a box corner or a tilted joint the curve is not planar, and the extreme point is
## the honest flat answer: no part of either solid is left crossing the other.
##
## LARGER AND SMALLER, NOT PARENT AND CHILD. Which solid gets cut back and which gets flattened is
## decided by VOLUME, not by the attach tree — "we must first classify which part is inside of which
## part, probably based on size and if they are overlapping" — because a small part is perfectly
## able to be the parent of a large one.
##
## FOUR COMBINATIONS, from two independent choices. The plane sits at the deepest crossing (IN) or
## the outermost (OUT); and the cut reaches only across the smaller solid's own cross-section
## (a FLANGE, a pad let into the host) or straight through the larger solid (a SLICE, a facet across
## the whole thing). A slice reads as a machined flat; a flange leaves the host's shape alone
## everywhere the joint does not touch.
##
## Pure data (SPEC §12): static-only, no [Node], no [SceneTree], no [code]res://[/code].
## Arguments are never mutated.

## Bisection steps used to walk a mesh edge onto the other solid's surface. Twenty halvings take
## an edge of any plausible length to well under a micrometre.
const BISECT_STEPS: int = 20

## A crossing must be this far inside the edge to count, as a fraction of it. An edge that merely
## touches the other surface at an endpoint is not a crossing and would place the plane at a point
## the two solids only graze.
const EDGE_MARGIN: float = 1.0e-4

## How far the footprint cutter is extruded past the plane, as a multiple of the smaller solid's
## own extent. Only has to clear the larger solid.
const CUTTER_REACH: float = 2.0

## How close two volumes have to be to count as one size - see [method first_is_larger]. Well above
## the noise two tessellations of one solid carry (about 1e-6 relative on a Vector3 pipeline) and
## well below any difference the author could have meant.
const TIE_REL: float = 1.0e-4

## How much of the distance from the origin two plane distances may differ by and still be read as
## the same plane - see [method _plane_match_tolerance].
const PLANE_D_REL: float = 1.0e-5


## One solid: its mesh, and the field that says where its surface is.
##
## The field is [ResolvedShape] evaluated in the part's own local space, which is exactly what
## [method ShipSdf.sample_part] does — the same shape, the same inverse transform, the same
## conservative distance scale for a non-rigid basis. It is used ONLY as a predicate here, to ask
## whether a point is on a surface; no geometry is taken from it.
class Piece:
	extends RefCounted

	var mesh: PolyMesh = null
	var shape: ResolvedShape = null
	var inv: Transform3D = Transform3D.IDENTITY
	var scale: float = 1.0

	static func make(mesh_in: PolyMesh, shape_in: ResolvedShape, xform: Transform3D) -> Piece:
		var out: Piece = Piece.new()
		out.mesh = mesh_in
		out.shape = shape_in
		out.inv = xform.affine_inverse()
		var b: Basis = xform.basis
		out.scale = minf(b.x.length(), minf(b.y.length(), b.z.length()))
		if out.scale <= 0.000001:
			out.scale = 1.0
		return out

	func distance(p: Vector3) -> float:
		return shape.sdf(inv * p) * scale


## Resolves the overlap of [param a] and [param b] into a flat joint.
##
## [param axis] and [param origin] are the joint's own frame — the seam normal and the point it
## passes through — used to measure "how far out" a crossing is. [param outward] picks the
## outermost crossing instead of the deepest; [param slice] cuts the larger solid with the whole
## plane instead of only across the smaller one's cross-section.
##
## Returns [code]{ "a": PolyMesh, "b": PolyMesh, "plane": Plane, "depth": float }[/code], or an
## EMPTY dictionary when the two do not cross — in which case the caller should leave both alone,
## because there is no joint to flatten.
static func resolve(
	a: Piece,
	b: Piece,
	axis: Vector3,
	origin: Vector3,
	outward: bool,
	slice: bool,
	inset: float = 0.0
) -> Dictionary:
	if a == null or b == null or a.mesh == null or b.mesh == null:
		return {}
	if a.mesh.is_empty() or b.mesh.is_empty() or axis.length_squared() < 1.0e-12:
		return {}

	# Larger and smaller by volume, and the axis oriented to point from the larger toward it.
	var a_big: bool = first_is_larger(a.mesh, b.mesh)
	var large: Piece = a if a_big else b
	var small: Piece = b if a_big else a
	var up: Vector3 = axis.normalized()
	var large_centre: Vector3 = large.mesh.aabb().get_center()
	var small_centre: Vector3 = small.mesh.aabb().get_center()
	if (small_centre - large_centre).dot(up) < 0.0:
		up = -up

	var span: Vector2 = _crossing_span(large, small, up, origin)
	if not is_finite(span.x):
		return {}
	var depth: float = span.y if outward else span.x
	var plane: Plane = Plane(up, up.dot(origin + up * depth))

	# The smaller solid keeps its outward side and comes out flat on the plane. clip_to_plane keeps
	# the side its normal points AWAY from, so the normal is reversed to keep the +up side.
	# BOTH SIDES RETREAT BY THE INSET, in opposite directions (ADR 0015). The plane itself is
	# where the two outer surfaces meet; an INTERIOR surface has to stop short of it on whichever
	# side it is on, or the cavity would open onto the seam face - and "the hatch and seam
	# surfaces remain solid".
	var small_plane: Plane = Plane(-up, -(plane.d + inset))
	var large_plane: Plane = Plane(up, plane.d - inset)
	var small_cut: PolyMesh = MeshCsg.clip_to_plane(small.mesh, small_plane)
	if small_cut.is_empty():
		return {}

	var large_cut: PolyMesh = large.mesh
	if outward:
		# OUT: the larger solid gains the smaller one's material up to the plane, so the pair
		# closes flush at a raised pad. Slicing additionally takes the larger one back to the
		# plane, which is what turns the pad into a facet across the whole solid.
		if slice:
			large_cut = MeshCsg.clip_to_plane(large_cut, large_plane)
		var stub: PolyMesh = MeshCsg.clip_to_plane(small.mesh, large_plane)
		if not stub.is_empty():
			large_cut = _add_stub(large_cut, stub)
	elif slice:
		large_cut = MeshCsg.clip_to_plane(large_cut, large_plane)
	else:
		# IN, flanged: only the smaller solid's own cross-section is let into the larger one, so
		# the host keeps its shape everywhere the joint does not reach.
		# THE PRISM STANDS ON THE LARGE SOLID SIDE OF THE SEAM, WHICH IS WHY IT IS DROPPED BY TWO
		# INSETS. Its cap is read off the smaller solid, and that cap has already retreated to
		# `plane + inset`; subtracting a prism from there would stop the larger solid CAVITY at
		# `plane + inset` too - past the seam, not short of it - so the two cavities would meet and
		# the smaller solid own plate would be left standing inside the larger one room. Dropping
		# the base by 2 * inset puts it at `plane - inset`, which is where large_plane already says
		# the larger solid has to stop. At inset 0 the drop is 0 and the outer cut is unchanged.
		var cutter: PolyMesh = _footprint_cutter(
			small_cut, small_plane_face(plane, inset), up, 2.0 * inset
		)
		if cutter.is_empty():
			large_cut = MeshCsg.clip_to_plane(large_cut, large_plane)
		else:
			large_cut = MeshMerge.merge(MeshCsg.subtract(large_cut, cutter))

	# NEVER HAND BACK A SOLID WORSE THAN THE ONE THAT CAME IN. A part can be the host of many
	# seams - a carbon nucleus carries nine - and each is resolved against the result of the last,
	# so one broken result feeds the next operation and the damage compounds rather than staying
	# put. Measured before this: `big_flat_cutoff` on a carbon class left the nucleus centre open,
	# nine plane cuts and stub unions deep. Refusing costs a joint that stays overlapped, which is
	# a gap the author allowed for and is a far better answer than an open hull.
	if large_cut.open_edges() != 0 and large.mesh.open_edges() == 0:
		large_cut = large.mesh
	if small_cut.open_edges() != 0 and small.mesh.open_edges() == 0:
		small_cut = small.mesh

	return {
		"a": large_cut if a_big else small_cut,
		"b": small_cut if a_big else large_cut,
		"plane": plane,
		"depth": depth,
	}


## Is [param a] the larger of the two by volume - with a TIE going to [param a]?
##
## ONE RULE, USED BY EVERY SEAM, WITH A TOLERANCE. Two protons of one class are the same solid
## under two transforms, and their tessellated volumes differ in the last few bits: measured on a
## carbon class, a plain `>=` sent some of a root's six children to one side of the tie and some
## to the other, so the root was indented by three neighbours and indenting the other two, and came
## out of the bake at 247 m3 - two and a half sealed shells' worth - with one child at 528. The
## tie is a tie to within TIE_REL of the larger volume, and it goes to the first argument, which
## every caller passes the CHILD as: a walled seam and an open one on the same pair then indent the
## same way, whichever pass sees them.
static func first_is_larger(a: PolyMesh, b: PolyMesh) -> bool:
	var va: float = a.volume()
	var vb: float = b.volume()
	return va >= vb - TIE_REL * maxf(absf(va), absf(vb))


## How far along [param up] the two surfaces cross, as `(nearest, furthest)` measured from
## [param origin]. Returns a non-finite x when they do not cross at all.
##
## Walks the edges of each mesh and bisects any that changes side of the OTHER solid's surface.
## Both meshes are walked because either one alone can miss the extremes: a coarse tessellation of
## the smaller solid may step straight over a shallow crossing that the larger one's edges catch.
static func _crossing_span(large: Piece, small: Piece, up: Vector3, origin: Vector3) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	for pair: Array in [[large, small], [small, large]]:
		var walk: Piece = pair[0]
		var against: Piece = pair[1]
		var edges: PackedInt32Array = walk.mesh.boundary_edges()
		var i: int = 0
		while i + 1 < edges.size():
			var pa: Vector3 = walk.mesh.vertices[edges[i]]
			var pb: Vector3 = walk.mesh.vertices[edges[i + 1]]
			i += 2
			var da: float = against.distance(pa)
			var db: float = against.distance(pb)
			if (da > 0.0) == (db > 0.0):
				continue
			var hit: Vector3 = _bisect(against, pa, pb, da)
			var t: float = (hit - origin).dot(up)
			lo = minf(lo, t)
			hi = maxf(hi, t)
	if not is_finite(lo) or not is_finite(hi):
		return Vector2(INF, INF)
	return Vector2(lo, hi)


## The point on the segment [param pa]-[param pb] where [param against]'s surface crosses it.
static func _bisect(against: Piece, pa: Vector3, pb: Vector3, da: float) -> Vector3:
	var lo: Vector3 = pa
	var hi: Vector3 = pb
	var lo_neg: bool = da < 0.0
	for _step: int in BISECT_STEPS:
		var mid: Vector3 = (lo + hi) * 0.5
		if (against.distance(mid) < 0.0) == lo_neg:
			lo = mid
		else:
			hi = mid
	assert(EDGE_MARGIN > 0.0)
	return (lo + hi) * 0.5


## How far two plane distances may differ and still be the same plane, for a solid sitting where
## [param cut] sits. RELATIVE, NOT ABSOLUTE (2026-09-22): a plane's `d` is measured from the world
## ORIGIN and a [PolyMesh] holds its vertices as 32-bit floats, so the same geometric plane computed
## two ways drifts further apart the further the ship is from the origin - about 2.4e-6 m a
## coordinate at 20 m, and more once a Newell normal has accumulated it. With the ships centred on
## the beacon (ADR 0033) rather than pinned by their first module, a fixed 1e-4 stopped finding the
## cap at all: measured, in-bump and out-bump baked the same carbon to within 6.2e-5 m3 where the
## same ship at the old origin differed by 5.5e-3.
static func _plane_match_tolerance(plane: Plane, cut: PolyMesh) -> float:
	var box: AABB = cut.aabb()
	var reach: float = absf(plane.d) + box.position.length() + box.size.length()
	return maxf(EDGE_MARGIN, PLANE_D_REL * reach)


## A prism over [param cut]'s flat face, standing along [param up], for letting exactly that
## cross-section into the larger solid and nothing else.
##
## The cross-section is read back off the already-clipped smaller solid rather than computed again:
## its cap is the face lying in [param plane], so the two can never disagree about where the
## footprint is. Returns an empty mesh when no cap can be identified, which sends the caller to the
## plain plane cut.
##
## [param drop] lowers the prism base along -[param up] before it is extruded, without moving the
## cross-section it is cut from. The interior pass needs the same footprint standing a wall-and-a-
## half further back than the face it was read off - see the caller.
static func _footprint_cutter(
	cut: PolyMesh, plane: Plane, up: Vector3, drop: float = 0.0
) -> PolyMesh:
	var reach: float = maxf(cut.aabb().size.length(), 1.0) * CUTTER_REACH + maxf(drop, 0.0)
	var best: int = -1
	var best_area: float = 0.0
	for i: int in cut.face_count():
		var face_plane: Plane = cut.face_plane(i)
		if face_plane.normal.dot(up) < 0.999:
			continue
		if absf(face_plane.d - plane.d) > _plane_match_tolerance(plane, cut):
			continue
		var area: float = absf(_loop_area(cut, cut.faces[i]))
		if area > best_area:
			best_area = area
			best = i
	if best < 0:
		return PolyMesh.new()

	var loop: PackedInt32Array = cut.faces[best]
	var base: PackedVector3Array = PackedVector3Array()
	for id: int in loop:
		base.append(cut.vertices[id] - up * drop)
	var polys: Array = []
	# The cap face already points along +up, so it is the prism's top once lifted.
	var top: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in base:
		top.append(p + up * reach)
	polys.append(top)
	var bottom: PackedVector3Array = base.duplicate()
	bottom.reverse()
	polys.append(bottom)
	var n: int = base.size()
	for i: int in n:
		var j: int = (i + 1) % n
		polys.append(
			PackedVector3Array([base[i], base[j], base[j] + up * reach, base[i] + up * reach])
		)
	return PolyMesh.from_polygons(polys)


## The plane the smaller solid's flat face actually lands on, which is the seam plane pushed out
## by the inset. [method _footprint_cutter] looks the face up by its plane, so it has to be told
## the same one the cut used rather than the seam's own.
static func small_plane_face(plane: Plane, inset: float) -> Plane:
	return Plane(plane.normal, plane.d + inset)


## Twice the area of a loop, by Newell — used only to pick the largest cap.
static func _loop_area(mesh: PolyMesh, loop: PackedInt32Array) -> float:
	var total: Vector3 = Vector3.ZERO
	var n: int = loop.size()
	for i: int in n:
		total += mesh.vertices[loop[i]].cross(mesh.vertices[loop[(i + 1) % n]])
	return total.length() * 0.5


## [param large] with [param stub] welded on, or [param large] UNCHANGED if that cannot be done
## without opening it.
##
## A UNION THAT BREAKS A SOLID MUST NOT BE KEPT, because the next one is taken against its result.
## Measured on `argon`, whose hub takes eight out-bump stubs: the first union came out at 101 faces
## and closed, the second left 60 open edges, and from there each union was fed a broken mesh -
## 5263 open edges and 20 seconds by the fifth, 11049 and 73 seconds by the seventh. Refusing the
## bad result stops the compounding dead, and the cost is a stub that is not added: the two parts
## meet with a gap where they would have met flush, which the author allowed for - "if a thin
## unseen buffer of space is needed between modules thats fine" - and which is a far better answer
## than a hull with eleven thousand open edges in it.
##
## The merged form is preferred, the raw union accepted if only the merge spoiled it, and neither
## if both are open.
static func _add_stub(large: PolyMesh, stub: PolyMesh) -> PolyMesh:
	var joined: PolyMesh = MeshCsg.union(large, stub)
	if joined.truncated:
		return large
	var tidied: PolyMesh = MeshMerge.merge(joined)
	if tidied.open_edges() == 0:
		return tidied
	if joined.open_edges() == 0:
		return joined
	return large
