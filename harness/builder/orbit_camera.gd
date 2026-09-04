## OrbitCamera - the single orbit view of the builder (SPEC section 11 / M2).
##
## A rig, not a camera: this Node3D sits AT the focus point and carries a Camera3D child
## pushed back along local +Z by `distance`. Orbiting is therefore two angles on the rig and
## dollying moves the child - no quaternion bookkeeping and no drift.
##
## THE CAMERA IS AN ORBIT/TURNTABLE ONLY: rotate and zoom, nothing else. That is not a
## simplification, it is the clone target. SPORE_CLONE_SPEC section 2 records four independent
## research passes over the official manual, the wikis and the forums finding no pan verb, no
## reset-view control and no front/side/top snap views in ANY Spore editor. Both were our own
## inventions and both are gone; see the two RETIRED notes below.
##
## RENDER-TO-TEXTURE RULE (SPEC section 10). This class never reads DisplayServer, never
## calls get_window(), and never asks for a global mouse position. Every input it handles
## arrives as an InputEvent whose position is already local to the 3D SubViewportContainer,
## and the caller passes the view size explicitly. That is what lets the same code drive
## the builder when it is a texture on a diegetic panel fed by Viewport.push_input().
class_name OrbitCamera
extends Node3D

## Emitted whenever the rig moves, so the view can redraw overlays that follow it.
signal camera_moved

# RETIRED(2026-08-31): `enum View { PERSPECTIVE, TOP, FRONT, SIDE }` + set_view_preset() -> removed
# as an un-Spore-like invention; no Spore editor has axis-snap views (SPORE_CLONE_SPEC section 2).

const PITCH_LIMIT_DEG: float = 89.5
const MIN_DISTANCE: float = 0.25
const MAX_DISTANCE: float = 4000.0
const ORBIT_DEG_PER_PIXEL: float = 0.35
const DOLLY_STEP: float = 0.9
const FRAME_MARGIN: float = 1.25

var focus: Vector3 = Vector3.ZERO
var distance: float = 24.0
var yaw_deg: float = -35.0
var pitch_deg: float = 24.0

var _camera: Camera3D = null
var _orbiting: bool = false
# RETIRED(2026-08-31): `_panning` -> removed with pan_by(); an orbit rig has one drag state.


func _ready() -> void:
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		_camera.fov = 55.0
		_camera.near = 0.05
		_camera.far = 6000.0
		_camera.current = true
		add_child(_camera)
	_apply()


func get_camera() -> Camera3D:
	return _camera


# ---------------------------------------------------------------- input


## Handle one event already localised to the 3D view. Returns true when the event was
## consumed, so the caller can accept_event() and stop it reaching anything else.
##
## Bindings (SPORE_CLONE_SPEC section 2, verified against the official manual): right-drag
## the background or left-drag empty space to orbit, SHIFT + wheel to zoom. The plain wheel
## is NOT ours - it scales the selected part - so the wheel is consumed here only with Shift
## held, and ShipView3D routes the unmodified wheel to ShipPlacement.scale_selected() before
## the event ever reaches this class.
##
## The LEFT button is deliberately NOT consumed on press - the view needs to tell a click
## (pick a part) from a drag (orbit), and only the view knows the drag threshold. A left
## press with SHIFT held starts no orbit at all: Shift + drag is the part-move verb.
##
## `view_size` is unused now that pan is gone; the parameter stays so the call site keeps
## reading as "one event, localised to this view of this size".
func handle_input(event: InputEvent, _view_size: Vector2) -> bool:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		return _handle_button(mb)
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		return _handle_motion(mm)
	return false


func _handle_button(mb: InputEventMouseButton) -> bool:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed and mb.shift_pressed:
				dolly(-1.0)
				return true
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and mb.shift_pressed:
				dolly(1.0)
				return true
		MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			return true
		MOUSE_BUTTON_LEFT:
			# Track the drag but do not consume it: the view still needs the release to
			# decide click-vs-drag for picking.
			_orbiting = mb.pressed and not mb.shift_pressed
			return false
	# RETIRED(2026-08-31): MOUSE_BUTTON_MIDDLE -> pan, and SHIFT + left-drag -> pan, both removed
	# as un-Spore-like inventions; Spore's camera has no pan verb (SPORE_CLONE_SPEC section 2).
	return false


func _handle_motion(mm: InputEventMouseMotion) -> bool:
	if _orbiting:
		orbit_by(mm.relative)
		return true
	return false


## Release any held drag state. Called when the pointer leaves the view so a button
## released outside does not leave the rig stuck in orbit.
func release_drag() -> void:
	_orbiting = false


# ---------------------------------------------------------------- motion


func orbit_by(relative: Vector2) -> void:
	yaw_deg = wrapf(yaw_deg - relative.x * ORBIT_DEG_PER_PIXEL, -180.0, 180.0)
	pitch_deg = clampf(
		pitch_deg + relative.y * ORBIT_DEG_PER_PIXEL, -PITCH_LIMIT_DEG, PITCH_LIMIT_DEG
	)
	_apply()


# RETIRED(2026-08-31): pan_by() -> removed as an un-Spore-like invention; Spore's editor camera
# orbits and zooms only, with no pan verb in the manual or any source (SPORE_CLONE_SPEC section 2).
# frame_aabb() below is how the focus point moves now, and it is the only thing that moves it.


## steps > 0 moves away, steps < 0 moves closer. Multiplicative so it feels constant.
func dolly(steps: float) -> void:
	distance = clampf(distance * pow(DOLLY_STEP, -steps), MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func set_focus(p: Vector3) -> void:
	focus = p
	_apply()


## Fit an AABB in view. Uses the bounding SPHERE of the box so the fit holds at every
## orbit angle instead of only the one it was computed at.
func frame_aabb(aabb: AABB) -> void:
	if not aabb.has_volume() and aabb.size.length() <= 0.0:
		focus = aabb.position
		distance = 8.0
		_apply()
		return
	focus = aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.25)
	var fov_rad: float = deg_to_rad(_camera.fov if _camera != null else 55.0)
	var fit: float = radius / maxf(sin(fov_rad * 0.5), 0.05) * FRAME_MARGIN
	distance = clampf(fit, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


# RETIRED(2026-08-31): set_view_preset() -> removed as an un-Spore-like invention; no Spore editor
# has front/side/top axis-snap views, and four research passes found no source for one
# (SPORE_CLONE_SPEC section 2, section 8b item 17). The 1/2/3/4 hotkeys that drove it are gone
# from ShipBuilder and the ShipView3D forwarder is gone with them.


# ---------------------------------------------------------------- internals


func _rig_basis() -> Basis:
	var b: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg))
	return b * Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))


func _apply() -> void:
	var b: Basis = _rig_basis()
	transform = Transform3D(b, focus)
	if _camera != null:
		# Child sits back along local +Z; its identity basis therefore looks down the
		# rig -Z, straight at the focus point.
		_camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, distance))
	camera_moved.emit()
