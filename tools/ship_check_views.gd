class_name ShipCheckViews
extends RefCounted

## The windowed checks for how the builder RENDERS and what can be clicked - split out of
## `tools/ship_visual_check.gd`, which is at gdlint's 2000-line file cap. ADR 0009.
##
## Every one of these exists because the opposite shipped and the author had to report it:
## "exploded view does not let part selection, and doesnt render it anything other then flat",
## "i dont see Fresnel node under the render types", and the seam menu they asked for by name.
##
## Shares the tool's `failures` array by reference - appending here is appending there - so the
## report at the end of a run reads as one list however many files produced it.

var _builder: Node = null
var _failures: PackedStringArray = PackedStringArray()


func _init(builder: Node, failures: PackedStringArray) -> void:
	_builder = builder
	_failures = failures


## What went wrong in here. The same list the caller holds - a PackedStringArray handed to a
## function is SHARED, not copied (measured: merging it back doubled every line) - so this is
## for reading, never for merging.
func failures() -> PackedStringArray:
	return _failures


func check_fresnel(histograms: Array, palette: PackedStringArray, mode_names: Array) -> void:
	var fresnel: int = mode_names.find("fresnel")
	var shaded: int = mode_names.find("shaded_wire")
	if fresnel < 0 or shaded < 0 or histograms.size() <= maxi(fresnel, shaded):
		_failures.append("fresnel: no captured frame to compare")
		return
	var a: Dictionary = histograms[shaded]["counts"]
	var b: Dictionary = histograms[fresnel]["counts"]
	var background: String = palette[0] if not palette.is_empty() else "081216"
	var moved: int = 0
	var ink: int = 0
	var keys: Dictionary = {}
	for key: Variant in a.keys():
		keys[key] = true
	for key: Variant in b.keys():
		keys[key] = true
		if String(key) != background:
			ink += int(b[key])
	for key: Variant in keys.keys():
		moved += absi(int(a.get(key, 0)) - int(b.get(key, 0)))
	if ink <= 0:
		_failures.append("fresnel: nothing but background in the frame")
		return
	var share: float = float(moved) * 0.5 / float(ink)
	if share < 0.15:
		(
			_failures
			. append(
				(
					(
						"fresnel: only %.1f%% of the ship differs from SHADED+WIRE - the mode is in the "
						+ "dropdown but renders the same thing"
					)
					% (share * 100.0)
				)
			)
		)
	else:
		print("  fresnel: %.1f%% of the ship differs from SHADED+WIRE" % (share * 100.0))


func check_explode_picking(explode: Object) -> void:
	var view: Object = _builder.call("get_view")
	var cam: Camera3D = view.call("get_orbit_camera").call("get_camera")
	var nodes: Array = explode.call("module_nodes")
	if cam == null or nodes.is_empty():
		_failures.append("explode: no module to click")
		return
	var doc: ShipDoc = _builder.call("get_doc")
	var before: PackedStringArray = _builder.call("get_selection")
	var target: MeshInstance3D = null
	var want: String = ""
	for node: MeshInstance3D in nodes:
		var id: String = str(node.name).replace(ShipExplodeView.NODE_PREFIX, "")
		if doc.parts.has(id) and not before.has(id):
			target = node
			want = id
			break
	if target == null:
		print("  explode: no unselected module to click; picking not exercised")
		return
	var centre: Vector3 = target.transform * target.mesh.get_aabb().get_center()
	if cam.is_position_behind(centre):
		print("  explode: the module to click is behind the camera; picking not exercised")
		return
	var at: Vector2 = cam.unproject_position(centre)
	view.call("_explode_left_button", _mouse(at, true))
	view.call("_explode_left_button", _mouse(at, false))
	view.call("_physics_process", 0.016)
	var after: PackedStringArray = _builder.call("get_selection")
	if after.has(want):
		print("  explode: clicking a module selected %s" % want)
	else:
		(
			_failures
			. append(
				(
					(
						"explode: clicking module %s at %s selected %s.\n"
						+ "    screen ray: %s\n"
						+ "    ray straight at it: %s\n"
						+ "    its pick body: %s\n"
						+ "    an assembled part's body: %s"
					)
					% [
						want,
						str(at),
						str(after),
						_describe_ray(view, cam.project_ray_origin(at), cam.project_ray_normal(at)),
						_describe_ray(
							view, cam.global_position, (centre - cam.global_position).normalized()
						),
						_describe_body(explode, want),
						_describe_part_ray(view, cam),
					]
				)
			)
		)
	if not bool(_builder.get("_exploded")):
		_failures.append("explode: selecting a module assembled the ship")


func _describe_ray(view: Object, from: Vector3, dir: Vector3) -> String:
	var space: PhysicsDirectSpaceState3D = view.call("_space_state")
	if space == null:
		return "could not be cast: the view has no physics space"
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * 10000.0, ShipSceneBuilder.PICK_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return "hit NO body on the pick layer"
	var collider: Node = hit.get("collider", null)
	var name: String = str(collider.name) if collider != null else "<null>"
	var meta: String = "none"
	if collider != null and collider.has_meta(ShipSceneBuilder.PART_META):
		meta = str(collider.get_meta(ShipSceneBuilder.PART_META))
	return "hit '%s' (part meta '%s')" % [name, meta]


func _describe_body(explode: Object, id: String) -> String:
	var body: StaticBody3D = explode.call("module_body", id)
	if body == null:
		return "there is no pick body for this module at all"
	var shape: Shape3D = null
	for child: Node in body.get_children():
		var cs: CollisionShape3D = child as CollisionShape3D
		if cs != null:
			shape = cs.shape
	var faces: int = -1
	if shape is ConcavePolygonShape3D:
		faces = (shape as ConcavePolygonShape3D).get_faces().size()
	return (
		"in_tree=%s layer=%d parent=%s shape=%s faces=%d at=%s"
		% [
			str(body.is_inside_tree()),
			body.collision_layer,
			str(body.get_parent().name) if body.get_parent() != null else "<none>",
			"<null>" if shape == null else shape.get_class(),
			faces,
			str(body.global_position) if body.is_inside_tree() else str(body.position),
		]
	)


func _describe_part_ray(view: Object, cam: Camera3D) -> String:
	var scene: Object = view.call("get_scene_builder")
	var doc: ShipDoc = _builder.call("get_doc")
	if scene == null or doc == null:
		return "could not be tested"
	var at: Vector3 = (scene.call("part_transform", doc.root) as Transform3D).origin
	return _describe_ray(view, cam.global_position, (at - cam.global_position).normalized())


## The material a module's first surface ACTUALLY wears. A piece whose WALLS layer is dropped
## (ADR 0046) carries its materials per surface, because a `material_override` beats a per-surface
## one and the wall could never be dropped otherwise - so reading the override alone reports null
## for every render type and the switch reads as a no-op. Surface 0 is the exterior wherever a
## piece has one (`PolyMesh.to_array_mesh_grouped` orders them exterior, interior, cut, wall).
##
## RETIRED(ADR 0046): `solid.material_override` on its own, which is what this checked until the
## walls became a layer - and it failed the moment they did, which is the tool working.
static func _module_material(solid: MeshInstance3D) -> Material:
	if solid.mesh != null and solid.get_surface_override_material_count() > 0:
		var per_surface: Material = solid.get_surface_override_material(0)
		if per_surface != null:
			return per_surface
	return solid.material_override


func check_explode_display_mode(explode: Object) -> void:
	var view: Object = _builder.call("get_view")
	var nodes: Array = explode.call("module_nodes")
	if nodes.is_empty():
		return
	var solid: MeshInstance3D = nodes[0]
	var started: int = int(view.call("get_display_mode"))
	var other: int = ShipSceneBuilder.DisplayMode.FLAT
	if started == other:
		other = ShipSceneBuilder.DisplayMode.FRESNEL
	var before: Material = _module_material(solid)
	view.call("set_display_mode", other)
	if _module_material(solid) == before:
		(
			_failures
			. append(
				(
					"explode: switching the render type from %d to %d left the module material unchanged"
					% [started, other]
				)
			)
		)
	# WIREFRAME must hide the solid and show the wire, exactly as it does for a part.
	view.call("set_display_mode", ShipSceneBuilder.DisplayMode.WIREFRAME)
	var wire_ok: bool = not solid.visible
	if not wire_ok:
		_failures.append("explode: the module solid is still visible in WIREFRAME")
	view.call("set_display_mode", ShipSceneBuilder.DisplayMode.SHADED_WIRE)
	if not solid.visible:
		_failures.append("explode: the module solid did not come back in SHADED+WIRE")
	elif wire_ok:
		print("  explode: modules follow the render type (%d, wireframe, shaded+wire)" % other)


func _mouse(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.pressed = pressed
	return ev


func check_seam_menu() -> void:
	var view: Object = _builder.call("get_view")
	# Asked of the feature, not of the builder: the seam styles moved to ShipSeamMenu on
	# 2026-09-27 and took `_context_menu` with them (F40 on tool-reached members).
	var seam: Object = _builder.get("_seam_menu")
	var menu: Object = seam.menu() if seam != null else null
	var doc: ShipDoc = _builder.call("get_doc")
	if view == null or menu == null or doc == null:
		_failures.append("seam menu: nothing to drive")
		return
	# A real parent/child pair, so the styles mean something.
	var child: String = ""
	for pid: String in doc.parts:
		var part: ShipPart = doc.parts[pid]
		if not part.parent.is_empty() and part.parent == doc.root:
			child = pid
			break
	if child == "":
		_failures.append("seam menu: no child of the root to pair with it")
		return
	_builder.call("set_selection", PackedStringArray([doc.root, child]))
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.position = Vector2(120.0, 120.0)
	ev.pressed = true
	view.call("_track_right_button", ev)
	ev.pressed = false
	view.call("_track_right_button", ev)
	if not bool(menu.call("is_open")):
		_failures.append("seam menu: a right click on two selected parts opened nothing")
		return
	var applied: PackedStringArray = PackedStringArray()
	for style: String in [
		ShipJoint.SEAM_BIG_NATIVE,
		ShipJoint.SEAM_SMALL_NATIVE,
		ShipJoint.SEAM_SMALL_FLAT_INSERT,
		ShipJoint.SEAM_BIG_FLAT_CUTOFF,
	]:
		if not bool(menu.call("press", style)):
			_failures.append("seam menu: no item for style '%s'" % style)
			continue
		var got: String = ShipSeams.style_for(_builder.call("get_doc"), doc.root, child)
		if got != style:
			_failures.append("seam menu: choosing '%s' left the seam '%s'" % [style, got])
		else:
			applied.append(style)
		# Re-open for the next one; the menu closes on every choice, as a menu should.
		ev.pressed = true
		view.call("_track_right_button", ev)
		ev.pressed = false
		view.call("_track_right_button", ev)
	menu.call("close")
	print("  seam menu: opened on a right click, applied %s" % str(applied))
	_check_multi_seam(view, menu, doc)


## Selecting MORE than two parts and restyling every connection between them at once (ADR 0013).
##
## The point of the feature is that it works when the seams DISAGREE, so the two are deliberately
## set to different styles first and then swept together.
func _check_multi_seam(view: Object, menu: Object, doc: ShipDoc) -> void:
	# A chain of three: the root, a child of it, and a child of that.
	var first: String = ""
	var second: String = ""
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.parent == doc.root and first.is_empty():
			first = pid
		elif not first.is_empty() and part.parent == first:
			second = pid
			break
	if first.is_empty() or second.is_empty():
		print("  multi seam: no three-part chain in this doc, skipped")
		return

	var builder: Object = _builder
	builder.call("set_selection", PackedStringArray([doc.root, first]))
	_press_seam(view, menu, ShipJoint.SEAM_BIG_NATIVE)
	builder.call("set_selection", PackedStringArray([first, second]))
	_press_seam(view, menu, ShipJoint.SEAM_SMALL_FLAT_CUTOFF)
	var before_a: String = ShipSeams.style_for(builder.call("get_doc"), first, doc.root)
	var before_b: String = ShipSeams.style_for(builder.call("get_doc"), second, first)
	if before_a == before_b:
		_failures.append("multi seam: could not make the two seams differ to begin with")
		return

	# All three selected at once, so both connections are in the selection.
	builder.call("set_selection", PackedStringArray([doc.root, first, second]))
	if not _press_seam(view, menu, ShipJoint.SEAM_SMALL_NATIVE):
		_failures.append("multi seam: the menu did not open over a three-part selection")
		return
	var after_a: String = ShipSeams.style_for(builder.call("get_doc"), first, doc.root)
	var after_b: String = ShipSeams.style_for(builder.call("get_doc"), second, first)
	if after_a != ShipJoint.SEAM_SMALL_NATIVE or after_b != ShipJoint.SEAM_SMALL_NATIVE:
		_failures.append(
			"multi seam: one press left the two seams '%s' and '%s'" % [after_a, after_b]
		)
		return
	# And it must be ONE edit, so a single undo puts both back.
	builder.call("undo")
	var undone_a: String = ShipSeams.style_for(builder.call("get_doc"), first, doc.root)
	var undone_b: String = ShipSeams.style_for(builder.call("get_doc"), second, first)
	if undone_a != before_a or undone_b != before_b:
		_failures.append(
			(
				"multi seam: one undo left '%s'/'%s', not '%s'/'%s'"
				% [undone_a, undone_b, before_a, before_b]
			)
		)
		return
	print(
		(
			"  multi seam: two differing seams (%s, %s) swept to %s in one press, one undo restored both"
			% [before_a, before_b, ShipJoint.SEAM_SMALL_NATIVE]
		)
	)


## Right-clicks the current selection and presses `style`. False when the menu did not open.
func _press_seam(view: Object, menu: Object, style: String) -> bool:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.position = Vector2(120.0, 120.0)
	ev.pressed = true
	view.call("_track_right_button", ev)
	ev.pressed = false
	view.call("_track_right_button", ev)
	if not bool(menu.call("is_open")):
		return false
	var pressed: bool = bool(menu.call("press", style))
	menu.call("close")
	return pressed


## The baked view after UPDATE MESHES (ADR 0023), read back off the scene: the baked view up
## and assembled, as many module meshes as the field has modules and every one at its own place
## (no offsets), the button no longer lit, the bar down, every part visual hidden, the ghost
## carrying the ship's parts - and, on leaving the baked view, the primitives back.
func check_update_finish(view: Object, scene: Object, explode: Object, expected: int) -> void:
	if not bool(_builder.get("_baked")) or not bool(view.call("is_baked")):
		_failures.append("update: the baked view did not come up")
	if not bool(explode.call("is_assembled")):
		_failures.append("update: the modules are exploded, not assembled")
	var count: int = int(explode.call("module_count"))
	if count != expected:
		_failures.append(
			"update: %d module meshes on screen, the field has %d modules" % [count, expected]
		)
	var nodes: Array = explode.call("module_nodes")
	for node: MeshInstance3D in nodes:
		if node.transform.origin.length() > 1.0e-4:
			_failures.append("update: module %s is offset in the assembled view" % node.name)
			break
	var button: Button = _builder.get("_update_button")
	if button != null and button.text.ends_with("*"):
		_failures.append("update: the button is still lit after the update")
	var bar: ProgressBar = _builder.get("_progress")
	if bar != null and bar.visible:
		_failures.append("update: the progress bar is still up after the update")
	if _shown_visuals(scene) != 0:
		_failures.append("update: part visuals are still visible under the baked view")
	_builder.call("_set_baked", false)
	if bool(_builder.get("_baked")) or int(explode.call("module_count")) != 0:
		_failures.append("update: leaving the baked view left modules behind")
	var shown: int = _shown_visuals(scene)
	if shown == 0:
		_failures.append("update: no part visual came back after leaving the baked view")
	print(
		(
			"  update: %d modules baked assembled, button lit then cleared, %d visuals back"
			% [count, shown]
		)
	)


func _shown_visuals(scene: Object) -> int:
	var visuals: Dictionary = scene.get("_visuals")
	var shown: int = 0
	for key: Variant in visuals.keys():
		var solid: MeshInstance3D = visuals[key].get("solid")
		if solid != null and solid.visible:
			shown += 1
	return shown


## How many modules the exact bake makes of [param doc] right now: one per placed id, a
## component's inner pieces included (ADR 0024).
func module_count(doc: ShipDoc) -> int:
	var data: ShipData = _builder.call("get_data")
	var cfg: ShipConfig = _builder.call("get_config")
	var sdf: ShipSdf = ShipSdf.build(doc, data, cfg)
	return sdf.part_count()


## ISOLATION (ADR 0024): a leaf part is lifted into a component of its own; opening the
## instance washes every visual outside it out and leaves its own alone; a pick body inside
## resolves to the inner part; ESC (cancel_placement) closes it and the materials come back.
func check_isolation() -> void:
	var doc: ShipDoc = _builder.call("get_doc")
	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder") if view != null else null
	if doc == null or scene == null:
		return
	# A small subtree - a part whose children are all leaves - so the instance has inner parts
	# and the pick inside it has something to resolve to.
	var head: String = ""
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if pid == doc.root or part.is_mirror() or part.kind == ShipPart.KIND_COMPONENT_INSTANCE:
			continue
		var kids: PackedStringArray = doc.children_of(pid)
		if kids.is_empty():
			continue
		var shallow: bool = true
		for kid: String in kids:
			if not doc.children_of(kid).is_empty() or (doc.parts[kid] as ShipPart).is_mirror():
				shallow = false
		if shallow:
			head = pid
			break
	if head == "":
		_failures.append("isolation: no shallow subtree to lift")
		return
	var lifted: PackedStringArray = PackedStringArray([head])
	lifted.append_array(doc.children_of(head))
	_builder.call("begin_edit", "lift for isolation")
	var component_id: String = ShipComponents.make_component(doc, lifted, "ISO")
	_builder.call("commit_edit", PackedStringArray())
	var instance: String = ""
	for pid: String in doc.part_order():
		var part: ShipPart = doc.parts[pid]
		if part.kind == ShipPart.KIND_COMPONENT_INSTANCE and part.family == component_id:
			instance = pid
			break
	if instance == "":
		_failures.append("isolation: no component instance to open")
		return
	_builder.call("_isolate", instance)
	if str(scene.get("_isolated")) != instance:
		_failures.append("isolation: the scene did not open %s" % instance)
	var visuals: Dictionary = scene.get("_visuals")
	var washed: int = 0
	var kept: int = 0
	var inner_pick: String = ""
	for key: Variant in visuals.keys():
		var v: Object = visuals[key]
		var solid: MeshInstance3D = v.get("solid")
		var pid: String = str(v.get("pid"))
		var inside: bool = ShipSymmetry.source_of_twin(ShipComponents.instance_of(pid)) == instance
		if solid == null:
			continue
		if inside:
			kept += 1
			if inner_pick == "" and ShipComponents.is_expanded_id(pid):
				var body: Node = v.get("body")
				if body != null:
					inner_pick = str(scene.call("part_id_for", body))
		elif solid.material_override == scene.get("_washed"):
			washed += 1
		else:
			_failures.append("isolation: %s outside the component is not washed out" % pid)
			break
	if kept == 0:
		_failures.append("isolation: nothing of the component stayed visible")
	if inner_pick != "" and not ShipComponents.is_expanded_id(inner_pick):
		_failures.append("isolation: a pick inside resolved to %s, not the inner part" % inner_pick)
	_builder.call("cancel_placement")
	if str(scene.get("_isolated")) != "":
		_failures.append("isolation: ESC did not close the component")
	for key: Variant in visuals.keys():
		var solid: MeshInstance3D = visuals[key].get("solid")
		if solid != null and solid.material_override == scene.get("_washed"):
			_failures.append("isolation: a visual stayed washed out after closing")
			break
	print(
		(
			"  isolation: opened %s - %d visuals washed, %d kept, inner pick %s, closed on ESC"
			% [instance, washed, kept, inner_pick if inner_pick != "" else "(none)"]
		)
	)


## One frame of [param vp] to [param path]; a failure names [param what].
func save_frame(vp: SubViewport, path: String, what: String) -> void:
	var img: Image = vp.get_texture().get_image() if vp != null else null
	if img == null or img.save_png(path) != OK:
		_failures.append("update: could not save %s" % what)
