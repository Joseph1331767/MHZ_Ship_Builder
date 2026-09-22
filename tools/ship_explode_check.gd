extends SceneTree
## THE EXPLODE (ADR 0031/0032), driven the way a player drives it. Windowed (it renders); run
## through tools/ship_run.ps1 -Windowed.
##
## A carbon of spheres resolves; EXPLODE cuts every piece into its fundamental cells once and the
## pieces travel out; the slicer is changed - parts trisected along their radial Y, cluster chunks
## bisected across X - which must only MOVE the cells, never bake; POSITION scrubs to halfway; the
## gaps widen and separation switches off, again with no bake; ASSEMBLE plays it backwards and lands
## on the whole baked pieces. Frames for the human: reports/visual_explode_{default,sliced,half,
## spread}.png.
##
## Starts from the shipped defaults (ShipExplodeControl.use) and never calls the panel's handlers,
## which save: the player's own settings file is not touched by a check.

const OUT_DIR: String = "res://reports"
const SETTLE_FRAMES: int = 6
const FRAME_FRAMES: int = 8
const MAX_BAKE_FRAMES: int = 3000
const HOST_SCENE: String = "res://harness/dev_host.tscn"
const PARTS_SLICES: Vector3i = Vector3i(0, 2, 0)
const CLUSTER_SLICES: Vector3i = Vector3i(1, 0, 0)

var _host: Node = null
var _builder: Node = null
var _frames: int = 0
var _stage: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _exploded_ms: int = 0
var _bake_before: Dictionary = {}


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
		done = _when_idle(_check_exploded)
	elif _stage == 3 and _frames >= FRAME_FRAMES:
		_save("visual_explode_default.png")
		_reslice()
	elif _stage == 4 and _frames >= FRAME_FRAMES:
		_save("visual_explode_sliced.png")
		_scrub()
	elif _stage == 5 and _frames >= FRAME_FRAMES:
		_save("visual_explode_half.png")
		_spread()
	elif _stage == 6 and _frames >= FRAME_FRAMES:
		_save("visual_explode_spread.png")
		_separation_off()
		_assemble()
	elif _stage == 7:
		done = _when_idle(_check_assembled)
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


## Calls [param next] once the engine and the view are both idle - the bake done and the pieces
## done travelling; aborts past MAX_BAKE_FRAMES.
func _when_idle(next: Callable) -> bool:
	if _session().busy or _explode().is_busy():
		if _frames <= MAX_BAKE_FRAMES:
			return false
		_failures.append("still busy after %d frames (stage %d)" % [_frames, _stage])
		_report()
		return true
	next.call()
	return false


func _explode_it() -> void:
	_exploded_ms = Time.get_ticks_msec()
	_builder.call("_set_exploded", true)
	var layer: Control = _control().get("_overlay")
	if layer == null or not layer.visible:
		_failures.append("EXPLODE did not bring the options panel up")
	_advance(2)


## Every piece in its fundamental cells, fully out.
func _check_exploded() -> void:
	var ms: int = Time.get_ticks_msec() - _exploded_ms
	var bake: Dictionary = _session().last
	var cells: Dictionary = bake.get("cells", {})
	var pieces: int = (bake.get("solids", {}) as Dictionary).size()
	var total: int = 0
	for id: String in cells:
		total += (cells[id] as Array).size()
	if cells.size() != pieces or total < pieces * 8:
		_failures.append("%d of %d pieces cut, %d cells" % [cells.size(), pieces, total])
	if not _explode().has_cells_showing() or absf(_explode().amount() - 1.0) > 1.0e-3:
		_failures.append("the explode did not run out to 1 (at %.3f)" % _explode().amount())
	var nodes: int = _explode().module_nodes().size()
	print(
		(
			"  exploded: %d pieces in %d cells, %d nodes, cut and carried out in %d ms"
			% [pieces, total, nodes, ms]
		)
	)
	_frame_all()
	_advance(3)


## Parts trisected along Y, cluster chunks bisected across X: the cells move, nothing bakes.
func _reslice() -> void:
	_bake_before = _session().last
	var probe: Node3D = _a_cell(false)
	var was: Vector3 = probe.position if probe != null else Vector3.ZERO
	var settings: ShipExplodeSettings = _control().settings
	settings.slices = PARTS_SLICES
	settings.cluster_slices = CLUSTER_SLICES
	_explode().relayout()
	_control().refresh()
	_no_bake("a slicer change")
	if probe == null or probe.position.is_equal_approx(was):
		_failures.append("a slicer change did not move the cells")
	print("  sliced: parts trisected on Y, cluster chunks bisected on X - moved, no bake")
	_advance(4)


## POSITION to halfway: everything half out.
func _scrub() -> void:
	var probe: Node3D = _a_cell(true)
	var full: Vector3 = probe.position if probe != null else Vector3.ZERO
	_explode().set_amount(0.5)
	if absf(_explode().amount() - 0.5) > 1.0e-4:
		_failures.append("POSITION 0.5 left the explode at %.3f" % _explode().amount())
	var slider: HSlider = (_control().get("_panel") as Object).get("_position")
	if slider == null or absf(slider.value - 0.5) > 1.0e-3:
		_failures.append("the POSITION slider did not follow the explode")
	if probe == null or probe.position.is_equal_approx(full):
		_failures.append("halfway left the pieces where they were")
	_no_bake("POSITION")
	print("  scrubbed: POSITION 50% - pieces halfway, no bake")
	_advance(5)


## Wider gaps, fully out again: the pieces follow, nothing bakes.
func _spread() -> void:
	_explode().set_amount(1.0)
	var probe: Node3D = _a_cell(true)
	var was: Vector3 = probe.position if probe != null else Vector3.ZERO
	var settings: ShipExplodeSettings = _control().settings
	settings.separation_m = 4.0
	settings.slice_separation_m = 2.0
	settings.cluster_slice_separation_m = 1.5
	_explode().relayout()
	if probe == null or probe.position.is_equal_approx(was):
		_failures.append("a wider separation did not move the pieces")
	_no_bake("a separation change")
	print(
		(
			"  spread: a piece moved %.2f m, no bake"
			% [probe.position.distance_to(was) if probe != null else 0.0]
		)
	)
	_frame_all()
	_advance(6)


## Separation off: every module back on its seam, the slices still apart.
func _separation_off() -> void:
	_control().settings.separate = false
	_explode().relayout()
	var offsets: Dictionary = _explode().get("_offsets")
	if not offsets.is_empty():
		_failures.append("separation off left %d modules pulled apart" % offsets.size())
	else:
		print("  separation off: every module back on its seam")


## ASSEMBLE: plays backwards, then lands on the whole pieces.
func _assemble() -> void:
	_builder.call("_set_exploded", false)
	if not _explode().is_busy():
		_failures.append("ASSEMBLE did not play the explode backwards")
	_advance(7)


func _check_assembled() -> void:
	if not bool(_builder.get("_baked")) or not _explode().is_assembled():
		_failures.append("ASSEMBLE did not land on the baked view")
	if _explode().has_cells_showing():
		_failures.append("cells still on screen after ASSEMBLE")
	var modules: int = _explode().module_count()
	var nodes: int = _explode().module_nodes().size()
	print("  assembled: back to %d whole pieces (%d nodes)" % [modules, nodes])
	_report()


func _no_bake(what: String) -> void:
	if _session().busy or not is_same(_session().last, _bake_before):
		_failures.append("%s started a bake" % what)


## A cell visual that the explode moves: of a module with an offset when [param moving_module],
## else any cell of a standalone piece.
func _a_cell(moving_module: bool) -> Node3D:
	var offsets: Dictionary = _explode().get("_offsets")
	for child: Node in _explode().get_children():
		if not (child is MeshInstance3D) or not child.has_meta(ShipExplodeView.META_CELL):
			continue
		var cell: Vector3i = child.get_meta(ShipExplodeView.META_CELL)
		if cell.x < 0 or cell.y != 0:
			continue
		if int(child.get_meta(ShipExplodeView.META_KIND)) != ShipExplodeView.SEP_PARTS:
			continue
		if moving_module and not offsets.has(str(child.get_meta(ShipExplodeView.META_MODULE))):
			continue
		return child
	return null


func _frame_all() -> void:
	var box: AABB = _explode().bounds()
	if box.size.length() > 0.0:
		_builder.call("get_view").call("frame_aabb", box)


func _control() -> ShipExplodeControl:
	return _builder.get("_explode_opts")


func _session() -> ShipBakeSession:
	return _builder.get("_bake_session")


func _explode() -> ShipExplodeView:
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
