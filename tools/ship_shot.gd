extends SceneTree

## Windowed screenshot tool. Loads a scene, lets it settle, writes a PNG to reports/.
##
##   ./tools/ship_run.ps1 res://tools/ship_shot.gd -Windowed
##   & $env:GODOT_BIN --path . -s res://tools/ship_shot.gd -- <scene_path> <out_name> <frames>
##
## MUST run windowed and MUST hold the GPU slot (AGENTS: the GPU is a booked resource). Headless
## produces an empty image -- there is no swap chain to read back, so a headless "screenshot" is a
## black rectangle that looks like a rendering bug and is not one.
##
## WHY THIS EXISTS. Every other gate in this repo proves the code parses, loads, and computes the
## right numbers. None of them prove a single pixel is correct. A suite that is green over a page
## nobody looked at is a suite that agrees with itself (AGENTS §10). This tool produces the
## artefact a human -- or an agent -- can actually read.
##
## It reports a black-frame check because that is the failure this tool is most likely to hide:
## a scene that errors during _ready() still presents a window, still saves a PNG, and still exits
## 0. A frame that is uniformly one colour is reported as SUSPECT rather than passed.

const DEFAULT_SCENE: String = "res://harness/dev_host.tscn"
const DEFAULT_OUT: String = "builder"
const DEFAULT_FRAMES: int = 90

## Frame at which a requested display mode is applied; see _process.
const MODE_APPLY_FRAME: int = 15

var _scene_path: String = DEFAULT_SCENE
var _out_name: String = DEFAULT_OUT
var _target_frames: int = DEFAULT_FRAMES
var _frames: int = 0
var _instance: Node = null
var _failed: bool = false

## ShipSceneBuilder.DisplayMode to force before capturing, or -1 to leave it alone.
##
## Added because a claim went unverified for a whole round: SHADED+WIRE was asserted to "carry the
## form" and never once compared against FLAT. A shot tool that can only capture the default state
## cannot check a mode toggle, so it cannot check most of this UI.
var _display_mode: int = -1


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_scene_path = args[0]
	if args.size() > 1:
		_out_name = args[1]
	if args.size() > 2 and args[2].is_valid_int():
		_target_frames = maxi(2, args[2].to_int())
	if args.size() > 3 and args[3].is_valid_int():
		_display_mode = args[3].to_int()

	print("=== ship_shot: %s (%d frames) ===" % [_scene_path, _target_frames])

	if not ResourceLoader.exists(_scene_path):
		printerr("scene does not exist: %s" % _scene_path)
		_failed = true
		return

	var packed: PackedScene = load(_scene_path) as PackedScene
	if packed == null:
		printerr("not a PackedScene: %s" % _scene_path)
		_failed = true
		return

	_instance = packed.instantiate()
	if _instance == null:
		printerr("instantiate() returned null: %s" % _scene_path)
		_failed = true
		return
	root.add_child(_instance)
	print("  instantiated: %s (%s)" % [_instance.name, _instance.get_class()])



## Depth-first search for the node exposing the builder facade.
func _find_builder(n: Node) -> Node:
	if n.has_method("set_display_mode") and n.has_method("get_doc"):
		return n
	for c: Node in n.get_children():
		var r: Node = _find_builder(c)
		if r != null:
			return r
	return null


func _process(_delta: float) -> bool:
	if _failed:
		quit(1)
		return true

	_frames += 1

	# Applied a few frames in, NOT during _initialize(): ShipBuilder._view does not exist yet at
	# that point, so set_display_mode() silently no-ops and every mode captures identically. That
	# is exactly how a "FLAT vs SHADED+WIRE look the same" bug hid behind a tool that appeared to
	# be setting the mode.
	if _display_mode >= 0 and _frames == MODE_APPLY_FRAME:
		var builder: Node = _find_builder(_instance)
		if builder == null:
			printerr("display mode %d requested but no ShipBuilder found" % _display_mode)
		else:
			builder.call("set_display_mode", _display_mode)
			var got: int = -1
			var view: Object = builder.call("get_view")
			if view != null:
				got = int(view.call("get_display_mode"))
			print("  display mode requested %d, view reports %d" % [_display_mode, got])

	if _frames < _target_frames:
		return false

	var img: Image = root.get_texture().get_image()
	if img == null:
		printerr("viewport returned no image - was this run headless?")
		quit(1)
		return true

	var dir_err: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://reports")
	)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		printerr("could not create reports/: %d" % dir_err)
		quit(1)
		return true

	var out_path: String = "res://reports/%s.png" % _out_name
	var save_err: Error = img.save_png(out_path)
	if save_err != OK:
		printerr("save_png failed (%d): %s" % [save_err, out_path])
		quit(1)
		return true

	print("  saved: %s  (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	_report_uniformity(img)
	quit(0)
	return true


## A scene that throws during _ready() still presents a window and still saves a PNG. Sampling a
## coarse grid and counting distinct colours is the cheapest way to notice that the "screenshot"
## is just the clear colour.
func _report_uniformity(img: Image) -> void:
	var seen: Dictionary = {}
	var w: int = img.get_width()
	var h: int = img.get_height()
	var step_x: int = maxi(1, w / 40)
	var step_y: int = maxi(1, h / 40)
	var y: int = 0
	while y < h:
		var x: int = 0
		while x < w:
			seen[img.get_pixel(x, y).to_rgba32()] = true
			x += step_x
		y += step_y
	var distinct: int = seen.size()
	if distinct <= 2:
		printerr(
			"SUSPECT: only %d distinct colours in the frame - the scene may have failed to draw"
			% distinct
		)
	else:
		print("  frame has %d distinct sampled colours (looks drawn)" % distinct)
