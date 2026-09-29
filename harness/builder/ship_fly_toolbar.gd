class_name ShipFlyToolbar
extends RefCounted
## THE FLY AND SOLID BUTTONS, and the render type they force with them (ADR 0049).
##
## One cohesive job: entering fly swaps the render type to CLAY and the console palette with it, and
## leaving puts back exactly what was there - so the two buttons, the render-type dropdown and the
## palette variant all belong to the same decision and are kept in one place. `ship_builder.gd`
## holds a reference and forwards; it was at gdlint's two-thousand-line cap, and this is a seam
## rather than a shave (see `.gdlintrc`).
##
## IT REACHES BACK INTO NOTHING. Everything it drives is handed to it in [method use], and what it
## cannot do itself - saying something in the status bar - it emits.

## A line for the status bar. The toolbar has no business writing there directly.
signal say(text: String)

## The buttons changed, so whatever draws the hint should re-read.
signal changed

## How hard the palette quantizer is dithered while CLAY is up - far above the shipped default,
## because CLAY is the only mode with a continuous gradient to preserve.
const CLAY_DITHER: float = 0.22

var _fly_button: Button = null
var _solid_button: Button = null
var _mode_option: OptionButton = null
var _view: ShipView3D = null
var _ui_mode: ShipUiMode = null
var _theme: ShipTheme = null
var _hotkeys: ShipHotkeys = null
## Answers "is a placement live?" - the builder owns that, not this.
var _busy: Callable = Callable()


## Both buttons, in the order they sit in the bar. [param make] is the caller's button factory, so
## the hotkey-on-hover wiring happens exactly once, in one place.
func build(bar: HBoxContainer, make: Callable) -> void:
	_fly_button = make.call("FLY", _on_fly_pressed, "fly_toggle")
	_fly_button.tooltip_text = (
		"FLY AROUND AND INSIDE THE SHIP - W A S D, SPACE TO STOP, V TO COME BACK"
	)
	bar.add_child(_fly_button)
	# SOLID WALLS - only meaningful while flying, so it is hidden until then.
	_solid_button = make.call("GHOST", _on_solid_pressed, "fly_solid")
	_solid_button.tooltip_text = (
		"SOLID: BUMP INTO THE SHIP, INSIDE AND OUT. GHOST: FLY STRAIGHT THROUGH IT."
	)
	_solid_button.visible = false
	bar.add_child(_solid_button)


## The things it drives, once they exist. `build` runs while the header is being assembled and the
## view does not exist yet.
func use(
	view: ShipView3D,
	ui_mode: ShipUiMode,
	theme: ShipTheme,
	mode_option: OptionButton,
	hotkeys: ShipHotkeys,
	busy: Callable
) -> void:
	_view = view
	_ui_mode = ui_mode
	_theme = theme
	_mode_option = mode_option
	_hotkeys = hotkeys
	_busy = busy
	if _view != null:
		# FLY and SOLID can both be changed from the KEYBOARD while flying (V/ESC/F/ENTER and C), so
		# the toolbar follows the MODE rather than only the button that was clicked.
		_view.fly.changed.connect(refresh)
	refresh()


## Point the dropdown and the console palette at whatever render type the VIEW is actually showing,
## and put the right words on both buttons. The view is the authority, because fly changes the
## render type without going through the toolbar.
func refresh() -> void:
	if _view == null:
		return
	var flying: bool = _view.fly.is_flying()
	if _fly_button != null:
		_fly_button.text = "LAND" if flying else "FLY"
	if _solid_button != null:
		_solid_button.visible = flying
		# The label names the state you are IN, not the one you would switch to: a toggle that names
		# the other state is the commonest way to make a player press it twice.
		_solid_button.text = "SOLID" if _view.fly.is_solid() else "GHOST"
	if _mode_option != null:
		var mode: int = _view.get_display_mode()
		for i: int in _mode_option.item_count:
			if _mode_option.get_item_id(i) == mode:
				_mode_option.select(i)
				break
		wear_clay(mode == ShipSceneBuilder.DisplayMode.CLAY)
	if _hotkeys != null:
		# The labels above may have just changed, so the hover swap has to learn the new resting
		# text or it would restore a stale one.
		_hotkeys.relabel()
	changed.emit()


## CLAY swaps the whole sixteen-entry LUT for the blue one, so the console goes with the ship - the
## alternative is blue clay sitting in a teal frame, which reads as a bug. A budget alert still
## beats it: [method ShipTheme.set_variant] defers while one is up.
##
## AND IT TURNS THE DITHER UP, which is what makes a real light look real. CLAY is the one mode
## whose shading is a SMOOTH continuous falloff rather than bands chosen from the palette, and a
## smooth falloff through a 16-entry quantizer comes out as hard concentric rings - which is why a
## genuine SpotLight3D "just doesnt read as a real light seems still very faked". It was a real
## light; the quantizer was posterizing it.
func wear_clay(on: bool) -> void:
	if _theme == null:
		return
	_theme.set_variant("clay" if on else "")
	_theme.set_dither_strength(CLAY_DITHER if on else ShipTheme.DITHER_DEFAULT)


## FLY (ADR 0049). The author asked twice - "also camera fly around modes", then in full detail,
## then "note i dont see flying mode either..". Entering forces CLAY and the void; leaving puts
## back exactly what was there.
##
## BASIC FLIES TOO, with heavier damping and direct look instead of torque (ux.md Q15): "the
## little kids mode cannot fly" is the version a child would resent.
func _on_fly_pressed() -> void:
	if _view == null:
		return
	if _view.fly.is_flying():
		_view.fly.leave(true, false)
		refresh()
		return
	var basic: bool = _ui_mode != null and _ui_mode.level == ShipUiMode.Level.BASIC
	# REFUSED while something else owns the view: a live placement, or a handle grab in progress.
	# The BUILDER owns the placement, so it answers that half; the view's gesture state is read the
	# same way STATE_PIVOT_HELD is.
	var busy: bool = _busy.is_valid() and bool(_busy.call())
	busy = busy or int(_view.get("_handle_drag")) != 0
	if not _view.fly.enter(basic, busy):
		# Say why rather than doing nothing, which reads as a dead button.
		say.emit("FINISH PLACING FIRST, THEN FLY")
		return
	refresh()


func _on_solid_pressed() -> void:
	if _view == null:
		return
	_view.fly.set_solid(not _view.fly.is_solid())
	refresh()
