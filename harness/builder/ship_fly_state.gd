class_name ShipFlyState
extends RefCounted
## THE FLY INTEGRATOR - conserved linear and angular momentum, lightly damped (ADR 0049).
##
## The author, 2026-09-27:
##
## > "player flys with newtonian physics with some dampening but the feeling of floating in space,
## > counter acting your thrust as linear momentum and angular momentum should be continous and
## > conserves aside from the very slight dampening we add."
##
## PURE STATIC, ON PURPOSE. [method step] takes a state, an input and a dt and returns a new state.
## No node, no clock, no engine call - so "momentum is conserved" and "the damping half-life is
## 2.77 seconds" are propositions gdUnit4 can hold to 1e-5 over ten thousand ticks, rather than
## claims about something only a human can see. `tests/harness/test_fly_state.gd` does exactly that.
##
## DAMPING IS EXPONENTIAL, NOT LINEAR. `v *= exp(-k * dt)` decays by the same FACTOR per unit time
## whatever the frame rate, so the feel is identical at 60 and 144 Hz and the half-life is a stated
## number (`ln 2 / k`). A linear `v -= k * dt` is frame-rate dependent, can cross zero and reverse,
## and has no half-life to quote.
##
## THE QUATERNION IS RENORMALISED EVERY TICK, and that is not hygiene. Godot's `real_t` is 32-bit;
## an un-renormalised quaternion shears the basis visibly within a minute of continuous spin, and
## the failure looks like the whole ship slowly skewing, which is diagnosed as a mesh bug.
##
## INERTIA IS ISOTROPIC, deliberately. A real rigid body with three different moments tumbles - the
## Dzhanibekov effect - which is physically gorgeous on a wrench and is motion sickness on a camera.
## Body-frame angular velocity with equal moments has no precession term, so a flick leaves a clean
## slow drift instead of a wobble.

## Metres per second squared at full thrust. About 1.2 g: a 20 m hull is crossed in ~2 s from rest.
const THRUST_A: float = 12.0

## Linear damping, per second. Half-life `ln 2 / 0.25` = **2.77 s** - the "very slight dampening"
## asked for. It also self-limits the top speed: terminal velocity is `THRUST_A / LIN_DAMP` = 48 m/s
## with no clamp anywhere, which is the honest way to cap a speed.
const LIN_DAMP: float = 0.25

## Degrees per second squared at full torque. A quarter turn from rest in ~1.4 s.
const ANG_A: float = 90.0

## Angular damping, per second. Half-life 1.98 s, so a flick leaves a visible slow drift - that
## drift IS the floating feeling; damp it harder and the camera reads as being on rails.
const ANG_DAMP: float = 0.35

## Degrees per second the spin is capped at. THE ONLY PLACE CONSERVATION IS OVERRIDDEN: past about
## 120 deg/s the 16-colour quantizer strobes and the view is unreadable, so this is a legibility
## limit, not a physical one. Reached only by holding a torque key for several seconds.
const MAX_SPIN: float = 100.0

## Braking. `X` kills both momenta - the single most important key in the mode, because "I cannot
## stop" is how a beginner abandons a flying camera. A full stop from terminal speed takes ~2 s.
const BRAKE_A: float = 24.0
const BRAKE_ANG: float = 240.0

## SHIFT and ALT multipliers on thrust and torque.
const BOOST: float = 3.0
const PRECISION: float = 0.3

## Damping either side of the tier gate for BASIC (docs/future/ux.md Q15): the same class with the
## training wheels on, so the youngest rung still flies. A 0.87 s linear half-life and a 0.28 s
## angular one mean the camera very nearly stops when you let go, which is what a child expects
## from a flying control, while the model underneath is still Newtonian.
const BASIC_LIN_DAMP: float = 0.80
const BASIC_ANG_DAMP: float = 2.50

## State keys. `pos` and `vel` are WORLD; `spin` is the body frame, in degrees per second.
const POS: String = "pos"
const VEL: String = "vel"
const ROT: String = "rot"
const SPIN: String = "spin"

## Input keys. `thrust` and `torque` are each clamped to -1..1 per axis.
##
## `thrust`: x strafe (+right), y rise (+up), z forward (+forward, i.e. toward -Z in Godot).
## `torque`: x pitch, y yaw, z roll, in the body frame.
const THRUST: String = "thrust"
const TORQUE: String = "torque"
const BRAKE: String = "brake"
const BOOSTING: String = "boosting"
const PRECISE: String = "precise"

## Tuning keys, so a tier can hand [method step] different damping without a second class.
const TUNE_LIN_DAMP: String = "lin_damp"
const TUNE_ANG_DAMP: String = "ang_damp"


## A state at rest at [param pos], looking along [param basis].
static func make(pos: Vector3 = Vector3.ZERO, basis: Basis = Basis.IDENTITY) -> Dictionary:
	return {
		POS: pos,
		VEL: Vector3.ZERO,
		ROT: basis.get_rotation_quaternion().normalized(),
		SPIN: Vector3.ZERO,
	}


## Nothing held.
static func no_input() -> Dictionary:
	return {
		THRUST: Vector3.ZERO,
		TORQUE: Vector3.ZERO,
		BRAKE: false,
		BOOSTING: false,
		PRECISE: false,
	}


## Default tuning - the constants above.
static func tune(lin_damp: float = LIN_DAMP, ang_damp: float = ANG_DAMP) -> Dictionary:
	return {TUNE_LIN_DAMP: lin_damp, TUNE_ANG_DAMP: ang_damp}


## ONE TICK. Semi-implicit Euler: accelerate, damp, then integrate position from the NEW velocity,
## which is stable at the step sizes a 60 Hz physics tick produces and does not gain energy the way
## explicit Euler does.
##
## Returns a NEW state dictionary - [param state] is never mutated (AGENTS section 2).
##
## ORDER IS LOAD-BEARING: thrust, damp, brake, move. Braking AFTER damping means `X` always wins
## and can never be fought by the damping term; braking before it would leave a residue that decays
## instead of stopping, and "X did not quite stop me" is worse than no brake at all.
static func step(state: Dictionary, input: Dictionary, dt: float, tuning: Dictionary) -> Dictionary:
	if dt <= 0.0:
		return state.duplicate()
	var lin_damp: float = float(tuning.get(TUNE_LIN_DAMP, LIN_DAMP))
	var ang_damp: float = float(tuning.get(TUNE_ANG_DAMP, ANG_DAMP))
	var rot: Quaternion = state.get(ROT, Quaternion.IDENTITY)
	var scale: float = _scale(input)

	# ---- linear. Thrust is a BODY direction, so the same key always means "forward".
	var thrust: Vector3 = _clamped(input.get(THRUST, Vector3.ZERO))
	var vel: Vector3 = state.get(VEL, Vector3.ZERO)
	vel += (rot * thrust) * (THRUST_A * scale * dt)
	# Exponential decay: the factor per second is exp(-k), so the half-life is ln2/k exactly.
	vel *= exp(-lin_damp * dt)
	if bool(input.get(BRAKE, false)):
		vel = _toward_zero(vel, BRAKE_A * dt)
	var pos: Vector3 = state.get(POS, Vector3.ZERO) + vel * dt

	# ---- angular, in the body frame with an isotropic inertia tensor (see the class docs).
	var torque: Vector3 = _clamped(input.get(TORQUE, Vector3.ZERO))
	var spin: Vector3 = state.get(SPIN, Vector3.ZERO)
	spin += torque * (ANG_A * scale * dt)
	spin *= exp(-ang_damp * dt)
	if bool(input.get(BRAKE, false)):
		spin = _toward_zero(spin, BRAKE_ANG * dt)
	if spin.length() > MAX_SPIN:
		spin = spin.normalized() * MAX_SPIN

	# The body-frame rate composes on the RIGHT of the current orientation, which is what makes
	# "pitch up" mean up relative to the player rather than to the world.
	var rate: float = spin.length()
	if rate > 1e-9:
		var axis: Vector3 = spin / rate
		rot = (rot * Quaternion(axis, deg_to_rad(rate) * dt)).normalized()

	return {POS: pos, VEL: vel, ROT: rot, SPIN: spin}


## Metres per second, for the mode strip.
static func speed_of(state: Dictionary) -> float:
	return (state.get(VEL, Vector3.ZERO) as Vector3).length()


## The transform a camera should wear for [param state].
static func transform_of(state: Dictionary) -> Transform3D:
	var rot: Quaternion = state.get(ROT, Quaternion.IDENTITY)
	return Transform3D(Basis(rot.normalized()), state.get(POS, Vector3.ZERO))


## The state's own forward direction - where the torch points.
static func forward_of(state: Dictionary) -> Vector3:
	var rot: Quaternion = state.get(ROT, Quaternion.IDENTITY)
	# Godot cameras look down local -Z.
	return (Basis(rot.normalized()) * Vector3.FORWARD).normalized()


## True once the state has essentially stopped, so a caller can skip work. Both thresholds are
## below what a single frame at 60 Hz can move on screen.
static func at_rest(state: Dictionary) -> bool:
	return speed_of(state) < 0.001 and (state.get(SPIN, Vector3.ZERO) as Vector3).length() < 0.01


static func _scale(input: Dictionary) -> float:
	if bool(input.get(BOOSTING, false)):
		return BOOST
	if bool(input.get(PRECISE, false)):
		return PRECISION
	return 1.0


static func _clamped(v: Variant) -> Vector3:
	var out: Vector3 = v
	return Vector3(clampf(out.x, -1.0, 1.0), clampf(out.y, -1.0, 1.0), clampf(out.z, -1.0, 1.0))


## Shrink toward zero by [param amount], stopping AT zero rather than crossing it. A brake that
## overshoots reverses, which reads as being thrown backwards.
static func _toward_zero(v: Vector3, amount: float) -> Vector3:
	var len: float = v.length()
	if len <= amount or len <= 0.0:
		return Vector3.ZERO
	return v * ((len - amount) / len)
