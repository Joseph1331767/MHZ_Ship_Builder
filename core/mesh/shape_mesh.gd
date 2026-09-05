class_name ShapeMesh
## A [ResolvedShape] tessellated into an exact [PolyMesh] — the entry point of the mesh bake.
##
## EXACT MEANS PLANE-EXACT, NOT CURVE-EXACT, and the distinction is the same one SketchUp makes.
## A box is six faces at any size, a cut is a straight line, and nothing is sampled on a grid.
## A circle is a [constant RADIAL_SEGMENTS]-gon, because a polygon mesh has no other way to be a
## circle — SketchUp's default is 24 for exactly this reason and this file matches it.
##
## THE OPS ARE INVERTED, NOT RE-DERIVED. [method ResolvedShape.sdf] warps the DOMAIN and then asks
## a primitive: `prim(shear(twist(taper(p / scale))))`. So the surface is the base primitive's
## surface carried BACKWARDS through those warps, and a vertex is placed by tessellating the base
## and applying `scale * taper⁻¹(twist⁻¹(shear⁻¹(q)))`. All three warps leave `y` untouched and act
## only on `x` and `z`, which is what makes each inverse a closed form rather than a solve — and
## what keeps this mesh on the SDF's surface rather than merely near it.
##
## WHICH WARPS KEEP A FACE FLAT. Taper scales `x` and `z` by a factor LINEAR in `y`, and shear
## slides them by an offset linear in `y`, so both carry a plane to a plane and a box stays six
## faces. TWIST DOES NOT: rotating by an angle that grows with `y` turns a flat side into a
## helicoid, which no quad can represent. So a twisted shape is subdivided along `y` and its faces
## are triangulated ([constant TWIST_SLABS]) — the one place this file trades n-gons for honesty.
##
## WHAT IT DOES NOT BUILD YET, by decision rather than oversight: `round_r` (the inflate op),
## ribs and scallops. Those are OFFSET and DISPLACEMENT ops, not domain warps, so they cannot be
## reached by moving a base vertex — a rounded box needs real fillet geometry along twelve edges
## and eight corners. Deferred deliberately (FOLLOWUPS F22): a part bakes with sharp edges and
## reads very slightly larger and crisper than its field says.
##
## Pure data (SPEC §12): static-only, no [Node], no [SceneTree], no [code]res://[/code].
## Arguments are never mutated.

## Segments around a full revolution. SketchUp's default circle is 24-sided; matching it is not
## imitation but the same trade — fine enough that a tube reads as round, coarse enough that its
## facets are a deliberate, countable feature rather than a mesh that quietly costs thousands.
const RADIAL_SEGMENTS: int = 24

## Segments per quarter-turn of a profile arc (an end fillet, a sphere cap).
const ARC_SEGMENTS: int = 6

## Rows a twisted shape is cut into along `y`. A helicoid has no flat faces, so the only question
## is how finely to approximate it; this is per shape, not per metre, so a long part twists as
## smoothly as a short one.
const TWIST_SLABS: int = 24

## Radii and heights below this are treated as degenerate rather than as geometry.
const MIN_EXTENT_M: float = 0.0001


## [param shape] as a closed [PolyMesh] in the part's local space, [param segments] around.
##
## Returns an empty mesh for a null or degenerate shape. The result is wound CCW-outward, the
## convention of [PolyMesh] and [MeshCsg]; the flip to Godot's clockwise front face happens once,
## in [method PolyMesh.to_array_mesh].
static func build(shape: ResolvedShape, segments: int = RADIAL_SEGMENTS) -> PolyMesh:
	if shape == null or _collapsed(shape):
		return PolyMesh.new()
	var cols: int = maxi(segments, 3)
	var twisted: bool = not is_zero_approx(shape.twist_deg)
	var base: PolyMesh = _base_mesh(shape, cols, twisted)
	if base.is_empty():
		return base
	return _warped(base, shape, twisted)


## [param shape] with its primitive moved inward by [param thickness] WORLD metres, for building
## an interior surface. A negative thickness grows it instead, which is how a cutter is fattened.
##
## ANALYTIC, NOT A MESH OFFSET. Insetting a polygon mesh by a constant distance is genuinely hard -
## miters, self-intersections, vanishing features - and it is the one thing ADR 0011 named as the
## reason polygons could not carry an interior shell. They do not have to: every part comes from a
## PARAMETRIC primitive, so the inner surface is the same primitive with smaller numbers, carried
## through the same domain warps and the same transform. Exact for a box, and correct to the
## tessellation for everything round.
##
## THE SHRINK IS PER AXIS, DIVIDED BY THE SCALE. `scale` is applied after the primitive, so a local
## shrink of `d` becomes a wall of `d * scale` in the world; dividing by the scale first is what
## keeps the wall the thickness that was asked for. Where one number has to serve a whole
## primitive - a sphere's single radius, a cylinder's round section - the SMALLEST scale component
## is used, which errs toward walls that are too thick rather than too thin.
##
## Returns a shape whose primitive has collapsed (a zero or negative dimension) when the part is
## thinner than twice the thickness. [method build] hands that back as an empty mesh, and a part
## with no interior is correctly left solid.
static func inset(shape: ResolvedShape, thickness: float) -> ResolvedShape:
	var out: ResolvedShape = shape.smooth_copy()
	out.rib_count = shape.rib_count
	out.rib_amp = shape.rib_amp
	out.scallop_amp = shape.scallop_amp
	if is_zero_approx(thickness):
		return out
	var sx: float = maxf(absf(shape.scale.x), MIN_EXTENT_M)
	var sy: float = maxf(absf(shape.scale.y), MIN_EXTENT_M)
	var sz: float = maxf(absf(shape.scale.z), MIN_EXTENT_M)
	var radial: float = thickness / minf(sx, sz)
	var axial: float = thickness / sy
	match shape.base:
		ResolvedShape.Base.BOX:
			out.size = shape.size - Vector3(thickness / sx, axial, thickness / sz)
		ResolvedShape.Base.SPHERE:
			var uniform: float = thickness / minf(sx, minf(sy, sz))
			out.size = Vector3(shape.size.x - uniform, shape.size.y, shape.size.z)
		ResolvedShape.Base.CYLINDER:
			out.size = Vector3(shape.size.x - radial, shape.size.y - axial, shape.size.z)
			if shape.radius_b >= 0.0:
				out.radius_b = maxf(shape.radius_b - radial, 0.0)
			out.end_round = maxf(shape.end_round - radial, 0.0)
		ResolvedShape.Base.CONE:
			out.size = Vector3(shape.size.x - radial, shape.size.y - axial, shape.size.z)
		ResolvedShape.Base.CAPSULE:
			# The caps shrink with the radius, so only the radius moves: taking the half-height in
			# as well would pull the two hemispheres past each other on a stubby capsule.
			out.size = Vector3(shape.size.x - radial, shape.size.y, shape.size.z)
		ResolvedShape.Base.TORUS:
			# The ring stays where it is and the tube thins: a torus insetted through its major
			# radius would turn inside out rather than hollow.
			out.size = Vector3(shape.size.x, shape.size.y - radial, shape.size.z)
	out.refresh()
	return out


## True when the primitive has no room left in it - which is what [method inset] hands back for a
## part thinner than twice the wall. An empty mesh is the right answer: that part has no interior
## and is correctly left solid, rather than being given one turned inside out.
static func _collapsed(shape: ResolvedShape) -> bool:
	match shape.base:
		ResolvedShape.Base.BOX:
			return (
				shape.size.x <= MIN_EXTENT_M
				or shape.size.y <= MIN_EXTENT_M
				or shape.size.z <= MIN_EXTENT_M
			)
		ResolvedShape.Base.SPHERE:
			return shape.size.x <= MIN_EXTENT_M
		ResolvedShape.Base.CYLINDER, ResolvedShape.Base.CONE:
			return shape.size.x <= MIN_EXTENT_M or shape.size.y <= MIN_EXTENT_M
		ResolvedShape.Base.CAPSULE:
			return shape.size.x <= MIN_EXTENT_M
		ResolvedShape.Base.TORUS:
			return shape.size.x <= MIN_EXTENT_M or shape.size.y <= MIN_EXTENT_M
	return false


## The unwarped, unscaled primitive: what [method ResolvedShape.sdf] asks after the domain warps.
static func _base_mesh(shape: ResolvedShape, cols: int, twisted: bool) -> PolyMesh:
	var rows: int = TWIST_SLABS if twisted else 1
	match shape.base:
		ResolvedShape.Base.BOX:
			return _box(shape.size, rows)
		ResolvedShape.Base.SPHERE:
			return _lathe(_sphere_profile(shape.size.x), cols, false)
		ResolvedShape.Base.CYLINDER:
			return _lathe(_cone_profile(shape, twisted), cols, false)
		ResolvedShape.Base.CONE:
			return _lathe(_pointed_profile(shape.size.x, shape.size.y), cols, false)
		ResolvedShape.Base.CAPSULE:
			return _lathe(_capsule_profile(shape.size.x, shape.size.y), cols, false)
		ResolvedShape.Base.TORUS:
			return _lathe(_torus_profile(shape.size.x, shape.size.y), cols, true)
	return _box(shape.size, rows)


# --- primitives ---------------------------------------------------------------------------------


## A box of half-extents [param half], its four sides cut into [param rows] bands.
##
## The bands exist only for twist: a twisted side is a helicoid and one quad cannot describe it.
## At `rows == 1` this is the six-face box it should be.
static func _box(half: Vector3, rows: int) -> PolyMesh:
	var h: Vector3 = half.abs()
	if h.x < MIN_EXTENT_M or h.y < MIN_EXTENT_M or h.z < MIN_EXTENT_M:
		return PolyMesh.new()
	var bands: int = maxi(rows, 1)
	var levels: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(bands + 1):
		levels.append(lerpf(-h.y, h.y, float(i) / float(bands)))

	# The four side corners in order around +Y, anticlockwise seen from above.
	var ring: Array[Vector2] = [
		Vector2(h.x, h.z), Vector2(-h.x, h.z), Vector2(-h.x, -h.z), Vector2(h.x, -h.z)
	]
	var polys: Array = []
	for b: int in bands:
		var y0: float = levels[b]
		var y1: float = levels[b + 1]
		for i: int in 4:
			var a: Vector2 = ring[i]
			var c: Vector2 = ring[(i + 1) % 4]
			(
				polys
				. append(
					PackedVector3Array(
						[
							Vector3(a.x, y0, a.y),
							Vector3(a.x, y1, a.y),
							Vector3(c.x, y1, c.y),
							Vector3(c.x, y0, c.y),
						]
					)
				)
			)
	# Caps. +Y anticlockwise seen from +Y, -Y the other way round.
	var top: PackedVector3Array = PackedVector3Array()
	var bottom: PackedVector3Array = PackedVector3Array()
	for i: int in 4:
		top.append(Vector3(ring[3 - i].x, h.y, ring[3 - i].y))
		bottom.append(Vector3(ring[i].x, -h.y, ring[i].y))
	polys.append(top)
	polys.append(bottom)
	return PolyMesh.from_polygons(polys)


## Revolves a `(radius, y)` profile about +Y.
##
## [param wrap] closes the profile back on itself, which is what makes a torus a torus rather
## than an open tube. An open profile is expected to start and end on the axis; a row at radius
## zero collapses its quads into triangles on its own, because [method PolyMesh.from_polygons]
## drops the repeated vertex.
static func _lathe(profile: PackedVector2Array, cols: int, wrap: bool) -> PolyMesh:
	var rows: int = profile.size()
	if rows < 2:
		return PolyMesh.new()
	var polys: Array = []
	var last: int = rows if wrap else rows - 1
	for r: int in last:
		var lo: Vector2 = profile[r]
		var hi: Vector2 = profile[(r + 1) % rows]
		for c: int in cols:
			var a0: float = TAU * float(c) / float(cols)
			var a1: float = TAU * float(c + 1) / float(cols)
			# Lower ring first, then up, then round: the right-hand normal points outward.
			(
				polys
				. append(
					PackedVector3Array(
						[
							Vector3(lo.x * cos(a0), lo.y, lo.x * sin(a0)),
							Vector3(hi.x * cos(a0), hi.y, hi.x * sin(a0)),
							Vector3(hi.x * cos(a1), hi.y, hi.x * sin(a1)),
							Vector3(lo.x * cos(a1), lo.y, lo.x * sin(a1)),
						]
					)
				)
			)
	return PolyMesh.from_polygons(polys)


## Half a circle, south pole to north pole.
static func _sphere_profile(radius: float) -> PackedVector2Array:
	var r: float = maxf(absf(radius), MIN_EXTENT_M)
	var out: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(ARC_SEGMENTS * 2, 4)
	for i: int in range(steps + 1):
		var phi: float = PI * float(i) / float(steps)
		out.append(Vector2(r * sin(phi), -r * cos(phi)))
	return out


## The rounded-cone profile of a CYLINDER, bottom pole to top pole (ADR 0005).
##
## Ported from `ShipMeshGen._rounded_cone_profile`, which `harness/` uses for the preview and
## which `core/` may not reach into. The straight flank is the cone through the two fillet
## CENTRES pushed out along its own normal by `e`; building it from the centres is what makes a
## frustum's fillets meet the flank tangentially instead of leaving a crease.
##
## The preview's version also narrows the +Y radius as a stand-in for taper. THIS ONE MUST NOT:
## taper is a real domain warp here and is applied, exactly, by [method _warped]. Doing both
## would taper the shape twice.
static func _cone_profile(shape: ResolvedShape, twisted: bool) -> PackedVector2Array:
	var r1: float = maxf(absf(shape.size.x), MIN_EXTENT_M)
	var r2: float = maxf(shape.radius_b if shape.radius_b >= 0.0 else r1, 0.0)
	var h: float = maxf(absf(shape.size.y), MIN_EXTENT_M)
	var e: float = clampf(maxf(shape.end_round, 0.0), 0.0, minf(maxf(r1, r2), h))
	var out: PackedVector2Array = PackedVector2Array()
	if e <= MIN_EXTENT_M:
		out.append(Vector2(0.0, -h))
		out.append(Vector2(r1, -h))
		out.append(Vector2(r2, h))
		out.append(Vector2(0.0, h))
		return _densified(out, twisted)
	var c1: Vector2 = Vector2(maxf(r1 - e, 0.0), -h + e)
	var c2: Vector2 = Vector2(maxf(r2 - e, 0.0), h - e)
	var flank: Vector2 = c2 - c1
	var normal: Vector2 = Vector2(flank.y, -flank.x)
	if normal.length_squared() < 1.0e-12:
		normal = Vector2(1.0, 0.0)
	var a_flank: float = normal.normalized().angle()
	_append_unique(out, Vector2(0.0, -h))
	_append_arc(out, c1, e, -PI * 0.5, a_flank)
	_append_arc(out, c2, e, a_flank, PI * 0.5)
	_append_unique(out, Vector2(0.0, h))
	return _densified(out, twisted)


## A cone: flat base at -Y, sharp apex at +Y (API_CONTRACT §6).
static func _pointed_profile(radius: float, half_h: float) -> PackedVector2Array:
	var r: float = maxf(absf(radius), MIN_EXTENT_M)
	var h: float = maxf(absf(half_h), MIN_EXTENT_M)
	return PackedVector2Array([Vector2(0.0, -h), Vector2(r, -h), Vector2(0.0, h)])


## A capsule: a cylinder of half-height [param half_h] with a hemisphere on each end.
static func _capsule_profile(radius: float, half_h: float) -> PackedVector2Array:
	var r: float = maxf(absf(radius), MIN_EXTENT_M)
	var h: float = maxf(absf(half_h), 0.0)
	var out: PackedVector2Array = PackedVector2Array()
	_append_unique(out, Vector2(0.0, -h - r))
	_append_arc(out, Vector2(0.0, -h), r, -PI * 0.5, 0.0)
	_append_arc(out, Vector2(0.0, h), r, 0.0, PI * 0.5)
	_append_unique(out, Vector2(0.0, h + r))
	return out


## A torus: a closed circle of minor radius offset to the major radius, revolved.
static func _torus_profile(major: float, minor: float) -> PackedVector2Array:
	var major_r: float = maxf(absf(major), MIN_EXTENT_M)
	var minor_r: float = maxf(absf(minor), MIN_EXTENT_M)
	var out: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(ARC_SEGMENTS * 4, 8)
	for i: int in steps:
		var a: float = TAU * float(i) / float(steps)
		out.append(Vector2(major_r + minor_r * cos(a), minor_r * sin(a)))
	return out


## [param profile] with a point inserted between every pair when [param twisted], so a helicoid
## has rows to bend along. A straight flank needs exactly two rows and gets more only here.
static func _densified(profile: PackedVector2Array, twisted: bool) -> PackedVector2Array:
	if not twisted or profile.size() < 2:
		return profile
	var out: PackedVector2Array = PackedVector2Array()
	var steps: int = maxi(TWIST_SLABS / maxi(profile.size() - 1, 1), 1)
	for i: int in profile.size() - 1:
		for k: int in steps:
			out.append(profile[i].lerp(profile[i + 1], float(k) / float(steps)))
	out.append(profile[profile.size() - 1])
	return out


static func _append_unique(out: PackedVector2Array, point: Vector2) -> void:
	if out.size() > 0 and out[out.size() - 1].distance_squared_to(point) < 1.0e-12:
		return
	out.append(point)


static func _append_arc(
	out: PackedVector2Array, centre: Vector2, radius: float, a0: float, a1: float
) -> void:
	var steps: int = maxi(2, ceili(absf(a1 - a0) / (PI * 0.5) * float(ARC_SEGMENTS)))
	for i: int in range(steps + 1):
		_append_unique(
			out,
			(
				centre
				+ (
					Vector2(
						cos(lerpf(a0, a1, float(i) / float(steps))),
						sin(lerpf(a0, a1, float(i) / float(steps)))
					)
					* radius
				)
			)
		)


# --- the warps, backwards -------------------------------------------------------------------------


## [param base] carried back through the domain warps and scaled, so its vertices land on the
## surface [method ResolvedShape.sdf] describes.
static func _warped(base: PolyMesh, shape: ResolvedShape, twisted: bool) -> PolyMesh:
	var out: PolyMesh = PolyMesh.new()
	var half_h: float = maxf(absf(shape.size.y), SdfOps.MIN_HALF_H)
	for v: Vector3 in base.vertices:
		out.vertices.append(_unwarp(v, shape, half_h))

	for index: int in base.faces.size():
		var loop: PackedInt32Array = base.faces[index]
		if not twisted:
			out.add_face(loop.duplicate())
			continue
		# A twisted face is a helicoid, so it has no plane to be an n-gon in. Fanned into
		# triangles, which are planar by construction.
		for k: int in range(1, loop.size() - 1):
			out.add_face(PackedInt32Array([loop[0], loop[k], loop[k + 1]]))
	return out


## The inverse of `shear(twist(taper(p / scale)))`, applied to a point on the base primitive.
##
## Read it bottom-up against [method ResolvedShape.sdf]: the field warps a query point forwards
## through taper, then twist, then shear before asking the primitive, so a point ON the primitive
## comes back through shear, then twist, then taper, and is scaled last.
static func _unwarp(q: Vector3, shape: ResolvedShape, half_h: float) -> Vector3:
	var p: Vector3 = q
	# shear⁻¹: the forward map subtracts k * y, so add it back.
	if shape.shear != Vector2.ZERO:
		p = Vector3(p.x + shape.shear.x * p.y, p.y, p.z + shape.shear.y * p.y)
	# twist⁻¹: the forward map rotates by +deg_per_m * y about +Y.
	if not is_zero_approx(shape.twist_deg):
		var a: float = -deg_to_rad(shape.twist_deg) * p.y
		var c: float = cos(a)
		var s: float = sin(a)
		p = Vector3(c * p.x - s * p.z, p.y, s * p.x + c * p.z)
	# taper⁻¹: the forward map divides x and z by a factor of y, so multiply by the same factor.
	if not is_zero_approx(shape.taper):
		var f: float = 1.0 - shape.taper * ((p.y / half_h) * 0.5 + 0.5)
		if f < SdfOps.MIN_TAPER_FACTOR:
			f = SdfOps.MIN_TAPER_FACTOR
		p = Vector3(p.x * f, p.y, p.z * f)
	return Vector3(p.x * shape.scale.x, p.y * shape.scale.y, p.z * shape.scale.z)
