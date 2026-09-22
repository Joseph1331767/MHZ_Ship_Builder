## PartPalettePanel - a flat, paginated icon palette over every shape in the pack.
##
## RETIRED(2026-08-31): nine fixed categories (bodies/cockpits/space/land/water/air/weaponry/
## effects/details) -> ONE flat list of every family, in pack order. Removed at the author's
## explicit instruction: "they are simple shapes and need no classification. the player
## classifies this later in the game". A cylinder is not a "weapon" until the player decides it
## is, and Phase 1 has no mechanism for them to decide - so the tabs were sorting shapes into
## roles the builder cannot express, and hiding two thirds of a six-family pack behind empty
## tabs to do it. Spore's own categories exist because Spore ships hundreds of hand-authored
## parts; six procedural primitives do not need a filing system.
##
## The retired contract sections are API_CONTRACT_SPORE section 9 (the nine categories) and the
## `category` key in section 11, both marked in place. THERE IS STILL NO SEARCH OR FILTER FIELD -
## no Spore editor palette has one (SPEC section 6), and with one flat page of shapes there is
## nothing to search.
##
## THE RED-OUT TEST - the whole point of this rework
## ------------------------------------------------
## SporeWiki, verbatim: "Parts will be coloured red when they cannot be added". An entry that
## `ShipGate.check_add()` refuses is drawn entirely in the `warning` role and its refusal
## message is its tooltip, VERBATIM. Two independent gates can refuse - the complexity
## ceiling and the physical budgets - and the message is the only thing that says which, so
## it is never paraphrased, never truncated, and never replaced with a generic string.
##
## Unaffordable cells stay CLICKABLE on purpose. A dead button tells the player nothing; a
## click re-runs `check_add()` for that one family and puts the gate's own sentence in a
## dialog. That is the mitigation for having two gates at all.
##
## COST CONTROL. `ShipGate.check_add()` also runs the physical budgets, which are not free,
## so the red-out has two speeds:
##   - FAST, every doc_changed/selection_changed: `ShipComplexity.can_afford()` only, which
##     the contract states is cheap. It flips the `ok` flag and therefore the colour.
##   - FULL, on a 250 ms idle Timer: `ShipGate.check_add()` for the families ON THE CURRENT
##     PAGE only (at most PAGE_SIZE of them), which refreshes `ok` AND the verbatim message.
## Between the two, a cell can be red with a stale message for up to 250 ms - which nobody
## sees, because the message is only read from a tooltip or from the click path, and the
## click path re-runs the full check synchronously for that one family before it answers.
##
## SYMMETRY IS ON BY DEFAULT and doubles a part's complexity, so the affordability question
## is "can I afford it AS IT WOULD BE PLACED". That is symmetric unless the document's
## symmetry plane is off, or the part the ghost would attach to is already effectively
## asymmetric - in which case the new part inherits the break and costs half. Hence the
## dependency on the SELECTION, and hence the refresh on selection_changed.
##
## MANUFACTURERS are not a Spore concept, so they do not get a control per icon. One picker
## sits under the grid and applies to the armed family; changing it re-raises the ghost with
## the new make. Each family remembers its own last choice.
##
## Colour comes only from ShipTheme.color_for_role() and is re-resolved on palette_changed;
## no palette index appears anywhere in this file (SPEC section 11).
class_name PartPalettePanel
extends VBoxContainer

const GRID_COLUMNS: int = 4
const GRID_ROWS: int = 3
## GRID_COLUMNS * GRID_ROWS. Spore's grids run four columns of eight to ten; this panel shares
## its column with the tree, so it pages sooner.
const PAGE_SIZE: int = 12

const CELL_SIZE: float = 40.0
const PAGE_HEIGHT: float = 15.0
const PICKER_HEIGHT: float = 17.0
## Room for about four component rows before the list scrolls.
const COMPONENT_LIST_HEIGHT: float = 60.0
const TICK_LENGTH: float = 4.0

const GLYPH_INSET: float = 8.0
const GLYPH_WIDTH: float = 1.0
const ARC_POINTS: int = 20
const LABEL_PAD: float = 2.0

## Idle window before the full ShipGate pass runs. Matches the gauge strip's debounce.
const IDLE_SECONDS: float = 0.25

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null

var _grid: GridContainer = null
var _cells: Array[Button] = []
var _page_label: Label = null
var _prev_button: Button = null
var _next_button: Button = null
var _mfr_picker: OptionButton = null
var _hint: Label = null
## The saved-components list. Empty until the player presses MAKE COMP in the tree panel.
var _component_list: ItemList = null
var _component_caption: Label = null
## Row index -> component id, so a click resolves without parsing the label back.
var _component_ids: PackedStringArray = PackedStringArray()
var _gate_timer: Timer = null
## Every Label that must be re-tinted with the "text_dim" role on a palette swap.
var _dim_labels: Array[Label] = []

## Every family in the pack, in pack order. One flat list - see the class docs.
var _families: PackedStringArray = PackedStringArray()
var _page: int = 0
## The family whose ghost is up, and therefore the one the manufacturer picker applies to.
var _armed: String = ""
## family_id -> manufacturer_id. Each family keeps its own last choice.
var _mfr_by_family: Dictionary = {}
## family_id -> { "ok": bool, "message": String }. `message` is the gate's own sentence.
var _gate: Dictionary = {}
## Cell index -> family id, "" for an empty cell on a short last page.
var _cell_family: PackedStringArray = PackedStringArray()


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)

	_build_grid()
	_build_page_row()
	_build_manufacturer_row()
	_build_component_section()

	_hint = Label.new()
	_hint.name = "PaletteHint"
	_hint.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_hint.text = "PICK A PART"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	_dim_labels.append(_hint)

	_gate_timer = Timer.new()
	_gate_timer.name = "GateIdle"
	_gate_timer.wait_time = IDLE_SECONDS
	_gate_timer.one_shot = true
	_gate_timer.timeout.connect(_on_gate_idle)
	add_child(_gate_timer)


func _draw() -> void:
	NumericField.draw_corner_ticks(
		self, Rect2(Vector2.ZERO, size), _role_color("line"), TICK_LENGTH
	)


## Called by ShipBuilder._ready() straight after this scene is mounted into its slot.
func setup(builder: ShipBuilder) -> void:
	_builder = builder
	if _builder == null:
		return
	_ship_theme = _builder.get_ship_theme()
	if _ship_theme != null and not _ship_theme.palette_changed.is_connected(_on_palette_changed):
		_ship_theme.palette_changed.connect(_on_palette_changed)
	_builder.doc_changed.connect(_on_doc_changed)
	_builder.selection_changed.connect(_on_selection_changed)
	_rebuild_index()
	_page = 0
	_refresh_cells()
	_refresh_components()
	_apply_palette()
	_refresh_gate_fast()


# ---------------------------------------------------------------- construction


func _build_grid() -> void:
	_grid = GridContainer.new()
	_grid.name = "PartGrid"
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	add_child(_grid)
	_cell_family.resize(PAGE_SIZE)
	for index: int in PAGE_SIZE:
		var cell: Button = Button.new()
		cell.name = "Cell%d" % index
		cell.focus_mode = Control.FOCUS_NONE
		cell.custom_minimum_size = Vector2(ShipTheme.pxf(CELL_SIZE), ShipTheme.pxf(CELL_SIZE))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# CanvasItem emits `draw` AFTER the control has painted itself, so one bound handler
		# paints an icon over all twelve cells without a Control subclass per cell.
		cell.draw.connect(_on_cell_draw.bind(index))
		cell.pressed.connect(_on_cell_pressed.bind(index))
		_grid.add_child(cell)
		_cells.append(cell)


## Saved components, listed under the shape grid and placed exactly like a shape.
##
## MAKE COMP in the tree panel could CREATE a component and there was nowhere to place one from:
## ShipComponents.instantiate() had no caller in the whole harness. The author reported it -
## "selecting 2 or more things and pressing make comp does not add it to its own section of
## addable shapes above". This is that section.
##
## A list rather than an icon grid: a component has no single primitive to draw a glyph for, and
## its NAME is the thing that identifies it - which is also why it is worth prompting for one.
func _build_component_section() -> void:
	_component_caption = Label.new()
	_component_caption.name = "ComponentCaption"
	_component_caption.text = "COMPONENTS"
	_component_caption.add_theme_font_size_override("font_size", ShipTheme.font_small())
	add_child(_component_caption)
	_dim_labels.append(_component_caption)

	_component_list = ItemList.new()
	_component_list.name = "ComponentList"
	_component_list.custom_minimum_size = Vector2(0.0, ShipTheme.pxf(COMPONENT_LIST_HEIGHT))
	_component_list.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_component_list.focus_mode = Control.FOCUS_NONE
	_component_list.allow_reselect = true
	_component_list.item_selected.connect(_on_component_selected)
	add_child(_component_list)
	# IMPORT: the components of another saved ship, and that ship as one (ADR 0024).
	var import_button: Button = Button.new()
	import_button.name = "ImportComponents"
	import_button.text = "IMPORT COMPONENTS"
	import_button.tooltip_text = "BRING THE COMPONENTS OF ANOTHER SAVED SHIP HERE, AND THE SHIP AS ONE"
	import_button.focus_mode = Control.FOCUS_NONE
	import_button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	import_button.pressed.connect(_on_import_pressed)
	add_child(import_button)
	_refresh_components()


## Re-read doc.components. Cheap and called on every doc change: a component list is a handful of
## rows, and it has to follow MAKE COMP / MAKE UNIQUE / undo without being told which happened.
func _refresh_components() -> void:
	if _component_list == null or _builder == null:
		return
	var doc: ShipDoc = _builder.get_doc()
	_component_list.clear()
	_component_ids = PackedStringArray()
	if doc == null:
		return
	var ids: Array = doc.components.keys()
	ids.sort()
	for entry: Variant in ids:
		var component_id: String = str(entry)
		var definition: Variant = doc.components[entry]
		var label: String = component_id
		if definition is Dictionary:
			label = str((definition as Dictionary).get("label", component_id))
		var parts: int = 0
		if definition is Dictionary:
			var inner: Variant = (definition as Dictionary).get("parts", {})
			if inner is Dictionary:
				parts = (inner as Dictionary).size()
		_component_list.add_item("%s  (%d)" % [label.to_upper(), parts])
		_component_ids.append(component_id)
	var empty: bool = _component_ids.is_empty()
	_component_caption.text = "COMPONENTS" if not empty else "COMPONENTS  (NONE YET)"
	_component_list.visible = not empty


## The builder lists the saved ships and imports the chosen one. Its handler is private - the
## facade is at its public-method budget - so the Callable is made by name, on purpose.
func _on_import_pressed() -> void:
	if _builder != null and _builder.has_method("_on_import_pressed"):
		Callable(_builder, "_on_import_pressed").call()


func _on_component_selected(index: int) -> void:
	if _builder == null or index < 0 or index >= _component_ids.size():
		return
	var component_id: String = _component_ids[index]
	_armed = ""
	_set_hint("PLACING COMPONENT %s" % component_id.to_upper())
	_builder.begin_component_placement(component_id)
	for cell: Button in _cells:
		cell.queue_redraw()


func _build_page_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "PageRow"
	row.add_theme_constant_override("separation", 2)
	add_child(row)

	_prev_button = _make_page_button("<", _on_prev_page, "PREVIOUS PAGE")
	row.add_child(_prev_button)

	_page_label = Label.new()
	_page_label.name = "PageLabel"
	_page_label.clip_text = true
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_page_label.text = "PAGE 1/1"
	row.add_child(_page_label)
	_dim_labels.append(_page_label)

	_next_button = _make_page_button(">", _on_next_page, "NEXT PAGE")
	row.add_child(_next_button)


func _build_manufacturer_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ManufacturerRow"
	row.add_theme_constant_override("separation", 4)
	add_child(row)

	var tag: Label = Label.new()
	tag.text = "MFR"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(tag)
	_dim_labels.append(tag)

	_mfr_picker = OptionButton.new()
	_mfr_picker.name = "ManufacturerPicker"
	_mfr_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mfr_picker.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(PICKER_HEIGHT))
	_mfr_picker.clip_text = true
	_mfr_picker.focus_mode = Control.FOCUS_NONE
	_mfr_picker.disabled = true
	_mfr_picker.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_mfr_picker.item_selected.connect(_on_manufacturer_selected)
	row.add_child(_mfr_picker)


func _make_page_button(label: String, handler: Callable, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ShipTheme.pxf(PAGE_HEIGHT), ShipTheme.pxf(PAGE_HEIGHT))
	button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	button.pressed.connect(handler)
	return button


# ---------------------------------------------------------------- catalogue index


## One pass over the pack. Families keep their pack order so the grid is deterministic.
func _rebuild_index() -> void:
	_families = PackedStringArray()
	var data: ShipData = _builder.get_data()
	if data == null:
		return
	for family_id: String in data.family_ids():
		_families.append(family_id)


func _page_count() -> int:
	if _families.is_empty():
		return 1
	return int(ceilf(float(_families.size()) / float(PAGE_SIZE)))


# ---------------------------------------------------------------- page state


func _on_prev_page() -> void:
	_page = maxi(0, _page - 1)
	_refresh_cells()
	_refresh_gate_fast()


func _on_next_page() -> void:
	_page = mini(_page_count() - 1, _page + 1)
	_refresh_cells()
	_refresh_gate_fast()


## Repoints the twelve reusable cells at the current page. Cells past the end of a short
## page stay VISIBLE and disabled so the grid keeps a stable height instead of reflowing.
func _refresh_cells() -> void:
	var families: PackedStringArray = _families
	var start: int = _page * PAGE_SIZE
	for index: int in PAGE_SIZE:
		var slot: int = start + index
		var family_id: String = ""
		if slot < families.size():
			family_id = families[slot]
		_cell_family[index] = family_id
		var cell: Button = _cells[index]
		cell.disabled = family_id == ""
		cell.tooltip_text = _tooltip_for(family_id)
		cell.queue_redraw()
	_page_label.text = ("PAGE %d/%d  (%d PARTS)" % [_page + 1, _page_count(), families.size()])
	_prev_button.disabled = _page <= 0
	_next_button.disabled = _page + 1 >= _page_count()
	if families.is_empty():
		_set_hint("NO SHAPES IN THE PACK")


func _set_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text


# ---------------------------------------------------------------- the red-out test


func _on_doc_changed(_doc: ShipDoc) -> void:
	_refresh_gate_fast()
	# MAKE COMP, MAKE UNIQUE and undo all land here as an ordinary doc change, so the component
	# list follows all three without any of them having to know this panel exists.
	_refresh_components()


func _on_selection_changed(_selected: PackedStringArray) -> void:
	# The ghost would attach to the selection, and an effectively-asymmetric parent halves
	# the new part's cost, so affordability genuinely depends on what is selected.
	_refresh_gate_fast()


## FAST PATH. ShipComplexity is cheap by contract and may run per edit; ShipGate is not,
## because it also runs the physical budgets. So this flips the colour now and lets the
## idle pass refresh the sentence.
func _refresh_gate_fast() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return
	var symmetric: bool = _symmetric_default()
	for index: int in PAGE_SIZE:
		var family_id: String = _cell_family[index]
		if family_id == "":
			continue
		var ok: bool = ShipComplexity.can_afford(doc, data, cfg, family_id, symmetric)
		var record: Dictionary = _gate_record(family_id)
		record["ok"] = ok
		_gate[family_id] = record
		_cells[index].queue_redraw()
	_gate_timer.start()


## FULL PASS. Both gates, current page only, and the message is stored verbatim - it is the
## only thing that says WHICH gate refused, which is the entire mitigation for having two.
func _on_gate_idle() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return
	var symmetric: bool = _symmetric_default()
	for index: int in PAGE_SIZE:
		var family_id: String = _cell_family[index]
		if family_id == "":
			continue
		_gate[family_id] = _check_add(family_id, symmetric)
		_cells[index].tooltip_text = _tooltip_for(family_id)
		_cells[index].queue_redraw()


## The authoritative single-family check. Returns { "ok": bool, "message": String }.
func _check_add(family_id: String, symmetric: bool) -> Dictionary:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return {"ok": true, "message": ""}
	var result: Dictionary = ShipGate.check_add(doc, data, cfg, family_id, symmetric)
	return {
		"ok": bool(result.get("ok", true)),
		"message": _text_of(result, "message", ""),
	}


## Would a part added right now be mirrored? Symmetry is ON by default (contract section 3),
## so this is true unless the plane is off or the part it would attach to has already had
## its symmetry broken - a break cascades to everything attached below it.
func _symmetric_default() -> bool:
	var doc: ShipDoc = _builder.get_doc()
	if doc == null or doc.symmetry_plane == "":
		return false
	var selected: PackedStringArray = _builder.get_selection()
	if selected.is_empty():
		return true
	return not ShipSymmetry.is_effectively_asymmetric(doc, selected[0])


func _gate_record(family_id: String) -> Dictionary:
	var value: Variant = _gate.get(family_id, null)
	if value is Dictionary:
		return value
	return {"ok": true, "message": ""}


func _is_affordable(family_id: String) -> bool:
	return bool(_gate_record(family_id).get("ok", true))


func _gate_message(family_id: String) -> String:
	return _text_of(_gate_record(family_id), "message", "")


# ---------------------------------------------------------------- actions


## Raise a ghost - unless a gate refuses, in which case the refusal is shown verbatim and
## nothing is placed. `check_add` is re-run here rather than trusting the cached record,
## because the cached one can be up to one idle window old and this answer is the one the
## player acts on.
func _on_cell_pressed(index: int) -> void:
	var family_id: String = _cell_family[index]
	if _builder == null or family_id == "":
		return
	var result: Dictionary = _check_add(family_id, _symmetric_default())
	_gate[family_id] = result
	_cells[index].tooltip_text = _tooltip_for(family_id)
	_cells[index].queue_redraw()
	if not bool(result.get("ok", true)):
		var message: String = _text_of(result, "message", "THIS PART CANNOT BE ADDED.")
		_set_hint(message)
		_builder.show_message("CANNOT ADD PART", message)
		return
	_armed = family_id
	_fill_picker(family_id)
	_set_hint("PLACING %s" % _label_of(family_id))
	_builder.begin_placement(family_id, _manufacturer_for(family_id))
	for cell: Button in _cells:
		cell.queue_redraw()


func _on_manufacturer_selected(index: int) -> void:
	if _armed == "" or _mfr_picker == null:
		return
	var meta: Variant = _mfr_picker.get_item_metadata(index)
	if meta is String:
		_mfr_by_family[_armed] = meta
	_refresh_picker_tooltip()
	# Re-raise the ghost so the make change is visible immediately rather than on the next
	# click. begin_placement() replaces any live placement, so this is not a leak.
	_builder.begin_placement(_armed, _manufacturer_for(_armed))


func _fill_picker(family_id: String) -> void:
	if _mfr_picker == null:
		return
	_mfr_picker.clear()
	var data: ShipData = _builder.get_data()
	if data == null:
		_mfr_picker.add_item("NONE")
		_mfr_picker.set_item_metadata(0, "")
		_mfr_picker.disabled = true
		return
	var ids: PackedStringArray = data.manufacturers_for(family_id)
	if ids.is_empty():
		_mfr_picker.add_item("NONE")
		_mfr_picker.set_item_metadata(0, "")
		_mfr_picker.disabled = true
		return
	_mfr_picker.disabled = false
	var remembered: String = _manufacturer_for(family_id)
	var chosen: int = 0
	for i: int in ids.size():
		var mid: String = ids[i]
		var entry: Dictionary = _entry(data.manufacturers, mid)
		_mfr_picker.add_item(_text_of(entry, "label", mid).to_upper(), i)
		_mfr_picker.set_item_metadata(i, mid)
		if mid == remembered:
			chosen = i
	_mfr_picker.select(chosen)
	_mfr_by_family[family_id] = ids[chosen]
	_refresh_picker_tooltip()


func _refresh_picker_tooltip() -> void:
	if _mfr_picker == null or _builder == null:
		return
	var data: ShipData = _builder.get_data()
	if data == null:
		return
	var mid: String = _manufacturer_for(_armed)
	var entry: Dictionary = _entry(data.manufacturers, mid)
	_mfr_picker.tooltip_text = _text_of(entry, "description", "NO CATALOGUE COPY FOR " + mid)


func _manufacturer_for(family_id: String) -> String:
	var value: Variant = _mfr_by_family.get(family_id, null)
	if value is String:
		return value
	var data: ShipData = _builder.get_data()
	if data == null:
		return ""
	var ids: PackedStringArray = data.manufacturers_for(family_id)
	if ids.is_empty():
		return ""
	return ids[0]


# ---------------------------------------------------------------- copy


func _label_of(family_id: String) -> String:
	var data: ShipData = _builder.get_data()
	if data == null:
		return family_id.to_upper()
	var entry: Dictionary = _entry(data.families, family_id)
	return _text_of(entry, "label", family_id).to_upper()


## The pack is the copy (AGENTS section 10b): label, then the written description, then the
## complexity price, then - only when refused - the gate's own sentence.
func _tooltip_for(family_id: String) -> String:
	if family_id == "" or _builder == null:
		return ""
	var data: ShipData = _builder.get_data()
	if data == null:
		return family_id.to_upper()
	var entry: Dictionary = _entry(data.families, family_id)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(_label_of(family_id))
	lines.append(_text_of(entry, "description", "NO CATALOGUE COPY FOR " + family_id))
	lines.append(_complexity_line(data, family_id))
	if not _is_affordable(family_id):
		lines.append(_gate_message(family_id))
	return "\n".join(lines)


func _complexity_line(data: ShipData, family_id: String) -> String:
	var symmetric: bool = _symmetric_default()
	var cost: float = ShipComplexity.cost_of_new(data, family_id, symmetric)
	var note: String = "SYMMETRIC - DOUBLED" if symmetric else "ASYMMETRIC - HALF PRICE"
	return "COMPLEXITY %s  (%s)" % [NumericField.format_number(cost), note]


# ---------------------------------------------------------------- cell drawing


## One palette icon: a frame, a silhouette of the family's base primitive, and its
## complexity price. Everything is drawn in ONE tint - `warning` when a gate refuses the
## part, `accent` otherwise - because Spore's signal is "the part is red", not "the part has
## a red badge".
func _on_cell_draw(index: int) -> void:
	var cell: Button = _cells[index]
	if not is_instance_valid(cell):
		return
	var family_id: String = _cell_family[index]
	var rect: Rect2 = Rect2(Vector2.ZERO, cell.size)
	if family_id == "":
		cell.draw_rect(rect, _role_color("line"), false, 1.0)
		return
	var tint: Color = _role_color("accent")
	if not _is_affordable(family_id):
		tint = _role_color("warning")
	if family_id == _armed:
		cell.draw_rect(rect, _role_color("selection"), false, 1.0)
	else:
		cell.draw_rect(rect, _role_color("line"), false, 1.0)
	draw_glyph(cell, rect.grow(-GLYPH_INSET), _base_of(family_id), tint)
	_draw_price(cell, rect, family_id, tint)


func _draw_price(cell: Button, rect: Rect2, family_id: String, tint: Color) -> void:
	var data: ShipData = _builder.get_data()
	if data == null:
		return
	var font: Font = cell.get_theme_font("font")
	if font == null:
		return
	var size: int = ShipTheme.font_small()
	var cost: float = ShipComplexity.cost_of_new(data, family_id, _symmetric_default())
	# One decimal, not the panel-wide three: the cell is 40 px and this is a price tag, not
	# a field the player types into.
	var text: String = String.num(cost, 1)
	var at: Vector2 = Vector2(rect.position.x + LABEL_PAD, rect.end.y - LABEL_PAD)
	cell.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, tint)


## Silhouettes for the base primitives in `data/shapes/families.json`. Read from the pack's
## `"base"` string rather than through ShapeGen, so the palette never has to resolve a shape it is
## not going to render.
##
## Static and public because ShipStartDialog draws the same silhouettes: the shape the player
## picks to found a ship must be the shape they then see in the palette, and two independent
## drawings of "a cylinder" would eventually disagree.
static func draw_glyph(target: CanvasItem, rect: Rect2, base: String, tint: Color) -> void:
	var centre: Vector2 = rect.get_center()
	var half: Vector2 = rect.size * 0.5
	var radius: float = minf(half.x, half.y)
	if base == "SPHERE":
		target.draw_arc(centre, radius, 0.0, TAU, ARC_POINTS, tint, GLYPH_WIDTH)
		return
	if base == "TORUS":
		target.draw_arc(centre, radius, 0.0, TAU, ARC_POINTS, tint, GLYPH_WIDTH)
		target.draw_arc(centre, radius * 0.45, 0.0, TAU, ARC_POINTS, tint, GLYPH_WIDTH)
		return
	if base == "CONE":
		_draw_cone(target, rect, tint)
		return
	if base == "CAPSULE":
		_draw_capsule(target, rect, radius, tint)
		return
	if base == "CYLINDER":
		_draw_cylinder(target, rect, tint)
		return
	# BOX and anything the pack adds later: a plain box reads as "a part", which is the
	# honest default for a silhouette we do not have a drawing for.
	target.draw_rect(rect, tint, false, GLYPH_WIDTH)


static func _draw_cone(target: CanvasItem, rect: Rect2, tint: Color) -> void:
	var rx: float = rect.size.x * 0.5
	var ry: float = minf(rect.size.y * 0.18, rx * 0.6)
	var cx: float = rect.get_center().x
	var base_y: float = rect.end.y - ry
	var apex: Vector2 = Vector2(cx, rect.position.y)
	target.draw_polyline(_ellipse(Vector2(cx, base_y), rx, ry, true), tint, GLYPH_WIDTH)
	target.draw_line(Vector2(cx - rx, base_y), apex, tint, GLYPH_WIDTH)
	target.draw_line(Vector2(cx + rx, base_y), apex, tint, GLYPH_WIDTH)


static func _draw_capsule(target: CanvasItem, rect: Rect2, radius: float, tint: Color) -> void:
	var r: float = minf(rect.size.x * 0.5, radius)
	var top: Vector2 = Vector2(rect.get_center().x, rect.position.y + r)
	var bottom: Vector2 = Vector2(rect.get_center().x, rect.end.y - r)
	target.draw_arc(top, r, PI, TAU, ARC_POINTS, tint, GLYPH_WIDTH)
	target.draw_arc(bottom, r, 0.0, PI, ARC_POINTS, tint, GLYPH_WIDTH)
	target.draw_line(Vector2(top.x - r, top.y), Vector2(bottom.x - r, bottom.y), tint, GLYPH_WIDTH)
	target.draw_line(Vector2(top.x + r, top.y), Vector2(bottom.x + r, bottom.y), tint, GLYPH_WIDTH)


## A cylinder read as a cylinder: a full ellipse for the top rim, the FRONT half of the bottom
## rim, and two straight sides.
##
## It used to be a rectangle with two horizontal lines across it. At a 40 px cell, through a
## 16-colour quantizer, that is indistinguishable from the capsule glyph next to it - the author
## reported "i dont see a cylinder add just the modified cylinder", and the plain cylinder was
## sitting right there wearing the wrong face.
static func _draw_cylinder(target: CanvasItem, rect: Rect2, tint: Color) -> void:
	var rx: float = rect.size.x * 0.5
	var ry: float = minf(rect.size.y * 0.18, rx * 0.6)
	var cx: float = rect.get_center().x
	var top: float = rect.position.y + ry
	var bottom: float = rect.end.y - ry
	target.draw_polyline(_ellipse(Vector2(cx, top), rx, ry, true), tint, GLYPH_WIDTH)
	target.draw_polyline(_ellipse(Vector2(cx, bottom), rx, ry, false), tint, GLYPH_WIDTH)
	target.draw_line(Vector2(cx - rx, top), Vector2(cx - rx, bottom), tint, GLYPH_WIDTH)
	target.draw_line(Vector2(cx + rx, top), Vector2(cx + rx, bottom), tint, GLYPH_WIDTH)


## An ellipse outline, or just its FRONT (lower) half when `closed` is false - the half of a
## bottom rim that is not hidden by the body above it.
static func _ellipse(centre: Vector2, rx: float, ry: float, closed: bool) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var span: float = TAU if closed else PI
	var start: float = 0.0
	for i: int in ARC_POINTS + 1:
		var t: float = start + span * float(i) / float(ARC_POINTS)
		out.append(centre + Vector2(cos(t) * rx, sin(t) * ry))
	return out


func _base_of(family_id: String) -> String:
	var data: ShipData = _builder.get_data()
	if data == null:
		return "BOX"
	var entry: Dictionary = _entry(data.families, family_id)
	return _text_of(entry, "base", "BOX").to_upper()


# ---------------------------------------------------------------- palette


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_apply_palette()


func _apply_palette() -> void:
	var dim: Color = _role_color("text_dim")
	for label: Label in _dim_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", dim)
	for cell: Button in _cells:
		if is_instance_valid(cell):
			cell.queue_redraw()
	queue_redraw()


## The only sanctioned colour lookup. Never an index (SPEC section 11).
func _role_color(role: String) -> Color:
	if _ship_theme == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	return _ship_theme.color_for_role(role)


# ---------------------------------------------------------------- pack readers


static func _entry(pack: Dictionary, entry_id: String) -> Dictionary:
	if entry_id == "":
		return {}
	var value: Variant = pack.get(entry_id, null)
	if value is Dictionary:
		return value
	return {}


static func _text_of(entry: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = entry.get(key, null)
	if value is String:
		var text: String = value
		if text.strip_edges() != "":
			return text
	return fallback
