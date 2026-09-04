class_name ShipContextMenu
extends Control

## The right-click menu, as an IN-SCENE Control (ADR 0009).
##
## "id like to be able to select 2 shapes, right click them and have 3 options for seem, parent
## indents child > child indents parent > and flat plane at intersection."
##
## NOT A PopupMenu, and not for a stylistic reason. SPEC section 10 is a CONTRACT: the whole
## builder ends up on a quad in MHZ_Origins, driven by `Viewport.push_input()`, and a native
## popup is a Window - it would simply not exist on the texture the player sees. Every dialog in
## this project is a Control for that reason, and a context menu is a dialog that happens to open
## where the pointer is.
##
## Full-rect and MOUSE_FILTER_STOP so a click anywhere outside the little panel dismisses it,
## which is what a menu is expected to do and is also what keeps it from stranding itself over
## the 3D view. Escape closes it too.

## A menu item was chosen. `id` is whatever the caller put in the item.
signal chosen(id: String)
## Closed with nothing chosen.
signal dismissed

## Margin, in DESIGN pixels, kept between the panel and the edge of this Control, so a menu
## opened near a corner stays fully on screen.
const EDGE_MARGIN_PX: float = 6.0

## Metadata key carrying an item's id on its button, so a driver can find and press one by id
## without knowing the order they were built in.
const ITEM_META: String = "mhz_item_id"

var _theme_ref: ShipTheme = null
var _frame: PanelContainer = null
var _items: VBoxContainer = null
var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_frame = PanelContainer.new()
	_frame.name = "MenuFrame"
	# Not anchored: the position is set per open() and must not be overwritten by a preset.
	add_child(_frame)

	_items = VBoxContainer.new()
	_frame.add_child(_items)


func setup(ship_theme: ShipTheme) -> void:
	_theme_ref = ship_theme


## Open at `at` (this Control's coordinates) with `title` over `items`, each `{"id", "label"}`,
## and `marked` the id to show as the current one. Rebuilt every time: a context menu is small
## and its contents depend on what was right-clicked.
func open(at: Vector2, title: String, items: Array[Dictionary], marked: String) -> void:
	for child: Node in _items.get_children():
		child.queue_free()
	_buttons.clear()

	var heading: Label = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", ShipTheme.font_small())
	if _theme_ref != null:
		heading.add_theme_color_override("font_color", _theme_ref.color_for_role("text_dim"))
	_items.add_child(heading)
	_items.add_child(HSeparator.new())

	for item: Dictionary in items:
		# A `header` entry groups the choices under it. The seam styles are two independent axes
		# and reading them as six unrelated names is what the headings exist to prevent.
		if item.has("header"):
			var group: Label = Label.new()
			group.text = str(item["header"])
			group.add_theme_font_size_override("font_size", ShipTheme.font_small())
			if _theme_ref != null:
				group.add_theme_color_override("font_color", _theme_ref.color_for_role("text_dim"))
			_items.add_child(group)
			continue
		var id: String = str(item.get("id", ""))
		var button: Button = Button.new()
		# The current choice is marked rather than disabled: a player needs to see which one is
		# already in force, and pressing it again is harmless.
		button.text = ("> " if id == marked else "  ") + str(item.get("label", id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_meta(ITEM_META, id)
		button.pressed.connect(_on_item_pressed.bind(id))
		_items.add_child(button)
		_buttons.append(button)

	visible = true
	# Placed after a layout pass, so the frame's real size is known and a menu near the right or
	# bottom edge can be pulled back inside instead of hanging off it.
	await get_tree().process_frame
	if not visible:
		return
	var margin: float = ShipTheme.pxf(EDGE_MARGIN_PX)
	var frame_size: Vector2 = _frame.get_combined_minimum_size()
	var limit: Vector2 = size - frame_size - Vector2(margin, margin)
	_frame.position = Vector2(
		clampf(at.x, margin, maxf(limit.x, margin)), clampf(at.y, margin, maxf(limit.y, margin))
	)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## Item ids in the order they are shown, for a check that drives this panel.
func item_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for button: Button in _buttons:
		out.append(str(button.get_meta(ITEM_META, "")))
	return out


## Press one item by id, as a click would. Returns false when there is no such item.
func press(id: String) -> bool:
	for i: int in _buttons.size():
		if str(_buttons[i].get_meta(ITEM_META, "")) == id:
			_on_item_pressed(id)
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	# A press anywhere this Control still sees is a press OUTSIDE the frame - the buttons eat
	# their own - so it dismisses.
	if mb != null and mb.pressed:
		accept_event()
		close()
		dismissed.emit()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		accept_event()
		close()
		dismissed.emit()


func _on_item_pressed(id: String) -> void:
	close()
	chosen.emit(id)
