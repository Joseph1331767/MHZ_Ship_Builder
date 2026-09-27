class_name ShipUiMode
extends RefCounted
## HOW MUCH OF THE BUILDER IS ON SCREEN. Four rungs, and each one shows everything the rung below
## it shows plus its own - so moving up never takes anything away, and a player who learns BASIC
## never has to unlearn it.
##
## The author, 2026-09-27: "a super simple view, a more advanced view, and an expert advanced view
## mode", and then, after seeing the first build: "keep the current view as 'dev working view' and
## ensure you complete the basic, moderate, and advanced views of the software (we may cull some
## views later if the easiest view is just as composable as the rest)."
##
## DEV IS TODAY'S UI, UNTOUCHED. That is what makes this safe to land: the view the author works in
## every day is a rung of the ladder rather than something replaced by it, so a mistake in the
## other three costs a click to escape and nothing else. It is also the honest name - everything in
## it exists because a developer needed it, not because a player did.
##
## WHY A WHOLE PANEL AND NOT A FIELD. This rung only hides and shows whole panels, columns and
## toolbar buttons. Hiding SECTIONS INSIDE a panel is the next step and belongs to the panels
## themselves - `harness/panels/` is the other agent's lane (AGENTS section 6), so it goes in one
## contiguous handoff rather than interleaved with this.
##
## THE COLUMN CARRIES THE WIDTH, NOT THE PANEL. `LEFT_WIDTH` and `RIGHT_WIDTH` are
## `custom_minimum_size` on the COLUMNS (`ship_builder.gd:1132`, `:1155`), so hiding every panel
## inside a column leaves an empty gutter exactly as wide as it was. The width has to move with the
## rung or BASIC is a narrow view of a ship with two grey bars beside it.

## Emitted after the rung changed and the layout was applied, so a panel can follow.
signal changed(level: int)

enum Level { BASIC, MODERATE, ADVANCED, DEV }

const LEVEL_NAMES: Array = ["BASIC", "MODERATE", "ADVANCED", "DEV"]

## One line per rung, for the button's tooltip - what you get, in the player's terms.
const LEVEL_HINTS: Array = [
	"JUST BUILD: THE SHAPES AND THE SHIP. NOTHING ELSE ON SCREEN.",
	"ADDS THE PART LIST, THE NUMBERS FOR THE SELECTED PART, AND THE BUDGETS.",
	"ADDS THE LINKS, THE ROOM TOOLS, THE RENDER TYPES AND THE BAKE.",
	"EVERYTHING, INCLUDING THE TOOLS ONLY A DEVELOPER NEEDS.",
]

## The lowest rung each named node appears at. A node absent from here is shown at every rung,
## which is the right default: a new control is visible until someone decides it is not.
##
## Keyed by NODE NAME, and every one of these is set where the node is built - the slot frames by
## `_make_slot_panel`, the buttons by `_make_button`. Matching on a button's TEXT would break the
## moment EXPLODE reads ASSEMBLE or ROOMS reads WHOLE.
const SHOWN_FROM: Dictionary = {
	# The left column: shapes first, because placing one is the whole of the first minute.
	"PartPaletteSlotFrame": Level.BASIC,
	"TreeSlotFrame": Level.MODERATE,
	# The right column and the strip under the view.
	"InspectorSlotFrame": Level.MODERATE,
	"GaugeSlotFrame": Level.MODERATE,
	# The toolbar, verb by verb.
	"NEW": Level.BASIC,
	"OPEN": Level.BASIC,
	"SAVE": Level.BASIC,
	"UNDO": Level.BASIC,
	"REDO": Level.BASIC,
	"HELP": Level.BASIC,
	"FRAME": Level.BASIC,
	"EXPLODE": Level.MODERATE,
	"EDIT": Level.MODERATE,
	"UPDATE MESHES": Level.MODERATE,
	"ROOMS: PIECES": Level.ADVANCED,
	"BAKE": Level.ADVANCED,
	"DITHER": Level.ADVANCED,
	"RenderTypeOption": Level.ADVANCED,
	# The whole layers explorer, not its rows: it is a diagnostic for someone asking why a face is
	# there, which is not a question a child has.
	"LayersPanel": Level.ADVANCED,
}

## Left and right column widths per rung, in DESIGN pixels. BASIC gives the right column nothing,
## because every panel in it is hidden and the gutter would be the only thing left of it.
const COLUMN_WIDTH: Array = [
	Vector2(212.0, 0.0),
	Vector2(236.0, 292.0),
	Vector2(236.0, 292.0),
	Vector2(236.0, 292.0),
]

var level: int = Level.DEV:
	set = _set_level

var _root: Control = null
var _buttons: Array[Button] = []


## Builds the rung picker into [param bar] - the header row. The layout arrives later through
## [method use], because `_build_header()` runs before `_build_layout()` has made any of it.
func _init(bar: Container, theme: ShipTheme) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "UiModeTabs"
	row.add_theme_constant_override("separation", 0)
	if bar != null:
		bar.add_child(row)
	for i: int in LEVEL_NAMES.size():
		var b: Button = Button.new()
		b.name = "UiMode%d" % i
		b.text = str(LEVEL_NAMES[i])
		b.tooltip_text = str(LEVEL_HINTS[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", ShipTheme.font_small())
		b.pressed.connect(_on_pressed.bind(i))
		row.add_child(b)
		_buttons.append(b)
	if theme != null:
		row.theme = theme.build_theme()


## The built layout to drive.
##
## OPENS ON DEV, EVERY RUN, and deliberately does not remember. Persisting the rung would mean a
## run that ended in BASIC opens the next one in BASIC - including a run of
## `tools/ship_visual_check.gd`, which asserts against panels that BASIC hides, so the gate would
## start failing for a reason nowhere near the change that caused it. Remembering is worth having
## and belongs with the hint bar, where there is a place to say which rung you are in.
func use(root: Control) -> void:
	_root = root
	_apply()
	_light()


## Whether [param key] is on screen at the current rung. Anything unlisted is shown - a control
## nobody has tiered yet is a control everybody sees, which fails visible rather than silent.
func shows(key: String) -> bool:
	return level >= int(SHOWN_FROM.get(key, Level.BASIC))


static func name_of(value: int) -> String:
	if value < 0 or value >= LEVEL_NAMES.size():
		return ""
	return str(LEVEL_NAMES[value])


func _on_pressed(index: int) -> void:
	level = index


func _set_level(value: int) -> void:
	var next: int = clampi(value, 0, LEVEL_NAMES.size() - 1)
	if next == level and _root != null:
		return
	level = next
	_apply()
	_light()
	changed.emit(level)


## Hide what this rung does not show, and move the column widths with it.
func _apply() -> void:
	if _root == null:
		return
	for key: String in SHOWN_FROM:
		# THROUGH validate_node_name, because Godot strips characters a label may carry: the node
		# built as "ROOMS: PIECES" is really named "ROOMS PIECES", so looking it up by its label
		# silently found nothing and the button stayed on screen at every rung.
		var node: Node = _root.find_child(key.validate_node_name(), true, false)
		if node is CanvasItem:
			(node as CanvasItem).visible = shows(key)
	var width: Vector2 = COLUMN_WIDTH[level]
	_set_column("LeftColumn", width.x)
	_set_column("RightColumn", width.y)


func _set_column(node_name: String, width: float) -> void:
	var column: Control = _root.find_child(node_name, true, false) as Control
	if column != null:
		column.custom_minimum_size = Vector2(ShipTheme.pxf(width), 0.0)


func _light() -> void:
	for i: int in _buttons.size():
		_buttons[i].button_pressed = i == level
