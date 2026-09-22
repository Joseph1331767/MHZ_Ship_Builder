## ShipView3D - the 3D panel: the INNER of the two nested SubViewports (SPEC section 10).
##
##   dev_host SubViewport (the app, 1280x800, nearest)
##     └── ShipBuilder
##           └── ShipView3D  <- this SubViewportContainer
##                 └── SubViewport (own World3D)
##                       ├── OrbitCamera -> Camera3D
##                       ├── ShipSceneBuilder -> MeshInstance3D per part
##                       ├── WorldEnvironment + DirectionalLight3D
##                       └── grid
##
## The nesting is deliberate. The inner viewport owns the 3D world and hands the outer
## one a texture; the palette post-process then quantizes the app viewport as a whole, so
## the 3D and the UI come out sharing one colour language without being matched by hand.
##
## INPUT (SPEC section 10, the rule most easily broken by accident). Everything arrives
## through _gui_input, whose event positions are already local to this Control - and
## because the container stretches 1:1, a local position IS a position in the inner
## viewport, which is exactly what Camera3D.project_ray_*() wants. Nothing here reads
## DisplayServer, get_window(), or a global mouse position, so the same code works when
## the builder is a texture on a diegetic panel fed by Viewport.push_input().
##
## _propagate_input_event() is overridden to false so events are NOT also forwarded into
## the inner viewport: this class is the only thing that interprets them, and a double
## delivery would orbit twice per drag.
##
## PLACEMENT (M3). While a ShipPlacement is active this view owns the left button: motion
## moves the ghost, release commits it, and the camera keeps right-drag (orbit) and
## Shift+wheel (zoom) so the player can still look around mid-placement.
##
## Both the pick ray and the placement ray are resolved in _physics_process for the same
## reason: a direct space state is only valid inside a physics frame. ShipPlacement cannot
## run the query itself (it is a RefCounted with no viewport), so this class hands it
## probe_surface() as a Callable and calls update_from_ray() from the physics frame. There
## is exactly ONE picking pattern in this file and the ghost uses it.
##
## THE SPORE INPUT GRAMMAR (API_CONTRACT_SPORE section 8, SPORE_CLONE_SPEC section 2 - taken
## from the official manual, not from preference). This class decides WHICH physical input
## happened; ShipPlacement decides what it MEANS. Nothing interaction-shaped is stored here
## beyond which key is currently held down.
##
##   plain wheel / Up-Down       scale the selected part (the camera never sees it)
##   Shift + wheel, + / -        zoom the camera
##   right-drag, left-drag empty space, < / >   orbit the camera
##   hold Tab                    rings and morph handles in place of the ball
##   Alt on a selected part      clone it and start dragging the copy
##   Ctrl + drag                 move the part along its mount axis - it may float free
##   Shift + drag                move it across the current parent's surface only
##   drag off the ship           remove the part being moved
##   hold A while selecting      break symmetry, cascading to children
##
## THE PLAIN WHEEL FALLS BACK TO THE CAMERA when there is nothing to scale. Spore always has
## something selected; a builder that has just started does not, and a wheel that does
## nothing at all reads as a broken wheel. The manual says nothing about the empty case, so
## this is the one binding here that is a judgement rather than a citation.
##
## SHIFT IS NO LONGER THE SNAP BYPASS. It was (SPEC section 6, routed through
## ShipPlacement.set_snap_bypass); the Spore contract assigns Shift+drag to horizontal
## movement and that is the stronger claim on the modifier. ShipPlacement.set_snap_bypass()
## still exists and still works for any caller that wants it - nothing drives it from here.
##
## KEYS NEED FOCUS. focus_mode is FOCUS_CLICK and every press grabs it, so the hold keys work
## once the player has touched the 3D view.
class_name ShipView3D
extends SubViewportContainer

## Emitted when a click lands on a part. `additive` is true when a modifier was held
## (ctrl/shift), which the builder reads as extend-selection.
## A right CLICK - pressed and released without orbiting - on a two-part selection. `position` is
## in this Control's coordinates, which is where the seam menu opens (ADR 0009).
signal seam_menu_requested(position: Vector2)

## A part was double-clicked: the id the pick resolved to, "" for empty space (ADR 0024).
signal part_double_clicked(part_id: String)
signal part_picked(part_id: String, additive: bool)
## Emitted when a click lands on empty space.
signal pick_cleared

## A press that moves further than this many pixels is a camera drag, not a click.
const CLICK_SLOP_PX: float = 4.0
const PICK_RAY_LENGTH: float = 10000.0
## Alpha of everything outside the component open in isolation (ADR 0024).
const WASHED_ALPHA: float = 0.12
const GRID_EXTENT: float = 20.0
const GRID_STEP: float = 1.0

## How many colliders the surface probe may skip before giving up. Only the part being
## re-placed and its subtree are ever skipped, so this is generous.
const PROBE_MAX_SKIPS: int = 8

## Camera buttons that keep working during a placement; a drag with one held is a camera
## move and must not drag the ghost.
##
## RETIRED(2026-08-31): MOUSE_BUTTON_MASK_MIDDLE -> removed with camera pan, which was an
## un-Spore-like invention (SPORE_CLONE_SPEC section 2). Right-drag is the only camera drag.
const CAMERA_DRAG_MASK: int = MOUSE_BUTTON_MASK_RIGHT

## Pixels of simulated drag per press of `<` or `>`. One press is a visible nudge, held
## auto-repeat sweeps - the same feel as Spore's on-screen rotate buttons.
const ORBIT_KEY_PX: float = 24.0

## How much of each half-extent a max-bbox corner bracket spans. An eighth is long enough to read
## as a corner and short enough that the eight of them never join up into a box.
const BBOX_BRACKET_FRACTION: float = 0.125

## Numpad rotation. Each press turns the part by the document's own snap increment, which is the
## whole point of calling them rotation SNAPS; holding Shift multiplies it, because reaching a
## quarter turn at the shipped 0.5 degrees is sixty taps otherwise.
const NUMPAD_COARSE: float = 15.0

## Numpad key -> [axis, direction]. The middle key of each row zeroes that axis, which is why the
## direction is 0 there: 7/8/9 about mount X, 4/5/6 about Y, 1/2/3 about Z, exactly as asked for.
const NUMPAD_ROTATE: Dictionary = {
	KEY_KP_7: [Vector3.AXIS_X, -1],
	KEY_KP_8: [Vector3.AXIS_X, 0],
	KEY_KP_9: [Vector3.AXIS_X, 1],
	KEY_KP_4: [Vector3.AXIS_Y, -1],
	KEY_KP_5: [Vector3.AXIS_Y, 0],
	KEY_KP_6: [Vector3.AXIS_Y, 1],
	KEY_KP_1: [Vector3.AXIS_Z, -1],
	KEY_KP_2: [Vector3.AXIS_Z, 0],
	KEY_KP_3: [Vector3.AXIS_Z, 1],
}

## Arrow key -> (yaw direction, pitch direction) of one placement-vector step, in the PARENT's
## frame: LEFT/RIGHT swing the ray about the parent's up axis, UP/DOWN tip it toward or away
## from it. Each press is one snap increment (Shift: NUMPAD_COARSE), the same lattice the numpad
## rotations and the typed fields use. Fixed sign, by the author's choice: LEFT is always yaw
## minus, whichever side of the parent the camera is on.
## RETIRED(2026-09-02): ARROW_STEP, which counted SnapTargets entries - see ShipReseat.
const ARROW_DELTA: Dictionary = {
	KEY_LEFT: Vector2i(-1, 0),
	KEY_RIGHT: Vector2i(1, 0),
	KEY_UP: Vector2i(0, 1),
	KEY_DOWN: Vector2i(0, -1),
}

## Idle window before the FULL gate (complexity plus the physical budgets, which cost a
## sampling grid) re-checks the pending placement. Matches the gauge strip's own debounce,
## deliberately: the two run the same expensive pass and should not be tuned apart.
const GATE_IDLE_SECONDS: float = 0.25

## Axis-lock keys, SketchUp style: hold or tap X / Y / Z to pin a rotation to ONE mount-frame
## axis whatever handle is grabbed. Tapping the live axis again, or pressing Escape, clears it.
##
## Spore has no such thing - it is a CAD affordance the author asked for by name ("theres no axial
## lock hot keys like sketchup has"), and it layers cleanly on the Spore grammar because Spore
## spends Ctrl and Shift on DRAG constraint and leaves the letter keys free.
const AXIS_LOCK_KEYS: Dictionary = {
	KEY_X: Vector3.AXIS_X,
	KEY_Y: Vector3.AXIS_Y,
	KEY_Z: Vector3.AXIS_Z,
}

## Corner inset and line spacing of the key legend, in DESIGN pixels (ShipTheme scales them).
const HINT_MARGIN_PX: float = 6.0

## Floor on the half-span of the distance cue, in metres. An empty document has a zero-size AABB;
## without a floor the cue's near and far would collapse together and the shader would skip it.
const DEPTH_MIN_RADIUS: float = 1.5

var _viewport: SubViewport = null
var _camera_rig: OrbitCamera = null
var _scene: ShipSceneBuilder = null
var _grid: MeshInstance3D = null
var _env: WorldEnvironment = null
var _light: DirectionalLight3D = null
var _theme: ShipTheme = null
## The document and config last handed to rebuild()/sync(). Kept only so the keyboard can read the
## live snap increment and the budget's bounding box - the SCENE owns the geometry, this owns
## nothing, and neither is ever written back through.
var _doc: ShipDoc = null
var _cfg: ShipConfig = null
## The application root, for the two keyboard verbs that edit the document directly through the
## edit protocol (ShipReseat). Nothing else here reaches through it.
var _builder: ShipBuilder = null
## The max-bbox cage. A separate node from the grid so a budget change redraws one and not both.
var _bbox_cage: MeshInstance3D = null
## The EXPLODED view (ADR 0008): module bakes pulled apart along their seams, shown INSTEAD of
## the parts. While it is up this view owns nothing but the camera - no picks, no handles, no
## edit keys - because what is on screen is a set of bakes, not the document.
var _explode: ShipExplodeView = null
var _exploded: bool = false
## The ASSEMBLED baked view is up: the finished pieces where they stand, in place of the preview
## primitives (ADR 0023). Never true together with _exploded.
var _baked: bool = false
## How far open every door is (ADR 0029): key -> {side -> 0..1}. Kept here, above the explode
## view, so a rebake puts the doors back the way the player left them.
var _door_open: Dictionary = {}
## The component instance being edited in isolation, or "" (ADR 0024).
var _isolated: String = ""

var _press_pos: Vector2 = Vector2.ZERO
var _press_active: bool = false
## The right button, tracked the same way the left one is, so a right CLICK can open the seam
## menu while a right DRAG still orbits and nothing about the camera changes.
var _rmb_pos: Vector2 = Vector2.ZERO
var _rmb_active: bool = false
var _pick_pending: bool = false
## A double-click waiting for the physics frame to resolve what it landed on.
var _double_pending: bool = false
var _pick_pos: Vector2 = Vector2.ZERO
var _pick_additive: bool = false
## Ctrl was held on the press: re-centre the orbit on whatever this pick resolves to.
var _pick_focus: bool = false
var _pick_shift: bool = false
var _pick_ctrl: bool = false
var _pick_alt: bool = false

var _placement: ShipPlacement = null
var _ghost_ray_pending: bool = false
var _ghost_ray_pos: Vector2 = Vector2.ZERO
var _ghost_commit_pending: bool = false
## Whether the release queued in `_ghost_commit_pending` came off a PLAIN surface drag, the
## only kind allowed to remove a part - see ShipPlacement.remove_if_dragged_off().
var _release_may_remove: bool = false

## Tab and A are HOLDS, not toggles, so their state lives here for as long as the key is
## down and nowhere else.
var _break_symmetry_held: bool = false

## The gizmo handle currently being dragged - a ShipPlacement.Handle value - plus the morph
## index it carries and the pointer position the last delta was measured from.
##
## Seeded in _ready(), not here: this class, ShipPlacement, ShipBuilder and ShipSceneBuilder
## form a ring of class-level type references, and reading another class's ENUM CONSTANT
## from inside that ring asks for a value while that class may itself be mid-resolution.
## Declared names are fine in a ring; constant VALUES belong in a function body.
var _handle_drag: int = 0
var _handle_index: int = -1
var _handle_last: Vector2 = Vector2.ZERO

## One-shot debounce for the expensive half of the placement gate. See GATE_IDLE_SECONDS.
var _gate_timer: Timer = null

## Mount-frame axis every rotation gesture is pinned to, or -1 for "whichever handle was
## grabbed". See AXIS_LOCK_KEYS.
var _axis_lock: int = -1
## Which reference numpad 0 aims the part at NEXT. Starts on the surface normal, because a part
## that has never been aimed is already standing on the normal and the first press should visibly
## do something.
var _aim_to_normal: bool = false
## FLOATING (false) spins the part about its own centre and lets ShipAttach re-seat it; ATTACHED
## (true) swings the PLACEMENT VECTOR instead, so the part travels across its parent's surface.
## Both are the author's words, and both are driven by the same three rings - see ShipReseat.
## swing_placement() for why it is a mode rather than a second gizmo.
var _attached_pivot: bool = false
## The always-on key legend. Rebuilt on every state change that alters what the keys do.
var _hint_label: Label = null
## Everything the legend's text depends on, as one comparable string. See _refresh_hints().
var _hints_key: String = ""
## PaintPanel's PaintMode, when that panel is mounted. Null in BUILD-only hosts.
var _paint: PaintMode = null


func _ready() -> void:
	# See the note on _handle_drag: the enum constant is read here rather than in the
	# declaration.
	_handle_drag = ShipPlacement.Handle.NONE

	# stretch = true keeps the inner viewport exactly the size of this panel, so one
	# container pixel is one viewport pixel and no coordinate scaling is needed anywhere.
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(ShipTheme.pxf(320.0), ShipTheme.pxf(240.0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_viewport = SubViewport.new()
	_viewport.name = "View3DViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_debanding = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# We do our own picking from _physics_process; the built-in picker would need a
	# global mouse position it must never ask for.
	_viewport.physics_object_picking = false
	_viewport.gui_disable_input = true
	_viewport.size = Vector2i(640, 480)
	add_child(_viewport)

	_env = WorldEnvironment.new()
	_env.name = "ViewEnvironment"
	_env.environment = _build_environment()
	_viewport.add_child(_env)

	_light = DirectionalLight3D.new()
	_light.name = "KeyLight"
	_light.rotation_degrees = Vector3(-52.0, -37.0, 0.0)
	_light.light_energy = 1.15
	# No shadows: at 16 colours a shadow is a hard-edged blotch, not information.
	_light.shadow_enabled = false
	_viewport.add_child(_light)

	_camera_rig = OrbitCamera.new()
	_camera_rig.name = "OrbitCamera"
	_viewport.add_child(_camera_rig)

	_grid = MeshInstance3D.new()
	_grid.name = "Grid"
	_viewport.add_child(_grid)

	_bbox_cage = MeshInstance3D.new()
	_bbox_cage.name = "BBoxCage"
	_viewport.add_child(_bbox_cage)

	_scene = ShipSceneBuilder.new()
	_scene.name = "ShipScene"
	_viewport.add_child(_scene)

	_explode = ShipExplodeView.new()
	_explode.name = "ExplodeView"
	_viewport.add_child(_explode)
	_explode.finished.connect(_on_explode_finished)

	# The distance cue needs to know how far the camera is; connect after both exist.
	_camera_rig.camera_moved.connect(_push_depth_range)

	# Lives on THIS node, not in the inner viewport: it is interaction bookkeeping, not
	# scene content, and it must survive a full 3D teardown.
	_build_hint_overlay()

	_gate_timer = Timer.new()
	_gate_timer.name = "GateIdle"
	_gate_timer.one_shot = true
	_gate_timer.wait_time = GATE_IDLE_SECONDS
	_gate_timer.timeout.connect(_on_gate_idle)
	add_child(_gate_timer)

	_rebuild_grid()


## Virtual on SubViewportContainer: returning false stops the container forwarding this
## event into the inner SubViewport. See the class docstring.
func _propagate_input_event(_event: InputEvent) -> bool:
	return false


# ---------------------------------------------------------------- wiring


## `owner_builder` is optional and trailing so the existing one-argument call still compiles: the
## view needs it only for the two keyboard verbs that go through ShipReseat, and a host that does
## not pass one simply has no arrow-step and no numpad-0 aim.
func setup(theme: ShipTheme, owner_builder: ShipBuilder = null) -> void:
	_builder = owner_builder
	_theme = theme
	if _scene != null:
		_scene.setup(theme)
	if _explode != null:
		_explode.setup(_scene)
	if _env != null:
		_env.environment = _build_environment()
	_rebuild_grid()
	# The legend is dim `text_dim`, which is not resolvable until the theme lands.
	_refresh_hints()


## Re-colour everything that caches a palette colour. Hook this to
## ShipTheme.palette_changed so a budget alert recolours the 3D view as well as the UI.
func on_palette_changed() -> void:
	if _env != null:
		_env.environment = _build_environment()
	if _scene != null:
		_scene.refresh_materials()
	_rebuild_grid()
	_refresh_hints()


## Bind a PaintMode so clicks can reach it. NOTHING CALLS THIS in the shipping builder.
##
## Paint is out of scope for this module (see ShipBuilder.paint_slot): the panel is not mounted,
## so `_paint` stays null and the hook in `_do_pick` is a no-op. The seam is kept because the
## author raised paint as a possible DEV tool for judging theme colours - re-mounting the panel is
## then a one-line change here and one entry in PANEL_CANDIDATES, with no other edits.
func set_paint_mode(mode: PaintMode) -> void:
	_paint = mode
	if _paint != null:
		_paint.set_surface_probe(probe_surface)


## Bind the session's ShipPlacement. This view renders its ghost and supplies its surface
## probe; ShipBuilder still owns the placement's lifecycle.
func set_placement(placement: ShipPlacement) -> void:
	if _placement == placement:
		return
	_clear_ghost()
	_disconnect_placement()
	_placement = placement
	if _placement == null:
		return
	_placement.set_surface_probe(probe_surface)
	_placement.ghost_moved.connect(_on_ghost_moved)
	_placement.ghost_validity_changed.connect(_on_ghost_validity_changed)
	_placement.ghost_state_changed.connect(_on_ghost_state_changed)
	_placement.placement_committed.connect(_on_placement_committed)
	_placement.placement_cancelled.connect(_on_placement_cancelled)
	_refresh_hints()


## Drop the previous placement's connections. Only ever needed if a second placement is
## bound, but a half-connected old instance would keep redrawing a ghost that nothing owns.
func _disconnect_placement() -> void:
	if _placement == null:
		return
	_placement.ghost_moved.disconnect(_on_ghost_moved)
	_placement.ghost_validity_changed.disconnect(_on_ghost_validity_changed)
	_placement.ghost_state_changed.disconnect(_on_ghost_state_changed)
	_placement.placement_committed.disconnect(_on_placement_committed)
	_placement.placement_cancelled.disconnect(_on_placement_cancelled)
	_placement.set_surface_probe(Callable())
	_placement = null


## The surface probe ShipPlacement drags along. Returns the first pick collider that is not
## in `blocked`, as { "hit": bool, "point": Vector3 (ship space), "part": String }.
##
## MUST be called from a physics frame - the direct space state is only valid there, which
## is why ShipPlacement is driven from _physics_process below and never from _gui_input.
func probe_surface(origin: Vector3, dir: Vector3, blocked: PackedStringArray) -> Dictionary:
	var miss: Dictionary = {"hit": false, "point": Vector3.ZERO, "part": ""}
	var space: PhysicsDirectSpaceState3D = _space_state()
	if space == null or _scene == null:
		return miss

	var blocked_set: Dictionary = {}
	for pid: String in blocked:
		blocked_set[pid] = true

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + dir * PICK_RAY_LENGTH, ShipSceneBuilder.PICK_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var skipped: Array[RID] = []
	for _i: int in PROBE_MAX_SKIPS:
		query.exclude = skipped
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var pid: String = _scene.part_id_for(hit.get("collider", null))
		if pid != "" and not blocked_set.has(pid):
			var point: Vector3 = hit.get("position", Vector3.ZERO)
			return {"hit": true, "point": point, "part": pid}
		# The part under the pointer is the one being moved (or is not ours): step past its
		# collider and try again, so a ghost can be dragged onto whatever is behind itself.
		var rid: RID = hit.get("rid", RID())
		if not rid.is_valid():
			break
		skipped.append(rid)
	return miss


func _space_state() -> PhysicsDirectSpaceState3D:
	if _viewport == null:
		return null
	# get_world_3d(), NOT the world_3d PROPERTY.
	#
	# `world_3d` is the explicit OVERRIDE slot: it stays null unless someone assigns a World3D
	# to it, and `own_world_3d = true` does not fill it in. The effective world — the one the
	# viewport actually renders and simulates in — is only reachable through the method.
	#
	# Reading the property returned null here, so _space_state() returned null, so
	# probe_surface() returned `miss` for EVERY ray. That made the ghost permanently
	# "off ship" -> BAD_LOCATION -> invalid -> commit() refused every click. The editor could
	# not place a single part, and nothing errored: a miss is a legal answer from a raycast.
	# Ask a node that LIVES in the world, not the viewport that owns it.
	#
	# Measured, not assumed: with `own_world_3d = true`, `View3DViewport.world_3d` is null (that
	# property is only the explicit override slot) AND `View3DViewport.get_world_3d()` also
	# returned null here — while a StaticBody3D parented inside that very viewport returned a
	# valid World3D that raycasts hit. Whatever the engine is doing there, the child is the
	# reliable answer.
	#
	# The consequence of getting this wrong was total and silent: _space_state() returned null,
	# probe_surface() answered `miss` for EVERY ray, the ghost was permanently "off ship", and
	# commit() refused every click. The editor could not place a single part and nothing errored,
	# because "the ray hit nothing" is a legal answer.
	var host: Node3D = _scene
	if host == null:
		host = _camera_rig
	if host == null or not host.is_inside_tree():
		return null
	var world: World3D = host.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


func get_orbit_camera() -> OrbitCamera:
	return _camera_rig


func get_scene_builder() -> ShipSceneBuilder:
	return _scene


func get_view_viewport() -> SubViewport:
	return _viewport


# ---------------------------------------------------------------- document


func rebuild(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	_doc = doc
	_cfg = cfg
	if _scene != null:
		_scene.rebuild(doc, data, cfg)
		_push_depth_range()
	_rebuild_bbox_cage()


func sync(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	_doc = doc
	_cfg = cfg
	if _scene != null:
		_scene.sync(doc, data, cfg)
		_push_depth_range()
	_rebuild_bbox_cage()


func refresh_parts(doc: ShipDoc, data: ShipData, cfg: ShipConfig, ids: PackedStringArray) -> void:
	if _scene != null:
		_scene.refresh_parts(doc, data, cfg, ids)
		_push_depth_range()


## Re-derive the part shader's distance-cue range from where the camera is now and how big the
## ship is.
##
## Spans the model, not a fixed world range: at a fixed range the near-is-light/far-is-dark cue
## washes out completely once you zoom into one part and clips to a single band once you pull back
## off a large ship. Anchoring it to (orbit distance +/- model radius) keeps the whole ramp in play
## at every zoom, which is the point of having the cue at all.
func _push_depth_range() -> void:
	if _scene == null or _camera_rig == null:
		return
	var box: AABB = _scene.scene_aabb()
	var radius: float = maxf(box.size.length() * 0.5, DEPTH_MIN_RADIUS)
	var dist: float = _camera_rig.distance
	# The cut plane stays at NO_CUT: the INTERIOR mode is the far walls from any angle, as
	# asked; a section through the orbit focus is the shader's to offer when a SECTION mode
	# wants it (ADR 0028).
	_scene.set_depth_range(maxf(dist - radius, 0.05), dist + radius, ShipSceneBuilder.NO_CUT)
	_push_handle_scale()


## Metres per inner-viewport pixel at the selected part - or, with nothing selected, at the orbit
## focus - so the gizmo's screen floors (ShipHandles) track the zoom. Perspective: one pixel
## spans 2 * d * tan(fov / 2) / height metres at distance d. Reads this view's own SubViewport,
## never the window (SPEC section 10).
func _push_handle_scale() -> void:
	if _scene == null or _camera_rig == null or _viewport == null:
		return
	var cam: Camera3D = _camera_rig.get_camera()
	if cam == null:
		return
	var dist: float = _camera_rig.distance
	var ids: PackedStringArray = _scene.selection()
	if ids.size() == 1:
		var origin: Vector3 = _scene.part_transform(ids[0]).origin
		dist = maxf(cam.global_position.distance_to(origin), 0.05)
	var height: float = maxf(float(_viewport.size.y), 1.0)
	var span: float = 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5)
	_scene.set_handle_pixel_size(span / height)


func set_selection(ids: PackedStringArray) -> void:
	if _scene != null:
		_scene.set_selection(ids)
		# The gizmo's screen floors are sized at the SELECTED part's distance.
		_push_handle_scale()
	if _explode != null:
		_explode.set_selection(ids)


func set_display_mode(mode: int) -> void:
	if _scene != null:
		_scene.set_display_mode(mode)
	if _explode != null:
		_explode.set_display_mode(mode)


func get_display_mode() -> int:
	if _scene == null:
		return ShipSceneBuilder.DisplayMode.FLAT
	return _scene.get_display_mode()


# RETIRED(2026-08-31): set_view_preset() -> removed as an un-Spore-like invention; there are no
# front/side/top axis-snap views in any Spore editor (SPORE_CLONE_SPEC section 2). The
# OrbitCamera method it forwarded to is gone, as is ShipBuilder's 1/2/3/4 binding.


## Fit the whole ship. Falls back to a default framing when the scene is empty.
func frame_all() -> void:
	if _camera_rig == null:
		return
	var box: AABB = AABB(Vector3(-4.0, -4.0, -4.0), Vector3(8.0, 8.0, 8.0))
	if _scene != null:
		var scene_box: AABB = _scene.scene_aabb()
		if scene_box.size.length() > 0.0:
			box = scene_box
	_camera_rig.frame_aabb(box)


func frame_aabb(box: AABB) -> void:
	if _camera_rig != null:
		_camera_rig.frame_aabb(box)


# ---------------------------------------------------------------- exploded view


## Show `sdf` exploded in place of the parts, or put the parts back. `selected` colours the
## selected parts' modules. The camera reframes on the exploded bounds once the last module
## has baked (_on_explode_finished), and on the whole ship on the way back.
func set_exploded(
	on: bool,
	sdf: ShipSdf = null,
	selected: PackedStringArray = PackedStringArray(),
	solids: Dictionary = {}
) -> void:
	if _explode == null or _scene == null:
		return
	if not on and not _exploded:
		return
	_exploded = on
	if on:
		_baked = false
		_scene.set_exploded(true)
		_explode.show_modules(sdf, _cfg, selected, solids)
		_explode.set_doors_open(_door_open)
	else:
		# ASSEMBLE plays the explode backwards (ADR 0032); the baked view the builder shows next
		# lands when it is done, and with none to show the explode view empties itself.
		_explode.collapse()
		_scene.set_exploded(false)
		frame_all()
	_refresh_hints()


## Whether an exploded room shows as its pieces or as one whole shell. Takes effect on the next
## EXPLODE, and at once when one is showing.
## The ASSEMBLED baked view (ADR 0023): every finished piece where it stands, whole, in place of
## the preview primitives, so a link or a wall is on screen as the engine made it. Rooms whole or
## in pieces per [method set_rooms_whole]. Off puts the primitives back. Exploding leaves it; it
## does not leave exploding.
func set_baked(
	on: bool,
	sdf: ShipSdf = null,
	selected: PackedStringArray = PackedStringArray(),
	report: Dictionary = {}
) -> void:
	if _explode == null or _scene == null:
		return
	if on:
		if sdf == null:
			return
		_exploded = false
		_baked = true
		var covered: PackedStringArray = PackedStringArray()
		for key: Variant in report.get("solids", {}) as Dictionary:
			covered.append(str(key))
		_scene.set_exploded(true, covered)
		_explode.show_modules(sdf, _cfg, selected, report, true)
		_explode.set_doors_open(_door_open)
	else:
		if not _baked:
			return
		_baked = false
		if not _exploded:
			_explode.clear()
			_scene.set_exploded(false)
	_refresh_hints()


func is_baked() -> bool:
	return _baked


## Swings one door (ADR 0029): the door of [param key] (ShipHatchEdit.door_key) on
## [param side] (ShipDoors.SIDE_CHILD or SIDE_HOST) to [param amount] open. Remembered across
## rebakes; animated when the baked pieces are on screen.
func set_door_open(key: String, side: String, amount: float) -> void:
	var sides: Dictionary = _door_open.get(key, {})
	sides[side] = clampf(amount, 0.0, 1.0)
	_door_open[key] = sides
	if _explode != null:
		_explode.set_door_open(key, side, amount, true)


## How far open the door of [param key] on [param side] is, 0 when never touched.
func door_open(key: String, side: String) -> float:
	var sides: Dictionary = _door_open.get(key, {})
	return float(sides.get(side, 0.0))


## ISOLATION (ADR 0024): [param instance_id] is the component being edited ("" to leave);
## the scene washes out everything else and picks inside resolve to inner parts.
func set_isolated(instance_id: String) -> void:
	_isolated = instance_id
	var washed: Material = _washed_material() if not instance_id.is_empty() else null
	if _scene != null:
		_scene.set_isolated(instance_id, washed)
	if _explode != null:
		_explode.set_isolated(instance_id, washed)
	_refresh_hints()


## What everything outside the open component wears: dim, translucent, depth-tested, so the
## component reads through the rest of the ship without the rest vanishing.
func _washed_material() -> Material:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = _role_color("text_dim", Color(0.4, 0.5, 0.5))
	m.albedo_color.a = WASHED_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func set_rooms_whole(on: bool) -> void:
	if _explode != null:
		_explode.set_rooms_whole(on)


func is_exploded() -> bool:
	return _exploded


func get_explode_view() -> ShipExplodeView:
	return _explode


func _on_explode_finished(_modules: int, _seams: int, _ms: int) -> void:
	if not _exploded or _explode == null:
		return
	var box: AABB = _explode.bounds()
	if box.size.length() > 0.0:
		frame_aabb(box)


# ---------------------------------------------------------------- input


func _gui_input(event: InputEvent) -> void:
	if _camera_rig == null:
		return

	if _exploded or _baked:
		_handle_explode_input(event)
		return

	var key: InputEventKey = event as InputEventKey
	if key != null:
		if _handle_key(key):
			accept_event()
		return

	# The plain wheel is the part-scale verb and never reaches the camera; Shift+wheel is
	# the camera's zoom and falls straight through (API_CONTRACT_SPORE section 8).
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel != null and _is_wheel(wheel.button_index) and _handle_wheel(wheel):
		accept_event()
		return

	# A live placement owns the left button and plain motion; everything it does not claim
	# falls through to the camera untouched.
	if _placement != null and _placement.active and _handle_placement_input(event):
		accept_event()
		return

	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and _handle_left_button(mb):
		accept_event()
		return

	# Tracked, never consumed: the camera still gets both edges of the right button, so orbiting
	# is untouched and only a click that did NOT orbit opens the menu.
	if mb != null and mb.button_index == MOUSE_BUTTON_RIGHT:
		_track_right_button(mb)

	if _camera_rig.handle_input(event, size):
		accept_event()


## A right CLICK on a two-part selection asks for the seam menu; a right DRAG is an orbit and
## asks for nothing (ADR 0009).
func _track_right_button(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		_rmb_pos = mb.position
		_rmb_active = true
		return
	if not _rmb_active:
		return
	_rmb_active = false
	if _rmb_pos.distance_to(mb.position) > CLICK_SLOP_PX:
		return
	# ANY multi-part selection, not exactly two (ADR 0013). Which of its connections the menu
	# actually offers is ShipBuilder's decision - it takes the seams with both ends selected - and
	# the view's job is only to notice that there is more than one part under the pointer's
	# selection at all.
	if _scene != null and _scene.selection().size() >= 2:
		seam_menu_requested.emit(mb.position)


## Input while the EXPLODED view is up: the camera's verbs, and picking a module.
##
## RETIRED(2026-09-02): swallowing the left button here - "exploded view does not let part
## selection". The module bakes carry pick bodies now (ShipExplodeView), so a click resolves to
## the part the module came from through the ordinary pick path. Everything that edits geometry
## stays out: no gizmo, no clone, no placement, because what is on screen is a set of bakes and
## not the document. Keys the camera does not own fall through unaccepted, so the builder's E /
## ASSEMBLE hotkey still reaches _unhandled_key_input.
func _handle_explode_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null:
		if key.pressed and _handle_camera_key(key.keycode):
			accept_event()
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and _is_wheel(mb.button_index):
		# Plain wheel zooms here. There is no part to scale, so the assembled view's reason for
		# reserving it does not apply.
		if mb.pressed:
			_camera_rig.dolly(1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
		accept_event()
		return
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_explode_left_button(mb)
		accept_event()
		return
	if _camera_rig.handle_input(event, size):
		accept_event()


## Selecting a module: the press records, a release that did not turn into a drag picks. The
## same click-versus-drag rule the assembled view uses, so a camera orbit that happens to start
## over a module does not reselect it.
func _explode_left_button(mb: InputEventMouseButton) -> void:
	if mb.pressed:
		grab_focus()
		if mb.double_click:
			_pick_pos = mb.position
			_double_pending = true
			_press_active = false
			return
		_press_pos = mb.position
		_press_active = true
		return
	if not _press_active:
		return
	_press_active = false
	if _press_pos.distance_to(mb.position) > CLICK_SLOP_PX:
		return
	_pick_pos = mb.position
	_pick_additive = mb.shift_pressed
	_pick_focus = mb.ctrl_pressed
	_pick_shift = mb.shift_pressed
	_pick_ctrl = mb.ctrl_pressed
	_pick_alt = mb.alt_pressed
	_pick_pending = true


## The left button when NO placement is live. Returns true when it was claimed by a verb
## that must not also reach the camera - a gizmo grab or an Alt clone.
##
## Both resolve at PRESS time, not on release, because both start a drag: the clone has to
## be peeling off under the pointer by the time the player moves, and a gizmo grab has to
## own the motion that follows it. Ordinary picking still waits for the release, so a
## camera orbit that happens to start over a part does not reselect it.
func _handle_left_button(mb: InputEventMouseButton) -> bool:
	if mb.pressed:
		grab_focus()
		if mb.double_click:
			_pick_pos = mb.position
			_double_pending = true
			_press_active = false
			return true
		if mb.alt_pressed and _clone_selected():
			return true
		if _try_begin_handle_drag(mb.position):
			return true
		_press_pos = mb.position
		_press_active = true
		return false
	if _press_active:
		_press_active = false
		# A left button that barely moved is a click, so it picks. Anything further was a
		# camera drag and must not change the selection.
		if _press_pos.distance_to(mb.position) <= CLICK_SLOP_PX:
			_pick_pos = mb.position
			# SHIFT extends the selection; CTRL re-centres the orbit on what was clicked.
			#
			# Ctrl used to be a second additive modifier, which made it a duplicate of Shift and
			# left no key for the thing the author actually asked for: "when selecting an object
			# while holding ctrl it should make that object the center of orbit attention". A
			# builder whose camera always orbits the world origin is unusable once a ship is
			# bigger than the first hull.
			_pick_additive = mb.shift_pressed
			_pick_focus = mb.ctrl_pressed
			# Captured separately from `_pick_additive` because PaintMode reads all three
			# independently: Shift paints a whole part, Shift+Ctrl every part of the family,
			# Alt is the eyedropper (API_CONTRACT_SPORE section 10). Recorded at PRESS time
			# with the rest of the pick, since the pick itself resolves a frame later.
			_pick_shift = mb.shift_pressed
			_pick_ctrl = mb.ctrl_pressed
			_pick_alt = mb.alt_pressed
			_pick_pending = true
	return false


## True when the event belonged to the placement and must not reach the camera.
##
## Motion with no button, or with the left button held, drags the ghost. Motion with the
## RIGHT button held is a camera orbit and is deliberately let through, so the player can
## look at the far side of a hull without cancelling what they are placing.
func _handle_placement_input(event: InputEvent) -> bool:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		if (mm.button_mask & CAMERA_DRAG_MASK) != 0:
			return false
		_placement.set_drag_mode(_drag_mode_for(mm.ctrl_pressed, mm.shift_pressed))
		if _handle_drag != ShipPlacement.Handle.NONE:
			_drive_handle(mm.position)
			return true
		_queue_ghost_ray(mm.position)
		return true

	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	if mb.pressed:
		grab_focus()
		_placement.set_drag_mode(_drag_mode_for(mb.ctrl_pressed, mb.shift_pressed))
		_queue_ghost_ray(mb.position)
	else:
		# A gizmo drag has already written every value it is going to; re-solving the ghost
		# from the release position would throw the rotation away and snap it back to the
		# surface under the pointer.
		if (
			_handle_drag == ShipPlacement.Handle.NONE
			or _handle_drag == ShipPlacement.Handle.PLACEMENT
		):
			# Resolve the release position first, then commit: the ghost commits exactly
			# where it is drawn, never one frame behind the pointer.
			_queue_ghost_ray(mb.position)
		# Recorded BEFORE the handle is cleared: a gizmo release, the placement arrow included,
		# may never remove the part (F13 - a rotation that ended off the silhouette deleted it).
		_release_may_remove = _handle_drag == ShipPlacement.Handle.NONE
		_handle_drag = ShipPlacement.Handle.NONE
		_handle_index = -1
		_ghost_commit_pending = true
	return true


## Ctrl and Shift, resolved to a ShipPlacement.DragMode. Ctrl wins when both are held: the
## vertical axis is the more specific claim, and Spore's own modifiers do not combine.
func _drag_mode_for(ctrl: bool, shift: bool) -> int:
	if ctrl:
		return ShipPlacement.DragMode.VERTICAL
	if not shift:
		return ShipPlacement.DragMode.FREE
	if _scene != null and _scene.selection().is_empty():
		return ShipPlacement.DragMode.WHOLE_SHIP
	return ShipPlacement.DragMode.HORIZONTAL


static func _is_wheel(button_index: int) -> bool:
	return button_index == MOUSE_BUTTON_WHEEL_UP or button_index == MOUSE_BUTTON_WHEEL_DOWN


## The plain mouse wheel scales the selected part (or the ghost); Shift+wheel is the
## camera's. Returns true when the event was consumed here.
##
## The release half of a wheel click is swallowed too when the press was: leaving it to fall
## through would let OrbitCamera see half of every scale gesture.
func _handle_wheel(mb: InputEventMouseButton) -> bool:
	# Shift+wheel belongs to the camera and OrbitCamera claims it there, which keeps the
	# zoom binding in one place rather than half here and half there.
	if mb.shift_pressed:
		return false
	if not mb.pressed:
		return true
	var up: bool = mb.button_index == MOUSE_BUTTON_WHEEL_UP
	if _can_scale():
		_placement.scale_selected(1.0 if up else -1.0)
	else:
		# Nothing to scale, so zoom rather than swallowing the gesture. Done HERE, not by
		# falling through: OrbitCamera only takes the wheel with Shift held, so a fall-through
		# would silently do nothing. See the class docstring - this is the one binding in
		# this file that is judgement rather than citation.
		_camera_rig.dolly(-1.0 if up else 1.0)
	return true


## Is there anything for the wheel (or Up/Down) to resize right now? False also means "no
## placement bound", so every caller may dereference _placement after a true.
func _can_scale() -> bool:
	if _placement == null:
		return false
	if _placement.active:
		return true
	return _scene != null and not _scene.selection().is_empty()


## Keyboard half of the grammar. Tab and A are holds; everything else acts on the press.
func _handle_key(key: InputEventKey) -> bool:
	# RETIRED(2026-08-31): KEY_TAB was the second hold key, gating the 'advanced' handle set.
	# There is no handle set to gate any more - everything is always live - and the flag it drove
	# existed in three places with different defaults. See ShipHandles' class docs.
	var held: bool = key.keycode == KEY_A
	if key.echo:
		# Auto-repeat is neither a press nor a release. Swallowed for the hold key so repeat
		# cannot re-announce a state that has not changed - but PASSED THROUGH for the numpad
		# rotations and the arrow steps, which are the two bindings a player holds down on
		# purpose. At the shipped 0.5 degree snap, a numpad key that did not repeat would need
		# sixty taps to reach a quarter turn.
		if not (NUMPAD_ROTATE.has(key.keycode) or ARROW_DELTA.has(key.keycode)):
			return held
		if not key.pressed:
			return held
	if key.keycode == KEY_A:
		_break_symmetry_held = key.pressed
		return true
	if not key.pressed:
		return false
	return _dispatch_press(key)


## The press dispatch, split off so _handle_key keeps to gdlint's six-return budget - the same
## reason _handle_axis_key exists. Order matters only where two tables could both claim a key,
## which none of these four do.
func _dispatch_press(key: InputEventKey) -> bool:
	if key.keycode == KEY_P:
		_attached_pivot = not _attached_pivot
		_refresh_hints()
		return true
	if _handle_axis_key(key.keycode):
		return true
	if _handle_numpad(key):
		return true
	if _handle_arrow(key):
		return true
	return _handle_press_key(key.keycode)


## X / Y / Z set the rotation axis lock; Escape clears it. Split out of _handle_key so that
## function keeps to gdlint's six-return budget.
func _handle_axis_key(code: int) -> bool:
	if AXIS_LOCK_KEYS.has(code):
		_toggle_axis_lock(int(AXIS_LOCK_KEYS[code]))
		return true
	if code == KEY_ESCAPE and _axis_lock >= 0:
		_set_axis_lock(-1)
		return true
	return false


## Tapping the live axis again clears the lock, which is the behaviour that makes a one-key
## toggle safe to hit twice.
func _toggle_axis_lock(axis: int) -> void:
	_set_axis_lock(-1 if axis == _axis_lock else axis)


func _set_axis_lock(axis: int) -> void:
	if axis == _axis_lock:
		return
	_axis_lock = axis
	_refresh_hints()


## Numpad 7-9 / 4-6 / 1-3 turn the part about mount X / Y / Z; the middle key of each row zeroes
## that axis. Numpad 0 toggles which reference the part is aimed at and snaps it there.
##
## The axes are the MOUNT FRAME's, so "z is aligned with the placement vector" in the author's
## words is z aligned with the mount normal in the code's (ADR 0004 pinned +Z to the normal, and
## numpad 0 is the control that moves between the two readings when they differ).
func _handle_numpad(key: InputEventKey) -> bool:
	if key.keycode == KEY_KP_0:
		if not ShipReseat.aim_selection(_builder, _aim_to_normal):
			return false
		_aim_to_normal = not _aim_to_normal
		_refresh_hints()
		return true
	if not NUMPAD_ROTATE.has(key.keycode):
		return false
	if _placement == null or not _can_scale():
		return false
	var entry: Array = NUMPAD_ROTATE[key.keycode]
	var axis: int = int(entry[0])
	var direction: int = int(entry[1])
	if direction == 0:
		_placement.rotate_selected(axis, 0.0, true)
		return true
	var step: float = _snap_degrees()
	if key.shift_pressed:
		step = maxf(step, NUMPAD_COARSE)
	_placement.rotate_selected(axis, step * float(direction))
	return true


## The document's own angular snap increment - "a snaping system of .5 degrees (changeable)" - so
## the numpad steps by whatever the player set rather than by a number baked in here.
func _snap_degrees() -> float:
	if _doc != null and _doc.settings.has("snap_deg"):
		var raw: Variant = _doc.settings["snap_deg"]
		if raw is float or raw is int:
			return maxf(float(raw), 0.01)
	if _cfg != null:
		return maxf(_cfg.snap_deg, 0.01)
	return 0.5


## Arrow keys step the selection's placement vector by one snap increment - see ARROW_DELTA.
##
## RETIRED(2026-09-01): UP/DOWN scaled the selection. The author asked for "arrow keys to snap
## across parent placement vectors" and the arrows were the only keys that could plausibly mean
## it; keyboard scaling moved to PAGE UP / PAGE DOWN, which is in the legend.
## RETIRED(2026-09-02): _parent_local(), the parent's origin in the part's frame that the old
## placement ARROW was hit-tested against -> ShipSceneBuilder.part_seam(), the plane the
## footprint collar is drawn in.
func _handle_arrow(key: InputEventKey) -> bool:
	if not ARROW_DELTA.has(key.keycode):
		return false
	var dir: Vector2i = ARROW_DELTA[key.keycode]
	var step: float = _snap_degrees()
	if key.shift_pressed:
		step = maxf(step, NUMPAD_COARSE)
	return ShipReseat.step_placement(_builder, dir.x, dir.y, step)


## The press-only keys, as one if-chain with a single exit so the dispatch stays flat.
func _handle_press_key(code: int) -> bool:
	if code == KEY_PAGEUP or code == KEY_PAGEDOWN:
		if not _can_scale():
			return false
		_placement.scale_selected(1.0 if code == KEY_PAGEUP else -1.0)
		return true
	return _handle_camera_key(code)


## The camera's own keys - zoom and orbit - which stay live in every state, the exploded view
## included.
func _handle_camera_key(code: int) -> bool:
	if code == KEY_EQUAL or code == KEY_PLUS or code == KEY_KP_ADD:
		_camera_rig.dolly(-1.0)
	elif code == KEY_MINUS or code == KEY_KP_SUBTRACT:
		_camera_rig.dolly(1.0)
	elif code == KEY_LESS or code == KEY_COMMA:
		_camera_rig.orbit_by(Vector2(-ORBIT_KEY_PX, 0.0))
	elif code == KEY_GREATER or code == KEY_PERIOD:
		_camera_rig.orbit_by(Vector2(ORBIT_KEY_PX, 0.0))
	else:
		return false
	return true


## The always-visible key legend.
##
## WHY IT IS ALWAYS VISIBLE. The builder has a modal grammar - Ctrl and Shift constrain a drag,
## A breaks symmetry, X/Y/Z lock a rotation axis - and none of it
## is discoverable from the screen. The author reported exactly that ("no hot key hints for
## rotating the placement object in 3d space"). A legend that only appears on hover would have the
## same problem, so it is a permanent, dim, non-interactive strip in the corner that rewrites
## itself as the state changes.
##
## MOUSE_FILTER_IGNORE on both nodes: this sits on top of the whole 3D view, and a legend that
## swallowed a click would break placement everywhere it overlapped.
func _build_hint_overlay() -> void:
	_hint_label = Label.new()
	_hint_label.name = "KeyHints"
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.offset_left = ShipTheme.pxf(HINT_MARGIN_PX)
	_hint_label.offset_bottom = -ShipTheme.pxf(HINT_MARGIN_PX)

	# INSIDE the inner SubViewport, not on this node.
	#
	# This class is a SubViewportContainer, i.e. a Container, and a Container OVERRIDES the rect
	# of every Control child on each sort - anchors and offsets are simply ignored there. A label
	# parented here got stretched to the full container rect, which happened to look right only
	# because of its vertical alignment, and stopped rendering at all the moment real anchors were
	# applied to it. A Control inside the SubViewport lays out against the viewport rect the
	# normal way, draws over the 3D, is clipped to the view, and goes through the palette
	# quantizer with everything else. `gui_disable_input` is already true, so it eats nothing.
	var overlay: Control = Control.new()
	overlay.name = "ViewOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_hint_label)
	_viewport.add_child(overlay)
	_refresh_hints()


## Rewrite the legend for the current state.
##
## Early-outs unless something that actually changes the text changed, because one of its callers
## is a per-move signal. `_hints_key` is the whole of the legend's input state.
func _refresh_hints() -> void:
	if _hint_label == null:
		return
	# The colour is applied on EVERY call, before the early-out. _ready() builds the legend while
	# `_theme` is still null, so the first call cannot tint it; setup() arrives with the theme but
	# would have hit the early-out and returned before ever reaching the override, leaving the
	# legend in the default white instead of the dim role. Measured: it rendered #daf1e0, the
	# BRIGHTEST palette entry, on a strip that is meant to sit quietly under the ship.
	if _theme != null:
		_hint_label.add_theme_color_override("font_color", _theme.color_for_role("text_dim"))

	var placing: bool = _placement != null and _placement.active
	var key: String = (
		"%d|%d|%d|%d|%d"
		% [
			int(placing),
			_axis_lock,
			int(_aim_to_normal),
			int(_attached_pivot),
			int(_exploded) + 2 * int(_baked) + 4 * int(not _isolated.is_empty())
		]
	)
	if key == _hints_key:
		return
	_hints_key = key
	var lines: PackedStringArray = PackedStringArray()
	if not _isolated.is_empty():
		lines.append("EDITING COMPONENT %s - THE REST IS WASHED OUT" % _isolated.to_upper())
		lines.append("LMB SELECT A PART OF IT   EDIT IT IN THE INSPECTOR (EVERY INSTANCE FOLLOWS)")
		lines.append("ESC OR DOUBLE-CLICK EMPTY SPACE TO CLOSE")
		_hint_label.text = "\n".join(lines)
		return
	if _exploded:
		lines.append("EXPLODED - EVERY MODULE PULLED OFF ITS SEAM, WALLS AND DOORS BAKED")
		lines.append("RMB ORBIT   , / . ORBIT   +/- ZOOM   SHIFT+WHEEL ZOOM")
		lines.append("E OR ASSEMBLE TO RETURN")
		_hint_label.text = "\n".join(lines)
		return
	if _baked:
		lines.append("BAKED - EVERY PIECE AS THE ENGINE MADE IT, LINKS AND WALLS INCLUDED")
		(
			lines
			. append(
				"EDIT FREELY - UPDATE MESHES WHEN THE BUTTON LIGHTS   DOUBLE-CLICK A COMPONENT TO OPEN IT"
			)
		)
		lines.append("LMB SELECT   RMB ORBIT   , / . ORBIT   +/- ZOOM   E EXPLODE")
		_hint_label.text = "\n".join(lines)
		return
	if placing:
		lines.append("DRAG ON A PART TO PLACE   LMB COMMIT   ESC CANCEL")
		lines.append("CTRL SLIDE ALONG NORMAL   SHIFT KEEP ON THIS PART")
	else:
		lines.append("LMB SELECT   SHIFT+LMB ADD   CTRL+LMB ORBIT HERE   RMB ORBIT")
		lines.append("ALT+DRAG CLONE   , / . ORBIT   +/- ZOOM   WHEEL ZOOM")
	lines.append("HANDLES: RINGS ROTATE   ARROWS STRETCH   STALK OFFSETS   COLLAR SLIDES")
	lines.append("TOP/BOTTOM ARROW SIDEWAYS SKEWS")
	lines.append("ARROWS STEP PLACEMENT YAW/PITCH BY SNAP (SHIFT COARSE)   PGUP/PGDN SCALE")
	lines.append("NUMPAD 789/456/123 ROTATE X/Y/Z (MIDDLE ZEROES, SHIFT COARSE)")
	lines.append(
		"NUMPAD 0 AIM AT %s" % ("THE SURFACE NORMAL" if _aim_to_normal else "THE PLACEMENT VECTOR")
	)
	lines.append(
		(
			"P PIVOT: %s"
			% (
				"ATTACHED - RINGS SWING THE PART ACROSS ITS PARENT"
				if _attached_pivot
				else "FLOATING - RINGS SPIN THE PART IN PLACE"
			)
		)
	)
	lines.append("A HOLD BREAK SYMMETRY")
	lines.append(_axis_lock_line())
	_hint_label.text = "\n".join(lines)
	if _theme != null:
		_hint_label.add_theme_color_override("font_color", _theme.color_for_role("text_dim"))


func _axis_lock_line() -> String:
	if _axis_lock < 0:
		return "X / Y / Z LOCK ROTATION TO ONE AXIS   (NONE LOCKED)"
	return (
		"X / Y / Z LOCK ROTATION TO ONE AXIS   LOCKED: %s   ESC CLEARS"
		% ["X", "Y", "Z"][_axis_lock]
	)


## Alt on a selected part. ShipPlacement does the whole verb - clone, select, begin_move -
## so the copy is already under the pointer when the drag starts.
func _clone_selected() -> bool:
	if _placement == null or _scene == null or _scene.selection().is_empty():
		return false
	return _placement.clone_selected() != ""


## Grab the gizmo handle under the pointer, if any, and start a move on its part.
##
## Hit-testing is ShipHandles' screen-space test against the drawn wireframe loops, not a
## physics query, so it costs nothing and can run on every left press. Exactly one selected
## part has a gizmo, which is also the only case ShipSceneBuilder draws one for.
func _try_begin_handle_drag(pos: Vector2) -> bool:
	if _placement == null or _scene == null or _camera_rig == null:
		return false
	var ids: PackedStringArray = _scene.selection()
	var cam: Camera3D = _camera_rig.get_camera()
	if ids.size() != 1 or cam == null:
		return false
	var shape: ResolvedShape = _scene.part_shape(ids[0])
	if shape == null:
		return false
	var xf: Transform3D = _scene.part_transform(ids[0])
	var hit: Dictionary = ShipHandles.hit_test(
		cam,
		xf,
		shape,
		pos,
		_scene.part_rot(ids[0]),
		_scene.part_seam(ids[0]),
		_scene.part_has_seam(ids[0])
	)
	if int(hit[ShipHandles.HIT_HANDLE]) == ShipPlacement.Handle.NONE:
		return false
	_placement.begin_move(ids[0])
	if not _placement.active:
		return false
	_handle_drag = int(hit[ShipHandles.HIT_HANDLE])
	_handle_index = int(hit[ShipHandles.HIT_INDEX])
	_handle_last = pos
	return true


## One frame of a gizmo drag. An offset handle spends vertical motion as standoff along the mount
## normal. A rotation handle spends horizontal motion on the mount-frame axis
## that handle drives (ADR 0004 - RING_X/Y/Z are independent now, and the free ball spins the
## normal); a morph handle spends motion along its own axis as a stretch, right and up both
## growing the part.
func _drive_handle(pos: Vector2) -> void:
	if _placement == null:
		return
	var delta: Vector2 = pos - _handle_last
	_handle_last = pos
	if _handle_drag == ShipPlacement.Handle.PLACEMENT:
		# The parent-side arrow slides the part over its parent, which is exactly what an ordinary
		# drag on the part does - so it goes through the same solve rather than a second one.
		_queue_ghost_ray(pos)
		return
	if _handle_drag == ShipPlacement.Handle.MORPH:
		_drive_morph(delta)
		return
	if _handle_drag == ShipPlacement.Handle.OFFSET:
		# Screen Y grows downward, so dragging UP must push the part OUT along its normal.
		_placement.offset_selected(-delta.y * ShipPlacement.OFFSET_M_PER_PIXEL)
		return
	var axis: int = _axis_lock
	if axis < 0:
		axis = ShipPlacement.axis_for_handle(_handle_drag)
	var degrees: float = delta.x * ShipPlacement.ROT_DEG_PER_PIXEL
	if _attached_pivot:
		_swing_placement(axis, degrees)
		return
	_placement.rotate_selected(axis, degrees)


## ATTACHED PIVOT: the ring turns the PLACEMENT VECTOR instead of the part, so the part swings
## across its parent's surface with the anchor. Written straight onto the live ghost through
## set_values(), so the preview is the same one a floating rotation gets.
func _swing_placement(axis: int, degrees: float) -> void:
	if _builder == null or _placement == null:
		return
	var pid: String = _placement.moving_part_id()
	if pid.is_empty():
		return
	var live: Dictionary = _placement.values()
	var angles: Vector2 = ShipReseat.swing_placement(
		_builder.get_doc(),
		_builder.get_data(),
		_builder.get_config(),
		pid,
		float(live["yaw"]),
		float(live["pitch"]),
		axis,
		degrees
	)
	_placement.set_values(angles.x, angles.y, live["rot"], float(live["offset"]))


## A morph-handle drag. The TOP and BOTTOM handles do double duty, exactly as Spore's do: pulled
## along their own axis they stretch the part, pushed SIDEWAYS they lean it (ADR 0007). The other
## four only stretch - a side handle pushed sideways is already its own stretch, and overloading it
## would make the same gesture mean two things on the same handle.
##
## Which lean the sideways push drives - X or Z - is decided by the CAMERA, not by a fixed
## mapping: the part's local +X and +Z are projected to screen and the drag goes to whichever one
## it is more aligned with. A fixed mapping would send a rightward drag to +X even when the player
## has orbited round to where +X points at them.
func _drive_morph(delta: Vector2) -> void:
	var axis: Vector3 = ShipHandles.morph_axis(_handle_index)
	if absf(axis.y) < 0.5:
		_placement.morph_selected(axis, delta.x - delta.y)
		return
	_placement.morph_selected(axis, -delta.y)
	if absf(delta.x) > 0.0:
		_placement.skew_selected(_screen_lean_param(delta.x), _screen_lean_amount(delta.x))


## Whichever of the part's own X and Z axes runs more nearly left-to-right on screen.
func _screen_lean_param(_sideways: float) -> String:
	return (
		"skew_x"
		if _screen_axis(Vector3.RIGHT).length() >= _screen_axis(Vector3.BACK).length()
		else "skew_z"
	)


## The sideways drag, signed so that pushing right always leans the part right on screen - the
## chosen local axis may project to the left, and a handle that leans away from the pointer reads
## as broken rather than as a convention.
func _screen_lean_amount(sideways: float) -> float:
	var live: Vector2 = _screen_axis(
		(
			Vector3.RIGHT
			if _screen_axis(Vector3.RIGHT).length() >= _screen_axis(Vector3.BACK).length()
			else Vector3.BACK
		)
	)
	return sideways * (1.0 if live.x >= 0.0 else -1.0)


## A part-local direction projected into screen space, as a 2D vector from the part's origin.
func _screen_axis(local: Vector3) -> Vector2:
	if _scene == null or _camera_rig == null:
		return Vector2.ZERO
	var ids: PackedStringArray = _scene.selection()
	var cam: Camera3D = _camera_rig.get_camera()
	if ids.is_empty() or cam == null:
		return Vector2.ZERO
	var xf: Transform3D = _scene.part_transform(ids[0])
	var here: Vector3 = xf.origin
	var there: Vector3 = xf * local
	if cam.is_position_behind(here) or cam.is_position_behind(there):
		return Vector2.ZERO
	return cam.unproject_position(there) - cam.unproject_position(here)


## Re-centre the orbit on a part without changing the camera's distance or angles, so the view
## swings to look at what was picked instead of jumping.
##
## Uses the part's TRANSFORM ORIGIN rather than the centre of its bounding box: the origin is the
## point the attach model actually places, so orbiting about it keeps a part steady under the
## pointer while its own handles are dragged.
func _focus_on_part(part_id: String) -> void:
	if _scene == null or _camera_rig == null or part_id == "":
		return
	var xform: Transform3D = _scene.part_transform(part_id)
	_camera_rig.set_focus(xform.origin)


func _queue_ghost_ray(local_pos: Vector2) -> void:
	_ghost_ray_pos = local_pos
	_ghost_ray_pending = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_press_active = false
		if _camera_rig != null:
			_camera_rig.release_drag()
	elif what == NOTIFICATION_FOCUS_EXIT:
		# The key-up for a held modifier is delivered to whoever has focus, so an A held across a
		# focus change would otherwise stick down forever.
		#
		# This used to reset the handle set here as well, which meant clicking a palette cell -
		# any focus change at all - silently dropped a selected part back to the ball-only gizmo
		# and left every grab spinning it about its placement vector.
		_break_symmetry_held = false


## Picking runs here, not in _gui_input: the direct space state may only be queried
## inside a physics frame. The placement ray is resolved from the same frame, in order:
## move the ghost, then commit it if the button came up.
func _physics_process(_delta: float) -> void:
	if _ghost_ray_pending:
		_ghost_ray_pending = false
		_do_ghost_ray(_ghost_ray_pos)
	if _ghost_commit_pending:
		_ghost_commit_pending = false
		_finish_placement()
	if not _pick_pending and not _double_pending:
		return
	var double: bool = _double_pending
	_pick_pending = false
	_double_pending = false
	_do_pick(_pick_pos, _pick_additive, double)


## Left button up over a live placement. Dragging a part clear of the ship REMOVES it
## (SPORE_CLONE_SPEC section 2) - but only off a plain surface drag, never off a gizmo
## handle (`_release_may_remove`); anything else commits.
##
## Both exit paths tear the ghost down - remove_if_dragged_off() cancels before it edits,
## and a successful commit resets - and a REFUSED commit deliberately leaves it up with
## ghost_validity_changed carrying the gate's message. Nothing here needs to know which way
## it went, but the ghost is accounted for in all three.
func _finish_placement() -> void:
	var may_remove: bool = _release_may_remove
	_release_may_remove = false
	if _placement == null or not _placement.active:
		return
	if may_remove and _placement.remove_if_dragged_off():
		return
	_placement.commit()


func _do_ghost_ray(local_pos: Vector2) -> void:
	if _placement == null or not _placement.active or _camera_rig == null:
		return
	var cam: Camera3D = _camera_rig.get_camera()
	if cam == null:
		return
	# Same coordinate story as _do_pick: with stretch = true a Control-local position IS an
	# inner-viewport position, so project_ray_* needs nothing global.
	_placement.update_from_ray(cam.project_ray_origin(local_pos), cam.project_ray_normal(local_pos))
	# The pointer moved, so the expensive gate result is about to be stale: restart the
	# debounce rather than paying for a sampling grid on a frame the player is mid-drag.
	if _gate_timer != null:
		_gate_timer.start()


## The idle half of the two-tier gate. Runs the physical budgets, which cost a full sampling
## grid through ShipSdf and must never touch a drag frame (API_CONTRACT_SPORE section 6).
func _on_gate_idle() -> void:
	if _placement != null and _placement.active:
		_placement.recheck_gate_with_metrics()


# ---------------------------------------------------------------- ghost


func _on_ghost_moved(_yaw: float, _pitch: float, _rot: Vector3, _offset: float) -> void:
	_refresh_ghost()


func _on_ghost_validity_changed(_is_valid: bool, _reason: String) -> void:
	_refresh_ghost()


## DEFAULT <-> GHOST is a state change with no validity change behind it - both are legal -
## so the ghost has to be repainted from this signal as well as from the validity one.
func _on_ghost_state_changed(_state: int) -> void:
	_refresh_ghost()
	# There is no placement_started signal (the contract's signal set is frozen), and this is the
	# first thing that fires once a ghost goes live. _refresh_hints() early-outs when the legend
	# would not change, so calling it from a per-move signal costs one bool compare.
	_refresh_hints()


func _on_placement_committed(_part_id: String) -> void:
	_clear_ghost()
	_refresh_hints()


func _on_placement_cancelled() -> void:
	_clear_ghost()
	_refresh_hints()


func _refresh_ghost() -> void:
	if _scene == null:
		return
	if _placement == null or not _placement.active:
		_clear_ghost()
		return
	var shape: ResolvedShape = _placement.ghost_shape()
	if shape == null:
		_clear_ghost()
		return
	_scene.set_suppressed_part(_placement.moving_part_id())
	# The pending part has no id yet, so the symmetry cascade is asked about whatever it belongs
	# to: the part being re-placed, or the parent a new one will attach to.
	var owner_id: String = _placement.moving_part_id()
	if owner_id == "":
		owner_id = _placement.target_parent
	_scene.show_ghost(shape, _placement.preview_transform(), _placement.ghost_state(), owner_id)
	# Which targets exist and which one is live - the whole reason the drop lands where it
	# does, made visible before the click rather than explained after it.
	var preview: Dictionary = _placement.snap_preview()
	var points: PackedVector3Array = preview["points"]
	_scene.show_snap_targets(points, int(preview["live"]))


## Every placement exit path funnels here: commit, cancel, a shape that will not resolve,
## and the placement being unbound. The gate debounce is stopped with the rest, so a timer
## armed mid-drag cannot fire a sampling pass into a placement that has already ended.
func _clear_ghost() -> void:
	_ghost_ray_pending = false
	_ghost_commit_pending = false
	_release_may_remove = false
	_handle_drag = ShipPlacement.Handle.NONE
	_handle_index = -1
	if _gate_timer != null:
		_gate_timer.stop()
	if _scene == null:
		return
	_scene.hide_ghost()
	_scene.hide_snap_targets()
	_scene.set_suppressed_part("")


func _do_pick(local_pos: Vector2, additive: bool, double: bool = false) -> void:
	var pid: String = _pid_under(local_pos)
	# A double-click reports what it landed on, "" for empty space (ADR 0024).
	if double:
		part_double_clicked.emit(pid)
		return
	if pid == "":
		pick_cleared.emit()
		return
	if _pick_focus:
		_focus_on_part(pid)
	part_picked.emit(pid, additive)
	# Hold A while selecting: break symmetry on what was just picked, cascading to its
	# children (SPORE_CLONE_SPEC section 4). part_picked is emitted first and is delivered
	# synchronously, so the builder's selection is already the new one by the time this runs.
	if _break_symmetry_held and _placement != null:
		_placement.break_symmetry_selected()


## The part id under [param local_pos], through the pick layer; "" when nothing is there.
## local_pos is this Control's local coordinate, which with stretch = true is also the inner
## viewport coordinate - exactly what project_ray_* expects. No global anything.
func _pid_under(local_pos: Vector2) -> String:
	if _viewport == null or _camera_rig == null or _scene == null:
		return ""
	var cam: Camera3D = _camera_rig.get_camera()
	if cam == null:
		return ""
	var from: Vector3 = cam.project_ray_origin(local_pos)
	var dir: Vector3 = cam.project_ray_normal(local_pos)
	var space: PhysicsDirectSpaceState3D = _space_state()
	if space == null:
		return ""
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * PICK_RAY_LENGTH, ShipSceneBuilder.PICK_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return ""
	return _scene.part_id_for(hit.get("collider", null))


# ---------------------------------------------------------------- decor


func _build_environment() -> Environment:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = _role_color("background", Color(0.03, 0.07, 0.09))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Ambient is a MULTIPLIER on albedo, so a dark ambient colour and a dark albedo compound:
	# two mid-dark teals multiply to something the 16-entry quantizer rounds to background.
	# Ambient therefore sits high on the ramp and the albedo carries the hue.
	env.ambient_light_color = _role_color("accent", Color(0.47, 0.85, 0.67))
	env.ambient_light_energy = 0.75
	# Linear tonemap: anything filmic would re-map the ramp before the palette quantizer
	# ever sees it, and the palette is meant to be the only colour authority.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return env


func _rebuild_grid() -> void:
	if _grid == null:
		return
	var grid_color: Color = _role_color("grid", Color(0.08, 0.20, 0.22))
	var axis_color: Color = _role_color("line", Color(0.15, 0.48, 0.47))

	var grid_mat: StandardMaterial3D = _line_material(grid_color)
	var axis_mat: StandardMaterial3D = _line_material(axis_color)

	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_mat)
	var n: int = int(GRID_EXTENT / GRID_STEP)
	for i: int in range(-n, n + 1):
		var t: float = float(i) * GRID_STEP
		if absf(t) < 0.001:
			continue
		mesh.surface_add_vertex(Vector3(t, 0.0, -GRID_EXTENT))
		mesh.surface_add_vertex(Vector3(t, 0.0, GRID_EXTENT))
		mesh.surface_add_vertex(Vector3(-GRID_EXTENT, 0.0, t))
		mesh.surface_add_vertex(Vector3(GRID_EXTENT, 0.0, t))
	mesh.surface_end()

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, axis_mat)
	mesh.surface_add_vertex(Vector3(-GRID_EXTENT, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(GRID_EXTENT, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, -GRID_EXTENT))
	mesh.surface_add_vertex(Vector3(0.0, 0.0, GRID_EXTENT))
	mesh.surface_end()

	_grid.mesh = mesh


## The MAX BOUNDING BOX, drawn as eight corner brackets around the ship origin.
##
## Reported missing in the author's own words - "i dont see the max bounding box". It is
## ShipConfig.max_bbox_m, the same per-axis budget the BBOX gauge reads and the same one
## ShipBuilder._bbox_exceeded() enforces, so what is drawn and what refuses an edit cannot drift.
##
## CORNER BRACKETS, NOT A FULL CAGE. The shipped budget is 250 x 120 x 250 m against a 5 m
## starting hull: twelve full edges at that scale is a box drawn around the entire grid floor and
## reads as scenery. Eight short brackets read as limits, which is the CAD convention and is what
## the thing actually is.
func _rebuild_bbox_cage() -> void:
	if _bbox_cage == null:
		return
	if _cfg == null:
		_bbox_cage.visible = false
		return
	var half: Vector3 = _cfg.max_bbox_m * 0.5
	if half.x <= 0.0 or half.y <= 0.0 or half.z <= 0.0:
		_bbox_cage.visible = false
		return
	# The colour is the whole readout: line while the ship fits, warning the moment it does not.
	var over: bool = _bbox_over(half)
	var tint: Color = _role_color("warning" if over else "grid", Color(0.08, 0.20, 0.22))
	var arm: Vector3 = Vector3(
		minf(half.x * BBOX_BRACKET_FRACTION, half.x),
		minf(half.y * BBOX_BRACKET_FRACTION, half.y),
		minf(half.z * BBOX_BRACKET_FRACTION, half.z)
	)
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material(tint))
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var corner: Vector3 = Vector3(half.x * sx, half.y * sy, half.z * sz)
				mesh.surface_add_vertex(corner)
				mesh.surface_add_vertex(corner - Vector3(arm.x * sx, 0.0, 0.0))
				mesh.surface_add_vertex(corner)
				mesh.surface_add_vertex(corner - Vector3(0.0, arm.y * sy, 0.0))
				mesh.surface_add_vertex(corner)
				mesh.surface_add_vertex(corner - Vector3(0.0, 0.0, arm.z * sz))
	mesh.surface_end()
	_bbox_cage.mesh = mesh
	_bbox_cage.visible = true


## Whether the CURRENT ship reaches outside the cage, measured from the parts already resolved in
## the scene rather than by re-running the metrics pass - this runs on every sync and the metrics
## bbox costs a full attach solve.
func _bbox_over(half: Vector3) -> bool:
	if _scene == null:
		return false
	var box: AABB = _scene.scene_aabb()
	var reach: Vector3 = Vector3(
		maxf(absf(box.position.x), absf(box.end.x)),
		maxf(absf(box.position.y), absf(box.end.y)),
		maxf(absf(box.position.z), absf(box.end.z))
	)
	return reach.x > half.x or reach.y > half.y or reach.z > half.z


func _line_material(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


func _role_color(role: String, fallback: Color) -> Color:
	if _theme == null:
		return fallback
	return _theme.color_for_role(role)
