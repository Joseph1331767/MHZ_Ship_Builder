class_name ShipFlyCamera
extends Node3D
## FLY MODE's camera - a free 6-DOF rig with conserved momentum (ADR 0049).
##
## The author asked for this twice, the second time in full: "a fly mode like minecraft ... where a
## flashlight is attached to camera, and player flys with newtonian physics with some dampening but
## the feeling of floating in space".
##
## WHY IT IS NOT A MODE OF [OrbitCamera]. That class's entire state is four scalars - `focus`,
## `distance`, `yaw_deg`, `pitch_deg` - and `_rig_basis()` welds Y-up in, so it cannot represent
## roll and must not learn to. This is a separate node that owns its own [Camera3D]; the view swaps
## which one is `current`. [OrbitCamera] is untouched, and ADR 0049 explicitly does not reopen the
## `pan_by()` and axis-snap-preset deletions of 2026-08-31.
##
## ALL MOTION IS [ShipFlyState], which is pure static maths with its own test suite. This class is
## only plumbing: collect held keys into an input dictionary, tick, wear the resulting transform.
## Nothing here decides how flying feels - that is all constants in [ShipFlyState].
##
## KEY STATE COMES FROM [InputEventKey], NEVER `Input.is_key_pressed`. `DiegeticHost` feeds the
## builder through [method Viewport.push_input], which does not set the `Input` singleton, so a
## polled key would simply be dead once the builder is a texture on an in-game panel. That is not a
## style preference; it is the difference between working and not working in the shipping path.
##
## NO MOUSE CAPTURE. `Input.MOUSE_MODE_CAPTURED` and `warp_mouse` are global input-server calls,
## AGENTS section 7 forbids them, and there is no OS cursor on a diegetic quad anyway. The honest
## cost is that a look-drag which reaches the edge of the view stops there, which is exactly why the
## ARROW KEYS also apply torque - on a diegetic panel they are the only look verb there is.

## Emitted every tick the rig actually moved, so the view can re-feed the shader's distance cue and
## the torch. Named to match [signal OrbitCamera.camera_moved]'s role without colliding.
signal fly_moved

## Emitted when a key that leaves the mode was pressed. [param restore] true means "put the orbit
## camera back exactly as it was" (V / ESC); false means "keep looking at what I am looking at"
## (ENTER). [param frame] true means "and frame the whole ship" (F).
signal exit_requested(restore: bool, frame: bool)

## Degrees per second squared of torque per pixel of right-drag.
##
## RIGHT-DRAG IS TORQUE, NOT LOOK - the author's words were explicit about conserved angular
## momentum, so a flick leaves a slow drift and `X` is how you stop it. BASIC reverses this to
## direct look ([member direct_look]), because for the youngest rung "the view kept turning after I
## let go" reads as a bug rather than as physics. One constant, and docs/future/ux.md Q14 records
## that the hybrid is the likely answer once it has been felt.
const TORQUE_PER_PX: float = 2.5

## Direct-look degrees per pixel, used when [member direct_look] is on.
const LOOK_DEG_PER_PX: float = 0.22

## Which held key contributes what. Thrust is body-frame: x strafe, y rise, z forward (-Z).
const THRUST_KEYS: Dictionary = {
	KEY_W: Vector3(0.0, 0.0, -1.0),
	KEY_S: Vector3(0.0, 0.0, 1.0),
	KEY_A: Vector3(-1.0, 0.0, 0.0),
	KEY_D: Vector3(1.0, 0.0, 0.0),
	KEY_SPACE: Vector3(0.0, 1.0, 0.0),
	KEY_Z: Vector3(0.0, -1.0, 0.0),
}

## Torque keys: x pitch, y yaw, z roll. The arrows are the no-mouse and diegetic look verb; Q and E
## roll, which is the one thing the orbit rig could never do.
const TORQUE_KEYS: Dictionary = {
	KEY_UP: Vector3(1.0, 0.0, 0.0),
	KEY_DOWN: Vector3(-1.0, 0.0, 0.0),
	KEY_LEFT: Vector3(0.0, 1.0, 0.0),
	KEY_RIGHT: Vector3(0.0, -1.0, 0.0),
	KEY_Q: Vector3(0.0, 0.0, 1.0),
	KEY_E: Vector3(0.0, 0.0, -1.0),
}

## BASIC's training wheels (docs/future/ux.md Q15): heavier damping and direct look instead of
## torque. The maths underneath is identical.
var direct_look: bool = false

## Set from the tier so BASIC settles faster. See [ShipFlyState.BASIC_LIN_DAMP].
var lin_damp: float = ShipFlyState.LIN_DAMP
var ang_damp: float = ShipFlyState.ANG_DAMP

var _camera: Camera3D = null
var _state: Dictionary = {}
var _held: Dictionary = {}
var _brake: bool = false
var _boost: bool = false
var _precise: bool = false
var _looking: bool = false
var _look_torque: Vector3 = Vector3.ZERO
var _flying: bool = false


func _ready() -> void:
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "FlyCamera3D"
		# Matched to OrbitCamera's so entering fly does not appear to zoom.
		_camera.fov = 55.0
		_camera.near = 0.05
		_camera.far = 6000.0
		_camera.current = false
		add_child(_camera)
	_state = ShipFlyState.make()
	set_physics_process(false)


func get_camera() -> Camera3D:
	return _camera


func is_flying() -> bool:
	return _flying


## Where the rig is, and where it looks - what the torch is fed from.
func position_now() -> Vector3:
	return _state.get(ShipFlyState.POS, Vector3.ZERO)


func forward_now() -> Vector3:
	return ShipFlyState.forward_of(_state)


## Metres per second, for the mode strip.
func speed_now() -> float:
	return ShipFlyState.speed_of(_state)


## Start flying from [param from], which is where the orbit camera's own Camera3D stands right now -
## so the first frame of fly is pixel-identical to the last frame of orbit. Anything else reads as a
## teleport and costs the player their bearings immediately.
func begin(from: Transform3D) -> void:
	_state = ShipFlyState.make(from.origin, from.basis)
	_clear_keys()
	_flying = true
	if _camera != null:
		_camera.current = true
		_camera.transform = Transform3D.IDENTITY
	transform = ShipFlyState.transform_of(_state)
	set_physics_process(true)


## Stop flying. The view puts the orbit camera back; this only stands down.
func end() -> void:
	_flying = false
	_clear_keys()
	set_physics_process(false)
	if _camera != null:
		_camera.current = false


## The pose to hand the orbit rig when leaving with ENTER - keep the view, discard the roll.
## Returns `{"focus": Vector3, "yaw_deg": float, "pitch_deg": float, "distance": float}`.
##
## ROLL IS DISCARDED BECAUSE THE ORBIT RIG CANNOT HOLD IT, and the honest thing is to say so in the
## hint bar rather than to silently snap. [param look_ahead] is how far in front of the camera the
## new focus point is put - the orbit rig orbits a POINT, so leaving fly has to invent one, and the
## point you were flying toward is the only defensible choice.
func keep_view_pose(look_ahead: float) -> Dictionary:
	var fwd: Vector3 = forward_now()
	var focus: Vector3 = position_now() + fwd * look_ahead
	# The rig's yaw/pitch are the angles its own _rig_basis() would need to look along `fwd`.
	var flat: Vector2 = Vector2(fwd.x, fwd.z)
	var yaw: float = 0.0
	if flat.length() > 1e-5:
		yaw = rad_to_deg(atan2(-fwd.x, -fwd.z))
	var pitch: float = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	return {
		"focus": focus,
		"yaw_deg": wrapf(yaw, -180.0, 180.0),
		# The rig's pitch is positive looking DOWN from above; flying up is looking up.
		"pitch_deg": clampf(-pitch, -OrbitCamera.PITCH_LIMIT_DEG, OrbitCamera.PITCH_LIMIT_DEG),
		"distance": look_ahead,
	}


# ---------------------------------------------------------------- input


## One event already localised to the 3D view, exactly as [method OrbitCamera.handle_input] takes
## it. Returns true when it was consumed.
func handle_input(event: InputEvent) -> bool:
	if not _flying:
		return false
	var key: InputEventKey = event as InputEventKey
	if key != null:
		return _handle_key(key)
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		return _handle_button(mb)
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _looking:
		_apply_look(mm.relative)
		return true
	return false


## THE STUCK-KEY GUARD. Called when the pointer leaves the view or focus is lost: a key released
## outside would otherwise leave the rig thrusting forever with nothing on screen explaining why.
func release_drag() -> void:
	_looking = false
	_clear_keys()


## Split in two so each half keeps to gdlint's six-return budget - the same reason
## `ShipView3D._dispatch_press` exists.
func _handle_key(key: InputEventKey) -> bool:
	# Auto-repeat is neither a press nor a release, and for a HELD control it is noise.
	if key.echo:
		return THRUST_KEYS.has(key.keycode) or TORQUE_KEYS.has(key.keycode)
	if key.ctrl_pressed or key.meta_pressed:
		return false
	if key.pressed and _handle_exit_key(key.keycode):
		return true
	return _handle_hold_key(key)


## The keys that are HELD rather than tapped: thrust, torque, brake and the two multipliers. All of
## them read their state from the event, never from `Input.is_key_pressed` - see the class docs.
func _handle_hold_key(key: InputEventKey) -> bool:
	if THRUST_KEYS.has(key.keycode) or TORQUE_KEYS.has(key.keycode):
		if key.pressed:
			_held[key.keycode] = true
		else:
			_held.erase(key.keycode)
		return true
	match key.keycode:
		KEY_X:
			_brake = key.pressed
		KEY_SHIFT:
			_boost = key.pressed
		KEY_ALT:
			_precise = key.pressed
		_:
			return false
	return true


## The three ways out, all printed in the hint bar the whole time flying.
##
## `V` IS THE GUARANTEED NON-ESC EXIT, and it is the same key that entered - `diegetic_host.gd` eats
## ESCAPE to unfocus the device before the builder ever sees it, so in the shipping path ESC may
## never arrive and a mode whose only exit is ESC would be a trap.
func _handle_exit_key(code: int) -> bool:
	match code:
		KEY_V, KEY_ESCAPE:
			exit_requested.emit(true, false)
			return true
		KEY_F:
			exit_requested.emit(false, true)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			exit_requested.emit(false, false)
			return true
	return false


func _handle_button(mb: InputEventMouseButton) -> bool:
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_looking = mb.pressed
		if not mb.pressed:
			_look_torque = Vector3.ZERO
		return true
	return false


## A right-drag either adds TORQUE (the default, conserved-momentum reading) or turns the rig
## DIRECTLY (BASIC). See [constant TORQUE_PER_PX].
func _apply_look(relative: Vector2) -> void:
	if direct_look:
		# Direct look still goes through the state's quaternion, so roll is preserved and the
		# maths stays in one place.
		var yaw: float = -relative.x * LOOK_DEG_PER_PX
		var pitch: float = -relative.y * LOOK_DEG_PER_PX
		var rot: Quaternion = _state.get(ShipFlyState.ROT, Quaternion.IDENTITY)
		rot = (rot * Quaternion(Vector3.RIGHT, deg_to_rad(pitch))).normalized()
		rot = (rot * Quaternion(Vector3.UP, deg_to_rad(yaw))).normalized()
		_state[ShipFlyState.ROT] = rot
		return
	_look_torque += Vector3(-relative.y, -relative.x, 0.0) * TORQUE_PER_PX


func _clear_keys() -> void:
	_held.clear()
	_brake = false
	_boost = false
	_precise = false
	_look_torque = Vector3.ZERO


# ---------------------------------------------------------------- the tick


func _physics_process(delta: float) -> void:
	if not _flying:
		return
	var input: Dictionary = ShipFlyState.no_input()
	var thrust: Vector3 = Vector3.ZERO
	var torque: Vector3 = Vector3.ZERO
	for code: Variant in _held:
		if THRUST_KEYS.has(code):
			thrust += THRUST_KEYS[code]
		if TORQUE_KEYS.has(code):
			torque += TORQUE_KEYS[code]
	# A drag's torque is spent in the frame it arrived: it is an impulse in the input, not a held
	# state, so releasing the button leaves the spin it earned rather than a continuing push.
	torque += _look_torque
	_look_torque = Vector3.ZERO
	input[ShipFlyState.THRUST] = thrust
	input[ShipFlyState.TORQUE] = torque
	input[ShipFlyState.BRAKE] = _brake
	input[ShipFlyState.BOOSTING] = _boost
	input[ShipFlyState.PRECISE] = _precise

	var before: Transform3D = transform
	_state = ShipFlyState.step(_state, input, delta, ShipFlyState.tune(lin_damp, ang_damp))
	transform = ShipFlyState.transform_of(_state)
	# Only report real movement: the torch and the distance cue are both rebuilt on this signal.
	if not before.is_equal_approx(transform):
		fly_moved.emit()
