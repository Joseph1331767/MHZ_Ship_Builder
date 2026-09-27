# The four views. The rung ladder is the one thing here that must not rot quietly: a control added
# without a tier is visible everywhere, which is the safe direction, but a control tiered WRONG is
# invisible to the author in the view they work in and there is nothing on screen to say why.
#
# These tests need no builder - the ladder and the table are the whole of what is asserted.
class_name TestUiMode
extends GdUnitTestSuite


func _mode() -> ShipUiMode:
	var bar: HBoxContainer = HBoxContainer.new()
	auto_free(bar)
	# No theme and no layout: the picker guards for both, and neither is under test.
	return ShipUiMode.new(bar, null)


func test_the_bar_gets_one_button_per_rung_in_order() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	auto_free(bar)
	ShipUiMode.new(bar, null)
	var row: Node = bar.get_child(0)
	assert_int(row.get_child_count()).is_equal(ShipUiMode.LEVEL_NAMES.size())
	for i: int in row.get_child_count():
		assert_str((row.get_child(i) as Button).text).is_equal(str(ShipUiMode.LEVEL_NAMES[i]))


## EVERY RUNG CONTAINS THE ONE BELOW IT. Moving up never takes anything away, so a player who
## learned BASIC never has to unlearn it - and the author, in DEV, sees everything there is.
func test_each_rung_contains_the_one_below() -> void:
	var mode: ShipUiMode = _mode()
	var seen: PackedStringArray = PackedStringArray()
	for level: int in ShipUiMode.LEVEL_NAMES.size():
		mode.level = level
		var here: PackedStringArray = PackedStringArray()
		for key: String in ShipUiMode.SHOWN_FROM:
			if mode.shows(key):
				here.append(key)
		for key: String in seen:
			(
				assert_bool(here.has(key))
				. append_failure_message(
					(
						"%s shows %s but %s does not"
						% [ShipUiMode.name_of(level - 1), key, ShipUiMode.name_of(level)]
					)
				)
				. is_true()
			)
		seen = here
	# And the top rung shows everything there is.
	assert_int(seen.size()).is_equal(ShipUiMode.SHOWN_FROM.size())


## DEV IS THE DEFAULT. The author works in it; a silent demotion of their own tools on startup
## would be the worst kind of surprise, and the gate tools assert against panels BASIC hides.
func test_it_opens_on_dev() -> void:
	assert_int(_mode().level).is_equal(ShipUiMode.Level.DEV)


## BASIC HAS TO BE ABLE TO BUILD A SHIP. A rung that cannot place a part is a screenshot, not a
## view - so the palette, the camera framing and undo are all in it by assertion, not by habit.
func test_basic_can_still_build() -> void:
	var mode: ShipUiMode = _mode()
	mode.level = ShipUiMode.Level.BASIC
	for key: String in ["PartPaletteSlotFrame", "FRAME", "UNDO", "REDO", "NEW", "OPEN", "SAVE"]:
		(
			assert_bool(mode.shows(key))
			. append_failure_message("BASIC cannot reach %s, so it cannot build a ship" % key)
			. is_true()
		)
	# And it is genuinely quieter: the numbers, the tree and the diagnostics are all gone.
	for key: String in ["InspectorSlotFrame", "TreeSlotFrame", "GaugeSlotFrame", "LayersPanel"]:
		(
			assert_bool(mode.shows(key))
			. append_failure_message("%s is still on screen in BASIC" % key)
			. is_false()
		)


## A KEY MUST SURVIVE Godot's node-name rules. "ROOMS: PIECES" is really named "ROOMS PIECES",
## and looking it up by its label found nothing at all - the button stayed visible at every rung
## until this was caught by eye.
func test_every_key_is_a_legal_node_name_or_is_looked_up_as_one() -> void:
	for key: String in ShipUiMode.SHOWN_FROM:
		var safe: String = key.validate_node_name()
		(
			assert_str(safe)
			. append_failure_message("%s validates to nothing, so it can never be found" % key)
			. is_not_empty()
		)


func test_an_untiered_control_is_visible_everywhere() -> void:
	var mode: ShipUiMode = _mode()
	mode.level = ShipUiMode.Level.BASIC
	(
		assert_bool(mode.shows("SomethingNobodyHasTieredYet"))
		. append_failure_message("a new control must fail VISIBLE, never silently missing")
		. is_true()
	)


func test_name_of_refuses_a_rung_that_does_not_exist() -> void:
	assert_str(ShipUiMode.name_of(-1)).is_empty()
	assert_str(ShipUiMode.name_of(99)).is_empty()
	assert_str(ShipUiMode.name_of(ShipUiMode.Level.BASIC)).is_equal("BASIC")
