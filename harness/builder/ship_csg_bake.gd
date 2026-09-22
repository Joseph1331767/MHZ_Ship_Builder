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
## ASYNCHRONOUS BY NECESSITY. A CSG node computes on a deferred call after it enters the tree, so
## [method bake] awaits frames between building nodes and reading meshes. Callers `await` it.

## The weld applied when the engine's triangles are read back into a [PolyMesh]. Manifold's
## output is exact to float; this is well above its noise and well below any feature.
const READ_WELD_M: float = 1.0e-5

## How many frames a pass will wait for the engine before reading what it has.
const READY_FRAMES: int = 12

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
	var keeper_of: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var shell: CSGCombiner3D = CSGCombiner3D.new()
		var bodies: CSGCombiner3D = CSGCombiner3D.new()
		var rooms: CSGCombiner3D = CSGCombiner3D.new()
		var any_room: bool = false
		for id: String in members:
			keeper_of[id] = members[0]
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
	_tick(progress, 0.45, "PIECES")

	# PASS TWO: each member's piece is the room's shell within the member's ORIGINAL body, less the
	# bodies of the members before it. A room of one is simply its shell.
	var solids: Dictionary = {}
	var pieces: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var shell: CSGCombiner3D = shells[members[0]]
		if members.size() == 1:
			var alone: PolyMesh = _read_combiner(shell)
			solids[members[0]] = alone if not alone.is_empty() else outer[members[0]]
			continue
		# The shell goes back into the engine AS THE ENGINE MADE IT - its own manifold triangles -
		# not as this file's merged n-gons re-triangulated. Measured on a box nucleus: the merged
		# reading, with holed faces bridged by PolyMesh, made pass two return 348 m3 for a piece of a
		# 50 m3 shell; the engine's own mesh does not.
		var engine_shell: Mesh = _engine_mesh(shell)
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
		for id: String in pieces:
			var solid: PolyMesh = _read_combiner(pieces[id])
			# Nothing came back: the engine rejected an operand. Keep the part as its own plain
			# body rather than lose it from the screen, and let the volume say so.
			solids[id] = solid if not solid.is_empty() else outer[id]

	# PASS TWO AND A HALF: THE DOORS (ADR 0029). Every bounded seam's opening, on both of its
	# pieces at once - a piece with several doors takes them all in one combiner - and on the
	# whole shell of any room a door opens out of, for the ROOMS: WHOLE view.
	var bored: Dictionary = {}
	var bored_rooms: Dictionary = {}
	var doors: Array = plan.get("doors", [])
	if not doors.is_empty():
		_tick(progress, 0.55, "DOORS")
		var work: Dictionary = _door_work(doors, solids)
		var ids: Array = work.keys()
		ids.sort()
		for id: String in ids:
			var source: Mesh = (
				_engine_mesh(pieces[id]) if pieces.has(id) else _engine_mesh(shells[keeper_of[id]])
			)
			bored[id] = _with_doors(stage, source, solids[id], work[id])
		for members: PackedStringArray in plan["rooms"]:
			if members.size() < 2:
				continue
			var all: Dictionary = {"union": [], "cut": []}
			for id: String in members:
				if work.has(id):
					(all["union"] as Array).append_array(work[id]["union"])
					(all["cut"] as Array).append_array(work[id]["cut"])
			if (all["cut"] as Array).is_empty():
				continue
			var keeper: String = members[0]
			bored_rooms[keeper] = _with_doors(
				stage, _engine_mesh(shells[keeper]), _read_combiner(shells[keeper]), all
			)
		await _until_ready(host, bored.values() + bored_rooms.values())
	var bored_ids: PackedStringArray = PackedStringArray()
	var door_failed: PackedStringArray = PackedStringArray()
	for id: String in bored:
		var solid: PolyMesh = _read_combiner(bored[id])
		if solid.is_empty():
			# The engine rejected the boring: the piece keeps its wall, and the report says so.
			door_failed.append(id)
			continue
		solids[id] = solid
		bored_ids.append(id)
	for id: String in door_failed:
		bored.erase(id)
	_tick(progress, 0.7, "HALVES")

	# PASS THREE: EVERY SOLID SLICED DOWN THE MIDDLE - each piece, and each room's whole shell -
	# on the part's manufacturing plane (ShipMeshBake.plan, "split"): the solid intersected with a
	# box on either side of the plane. "in manufacturing they are made in 2 pieces" (2026-09-05).
	var split: Dictionary = plan["split"]
	var room_shells: Dictionary = {}
	var half_combiners: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		var keeper: String = members[0]
		if members.size() > 1:
			var room_node: CSGCombiner3D = (
				bored_rooms[keeper] if bored_rooms.has(keeper) else shells[keeper]
			)
			var whole: PolyMesh = _read_combiner(room_node)
			if whole.is_empty() and bored_rooms.has(keeper):
				room_node = shells[keeper]
				whole = _read_combiner(room_node)
			if not whole.is_empty():
				room_shells[keeper] = whole
				_halve(
					stage,
					half_combiners,
					"room:" + keeper,
					_engine_mesh(room_node),
					whole,
					split[keeper]
				)
		for id: String in members:
			var source: Mesh = null
			if bored.has(id):
				source = _engine_mesh(bored[id])
			elif pieces.has(id):
				source = _engine_mesh(pieces[id])
			else:
				source = _engine_mesh(shells[keeper])
			_halve(stage, half_combiners, id, source, solids[id], split[id])
	await _until_ready(host, half_combiners.values())
	_tick(progress, 0.9, "SURFACES")
	var halves: Dictionary = {}
	var room_shell_halves: Dictionary = {}
	for key: String in half_combiners:
		var half: PolyMesh = _read_combiner(half_combiners[key])
		var id: String = key.trim_suffix("#a").trim_suffix("#b")
		var into: Dictionary = halves
		if id.begins_with("room:"):
			id = id.trim_prefix("room:")
			into = room_shell_halves
		var pair: Array = into.get(id, [null, null])
		pair[0 if key.ends_with("#a") else 1] = half
		into[id] = pair
	stage.queue_free()

	var report: Dictionary = ShipMeshBake.report(solids, plan, t0)
	# Every mesh the view draws carries its faces in three NAMED surfaces - exterior, interior,
	# cut - so the INTERIOR display mode can treat them apart (PolyMesh.to_array_mesh_grouped).
	var meshes: Dictionary = {}
	var half_meshes: Dictionary = {}
	var room_meshes: Dictionary = {}
	var room_half_meshes: Dictionary = {}
	for members: PackedStringArray in plan["rooms"]:
		for id: String in members:
			meshes[id] = _grouped(solids[id], members, cutters, outer, inner)
			if halves.has(id):
				half_meshes[id] = [
					_grouped(halves[id][0], members, cutters, outer, inner),
					_grouped(halves[id][1], members, cutters, outer, inner),
				]
		var keeper: String = members[0]
		if room_shells.has(keeper):
			room_meshes[keeper] = _grouped(room_shells[keeper], members, cutters, outer, inner)
			if room_shell_halves.has(keeper):
				room_half_meshes[keeper] = [
					_grouped(room_shell_halves[keeper][0], members, cutters, outer, inner),
					_grouped(room_shell_halves[keeper][1], members, cutters, outer, inner),
				]
	report["meshes"] = meshes
	report["halves"] = halves
	report["half_meshes"] = half_meshes
	report["split"] = split
	report["rooms"] = plan["rooms"]
	report["room_shells"] = room_shells
	report["room_meshes"] = room_meshes
	report["room_half_meshes"] = room_half_meshes
	report["bored"] = bored_ids
	report["door_failed"] = door_failed
	return report


## What every piece takes at its doors (ADR 0029): id -> `{"union": [PolyMesh], "cut":
## [PolyMesh]}` - its collar halves to add, then its clearing prisms and the bores to subtract.
## Only pieces the bake produced are listed.
static func _door_work(doors: Array, solids: Dictionary) -> Dictionary:
	var work: Dictionary = {}
	for door: Dictionary in doors:
		for side: String in ShipDoors.SIDES:
			var id: String = str(door[side])
			if not solids.has(id):
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


## Two combiners under [param stage], keyed `key#a` and `key#b` in [param out]: [param source]
## (the engine's own mesh of the solid, or [param fallback] when it has none) intersected with a
## box on each side of the plane [param cut] ({"origin", "normal"}).
static func _halve(
	stage: Node, out: Dictionary, key: String, source: Mesh, fallback: PolyMesh, cut: Dictionary
) -> void:
	var origin: Vector3 = cut["origin"]
	var normal: Vector3 = (cut["normal"] as Vector3).normalized()
	var reach: float = maxf(fallback.aabb().size.length(), 1.0) * 2.0
	for side: int in 2:
		var piece: CSGCombiner3D = CSGCombiner3D.new()
		if source != null and source.get_surface_count() > 0:
			_add_engine_mesh(piece, source, CSGShape3D.OPERATION_UNION)
		else:
			_add_mesh(piece, fallback, CSGShape3D.OPERATION_UNION)
		var box: CSGBox3D = CSGBox3D.new()
		box.size = Vector3(reach, reach, reach)
		box.operation = CSGShape3D.OPERATION_INTERSECTION
		var away: Vector3 = normal * (reach * 0.5) * (1.0 if side == 1 else -1.0)
		box.transform = Transform3D(_basis_facing(normal), origin + away)
		piece.add_child(box)
		stage.add_child(piece)
		out[key + ("#b" if side == 1 else "#a")] = piece


## A basis whose Z is [param normal].
static func _basis_facing(normal: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	var x: Vector3 = up.cross(normal).normalized()
	var y: Vector3 = normal.cross(x).normalized()
	return Basis(x, y, normal)


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
