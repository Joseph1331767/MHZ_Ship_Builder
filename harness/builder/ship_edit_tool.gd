class_name ShipEditTool
extends RefCounted
## THE EDIT MENU - which verb you are editing with, and therefore which handles are on the part.
##
## The author, 2026-09-27, after a stretch drag inside a picked-up part turned into a move:
##
## > "instead of all editing handles existing, we should have a menu in top left under layers and
## > alignment thats titled 'edit'. and under those edit options should be scale, position,
## > orientation, distance from parent, etc. and when one is selected its handles appear."
##
## ELEVEN HANDLES ON ONE PART IS THE BUG UNDER THE OTHER TWO NOTES. Three rings, six stretch
## arrows, an offset stalk and a placement collar all share the same few hundred pixels, so two
## verbs meet on one pixel and a grab means whichever the hit test tries first. That is how
## "grabbing the scalling handles" ended in "the item moves from its attachment" and in "it
## changed the alignment of the piece" - the grab was never the verb they aimed at.
##
## THIS IS NOT THE TAB GATE COMING BACK. That one failed for three reasons `ShipHandles`' class
## docs record, and none of them is modality: the flag "lived in three places at once with
## different defaults, and a focus change silently turned the rings off", and the ball it revealed
## swallowed every grab. This mask has ONE owner, is on screen the whole time, changes only when
## clicked, and reveals nothing that was not already there.
##
## EVERYTHING stays as a choice, and it is the default - the author works with every handle live
## and asked for the current view to be preserved, so nothing is taken away by opening the app.

## Emitted after the mask changed, with the new `ShipHandles.TOOL_*` value.
signal changed(mask: int)

## Label, tooltip, and the `ShipHandles.TOOL_*` mask it selects.
const TOOLS: Array = [
	["EVERYTHING", "EVERY HANDLE AT ONCE, THE WAY IT HAS ALWAYS BEEN", ShipHandles.TOOL_ALL],
	["MOVE", "SLIDE THE PART OVER ITS PARENT - THE COLLAR ROUND ITS BASE", ShipHandles.TOOL_MOVE],
	["TURN", "THE THREE RINGS, ONE PER AXIS", ShipHandles.TOOL_TURN],
	["SCALE", "THE SIX ARROWS OUT OF ITS FACES", ShipHandles.TOOL_STRETCH],
	["LIFT", "DISTANCE FROM ITS PARENT - THE STALK ALONG THE MOUNT NORMAL", ShipHandles.TOOL_LIFT],
]

var _view: ShipView3D = null
var _buttons: Array[Button] = []
var _chosen: int = 0


## Docks under [param frame]'s top-left, below the layers panel. [param below] is how far down to
## start, in DESIGN pixels, so the two panels stack without either knowing the other's height.
func _init(frame: Control, theme: ShipTheme, below: float) -> void:
	var overlay: Control = Control.new()
	overlay.name = "EditToolLayer"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if frame != null:
		frame.add_child(overlay)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "EditToolPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = ShipTheme.pxf(6.0)
	panel.offset_top = ShipTheme.pxf(below)
	if theme != null:
		panel.theme = theme.build_theme()
	overlay.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = "EDIT"
	title.add_theme_font_size_override("font_size", ShipTheme.font_small())
	box.add_child(title)
	for i: int in TOOLS.size():
		var row: Array = TOOLS[i]
		var b: Button = Button.new()
		b.name = "EditTool%d" % i
		b.text = str(row[0])
		b.tooltip_text = str(row[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", ShipTheme.font_small())
		b.pressed.connect(_on_pressed.bind(i))
		box.add_child(b)
		_buttons.append(b)
	_light()


## The view, once it exists - `_build_header` runs before `_build_layout` has made it.
func use(view: ShipView3D) -> void:
	_view = view
	_apply()


## The `ShipHandles.TOOL_*` mask in force.
func mask() -> int:
	return int((TOOLS[_chosen] as Array)[2])


## Choose a verb by its row, for a tool or a test; moves the button with it.
func choose(index: int) -> void:
	if index < 0 or index >= TOOLS.size():
		return
	_chosen = index
	_light()
	_apply()
	changed.emit(mask())


func _on_pressed(index: int) -> void:
	choose(index)


func _light() -> void:
	for i: int in _buttons.size():
		_buttons[i].button_pressed = i == _chosen


func _apply() -> void:
	if _view != null:
		_view.set_edit_tools(mask())
