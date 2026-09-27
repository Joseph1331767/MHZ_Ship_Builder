# Snapshot undo/redo, and the coalescing window added on 2026-09-27.
#
# The window exists because auto-repeat was flushing the whole stack: the numpad rotations and the
# arrow steps pass their echo events through on purpose, and every echo pushed a full doc snapshot,
# so about two seconds of held numpad-4 consumed all 64 slots and every earlier edit with them
# (docs/future/ux.md section 2.5, B9). These tests run far inside the 400 ms window, so a
# back-to-back pair coalesces by construction - no clock control is needed, only `coalesce_ms` to
# turn it off.
class_name TestHistory
extends GdUnitTestSuite

var _data: ShipData
var _cfg: ShipConfig


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message("ShipData.load_all() failed: %s" % [str(_data.load_errors)])
		. is_true()
	)
	_cfg = ShipConfig.defaults()


## A one-part document whose root yaw is [param yaw], so two snapshots can be told apart.
func _doc(yaw: float) -> ShipDoc:
	var out: ShipDoc = ShipDoc.create_new(_data.family_ids()[0], "", _data, 0.0)
	(out.parts[out.root] as ShipPart).yaw = yaw
	return out


func _yaw_of(doc: ShipDoc) -> float:
	return (doc.parts[doc.root] as ShipPart).yaw


## A snapshot is the state ARRIVED at, not the state left - see the class docstring. So a hold of
## three repeats leaves one slot holding the LAST state of the run, and one undo steps over all of
## it to the state before the hold began.
func test_a_run_of_one_label_folds_into_one_slot() -> void:
	var history: ShipHistory = ShipHistory.new()
	history.push(_doc(1.0), "seed")
	# The hold: three repeats of one verb, all inside the window.
	history.push(_doc(2.0), "rotate", "p_0001")
	history.push(_doc(3.0), "rotate", "p_0001")
	history.push(_doc(4.0), "rotate", "p_0001")
	(
		assert_float(_yaw_of(history.peek()))
		. append_failure_message(
			"the head must track the live document, or peek() rolls back wrong"
		)
		. is_equal_approx(4.0, 0.001)
	)
	(
		assert_float(_yaw_of(history.undo()))
		. append_failure_message("one undo must step back over the whole hold, not one repeat")
		. is_equal_approx(1.0, 0.001)
	)
	(
		assert_bool(history.can_undo())
		. append_failure_message("the hold took one slot, so there is nothing before the seed")
		. is_false()
	)


func test_two_different_verbs_keep_their_own_slots() -> void:
	var history: ShipHistory = ShipHistory.new()
	history.push(_doc(1.0), "seed")
	history.push(_doc(2.0), "rotate")
	history.push(_doc(3.0), "move")
	assert_float(_yaw_of(history.undo())).is_equal_approx(2.0, 0.001)
	assert_float(_yaw_of(history.undo())).is_equal_approx(1.0, 0.001)
	assert_bool(history.can_undo()).is_false()


## Off, every push takes a slot - which is what the class did before the window existed.
func test_the_window_can_be_switched_off() -> void:
	var history: ShipHistory = ShipHistory.new()
	history.coalesce_ms = 0
	history.push(_doc(1.0), "seed")
	history.push(_doc(2.0), "rotate", "p_0001")
	history.push(_doc(3.0), "rotate", "p_0001")
	assert_float(_yaw_of(history.undo())).is_equal_approx(2.0, 0.001)
	assert_float(_yaw_of(history.undo())).is_equal_approx(1.0, 0.001)


## STEPPING THROUGH HISTORY CLOSES THE RUN. Without this the edit after an undo would fold into
## the run it just stepped out of, and the redo tail - which only the appending branch discards -
## would survive as a future that no longer follows from the present.
func test_an_edit_after_an_undo_takes_its_own_slot() -> void:
	var history: ShipHistory = ShipHistory.new()
	history.push(_doc(1.0), "seed")
	history.push(_doc(2.0), "rotate", "p_0001")
	history.undo()
	history.push(_doc(99.0), "rotate", "p_0001")
	(
		assert_bool(history.can_redo())
		. append_failure_message("a new edit must discard the redo tail it branched from")
		. is_false()
	)
	assert_float(_yaw_of(history.peek())).is_equal_approx(99.0, 0.001)
	assert_float(_yaw_of(history.undo())).is_equal_approx(1.0, 0.001)


func test_undo_and_redo_return_null_at_the_ends() -> void:
	var history: ShipHistory = ShipHistory.new()
	assert_object(history.undo()).is_null()
	assert_object(history.redo()).is_null()
	history.push(_doc(1.0), "seed")
	assert_bool(history.can_undo()).is_false()
	assert_object(history.undo()).is_null()


func test_the_depth_cap_drops_from_the_front() -> void:
	var history: ShipHistory = ShipHistory.new(3)
	# Distinct labels, or the window would fold them into one slot and the cap never fire.
	for i: int in 6:
		history.push(_doc(float(i)), "edit %d" % i)
	var seen: int = 0
	while history.can_undo():
		history.undo()
		seen += 1
	(
		assert_int(seen)
		. append_failure_message("a depth of 3 holds 3 snapshots, so 2 steps back")
		. is_equal(2)
	)


## AN EDIT THAT NAMES NO PARTS NEVER FOLDS. A joint or topology change passes no ids, and without
## them there is nothing to say two pushes were one gesture - `tools/ship_visual_check.gd` found
## one undo swallowing two different seam-style edits when the window keyed on the label alone.
func test_two_edits_that_name_nothing_keep_their_own_slots() -> void:
	var history: ShipHistory = ShipHistory.new()
	history.push(_doc(1.0), "seed")
	history.push(_doc(2.0), "seam style")
	history.push(_doc(3.0), "seam style")
	assert_float(_yaw_of(history.undo())).is_equal_approx(2.0, 0.001)
	assert_float(_yaw_of(history.undo())).is_equal_approx(1.0, 0.001)


## And two gestures on DIFFERENT parts keep their own slots however fast they follow.
func test_the_same_verb_on_two_parts_keeps_two_slots() -> void:
	var history: ShipHistory = ShipHistory.new()
	history.push(_doc(1.0), "seed")
	history.push(_doc(2.0), "rotate", "p_0001")
	history.push(_doc(3.0), "rotate", "p_0002")
	assert_float(_yaw_of(history.undo())).is_equal_approx(2.0, 0.001)
	assert_float(_yaw_of(history.undo())).is_equal_approx(1.0, 0.001)
