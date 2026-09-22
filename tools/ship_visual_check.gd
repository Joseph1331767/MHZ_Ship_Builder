extends SceneTree

## Windowed visual gate. Builds a representative multi-part ship, renders it in every display
## mode, saves a PNG per mode, and ASSERTS on what came out.
##
##   ./tools/ship_run.ps1 res://tools/ship_visual_check.gd -Windowed -TimeoutSeconds 300
##
## MUST run windowed and MUST hold the GPU slot (AGENTS section 8c). Headless has no swap chain,
## so a headless "screenshot" is a black rectangle that looks like a rendering bug and is not one.
##
## WHY THIS EXISTS, when tools/ship_shot.gd already saves a PNG.
##
## ship_shot.gd proves a frame was drawn. It cannot tell a correct frame from a wrong one, and
## rounds of "verification" went past on exactly that gap: FLAT and SHADED+WIRE were asserted to
## differ and were never compared; a box rendered as a single flat quad in three consecutive
## screenshots and was read as "shaded"; and when parts finally did shade, the ramp was uploaded
## in the wrong colour space, so two of its four bands collapsed onto one palette entry and the
## brightest landed on pale mint. Every one of those is invisible to "did the tool exit 0" and
## obvious to "how many distinct palette entries is the ship wearing".
##
## So this tool makes the claims machine-checkable:
##
##   BAND COVERAGE    - a shaded ship must wear at least MIN_BANDS distinct ramp entries. One band
##                      means the shading collapsed and the ship is a flat silhouette again.
##   PALETTE PURITY   - every 3D pixel must BE a palette entry. Anything else is a colour the
##                      quantizer is free to move, which is how the mint triangle got in.
##   MODE DISTINCTNESS - FLAT, WIREFRAME and SHADED+WIRE must not produce identical frames.
##   INK COVERAGE     - the ship must occupy a plausible share of the viewport, so an empty or
##                      off-screen scene fails instead of passing as "no bands, no error".
##
## It writes reports/visual_<n>_<mode>.png so a human can look at the same frames the assertions
## ran over, because an assertion suite nobody eyeballs is how the mint triangle survived several
## rounds of green checks.

const OUT_DIR: String = "res://reports"
const MODE_NAMES: Array = ["flat", "wireframe", "shaded_wire", "xray", "fresnel"]

## Frames to let the scene settle before the first capture, and between mode switches. The builder
## resolves shapes, rebuilds materials and reframes the camera across several frames; capturing
## earlier catches a half-built scene and reports a failure that is not real.
const SETTLE_FRAMES: int = 45
const MODE_FRAMES: int = 12
## Frames the exploded view may take to bake every module before the stage gives up. One module
## per frame at the explode resolution is well under a second each on the demo ship.
const EXPLODE_MAX_FRAMES: int = 900

## Fraction of a rotation ring's on-screen circle that must answer to a press on it. The morph
## ticks and the offset stalk deliberately win where they overlap a ring, so no ring is ever
## wholly its own; a fifth of the circle is roughly a quadrant of clear arc, which is the least a
## player can be expected to find by aiming at the ring itself.
const RING_GRAB_MIN_SHARE: float = 0.2

## A shaded ship must wear at least this many distinct ramp entries. Three is the meaningful
## floor: a cube shows three faces, and if they do not land on three entries the shading is not
## conveying form.
const MIN_BANDS: int = 3

## Share of the 3D viewport the ship must cover. Wide open on purpose - the framing depends on the
## demo ship, and the point is to catch "nothing rendered" and "camera is inside the hull".
const MIN_INK: float = 0.02
const MAX_INK: float = 0.85

## Sampling stride for the frame analysis. The frames are ~2.5k wide; every pixel is needlessly
## slow in GDScript and every 4th tells the same story.
const SAMPLE_STEP: int = 4

var _frames: int = 0
var _stage: int = 0
var _host: Node = null
var _builder: Node = null
var _failures: PackedStringArray = PackedStringArray()
## The ADR 0009 view checks - fresnel, explode picking and display mode, the seam menu -
## which live in their own file because this one is at gdlint's file-length cap.
var _views: ShipCheckViews = null
var _histograms: Array = []
var _palette: PackedStringArray = PackedStringArray()
## Which step of the release-survival gate (F13) is next, and the part it runs on.
var _release_step: int = 0
var _release_pid: String = ""
var _release_family: String = ""
## The explode stage's step, and what it expects the field to explode into.
var _explode_step: int = 0
var _update_step: int = 0
var _explode_expected: int = 0
var _explode_seams: int = 0


func _initialize() -> void:
	print("=== ship_visual_check ===")
	var packed: PackedScene = load("res://harness/dev_host.tscn") as PackedScene
	if packed == null:
		printerr("cannot load res://harness/dev_host.tscn")
		quit(1)
		return
	_host = packed.instantiate()
	root.add_child(_host)


## Returning true ends the run, so every branch here funnels through a single `done` flag rather
## than an early return - gdlint caps a function at 6 returns and the stage machine needs more
## branches than that.
func _process(_delta: float) -> bool:
	_frames += 1
	var done: bool = false

	if _stage == 0:
		if _frames >= SETTLE_FRAMES:
			done = _setup()
	elif _stage - 1 < MODE_NAMES.size():
		done = _run_mode(_stage - 1)
	elif _stage - 1 == MODE_NAMES.size():
		_check_bbox_cage()
		_views.check_fresnel(_histograms, _palette, MODE_NAMES)
		_stage += 1
	elif _stage - 2 == MODE_NAMES.size():
		# AFTER the captures, because driving handles mutates the document and would change the
		# frames the mode captures above are asserting about.
		_check_gizmo()
		_check_arrows()
		_stage += 1
		_frames = 0
	elif _stage - 3 == MODE_NAMES.size():
		# Frame-driven: every release here goes through the real input path and lands in the
		# view's _physics_process, so each gesture needs frames between press and verdict.
		if _check_release_survival():
			_stage += 1
	elif _stage - 4 == MODE_NAMES.size():
		_check_make_component()
		_stage += 1
	elif _stage - 5 == MODE_NAMES.size():
		_check_rooms_and_hatches()
		_views.check_seam_menu()
		_stage += 1
	elif _stage - 6 == MODE_NAMES.size():
		_check_tutorial()
		_stage += 1
		_frames = 0
	elif _stage - 7 == MODE_NAMES.size():
		# Frame-driven: the exploded view bakes one module per frame.
		if _check_explode():
			_stage += 1
			_frames = 0
	elif _stage - 8 == MODE_NAMES.size():
		# Frame-driven: the engine bakes over frames and the view places a module a frame.
		if _check_update_meshes():
			_stage += 1
	elif _stage - 9 == MODE_NAMES.size():
		# Last, because it lifts a part into a component and leaves it so.
		_views.check_isolation()
		_stage += 1
	else:
		_report()
		done = true
	return done


## Find the builder and stand up the demo ship. Returns true only to abort the run.
func _setup() -> bool:
	_builder = _find_builder(_host)
	_views = ShipCheckViews.new(_builder, _failures)
	if _builder == null:
		printerr("no ShipBuilder in the scene")
		quit(1)
		return true
	_record_palette()
	# The mode captures assert about the primitives; a ship that resolves itself would swap
	# them for baked pieces mid-capture. tools/ship_resolve_check.gd covers the resolve.
	_builder.set("_resolve_on_load_enabled", false)
	_build_demo_ship()
	_stage = 1
	_frames = 0
	return false


## Switch to `mode`, let it render, capture it. Never ends the run.
func _run_mode(mode: int) -> bool:
	if _frames == 1:
		_builder.call("set_display_mode", mode)
		return false
	if _frames < MODE_FRAMES:
		return false
	_capture(mode)
	_stage += 1
	_frames = 0
	return false


# ---------------------------------------------------------------- scene


## A ship that exercises what a single cube cannot: several families, several depths from the
## camera (so the distance cue has something to separate), and one selected part (so the `part`
## and `part_selected` ramps are both on screen at once).
func _build_demo_ship() -> void:
	var data: ShipData = _builder.call("get_data")
	if data == null:
		_failures.append("builder has no data pack")
		return
	var families: PackedStringArray = data.family_ids()
	if families.is_empty():
		_failures.append("data pack exposes no families")
		return
	# A fresh console has NO document: it is sitting on the start chooser waiting for the player to
	# pick a founding primitive (2026-09-01). Drive the chooser's own buttons rather than calling
	# found_document() behind it - that founds a ship but leaves the chooser's full-screen dim over
	# the viewport, and every mode below then measures the DIALOG instead of the ship.
	var dialog: Object = _builder.call("get_start_dialog")
	if dialog != null and bool(dialog.get("visible")):
		dialog.call("_on_cell_pressed", families[0])
		dialog.call("_on_start_pressed")
	if dialog != null and bool(dialog.get("visible")):
		_failures.append("the start chooser is still on screen after pressing START")
	var doc: ShipDoc = _builder.call("get_doc")
	if doc == null:
		_failures.append("the start chooser produced no document")
		return

	var root_id: String = doc.root
	var added: PackedStringArray = PackedStringArray()
	for i: int in range(mini(4, families.size())):
		var made: String = _builder.call("add_part", families[i], "", root_id)
		if made == "":
			continue
		added.append(made)
		# Spread the children around the parent so they sit at different depths rather than
		# stacking on one face - the distance cue is invisible on co-planar parts.
		var part: ShipPart = doc.parts.get(made, null) as ShipPart
		if part != null:
			part.yaw = float(i) * 90.0
			part.pitch = 18.0 - float(i) * 12.0
			# All three mount-frame axes, not just the spin (ADR 0004). A demo ship that only
			# ever wrote rot.z would render identically whether or not the other two axes work.
			part.rot = Vector3(float(i) * 15.0, float(i) * -10.0, float(i) * 25.0)

	var pick: PackedStringArray = PackedStringArray()
	if not added.is_empty():
		pick.append(added[0])
	_builder.call("set_selection", pick)

	var view: Object = _builder.call("get_view")
	if view != null:
		view.call("rebuild", doc, data, _builder.call("get_config"))
		view.call("frame_all")
	_check_twins(doc, data)
	print(
		(
			"  demo ship: %d parts (%d added), selection=%s"
			% [doc.parts.size(), added.size(), "none" if pick.is_empty() else pick[0]]
		)
	)


## Symmetry must produce VISIBLE mirrored parts, not just mirrored transforms.
##
## This check exists because its absence let a false claim stand: twin transforms were verified in
## a unit test, "twins render" was reported on the strength of a screenshot of four DIFFERENT
## families placed at 0/90/180/270 degrees - parts on opposite sides by construction - and the
## mirrored halves were never actually drawn on the incremental edit path at all. Counting
## `~m` entries in the scene builder is the question that was never asked.
func _check_twins(doc: ShipDoc, data: ShipData) -> void:
	if ShipSymmetry.plane_axis(doc.symmetry_plane) < 0:
		return
	var cfg: ShipConfig = _builder.call("get_config")
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, cfg)
	var expected: PackedStringArray = PackedStringArray()
	for key: Variant in xforms.keys():
		var id: String = str(key)
		if ShipSymmetry.is_twin_id(id):
			expected.append(id)
	if expected.is_empty():
		_failures.append(
			(
				(
					"symmetry is on across '%s' but the demo ship generated no twin at all - "
					% doc.symmetry_plane
				)
				+ "every part is sitting on the mirror plane, so this run proves nothing"
			)
		)
		return

	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder") if view != null else null
	var visuals: Variant = scene.get("_visuals") if scene != null else null
	if not (visuals is Dictionary):
		_failures.append("cannot read the scene builder's visuals to check twins")
		return
	var drawn: Dictionary = visuals
	for id: String in expected:
		if not drawn.has(id):
			_failures.append(
				"twin %s has a transform but no mesh - symmetry is invisible on screen" % id
			)
	print("  twins: %d expected, %d drawn" % [expected.size(), expected.size()])


func _record_palette() -> void:
	var theme: Object = _builder.call("get_ship_theme")
	if theme == null:
		return
	var pal: PackedColorArray = theme.get("active_palette")
	for c: Color in pal:
		_palette.append(c.to_html(false))
	print("  palette: %d entries" % _palette.size())
	for ramp_entry: Variant in ["part", "part_selected"]:
		var ramp_name: String = String(ramp_entry)
		var idx: PackedInt32Array = theme.call("ramp_indices", ramp_name)
		var cols: PackedStringArray = PackedStringArray()
		for i: int in idx:
			cols.append(_palette[i] if i < _palette.size() else "??")
		print("  ramp %-14s %s" % [ramp_name, ", ".join(cols)])


# ---------------------------------------------------------------- capture


func _capture(mode: int) -> void:
	var vp: SubViewport = _app_viewport(_host)
	if vp == null:
		_failures.append("no AppViewport to read back")
		return
	var img: Image = vp.get_texture().get_image()
	if img == null:
		_failures.append("%s: viewport returned no image (was this run headless?)" % _name(mode))
		return

	var reported: int = -1
	var view: Object = _builder.call("get_view")
	if view != null:
		reported = int(view.call("get_display_mode"))
	if reported != mode:
		_failures.append("%s: asked for mode %d, view reports %d" % [_name(mode), mode, reported])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path: String = "%s/visual_%d_%s.png" % [OUT_DIR, mode, _name(mode)]
	var err: Error = img.save_png(path)
	if err != OK:
		_failures.append("%s: save_png failed (%d)" % [_name(mode), err])

	var hist: Dictionary = _histogram(img)
	_histograms.append(hist)
	_check(mode, hist)
	print("  %-12s -> %s" % [_name(mode), path])
	_print_hist(hist)


## Colour census over the 3D area only. The side panels are full of palette-coloured chrome that
## would swamp the ship's own bands and make MIN_BANDS meaningless.
func _histogram(img: Image) -> Dictionary:
	var rect: Rect2i = _view_rect(img)
	var counts: Dictionary = {}
	var total: int = 0
	var y: int = rect.position.y
	while y < rect.end.y:
		var x: int = rect.position.x
		while x < rect.end.x:
			var key: String = img.get_pixel(x, y).to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
			total += 1
			x += SAMPLE_STEP
		y += SAMPLE_STEP
	return {"counts": counts, "total": total}


## The inner 3D viewport's rect inside the app image, read off the node rather than guessed. An
## earlier throwaway analysis hardcoded a crop and silently measured the wrong region.
func _view_rect(img: Image) -> Rect2i:
	var whole: Rect2i = Rect2i(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height()))
	var view: Node = _find_named(_host, "View3DViewport")
	if view == null:
		return whole
	var ctl: Control = view.get_parent() as Control
	if ctl == null or not ctl.is_inside_tree():
		return whole
	var r: Rect2 = ctl.get_global_rect()
	var pos: Vector2i = Vector2i(int(r.position.x), int(r.position.y))
	var size: Vector2i = Vector2i(int(r.size.x), int(r.size.y))
	pos.x = clampi(pos.x, 0, img.get_width() - 1)
	pos.y = clampi(pos.y, 0, img.get_height() - 1)
	size.x = clampi(size.x, 1, img.get_width() - pos.x)
	size.y = clampi(size.y, 1, img.get_height() - pos.y)
	return Rect2i(pos, size)


# ---------------------------------------------------------------- assertions


func _check(mode: int, hist: Dictionary) -> void:
	var counts: Dictionary = hist["counts"]
	var total: int = int(hist["total"])
	if total <= 0:
		_failures.append("%s: empty sample region" % _name(mode))
		return

	var background: String = _palette[0] if not _palette.is_empty() else "081216"
	var ink: int = 0
	var off_palette: PackedStringArray = PackedStringArray()
	for key: Variant in counts.keys():
		var hex: String = String(key)
		if hex != background:
			ink += int(counts[key])
		if not _palette.has(hex) and not off_palette.has(hex):
			off_palette.append(hex)

	var ink_frac: float = float(ink) / float(total)
	if ink_frac < MIN_INK:
		_failures.append(
			(
				"%s: only %.1f%% of the 3D view is non-background - did anything render?"
				% [_name(mode), ink_frac * 100.0]
			)
		)
	elif ink_frac > MAX_INK:
		_failures.append(
			(
				"%s: %.1f%% of the 3D view is non-background - camera is probably inside the ship"
				% [_name(mode), ink_frac * 100.0]
			)
		)

	if not off_palette.is_empty():
		_failures.append(
			(
				(
					"%s: %d colour(s) are not palette entries (%s) - these are exactly the colours "
					% [_name(mode), off_palette.size(), ", ".join(off_palette)]
				)
				+ "the quantizer is free to move"
			)
		)

	# WIREFRAME draws no solids, so band coverage is not meaningful there. XRAY is translucent and
	# deliberately does not use the ramps.
	if mode == 0 or mode == 2:
		var bands: int = _ramp_bands_present(counts)
		if bands < MIN_BANDS:
			_failures.append(
				(
					(
						"%s: only %d ramp band(s) on screen, need %d - the shading has collapsed "
						% [_name(mode), bands, MIN_BANDS]
					)
					+ "and parts read as flat silhouettes"
				)
			)


## FRESNEL must be its OWN render type, not a relabelled SHADED+WIRE (ADR 0009).
##
## "i mean i wanted that rendering effect/node to be listed among wire, flat, shaded options."
## A mode that appears in the dropdown and renders identically to its neighbour would satisfy the
## letter of that and none of the point, so the two frames are compared as colour censuses: the
## rim render drops the body to the ramp's dark end and lights the silhouette, which moves a
## large share of the pixels between palette entries.
## FRESNEL must be its OWN render type, not a relabelled SHADED+WIRE (ADR 0009).
##
## "i mean i wanted that rendering effect/node to be listed among wire, flat, shaded options."
## A mode that appears in the dropdown and renders identically to its neighbour would satisfy the
## letter of that and none of the point, so the two frames are compared as colour censuses.
##
## AS A SHARE OF INK, not of the viewport. The ship covers about an eighth of the frame, so
## repainting every single part pixel could never move more than that much of the whole - the
## first draft of this asked for 5% of the viewport and would have failed a mode that changed
## every pixel it was capable of changing.
## ShipConfig.max_bbox_m rather than checking that a node exists.
func _check_bbox_cage() -> void:
	var view: Object = _builder.call("get_view")
	var cfg: ShipConfig = _builder.call("get_config")
	var cage: MeshInstance3D = (view as Node).find_child("BBoxCage", true, false) as MeshInstance3D
	if cage == null:
		_failures.append("there is no max-bounding-box cage in the view at all")
		return
	if not cage.visible or cage.mesh == null:
		_failures.append("the max-bounding-box cage exists but draws nothing")
		return
	var box: AABB = cage.mesh.get_aabb()
	var want: Vector3 = cfg.max_bbox_m
	if not box.size.is_equal_approx(want):
		_failures.append(
			"the max-bbox cage spans %s but the budget is %s" % [str(box.size), str(want)]
		)
		return
	print("  bbox cage: %s m, matching ShipConfig.max_bbox_m" % str(box.size))


## Every rotation ring must turn the part about the circle it is DRAWN around, and every point
## handle must be grabbable and do something - driven through ShipView3D's OWN press/drag path.
##
## THE PATH IS THE POINT. A unit test already asserts the ring axis maths, and it passed for two
## rounds while the gizmo was broken in the app, because it called ShipHandles.hit_test() with the
## handle-set flag supplied BY HAND. The real flag lived in three places with different defaults
## and any focus change reset it, so hit_test returned BALL_ROTATE and every ring spun the part
## about its placement vector. Nothing below supplies any state: it computes a pixel on a drawn
## handle, hands it to the press handler, drags, and reads what moved.
func _check_gizmo() -> void:
	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder") if view != null else null
	var placement: Object = _builder.call("get_placement")
	if view == null or scene == null or placement == null:
		_failures.append("cannot reach the view, scene or placement to drive the gizmo")
		return
	var ids: PackedStringArray = _builder.call("get_selection")
	if ids.is_empty():
		_failures.append("nothing selected, so the gizmo cannot be checked")
		return
	var pid: String = ids[0]
	var cam: Camera3D = view.call("get_orbit_camera").call("get_camera")
	var shape: ResolvedShape = scene.call("part_shape", pid)
	if cam == null or shape == null:
		_failures.append("no camera or shape for the selected part")
		return

	# A focus change used to silently drop the gizmo back to a ball-only handle set. Do it here so
	# the check runs against the state a player actually has after touching a panel.
	view.call("notification", Control.NOTIFICATION_FOCUS_EXIT)

	var checked: int = 0
	for handle: int in ShipHandles.ring_handles():
		placement.call("cancel")
		var xform: Transform3D = scene.call("part_transform", pid)
		var rot: Vector3 = scene.call("part_rot", pid)
		# HOW MUCH of the ring answers to a press, not whether one chosen pixel does. A ring the
		# player can only grab at one lucky pixel is a ring the player cannot grab. The morph
		# ticks and the offset stalk legitimately take precedence where they overlap (see
		# ShipHandles' precedence note), so some of every ring is always someone else's, but a
		# ring that is mostly buried is a defect and the single-pixel probe could not see it.
		var reach: Dictionary = _ring_reach(view, placement, cam, xform, shape, rot, handle)
		var visible: int = int(reach["visible"])
		var mine: int = int(reach["mine"])
		if visible == 0:
			continue
		var share: float = float(mine) / float(visible)
		if mine == 0:
			(
				_failures
				. append(
					(
						(
							"ring %d: none of its %d on-screen points starts a drag on it - the ring is "
							+ "drawn but not grabbable anywhere"
						)
						% [handle, visible]
					)
				)
			)
			continue
		if share < RING_GRAB_MIN_SHARE:
			_failures.append(
				(
					(
						"ring %d is grabbable on only %.0f%% of its visible circle (%d of %d "
						+ "points); below the %.0f%% a player can reasonably hit"
					)
					% [handle, share * 100.0, mine, visible, RING_GRAB_MIN_SHARE * 100.0]
				)
			)
		var grab: Vector2 = reach["best"]
		var drawn: Vector3 = (xform.basis * ShipHandles.ring_axis_local(handle, rot)).normalized()
		placement.call("cancel")
		if not bool(view.call("_try_begin_handle_drag", grab)):
			_failures.append("ring %d: a press on its own circle started no drag" % handle)
			continue
		var got: int = int(view.get("_handle_drag"))
		if got != handle:
			_failures.append("ring %d: grabbing its own circle returned handle %d" % [handle, got])
			continue
		var before: Transform3D = placement.call("preview_transform")
		view.call("_drive_handle", grab + Vector2(60.0, 0.0))
		var after: Transform3D = placement.call("preview_transform")
		var quat: Quaternion = (after.basis * before.basis.inverse()).get_rotation_quaternion()
		var actual: Vector3 = Vector3(quat.x, quat.y, quat.z)
		if actual.length_squared() < 1.0e-9:
			_failures.append("ring %d: dragging it rotated nothing" % handle)
			continue
		var agreement: float = absf(drawn.dot(actual.normalized()))
		if agreement <= 0.99:
			_failures.append(
				(
					"ring %d is drawn about %s but turns the part about %s"
					% [handle, str(drawn), str(actual.normalized())]
				)
			)
		checked += 1

	checked += _check_point_handle(view, scene, placement, cam, shape, pid)
	checked += _check_placement_handle(view, scene, placement, cam, pid)
	_check_pivot_modes(view, placement, pid)
	placement.call("cancel")
	_check_gizmo_solid(scene, shape)
	print("  gizmo: %d handles driven through the real press/drag path" % checked)


## The placement handle is the FOOTPRINT COLLAR on the parent's surface (ShipHandles.footprint_loop,
## 2026-09-02): grabbable somewhere round its circle, and the grab is a PLACEMENT drag.
##
## "i dont see the handles for the placement vector on the parent i only see the ones that try to
## rotate the child piece." A handle that draws but cannot be grabbed would satisfy the letter of
## that and none of the point, so this presses pixels ON the drawn collar and checks that the
## press handler claims one of them. RETIRED(2026-09-02): a press two thirds of the way along the
## parent-origin -> part-origin arrow, which is a reference line now and grabs nothing.
func _check_placement_handle(
	view: Object, scene: Object, placement: Object, cam: Camera3D, pid: String
) -> int:
	var doc: ShipDoc = _builder.call("get_doc")
	var part: ShipPart = doc.parts.get(pid, null) as ShipPart
	if part == null or part.parent.is_empty():
		return 0
	placement.call("cancel")
	if not bool(scene.call("part_has_seam", pid)):
		_failures.append("the selected part has a parent but no seam to draw its collar in")
		return 0
	var xform: Transform3D = scene.call("part_transform", pid)
	var shape: ResolvedShape = scene.call("part_shape", pid)
	var seam: Transform3D = scene.call("part_seam", pid)
	var loop: PackedVector3Array = ShipHandles.footprint_loop(shape, seam)
	var tried: int = 0
	var others: int = 0
	for p: Vector3 in loop:
		var world: Vector3 = xform * p
		if cam.is_position_behind(world):
			continue
		var grab: Vector2 = cam.unproject_position(world)
		tried += 1
		placement.call("cancel")
		if not bool(view.call("_try_begin_handle_drag", grab)):
			continue
		if int(view.get("_handle_drag")) == ShipPlacement.Handle.PLACEMENT:
			placement.call("cancel")
			return 1
		others += 1
	placement.call("cancel")
	(
		_failures
		. append(
			(
				(
					"the footprint collar is drawn but none of its %d on-screen points starts a PLACEMENT "
					+ "drag (%d of them grabbed some other handle)"
				)
				% [tried, others]
			)
		)
	)
	return 0


## The gizmo is SOLID geometry with screen floors (ShipHandles, 2026-09-02): triangle surfaces,
## not lines, and an arrow head that is never smaller on screen than HEAD_PX whatever the zoom.
## "the visual handle system is barely visible" was one-pixel lines through the quantizer.
func _check_gizmo_solid(scene: Object, shape: ResolvedShape) -> void:
	var handles: MeshInstance3D = scene.get("_handles") as MeshInstance3D
	if handles == null or handles.mesh == null:
		_failures.append("gizmo: no handle mesh on the selected part")
		return
	var mesh: ImmediateMesh = handles.mesh as ImmediateMesh
	if mesh == null:
		_failures.append("gizmo: the handle mesh is not an ImmediateMesh")
		return
	# ImmediateMesh does not expose surface_get_primitive_type(); the server does, per surface.
	var tri_surfaces: int = 0
	for s: int in mesh.get_surface_count():
		var surface: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		if int(surface.get("primitive", -1)) == RenderingServer.PRIMITIVE_TRIANGLES:
			tri_surfaces += 1
	if tri_surfaces < 2:
		_failures.append(
			(
				"gizmo: %d triangle surfaces on the handle mesh - the handles are still lines"
				% tri_surfaces
			)
		)
	var m_per_px: float = float(scene.get("_m_per_px"))
	if m_per_px <= 0.0:
		_failures.append("gizmo: no metres-per-pixel was pushed, so the screen floors are off")
		return
	var head_px: float = ShipHandles.head_radius(shape, m_per_px) / m_per_px
	var length_px: float = ShipHandles.arrow_length(shape, m_per_px) / m_per_px
	if head_px < ShipHandles.HEAD_PX - 0.01:
		_failures.append(
			"gizmo: arrow head is %.1f px on screen, floor is %.1f" % [head_px, ShipHandles.HEAD_PX]
		)
	if length_px < ShipHandles.ARROW_PX - 0.01:
		_failures.append(
			(
				"gizmo: arrow is %.1f px long on screen, floor is %.1f"
				% [length_px, ShipHandles.ARROW_PX]
			)
		)
	print(
		(
			"  gizmo: solid - %d triangle surfaces, arrow head %.1f px, arrow %.1f px long"
			% [tri_surfaces, head_px, length_px]
		)
	)


## Arrow keys step the selection's PLACEMENT VECTOR by one snap increment in the parent's frame
## (ShipReseat.step_placement, 2026-09-02): RIGHT is yaw plus one snap, UP is pitch plus one
## snap, Shift makes the step coarse, and a stepped part leaves its snap target. "pressing arrow
## keys doesnt work properly, moves the object almost randomly at large 90 degree snaps" was
## the arrows walking the parent's SnapTargets list.
func _check_arrows() -> void:
	var view: Object = _builder.call("get_view")
	var ids: PackedStringArray = _builder.call("get_selection")
	var doc: ShipDoc = _builder.call("get_doc")
	if view == null or doc == null or ids.size() != 1:
		_failures.append("arrows: need exactly one selected part to step")
		return
	var pid: String = ids[0]
	var part: ShipPart = doc.parts.get(pid, null) as ShipPart
	if part == null or part.parent.is_empty():
		_failures.append("arrows: the selected part has no parent to step across")
		return
	var snap: float = float(view.call("_snap_degrees"))
	var yaw0: float = part.yaw
	var pitch0: float = part.pitch
	var history: Object = _builder.call("get_history")
	var undo_before: bool = bool(history.call("can_undo"))
	_press_key(view, KEY_RIGHT, false)
	part = (_builder.call("get_doc") as ShipDoc).parts[pid]
	var want_yaw: float = ShipAttach.wrap_yaw_deg(roundf((yaw0 + snap) / snap) * snap)
	if not is_equal_approx(part.yaw, want_yaw):
		_failures.append(
			"arrows: RIGHT took yaw from %.3f to %.3f, expected %.3f" % [yaw0, part.yaw, want_yaw]
		)
	if not is_equal_approx(part.pitch, pitch0):
		_failures.append("arrows: RIGHT moved pitch from %.3f to %.3f" % [pitch0, part.pitch])
	if not part.snap_id.is_empty():
		_failures.append("arrows: a stepped part still carries snap target '%s'" % part.snap_id)
	_press_key(view, KEY_UP, false)
	part = (_builder.call("get_doc") as ShipDoc).parts[pid]
	var want_pitch: float = clampf(roundf((pitch0 + snap) / snap) * snap, -90.0, 90.0)
	if not is_equal_approx(part.pitch, want_pitch):
		_failures.append(
			(
				"arrows: UP took pitch from %.3f to %.3f, expected %.3f"
				% [pitch0, part.pitch, want_pitch]
			)
		)
	var yaw_after_right: float = part.yaw
	_press_key(view, KEY_LEFT, true)
	part = (_builder.call("get_doc") as ShipDoc).parts[pid]
	var coarse: float = maxf(snap, float(view.get("NUMPAD_COARSE")))
	var want_coarse: float = ShipAttach.wrap_yaw_deg(
		roundf((yaw_after_right - coarse) / coarse) * coarse
	)
	if not is_equal_approx(part.yaw, want_coarse):
		_failures.append(
			(
				"arrows: SHIFT+LEFT took yaw from %.3f to %.3f, expected %.3f"
				% [yaw_after_right, part.yaw, want_coarse]
			)
		)
	# Three undoable edits, and the part is back where it started.
	_builder.call("undo")
	_builder.call("undo")
	_builder.call("undo")
	part = (_builder.call("get_doc") as ShipDoc).parts[pid]
	if not is_equal_approx(part.yaw, yaw0) or not is_equal_approx(part.pitch, pitch0):
		_failures.append(
			(
				"arrows: three undos left the part at (%.3f, %.3f), started at (%.3f, %.3f)"
				% [part.yaw, part.pitch, yaw0, pitch0]
			)
		)
	if bool(history.call("can_undo")) != undo_before:
		_failures.append("arrows: the undo stack did not return to where it was")
	print(
		(
			"  arrows: RIGHT +%.2f yaw, UP +%.2f pitch, SHIFT+LEFT -%.0f yaw, all undone"
			% [snap, snap, coarse]
		)
	)


## A key press through the view's own handler, the way the keyboard reaches it.
func _press_key(view: Object, keycode: int, shift: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = keycode as Key
	ev.physical_keycode = keycode as Key
	ev.pressed = true
	ev.shift_pressed = shift
	view.call("_handle_key", ev)


## FLOATING and ATTACHED must do DIFFERENT things with the same ring.
##
## "attached pivot changes the angle of the placement vector extending from the parents placement
## spot. but floating rotation rotates the part around its center." A mode flag that both branches
## honour by accident - or that only changes a label - is the exact failure this project has
## already paid for once (the Tab-gated handle set), so each mode is driven and the OTHER value is
## asserted to have stayed put.
func _check_pivot_modes(view: Object, placement: Object, pid: String) -> void:
	for attached: bool in [false, true]:
		placement.call("cancel")
		placement.call("begin_move", pid)
		if not bool(placement.get("active")):
			_failures.append("begin_move refused, so the pivot modes cannot be checked")
			return
		view.set("_attached_pivot", attached)
		view.set("_handle_drag", ShipPlacement.Handle.RING_X)
		view.set("_handle_last", Vector2.ZERO)
		var before: Dictionary = placement.call("values")
		view.call("_drive_handle", Vector2(80.0, 0.0))
		var after: Dictionary = placement.call("values")
		var turned: float = ((after["rot"] as Vector3) - (before["rot"] as Vector3)).length()
		var swung: float = (
			absf(float(after["yaw"]) - float(before["yaw"]))
			+ absf(float(after["pitch"]) - float(before["pitch"]))
		)
		var name: String = "ATTACHED" if attached else "FLOATING"
		print("  pivot %-8s: rot moved %.3f, placement moved %.3f deg" % [name, turned, swung])
		if attached:
			if swung <= 0.01:
				_failures.append("ATTACHED pivot: a ring drag did not move the placement vector")
			if turned > 0.01:
				(
					_failures
					. append(
						(
							(
								"ATTACHED pivot: a ring drag ALSO spun the part by %.3f - the two modes are "
								% turned
							)
							+ "not separate"
						)
					)
				)
		else:
			if turned <= 0.01:
				_failures.append("FLOATING pivot: a ring drag did not rotate the part")
			if swung > 0.01:
				_failures.append(
					(
						"FLOATING pivot: a ring drag ALSO moved the placement vector by %.3f deg"
						% swung
					)
				)
	view.set("_attached_pivot", false)
	view.set("_handle_drag", ShipPlacement.Handle.NONE)
	placement.call("cancel")


# ---------------------------------------------------------------- release survival (F13)


## A part must survive the release of every gizmo gesture and of a move that ends over its own
## body; only a move released in EMPTY SPACE removes it (Spore's drag-off, SPORE_CLONE_SPEC
## section 2).
##
## This gate exists because the opposite shipped: the placement arrow won hit-test ties against
## the rings, an "ordinary drag" release re-solved the ghost from the pointer, the probe ignores
## the moving part, and remove_if_dragged_off() deleted on any collider miss. A rotation that
## strayed a few pixels off the parent's silhouette, or a Ctrl-drag that sank a part into its
## parent, deleted it - "undo brings it back" (FOLLOWUPS F13). Each gesture below is driven
## through the REAL input path (_handle_placement_input, resolved in _physics_process), and the
## verdict is read frames later, once the release has actually landed.
##
## Returns true when every step has run.
func _check_release_survival() -> bool:
	if _frames == 1:
		_release_step = 0
		var ids: PackedStringArray = _builder.call("get_selection")
		_release_pid = "" if ids.is_empty() else ids[0]
		if _release_pid == "":
			_failures.append("nothing selected, so release survival cannot be checked")
			return true
		var doc: ShipDoc = _builder.call("get_doc")
		var part: ShipPart = doc.parts.get(_release_pid, null) as ShipPart
		_release_family = "" if part == null else part.family
	# Six frames per step: the ghost ray and the commit each take a physics frame, and the scene
	# builder rebuilds on the frame after the commit.
	if (_frames % 6) != 0:
		return false
	match _release_step:
		0:
			_release_gesture_arrow()
		1:
			_release_verdict("placement-arrow drag", false)
			_release_gesture_self_move()
		2:
			_release_verdict("G-move released over the part's own body", false)
			_release_gesture_ctrl_sink()
		3:
			_release_verdict("Ctrl-drag sinking the part into its parent", false)
			_release_gesture_ring()
		4:
			_release_verdict("ring drag released off the silhouette", false)
			_release_gesture_void()
		5:
			_release_verdict("G-move released in empty space", true)
			return true
	_release_step += 1
	return false


## Every step reads the document AFTER the previous step's release has landed. A part that is
## gone when it should not be fails; so does one that stayed when it should be gone.
func _release_verdict(label: String, expect_gone: bool) -> void:
	var doc: ShipDoc = _builder.call("get_doc")
	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder")
	var in_doc: bool = doc != null and doc.parts.has(_release_pid)
	var drawn: bool = in_doc and (scene.get("_visuals") as Dictionary).has(_release_pid)
	var gone: bool = not in_doc or not drawn
	print("  release %-46s -> %s" % [label, "gone" if gone else "kept"])
	if gone != expect_gone:
		_failures.append(
			(
				"%s: the part was %s (in_doc=%s drawn=%s)"
				% [label, "REMOVED" if gone else "kept", str(in_doc), str(drawn)]
			)
		)
	if gone and not expect_gone:
		# Put it back so the next gesture has something to drive.
		_release_pid = _builder.call("add_part", _release_family, "", doc.root)
		_builder.call("set_selection", PackedStringArray([_release_pid]))


func _release_view() -> Object:
	return _builder.call("get_view")


# ---------------------------------------------------------------- make component


## MAKE COMP on a multi-selection must leave every part on screen, exactly where it was.
##
## This gate exists because the opposite shipped: a lifted subtree resolved to its head alone -
## the attach pass placed the definition root as the instance's proxy and nothing drew the
## rest - so "when i selected multiple parts and press make component they all dissapear".
## Driven through the builder's own edit protocol, the way part_tree.gd's MAKE COMP is, and
## read back off the scene builder's visuals: the lift must keep every mesh (same count, same
## origins), a click on an inner mesh must resolve to the instance, selecting the instance must
## highlight all of it, and undo must restore the original ids.
func _check_make_component() -> void:
	_check_make_component_body()


func _check_make_component_body() -> bool:
	var doc: ShipDoc = _builder.call("get_doc")
	var scene: Object = _builder.call("get_view").call("get_scene_builder")
	var head: String = _make_component_subtree(doc)
	if head == "":
		_failures.append("make component: could not build a two-deep subtree to lift")
		return false
	var ids: PackedStringArray = PackedStringArray([head])
	ids.append_array(doc.descendants_of(head))
	var before: Dictionary = _visual_origins(scene)
	var before_keys: PackedStringArray = _sorted_keys(before)

	_builder.call("set_selection", ids)
	_builder.call("begin_edit", "make component")
	var comp_id: String = ShipComponents.make_component(doc, ids, "GATE ARM")
	if comp_id == "":
		_failures.append("make component: ShipComponents.make_component refused %s" % [ids])
		return false
	_builder.call("commit_edit", PackedStringArray())
	doc = _builder.call("get_doc")
	var instance_id: String = ""
	for pid: String in doc.parts:
		if (doc.parts[pid] as ShipPart).kind == ShipPart.KIND_COMPONENT_INSTANCE:
			instance_id = pid
	if instance_id == "" or not doc.components.has(comp_id):
		_failures.append("make component: the edit did not leave an instance in the document")
		return false

	var after: Dictionary = _visual_origins(scene)
	var inner: int = 0
	for key: Variant in after.keys():
		if str(key).begins_with(instance_id + "/") and not ShipSymmetry.is_twin_id(str(key)):
			inner += 1
	print(
		(
			"  make component: %d parts lifted -> instance %s, meshes %d before / %d after, %d inner"
			% [ids.size(), instance_id, before.size(), after.size(), inner]
		)
	)
	if inner != ids.size() - 1:
		_failures.append(
			(
				"make component: %d parts were lifted but %d inner meshes are drawn - keys %s"
				% [ids.size(), inner, _sorted_keys(after)]
			)
		)
	_assert_same_origins(before, after, "make component")
	_check_scene_matches_attach(doc, scene, "make component")

	# A click on an inner mesh is a click on the component.
	var visuals: Dictionary = scene.get("_visuals")
	for key: Variant in after.keys():
		var pid: String = str(key)
		if not pid.begins_with(instance_id + "/") or ShipSymmetry.is_twin_id(pid):
			continue
		var body: Node = visuals[pid].get("body")
		var picked: String = scene.call("part_id_for", body)
		if picked != instance_id:
			_failures.append(
				"make component: clicking %s resolves to '%s', not its instance" % [pid, picked]
			)
	# Selecting the instance highlights all of it.
	_builder.call("set_selection", PackedStringArray([instance_id]))
	for key: Variant in after.keys():
		var pid: String = str(key)
		var owner: String = ShipComponents.instance_of(pid)
		var lit: bool = bool(visuals[pid].get("selected"))
		if owner == instance_id and not lit:
			_failures.append("make component: %s is part of the selected instance but unlit" % pid)
		elif owner != instance_id and lit:
			_failures.append("make component: %s is lit but not part of the selection" % pid)

	_builder.call("undo")
	var restored: Dictionary = _visual_origins(scene)
	var restored_keys: PackedStringArray = _sorted_keys(restored)
	if restored_keys != before_keys:
		_failures.append("make component: undo drew %s, expected %s" % [restored_keys, before_keys])
	_assert_same_origins(before, restored, "make component undo")
	return true


## A head part with a child and a grandchild, built from what the demo ship left behind so the
## lift has real depth to it. Returns the head id, or "" when nothing could be added.
func _make_component_subtree(doc: ShipDoc) -> String:
	var head: String = ""
	for pid: String in doc.parts:
		var part: ShipPart = doc.parts[pid]
		if pid != doc.root and part.kind == ShipPart.KIND_PRIMITIVE and part.mirror_source == "":
			head = pid
			break
	if head == "":
		return ""
	var data: ShipData = _builder.call("get_data")
	var families: PackedStringArray = data.family_ids()
	var child: String = _builder.call("add_part", families[families.size() - 1], "", head)
	if child == "":
		return ""
	var grandchild: String = _builder.call("add_part", families[0], "", child)
	if grandchild == "":
		return ""
	var gc: ShipPart = doc.parts[grandchild]
	gc.yaw = 70.0
	gc.pitch = 25.0
	_builder.call("begin_edit", "tilt")
	_builder.call("commit_edit", PackedStringArray([grandchild]))
	return head


## Every part is a room, any two parts that meet can be hatched, and several parts linked together
## step every seam between them at once and stay on screen (2026-09-02, 2026-09-04).
##
## This gate exists because the opposite shipped: "when trying to link my tunnel with my sphere
## it sys 'tunnel isnt a room yet'". Everything below is driven through the tree panel's own
## button handlers and the builder's own in-scene dialog, the way a player reaches them, and
## read back off the document, the dialog and the scene builder's visuals.
func _check_rooms_and_hatches() -> void:
	var tree: Object = _find_named(_host, "PartTreePanel")
	if tree == null:
		_failures.append("rooms: no PartTreePanel in the scene")
		return
	var doc: ShipDoc = _builder.call("get_doc")
	var root: String = doc.root
	# Every part is a room with nothing declared.
	for pid: String in doc.parts:
		var part: ShipPart = doc.parts[pid]
		if not part.is_room():
			_failures.append("rooms: %s is not a room by default (role '%s')" % [pid, part.role])
	var tunnel: String = _rooms_toggle_hatch(tree, root)
	if tunnel == "":
		return
	var far: String = _rooms_refuse_far_pair(tree, root, tunnel)
	if far == "":
		return
	_rooms_link_group(tree, root, tunnel)


## A tunnel dropped on the hull links to it - nothing declared first - and LINK cycles the seam
## WALL -> DOORWAY -> HATCH -> OPEN -> WALL (ADR 0008). Returns the tunnel's id, or "" when
## nothing could be added. RETIRED(2026-09-02): LINK HATCH toggling hatched / nothing.
func _rooms_toggle_hatch(tree: Object, root: String) -> String:
	var families: PackedStringArray = (_builder.call("get_data") as ShipData).family_ids()
	var tunnel: String = _builder.call("add_part", _family_or(families, "cylinder_spar"), "", root)
	if tunnel == "":
		_failures.append("rooms: could not add a tunnel to link")
		return ""
	_builder.call("set_selection", PackedStringArray([root, tunnel]))
	if _link_mode(root, tunnel) != "wall":
		_failures.append("rooms: a fresh tunnel on the hull is not a WALL by default")
	var expected: Array = ["doorway", "hatched", "open", "wall"]
	var wanted_joint: Array = [
		ShipJoint.MODE_DOORWAY, ShipJoint.MODE_HATCHED, ShipJoint.MODE_OPEN, ""
	]
	for i: int in expected.size():
		tree.call("_on_link")
		_expect_no_dialog("rooms: LINK press %d on a tunnel at its default placement" % (i + 1))
		var mode: String = _link_mode(root, tunnel)
		if mode != expected[i]:
			_failures.append(
				"rooms: LINK press %d left the seam %s, expected %s" % [i + 1, mode, expected[i]]
			)
		var joint: ShipJoint = _joint_between(_builder.call("get_doc"), root, tunnel)
		var stored: String = joint.mode if joint != null else ""
		if stored != wanted_joint[i]:
			_failures.append(
				(
					"rooms: LINK press %d stored joint mode '%s', expected '%s'"
					% [i + 1, stored, wanted_joint[i]]
				)
			)
	# Leave the pair HATCHED, as the join stage expects the hull-to-tunnel hatch to be carried.
	tree.call("_on_link")
	tree.call("_on_link")
	if not _hatched(_builder.call("get_doc"), root, tunnel):
		_failures.append("rooms: two more LINK presses did not bring the pair back to HATCH")
	return tunnel


func _link_mode(a: String, b: String) -> String:
	return ShipSeams.mode_for(_builder.call("get_doc"), a, b)


## Two parts that do not meet are refused, with the fix named, and no joint is written. Returns
## the far part's id, or "" when it could not be placed.
func _rooms_refuse_far_pair(tree: Object, root: String, tunnel: String) -> String:
	var families: PackedStringArray = (_builder.call("get_data") as ShipData).family_ids()
	var far: String = _builder.call("add_part", _family_or(families, "sphere_pod"), "", root)
	if far == "":
		_failures.append("rooms: could not add a part on the far side")
		return ""
	var doc: ShipDoc = _builder.call("get_doc")
	(doc.parts[far] as ShipPart).yaw = 180.0
	_builder.call("begin_edit", "aim")
	_builder.call("commit_edit", PackedStringArray([far]))
	doc = _builder.call("get_doc")
	if not doc.parts.has(far) or not is_equal_approx((doc.parts[far] as ShipPart).yaw, 180.0):
		_failures.append("rooms: could not aim a part at the far side of the hull")
		return ""
	_builder.call("set_selection", PackedStringArray([tunnel, far]))
	tree.call("_on_link")
	var refusal: String = _dialog_title()
	if refusal != "LINK":
		_failures.append(
			"rooms: LINK on parts that do not meet was not refused (dialog '%s')" % refusal
		)
	elif not _dialog_body().contains("DO NOT MEET"):
		_failures.append(
			"rooms: the refusal does not say the parts do not meet: %s" % _dialog_body()
		)
	_builder.call("_close_dialog")
	if _joint_between(doc, tunnel, far) != null:
		_failures.append("rooms: a joint was written between parts that do not meet")
	return far


## Sinks [param pid] into its host until their interiors meet, by the same test the panel refuses
## on. Returns false - having recorded the failure - when no reachable depth does it.
##
## Offsets are NEGATIVE inward (ShipAttach.default_offset), and the placement is affine in the
## offset, so stepping down by a fraction of the part own height walks it straight in.
func _sink_until_meeting(pid: String) -> bool:
	var doc: ShipDoc = _builder.call("get_doc")
	var data: ShipData = _builder.call("get_data")
	var cfg: ShipConfig = _builder.call("get_config")
	var part: ShipPart = doc.parts[pid]
	var host: String = part.parent
	var step: float = maxf(cfg.attach_embed_m, 0.25)
	for i: int in 8:
		var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
		var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
		if shapes.has(pid) and shapes.has(host):
			var state: Dictionary = ShipJoints.solid_pair_state(
				shapes[pid],
				xforms[pid],
				shapes[host],
				xforms[host],
				maxf(cfg.hull_thickness_m, 0.0)
			)
			if bool(state["merges"]):
				return true
		_builder.call("begin_edit", "sink")
		(doc.parts[pid] as ShipPart).offset -= step
		_builder.call("commit_edit", PackedStringArray([pid]))
		doc = _builder.call("get_doc")
	_failures.append("rooms: could not sink %s into %s deep enough to link" % [pid, host])
	return false


## LINK ON SEVERAL PARTS steps every seam inside the selection together - which is what making
## them one room now is. A chain of three under the tunnel goes WALL -> DOORWAY -> HATCH -> OPEN
## -> WALL as a unit, every part stays a part of its own, nothing on screen moves, and undo walks
## it back one press at a time.
##
## RETIRED(2026-09-04): _rooms_name_one and _rooms_join_three, which drove MAKE ROOM. Naming is the
## tree row own edit; joining is this. The old join lifted the selection into a COMPONENT and left
## the seams between the joined parts WALLED, which is the opposite of what it promised - a dropped
## joint record IS a wall.
func _rooms_link_group(tree: Object, root: String, tunnel: String) -> void:
	var scene: Object = _builder.call("get_view").call("get_scene_builder")
	var families: PackedStringArray = (_builder.call("get_data") as ShipData).family_ids()
	var child: String = _builder.call("add_part", families[0], "", tunnel)
	# A POD on the end, not whatever family sorts last: a part thinner than two hull walls has no
	# interior at all (ADR 0015), and two solids whose interiors do not exist can never be linked
	# however deep one is sunk into the other.
	var grandchild: String = _builder.call(
		"add_part", _family_or(families, "sphere_pod"), "", child
	)
	if child == "" or grandchild == "":
		_failures.append("rooms: could not grow a chain under the tunnel to link")
		return
	# A part dropped at its default embed can end up merely TOUCHING its host - the two solids
	# overlap but their interiors do not, at the hull thickness - and LINK rightly refuses to open
	# an opening that would lead into solid hull. That refusal has its own gate above; here the
	# chain has to be a chain, so each one is sunk until it really is.
	if not (_sink_until_meeting(child) and _sink_until_meeting(grandchild)):
		return
	# The scene builder rebuilds on the frame AFTER a commit and the sinking above just committed,
	# so the baseline is forced current rather than read one frame behind the document.
	_builder.call("get_view").call(
		"rebuild", _builder.call("get_doc"), _builder.call("get_data"), _builder.call("get_config")
	)
	var before: Dictionary = _visual_origins(scene)
	var before_keys: PackedStringArray = _sorted_keys(before)
	var members: PackedStringArray = PackedStringArray([tunnel, child, grandchild])
	var inner: Array = [[child, tunnel], [grandchild, child]]

	_builder.call("set_selection", members)
	var steps: Array = ["doorway", "hatched", "open", "wall"]
	for i: int in steps.size():
		tree.call("_on_link")
		_expect_no_dialog("rooms: LINK press %d on a chain of three" % (i + 1))
		for pair: Array in inner:
			var mode: String = _link_mode(str(pair[0]), str(pair[1]))
			if mode != steps[i]:
				_failures.append(
					(
						"rooms: LINK press %d left %s<->%s at %s, expected %s"
						% [i + 1, pair[0], pair[1], mode, steps[i]]
					)
				)

	var doc: ShipDoc = _builder.call("get_doc")
	for pid: String in members:
		if not doc.parts.has(pid):
			_failures.append("rooms: %s stopped being a part of its own after LINK" % pid)
	if _joint_between(doc, root, tunnel) == null:
		_failures.append("rooms: linking the group inside disturbed the seam to the hull")
	_assert_same_origins(before, _visual_origins(scene), "link group")
	_check_scene_matches_attach(doc, scene, "link group")

	# One press, one edit: four steps back and every seam is where it started, with the parts still
	# on screen where the sinking left them.
	for _i: int in steps.size():
		_builder.call("undo")
	doc = _builder.call("get_doc")
	for pair: Array in inner:
		if _link_mode(str(pair[0]), str(pair[1])) != "wall":
			_failures.append("rooms: undo left %s<->%s linked" % [pair[0], pair[1]])
	var restored_keys: PackedStringArray = _sorted_keys(_visual_origins(scene))
	if restored_keys != before_keys:
		_failures.append("rooms: undo drew %s, expected %s" % [restored_keys, before_keys])
	print(
		(
			(
				"  rooms: %d parts all rooms; seam cycled WALL/DOORWAY/HATCH/OPEN on hull+tunnel; "
				+ "far pair refused; %d seams inside a 3-part selection cycled as one; "
				+ "undo restored %d meshes"
			)
			% [doc.parts.size(), inner.size(), restored_keys.size()]
		)
	)


## EXPLODE pulls every module apart as its own bake and ASSEMBLE puts the parts back (ADR 0008).
## "we want an auto explode btn that explodes all the modules apart revealing their internal hatch
## walls." Frame-driven: the view bakes one module per frame. Returns true when done.
##
## Read back off the scene: as many module meshes as the field has modules, every part visual
## hidden meanwhile, a frame saved to reports/visual_explode.png with ink in it, and everything
## restored on the way back.
func _check_explode() -> bool:
	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder") if view != null else null
	var explode: Object = view.call("get_explode_view") if view != null else null
	if view == null or scene == null or explode == null:
		_failures.append("explode: cannot reach the view, scene or explode view")
		return true
	if _explode_step == 0:
		_explode_begin()
		return false
	if _explode_step == 1:
		return _explode_wait(scene, explode)
	if _frames < MODE_FRAMES:
		return false
	_explode_finish(scene, explode)
	return true


## Count what the field will explode into, then press EXPLODE.
func _explode_begin() -> void:
	var doc: ShipDoc = _builder.call("get_doc")
	var data: ShipData = _builder.call("get_data")
	var cfg: ShipConfig = _builder.call("get_config")
	var sdf: ShipSdf = ShipSdf.build(doc, data, cfg)
	_explode_expected = _views.module_count(doc)
	_explode_seams = sdf.seam_count()
	_builder.call("_set_exploded", true)
	_frames = 0
	if bool(_builder.get("_exploded")):
		_explode_step = 1
		return
	_failures.append("explode: _set_exploded(true) did not take")
	_explode_step = 2


## Wait for the last module to bake, then read the exploded scene back. Returns true only when
## the stage must abort.
func _explode_wait(scene: Object, explode: Object) -> bool:
	# Two waits: the engine bake the builder awaits before it hands modules to the view (ADR
	# 0020), and then the view placing them a module a frame.
	if (_builder.get("_bake_session") as ShipBakeSession).busy or bool(explode.call("is_busy")):
		if _frames <= EXPLODE_MAX_FRAMES:
			return false
		_failures.append("explode: still baking after %d frames" % _frames)
		_builder.call("_set_exploded", false)
		return true
	var count: int = int(explode.call("module_count"))
	_views.check_explode_picking(explode)
	_views.check_explode_display_mode(explode)
	if count != _explode_expected:
		_failures.append(
			(
				"explode: %d module meshes on screen, the field has %d modules"
				% [count, _explode_expected]
			)
		)
	var visuals: Dictionary = scene.get("_visuals")
	for key: Variant in visuals.keys():
		var solid: MeshInstance3D = visuals[key].get("solid")
		if solid != null and solid.visible:
			_failures.append("explode: part %s is still visible under the exploded view" % str(key))
			break
	var box: AABB = explode.call("bounds")
	if box.size.length() <= 0.0:
		_failures.append("explode: the exploded view has no bounds")
	_explode_step = 2
	_frames = 0
	return false


## Capture the exploded frame, press ASSEMBLE, and check everything came back.
func _explode_finish(scene: Object, explode: Object) -> void:
	_capture_explode()
	_builder.call("_set_exploded", false)
	if bool(_builder.get("_exploded")):
		_failures.append("explode: _set_exploded(false) did not take")
	# ASSEMBLE lands in the BAKED view (ADR 0023): the same bake, the pieces where they stand,
	# the primitives still hidden. Leaving that view is what brings the primitives back.
	if not bool(_builder.get("_baked")) or not bool(explode.call("is_assembled")):
		_failures.append("explode: ASSEMBLE did not land in the baked assembled view")
	# The view places a module a frame, so on this frame the baked view is either still placing
	# or already full.
	if not bool(explode.call("is_busy")) and int(explode.call("module_count")) != _explode_expected:
		_failures.append(
			(
				"explode: %d module meshes after ASSEMBLE, the field has %d modules"
				% [int(explode.call("module_count")), _explode_expected]
			)
		)
	_builder.call("_set_baked", false)
	if int(explode.call("module_count")) != 0:
		_failures.append("explode: module meshes left behind after leaving the baked view")
	var visuals: Dictionary = scene.get("_visuals")
	var shown: int = 0
	for key: Variant in visuals.keys():
		var solid: MeshInstance3D = visuals[key].get("solid")
		if solid != null and solid.visible:
			shown += 1
	if shown == 0:
		_failures.append("explode: no part visual came back after leaving the baked view")
	print(
		(
			(
				"  explode: %d modules baked from %d seams, parts hidden meanwhile, ASSEMBLE "
				+ "landed baked, %d visuals back after leaving it"
			)
			% [_explode_expected, _explode_seams, shown]
		)
	)


## One frame of the exploded view, saved beside the mode captures and checked for ink and for
## palette purity the same way.
func _capture_explode() -> void:
	var vp: SubViewport = _app_viewport(_host)
	if vp == null:
		_failures.append("explode: no AppViewport to read back")
		return
	var img: Image = vp.get_texture().get_image()
	if img == null:
		_failures.append("explode: viewport returned no image")
		return
	var path: String = "%s/visual_explode.png" % OUT_DIR
	var err: Error = img.save_png(path)
	if err != OK:
		_failures.append("explode: save_png failed (%d)" % err)
	var hist: Dictionary = _histogram(img)
	var counts: Dictionary = hist["counts"]
	var total: int = int(hist["total"])
	var background: String = _palette[0] if not _palette.is_empty() else "081216"
	var ink: int = 0
	for key: Variant in counts.keys():
		if String(key) != background:
			ink += int(counts[key])
	var ink_frac: float = float(ink) / float(maxi(total, 1))
	if ink_frac < MIN_INK:
		_failures.append(
			"explode: only %.1f%% of the 3D view is non-background" % (ink_frac * 100.0)
		)
	print("  explode      -> %s  (%.1f%% ink)" % [path, ink_frac * 100.0])


## Clicking an exploded module must select the part it was baked from, and must NOT assemble.
##
## "exploded view does not let part selection." The click goes through the view's real press and
## release handlers at the module's own screen position, so a pick body that is missing, on the
## wrong layer or carrying the wrong id fails here rather than in someone's hands. On a miss the
## ray is re-cast directly and what it found is reported: "no body at all" and "a different
## module was in front" are different bugs.
## Clicking an exploded module must select the part it was baked from, and must NOT assemble.
##
## "exploded view does not let part selection." The click goes through the view's real press and
## release handlers at the module's own screen position, so a pick body that is missing, on the
## wrong layer or carrying the wrong id fails here rather than in someone's hands. On a miss it
## reports the body itself and whether an ASSEMBLED part is reachable from the same camera, which
## is the difference between "my bodies are wrong" and "nothing on this layer is reachable".
## What a pick ray hits, in words.
## The state of one module's pick body.
## Whether an ASSEMBLED part's pick body - the same machinery, built by ShipSceneBuilder - is
## reachable from the same camera.
## What a pick ray hits, in words, for a picking failure message.
## The render type must reach the modules: "doesnt render it anything other then flat".
##
## Switched to a mode known to differ from the one on screen. The first draft switched TO fresnel
## while the capture loop had already left the view in fresnel, so it asserted that a no-op
## changed something.
## A mouse button event at `at`, for driving the view's own handlers.
## Right-clicking two selected parts opens the seam menu, and each option writes its style
## (ADR 0009). Driven through the view's own right-button tracker and the menu's own buttons.
## NEXT on the tutorial card must advance - every press, at every step, done or not.
##
## "also tutorial next btn doesnt work so i couldnt test." The button was disabled until the
## step's predicate held, so a player who could not do a step could not skip it either. This
## opens the card, reads which step it shows, and presses NEXT through to FINISH, asserting each
## press moved the card on and the last one closed it.
func _check_tutorial() -> void:
	var tutorial: Object = _builder.get("_tutorial")
	if tutorial == null:
		_failures.append("tutorial: the builder has no tutorial card")
		return
	tutorial.call("open")
	var total: int = int(tutorial.call("step_count"))
	var button: Button = tutorial.get("_next_button")
	var shown: int = int(tutorial.call("current_step"))
	var first: int = shown
	var presses: int = 0
	while bool(tutorial.call("is_open")) and presses <= total:
		if button != null and button.disabled:
			_failures.append("tutorial: NEXT is disabled at step %d of %d" % [shown + 1, total])
			break
		tutorial.call("press_next")
		presses += 1
		var now: int = int(tutorial.call("current_step"))
		if bool(tutorial.call("is_open")) and now <= shown:
			_failures.append(
				(
					"tutorial: NEXT at step %d of %d did not advance (still %d)"
					% [shown + 1, total, now + 1]
				)
			)
			break
		shown = now
	if bool(tutorial.call("is_open")):
		_failures.append(
			"tutorial: still open after %d presses of NEXT over %d steps" % [presses, total]
		)
		tutorial.call("close")
	print(
		(
			"  tutorial: opened at step %d of %d, %d presses of NEXT to FINISH"
			% [first + 1, total, presses]
		)
	)


func _family_or(families: PackedStringArray, want: String) -> String:
	return want if families.has(want) else families[0]


func _joint_between(doc: ShipDoc, a: String, b: String) -> ShipJoint:
	var key: String = ShipDoc.joint_key_for(a, b)
	for jid: String in doc.joints:
		var joint: ShipJoint = doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == key:
			return joint
	return null


func _hatched(doc: ShipDoc, a: String, b: String) -> bool:
	var joint: ShipJoint = _joint_between(doc, a, b)
	return joint != null and joint.mode == ShipJoint.MODE_HATCHED


## The builder's one in-scene dialog: its title while it is showing, "" when it is not.
func _dialog_title() -> String:
	var modal: Control = _builder.get("_modal")
	if modal == null or not modal.visible:
		return ""
	return (_builder.get("_dialog_title") as Label).text


func _dialog_body() -> String:
	return (_builder.get("_dialog_body") as Label).text


## A step that must not have ended in a refusal. Closes the dialog if one is up, so the next
## step is not driven under it.
func _expect_no_dialog(label: String) -> void:
	var title: String = _dialog_title()
	if title == "":
		return
	_failures.append("%s was refused: %s - %s" % [label, title, _dialog_body()])
	_builder.call("_close_dialog")


## Every drawn mesh's origin, by visual id.
func _visual_origins(scene: Object) -> Dictionary:
	var out: Dictionary = {}
	var visuals: Dictionary = scene.get("_visuals")
	for key: Variant in visuals.keys():
		var solid: MeshInstance3D = visuals[key].get("solid")
		if solid != null:
			out[str(key)] = solid.transform.origin
	return out


## Same number of meshes, and every origin in `before` is drawn in `after` - ids aside, since a
## lift renames what it takes.
func _assert_same_origins(before: Dictionary, after: Dictionary, label: String) -> void:
	if before.size() != after.size():
		_failures.append("%s: %d meshes before, %d after" % [label, before.size(), after.size()])
	for key: Variant in before.keys():
		var want: Vector3 = before[key]
		var found: bool = false
		for other: Variant in after.keys():
			if (after[other] as Vector3).is_equal_approx(want):
				found = true
				break
		if not found:
			_failures.append(
				"%s: the mesh that stood at %s (%s) is gone from the screen" % [label, want, key]
			)


## The scene draws exactly what the attach pass places: no missing mesh, no stale one.
func _check_scene_matches_attach(doc: ShipDoc, scene: Object, label: String) -> void:
	var data: ShipData = _builder.call("get_data")
	var cfg: ShipConfig = _builder.call("get_config")
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	var visuals: Dictionary = scene.get("_visuals")
	for key: Variant in xforms.keys():
		if shapes.has(key) and not visuals.has(key):
			_failures.append("%s: %s is placed but not drawn" % [label, key])
	for key: Variant in visuals.keys():
		if not xforms.has(key):
			_failures.append("%s: %s is drawn but no longer placed" % [label, key])


func _sorted_keys(d: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in d.keys():
		out.append(str(key))
	out.sort()
	return out


func _release_cam() -> Camera3D:
	return _release_view().call("get_orbit_camera").call("get_camera")


## A motion or button event fed to the view's placement input, exactly as _gui_input would.
func _release_motion(pos: Vector2, ctrl: bool = false) -> void:
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = pos
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.ctrl_pressed = ctrl
	_release_view().call("_handle_placement_input", mm)


func _release_button(pos: Vector2, ctrl: bool = false) -> void:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = pos
	mb.ctrl_pressed = ctrl
	_release_view().call("_handle_placement_input", mb)


## Grab the placement arrow two thirds of the way from the parent and pull it 60 px sideways.
func _release_gesture_arrow() -> void:
	var view: Object = _release_view()
	var scene: Object = view.call("get_scene_builder")
	var doc: ShipDoc = _builder.call("get_doc")
	var part: ShipPart = doc.parts.get(_release_pid, null) as ShipPart
	_builder.call("get_placement").call("cancel")
	if part == null or part.parent.is_empty():
		return
	var xform: Transform3D = scene.call("part_transform", _release_pid)
	var parent_x: Transform3D = scene.call("part_transform", part.parent)
	var cam: Camera3D = _release_cam()
	var world: Vector3 = parent_x.origin.lerp(xform.origin, 0.66)
	if cam.is_position_behind(world):
		return
	var grab: Vector2 = cam.unproject_position(world)
	if not bool(view.call("_try_begin_handle_drag", grab)):
		return
	var to: Vector2 = grab + Vector2(60.0, 0.0)
	_release_motion(to)
	_release_button(to)


## G, then release with the pointer over the moving part's OWN body - which the probe ignores.
func _release_gesture_self_move() -> void:
	var view: Object = _release_view()
	var scene: Object = view.call("get_scene_builder")
	_builder.call("set_selection", PackedStringArray([_release_pid]))
	_builder.call("begin_move_selected")
	var shape: ResolvedShape = scene.call("part_shape", _release_pid)
	var xform: Transform3D = scene.call("part_transform", _release_pid)
	if shape == null:
		return
	var box: AABB = shape.local_aabb()
	var pos: Vector2 = _release_cam().unproject_position(
		xform * Vector3(0.0, box.size.y * 0.45, 0.0)
	)
	_release_motion(pos)
	_release_button(pos)


## Ctrl-drag 300 px along the screen: VERTICAL mode, the part sinking through its parent.
func _release_gesture_ctrl_sink() -> void:
	var scene: Object = _release_view().call("get_scene_builder")
	_builder.call("get_placement").call("begin_move", _release_pid)
	var here: Vector2 = _release_cam().unproject_position(
		(scene.call("part_transform", _release_pid) as Transform3D).origin
	)
	for k: int in 5:
		_release_motion(here + Vector2(0.0, -60.0 * float(k + 1)), true)
	_release_button(here + Vector2(0.0, -300.0), true)


## A ring drag whose release lands well off the silhouette.
func _release_gesture_ring() -> void:
	var view: Object = _release_view()
	var scene: Object = view.call("get_scene_builder")
	var shape: ResolvedShape = scene.call("part_shape", _release_pid)
	var xform: Transform3D = scene.call("part_transform", _release_pid)
	var rot: Vector3 = scene.call("part_rot", _release_pid)
	_builder.call("get_placement").call("cancel")
	if shape == null:
		return
	var cam: Camera3D = _release_cam()
	for local: Vector3 in ShipHandles.ring_loop(shape, ShipPlacement.Handle.RING_Y, rot):
		var world: Vector3 = xform * local
		if cam.is_position_behind(world):
			continue
		var grab: Vector2 = cam.unproject_position(world)
		if not bool(view.call("_try_begin_handle_drag", grab)):
			continue
		if int(view.get("_handle_drag")) != ShipPlacement.Handle.RING_Y:
			_builder.call("get_placement").call("cancel")
			continue
		var to: Vector2 = grab + Vector2(250.0, -250.0)
		_release_motion(to)
		_release_button(to)
		return


## G, then release in the top-left corner of the viewport: nothing there, so this one IS removed.
func _release_gesture_void() -> void:
	_builder.call("set_selection", PackedStringArray([_release_pid]))
	_builder.call("begin_move_selected")
	_release_motion(Vector2(20.0, 20.0))
	_release_button(Vector2(20.0, 20.0))


## The offset stalk and the six stretch ticks: grabbable, and each moves the state it owns.
func _check_point_handle(
	view: Object, scene: Object, placement: Object, cam: Camera3D, shape: ResolvedShape, pid: String
) -> int:
	var probes: Array = [[ShipHandles.offset_point(shape), ShipPlacement.Handle.OFFSET, -1]]
	var ticks: PackedVector3Array = ShipHandles.morph_points(shape)
	for i: int in ticks.size():
		probes.append([ticks[i], ShipPlacement.Handle.MORPH, i])

	var checked: int = 0
	for entry: Variant in probes:
		var row: Array = entry
		placement.call("cancel")
		var xform: Transform3D = scene.call("part_transform", pid)
		var world: Vector3 = xform * (row[0] as Vector3)
		if cam.is_position_behind(world):
			continue
		var want: int = int(row[1])
		var grab: Vector2 = cam.unproject_position(world)
		if not bool(view.call("_try_begin_handle_drag", grab)):
			_failures.append("handle %d/%d: a press on it started no drag" % [want, int(row[2])])
			continue
		var got: int = int(view.get("_handle_drag"))
		if got != want:
			_failures.append("handle %d/%d: pressing on it gave %d" % [want, int(row[2]), got])
			continue
		# The STATE the handle drives, not the transform: a sideways stretch moves neither the
		# origin nor the (rigid) preview basis.
		var scale_before: Vector3 = placement.get("_part_scale")
		var offset_before: float = float(placement.call("values")["offset"])
		view.call("_drive_handle", grab + Vector2(0.0, -50.0))
		var moved: float = (placement.get("_part_scale") - scale_before).length()
		moved += absf(float(placement.call("values")["offset"]) - offset_before)
		if moved < 1.0e-4:
			_failures.append(
				"handle %d/%d: grabbing and dragging it changed nothing" % [want, int(row[2])]
			)
		checked += 1
	return checked


## Walks every point of `handle`'s drawn circle and asks ShipView3D's OWN press handler what a
## click there would grab. Returns how many of those points are on screen, how many answer with
## this handle, and the best pixel to drive the drag from.
##
## "Best" is the answering point furthest in screen space from the other two rings, so the drag
## is never launched from an intersection where any answer would have been defensible.
func _ring_reach(
	view: Object,
	placement: Object,
	cam: Camera3D,
	xform: Transform3D,
	shape: ResolvedShape,
	rot: Vector3,
	handle: int
) -> Dictionary:
	var visible: int = 0
	var mine: int = 0
	var best: Vector2 = Vector2(-1.0, -1.0)
	var best_clear: float = -1.0
	var others: Array[PackedVector2Array] = []
	for other: int in ShipHandles.ring_handles():
		if other == handle:
			continue
		others.append(_ring_pixels(cam, xform, shape, rot, other))
	for point: Vector3 in ShipHandles.ring_loop(shape, handle, rot):
		var world: Vector3 = xform * point
		if cam.is_position_behind(world):
			continue
		visible += 1
		var screen: Vector2 = cam.unproject_position(world)
		placement.call("cancel")
		if not bool(view.call("_try_begin_handle_drag", screen)):
			continue
		if int(view.get("_handle_drag")) != handle:
			continue
		mine += 1
		var clearance: float = 1.0e30
		for ring: PackedVector2Array in others:
			for p2: Vector2 in ring:
				clearance = minf(clearance, screen.distance_to(p2))
		if clearance > best_clear:
			best_clear = clearance
			best = screen
	placement.call("cancel")
	return {"visible": visible, "mine": mine, "best": best}


## Screen positions of one ring's drawn circle, skipping anything behind the camera.
func _ring_pixels(
	cam: Camera3D, xform: Transform3D, shape: ResolvedShape, rot: Vector3, handle: int
) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for point: Vector3 in ShipHandles.ring_loop(shape, handle, rot):
		var world: Vector3 = xform * point
		if not cam.is_position_behind(world):
			out.append(cam.unproject_position(world))
	return out


## RETIRED(2026-09-01): _clearest_pixel() -> _ring_reach() (just above). Probing ONE pixel per
## ring could not tell "this ring is grabbable and I picked a spot a morph tick owns" apart from
## "this ring is unreachable", and reported the first as the second.
## The pixel on `handle`'s ring that is furthest in screen space from the other two rings, so the
## probe is never sitting on an intersection where any answer would be defensible. Returns
## (-1, -1) when the whole ring is behind the camera.
func _clearest_pixel(
	cam: Camera3D, xform: Transform3D, shape: ResolvedShape, rot: Vector3, handle: int
) -> Vector2:
	var best: Vector2 = Vector2(-1.0, -1.0)
	var best_clear: float = -1.0
	for point: Vector3 in ShipHandles.ring_loop(shape, handle, rot):
		var world: Vector3 = xform * point
		if cam.is_position_behind(world):
			continue
		var screen: Vector2 = cam.unproject_position(world)
		var clearance: float = 1.0e30
		for other: int in ShipHandles.ring_handles():
			if other == handle:
				continue
			for p2: Vector3 in ShipHandles.ring_loop(shape, other, rot):
				var w2: Vector3 = xform * p2
				if not cam.is_position_behind(w2):
					clearance = minf(clearance, screen.distance_to(cam.unproject_position(w2)))
		if clearance > best_clear:
			best_clear = clearance
			best = screen
	return best


## How many DISTINCT shading-ramp entries are actually on screen. Counting all palette entries
## would be fooled by the grid and the gizmo; counting ramp entries asks the question that
## matters, which is whether a part's faces separated into bands.
func _ramp_bands_present(counts: Dictionary) -> int:
	var theme: Object = _builder.call("get_ship_theme")
	if theme == null:
		return 0
	var seen: Dictionary = {}
	for ramp_entry: Variant in ["part", "part_selected"]:
		var idx: PackedInt32Array = theme.call("ramp_indices", String(ramp_entry))
		for i: int in idx:
			if i < 0 or i >= _palette.size():
				continue
			var hex: String = _palette[i]
			if int(counts.get(hex, 0)) > 0:
				seen[hex] = true
	return seen.size()


func _report() -> void:
	# Two modes rendering byte-identical frames means a toggle is not wired, which is how
	# "SHADED+WIRE looks exactly like FLAT" survived a round of green checks.
	for a: int in range(_histograms.size()):
		for b: int in range(a + 1, _histograms.size()):
			if _same_frame(_histograms[a], _histograms[b]):
				_failures.append(
					(
						"%s and %s produced identical frames - is the mode toggle wired?"
						% [_name(a), _name(b)]
					)
				)

	print("")
	if _failures.is_empty():
		print("=== visual check PASSED (%d modes) ===" % _histograms.size())
		quit(0)
		return
	printerr("=== visual check FAILED (%d problem(s)) ===" % _failures.size())
	for f: String in _failures:
		printerr("  %s" % f)
	quit(1)


func _same_frame(a: Dictionary, b: Dictionary) -> bool:
	var ca: Dictionary = a["counts"]
	var cb: Dictionary = b["counts"]
	if ca.size() != cb.size():
		return false
	for key: Variant in ca.keys():
		if int(ca[key]) != int(cb.get(key, -1)):
			return false
	return true


# ---------------------------------------------------------------- helpers


func _print_hist(hist: Dictionary) -> void:
	var counts: Dictionary = hist["counts"]
	var total: int = maxi(int(hist["total"]), 1)
	var keys: Array = counts.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return counts[x] > counts[y])
	var shown: int = 0
	for key: Variant in keys:
		if shown >= 8:
			break
		print("       #%s  %5.2f%%" % [String(key), 100.0 * float(counts[key]) / float(total)])
		shown += 1


func _name(mode: int) -> String:
	if mode < 0 or mode >= MODE_NAMES.size():
		return "mode_%d" % mode
	return String(MODE_NAMES[mode])


func _app_viewport(n: Node) -> SubViewport:
	if n is SubViewport and n.name == "AppViewport":
		return n as SubViewport
	for c: Node in n.get_children():
		var r: SubViewport = _app_viewport(c)
		if r != null:
			return r
	return null


func _find_named(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c: Node in n.get_children():
		var r: Node = _find_named(c, want)
		if r != null:
			return r
	return null


func _find_builder(n: Node) -> Node:
	if n.has_method("get_doc") and n.has_method("set_display_mode"):
		return n
	for c: Node in n.get_children():
		var r: Node = _find_builder(c)
		if r != null:
			return r
	return null


## UPDATE MESHES bakes the exact pieces and shows them ASSEMBLED in place of the preview
## primitives (ADR 0023; the ghost that once stood in meanwhile is gone, ADR 0024). "so when
## the renderer needs to update because changes were made a button highlighted at top should say
## update meshes .. a loading bar so the user knows the renderer isnt frozen". Frame-driven;
## returns true when done. The read-back is ShipCheckViews.check_update_finish.
func _check_update_meshes() -> bool:
	var view: Object = _builder.call("get_view")
	var scene: Object = view.call("get_scene_builder") if view != null else null
	var explode: Object = view.call("get_explode_view") if view != null else null
	var done: bool = false
	if view == null or scene == null or explode == null:
		_failures.append("update: cannot reach the view, scene or explode view")
		done = true
	elif _update_step == 0:
		_update_begin()
	elif _update_step == 1:
		done = _update_wait(explode)
	elif _update_step == 2 and _frames >= MODE_FRAMES:
		_views.save_frame(_app_viewport(_host), "%s/visual_update.png" % OUT_DIR, "the baked frame")
		# INTERIOR on the baked pieces: interior fronts, exterior backs (ADR 0024). A frame for
		# the human's eyes, and the mode put back for the read-back.
		_builder.call("set_display_mode", ShipSceneBuilder.DisplayMode.INSIDE)
		_update_step = 3
		_frames = 0
	elif _update_step == 3 and _frames >= MODE_FRAMES:
		_views.save_frame(
			_app_viewport(_host), "%s/visual_interior.png" % OUT_DIR, "the interior frame"
		)
		_builder.call("set_display_mode", ShipSceneBuilder.DisplayMode.SHADED_WIRE)
		_views.check_update_finish(view, scene, explode, _explode_expected)
		done = true
	return done


## In the baked view (the explode stage left a fresh bake), an edit: the button must light and
## nothing must bake by itself; then press the button.
func _update_begin() -> void:
	_builder.call("_set_baked", true)
	if not bool(_builder.get("_baked")):
		_failures.append("update: _set_baked(true) did not take on a fresh bake")
	var doc: ShipDoc = _builder.call("get_doc")
	var pid: String = doc.part_order()[doc.part_order().size() - 1]
	_builder.call("begin_edit", "nudge")
	(doc.parts[pid] as ShipPart).yaw += 1.0
	_builder.call("commit_edit", PackedStringArray([pid]))
	_explode_expected = _views.module_count(doc)
	var button: Button = _builder.get("_update_button")
	if button == null or not button.text.ends_with("*"):
		_failures.append("update: the button did not light after an edit")
	_builder.call("_on_update_pressed")
	_update_step = 1
	_frames = 0


## The bar must show while the engine bakes; wait for the bake and the placement. Returns true
## only when the stage must abort.
func _update_wait(explode: Object) -> bool:
	var bar: ProgressBar = _builder.get("_progress")
	if _frames == 2 and (bar == null or not bar.visible):
		_failures.append("update: no progress bar while the engine bakes")
	if (_builder.get("_bake_session") as ShipBakeSession).busy or bool(explode.call("is_busy")):
		if _frames <= EXPLODE_MAX_FRAMES:
			return false
		_failures.append("update: still baking after %d frames" % _frames)
		return true
	_update_step = 2
	_frames = 0
	return false
