## GaugesPanel - the complexity meter, then the four physical budget bars: BBOX, VOLUME,
## WEIGHT, COST (SPEC section 8).
##
## COMPLEXITY IS THE FIRST BAR BECAUSE IN SPORE IT IS THE ONLY ONE
## ----------------------------------------------------------------
## The UFO editor has no physical budgets at all - its parts are 100% cosmetic and
## "won't affect its attributes" (SPORE_CLONE_SPEC section 0). Complexity plus a 3-part
## minimum is the entire constraint model, and it is the wall players actually meet:
## "Adding parts will increase the complexity of the creation until it reaches the maximum
## amount, at which point nothing else can be added." The four bars under it are THIS
## project's divergence, not Spore's, so the Spore gate reads first and the physical
## budgets read as the addition they are.
##
## THE 148 CAP IS BORROWED AND THE BORROWING IS DELIBERATE. Four independent research
## passes established that the ship editor has a complexity ceiling, configured separately
## for that editor and confirmed by modder testing - and that its numeric value is
## unpublished anywhere reachable (SPORE_CLONE_SPEC section 5, wall 2). The only documented
## figure in the entire game is the CREATURE cap: 138 base, 148 outfitted. `ShipConfig`
## ships 148 as a stand-in with that citation attached. It is a placeholder with a source,
## not a measurement of the UFO editor, and `data/tuning.json` -> `max_complexity` is the
## one place to move it if a real figure ever surfaces.
##
## IT IS NOT DEBOUNCED, AND THAT IS BY CONTRACT. `ShipComplexity` is cheap - one pass over
## `part_order()`, no SDF sampling, no grid (API_CONTRACT_SPORE section 5) - so it is
## recomputed on every `doc_changed` alongside the cheap bbox. The 250 ms idle timer below
## still guards VOLUME / WEIGHT / COST, which are the expensive ones. Do not move complexity
## behind that timer: the palette's red-out test already runs it per edit, so a debounced
## gauge would disagree with the palette for 250 ms about the same number.
##
## IT DOES NOT TOUCH THE ALERT CHANNEL. `set_budget_alert()` takes a `ShipBudgets` key and
## the four physical budgets own that channel; there is no complexity key and inventing one
## would mean this panel fighting itself over the console palette. Over the cap, the
## complexity bar goes to the `warning` role and nothing else changes.
##
## METRICS ARE EXPENSIVE AND THIS PANEL IS WHERE THAT IS MANAGED. ShipMetrics.compute() runs
## a full sampling grid through ShipSdf; a 250 m ship is hundreds of thousands of sample()
## calls even after the adaptive cell has coarsened. Calling it from doc_changed would put
## that on every keystroke in the inspector. So:
##
##   - doc_changed runs ShipMetrics.compute_bbox() ONLY - the cheap, grid-free union of
##     transformed part AABBs - and restarts a 250 ms one-shot Timer.
##   - the Timer's timeout runs the full pass, once, when the user has stopped editing.
##   - between passes the BBOX bar is live and the other three show the last full pass. That
##     window is stated here rather than hidden: for the first 250 ms of a session, and for
##     250 ms after any edit, VOLUME/WEIGHT/COST are one edit stale.
##
## The retained ShipMetrics is mutated in place on the cheap path (`_metrics.bbox = ...`) so
## ShipBudgets.usage() keeps seeing one coherent record with a fresh bbox and the last known
## volume/weight/cost, instead of the panel re-deriving ratios by hand.
##
## SAMPLE CELL. metrics.sample_cell_m is ADAPTIVE and is NOT cfg.metrics_cell_m - the
## requested cell is a floor that _choose_cell() coarsens upward until the grid fits the
## sample budget. The footer prints the cell that was actually used, because a volume read at
## 1.4 m means something different from one read at 0.5 m.
##
## TAKING ALERT CONTROL. The first set_budget_alert() call switches ShipBuilder's own
## bbox-only auto-check off permanently, so from that moment this panel owns the alert state
## for all four budgets. It is therefore called on EVERY refresh, cheap or full, with
## ShipBudgets.budget_key(top_violation()) - which is "" when nothing is violated, exactly
## the clear signal.
##
## Colour is role-only (SPEC section 11): "accent" for a bar under its cap, "warning" for one
## over it, re-resolved on palette_changed because a maxed budget swaps the whole 16-entry
## LUT and any cached Color would be from the previous one.
class_name GaugesPanel
extends VBoxContainer

## SPEC section 8 order, which is also ShipBudgets.Budget's enum order.
const BUDGET_NAMES: Array = ["BBOX", "VOLUME", "WEIGHT", "COST"]
const BUDGET_UNITS: Array = ["M", "M3", "KG", ""]
const BUDGET_COUNT: int = 4

## The complexity row's label. Kept out of BUDGET_NAMES on purpose: those four indices are
## ShipBudgets.Budget enum values and _ratios/_names/_readouts are indexed by them, so
## prepending a fifth entry would silently reindex every budget in this file.
const COMPLEXITY_NAME: String = "COMPLEX"

## Idle window before the full grid pass runs. API_CONTRACT_UI section 3.
const IDLE_SECONDS: float = 0.25

const BAR_HEIGHT: float = 11.0
const ROW_HEIGHT: float = 13.0
const NAME_WIDTH: float = 62.0
const READOUT_WIDTH: float = 190.0
const TICK_LENGTH: float = 4.0
const AXIS_NAMES: Array = ["X", "Y", "Z"]

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null

## The last full pass, with its bbox kept live by the cheap path between passes.
var _metrics: ShipMetrics = ShipMetrics.new()
var _timer: Timer = null
var _footer: Label = null
var _bars: Array[Control] = []
var _names: Array[Label] = []
var _readouts: Array[Label] = []
## Budget -> usage ratio, 1.0 meaning exactly at the cap. Not clamped here; the draw clamps.
var _ratios: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

## The complexity row. Held in its own members rather than appended to the four arrays
## above - see COMPLEXITY_NAME.
var _cx_bar: Control = null
var _cx_name: Label = null
var _cx_readout: Label = null
var _cx_used: float = 0.0
var _cx_cap: float = 0.0
var _cx_ratio: float = 0.0


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 1)

	add_child(_make_complexity_row())
	# One rule between the Spore gate and this project's physical budgets. They are two
	# different constraint systems that both hard-block (API_CONTRACT_SPORE section 6), and
	# a player who cannot see the seam cannot tell which one just refused them.
	add_child(HSeparator.new())

	for index: int in BUDGET_COUNT:
		add_child(_make_row(index))

	_footer = Label.new()
	_footer.name = "GaugeFooter"
	_footer.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_footer.text = "CELL ---  AREA ---"
	add_child(_footer)

	_timer = Timer.new()
	_timer.name = "MetricsIdle"
	_timer.wait_time = IDLE_SECONDS
	_timer.one_shot = true
	_timer.timeout.connect(_on_metrics_idle)
	add_child(_timer)


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
	_apply_palette()
	_refresh_bbox()
	_timer.start()


# ---------------------------------------------------------------- construction


## The complexity row, structurally identical to a budget row but wired to its own members.
func _make_complexity_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "GaugeComplexity"
	row.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	row.add_theme_constant_override("separation", 4)

	_cx_name = Label.new()
	_cx_name.text = COMPLEXITY_NAME
	_cx_name.custom_minimum_size = Vector2(ShipTheme.pxf(NAME_WIDTH), ShipTheme.pxf(0.0))
	_cx_name.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(_cx_name)

	_cx_bar = Control.new()
	_cx_bar.name = "BarComplexity"
	_cx_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cx_bar.custom_minimum_size = Vector2(ShipTheme.pxf(60.0), ShipTheme.pxf(BAR_HEIGHT))
	_cx_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_cx_bar.draw.connect(_on_complexity_bar_draw)
	row.add_child(_cx_bar)

	_cx_readout = Label.new()
	_cx_readout.text = "---"
	_cx_readout.custom_minimum_size = Vector2(ShipTheme.pxf(READOUT_WIDTH), ShipTheme.pxf(0.0))
	_cx_readout.clip_text = true
	_cx_readout.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(_cx_readout)
	return row


func _make_row(index: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Gauge" + str(BUDGET_NAMES[index])
	row.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	row.add_theme_constant_override("separation", 4)

	var name_label: Label = Label.new()
	name_label.text = str(BUDGET_NAMES[index])
	name_label.custom_minimum_size = Vector2(ShipTheme.pxf(NAME_WIDTH), ShipTheme.pxf(0.0))
	name_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(name_label)
	_names.append(name_label)

	var bar: Control = Control.new()
	bar.name = "Bar" + str(BUDGET_NAMES[index])
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(ShipTheme.pxf(60.0), ShipTheme.pxf(BAR_HEIGHT))
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	# CanvasItem.draw fires on redraw; binding the index keeps four identical bars on one
	# handler without a Control subclass per bar.
	bar.draw.connect(_on_bar_draw.bind(index))
	row.add_child(bar)
	_bars.append(bar)

	var readout: Label = Label.new()
	readout.text = "---"
	readout.custom_minimum_size = Vector2(ShipTheme.pxf(READOUT_WIDTH), ShipTheme.pxf(0.0))
	readout.clip_text = true
	readout.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(readout)
	_readouts.append(readout)
	return row


# ---------------------------------------------------------------- metrics


## Cheap path. compute_bbox() has no grid: it is the union of the transformed part AABBs and
## is what the bbox budget is allowed to read on every single edit.
func _on_doc_changed(_doc: ShipDoc) -> void:
	_refresh_bbox()
	# Restarting rather than starting: continuous editing keeps deferring the full pass,
	# which is the entire point of an idle debounce.
	_timer.start()


func _refresh_bbox() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		_refresh_display()
		return
	_metrics.bbox = ShipMetrics.compute_bbox(doc, data, cfg)
	_refresh_display()


## The full grid pass, and the only place it runs. Never call this from a signal handler.
func _on_metrics_idle() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return
	var sdf: ShipSdf = ShipSdf.build(doc, data, cfg)
	_metrics = ShipMetrics.compute(sdf, doc, data, cfg)
	_refresh_display()


# ---------------------------------------------------------------- display


## The complexity total. Cheap by contract (API_CONTRACT_SPORE section 5) and therefore run
## on the same path as the cheap bbox, never behind the idle timer.
##
## `used` already carries the symmetry doubling: a part that generates a mirrored twin is
## billed twice and the twin is not billed at all, so breaking symmetry on a part HALVES its
## contribution to this number. That is a documented Spore trade-off, not an exploit to
## hide - the tooltip says so out loud.
func _refresh_complexity() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return
	var state: Dictionary = ShipComplexity.compute(doc, data, cfg)
	_cx_used = float(state.get("used", 0.0))
	_cx_cap = float(state.get("cap", 0.0))
	_cx_ratio = 0.0
	if is_finite(_cx_cap) and _cx_cap > 0.0:
		_cx_ratio = _cx_used / _cx_cap
	_cx_readout.text = "%s / %s" % [NumericField.format_number(_cx_used), _cap_text(_cx_cap)]
	_cx_bar.tooltip_text = _complexity_tooltip()
	_cx_bar.queue_redraw()


func _complexity_tooltip() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("COMPLEXITY  %s%%" % NumericField.format_number(_cx_ratio * 100.0))
	lines.append("%s / %s PARTS-WORTH" % [NumericField.format_number(_cx_used), _cap_text(_cx_cap)])
	lines.append("SPORE'S OWN GATE - AN UNAFFORDABLE PART REDDENS IN THE PALETTE")
	lines.append("A SYMMETRIC PART COSTS DOUBLE; BREAKING ITS SYMMETRY HALVES IT")
	if _cx_ratio > 1.0:
		lines.append("OVER THE CAP - REMOVE A PART OR BREAK SYMMETRY")
	return "\n".join(lines)


func _refresh_display() -> void:
	var cfg: ShipConfig = _builder.get_config()
	if cfg == null:
		return
	_refresh_complexity()
	var usage: Dictionary = ShipBudgets.usage(_metrics, cfg)
	for index: int in BUDGET_COUNT:
		_ratios[index] = _ratio_of(usage, index)
		_readouts[index].text = _readout_for(index, cfg)
		_bars[index].tooltip_text = _tooltip_for(index, cfg)
		_bars[index].queue_redraw()
	_footer.text = (
		"CELL %s M   AREA %s M2"
		% [
			NumericField.format_number(_metrics.sample_cell_m),
			NumericField.format_number(_metrics.surface_area_m2),
		]
	)
	# Alert control is ours from the first call onwards, so all four budgets are reported
	# every time. budget_key(-1) is "", which is exactly the "clear the alert" argument.
	_builder.set_budget_alert(ShipBudgets.budget_key(ShipBudgets.top_violation(_metrics, cfg)))
	# Re-tint AFTER the alert, so the row names read from the palette that alert just chose.
	# Not left to palette_changed alone: ShipTheme.set_alert() returns early when the same
	# budget is already alerting, so a SECOND budget going over emits nothing and its name
	# would stay in the normal role.
	_apply_palette()


func _readout_for(index: int, cfg: ShipConfig) -> String:
	var unit: String = str(BUDGET_UNITS[index])
	if index == ShipBudgets.Budget.BBOX:
		var axis: int = _driving_axis(cfg)
		return (
			"%s %s / %s %s"
			% [
				str(AXIS_NAMES[axis]),
				NumericField.format_number(_metrics.bbox.size.abs()[axis]),
				NumericField.format_number(cfg.max_bbox_m[axis]),
				unit,
			]
		)
	return (
		"%s / %s %s"
		% [
			NumericField.format_number(_used_of(index)),
			_cap_text(_cap_of(index, cfg)),
			unit,
		]
	)


## An unbounded cap must not be printed as a number.
##
## `data/tuning.json` uses -1 as the documented "unbounded" sentinel (JSON has no Infinity
## literal), and ShipBudgets already treats INF, NAN and <= 0 alike as "no cap, usage 0.0".
## Rendering that through format_number() put a literal "COST 141.943 / -1.000" on the gauge
## strip, which reads as a cap of minus one rather than as no cap at all.
func _cap_text(cap: float) -> String:
	if not is_finite(cap) or cap <= 0.0:
		return "UNCAPPED"
	return NumericField.format_number(cap)


func _tooltip_for(index: int, cfg: ShipConfig) -> String:
	var percent: float = _ratios[index] * 100.0
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s  %s%%" % [str(BUDGET_NAMES[index]), NumericField.format_number(percent)])
	lines.append(_readout_for(index, cfg))
	lines.append("SAMPLE CELL %s M" % NumericField.format_number(_metrics.sample_cell_m))
	if index != ShipBudgets.Budget.BBOX:
		lines.append("FROM THE LAST FULL GRID PASS")
	return "\n".join(lines)


## Plain comparisons rather than a `match`: a match PATTERN has to be a constant expression,
## and leaning on another class's enum in that position is a compile-time subtlety this does
## not need. BBOX is absent on purpose - it is per axis and _readout_for() handles it.
func _used_of(index: int) -> float:
	if index == ShipBudgets.Budget.VOLUME:
		return _metrics.internal_volume_m3
	if index == ShipBudgets.Budget.WEIGHT:
		return _metrics.weight_kg
	if index == ShipBudgets.Budget.COST:
		return _metrics.cost
	return 0.0


static func _cap_of(index: int, cfg: ShipConfig) -> float:
	if index == ShipBudgets.Budget.VOLUME:
		return cfg.max_internal_volume_m3
	if index == ShipBudgets.Budget.WEIGHT:
		return cfg.max_weight_kg
	if index == ShipBudgets.Budget.COST:
		return cfg.max_cost
	return 0.0


## SPEC section 8: max_bbox is PER AXIS, not a diagonal. The bar reads the axis that is
## closest to its own cap, so the number beside it is the one that would actually block.
func _driving_axis(cfg: ShipConfig) -> int:
	var size: Vector3 = _metrics.bbox.size.abs()
	var cap: Vector3 = cfg.max_bbox_m
	var best: int = 0
	var best_ratio: float = -1.0
	for axis: int in 3:
		var limit: float = cap[axis]
		var ratio: float = 0.0
		if is_finite(limit) and limit > 0.0:
			ratio = size[axis] / limit
		if ratio > best_ratio:
			best_ratio = ratio
			best = axis
	return best


static func _ratio_of(usage: Dictionary, index: int) -> float:
	var value: Variant = usage.get(index, 0.0)
	var kind: int = typeof(value)
	if kind != TYPE_FLOAT and kind != TYPE_INT:
		return 0.0
	var out: float = value
	if is_nan(out):
		return 0.0
	return out


# ---------------------------------------------------------------- drawing


## One horizontal fill bar: a filled ground, a fill proportional to usage, and a 1 px box
## (SPEC section 11). Over the cap the whole bar goes to the warning role, so a violation is
## legible even in the alert palette the violation itself just swapped in.
func _on_bar_draw(index: int) -> void:
	_paint_bar(_bars[index], _ratios[index])


func _on_complexity_bar_draw() -> void:
	_paint_bar(_cx_bar, _cx_ratio)


func _paint_bar(bar: Control, raw_ratio: float) -> void:
	if not is_instance_valid(bar):
		return
	var rect: Rect2 = Rect2(Vector2.ZERO, bar.size)
	var over: bool = raw_ratio > 1.0
	bar.draw_rect(rect, _role_color("background"), true)
	var ratio: float = clampf(raw_ratio, 0.0, 1.0)
	var width: float = floorf(rect.size.x * ratio)
	if width >= 1.0:
		var fill: Color = _role_color("warning") if over else _role_color("accent")
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(width, rect.size.y)), fill, true)
	bar.draw_rect(rect, _role_color("line"), false, 1.0)


# ---------------------------------------------------------------- palette


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_apply_palette()


func _apply_palette() -> void:
	var text: Color = _role_color("text")
	var dim: Color = _role_color("text_dim")
	for index: int in _names.size():
		var over: bool = index < _ratios.size() and _ratios[index] > 1.0
		_names[index].add_theme_color_override(
			"font_color", _role_color("warning") if over else text
		)
		_readouts[index].add_theme_color_override("font_color", text)
	if _cx_name != null:
		var cx_over: bool = _cx_ratio > 1.0
		_cx_name.add_theme_color_override("font_color", _role_color("warning") if cx_over else text)
	if _cx_readout != null:
		_cx_readout.add_theme_color_override("font_color", text)
	if _footer != null:
		_footer.add_theme_color_override("font_color", dim)
	for bar: Control in _bars:
		if is_instance_valid(bar):
			bar.queue_redraw()
	if is_instance_valid(_cx_bar):
		_cx_bar.queue_redraw()
	queue_redraw()


## The only sanctioned colour lookup. Never an index (SPEC section 11), and re-resolved on
## every palette_changed because a maxed budget swaps the entire LUT.
func _role_color(role: String) -> Color:
	if _ship_theme == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	return _ship_theme.color_for_role(role)
