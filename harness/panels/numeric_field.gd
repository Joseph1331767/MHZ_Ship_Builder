## NumericField - the one numeric input in the whole builder.
##
## A CAPS label plus a right-aligned entry box that always renders three decimals
## (SPEC section 11: "numbers always to 3 decimals so fields do not jitter"). Three ways in:
## type a number, drag horizontally over the label to scrub, or have a panel push a value in
## from a signal. The three must not fight, and this class is where that is arranged.
##
## THE TWO-WAY BINDING RULE, and why it lives here rather than in every panel.
##
##   1. set_value() NEVER emits value_changed. Only a human edit does - typing or scrubbing.
##      That single asymmetry is what stops the classic loop: field emits -> model updates ->
##      model emits -> field writes -> field emits -> ...
##   2. set_value() NEVER overwrites the text of a field the user is currently typing into.
##      The model number is still taken (so the field is not stale once they finish); only the
##      view is left alone. Escape or a bad parse reverts to whatever the model last said, so
##      abandoning an edit lands on the CURRENT value, not the one from when typing started.
##   3. set_value() NEVER overwrites the text mid-scrub either. A scrub emits, which makes the
##      model emit back, which would otherwise stamp the quantized echo over the drag.
##
## SPEC section 10 - render to texture. Nothing here asks the OS or the display layer for
## anything: no global mouse position, no window size. Scrubbing uses only
## InputEventMouseMotion.relative, which arrives inside the event that Godot already routed
## to this Control, so the same code works when the builder is a texture on a diegetic device
## driven by Viewport.push_input().
## The LineEdit's context menu is switched off because a native popup would not exist on the
## device texture, and the field is deliberately a plain LineEdit so a synthesized keypad can
## drive it later (SPEC section 10, last bullet).
class_name NumericField
extends Control

## A human changed the value: typed and committed, or dragged. Never emitted by set_value().
signal value_changed(value: float)

## SPEC section 11. Every number in the builder is rendered through format_number().
## NUMBER_FORMAT is written out rather than built from DECIMALS with a dynamic-precision
## "%.*f": Godot's format operator is a printf SUBSET and dynamic precision is not something
## to bet a whole UI's numbers on. Keep the two in step by hand if DECIMALS ever moves.
const DECIMALS: int = 3
const NUMBER_FORMAT: String = "%.3f"
const EPSILON_DISPLAY: float = 0.0005

const ROW_HEIGHT: float = 18.0
const LABEL_WIDTH: float = 62.0
const FIELD_WIDTH: float = 68.0
const TICK_LENGTH: float = 3.0

## A full sweep of the declared range takes about this many pixels of drag.
const SCRUB_SPAN_PX: float = 300.0
## Fallback span when a field declares no finite range (raw yaw, say).
const SCRUB_FALLBACK_SPAN: float = 180.0
const FINE_FACTOR: float = 0.1
const COARSE_FACTOR: float = 8.0

var _value: float = 0.0
var _minimum: float = -INF
var _maximum: float = INF
## Quantization increment. 0.0 means "do not quantize".
var _step: float = 0.0
var _is_int: bool = false
## Units per pixel of drag. 0.0 means "derive it from the range" - see _scrub_rate().
var _scrub_override: float = 0.0
var _editable: bool = true
var _label_text: String = ""
var _suffix: String = ""

var _label: Label = null
var _line: LineEdit = null
var _ship_theme: ShipTheme = null

## True between the first keystroke and the commit/abandon of an entry.
var _typing: bool = false
var _dragging: bool = false
## Unquantized accumulator for the current drag, so quantization cannot ratchet.
var _drag_value: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE so a drag over the label reaches this Control's _gui_input; the LineEdit keeps
	# its own events because it is the only child that does not ignore the mouse.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	_label = Label.new()
	_label.name = "FieldLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.custom_minimum_size = Vector2(ShipTheme.pxf(LABEL_WIDTH), ShipTheme.pxf(0.0))
	_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_label.text = _label_text
	row.add_child(_label)

	_line = LineEdit.new()
	_line.name = "FieldEntry"
	_line.custom_minimum_size = Vector2(ShipTheme.pxf(FIELD_WIDTH), ShipTheme.pxf(0.0))
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_line.add_theme_font_size_override("font_size", ShipTheme.font_small())
	# A LineEdit context menu is a PopupMenu, i.e. a Window. SPEC section 10 forbids native
	# windows in the builder, so it is switched off rather than relied upon to embed.
	_line.context_menu_enabled = false
	_line.select_all_on_focus = true
	_line.text_changed.connect(_on_text_changed)
	_line.text_submitted.connect(_on_text_submitted)
	_line.focus_entered.connect(queue_redraw)
	_line.focus_exited.connect(_on_focus_exited)
	_line.gui_input.connect(_on_entry_gui_input)
	row.add_child(_line)

	_refresh_text()
	_apply_editable()
	_apply_palette()


## Corner ticks mark the ACTIVE field rather than decorating every row (SPEC section 11):
## eight marks on each of a dozen fields is noise, eight on the one being edited is an
## affordance, and it is the only feedback a scrub has other than the number moving.
func _draw() -> void:
	if not _dragging and (_line == null or not _line.has_focus()):
		return
	var tint: Color = _role_color("accent", Color(0.5, 0.5, 0.5, 1.0))
	draw_corner_ticks(self, Rect2(Vector2.ZERO, size), tint, TICK_LENGTH)


# ---------------------------------------------------------------- configuration


## One-shot setup. `step` of 0.0 leaves the value unquantized; `is_integer` forces whole
## numbers (this is what `is_int` from ShapeGen.effective_ranges() maps onto).
func configure(
	field_label: String, minimum: float, maximum: float, step: float, is_integer: bool
) -> void:
	_label_text = field_label.to_upper()
	_minimum = minimum
	_maximum = maximum
	_step = maxf(step, 0.0)
	_is_int = is_integer
	if _is_int and _step <= 0.0:
		_step = 1.0
	if _label != null:
		_label.text = _label_text
	_apply_value(_value, false)


## Narrow or widen the accepted range in place, keeping the current value inside it.
func set_range(minimum: float, maximum: float) -> void:
	_minimum = minimum
	_maximum = maximum
	_apply_value(_value, false)


## Quantization increment; 0.0 disables it. The snap selector writes the angular increment
## here so what is displayed is exactly what is stored (SPEC section 6).
func set_step(step: float) -> void:
	_step = maxf(step, 0.0)
	if _is_int and _step <= 0.0:
		_step = 1.0
	_apply_value(_value, false)


## Units per pixel of horizontal drag, overriding the range-derived default. Needed wherever
## the CLAMP range and the useful DRAG range differ by an order of magnitude - attach offset
## is clamped generously but has to scrub in centimetres. 0.0 restores the derived rate.
func set_scrub_rate(units_per_pixel: float) -> void:
	_scrub_override = maxf(units_per_pixel, 0.0)


## Unit shown after the label, e.g. "DEG" or "M". Purely cosmetic.
func set_suffix(suffix: String) -> void:
	_suffix = suffix.to_upper()
	if _label != null:
		_label.text = _display_label()


## The external / model write. Never emits, and never stamps over a field the user is busy
## with - see the class docs.
func set_value(value: float) -> void:
	var clean: float = value
	if not is_finite(clean):
		clean = 0.0
	_value = clampf(clean, _minimum, _maximum)
	if _dragging or has_uncommitted_edit():
		return
	_refresh_text()


func get_value() -> float:
	return _value


## True while the user has typed into this field and neither committed nor abandoned the
## edit. Panels use it to decide whether a refresh may touch this field.
func has_uncommitted_edit() -> bool:
	return _typing and _line != null and _line.has_focus()


func set_editable(on: bool) -> void:
	_editable = on
	_apply_editable()


func is_field_editable() -> bool:
	return _editable


## Roles from data/palette.json, re-resolved on every palette_changed. No index is ever
## named here - the whole LUT swaps when a budget maxes out (SPEC section 8).
func bind_theme(ship_theme: ShipTheme) -> void:
	_ship_theme = ship_theme
	if _ship_theme != null and not _ship_theme.palette_changed.is_connected(_on_palette_changed):
		_ship_theme.palette_changed.connect(_on_palette_changed)
	_apply_palette()


# ---------------------------------------------------------------- shared helpers


## The one number formatter in the builder. Exactly three decimals, always, so a column of
## fields never changes width as values change (SPEC section 11).
static func format_number(value: float) -> String:
	if is_nan(value):
		return "---"
	if value == INF:
		return "INF"
	if value == -INF:
		return "-INF"
	var v: float = value
	if absf(v) < EPSILON_DISPLAY:
		# Kills "-0.000", which reads as a different number from "0.000".
		v = 0.0
	return NUMBER_FORMAT % v


## 1 px corner ticks - the retro-console frame detail from SPEC section 11. Shared so all
## four panels draw the identical mark.
static func draw_corner_ticks(target: CanvasItem, rect: Rect2, tint: Color, length: float) -> void:
	if target == null or rect.size.x <= length * 2.0 or rect.size.y <= length * 2.0:
		return
	var x0: float = rect.position.x
	var y0: float = rect.position.y
	var x1: float = rect.position.x + rect.size.x - 1.0
	var y1: float = rect.position.y + rect.size.y - 1.0
	var corners: Array[Vector2] = [
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)
	]
	var steps: Array[Vector2] = [
		Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)
	]
	for i: int in corners.size():
		var c: Vector2 = corners[i]
		var s: Vector2 = steps[i]
		target.draw_line(c, c + Vector2(s.x * length, 0.0), tint, 1.0)
		target.draw_line(c, c + Vector2(0.0, s.y * length), tint, 1.0)


# ---------------------------------------------------------------- input


func _gui_input(event: InputEvent) -> void:
	if not _editable:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		_handle_scrub_button(button)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		_handle_scrub_motion(motion)


func _handle_scrub_button(button: InputEventMouseButton) -> void:
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_dragging = true
		_drag_value = _value
	else:
		_dragging = false
		_refresh_text()
	queue_redraw()
	accept_event()


func _handle_scrub_motion(motion: InputEventMouseMotion) -> void:
	# event.relative only. Reading a global mouse position here would break the diegetic
	# device path (SPEC section 10) and is grep-checked at the gate.
	var rate: float = _scrub_rate()
	if motion.shift_pressed:
		rate *= FINE_FACTOR
	elif motion.ctrl_pressed:
		rate *= COARSE_FACTOR
	_drag_value += motion.relative.x * rate
	_drag_value = clampf(_drag_value, _minimum, _maximum)
	_apply_value(_drag_value, true)
	accept_event()


func _on_entry_gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_ESCAPE:
		return
	# Abandon: fall back to the CURRENT model value, which may have moved while typing.
	_typing = false
	_refresh_text()
	_line.release_focus()
	accept_event()


func _on_text_changed(_new_text: String) -> void:
	_typing = true


func _on_text_submitted(new_text: String) -> void:
	_commit_text(new_text)
	if _line != null:
		_line.release_focus()


func _on_focus_exited() -> void:
	queue_redraw()
	if _line == null:
		return
	_commit_text(_line.text)


func _commit_text(raw: String) -> void:
	_typing = false
	var text: String = raw.strip_edges()
	if not text.is_valid_float():
		# Unparseable entry is not an error state; it just does not happen.
		_refresh_text()
		return
	_apply_value(text.to_float(), true)


# ---------------------------------------------------------------- internals


## The single place a value is clamped, quantized and rendered. `notify` is true only on the
## human-edit paths, which is what keeps set_value() silent.
func _apply_value(value: float, notify: bool) -> void:
	var next: float = value
	if not is_finite(next):
		next = _value
	if _step > 0.0:
		next = snappedf(next, _step)
	if _is_int:
		next = roundf(next)
	next = clampf(next, _minimum, _maximum)
	if _is_int:
		next = roundf(next)
	var changed: bool = not is_equal_approx(next, _value)
	_value = next
	_refresh_text()
	if notify and changed:
		value_changed.emit(_value)


func _refresh_text() -> void:
	if _line == null:
		return
	var text: String = format_number(_value)
	if _line.text == text:
		return
	_line.text = text
	_line.caret_column = text.length()


## Units per pixel of horizontal drag: a full sweep of the declared range in SCRUB_SPAN_PX,
## but never finer than one quantization step.
func _scrub_rate() -> float:
	if _scrub_override > 0.0:
		return _scrub_override
	var span: float = _maximum - _minimum
	if not is_finite(span) or span <= 0.0:
		span = SCRUB_FALLBACK_SPAN
	var rate: float = span / SCRUB_SPAN_PX
	if _step > 0.0:
		rate = maxf(rate, _step / 6.0)
	return maxf(rate, 0.000001)


func _display_label() -> String:
	if _suffix == "":
		return _label_text
	return "%s %s" % [_label_text, _suffix]


func _apply_editable() -> void:
	if _line != null:
		_line.editable = _editable
		_line.focus_mode = Control.FOCUS_ALL if _editable else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_HSIZE if _editable else Control.CURSOR_ARROW
	_apply_palette()


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_apply_palette()


func _apply_palette() -> void:
	if _label != null:
		var role: String = "text" if _editable else "text_dim"
		_label.add_theme_color_override("font_color", _role_color(role, Color.WHITE))
		_label.text = _display_label()
	queue_redraw()


func _role_color(role: String, fallback: Color) -> Color:
	if _ship_theme == null:
		return fallback
	return _ship_theme.color_for_role(role)
