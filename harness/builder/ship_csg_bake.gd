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
## view and ROOMS: WHOLE draw - every piece cut into its slicing grid (ADR 0031), every room of
## several as one bored shell and its grid - from that report, when first asked. Measured on a
## carbon of spheres: 58 read-backs a bake, of which 14 are the ship on screen, and the n-gon merge
## in each read-back was 7.6 s of the 19.
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

## The report key naming the slicing a report's extras were made with ([method slicing_key]).
const EXTRAS_SLICING: String = "extras_slicing"

## The slicing the extras are made with when a caller names none: every piece, cluster chunks
## included, bisected across its Z - the one cut the exploded view made before ADR 0031.
const DEFAULT_SLICING: Dictionary = {"parts": Vector3i(0, 0, 1), "clusters": Vector3i(0, 0, 1)}

## At most this many cuts per axis: two, a trisection.
const MAX_CUTS: int = 2

## A whole room's slicing job is keyed by its keeper under this prefix.
const ROOM_PREFIX: String = "room:"

## The three named surfaces every drawn mesh carries - see [method _grouped].
const SURFACE_EXTERIOR: String = "exterior"
const SURFACE_INTERIOR: String = "interior"
const SURFACE_CUT: String = "cut"

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

	# PASS TWO: each member's piece is the room's shell within the member's ORIGINAL body, less the
	# bodies of the members before it. A room of one is simply its shell. Nothing is read back
	# here (ADR 0030): a piece stays in the engine, as the combiner that made it, until the doors
	# are through it - measured, reading every piece at every pass was the larger half of a bake.
	var pieces: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		if members.size() == 1:
			continue
		# The shell goes back into the engine AS THE ENGINE MADE IT - its own manifold triangles -
		# not as this file's merged n-gons re-triangulated. Measured on a box nucleus: the merged
		# reading, with holed faces bridged by PolyMesh, made pass two return 348 m3 for a piece of a
		# 50 m3 shell; the engine's own mesh does not.
		var engine_shell: Mesh = _engine_mesh(shells[members[0]])
		for i: int in members.size():
			var id: String = members[i]
			var piece: CSGCombiner3D = CSGCombiner3D.new()
			_add_engine_mesh(piece, engine_shell, CSGShape3D.OPERATION_UNION)
			_add_mesh(piece, outer[id], CSGShape3D.OPERATION_INTERSECTION)
			for j: int in i:
				_add_mesh(piece, outer[members[j]], CSGShape3D.OPERATION_SUBTRACTION)
			stage.add_child(piece)
			pieces[id] = piece
	if not pieces.is_empty():
		await _until_ready(host, pieces.values())
	# Where every piece stands so far: its own combiner, or a room of one's shell.
	var made: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		for id: String in members:
			made[id] = pieces[id] if pieces.has(id) else shells[members[0]]

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
			bored[id] = _with_doors(stage, _engine_mesh(made[id]), outer[id], work[id])
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
			var solid: PolyMesh = _read_combiner(made[id])
			solids[id] = solid if not solid.is_empty() else outer[id]
			engine[id] = _engine_mesh(made[id])
	# The engine's meshes are Resources and outlive the nodes that made them: the extras operate
	# on them later, after this stage is gone.
	stage.queue_free()
	_tick(progress, 0.9, "SURFACES")

	var report: Dictionary = ShipMeshBake.report(solids, plan, t0)
	# Every mesh the view draws carries its faces in three NAMED surfaces - exterior, interior,
	# cut - so the INTERIOR display mode can treat them apart (PolyMesh.to_array_mesh_grouped).
	var meshes: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		for id: String in members:
			meshes[id] = _grouped(solids[id], members, cutters, outer, inner)
	report["meshes"] = meshes
	report["split"] = plan["split"]
	report["rooms"] = plan["rooms"]
	report["bored"] = bored_ids
	report["door_failed"] = door_failed
	report[EXTRAS_READY] = false
	report[EXTRAS_INPUT] = {"plan": plan, "engine": engine, "room_engine": room_engine}
	return report


## The exploded view's extras for a report [method bake] made (ADR 0030/0031): every room of
## several as one whole shell, its own doors bored, and every piece and whole room cut into the
## cells of its SLICING GRID - per axis of its own frame (plan "frames"), off, one cut (bisect) or
## two (trisect), at equal divisions of its body's extent. [param slicing] is
## `{"parts": Vector3i, "clusters": Vector3i}`: the counts for a piece standing alone (and for a
## room shown whole), and for a chunk of a room of several. Returns a COPY of [param bake] with
## `chunks`, `chunk_cells`, `chunk_counts`, `chunk_meshes`, `frames`, `room_shells`,
## `room_meshes` and their `room_chunk*` twins in, [constant EXTRAS_READY] set and
## [constant EXTRAS_SLICING] naming the slicing; [param bake] itself is not touched. A report
## that never reached the engine comes back marked ready with nothing added, so a caller asks once.
static func bake_extras(
	host: Node,
	bake: Dictionary,
	slicing: Dictionary = DEFAULT_SLICING,
	progress: Callable = Callable()
) -> Dictionary:
	var out: Dictionary = bake.duplicate()
	out[EXTRAS_READY] = true
	out[EXTRAS_SLICING] = slicing_key(slicing)
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
	var frames: Dictionary = plan.get("frames", {})
	var stage: Node3D = Node3D.new()
	stage.name = "CsgExtrasStage"
	host.add_child(stage)

	# THE WHOLE ROOMS: a room of several shown as one shell for ROOMS: WHOLE, bored with every
	# door any of its members opens (ADR 0029), from the room's shell as the engine made it.
	_tick(progress, 0.1, "WHOLE ROOMS")
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
	_tick(progress, 0.3, "SLICING")

	# THE SLICES (ADR 0031). "3 orthogonal slices, and offer single slice or double slice in each
	# orthogonal direction for bisection vs trisection" (2026-09-21). A piece standing alone takes
	# the parts' counts; a chunk of a room of several takes the clusters'; a room shown whole takes
	# the parts', in its keeper's frame, across the extent of all its members.
	var parts_counts: Vector3i = _counts(slicing.get("parts", Vector3i.ZERO))
	var cluster_counts: Vector3i = _counts(slicing.get("clusters", Vector3i.ZERO))
	var jobs: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var keeper: String = members[0]
		if room_shells.has(keeper):
			var bodies: Array = []
			for id: String in members:
				bodies.append(outer[id])
			jobs[ROOM_PREFIX + keeper] = _slice_job(
				room_source[keeper], room_shells[keeper], frames[keeper], bodies, parts_counts
			)
		for id: String in members:
			var counts: Vector3i = cluster_counts if members.size() > 1 else parts_counts
			jobs[id] = _slice_job(engine.get(id, null), solids[id], frames[id], [outer[id]], counts)
	for key: String in jobs.keys():
		if (jobs[key]["counts"] as Vector3i) == Vector3i.ZERO:
			jobs.erase(key)
	var cut: Dictionary = await _slice(stage, host, jobs)
	stage.queue_free()
	_tick(progress, 0.9, "SURFACES")

	var chunks: Dictionary = {}
	var chunk_cells: Dictionary = {}
	var chunk_counts: Dictionary = {}
	var chunk_meshes: Dictionary = {}
	var room_chunks: Dictionary = {}
	var room_chunk_cells: Dictionary = {}
	var room_chunk_counts: Dictionary = {}
	var room_chunk_meshes: Dictionary = {}
	var room_meshes: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var keys: Array = members.duplicate()
		var keeper: String = members[0]
		if room_shells.has(keeper):
			room_meshes[keeper] = _grouped(room_shells[keeper], members, cutters, outer, inner)
			keys.append(ROOM_PREFIX + keeper)
		for key: String in keys:
			if not cut.has(key):
				continue
			var polys: Array = []
			var cells: Array = []
			var meshes: Array = []
			for leaf: Dictionary in cut[key]:
				polys.append(leaf["solid"])
				cells.append(leaf["cell"])
				meshes.append(_grouped(leaf["solid"], members, cutters, outer, inner))
			var room: bool = key.begins_with(ROOM_PREFIX)
			var id: String = key.trim_prefix(ROOM_PREFIX) if room else key
			(room_chunks if room else chunks)[id] = polys
			(room_chunk_cells if room else chunk_cells)[id] = cells
			(room_chunk_meshes if room else chunk_meshes)[id] = meshes
			(room_chunk_counts if room else chunk_counts)[id] = jobs[key]["counts"]
	out["frames"] = frames
	out["chunks"] = chunks
	out["chunk_cells"] = chunk_cells
	out["chunk_counts"] = chunk_counts
	out["chunk_meshes"] = chunk_meshes
	out["room_shells"] = room_shells
	out["room_meshes"] = room_meshes
	out["room_chunks"] = room_chunks
	out["room_chunk_cells"] = room_chunk_cells
	out["room_chunk_counts"] = room_chunk_counts
	out["room_chunk_meshes"] = room_chunk_meshes
	return out


## A stable name for [param slicing] - what a report's extras were made with, so a caller can tell
## whether the extras on hand match the player's settings.
static func slicing_key(slicing: Dictionary) -> String:
	var parts: Vector3i = _counts(slicing.get("parts", Vector3i.ZERO))
	var clusters: Vector3i = _counts(slicing.get("clusters", Vector3i.ZERO))
	return "%d%d%d|%d%d%d" % [parts.x, parts.y, parts.z, clusters.x, clusters.y, clusters.z]


## [param value] as per-axis cut counts, each 0 (off), 1 (bisect) or 2 (trisect).
static func _counts(value: Variant) -> Vector3i:
	if not (value is Vector3i):
		return Vector3i.ZERO
	var v: Vector3i = value
	return Vector3i(clampi(v.x, 0, MAX_CUTS), clampi(v.y, 0, MAX_CUTS), clampi(v.z, 0, MAX_CUTS))


## One slicing job: the solid (as the engine made it, or [param fallback] when it has none), the
## frame it is cut in, its extent in that frame read off [param bodies] - the ORIGINAL bodies, so a
## cut does not move when a neighbour changes what was carved off this piece - and the counts.
static func _slice_job(
	source: Mesh, fallback: PolyMesh, frame: Transform3D, bodies: Array, counts: Vector3i
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
	return {
		"source": source,
		"fallback": fallback,
		"frame": frame,
		"lo": lo,
		"hi": hi,
		"counts": counts,
	}


## Every job of [param jobs] cut into the cells of its grid, one axis at a time: the X slabs of
## the whole solid, then the Y slabs of each X slab, then Z - so each engine pass works on the
## pieces of the last rather than all of every piece, and nothing is read back until the leaves.
## Returns key -> `[{"cell": Vector3i, "solid": PolyMesh}]`, empty cells left out.
static func _slice(stage: Node, host: Node, jobs: Dictionary) -> Dictionary:
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
		var made: Array = []
		var sliced: Array = []
		for key: String in jobs:
			var count: int = (jobs[key]["counts"] as Vector3i)[axis]
			if count <= 0:
				continue
			sliced.append(key)
			var next: Array = []
			for entry: Dictionary in entries[key]:
				for slab: int in count + 1:
					var combiner: CSGCombiner3D = _slab(stage, entry, jobs[key], axis, slab, count)
					var cell: Vector3i = entry["cell"]
					cell[axis] = slab
					next.append({"cell": cell, "mesh": null, "fallback": null, "made": combiner})
					made.append(combiner)
			entries[key] = next
		if made.is_empty():
			continue
		await _until_ready(host, made)
		# Only the jobs cut on THIS axis have new cells to read; a job cut on another axis keeps the
		# cells it had. Measured: re-reading every job here dropped each piece sliced on Y whenever a
		# cluster was sliced on X - the entry it still held had no combiner to read.
		for key: String in sliced:
			var kept: Array = []
			for entry: Dictionary in entries[key]:
				var combiner: CSGCombiner3D = entry["made"]
				var mesh: Mesh = _engine_mesh(combiner) if combiner != null else null
				if mesh == null or mesh.get_surface_count() == 0:
					continue
				entry["mesh"] = mesh
				kept.append(entry)
			entries[key] = kept
	var out: Dictionary = {}
	for key: String in jobs:
		var leaves: Array = []
		for entry: Dictionary in entries[key]:
			var solid: PolyMesh = _read(entry["mesh"])
			if not solid.is_empty():
				leaves.append({"cell": entry["cell"], "solid": solid})
		out[key] = leaves
	return out


## One cell of a slicing pass under [param stage]: [param entry]'s solid intersected with the
## slab [param slab] of [param count] + 1 along [param axis] of the job's frame. The outer slabs
## run out past the extent; the cuts sit at equal divisions of it.
static func _slab(
	stage: Node, entry: Dictionary, job: Dictionary, axis: int, slab: int, count: int
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
	var step: float = (hi[axis] - lo[axis]) / float(count + 1)
	var a: float = lo[axis] - reach if slab == 0 else lo[axis] + step * float(slab)
	var b: float = hi[axis] + reach if slab == count else lo[axis] + step * float(slab + 1)
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
	inner: Dictionary
) -> ArrayMesh:
	var bodies: Array = []
	var rooms: Array = []
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
		for id: int in solid.faces[i]:
			var v: Vector3 = solid.vertices[id]
			if on_body and not _on_any(v, bodies):
				on_body = false
			if on_room and not _on_any(v, rooms):
				on_room = false
			if not on_body and not on_room:
				break
		if on_body:
			groups[i] = 0
		elif on_room:
			groups[i] = 1
		else:
			groups[i] = 2
	return solid.to_array_mesh_grouped(
		groups, PackedStringArray([SURFACE_EXTERIOR, SURFACE_INTERIOR, SURFACE_CUT])
	)


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
	if mesh == null:
		return PolyMesh.new()
	var polys: Array = []
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index_v: Variant = arrays[Mesh.ARRAY_INDEX]
		var index: PackedInt32Array = index_v if index_v is PackedInt32Array else PackedInt32Array()
		# Read in the engine's own order. Measured: reading them reversed breaks the merge (two of
		# fourteen halves no longer summed to their piece) and names no surface at all, so the
		# engine's triangle order IS this class's outward winding.
		if index.is_empty():
			for i: int in range(0, verts.size() - 2, 3):
				polys.append(PackedVector3Array([verts[i], verts[i + 1], verts[i + 2]]))
		else:
			for i: int in range(0, index.size() - 2, 3):
				polys.append(
					PackedVector3Array([verts[index[i]], verts[index[i + 1]], verts[index[i + 2]]])
				)
	if polys.is_empty():
		return PolyMesh.new()
	var raw: PolyMesh = PolyMesh.from_polygons(polys, READ_WELD_M)
	var tidy: PolyMesh = MeshMerge.merge(raw)
	if tidy.open_edges() != 0 or tidy.is_empty():
		return raw
	var raw_volume: float = raw.volume()
	if absf(tidy.volume() - raw_volume) > READ_VOLUME_REL * absf(raw_volume) + 1.0e-6:
		return raw
	return tidy
