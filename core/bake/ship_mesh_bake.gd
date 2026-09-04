class_name ShipMeshBake
## The exact bake: every part tessellated into its own solid [PolyMesh], placed in ship space.
##
## ONE MESH PER PART, NOT ONE MESH PER SHIP, and that is a design decision rather than a stage on
## the way to welding them: "all primatives can be their own mesh, we arent trying to create a
## single ship mesh, they can remain in parts as in space they will have detach capabilities."
## A module that can come off in flight has to exist as a closed solid on its own, so it is built
## as one and never merged into its neighbours.
##
## WHAT THAT BUYS. The two failure modes a whole-ship union has — fragments accumulating across a
## dozen operations, and the pathological cost of near-coplanar solids unioned repeatedly — do not
## arise, because no part is ever unioned into another. Every boolean below is a single PAIRWISE
## operation between two parts that share a seam, on meshes of a few dozen faces, and its result is
## never a cutter for the next one. Each part starts as [ShapeMesh]'s output moved by its attach
## transform, and is exact for the same reason that is: every vertex is placed analytically.
##
## SEAMS ARE RESOLVED, THOUGH, AND THAT IS THE ONE PLACE A BOOLEAN RUNS. A child is seated INTO
## its parent (SPEC §3), so the two solids interpenetrate by the embed depth, and the author picks
## per pair what should happen to that overlap (ADR 0009):
##
##   FLAT   - the child is cut back to the seam plane and comes out with a flat mating face.
##            The host is left whole.
##   PARENT - the host dents the child: the host solid is subtracted from the child.
##   CHILD  - the child dents the host: the child solid is subtracted from the host.
##
## RETIRED(2026-09-03b): "Nothing here trims that". The first cut of this file ran no boolean at
## all, which quietly dropped a feature that already worked through [method ShipSdf.module_view] -
## "i right click 2 selected solids, i press the option i want ... and then after i press explode
## and it does not show the created manifolds." The styles are read from the JOINT, never baked
## into the part, so switching one is non-destructive and switching back costs nothing.
##
## THE CUTTERS ARE THE ORIGINAL SOLIDS, never the partly-cut ones. A part can be the child of one
## seam and the host of another, so cutting with whatever happens to be in hand at the time would
## make the result depend on seam order - and seam order is a Dictionary walk. Every cut is taken
## against the part as tessellated.
##
## NOTHING IS EVER UNIONED, and that is now a rule rather than an accident. RETIRED(2026-09-03d):
## the FLAT style used to hand the host a COLLAR - the child's half below the seam plane - unioned
## on, mirroring what [method ShipSdf.module_view] does in the field. It was wrong twice over.
##
## Visually: the seam plane is the tangent plane at the ATTACH POINT, so on a curved host or a box
## CORNER it is not the host's surface. `argon` attaches eight branches at the corners of a box,
## and each collar came out as a spike protruding diagonally past its corner - "somehow it cut the
## upper sphere way into the sphere, and short of the lower sphere".
##
## And by cost: a union is the one operation that GROWS a mesh, so a hub host to eight seams grew
## through eight of them. Measured on `argon`, merging in between and still: 1262 faces after four
## collars, 13442 after five (a 24-second union), 28056 after six (40 seconds), never finishing.
## Where the host is FLAT the collar sat entirely inside it and added nothing anyway, so dropping
## it changes nothing in the common case and removes a spike in the rest. The author had already
## allowed for the gap this leaves on a curved host: "if a thin unseen buffer of space is needed
## between modules thats fine".
##
## Hatch and doorway OPENINGS are not bored here yet; that is the next piece of work.
##
## THE SDF IS STILL THE TRUTH LAYER. Attach, snapping, joints, metrics and the budget gates all
## read [ShipSdf] and are untouched; this replaces only how the visible mesh is produced. The two
## agree by construction and it is checked rather than assumed — [ShapeMesh] inverts the very
## domain warps [method ResolvedShape.sdf] applies, and the test suite asserts that every baked
## vertex samples to zero in the field it came from.
##
## Pure data (SPEC §12): [ArrayMesh] is a [Resource], not a [Node], so returning one is inside the
## boundary. No [SceneTree], no signals, no [code]res://[/code]. Arguments are never mutated.


## Bakes every placed part of [param doc].
##
## Returns [code]{ "order": PackedStringArray, "solids": Dictionary, "meshes": Dictionary,
## "edges": Dictionary, "faces": int, "tris": int, "verts": int, "area_m2": float,
## "parts_volume_m3": float, "aabb": AABB, "open_parts": PackedStringArray, "ms": int }[/code].
##
## [code]solids[/code] maps a placed id to its [PolyMesh] in SHIP space, [code]meshes[/code] to
## the [ArrayMesh] a renderer wants, and [code]edges[/code] to the model edges a wireframe should
## draw — real edges only, never triangulation diagonals.
##
## [code]parts_volume_m3[/code] is the SUM OF THE PARTS and therefore over-reads the ship wherever
## two of them overlap, which is at every joint. It is a per-part figure reported honestly rather
## than a hull volume; [ShipMetrics] remains the answer for what the ship encloses.
##
## [code]open_parts[/code] lists any part that did not come out a closed solid. It should always
## be empty; if it is not, the tessellator met a shape it could not close and the caller is being
## told rather than shown a hull with a hole in it.
static func bake(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, segments: int = ShapeMesh.RADIAL_SEGMENTS
) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var out: Dictionary = _empty(t0)
	if doc == null or data == null or cfg == null:
		return out

	# Resolved ONCE and handed on, exactly as ShipSdf.build does it: shape generation is the
	# expensive half of a rebuild and resolve_all() would repeat it internally.
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)

	var solids: Dictionary = {}
	for id: Variant in xforms.keys():
		var shape_v: Variant = shapes.get(id)
		var xform_v: Variant = xforms.get(id)
		if not (shape_v is ResolvedShape) or not (xform_v is Transform3D):
			continue
		var local: PolyMesh = ShapeMesh.build(shape_v as ResolvedShape, segments)
		if not local.is_empty():
			solids[id] = local.transformed(xform_v as Transform3D)
	solids = _apply_seams(solids, ShipSeams.seams(doc, shapes, xforms, cfg, data), shapes, xforms)

	var order: PackedStringArray = PackedStringArray()
	for id: Variant in solids.keys():
		order.append(id)
	# Sorted, because determinism is a gate in this project and a Dictionary is not ordered by
	# anything a caller can rely on (AGENTS §8b).
	order.sort()

	var meshes: Dictionary = {}
	var edges: Dictionary = {}
	var open_parts: PackedStringArray = PackedStringArray()
	var placed: PackedStringArray = PackedStringArray()
	var faces: int = 0
	var tris: int = 0
	var verts: int = 0
	var area: float = 0.0
	var volume: float = 0.0
	var bounds: AABB = AABB()
	var has_bounds: bool = false

	for id: String in order:
		var solid: PolyMesh = solids[id]
		var mesh: ArrayMesh = solid.to_array_mesh()
		if mesh.get_surface_count() == 0:
			continue
		if solid.open_edges() != 0:
			open_parts.append(id)

		placed.append(id)
		meshes[id] = mesh
		edges[id] = solid.boundary_edges()
		faces += solid.face_count()
		verts += solid.vertices.size()
		@warning_ignore("integer_division")
		var part_tris: int = (
			(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		)
		tris += part_tris
		area += solid.area()
		volume += solid.volume()
		var box: AABB = solid.aabb()
		if has_bounds:
			bounds = bounds.merge(box)
		else:
			bounds = box
			has_bounds = true

	out["order"] = placed
	out["solids"] = solids
	out["meshes"] = meshes
	out["edges"] = edges
	out["faces"] = faces
	out["tris"] = tris
	out["verts"] = verts
	out["area_m2"] = area
	out["parts_volume_m3"] = volume
	out["aabb"] = bounds
	out["open_parts"] = open_parts
	out["ms"] = Time.get_ticks_msec() - t0
	return out


## [param solids] with every seam of [param seams] resolved by its style, then tidied back into
## n-gons.
##
## Order-independent by construction: every cut is taken against [param solids] as they arrived,
## while the results accumulate separately. A part that is the child of one seam and the host of
## another therefore gets both cuts, and gets the same two whichever seam is visited first.
static func _apply_seams(
	solids: Dictionary, seams: Array[Dictionary], shapes: Dictionary, xforms: Dictionary
) -> Dictionary:
	if solids.is_empty() or seams.is_empty():
		return solids
	var out: Dictionary = {}
	for id: Variant in solids:
		out[id] = solids[id]
	var touched: Dictionary = {}

	for seam: Dictionary in seams:
		var child_id: String = str(seam.get(ShipSeams.SEAM_CHILD, ""))
		var host_id: String = str(seam.get(ShipSeams.SEAM_HOST, ""))
		if not solids.has(child_id) or not solids.has(host_id):
			continue
		var frame: Transform3D = seam.get(ShipSeams.SEAM_FRAME, Transform3D.IDENTITY)
		var normal: Vector3 = frame.basis.z.normalized()
		if normal == Vector3.ZERO:
			continue
		var style: String = str(seam.get(ShipSeams.SEAM_STYLE, ShipSeams.STYLE_FLAT))

		# TWO AXES, NOT SIX NAMES (ADR 0013): which solid indents the other, and what the linkage
		# surface is. Both are read off the style id rather than the attach tree - a small part is
		# perfectly able to be the parent of a large one, and which presses into which is a fact
		# about the shapes.
		var big_indents: bool = ShipJoint.indent_of(style) == ShipJoint.INDENT_BIG
		var surface: String = ShipJoint.surface_of(style)

		if surface == ShipJoint.SURFACE_NATIVE:
			# NATIVE: no flattening. The interface is the indenting solid's real surface, which
			# fits any shape exactly, so this is a plain subtraction the other way about.
			var child_is_big: bool = (
				(out[child_id] as PolyMesh).volume() >= (out[host_id] as PolyMesh).volume()
			)
			var big_id: String = child_id if child_is_big else host_id
			var small_id: String = host_id if child_is_big else child_id
			var loser: String = small_id if big_indents else big_id
			var cutter: String = big_id if big_indents else small_id
			out[loser] = _cut(out[loser], solids[cutter])
			touched[loser] = true
		else:
			# A FLAT linkage surface (ADR 0012). The plane comes from where the two surfaces
			# actually cross, so the anchor frame is used only for the DIRECTION to measure along.
			var child_shape: Variant = shapes.get(child_id)
			var host_shape: Variant = shapes.get(host_id)
			if not (child_shape is ResolvedShape) or not (host_shape is ResolvedShape):
				continue
			# The big indenting the small is the OUTERMOST crossing; the small indenting the
			# big is the deepest. A CUTOFF takes the plane straight through the other solid; an
			# INSERT lets in only the indenting solid's own cross-section.
			var flanged: Dictionary = MeshFlange.resolve(
				MeshFlange.Piece.make(out[child_id], child_shape, xforms[child_id]),
				MeshFlange.Piece.make(out[host_id], host_shape, xforms[host_id]),
				normal,
				frame.origin,
				big_indents,
				surface == ShipJoint.SURFACE_FLAT_CUTOFF
			)
			# An empty result means the two never cross, so there is no joint to flatten and
			# both keep the shape they had.
			if flanged.is_empty():
				continue
			out[child_id] = flanged["a"]
			out[host_id] = flanged["b"]
			touched[child_id] = true
			touched[host_id] = true

	assert(touched.size() >= 0)
	return out


## [param target] with [param cutter] taken out of it, or [param target] UNCHANGED when that
## cannot be done without opening it.
##
## THE SAME RULE AS THE OUT-BUMP UNION, and for the same reason: a part can be the host of many
## seams - a carbon nucleus carries nine children - and each cut is taken against the result of the
## last. One failure that is kept feeds the next boolean a broken mesh, and the damage compounds
## instead of staying put. Measured before this guard: `small_native` on a carbon class left the
## nucleus centre open, because its four tunnels each subtract from the same root in turn.
##
## Refusing costs a cut that does not happen - two parts overlap where they would have met flush -
## which is a gap the author has allowed for, and is a far better answer than an open hull.
static func _cut(target: PolyMesh, cutter: PolyMesh) -> PolyMesh:
	var carved: PolyMesh = MeshCsg.subtract(target, cutter)
	if carved.truncated:
		return target
	var tidied: PolyMesh = MeshMerge.merge(carved)
	if tidied.open_edges() == 0:
		return tidied
	if carved.open_edges() == 0:
		return carved
	return target


## One boolean result, tidied back into n-gons before anything else is done to it.
##
## MERGING AFTER EVERY OPERATION IS NOT AN OPTIMISATION, IT IS WHAT STOPS THE BAKE HANGING. A BSP
## shreds both operands into fragments, and a hub is host to as many seams as it has branches - the
## `argon` template has EIGHT on one box. Leaving the merge until the end means collar two is
## unioned into the shredded result of collar one, collar three into the shredding of that, and the
## face count compounds: measured, each of those unions costs 50 ms and its merge 100 ms on their
## own, and the same sixteen seams left unmerged in between did not finish in sixteen MINUTES.
##
## Tidying between operations keeps every operand at the few dozen faces the shape actually has,
## which is the size at which this is fast — and it is why the boolean cost stays proportional to
## the number of seams rather than exploding with them.
static func _tidy(mesh: PolyMesh) -> PolyMesh:
	return MeshMerge.merge(mesh)


## One part, tessellated and placed, or null when [param id] is not a placed part.
##
## For a caller that needs a single module rather than the whole ship — the exploded view rebakes
## one piece at a time — without paying for every other part.
static func bake_part(
	doc: ShipDoc,
	data: ShipData,
	cfg: ShipConfig,
	id: String,
	segments: int = ShapeMesh.RADIAL_SEGMENTS
) -> PolyMesh:
	if doc == null or data == null or cfg == null:
		return null
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	var shape_v: Variant = shapes.get(id)
	var xform_v: Variant = xforms.get(id)
	if not (shape_v is ResolvedShape) or not (xform_v is Transform3D):
		return null
	return ShapeMesh.build(shape_v as ResolvedShape, segments).transformed(xform_v as Transform3D)


static func _empty(t0: int) -> Dictionary:
	return {
		"order": PackedStringArray(),
		"solids": {},
		"meshes": {},
		"edges": {},
		"faces": 0,
		"tris": 0,
		"verts": 0,
		"area_m2": 0.0,
		"parts_volume_m3": 0.0,
		"aabb": AABB(),
		"open_parts": PackedStringArray(),
		"ms": Time.get_ticks_msec() - t0,
	}
