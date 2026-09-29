class_name ShipFlyMode
extends RefCounted
## ENTERING AND LEAVING FLY - the void, the torch, and the guaranteed way back (ADR 0049).
##
## [ShipFlyCamera] is the rig and [ShipFlyState] is the maths; this is the MODE - everything that
## has to change about the rest of the scene when the player stops orbiting a model and starts
## flying around inside one. That is a different question from "how does the camera move", which is
## why it is a different class.
##
## IT OWNS NO NODES AND REACHES BACK INTO NOTHING. Every node it drives is handed to it once, in
## [method _init] - the environment, the grid, the cage, the mass cross, the scene builder, the two
## camera rigs. So it can be constructed and driven in a test with stand-ins, and `ship_view3d.gd`
## keeps one reference and a `_gui_input` branch rather than a hundred and fifty lines of mode
## bookkeeping. (`.gdlintrc`: "A good extraction is a self-contained, statically testable unit with
## no reference back to the file it came from." This is that, and the file-length alarm that
## prompted it was right.)
##
## THE WAY OUT IS ARRANGED BEFORE THE WAY IN. `_return` is stashed in [method enter] before
## anything moves, so `V` and `ESC` can put the orbit camera back EXACTLY as it was. The number one
## way a beginner abandons a 3D editor is flying somewhere they cannot get back from.

## Emitted after entering or leaving, so the view can refresh hints and the builder its toolbar.
signal changed

## How bright the torch is. Strong enough that a face square-on to the beam reaches the ramp's top
## band; the falloff, not this, is what makes distance read.
const TORCH_STRENGTH: float = 1.35

## The beam is half strength at this many scene radii, so it reaches across the ship you are flying
## around whatever size that ship is. Measured at a fixed 14 m: entering fly on a 12 m ship from
## the orbit camera's standoff put the beam at 8% and the mode looked like the lights had simply
## gone out.
const TORCH_REACH_RADII: float = 1.5
const TORCH_REACH_MIN_M: float = 10.0

## Where ENTER-to-keep-the-view puts the orbit rig's new focus point. The rig orbits a POINT, so
## leaving fly has to invent one, and the point you were flying toward is the only defensible pick.
const LOOK_AHEAD_M: float = 12.0

## Below this the depth cue's span collapses and the shader divides by nearly nothing.
const MIN_RADIUS: float = 1.5

var _rig: OrbitCamera = null
var _fly: ShipFlyCamera = null
var _scene: ShipSceneBuilder = null
var _env: WorldEnvironment = null
var _grid: MeshInstance3D = null
var _cage: MeshInstance3D = null
var _com: MeshInstance3D = null
var _return: Dictionary = {}
var _prev_mode: int = -1


func _init(
	rig: OrbitCamera,
	fly: ShipFlyCamera,
	scene: ShipSceneBuilder,
	env: WorldEnvironment,
	grid: MeshInstance3D,
	cage: MeshInstance3D,
	com: MeshInstance3D
) -> void:
	_rig = rig
	_fly = fly
	_scene = scene
	_env = env
	_grid = grid
	_cage = cage
	_com = com


func is_flying() -> bool:
	return _fly != null and _fly.is_flying()


## Metres per second, for the mode strip.
func speed() -> float:
	return _fly.speed_now() if is_flying() else 0.0


## Enter FLY, unless [param refuse] says something else owns the view - a live placement or a
## handle drag. Returns false when refused, so the caller can say why rather than doing nothing.
##
## [param basic] is the youngest rung's training wheels: heavier damping and direct look instead of
## torque (docs/future/ux.md Q15).
##
## THE VOID IS THE POINT. The author: "a themed blue clay with wire edges rendering mode with a
## completely dark environment like deep void of space, where a flashlight is attached to camera".
## So entering also forces CLAY, drops the ambient floor so the torch is the only light there is,
## and takes away the grid, the cage and the mass cross - none of which is scenery you want to meet
## while flying inside a hull.
func enter(basic: bool, refuse: bool) -> bool:
	if _fly == null or _rig == null or refuse:
		return false
	if _fly.is_flying():
		return true
	_return = {
		"focus": _rig.focus,
		"distance": _rig.distance,
		"yaw_deg": _rig.yaw_deg,
		"pitch_deg": _rig.pitch_deg,
	}
	_fly.direct_look = basic
	_fly.lin_damp = ShipFlyState.BASIC_LIN_DAMP if basic else ShipFlyState.LIN_DAMP
	_fly.ang_damp = ShipFlyState.BASIC_ANG_DAMP if basic else ShipFlyState.ANG_DAMP
	_prev_mode = _scene.get_display_mode() if _scene != null else -1
	if _scene != null:
		_scene.set_display_mode(ShipSceneBuilder.DisplayMode.CLAY)
	# Start exactly where the orbit camera stands, so the first frame of fly is the last frame of
	# orbit. Anything else is a teleport and costs the player their bearings immediately.
	var cam: Camera3D = _rig.get_camera()
	_fly.begin(cam.global_transform if cam != null else Transform3D.IDENTITY)
	# AFTER begin(), so is_flying() is true and the torch is actually lit. Lighting it before would
	# push strength 0 and leave the void pitch black until the first frame the rig happened to
	# move, which on a still stick is never.
	_set_void(true)
	changed.emit()
	return true


## Leave FLY. [param restore] puts the orbit camera back exactly as it was (`V` / `ESC`).
## [param frame] frames the whole ship instead (`F`). Neither means KEEP THE VIEW (`ENTER`), which
## hands the rig a focus point on the ray ahead and discards the roll.
func leave(restore: bool = true, frame: bool = false) -> void:
	if _fly == null or not _fly.is_flying():
		return
	var pose: Dictionary = _fly.keep_view_pose(LOOK_AHEAD_M)
	_fly.end()
	_set_void(false)
	if _scene != null and _prev_mode >= 0:
		_scene.set_display_mode(_prev_mode)
	_prev_mode = -1
	var cam: Camera3D = _rig.get_camera()
	if cam != null:
		cam.current = true
	if restore and not _return.is_empty():
		_rig.distance = float(_return["distance"])
		_rig.yaw_deg = float(_return["yaw_deg"])
		_rig.pitch_deg = float(_return["pitch_deg"])
		_rig.set_focus(_return["focus"])
	elif not frame:
		# KEEP THE VIEW, ROLL DISCARDED - the orbit rig has no roll and must not learn one.
		_rig.yaw_deg = float(pose["yaw_deg"])
		_rig.pitch_deg = float(pose["pitch_deg"])
		_rig.distance = float(pose["distance"])
		_rig.set_focus(pose["focus"])
	_return = {}
	changed.emit()


## The render type this mode took away, so the caller can put its own toolbar back. -1 when nothing
## was taken.
func previous_mode() -> int:
	return _prev_mode


## Push the torch's position, aim and reach at the part shader. Called every tick the rig moves,
## exactly as the distance cue is - and pushes strength 0 the moment fly ends, which turns the
## shader term off entirely.
func push_torch() -> void:
	if _scene == null:
		return
	if not is_flying():
		_scene.torch = {"pos": Vector3.ZERO, "dir": Vector3.FORWARD, "strength": 0.0, "reach": 1.0}
		return
	# THE REACH IS SCALED TO THE SHIP, exactly as the distance cue is, and for the same reason a
	# fixed range fails there: a 6 m pod and a 300 m hull cannot share one number.
	var box: AABB = _scene.scene_aabb()
	var radius: float = maxf(box.size.length() * 0.5, MIN_RADIUS)
	_scene.torch = {
		"pos": _fly.position_now(),
		"dir": _fly.forward_now(),
		"strength": TORCH_STRENGTH,
		"reach": maxf(radius * TORCH_REACH_RADII, TORCH_REACH_MIN_M),
	}


## How far the fly rig is from the model's centre - what the part shader's distance cue is derived
## from while flying. Left on the orbit rig's `distance` it would freeze at whatever it was when
## fly started, and a frozen distance cue looks exactly like a shading bug rather than a camera one.
func distance_to_scene() -> float:
	if _scene == null or not is_flying():
		return 0.0
	return maxf(_fly.position_now().distance_to(_scene.scene_aabb().get_center()), 0.05)


## THE DEEP VOID. Background to the clay palette's own darkest entry so the quantizer is a no-op on
## it, the ambient floor dropped so the torch is the only light, and every piece of orientation
## scenery taken away.
##
## NO STARFIELD: at sixteen colours a star field quantizes to single-pixel noise indistinguishable
## from the dither, which is why the void is plain.
func _set_void(on: bool) -> void:
	if _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = 0.0 if on else 0.75
	if _grid != null:
		_grid.visible = not on
	if on:
		if _cage != null:
			_cage.visible = false
		if _com != null:
			_com.visible = false
	if _scene != null:
		# One flag: the gizmo goes away, the clay ambient drops and the fixed world sun stands
		# down, all from the same fact.
		_scene.flying = on
	push_torch()
