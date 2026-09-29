## ShipTheme - the single source of colour for the entire builder (SPEC section 11).
##
## The whole SubViewport is quantized through ONE 16-entry palette, so the 3D view and
## the UI share a colour language automatically instead of being matched by hand. This
## class is the only place that knows what an index means:
##
##   - it loads data/palette.json (base LUT + one alert LUT per budget + a roles map),
##   - color_for_role() resolves a SEMANTIC name, so no UI code ever hardcodes an index,
##   - build_theme() produces the Godot Theme every panel inherits,
##   - set_alert() swaps the shader palette[] uniform to a budget alert palette.
##
## That last one is the whole "a budget maxes out and the console changes colour"
## feature: one uniform write plus an in-place recolour of the shared Theme, not a UI
## refactor. Panels that used color_for_role() or the inherited Theme follow for free.
##
## Loading is deliberately defensive: a missing or malformed pack falls back to a
## hardcoded 16-entry blue-green ramp so the app still runs and still looks like itself.
class_name ShipTheme
extends RefCounted

## Emitted after any change to the active palette (load, set_alert, clear_alert).
signal palette_changed(palette: PackedColorArray)

const PALETTE_SIZE: int = 16
## The shipped dither strength. Named so a mode that needs more of it (CLAY, whose shading is a
## continuous gradient rather than palette bands) can put it back afterwards.
const DITHER_DEFAULT: float = 0.06
const PALETTE_PATH: String = "res://data/palette.json"

## Design font sizes, in pixels AT THE DEVICE RESOLUTION (DESIGN_SIZE). Never used raw for a
## font_size override - go through font_small() / font_normal() / font_title(), which apply
## `ui_scale`. Raw use is what made a maximised desktop window render 10px labels.
const FONT_SIZE_NORMAL: int = 13
const FONT_SIZE_SMALL: int = 11
const FONT_SIZE_TITLE: int = 16

## The diegetic device's resolution (SPEC section 10). Every hardcoded pixel metric in the
## builder is authored against this, and `ui_scale` maps it onto whatever the host actually gave
## us.
const DESIGN_SIZE: Vector2i = Vector2i(1280, 800)

## Bounds and quantization for `ui_scale`. Quantized so a window drag does not restyle the whole
## console every pixel, and floored at 1.0 because shrinking below the design size makes the
## console illegible rather than merely cramped - the host crops instead (DevHost.MIN_SIZE).
const UI_SCALE_MIN: float = 1.0
const UI_SCALE_MAX: float = 3.0
const UI_SCALE_STEP: float = 0.25


## Role names the pack is required to carry (SPEC section 11).
const ROLE_NAMES: Array = [
	"background",
	"grid",
	"text",
	"text_dim",
	"line",
	"accent",
	"selection",
	"warning",
	"ghost",
]

## Shading ramps the pack is required to carry. Unlike a role (one colour) a ramp is an ORDERED
## list of LUT indices used as the discrete shading bands of a 3D part, darkest first.
##
## WHY RAMPS EXIST AT ALL. A part used to be one albedo multiplied by a lambert term, and the
## result was handed to the 16-entry quantizer to land wherever it landed. It landed badly: the
## two shaded bands of a selected amber part measured as #9f752d and #ba8936, and the quantizer
## put one on the warning red and the other on the background - so a cube rendered as a single
## flat lit face floating in space with no sides. Choosing a LUT ENTRY per band instead means
## every shaded face is already an exact palette colour and the quantizer cannot move it.
const RAMP_NAMES: Array = [
	"part",
	"part_selected",
	"ghost",
]

## Global UI scale: 1.0 IS the device, and the device never changes, so in the shipping diegetic
## host this is 1.0 forever and nothing below does anything.
##
## It exists for the dev host, where the console renders at the desktop window's resolution so
## text stays crisp instead of being magnified out of a small buffer. At 2560x1377 that left every
## label at its 11px design size - about 4mm on screen - which is the "hard to read that font"
## the author reported. Scaling the METRICS instead of upscaling the TEXTURE keeps glyphs
## natively rasterised at their real size.
##
## Static because font overrides are applied while panels build, before any panel has been handed
## a ShipTheme instance. Read it through px()/font_*() rather than directly.
static var ui_scale: float = 1.0

var base_palette: PackedColorArray = PackedColorArray()
var active_palette: PackedColorArray = PackedColorArray()
## budget_key ("bbox"|"volume"|"weight"|"cost") -> PackedColorArray of PALETTE_SIZE.
var alerts: Dictionary = {}
## role name -> LUT index.
var roles: Dictionary = {}
## ramp name -> PackedInt32Array of LUT indices, darkest band first.
var ramps: Dictionary = {}
## Non-fatal complaints from the last load_pack(). Empty means the pack was clean.
var load_errors: PackedStringArray = PackedStringArray()
## "" when no budget is alerting, else the budget key whose LUT is live.
var active_alert: String = ""

## Render-type palette variants by name, each a full 16-entry LUT. See [method set_variant].
var variants: Dictionary = {}

## The variant in force, or "" for base. See [method set_variant] for the precedence rule.
var active_variant: String = ""

var dither_enabled: bool = false
var dither_strength: float = DITHER_DEFAULT

var _post_material: ShaderMaterial = null
var _theme: Theme = null
var _styles: Dictionary = {}
## style key -> Vector2i(border_px, margin_px) as AUTHORED, before ui_scale. Kept so a scale
## change recomputes from the design value instead of compounding rounding off the live box.
var _style_specs: Dictionary = {}


## Scale for a viewport of `view` pixels: how many times the design resolution fits, taking the
## tighter of the two axes so a wide, short window does not blow the type up past the height.
static func scale_for(view: Vector2) -> float:
	if view.x <= 0.0 or view.y <= 0.0:
		return 1.0
	var raw: float = minf(view.x / float(DESIGN_SIZE.x), view.y / float(DESIGN_SIZE.y))
	var stepped: float = floorf(raw / UI_SCALE_STEP) * UI_SCALE_STEP
	return clampf(stepped, UI_SCALE_MIN, UI_SCALE_MAX)


## Any authored pixel metric, scaled. Widths, heights, margins - anything laid out in pixels
## against DESIGN_SIZE.
static func px(v: int) -> int:
	if v == 0:
		return 0
	return maxi(1, int(roundf(float(v) * ui_scale)))


## Float form, for a metric that is legitimately zero (a Vector2 minimum size with one free axis)
## and must stay zero rather than being floored to one pixel.
static func pxf(v: float) -> float:
	return v * ui_scale


static func font_small() -> int:
	return px(FONT_SIZE_SMALL)


static func font_normal() -> int:
	return px(FONT_SIZE_NORMAL)


static func font_title() -> int:
	return px(FONT_SIZE_TITLE)


## Restyle an already-built Control tree for a new scale, then adopt it.
##
## Rescales EXISTING values by new/old rather than recomputing them from the design constants, so
## it needs no record of what each override was authored as and stays exact across repeated
## resizes. Two things move: font_size overrides (the type) and custom_minimum_size (the space the
## type has to live in). Scaling only the first is what makes big text overflow small panels.
static func apply_ui_scale(root: Node, new_scale: float) -> void:
	var old_scale: float = ui_scale
	if root == null or is_equal_approx(new_scale, old_scale) or old_scale <= 0.0:
		return
	var factor: float = new_scale / old_scale
	ui_scale = new_scale
	_rescale_tree(root, factor)


static func _rescale_tree(n: Node, factor: float) -> void:
	var ctl: Control = n as Control
	if ctl != null:
		if ctl.has_theme_font_size_override("font_size"):
			var current: int = ctl.get_theme_font_size("font_size")
			ctl.add_theme_font_size_override(
				"font_size", maxi(1, int(roundf(float(current) * factor)))
			)
		var minimum: Vector2 = ctl.custom_minimum_size
		if minimum != Vector2.ZERO:
			ctl.custom_minimum_size = minimum * factor
	for c: Node in n.get_children():
		_rescale_tree(c, factor)


func _init() -> void:
	base_palette = _fallback_palette()
	active_palette = base_palette
	roles = _fallback_roles()
	ramps = _fallback_ramps()


# ---------------------------------------------------------------- loading


## Load the palette pack. Prefers the already-parsed ShipData.palette when one is handed
## in; otherwise reads the JSON directly (harness/ is not bound by the core/ purity rule,
## so touching res:// here is legal). Never fails - falls back instead.
func load_pack(data: ShipData = null) -> void:
	load_errors = PackedStringArray()
	var pack: Dictionary = {}
	if data != null and not data.palette.is_empty():
		pack = data.palette
	else:
		pack = _read_pack_file()
	if pack.is_empty():
		load_errors.append("palette pack unavailable; using the built-in fallback ramp")
		base_palette = _fallback_palette()
		roles = _fallback_roles()
		ramps = _fallback_ramps()
		alerts = {}
	else:
		_parse_pack(pack)
	active_alert = ""
	active_variant = ""
	active_palette = base_palette
	_push_palette_uniform()
	_apply_theme_colors()
	palette_changed.emit(active_palette)


func _read_pack_file() -> Dictionary:
	if not FileAccess.file_exists(PALETTE_PATH):
		load_errors.append("missing %s" % PALETTE_PATH)
		return {}
	var text: String = FileAccess.get_file_as_string(PALETTE_PATH)
	if text.is_empty():
		load_errors.append("empty %s" % PALETTE_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		load_errors.append("malformed JSON in %s" % PALETTE_PATH)
		return {}
	return parsed


func _parse_pack(pack: Dictionary) -> void:
	base_palette = _colors_from(pack.get("base", null), "base")
	if base_palette.size() < PALETTE_SIZE:
		base_palette = _fallback_palette()

	alerts = {}
	var raw_variants: Variant = pack.get("variants", null)
	if typeof(raw_variants) == TYPE_DICTIONARY:
		var variant_dict: Dictionary = raw_variants
		for key: Variant in variant_dict:
			# `_description` is prose for the reader, not a palette.
			if str(key).begins_with("_"):
				continue
			var colors: PackedColorArray = _colors_from(variant_dict[key], "variants." + str(key))
			if colors.size() == PALETTE_SIZE:
				variants[str(key)] = colors
	var raw_alerts: Variant = pack.get("alerts", null)
	if typeof(raw_alerts) == TYPE_DICTIONARY:
		var alert_dict: Dictionary = raw_alerts
		for key: Variant in alert_dict.keys():
			var budget_key: String = str(key)
			var cols: PackedColorArray = _colors_from(alert_dict[key], "alerts." + budget_key)
			if cols.size() >= PALETTE_SIZE:
				alerts[budget_key] = cols
	else:
		load_errors.append("pack has no alerts object; budget alerts will not flip the LUT")

	roles = _fallback_roles()
	var raw_roles: Variant = pack.get("roles", null)
	if typeof(raw_roles) == TYPE_DICTIONARY:
		var role_dict: Dictionary = raw_roles
		for key: Variant in role_dict.keys():
			var role_name: String = str(key)
			var v: Variant = role_dict[key]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				roles[role_name] = clampi(int(v), 0, PALETTE_SIZE - 1)
			else:
				load_errors.append("role %s is not an index" % role_name)
	else:
		load_errors.append("pack has no roles object; using fallback role indices")

	for role_entry: Variant in ROLE_NAMES:
		var required: String = str(role_entry)
		if not roles.has(required):
			load_errors.append("pack is missing role %s" % required)

	ramps = _fallback_ramps()
	var raw_ramps: Variant = pack.get("ramps", null)
	if typeof(raw_ramps) == TYPE_DICTIONARY:
		var ramp_dict: Dictionary = raw_ramps
		for key: Variant in ramp_dict.keys():
			var ramp_name: String = str(key)
			var indices: PackedInt32Array = _indices_from(ramp_dict[key], "ramps." + ramp_name)
			if indices.size() >= 2:
				ramps[ramp_name] = indices
	else:
		load_errors.append("pack has no ramps object; using fallback shading ramps")

	for ramp_entry: Variant in RAMP_NAMES:
		var ramp_required: String = str(ramp_entry)
		if not ramps.has(ramp_required):
			load_errors.append("pack is missing ramp %s" % ramp_required)


func _indices_from(v: Variant, where: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if typeof(v) != TYPE_ARRAY:
		load_errors.append("%s is not an array" % where)
		return out
	var arr: Array = v
	for entry: Variant in arr:
		if typeof(entry) != TYPE_INT and typeof(entry) != TYPE_FLOAT:
			load_errors.append("%s has a non-integer entry" % where)
			return PackedInt32Array()
		var idx: int = int(entry)
		if idx < 0 or idx >= PALETTE_SIZE:
			load_errors.append("%s index %d is outside the LUT" % [where, idx])
			return PackedInt32Array()
		out.append(idx)
	if out.size() < 2:
		load_errors.append("%s has %d entries, expected at least 2" % [where, out.size()])
	return out


func _colors_from(v: Variant, where: String) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	if typeof(v) != TYPE_ARRAY:
		load_errors.append("%s is not an array" % where)
		return out
	var arr: Array = v
	for entry: Variant in arr:
		if typeof(entry) != TYPE_STRING:
			load_errors.append("%s has a non-string entry" % where)
			return PackedColorArray()
		var hex: String = str(entry)
		if not Color.html_is_valid(hex):
			load_errors.append("%s has an invalid colour %s" % [where, hex])
			return PackedColorArray()
		out.append(Color.html(hex))
	if out.size() != PALETTE_SIZE:
		load_errors.append("%s has %d entries, expected %d" % [where, out.size(), PALETTE_SIZE])
	return out


# ---------------------------------------------------------------- roles


## The only sanctioned way to get a colour. Ask for a role, never an index.
func color_for_role(role: String) -> Color:
	var idx: int = int(roles.get(role, -1))
	if idx < 0 or idx >= active_palette.size():
		return _fallback_color_for_role(role)
	return active_palette[idx]


## Same colour with an alpha override, for ghosts and dimmed overlays.
func color_for_role_a(role: String, alpha: float) -> Color:
	var c: Color = color_for_role(role)
	c.a = alpha
	return c


func index_for_role(role: String) -> int:
	return int(roles.get(role, -1))


## The colours of a named shading ramp, darkest band first, resolved against the ACTIVE palette
## so an alert LUT swap recolours parts along with everything else. Never empty: an unknown or
## malformed ramp falls back to a two-step ramp built from the part role, which shades badly but
## is always visible - the failure this whole mechanism exists to avoid is an invisible part.
func ramp_for(name: String) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	var raw: Variant = ramps.get(name, null)
	if raw is PackedInt32Array:
		var indices: PackedInt32Array = raw
		for idx: int in indices:
			if idx >= 0 and idx < active_palette.size():
				out.append(active_palette[idx])
	if out.size() >= 2:
		return out
	out = PackedColorArray()
	out.append(color_for_role("line"))
	out.append(color_for_role("text_dim"))
	return out


## The ramp's indices as stored. Mostly for tools and tests that assert pack shape.
func ramp_indices(name: String) -> PackedInt32Array:
	var raw: Variant = ramps.get(name, null)
	if raw is PackedInt32Array:
		return raw
	return PackedInt32Array()


func color_at(index: int) -> Color:
	if index < 0 or index >= active_palette.size():
		return Color.MAGENTA
	return active_palette[index]


# ---------------------------------------------------------------- alerts


## Point the post-process LUT at a budget alert palette. SPEC section 8: this is what a
## maxed budget does. One uniform write; the Theme is recoloured in place so live panels
## follow without being rebuilt.
func set_alert(budget_key: String) -> void:
	if active_alert == budget_key:
		return
	if not alerts.has(budget_key):
		# No alert LUT authored for this budget - stay on base rather than invent one.
		if active_alert != "":
			clear_alert()
		return
	active_alert = budget_key
	active_palette = alerts[budget_key]
	_push_palette_uniform()
	_apply_theme_colors()
	palette_changed.emit(active_palette)


func clear_alert() -> void:
	if active_alert == "":
		return
	active_alert = ""
	# Back to the VARIANT if one is live, not straight to base - otherwise a budget alert that
	# came and went while CLAY was on would drop the render type's palette on the floor.
	active_palette = _palette_now()
	_push_palette_uniform()
	_apply_theme_colors()
	palette_changed.emit(active_palette)


# ---------------------------------------------------------------- render-type variants


## Wear a named render-type palette variant - "clay" is the only one authored (ADR 0049). Passing
## "" clears it. Unknown names clear it too, rather than inventing a LUT.
##
## THE ONE PRECEDENCE RULE: AN ACTIVE BUDGET ALERT ALWAYS BEATS A VARIANT. A maxed budget is the
## most important thing on the screen and must never be hidden by a pretty render mode, so this
## records the variant and then defers - the alert's own palette stays up, and the variant takes
## effect the moment [method clear_alert] runs.
func set_variant(name: String) -> void:
	var wanted: String = name if variants.has(name) else ""
	if wanted == active_variant:
		return
	active_variant = wanted
	if active_alert != "":
		# Recorded, deferred. clear_alert() picks it up.
		return
	active_palette = _palette_now()
	_push_palette_uniform()
	_apply_theme_colors()
	palette_changed.emit(active_palette)


## The LUT that should be up right now, alert first, then variant, then base.
func _palette_now() -> PackedColorArray:
	if active_alert != "" and alerts.has(active_alert):
		return alerts[active_alert]
	if active_variant != "" and variants.has(active_variant):
		return variants[active_variant]
	return base_palette


# ---------------------------------------------------------------- shader


## Bind the ColorRect material running shaders/palette_post.gdshader. Every later palette
## change writes straight into it.
func bind_post_material(mat: ShaderMaterial) -> void:
	_post_material = mat
	_push_palette_uniform()


func set_dither(on: bool) -> void:
	dither_enabled = on
	_push_palette_uniform()


func set_dither_strength(v: float) -> void:
	dither_strength = clampf(v, 0.0, 0.5)
	_push_palette_uniform()


func _push_palette_uniform() -> void:
	if _post_material == null:
		return
	# vec3 palette[16] - upload raw sRGB components; see the shader header comment.
	var vecs: PackedVector3Array = PackedVector3Array()
	for c: Color in active_palette:
		vecs.append(Vector3(c.r, c.g, c.b))
	_post_material.set_shader_parameter("palette", vecs)
	_post_material.set_shader_parameter("palette_size", active_palette.size())
	_post_material.set_shader_parameter("dither_enabled", dither_enabled)
	_post_material.set_shader_parameter("dither_strength", dither_strength)


# ---------------------------------------------------------------- Theme


## Build (once) the Theme every panel inherits. Later palette changes mutate the same
## Theme and StyleBox objects in place, so panels restyle without being rebuilt.
func build_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.default_font = _build_font()
	_theme.default_font_size = font_normal()

	var specs: Dictionary = {
		"panel": Vector2i(1, 4),
		"panel_flat": Vector2i(0, 4),
		"button": Vector2i(1, 4),
		"button_hover": Vector2i(1, 4),
		"button_pressed": Vector2i(1, 4),
		"button_disabled": Vector2i(1, 4),
		"focus": Vector2i(1, 4),
		"line_edit": Vector2i(1, 3),
		"line_edit_focus": Vector2i(1, 3),
		"selected": Vector2i(0, 2),
		"gauge_bg": Vector2i(1, 0),
		"gauge_fill": Vector2i(0, 0),
	}
	for key: Variant in specs.keys():
		var spec: Vector2i = specs[key]
		_style_specs[key] = spec
		_styles[key] = _new_box(spec.x, spec.y)

	var panel_types: PackedStringArray = PackedStringArray(
		["PanelContainer", "Panel", "ScrollContainer", "ItemList", "Tree"]
	)
	for type_name: String in panel_types:
		_theme.set_stylebox("panel", type_name, _styles["panel"])
	_theme.set_stylebox("normal", "Button", _styles["button"])
	_theme.set_stylebox("hover", "Button", _styles["button_hover"])
	_theme.set_stylebox("pressed", "Button", _styles["button_pressed"])
	_theme.set_stylebox("disabled", "Button", _styles["button_disabled"])
	_theme.set_stylebox("focus", "Button", _styles["focus"])
	_theme.set_stylebox("normal", "OptionButton", _styles["button"])
	_theme.set_stylebox("hover", "OptionButton", _styles["button_hover"])
	_theme.set_stylebox("pressed", "OptionButton", _styles["button_pressed"])
	_theme.set_stylebox("disabled", "OptionButton", _styles["button_disabled"])
	_theme.set_stylebox("focus", "OptionButton", _styles["focus"])
	_theme.set_stylebox("normal", "LineEdit", _styles["line_edit"])
	_theme.set_stylebox("focus", "LineEdit", _styles["line_edit_focus"])
	_theme.set_stylebox("selected", "ItemList", _styles["selected"])
	_theme.set_stylebox("cursor", "ItemList", _styles["focus"])
	_theme.set_stylebox("selected", "Tree", _styles["selected"])
	_theme.set_stylebox("selected_focus", "Tree", _styles["selected"])
	_theme.set_stylebox("background", "ProgressBar", _styles["gauge_bg"])
	_theme.set_stylebox("fill", "ProgressBar", _styles["gauge_fill"])

	_apply_theme_metrics()

	_apply_theme_colors()
	return _theme


## Spacing constants and the default font size, (re)applied for the current ui_scale. Split out of
## build_theme() so a scale change can refresh them on the live Theme instead of rebuilding it -
## every panel already points at that object.
func _apply_theme_metrics() -> void:
	if _theme == null:
		return
	_theme.default_font_size = font_normal()
	_theme.set_constant("separation", "HBoxContainer", px(4))
	_theme.set_constant("separation", "VBoxContainer", px(4))
	_theme.set_constant("h_separation", "GridContainer", px(6))
	_theme.set_constant("v_separation", "GridContainer", px(3))


## Adopt a new UI scale across an already-built tree: rescale every override, then refresh the
## shared Theme's own metrics so newly created controls match the ones already on screen.
func rescale_ui(root: Node, new_scale: float) -> void:
	apply_ui_scale(root, new_scale)
	_apply_theme_metrics()
	_apply_style_metrics()
	_apply_theme_colors()


func get_theme() -> Theme:
	return build_theme()


func _build_font() -> Font:
	# Monospace, caps labels, numbers to 3 dp - SPEC section 11. SystemFont picks the
	# first family that exists and silently falls back to the engine default otherwise.
	# Antialiasing and subpixel positioning are off so glyphs stay crisp at the fixed
	# virtual resolution and survive palette quantization without colour fringing.
	var f: SystemFont = SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.hinting = TextServer.HINTING_NONE
	f.generate_mipmaps = false
	return f


## Border and padding are authored against DESIGN_SIZE and scaled on the way in. The DESIGN
## numbers are kept in _style_specs so a later scale change can recompute them from the original
## rather than compounding rounding error off the live box.
func _new_box(border: int, margin: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	_size_box(sb, border, margin)
	return sb


func _size_box(sb: StyleBoxFlat, border: int, margin: int) -> void:
	# A 1px border must survive scaling as a VISIBLE border, so it floors at 1 rather than
	# rounding to 0 on a fractional scale.
	sb.set_border_width_all(0 if border <= 0 else maxi(1, int(roundf(float(border) * ui_scale))))
	sb.content_margin_left = float(px(margin + 2))
	sb.content_margin_right = float(px(margin + 2))
	sb.content_margin_top = float(px(margin))
	sb.content_margin_bottom = float(px(margin))


func _apply_style_metrics() -> void:
	for key: Variant in _style_specs.keys():
		var spec: Vector2i = _style_specs[key]
		var box: StyleBoxFlat = _styles.get(key, null) as StyleBoxFlat
		if box != null:
			_size_box(box, spec.x, spec.y)


func _apply_theme_colors() -> void:
	if _theme == null:
		return
	var bg: Color = color_for_role("background")
	var line: Color = color_for_role("line")
	var text: Color = color_for_role("text")
	var dim: Color = color_for_role("text_dim")
	var accent: Color = color_for_role("accent")
	var sel: Color = color_for_role("selection")
	var warn: Color = color_for_role("warning")

	_style_colors("panel", bg, line)
	_style_colors("panel_flat", bg, line)
	_style_colors("button", bg, line)
	_style_colors("button_hover", line.darkened(0.4), accent)
	_style_colors("button_pressed", accent.darkened(0.5), accent)
	_style_colors("button_disabled", bg, dim.darkened(0.5))
	_style_colors("focus", Color(0.0, 0.0, 0.0, 0.0), accent)
	_style_colors("line_edit", bg.lightened(0.05), line)
	_style_colors("line_edit_focus", bg.lightened(0.05), accent)
	_style_colors("selected", sel.darkened(0.45), sel)
	_style_colors("gauge_bg", bg, line)
	_style_colors("gauge_fill", accent, accent)

	var text_types: PackedStringArray = PackedStringArray(
		["Label", "Button", "OptionButton", "CheckBox", "CheckButton"]
	)
	for type_name: String in text_types:
		_theme.set_color("font_color", type_name, text)
	_theme.set_color("font_hover_color", "Button", accent)
	_theme.set_color("font_pressed_color", "Button", bg)
	_theme.set_color("font_disabled_color", "Button", dim)
	_theme.set_color("font_hover_color", "OptionButton", accent)
	_theme.set_color("font_color", "LineEdit", text)
	_theme.set_color("font_placeholder_color", "LineEdit", dim)
	_theme.set_color("caret_color", "LineEdit", accent)
	_theme.set_color("selection_color", "LineEdit", sel.darkened(0.5))
	_theme.set_color("font_color", "ItemList", text)
	_theme.set_color("font_selected_color", "ItemList", bg)
	_theme.set_color("guide_color", "ItemList", line)
	_theme.set_color("font_color", "Tree", text)
	_theme.set_color("font_selected_color", "Tree", bg)
	_theme.set_color("guide_color", "Tree", line)
	_theme.set_color("relationship_line_color", "Tree", line)
	_theme.set_color("separator", "HSeparator", line)
	_theme.set_color("separator", "VSeparator", line)
	_theme.set_color("warning_color", "Label", warn)


func _style_colors(key: String, bg: Color, border: Color) -> void:
	if not _styles.has(key):
		return
	var sb: StyleBoxFlat = _styles[key]
	sb.bg_color = bg
	sb.border_color = border


# ---------------------------------------------------------------- fallbacks


## Deep ink -> teal -> cyan-green -> pale mint, with warm slots 14/15 reserved for
## selection and warning. Mirrors the shape of data/palette.json so the app still looks
## like itself when the pack is missing or malformed.
static func _fallback_palette() -> PackedColorArray:
	var hex: PackedStringArray = PackedStringArray(
		[
			"#081216",
			"#0f1f24",
			"#153237",
			"#4d3311",
			"#216163",
			"#277c79",
			"#2c968c",
			"#8a5f22",
			"#41c8a9",
			"#5dd0aa",
			"#79d8ab",
			"#bd8734",
			"#b3e6c4",
			"#daf1e0",
			"#e4a944",
			"#dd493c",
		]
	)
	var out: PackedColorArray = PackedColorArray()
	for h: String in hex:
		out.append(Color.html(h))
	return out


## Mirrors data/palette.json's "ramps". Kept in step with _fallback_palette() by hand: this is
## only reached when the pack fails to load, and a wrong ramp there is better than no part.
static func _fallback_ramps() -> Dictionary:
	return {
		"part": PackedInt32Array([4, 6, 9, 12]),
		"part_selected": PackedInt32Array([3, 7, 11, 14]),
		"ghost": PackedInt32Array([2, 4, 6, 8]),
	}


static func _fallback_roles() -> Dictionary:
	return {
		"background": 0,
		"grid": 2,
		"text": 13,
		"text_dim": 8,
		"line": 5,
		"accent": 10,
		"selection": 14,
		"warning": 15,
		"ghost": 10,
	}


func _fallback_color_for_role(role: String) -> Color:
	var idx: int = int(_fallback_roles().get(role, 13))
	if idx < active_palette.size():
		return active_palette[idx]
	return Color.MAGENTA
