class_name ShipLayersControl
extends RefCounted
## THE LAYERS EXPLORER - one checkbox per thing the view can stop drawing, docked over the 3D
## view. The author, 2026-09-26:
##
## > "because of hatches i cannot tell if the walls are being built and overriding the hatches
## > visually. so i thought a layers explorer that lets the player hide hatches, walls,
## > [expandable later] type of stuff."
##
## So the point of it is DIAGNOSIS: with the walls off you can see whether the door was ever
## bored, and with the doors off you can see the wall it was bored through. Nothing here changes
## the document, nothing is undoable, and nothing makes a bake stale.
##
## EXPANDABLE IS THE REQUIREMENT, so a layer is one row of [constant LAYERS] and nothing else -
## a key, a label and a line of help. A new one costs one entry here plus whatever honours the
## key, which for a named surface of a baked piece is already written
## ([member ShipSceneBuilder.hidden_layers]).
##
## THE LAYERS ONLY EXIST ON A BAKED PIECE. A preview primitive has one unnamed surface, so the
## panel reads as inert until UPDATE MESHES or EXPLODE has run - which is honest, because until
## then there are no walls, cuts or doors to draw.

## Doors are whole nodes rather than a named surface, so this key has no `ShipCsgBake.SURFACE_*`
## to borrow and lives here, where the layer list does.
const LAYER_DOOR: String = "door"

## key, label, tooltip. Order is the order they are listed.
const LAYERS: Array = [
	[
		ShipCsgBake.SURFACE_WALL,
		"WALLS",
		"THE PLATE BETWEEN TWO ROOMS. OFF SHOWS THE OPEN ROOM THE PAIR WOULD OTHERWISE BE.",
	],
	[
		ShipCsgBake.SURFACE_CUT,
		"CUTS",
		"WHERE A PIECE WAS CUT FROM ITS NEIGHBOUR OR DICED FOR PRINTING - NOT A WALL.",
	],
	[
		LAYER_DOOR,
		"DOORS",
		"THE HATCH LEAVES. OFF LEAVES THE OPENING THEY SIT IN, SO THE BORE CAN BE SEEN.",
	],
]

## Which layers are drawn when the builder opens. WALLS start OFF, because a prebuild carries
## none by default (2026-09-26) and the mode that gains most from the switch is INTERIOR.
const SHOWN_AT_START: Dictionary = {
	ShipCsgBake.SURFACE_WALL: false,
	ShipCsgBake.SURFACE_CUT: true,
	LAYER_DOOR: true,
}

var _view: ShipView3D = null
var _overlay: Control = null
var _boxes: Dictionary = {}


## Docks the panel over [param frame] (the 3D view's frame), top left - the top right belongs to
## the explode options, which come and go; this one stays.
func _init(frame: Control, theme: ShipTheme) -> void:
	_overlay = Control.new()
	_overlay.name = "LayersLayer"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if frame != null:
		frame.add_child(_overlay)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "LayersPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var margin: float = ShipTheme.pxf(6.0)
	panel.offset_left = margin
	panel.offset_top = margin
	if theme != null:
		panel.theme = theme.build_theme()
	_overlay.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var title: Label = Label.new()
	title.text = "LAYERS"
	title.add_theme_font_size_override("font_size", ShipTheme.font_small())
	box.add_child(title)
	for layer: Array in LAYERS:
		_boxes[layer[0]] = _row(box, layer)


## The view, once it exists - `_build_header` runs before `_build_layout` has made it, the same
## way [ShipViewToggles] and [ShipExplodeControl] are wired.
func use(view: ShipView3D) -> void:
	_view = view
	_apply()


## Whether [param layer] is drawn, for a tool or a test; moves the box with it so the panel never
## lies about what is on screen.
func set_layer_shown(layer: String, on: bool) -> void:
	if _boxes.has(layer):
		(_boxes[layer] as CheckBox).button_pressed = on


## Every layer that is NOT drawn.
func hidden() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for layer: Array in LAYERS:
		var box: CheckBox = _boxes[layer[0]]
		if not box.button_pressed:
			out.append(layer[0])
	return out


func _row(box: VBoxContainer, layer: Array) -> CheckBox:
	var check: CheckBox = CheckBox.new()
	check.text = str(layer[1])
	check.tooltip_text = str(layer[2])
	check.button_pressed = bool(SHOWN_AT_START.get(layer[0], true))
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", ShipTheme.font_small())
	check.toggled.connect(_on_toggled)
	box.add_child(check)
	return check


func _on_toggled(_on: bool) -> void:
	_apply()


func _apply() -> void:
	if _view != null:
		_view.set_hidden_layers(hidden())
