extends SceneTree
## A ship that arrives is RESOLVED (ADR 0028): the builder is stood up, a carbon of spheres is
## generated exactly as the start dialog would, and without a single press the baked pieces
## must land on screen - the nucleus one open room, every tunnel hatched - with the bar showing
## meanwhile. Windowed (it renders); run through tools/ship_run.ps1 -Windowed.
##
## Read back: the baked view up, one module per placed id, the nucleus' room of six in the bake,
## every primitive the bake covers hidden, and frames saved for the human's eyes -
## reports/visual_resolved_wire.png (WIRE, where six overlapping spheres would show),
## reports/visual_resolved_interior.png (INTERIOR), and reports/visual_resolved_doors.png:
## one hatch close up with BOTH its doors swung open (ADR 0029), after the doors were counted -
## eight planned, twelve pieces bored and capped, a leaf on every piece at a hatch.

const OUT_DIR: String = "res://reports"
const SETTLE_FRAMES: int = 6
const MODE_FRAMES: int = 12
## Long enough for a door's swing (ShipExplodeView.DOOR_TWEEN_S) to finish before the frame.
const DOOR_FRAMES: int = 40
const DOOR_CLOSE_UP_M: float = 1.6
const MAX_BAKE_FRAMES: int = 1800
const HOST_SCENE: String = "res://harness/dev_host.tscn"

## Frames between each beat of the placement, for the queued ghost ray to resolve.
const PLACE_FRAMES: int = 14

var _parts_before: int = 0
var _ghost_before: Vector3 = Vector3.ZERO
var _host: Node = null
var _builder: Node = null
var _frames: int = 0
var _stage: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	var packed: PackedScene = load(HOST_SCENE)
	if packed == null:
		printerr("cannot load %s" % HOST_SCENE)
		quit(1)
		return
	_host = packed.instantiate()
	root.add_child(_host)


func _process(_delta: float) -> bool:
	_frames += 1
	var done: bool = false
	if _stage == 0 and _frames >= SETTLE_FRAMES:
		done = _begin()
	elif _stage == 1:
		done = _wait_for_resolve()
	elif _stage == 2 and _frames >= MODE_FRAMES:
		_save("visual_resolved_wire.png")
		_next(ShipSceneBuilder.DisplayMode.SHADED_WIRE, 4)
	elif _stage == 4 and _frames >= MODE_FRAMES:
		_save("visual_resolved_shaded.png")
		_next(ShipSceneBuilder.DisplayMode.INSIDE, 3)
	elif _stage == 3 and _frames >= MODE_FRAMES:
		_save("visual_resolved_interior.png")
		_read_back()
		_open_a_hatch()
		_next(ShipSceneBuilder.DisplayMode.INSIDE, 5)
	elif _stage == 5 and _frames >= DOOR_FRAMES:
		_save("visual_resolved_doors.png")
		_arm_ghost()
	elif _stage == 6 and _frames >= PLACE_FRAMES:
		_drag_ghost()
	elif _stage == 7 and _frames >= PLACE_FRAMES:
		_drop_ghost()
	elif _stage == 8 and _frames >= PLACE_FRAMES:
		_check_placed()
		_report()
		done = true
	return done


## CAN A PART STILL BE PLACED? Nothing else in the repo asks: `ship_visual_check.gd` drives
## `_handle_placement_input` DIRECTLY and so cannot see a closed `_gui_input`, which is exactly
## how a baked-on-arrival view swallowed every placement event and left the player with a ghost
## that would not move - "its a dead end" (2026-09-27). Driven here through `_gui_input`, from a
## ship that has just resolved itself, which is the state the bug lived in.
func _arm_ghost() -> void:
	_builder.call("_set_baked", false)
	var data: ShipData = _builder.call("get_data")
	_parts_before = (_builder.call("get_doc") as ShipDoc).parts.size()
	_builder.call("begin_placement", data.family_ids()[0], "")
	if not bool((_builder.call("get_placement") as Object).get("active")):
		_failures.append("place: the palette did not arm a ghost at all")
	_ghost_before = _ghost_at()
	_advance(6)


## THE GHOST RAY IS QUEUED, never resolved inline, so the press and the read sit frames apart.
func _drag_ghost() -> void:
	_gui(_place_press(true))
	_gui(_place_motion())
	_advance(7)


func _drop_ghost() -> void:
	if _ghost_at().is_equal_approx(_ghost_before):
		_failures.append("place: the ghost did not follow the pointer")
	_gui(_place_press(false))
	_advance(8)


func _check_placed() -> void:
	var after: int = (_builder.call("get_doc") as ShipDoc).parts.size()
	if after <= _parts_before:
		_failures.append("place: a release did not commit the ghost (%d parts, still)" % after)


func _ghost_at() -> Vector3:
	return ((_builder.call("get_placement").call("preview_transform")) as Transform3D).origin


func _gui(event: InputEvent) -> void:
	(_builder.call("get_view") as Control).call("_gui_input", event)


## Off centre, so the ray lands on the hull's flank rather than dead on its pole.
func _place_at() -> Vector2:
	return (_builder.call("get_view") as Control).size * Vector2(0.56, 0.46)


func _place_press(down: bool) -> InputEventMouseButton:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = down
	mb.position = _place_at()
	return mb


func _place_motion() -> InputEventMouseMotion:
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = _place_at()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	return mm


func _advance(stage: int) -> void:
	_stage = stage
	_frames = 0


func _next(mode: int, stage: int) -> void:
	_builder.call("set_display_mode", mode)
	_stage = stage
	_frames = 0


## Stand the builder up and generate the carbon. True only to abort.
func _begin() -> bool:
	_builder = _find_builder(_host)
	if _builder == null:
		printerr("no ShipBuilder in the scene")
		quit(1)
		return true
	# The start chooser and the tutorial card cover the viewport: away with both, as a player
	# would, and then the carbon exactly as STOCK TEMPLATE would build it.
	var data: ShipData = _builder.call("get_data")
	var dialog: Object = _builder.call("get_start_dialog")
	if dialog != null and bool(dialog.get("visible")):
		dialog.call("_on_cell_pressed", data.family_ids()[0])
		dialog.call("_on_start_pressed")
	var tutorial: Object = _builder.get("_tutorial")
	if tutorial != null and bool(tutorial.call("is_open")):
		tutorial.call("close")
	# LINKS HATCHED, and said out loud. A prebuild links OPEN since 2026-09-26 ("by default in the
	# prebuilds we dont want any walls in our prebuilds by default"), and this tool checks the
	# WALLS, the doors and the bores - so it asks for the links that make them, instead of resting
	# on a default that no longer says that.
	_builder.call(
		"found_from_template",
		"carbon",
		{
			ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod",
			ShipTemplates.OPT_LINK_MODE: ShipJoint.MODE_HATCHED
		}
	)
	_stage = 1
	_frames = 0
	return false


## The bake the ship started on its own: the bar must be up while it runs.
func _wait_for_resolve() -> bool:
	var view: Object = _builder.call("get_view")
	var explode: Object = view.call("get_explode_view") if view != null else null
	if explode == null:
		_failures.append("no explode view")
		_report()
		return true
	var bar: ProgressBar = _builder.get("_progress")
	if _frames == 3 and (bar == null or not bar.visible):
		_failures.append("no progress bar while the ship resolves")
	if (_builder.get("_bake_session") as ShipBakeSession).busy or bool(explode.call("is_busy")):
		if _frames <= MAX_BAKE_FRAMES:
			return false
		_failures.append("still resolving after %d frames" % _frames)
		_report()
		return true
	_builder.call("set_display_mode", ShipSceneBuilder.DisplayMode.WIREFRAME)
	# Close on the nucleus (it sits at the origin, about 12 m across), so the frame shows whether
	# its six pieces are cut at their intersections or six whole spheres drawn over one another.
	view.call("frame_aabb", AABB(Vector3(-7.0, -7.0, -7.0), Vector3(14.0, 14.0, 14.0)))
	_stage = 2
	_frames = 0
	return false


func _read_back() -> void:
	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder")
	var explode: Object = view.call("get_explode_view")
	var doc: ShipDoc = _builder.call("get_doc")
	var data: ShipData = _builder.call("get_data")
	var cfg: ShipConfig = _builder.call("get_config")
	# HELD, NOT WORN (2026-09-27). A ship that arrives still resolves itself - ADR 0028 is intact
	# and the bake is made - but it no longer REPLACES the editable view, because a baked view
	# sends every event to the explode handler and the player could not place a part into it:
	# "i click the part, a ghost version of it spawns, then i cant move, or apply the ghost
	# version at all its a dead end." So the assertion is that the bake EXISTS and that the view
	# is still editable, and then SHOW BAKED is pressed and the pieces read back as before.
	if bool(_builder.get("_baked")) or bool(view.call("is_baked")):
		_failures.append("the ship came up BAKED, so nothing can be placed into it")
	var session: Object = _builder.get("_bake_session")
	if session == null or (session.get("last") as Dictionary).is_empty():
		_failures.append("the ship did not come up resolved (no bake in hand)")
		return
	_builder.call("_set_baked", true)
	if not bool(_builder.get("_baked")) or not bool(view.call("is_baked")):
		_failures.append("SHOW BAKED did not put the resolved pieces on screen")
	var placed: int = ShipAttach.resolve_all(doc, data, cfg).size()
	var modules: int = int(explode.call("module_count"))
	if modules != placed:
		_failures.append("%d modules on screen, %d placed ids" % [modules, placed])
	var bake: Dictionary = (_builder.get("_bake_session") as ShipBakeSession).last
	var biggest: int = 0
	for members: PackedStringArray in bake.get("rooms", []):
		biggest = maxi(biggest, members.size())
	if biggest != 6:
		_failures.append("the nucleus did not bake as one room of six (biggest room %d)" % biggest)
	var hatched: int = 0
	for jid: String in doc.joints:
		if (doc.joints[jid] as ShipJoint).mode == ShipJoint.MODE_HATCHED:
			hatched += 1
	if hatched < 8:
		_failures.append("only %d hatched joints on a carbon (eight tunnel ends)" % hatched)
	var visuals: Dictionary = scene.get("_visuals")
	var shown: int = 0
	for key: Variant in visuals.keys():
		var solid: MeshInstance3D = visuals[key].get("solid")
		if solid != null and solid.visible:
			shown += 1
	if shown != 0:
		_failures.append("%d primitives still visible under the resolved pieces" % shown)
	print(
		(
			(
				"  resolved: %d modules for %d placed ids, room of %d, %d hatched joints, "
				+ "%d primitives showing"
			)
			% [modules, placed, biggest, hatched, shown]
		)
	)


## THE DOORS (ADR 0029): counted, then one hatch framed close with both its doors swung open.
func _open_a_hatch() -> void:
	var view: Object = _builder.call("get_view")
	var explode: Object = view.call("get_explode_view")
	var bake: Dictionary = (_builder.get("_bake_session") as ShipBakeSession).last
	var doors: Array = bake.get("doors", [])
	var bored: PackedStringArray = bake.get("bored", PackedStringArray())
	var failed: PackedStringArray = bake.get("door_failed", PackedStringArray())
	if doors.size() < 8:
		_failures.append("only %d doors planned on a carbon (eight tunnel ends)" % doors.size())
	if bored.size() < 12:
		_failures.append("only %d pieces bored (twelve carry a hatch)" % bored.size())
	if not failed.is_empty():
		_failures.append("the engine could not bore %s" % str(failed))
	var leaves: int = (explode.call("door_nodes") as Array).size()
	if leaves < doors.size() * 2:
		_failures.append(
			"%d door leaves on screen for %d doors (two apiece)" % [leaves, doors.size()]
		)
	print(
		(
			"  doors: %d planned, %d pieces bored, %d leaves on screen"
			% [doors.size(), bored.size(), leaves]
		)
	)
	if doors.size() < 2:
		return
	# A door lives inside the walls, so the frame is INTERIOR (the near walls culled) round one
	# whole tunnel - the first two doors are its two ends - with all four leaves swung open.
	var box: AABB = AABB((doors[0][ShipDoors.DOOR_FRAME] as Transform3D).origin, Vector3.ZERO)
	for i: int in 2:
		var door: Dictionary = doors[i]
		var key: String = str(door[ShipDoors.DOOR_KEY])
		view.call("set_door_open", key, ShipDoors.SIDE_CHILD, 1.0)
		view.call("set_door_open", key, ShipDoors.SIDE_HOST, 1.0)
		box = box.expand((door[ShipDoors.DOOR_FRAME] as Transform3D).origin)
	view.call("frame_aabb", box.grow(DOOR_CLOSE_UP_M))


func _save(file_name: String) -> void:
	var vp: SubViewport = _app_viewport(_host)
	var img: Image = vp.get_texture().get_image() if vp != null else null
	var path: String = "%s/%s" % [OUT_DIR, file_name]
	if img == null or img.save_png(path) != OK:
		_failures.append("could not save %s" % file_name)
	else:
		print("  frame -> %s" % path)


func _report() -> void:
	if _failures.is_empty():
		print("=== resolve check PASSED ===")
		quit(0)
		return
	print("=== resolve check FAILED (%d problem(s)) ===" % _failures.size())
	for line: String in _failures:
		print("  " + line)
	quit(1)


func _find_builder(n: Node) -> Node:
	if n is ShipBuilder:
		return n
	for child: Node in n.get_children():
		var found: Node = _find_builder(child)
		if found != null:
			return found
	return null


func _app_viewport(n: Node) -> SubViewport:
	if n is SubViewport and n.name == "AppViewport":
		return n
	for child: Node in n.get_children():
		var found: SubViewport = _app_viewport(child)
		if found != null:
			return found
	return null
