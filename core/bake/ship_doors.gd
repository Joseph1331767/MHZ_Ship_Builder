class_name ShipDoors
## The openings of the hatched and doorway seams, and the doors that cover them (ADR 0029).
##
## "where we cut holes for hatches, and openings, we need those manifold meshes to cap the
## exposed open hole edges .. each hatch will be a double hatch with one on each module such that
## they are aligned and both act as isolated doors covering the same opening on each module ..
## for doors going on weird topology the topology must resolve into a manifold shape that a
## hatch can go on (easiest way for those is a thin flat faced cylinder (or extrusion with the
## profile of the hatch shape itself) that extends into each module just enough to give a flat
## manifold gasket for the door)" (2026-09-06).
##
## ONE OPENING, TWO MODULES, TWO DOORS. A hatched seam stands between a child and the host it is
## seated in, and each keeps its own wall there: the child's end cap and the host's socket wall,
## a hull thickness each, pressed together at the child's surface. This file finds the GASKET
## PLANE - the plane through the point where the indenting module's surface crosses the seam
## axis, square to that axis - and gives each module, on its own side of it:
##
##   a COLLAR   the frame's outline (the hole grown by a frame width) extruded from the plane into
##              the module, one wall deep or deeper where the module's surface sags away from the
##              plane; unioned into the module, it turns whatever the surface was doing there into
##              a flat ring the door can seat on - the "tiny cylinder manifold";
##   a CLEAR    the same outline on the OTHER side of the plane, subtracted, so nothing of the
##              module bulges past the gasket into its neighbour's door;
##   the BORE   the hole's own outline, extruded through both walls and subtracted from both.
##
## The engine's booleans (ShipCsgBake) carry these out, and a difference of closed solids is a
## closed solid, so every hole comes out with its rim CAPPED - the ring of wall thickness between
## the exterior and the interior - with no work of this file's own. The pure executor keeps its
## walls (FOLLOWUPS F41).
##
## The DOOR LEAVES are not booleans: they are separate closed solids a view places and moves.
## [method leaves] builds a module's leaves for any opening amount - a hinged door swung into its
## own module, a pair of leaves swung apart, or an iris of blades withdrawn into the frame - so
## the two doors over one opening are independent, "one can be closed or both".
##
## SIZES FOLLOW THE WALL. The frame width, the collar depth and the leaf thickness are fractions
## of `ShipConfig.hull_thickness_m`, so a hatch on a thin skin is a thin frame and a hatch in a
## thick bulkhead a deep one; the leaf sits inside its module's wall and never past its inner
## surface. A hole is CLAMPED to what fits: the frame's outline must stand inside BOTH modules'
## cavities behind their walls, measured on the modules' own fields, or the hole is scaled down
## until it does. Below `ShipConfig.hatch_min_m` (a person's squeeze) it is still bored, and
## reported TIGHT.
##
## EVERY FIELD IS READ AT ITS OWN MESH, NOT AT ZERO (FOLLOWUPS F34). A tessellation sits inside
## its field by a constant - a box by its fillet, a spar by its end rounding - and the engine
## builds the TESSELLATION. Measured on a carbon tunnel: the field's zero lay 0.094 m outside the
## cap the engine had built, so a gasket plane put on the zero stood in the air; the collar then
## added a disc of hull beyond the cap and the bore took mostly that disc back - a tunnel bored
## at both ends lost 0.015 m3 of the 0.077 two holes cost. Every field here is a [Field]: the
## cutter and the value it reads at its own surface, and "on the surface" means that value.
##
## Pure data (SPEC section 12): static-only, nothing here touches a tree. Deterministic: door
## records come out in seam order, and every march is a fixed number of steps.


## A module's field, calibrated to the surface the engine builds - see the class docs.
class Field:
	extends RefCounted

	var cutter: MeshClip.Cutter = null
	## What the field reads at its own tessellation: 0 on a sphere, -round_r on a box or spar.
	var offset: float = 0.0
	## The tessellation itself, in the same space, for the one test that has to be exact.
	var surface: PolyMesh = null

	## Negative inside the MESH, zero on it, positive outside.
	func d(p: Vector3) -> float:
		return cutter.distance(p) - offset


const SIDE_CHILD: String = "child"
const SIDE_HOST: String = "host"
const SIDES: Array = [SIDE_CHILD, SIDE_HOST]

## Keys of a door record - see [method plan].
const DOOR_CHILD: String = "child"  # String, the placed id standing on the host
const DOOR_HOST: String = "host"  # String, the placed id it stands on
const DOOR_KEY: String = "key"  # String, ShipDoc.joint_key_for over the SOURCE ids
const DOOR_MODE: String = "mode"  # ShipSeams.MODE_HATCHED or MODE_DOORWAY
const DOOR_HOLE: String = "hole"  # Dictionary, the hole as BORED (after the fit)
const DOOR_FRAME: String = "frame"  # Transform3D, origin on the gasket plane, basis.z host->child
const DOOR_THICKNESS: String = "thickness"  # float, the wall
const DOOR_FRAME_W: String = "frame_w"  # float, the ring between hole and collar outline
const DOOR_LEAF_T: String = "leaf_t"  # float, a leaf's thickness
const DOOR_FIT: String = "fit"  # float, the scale applied to what was asked (1 = as asked)
const DOOR_MAX: String = "max"  # Vector2, the largest size of this shape both rooms take
const DOOR_TIGHT: String = "tight"  # bool, under the person-passable minimum
const DOOR_PROFILE: String = "profile"  # PackedVector2Array, the hole outline (gasket XY)
const DOOR_SEAT: String = "seat"  # PackedVector2Array, the outline a leaf covers
const DOOR_OUTER: String = "outer"  # PackedVector2Array, the collar outline
const DOOR_DEPTH: String = "depth"  # {child: float, host: float}, collar depth per side
const DOOR_COLLAR: String = "collar"  # {child: PolyMesh, host: PolyMesh}, to UNION per side
const DOOR_CLEAR: String = "clear"  # {child: PolyMesh, host: PolyMesh}, to SUBTRACT per side
const DOOR_BORE: String = "bore"  # PolyMesh, to subtract from both
const DOOR_BLADES: String = "blades"  # int, an iris's blade count

## Keys of a misfit record - a door seam nothing could be bored for.
const MISFIT_CHILD: String = "child"
const MISFIT_HOST: String = "host"
const MISFIT_REASON: String = "reason"

## Keys of the [method plan] entries.
const ENTRY_SEAM: String = "seam"
const ENTRY_INDENTER: String = "indenter"
const ENTRY_CHILD_BODY: String = "child_body"
const ENTRY_CHILD_ROOM: String = "child_room"
const ENTRY_HOST_BODY: String = "host_body"
const ENTRY_HOST_ROOM: String = "host_room"

## The frame ring's width as a fraction of the wall, within [FRAME_MIN_M, FRAME_MAX_M].
const FRAME_FRACTION: float = 0.5
const FRAME_MIN_M: float = 0.04
const FRAME_MAX_M: float = 0.20
## A leaf's thickness as a fraction of the wall, within [LEAF_MIN_M, LEAF_MAX_M]: inside its
## module's wall, with room for the other module's leaf on the far side of the plane.
const LEAF_FRACTION: float = 0.4
const LEAF_MIN_M: float = 0.02
const LEAF_MAX_M: float = 0.12
## How far across the frame ring a leaf laps when closed, as a fraction of the ring's width.
const SEAT_FRACTION: float = 0.5
## A leaf stands off the gasket plane by this, so two closed leaves never share a face.
const LEAF_GAP_M: float = 0.01
## The bore runs this much past the last wall it has to pierce.
const BORE_MARGIN_M: float = 0.02
## A collar reaches this much (of a wall) past the deepest sag it has to bridge.
const COLLAR_MARGIN_FRACTION: float = 0.25
## Marching along the seam axis: never coarser than this fraction of a wall.
const MARCH_WALL_FRACTION: float = 0.5
const MARCH_MAX_STEPS: int = 64
const BISECT_STEPS: int = 14
## A field value this close to zero is ON the surface, which counts as inside.
const ON_SURFACE_M: float = 1.0e-3
## The fit search: outline points tried per side, bisection steps, and the smallest scale tried.
const FIT_SAMPLES: int = 12
const FIT_BISECT_STEPS: int = 8
const FIT_MIN_SCALE: float = 0.05
## How far past what was asked the fit search looks, so DOOR_MAX can say what the seam would
## take: the asked size doubled this many times.
const FIT_DOUBLINGS: int = 4
## How far (in walls) past a module's surface a fit probe marches for its cavity: a domed cap
## puts the inner surface at the rim further in than one wall along the axis.
const FIT_ROOM_REACH_WALLS: float = 2.5
## A hinged leaf swings this far when fully open, into its own module.
const HINGE_OPEN_DEG: float = 100.0
const IRIS_MIN_BLADES: int = 3
const IRIS_MAX_BLADES: int = 12
const IRIS_DEFAULT_BLADES: int = 6
## Outline samples along one blade's arc (its ends included).
const IRIS_SAMPLES_PER_BLADE: int = 5
## How many of a surface's own corners are read to find where it sits in its field.
const CALIBRATION_SAMPLES: int = 16
const EPS: float = 1.0e-6


## Plans every door of [param entries] - one per hatched or doorway seam, each
## `{seam, indenter, child_body, child_room, host_body, host_room}` (the seam record, the id
## of the module whose surface is the interface, and the two modules' body and room fields as
## [Field]s from [method field_of]). [param thickness] is the wall, [param min_clear_m] the
## person-passable minimum, [param segments] the outline resolution of a round hole.
##
## Returns `{"doors": Array[Dictionary], "misfits": Array[Dictionary]}` - door records (see the
## DOOR_* keys) in entry order, and the seams no opening could be bored for, with a reason.
static func plan(
	entries: Array[Dictionary],
	thickness: float,
	min_clear_m: float,
	segments: int = ShipSeams.HOLE_SEGMENTS
) -> Dictionary:
	var doors: Array[Dictionary] = []
	var misfits: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var result: Dictionary = _plan_one(entry, thickness, min_clear_m, segments)
		if result.has(MISFIT_REASON):
			misfits.append(result)
		elif not result.is_empty():
			doors.append(result)
	return {"doors": doors, "misfits": misfits}


## What the seam between [param child] and [param host] of [param doc] can take, for a panel
## that clamps its fields: `{"ok": bool, "reason": String, "size": Vector2 (as asked),
## "max": Vector2, "fit": float, "min": float, "tight": bool, "hole": Dictionary}`. Resolves the
## two parts alone; nothing is baked.
static func limits(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, child: String, host: String
) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "NO SEAM",
		"size": Vector2.ZERO,
		"max": Vector2.ZERO,
		"fit": 1.0,
		"min": cfg.hatch_min_m if cfg != null else 0.0,
		"tight": false,
		"hole": {},
	}
	if doc == null or data == null or cfg == null:
		return out
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	var seam: Dictionary = {}
	for record: Dictionary in ShipSeams.seams(doc, shapes, xforms, cfg, data):
		if record[ShipSeams.SEAM_CHILD] == child and record[ShipSeams.SEAM_HOST] == host:
			seam = record
			break
	if seam.is_empty():
		return out
	var hole: Dictionary = seam[ShipSeams.SEAM_HOLE]
	out["hole"] = hole
	out["size"] = hole.get(ShipSeams.HOLE_SIZE, Vector2.ZERO)
	var thickness: float = maxf(cfg.hull_thickness_m, 0.0)
	var child_mesh: PolyMesh = ShapeMesh.build(shapes[child])
	var host_mesh: PolyMesh = ShapeMesh.build(shapes[host])
	var big_indents: bool = (
		ShipJoint.indent_of(str(seam[ShipSeams.SEAM_STYLE])) == ShipJoint.INDENT_BIG
	)
	var child_is_big: bool = MeshFlange.first_is_larger(child_mesh, host_mesh)
	var child_in: ResolvedShape = ShapeMesh.inset(shapes[child], thickness)
	var host_in: ResolvedShape = ShapeMesh.inset(shapes[host], thickness)
	var entry: Dictionary = {
		ENTRY_SEAM: seam,
		ENTRY_INDENTER: indenter_for(big_indents, child_is_big, child, host),
		ENTRY_CHILD_BODY:
		field_of(
			MeshClip.Cutter.of_shape(shapes[child], xforms[child], null),
			child_mesh.transformed(xforms[child])
		),
		ENTRY_CHILD_ROOM:
		field_of(
			MeshClip.Cutter.of_shape(child_in, xforms[child], null),
			ShapeMesh.build(child_in).transformed(xforms[child])
		),
		ENTRY_HOST_BODY:
		field_of(
			MeshClip.Cutter.of_shape(shapes[host], xforms[host], null),
			host_mesh.transformed(xforms[host])
		),
		ENTRY_HOST_ROOM:
		field_of(
			MeshClip.Cutter.of_shape(host_in, xforms[host], null),
			ShapeMesh.build(host_in).transformed(xforms[host])
		),
	}
	var result: Dictionary = _plan_one(entry, thickness, cfg.hatch_min_m)
	if result.has(MISFIT_REASON):
		out["reason"] = str(result[MISFIT_REASON])
		return out
	if result.is_empty():
		out["reason"] = "NO OPENING"
		return out
	out["ok"] = true
	out["reason"] = ""
	out["max"] = result[DOOR_MAX]
	out["fit"] = result[DOOR_FIT]
	out["tight"] = result[DOOR_TIGHT]
	return out


## [param cutter] calibrated to [param surface], its own tessellation in the same space: the
## field's median value at a spread of the surface's corners becomes the field's zero.
## The narrowest tunnel that can pass a hatch of [param hatch] metres through a wall of
## [param wall]: the hole, the frame ring either side of it, and the wall either side of that.
##
## A floor is only worth what the geometry can honour. `hatch_min_m` clamps what a PANEL may ask
## for, and says nothing about whether the seam can give it - so a prebuilt tunnel narrower than
## this bores a hole under the minimum and reports it TIGHT, which is how a 0.66 m floor produced a
## 0.38 m hole (2026-09-24). Templates size a hallway to at least this, so the floor is met rather
## than merely asked for.
static func bore_for_hatch(hatch: float, wall: float) -> float:
	var frame: float = clampf(wall * FRAME_FRACTION, FRAME_MIN_M, FRAME_MAX_M)
	return maxf(hatch, 0.0) + 2.0 * frame + 2.0 * maxf(wall, 0.0)


static func field_of(cutter: MeshClip.Cutter, surface: PolyMesh) -> Field:
	var out: Field = Field.new()
	out.cutter = cutter
	out.surface = surface
	if surface == null or surface.is_empty():
		return out
	var count: int = surface.vertices.size()
	var samples: PackedFloat64Array = PackedFloat64Array()
	@warning_ignore("integer_division")
	var step: int = maxi(count / CALIBRATION_SAMPLES, 1)
	var i: int = 0
	while i < count:
		samples.append(cutter.distance(surface.vertices[i]))
		i += step
	samples.sort()
	@warning_ignore("integer_division")
	out.offset = samples[samples.size() / 2]
	return out


## Where the line through [param origin] along unit [param axis] crosses [param surface]
## nearest to the origin, either way, within [param reach]: the signed distance along the axis,
## or NAN when it never does. Every face is cast as its triangles, both sides.
static func mesh_crossing(surface: PolyMesh, origin: Vector3, axis: Vector3, reach: float) -> float:
	var best: float = NAN
	for i: int in surface.face_count():
		var tri: PackedInt32Array = surface.triangulate_face(i)
		var k: int = 0
		while k + 2 < tri.size():
			var t: float = _ray_triangle(
				origin,
				axis,
				surface.vertices[tri[k]],
				surface.vertices[tri[k + 1]],
				surface.vertices[tri[k + 2]]
			)
			k += 3
			if not is_finite(t) or absf(t) > reach:
				continue
			if not is_finite(best) or absf(t) < absf(best):
				best = t
	return best


## Moller-Trumbore, both sides: the signed distance along [param d] from [param o] to the
## triangle, or INF when the line misses it.
static func _ray_triangle(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1: Vector3 = b - a
	var e2: Vector3 = c - a
	var p: Vector3 = d.cross(e2)
	var det: float = e1.dot(p)
	if absf(det) < 1.0e-12:
		return INF
	var inv: float = 1.0 / det
	var s: Vector3 = o - a
	var u: float = s.dot(p) * inv
	if u < -EPS or u > 1.0 + EPS:
		return INF
	var q: Vector3 = s.cross(e1)
	var v: float = d.dot(q) * inv
	if v < -EPS or u + v > 1.0 + EPS:
		return INF
	return e2.dot(q) * inv


## Which of [param child] and [param host] is the INDENTER at a seam - the one whose surface is
## the interface the other is cut around - under the seam style's choice of which solid indents
## (ShipJoint.indent_of) and the volume order (MeshFlange.first_is_larger). The same answer
## [ShipMeshBake.plan] cuts the socket by.
static func indenter_for(
	big_indents: bool, child_is_big: bool, child: String, host: String
) -> String:
	var big: String = child if child_is_big else host
	var small: String = host if child_is_big else child
	return big if big_indents else small


## The leaves of [param door]'s door on [param side] (SIDE_CHILD or SIDE_HOST), [param open]
## of the way open (0 closed, 1 open), as closed solids in ship space. A doorway has none.
##
## SINGLE: one leaf over the seat, hinged on its low-X edge, swung HINGE_OPEN_DEG into its own
## module. DOUBLE: the seat split at X = 0, each half hinged on its outer edge and swung apart.
## IRIS: DOOR_BLADES blades, each the wedge of the seat between two spokes, withdrawn toward the
## frame as the aperture - the hole scaled by [param open] - grows: the shutter eye. A leaf sits
## LEAF_GAP_M off the gasket plane and LEAF_T deep, inside its module's wall, so the two modules'
## closed leaves are back to back and never share a face.
static func leaves(door: Dictionary, side: String, open: float) -> Array[PolyMesh]:
	var out: Array[PolyMesh] = []
	if door.is_empty():
		return out
	var hole: Dictionary = door.get(DOOR_HOLE, {})
	var style: String = str(hole.get(ShipSeams.HOLE_STYLE, ShipSeams.DOOR_NONE))
	if style == ShipSeams.DOOR_NONE:
		return out
	var sign: float = 1.0 if side == SIDE_CHILD else -1.0
	var gasket: Transform3D = door[DOOR_FRAME]
	var leaf_t: float = float(door[DOOR_LEAF_T])
	var z_near: float = sign * LEAF_GAP_M
	var z_far: float = sign * (LEAF_GAP_M + leaf_t)
	var z_lo: float = minf(z_near, z_far)
	var z_hi: float = maxf(z_near, z_far)
	var seat: PackedVector2Array = door[DOOR_SEAT]
	var amount: float = clampf(open, 0.0, 1.0)
	var swing: float = deg_to_rad(HINGE_OPEN_DEG) * amount
	match style:
		ShipSeams.DOOR_SINGLE:
			var leaf: PolyMesh = prism(seat, gasket, z_lo, z_hi)
			out.append(_swung(leaf, gasket, _min_x(seat), z_far, -sign * swing))
		ShipSeams.DOOR_DOUBLE:
			var left: PackedVector2Array = _clip_x(seat, true)
			var right: PackedVector2Array = _clip_x(seat, false)
			if left.size() >= 3:
				var leaf: PolyMesh = prism(left, gasket, z_lo, z_hi)
				out.append(_swung(leaf, gasket, _min_x(left), z_far, -sign * swing))
			if right.size() >= 3:
				var leaf: PolyMesh = prism(right, gasket, z_lo, z_hi)
				out.append(_swung(leaf, gasket, _max_x(right), z_far, sign * swing))
		ShipSeams.DOOR_IRIS:
			out = _iris(door, gasket, z_lo, z_hi, amount)
	return out


## The profile's outline extruded along [param frame]'s Z from [param z_lo] to [param z_hi],
## as a closed solid in ship space, wound outward. The outline is counter-clockwise in the
## frame's XY, as [method ShipSeams.hole_profile] makes it. Empty when degenerate.
static func prism(
	profile: PackedVector2Array, frame: Transform3D, z_lo: float, z_hi: float
) -> PolyMesh:
	if profile.size() < 3 or z_hi - z_lo <= EPS:
		return PolyMesh.new()
	var n: int = profile.size()
	var top: PackedVector3Array = PackedVector3Array()
	var bottom: PackedVector3Array = PackedVector3Array()
	for i: int in n:
		var p: Vector2 = profile[i]
		top.append(frame * Vector3(p.x, p.y, z_hi))
		bottom.append(frame * Vector3(p.x, p.y, z_lo))
	var polys: Array = []
	polys.append(top)
	var under: PackedVector3Array = bottom.duplicate()
	under.reverse()
	polys.append(under)
	for i: int in n:
		var j: int = (i + 1) % n
		polys.append(PackedVector3Array([bottom[i], bottom[j], top[j], top[i]]))
	return PolyMesh.from_polygons(polys)


# --- the plan of one door ------------------------------------------------------------------


## One entry's door record, a misfit record (MISFIT_REASON set), or {} for a seam with no
## opening to plan (open, walled, or a zero wall).
static func _plan_one(
	entry: Dictionary, thickness: float, min_clear_m: float, segments: int = 24
) -> Dictionary:
	var seam: Dictionary = entry.get(ENTRY_SEAM, {})
	var child: String = str(seam.get(ShipSeams.SEAM_CHILD, ""))
	var host: String = str(seam.get(ShipSeams.SEAM_HOST, ""))
	var mode: String = str(seam.get(ShipSeams.SEAM_MODE, ""))
	var hole: Dictionary = seam.get(ShipSeams.SEAM_HOLE, {})
	var kind: String = str(hole.get(ShipSeams.HOLE_KIND, ""))
	var bounded: bool = mode == ShipSeams.MODE_HATCHED or mode == ShipSeams.MODE_DOORWAY
	if not bounded or hole.is_empty() or kind == ShipSeams.KIND_ALL or thickness <= 0.0:
		return {}
	var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
	var axis: Vector3 = frame.basis.z.normalized()
	if axis.length_squared() < EPS:
		return _misfit(child, host, "NO SEAM AXIS")

	# THE GASKET PLANE: through the indenter's surface on the seam axis - the nearest crossing
	# of its MESH from the anchor, either way along the axis. Not the anchor itself, even for
	# the host: the anchor is a trace on the host's FIELD, and a spar's field zero stood 0.108 m
	# outside the cap the engine had built (F34).
	var child_indents: bool = str(entry.get(ENTRY_INDENTER, "")) == child
	var indenter: Field = entry[ENTRY_CHILD_BODY if child_indents else ENTRY_HOST_BODY]
	var reach: float = 4.0 * thickness + _half_extent(hole)
	var z0: float = _crossing_on_axis(indenter, frame.origin, axis, reach, thickness)
	if not is_finite(z0):
		return _misfit(child, host, "THE INDENTER NEVER CROSSES THE SEAM AXIS")
	var gasket: Transform3D = Transform3D(_orthonormal(frame.basis, axis), frame.origin + axis * z0)
	var frame_w: float = clampf(thickness * FRAME_FRACTION, FRAME_MIN_M, FRAME_MAX_M)
	var leaf_t: float = clampf(thickness * LEAF_FRACTION, LEAF_MIN_M, LEAF_MAX_M)

	# THE FIT: the collar's outline must stand inside both cavities behind their walls. The
	# search finds the LARGEST scale the seam takes (DOOR_MAX says so); what is bored is what
	# was asked, or that when what was asked is more.
	var room: float = _fit_scale(gasket, hole, frame_w, thickness, entry, segments)
	if room <= 0.0:
		return _misfit(child, host, "NO ROOM BEHIND THE SEAM FOR ANY OPENING")
	var fit: float = minf(room, 1.0)
	var used: Dictionary = ShipSeams.hole_scaled(hole, fit)
	var size: Vector2 = used.get(ShipSeams.HOLE_SIZE, Vector2.ZERO)
	var profile: PackedVector2Array = ShipSeams.hole_profile(used, segments)
	var outer: PackedVector2Array = ShipSeams.hole_profile(_grown(used, frame_w), segments)
	var seat: PackedVector2Array = ShipSeams.hole_profile(
		_grown(used, frame_w * SEAT_FRACTION), segments
	)
	if profile.size() < 3 or outer.size() < 3:
		return _misfit(child, host, "NO OUTLINE")

	# DEPTHS: each side's collar reaches one wall in, or past the deepest sag of the module's
	# surface away from the plane; the bore runs one wall past that sag and a margin beyond.
	var depth: Dictionary = {}
	var bore_depth: Dictionary = {}
	for side: String in SIDES:
		var sag: float = _sag_max(gasket, outer, side, entry, thickness)
		depth[side] = maxf(thickness, sag + thickness * COLLAR_MARGIN_FRACTION)
		bore_depth[side] = sag + thickness + BORE_MARGIN_M
	var collar: Dictionary = {
		SIDE_CHILD: prism(outer, gasket, 0.0, depth[SIDE_CHILD]),
		SIDE_HOST: prism(outer, gasket, -float(depth[SIDE_HOST]), 0.0),
	}
	var clear: Dictionary = {
		SIDE_CHILD: prism(outer, gasket, -(float(depth[SIDE_HOST]) + thickness), 0.0),
		SIDE_HOST: prism(outer, gasket, 0.0, float(depth[SIDE_CHILD]) + thickness),
	}
	var bore: PolyMesh = prism(
		profile, gasket, -float(bore_depth[SIDE_HOST]), float(bore_depth[SIDE_CHILD])
	)
	return {
		DOOR_CHILD: child,
		DOOR_HOST: host,
		DOOR_KEY:
		ShipDoc.joint_key_for(
			ShipSymmetry.source_of_twin(child), ShipSymmetry.source_of_twin(host)
		),
		DOOR_MODE: mode,
		DOOR_HOLE: used,
		DOOR_FRAME: gasket,
		DOOR_THICKNESS: thickness,
		DOOR_FRAME_W: frame_w,
		DOOR_LEAF_T: leaf_t,
		DOOR_FIT: fit,
		DOOR_MAX: (hole.get(ShipSeams.HOLE_SIZE, Vector2.ZERO) as Vector2) * room,
		DOOR_TIGHT: size.x < min_clear_m - EPS or size.y < min_clear_m - EPS,
		DOOR_PROFILE: profile,
		DOOR_SEAT: seat,
		DOOR_OUTER: outer,
		DOOR_DEPTH: depth,
		DOOR_COLLAR: collar,
		DOOR_CLEAR: clear,
		DOOR_BORE: bore,
		DOOR_BLADES:
		clampi(
			int(hole.get(ShipSeams.HOLE_BLADES, IRIS_DEFAULT_BLADES)),
			IRIS_MIN_BLADES,
			IRIS_MAX_BLADES
		),
	}


static func _misfit(child: String, host: String, reason: String) -> Dictionary:
	return {MISFIT_CHILD: child, MISFIT_HOST: host, MISFIT_REASON: reason}


## The largest scale of [param hole] whose frame outline fits both rooms, or 0 when not even
## FIT_MIN_SCALE does. Tried at 1 first; a hole that fits as asked is then doubled until it
## does not (FIT_DOUBLINGS at most), one that does not is halved down to FIT_MIN_SCALE, and the
## last fit and first miss are bisected.
static func _fit_scale(
	gasket: Transform3D,
	hole: Dictionary,
	frame_w: float,
	thickness: float,
	entry: Dictionary,
	segments: int
) -> float:
	var lo: float = 0.0
	var hi: float = 0.0
	if _fits(gasket, hole, 1.0, frame_w, thickness, entry, segments):
		lo = 1.0
		hi = 2.0
		var doublings: int = FIT_DOUBLINGS
		while doublings > 0 and _fits(gasket, hole, hi, frame_w, thickness, entry, segments):
			doublings -= 1
			lo = hi
			hi *= 2.0
		if doublings == 0:
			return lo
	else:
		if not _fits(gasket, hole, FIT_MIN_SCALE, frame_w, thickness, entry, segments):
			return 0.0
		lo = FIT_MIN_SCALE
		hi = 1.0
	for _step: int in FIT_BISECT_STEPS:
		var mid: float = (lo + hi) * 0.5
		if _fits(gasket, hole, mid, frame_w, thickness, entry, segments):
			lo = mid
		else:
			hi = mid
	return lo


## Does the frame outline of [param hole] at [param scale] stand inside BOTH modules' cavities
## behind their walls? Every sampled outline point must enter the module's body along the axis
## and find the module's room within a few walls further on - marched, not probed at one
## depth: measured on a carbon tunnel, the cap is a dome and its inner surface at the frame's
## rim sits deeper than one wall along the axis.
static func _fits(
	gasket: Transform3D,
	hole: Dictionary,
	scale: float,
	frame_w: float,
	thickness: float,
	entry: Dictionary,
	segments: int
) -> bool:
	var outline: PackedVector2Array = ShipSeams.hole_profile(
		_grown(ShipSeams.hole_scaled(hole, scale), frame_w), segments
	)
	if outline.size() < 3:
		return false
	var samples: PackedVector2Array = _subsampled(outline, FIT_SAMPLES)
	var reach: float = 2.0 * thickness + _half_extent(hole) * scale
	var room_reach: float = thickness * FIT_ROOM_REACH_WALLS
	for side: String in SIDES:
		var sign: float = 1.0 if side == SIDE_CHILD else -1.0
		var body: Field = entry[ENTRY_CHILD_BODY if side == SIDE_CHILD else ENTRY_HOST_BODY]
		var room: Field = entry[ENTRY_CHILD_ROOM if side == SIDE_CHILD else ENTRY_HOST_ROOM]
		for p: Vector2 in samples:
			var at: Vector3 = gasket * Vector3(p.x, p.y, 0.0)
			var dir: Vector3 = gasket.basis.z * sign
			var sag: float = _entry_depth(body, at, dir, reach, thickness)
			if not is_finite(sag):
				return false
			var into: Vector3 = at + dir * sag
			if not is_finite(_entry_depth(room, into, dir, room_reach, thickness)):
				return false
	return true


## The deepest sag of [param side]'s module surface away from the gasket plane over
## [param outline]: how far along the axis, into the module, each outline point has to go
## before it is inside the module's body, at most. Zero where the surface lies on the plane.
static func _sag_max(
	gasket: Transform3D,
	outline: PackedVector2Array,
	side: String,
	entry: Dictionary,
	thickness: float
) -> float:
	var sign: float = 1.0 if side == SIDE_CHILD else -1.0
	var body: Field = entry[ENTRY_CHILD_BODY if side == SIDE_CHILD else ENTRY_HOST_BODY]
	var reach: float = 2.0 * thickness + _half_extent_of(outline)
	var worst: float = 0.0
	for p: Vector2 in outline:
		var at: Vector3 = gasket * Vector3(p.x, p.y, 0.0)
		var sag: float = _entry_depth(body, at, gasket.basis.z * sign, reach, thickness)
		if is_finite(sag):
			worst = maxf(worst, sag)
	return worst


## How far from [param from] along unit [param dir] the point is first inside [param body]
## (on its surface counts), up to [param reach]; INF when it never is.
static func _entry_depth(
	body: Field, from: Vector3, dir: Vector3, reach: float, thickness: float
) -> float:
	if body.d(from) <= ON_SURFACE_M:
		return 0.0
	var step: float = _march_step(reach, thickness)
	var z: float = 0.0
	var guard: int = MARCH_MAX_STEPS
	while z < reach and guard > 0:
		guard -= 1
		var next: float = minf(z + step, reach)
		if body.d(from + dir * next) <= ON_SURFACE_M:
			return _bisect_entry(body, from, dir, z, next)
		z = next
	return INF


## The signed distance along [param axis] from [param origin] to the nearest crossing of
## [param body]'s surface, searched [param reach] both ways; NAN when there is none. The MESH
## is cast first, which is exact; the field is marched only for a body with no mesh.
static func _crossing_on_axis(
	body: Field, origin: Vector3, axis: Vector3, reach: float, thickness: float
) -> float:
	if body.surface != null and not body.surface.is_empty():
		var hit: float = mesh_crossing(body.surface, origin, axis, reach)
		if is_finite(hit):
			return hit
	var step: float = _march_step(reach, thickness)
	var d0: float = body.d(origin)
	if absf(d0) <= ON_SURFACE_M:
		return 0.0
	var inside0: bool = d0 < 0.0
	var z: float = 0.0
	var guard: int = MARCH_MAX_STEPS
	while z < reach and guard > 0:
		guard -= 1
		var next: float = minf(z + step, reach)
		for sign: float in [-1.0, 1.0]:
			var d: float = body.d(origin + axis * (sign * next))
			if (d < 0.0) != inside0 or absf(d) <= ON_SURFACE_M:
				var lo: float = sign * z
				var hi: float = sign * next
				return _bisect_crossing(body, origin, axis, lo, hi, inside0)
		z = next
	return NAN


static func _bisect_entry(
	body: Field, from: Vector3, dir: Vector3, outside: float, inside: float
) -> float:
	var lo: float = outside
	var hi: float = inside
	for _step: int in BISECT_STEPS:
		var mid: float = (lo + hi) * 0.5
		if body.d(from + dir * mid) <= ON_SURFACE_M:
			hi = mid
		else:
			lo = mid
	return hi


static func _bisect_crossing(
	body: Field, origin: Vector3, axis: Vector3, lo_z: float, hi_z: float, lo_in: bool
) -> float:
	var lo: float = lo_z
	var hi: float = hi_z
	for _step: int in BISECT_STEPS:
		var mid: float = (lo + hi) * 0.5
		if (body.d(origin + axis * mid) < 0.0) == lo_in:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func _march_step(reach: float, thickness: float) -> float:
	var step: float = maxf(thickness * MARCH_WALL_FRACTION, EPS)
	return minf(step, maxf(reach / float(MARCH_MAX_STEPS), EPS))


# --- outlines ------------------------------------------------------------------------------


## [param hole] grown by [param by] on every side: a true offset of a circle, an ellipse, a
## rectangle (its corner radius grows too) and a square; a regular polygon or triangle grows
## by its circumradius so its edges move out by [param by].
static func _grown(hole: Dictionary, by: float) -> Dictionary:
	var out: Dictionary = hole.duplicate(true)
	var size: Vector2 = hole.get(ShipSeams.HOLE_SIZE, Vector2.ZERO)
	var kind: String = str(hole.get(ShipSeams.HOLE_KIND, ""))
	var grow: float = 2.0 * by
	if kind == ShipSeams.KIND_TRIANGLE or kind == ShipSeams.KIND_POLYGON:
		var sides: int = 3
		if kind == ShipSeams.KIND_POLYGON:
			sides = clampi(
				int(hole.get(ShipSeams.HOLE_SIDES, 6)),
				ShipSeams.POLYGON_MIN_SIDES,
				ShipSeams.POLYGON_MAX_SIDES
			)
		grow = 2.0 * by / maxf(cos(PI / float(sides)), 0.1)
	out[ShipSeams.HOLE_SIZE] = Vector2(size.x + grow, size.y + grow)
	out[ShipSeams.HOLE_CORNER] = float(hole.get(ShipSeams.HOLE_CORNER, 0.0)) + by
	return out


## Half the hole's larger dimension.
static func _half_extent(hole: Dictionary) -> float:
	var size: Vector2 = hole.get(ShipSeams.HOLE_SIZE, Vector2.ZERO)
	return 0.5 * maxf(size.x, size.y)


static func _half_extent_of(outline: PackedVector2Array) -> float:
	var worst: float = 0.0
	for p: Vector2 in outline:
		worst = maxf(worst, p.length())
	return worst


## At most [param count] points of [param outline], evenly spread.
static func _subsampled(outline: PackedVector2Array, count: int) -> PackedVector2Array:
	if outline.size() <= count:
		return outline
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in count:
		@warning_ignore("integer_division")
		out.append(outline[(i * outline.size()) / count])
	return out


static func _min_x(outline: PackedVector2Array) -> float:
	var best: float = INF
	for p: Vector2 in outline:
		best = minf(best, p.x)
	return best


static func _max_x(outline: PackedVector2Array) -> float:
	var best: float = -INF
	for p: Vector2 in outline:
		best = maxf(best, p.x)
	return best


## [param outline] clipped to X <= 0 ([param left]) or X >= 0.
static func _clip_x(outline: PackedVector2Array, left: bool) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var n: int = outline.size()
	for i: int in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var a_in: bool = a.x <= EPS if left else a.x >= -EPS
		var b_in: bool = b.x <= EPS if left else b.x >= -EPS
		if a_in:
			out.append(a)
		if a_in != b_in and absf(b.x - a.x) > EPS:
			var t: float = -a.x / (b.x - a.x)
			out.append(Vector2(0.0, a.y + (b.y - a.y) * t))
	return out


## Where the ray from the origin at angle [param phi] leaves [param outline]. The outlines here
## are star-shaped about the origin, so there is one crossing; 0 when none is found.
static func _radius_at(outline: PackedVector2Array, phi: float) -> float:
	var dir: Vector2 = Vector2(cos(phi), sin(phi))
	var n: int = outline.size()
	var best: float = 0.0
	for i: int in n:
		var a: Vector2 = outline[i]
		var e: Vector2 = outline[(i + 1) % n] - a
		var denom: float = dir.cross(e)
		if absf(denom) < EPS:
			continue
		var t: float = a.cross(e) / denom
		var s: float = a.cross(dir) / denom
		if s >= -EPS and s <= 1.0 + EPS and t > 0.0:
			best = maxf(best, t)
	return best


# --- leaves ----------------------------------------------------------------------------------


## [param leaf] rotated by [param angle] about the gasket's Y axis through the hinge line at
## X = [param hinge_x], Z = [param z_far].
static func _swung(
	leaf: PolyMesh, gasket: Transform3D, hinge_x: float, z_far: float, angle: float
) -> PolyMesh:
	if absf(angle) < EPS:
		return leaf
	var pivot: Vector3 = gasket * Vector3(hinge_x, 0.0, z_far)
	var turn: Basis = Basis(gasket.basis.y.normalized(), angle)
	var xform: Transform3D = Transform3D(turn, pivot - turn * pivot)
	return leaf.transformed(xform)


## The iris: DOOR_BLADES wedges of the seat between spokes, each cut back to the aperture -
## the hole scaled by [param amount] - so the eye opens from the centre out.
static func _iris(
	door: Dictionary, gasket: Transform3D, z_lo: float, z_hi: float, amount: float
) -> Array[PolyMesh]:
	var out: Array[PolyMesh] = []
	var blades: int = int(door.get(DOOR_BLADES, IRIS_DEFAULT_BLADES))
	var seat: PackedVector2Array = door[DOOR_SEAT]
	var profile: PackedVector2Array = door[DOOR_PROFILE]
	var samples: int = maxi(IRIS_SAMPLES_PER_BLADE, 2)
	for i: int in blades:
		var a0: float = TAU * float(i) / float(blades)
		var a1: float = TAU * float(i + 1) / float(blades)
		var poly: PackedVector2Array = PackedVector2Array()
		for k: int in samples:
			var phi: float = lerpf(a0, a1, float(k) / float(samples - 1))
			poly.append(Vector2(cos(phi), sin(phi)) * _radius_at(seat, phi))
		if amount > EPS:
			for k: int in samples:
				var phi: float = lerpf(a1, a0, float(k) / float(samples - 1))
				poly.append(Vector2(cos(phi), sin(phi)) * (_radius_at(profile, phi) * amount))
		else:
			poly.append(Vector2.ZERO)
		var blade: PolyMesh = prism(poly, gasket, z_lo, z_hi)
		if not blade.is_empty():
			out.append(blade)
	return out


# --- frames ----------------------------------------------------------------------------------


## [param basis] made orthonormal with [param axis] as its Z, keeping its Y as up where it can.
static func _orthonormal(basis: Basis, axis: Vector3) -> Basis:
	var y: Vector3 = basis.y - axis * basis.y.dot(axis)
	if y.length_squared() < EPS:
		y = basis.x - axis * basis.x.dot(axis)
	if y.length_squared() < EPS:
		y = Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
		y = y - axis * y.dot(axis)
	y = y.normalized()
	var x: Vector3 = y.cross(axis).normalized()
	return Basis(x, y, axis)
