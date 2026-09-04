class_name ShipSdf
extends RefCounted

## The whole ship as one signed distance field: every part's `ResolvedShape` evaluated in its
## own local space and combined with `min()`, or with a polynomial smooth-min where that part
## carries a `blend > 0` (SPEC section 9).
##
## Built once per rebuild. `build()` resolves the shapes and the ship-space transforms through
## `ShipAttach`, then caches the INVERSE transform and the union AABB — `sample()` runs
## millions of times per bake and must never recompute either.
##
## Two honest caveats, both from SPEC section 9, neither a bug:
## 1. Interior distance from a union of `min()`s is not exact. Exact outside; inside, each part
##    only knows its own surface, some of which is no longer real boundary, so near a joint the
##    `-thickness` level set sits slightly too far out.
## 2. Non-uniform scale makes a field a bound, not a distance. Part scale is handled inside
##    `ResolvedShape.sdf()`; `_dist` below is the same conservative correction (multiply by the
##    smallest basis column length) applied to the transform, and is 1.0 for a rigid basis.
##
## SEAM WALLS (ADR 0008). RETIRED(ADR 0008, 2026-09-02): "the Phase 1 bake produces the all-open
## studio hull with no walls" -> every seam a part makes with the part it stands on carries a
## PLATE unless its joint says `open` ([ShipSeams]). The plate is the host's own skin continued
## across the opening the union removed: a slab of hull thickness T on the INNER side of the seam
## plane, `[P - T, P]` along the normal, clipped to the child's cross-section, with the seam's
## opening (a doorway, a hatch) subtracted. It enters the field as
##     f = max(union_d, -T - plate_d)
## which is the only way a wall can be added to a `min()` union: inside the plate `-T - plate_d`
## sits in `[-T, -T/2]` - solid but never cavity - so the OUTER surface (level 0) is untouched
## and the INTERIOR isosurface (level -T, the one [HullBake] extracts for the cavity) gains the
## plate's two faces, which close against the cavity wall exactly where `union_d == -T`. Outside
## the plate the term is below -T and can only distort distances that no isosurface reads.
## Unioning a solid plate with `min()` instead does nothing: the union is already deep inside
## there. Plates need `T > 0`; at zero thickness the field is the plain union.
##
## MODULE VIEWS ([method module_view]) are the same class with three extra ingredients and no
## plates: an entry may carry a CLIP (a half-space of a seam plane - the child keeps its outer
## side, so its seam face comes out flat; the host gains the child's inner side as the collar
## the author called "added to each other"), and PUCKS bore the seam's opening through the flat
## face and the collar. The exploded view bakes one of these per module.
##
## `core/` purity: RefCounted, no engine objects, no `res://`.

## What an empty ship returns: far outside everything, finite so the gradient stays usable.
const EMPTY_DISTANCE: float = 1.0e30

## Below this, a basis column length is treated as degenerate rather than as a distance scale.
const MIN_BASIS_SCALE: float = 0.000001

## Over-reach, in metres, of a puck past the wall it bores through, so the hole is never left
## with a skin one sample thick at either end.
const PUCK_SLACK_M: float = 0.02

## Half-space clip signs. A half-space-clipped entry contributes `max(part_d, sign * q.z)`, `q`
## the point in the seam frame: OUTER keeps `q.z >= 0` (the child's side of its seam), INNER
## keeps `q.z <= 0`.
const CLIP_NONE: float = 0.0
const CLIP_OUTER: float = -1.0
const CLIP_INNER: float = 1.0

## Seam styles as ints, for the sample loop. Same three as [ShipSeams]' string vocabulary; the
## strings are the stored form and these are what the hot path compares.
const STYLE_FLAT: int = 0
const STYLE_PARENT: int = 1
const STYLE_CHILD: int = 2


## What one entry of a MODULE VIEW is cut back by (ADR 0009). Null on an unclipped entry, and
## always null in an assembled field.
##
## A CLASS rather than a dictionary because this is read inside [method sample], which runs
## millions of times per bake: a dictionary lookup per entry per sample is the one cost this
## file exists to avoid.
class Clip:
	extends RefCounted

	## Seam frame inverse and a CLIP_* sign, for the flat style's half-space. `sign` of
	## CLIP_NONE means this clip carries no half-space.
	var inv: Transform3D = Transform3D.IDENTITY
	var sign: float = 0.0
	## Solids subtracted from this entry, for the parent/child styles. A module can be indented
	## by more than one neighbour, so this is a list and not one shape.
	var shapes: Array[ResolvedShape] = []
	var shape_inv: Array[Transform3D] = []
	var shape_dist: PackedFloat32Array = PackedFloat32Array()

	func subtract(shape: ResolvedShape, world_inv: Transform3D, dist: float) -> void:
		shapes.append(shape)
		shape_inv.append(world_inv)
		shape_dist.append(dist)

	func is_empty() -> bool:
		return sign == 0.0 and shapes.is_empty()

	## `d` cut back by this clip.
	func apply(d: float, p: Vector3) -> float:
		var out: float = d
		if sign != 0.0:
			out = maxf(out, sign * (inv * p).z)
		for i: int in shapes.size():
			out = maxf(out, -(shapes[i].sdf(shape_inv[i] * p) * shape_dist[i]))
		return out


var _ids: PackedStringArray = PackedStringArray()
var _shapes: Array[ResolvedShape] = []
var _inv: Array[Transform3D] = []
var _blend: PackedFloat32Array = PackedFloat32Array()
var _dist: PackedFloat32Array = PackedFloat32Array()
## Per-part world-space AABB, index-aligned with _ids. Computed during build() anyway, on the
## way to the scene bounds; kept because sampling it back out of the field is both slower and
## less accurate than the exact box that produced it.
var _boxes: Array[AABB] = []
var _bounds: AABB = AABB()
var _count: int = 0

## Per-entry clip, index-aligned with _ids. Null where the entry is not cut back at all, which
## is every entry of an assembled field.
var _clips: Array[Clip] = []

## The seams, as [ShipSeams] records, for read-back.
var _seams: Array[Dictionary] = []

## THE PLATES, as parallel arrays holding only the seams that lay one — an `open` seam is absent
## rather than skipped. Everything [method _with_plates] needs, with no dictionary lookup and no
## string compare in the sample loop: the seam frame's inverse, the entry indices of the child
## and the host, the region the plate can touch, the opening cut through it, and the STYLE that
## says which surface the plate lies on (ADR 0009).
var _plate_inv: Array[Transform3D] = []
var _plate_child: PackedInt32Array = PackedInt32Array()
var _plate_host: PackedInt32Array = PackedInt32Array()
var _plate_box: Array[AABB] = []
var _plate_hole: Array[Dictionary] = []
var _plate_style: PackedInt32Array = PackedInt32Array()
var _plate_count: int = 0
var _thickness: float = 0.0
## How thick the plates are actually laid: `_thickness` from build(), or more after
## [method with_min_wall_m]. The wall's field value still peaks at -T/2 whatever this is.
var _plate_thickness: float = 0.0

## Module-view pucks: the holes bored through a flat seam face or a collar. Parallel arrays.
var _puck_inv: Array[Transform3D] = []
var _puck_hole: Array[Dictionary] = []
var _puck_zmin: PackedFloat32Array = PackedFloat32Array()
var _puck_zmax: PackedFloat32Array = PackedFloat32Array()
## Entry index whose cross-section IS the opening (an `open` seam), else -1.
var _puck_foot: PackedInt32Array = PackedInt32Array()
var _puck_box: Array[AABB] = []
var _puck_count: int = 0


## Resolves the doc into a sampleable field. Part order follows `ShipDoc.part_order()` (root
## first, then depth-first by id) so results are deterministic; any extra ids the attach pass
## produced are appended in sorted order, which matches `ShipAttach.ordered_part_ids()`.
##
## Derived symmetry twins ("<source>~m") arrive from the attach pass in the transform map and are
## unioned like any other lobe, so a mirrored ship bakes as one solid. Legacy mirror derivatives
## are real doc parts and are included too. A component instance arrives the same way: its own id
## carries the proxy shape `ShipAttach.resolve_shapes()` resolves from its definition's root, and
## the rest of the definition follows under `"<instance>/<inner>"` ids, so a component bakes whole.
## RETIRED(2026-09-02): the rest of a definition being "placed by `ShipComponents.expand()`, not
## here" -> the attach pass emits it (`ShipAttach._expand_instance_shapes`), and expand() reads it.
static func build(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> ShipSdf:
	var out: ShipSdf = ShipSdf.new()
	if doc == null:
		return out
	# Resolve the shapes ONCE and hand that dictionary to the transform pass. `resolve_all()`
	# would re-resolve every shape internally, and shape generation is the expensive half of a
	# rebuild — the same shapes are then kept for sampling.
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	# Accumulate into locals: appending straight into another object's packed-array member
	# would hit copy-on-write and be silently discarded.
	var ids: PackedStringArray = PackedStringArray()
	var resolved: Array[ResolvedShape] = []
	var inverses: Array[Transform3D] = []
	var blends: PackedFloat32Array = PackedFloat32Array()
	var scales: PackedFloat32Array = PackedFloat32Array()
	var boxes: Array[AABB] = []
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	for id: String in _build_order(doc, xforms):
		var shape_v: Variant = shapes.get(id)
		if not (shape_v is ResolvedShape):
			continue
		var xform_v: Variant = xforms.get(id)
		if not (xform_v is Transform3D):
			continue
		var shape: ResolvedShape = shape_v
		var xform: Transform3D = xform_v
		ids.append(id)
		resolved.append(shape)
		inverses.append(xform.affine_inverse())
		blends.append(_blend_for(doc, id))
		scales.append(_distance_scale(xform))
		var box: AABB = xform * shape.local_aabb()
		boxes.append(box)
		if has_bounds:
			bounds = bounds.merge(box)
		else:
			bounds = box
			has_bounds = true
	out._ids = ids
	out._boxes = boxes
	out._shapes = resolved
	out._inv = inverses
	out._blend = blends
	out._dist = scales
	out._bounds = bounds
	out._count = ids.size()
	out._clips.resize(ids.size())
	if cfg != null:
		out._thickness = maxf(cfg.hull_thickness_m, 0.0)
		out._plate_thickness = out._thickness
		out._install_seams(ShipSeams.seams(doc, shapes, xforms, cfg, data))
	return out


## Signed distance to the whole ship at `p`, in SHIP space. Negative inside.
func sample(p: Vector3) -> float:
	var n: int = _count
	if n == 0:
		return EMPTY_DISTANCE
	var d: float = _shapes[0].sdf(_inv[0] * p) * _dist[0]
	var clip0: Clip = _clips[0]
	if clip0 != null:
		d = clip0.apply(d, p)
	for i: int in range(1, n):
		var di: float = _shapes[i].sdf(_inv[i] * p) * _dist[i]
		var clip: Clip = _clips[i]
		if clip != null:
			di = clip.apply(di, p)
		var k: float = _blend[i]
		if k > 0.0:
			d = SdfOps.smooth_min(d, di, k)
		else:
			d = minf(d, di)
	if _plate_count > 0:
		d = _with_plates(d, p)
	if _puck_count > 0:
		d = _with_pucks(d, p)
	return d


## Normalised field gradient by central differences (6 samples) — the surface normal.
## Falls back to +Y in the degenerate case so callers never get a zero-length "normal".
func gradient(p: Vector3, eps: float) -> Vector3:
	var h: float = maxf(eps, MIN_BASIS_SCALE)
	var gx: float = sample(p + Vector3(h, 0.0, 0.0)) - sample(p - Vector3(h, 0.0, 0.0))
	var gy: float = sample(p + Vector3(0.0, h, 0.0)) - sample(p - Vector3(0.0, h, 0.0))
	var gz: float = sample(p + Vector3(0.0, 0.0, h)) - sample(p - Vector3(0.0, 0.0, h))
	var g: Vector3 = Vector3(gx, gy, gz)
	if g.length_squared() <= 0.0:
		return Vector3.UP
	return g.normalized()


## Union of the transformed per-part AABBs, computed at build time. Empty ship -> empty AABB.
func aabb() -> AABB:
	return _bounds


## World-space AABB of one part, EXACT - it is the shape's local AABB through the part's own
## transform, not a probe of the field.
##
## Exists because probing was wrong. Island detection used to recover each part's box by sampling
## the union field on a fixed 10-step grid spanning the WHOLE ship, so the cell size grew with the
## ship: turning symmetry on doubled the scene width, the grid got coarser, small parts stopped
## registering entirely, and every part came back as its own island. Resolution-dependent geometry
## in a connectivity test is a bug waiting for a big enough ship - this has no resolution.
func part_aabb(index: int) -> AABB:
	if index < 0 or index >= _boxes.size():
		return AABB()
	return _boxes[index]


func part_count() -> int:
	return _count


## Part id at `index`, or "" when out of range. Index order is the build order.
func part_id_at(index: int) -> String:
	if index < 0 or index >= _count:
		return ""
	return _ids[index]


## Distance to one part alone, ignoring every other part, every blend, every clip and every
## plate.
func sample_part(index: int, p: Vector3) -> float:
	if index < 0 or index >= _count:
		return EMPTY_DISTANCE
	return _shapes[index].sdf(_inv[index] * p) * _dist[index]


## The seams this field was built over ([ShipSeams] records), in order. Empty for a module view.
func seams() -> Array[Dictionary]:
	return _seams.duplicate()


func seam_count() -> int:
	return _seams.size()


## The hull thickness the plates were laid at.
func thickness() -> float:
	return _thickness


## The same field with every plate at least `min_wall_m` thick, for a grid that could not see
## them thinner. A plate is a BUMP in the field - cavity, wall, cavity - and a bump narrower than
## the sample spacing can fall between two samples and vanish, unlike the hull skin, which the
## field crosses monotonically and the extractor finds by interpolation however thin it is.
## [HullBake] therefore widens the plates to its real grid spacing (ADR 0008): a coarse bake gets
## a thicker bulkhead rather than none. The wall's field value still peaks at -T/2, so the outer
## surface is untouched, and the extra thickness goes INTO the host, the side the plate always
## lay on. Shares every shape with this field; nothing is copied but the bookkeeping. At zero
## hull thickness there are still no plates - a skinless hull has no walls to widen.
func with_min_wall_m(min_wall_m: float) -> ShipSdf:
	var out: ShipSdf = ShipSdf.new()
	out._ids = _ids
	out._shapes = _shapes
	out._inv = _inv
	out._blend = _blend
	out._dist = _dist
	out._boxes = _boxes
	out._bounds = _bounds
	out._count = _count
	out._clips = _clips
	out._seams = _seams
	out._plate_inv = _plate_inv
	out._plate_child = _plate_child
	out._plate_host = _plate_host
	out._plate_hole = _plate_hole
	out._plate_style = _plate_style
	out._plate_count = _plate_count
	out._thickness = _thickness
	out._plate_thickness = maxf(_thickness, maxf(min_wall_m, 0.0))
	var boxes: Array[AABB] = []
	for s: int in _plate_child.size():
		boxes.append(_boxes[_plate_child[s]].grow(out._plate_thickness + PUCK_SLACK_M))
	out._plate_box = boxes
	out._puck_inv = _puck_inv
	out._puck_hole = _puck_hole
	out._puck_zmin = _puck_zmin
	out._puck_zmax = _puck_zmax
	out._puck_foot = _puck_foot
	out._puck_box = _puck_box
	out._puck_count = _puck_count
	return out


## How thick the plates are actually laid - see [method with_min_wall_m].
func plate_thickness() -> float:
	return _plate_thickness


## ONE MODULE ON ITS OWN, cut and bored the way the exploded view shows it (ADR 0008):
##
##   - its own entries (the id, and for an instance every "<id>/<inner>" part), each clipped to
##     the OUTER side of the module's seam so the face it stood on comes out flat - "subtracted";
##   - for every seam whose host it is, the child's entry clipped to the INNER side: the collar
##     of the child that was sunk into it stays with the host - "added";
##   - a puck through its own flat face wherever its seam has an opening, and a puck down
##     through each collar and the skin beneath it wherever THAT seam has an opening. An `open`
##     seam's puck is the whole cross-section, so the face is left off entirely.
##
## No plates: the flat face gets its T-thick wall from the interior isosurface for free. Baking
## the result at levels 0 and -T therefore gives a closed shell whose seam face is a wall with the
## door in it. Shapes are shared with this field, never copied. An unknown id gives an empty field.
func module_view(module_id: String) -> ShipSdf:
	var out: ShipSdf = ShipSdf.new()
	out._thickness = _thickness
	var own: Dictionary = _seam_for_child(module_id)

	# What cuts this module's OWN entries: its seam with the module it stands on, resolved by
	# style (ADR 0009). FLAT keeps the outer half-space; PARENT subtracts the host, which is the
	# dent the host presses into it; CHILD cuts nothing, because under that style the module
	# keeps its whole shape and the HOST is the one that loses a socket.
	var own_clip: Clip = Clip.new()
	if not own.is_empty():
		var own_style: int = style_code(str(own.get(ShipSeams.SEAM_STYLE, ShipSeams.STYLE_FLAT)))
		if own_style == STYLE_FLAT:
			own_clip.inv = (own[ShipSeams.SEAM_FRAME] as Transform3D).affine_inverse()
			own_clip.sign = CLIP_OUTER
		elif own_style == STYLE_PARENT:
			var host: int = _index_of(own[ShipSeams.SEAM_HOST])
			if host >= 0:
				own_clip.subtract(_shapes[host], _inv[host], _dist[host])
	# ... and every child that INDENTS this module takes its solid out of it as well.
	for seam: Dictionary in _seams:
		if seam[ShipSeams.SEAM_HOST] != module_id:
			continue
		if style_code(str(seam.get(ShipSeams.SEAM_STYLE, ShipSeams.STYLE_FLAT))) != STYLE_CHILD:
			continue
		var child: int = _index_of(seam[ShipSeams.SEAM_CHILD])
		if child >= 0:
			own_clip.subtract(_shapes[child], _inv[child], _dist[child])

	var members: int = 0
	for i: int in _count:
		if ShipSeams.module_of(_ids[i]) != module_id:
			continue
		members += 1
		out._append_entry(self, i, null if own_clip.is_empty() else own_clip)
	if members == 0:
		return out

	# Collars: a FLAT seam splits the overlap at the plane, so the half of each child below the
	# plane stays with this module. The other two styles give the whole overlap to one side or
	# the other and leave nothing to add here.
	for seam: Dictionary in _seams:
		if seam[ShipSeams.SEAM_HOST] != module_id:
			continue
		if style_code(str(seam.get(ShipSeams.SEAM_STYLE, ShipSeams.STYLE_FLAT))) != STYLE_FLAT:
			continue
		var child: int = _index_of(seam[ShipSeams.SEAM_CHILD])
		if child < 0:
			continue
		var collar: Clip = Clip.new()
		collar.inv = (seam[ShipSeams.SEAM_FRAME] as Transform3D).affine_inverse()
		collar.sign = CLIP_INNER
		out._append_entry(self, child, collar)

	# The door through the module's own seam face.
	if not own.is_empty() and own[ShipSeams.SEAM_MODE] != ShipSeams.MODE_WALL:
		var own_inv: Transform3D = (own[ShipSeams.SEAM_FRAME] as Transform3D).affine_inverse()
		var foot: int = -1
		if own[ShipSeams.SEAM_MODE] == ShipSeams.MODE_OPEN:
			foot = out._index_of(str(own[ShipSeams.SEAM_CHILD]))
		out._add_puck(
			own_inv,
			own[ShipSeams.SEAM_HOLE],
			-PUCK_SLACK_M,
			_thickness + PUCK_SLACK_M,
			foot,
			_puck_reach(str(own[ShipSeams.SEAM_CHILD]))
		)
	# The door down through each child's seam and the skin under it.
	for seam: Dictionary in _seams:
		if seam[ShipSeams.SEAM_HOST] != module_id:
			continue
		if seam[ShipSeams.SEAM_MODE] == ShipSeams.MODE_WALL:
			continue
		var child: int = _index_of(seam[ShipSeams.SEAM_CHILD])
		if child < 0:
			continue
		var seam_inv: Transform3D = (seam[ShipSeams.SEAM_FRAME] as Transform3D).affine_inverse()
		var depth: float = _stub_depth(_boxes[child], seam_inv)
		var foot: int = -1
		if seam[ShipSeams.SEAM_MODE] == ShipSeams.MODE_OPEN:
			foot = out._index_of(str(seam[ShipSeams.SEAM_CHILD]))
		out._add_puck(
			seam_inv,
			seam[ShipSeams.SEAM_HOLE],
			-(depth + _thickness + PUCK_SLACK_M),
			PUCK_SLACK_M,
			foot,
			_puck_reach(str(seam[ShipSeams.SEAM_CHILD]))
		)
	out._count = out._ids.size()
	out._puck_count = out._puck_inv.size()
	return out


# --- internals -----------------------------------------------------------------------------


## Deterministic evaluation order: the doc's own order first, then anything else the attach
## pass produced, sorted so a rebuild never reshuffles the union.
static func _build_order(doc: ShipDoc, xforms: Dictionary) -> PackedStringArray:
	var order: PackedStringArray = doc.part_order()
	var seen: Dictionary = {}
	for id: String in order:
		seen[id] = true
	var extra: PackedStringArray = PackedStringArray()
	for id: String in xforms:
		if not seen.has(id):
			extra.append(id)
	extra.sort()
	for id: String in extra:
		order.append(id)
	return order


## The part's smooth-union radius. Generated ids that are not doc parts (an expanded component
## instance, "instance_id/inner_id") inherit the blend of the instance they came from.
static func _blend_for(doc: ShipDoc, id: String) -> float:
	var part_v: Variant = doc.parts.get(id)
	if not (part_v is ShipPart):
		# A derived symmetry twin ("<source>~m") inherits its source's blend; without this it
		# would hard-union where its source smooth-unions and the two sides of the ship would
		# not match.
		part_v = doc.parts.get(ShipSymmetry.source_of_twin(id))
	if not (part_v is ShipPart):
		var slash: int = id.find("/")
		if slash > 0:
			part_v = doc.parts.get(id.substr(0, slash))
	if part_v is ShipPart:
		var part: ShipPart = part_v
		return maxf(part.blend, 0.0)
	return 0.0


## Conservative distance correction for a transform that is not a rigid motion. Attach
## transforms ARE rigid — per-axis part scale lives inside `ResolvedShape.sdf()` as a domain
## warp and never enters a transform basis — so this is exactly 1.0 and costs nothing. It exists
## only so a non-rigid basis degrades to a valid bound instead of a wrong distance.
static func _distance_scale(xform: Transform3D) -> float:
	var sx: float = xform.basis.x.length()
	var sy: float = xform.basis.y.length()
	var sz: float = xform.basis.z.length()
	var lo: float = minf(sx, minf(sy, sz))
	if lo < MIN_BASIS_SCALE:
		return 1.0
	if is_equal_approx(lo, 1.0):
		return 1.0
	return lo


## Record the seams and lay a plate for every non-open one whose child AND host are in the field.
## The plate's reach is the child's box grown by T: beyond it the plate term is under -2T and no
## isosurface this field is read at can see it.
##
## An `open` seam lays no plate and is simply absent from the plate arrays, so [method
## _with_plates] never has to ask what mode a seam is.
func _install_seams(records: Array[Dictionary]) -> void:
	var seams_kept: Array[Dictionary] = []
	var invs: Array[Transform3D] = []
	var children: PackedInt32Array = PackedInt32Array()
	var hosts: PackedInt32Array = PackedInt32Array()
	var boxes: Array[AABB] = []
	var holes: Array[Dictionary] = []
	var styles: PackedInt32Array = PackedInt32Array()
	for seam: Dictionary in records:
		var child: int = _index_of(seam[ShipSeams.SEAM_CHILD])
		if child < 0:
			continue
		seams_kept.append(seam)
		if seam[ShipSeams.SEAM_MODE] == ShipSeams.MODE_OPEN:
			continue
		var host: int = _index_of(seam[ShipSeams.SEAM_HOST])
		if host < 0:
			continue
		var frame: Transform3D = seam[ShipSeams.SEAM_FRAME]
		invs.append(frame.affine_inverse())
		children.append(child)
		hosts.append(host)
		boxes.append(_boxes[child].grow(_plate_thickness + PUCK_SLACK_M))
		holes.append(seam[ShipSeams.SEAM_HOLE])
		styles.append(style_code(str(seam.get(ShipSeams.SEAM_STYLE, ShipSeams.STYLE_FLAT))))
	_seams = seams_kept
	_plate_inv = invs
	_plate_child = children
	_plate_host = hosts
	_plate_box = boxes
	_plate_hole = holes
	_plate_style = styles
	# Plates need a thickness to be made of; at T == 0 the field stays the plain union.
	_plate_count = invs.size() if _thickness > 0.0 else 0


## [ShipSeams]' stored style string as the int the sample loop compares.
static func style_code(style: String) -> int:
	if style == ShipSeams.STYLE_PARENT:
		return STYLE_PARENT
	if style == ShipSeams.STYLE_CHILD:
		return STYLE_CHILD
	return STYLE_FLAT


## The plate term, see the class docs. `d` is the union so far.
##
## The plate distance is scaled by T / plate thickness before it becomes a field value, so a
## widened plate ([method with_min_wall_m]) still reads -T on its faces and -T/2 at its centre:
## thicker, never taller, and never above the outer surface.
func _with_plates(d: float, p: Vector3) -> float:
	var t: float = _thickness
	var tp: float = maxf(_plate_thickness, t)
	var gain: float = t / tp if tp > 0.0 else 1.0
	var out: float = d
	for s: int in _plate_count:
		if not _plate_box[s].has_point(p):
			continue
		var q: Vector3 = _plate_inv[s] * p
		var child: int = _plate_child[s]
		var host: int = _plate_host[s]
		var child_d: float = _shapes[child].sdf(_inv[child] * p) * _dist[child]
		# ONE RULE, THREE SEAM SURFACES (ADR 0009): the plate is the shell of thickness `tp`
		# lying just INSIDE the seam surface, clipped to the other solid. `surface` is the
		# signed distance to whichever surface this style seams on, and `clip` the solid the
		# shell is trimmed to.
		var surface: float = q.z
		var clip: float = child_d
		var style: int = _plate_style[s]
		if style != STYLE_FLAT:
			var host_d: float = _shapes[host].sdf(_inv[host] * p) * _dist[host]
			if style == STYLE_PARENT:
				# The parent indents the child: the seam follows the HOST's surface.
				surface = host_d
			else:
				# The child indents the parent: the seam follows the CHILD's surface, and the
				# shell is trimmed to the host instead.
				surface = child_d
				clip = host_d
		var plate: float = maxf(-surface - tp, surface)
		if clip > plate:
			plate = clip
		var hole: Dictionary = _plate_hole[s]
		if not hole.is_empty():
			var open_d: float = -ShipSeams.hole_distance(hole, Vector2(q.x, q.y))
			if open_d > plate:
				plate = open_d
		var wall: float = -t - plate * gain
		if wall > out:
			out = wall
	return out


## The puck term of a module view: each hole subtracts its profile over its depth range.
func _with_pucks(d: float, p: Vector3) -> float:
	var out: float = d
	for k: int in _puck_count:
		if not _puck_box[k].has_point(p):
			continue
		var q: Vector3 = _puck_inv[k] * p
		var depth: float = maxf(_puck_zmin[k] - q.z, q.z - _puck_zmax[k])
		var profile: float
		var foot: int = _puck_foot[k]
		if foot >= 0:
			profile = _shapes[foot].sdf(_inv[foot] * p) * _dist[foot]
		else:
			profile = ShipSeams.hole_distance(_puck_hole[k], Vector2(q.x, q.y))
		var puck: float = maxf(depth, profile)
		if -puck > out:
			out = -puck
	return out


func _index_of(id: String) -> int:
	for i: int in _count:
		if _ids[i] == id:
			return i
	return -1


## The seam record where `id` is the CHILD - the one seam that says how this module meets the
## module it stands on - or {} for a root.
func _seam_for_child(id: String) -> Dictionary:
	for seam: Dictionary in _seams:
		if seam[ShipSeams.SEAM_CHILD] == id:
			return seam
	return {}


## How far a puck through a seam may reach: the child's own box, grown so the hole clears both
## faces of the wall it bores. An id the field does not hold gives an empty box, which stops
## the puck touching anything.
func _puck_reach(child_id: String) -> AABB:
	var index: int = _index_of(child_id)
	if index < 0:
		return AABB()
	return _boxes[index].grow(_plate_thickness + PUCK_SLACK_M)


## Copy entry `index` of `source` into this field with a clip (null for none). Bounds grow with
## it. `_count` is left to the caller, which finishes the build.
func _append_entry(source: ShipSdf, index: int, clip: Clip) -> void:
	_ids.append(source._ids[index])
	_shapes.append(source._shapes[index])
	_inv.append(source._inv[index])
	_blend.append(source._blend[index])
	_dist.append(source._dist[index])
	var box: AABB = source._boxes[index]
	_boxes.append(box)
	_clips.append(clip)
	if _ids.size() == 1:
		_bounds = box
	else:
		_bounds = _bounds.merge(box)
	_count = _ids.size()


func _add_puck(
	inv: Transform3D, hole: Dictionary, zmin: float, zmax: float, foot: int, box: AABB
) -> void:
	_puck_inv.append(inv)
	_puck_hole.append(hole)
	_puck_zmin.append(zmin)
	_puck_zmax.append(zmax)
	_puck_foot.append(foot)
	_puck_box.append(box)


## How far a child's box reaches below its seam plane, along -N: the depth of the collar it
## leaves in its host. Zero for a child that sits entirely outside.
static func _stub_depth(box: AABB, seam_inv: Transform3D) -> float:
	var deepest: float = 0.0
	for i: int in 8:
		var corner: Vector3 = box.get_endpoint(i)
		var q: Vector3 = seam_inv * corner
		if -q.z > deepest:
			deepest = -q.z
	return deepest
