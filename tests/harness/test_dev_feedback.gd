# The developer note (SHIFT+F). Only the parts that can be asked without standing a builder up:
# whether it arms, and what opens it. The chord is worth a test of its own because the cost of
# getting it wrong is silent - either the note never opens, or FRAME loses the key it has had since
# the beginning and nobody connects the two.
class_name TestDevFeedback
extends GdUnitTestSuite


func _key(code: Key, shift: bool) -> InputEventKey:
	var out: InputEventKey = InputEventKey.new()
	out.keycode = code
	out.shift_pressed = shift
	out.pressed = true
	return out


## A test run is a debug build, so the feature is live in one.
func test_it_arms_in_a_debug_build() -> void:
	assert_bool(OS.is_debug_build()).is_true()
	assert_bool(ShipDevFeedback.is_enabled()).is_equal(ShipDevFeedback.ENABLED)


func test_shift_f_opens_a_note() -> void:
	assert_bool(ShipDevFeedback.opens(_key(KEY_F, true))).is_true()


## PLAIN F BELONGS TO FRAME (`ShipBuilder._handle_view_hotkey`). If this ever passes, the note has
## taken a key the view was using and framing has quietly stopped working.
func test_plain_f_is_left_to_frame() -> void:
	assert_bool(ShipDevFeedback.opens(_key(KEY_F, false))).is_false()


func test_nothing_else_opens_it() -> void:
	for code: Key in [KEY_E, KEY_G, KEY_ESCAPE, KEY_DELETE, KEY_Z]:
		(
			assert_bool(ShipDevFeedback.opens(_key(code, true)))
			. append_failure_message("SHIFT+%s opened a note" % OS.get_keycode_string(code))
			. is_false()
		)


## The switch is a switch: with it off, no key opens a note whatever the build.
func test_the_switch_is_the_whole_of_it() -> void:
	if not ShipDevFeedback.ENABLED:
		assert_bool(ShipDevFeedback.is_enabled()).is_false()
		assert_bool(ShipDevFeedback.opens(_key(KEY_F, true))).is_false()
