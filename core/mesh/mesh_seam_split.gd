class_name MeshSeamSplit
extends RefCounted

## A room's shell split at its SEAMS into one piece per member, each capped from its inner seam
## loop to its outer one. ADR 0036.
##
## THE AUTHOR'S CONSTRUCTION, and it is the whole of this file:
##
## > "the proper way is to union all primitave shapes together, then cut them along the shape of
## > interior seam to exterior seam .. the cut shapes inner seams all have vertexes, and the outter
## > shell has vertexes, their end caps would be the capping of inner seam verticies to outter seam
## > verticies, independantly for each piece .. think of a cuve in a cube, and think of the cubes
## > edges as the "seams" of 2 joined shapes. the inner cube line between verticies i,j exist, and
## > the outter cubes a,b exists, so a face between i,a,b,j would be the cap" (2026-09-22)
##
## RETIRED(ADR 0036): cutting each piece back with the neighbours' own SOLIDS (ADR 0021) and, for a
## pair of equals, with a PLANE between them (ADR 0035). A solid cutter is a priority order - the
## first member keeps everything, the last is bitten by all of them - and a plane is the right
## divider only where the two bodies are mirror images across it, which is why a carbon of cubes
## came out right and a boron of cubes came out notched. Neither follows the seam; this does,
## because it IS the seam.
##
## NOTHING IS MARCHED AND NOTHING IS SAMPLED ON A GRID. "we will never marsh cubes or use surface
## nets. weve already decided on excat mesh cfg stuff" (2026-09-22). The seam loops are already
## VERTICES OF THE SHELL - exact CSG puts them there, because that is what intersecting two solids
## means - so this file reads what the engine already computed and never invents a point. Measured:
## a helium of `box_hull` has exactly 4 vertices of its shell lying on both bodies' surfaces, the
## rectangle where the two cubes cross.
##
## WHAT THE PIECES COME OUT AS. Every face of a piece is a real surface: its own outer face, its
## own cavity wall, a neighbour's cavity wall where that neighbour opens through it, and the cap.
## Two pieces of a pair share the same two loops, so their caps are the same surface and they meet
## exactly - no overlap, no gap, and no plane anywhere.
##
## NOT WIRED YET, and FOLLOWUPS F48 says why. What this file does is measured and right: a cube
## carbon splits into six pieces of 26.64 m3 that sum to its shell exactly, every piece closed and
## every edge shared by two faces. What is not solved is the ENGINE work downstream - a piece with
## a door bored through it will not slice into its cells. [ShipCsgBake] therefore still cuts rooms
## back the old way; do not delete either until the other is proven.
##
## Pure data (SPEC section 12): [RefCounted], static only, no [Node], no [code]res://[/code].

## Which surface of a member a face lies on.
const KIND_BODY: int = 0
const KIND_ROOM: int = 1

## How far a face's vertices may lie from a surface and still be ON it, metres. Every vertex of the
## shell came from one of these surfaces by an exact boolean, so the real figure is float noise;
## this is loose enough to survive a read-back and tight enough that no vertex is on two surfaces
## it is not actually on. Vertices, never centroids: a face's centroid sits inside a curved surface
## by its own sagitta, which on a 9 m sphere is centimetres.
const ON_SURFACE_M: float = 0.002

## How far apart two loops' centres may stand and still be the two sides of one seam, as a
## fraction of the loop's own reach. They are a wall apart in truth; this is loose enough for a
## seam whose two curves are not concentric and tight enough to refuse a loop from somewhere else.
const SAME_SEAM_FRACTION: float = 0.5

## How many times an island may be handed to what surrounds it. Each pass can only dissolve the
## outermost layer of one, and the islands a seam leaves are single faces; a handful is plenty and
## the pass stops of its own accord when nothing moves.
const SETTLE_PASSES: int = 4

## Loop chaining gives up past this many steps rather than spin on a malformed boundary.
const MAX_LOOP_STEPS: int = 100000


## The pieces of [param shell], keyed by member id: `{id: PolyMesh}`.
##
## [param bodies] and [param rooms] give, per member, the LIST of calibrated fields
## ([method ShipDoors.field_of]) that its outer and cavity surfaces are made of - `d(p)` reading
## zero on the tessellation the engine was handed, which is not the same as the field's own zero
## (F34: a box mesh sits 0.16 m inside its field).
##
## A LIST, because a member's surface is not only its own body. A tunnel standing in it cuts a
## SOCKET, and the face at the bottom of that socket lies on the tunnel's surface while belonging
## to the member as surely as any other: measured, a carbon whose sockets were left out of the
## reckoning had them claimed by whichever member was nearest, which is how a piece ends up with
## an island of surface that is not its own and a cap that crosses itself.
##
## A member whose surface never reaches the shell gets an empty mesh: it contributed no hull, which
## is a true answer about a body buried inside its neighbours, and the caller decides what to draw.
static func split(
	shell: PolyMesh, members: PackedStringArray, bodies: Dictionary, rooms: Dictionary
) -> Dictionary:
	var out: Dictionary = {}
	if shell == null or shell.is_empty() or members.is_empty():
		return out
	var owner_of: PackedInt32Array = PackedInt32Array()
	var kind_of: PackedInt32Array = PackedInt32Array()
	_classify(shell, members, bodies, rooms, owner_of, kind_of)

	# Every directed edge of the shell: what face it belongs to, and which edge follows it round
	# that face. A closed solid traverses every edge once each way, which is what makes the first
	# lookup a twin; the second is what lets a boundary be WALKED rather than guessed at.
	var across: Dictionary = {}
	var after: Dictionary = {}
	for face: int in shell.faces.size():
		for loop: PackedInt32Array in _loops_of(shell, face):
			for k: int in loop.size():
				var u: int = loop[k]
				var v: int = loop[(k + 1) % loop.size()]
				var w: int = loop[(k + 2) % loop.size()]
				across[_edge_key(u, v, shell)] = face
				after[_edge_key(u, v, shell)] = _edge_key(v, w, shell)

	_settle(shell, owner_of, kind_of, across)
	for index: int in members.size():
		var id: String = members[index]
		out[id] = _piece(shell, index, owner_of, kind_of, across, after)
	return out


## Which member's surface, and which of its two, every face of [param shell] lies on. -1 for a face
## that is on none of them, which the caller sees as a face no piece claims.
static func _classify(
	shell: PolyMesh,
	members: PackedStringArray,
	bodies: Dictionary,
	rooms: Dictionary,
	owner_of: PackedInt32Array,
	kind_of: PackedInt32Array
) -> void:
	# Sampled ONCE per vertex per surface. Every face then reads its own vertices out of the table;
	# faces share vertices several times over, and the field is the expensive call in here.
	var count: int = shell.vertices.size()
	var body_d: Array = []
	var room_d: Array = []
	for id: String in members:
		body_d.append(_distances(shell, bodies.get(id, []), count))
		room_d.append(_distances(shell, rooms.get(id, []), count))

	owner_of.resize(shell.faces.size())
	kind_of.resize(shell.faces.size())
	for face: int in shell.faces.size():
		var loop: PackedInt32Array = shell.faces[face]
		var best: float = ON_SURFACE_M
		var best_member: int = -1
		var best_kind: int = KIND_BODY
		for index: int in members.size():
			for kind: int in [KIND_BODY, KIND_ROOM]:
				var table: PackedFloat32Array = (
					body_d[index] if kind == KIND_BODY else room_d[index]
				)
				if table.is_empty():
					continue
				# The WHOLE face has to lie on the surface, so the worst of its vertices decides.
				var worst: float = 0.0
				for v: int in loop:
					worst = maxf(worst, table[v])
					if worst >= best:
						break
				if worst < best:
					best = worst
					best_member = index
					best_kind = kind
		if best_member < 0:
			# NOTHING OWNS IT OUTRIGHT. A triangle of an exact boolean lies on one of the surfaces
			# that made it, so this is the coplanar case - two bodies whose surfaces share a plane,
			# with a face the engine did not split between them. The nearest surface takes it
			# whole: one piece is then a little large and its neighbour a little small, which is a
			# better answer than a hole in the hull where nobody claimed the face at all.
			var mean: float = INF
			for index: int in members.size():
				for kind: int in [KIND_BODY, KIND_ROOM]:
					var table: PackedFloat32Array = (
						body_d[index] if kind == KIND_BODY else room_d[index]
					)
					if table.is_empty():
						continue
					var total: float = 0.0
					for v: int in loop:
						total += table[v]
					var average: float = total / float(maxi(loop.size(), 1))
					if average < mean:
						mean = average
						best_member = index
						best_kind = kind
		owner_of[face] = best_member
		kind_of[face] = best_kind


## Is [param piece] a solid a boolean engine will accept - closed, and with every edge shared by
## exactly two faces?
##
## CLOSED IS NOT ENOUGH. [method PolyMesh.open_edges] counts edges that find no partner, and an
## edge used FOUR times finds partners perfectly well; the engine refuses it all the same. Measured
## on a sphere carbon, whose pieces came back closed with four to twenty-two such edges and sliced
## into nothing at all, while every box piece had none.
static func is_sound(piece: PolyMesh) -> bool:
	if piece == null or piece.is_empty() or piece.open_edges() != 0:
		return false
	var count: int = piece.vertices.size()
	var seen: Dictionary = {}
	for face: int in piece.faces.size():
		for loop: PackedInt32Array in _loops_of(piece, face):
			for k: int in loop.size():
				var a: int = loop[k]
				var b: int = loop[(k + 1) % loop.size()]
				var key: int = mini(a, b) * count + maxi(a, b)
				var used: int = int(seen.get(key, 0)) + 1
				if used > 2:
					return false
				seen[key] = used
	return true


## An ISLAND JOINS WHAT SURROUNDS IT. A face whose every neighbour belongs to one other surface is
## on the wrong one: along a seam the two fields read alike to the last bit, and the worst-vertex
## rule then hands single triangles to the far side. Each one becomes a patch of its own with a
## three-edge boundary, a cap of its own, and a flap of no volume hanging off the piece - measured
## on a sphere carbon, whose pieces carried fourteen such islands and were refused by the engine
## when it came to slice them.
##
## Only the unanimous case is moved, and moved repeatedly until nothing changes: a face with
## neighbours on both sides is on a real boundary and is left exactly where the fields put it.
static func _settle(
	shell: PolyMesh, owner_of: PackedInt32Array, kind_of: PackedInt32Array, across: Dictionary
) -> void:
	for _pass: int in SETTLE_PASSES:
		var moved: int = 0
		for face: int in shell.faces.size():
			var owner: int = -1
			var kind: int = -1
			var alone: bool = true
			for loop: PackedInt32Array in _loops_of(shell, face):
				for k: int in loop.size():
					var twin: Variant = across.get(
						_edge_key(loop[(k + 1) % loop.size()], loop[k], shell), null
					)
					if twin == null:
						continue
					var other: int = int(twin)
					if owner_of[other] == owner_of[face] and kind_of[other] == kind_of[face]:
						alone = false
						break
					if owner < 0:
						owner = owner_of[other]
						kind = kind_of[other]
					elif owner != owner_of[other] or kind != kind_of[other]:
						alone = false
						break
				if not alone:
					break
			if alone and owner >= 0:
				owner_of[face] = owner
				kind_of[face] = kind
				moved += 1
		if moved == 0:
			return


## How far every vertex of [param shell] stands from the NEAREST of [param fields] - the surface a
## member is made of, sockets included. Empty when the member has no such surface at all.
static func _distances(shell: PolyMesh, fields: Array, count: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	if fields.is_empty():
		return out
	out.resize(count)
	for i: int in count:
		var p: Vector3 = shell.vertices[i]
		var best: float = INF
		for field: Variant in fields:
			if field == null:
				continue
			var d: float = absf(field.d(p))
			if d < best:
				best = d
		out[i] = best
	return out


## One member's piece: its own faces, plus a cap along every boundary it has with another member.
##
## Assembled FACE BY FACE rather than welded from a polygon soup, so a face that carries holes -
## which a merged read-back makes - keeps them. The vertices are the shell's own, already welded by
## the engine, and only the ones this piece uses come across.
static func _piece(
	shell: PolyMesh,
	index: int,
	owner_of: PackedInt32Array,
	kind_of: PackedInt32Array,
	across: Dictionary,
	after: Dictionary
) -> PolyMesh:
	var mine: PackedInt32Array = PackedInt32Array()
	for face: int in shell.faces.size():
		if owner_of[face] == index:
			mine.append(face)
	var out: PolyMesh = PolyMesh.new()
	if mine.is_empty():
		return out

	# THE BOUNDARY, as directed edges. An edge of mine whose twin belongs to another member is
	# where my surface ends - the seam - and the direction it runs in is my own face's, which is
	# what lets the cap be wound without ever asking which way is out.
	var body_loops: Array = _patch_loops(shell, index, KIND_BODY, owner_of, kind_of, across, after)
	var room_loops: Array = _patch_loops(shell, index, KIND_ROOM, owner_of, kind_of, across, after)

	var remap: Dictionary = {}
	for face: int in mine:
		var holes: Array = []
		for hole: PackedInt32Array in shell.holes_of(face):
			holes.append(_carried(shell, hole, remap, out))
		out.add_face(_carried(shell, shell.faces[face], remap, out), holes)
	for cap: PackedInt32Array in _caps(shell, body_loops, room_loops):
		if cap.size() >= 3:
			out.add_face(_carried(shell, cap, remap, out))
	return out


## [param loop] in [param out]'s own numbering, bringing across any vertex it has not seen.
static func _carried(
	shell: PolyMesh, loop: PackedInt32Array, remap: Dictionary, out: PolyMesh
) -> PackedInt32Array:
	var carried: PackedInt32Array = PackedInt32Array()
	for v: int in loop:
		if not remap.has(v):
			remap[v] = out.vertices.size()
			out.vertices.append(shell.vertices[v])
		carried.append(int(remap[v]))
	return carried


## The cap faces joining each outer loop to the inner loop that answers it. Loops are answered by
## proximity: a member with several neighbours has one pair of loops per neighbour, and the two of
## a pair run around the same seam a wall apart.
static func _caps(shell: PolyMesh, outer: Array, inner: Array) -> Array:
	var out: Array = []
	var taken: Dictionary = {}
	for loop: PackedInt32Array in outer:
		var pick: int = -1
		# Only a loop that stands where this one stands can be the other side of the same seam:
		# the two are a WALL apart, which is nothing beside the seam's own reach. Pairing on
		# nearest-centroid alone marries a seam to a stray triangle on the far side of the piece
		# and zips a cap across the whole of it.
		var best: float = _loop_reach(shell, loop) * SAME_SEAM_FRACTION
		for i: int in inner.size():
			if taken.has(i):
				continue
			var gap: float = _loop_centre(shell, loop).distance_to(_loop_centre(shell, inner[i]))
			if gap < best:
				best = gap
				pick = i
		if pick < 0:
			out.append(_reversed(loop))
			continue
		taken[pick] = true
		out.append_array(_zip(shell, loop, inner[pick]))
	# A LOOP WITH NOTHING TO ANSWER IT IS CLOSED BY ITSELF. The two surfaces do not always bound
	# the same number of holes - where three cavities meet, the inner one carries little triangles
	# of its own - and a hole nothing spans is still a hole. One face over it is both the smallest
	# answer and the right one.
	for i: int in inner.size():
		if not taken.has(i):
			out.append(_reversed(inner[i]))
	return out


## [param loop] the other way about, which is how a loop is closed by a face of its own: the face
## has to traverse the boundary against the patch that already owns it.
static func _reversed(loop: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(loop.size() - 1, -1, -1):
		out.append(loop[i])
	return out


## The cap between one outer loop and one inner loop: a face per OUTER edge, carrying that edge
## backwards (so it pairs with the face it came from) and returning along the inner loop.
##
## The author's `(i, a, b, j)`. The two loops do not have the same vertex count in general - they
## are found independently, on two different pairs of surfaces - so each outer vertex is answered
## by the inner vertex nearest it AROUND THE LOOP rather than by index, and an inner vertex that no
## outer vertex claimed is carried inside the face that spans it. Every inner edge ends up in
## exactly one face, which is what keeps the piece closed.
static func _zip(shell: PolyMesh, outer: PackedInt32Array, inner: PackedInt32Array) -> Array:
	var out: Array = []
	if outer.size() < 2 or inner.size() < 2:
		return out
	# The inner loop runs the other way around the seam - its surface faces into the cavity - so it
	# is turned to travel with the outer one before anything is matched.
	var ring: PackedInt32Array = _aligned(shell, outer, inner)
	var partner: PackedInt32Array = _partners(shell, outer, ring)
	for k: int in outer.size():
		var u: int = outer[k]
		var v: int = outer[(k + 1) % outer.size()]
		var loop: PackedInt32Array = PackedInt32Array([v, u])
		var a: int = partner[k]
		var b: int = partner[(k + 1) % outer.size()]
		var step: int = a
		loop.append(ring[step])
		var guard: int = ring.size() + 1
		while step != b and guard > 0:
			step = (step + 1) % ring.size()
			loop.append(ring[step])
			guard -= 1
		out.append(loop)
	return out


## [param inner] turned and rotated so it travels the same way around the seam as [param outer],
## starting beside its first vertex.
##
## TURNED BY THE TWO LOOPS' OWN NORMALS, not by which of two candidate vertices is nearer. Both
## patches are wound outward, so a wall's outer boundary and its inner boundary run OPPOSITE ways
## around the seam - which is exactly what makes the cap pair with both of them - and the way to
## see that is the direction each loop encloses, not a local comparison: on a seam of fifty
## vertices the nearest-neighbour probe reads the wrong way wherever the two curves are not
## parallel, and the cap then crosses over itself.
static func _aligned(
	shell: PolyMesh, outer: PackedInt32Array, inner: PackedInt32Array
) -> PackedInt32Array:
	var chosen: PackedInt32Array = inner
	if _loop_normal(shell, outer).dot(_loop_normal(shell, inner)) < 0.0:
		var backward: PackedInt32Array = PackedInt32Array()
		for i: int in range(inner.size() - 1, -1, -1):
			backward.append(inner[i])
		chosen = backward
	var start: int = _nearest(shell, chosen, shell.vertices[outer[0]])
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in chosen.size():
		out.append(chosen[(start + i) % chosen.size()])
	return out


## The direction a closed loop encloses, by Newell's method - which needs no plane and no centre,
## and is stable on a loop that is not flat.
static func _loop_normal(shell: PolyMesh, loop: PackedInt32Array) -> Vector3:
	var out: Vector3 = Vector3.ZERO
	for i: int in loop.size():
		var a: Vector3 = shell.vertices[loop[i]]
		var b: Vector3 = shell.vertices[loop[(i + 1) % loop.size()]]
		out += a.cross(b)
	return out


## For each vertex of [param outer], the vertex of [param ring] that answers it - matched by HOW
## FAR ROUND EACH LOOP THEY STAND, not by which is nearest.
##
## The two loops run around one seam a wall apart and are found on two different pairs of surfaces,
## so they share no vertex count and no vertex. Arc length is the one thing they do share: a vertex
## a third of the way round the outer seam is answered by the vertex a third of the way round the
## inner one. Nearest-point matching reads better on paper and doubles back wherever the two curves
## are not parallel, which crosses the cap over itself.
static func _partners(
	shell: PolyMesh, outer: PackedInt32Array, ring: PackedInt32Array
) -> PackedInt32Array:
	var along_outer: PackedFloat32Array = _arc_lengths(shell, outer)
	var along_ring: PackedFloat32Array = _arc_lengths(shell, ring)
	var out: PackedInt32Array = PackedInt32Array()
	var at: int = 0
	var last: int = 0
	for k: int in outer.size():
		var want: float = along_outer[k]
		# Forward only: the walk keeps step with the outer loop and never turns back on itself.
		while at + 1 < ring.size() and along_ring[at + 1] <= want:
			at += 1
		var here: int = at
		if at + 1 < ring.size():
			var before: float = absf(along_ring[at] - want)
			var ahead: float = absf(along_ring[at + 1] - want)
			if ahead < before:
				here = at + 1
		# Rounding to the nearer of two can step BACK one where the walk itself did not move, and
		# a cap face that starts behind the one before it spans the loop the long way round -
		# covering edges twice and leaving others bare. It is held to what it has already reached.
		here = maxi(here, last)
		last = here
		out.append(here)
	return out


## Where each vertex of [param loop] stands as a fraction of the way round it, the last edge -
## back to the first vertex - counted in the total.
static func _arc_lengths(shell: PolyMesh, loop: PackedInt32Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(loop.size())
	var total: float = 0.0
	for i: int in loop.size():
		out[i] = total
		total += shell.vertices[loop[i]].distance_to(shell.vertices[loop[(i + 1) % loop.size()]])
	if total <= 0.0:
		return out
	for i: int in out.size():
		out[i] = out[i] / total
	return out


static func _nearest(shell: PolyMesh, loop: PackedInt32Array, to: Vector3) -> int:
	var best: int = 0
	var gap: float = INF
	for i: int in loop.size():
		var d: float = shell.vertices[loop[i]].distance_to(to)
		if d < gap:
			gap = d
			best = i
	return best


## The closed loops that bound one member's BODY or ROOM patch, walked.
##
## WALKED, NOT CHAINED. Where three bodies meet, one vertex carries boundary edges of two different
## seams, and a walk that only knows the edge SET takes whichever it finds and hops from one seam
## onto the other - measured on a sphere carbon, whose four room seams came back as one loop of 149
## and whose pieces would not close. The way out is the one a half-edge structure always uses: from
## the edge just walked, turn around its far vertex THROUGH THIS PATCH - each step crossing to the
## neighbouring face and taking its next edge - and stop at the first edge that is a boundary
## again. That is the next edge of this loop and no other, whatever else passes through the vertex.
static func _patch_loops(
	shell: PolyMesh,
	index: int,
	kind: int,
	owner_of: PackedInt32Array,
	kind_of: PackedInt32Array,
	across: Dictionary,
	after: Dictionary
) -> Array:
	var edges: Dictionary = {}
	for face: int in shell.faces.size():
		if owner_of[face] != index or kind_of[face] != kind:
			continue
		for loop: PackedInt32Array in _loops_of(shell, face):
			for k: int in loop.size():
				var u: int = loop[k]
				var v: int = loop[(k + 1) % loop.size()]
				var twin: Variant = across.get(_edge_key(v, u, shell), null)
				if twin == null:
					continue
				if owner_of[int(twin)] == index and kind_of[int(twin)] == kind:
					continue
				edges[_edge_key(u, v, shell)] = u

	var out: Array = []
	var used: Dictionary = {}
	var keys: Array = edges.keys()
	keys.sort()
	for key: int in keys:
		if used.has(key):
			continue
		var loop: PackedInt32Array = PackedInt32Array()
		var at: int = key
		var guard: int = MAX_LOOP_STEPS
		while at >= 0 and not used.has(at) and guard > 0:
			guard -= 1
			used[at] = true
			loop.append(int(edges[at]))
			at = _next_boundary(shell, at, edges, after)
		if loop.size() >= 3:
			out.append(loop)
	return out


## The boundary edge that follows [param key] around its patch: turn about the far vertex, one
## face at a time, until an edge of the boundary comes round. -1 when the turn closes on nothing,
## which a closed solid cannot do and a torn one can.
static func _next_boundary(shell: PolyMesh, key: int, edges: Dictionary, after: Dictionary) -> int:
	var step: Variant = after.get(key, null)
	var guard: int = 64
	while step != null and guard > 0:
		guard -= 1
		var here: int = int(step)
		if edges.has(here):
			return here
		var count: int = shell.vertices.size()
		@warning_ignore("integer_division")
		var a: int = here / count
		var b: int = here % count
		step = after.get(_edge_key(b, a, shell), null)
	return -1


## How far a loop's vertices stand from its own centre, on average - its reach. The scale against
## which "these two loops are the same seam" is judged, so the test holds on a seam of any size.
static func _loop_reach(shell: PolyMesh, loop: PackedInt32Array) -> float:
	var centre: Vector3 = _loop_centre(shell, loop)
	var total: float = 0.0
	for v: int in loop:
		total += shell.vertices[v].distance_to(centre)
	return total / float(maxi(loop.size(), 1))


static func _loop_centre(shell: PolyMesh, loop: PackedInt32Array) -> Vector3:
	var out: Vector3 = Vector3.ZERO
	for v: int in loop:
		out += shell.vertices[v]
	return out / float(maxi(loop.size(), 1))


## Every loop of a face, its outer boundary first.
static func _loops_of(shell: PolyMesh, face: int) -> Array:
	var out: Array = [shell.faces[face]]
	out.append_array(shell.holes_of(face))
	return out


## A directed edge as one integer, so the twin lookup is an integer hash rather than a string.
static func _edge_key(a: int, b: int, shell: PolyMesh) -> int:
	return a * shell.vertices.size() + b
