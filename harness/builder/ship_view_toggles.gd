class_name ShipViewToggles
extends RefCounted
## The top bar's LAYER TOGGLES - the switches that change what the view DRAWS, never what the
## document holds. Nothing here touches a ShipDoc, so nothing here is undoable and nothing here
## makes a bake stale.
##
## A HOME OF THEIR OWN because `ship_builder.gd` stands at gdlint's two-thousand-line cap and its
## thirty-public-method cap at once, and `.gdlintrc` asks for a REAL seam rather than a split at
## whatever line the alarm happens to fire on: "A good extraction is a self-contained, statically
## testable unit with no reference back to the file it came from." These toggles are exactly that
## - each one forwards to the theme or the view and reads nothing of the builder's state - so the
## next one costs the builder no lines at all.
##
## THE VIEW ARRIVES SECOND. `_build_header()` runs before `_build_layout()` has made the
## ShipView3D, so the bar is built with the theme alone and [method use] hands the view over once
## it exists - the same shape [ShipExplodeControl] uses.

## Whether the WALLS layer starts shown. OFF, because the mode that gains most from the toggle is
## INTERIOR, whose whole purpose is looking into rooms (ADR 0046).
const WALLS_SHOWN: bool = false

var _theme: ShipTheme = null
var _view: ShipView3D = null
var _walls: CheckButton = null


func _init(bar: Container, theme: ShipTheme) -> void:
	_theme = theme
	var dither: CheckButton = _add(bar, "DITHER", true, _on_dither_toggled)
	dither.tooltip_text = "DITHER THE PALETTE QUANTIZER, OR BAND IT FLAT"
	_walls = _add(bar, "WALLS", WALLS_SHOWN, _on_walls_toggled)
	_walls.tooltip_text = "DRAW THE WALLS BETWEEN ROOMS, OR DROP THE LAYER AND SEE THE OPEN ROOM"


## The view, once it exists. Applies whatever the toggles already read.
func use(view: ShipView3D) -> void:
	_view = view
	_on_walls_toggled(_walls.button_pressed)


## The WALLS layer, from a tool or a test. Moves the button with it, so the bar never lies about
## what is on screen - which is why a caller should come through here rather than straight to
## [method ShipView3D.set_walls_hidden].
func set_walls_shown(on: bool) -> void:
	if _walls != null:
		_walls.button_pressed = on  # emits `toggled`, which is what applies it


## True while the WALLS layer is drawn.
func walls_shown() -> bool:
	return _walls != null and _walls.button_pressed


func _add(bar: Container, label: String, on: bool, handler: Callable) -> CheckButton:
	var b: CheckButton = CheckButton.new()
	b.text = label
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(handler)
	bar.add_child(b)
	return b


func _on_dither_toggled(on: bool) -> void:
	if _theme != null:
		_theme.set_dither(on)


func _on_walls_toggled(on: bool) -> void:
	if _view != null:
		_view.set_walls_hidden(not on)
