extends SceneTree
## THE EXPLODE OPTIONS (ADR 0031), driven the way a player drives them. Windowed (it renders); run
## through tools/ship_run.ps1 -Windowed.
##
## A carbon of spheres resolves; EXPLODE brings the options panel up and the default slicing (every
## piece bisected across its Z) on screen; the slicer is changed - parts trisected along their
## radial Y, cluster chunks bisected across X - which lights APPLY SLICES, and APPLY re-cuts them;
## then the separations are moved and switched off, which must move what is on screen WITHOUT a
## rebake. Frames for the human: reports/visual_explode_{default,sliced,spread}.png.
##
## Starts from the shipped defaults (ShipExplodeControl.use) and never calls the panel's handlers,
## which save: the player's own settings file is not touched by a check.

const OUT_DIR: String = "res://reports"
const SETTLE_FRAMES: int = 6
const FRAME_FRAMES: int = 12
const MAX_BAKE_FRAMES: int = 2400
const HOST_SCENE: String = "res://harness/dev_host.tscn"
const PARTS_SLICES: Vector3i = Vector3i(0, 2, 0)
const CLUSTER_SLICES: Vector3i = Vector3i(1, 0, 0)

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
		done = _when_idle(_explode_it)
	elif _stage == 2:
		done = _when_idle(_check_default)
	elif _stage == 3 and _frames >= FRAME_FRAMES:
		_save("visual_explode_default.png")
		_reslice()
	elif _stage == 4:
		done = _when_idle(_check_sliced)
	elif _stage == 5 and _frames >= FRAME_FRAMES:
		_save("visual_explode_sliced.png")
		_spread()
	elif _stage == 6 and _frames >= FRAME_FRAMES:
		_save("visual_explode_spread.png")
		_separation_off()
		_report()
		done = true
	return done


func _advance(stage: int) -> void:
	_stage = stage
	_frames = 0


## Stand the builder up, start from the default settings, and generate the carbon.
func _begin() -> bool:
	_builder = _find_builder(_host)
	if _builder == null:
		printerr("no ShipBuilder in the scene")
		quit(1)
		return true
	var data: ShipData = _builder.call("get_data")
	var dialog: Object = _builder.call("get_start_dialog")
	if dialog != null and bool(dialog.get("visible")):
		dialog.call("_on_cell_pressed", data.family_ids()[0])
		dialog.call("_on_start_pressed")
	var tutorial: Object = _builder.get("_tutorial")
	if tutorial != null and bool(tutorial.call("is_open")):
		tutorial.call("close")
	_control().use(ShipExplodeSettings.defaults(_builder.call("get_config")))
	_builder.call("found_from_template", "carbon", {ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"})
	_advance(1)
	return false


## Calls [param next] once the engine and the view are both idle; aborts past MAX_BAKE_FRAMES.
func _when_idle(next: Callable) -> bool:
	if _session().busy or bool(_explode().call("is_busy")):
		if _frames <= MAX_BAKE_FRAMES:
			return false
		_failures.append("still baking after %d frames (stage %d)" % [_frames, _stage])
		_report()
		return true
	next.call()
	return false


func _explode_it() -> void:
	_builder.call("_set_exploded", true)
	var layer: Control = _control().get("_overlay")
	if layer == null or not layer.visible:
		_failures.append("EXPLODE did not bring the options panel up")
	_advance(2)


## The default slicing on screen: every piece in two.
func _check_default() -> void:
	var bake: Dictionary = _session().last
	var chunks: Dictionary = bake.get("chunks", {})
	var two: int = 0
	for id: String in chunks:
		if (chunks[id] as Array).size() == 2:
			two += 1
	var pieces: int = (bake.get("solids", {}) as Dictionary).size()
	if two != pieces:
		_failures.append("default slicing: %d of %d pieces in two" % [two, pieces])
	print("  default: %d of %d pieces bisected across Z" % [two, pieces])
	_frame_all()
	_advance(3)


## Parts trisected along Y, cluster chunks bisected across X: APPLY lights, then APPLY re-cuts.
func _reslice() -> void:
	var settings: ShipExplodeSettings = _control().settings
	settings.slices = PARTS_SLICES
	settings.cluster_slices = CLUSTER_SLICES
	_control().refresh()
	var apply: Button = (_control().get("_panel") as Object).get("_apply")
	if apply == null or not apply.text.ends_with("*"):
		_failures.append("APPLY SLICES did not light when the slicer changed")
	_builder.call("_show_bake")
	_advance(4)


func _check_sliced() -> void:
	var bake: Dictionary = _session().last
	var want: String = ShipCsgBake.slicing_key({"parts": PARTS_SLICES, "clusters": CLUSTER_SLICES})
	if str(bake.get(ShipCsgBake.EXTRAS_SLICING, "")) != want:
		_failures.append(
			(
				"APPLY did not re-cut the pieces (extras %s)"
				% str(bake.get(ShipCsgBake.EXTRAS_SLICING))
			)
		)
	var counts: Dictionary = bake.get("chunk_counts", {})
	var chunks: Dictionary = bake.get("chunks", {})
	var parts: int = 0
	var clusters: int = 0
	for members: PackedStringArray in bake.get("rooms", []):
		for id: String in members:
			var got: Vector3i = counts.get(id, Vector3i.ZERO)
			var expected: Vector3i = CLUSTER_SLICES if members.size() > 1 else PARTS_SLICES
			# The slices that EXIST, not only the counts asked for: a grid of n cells gives at
			# least two and at most n (a cell wholly in a cavity has nothing in it).
			var cells: int = (expected.x + 1) * (expected.y + 1) * (expected.z + 1)
			var made: int = (chunks.get(id, []) as Array).size()
			if got != expected:
				_failures.append("%s sliced %s, expected %s" % [id, str(got), str(expected)])
			elif made < 2 or made > cells:
				_failures.append("%s came out in %d slices for a grid of %d" % [id, made, cells])
			elif members.size() > 1:
				clusters += 1
			else:
				parts += 1
	var apply: Button = (_control().get("_panel") as Object).get("_apply")
	if apply != null and apply.text.ends_with("*"):
		_failures.append("APPLY SLICES still lit after the re-cut landed")
	var nodes: int = (_explode().call("module_nodes") as Array).size()
	print(
		(
			"  sliced: %d parts trisected along Y, %d cluster chunks bisected across X, %d nodes"
			% [parts, clusters, nodes]
		)
	)
	_frame_all()
	_advance(5)


## Wider separations move what is on screen, and the engine is not asked for anything.
func _spread() -> void:
	var before: Dictionary = _session().last
	var probe: Node3D = _a_moving_node()
	var was: Vector3 = probe.position if probe != null else Vector3.ZERO
	var settings: ShipExplodeSettings = _control().settings
	settings.separation_m = 4.0
	settings.slice_separation_m = 2.0
	settings.cluster_slice_separation_m = 1.5
	_explode().call("relayout")
	if probe == null or probe.position.is_equal_approx(was):
		_failures.append("a wider separation did not move the pieces")
	if _session().busy or not is_same(_session().last, before):
		_failures.append("a separation change started a bake")
	print(
		(
			"  spread: a piece moved %.2f m with no rebake"
			% [probe.position.distance_to(was) if probe != null else 0.0]
		)
	)
	_frame_all()
	_advance(6)


## Separation off: every module back at its seam, the slices still apart.
func _separation_off() -> void:
	_control().settings.separate = false
	_explode().call("relayout")
	var offsets: Dictionary = _explode().get("_offsets")
	if not offsets.is_empty():
		_failures.append("separation off left %d modules pulled apart" % offsets.size())
	else:
		print("  separation off: every module back on its seam")


## A module node that a separation moves: one hanging off a module with an offset.
func _a_moving_node() -> Node3D:
	var offsets: Dictionary = _explode().get("_offsets")
	for child: Node in _explode().get_children():
		if child is MeshInstance3D and child.has_meta(ShipExplodeView.META_MODULE):
			if offsets.has(str(child.get_meta(ShipExplodeView.META_MODULE))):
				return child
	return null


func _frame_all() -> void:
	var box: AABB = _explode().call("bounds")
	if box.size.length() > 0.0:
		_builder.call("get_view").call("frame_aabb", box)


func _control() -> ShipExplodeControl:
	return _builder.get("_explode_opts")


func _session() -> ShipBakeSession:
	return _builder.get("_bake_session")


func _explode() -> Node:
	return _builder.call("get_view").call("get_explode_view")


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
		print("=== explode check PASSED ===")
		quit(0)
		return
	print("=== explode check FAILED (%d problem(s)) ===" % _failures.size())
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
