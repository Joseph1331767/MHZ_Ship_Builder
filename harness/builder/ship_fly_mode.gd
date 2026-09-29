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
const TORCH_ENERGY: float = 4.0

## The beam's half-angle in degrees - the flashlight's FOV. NARROW, deliberately: "flashlight fov
## very narrow, the player should feel like they are in a black void and cant see anything outside
## of their light source" (2026-09-28). A wide cone lights the whole room at once and the void stops
## being a void.
const TORCH_ANGLE_DEG: float = 19.0

## How hard the cone's edge falls off (0 hard, 1 soft) and how the brightness falls with distance.
## 1.0 is Godot's physically-plausible inverse-square; lower spreads the light further.
const TORCH_ANGLE_FALLOFF: float = 1.4
const TORCH_ATTENUATION: float = 2.0

## HOW FAR THE BEAM REACHES, IN METRES, AND IT IS FIXED. A flashlight reaches as far as a flashlight
## reaches; it does not get longer because the ship got bigger.
##
## SCALING IT TO THE SHIP WAS THE BUG, and it is worth writing down because the reasoning sounded
## right. The distance cue is scaled to the scene, so I scaled this the same way - and on a baked
## carbon class, whose scene radius is 32 m, the reach came out at **190 m**. Godot's falloff is
## `pow(1 - d/range, attenuation)`, so at 190 m of range everything within the cone at any
## distance is at essentially full brightness: no falloff, no darkness, "everything is lit, theres
## no flashlight, all of ship is lit". Measured: only 3.6% of the ship's pixels were black.
##
## At 18 m with an attenuation of 2, a wall 2 m away reads at 0.79, at 5 m 0.52, at 10 m 0.20 and at
## 15 m 0.03. That is a torch: bright where you point it, gone a room away.
const TORCH_REACH_M: float = 18.0

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
var _collide: ShipFlyCollide = null
var _explode: Node3D = null
var _solid: bool = false
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
	key: DirectionalLight3D = null,
	explode: Node3D = null,
	collider: ShipFlyCollide = null
) -> void:
	_rig = rig
	_fly = fly
	_scene = scene
	_env = env
	_grid = grid
	_cage = cage
	_com = com
	_key = key
	_explode = explode
	_collide = collider


func is_flying() -> bool:
	return _fly != null and _fly.is_flying()


## Are the hull surfaces solid right now?
func is_solid() -> bool:
	return _solid


## SOLID WALLS ON OR OFF (ADR 0049) - "i need a btn on screen when in fly mode that turns on
## collision both inner and outer" (2026-09-28).
##
## OFF BY DEFAULT, deliberately: the reason to fly is usually to LOOK, and a camera that snags on
## geometry while you are inspecting something is infuriating. Building the colliders is deferred to
## the moment it is switched on for the same reason - nobody pays for a trimesh of the whole ship
## unless they have asked to bump into it.
func set_solid(on: bool) -> void:
	if on == _solid:
		return
	_solid = on
	if _collide == null:
		return
	if on:
		rebuild_solids()
	else:
		_collide.clear()
	if _fly != null:
		_fly.use_collider(_collide if on else null)
	changed.emit()


## Re-derive the colliders from what is currently drawn. Called when collision is switched on, and
## again after a bake, because the pieces they were built from are replaced by then.
func rebuild_solids() -> void:
	if _collide == null or not _solid:
		return
	var roots: Array[Node3D] = []
	if _scene != null:
		roots.append(_scene)
	if _explode != null:
		roots.append(_explode)
	_collide.build(roots)


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
	if _solid:
		rebuild_solids()
		_fly.use_collider(_collide)
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
	# The colliders are only meaningful while something is flying, and a trimesh of the whole ship
	# is not worth keeping around for the orbit view.
	if _collide != null:
		_collide.clear()
		_fly.use_collider(null)
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


## Set the beam's reach. A FIXED distance - see [constant TORCH_REACH_M] for why scaling it to the
## ship was wrong. Kept as a call rather than set once, because the tuning is the thing most likely
## to be revisited and one place to change it is worth a function.
func size_torch() -> void:
	if _torch == null:
		return
	_torch.spot_range = TORCH_REACH_M


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
