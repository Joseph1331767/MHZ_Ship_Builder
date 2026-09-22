class_name ShipMeshBake
## TWO EXECUTORS, ONE PLAN (ADR 0020). [method plan] is the truth here: pure data saying which
## surfaces of which part are cut by which cutters. [method bake] carries it out with this file's
## own polygon clipping - exact on planes, approximate on curves - and is the fallback for a
## caller with no scene tree. The builder carries the SAME plan out with the engine's CSG
## (ShipCsgBake, harness/), which is exact everywhere and is what the player sees. The paragraphs
## below that describe a BSP union describe RETIRED machinery; the booleans are the engine's now.
##
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
## EVERY MODULE IS A SHELL (ADR 0015). Each part is built solid, an interior surface is derived
## from the same parametric primitive inset by [member ShipConfig.hull_thickness_m], and the one is
## subtracted from the other. The interior is cut by the SAME seams with every plane pushed inward
## and every neighbour fattened, so it stops short of each seam face rather than opening onto it -
## "the hatch and seam surfaces remain solid". A module is therefore a closed shell with no way in.
##
## RETIRED(ADR 0029, 2026-09-06): "Hatch and doorway OPENINGS are not bored here yet" -> they
## are planned here ([ShipDoors], the "doors" of the plan) and bored by the engine executor;
## this pure executor still keeps its walls at them (FOLLOWUPS F41).
##
## THE SDF IS STILL THE TRUTH LAYER. Attach, snapping, joints, metrics and the budget gates all
## read [ShipSdf] and are untouched; this replaces only how the visible mesh is produced. The two
## agree by construction and it is checked rather than assumed — [ShapeMesh] inverts the very
## domain warps [method ResolvedShape.sdf] applies, and the test suite asserts that every baked
## vertex samples to zero in the field it came from.
##
## Pure data (SPEC §12): [ArrayMesh] is a [Resource], not a [Node], so returning one is inside the
## boundary. No [SceneTree], no signals, no [code]res://[/code]. Arguments are never mutated.

## How far apart, as a fraction of one segment, consecutive parts' tessellations are turned about
## their own axes - the golden ratio, so no two of any count land on one phase. See [method bake].
const PHASE_STRIDE: float = 0.6180339887

## How many cells a surface's longest extent is gridded into before it is clipped - the count of
## segments a lathe already has round its waist, halved, since a lathe's polygons are that size.
const CLIP_CELLS: int = 12

## The three cutters a part offers, by name - see [method plan].
const CUT_BODY: String = "body"
const CUT_ROOM: String = "room"
const CUT_GROWN: String = "grown"


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
## [code]hollowed_parts[/code] is how many came out as SHELLS rather than solids, at
## [code]hull_thickness_m[/code] metres of wall. A part thinner than twice that has no interior to
## give it and stays solid, which is the honest answer rather than a wall turned inside out.
##
## [code]open_parts[/code] lists any part that did not come out a closed solid. It should always
## be empty; if it is not, the tessellator met a shape it could not close and the caller is being
## told rather than shown a hull with a hole in it.
static func bake(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, segments: int = ShapeMesh.RADIAL_SEGMENTS
) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var plan: Dictionary = plan(doc, data, cfg, segments)
	if plan.is_empty():
		return _empty(t0)
	var outer: Dictionary = plan["outer"]
	var inner: Dictionary = plan["inner"]
	var cutters: Dictionary = plan["cutters"]
	var solids: Dictionary = {}
	for id: String in plan["ids"]:
		var cuts: Array = []
		for cut: Dictionary in plan["cuts"].get(id, []) + plan["open_cuts"].get(id, []):
			cuts.append({"outer": cutters[cut["outer"]], "inner": cutters[cut["inner"]]})
		solids[id] = _carve(
			outer[id],
			inner.get(id, null),
			cutters[_cutter_key(id, CUT_BODY)],
			cutters.get(_cutter_key(id, CUT_ROOM), null),
			cuts
		)
	return report(solids, plan, t0)


## Everything a bake needs to know, and nothing it has yet done: every placed part's three
## surfaces, and for each part the list of cuts its seams ask for, as
##   { "ids": PackedStringArray (sorted), "outer": {id: PolyMesh}, "inner": {id: PolyMesh},
##     "grown": {id: PolyMesh}, "cutters": {key: MeshClip.Cutter}, "cuts": {id: [ {"outer": key,
##     "inner": key} ]} (the WALLED seams), "open_cuts": the same shape for the OPEN seams as the
##     pure executor reads them, "rooms": [PackedStringArray] (every part in exactly one, members
##     sorted), "split": {id: {"origin": Vector3, "normal": Vector3}} (the manufacturing plane
##     the exploded view slices a module on), "open_seams": int, "pending_seams": int,
##     "hull_thickness_m": float }
## A cutter key is `_cutter_key(id, kind)` with kind one of CUT_BODY, CUT_ROOM, CUT_GROWN.
##
## THE PLAN IS PURE, THE EXECUTION IS NOT. Working out what each seam means for each part is a
## question about the document and belongs here in core; carrying the cuts out is a question about
## a boolean engine. This module carries them out with its own polygon clipping ([method _carve]),
## which is exact where surfaces are planar and approximate where they curve; the builder carries
## the same plan out with the engine's CSG nodes (ShipCsgBake), which is exact everywhere and is
## what the player sees. One plan, two executors, no second reading of the seams.
static func plan(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, segments: int = ShapeMesh.RADIAL_SEGMENTS
) -> Dictionary:
	if doc == null or data == null or cfg == null:
		return {}

	# Resolved ONCE and handed on, exactly as ShipSdf.build does it: shape generation is the
	# expensive half of a rebuild and resolve_all() would repeat it internally.
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)

	# THREE SURFACES PER PART (ADR 0015): the outer one, an interior one inset by the wall
	# thickness, and a set of GROWN copies that the interior's seams are cut against.
	var thickness: float = maxf(cfg.hull_thickness_m, 0.0)
	var outer: Dictionary = {}
	var inner: Dictionary = {}
	var grown: Dictionary = {}
	# Sorted, so the phase each part is tessellated at is a function of the DOCUMENT and not of
	# dictionary order (AGENTS section 8b).
	var ids: PackedStringArray = PackedStringArray()
	for id: Variant in xforms.keys():
		ids.append(str(id))
	ids.sort()
	for index: int in ids.size():
		var id: String = ids[index]
		var shape_v: Variant = shapes.get(id)
		var xform_v: Variant = xforms.get(id)
		if not (shape_v is ResolvedShape) or not (xform_v is Transform3D):
			continue
		var shape: ResolvedShape = shape_v
		var xform: Transform3D = xform_v
		# EACH PART AT ITS OWN PHASE, so no two lathes ever share a longitude plane. Two spheres on
		# one axis with one segment count do, and a boolean between them then meets coplanar
		# faces at every split. The golden ratio spreads the phases so that no two parts of any
		# count coincide; a part's outer and inner keep one phase, which is what makes them nest.
		var phase: float = fmod(float(index) * PHASE_STRIDE, 1.0)
		var local: PolyMesh = ShapeMesh.build(shape, segments, phase)
		if local.is_empty():
			continue
		outer[id] = local.transformed(xform)
		if thickness <= 0.0:
			continue
		var hollow: PolyMesh = ShapeMesh.build(ShapeMesh.inset(shape, thickness), segments, phase)
		if not hollow.is_empty():
			inner[id] = hollow.transformed(xform)
		var fat: PolyMesh = ShapeMesh.build(ShapeMesh.inset(shape, -thickness), segments, phase)
		grown[id] = fat.transformed(xform) if not fat.is_empty() else outer[id]

	# ONE CUTTER PER SURFACE PER PART: its body, its room (the interior), and its body grown by a
	# wall. A seam then names, for each of its two parts, which cutters take the part's outer and
	# inner surfaces.
	var cutters: Dictionary = {}
	var placed: PackedStringArray = PackedStringArray()
	for id: String in ids:
		if not outer.has(id):
			continue
		placed.append(id)
		var shape: ResolvedShape = shapes[id]
		var xform: Transform3D = xforms[id]
		cutters[_cutter_key(id, CUT_BODY)] = MeshClip.Cutter.of_shape(shape, xform, outer[id])
		if inner.has(id):
			cutters[_cutter_key(id, CUT_ROOM)] = MeshClip.Cutter.of_shape(
				ShapeMesh.inset(shape, thickness), xform, inner[id]
			)
		if grown.has(id):
			cutters[_cutter_key(id, CUT_GROWN)] = MeshClip.Cutter.of_shape(
				ShapeMesh.inset(shape, -thickness), xform, grown[id]
			)

	var seams: Array[Dictionary] = ShipSeams.seams(doc, shapes, xforms, cfg, data)
	var cuts: Dictionary = {}
	var open_cuts: Dictionary = {}
	var room_of: Dictionary = {}
	var bounded_seams: int = 0
	var open_seams: int = 0
	var door_entries: Array[Dictionary] = []
	for seam: Dictionary in seams:
		var child_id: String = str(seam.get(ShipSeams.SEAM_CHILD, ""))
		var host_id: String = str(seam.get(ShipSeams.SEAM_HOST, ""))
		if not outer.has(child_id) or not outer.has(host_id):
			continue
		var mode: String = str(seam.get(ShipSeams.SEAM_MODE, ShipSeams.MODE_WALL))
		var bounded: bool = mode == ShipSeams.MODE_DOORWAY or mode == ShipSeams.MODE_HATCHED
		if bounded:
			bounded_seams += 1
		var style: String = str(seam.get(ShipSeams.SEAM_STYLE, ShipSeams.STYLE_FLAT))
		var big_indents: bool = ShipJoint.indent_of(style) == ShipJoint.INDENT_BIG
		var child_is_big: bool = MeshFlange.first_is_larger(outer[child_id], outer[host_id])
		var big_id: String = child_id if child_is_big else host_id
		var small_id: String = host_id if child_is_big else child_id
		var indented: String = small_id if big_indents else big_id
		var indenter: String = big_id if big_indents else small_id
		if mode == ShipSeams.MODE_OPEN and inner.has(indented) and inner.has(indenter):
			# ONE ROOM. Two answers, for two executors. For the engine (ShipCsgBake): the pair are
			# members of one ROOM, and a room is built whole - the union of its members' bodies
			# less the union of their interiors - and then cut back into pieces along the members'
			# original bodies, so no member keeps any hull inside another's walls. "union all
			# proton chunks .. down sizing them slightly, unioning all those smaller chunks ..
			# subtracting .. then we re cut the single mesh using orignal data" (2026-09-05). For
			# the pure executor, which has no union: the per-part rule - the indented part loses
			# the indenter's body on both surfaces, the indenter loses the indented part's room.
			open_seams += 1
			_join_rooms(room_of, indented, indenter)
			_add_cut(
				open_cuts,
				indented,
				_cutter_key(indenter, CUT_BODY),
				_cutter_key(indenter, CUT_BODY)
			)
			_add_cut(
				open_cuts,
				indenter,
				_cutter_key(indented, CUT_ROOM),
				_cutter_key(indented, CUT_ROOM)
			)
		else:
			# A WALL. The indented part gets a socket the indenter's body punches through its
			# outer surface only; its inner surface retreats from the indenter's body GROWN by a
			# wall, so the wall follows the socket at its own thickness and the room stays sealed.
			# The indenter is untouched: its end sits in the socket. This is the native linkage
			# surface for every style for now - see FOLLOWUPS F32 for the flat ones.
			var deep: String = (
				_cutter_key(indenter, CUT_GROWN)
				if cutters.has(_cutter_key(indenter, CUT_GROWN))
				else _cutter_key(indenter, CUT_BODY)
			)
			_add_cut(cuts, indented, _cutter_key(indenter, CUT_BODY), deep)
			# A DOOR (ADR 0029): a bounded opening is a wall with a hole bored through both
			# sides of it, planned by ShipDoors on the two modules' fields once every socket is
			# known. Two modules without rooms have no cavities to open into.
			if bounded and inner.has(child_id) and inner.has(host_id):
				# Each field calibrated to the mesh the engine builds (F34): a tessellation
				# sits inside its field by a constant, and the doors go on the tessellation.
				(
					door_entries
					. append(
						{
							ShipDoors.ENTRY_SEAM: seam,
							ShipDoors.ENTRY_INDENTER: indenter,
							ShipDoors.ENTRY_CHILD_BODY:
							ShipDoors.field_of(
								cutters[_cutter_key(child_id, CUT_BODY)], outer[child_id]
							),
							ShipDoors.ENTRY_CHILD_ROOM:
							ShipDoors.field_of(
								cutters[_cutter_key(child_id, CUT_ROOM)], inner[child_id]
							),
							ShipDoors.ENTRY_HOST_BODY:
							ShipDoors.field_of(
								cutters[_cutter_key(host_id, CUT_BODY)], outer[host_id]
							),
							ShipDoors.ENTRY_HOST_ROOM:
							ShipDoors.field_of(
								cutters[_cutter_key(host_id, CUT_ROOM)], inner[host_id]
							),
						}
					)
				)

	var members: Dictionary = {}
	for id: String in placed:
		var room: String = _room_root(room_of, id) if room_of.has(id) else id
		var list: PackedStringArray = members.get(room, PackedStringArray())
		list.append(id)
		members[room] = list
	var rooms: Array = []
	var keys: PackedStringArray = PackedStringArray()
	for room: Variant in members.keys():
		keys.append(str(room))
	keys.sort()
	for room: String in keys:
		var list: PackedStringArray = members[room]
		list.sort()
		rooms.append(list)

	# THE SPLIT. "for any module .. need to get sliced down the middle in the explode group. (in
	# manufacturing they are made in 2 pieces)" (2026-09-05). The plane through the part's own
	# origin with its local Z as normal - so a tunnel or a hull comes apart lengthways, as a
	# clamshell, and never across its bore.
	var split: Dictionary = {}
	for id: String in placed:
		var xform: Transform3D = xforms[id]
		var normal: Vector3 = xform.basis.z
		if normal.length_squared() <= 1.0e-12:
			normal = Vector3.FORWARD
		split[id] = {"origin": xform.origin, "normal": normal.normalized()}

	# THE DOORS (ADR 0029): one record per bounded seam both of whose modules have a cavity -
	# its gasket plane, its collar halves, its clearing prisms and its bore, and the door leaves
	# a view builds from it. A seam nothing can be bored for is PENDING: reported, not hidden.
	var doors: Dictionary = ShipDoors.plan(door_entries, thickness, cfg.hatch_min_m, segments)
	var door_list: Array = doors["doors"]

	return {
		"ids": placed,
		"outer": outer,
		"inner": inner,
		"grown": grown,
		"cutters": cutters,
		"cuts": cuts,
		"open_cuts": open_cuts,
		"rooms": rooms,
		"split": split,
		"open_seams": open_seams,
		"pending_seams": bounded_seams - door_list.size(),
		"doors": door_list,
		"door_misfits": doors["misfits"],
		"hull_thickness_m": thickness,
	}


## Union-find over the open seams: [param a] and [param b] are in one room.
static func _join_rooms(room_of: Dictionary, a: String, b: String) -> void:
	var ra: String = _room_root(room_of, a)
	var rb: String = _room_root(room_of, b)
	if ra != rb:
		room_of[ra] = rb


static func _room_root(room_of: Dictionary, id: String) -> String:
	if not room_of.has(id):
		room_of[id] = id
	var walk: String = id
	var guard: int = 64
	while str(room_of[walk]) != walk and guard > 0:
		guard -= 1
		walk = room_of[walk]
	return walk


## The bake report over [param solids] carried out from [param plan] - the same shape whichever
## executor made them.
static func report(solids: Dictionary, plan: Dictionary, t0: int) -> Dictionary:
	var out: Dictionary = _empty(t0)
	var inner: Dictionary = plan.get("inner", {})
	var hollowed: int = 0
	for id: String in plan.get("ids", PackedStringArray()):
		if inner.has(id) and solids.has(id) and not (solids[id] as PolyMesh).is_empty():
			hollowed += 1
	var order: PackedStringArray = PackedStringArray()
	for id: Variant in solids.keys():
		order.append(id)
	# Sorted, because determinism is a gate in this project and a Dictionary is not ordered by
	# anything a caller can rely on (AGENTS section 8b).
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
	out["hull_thickness_m"] = float(plan.get("hull_thickness_m", 0.0))
	out["hollowed_parts"] = hollowed
	out["open_seams"] = int(plan.get("open_seams", 0))
	out["pending_seams"] = int(plan.get("pending_seams", 0))
	# The doors as planned (ADR 0029). Which pieces were actually bored is the executor's to
	# say: the engine fills `bored`; the pure executor keeps its walls (FOLLOWUPS F41).
	out["doors"] = plan.get("doors", [])
	out["door_misfits"] = plan.get("door_misfits", [])
	out["bored"] = PackedStringArray()
	out["absorbed"] = PackedStringArray()
	out["aabb"] = bounds
	out["open_parts"] = open_parts
	out["ms"] = Time.get_ticks_msec() - t0
	return out


## One name for one surface of one part, in [method plan].
static func _cutter_key(id: String, kind: String) -> String:
	return id + "\u0001" + kind


## Records that [param id]'s outer surface is cut by [param outer_cutter] and its inner surface by
## [param inner_cutter]. The two are the same cutter for an open seam and body-then-grown for a
## walled one, and [method _carve] reads the difference.
static func _add_cut(cuts: Dictionary, id: String, outer_key: String, inner_key: String) -> void:
	var list: Array = cuts.get(id, [])
	list.append({"outer": outer_key, "inner": inner_key})
	cuts[id] = list


## One part's finished piece: its two surfaces, each less what any cutter took, plus the faces the
## cutters left exposed, as one closed solid.
##
## THE PIECE IS A SET, AND ITS BOUNDARY IS READ OFF THAT SET. With O the outer cutters and I the
## inner ones (O_c inside I_c for every cut c):
##   body B     = inside(outer) and outside every O_c
##   cavity C   = inside(inner) and outside every I_c
##   piece      = B and not C
## so its boundary is (boundary of B, outside C) together with (boundary of C, inside B, turned
## inside out). Boundary of B is the outer surface outside every O_c, plus each O_c's own surface
## where it lies inside the outer and outside the other O's. Boundary of C is the inner surface
## outside every I_c, plus each I_c's own surface where it lies inside the inner and outside the
## other I's. Every term is a polygon list clipped by a distance function, and every clip commutes
## with every other, so the order the seams arrive in cannot change the piece.
##
## Orientation: the outer surface and the I-surfaces face out of the piece as built; the inner
## surface and the O-surfaces face into it and are turned round.
##
## Where two of these surfaces meet, each boundary was found by bisection on its own edges, and
## they agree only to the sagitta of a segment; the assembled piece is welded and its T-junctions
## repaired, and what is still open is reported by the caller rather than hidden.
static func _carve(
	outer: PolyMesh,
	inner: PolyMesh,
	own_body: MeshClip.Cutter,
	own_room: MeshClip.Cutter,
	cuts: Array
) -> PolyMesh:
	if cuts.is_empty():
		if inner == null or inner.is_empty():
			return outer
		return _nest(outer, inner)
	var hollow: bool = inner != null and not inner.is_empty() and own_room != null

	# Every surface that meets a cutter is gridded first, to the cell a lathe already has: see
	# MeshClip.subdivided for why a cutter inside one big face is otherwise invisible. Gridded ONCE,
	# and the same polygons serve both as the surface to clip and as the planes the other side's
	# crossings snap onto, so the two sides of every seam agree by construction.
	var cell: float = _cell_for(outer)
	var my_outer: Array = MeshClip.subdivided(outer.polygons(), cell)
	var my_inner: Array = []
	if hollow:
		my_inner = MeshClip.subdivided(inner.polygons(), cell)
	var outers: Array = []
	var inners: Array = []
	var o_polys: Array = []
	var i_polys: Array = []
	for cut: Dictionary in cuts:
		var o: MeshClip.Cutter = cut["outer"]
		var i: MeshClip.Cutter = cut["inner"]
		outers.append(o)
		inners.append(i)
		o_polys.append(
			(
				MeshClip.subdivided(o.surface.polygons(), _cell_for(o.surface))
				if o.surface != null
				else []
			)
		)
		i_polys.append(
			(
				MeshClip.subdivided(i.surface.polygons(), _cell_for(i.surface))
				if i.surface != null and i != o
				else o_polys[o_polys.size() - 1]
			)
		)

	# What each side snaps onto: my outer onto every O-surface, my inner onto every I-surface, an
	# O-surface onto my outer (and the other O's), an I-surface onto my inner (and the other I's).
	var all_o: Array = []
	var all_i: Array = []
	for c: int in cuts.size():
		all_o.append_array(o_polys[c])
		all_i.append_array(i_polys[c])
	var polys: Array = MeshClip.clip_all(
		my_outer, MeshClip.outside_all(outers), MeshClip.PlaneFinder.make(all_o)
	)
	if hollow:
		polys.append_array(
			MeshClip.flipped(
				MeshClip.clip_all(
					my_inner, MeshClip.outside_all(inners), MeshClip.PlaneFinder.make(all_i)
				)
			)
		)

	for c: int in cuts.size():
		var o: MeshClip.Cutter = cuts[c]["outer"]
		var i: MeshClip.Cutter = cuts[c]["inner"]
		var other_o: Array = []
		var other_i: Array = []
		var onto_o: Array = my_outer.duplicate()
		var onto_i: Array = my_inner.duplicate()
		for d: int in cuts.size():
			if d != c:
				other_o.append(cuts[d]["outer"])
				other_i.append(cuts[d]["inner"])
				onto_o.append_array(o_polys[d])
				onto_i.append_array(i_polys[d])
		# The O-surface: inside the outer, clear of the other O's, and not in the cavity - which
		# it is unless it is outside the inner or strictly inside some I.
		var not_in_cavity: Callable = MeshClip.everything()
		if hollow:
			not_in_cavity = MeshClip.either(
				func(p: Vector3) -> float: return own_room.distance(p), MeshClip.strictly_inside(i)
			)
			for d: int in cuts.size():
				not_in_cavity = MeshClip.either(
					not_in_cavity, MeshClip.strictly_inside(cuts[d]["inner"])
				)
			onto_o.append_array(my_inner)
		var keep_o: Callable = MeshClip.both(
			MeshClip.both(MeshClip.inside(own_body), MeshClip.outside_all(other_o)), not_in_cavity
		)
		polys.append_array(
			MeshClip.flipped(
				MeshClip.clip_all(o_polys[c], keep_o, MeshClip.PlaneFinder.make(onto_o))
			)
		)
		# The I-surface, only where it differs from the O: inside the inner, clear of the other I's.
		if hollow and i != o and i.surface != null:
			var keep_i: Callable = MeshClip.both(
				MeshClip.inside(own_room), MeshClip.outside_all(other_i)
			)
			polys.append_array(
				MeshClip.clip_all(i_polys[c], keep_i, MeshClip.PlaneFinder.make(onto_i))
			)
	if polys.is_empty():
		return PolyMesh.new()
	return MeshMerge.merge(PolyMesh.from_polygons(polys))


## The grid cell a surface is cut into before clipping: its longest extent over CLIP_CELLS, so a
## box face is gridded to about what a lathe's polygons already are, and a lathe is left alone.
static func _cell_for(mesh: PolyMesh) -> float:
	var size: Vector3 = mesh.aabb().size
	return maxf(maxf(size.x, maxf(size.y, size.z)) / float(CLIP_CELLS), 0.05)


## A shell: [param outer] and [param inner] as ONE closed solid with a cavity - the outer surface
## as it is and the inner surface turned inside out. Nothing is computed.
##
## THIS IS HOW A SHELL IS MADE, AND IT IS NOT A BOOLEAN. "if i had to make a shell... i would make
## a copy of the part, downsize or upsize slightly, then sub one from the other" (2026-09-05) - and
## the subtraction is the step that is not needed: the inner surface lies strictly inside the outer
## by construction, so the two surfaces together already bound exactly the solid the subtraction
## would produce. Blender's Solidify modifier is this operation.
##
## RETIRED(ADR 0019, 2026-09-05): `_cut(outer, inner)` through the BSP. On two concentric spheres of
## one tessellation it returned 742 open edges and the wrong volume, the guard refused it, and the
## module stayed SOLID - silently, on every sphere pod, for six rounds of "fixed".
static func _nest(outer: PolyMesh, inner: PolyMesh) -> PolyMesh:
	return PolyMesh.from_polygons(outer.polygons() + MeshClip.flipped(inner.polygons()))


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
		"open_seams": 0,
		"pending_seams": 0,
		"absorbed": PackedStringArray(),
		"ms": Time.get_ticks_msec() - t0,
	}
