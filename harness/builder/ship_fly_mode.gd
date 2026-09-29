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

## THE FLASHLIGHT IS A REAL [SpotLight3D] (ADR 0049, revised 2026-09-28) - real cone, real inverse
## -square falloff, real shadows, parented to the camera so it points where you look.
##
## RETUNED 2026-09-28 after the author flew it: "makes viewing inside of the ship near impossible
## like a flashlight in a mirror". That was not the void being wrong - the void is exactly what was
## asked for, twice - it was the BEAM being wrong. At energy 6 with a 34-degree cone, a surface an
## arm's length away saturates, and a saturated surface has no gradient left to read, so a room
## you fly into turns into one flat white shape. Dimmer and much narrower reads as a torch.
##
## IT WAS FAKED FIRST, AND THAT WAS A MISTAKE BUILT ON AN UNCLOSED BUG. FOLLOWUPS F7 recorded
## "shaded materials render black in this SubViewport" as OPEN, ROOT CAUSE UNKNOWN, and I treated
## it as a property of the engine. The author pushed back - "godot cant render real light sources,
## shadows, pbr material effects etc.. why do we have to fake lighting" - and a direct measurement
## settled it in one run: a shaded box in this very viewport reads luma 0.836 under the existing
## directional light, 0.922 with an OmniLight3D and 0.928 with a SpotLight3D. F7 was a dark albedo
## quantizing onto the background, not a lighting failure - see FOLLOWUPS F7, now RESOLVED.
const TORCH_ENERGY: float = 3.4

## The beam's half-angle in degrees - the flashlight's FOV. NARROW, deliberately: "flashlight fov
## very narrow, the player should feel like they are in a black void and cant see anything outside
## of their light source" (2026-09-28). A wide cone lights the whole room at once and the void stops
## being a void.
const TORCH_ANGLE_DEG: float = 19.0

## How hard the cone's edge falls off (0 hard, 1 soft) and how the brightness falls with distance.
## 1.0 is Godot's physically-plausible inverse-square; lower spreads the light further.
const TORCH_ANGLE_FALLOFF: float = 0.55
const TORCH_ATTENUATION: float = 1.2

## The beam reaches this many scene radii. GENEROUS, and it has to be: Godot's spot attenuation is
## `pow(1 - d/range, attenuation)`, which is essentially ZERO at the range itself. The first tuning
## set the range to the scene radius and the camera enters fly at about that distance, so the beam
## arrived at roughly 1% strength and the mode looked like the torch was not on at all. The CONE is
## what makes the void a void; the range only has to be far enough not to be the thing that stops
## the light.
const TORCH_REACH_RADII: float = 6.0
const TORCH_REACH_MIN_M: float = 50.0

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
var _torch: SpotLight3D = null
var _key: DirectionalLight3D = null
var _return: Dictionary = {}
var _prev_mode: int = -1
var _key_was: float = 0.0


func _init(
	rig: OrbitCamera,
	fly: ShipFlyCamera,
	scene: ShipSceneBuilder,
	env: WorldEnvironment,
	grid: MeshInstance3D,
	cage: MeshInstance3D,
	com: MeshInstance3D,
	key: DirectionalLight3D = null
) -> void:
	_rig = rig
	_fly = fly
	_scene = scene
	_env = env
	_grid = grid
	_cage = cage
	_com = com
	_key = key


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


## Size the beam to the ship. Called on entry and whenever the scene bounds could have changed -
## NOT every tick, because the light is parented to the camera and follows it by itself. That is the
## point of using a real light: there is no per-frame bookkeeping to get wrong.
##
## THE REACH IS SCALED TO THE SHIP for the same reason the distance cue is: a 6 m pod and a 300 m
## hull cannot share one number, and a beam that cannot reach your own ship is not a flashlight.
func size_torch() -> void:
	if _torch == null or _scene == null:
		return
	var radius: float = maxf(_scene.scene_aabb().size.length() * 0.5, MIN_RADIUS)
	_torch.spot_range = maxf(radius * TORCH_REACH_RADII, TORCH_REACH_MIN_M)


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
		_scene.flying = on
	_light_void(on)


## THE FLASHLIGHT, and the darkness that makes it worth having.
##
## Entering: the scene's key light goes OUT and ambient goes to zero, so the ONLY thing lighting the
## ship is the [SpotLight3D] parented to the fly camera. That is what "pitch black aside whats in
## players flashlight" means, and with real lights it is literally true rather than approximated.
##
## SHADOWS ARE ON. A flashlight that does not cast a shadow inside a hull reads as a glow; one that
## does is how you tell a doorway from a wall. It costs one shadow map.
func _light_void(on: bool) -> void:
	if not on:
		if _torch != null:
			_torch.visible = false
		if _key != null:
			_key.light_energy = _key_was
		return
	if _key != null:
		_key_was = _key.light_energy
		# OUT, not dimmed. A fixed world sun is exactly what stops a void being a void.
		_key.light_energy = 0.0
	if _torch == null:
		_torch = SpotLight3D.new()
		_torch.name = "Flashlight"
		_torch.spot_angle = TORCH_ANGLE_DEG
		_torch.spot_angle_attenuation = TORCH_ANGLE_FALLOFF
		_torch.spot_attenuation = TORCH_ATTENUATION
		_torch.light_energy = TORCH_ENERGY
		_torch.shadow_enabled = true
		# A spot light points down its own -Z, which is also where the camera looks, so parenting it
		# to the camera is the whole of "the flashlight is attached to the camera".
		var cam: Camera3D = _fly.get_camera()
		if cam != null:
			cam.add_child(_torch)
	_torch.visible = true
	size_torch()
