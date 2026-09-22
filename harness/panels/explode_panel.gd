class_name ShipExplodePanel
extends PanelContainer
## EXPLODE OPTIONS (ADR 0031): the player's controls for the exploded view, docked over the 3D
## view while it is exploded. An in-scene Control, never a Window (AGENTS section 7).
##
## Edits a [ShipExplodeSettings] it holds by reference. Every change is a move, never a bake (ADR
## 0032): the pieces are already cut into their fundamental cells, so a gap, a slicer axis or the
## cluster toggle only relocates them - [signal layout_changed]. The POSITION slider scrubs the
## explode itself ([signal position_changed]) and follows the animation ([method show_amount]).

## A separation, a slicer axis or the cluster toggle changed: move what is on screen.
signal layout_changed
## The animation speed changed: remember it.
signal speed_changed
## The POSITION slider was dragged: put the pieces this far exploded, 0 to 1.
signal position_changed(amount: float)

const AXIS_LABELS: PackedStringArray = ["X", "Y RADIAL", "Z"]
const COUNT_LABELS: PackedStringArray = ["OFF", "BISECT", "TRISECT"]
## Design-space width of the panel; ShipTheme scales it.
const WIDTH: float = 296.0
## Slider resolution, in metres.
const SLIDER_STEP: float = 0.05

var _settings: ShipExplodeSettings = null
var _theme: ShipTheme = null
var _body: VBoxContainer = null
var _collapse: Button = null
var _separate: CheckButton = null
var _separation: HSlider = null
var _separation_value: Label = null
var _slice_options: Array[OptionButton] = []
var _slice_gap: HSlider = null
var _slice_gap_value: Label = null
var _cluster: CheckButton = null
var _cluster_options: Array[OptionButton] = []
var _cluster_gap: HSlider = null
var _cluster_gap_value: Label = null
var _speed: HSlider = null
var _speed_value: Label = null
var _position: HSlider = null
var _position_value: Label = null


## Builds the controls once, for [param settings].
func setup(settings: ShipExplodeSettings, theme: ShipTheme) -> void:
	_settings = settings
	_theme = theme
	if _body == null:
		_build()
	refresh()


## Edit [param settings] from now on - a tool resetting to defaults hands in a fresh object.
func bind(settings: ShipExplodeSettings) -> void:
	_settings = settings
	refresh()


## Every control shows what the settings hold, without emitting a change.
func refresh() -> void:
	if _settings == null or _body == null:
		return
	_separate.set_pressed_no_signal(_settings.separate)
	_separation.set_value_no_signal(_settings.separation_m)
	_separation.editable = _settings.separate
	_slice_gap.set_value_no_signal(_settings.slice_separation_m)
	_cluster.set_pressed_no_signal(_settings.cluster_slicing)
	_cluster_gap.set_value_no_signal(_settings.cluster_slice_separation_m)
	for axis: int in 3:
		_slice_options[axis].select(_settings.slices[axis])
		_cluster_options[axis].select(_settings.cluster_slices[axis])
		_cluster_options[axis].disabled = not _settings.cluster_slicing
	_cluster_gap.editable = _settings.cluster_slicing
	_speed.set_value_no_signal(_settings.speed)
	_show_values()


## The POSITION slider shows how far exploded the view is, without emitting a change.
func show_amount(amount: float) -> void:
	if _position == null:
		return
	_position.set_value_no_signal(amount)
	_position_value.text = "%d %%" % int(round(amount * 100.0))


# --- building ------------------------------------------------------------------------------


func _build() -> void:
	name = "ExplodeOptions"
	custom_minimum_size = Vector2(ShipTheme.pxf(WIDTH), 0.0)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	var head: HBoxContainer = HBoxContainer.new()
	box.add_child(head)
	var title: Label = _label("EXPLODE OPTIONS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_collapse = _button("-", _on_collapse_pressed)
	_collapse.tooltip_text = "FOLD THE EXPLODE OPTIONS AWAY"
	head.add_child(_collapse)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 2)
	box.add_child(_body)

	_separate = _check("SEPARATE MODULES", "PULL MODULES AND THEIR CHUNKS APART AT THEIR SEAMS")
	_separate.toggled.connect(_on_separate_toggled)
	_body.add_child(_separate)
	var sep_row: Array = _slider_row(
		"GAP", ShipExplodeSettings.SEPARATION_MAX_M, "CLEAR SPACE EACH SEAM OPENS, IN METRES"
	)
	_separation = sep_row[0]
	_separation_value = sep_row[1]
	_separation.value_changed.connect(_on_separation_changed)

	_body.add_child(HSeparator.new())
	_body.add_child(_label("SLICES - EACH PART IN ITS OWN AXES"))
	_slice_options = _axis_rows(_on_slice_selected)
	var slice_row: Array = _slider_row(
		"SLICE GAP",
		ShipExplodeSettings.SLICE_SEPARATION_MAX_M,
		"HOW FAR EACH SLICE PULLS OFF ITS CUT, IN METRES"
	)
	_slice_gap = slice_row[0]
	_slice_gap_value = slice_row[1]
	_slice_gap.value_changed.connect(_on_slice_gap_changed)

	_body.add_child(HSeparator.new())
	_cluster = _check(
		"SLICE CLUSTER CHUNKS",
		"SLICE THE CHUNKS OF A ROOM OF SEVERAL PARTS, WITH THEIR OWN SETTINGS"
	)
	_cluster.toggled.connect(_on_cluster_toggled)
	_body.add_child(_cluster)
	_cluster_options = _axis_rows(_on_cluster_selected)
	var cluster_row: Array = _slider_row(
		"CHUNK GAP",
		ShipExplodeSettings.SLICE_SEPARATION_MAX_M,
		"HOW FAR EACH CLUSTER CHUNK SLICE PULLS OFF ITS CUT, IN METRES"
	)
	_cluster_gap = cluster_row[0]
	_cluster_gap_value = cluster_row[1]
	_cluster_gap.value_changed.connect(_on_cluster_gap_changed)

	_body.add_child(HSeparator.new())
	_body.add_child(_label("ANIMATION"))
	var speed_row: Array = _slider_row(
		"SPEED", ShipExplodeSettings.SPEED_MAX, "HOW FAST THE PIECES COME APART AND BACK TOGETHER"
	)
	_speed = speed_row[0]
	_speed_value = speed_row[1]
	_speed.min_value = ShipExplodeSettings.SPEED_MIN
	_speed.value_changed.connect(_on_speed_changed)
	var position_row: Array = _slider_row(
		"POSITION", 1.0, "HOW FAR APART - DRAG TO SCRUB THE EXPLODE, 0 ASSEMBLED, 100 FULLY APART"
	)
	_position = position_row[0]
	_position_value = position_row[1]
	_position.step = 0.01
	_position.value_changed.connect(_on_position_changed)


## Three rows - X, Y RADIAL, Z - each an OFF / BISECT / TRISECT choice; their selectors, in axis
## order, each reporting (axis, count) to [param handler].
func _axis_rows(handler: Callable) -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	for axis: int in 3:
		var row: HBoxContainer = HBoxContainer.new()
		_body.add_child(row)
		var tag: Label = _label(AXIS_LABELS[axis])
		tag.custom_minimum_size = Vector2(ShipTheme.pxf(NumericField.LABEL_WIDTH), 0.0)
		row.add_child(tag)
		var option: OptionButton = OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.focus_mode = Control.FOCUS_NONE
		option.add_theme_font_size_override("font_size", ShipTheme.font_small())
		for count: int in COUNT_LABELS.size():
			option.add_item(COUNT_LABELS[count], count)
		option.item_selected.connect(handler.bind(axis))
		row.add_child(option)
		out.append(option)
	return out


## A labelled slider from 0 to [param maximum] metres with its value beside it:
## `[HSlider, Label]`.
func _slider_row(caption: String, maximum: float, tip: String) -> Array:
	var row: HBoxContainer = HBoxContainer.new()
	_body.add_child(row)
	var tag: Label = _label(caption)
	tag.custom_minimum_size = Vector2(ShipTheme.pxf(NumericField.LABEL_WIDTH), 0.0)
	row.add_child(tag)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = maximum
	slider.step = SLIDER_STEP
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = tip
	row.add_child(slider)
	var value: Label = _label("0.00 M")
	value.custom_minimum_size = Vector2(ShipTheme.pxf(56.0), 0.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return [slider, value]


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	return label


func _check(text: String, tip: String) -> CheckButton:
	var check: CheckButton = CheckButton.new()
	check.text = text
	check.tooltip_text = tip
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", ShipTheme.font_small())
	return check


func _button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", ShipTheme.font_small())
	b.pressed.connect(handler)
	return b


func _show_values() -> void:
	_separation_value.text = "%.2f M" % _settings.separation_m
	_slice_gap_value.text = "%.2f M" % _settings.slice_separation_m
	_cluster_gap_value.text = "%.2f M" % _settings.cluster_slice_separation_m
	_speed_value.text = "%.2f X" % _settings.speed


# --- edits ---------------------------------------------------------------------------------


func _on_collapse_pressed() -> void:
	_body.visible = not _body.visible
	_collapse.text = "-" if _body.visible else "+"


func _on_separate_toggled(on: bool) -> void:
	_settings.separate = on
	_separation.editable = on
	layout_changed.emit()


func _on_separation_changed(value: float) -> void:
	_settings.separation_m = value
	_show_values()
	layout_changed.emit()


func _on_slice_gap_changed(value: float) -> void:
	_settings.slice_separation_m = value
	_show_values()
	layout_changed.emit()


func _on_cluster_gap_changed(value: float) -> void:
	_settings.cluster_slice_separation_m = value
	_show_values()
	layout_changed.emit()


func _on_slice_selected(count: int, axis: int) -> void:
	var slices: Vector3i = _settings.slices
	slices[axis] = count
	_settings.slices = slices
	layout_changed.emit()


func _on_cluster_selected(count: int, axis: int) -> void:
	var slices: Vector3i = _settings.cluster_slices
	slices[axis] = count
	_settings.cluster_slices = slices
	layout_changed.emit()


func _on_cluster_toggled(on: bool) -> void:
	_settings.cluster_slicing = on
	for option: OptionButton in _cluster_options:
		option.disabled = not on
	_cluster_gap.editable = on
	layout_changed.emit()


func _on_speed_changed(value: float) -> void:
	_settings.speed = value
	_show_values()
	speed_changed.emit()


func _on_position_changed(value: float) -> void:
	_position_value.text = "%d %%" % int(round(value * 100.0))
	position_changed.emit(value)
