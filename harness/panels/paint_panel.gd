## PaintPanel - the BUILD | PAINT mode switch and the finishing catalogue.
##
## TWO MODES, NOT THREE. `Editors::cEditor` gives every Spore editor `BuildMode`,
## `PaintMode` and `PlayMode`, but the ship editor has no PLAY - confirmed by two
## independent research passes and pinned in API_CONTRACT_SPORE section 10. There is
## therefore no third button here and adding one would be an invention.
##
## THREE PAINT METHODS, which is what `data/paint_styles.json` is three blocks of and what
## SPORE_CLONE_SPEC section 6 lists as the vehicle/ship editors' sub-options:
##
##   BRUSH    - a palette colour and a texture id, applied by hand. The `textures` block is
##              the shared finish vocabulary and the only place a texture id is defined.
##   COMPLETE - a style that carries one ordered colour per paint region plus one texture
##              and leaves NO region untouched. Pick one and the part is finished.
##   PARTIAL  - a style that names only the regions it cares about and leaves every other
##              region exactly as the player left it, so a trim pack LAYERS over a complete
##              style instead of replacing it.
##
## NO PALETTE INDEX IS HARDCODED ANYWHERE (SPEC section 11). The swatch grid ENUMERATES
## `ShipTheme.active_palette` - it does not name entries - the chrome comes from
## `color_for_role()`, and the panel opens with NO colour armed rather than defaulting to
## an index it would have had to pick. Everything re-resolves on `palette_changed`, so a
## budget alert that swaps the whole LUT repaints the swatches, the readouts and the ship
## together.
##
## WHERE THE INPUT COMES FROM. This panel owns the session's [PaintMode] and wires its
## surface probe to [method ShipView3D.probe_surface], which is a public API and needs no
## change to that file. What it CANNOT do from a side panel is deliver a camera ray: the
## 3D view must call `paint_mode().click(origin, dir, shift, ctrl, alt)` and
## `paint_mode().hover(origin, dir)` from its own `_physics_process`, the same way it
## already drives [ShipPlacement]. Until that one wire exists, the APPLY buttons below
## drive the identical [ShipPaint] plans from the current SELECTION instead, so paint mode
## is usable and testable today without a click in the viewport.
##
## PAINT IS STORED, NOT YET RENDERED. [member ShipPart.paint] round-trips through save and
## load and is what the region readout shows, but `ShipSceneBuilder` still colours parts by
## palette ROLE. Making the 3D view read `ShipPaint.resolve_part()` belongs to whoever owns
## that file; this panel says so on screen rather than implying the ship changed colour.
class_name PaintPanel
extends VBoxContainer

## The catalogue. Read here rather than through [ShipData], which does not load it -
## `harness/` may touch `res://`, `core/` may not (AGENTS section 3).
const PACK_PATH: String = "res://data/paint_styles.json"

const SWATCH_COLUMNS: int = 8
const SWATCH_SIZE: Vector2 = Vector2(22.0, 14.0)
const ROW_HEIGHT: float = 16.0
const LIST_HEIGHT: float = 78.0
const REGION_HEIGHT: float = 62.0
const TICK_LENGTH: float = 4.0
const SWATCH_BORDER: int = 1
const SWATCH_BORDER_ARMED: int = 2

## Shown for the "no texture" entry, which is a real choice and not an absence.
const NO_TEXTURE_LABEL: String = "(BARE - NO TEXTURE)"

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null
var _paint: PaintMode = null

## Parsed `data/paint_styles.json`. Empty when the pack is missing or malformed; the panel
## still runs and says so instead of failing to mount.
var _pack: Dictionary = {}
var _pack_error: String = ""

var _build_button: Button = null
var _paint_button: Button = null
var _method_buttons: Array[Button] = []
var _swatch_grid: GridContainer = null
var _swatches: Array[Button] = []
var _swatch_boxes: Array[StyleBoxFlat] = []
var _brush_page: VBoxContainer = null
var _style_page: VBoxContainer = null
var _texture_list: ItemList = null
var _style_list: ItemList = null
var _style_blurb: Label = null
var _channel_buttons: Array[Button] = []
var _pick_label: Label = null
var _target_label: Label = null
var _region_list: ItemList = null
var _hint: Label = null
var _apply_region: Button = null
var _apply_part: Button = null

## Every Label re-tinted with "text_dim" on a palette swap.
var _dim_labels: Array[Label] = []
## Texture ids by row index in [member _texture_list]; row 0 is always "".
var _texture_ids: PackedStringArray = PackedStringArray()
## Style ids by row index in [member _style_list], for the block currently shown.
var _style_ids: PackedStringArray = PackedStringArray()
## Region ids by row index in [member _region_list], for the part currently read out.
var _region_ids: PackedStringArray = PackedStringArray()
## The part whose regions are on screen: the hovered one, else the first selected one.
var _read_part: String = ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)

	_paint = PaintMode.new()
	_load_pack()

	_build_mode_row()
	add_child(HSeparator.new())
	_build_method_row()
	_build_brush_page()
	_build_style_page()
	add_child(HSeparator.new())
	_build_channel_row()
	_build_readout()

	_connect_paint_signals()
	_select_method(PaintMode.Method.BRUSH)
	_set_mode(false)


func _draw() -> void:
	NumericField.draw_corner_ticks(
		self, Rect2(Vector2.ZERO, size), _role_color("line"), TICK_LENGTH
	)


## Called by ShipBuilder straight after this scene is mounted into a slot.
func setup(builder: ShipBuilder) -> void:
	_builder = builder
	if _builder == null:
		return
	_paint.setup(_builder)
	_paint.set_style_pack(_pack)

	# Every connection is guarded the same way. setup() is called exactly once per panel
	# instance today (ShipBuilder._mount_panels()), but an unguarded connect turns a second
	# call into a silent double-fire - two _refresh_readout() passes per document change -
	# which is the kind of bug that only shows up as "the UI got slow" months later.
	_ship_theme = _builder.get_ship_theme()
	if _ship_theme != null and not _ship_theme.palette_changed.is_connected(_on_palette_changed):
		_ship_theme.palette_changed.connect(_on_palette_changed)
	if not _builder.doc_changed.is_connected(_on_doc_changed):
		_builder.doc_changed.connect(_on_doc_changed)
	if not _builder.selection_changed.is_connected(_on_selection_changed):
		_builder.selection_changed.connect(_on_selection_changed)

	# The view's probe is public API, so binding it needs no change to that file. The
	# camera ray still has to be pushed in from the view - see the class docstring.
	var view: ShipView3D = _builder.get_view()
	if view != null:
		_paint.set_surface_probe(view.probe_surface)

	_rebuild_swatches()
	_apply_palette()
	_refresh_readout()


## The session's PaintMode, for whoever routes viewport input into it.
func paint_mode() -> PaintMode:
	return _paint


# ---------------------------------------------------------------- construction


func _build_mode_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ModeRow"
	add_child(row)

	var group: ButtonGroup = ButtonGroup.new()
	_build_button = _make_toggle("BUILD", group)
	_build_button.pressed.connect(_on_build_pressed)
	row.add_child(_build_button)
	_paint_button = _make_toggle("PAINT", group)
	_paint_button.pressed.connect(_on_paint_pressed)
	row.add_child(_paint_button)


func _build_method_row() -> void:
	var caption: Label = _make_caption("METHOD")
	add_child(caption)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "MethodRow"
	add_child(row)

	var group: ButtonGroup = ButtonGroup.new()
	var labels: PackedStringArray = PackedStringArray(["BRUSH", "COMPLETE", "PARTIAL"])
	var count: int = labels.size()
	for i: int in count:
		var button: Button = _make_toggle(labels[i], group)
		button.pressed.connect(_on_method_pressed.bind(i))
		row.add_child(button)
		_method_buttons.append(button)


func _build_brush_page() -> void:
	_brush_page = VBoxContainer.new()
	_brush_page.name = "BrushPage"
	_brush_page.add_theme_constant_override("separation", 2)
	add_child(_brush_page)

	_brush_page.add_child(_make_caption("COLOUR"))
	_swatch_grid = GridContainer.new()
	_swatch_grid.name = "Swatches"
	_swatch_grid.columns = SWATCH_COLUMNS
	_swatch_grid.add_theme_constant_override("h_separation", 2)
	_swatch_grid.add_theme_constant_override("v_separation", 2)
	_brush_page.add_child(_swatch_grid)

	_brush_page.add_child(_make_caption("TEXTURE"))
	_texture_list = _make_list("TextureList", LIST_HEIGHT)
	_texture_list.item_selected.connect(_on_texture_selected)
	_brush_page.add_child(_texture_list)
	_fill_texture_list()


func _build_style_page() -> void:
	_style_page = VBoxContainer.new()
	_style_page.name = "StylePage"
	_style_page.add_theme_constant_override("separation", 2)
	add_child(_style_page)

	_style_page.add_child(_make_caption("STYLE"))
	_style_list = _make_list("StyleList", LIST_HEIGHT)
	_style_list.item_selected.connect(_on_style_selected)
	_style_page.add_child(_style_list)

	_style_blurb = Label.new()
	_style_blurb.name = "StyleBlurb"
	_style_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_blurb.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_style_blurb.text = ""
	_style_page.add_child(_style_blurb)
	_dim_labels.append(_style_blurb)


func _build_channel_row() -> void:
	add_child(_make_caption("EYEDROPPER  ALT+LMB   3 / 4 / 5"))

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ChannelRow"
	add_child(row)

	var group: ButtonGroup = ButtonGroup.new()
	# Order matches the sourced keys: 3 = colour only, 4 = texture only, 5 = both.
	var labels: PackedStringArray = PackedStringArray(["COLOUR", "TEXTURE", "BOTH"])
	var channels: PackedInt32Array = PackedInt32Array(
		[ShipPaint.Channel.COLOR, ShipPaint.Channel.TEXTURE, ShipPaint.Channel.BOTH]
	)
	var count: int = labels.size()
	for i: int in count:
		var button: Button = _make_toggle(labels[i], group)
		button.pressed.connect(_on_channel_pressed.bind(channels[i]))
		row.add_child(button)
		_channel_buttons.append(button)
	_channel_buttons[2].button_pressed = true

	_pick_label = Label.new()
	_pick_label.name = "PickLabel"
	_pick_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_pick_label.text = "NO COLOUR ARMED"
	_pick_label.clip_text = true
	add_child(_pick_label)


func _build_readout() -> void:
	add_child(HSeparator.new())

	_target_label = Label.new()
	_target_label.name = "TargetLabel"
	_target_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_target_label.text = "NO PART"
	_target_label.clip_text = true
	add_child(_target_label)

	_region_list = _make_list("RegionList", REGION_HEIGHT)
	_region_list.item_selected.connect(_on_region_selected)
	add_child(_region_list)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "ApplyRow"
	add_child(row)
	_apply_region = _make_button("APPLY REGION", _on_apply_region)
	row.add_child(_apply_region)
	_apply_part = _make_button("APPLY PART", _on_apply_part)
	row.add_child(_apply_part)

	_hint = Label.new()
	_hint.name = "PaintHint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_hint.text = ""
	add_child(_hint)
	_dim_labels.append(_hint)


func _make_toggle(text: String, group: ButtonGroup) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	return button


func _make_button(text: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	button.pressed.connect(handler)
	return button


func _make_caption(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.clip_text = true
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_dim_labels.append(label)
	return label


func _make_list(list_name: String, height: float) -> ItemList:
	var list: ItemList = ItemList.new()
	list.name = list_name
	list.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(height))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.auto_height = false
	list.allow_reselect = true
	list.focus_mode = Control.FOCUS_NONE
	list.add_theme_font_size_override("font_size", ShipTheme.font_small())
	return list


# ---------------------------------------------------------------- pack


func _load_pack() -> void:
	_pack = {}
	_pack_error = ""
	if not FileAccess.file_exists(PACK_PATH):
		_pack_error = "MISSING %s" % PACK_PATH
		return
	var text: String = FileAccess.get_file_as_string(PACK_PATH)
	if text.is_empty():
		_pack_error = "EMPTY %s" % PACK_PATH
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_pack_error = "MALFORMED %s" % PACK_PATH
		return
	_pack = parsed


func _fill_texture_list() -> void:
	_texture_list.clear()
	_texture_ids = PackedStringArray()
	# Row 0 is a real choice - "bare" - not an absence, so it is always present even when
	# the pack failed to load.
	_texture_list.add_item(NO_TEXTURE_LABEL)
	_texture_ids.append("")
	for texture_id: String in ShipPaint.catalogue_ids(_pack, ShipPaint.BLOCK_TEXTURES):
		var entry: Dictionary = ShipPaint.catalogue_entry(
			_pack, ShipPaint.BLOCK_TEXTURES, texture_id
		)
		var row: int = _texture_list.add_item(_label_of(entry, texture_id))
		_texture_list.set_item_tooltip(row, _text_of(entry, "description"))
		_texture_ids.append(texture_id)
	_texture_list.select(0)


func _fill_style_list(block: String) -> void:
	_style_list.clear()
	_style_ids = PackedStringArray()
	for style_id: String in ShipPaint.catalogue_ids(_pack, block):
		var entry: Dictionary = ShipPaint.catalogue_entry(_pack, block, style_id)
		var row: int = _style_list.add_item(_label_of(entry, style_id))
		_style_list.set_item_tooltip(row, _text_of(entry, "description"))
		_style_ids.append(style_id)
	if _style_ids.is_empty():
		_style_blurb.text = _pack_error if _pack_error != "" else "NO STYLES IN THIS BLOCK"
		_paint.set_style(block, "")
		return
	_style_list.select(0)
	_on_style_selected(0)


# ---------------------------------------------------------------- swatches


## One button per entry in the ACTIVE palette. Built by enumeration, never by naming an
## index - see the class docstring.
func _rebuild_swatches() -> void:
	for button: Button in _swatches:
		if is_instance_valid(button):
			button.queue_free()
	_swatches.clear()
	_swatch_boxes.clear()
	if _swatch_grid == null:
		return
	var palette: PackedColorArray = _active_palette()
	var count: int = palette.size()
	for i: int in count:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.set_corner_radius_all(0)
		box.anti_aliasing = false
		box.set_border_width_all(SWATCH_BORDER)
		var button: Button = Button.new()
		button.name = "Swatch%d" % i
		button.custom_minimum_size = SWATCH_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "PALETTE %d" % i
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, box)
		button.pressed.connect(_on_swatch_pressed.bind(i))
		_swatch_grid.add_child(button)
		_swatches.append(button)
		_swatch_boxes.append(box)
	_apply_swatch_colors()


func _apply_swatch_colors() -> void:
	var palette: PackedColorArray = _active_palette()
	var armed: int = int(_paint.brush().get(ShipPart.PAINT_COLOR, ShipPaint.UNPAINTED))
	var edge: Color = _role_color("line")
	var lit: Color = _role_color("selection")
	var count: int = _swatch_boxes.size()
	for i: int in count:
		var box: StyleBoxFlat = _swatch_boxes[i]
		box.bg_color = palette[i] if i < palette.size() else Color.MAGENTA
		box.border_color = lit if i == armed else edge
		box.set_border_width_all(SWATCH_BORDER_ARMED if i == armed else SWATCH_BORDER)


# ---------------------------------------------------------------- mode / method


func _set_mode(painting: bool) -> void:
	if _build_button != null:
		_build_button.button_pressed = not painting
	if _paint_button != null:
		_paint_button.button_pressed = painting
	_paint.set_active(painting)
	# A ghost mid-placement has no meaning once the player is painting; drop it rather than
	# leaving a half-placed part following a pointer that no longer commits it.
	if painting and _builder != null and _builder.get_placement() != null:
		if _builder.get_placement().active:
			_builder.cancel_placement()
	_refresh_hint()


func _select_method(paint_method: int) -> void:
	_paint.set_method(paint_method)
	var count: int = _method_buttons.size()
	for i: int in count:
		_method_buttons[i].button_pressed = i == paint_method
	var brush: bool = paint_method == PaintMode.Method.BRUSH
	if _brush_page != null:
		_brush_page.visible = brush
	if _style_page != null:
		_style_page.visible = not brush
	if not brush:
		var block: String = ShipPaint.BLOCK_COMPLETE
		if paint_method == PaintMode.Method.PARTIAL_STYLE:
			block = ShipPaint.BLOCK_PARTIAL
		_fill_style_list(block)
	_refresh_hint()


# ---------------------------------------------------------------- readout


func _refresh_readout() -> void:
	var pid: String = _read_target()
	_read_part = pid
	_region_list.clear()
	_region_ids = PackedStringArray()
	if pid == "" or _builder == null:
		_target_label.text = "NO PART"
		return

	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var fallback: Color = _role_color("text_dim")
	var resolved: Dictionary = ShipPaint.resolve_part(doc, data, pid, _active_palette(), fallback)
	var hovered: Dictionary = _paint.hovered()
	var hover_region: String = str(hovered.get(PaintMode.HIT_REGION, ""))
	_target_label.text = "%s  %s" % [pid.to_upper(), _family_of(doc, pid).to_upper()]

	for region: String in ShipPaint.regions_for_part(doc, data, pid):
		var record: Dictionary = resolved.get(region, {})
		var row: int = _region_list.add_item(_region_text(region, record, region == hover_region))
		_region_list.set_item_custom_fg_color(row, _region_color(record, fallback))
		_region_ids.append(region)
	var armed_row: int = _region_ids.find(hover_region)
	if armed_row >= 0:
		_region_list.select(armed_row)


static func _region_text(region: String, record: Dictionary, hovered: bool) -> String:
	var mark: String = ">" if hovered else " "
	if not bool(record.get(ShipPaint.RESOLVED_PAINTED, false)):
		return "%s %s  UNPAINTED" % [mark, region.to_upper()]
	var texture: String = str(record.get(ShipPart.PAINT_TEXTURE, ""))
	var finish: String = texture.to_upper() if texture != "" else "BARE"
	return (
		"%s %s  #%d  %s"
		% [mark, region.to_upper(), int(record.get(ShipPart.PAINT_COLOR, 0)), finish]
	)


static func _region_color(record: Dictionary, fallback: Color) -> Color:
	var rgb: Variant = record.get(ShipPaint.RESOLVED_RGB, null)
	if rgb is Color:
		var c: Color = rgb
		return c
	return fallback


## The part whose regions are on screen: whatever the pointer is over, else the first
## selected part. Hover wins so the readout answers "what would this click paint".
func _read_target() -> String:
	var hovered: Dictionary = _paint.hovered()
	var hover_part: String = str(hovered.get(PaintMode.HIT_PART, ""))
	if hover_part != "":
		return hover_part
	if _builder == null:
		return ""
	var selection: PackedStringArray = _builder.get_selection()
	return selection[0] if not selection.is_empty() else ""


func _refresh_hint() -> void:
	if _hint == null:
		return
	if _pack_error != "":
		_hint.text = _pack_error
		return
	if not _paint.is_active():
		_hint.text = "BUILD MODE - SWITCH TO PAINT TO FINISH A HULL"
		return
	_hint.text = (
		"LMB REGION / SHIFT PART / SHIFT+CTRL FAMILY / ALT PICK / HOLD 1 ALL / 2 IDENTICAL."
		+ "  PAINT IS STORED ON THE PART; THE 3D VIEW DOES NOT RENDER IT YET."
	)


func _selected_region() -> String:
	var rows: PackedInt32Array = _region_list.get_selected_items()
	if rows.is_empty():
		return ""
	var row: int = rows[0]
	if row < 0 or row >= _region_ids.size():
		return ""
	return _region_ids[row]


func _apply_targets() -> PackedStringArray:
	if _builder == null:
		return PackedStringArray()
	var selection: PackedStringArray = _builder.get_selection()
	if not selection.is_empty():
		return selection
	return PackedStringArray([_read_part]) if _read_part != "" else PackedStringArray()


# ---------------------------------------------------------------- handlers


func _connect_paint_signals() -> void:
	_paint.brush_changed.connect(_on_brush_changed)
	_paint.paint_applied.connect(_on_paint_applied)
	_paint.paint_refused.connect(_on_paint_refused)
	_paint.eyedropper_picked.connect(_on_eyedropper_picked)
	_paint.hover_changed.connect(_on_hover_changed)
	_paint.channel_changed.connect(_on_channel_changed)


func _on_build_pressed() -> void:
	_set_mode(false)


func _on_paint_pressed() -> void:
	_set_mode(true)


func _on_method_pressed(paint_method: int) -> void:
	_select_method(paint_method)


func _on_swatch_pressed(index: int) -> void:
	_paint.set_brush(index, str(_paint.brush().get(ShipPart.PAINT_TEXTURE, "")))


func _on_texture_selected(row: int) -> void:
	if row < 0 or row >= _texture_ids.size():
		return
	var color: int = int(_paint.brush().get(ShipPart.PAINT_COLOR, ShipPaint.UNPAINTED))
	_paint.set_brush(color, _texture_ids[row])


func _on_style_selected(row: int) -> void:
	if row < 0 or row >= _style_ids.size():
		return
	var block: String = ShipPaint.BLOCK_COMPLETE
	if _paint.paint_method() == PaintMode.Method.PARTIAL_STYLE:
		block = ShipPaint.BLOCK_PARTIAL
	var style_id: String = _style_ids[row]
	_paint.set_style(block, style_id)
	var entry: Dictionary = ShipPaint.catalogue_entry(_pack, block, style_id)
	_style_blurb.text = _text_of(entry, "description")


func _on_region_selected(_row: int) -> void:
	_refresh_hint()


func _on_channel_pressed(channel: int) -> void:
	_paint.set_channel(channel)


func _on_apply_region() -> void:
	var region: String = _selected_region()
	if region == "":
		_set_status("SELECT A REGION FIRST")
		return
	_apply(region)


func _on_apply_part() -> void:
	_apply("")


func _apply(region: String) -> void:
	var targets: PackedStringArray = _apply_targets()
	if targets.is_empty():
		_set_status("SELECT A PART FIRST")
		return
	var changed: int = _paint.apply_current(targets, region)
	if changed == 0:
		_set_status("NOTHING CHANGED")
		return
	_set_status("PAINTED %d PART(S)" % changed)


func _on_brush_changed(color: int, texture: String) -> void:
	_apply_swatch_colors()
	var row: int = _texture_ids.find(texture)
	if row >= 0:
		_texture_list.select(row)
	if color == ShipPaint.UNPAINTED:
		_pick_label.text = "NO COLOUR ARMED"
		return
	var finish: String = texture.to_upper() if texture != "" else "BARE"
	_pick_label.text = "BRUSH  #%d  %s" % [color, finish]


func _on_paint_applied(part_ids: PackedStringArray, _spread: int) -> void:
	_set_status("PAINTED %d PART(S)" % part_ids.size())
	_refresh_readout()


func _on_paint_refused(reason: String) -> void:
	_set_status(reason)


func _on_eyedropper_picked(part_id: String, region: String, color: int, texture: String) -> void:
	var finish: String = texture.to_upper() if texture != "" else "BARE"
	_pick_label.text = (
		"PICKED %s/%s  #%d  %s" % [part_id.to_upper(), region.to_upper(), color, finish]
	)


func _on_hover_changed(_part_id: String, _region: String) -> void:
	_refresh_readout()


func _on_channel_changed(channel: int) -> void:
	var order: PackedInt32Array = PackedInt32Array(
		[ShipPaint.Channel.COLOR, ShipPaint.Channel.TEXTURE, ShipPaint.Channel.BOTH]
	)
	var index: int = order.find(channel)
	if index >= 0 and index < _channel_buttons.size():
		_channel_buttons[index].button_pressed = true


func _on_doc_changed(_doc: ShipDoc) -> void:
	_paint.notify_doc_changed(_doc)
	_refresh_readout()


func _on_selection_changed(_ids: PackedStringArray) -> void:
	_refresh_readout()


func _on_palette_changed(palette: PackedColorArray) -> void:
	# The LUT may have been swapped for a shorter or longer one, so rebuild rather than
	# recolour: a stale swatch pointing past the end of the palette would draw magenta.
	if _swatches.size() != palette.size():
		_rebuild_swatches()
	else:
		_apply_swatch_colors()
	_apply_palette()
	_refresh_readout()


func _apply_palette() -> void:
	var dim: Color = _role_color("text_dim")
	for label: Label in _dim_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", dim)
	_apply_swatch_colors()
	queue_redraw()


# ---------------------------------------------------------------- helpers


func _active_palette() -> PackedColorArray:
	if _ship_theme == null:
		return PackedColorArray()
	return _ship_theme.active_palette


## The only sanctioned colour lookup. Never an index (SPEC section 11).
func _role_color(role: String) -> Color:
	if _ship_theme == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	return _ship_theme.color_for_role(role)


func _set_status(text: String) -> void:
	if _builder != null:
		_builder.set_status(text)


func _family_of(doc: ShipDoc, part_id: String) -> String:
	if doc == null:
		return ""
	var raw: Variant = doc.parts.get(part_id, null)
	if raw is ShipPart:
		var part: ShipPart = raw
		return part.family
	return ""


static func _label_of(entry: Dictionary, fallback: String) -> String:
	return _text_of(entry, "label").to_upper() if entry.has("label") else fallback.to_upper()


static func _text_of(entry: Dictionary, key: String) -> String:
	var value: Variant = entry.get(key, null)
	if value is String:
		var text: String = value
		return text
	return ""
