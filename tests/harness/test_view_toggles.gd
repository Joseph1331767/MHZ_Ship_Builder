# The top bar's toggles and the LAYERS explorer. Only the parts that can be asked without
# standing a builder up: what each one ends up holding, and whether the boxes and the layer set
# stay in step. The sync is worth a test because the cost of losing it is a panel that lies about
# what is on screen - a tool drives the layers, the boxes stay where they were, and the next click
# sends a layer the way it already went.
class_name TestViewToggles
extends GdUnitTestSuite


func _bar() -> HBoxContainer:
	var out: HBoxContainer = HBoxContainer.new()
	# No theme and no view: every handler guards for both, and neither is what is under test.
	auto_free(out)
	return out


func _layers() -> ShipLayersControl:
	var frame: Control = Control.new()
	auto_free(frame)
	return ShipLayersControl.new(frame, null)


func test_the_bar_keeps_dither_and_nothing_else() -> void:
	# RETIRED(2026-09-26): a WALLS check button here. It is a LAYER, so it went to the explorer;
	# DITHER is a render setting and stays.
	var bar: HBoxContainer = _bar()
	ShipViewToggles.new(bar, null)  # the constructor IS what fills the bar
	assert_int(bar.get_child_count()).is_equal(1)
	assert_str((bar.get_child(0) as CheckButton).text).is_equal("DITHER")


func test_every_layer_is_listed_once_with_a_label_and_help() -> void:
	var keys: PackedStringArray = PackedStringArray()
	for layer: Array in ShipLayersControl.LAYERS:
		assert_int(layer.size()).is_equal(3)
		for field: Variant in layer:
			assert_str(str(field)).is_not_empty()
		(
			assert_bool(keys.has(str(layer[0])))
			. append_failure_message("layer %s is listed twice" % str(layer[0]))
			. is_false()
		)
		keys.append(str(layer[0]))
	assert_array(keys).contains(
		[ShipCsgBake.SURFACE_WALL, ShipCsgBake.SURFACE_CUT, ShipLayersControl.LAYER_DOOR]
	)


## WALLS start dropped and the other two drawn: a prebuild carries no walls at all since
## 2026-09-26, and the mode that gains most from the switch is INTERIOR.
func test_the_walls_layer_starts_dropped_and_the_rest_drawn() -> void:
	assert_array(_layers().hidden()).contains_exactly([ShipCsgBake.SURFACE_WALL])


func test_driving_a_layer_moves_its_box_with_it() -> void:
	var layers: ShipLayersControl = _layers()
	layers.set_layer_shown(ShipCsgBake.SURFACE_WALL, true)
	assert_array(layers.hidden()).is_empty()
	layers.set_layer_shown(ShipLayersControl.LAYER_DOOR, false)
	layers.set_layer_shown(ShipCsgBake.SURFACE_CUT, false)
	(
		assert_array(layers.hidden())
		. append_failure_message("hidden() must list every box that is off, in LAYERS order")
		. contains_exactly([ShipCsgBake.SURFACE_CUT, ShipLayersControl.LAYER_DOOR])
	)
