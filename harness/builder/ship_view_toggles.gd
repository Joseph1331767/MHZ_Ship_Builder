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
## RETIRED(2026-09-26): the WALLS switch, which lived here for one day. It moved to
## [ShipLayersControl] the moment there was more than one layer to drop, because the author asked
## for "a layers explorer that lets the player hide hatches, walls, [expandable later]" and three
## more check buttons in a bar that already holds eleven is not an explorer. DITHER stays: it is a
## render setting, not a layer.

var _theme: ShipTheme = null


func _init(bar: Container, theme: ShipTheme) -> void:
	_theme = theme
	var dither: CheckButton = _add(bar, "DITHER", true, _on_dither_toggled)
	dither.tooltip_text = "DITHER THE PALETTE QUANTIZER, OR BAND IT FLAT"


func _add(bar: Container, label: String, on: bool, handler: Callable) -> CheckButton:
	var b: CheckButton = CheckButton.new()
	# Named, so [ShipUiMode] can tier it - a control built by hand gets no name from Godot.
	b.name = label
	b.text = label
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(handler)
	bar.add_child(b)
	return b


func _on_dither_toggled(on: bool) -> void:
	if _theme != null:
		_theme.set_dither(on)
