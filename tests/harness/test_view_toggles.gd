# The top bar's layer toggles. Only the parts that can be asked without standing a builder up:
# what the bar ends up holding, and whether the WALLS switch and the layer stay in step. The sync
# is worth a test because the cost of losing it is a bar that lies about what is on screen - a
# tool or a hotkey drives the layer, the button stays where it was, and the next click sends the
# layer the way it already went.
class_name TestViewToggles
extends GdUnitTestSuite


func _bar() -> HBoxContainer:
	var out: HBoxContainer = HBoxContainer.new()
	# No theme and no view: every handler guards for both, and neither is what is under test.
	auto_free(out)
	return out


func test_the_bar_gets_both_toggles_named() -> void:
	var bar: HBoxContainer = _bar()
	ShipViewToggles.new(bar, null)  # the constructor IS what fills the bar
	assert_int(bar.get_child_count()).is_equal(2)
	var labels: PackedStringArray = PackedStringArray()
	for child: Node in bar.get_children():
		labels.append((child as CheckButton).text)
	assert_array(labels).contains(["DITHER", "WALLS"])


## OFF, and deliberately: INTERIOR is the mode the layer was built for and its whole purpose is
## looking into rooms (ADR 0046). A change here is a change to what the builder opens on.
func test_the_walls_layer_starts_dropped() -> void:
	var toggles: ShipViewToggles = ShipViewToggles.new(_bar(), null)
	assert_bool(ShipViewToggles.WALLS_SHOWN).is_false()
	assert_bool(toggles.walls_shown()).is_equal(ShipViewToggles.WALLS_SHOWN)


func test_driving_the_layer_moves_the_button_with_it() -> void:
	var bar: HBoxContainer = _bar()
	var toggles: ShipViewToggles = ShipViewToggles.new(bar, null)
	for wanted: bool in [true, false, true]:
		toggles.set_walls_shown(wanted)
		(
			assert_bool(toggles.walls_shown())
			. append_failure_message("set_walls_shown(%s) did not take" % str(wanted))
			. is_equal(wanted)
		)
		for child: Node in bar.get_children():
			if (child as CheckButton).text == "WALLS":
				(
					assert_bool((child as CheckButton).button_pressed)
					. append_failure_message("the button did not follow the layer")
					. is_equal(wanted)
				)
