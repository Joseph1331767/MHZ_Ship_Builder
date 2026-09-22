class_name ShipExplodeControl
extends RefCounted
## The explode options (ADR 0031) as one unit the builder composes: the player's settings, the
## panel that edits them over the 3D view, the file that keeps them, and what each change does.
## Lifted out of ShipBuilder, which is at its size budget, the way ShipBakeHud and ShipBakeSession
## were.
##
## A separation moves what is on screen at once ([method ShipExplodeView.relayout]). A slicer
## change only lights APPLY SLICES; APPLY hands back to the builder, whose next show of the bake
## asks the session for extras made with the new slicing.

## The settings the panel edits and the exploded view reads - one object, shared.
var settings: ShipExplodeSettings = null

var _panel: ShipExplodePanel = null
var _overlay: Control = null
var _explode: ShipExplodeView = null
var _session: ShipBakeSession = null
var _reslice: Callable = Callable()
var _save_path: String = ShipExplodeSettings.SAVE_PATH


## Docks the panel over [param frame] (the 3D view's frame), top right, hidden until the view
## explodes. [param reslice] is called when the player presses APPLY SLICES.
func _init(
	frame: Control,
	view: ShipView3D,
	session: ShipBakeSession,
	cfg: ShipConfig,
	theme: ShipTheme,
	reslice: Callable
) -> void:
	_session = session
	_reslice = reslice
	settings = ShipExplodeSettings.load_or_defaults(cfg, _save_path)
	# A full-rect layer that lets every click through to the 3D view except those on the panel.
	_overlay = Control.new()
	_overlay.name = "ExplodeOptionsLayer"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	if frame != null:
		frame.add_child(_overlay)
	_panel = ShipExplodePanel.new()
	_overlay.add_child(_panel)
	_panel.setup(settings, theme)
	var margin: float = ShipTheme.pxf(6.0)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -margin
	_panel.offset_top = margin
	_panel.layout_changed.connect(_on_layout_changed)
	_panel.slicing_changed.connect(_on_slicing_changed)
	_panel.apply_pressed.connect(_on_apply_pressed)
	_explode = view.get_explode_view() if view != null else null
	if _explode != null:
		_explode.set_settings(settings)


## The panel is on screen while the view is exploded.
func set_shown(on: bool) -> void:
	_overlay.visible = on
	if on:
		refresh()


## The slicing the extras should be made with, from the settings.
func slicing() -> Dictionary:
	return settings.slicing()


## The panel shows the settings as they are, and APPLY SLICES lights while the bake on hand
## carries extras made with some other slicing.
func refresh() -> void:
	if _session == null:
		return
	var has_bake: bool = not _session.last.is_empty()
	_panel.refresh()
	_panel.set_stale(has_bake and not _session.has_extras(settings.slicing()))


## Use [param next] from now on, unsaved - what a check calls to start from known settings rather
## than whatever this player last chose.
func use(next: ShipExplodeSettings) -> void:
	settings = next
	_panel.bind(next)
	if _explode != null:
		_explode.set_settings(next)
		_explode.relayout()
	refresh()


func _on_layout_changed() -> void:
	settings.save(_save_path)
	if _explode != null:
		_explode.relayout()


func _on_slicing_changed() -> void:
	settings.save(_save_path)
	refresh()


func _on_apply_pressed() -> void:
	if _reslice.is_valid():
		_reslice.call()
	refresh()
