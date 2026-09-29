class_name ShipHotkeys
extends RefCounted
## EVERY BUTTON TEACHES ITS OWN HOTKEY, by showing it the moment you hover the button.
##
## The author, 2026-09-28:
##
## > "ALL Btns with hotkeys in all view modes should have the hotkey appear as the btn text when
## > hovering the btn for easy learning. (can also appear in the directive/hint box)"
##
## WHY HOVER AND NOT A PERMANENT LABEL. A permanent `FLY [V]` doubles the width of every button in a
## toolbar that is already eleven wide, and at BASIC the label is the only thing a child can read. A
## hover swap costs no space at rest, and the moment of hovering is exactly the moment the player is
## deciding to press it - which is when a keyboard shortcut is worth learning and at no other time.
##
## NOTHING MOVES WHEN IT SWAPS. The button's minimum width is set to the wider of the two strings at
## registration, so a toolbar does not reflow under the pointer. A control that jumps while you are
## aiming at it is worse than no hint at all.
##
## THE CHORD COMES FROM [ShipKeymap], never from a literal here. That table already records every
## binding with its status, and it is the thing the key legend reads - so a rebinding, or a binding
## discovered to be dead, changes both at once. A button whose action has no chord is registered and
## simply never swaps.

## Emitted when the pointer enters a button that has a chord, with the action name - so the hint bar
## can say the same thing in a sentence. "" when the pointer leaves.
signal hovered(action: String, chord: String)

## Extra width allowed for the chord string, in DESIGN pixels, so "CTRL+SHIFT+Z" does not clip.
const PAD_PX: float = 10.0

var _rows: Array[Dictionary] = []


## Register [param button] as the on-screen twin of [param action] in [ShipKeymap]. Safe to call for
## an action with no chord, or an unbound one: the button is left alone.
func watch(button: Button, action: String) -> void:
	if button == null or action.is_empty():
		return
	var chord: String = ShipKeymap.chord_for(action)
	if chord.is_empty() or chord == ShipKeymap.UNBOUND_CHORD:
		return
	var keyrow: Dictionary = ShipKeymap.row_for(action)
	# A DEAD or LYING binding is not offered. Printing a key that does nothing is worse than
	# printing none, and ShipKeymap exists partly to keep that record honest.
	if not keyrow.is_empty() and not ShipKeymap.is_live(keyrow):
		return
	var label: String = button.text
	_reserve(button, label, chord)
	button.tooltip_text = _tooltip(button.tooltip_text, label, chord)
	var row: Dictionary = {"button": button, "action": action, "chord": chord, "label": label}
	button.mouse_entered.connect(_on_enter.bind(button, action, chord))
	# THE ROW, NOT THE LABEL. `Callable.bind` copies its arguments by value and a String is a value
	# type, so binding `label` froze the build-time text into the connection for good: after FLY
	# became LAND (or GHOST became SOLID), hovering and leaving restored the ORIGINAL word and the
	# button lied about its own state. Binding the row Dictionary - a reference - means
	# [method relabel] actually reaches the restore path.
	button.mouse_exited.connect(_on_exit.bind(row))
	_rows.append(row)


## Re-read every watched button's resting label. Call after anything that rewrites button text -
## EXPLODE becomes ASSEMBLE, FLY becomes LAND - or the hover would restore the stale one.
func relabel() -> void:
	for row: Dictionary in _rows:
		var b: Button = row["button"]
		if not is_instance_valid(b):
			continue
		# Only when the pointer is away; mid-hover the text IS the chord and is not a label.
		if b.text != row["chord"]:
			row["label"] = b.text
			_reserve(b, str(row["label"]), str(row["chord"]))


func _on_enter(button: Button, action: String, chord: String) -> void:
	button.text = chord
	hovered.emit(action, chord)


func _on_exit(row: Dictionary) -> void:
	var button: Button = row["button"]
	if is_instance_valid(button):
		button.text = str(row["label"])
	hovered.emit("", "")


## Hold the button at least as wide as the longer of its two strings, so the swap never reflows the
## bar. Measured from the button's own font rather than guessed from character counts.
func _reserve(button: Button, label: String, chord: String) -> void:
	var font: Font = button.get_theme_font("font")
	var size: int = button.get_theme_font_size("font_size")
	if font == null or size <= 0:
		return
	var a: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	var b: float = font.get_string_size(chord, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, maxf(a, b) + PAD_PX)


func _tooltip(existing: String, label: String, chord: String) -> String:
	var line: String = "%s - PRESS %s" % [label, chord]
	if existing.is_empty():
		return line
	return "%s\n%s" % [existing, line]
