extends GdUnitTestSuite
## ShipFlyState - the claims the class docs make, held to numbers (ADR 0049).
##
## The whole reason the integrator is pure static: "momentum is conserved" and "the half-life is
## 2.77 seconds" are checkable here, over ten thousand ticks, with no scene and no human looking.

const DT: float = 1.0 / 60.0


func _tune(lin: float, ang: float) -> Dictionary:
	return ShipFlyState.tune(lin, ang)


## ZERO DAMPING CONSERVES LINEAR MOMENTUM EXACTLY. The author asked for momentum that "should be
## continous and conserves aside from the very slight dampening we add" - so with the damping taken
## out, drift over ten thousand ticks is the measure of whether the integrator is honest.
func test_linear_momentum_conserved_without_damping() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.VEL] = Vector3(3.0, -1.0, 2.0)
	var speed0: float = ShipFlyState.speed_of(state)
	var tuning: Dictionary = _tune(0.0, 0.0)
	var idle: Dictionary = ShipFlyState.no_input()
	for _i: int in 10000:
		state = ShipFlyState.step(state, idle, DT, tuning)
	assert_float(ShipFlyState.speed_of(state)).is_equal_approx(speed0, 1e-5)
	# And it went somewhere: 10000 ticks at 60 Hz is 166.7 s.
	assert_float((state[ShipFlyState.POS] as Vector3).length()).is_greater(100.0)


## ZERO DAMPING CONSERVES ANGULAR MOMENTUM EXACTLY, which is the half of the ask that a naive
## implementation silently loses - every renormalise of the quaternion is a chance to bleed rate.
func test_angular_momentum_conserved_without_damping() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.SPIN] = Vector3(12.0, -20.0, 5.0)
	var rate0: float = (state[ShipFlyState.SPIN] as Vector3).length()
	var tuning: Dictionary = _tune(0.0, 0.0)
	var idle: Dictionary = ShipFlyState.no_input()
	for _i: int in 10000:
		state = ShipFlyState.step(state, idle, DT, tuning)
	assert_float((state[ShipFlyState.SPIN] as Vector3).length()).is_equal_approx(rate0, 1e-5)


## THE QUATERNION STAYS UNIT after a minute of continuous spin. Godot's real_t is 32-bit; without
## the per-tick renormalise this shears the basis and the symptom looks like a mesh bug.
func test_quaternion_stays_normalised_under_long_spin() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.SPIN] = Vector3(0.0, 90.0, 0.0)
	var tuning: Dictionary = _tune(0.0, 0.0)
	var idle: Dictionary = ShipFlyState.no_input()
	for _i: int in 3600:  # 60 s at 60 Hz
		state = ShipFlyState.step(state, idle, DT, tuning)
	var q: Quaternion = state[ShipFlyState.ROT]
	assert_float(q.length()).is_equal_approx(1.0, 1e-6)


## THE DAMPING HALF-LIFE IS THE STATED NUMBER. ln2 / 0.25 = 2.7726 s, and exponential decay is the
## only form that HAS a half-life - this is the test that stops someone "simplifying" it to a
## linear subtraction, which would pass a smoke test and change the feel at every frame rate.
func test_damping_half_life_is_exact() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.VEL] = Vector3(0.0, 0.0, 10.0)
	var tuning: Dictionary = _tune(ShipFlyState.LIN_DAMP, ShipFlyState.ANG_DAMP)
	var idle: Dictionary = ShipFlyState.no_input()
	var half_life: float = log(2.0) / ShipFlyState.LIN_DAMP
	var ticks: int = int(round(half_life / DT))
	for _i: int in ticks:
		state = ShipFlyState.step(state, idle, DT, tuning)
	# Within a tick's worth of decay of exactly half.
	assert_float(ShipFlyState.speed_of(state)).is_equal_approx(5.0, 0.02)


## FRAME-RATE INDEPENDENCE, which is what exponential damping buys and linear damping does not.
## The same elapsed time at 60 Hz and at 240 Hz must leave the same speed.
func test_damping_is_frame_rate_independent() -> void:
	var tuning: Dictionary = _tune(ShipFlyState.LIN_DAMP, ShipFlyState.ANG_DAMP)
	var idle: Dictionary = ShipFlyState.no_input()
	var coarse: Dictionary = ShipFlyState.make()
	coarse[ShipFlyState.VEL] = Vector3(0.0, 0.0, 10.0)
	for _i: int in 60:
		coarse = ShipFlyState.step(coarse, idle, 1.0 / 60.0, tuning)
	var fine: Dictionary = ShipFlyState.make()
	fine[ShipFlyState.VEL] = Vector3(0.0, 0.0, 10.0)
	for _i: int in 240:
		fine = ShipFlyState.step(fine, idle, 1.0 / 240.0, tuning)
	assert_float(ShipFlyState.speed_of(coarse)).is_equal_approx(ShipFlyState.speed_of(fine), 1e-4)


## THE BRAKE STOPS AT ZERO AND NEVER CROSSES IT. An overshooting brake reverses, which reads as
## being thrown backwards - and `X` is the key that has to be trustworthy.
func test_brake_never_overshoots() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.VEL] = Vector3(0.05, 0.0, 0.0)
	state[ShipFlyState.SPIN] = Vector3(0.3, 0.0, 0.0)
	var braking: Dictionary = ShipFlyState.no_input()
	braking[ShipFlyState.BRAKE] = true
	var tuning: Dictionary = _tune(0.0, 0.0)
	# One tick of brake is far more than 0.05 m/s of authority, so it must land exactly on zero.
	state = ShipFlyState.step(state, braking, DT, tuning)
	assert_vector(state[ShipFlyState.VEL] as Vector3).is_equal(Vector3.ZERO)
	assert_vector(state[ShipFlyState.SPIN] as Vector3).is_equal(Vector3.ZERO)
	assert_bool(ShipFlyState.at_rest(state)).is_true()


## THE BRAKE BEATS THE DAMPING, because it is applied after it. A brake that could be fought by
## another term is the failure this ordering exists to prevent.
func test_brake_stops_from_terminal_speed() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.VEL] = Vector3(0.0, 0.0, 48.0)
	var braking: Dictionary = ShipFlyState.no_input()
	braking[ShipFlyState.BRAKE] = true
	var tuning: Dictionary = _tune(ShipFlyState.LIN_DAMP, ShipFlyState.ANG_DAMP)
	var ticks: int = 0
	while not ShipFlyState.at_rest(state) and ticks < 600:
		state = ShipFlyState.step(state, braking, DT, tuning)
		ticks += 1
	assert_bool(ShipFlyState.at_rest(state)).is_true()
	# ~2 s from terminal, so comfortably inside 3.
	assert_int(ticks).is_less(180)


## THRUST IS A BODY DIRECTION: the same key means "forward" whichever way you are facing. Yawed a
## quarter turn, forward thrust must move along world -X, not world -Z.
func test_thrust_follows_the_body() -> void:
	var yawed: Basis = Basis(Vector3.UP, deg_to_rad(90.0))
	var state: Dictionary = ShipFlyState.make(Vector3.ZERO, yawed)
	var input: Dictionary = ShipFlyState.no_input()
	input[ShipFlyState.THRUST] = Vector3(0.0, 0.0, -1.0)  # forward, Godot -Z
	var tuning: Dictionary = _tune(0.0, 0.0)
	for _i: int in 60:
		state = ShipFlyState.step(state, input, DT, tuning)
	var moved: Vector3 = state[ShipFlyState.POS]
	# A +90 deg yaw sends local -Z to world -X.
	assert_float(moved.x).is_less(-1.0)
	assert_float(absf(moved.z)).is_less(0.01)


## THE SPIN CAP IS THE ONE PLACE CONSERVATION IS OVERRIDDEN, and it is a legibility limit: past it
## the 16-colour quantizer strobes. Holding torque forever must not exceed it.
func test_spin_is_capped() -> void:
	var state: Dictionary = ShipFlyState.make()
	var input: Dictionary = ShipFlyState.no_input()
	input[ShipFlyState.TORQUE] = Vector3(0.0, 1.0, 0.0)
	input[ShipFlyState.BOOSTING] = true
	var tuning: Dictionary = _tune(0.0, 0.0)
	for _i: int in 1200:
		state = ShipFlyState.step(state, input, DT, tuning)
	assert_float((state[ShipFlyState.SPIN] as Vector3).length()).is_less_equal(
		ShipFlyState.MAX_SPIN + 1e-4
	)


## TERMINAL SPEED IS SET BY THE DAMPING, NOT BY A CLAMP - there is no speed limit in the code to go
## looking for, only `THRUST_A / LIN_DAMP`.
##
## AND IT SETTLES A HAIR BELOW THE TEXTBOOK 48 m/s, which is worth pinning rather than papering
## over: a DISCRETE integrator has a discrete fixed point. From `v -> (v + a*dt) * exp(-k*dt)`,
## solving `v* = (v* + a*dt)*d` gives `v* = a*dt*d / (1 - d)`, which is 47.8995 at 60 Hz - about
## 0.2% under the continuous limit, exactly the `1 - k*dt/2` first-order offset semi-implicit Euler
## is known for. Measured first, then derived: the first version of this test asserted 48.0 +/- 0.1
## and read 47.8995, and the formula accounts for the gap to five figures. Asserting the CONTINUOUS
## value with a loose tolerance would have hidden a real integrator change behind slack.
func test_terminal_speed_is_thrust_over_damping() -> void:
	var state: Dictionary = ShipFlyState.make()
	var input: Dictionary = ShipFlyState.no_input()
	input[ShipFlyState.THRUST] = Vector3(0.0, 0.0, -1.0)
	var tuning: Dictionary = _tune(ShipFlyState.LIN_DAMP, ShipFlyState.ANG_DAMP)
	for _i: int in 3600:
		state = ShipFlyState.step(state, input, DT, tuning)
	var continuous: float = ShipFlyState.THRUST_A / ShipFlyState.LIN_DAMP
	var decay: float = exp(-ShipFlyState.LIN_DAMP * DT)
	var discrete: float = ShipFlyState.THRUST_A * DT * decay / (1.0 - decay)
	assert_float(ShipFlyState.speed_of(state)).is_equal_approx(discrete, 1e-3)
	# And the discrete fixed point really is just under the continuous one, by well under a percent.
	assert_float(discrete).is_less(continuous)
	assert_float(continuous - discrete).is_less(continuous * 0.01)


## STEP NEVER MUTATES ITS ARGUMENT (AGENTS section 2).
func test_step_does_not_mutate_the_state_given() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.VEL] = Vector3(1.0, 2.0, 3.0)
	var input: Dictionary = ShipFlyState.no_input()
	input[ShipFlyState.THRUST] = Vector3(1.0, 1.0, 1.0)
	var before: Vector3 = state[ShipFlyState.VEL]
	ShipFlyState.step(state, input, DT, ShipFlyState.tune())
	assert_vector(state[ShipFlyState.VEL] as Vector3).is_equal(before)


## A ZERO OR NEGATIVE dt IS A NO-OP, not a divide or a NaN. A paused frame or a clock that goes
## backwards must not corrupt the state.
func test_zero_dt_is_a_no_op() -> void:
	var state: Dictionary = ShipFlyState.make()
	state[ShipFlyState.VEL] = Vector3(1.0, 0.0, 0.0)
	var out: Dictionary = ShipFlyState.step(
		state, ShipFlyState.no_input(), 0.0, ShipFlyState.tune()
	)
	assert_vector(out[ShipFlyState.VEL] as Vector3).is_equal(Vector3(1.0, 0.0, 0.0))
	assert_vector(out[ShipFlyState.POS] as Vector3).is_equal(Vector3.ZERO)


## BASIC's damping is heavier but still exponential, so the youngest rung flies the same maths with
## the training wheels on (docs/future/ux.md Q15).
func test_basic_damping_settles_faster_but_still_moves() -> void:
	var idle: Dictionary = ShipFlyState.no_input()
	var basic: Dictionary = ShipFlyState.make()
	basic[ShipFlyState.VEL] = Vector3(0.0, 0.0, 10.0)
	var normal: Dictionary = basic.duplicate()
	var basic_tune: Dictionary = _tune(ShipFlyState.BASIC_LIN_DAMP, ShipFlyState.BASIC_ANG_DAMP)
	var normal_tune: Dictionary = _tune(ShipFlyState.LIN_DAMP, ShipFlyState.ANG_DAMP)
	for _i: int in 60:
		basic = ShipFlyState.step(basic, idle, DT, basic_tune)
		normal = ShipFlyState.step(normal, idle, DT, normal_tune)
	assert_float(ShipFlyState.speed_of(basic)).is_less(ShipFlyState.speed_of(normal))
	# Still drifting, not nailed down - it is a fly mode, not a dolly.
	assert_float(ShipFlyState.speed_of(basic)).is_greater(0.1)


## The torch points where the camera looks, which is what makes it a flashlight and not a lamp.
func test_forward_follows_the_orientation() -> void:
	var yawed: Basis = Basis(Vector3.UP, deg_to_rad(90.0))
	var state: Dictionary = ShipFlyState.make(Vector3.ZERO, yawed)
	var fwd: Vector3 = ShipFlyState.forward_of(state)
	assert_float(fwd.x).is_equal_approx(-1.0, 1e-4)
	assert_float(absf(fwd.z)).is_less(1e-4)
