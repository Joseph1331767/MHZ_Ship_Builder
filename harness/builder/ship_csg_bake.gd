class_name ShipCsgBake
extends RefCounted
## The exact bake, carried out by the engine's own CSG.
##
## "if i had to make a shell... i would make a copy of the part, downsize or upsize slightly, then
## sub one from the other.. so whats the big deal here? ... humanity has figured out shells
## already" (2026-09-05). It has, and it ships inside this engine: Godot's CSG nodes are backed by
## the Manifold library, an exact and robust mesh-boolean engine that handles coincident faces and
## concentric surfaces correctly. Measured on a helium sphere: the shell, a hole through it and a
## wall stopped at a neighbour's room, every one closed with zero open edges, all three in under
## 80 ms - where the BSP hand-built in core/ returned 742 open edges on the shell alone (ADR 0019)
## and its successor could not make two sides of a seam agree (ADR 0020).
##
## WHY THIS IS IN harness/ AND NOT core/. CSG nodes are [Node]s and need a scene tree; core/ is
## pure data by rule (AGENTS section 3). So the split is: [method ShipMeshBake.plan] in core/
## decides what every seam means for every part - which surfaces are cut by which, and which
## parts are one room - and this class carries that plan out with the engine. One plan, two
## executors; the player sees this one, and the pure one remains for anything that has no tree.
##
## A ROOM IS BUILT WHOLE AND CUT BACK INTO ITS PIECES (ADR 0021). "union all proton chunks = 1
## single solid mesh = exterior mesh, then make the interior mesh by taking all the original proton
## chunks, down sizing them slightly, unioning all those smaller chunks. then we make the shell by
## taking the big proton mesh and subtracting the small proton mass. then we re cut the single mesh
## using orignal data, such that each sub chunk shell is created by cutting the single mesh
## intersection with the orignal chunks." Exactly that, in two engine passes: the room's shell,
## then the shell intersected with each member's original body - each member also less the bodies
## of the members before it, so where two chunks overlap the shell there is counted once. A part
## on its own is a room of one, and its walled seams are cut into its two surfaces before either
## pass, so a socket survives into the room.
##
## EVERY OPENING IS CAPPED, COLLARED AND DOORED (ADR 0029). After the pieces, a third engine pass
## takes every hatched or doorway seam's plan from [ShipDoors]: each of the two pieces at the seam
## gains its half of the collar (the frame's outline extruded from the gasket plane into the
## module), loses whatever it had past that plane within the frame, and is bored through by the
## hole. A difference of closed solids is closed, so the hole's rim - the ring of wall between the
## exterior and the interior - is capped by the engine with no work of this file's own, and lands
## in the CUT surface. The door leaves themselves are not booleans; the view builds them from the
## same records ([method ShipDoors.leaves]).
##
## ONLY WHAT IS ON SCREEN (ADR 0030). [method bake] makes the assembled ship - the pieces with
## their doors - and reads each piece back once. [method bake_extras] makes what only the exploded
## view and ROOMS: WHOLE draw - every piece cut into its 64 fundamental cells (ADR 0032), every
## room of several as one bored shell and its cells - from that report, when first asked.
## Measured on a carbon of spheres: 58 read-backs a bake, of which 14 are the ship on screen, and
## the n-gon merge in each read-back was 7.6 s of the 19.
##
## ASYNCHRONOUS BY NECESSITY. A CSG node computes on a deferred call after it enters the tree, so
## [method bake] awaits frames between building nodes and reading meshes. Callers `await` it.

## The weld applied when the engine's triangles are read back into a [PolyMesh]. Manifold's
## output is exact to float; this is well above its noise and well below any feature.
const READ_WELD_M: float = 1.0e-5

## How many frames a pass will wait for the engine before reading what it has.
const READY_FRAMES: int = 12

## The report keys under which [method bake] keeps what [method bake_extras] needs, and which say
## the extras are in (ADR 0030).
const EXTRAS_INPUT: String = "extras_input"
const EXTRAS_READY: String = "extras_ready"

## The cuts every piece is made with, as fractions of its extent along each axis of its own frame
## (ADR 0032): the bisection's half and the trisection's thirds together - four slabs an axis, 64
## cells a piece - so any slicing the player picks is a grouping of cells that already exist.
const FINE_CUTS: Array = [1.0 / 3.0, 0.5, 2.0 / 3.0]

## A cell's wireframe keeps the edges where its surface turns by more than this - outlines, cuts,
## a box's corners, a lathe's rings - and drops the diagonals the engine triangulated flat and
## gently curved faces into (see [method _feature_wire]).
const WIRE_FEATURE_DEG: float = 10.0

## How far past a door's own bounds a face may stand and still be claimed as part of it, metres.
## The hardware is modelled tight to the hole; this is slack for the weld, nothing more.
const DOOR_CLAIM_M: float = 0.05

## Report keys: how many rooms of several were split at their seams (ADR 0036), and how many fell
## back to the older cut-back because the split did not come out sound.
const SPLIT_ROOMS: String = "split_rooms"
const CUT_BACK_ROOMS: String = "cut_back_rooms"

## A whole room's slicing job is keyed by its keeper under this prefix.
const ROOM_PREFIX: String = "room:"

## The named surfaces every drawn mesh carries - see [method _grouped].
const SURFACE_EXTERIOR: String = "exterior"
const SURFACE_INTERIOR: String = "interior"
const SURFACE_CUT: String = "cut"

## THE WALL A SEAM CLOSES (ADR 0046), its own surface so it can be taken off and the room read as
## the open space it would otherwise be. "walls should be isolated from the shape its actually
## apart of, such that when walls layer is removed you see an open room" (2026-09-25).
const SURFACE_WALL: String = "wall"

## A corner this close to a primitive's surface is ON it - see [method _grouped]. The wall is a
## hundred times this, and a tessellation's corners are on the surface to float precision.
const ON_SURFACE_M: float = 1.0e-3

## How many of a surface's own corners are read to find where it sits in its field.
const CALIBRATION_SAMPLES: int = 16

## A merged reading whose volume differs from the engine's triangles by more than this (of the
## volume) is thrown away for the triangles - see [method _read].
const READ_VOLUME_REL: float = 1.0e-3


## Bakes every placed part of [param doc] under [param host], which must be in the tree. Returns
## the same report as [method ShipMeshBake.bake], with each part's solid a closed [PolyMesh] of
## n-gons (the engine's triangles merged back into faces, so a box shows twelve lines and not
## eighteen). [param progress], when given, is called with (fraction, label) as each pass lands,
## so a bar can move while the engine works (ADR 0023).
##
## THE ASSEMBLED SHIP, AND NOTHING IT DOES NOT SHOW (ADR 0030): every piece with its doors, each
## read back ONCE, from the last combiner that touched it. The slices and the whole-room shells
## that only the exploded view and ROOMS: WHOLE draw are [method bake_extras], made from this
## report the first time they are asked for; what they need is kept under [constant EXTRAS_INPUT].
static func bake(
	host: Node, doc: ShipDoc, data: ShipData, cfg: ShipConfig, progress: Callable = Callable()
) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	_tick(progress, 0.02, "PLANNING")
	var plan: Dictionary = ShipMeshBake.plan(doc, data, cfg)
	_tick(progress, 0.12, "ROOM SHELLS")
	if plan.is_empty() or host == null or not host.is_inside_tree():
		return ShipMeshBake.report({}, plan, t0)
	var outer: Dictionary = plan["outer"]
	var inner: Dictionary = plan["inner"]
	var cutters: Dictionary = plan["cutters"]
	var cuts: Dictionary = plan["cuts"]

	# PASS ONE: every room's shell. A room of one is its own shell; a room of several is the union
	# of its members' bodies less the union of their interiors. Each member's walled cuts go into
	# its body and its interior first, so a tunnel's socket is in the room's shell.
	var stage: Node3D = Node3D.new()
	stage.name = "CsgBakeStage"
	host.add_child(stage)
	var shells: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var shell: CSGCombiner3D = CSGCombiner3D.new()
		var bodies: CSGCombiner3D = CSGCombiner3D.new()
		var rooms: CSGCombiner3D = CSGCombiner3D.new()
		var any_room: bool = false
		for id: String in members:
			bodies.add_child(_less_cuts(outer[id], cuts.get(id, []), cutters, "outer"))
			if inner.has(id):
				rooms.add_child(_less_cuts(inner[id], cuts.get(id, []), cutters, "inner"))
				any_room = true
		bodies.operation = CSGShape3D.OPERATION_UNION
		shell.add_child(bodies)
		if any_room:
			rooms.operation = CSGShape3D.OPERATION_SUBTRACTION
			shell.add_child(rooms)
		stage.add_child(shell)
		shells[members[0]] = shell
	await _until_ready(host, shells.values())
	_tick(progress, 0.3, "PIECES")

	# PASS TWO: the room is finished as ONE BODY and only then broken into its pieces (ADR 0036).
	# Every hatch of the room is bored while it is whole, and the shell is then SPLIT AT ITS SEAMS -
	# each piece its own faces of it, capped from its inner seam loop to its outer one. This is the
	# order every CAD pipeline uses and the author named it: "union all primatave shapes together,
	# then cut them along the shape of interior seam to exterior seam", and cut the openings before
	# separating, not after. Mesh surgery, not a boolean: the seam loops are already vertices of the
	# shell, because that is what an exact union puts there.
	#
	# RETIRED(ADR 0036) where the split holds: the piece as "the shell within the member's own body,
	# less the bodies of the members before it" (ADR 0021) and, for a pair of equals, less a PLANE
	# between them (ADR 0035). A solid cutter is a priority order - the first member keeps
	# everything, the last is bitten by all of them - and a plane divides two bodies correctly only
	# where they mirror across it. Neither follows the seam.
	#
	# A ROOM THE SPLIT CANNOT DIVIDE SOUNDLY FALLS BACK to that older cut-back, whole. The two
	# constructions disagree about who owns the wall at a seam and are not meant to agree, so a room
	# takes one or the other. Measured: a carbon of BOXES splits - six pieces of one size, summing
	# exactly to the room, every one of them closed and every edge shared by two faces - and a
	# carbon of SPHERES does not yet, and keeps the pieces it has always had.
	var pieces: Dictionary = {}
	var pre_bored: Dictionary = {}
	var cut_back: Array = []
	var split_rooms: int = 0
	for members: PackedStringArray in plan["rooms"]:
		if members.size() == 1:
			continue
		var work: Dictionary = {"union": [], "cut": []}
		var claims: Array = []
		var holed_ids: Dictionary = {}
		for door: Dictionary in plan.get("doors", []):
			for side: String in ShipDoors.SIDES:
				var id: String = str(door[side])
				if not members.has(id):
					continue
				var collar: PolyMesh = door[ShipDoors.DOOR_COLLAR][side]
				var clear: PolyMesh = door[ShipDoors.DOOR_CLEAR][side]
				var bore: PolyMesh = door[ShipDoors.DOOR_BORE]
				(work["union"] as Array).append(collar)
				(work["cut"] as Array).append(clear)
				(work["cut"] as Array).append(bore)
				# WHOSE THESE FACES ARE. A collar and a bore lie on no field of the member's own,
				# so the split would hand them to whichever member was nearest and scatter islands
				# through the wrong patches; a door names its two modules, and this is that, said
				# in the only terms a mesh can be recognised by - where it stands.
				var bounds: AABB = collar.aabb().merge(clear.aabb()).merge(bore.aabb())
				claims.append({"id": id, "bounds": bounds.grow(DOOR_CLAIM_M)})
				holed_ids[id] = true
		var source: Mesh = _engine_mesh(shells[members[0]])
		if not (work["union"] as Array).is_empty() or not (work["cut"] as Array).is_empty():
			var holed: CSGCombiner3D = _with_doors(stage, source, outer[members[0]], work)
			await _until_ready(host, [holed])
			source = _engine_mesh(holed)
		var shell_mesh: PolyMesh = _read_raw(source)
		if shell_mesh.is_empty():
			cut_back.append(members)
			continue
		var body_fields: Dictionary = {}
		var room_fields: Dictionary = {}
		for id: String in members:
			body_fields[id] = _member_fields(plan, id, ShipMeshBake.CUT_BODY, outer)
			room_fields[id] = _member_fields(plan, id, ShipMeshBake.CUT_ROOM, inner)
		var split: Dictionary = MeshSeamSplit.split(
			shell_mesh, members, body_fields, room_fields, claims
		)
		var sound: bool = true
		for id: String in members:
			var piece: Variant = split.get(id, null)
			if not (piece is PolyMesh) or not MeshSeamSplit.is_sound(piece as PolyMesh):
				sound = false
				break
		if not sound:
			cut_back.append(members)
			continue
		split_rooms += 1
		for id: String in members:
			# Back into CAD shape: the split works on the engine's triangles, and a piece of a box
			# should read as six faces and a chamfer, not as the fragments of one.
			pieces[id] = _tidy(split[id] as PolyMesh)
			if holed_ids.has(id):
				pre_bored[id] = true

	# THE OLD CUT-BACK, for a room the split could not divide soundly.
	var carved: Dictionary = {}
	for members: PackedStringArray in cut_back:
		var engine_shell: Mesh = _engine_mesh(shells[members[0]])
		for i: int in members.size():
			var id: String = members[i]
			var piece: CSGCombiner3D = CSGCombiner3D.new()
			_add_engine_mesh(piece, engine_shell, CSGShape3D.OPERATION_UNION)
			_add_mesh(piece, outer[id], CSGShape3D.OPERATION_INTERSECTION)
			for j: int in i:
				_add_mesh(piece, outer[members[j]], CSGShape3D.OPERATION_SUBTRACTION)
			stage.add_child(piece)
			carved[id] = piece
	if not carved.is_empty():
		await _until_ready(host, carved.values())

	# Where every piece stands: its own mesh from the split, its own combiner from the cut-back, or
	# - for a room of one - the room's shell as the engine made it.
	var made: Dictionary = {}
	var cut_solid: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		for id: String in members:
			if pieces.has(id):
				cut_solid[id] = pieces[id]
				made[id] = (pieces[id] as PolyMesh).to_array_mesh()
			elif carved.has(id):
				made[id] = _engine_mesh(carved[id])
			else:
				made[id] = _engine_mesh(shells[members[0]])

	# PASS TWO AND A HALF: THE DOORS (ADR 0029). Every bounded seam's opening, on both of its
	# pieces at once - a piece with several doors takes them all in one combiner. A piece the
	# engine returned empty is bored as its own plain body, which is what it is drawn as.
	var bored: Dictionary = {}
	var doors: Array = plan.get("doors", [])
	if not doors.is_empty():
		_tick(progress, 0.5, "DOORS")
		var work: Dictionary = _door_work(doors, made)
		var ids: Array = work.keys()
		ids.sort()
		for id: String in ids:
			# A piece that was split off a room already carries its hatches: they were bored while
			# the room was one body, which is the whole point of the order (ADR 0036).
			if pre_bored.has(id):
				continue
			bored[id] = _with_doors(stage, made[id] as Mesh, outer[id], work[id])
		await _until_ready(host, bored.values())
	_tick(progress, 0.75, "READING")

	# THE READ-BACK, once per piece. A boring the engine rejected leaves the piece its wall, and the
	# report says so; a piece the engine returned empty is kept as its own plain body rather than
	# lost from the screen, and the volume says so.
	var solids: Dictionary = {}
	var engine: Dictionary = {}
	var bored_ids: PackedStringArray = PackedStringArray()
	var door_failed: PackedStringArray = PackedStringArray()
	var bored_keys: Array = bored.keys()
	bored_keys.sort()
	for id: String in bored_keys:
		var solid: PolyMesh = _read_combiner(bored[id])
		if solid.is_empty():
			door_failed.append(id)
			continue
		solids[id] = solid
		engine[id] = _engine_mesh(bored[id])
		bored_ids.append(id)
	var room_engine: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		if members.size() > 1:
			room_engine[members[0]] = _engine_mesh(shells[members[0]])
		for id: String in members:
			if solids.has(id):
				continue
			# A piece the split made is already exact and needs no second reading.
			var solid: PolyMesh = cut_solid.get(id, null)
			if solid == null:
				solid = _read_combiner(carved[id] if carved.has(id) else shells[members[0]])
			solids[id] = solid if not solid.is_empty() else outer[id]
			engine[id] = made[id]
	# The engine's meshes are Resources and outlive the nodes that made them: the extras operate
	# on them later, after this stage is gone.
	stage.queue_free()
	_tick(progress, 0.9, "SURFACES")

	var report: Dictionary = ShipMeshBake.report(solids, plan, t0)
	# WHICH CONSTRUCTION EACH ROOM GOT (ADR 0036): split at its seams, or cut back the older way
	# because the split did not come out sound. A room that falls back is not an error and not a
	# silent one either - its pieces look different, and this is how anyone can tell which.
	report[SPLIT_ROOMS] = split_rooms
	report[CUT_BACK_ROOMS] = cut_back.size()
	# Every mesh the view draws carries its faces in three NAMED surfaces - exterior, interior,
	# cut - so the INTERIOR display mode can treat them apart (PolyMesh.to_array_mesh_grouped).
	var meshes: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		for id: String in members:
			meshes[id] = _grouped(
				solids[id], members, cutters, outer, inner, plan["cuts"], plan["grown"]
			)
	report["meshes"] = meshes
	report["split"] = plan["split"]
	report["rooms"] = plan["rooms"]
	# A PIECE CARRIES ITS HATCHES EITHER WAY (ADR 0036): bored on its own, or bored while its room
	# was still one body and then split off it. Both belong here - the caller is asking which pieces
	# have their openings, not which pass made them.
	for id: String in pre_bored:
		if not bored_ids.has(id) and solids.has(id):
			bored_ids.append(id)
	bored_ids.sort()
	report["bored"] = bored_ids
	report["door_failed"] = door_failed
	report[EXTRAS_READY] = false
	report[EXTRAS_INPUT] = {"plan": plan, "engine": engine, "room_engine": room_engine}
	return report


## The exploded view's extras for a report [method bake] made (ADR 0030/0032): every room of
## several as one whole shell, its own doors bored, and every piece and whole room cut into its 64
## FUNDAMENTAL CELLS - four slabs along each axis of its own frame (plan "frames"), at the cuts of
## [constant FINE_CUTS]. The cells do not depend on any setting: bisecting, trisecting or leaving an
## axis whole is a grouping of cells that already exist, so no player setting ever re-bakes.
## "the ship should exist as all of those separate tiny mesh pieces.. so animating them apart or
## together, or changing a setting is simply relocating the positions of those fundamental pieces"
## (2026-09-21). Returns a COPY of [param bake] with `cells` and `room_cells` (id -> `[{"cell":
## Vector3i, "solid": PolyMesh, "mesh": ArrayMesh, "wire": ArrayMesh}]`), `frames`, `room_shells`
## and `room_meshes` in and [constant EXTRAS_READY] set; [param bake] itself is not touched. A
## report that never reached the engine comes back marked ready with nothing added, so a caller
## asks once.
static func bake_extras(
	host: Node, bake: Dictionary, progress: Callable = Callable()
) -> Dictionary:
	var out: Dictionary = bake.duplicate()
	out[EXTRAS_READY] = true
	var input: Dictionary = bake.get(EXTRAS_INPUT, {})
	if input.is_empty() or host == null or not host.is_inside_tree():
		return out
	var plan: Dictionary = input["plan"]
	var engine: Dictionary = input["engine"]
	var room_engine: Dictionary = input["room_engine"]
	var solids: Dictionary = bake.get("solids", {})
	var outer: Dictionary = plan["outer"]
	var inner: Dictionary = plan["inner"]
	var cutters: Dictionary = plan["cutters"]
	var cuts: Dictionary = plan["cuts"]
	var grown: Dictionary = plan["grown"]
	var frames: Dictionary = plan.get("frames", {})
	var stage: Node3D = Node3D.new()
	stage.name = "CsgExtrasStage"
	host.add_child(stage)

	# THE WHOLE ROOMS: a room of several shown as one shell for ROOMS: WHOLE, bored with every
	# door any of its members opens (ADR 0029), from the room's shell as the engine made it.
	_tick(progress, 0.05, "WHOLE ROOMS")
	var work: Dictionary = _door_work(plan.get("doors", []), solids)
	var bored_rooms: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		if members.size() < 2:
			continue
		var keeper: String = members[0]
		var room_mesh: Mesh = room_engine.get(keeper, null)
		if room_mesh == null:
			continue
		var all: Dictionary = {"union": [], "cut": []}
		for id: String in members:
			if work.has(id):
				(all["union"] as Array).append_array(work[id]["union"])
				(all["cut"] as Array).append_array(work[id]["cut"])
		if (all["cut"] as Array).is_empty():
			continue
		bored_rooms[keeper] = _with_doors(stage, room_mesh, PolyMesh.new(), all)
	if not bored_rooms.is_empty():
		await _until_ready(host, bored_rooms.values())
	var room_shells: Dictionary = {}
	var room_source: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		if members.size() < 2:
			continue
		var keeper: String = members[0]
		var room_mesh: Mesh = null
		var whole: PolyMesh = PolyMesh.new()
		if bored_rooms.has(keeper):
			room_mesh = _engine_mesh(bored_rooms[keeper])
			whole = _read_combiner(bored_rooms[keeper])
		if whole.is_empty():
			room_mesh = room_engine.get(keeper, null)
			whole = _read(room_mesh)
		if not whole.is_empty():
			room_shells[keeper] = whole
			room_source[keeper] = room_mesh

	# THE CELLS: EVERY PIECE IN ITS OWN AXES, ACROSS ITS OWN EXTENT (ADR 0041), which is what the
	# slicer panel has always said it does. A chunk is cut square to its own faces, so its cells are
	# its own shape divided evenly, and the separation pulls them apart along the axes the chunk is
	# built on. A room shown WHOLE is one body and keeps one grid: the keeper's frame across every
	# member's extent.
	#
	# RETIRED(ADR 0041): "A ROOM IS CUT AS ONE BODY (ADR 0033). Its chunks are one mass that happens
	# to be several pieces, so they take the KEEPER's frame across the whole room's extent - one grid
	# of planes through all of them - rather than each its own, whose axes fan out from an off-centre
	# root and left the cuts of neighbouring chunks visibly out of line." The author looked at it
	# again with the split working: "the splitting/dicing system is using global world space
	# alignemnt, id rather use local node alignment" (2026-09-24). One grid through a room cuts every
	# chunk diagonally unless the keeper happens to stand square to it, and it sized the grid to the
	# ROOM, so a chunk occupied a corner of it and diced into slivers on one side and nothing on the
	# other.
	var jobs: Dictionary = {}
	var cell_frames: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var keeper: String = members[0]
		var bodies: Array = []
		for id: String in members:
			bodies.append(outer[id])
		if room_shells.has(keeper):
			jobs[ROOM_PREFIX + keeper] = _slice_job(
				room_source[keeper], room_shells[keeper], frames[keeper], bodies
			)
		for id: String in members:
			cell_frames[id] = frames[id]
			jobs[id] = _slice_job(engine.get(id, null), solids[id], frames[id], [outer[id]])
	var cut: Dictionary = await _slice(stage, host, jobs, progress)
	stage.queue_free()
	_tick(progress, 0.8, "SURFACES")

	var cells: Dictionary = {}
	var room_cells: Dictionary = {}
	var room_meshes: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var keys: Array = members.duplicate()
		var keeper: String = members[0]
		if room_shells.has(keeper):
			room_meshes[keeper] = _grouped(
				room_shells[keeper], members, cutters, outer, inner, cuts, grown
			)
			keys.append(ROOM_PREFIX + keeper)
		for key: String in keys:
			var list: Array = []
			for leaf: Dictionary in cut.get(key, []):
				var solid: PolyMesh = leaf["solid"]
				(
					list
					. append(
						{
							"cell": leaf["cell"],
							"solid": solid,
							"mesh": _grouped(solid, members, cutters, outer, inner, cuts, grown),
							"wire": _feature_wire(solid),
						}
					)
				)
			if key.begins_with(ROOM_PREFIX):
				room_cells[key.trim_prefix(ROOM_PREFIX)] = list
			else:
				cells[key] = list
	out["frames"] = frames
	# The frame each piece's cells were CUT in - its own, or its room's (ADR 0033). What the view
	# pulls a cell along; `frames` stays the per-part frame the plan made.
	out["cell_frames"] = cell_frames
	out["cells"] = cells
	out["room_shells"] = room_shells
	out["room_meshes"] = room_meshes
	out["room_cells"] = room_cells
	return out


## One slicing job: the solid (as the engine made it, or [param fallback] when it has none), the
## frame it is cut in, and its extent in that frame read off [param bodies] - the ORIGINAL bodies,
## so a cut does not move when a neighbour changes what was carved off this piece.
## What a member of a room gives up to an equal neighbour (ADR 0035): ONE box, standing on the
## plane through [param at] with [param normal] and covering [param shared] - the box the two
## bodies have in common - on the far side of it. The member keeps the side the normal points
## away from. Null when the two share nothing beyond the plane.
##
## CONFINED TO WHAT THEY SHARE, NOT A BARE HALF-SPACE. A plane is infinite and a body is not: where
## two bodies meet at anything but a right angle the plane runs on past the one it is dividing from
## and takes a corner of the member with it, which is material no neighbour ever stood in. "when a
## cube collides non-orthognally it doesnt bite and seam along all geodesics, its just a flat cut
## and leaves cornerns and stuff cut out and unresolved" (2026-09-22) - measured on a boron class,
## whose three equatorial bodies sit 120 degrees apart: the plane reached 0.39 m into each body over
## its whole height.
##
## THE BOUND IS A BOX, NOT THE NEIGHBOUR ITSELF. Clipping to the neighbour's own solid is the exact
## answer and cannot be used: that surface IS the room shell's surface there, and a cutter standing
## on the surface it cuts is the coincidence a boolean engine will not resolve - measured, a sphere
## nucleus came back with an open piece and with cells that would not close. The two bodies' common
## box is a plain axis-aligned box, which coincides with nothing, and it is as tight a bound as the
## pair's own reach.
static func _beyond(at: Vector3, normal: Vector3, shared: AABB) -> CSGBox3D:
	var axis: Vector3 = normal
	if axis.length_squared() <= 1.0e-12:
		axis = Vector3.BACK
	axis = axis.normalized()
	var frame: Basis = ShipAttach.mount_frame(axis)
	var inv: Basis = frame.inverse()
	var low: Vector3 = Vector3.ZERO
	var high: Vector3 = Vector3.ZERO
	for i: int in 8:
		var corner: Vector3 = inv * (shared.get_endpoint(i) - at)
		low = (
			corner
			if i == 0
			else Vector3(minf(low.x, corner.x), minf(low.y, corner.y), minf(low.z, corner.z))
		)
		high = (
			corner
			if i == 0
			else Vector3(maxf(high.x, corner.x), maxf(high.y, corner.y), maxf(high.z, corner.z))
		)
	if high.z <= 0.0:
		return null
	var out: CSGBox3D = CSGBox3D.new()
	out.operation = CSGShape3D.OPERATION_SUBTRACTION
	out.size = Vector3(maxf(high.x - low.x, 0.001), maxf(high.y - low.y, 0.001), high.z)
	var centre: Vector3 = Vector3((low.x + high.x) * 0.5, (low.y + high.y) * 0.5, high.z * 0.5)
	out.transform = Transform3D(frame, at + frame * centre)
	return out


static func _slice_job(
	source: Mesh, fallback: PolyMesh, frame: Transform3D, bodies: Array
) -> Dictionary:
	var inv: Transform3D = frame.affine_inverse()
	var lo: Vector3 = Vector3.INF
	var hi: Vector3 = -Vector3.INF
	for body: PolyMesh in bodies:
		for v: Vector3 in body.vertices:
			var p: Vector3 = inv * v
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x > hi.x:
		lo = Vector3.ZERO
		hi = Vector3.ZERO
	return {"source": source, "fallback": fallback, "frame": frame, "lo": lo, "hi": hi}


## Every job of [param jobs] cut into its cells, one axis at a time: the X slabs of the whole
## solid, then the Y slabs of each X slab, then Z - so each engine pass works on the pieces of the
## last rather than all of every piece, and nothing is read back until the leaves.
## Returns key -> `[{"cell": Vector3i, "solid": PolyMesh}]`, empty cells left out.
static func _slice(
	stage: Node, host: Node, jobs: Dictionary, progress: Callable = Callable()
) -> Dictionary:
	var entries: Dictionary = {}
	for key: String in jobs:
		var job: Dictionary = jobs[key]
		entries[key] = [
			{
				"cell": Vector3i.ZERO,
				"mesh": job["source"],
				"fallback": job["fallback"],
				"made": null
			}
		]
	for axis: int in 3:
		_tick(progress, 0.1 + 0.2 * float(axis), "SLICING %s" % ["X", "Y", "Z"][axis])
		var made: Array = []
		for key: String in jobs:
			var next: Array = []
			for entry: Dictionary in entries[key]:
				for slab: int in FINE_CUTS.size() + 1:
					var combiner: CSGCombiner3D = _slab(stage, entry, jobs[key], axis, slab)
					var cell: Vector3i = entry["cell"]
					cell[axis] = slab
					next.append({"cell": cell, "mesh": null, "fallback": null, "made": combiner})
					made.append(combiner)
			entries[key] = next
		await _until_ready(host, made)
		for key: String in jobs:
			var kept: Array = []
			for entry: Dictionary in entries[key]:
				var mesh: Mesh = _engine_mesh(entry["made"])
				if mesh == null or mesh.get_surface_count() == 0:
					continue
				entry["mesh"] = mesh
				kept.append(entry)
			entries[key] = kept
	_tick(progress, 0.7, "READING CELLS")
	var out: Dictionary = {}
	for key: String in jobs:
		var leaves: Array = []
		for entry: Dictionary in entries[key]:
			var solid: PolyMesh = _read_cell(entry["mesh"])
			if not solid.is_empty():
				leaves.append({"cell": entry["cell"], "solid": solid})
		out[key] = leaves
	return out


## One cell of a slicing pass under [param stage]: [param entry]'s solid intersected with slab
## [param slab] along [param axis] of the job's frame, between the cuts of FINE_CUTS. The outer
## slabs run out past the extent.
static func _slab(
	stage: Node, entry: Dictionary, job: Dictionary, axis: int, slab: int
) -> CSGCombiner3D:
	var combiner: CSGCombiner3D = CSGCombiner3D.new()
	var mesh: Mesh = entry["mesh"]
	if mesh != null and mesh.get_surface_count() > 0:
		_add_engine_mesh(combiner, mesh, CSGShape3D.OPERATION_UNION)
	else:
		_add_mesh(combiner, entry["fallback"], CSGShape3D.OPERATION_UNION)
	var lo: Vector3 = job["lo"]
	var hi: Vector3 = job["hi"]
	var reach: float = (hi - lo).length() + 1.0
	var length: float = hi[axis] - lo[axis]
	var last: int = FINE_CUTS.size()
	var a: float = lo[axis] - reach if slab == 0 else lo[axis] + length * float(FINE_CUTS[slab - 1])
	var b: float = hi[axis] + reach if slab == last else lo[axis] + length * float(FINE_CUTS[slab])
	var center: Vector3 = (lo + hi) * 0.5
	center[axis] = (a + b) * 0.5
	var size: Vector3 = (hi - lo) + Vector3.ONE * (2.0 * reach)
	size[axis] = b - a
	var box: CSGBox3D = CSGBox3D.new()
	box.size = size
	box.operation = CSGShape3D.OPERATION_INTERSECTION
	var frame: Transform3D = job["frame"]
	box.transform = Transform3D(frame.basis, frame * center)
	combiner.add_child(box)
	stage.add_child(combiner)
	return combiner


## A cell's triangles as a [PolyMesh], welded and NOT merged back into n-gons. Measured on a carbon
## of spheres: the merge was 30.7 s of a 38 s fine-grid bake over 713 cells, and it bought only a
## tidier wireframe, which [method _feature_wire] gives for a fraction of that.
static func _read_cell(mesh: Mesh) -> PolyMesh:
	if mesh == null:
		return PolyMesh.new()
	var polys: Array = []
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var index: PackedInt32Array = index_v if index_v is PackedInt32Array else PackedInt32Array()
		# Turned round on the way in, for the reason [method _read_raw] gives at length.
		if index.is_empty():
			for i: int in range(0, verts.size() - 2, 3):
				polys.append(PackedVector3Array([verts[i + 2], verts[i + 1], verts[i]]))
		else:
			for i: int in range(0, index.size() - 2, 3):
				polys.append(
					PackedVector3Array([verts[index[i + 2]], verts[index[i + 1]], verts[index[i]]])
				)
	return PolyMesh.from_polygons(polys, READ_WELD_M) if not polys.is_empty() else PolyMesh.new()


## [param solid]'s wireframe as lines: every edge where the two faces beside it turn by more than
## WIRE_FEATURE_DEG, and any edge with only one face.
static func _feature_wire(solid: PolyMesh) -> ArrayMesh:
	var limit: float = cos(deg_to_rad(WIRE_FEATURE_DEG))
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(solid.face_count())
	for f: int in solid.face_count():
		normals[f] = solid.face_plane(f).normal
	var first: Dictionary = {}
	var lines: PackedVector3Array = PackedVector3Array()
	for f: int in solid.face_count():
		var loop: PackedInt32Array = solid.faces[f]
		for k: int in loop.size():
			var a: int = loop[k]
			var b: int = loop[(k + 1) % loop.size()]
			var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
			if not first.has(key):
				first[key] = f
				continue
			var g: int = first[key]
			first.erase(key)
			if normals[f].dot(normals[g]) < limit:
				lines.append(solid.vertices[a])
				lines.append(solid.vertices[b])
	for key: Vector2i in first:
		lines.append(solid.vertices[key.x])
		lines.append(solid.vertices[key.y])
	var mesh: ArrayMesh = ArrayMesh.new()
	if lines.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


## What every piece takes at its doors (ADR 0029): id -> `{"union": [PolyMesh], "cut":
## [PolyMesh]}` - its collar halves to add, then its clearing prisms and the bores to subtract.
## Only pieces [param made] holds (id -> anything) are listed.
static func _door_work(doors: Array, made: Dictionary) -> Dictionary:
	var work: Dictionary = {}
	for door: Dictionary in doors:
		for side: String in ShipDoors.SIDES:
			var id: String = str(door[side])
			if not made.has(id):
				continue
			var entry: Dictionary = work.get(id, {"union": [], "cut": []})
			(entry["union"] as Array).append(door[ShipDoors.DOOR_COLLAR][side])
			(entry["cut"] as Array).append(door[ShipDoors.DOOR_CLEAR][side])
			(entry["cut"] as Array).append(door[ShipDoors.DOOR_BORE])
			work[id] = entry
	return work


## One combiner under [param stage]: [param source] (the engine's own mesh of the solid, or
## [param fallback] when it has none) plus every solid of [param work]'s "union", less every
## solid of its "cut", in that order - the collar goes on before the bore comes out.
static func _with_doors(
	stage: Node, source: Mesh, fallback: PolyMesh, work: Dictionary
) -> CSGCombiner3D:
	var out: CSGCombiner3D = CSGCombiner3D.new()
	if source != null and source.get_surface_count() > 0:
		_add_engine_mesh(out, source, CSGShape3D.OPERATION_UNION)
	else:
		_add_mesh(out, fallback, CSGShape3D.OPERATION_UNION)
	for mesh: PolyMesh in work["union"]:
		_add_mesh(out, mesh, CSGShape3D.OPERATION_UNION)
	for mesh: PolyMesh in work["cut"]:
		_add_mesh(out, mesh, CSGShape3D.OPERATION_SUBTRACTION)
	stage.add_child(out)
	return out


## [param solid] as an ArrayMesh with its faces in three named surfaces: EXTERIOR where every
## corner of the face lies on a member's body surface, INTERIOR where every corner lies on a
## member's room surface, and CUT for everything else - the sockets, the holes' rims, the split.
##
## BY VERTICES AGAINST THE DISTANCE FIELDS, NOT BY PLANES. A lathe's quads are not planar, so the
## "plane" of one depends on which three corners are used, and the engine re-triangulates them
## its own way: measured on one hydrogen sphere, the input quads reported d = 12.63 and the baked
## faces d = 12.48 and 12.26, and not one exterior face matched. A tessellation's corners are what
## the engine keeps, so they are what is tested.
##
## CALIBRATED, NOT ASSUMED ON THE FIELD'S ZERO. A box's tessellation is the fillet's CORE - its
## half-extent less `round_r` - while its field is the full rounded envelope, so every corner,
## edge and face centre of a box reads the same constant below zero: measured, -0.200 m on a
## carbon box, and 0 on a sphere. Each surface's offset is read off its own tessellation first
## and the test is made relative to it. (That the box mesh sits inside its own field by the fillet
## is recorded in FOLLOWUPS F34.)
static func _grouped(
	solid: PolyMesh,
	members: PackedStringArray,
	cutters: Dictionary,
	outer: Dictionary,
	inner: Dictionary,
	cuts: Dictionary = {},
	grown: Dictionary = {}
) -> ArrayMesh:
	var bodies: Array = []
	var rooms: Array = []
	# THE WALLS THIS PIECE CARRIES. A walled seam authors no plate: the two cavities simply do not
	# merge, and the INDENTED part's cavity is cut back by the neighbour's GROWN body (see
	# ShipMeshBake's walled branch). So the face standing where the neighbour pushed in - the floor
	# of that socket - IS the wall, and it is found by asking the same grown field that made it.
	var walls: Array = []
	for id: String in members:
		for cut: Variant in cuts.get(id, []) as Array:
			var key: String = str((cut as Dictionary).get("inner", ""))
			if not cutters.has(key):
				continue
			var owner_id: String = _owner_of_cutter(key, grown)
			if owner_id.is_empty():
				continue
			walls.append([cutters[key], _offset_of(cutters[key], grown[owner_id])])
	for id: String in members:
		var body_key: String = ShipMeshBake._cutter_key(id, ShipMeshBake.CUT_BODY)
		var room_key: String = ShipMeshBake._cutter_key(id, ShipMeshBake.CUT_ROOM)
		if cutters.has(body_key) and outer.has(id):
			bodies.append([cutters[body_key], _offset_of(cutters[body_key], outer[id])])
		if cutters.has(room_key) and inner.has(id):
			rooms.append([cutters[room_key], _offset_of(cutters[room_key], inner[id])])
	var groups: PackedInt32Array = PackedInt32Array()
	groups.resize(solid.face_count())
	for i: int in solid.face_count():
		var on_body: bool = true
		var on_room: bool = true
		var on_wall: bool = not walls.is_empty()
		for id: int in solid.faces[i]:
			var v: Vector3 = solid.vertices[id]
			if on_body and not _on_any(v, bodies):
				on_body = false
			if on_room and not _on_any(v, rooms):
				on_room = false
			if on_wall and not _on_any(v, walls):
				on_wall = false
			if not on_body and not on_room and not on_wall:
				break
		# THE WALL IS ASKED FIRST, because it is also a cavity face: it bounds the room, so the
		# cavity field owns it too, and asking the cavity first would swallow every wall there is.
		if on_wall:
			groups[i] = 3
		elif on_body:
			groups[i] = 0
		elif on_room:
			groups[i] = 1
		else:
			groups[i] = 2
	return solid.to_array_mesh_grouped(
		groups, PackedStringArray([SURFACE_EXTERIOR, SURFACE_INTERIOR, SURFACE_CUT, SURFACE_WALL])
	)


## Which part a cutter key belongs to, when [param grown] has a surface for it.
##
## [method ShipMeshBake._cutter_key] joins the id and the kind with U+0001 - a character no part id
## can hold - so the owner is simply everything before it. Guessing at the separator is how this
## first read zero walls on a ship that has plenty.
static func _owner_of_cutter(key: String, grown: Dictionary) -> String:
	var at: int = key.find("")
	if at <= 0:
		return ""
	var id: String = key.substr(0, at)
	return id if grown.has(id) else ""


## Where [param surface]'s own corners sit in [param field]: the median of a spread of them.
static func _offset_of(field: MeshClip.Cutter, surface: PolyMesh) -> float:
	var count: int = surface.vertices.size()
	if count == 0:
		return 0.0
	var samples: PackedFloat64Array = PackedFloat64Array()
	@warning_ignore("integer_division")
	var step: int = maxi(count / CALIBRATION_SAMPLES, 1)
	var i: int = 0
	while i < count:
		samples.append(field.distance(surface.vertices[i]))
		i += step
	samples.sort()
	@warning_ignore("integer_division")
	var middle: int = samples.size() / 2
	return samples[middle]


## Is [param v] on the surface of any of [param fields] - each `[cutter, offset]` - to
## ON_SURFACE_M?
static func _on_any(v: Vector3, fields: Array) -> bool:
	for pair: Array in fields:
		var cutter: MeshClip.Cutter = pair[0]
		if absf(cutter.distance(v) - float(pair[1])) <= ON_SURFACE_M:
			return true
	return false


## [param surface] less every cutter of [param cuts] on its [param side] ("outer" or "inner"), as
## one combiner.
## Every calibrated field one member's surface of [param kind] is made of: the member's own, and one
## per SOCKET cut into it. A socket's face lies on the cutter's surface and belongs to the member it
## was cut into - which is the only member it can belong to, since whatever cut it is a room of its
## own and not in this split at all.
static func _member_fields(
	plan: Dictionary, id: String, kind: String, surfaces: Dictionary
) -> Array:
	var cutters: Dictionary = plan["cutters"]
	var side: String = "outer" if kind == ShipMeshBake.CUT_BODY else "inner"
	var out: Array = []
	var key: String = ShipMeshBake._cutter_key(id, kind)
	if cutters.has(key) and surfaces.has(id):
		out.append(ShipDoors.field_of(cutters[key], surfaces[id]))
	for cut: Dictionary in (plan["cuts"] as Dictionary).get(id, []):
		if not cutters.has(cut.get(side, "")):
			continue
		var cutter: MeshClip.Cutter = cutters[cut[side]]
		if cutter.surface != null and not cutter.surface.is_empty():
			out.append(ShipDoors.field_of(cutter, cutter.surface))
	return out


static func _less_cuts(
	surface: PolyMesh, cuts: Array, cutters: Dictionary, side: String
) -> CSGCombiner3D:
	var out: CSGCombiner3D = CSGCombiner3D.new()
	_add_mesh(out, surface, CSGShape3D.OPERATION_UNION)
	for cut: Dictionary in cuts:
		var cutter: MeshClip.Cutter = cutters[cut[side]]
		if cutter.surface != null:
			_add_mesh(out, cutter.surface, CSGShape3D.OPERATION_SUBTRACTION)
	return out


static func _add_mesh(parent: Node, mesh: PolyMesh, op: int) -> void:
	if mesh == null or mesh.is_empty():
		return
	var node: CSGMesh3D = CSGMesh3D.new()
	node.mesh = mesh.to_array_mesh()
	node.operation = op
	parent.add_child(node)


## Waits until every combiner in [param combiners] has produced a mesh, up to READY_FRAMES. The
## engine computes on a deferred call, and a combiner whose children are themselves dirty can
## take a frame more than that: measured, one frame was enough for the second bake of a run and
## not for the first, whose fourteen parts all came back empty.
## Reports [param fraction] of the bake done, under [param label], to whoever asked. The engine
## computes on frames of its own, so a caller's bar can move between passes.
static func _tick(progress: Callable, fraction: float, label: String) -> void:
	if progress.is_valid():
		progress.call(fraction, label)


static func _until_ready(host: Node, combiners: Array) -> void:
	for _frame: int in READY_FRAMES:
		await host.get_tree().process_frame
		var ready: bool = true
		for combiner: CSGCombiner3D in combiners:
			var meshes: Array = combiner.get_meshes()
			if meshes.size() < 2 or not (meshes[1] is Mesh):
				ready = false
				break
			if (meshes[1] as Mesh).get_surface_count() == 0:
				ready = false
				break
		if ready:
			return


## The mesh a combiner produced, as the engine holds it, or null.
static func _engine_mesh(combiner: CSGCombiner3D) -> Mesh:
	var meshes: Array = combiner.get_meshes()
	if meshes.size() < 2 or not (meshes[1] is Mesh):
		return null
	return meshes[1]


static func _add_engine_mesh(parent: Node, mesh: Mesh, op: int) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node: CSGMesh3D = CSGMesh3D.new()
	node.mesh = mesh
	node.operation = op
	parent.add_child(node)


static func _read_combiner(combiner: CSGCombiner3D) -> PolyMesh:
	var meshes: Array = combiner.get_meshes()
	if meshes.size() < 2 or not (meshes[1] is Mesh):
		return PolyMesh.new()
	return _read(meshes[1])


## The engine's triangles as a [PolyMesh] of merged n-gons - or, when merging them into n-gons
## tears an edge open OR CHANGES THE VOLUME, as the triangles themselves. Manifold's output is
## closed by construction; the merge is presentation (a box shows twelve lines, not eighteen) and
## never worth a hole, nor a solid that is not the engine's. Measured (ADR 0029): the flat ring a
## bore leaves round a collar is an annulus, and the merge bridged three of twelve such pieces
## on a box carbon into closed solids 0.4-0.5 m3 too big - a tunnel read 1.498 m3 where its own
## halves summed to 1.026. Closed is not enough; the volume is checked too.
static func _read(mesh: Mesh) -> PolyMesh:
	return _tidy(_read_raw(mesh))


## The engine's triangles as a [PolyMesh], welded and NOT merged - what the seam split reads (ADR
## 0036). A triangle of an exact boolean lies on exactly ONE of the surfaces that made it, while a
## merged n-gon spanning two bodies' coplanar surfaces lies wholly on neither: measured, a helium of
## cubes left 2188 m2 of its shell, most of its area, claimed by no member at all.
static func _read_raw(mesh: Mesh) -> PolyMesh:
	if mesh == null:
		return PolyMesh.new()
	var polys: Array = []
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var index: PackedInt32Array = index_v if index_v is PackedInt32Array else PackedInt32Array()
		# TURNED ROUND ON THE WAY IN. Godot's front face is clockwise seen from outside, which is
		# what the engine hands back and what [method PolyMesh.to_array_mesh] reverses INTO; this
		# class is anticlockwise-outward. Reading the engine's order as-is therefore hands back
		# every baked solid INSIDE OUT.
		#
		# RETIRED(2026-09-23): "read in the engine's own order ... the engine's triangle order IS
		# this class's outward winding". It is not, and the measurement that said so could not have
		# seen it: [method PolyMesh.volume] returns an ABSOLUTE value, so a solid and its inside-out
		# twin measure the same, and a whole pipeline of "the volume matches" checks was blind to
		# the one thing that was wrong. Measured with a SIGNED volume: a hollow box built by hand
		# reads +31.232 m3 and the same box through here read -31.232, as did every baked solid in
		# the project. An inside-out solid handed back to the engine is intersected as its own
		# COMPLEMENT - a cut through a hollow piece came back with a solid lid over the cavity
		# instead of a ring, which is the author's "sensless infill slabs" - and drawn with
		# CULL_BACK it loses its outside, which is their "the exterior surface is simply missing".
		if index.is_empty():
			for i: int in range(0, verts.size() - 2, 3):
				polys.append(PackedVector3Array([verts[i + 2], verts[i + 1], verts[i]]))
		else:
			for i: int in range(0, index.size() - 2, 3):
				polys.append(
					PackedVector3Array([verts[index[i + 2]], verts[index[i + 1]], verts[index[i]]])
				)
	if polys.is_empty():
		return PolyMesh.new()
	return PolyMesh.from_polygons(polys, READ_WELD_M)


## [param raw] with its coplanar fragments merged into n-gons - unless the merge tears an edge open,
## makes the solid non-manifold, or changes the volume, in which case the fragments stand. See
## [method _read].
##
## THE MANIFOLD GUARD IS NOT SPARE. A merge joins coplanar fragments into one face, and where the
## fragments meet a third surface along the same line the merged face can end up sharing an edge
## with two others. Measured on a neon of cube rooms: `p_0009/cp_0002` passed
## [method MeshSeamSplit.is_sound] at 1388 faces with every edge on two faces, and came out of the
## merge at 507 faces with TWO edges on three - so the gate had approved a piece and the tidy-up
## broke it afterwards, which is the one order in which nothing was watching. A non-manifold solid
## is what the engine mis-cuts (ADR 0037), so this is the same class of fault, caught one step
## earlier.
static func _tidy(raw: PolyMesh) -> PolyMesh:
	if raw.is_empty():
		return raw
	var tidy: PolyMesh = MeshMerge.merge(raw)
	if tidy.is_empty() or not MeshSeamSplit.is_sound(tidy):
		return raw
	var raw_volume: float = raw.volume()
	if absf(tidy.volume() - raw_volume) > READ_VOLUME_REL * absf(raw_volume) + 1.0e-6:
		return raw
	return tidy
