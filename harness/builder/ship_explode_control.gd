class_name ShipExplodeControl
extends RefCounted
## The explode options (ADR 0031/0032) as one unit the builder composes: the player's settings, the
## panel that edits them over the 3D view, the file that keeps them, and what each change does.
## Lifted out of ShipBuilder, which is at its size budget, the way ShipBakeHud and ShipBakeSession
## were.
##
## EVERY CHANGE IS A MOVE (ADR 0032). The pieces are cut into their fundamental cells once, so a
## gap, a slicer axis or the cluster toggle relays out what is on screen
## ([method ShipExplodeView.relayout]) and the POSITION slider scrubs the explode
## ([method ShipExplodeView.set_amount]); the slider follows the animation back.

## The settings the panel edits and the exploded view reads - one object, shared.
var settings: ShipExplodeSettings = null

var _panel: ShipExplodePanel = null
var _overlay: Control = null
var _explode: ShipExplodeView = null
var _save_path: String = ShipExplodeSettings.SAVE_PATH


## Docks the panel over [param frame] (the 3D view's frame), top right, hidden until the view
## explodes.
func _init(frame: Control, view: ShipView3D, cfg: ShipConfig, theme: ShipTheme) -> void:
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
	_panel.speed_changed.connect(_on_speed_changed)
	_panel.position_changed.connect(_on_position_changed)
	_explode = view.get_explode_view() if view != null else null
	if _explode != null:
		_explode.set_settings(settings)
		_explode.amount_changed.connect(_panel.show_amount)


## The panel is on screen while the view is exploded.
func set_shown(on: bool) -> void:
	_overlay.visible = on
	if on:
		refresh()


## The panel shows the settings and the explode amount as they are.
func refresh() -> void:
	_panel.refresh()
	if _explode != null:
		_panel.show_amount(_explode.amount())


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


func _on_speed_changed() -> void:
	settings.save(_save_path)


func _on_position_changed(amount: float) -> void:
	if _explode != null:
		_explode.set_amount(amount)
