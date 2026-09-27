class_name ShipHintBar
extends RefCounted
## THE DIRECTIVE. What [ShipHintText] decided to say, put where a child will actually read it.
##
## The author, 2026-09-27, after seeing the 52 px band proposed on paper:
##
## > "well because its for kids, perhaps experiment with a pop up non-intrusive
## > hint/directive/next options pane, that doesnt ever overlap anything important on screen but
## > puts the directive infront of their face.. maybe even the bottom bar as you stated but much
## > larger and noticable then 52 px idk you experiment with that."
##
## So this renders the SAME resolved text two ways and the layout is a constant, because the only
## way to answer "much larger and noticable" is to look at both:
##
##   BAND - docked full width under the 3D view, replacing the 22 px status strip. Never overlaps
##          anything, because it is laid out rather than floated: the view gives up the height.
##   CARD - a panel floating at the bottom-centre OF THE 3D VIEW, over the ship's empty lower
##          third and never over the side panels. Nothing gives up any height, and the sentence
##          sits inside the same rectangle the player is already looking at.
##
## WHY THE WORDING IS NOT IN HERE. `ShipHintText` is 42 states, a priority ladder and a verbosity
## decay, all of it headlessly tested; a renderer needs a GPU slot and a theme and can test almost
## nothing. Everything that will be got WRONG lives in the other file. This one owns pixels.
##
## THE CARD IS A CHILD OF THE VIEW'S FRAME, not of the builder's root, because it must follow the
## 3D view's rectangle rather than the console's - in BASIC the side columns are gone and the view
## is 400 px wider. `ship_view3d.gd:297` sets `gui_disable_input = true` on the INNER SubViewport,
## so a sibling of the view (which is what this is, like [ShipLayersControl]) still takes input
## while anything placed inside that viewport would not.

enum Layout { BAND, CARD }

## Which layout is built. The author asked for an experiment, so this is the dial it turns.
const LAYOUT: int = Layout.CARD

## Docked height of the BAND, in DESIGN pixels. The paper said 52; the author said larger.
const BAND_HEIGHT: float = 104.0

## The CARD's width as a fraction of the 3D view, and how far it floats off the bottom.
const CARD_WIDTH_FRACTION: float = 0.62
const CARD_MARGIN: float = 14.0

## The LEDE is the largest type in the application - one step above the title, because a sentence
## a child is meant to obey cannot be the same size as a panel heading.
const LEDE_SCALE: float = 1.45

var _lede: Label = null
var _sub: Label = null
var _facts: Label = null
var _strip: Label = null
var _chips: HBoxContainer = null
var _next: Label = null
var _theme: ShipTheme = null
var _card: PanelContainer = null


## Builds into [param host]. For BAND that is the status frame the strip used to fill; for CARD it
## is the 3D view's frame, where it floats as a sibling of the view.
func _init(host: Control, theme: ShipTheme) -> void:
	_theme = theme
	if host == null:
		return
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "HintContent"
	box.add_theme_constant_override("separation", 2)
	if LAYOUT == Layout.CARD:
		var overlay: Control = Control.new()
		overlay.name = "HintLayer"
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(overlay)
		_card = PanelContainer.new()
		_card.name = "HintCard"
		# Bottom centre of the VIEW, floating clear of its edge. Grows upward from the bottom, so
		# a two-line hint never pushes its own first line off the top of the card.
		_card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_card.offset_bottom = -ShipTheme.pxf(CARD_MARGIN)
		_card.mouse_filter = Control.MOUSE_FILTER_STOP
		if theme != null:
			_card.theme = theme.build_theme()
		overlay.add_child(_card)
		_card.add_child(box)
	else:
		host.add_child(box)
	_build_rows(box)


## The finished strings from [method ShipHintText.resolve], put on screen.
func show_hint(out: Dictionary) -> void:
	if _lede == null:
		return
	_lede.text = str(out.get(ShipHintText.OUT_LEDE, ""))
	_set_line(_sub, str(out.get(ShipHintText.OUT_SUB, "")))
	_set_line(_facts, str(out.get(ShipHintText.OUT_FACTS, "")))
	_set_line(_strip, str(out.get(ShipHintText.OUT_STRIP, "")))
	_set_line(_next, str(out.get(ShipHintText.OUT_NEXT, "")))
	if _next != null and _theme != null:
		_next.add_theme_color_override(
			"font_color", _theme.color_for_role(str(out.get(ShipHintText.OUT_TONE, "text_dim")))
		)
	_fill_chips(out.get(ShipHintText.OUT_CHIPS, []) as Array)
	_resize_card()


## The card is sized from the VIEW it floats in, so it stays clear of the side panels at every
## rung - in BASIC the view is some 400 px wider than in DEV.
##
## AND LIFTED CLEAR OF THE OLD KEY LEGEND where that still exists. `ShipView3D`'s `KeyHints` label
## is anchored BOTTOM_WIDE - the same strip this card wants - and survives in DEV (ux.md R29), so
## the two would print over each other in the one view the author actually works in. Asked of the
## live node rather than assumed, because whether it is there is [ShipUiMode]'s decision and not
## this class's.
func _resize_card() -> void:
	if _card == null:
		return
	var frame: Control = _card.get_parent() as Control
	if frame == null:
		return
	_card.custom_minimum_size = Vector2(frame.size.x * CARD_WIDTH_FRACTION, 0.0)
	var legend: Control = frame.find_child("KeyHints", true, false) as Control
	var clearance: float = legend.size.y if legend != null and legend.visible else 0.0
	_card.offset_bottom = -(ShipTheme.pxf(CARD_MARGIN) + clearance)


func _build_rows(box: VBoxContainer) -> void:
	_lede = Label.new()
	_lede.name = "HintLede"
	_lede.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lede.add_theme_font_size_override(
		"font_size", int(roundf(float(ShipTheme.font_title()) * LEDE_SCALE))
	)
	box.add_child(_lede)

	_sub = _dim_label("HintSub")
	box.add_child(_sub)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "HintRow"
	box.add_child(row)
	_chips = HBoxContainer.new()
	_chips.name = "HintChips"
	_chips.add_theme_constant_override("separation", 6)
	row.add_child(_chips)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_next = _dim_label("HintNext")
	row.add_child(_next)

	_facts = _dim_label("HintFacts")
	box.add_child(_facts)
	_strip = _dim_label("HintStrip")
	box.add_child(_strip)


func _dim_label(node_name: String) -> Label:
	var out: Label = Label.new()
	out.name = node_name
	out.add_theme_font_size_override("font_size", ShipTheme.font_small())
	if _theme != null:
		out.add_theme_color_override("font_color", _theme.color_for_role("text_dim"))
	return out


## A row of `[KEY] VERB` caps - what the player can do NEXT, which is the half of the brief the
## status line never had. LABELS, NOT BUTTONS, for now: the verbs are dispatched by key today and
## a button that looks pressable and is not would teach the wrong thing. Wiring them to
## `ShipKeymap` is its own step.
func _fill_chips(chips: Array) -> void:
	for child: Node in _chips.get_children():
		child.queue_free()
	for chip: Variant in chips:
		if not (chip is Dictionary):
			continue
		var d: Dictionary = chip
		var cap: Label = Label.new()
		cap.text = "[%s] %s" % [str(d.get("key", "")), str(d.get("verb", ""))]
		cap.add_theme_font_size_override("font_size", ShipTheme.font_small())
		_chips.add_child(cap)


func _set_line(label: Label, text: String) -> void:
	if label == null:
		return
	label.text = text
	label.visible = not text.is_empty()
