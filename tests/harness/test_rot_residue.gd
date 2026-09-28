# A ROTATION DRAG MUST NOT THROW ITS REMAINDER AWAY.
#
# The handler turns pixels into degrees and the placement quantizes the RESULT, so the difference
# has to be carried to the next event. At the old 0.5 degree default every pixel produced a whole
# step and the loss was invisible; at the 5 degrees the author asked for, a slow drag rounds to
# zero every event and the part does not move at all - "placement does not snap visually" is the
# same coarse-lattice problem seen from the other side.
#
# Driven against the accumulator directly, because the alternative needs a builder, a GPU slot and
# a camera to turn a pixel into a ray.
class_name TestRotResidue
extends GdUnitTestSuite


## The accumulator, spelt exactly as `ShipView3D._earned_degrees` spells it.
func _spend(raw: float, step: float, residue: Array) -> float:
	if step <= 0.0:
		return raw
	residue[0] = float(residue[0]) + raw
	var whole: float = float(int(float(residue[0]) / step)) * step
	residue[0] = float(residue[0]) - whole
	return whole


## 400 px at 1 px an event, at a 5 degree snap, is 80 clicks of 5 degrees - not nothing.
func test_a_slow_drag_still_turns_the_part() -> void:
	var residue: Array = [0.0]
	var per_px: float = ShipPlacement.ROT_DEG_PER_PIXEL
	var total: float = 0.0
	var steps: int = 0
	for _i: int in 400:
		var spent: float = _spend(per_px, 5.0, residue)
		if not is_zero_approx(spent):
			steps += 1
			total += spent
	(
		assert_float(total)
		. append_failure_message("a 400 px drag lost its remainder and turned %s degrees" % total)
		. is_equal_approx(400.0 * per_px, 5.0)
	)
	(
		assert_int(steps)
		. append_failure_message("it must move in visible clicks, not continuously")
		. is_less(400)
	)


## Every emitted amount is a whole number of steps, so the value stays on the lattice.
func test_every_spend_is_a_whole_step() -> void:
	var residue: Array = [0.0]
	for i: int in 200:
		var spent: float = _spend(0.7 + float(i) * 0.013, 5.0, residue)
		assert_float(fmod(absf(spent), 5.0)).is_equal_approx(0.0, 0.0001)


## AND IT WORKS BOTH WAYS. int() truncates toward zero, so a leftward drag spends negative steps and
## never rounds a small backward motion into a forward one.
func test_it_carries_in_both_directions() -> void:
	var residue: Array = [0.0]
	var total: float = 0.0
	for _i: int in 100:
		total += _spend(-1.0, 5.0, residue)
	assert_float(total).is_equal_approx(-100.0, 5.0)
	(
		assert_float(total)
		. append_failure_message("a backward drag must not move the part forward")
		. is_less(0.0)
	)


## With the snap off nothing is withheld - the drag is continuous, exactly as it was.
func test_the_snap_off_spends_everything() -> void:
	var residue: Array = [0.0]
	assert_float(_spend(0.31, 0.0, residue)).is_equal_approx(0.31, 0.0001)
	assert_float(float(residue[0])).is_equal_approx(0.0, 0.0001)


## The shipped lattice is the one the author asked for, and a child can see it move.
func test_the_defaults_are_the_visible_ones() -> void:
	var cfg: ShipConfig = ShipConfig.defaults()
	assert_float(cfg.snap_deg).is_equal_approx(5.0, 0.001)
	assert_float(cfg.snap_m).is_equal_approx(0.1, 0.001)
	(
		assert_float(float(InspectorPanel.SNAP_CHOICES[InspectorPanel.SNAP_DEFAULT_INDEX]))
		. append_failure_message("the picker must open on the same step the config ships")
		. is_equal_approx(5.0, 0.001)
	)
