## ShipMeshGen - ResolvedShape -> preview Mesh.
##
## SPEC section 2: the editing view is NEVER the SDF, and the SDF is never remeshed per
## frame. That split is the whole point - it is what lets the editor stay crisp and picky
## while the hull stays volumetric. So Phase 1 previews are Godot primitive meshes sized
## from ResolvedShape.size, nothing more.
##
## SIZE CONVENTION. ResolvedShape.size is the family's UNSCALED base_size and follows the
## contract's convention, which is NOT Godot's: box half-extents, (radius, half_height, _)
## for cylinder/cone/capsule, (major_r, minor_r, _) for torus. Since ADR 0005 a CYLINDER also
## carries `radius_b` (the +Y end radius) and `end_round` (how far the end discs are rounded),
## and it is the only base whose preview is LATHED rather than a Godot primitive - see
## `_rounded_cone_mesh`, and see the honesty table below for why that one earns the exception.
##
## Godot's primitives want full sizes and diameters, so every builder below doubles -
## box.size = half * 2,
## CylinderMesh.height = half_height * 2, SphereMesh.height = radius * 2, and CapsuleMesh
## .height is the TOTAL height including both caps (half_height * 2 + radius * 2).
## TorusMesh takes inner/outer radii, so major -/+ minor.
##
## SHEAR IS A TRANSFORM TOO, and for the same reason: it is LINEAR, so the preview gets it
## EXACTLY for free by folding it into the instance basis beside the scale (ADR 0007). See
## `mesh_basis()`. This is the only warp the preview reproduces perfectly rather than
## approximating - taper and twist are non-linear and cannot be a matrix.
##
## SCALE IS A TRANSFORM, NOT A SIZE. ResolvedShape.scale is per-axis and the SDF applies
## it as min_component(scale) * base_sdf(p / scale), i.e. genuine ellipsoids and stretched
## capsules and torii. A SphereMesh cannot be an ellipsoid, so the preview does NOT bake
## scale into the mesh: mesh_scale() hands the scale back and ShipSceneBuilder folds it
## into the MeshInstance3D basis. Collision points ARE pre-scaled (see collision_for) so
## no pick body ever carries a non-uniform node scale.
##
## WHAT THE PREVIEW HONESTLY SHOWS, and what it does not:
##
##   size        - exact.
##   scale       - exact, via the instance transform.
##   round_r     - APPROXIMATED by inflating the primitive outward by round_r. A real
##                 rounded box has filleted edges; this one has square edges in the
##                 slightly-too-large place. Close enough to place parts by.
##   taper       - APPROXIMATED on CYLINDER/CONE only, by narrowing the +Y radius, which
##                 is the direction positive taper narrows in the ruleset.
##                 Ignored on BOX/SPHERE/CAPSULE/TORUS - the primitives cannot express it.
##   radius_b    - EXACT on CYLINDER. Neither is an ornament: together they are the
##   end_round     difference between a tube, a frustum, a cone and a capsule, so a preview
##                 that rounded them off the way it rounds off ribs would be showing the
##                 player a different PART rather than a simplified one. Hence the lathe - no
##                 Godot primitive spans that family, and CylinderMesh cannot round an end.
##   twist       - IGNORED.
##   ribs        - IGNORED.
##   scallops    - IGNORED.
##
## Those are not oversights and must not be "fixed" by remeshing the SDF here. The honest
## bake (core/bake/, Surface Nets over ShipSdf) is what shows the real shape; the preview
## exists to be fast, crisp and pickable while dragging.
##
## CACHING. Two keys, on purpose. signature() is the FULL key including scale and is what
## ShipSceneBuilder diffs against, so scaling a part - the most common edit there is -
## always refreshes it. The unscaled mesh and wire caches are keyed by the scale-free
## base signature instead, so ten differently-stretched cylinders still share one mesh.
## Both keys deliberately OMIT the ignored ops: two shapes differing only in rib count
## produce an identical preview and should share it rather than thrash the cache.
class_name ShipMeshGen
extends RefCounted

## Chunky on purpose - low segment counts suit the 70s-remembered-future look and keep
## the derived wireframe legible instead of a grey smear.
const RADIAL_SEGMENTS: int = 16
const RINGS: int = 8
const TORUS_RING_SEGMENTS: int = 16
const TORUS_RINGS: int = 24
## Arc samples per quarter turn of a lathed end fillet. Matches RINGS' chunkiness so a
## rounded cylinder end does not read as smoother than the sphere next to it.
const CAP_SEGMENTS: int = 4

## Signature quantization. 1e-4 m is far below the finest feature the spec cares about
## (0.01 m) so this never merges two shapes a player could tell apart.
const SIG_QUANT: float = 10000.0

var _mesh_cache: Dictionary = {}
var _wire_cache: Dictionary = {}
var _shape_cache: Dictionary = {}


## FULL cache key, including per-axis scale. This is the key ShipSceneBuilder diffs, so
## a scale-only edit is never mistaken for "nothing changed".
static func signature(shape: ResolvedShape) -> String:
	if shape == null:
		return "null"
	var s: Vector3 = mesh_scale(shape)
	return "%s|%d,%d,%d" % [base_signature(shape), _q(s.x), _q(s.y), _q(s.z)]


## Scale-free key. Two parts that differ only in scale share one unscaled mesh.
static func base_signature(shape: ResolvedShape) -> String:
	if shape == null:
		return "null"
	return (
		"%d|%d,%d,%d|%d|%d|%d,%d|%d,%d"
		% [
			shape.base,
			_q(shape.size.x),
			_q(shape.size.y),
			_q(shape.size.z),
			_q(shape.round_r),
			_q(shape.taper),
			# SHAPE, not ornament (see the honesty table). Omitting them would serve a cached
			# tube for a cone the moment two parts happened to share a size.
			_q(shape.radius_b),
			_q(shape.end_round),
			# The shear rides in the instance BASIS, not in the mesh, so two parts that differ only
			# in lean legitimately share one mesh - but they must not share one COLLISION hull,
			# which is pre-scaled. Keyed here because collision_for() keys off the same signature.
			_q(shape.shear.x),
			_q(shape.shear.y),
		]
	)


## Per-axis scale to fold into the instance transform, guarded against a zero or negative
## component that would collapse or invert the preview.
static func mesh_scale(shape: ResolvedShape) -> Vector3:
	if shape == null:
		return Vector3.ONE
	var s: Vector3 = shape.scale
	return Vector3(maxf(absf(s.x), 0.0001), maxf(absf(s.y), 0.0001), maxf(absf(s.z), 0.0001))


static func _q(v: float) -> int:
	return int(roundf(v * SIG_QUANT))


## Solid preview mesh for a shape, UNSCALED. Never null - falls back to a unit box.
## The full linear part of the instance transform: the per-axis scale with the SHEAR applied on
## top. Callers that fold `mesh_scale()` into a basis should fold this instead - it reduces to
## exactly `Basis.from_scale(mesh_scale(shape))` when there is no shear, so nothing changes for a
## part that is not leaning.
##
## Order matters and is the one the SDF implies. `ResolvedShape.sdf()` divides by the scale FIRST
## and shears the result SECOND, so the solid is shear(scale(base)) and the matrix is
## `Shear * Scale`, not the other way round. Swapping them scales the lean instead of leaning the
## scaled part, which is a different shape everywhere the scale is non-uniform.
static func mesh_basis(shape: ResolvedShape) -> Basis:
	var scaled: Basis = Basis.from_scale(mesh_scale(shape))
	if shape == null or shape.shear == Vector2.ZERO:
		return scaled
	# Columns: X and Z unchanged, Y carries the lean. p' = (x + kx*y, y, z + kz*y).
	var shear: Basis = Basis(
		Vector3(1.0, 0.0, 0.0), Vector3(shape.shear.x, 1.0, shape.shear.y), Vector3(0.0, 0.0, 1.0)
	)
	return shear * scaled


## Apply mesh_scale() to the instance transform to get the shape the SDF describes.
func mesh_for(shape: ResolvedShape) -> Mesh:
	var sig: String = base_signature(shape)
	if _mesh_cache.has(sig):
		return _mesh_cache[sig]
	var m: Mesh = _build_mesh(shape)
	_mesh_cache[sig] = m
	return m


## Line-primitive wireframe derived from the solid mesh, for the wireframe and
## shaded+wireframe display modes (SPEC section 11). Unscaled, like mesh_for(). May be
## null if the primitive has no index array to walk.
func wire_for(shape: ResolvedShape) -> Mesh:
	var sig: String = base_signature(shape)
	if _wire_cache.has(sig):
		return _wire_cache[sig]
	var w: Mesh = _build_wire(mesh_for(shape))
	_wire_cache[sig] = w
	return w


## Convex collision shape for MOUSE PICKING ONLY - never physics. Convex is wrong for a
## torus (it fills the hole) but a click near the hole picking the torus is a fine trade
## against re-triangulating a concave shape on every rebuild.
##
## The scale is baked into the hull POINTS rather than left on the node, so a stretched
## part never puts a non-uniform scale on a CollisionShape3D - which the physics server
## does not handle the way a renderer does.
func collision_for(shape: ResolvedShape) -> Shape3D:
	var sig: String = signature(shape)
	if _shape_cache.has(sig):
		return _shape_cache[sig]
	var m: Mesh = mesh_for(shape)
	var basis: Basis = mesh_basis(shape)
	var s: Shape3D = _transformed_convex(m, basis)
	if s == null:
		var box: BoxShape3D = BoxShape3D.new()
		# A BoxShape3D cannot lean, so the fallback grows to the sheared bounds instead of
		# leaving a leaning part unpickable at its ends.
		box.size = (basis * m.get_aabb().size).abs()
		s = box
	_shape_cache[sig] = s
	return s


## RETIRED(ADR 0007): _scaled_convex() -> _transformed_convex(). A Vector3 cannot carry a lean,
## so a sheared part's pick body stayed upright while the part leaned away from it.
func _transformed_convex(m: Mesh, basis: Basis) -> ConvexPolygonShape3D:
	var hull: ConvexPolygonShape3D = m.create_convex_shape(true, false)
	if hull == null:
		return null
	if basis.is_equal_approx(Basis.IDENTITY):
		return hull
	var pts: PackedVector3Array = hull.points
	for i: int in range(pts.size()):
		pts[i] = basis * pts[i]
	hull.points = pts
	return hull


func clear_cache() -> void:
	_mesh_cache.clear()
	_wire_cache.clear()
	_shape_cache.clear()


func cache_size() -> int:
	return _mesh_cache.size()


# ---------------------------------------------------------------- building


func _build_mesh(shape: ResolvedShape) -> Mesh:
	if shape == null:
		return _box_mesh(Vector3.ONE * 0.5, 0.0)

	# round_r inflates the surface outward (SPEC section 4: d = d - round_r), so the
	# preview grows by the same amount. Crude - the real shape also fillets its edges.
	var r: float = maxf(shape.round_r, 0.0)
	var half: Vector3 = shape.size.abs()
	var out: Mesh = null

	match shape.base:
		ResolvedShape.Base.SPHERE:
			out = _sphere_mesh(half, r)
		ResolvedShape.Base.CYLINDER:
			out = _rounded_cone_mesh(shape, r)
		ResolvedShape.Base.CONE:
			out = _cone_mesh(half, r)
		ResolvedShape.Base.CAPSULE:
			out = _capsule_mesh(half, r)
		ResolvedShape.Base.TORUS:
			out = _torus_mesh(half, r)
		_:
			# BOX, and anything unrecognised, which is safer as a box than as nothing.
			out = _box_mesh(half, r)
	return out


func _box_mesh(half: Vector3, r: float) -> BoxMesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = (half + Vector3(r, r, r)) * 2.0
	return box


func _sphere_mesh(half: Vector3, r: float) -> SphereMesh:
	var sph: SphereMesh = SphereMesh.new()
	sph.radius = maxf(half.x + r, 0.001)
	sph.height = sph.radius * 2.0
	sph.radial_segments = RADIAL_SEGMENTS
	sph.rings = RINGS
	return sph


## The CYLINDER preview: a lathed surface of revolution honouring both end radii and the end
## rounding exactly (ADR 0005).
##
## `round_r` folds in for free rather than being approximated, which is the one place this
## generator is MORE honest than the rest of it. Inflating a rounded cone by rho is exactly a
## rounded cone with every one of its four parameters raised by rho:
## [codeblock]
## rounded_cone(r1, r2, h, e) - rho  ==  rounded_cone(r1+rho, r2+rho, h+rho, e+rho)
## [/codeblock]
## because both sides reduce to `capped_cone(r1-e, r2-e, h-e) - (e+rho)`. So the fillet the
## player sees on a rounded part is the real fillet, not a square edge in a slightly-too-large
## place.
func _rounded_cone_mesh(shape: ResolvedShape, r: float) -> ArrayMesh:
	var r1: float = maxf(absf(shape.size.x) + r, 0.0001)
	var r2: float = maxf(maxf(shape.radius_b, 0.0) + r, 0.0)
	var h: float = maxf(absf(shape.size.y) + r, 0.0001)
	# Taper is a domain warp in the ruleset, not a lofted radius; narrowing the +Y end is the
	# same look-alike the CylinderMesh path used, kept so the two agree.
	r2 *= 1.0 - clampf(shape.taper, 0.0, 0.98)
	# The WIDER end sets the reach, matching SdfPrims.rounded_cone -- a cone's rounded nose is a
	# real shape and the preview must be able to draw it.
	var e: float = clampf(maxf(shape.end_round, 0.0) + r, 0.0, minf(maxf(r1, r2), h))
	return _lathe(_rounded_cone_profile(r1, r2, h, e))


## The (radius, y) profile of a rounded cone, bottom pole to top pole, as a polyline.
##
## The straight flank is the cone through the two fillet CENTRES pushed out along its own
## normal by `e`; the two fillets are arcs joining that flank to the end discs. Building it
## from the centres is what makes a frustum's fillets meet the flank tangentially instead of
## leaving a visible crease at the joint.
func _rounded_cone_profile(r1: float, r2: float, h: float, e: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if e <= 0.0001:
		out.append(Vector2(0.0, -h))
		out.append(Vector2(r1, -h))
		out.append(Vector2(r2, h))
		out.append(Vector2(0.0, h))
		return out
	var c1: Vector2 = Vector2(maxf(r1 - e, 0.0), -h + e)
	var c2: Vector2 = Vector2(maxf(r2 - e, 0.0), h - e)
	var flank: Vector2 = c2 - c1
	var normal: Vector2 = Vector2(flank.y, -flank.x)
	if normal.length_squared() < 1.0e-12:
		normal = Vector2(1.0, 0.0)
	normal = normal.normalized()
	var a_flank: float = normal.angle()
	# The two poles are appended only when the arcs did not already land on them, which they do
	# whenever an end has been rounded all the way in (r == e). A duplicated vertex would revolve
	# into a ring of degenerate triangles.
	_append_unique(out, Vector2(0.0, -h))
	_append_arc(out, c1, e, -PI * 0.5, a_flank)
	_append_arc(out, c2, e, a_flank, PI * 0.5)
	_append_unique(out, Vector2(0.0, h))
	return out


## Appends `point` unless the profile already ends there.
func _append_unique(out: PackedVector2Array, point: Vector2) -> void:
	if out.size() > 0 and out[out.size() - 1].distance_squared_to(point) < 1.0e-12:
		return
	out.append(point)


## Samples an arc of `radius` about `centre` from `a0` to `a1` radians, where angle 0 points
## along +radius and +PI/2 along +y. Both endpoints are included, so consecutive segments of the
## profile share a vertex exactly.
func _append_arc(
	out: PackedVector2Array, centre: Vector2, radius: float, a0: float, a1: float
) -> void:
	var steps: int = maxi(2, int(ceil(absf(a1 - a0) / (PI * 0.5) * float(CAP_SEGMENTS))))
	for i: int in range(steps + 1):
		var a: float = lerpf(a0, a1, float(i) / float(steps))
		out.append(centre + Vector2(cos(a), sin(a)) * radius)


## Revolves a (radius, y) profile about +Y into a closed ArrayMesh.
##
## Normals come from the PROFILE tangent rather than from triangle cross products, so a profile
## point at radius 0 - either pole - still gets a usable axial normal instead of a degenerate
## zero vector, and the fillets stay smooth across the seam.
func _lathe(profile: PackedVector2Array) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var rows: int = profile.size()
	var cols: int = RADIAL_SEGMENTS
	for ri: int in range(rows):
		var pt: Vector2 = profile[ri]
		var tangent: Vector2 = _profile_tangent(profile, ri)
		# The profile runs -Y to +Y, so its outward normal is the tangent turned by -90.
		var n2: Vector2 = Vector2(tangent.y, -tangent.x).normalized()
		for ci: int in range(cols + 1):
			var a: float = TAU * float(ci) / float(cols)
			var ca: float = cos(a)
			var sa: float = sin(a)
			verts.append(Vector3(pt.x * ca, pt.y, pt.x * sa))
			norms.append(Vector3(n2.x * ca, n2.y, n2.x * sa).normalized())
	for ri: int in range(rows - 1):
		for ci: int in range(cols):
			var a0: int = ri * (cols + 1) + ci
			var b0: int = a0 + 1
			var a1: int = a0 + (cols + 1)
			var b1: int = a1 + 1
			idx.append_array(PackedInt32Array([a0, a1, b0, b0, a1, b1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Central-difference tangent along the profile, so a vertex shared by two segments gets the
## average of both and the fillet/flank joint reads as one surface.
func _profile_tangent(profile: PackedVector2Array, i: int) -> Vector2:
	var prev: Vector2 = profile[maxi(i - 1, 0)]
	var next: Vector2 = profile[mini(i + 1, profile.size() - 1)]
	var t: Vector2 = next - prev
	if t.length_squared() < 1.0e-12:
		return Vector2(0.0, 1.0)
	return t.normalized()


## RETIRED(ADR 0005): _cylinder_mesh() -> _rounded_cone_mesh() (above). A CylinderMesh
## cannot round an end at all, so it could not draw a capsule a player had made out of a
## cylinder; the whole builder went with it rather than sitting here uncalled.


func _cone_mesh(half: Vector3, r: float) -> CylinderMesh:
	# Contract section 6: apex +Y, base -Y. CylinderMesh top is +Y.
	var cone: CylinderMesh = CylinderMesh.new()
	cone.bottom_radius = maxf(half.x + r, 0.001)
	cone.top_radius = 0.0
	cone.height = maxf(half.y + r, 0.001) * 2.0
	cone.radial_segments = RADIAL_SEGMENTS
	cone.rings = 1
	return cone


func _capsule_mesh(half: Vector3, r: float) -> CapsuleMesh:
	var cap: CapsuleMesh = CapsuleMesh.new()
	var rad: float = maxf(half.x + r, 0.001)
	cap.radius = rad
	# CapsuleMesh.height is the TOTAL height including both hemispherical caps, while
	# ResolvedShape.size.y is the cylindrical half-height.
	cap.height = maxf(half.y * 2.0 + rad * 2.0, rad * 2.0 + 0.001)
	cap.radial_segments = RADIAL_SEGMENTS
	cap.rings = RINGS
	return cap


func _torus_mesh(half: Vector3, r: float) -> TorusMesh:
	# Contract section 6: ring in XZ, axis +Y - which is TorusMesh orientation.
	var tor: TorusMesh = TorusMesh.new()
	var major: float = maxf(half.x, 0.002)
	var minor: float = maxf(half.y + r, 0.001)
	minor = minf(minor, major - 0.001)
	tor.inner_radius = maxf(major - minor, 0.001)
	tor.outer_radius = major + minor
	tor.rings = TORUS_RINGS
	tor.ring_segments = TORUS_RING_SEGMENTS
	return tor


## Deduplicated triangle edges as a PRIMITIVE_LINES ArrayMesh. Godot has no per-material
## wireframe mode (viewport debug_draw is all-or-nothing and would hit the UI too), so
## the wire overlay is real line geometry.
## The line-primitive wireframe of an ARBITRARY mesh, deduplicated edge by edge. Public because
## the exploded view has meshes that came from the baker rather than from a [ResolvedShape], and
## its wireframe must be built the same way a part's is or the two modes would not match.
## Uncached: a bake result is a one-off, and caching it by object would leak.
func wire_from_mesh(m: Mesh) -> Mesh:
	return _build_wire(m)


func _build_wire(m: Mesh) -> Mesh:
	if m == null or m.get_surface_count() == 0:
		return null
	var arrays: Array = m.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_INDEX:
		return null
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if verts.is_empty() or idx.is_empty():
		return null

	var seen: Dictionary = {}
	var lines: PackedInt32Array = PackedInt32Array()
	var tri: int = 0
	while tri + 2 < idx.size():
		_add_edge(seen, lines, idx[tri], idx[tri + 1])
		_add_edge(seen, lines, idx[tri + 1], idx[tri + 2])
		_add_edge(seen, lines, idx[tri + 2], idx[tri])
		tri += 3

	var out_arrays: Array = []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = verts
	out_arrays[Mesh.ARRAY_INDEX] = lines
	var am: ArrayMesh = ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, out_arrays)
	return am


func _add_edge(seen: Dictionary, lines: PackedInt32Array, a: int, b: int) -> void:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	var key: int = lo * 65536 + hi
	if seen.has(key):
		return
	seen[key] = true
	lines.append(lo)
	lines.append(hi)
