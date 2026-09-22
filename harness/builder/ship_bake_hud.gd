class_name ShipBakeHud
extends RefCounted
## The two controls that say where the exact meshes stand (ADR 0023/0024): the UPDATE MESHES
## button, lit in the warning role while the document is ahead of the meshes, and the bar in the
## status row that moves while the engine bakes. Owned by the builder, which hands the controls
## in once they exist; nothing here reads the document.

var _button: Button = null
var _bar: ProgressBar = null
var _theme: ShipTheme = null


func _init(button: Button, bar: ProgressBar, theme: ShipTheme) -> void:
	_button = button
	_bar = bar
	_theme = theme


## The bar styled by hand: the console theme gives a ProgressBar no boxes of its own, and a bar
## with `visible` on that draws nothing is the frozen look it exists to dispel (measured).
func style_bar() -> void:
	if _bar == null or _theme == null:
		return
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = _theme.color_for_role("accent")
	var back: StyleBoxFlat = StyleBoxFlat.new()
	back.bg_color = _theme.color_for_role_a("text_dim", 0.25)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)


## The button lights (the theme's warning role) while [param stale].
func refresh_button(stale: bool) -> void:
	if _button == null:
		return
	if stale and _theme != null:
		_button.add_theme_color_override("font_color", _theme.color_for_role("warning"))
		_button.text = "UPDATE MESHES *"
	else:
		_button.remove_theme_color_override("font_color")
		_button.text = "UPDATE MESHES"


func show_progress(fraction: float) -> void:
	if _bar != null:
		_bar.visible = true
		_bar.value = clampf(fraction, 0.0, 1.0) * 100.0


func hide_progress() -> void:
	if _bar != null:
		_bar.visible = false
		_bar.value = 0.0
