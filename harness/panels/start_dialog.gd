## ShipStartDialog - the first thing a player sees: pick the primitive the ship is founded on.
##
## RETIRED(2026-09-01): ShipBuilder._new_document() founding every ship on `family_ids()[0]`.
## That is why the console "auto started with a block again instead of letting player choose
## starting choice" - box_hull is simply first in the pack, so the choice was being made by JSON
## key order. NEW now raises this, and nothing exists until a choice is made.
##
## THE ROOT IS SIZED, NOT UNIT-SCALED. A freshly founded root is scaled so its widest bounding-box
## axis is `ShipConfig.root_span_m` (5 m by default, a dev lever in data/tuning.json), rather than
## whatever the family happened to author as its base_size. Without that, founding on a sphere_pod
## gave a 2 m ship and founding on a torus_ring gave a 4 m one, and the player's first impression
## of scale depended on which icon they clicked.
##
## IN-SCENE CONTROL, NEVER A Window (AGENTS section 7). This is a full-rect Control layered over
## the console, so it exists on the device's texture. An AcceptDialog would render into an OS
## window that does not exist in-game and the player would face a console that never starts.
##
## Only root-capable families are offered. `can_be_root` is the pack's own statement about which
## shapes may found a ship (Spore's body/chassis distinction), and a start list that offered a
## shape the document model then refuses would be a dead-end dialog.
##
## TWO WAYS IN. A ship starts either from one PRIMITIVE or from a stock TEMPLATE - the atom and
## molecule hulls in `data/templates.json`, rooms joined by tunnels with a hatch at every
## connection. The template side exposes exactly the four levers the brief names as controllable:
## room shape, hallway shape, tunnel length and room size (plus tunnel bore, which is the other
## half of "skinny tunnels"). They default from `data/tuning.json` and are handed to
## [method ShipTemplates.build] verbatim.
class_name ShipStartDialog
extends Control

## The chosen family and manufacturer. ShipBuilder founds the document from these.
signal chosen(family_id: String, manufacturer_id: String)
## A stock template plus the room/hallway/size options the player set.
signal template_chosen(template_id: String, options: Dictionary)
## Raised only when the dialog was cancellable, i.e. there was already a ship to go back to.
signal cancelled

## No ship at all: the console opens empty and the FIRST PART the player picks founds it.
##
## The author, asking for the third time: "im still forced to pick a part at start, there should be
## an option for blank, as i keep suggesting." The full version of that ask - an invisible root
## node the first part attaches to - is a change to what a `ShipDoc` IS and wants an ADR; this is
## the half that needs neither, because a null document is already a state the builder handles
## (`ship_builder.gd:828`, the no-families console).
signal blank_chosen

const PANEL_WIDTH: float = 440.0
## Room for about eight template rows before the list scrolls. Sixteen elements plus six molecules
## is a real list, and a chooser that shows two of them at a time reads as an error.
const TEMPLATE_LIST_HEIGHT: float = 150.0
const CELL_SIZE: float = 56.0
const GRID_COLUMNS: int = 4
const GLYPH_INSET: float = 10.0

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null

var _grid: GridContainer = null
var _cells: Array[Button] = []
var _families: PackedStringArray = PackedStringArray()
var _picker: OptionButton = null
var _detail: Label = null
var _start_button: Button = null
var _cancel_button: Button = null
var _picked: String = ""
var _can_cancel: bool = false

var _mode_primitive: Button = null
var _mode_template: Button = null
var _primitive_box: VBoxContainer = null
var _template_box: VBoxContainer = null
var _template_list: ItemList = null
var _template_ids: PackedStringArray = PackedStringArray()
var _template_detail: Label = null
var _room_picker: OptionButton = null
var _electron_picker: OptionButton = null
var _proton_blend: OptionButton = null
var _electron_blend: OptionButton = null
var _link_picker: OptionButton = null
var _hall_picker: OptionButton = null
var _room_span: NumericField = null
var _tunnel_length: NumericField = null
var _tunnel_bore: NumericField = null
var _template_mode: bool = false


func setup(builder: ShipBuilder) -> void:
	_builder = builder
	_ship_theme = builder.get_ship_theme()
	if _ship_theme != null and not _ship_theme.palette_changed.is_connected(_on_palette_changed):
		_ship_theme.palette_changed.connect(_on_palette_changed)
	_build()


## Shows the chooser. `can_cancel` is false on the very first launch, where there is no document
## to fall back to and a CANCEL would leave the console empty and inert.
func open(can_cancel: bool) -> void:
	_can_cancel = can_cancel
	if _cancel_button != null:
		_cancel_button.visible = can_cancel
	_refresh_families()
	_refresh_templates()
	_apply_mode()
	visible = true
	if _start_button != null:
		_start_button.grab_focus()


func close() -> void:
	visible = false


# ---------------------------------------------------------------- construction


func _build() -> void:
	name = "StartLayer"
	# set_anchors_AND_OFFSETS_preset, not set_anchors_preset. The latter PRESERVES the control's
	# current rect by recomputing its offsets, so a node anchored after it was already parented at
	# zero size stays at zero size: full-rect anchors, a 0x0 rect, and a chooser drawn in the top
	# left corner over the palette with no dim behind it. Measured, not guessed - diag printed
	# `StartLayer: rect=[P: (0,0), S: (0,0)] anchors=(0,0,1,1)`.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = _role_a("background", 0.88)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(ShipTheme.pxf(PANEL_WIDTH), 0.0)
	center.add_child(frame)

	var box: VBoxContainer = VBoxContainer.new()
	frame.add_child(box)

	var title: Label = Label.new()
	title.text = "CHOOSE A STARTING MODULE"
	title.add_theme_font_size_override("font_size", ShipTheme.font_title())
	box.add_child(title)
	box.add_child(HSeparator.new())

	# BLANK FIRST, and outside the two modes, because it is not a third way to choose a hull - it
	# is the choice not to.
	var blank: Button = Button.new()
	blank.name = "StartBlank"
	blank.text = "START BLANK"
	blank.tooltip_text = "OPEN AN EMPTY SHIPYARD - THE FIRST PART YOU PICK BECOMES THE SHIP"
	blank.focus_mode = Control.FOCUS_NONE
	blank.pressed.connect(_on_blank_pressed)
	box.add_child(blank)

	var mode_row: HBoxContainer = HBoxContainer.new()
	box.add_child(mode_row)
	_mode_primitive = Button.new()
	_mode_primitive.text = "ONE PRIMITIVE"
	_mode_primitive.toggle_mode = true
	_mode_primitive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_primitive.pressed.connect(_on_mode_pressed.bind(false))
	mode_row.add_child(_mode_primitive)
	_mode_template = Button.new()
	_mode_template.text = "STOCK TEMPLATE"
	_mode_template.toggle_mode = true
	_mode_template.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_template.pressed.connect(_on_mode_pressed.bind(true))
	mode_row.add_child(_mode_template)

	_primitive_box = VBoxContainer.new()
	box.add_child(_primitive_box)

	var blurb: Label = Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", ShipTheme.font_small())
	blurb.text = (
		"EVERY SHIP IS FOUNDED ON ONE PRIMITIVE. PICK ITS SHAPE AND ITS YARD - "
		+ "BOTH STAY EDITABLE AFTERWARDS."
	)
	_primitive_box.add_child(blurb)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_primitive_box.add_child(_grid)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_primitive_box.add_child(_detail)

	var picker_row: HBoxContainer = HBoxContainer.new()
	_primitive_box.add_child(picker_row)
	var picker_label: Label = Label.new()
	picker_label.text = "YARD"
	picker_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	picker_row.add_child(picker_label)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.item_selected.connect(_on_manufacturer_selected)
	picker_row.add_child(_picker)

	_build_template_box(box)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	buttons.add_child(_cancel_button)
	_start_button = Button.new()
	_start_button.text = "START"
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)


## The stock-template side: the catalogue, its description, and the four shape/size levers the
## brief names. Sizes seed from ShipConfig so the shipped defaults really are "the smallest room
## module" without this panel hardcoding a number.
func _build_template_box(box: VBoxContainer) -> void:
	_template_box = VBoxContainer.new()
	_template_box.visible = false
	box.add_child(_template_box)

	var blurb: Label = Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", ShipTheme.font_small())
	blurb.text = (
		"STOCK HULLS: ROOMS JOINED BY TUNNELS, WITH A HATCH AT EVERY CONNECTION. "
		+ "EACH ONE MODELS AN ATOM OR A MOLECULE AND TAKES ITS NAME."
	)
	_template_box.add_child(blurb)

	_template_list = ItemList.new()
	_template_list.custom_minimum_size = Vector2(0.0, ShipTheme.pxf(TEMPLATE_LIST_HEIGHT))
	_template_list.item_selected.connect(_on_template_selected)
	_template_box.add_child(_template_list)

	_template_detail = Label.new()
	_template_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_template_detail.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_template_box.add_child(_template_detail)

	# A SHAPE PER GROUP (dev note 2026-09-24): "the player options for the prebuilt structures need
	# expanding with options for outter/electron node shapes, tunnel shapes, proton shapes", each
	# with a second shape blended through the cluster - "so a protons shapes can be shape1 and
	# shape2 ... so a proton cluster can exist with cubes and spheres blended".
	_room_picker = _shape_row("PROTON SHAPE")
	_proton_blend = _shape_row("  + BLEND")
	_electron_picker = _shape_row("ELECTRON SHAPE")
	_electron_blend = _shape_row("  + BLEND")
	_hall_picker = _shape_row("TUNNEL SHAPE")

	var cfg: ShipConfig = _builder.get_config() if _builder != null else ShipConfig.defaults()
	_room_span = _size_row("ROOM SIZE", 0.5, 40.0, cfg.room_span_m)
	_tunnel_length = _size_row("TUNNEL LEN", 0.0, 40.0, cfg.tunnel_length_m)
	_tunnel_bore = _size_row("TUNNEL BORE", 0.2, 10.0, cfg.tunnel_bore_m)
	_link_picker = _link_row()


## One labelled family picker. Lists every family, not only root-capable ones: a tunnel is never
## the root, and a family that cannot found a ship can still be a corridor.
func _shape_row(label_text: String) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	_template_box.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(ShipTheme.pxf(84.0), 0.0)
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(label)
	var picker: OptionButton = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(_on_template_option_changed)
	row.add_child(picker)
	return picker


## HOW EVERY CONNECTION IS LINKED. Open by default and listed first, because "by default in the
## prebuilds we dont want any walls in our prebuilds by default" (2026-09-26) - and the hatch is
## authored on every joint whichever of these is picked, so the other two cost nothing to choose
## later, one link at a time, in the seam menu.
func _link_row() -> OptionButton:
	var picker: OptionButton = _shape_row("LINKS")
	picker.add_item("OPEN - ONE ROOM, NO WALLS")
	picker.set_item_metadata(0, ShipJoint.MODE_OPEN)
	picker.add_item("HATCHED - A WALL WITH A DOOR")
	picker.set_item_metadata(1, ShipJoint.MODE_HATCHED)
	picker.add_item("SEALED - A SOLID WALL")
	picker.set_item_metadata(2, ShipJoint.MODE_SEALED)
	picker.select(0)
	return picker


func _size_row(label_text: String, low: float, high: float, value: float) -> NumericField:
	var field: NumericField = NumericField.new()
	_template_box.add_child(field)
	field.configure(label_text, low, high, 0.05, false)
	field.set_suffix(" m")
	field.set_value(value)
	if _ship_theme != null:
		field.bind_theme(_ship_theme)
	return field


# ---------------------------------------------------------------- contents


func _refresh_families() -> void:
	_families = _root_capable()
	for cell: Button in _cells:
		cell.queue_free()
	_cells.clear()
	for family_id: String in _families:
		var cell: Button = Button.new()
		cell.custom_minimum_size = Vector2(ShipTheme.pxf(CELL_SIZE), ShipTheme.pxf(CELL_SIZE))
		cell.flat = true
		cell.tooltip_text = _label_of(family_id)
		cell.pressed.connect(_on_cell_pressed.bind(family_id))
		cell.draw.connect(_on_cell_draw.bind(cell, family_id))
		_grid.add_child(cell)
		_cells.append(cell)
	if _picked == "" or not _families.has(_picked):
		_picked = _families[0] if not _families.is_empty() else ""
	_refresh_manufacturers()
	_refresh_detail()
	_redraw_cells()


func _refresh_templates() -> void:
	if _template_list == null:
		return
	var data: ShipData = _builder.get_data() if _builder != null else null
	_template_list.clear()
	_template_ids = ShipTemplates.ids(data) if data != null else PackedStringArray()
	for tid: String in _template_ids:
		_template_list.add_item(
			(
				"%s   (%d PARTS)"
				% [ShipTemplates.label_of(data, tid), ShipTemplates.part_count(data, tid)]
			)
		)
	if _template_list.item_count > 0:
		_template_list.select(0)
	_fill_shape_pickers()
	_refresh_template_detail()


## Both family pickers list every family in the pack. The room picker defaults to the first
## root-capable one and the tunnel picker to the first CYLINDER, which is what the brief calls a
## hallway - but both stay free, because "what shape for rooms, what shape for hallways" is one of
## the four levers the author asked to be able to turn.
func _fill_shape_pickers() -> void:
	var data: ShipData = _builder.get_data() if _builder != null else null
	if data == null or _room_picker == null or _hall_picker == null:
		return
	if _electron_picker == null or _proton_blend == null or _electron_blend == null:
		return
	if _room_picker.item_count > 0:
		return
	var families: PackedStringArray = data.family_ids()
	# A BLEND PICKER LEADS WITH "NONE", so its indices run one ahead of the plain ones.
	for blend: OptionButton in [_proton_blend, _electron_blend]:
		blend.add_item("- NONE -")
		blend.set_item_metadata(0, "")
	var tube: int = 0
	for i: int in families.size():
		var fid: String = families[i]
		var label: String = _label_of(fid).to_upper()
		for picker: OptionButton in [_room_picker, _electron_picker, _hall_picker]:
			picker.add_item(label)
			picker.set_item_metadata(i, fid)
		for blend: OptionButton in [_proton_blend, _electron_blend]:
			blend.add_item(label)
			blend.set_item_metadata(i + 1, fid)
		if _base_of(fid) == "CYLINDER":
			tube = i
	var room_default: int = 0
	for i: int in families.size():
		if _root_capable().has(families[i]):
			room_default = i
			break
	_room_picker.select(room_default)
	_electron_picker.select(room_default)
	_proton_blend.select(0)
	_electron_blend.select(0)
	_hall_picker.select(tube)


func _refresh_template_detail() -> void:
	if _template_detail == null:
		return
	var data: ShipData = _builder.get_data() if _builder != null else null
	var tid: String = _selected_template()
	if data == null or tid.is_empty():
		_template_detail.text = "NO TEMPLATES IN data/templates.json"
		return
	_template_detail.text = ShipTemplates.description_of(data, tid)


func _selected_template() -> String:
	if _template_list == null:
		return ""
	var picked: PackedInt32Array = _template_list.get_selected_items()
	if picked.is_empty() or picked[0] >= _template_ids.size():
		return ""
	return _template_ids[picked[0]]


func _template_options() -> Dictionary:
	return {
		# OPT_ROOM_FAMILY stays the fallback both node groups resolve against, so it carries the
		# proton shape: a template asked for only that still builds the ship it always did.
		ShipTemplates.OPT_ROOM_FAMILY: _picker_id(_room_picker),
		ShipTemplates.OPT_PROTON_FAMILY: _picker_id(_room_picker),
		ShipTemplates.OPT_PROTON_FAMILY_B: _picker_id(_proton_blend),
		ShipTemplates.OPT_ELECTRON_FAMILY: _picker_id(_electron_picker),
		ShipTemplates.OPT_ELECTRON_FAMILY_B: _picker_id(_electron_blend),
		ShipTemplates.OPT_HALL_FAMILY: _picker_id(_hall_picker),
		ShipTemplates.OPT_ROOM_SPAN: _room_span.get_value() if _room_span != null else 0.0,
		ShipTemplates.OPT_TUNNEL_LENGTH:
		_tunnel_length.get_value() if _tunnel_length != null else 0.0,
		ShipTemplates.OPT_TUNNEL_BORE: _tunnel_bore.get_value() if _tunnel_bore != null else 0.0,
		ShipTemplates.OPT_LINK_MODE: _picker_id(_link_picker),
	}


func _picker_id(picker: OptionButton) -> String:
	if picker == null or picker.selected < 0:
		return ""
	var meta: Variant = picker.get_item_metadata(picker.selected)
	return String(meta) if meta is String else ""


func _apply_mode() -> void:
	if _primitive_box != null:
		_primitive_box.visible = not _template_mode
	if _template_box != null:
		_template_box.visible = _template_mode
	if _mode_primitive != null:
		_mode_primitive.button_pressed = not _template_mode
	if _mode_template != null:
		_mode_template.button_pressed = _template_mode


func _refresh_manufacturers() -> void:
	if _picker == null:
		return
	_picker.clear()
	var data: ShipData = _builder.get_data() if _builder != null else null
	if data == null or _picked == "":
		return
	for mid: String in data.manufacturers_for(_picked):
		_picker.add_item(_manufacturer_label(data, mid))
		_picker.set_item_metadata(_picker.item_count - 1, mid)
	if _picker.item_count > 0:
		_picker.select(0)


func _refresh_detail() -> void:
	if _detail == null:
		return
	if _picked == "":
		_detail.text = "NO ROOT-CAPABLE FAMILY IN data/shapes/families.json"
		return
	_detail.text = (
		"%s - STARTS AT %s m ACROSS\n%s"
		% [_label_of(_picked).to_upper(), String.num(_root_span(), 1), _description_of(_picked)]
	)


func _redraw_cells() -> void:
	for cell: Button in _cells:
		cell.queue_redraw()


func _on_cell_draw(cell: Button, family_id: String) -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, cell.size)
	var tint: Color = _role("text")
	if family_id == _picked:
		tint = _role("selection")
		cell.draw_rect(rect, tint, false, 1.0)
	else:
		cell.draw_rect(rect, _role("line"), false, 1.0)
	PartPalettePanel.draw_glyph(
		cell, rect.grow(-ShipTheme.pxf(GLYPH_INSET)), _base_of(family_id), tint
	)


# ---------------------------------------------------------------- input


func _on_cell_pressed(family_id: String) -> void:
	_picked = family_id
	_refresh_manufacturers()
	_refresh_detail()
	_redraw_cells()


func _on_manufacturer_selected(_index: int) -> void:
	_refresh_detail()


func _on_blank_pressed() -> void:
	close()
	blank_chosen.emit()


func _on_mode_pressed(template_mode: bool) -> void:
	_template_mode = template_mode
	_apply_mode()


func _on_template_selected(_index: int) -> void:
	_refresh_template_detail()


func _on_template_option_changed(_index: int) -> void:
	_refresh_template_detail()


func _on_start_pressed() -> void:
	if _template_mode:
		var tid: String = _selected_template()
		if tid.is_empty():
			return
		var options: Dictionary = _template_options()
		close()
		template_chosen.emit(tid, options)
		return
	if _picked == "":
		return
	close()
	chosen.emit(_picked, _selected_manufacturer())


func _on_cancel_pressed() -> void:
	if not _can_cancel:
		return
	close()
	cancelled.emit()


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_redraw_cells()


# ---------------------------------------------------------------- pack readers


## Families the pack says may found a ship. A family that omits `can_be_root` is treated as
## capable, matching ShapeGen's "the family did not say" convention everywhere else.
func _root_capable() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var data: ShipData = _builder.get_data() if _builder != null else null
	if data == null:
		return out
	for family_id: String in data.family_ids():
		var entry: Dictionary = data.families.get(family_id, {}) as Dictionary
		var raw: Variant = entry.get("can_be_root", true)
		if raw is bool and not bool(raw):
			continue
		out.append(family_id)
	return out


func _selected_manufacturer() -> String:
	if _picker == null or _picker.selected < 0:
		return ""
	var meta: Variant = _picker.get_item_metadata(_picker.selected)
	return String(meta) if meta is String else ""


func _label_of(family_id: String) -> String:
	var entry: Dictionary = _family_entry(family_id)
	var raw: Variant = entry.get("label", family_id)
	return String(raw) if raw is String else family_id


func _description_of(family_id: String) -> String:
	var entry: Dictionary = _family_entry(family_id)
	var raw: Variant = entry.get("description", "")
	return String(raw) if raw is String else ""


func _base_of(family_id: String) -> String:
	var entry: Dictionary = _family_entry(family_id)
	var raw: Variant = entry.get("base", "BOX")
	return String(raw).to_upper() if raw is String else "BOX"


func _family_entry(family_id: String) -> Dictionary:
	var data: ShipData = _builder.get_data() if _builder != null else null
	if data == null:
		return {}
	var raw: Variant = data.families.get(family_id, {})
	return raw if raw is Dictionary else {}


func _manufacturer_label(data: ShipData, manufacturer_id: String) -> String:
	var raw: Variant = data.manufacturers.get(manufacturer_id, {})
	if raw is Dictionary:
		var entry: Dictionary = raw
		var label: Variant = entry.get("label", manufacturer_id)
		if label is String:
			return String(label).to_upper()
	return manufacturer_id.to_upper()


func _root_span() -> float:
	var cfg: ShipConfig = _builder.get_config() if _builder != null else null
	return cfg.root_span_m if cfg != null else 5.0


func _role(role: String) -> Color:
	return _ship_theme.color_for_role(role) if _ship_theme != null else Color.WHITE


func _role_a(role: String, alpha: float) -> Color:
	return _ship_theme.color_for_role_a(role, alpha) if _ship_theme != null else Color.BLACK
