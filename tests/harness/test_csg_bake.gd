# The exact bake the player sees: core's plan, carried out by the engine's CSG (ADR 0020).
#
# Every test here builds on SPHERE pods - the family the author builds with - and on boxes, and
# reads the result the way the exploded view will: one closed solid per part. A gdUnit suite is a
# Node, so it can host the CSG nodes and await the frame they compute on.
class_name TestCsgBake
extends GdUnitTestSuite
var _data: ShipData
var _cfg: ShipConfig


## TEMPLATE LINKS ARE OPEN BY DEFAULT since 2026-09-26 ("by default in the prebuilds we dont want
## any walls in our prebuilds by default"). This suite is about what a ship with LINKS does - its
## walls, its doors, the rooms they bound or the meshes they cut - so it asks for the hatches the
## templates used to place, instead of resting on a default that no longer says that.
func _linked(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {ShipTemplates.OPT_LINK_MODE: ShipJoint.MODE_HATCHED}
	out.merge(extra)
	return out


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message("ShipData.load_all() failed: %s" % [str(_data.load_errors)])
		. is_true()
	)
	_cfg = ShipConfig.defaults()


## A carbon whose nucleus is one open room (the root component the template builds, ADR 0024)
## or walled (the component dissolved back into six plain protons with no joints between them).
func _carbon(family: String, open_nucleus: bool) -> ShipDoc:
	var doc: ShipDoc = ShipTemplates.build(
		_data, _cfg, "carbon", _linked({ShipTemplates.OPT_ROOM_FAMILY: family})
	)
	if not open_nucleus:
		assert_int(ShipComponents.dissolve(doc, doc.root).size()).is_equal(6)
		# The definition's open links come back with the protons (ADR 0025); walled means walled,
		# so they are SEALED. Erasing them instead - which this did until 2026-09-25 - leaves the
		# protons with no link at all, and a nucleus laid out side by side has no parent-child
		# link either, so ADR 0034's rule ("THE LINK IS THE JOINT RECORD, never mere contact")
		# means no seam is authored: the six bodies read as separate rooms that merely intersect,
		# each uncut. Measured on a carbon, the difference is plain - 5214 m2 of exterior unlinked
		# against 4741 m2 sealed, and 18 m2 of wall against 493 m2.
		_all_seams(doc, ShipJoint.MODE_SEALED)
	return doc


## Every joint of [param doc] set to [param mode]. Returns how many changed.
func _all_seams(doc: ShipDoc, mode: String) -> int:
	var changed: int = 0
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if joint.mode != mode:
			joint.mode = mode
			changed += 1
	return changed


## The total area of every surface named [param surface_name] across a bake's drawn meshes.
func _surface_area(report: Dictionary, surface_name: String) -> float:
	var total: float = 0.0
	for id: String in report["meshes"] as Dictionary:
		var mesh: ArrayMesh = (report["meshes"] as Dictionary)[id]
		for s: int in mesh.get_surface_count():
			if mesh.surface_get_name(s) != surface_name:
				continue
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for k: int in range(0, index.size() - 2, 3):
				var a: Vector3 = verts[index[k]]
				total += (0.5 * (verts[index[k + 1]] - a).cross(verts[index[k + 2]] - a).length())
	return total


## A part's plain shell, for scale: the difference of its two surfaces as built.
func _whole_shell(doc: ShipDoc, pid: String) -> float:
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
	var outer: float = ShapeMesh.build(shapes[pid]).volume()
	var inner: float = ShapeMesh.build(ShapeMesh.inset(shapes[pid], _cfg.hull_thickness_m)).volume()
	return outer - inner


func test_every_module_is_a_closed_shell_on_spheres_and_on_boxes() -> void:
	# "they are not shells with uniform thickness, infact the inner mesh looks like a sphere
	# partially subtracted from another" (2026-09-05). Every part, both families, walled: a closed
	# solid of about one shell's worth of hull - never the raw solid, never torn.
	for family: String in ["sphere_pod", "box_hull"]:
		var doc: ShipDoc = _carbon(family, false)
		var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
		(
			assert_int((report["open_parts"] as PackedStringArray).size())
			. append_failure_message(
				"%s: parts came out open: %s" % [family, str(report["open_parts"])]
			)
			. is_equal(0)
		)
		var solids: Dictionary = report["solids"]
		for pid: String in doc.part_order():
			var piece: PolyMesh = solids[pid]
			var whole: float = _whole_shell(doc, pid)
			(
				assert_float(piece.volume())
				. append_failure_message(
					(
						"%s %s is not a shell (%.1f m3 against %.1f)"
						% [family, pid, piece.volume(), whole]
					)
				)
				. is_less(whole * 1.5)
			)
			assert_float(piece.volume()).is_greater(0.0)


func test_a_tunnel_cuts_its_socket_into_every_pod() -> void:
	# "only half of the tunnel-to-module connections cut as described" (2026-09-05). A pod at the
	# end of a tunnel carries the tunnel's socket - visibly, as many more faces than a plain shell
	# has - on all four, on both families.
	for family: String in ["sphere_pod", "box_hull"]:
		var doc: ShipDoc = _carbon(family, false)
		var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
		var solids: Dictionary = report["solids"]
		var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
		for pid: String in doc.part_order():
			var part: ShipPart = doc.parts[pid]
			if part.role != ShipPart.ROLE_HALLWAY:
				continue
			var pod: String = ""
			for other: String in doc.part_order():
				if (doc.parts[other] as ShipPart).parent == pid:
					pod = other
			assert_str(pod).is_not_empty()
			var plain: int = ShapeMesh.build(shapes[pod]).face_count() * 2
			(
				assert_int((solids[pod] as PolyMesh).face_count())
				. append_failure_message(
					"%s: pod %s shows no socket for tunnel %s" % [family, pod, pid]
				)
				. is_greater(plain)
			)


func test_an_open_nucleus_explodes_into_holed_pieces() -> void:
	# "the assembled room doesnt explode into its pieces so i cant inspect the interior"
	# (2026-09-05). Six protons one room - the root component's, joined by membership rather
	# than by joints (ADR 0024): six separate closed pieces, the root with five holes (far less
	# hull than a whole shell), every rim with its own - and nothing absorbed.
	for family: String in ["sphere_pod", "box_hull"]:
		var doc: ShipDoc = _carbon(family, true)
		var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
		var nucleus: PackedStringArray = PackedStringArray()
		for members: PackedStringArray in report["rooms"]:
			if members.has(doc.root):
				nucleus = members
		assert_int(nucleus.size()).append_failure_message(family).is_equal(6)
		assert_int((report["absorbed"] as PackedStringArray).size()).is_equal(0)
		(
			assert_int((report["open_parts"] as PackedStringArray).size())
			. append_failure_message(
				"%s: room pieces came out open: %s" % [family, str(report["open_parts"])]
			)
			. is_equal(0)
		)
		var solids: Dictionary = report["solids"]
		var root: PolyMesh = solids[doc.root]
		var whole: float = _whole_shell(doc, doc.root)
		assert_float(root.volume()).is_greater(0.0)
		(
			assert_float(root.volume())
			. append_failure_message("%s: the root kept its walls across five open seams" % family)
			. is_less(whole * 0.6)
		)
		for pid: String in nucleus:
			if pid == doc.root:
				continue
			var rim: PolyMesh = solids[pid]
			assert_bool(rim.is_empty()).append_failure_message("%s absorbed" % pid).is_false()
			assert_float(rim.volume()).is_less(_whole_shell(doc, pid))


func test_no_room_piece_keeps_hull_inside_another_member() -> void:
	# "the central proton doesnt resolve correctly" (2026-09-05): under a per-part rule the root
	# kept slabs of its own skin lying inside its neighbours' walls. A room built whole - union of
	# bodies less union of interiors, then cut back along the original bodies (ADR 0021) - has no
	# such slab to keep. Measured by the engine itself: each piece intersected with every OTHER
	# member's interior body has no volume.
	for family: String in ["sphere_pod", "box_hull"]:
		var doc: ShipDoc = _carbon(family, true)
		var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
		var solids: Dictionary = report["solids"]
		var shapes: Dictionary = ShipAttach.resolve_shapes(doc, _data, _cfg)
		var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, _cfg)
		var members: PackedStringArray = PackedStringArray([doc.root])
		for pid: String in doc.part_order():
			var part: ShipPart = doc.parts[pid]
			if part.parent == doc.root and part.role == ShipPart.ROLE_ROOM:
				members.append(pid)
		var stage: Node3D = Node3D.new()
		add_child(stage)
		var probes: Dictionary = {}
		for a: String in members:
			for b: String in members:
				if a == b:
					continue
				var probe: CSGCombiner3D = CSGCombiner3D.new()
				var piece: CSGMesh3D = CSGMesh3D.new()
				piece.mesh = (solids[a] as PolyMesh).to_array_mesh()
				probe.add_child(piece)
				var room: CSGMesh3D = CSGMesh3D.new()
				room.mesh = (
					ShapeMesh
					. build(ShapeMesh.inset(shapes[b], _cfg.hull_thickness_m))
					. transformed(xforms[b])
					. to_array_mesh()
				)
				room.operation = CSGShape3D.OPERATION_INTERSECTION
				probe.add_child(room)
				stage.add_child(probe)
				probes[a + "/" + b] = probe
		for _frame: int in 6:
			await get_tree().process_frame
		for key: String in probes:
			var meshes: Array = (probes[key] as CSGCombiner3D).get_meshes()
			var inside: float = 0.0
			if meshes.size() >= 2 and meshes[1] is Mesh:
				var mesh: Mesh = meshes[1]
				if mesh.get_surface_count() > 0:
					var arrays: Array = mesh.surface_get_arrays(0)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var polys: Array = []
					for i: int in range(0, verts.size() - 2, 3):
						polys.append(PackedVector3Array([verts[i], verts[i + 1], verts[i + 2]]))
					inside = absf(PolyMesh.from_polygons(polys, 1.0e-5).volume())
			(
				assert_float(inside)
				. append_failure_message(
					(
						"%s: piece %s keeps %.2f m3 of hull inside the other's room"
						% [family, key, inside]
					)
				)
				. is_less(0.05)
			)
		stage.queue_free()


func test_every_piece_is_sliced_into_two_closed_halves() -> void:
	# "any module .. need to get sliced down the middle in the explode group. (in manufacturing
	# they are made in 2 pieces.)" (2026-09-05). Both families, walled and as one room: every part
	# has two halves, each closed, and the two together are the piece.
	for family: String in ["sphere_pod", "box_hull"]:
		for open_nucleus: bool in [false, true]:
			var doc: ShipDoc = _carbon(family, open_nucleus)
			var assembled: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
			# A bisection across Z is the cells on either side of the middle cut (ADR 0032).
			var report: Dictionary = await ShipCsgBake.bake_extras(self, assembled)
			var cells: Dictionary = report["cells"]
			var solids: Dictionary = report["solids"]
			# EVERY PIECE IS CUT IN ITS OWN AXES (ADR 0041), so it is the PIECE that comes apart
			# down its own middle. There is no longer one grid through a room to ask the question
			# of: each chunk has its own z, and a room's chunks point every way a nucleus does.
			#
			# RETIRED(ADR 0041): "A ROOM is cut as one body (ADR 0033): one grid of planes runs
			# through all of its members, so it is the ROOM that comes apart down the middle - a
			# member standing on one side of it .. keeps all of its cells on that side and is not a
			# sliver for it." Summed per room under the new rule a carbon reads 8.0 / 152.0, which
			# measures nothing but the chunks disagreeing about which way z points.
			for pid: String in doc.part_order():
				(
					assert_bool(cells.has(pid))
					. append_failure_message("%s: %s was not split" % [family, pid])
					. is_true()
				)
			# EVERY placed piece, not only the document's own parts: a room of several is mostly
			# made of the inner parts of a component (ADR 0024), and it is the room that has to
			# come apart in two.
			var pieces: Array = cells.keys()
			pieces.sort()
			for pid: String in pieces:
				var halves: Array[float] = [0.0, 0.0]
				for entry: Dictionary in cells[pid]:
					var cell: PolyMesh = entry["solid"]
					assert_int(cell.open_edges()).is_equal(0)
					halves[0 if (entry["cell"] as Vector3i).z < 2 else 1] += cell.volume()
				var piece: float = (solids[pid] as PolyMesh).volume()
				(
					assert_float(halves[0] + halves[1])
					. append_failure_message(
						"%s: the halves of %s do not make the piece" % [family, pid]
					)
					. is_equal_approx(piece, maxf(piece * 0.02, 0.01))
				)
				# IT COMES APART IN TWO, which is the manufacturing claim - "in manufacturing they
				# are made in 2 pieces" - and is all that can be claimed now.
				#
				# NOT down the middle, and deliberately not: the grid is anchored to the NODE'S OWN
				# BODY, not to the chunk, so that a cut does not move when a neighbour changes what
				# was carved off this piece ([method ShipCsgBake._slice_job]). A chunk is only part
				# of its body, so it sits off-centre in that grid and its halves are uneven -
				# measured, a sphere carbon's p_0007 comes apart 1.55 / 19.75. Evenness was a
				# property of the one grid a room used to share (ADR 0033), and went with it.
				for half: int in 2:
					(
						assert_float(halves[half])
						. append_failure_message(
							(
								"%s: %s has nothing on side %d (%f / %f)"
								% [family, pid, half, halves[0], halves[1]]
							)
						)
						. is_greater(0.0)
					)


func test_every_drawn_mesh_names_its_exterior_and_interior() -> void:
	# The INTERIOR display mode draws a piece's exterior, interior and cut faces differently, so
	# every mesh the bake hands the view carries them as named surfaces. A hollow part has both an
	# exterior and an interior; a cut part has a cut.
	var doc: ShipDoc = _carbon("sphere_pod", true)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	var meshes: Dictionary = report["meshes"]
	var plan: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)
	for pid: String in doc.part_order():
		var mesh: ArrayMesh = meshes[pid]
		(
			assert_int(mesh.surface_find_by_name(ShipCsgBake.SURFACE_EXTERIOR))
			. append_failure_message("%s has no exterior surface" % pid)
			. is_greater_equal(0)
		)
		# A part too thin to have an interior - a tunnel can be - has no interior surface either.
		if (plan["inner"] as Dictionary).has(pid):
			(
				assert_int(mesh.surface_find_by_name(ShipCsgBake.SURFACE_INTERIOR))
				. append_failure_message("%s has no interior surface" % pid)
				. is_greater_equal(0)
			)
		if (doc.parts[pid] as ShipPart).role == ShipPart.ROLE_ROOM and pid == doc.root:
			# The root of an open nucleus carries five holes: cut faces.
			assert_int(mesh.surface_find_by_name(ShipCsgBake.SURFACE_CUT)).is_greater_equal(0)
	# And a room shown whole is there to be drawn, in halves too - once the extras are made.
	var extras: Dictionary = await ShipCsgBake.bake_extras(self, report)
	assert_int((extras["room_shells"] as Dictionary).size()).is_equal(1)
	assert_int((extras["room_meshes"] as Dictionary).size()).is_equal(1)
	# And its cells, for a whole room to come apart like any piece (ADR 0032).
	assert_int((extras["room_cells"] as Dictionary).size()).is_equal(1)


## The assembled bake makes only what the assembled ship shows; the halves and whole rooms wait
## for the first ask, are made from the report without re-baking it, and leave it untouched (ADR
## 0030). "yes" - the author, 2026-09-21, to the first EXPLODE after an update taking its time.
func test_the_assembled_bake_leaves_the_extras_for_the_first_ask() -> void:
	var doc: ShipDoc = _carbon("sphere_pod", true)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	assert_bool(bool(report[ShipCsgBake.EXTRAS_READY])).is_false()
	assert_bool(report.has("cells") or report.has("room_shells")).is_false()
	var extras: Dictionary = await ShipCsgBake.bake_extras(self, report)
	assert_bool(bool(extras[ShipCsgBake.EXTRAS_READY])).is_true()
	# The report it was made from is not touched: the extras are a copy with them in.
	assert_bool(report.has("cells")).is_false()
	assert_bool(bool(report[ShipCsgBake.EXTRAS_READY])).is_false()
	# The pieces are the SAME pieces - the extras slice them, they do not bake them again.
	assert_bool(is_same(extras["solids"], report["solids"])).is_true()
	var halves: Dictionary = extras["cells"]
	for pid: String in report["solids"] as Dictionary:
		assert_bool(halves.has(pid)).append_failure_message("%s was not halved" % pid).is_true()
	# A report that never reached the engine comes back ready with nothing to add.
	var empty: Dictionary = await ShipCsgBake.bake_extras(self, {})
	assert_bool(bool(empty[ShipCsgBake.EXTRAS_READY])).is_true()
	assert_bool(empty.has("cells")).is_false()


## The bake reports its progress in order - a bar has something to move with (ADR 0023).
func test_the_bake_reports_progress_in_order() -> void:
	var doc: ShipDoc = _carbon("sphere_pod", true)
	var ticks: Array[float] = []
	var labels: PackedStringArray = PackedStringArray()
	var progress: Callable = func(fraction: float, label: String) -> void:
		ticks.append(fraction)
		labels.append(label)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg, progress)
	# Every placed id bakes - the nucleus component's inner parts included (ADR 0024).
	var placed: int = ShipAttach.resolve_all(doc, _data, _cfg).size()
	assert_int((report["solids"] as Dictionary).size()).is_equal(placed)
	assert_int(ticks.size()).append_failure_message("ticks: %s" % [str(ticks)]).is_greater_equal(4)
	for i: int in range(1, ticks.size()):
		(
			assert_float(ticks[i])
			. append_failure_message("tick %d of %s went backwards" % [i, str(ticks)])
			. is_greater_equal(ticks[i - 1])
		)
	assert_float(ticks[0]).is_less(0.2)
	assert_float(ticks[ticks.size() - 1]).is_greater_equal(0.9)
	assert_bool(labels.has("PIECES")).is_true()


## Every hatched seam is BORED through both of its pieces and every rim comes out CAPPED (ADR
## 0029): "where we cut holes for hatches, and openings, we need those manifold meshes to cap the
## exposed open hole edges." Eight doors on a carbon, twelve pieces bored, none open, and a
## tunnel with a hole at each end holds less hull than its plain shell.
func test_every_hatched_seam_is_bored_through_both_pieces_and_capped() -> void:
	var doc: ShipDoc = _carbon("sphere_pod", true)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	assert_int((report["doors"] as Array).size()).is_equal(8)
	var bored: PackedStringArray = report["bored"]
	(
		assert_int(bored.size())
		. append_failure_message("bored %s, failed %s" % [str(bored), str(report["door_failed"])])
		. is_equal(12)
	)
	assert_int((report["door_failed"] as PackedStringArray).size()).is_equal(0)
	var solids: Dictionary = report["solids"]
	for pid: String in bored:
		var piece: PolyMesh = solids[pid]
		(
			assert_int(piece.open_edges())
			. append_failure_message("%s came out of its boring open" % pid)
			. is_equal(0)
		)
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.role != ShipPart.ROLE_HALLWAY:
			continue
		assert_bool(bored.has(pid)).append_failure_message("%s not bored" % pid).is_true()
		var whole: float = _whole_shell(doc, pid)
		# Two crawlway bores of about 0.38 m2 through a 0.1 m cap each (measured: 0.0376 m3 a
		# bore on the tessellated cap), less the two gasket collars that bridge the cap's dome
		# to the frame's flat ring (measured: 0.005 m3 each): over 0.05 m3 gone.
		(
			assert_float((solids[pid] as PolyMesh).volume())
			. append_failure_message("tunnel %s kept its end caps" % pid)
			. is_less(whole - 0.05)
		)
	# The drawn mesh names the rims: the CUT surface carries faces the walled bake had none of.
	var meshes: Dictionary = report["meshes"]
	var tunnel: ArrayMesh = meshes[bored[0]]
	assert_int(tunnel.surface_find_by_name(ShipCsgBake.SURFACE_CUT)).is_greater_equal(0)


## A class imported as components is built at the HOST ship's dimensions (ADR 0026): a carbon
## built with an 8 m proton span and a 2.2 m bore hands those numbers back, and the class rebuilt
## from them has the same proton.
func test_an_imported_class_is_built_at_the_host_ships_dimensions() -> void:
	var options: Dictionary = {
		ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod",
		ShipTemplates.OPT_ROOM_SPAN: 8.0,
		ShipTemplates.OPT_TUNNEL_BORE: 2.2,
		ShipTemplates.OPT_TUNNEL_LENGTH: 5.0,
	}
	var host: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", options)
	var derived: Dictionary = ShipComponentImport.template_options(host, _data)
	assert_str(str(derived.get(ShipTemplates.OPT_ROOM_FAMILY, ""))).is_equal("sphere_pod")
	assert_float(float(derived.get(ShipTemplates.OPT_ROOM_SPAN, 0.0))).is_equal_approx(8.0, 0.05)
	assert_float(float(derived.get(ShipTemplates.OPT_TUNNEL_BORE, 0.0))).is_equal_approx(2.2, 0.05)
	var rebuilt: ShipDoc = ShipTemplates.build(_data, _cfg, "carbon", derived)
	var host_shapes: Dictionary = ShipAttach.resolve_shapes(host, _data, _cfg)
	var rebuilt_shapes: Dictionary = ShipAttach.resolve_shapes(rebuilt, _data, _cfg)
	var host_span: float = (host_shapes[host.root] as ResolvedShape).local_aabb().size.x
	var rebuilt_span: float = (rebuilt_shapes[rebuilt.root] as ResolvedShape).local_aabb().size.x
	assert_float(rebuilt_span).is_equal_approx(host_span, 0.01)


## THE AUTHOR'S OWN CHECK (2026-09-22): "6 cubes overlaping about the center should not be leaving
## messy edges between their seams and all should be exact copies of one another". Six equal bodies
## ringing the beacon (ADR 0034) come out as six pieces of one volume, cut on flat planes, and they
## still add up to the room they came from.
func test_a_clump_of_equal_bodies_comes_out_as_pieces_of_one_size() -> void:
	var doc: ShipDoc = ShipTemplates.build(
		_data, _cfg, "carbon", _linked({ShipTemplates.OPT_ROOM_FAMILY: "box_hull"})
	)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	var solids: Dictionary = report["solids"]
	var nucleus: PackedStringArray = PackedStringArray()
	for members: PackedStringArray in report["rooms"]:
		if members.size() > nucleus.size():
			nucleus = members
	assert_int(nucleus.size()).is_equal(6)
	var total: float = 0.0
	var volumes: Dictionary = {}
	for id: String in nucleus:
		volumes[id] = (solids[id] as PolyMesh).volume()
		total += float(volumes[id])
	var mean: float = total / float(nucleus.size())
	for id: String in nucleus:
		# One per cent: four of the six carry a tunnel socket, which is real geometry, not a
		# difference in how the piece was cut. Before the planes they ranged over 20 per cent.
		(
			assert_float(float(volumes[id]))
			. append_failure_message(
				"%s is %.2f m3 against a mean of %.2f" % [id, volumes[id], mean]
			)
			. is_equal_approx(mean, mean * 0.01)
		)
		assert_int((solids[id] as PolyMesh).open_edges()).append_failure_message(id).is_equal(0)


## THE SEAM SPLIT (ADR 0036). A room is finished as one body - its hatches bored while it is whole -
## and only then broken into its members' pieces, each capped from its inner seam loop to its outer
## one. "the proper way is to union all primatave shapes together, then cut them along the shape of
## interior seam to exterior seam" (2026-09-22).
##
## The claim is exactness: the pieces PARTITION the room. Nothing is owned twice, nothing is owned
## by nobody, and every piece is a solid the engine will take - closed, and with every edge shared
## by exactly two faces, which "closed" alone does not promise.
func test_a_cube_nucleus_divides_at_its_seams() -> void:
	var doc: ShipDoc = ShipTemplates.build(
		_data, _cfg, "carbon", _linked({ShipTemplates.OPT_ROOM_FAMILY: "box_hull"})
	)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	(
		assert_int(int(report[ShipCsgBake.SPLIT_ROOMS]))
		. append_failure_message("the nucleus fell back to the older cut-back")
		. is_equal(1)
	)
	assert_int(int(report[ShipCsgBake.CUT_BACK_ROOMS])).is_equal(0)
	var nucleus: PackedStringArray = PackedStringArray()
	for members: PackedStringArray in report["rooms"]:
		if members.size() > nucleus.size():
			nucleus = members
	assert_int(nucleus.size()).is_equal(6)

	var solids: Dictionary = report["solids"]
	var total: float = 0.0
	for id: String in nucleus:
		var piece: PolyMesh = solids[id]
		total += piece.volume()
		(
			assert_bool(MeshSeamSplit.is_sound(piece))
			. append_failure_message("%s is not a solid the engine will take" % id)
			. is_true()
		)
	# THE PARTITION. Six bodies that overlap deeply cannot come to six WHOLE shells between them
	# unless something is owned twice; measured by hand, the pieces come to the room's own 159.99 m3
	# exactly, and the cheap form of that claim here is that they come to well under the six.
	var whole: float = 0.0
	for id: String in nucleus:
		whole += _whole_shell(doc, id)
	(
		assert_float(total)
		. append_failure_message(
			"the pieces come to %.2f m3 of six whole shells' %.2f" % [total, whole]
		)
		. is_less(whole * 0.85)
	)
	# And on a clump this symmetric they are the same piece, which is the author's own check.
	var mean: float = total / float(nucleus.size())
	for id: String in nucleus:
		(
			assert_float((solids[id] as PolyMesh).volume())
			. append_failure_message("%s stands apart from its six" % id)
			. is_equal_approx(mean, mean * 0.01)
		)


## EVERY BAKED SOLID IS WOUND OUTWARD (ADR 0037). This is the invariant the whole bake rests on
## and the one nothing could see: the engine hands its triangles back the other way round, and for
## the life of the project they were read as-is, so every piece was inside out. An inside-out solid
## goes back to the engine as its own COMPLEMENT - a cut through a hollow piece came back with a
## solid lid over the cavity rather than a ring, which the author reported as slabs hanging inside
## the rooms - and draws with its outside culled away. [method PolyMesh.volume] is absolute and
## cannot catch it, so this asserts on the sign.
func test_every_baked_solid_is_wound_outward() -> void:
	var doc: ShipDoc = _carbon("box_hull", true)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	var solids: Dictionary = report["solids"]
	assert_int(solids.size()).is_greater(0)
	for id: String in solids:
		var solid: PolyMesh = solids[id]
		(
			assert_float(solid.signed_volume())
			. append_failure_message("%s came out of the bake INSIDE OUT" % id)
			. is_greater(0.0)
		)


## AND A CUT THROUGH ONE LEAVES A RING, NOT A LID (ADR 0037) - which is the same invariant said in
## the terms the cell slicer cares about, because that is where the author saw it go wrong. Half a
## hollow piece is half its volume; a piece the engine reads inside out came back at two thirds.
func test_a_piece_cut_in_half_is_half_of_it() -> void:
	var doc: ShipDoc = _carbon("box_hull", true)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	var members: PackedStringArray = PackedStringArray()
	for list: PackedStringArray in report["rooms"]:
		if list.size() > members.size():
			members = list
	var piece: PolyMesh = report["solids"][members[0]]
	var box: AABB = piece.aabb()
	var combiner := CSGCombiner3D.new()
	ShipCsgBake._add_engine_mesh(combiner, piece.to_array_mesh(), CSGShape3D.OPERATION_UNION)
	var keep := CSGBox3D.new()
	keep.size = box.size * 4.0
	keep.position = box.get_center() - Vector3(0.0, 0.0, box.size.z * 2.0)
	keep.operation = CSGShape3D.OPERATION_INTERSECTION
	combiner.add_child(keep)
	add_child(combiner)
	await ShipCsgBake._until_ready(self, [combiner])
	var half: PolyMesh = ShipCsgBake._read_raw(ShipCsgBake._engine_mesh(combiner))
	combiner.queue_free()
	(
		assert_float(half.volume())
		. append_failure_message(
			"half of %.3f m3 came back as %.3f" % [piece.volume(), half.volume()]
		)
		. is_equal_approx(piece.volume() * 0.5, piece.volume() * 0.02)
	)
	assert_float(half.signed_volume()).is_greater(0.0)
	assert_int(half.open_edges()).is_equal(0)


## THE TIDY-UP MUST NOT UNDO THE GATE. `MeshSeamSplit.is_sound` approves a piece, and `_tidy` then
## merges its coplanar fragments into n-gons - and a merge can leave an edge on three faces where
## the fragments met a third surface along the same line. Measured on a NEON of cube rooms, which
## is why the test is a neon and not the carbon everything else here uses: `p_0009/cp_0002` passed
## the gate at 1388 faces with every edge on two, and came out of the merge at 507 faces with two
## edges on three. A non-manifold solid is what the engine mis-cuts (ADR 0037).
func test_the_merge_never_breaks_a_piece_the_gate_passed() -> void:
	var doc: ShipDoc = ShipTemplates.build(
		_data, _cfg, "neon", _linked({ShipTemplates.OPT_ROOM_FAMILY: "box_hull"})
	)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	var members: PackedStringArray = PackedStringArray()
	for list: PackedStringArray in report["rooms"]:
		if list.size() > members.size():
			members = list
	assert_int(members.size()).is_greater(2)
	for id: String in members:
		var piece: PolyMesh = report["solids"][id]
		(
			assert_bool(MeshSeamSplit.is_sound(piece))
			. append_failure_message(
				"%s left the bake non-manifold or open (%d faces)" % [id, piece.face_count()]
			)
			. is_true()
		)


func test_the_wall_layer_is_named_and_tracks_the_seams() -> void:
	# "walls should be isolated from the shape its actually apart of, such that when walls layer
	# is removed you see an open room" (2026-09-25, ADR 0046). A walled seam authors no plate -
	# the two cavities simply do not merge - so the wall is the INDENTED part's own cavity face
	# standing where its neighbour's grown body pushed in, and naming it is what lets a view drop
	# it. The test the layer has to pass is that it tracks the seams and nothing else: no walled
	# seam, no wall.
	var opened: ShipDoc = _carbon("box_hull", true)
	_all_seams(opened, ShipJoint.MODE_OPEN)
	var open_report: Dictionary = await ShipCsgBake.bake(self, opened, _data, _cfg)
	(
		assert_float(_surface_area(open_report, ShipCsgBake.SURFACE_WALL))
		. append_failure_message("every seam open, so no face of any piece is a wall")
		. is_equal_approx(0.0, 0.0001)
	)

	# Sealed, every one of those seams stands a wall, and it is a real area rather than a sliver.
	var sealed: ShipDoc = _carbon("box_hull", false)
	var walls: float = _surface_area(
		await ShipCsgBake.bake(self, sealed, _data, _cfg), ShipCsgBake.SURFACE_WALL
	)
	(
		assert_float(walls)
		. append_failure_message("every seam sealed, so every one of them stands a wall")
		. is_greater(100.0)
	)


## THE WHOLE POINT OF THE NEW DEFAULT, measured on the baked meshes rather than on the document:
## a carbon out of the picker has no wall face anywhere on it. The author, 2026-09-26: "by default
## in the prebuilds we dont want any walls in our prebuilds by default."
func test_a_prebuild_bakes_with_no_wall_anywhere() -> void:
	for family: String in ["sphere_pod", "box_hull"]:
		var doc: ShipDoc = ShipTemplates.build(
			_data, _cfg, "carbon", {ShipTemplates.OPT_ROOM_FAMILY: family}
		)
		var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
		(
			assert_float(_surface_area(report, ShipCsgBake.SURFACE_WALL))
			. append_failure_message("%s: a prebuild came out with walls on it" % family)
			. is_equal_approx(0.0, 0.0001)
		)
