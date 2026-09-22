# The exact bake the player sees: core's plan, carried out by the engine's CSG (ADR 0020).
#
# Every test here builds on SPHERE pods - the family the author builds with - and on boxes, and
# reads the result the way the exploded view will: one closed solid per part. A gdUnit suite is a
# Node, so it can host the CSG nodes and await the frame they compute on.
class_name TestCsgBake
extends GdUnitTestSuite

var _data: ShipData
var _cfg: ShipConfig


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
		_data, _cfg, "carbon", {ShipTemplates.OPT_ROOM_FAMILY: family}
	)
	if not open_nucleus:
		assert_int(ShipComponents.dissolve(doc, doc.root).size()).is_equal(6)
		# The definition's open links come back with the protons (ADR 0025); walled means walled.
		for jid: String in doc.joints.keys():
			if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_OPEN:
				doc.joints.erase(jid)
	return doc


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
			# The default slicing (ADR 0031) is the old one: every piece bisected across its Z.
			var report: Dictionary = await ShipCsgBake.bake_extras(self, assembled)
			var halves: Dictionary = report["chunks"]
			var solids: Dictionary = report["solids"]
			for pid: String in doc.part_order():
				(
					assert_bool(halves.has(pid))
					. append_failure_message("%s: %s was not split" % [family, pid])
					. is_true()
				)
				var pair: Array = halves[pid]
				assert_int(pair.size()).is_equal(2)
				var a: PolyMesh = pair[0]
				var b: PolyMesh = pair[1]
				assert_object(a).is_not_null()
				assert_object(b).is_not_null()
				assert_int(a.open_edges() + b.open_edges()).is_equal(0)
				var piece: float = (solids[pid] as PolyMesh).volume()
				(
					assert_float(a.volume() + b.volume())
					. append_failure_message(
						"%s: the halves of %s do not make the piece" % [family, pid]
					)
					. is_equal_approx(piece, maxf(piece * 0.02, 0.01))
				)
				# Down the MIDDLE: neither half is a sliver.
				assert_float(minf(a.volume(), b.volume())).is_greater(piece * 0.2)


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
	assert_int((extras["room_chunk_meshes"] as Dictionary).size()).is_equal(1)
	# The PolyMesh slices too: the view reads them to explode a whole room apart (ADR 0030/0031).
	assert_int((extras["room_chunks"] as Dictionary).size()).is_equal(1)


## The assembled bake makes only what the assembled ship shows; the halves and whole rooms wait
## for the first ask, are made from the report without re-baking it, and leave it untouched (ADR
## 0030). "yes" - the author, 2026-09-21, to the first EXPLODE after an update taking its time.
func test_the_assembled_bake_leaves_the_extras_for_the_first_ask() -> void:
	var doc: ShipDoc = _carbon("sphere_pod", true)
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	assert_bool(bool(report[ShipCsgBake.EXTRAS_READY])).is_false()
	assert_bool(report.has("chunks") or report.has("room_shells")).is_false()
	var extras: Dictionary = await ShipCsgBake.bake_extras(self, report)
	assert_bool(bool(extras[ShipCsgBake.EXTRAS_READY])).is_true()
	# The report it was made from is not touched: the extras are a copy with them in.
	assert_bool(report.has("chunks")).is_false()
	assert_bool(bool(report[ShipCsgBake.EXTRAS_READY])).is_false()
	# The pieces are the SAME pieces - the extras slice them, they do not bake them again.
	assert_bool(is_same(extras["solids"], report["solids"])).is_true()
	var halves: Dictionary = extras["chunks"]
	for pid: String in report["solids"] as Dictionary:
		assert_bool(halves.has(pid)).append_failure_message("%s was not halved" % pid).is_true()
	# A report that never reached the engine comes back ready with nothing to add.
	var empty: Dictionary = await ShipCsgBake.bake_extras(self, {})
	assert_bool(bool(empty[ShipCsgBake.EXTRAS_READY])).is_true()
	assert_bool(empty.has("chunks")).is_false()


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
