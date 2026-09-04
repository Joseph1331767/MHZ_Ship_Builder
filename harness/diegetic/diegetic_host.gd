## DiegeticHost - M7 placeholder: proves the ship builder works as a texture on a mesh in
## world space, driven by raycast rather than the OS cursor (SPEC section 10, AGENTS
## section 7). This is the acceptance test for the render-to-texture contract - anything
## in the builder that secretly depends on being a real window shows up here.
##
## SCENE IS CODE-BUILT ON PURPOSE. diegetic_host.tscn holds only this script on a bare
## Node3D; every mesh, light, camera and the SubViewport below are created in `_ready()`,
## for the same reason `ship_builder.gd` gives for its own scene (see that file's
## docstring): hand-authored .tscn text is error-prone and a diff of it is unreadable.
##
## THE INPUT PIPELINE THIS FILE EXISTS TO PROVE (SPEC section 10, task brief steps 1-6):
##   1. Every event, raycast from the active Camera3D through that event's own screen
##      position (`Camera3D.project_ray_origin` / `project_ray_normal`,
##      `PhysicsDirectSpaceState3D.intersect_ray`). This node is the "real world" the
##      builder is mounted in, not the builder itself, so reading the camera/viewport
##      like this is correct here - it would NOT be correct inside harness/builder or
##      core/, which may never read window size or a global mouse position (AGENTS
##      section 7 / SPEC section 10).
##   2. A hit against ScreenSurface's collider is converted to a local UV with
##      `ScreenSurface.get_uv_at()`, then to a viewport pixel with
##      `ScreenSurface.uv_to_pixel()` - see screen_surface.gd's docstring for why that
##      needs no V-flip.
##   3. A FRESH `InputEventMouseMotion` / `InputEventMouseButton` is built from that pixel
##      position and pushed into the hosted SubViewport with `push_input(event, true)`.
##      The real incoming event is only ever read for its fields (button_index, pressed,
##      double_click, modifiers, button_mask) - never mutated or reused - in
##      `_forward_motion()` / `_forward_button()`.
##   4. `relative` on the forwarded motion event is the difference between this UV's pixel
##      position and the previous one's, in VIEWPORT pixel space, not screen space (task
##      brief step 4) - tracked in `_last_pixel`.
##   5. Keyboard is forwarded unchanged (no coordinate mapping needed) but only while
##      `_focused` is true. Focus is entered by a mouse press that lands on the screen and
##      left by Escape - see `_set_focused()`. That is the ONLY thing focus decides: mouse
##      routing is decided purely by the per-event raycast hit-test, independent of focus,
##      so the very click that focuses the device also reaches whatever it landed on
##      inside the builder.
##   6. When the ray misses the screen while a drag/hover was in progress, the pointer is
##      told it left via `sub_viewport.notification(NOTIFICATION_WM_MOUSE_EXIT)`
##      (`_handle_miss_motion()`), so hover state does not stick on.
class_name DiegeticHost
extends Node3D

const BUILDER_SCENE_PATH: String = "res://harness/builder/ship_builder.tscn"

## SPEC section 10: the builder is a fixed 1280x800 SubViewport.
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 800)

## ASPECT CHECK (task brief): 1280 / 800 = 1.6. The screen is built at 1.2m x 0.75m, and
## 1.2 / 0.75 = 1.6 - same ratio, so the UI is not stretched on the panel.
const SCREEN_WIDTH_M: float = 1.2
const SCREEN_HEIGHT_M: float = 0.75

const SCREEN_POSITION: Vector3 = Vector3(0.0, 1.3, 0.1)
const CAMERA_START_POSITION: Vector3 = Vector3(0.0, 1.5, 2.2)
## 0 deg: with the rig math in `_apply_camera_transform()`, yaw 0 looks down local -Z,
## which points from the camera's start position (z = 2.2) toward the screen (z = 0.1).
const CAMERA_START_YAW_DEG: float = 0.0

const MOVE_SPEED_M_S: float = 2.2
const LOOK_DEG_PER_PIXEL: float = 0.12
const PITCH_LIMIT_DEG: float = 85.0
const RAY_LENGTH_M: float = 50.0

var _sub_viewport: SubViewport = null
var _builder_root: Node = null
var _screen: ScreenSurface = null
var _camera: Camera3D = null

var _cam_pos: Vector3 = CAMERA_START_POSITION
var _cam_yaw_deg: float = CAMERA_START_YAW_DEG
var _cam_pitch_deg: float = 0.0
## Held to look around the room with the mouse (only when the ray misses the screen -
## see `_handle_miss_motion()`). Left button is reserved entirely for the console.
var _rmb_held: bool = false

## The ONLY thing this flag gates is keyboard routing - see the class docstring, step 5.
var _focused: bool = false
## Whether the last routed event's ray hit the screen. Drives the WM_MOUSE_EXIT signal
## and the `relative` baseline for forwarded motion (task brief step 6).
var _hovering: bool = false
var _has_last_pixel: bool = false
var _last_pixel: Vector2 = Vector2.ZERO

## Real mouse/button events are queued here in `_input()` and drained in
## `_physics_process()`, because `PhysicsDirectSpaceState3D` may only be queried inside a
## physics frame (the same rule `ship_view3d.gd`'s `_do_pick()` documents and follows).
var _pending_events: Array[InputEvent] = []


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_kiosk()
	_screen = _build_screen()
	_camera = _build_camera()
	_sub_viewport = _build_builder_viewport()
	_builder_root = _load_builder_scene(_sub_viewport)
	_screen.set_viewport_texture(_sub_viewport.get_texture())
	_apply_camera_transform()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_pending_events.append(event)
		return
	var key: InputEventKey = event as InputEventKey
	if key != null:
		_handle_key(key)


func _physics_process(delta: float) -> void:
	_update_camera_movement(delta)
	for event: InputEvent in _pending_events:
		_route_event(event)
	_pending_events.clear()


# ---------------------------------------------------------------- keyboard


func _handle_key(key: InputEventKey) -> void:
	if key.pressed and not key.echo and key.keycode == KEY_ESCAPE and _focused:
		_set_focused(false)
		get_viewport().set_input_as_handled()
		return
	if not _focused or _sub_viewport == null:
		return
	# Keys need no coordinate mapping (task brief step 5) - forward the same event.
	_sub_viewport.push_input(key, true)
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- mouse routing


func _route_event(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if button == null and motion == null:
		return
	if button != null and button.button_index == MOUSE_BUTTON_RIGHT:
		_rmb_held = button.pressed

	var screen_pos: Vector2 = button.position if button != null else motion.position
	var hit: Dictionary = _raycast_screen(screen_pos)
	if hit.is_empty():
		if motion != null:
			_handle_miss_motion(motion)
		return

	var world_point: Vector3 = hit.get("position", Vector3.ZERO) as Vector3
	var uv: Vector2 = _screen.get_uv_at(world_point)
	var pixel: Vector2 = _screen.uv_to_pixel(uv)
	if motion != null:
		_forward_motion(motion, pixel)
	else:
		_forward_button(button, pixel)


func _raycast_screen(screen_pos: Vector2) -> Dictionary:
	if _camera == null or _screen == null:
		return {}
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return {}
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, from + dir * RAY_LENGTH_M
	)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or hit.get("collider", null) != _screen:
		return {}
	return hit


## Ray missed the screen. Tells the builder the pointer left (task brief step 6) and, if
## the free-look button is held, uses this motion to look around the room instead.
func _handle_miss_motion(motion: InputEventMouseMotion) -> void:
	if _hovering:
		_hovering = false
		_has_last_pixel = false
		if _sub_viewport != null:
			_sub_viewport.notification(NOTIFICATION_WM_MOUSE_EXIT)
	if not _rmb_held:
		return
	_cam_yaw_deg = wrapf(_cam_yaw_deg - motion.relative.x * LOOK_DEG_PER_PIXEL, -180.0, 180.0)
	_cam_pitch_deg = clampf(
		_cam_pitch_deg + motion.relative.y * LOOK_DEG_PER_PIXEL, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG
	)
	_apply_camera_transform()


## Builds a FRESH InputEventMouseMotion - never mutates `source` - with `relative` in
## viewport pixel space (task brief step 4), not screen space.
func _forward_motion(source: InputEventMouseMotion, pixel: Vector2) -> void:
	if _sub_viewport == null:
		return
	var relative: Vector2 = Vector2.ZERO
	if _hovering and _has_last_pixel:
		relative = pixel - _last_pixel
	_hovering = true
	_last_pixel = pixel
	_has_last_pixel = true

	var forwarded: InputEventMouseMotion = InputEventMouseMotion.new()
	forwarded.position = pixel
	forwarded.global_position = pixel
	forwarded.relative = relative
	forwarded.shift_pressed = source.shift_pressed
	forwarded.ctrl_pressed = source.ctrl_pressed
	forwarded.alt_pressed = source.alt_pressed
	# Not in the task brief's minimum list, but real and needed for drag detection inside
	# the builder's own Control tree (Godot's drag logic reads button_mask mid-motion).
	forwarded.button_mask = source.button_mask
	_sub_viewport.push_input(forwarded, true)


## Builds a FRESH InputEventMouseButton - never mutates `source`.
func _forward_button(source: InputEventMouseButton, pixel: Vector2) -> void:
	if _sub_viewport == null:
		return
	if source.pressed:
		_set_focused(true)

	var forwarded: InputEventMouseButton = InputEventMouseButton.new()
	forwarded.position = pixel
	forwarded.global_position = pixel
	forwarded.button_index = source.button_index
	forwarded.pressed = source.pressed
	forwarded.double_click = source.double_click
	forwarded.shift_pressed = source.shift_pressed
	forwarded.ctrl_pressed = source.ctrl_pressed
	forwarded.alt_pressed = source.alt_pressed
	forwarded.button_mask = source.button_mask
	# Real for wheel events - needed for the builder's dolly/zoom to scale correctly.
	forwarded.factor = source.factor
	_sub_viewport.push_input(forwarded, true)


func _set_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	if _screen != null:
		_screen.set_focused(focused)


# ---------------------------------------------------------------- free-look camera


## WASD only - gated by `_focused` so the builder's own fields own the keys once the
## device has focus (task brief step 5). Mouse-look is handled in `_handle_miss_motion()`
## instead, gated by the raycast hit-test rather than focus, since aiming at the console
## and looking around the room are already mutually exclusive by where the cursor points.
func _update_camera_movement(delta: float) -> void:
	if _focused:
		return
	var yaw_basis: Basis = Basis(Vector3.UP, deg_to_rad(_cam_yaw_deg))
	var forward: Vector3 = yaw_basis * Vector3(0.0, 0.0, -1.0)
	var right: Vector3 = yaw_basis * Vector3(1.0, 0.0, 0.0)
	var move: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move += forward
	if Input.is_key_pressed(KEY_S):
		move -= forward
	if Input.is_key_pressed(KEY_D):
		move += right
	if Input.is_key_pressed(KEY_A):
		move -= right
	if move.length_squared() > 0.0:
		_cam_pos += move.normalized() * MOVE_SPEED_M_S * delta
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	if _camera == null:
		return
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(_cam_yaw_deg))
	basis *= Basis(Vector3.RIGHT, deg_to_rad(-_cam_pitch_deg))
	_camera.transform = Transform3D(basis, _cam_pos)


# ---------------------------------------------------------------- scene construction


func _build_environment() -> void:
	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.name = "RoomEnvironment"
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.07, 0.08)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	add_child(env_node)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.name = "DimKeyLight"
	key_light.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
	key_light.light_energy = 0.2
	key_light.shadow_enabled = false
	add_child(key_light)

	var glow: OmniLight3D = OmniLight3D.new()
	glow.name = "ScreenGlow"
	glow.position = SCREEN_POSITION + Vector3(0.0, 0.0, 0.3)
	glow.light_color = Color(0.4, 0.85, 0.8)
	glow.light_energy = 0.6
	glow.omni_range = 2.0
	glow.shadow_enabled = false
	add_child(glow)


func _build_floor() -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Floor"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(8.0, 0.1, 8.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.045, 0.05)
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, -0.05, 0.0)
	add_child(mesh_instance)


## No collider by design - this placeholder's camera flies rather than walks. See
## docs/DIEGETIC_HOST.md's known limitations.
func _build_kiosk() -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Kiosk"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.5, 1.6, 0.45)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.07, 0.08)
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, 0.8, -0.1)
	add_child(mesh_instance)


func _build_screen() -> ScreenSurface:
	var screen: ScreenSurface = ScreenSurface.new()
	screen.name = "ScreenSurface"
	screen.width_m = SCREEN_WIDTH_M
	screen.height_m = SCREEN_HEIGHT_M
	screen.viewport_size = VIEWPORT_SIZE
	screen.position = SCREEN_POSITION
	add_child(screen)
	return screen


func _build_camera() -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.name = "FreeLookCamera"
	camera.fov = 65.0
	camera.near = 0.05
	camera.far = 200.0
	camera.current = true
	add_child(camera)
	return camera


func _build_builder_viewport() -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "BuilderViewport"
	viewport.size = VIEWPORT_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	viewport.gui_disable_input = false
	add_child(viewport)
	return viewport


## Defensive on purpose: at the time this file was written, ship_builder.tscn did not yet
## exist on disk (another agent owns it) - `load()`, not `preload()`, and a placeholder so
## this scene still runs standalone (mirrors `ShipBuilder._try_mount()`'s own pattern).
func _load_builder_scene(viewport: SubViewport) -> Node:
	if not ResourceLoader.exists(BUILDER_SCENE_PATH):
		push_warning("DiegeticHost: %s not found - showing placeholder" % BUILDER_SCENE_PATH)
		var placeholder: Node = _build_missing_placeholder()
		viewport.add_child(placeholder)
		return placeholder
	var packed: PackedScene = load(BUILDER_SCENE_PATH)
	if packed == null:
		push_warning("DiegeticHost: failed to load %s" % BUILDER_SCENE_PATH)
		var fallback: Node = _build_missing_placeholder()
		viewport.add_child(fallback)
		return fallback
	var inst: Node = packed.instantiate()
	viewport.add_child(inst)
	return inst


func _build_missing_placeholder() -> Control:
	var root: ColorRect = ColorRect.new()
	root.name = "BuilderMissingPlaceholder"
	root.color = Color(0.05, 0.3, 0.32)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var label: Label = Label.new()
	label.text = "SHIP BUILDER SCENE NOT FOUND\n%s" % BUILDER_SCENE_PATH
	label.set_anchors_preset(Control.PRESET_CENTER)
	root.add_child(label)
	return root
