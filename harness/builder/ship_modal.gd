class_name ShipModal
extends RefCounted
## THE IN-SCENE DIALOG, in one place. Message, confirm, prompt and pick-from-a-list, over a dimmed
## full-rect layer that swallows every click behind it.
##
## NO NATIVE DIALOGS, EVER (AGENTS section 7, API_CONTRACT_UI): the whole builder renders into a
## 1280x800 SubViewport that becomes a screen inside another game, and a `Window` - an
## `AcceptDialog`, a `FileDialog` - simply does not exist on the texture the player sees. It looks
## right in the editor and is missing in the game, which is why the rule is absolute rather than a
## preference.
##
## A HOME OF ITS OWN because `ship_builder.gd` stood at gdlint's two-thousand-line cap and its
## thirty-public-method cap at the same time, and nothing in the UX plan (docs/future/ux.md
## section 5.1 step 0) fits on disk until lines are bought back. This is the seam `.gdlintrc` asks
## for rather than a split at whatever line the alarm fires on: "a self-contained, statically
## testable unit with no reference back to the file it came from". The dialog reads none of the
## builder's state - it takes a title, a body and a Callable, and hands back a String.
##
## `ShipBuilder.prompt()` and `show_message()` stay as two-line forwarders, so the public count
## does not move and no caller had to change. `API_CONTRACT_UI` line 181 pins `show_message`.

enum Mode { MESSAGE, CONFIRM, PROMPT, LIST }

## How tall the LIST mode's picker stands, in DESIGN pixels (ShipTheme scales them).
const LIST_HEIGHT: float = 200.0

## How far the dim goes toward opaque. Enough that the builder behind reads as out of reach,
## short of hiding what the dialog is about to act on.
const DIM_ALPHA: float = 0.78

var _theme: ShipTheme = null
var _layer: Control = null
var _dim: ColorRect = null
var _title: Label = null
var _body: Label = null
var _input: LineEdit = null
var _list: ItemList = null
var _cancel: Button = null
var _mode: int = Mode.MESSAGE
var _cb: Callable = Callable()


## Builds the layer as a child of [param parent], hidden. [param parent] must be the application
## root Control itself and never a Container - a Container overrides a child's rect on every sort.
func _init(parent: Control, theme: ShipTheme, width: float) -> void:
	_theme = theme
	_layer = Control.new()
	_layer.name = "ModalLayer"
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.visible = false
	if parent != null:
		parent.add_child(_layer)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = _dim_colour()
	_layer.add_child(_dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)

	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(ShipTheme.pxf(width), 0.0)
	center.add_child(frame)

	var box: VBoxContainer = VBoxContainer.new()
	frame.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", ShipTheme.font_title())
	box.add_child(_title)
	box.add_child(HSeparator.new())

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)

	_input = LineEdit.new()
	_input.visible = false
	# ENTER in the field is the same as pressing OK, which is what every text box in every dialog
	# has done since dialogs existed.
	_input.text_submitted.connect(_on_submitted)
	box.add_child(_input)

	_list = ItemList.new()
	_list.visible = false
	_list.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(LIST_HEIGHT))
	# Double-click or ENTER on a row picks it, rather than forcing a trip to the OK button.
	_list.item_activated.connect(_on_activated)
	box.add_child(_list)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	_cancel = _button("CANCEL", _on_cancel)
	buttons.add_child(_cancel)
	buttons.add_child(_button("OK", _on_ok))


## The full-rect layer. `ShipBuilder` keeps its own reference to this because
## `tools/ship_visual_check.gd` reaches `_builder.get("_modal")` BY NAME (FOLLOWUPS F40 on
## tool-reached members) - so the member has to go on surviving whatever owns the dialog.
func layer() -> Control:
	return _layer


func is_open() -> bool:
	return _layer != null and _layer.visible


## What the dialog is saying, for the windowed checks - `tools/ship_visual_check.gd` asserts on a
## refusal's wording, which is the only way it can tell a refusal from a step that did nothing.
func title_text() -> String:
	return _title.text if _title != null else ""


func body_text() -> String:
	return _body.text if _body != null else ""


## Raise the dialog. [param cb] receives the entered String for PROMPT and the picked row's text
## for LIST; it is NOT called when the dialog is cancelled, and MESSAGE never calls it at all.
func open(
	title: String,
	body: String,
	mode: int,
	cb: Callable,
	items: PackedStringArray,
	default_text: String
) -> void:
	if _layer == null:
		return
	_mode = mode
	_cb = cb
	_title.text = title
	_body.text = body
	_input.visible = mode == Mode.PROMPT
	_input.text = default_text
	_list.visible = mode == Mode.LIST
	_list.clear()
	for item: String in items:
		_list.add_item(item)
	_cancel.visible = mode != Mode.MESSAGE
	_layer.visible = true
	if mode == Mode.PROMPT:
		_input.grab_focus()
		_input.select_all()


func close() -> void:
	if _layer != null:
		_layer.visible = false
	_cb = Callable()


## ENTER commits, ESCAPE backs out. Returns true when the key was the dialog's, so the caller can
## mark the event handled.
##
## THE DIALOG HAD NO KEYBOARD AT ALL until 2026-09-27: `ShipBuilder._unhandled_key_input` returned
## early on a visible modal - correctly, so a hotkey cannot fire behind it - and nothing picked
## the keys up on the other side. Every dialog had to be finished with the mouse.
func handle_key(key: InputEventKey) -> bool:
	if key == null or not key.pressed or key.echo:
		return false
	if key.keycode == KEY_ESCAPE:
		# A message has only one way out, so Escape takes it rather than doing nothing.
		if _mode == Mode.MESSAGE:
			_on_ok()
		else:
			_on_cancel()
		return true
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_on_ok()
		return true
	return false


## The palette changed under us (ShipTheme.palette_changed).
func refresh_theme() -> void:
	if _dim != null:
		_dim.color = _dim_colour()


func _dim_colour() -> Color:
	if _theme == null:
		return Color(0.0, 0.0, 0.0, DIM_ALPHA)
	return _theme.color_for_role_a("background", DIM_ALPHA)


func _button(label: String, handler: Callable) -> Button:
	var out: Button = Button.new()
	out.text = label
	out.focus_mode = Control.FOCUS_NONE
	out.pressed.connect(handler)
	return out


func _on_submitted(_text: String) -> void:
	_on_ok()


func _on_activated(_index: int) -> void:
	_on_ok()


func _on_ok() -> void:
	var payload: String = ""
	if _mode == Mode.PROMPT:
		payload = _input.text
	elif _mode == Mode.LIST:
		var picked: PackedInt32Array = _list.get_selected_items()
		if picked.is_empty():
			return
		payload = _list.get_item_text(picked[0])
	var cb: Callable = _cb
	var mode: int = _mode
	close()
	if mode != Mode.MESSAGE and cb.is_valid():
		cb.call(payload)


func _on_cancel() -> void:
	close()
