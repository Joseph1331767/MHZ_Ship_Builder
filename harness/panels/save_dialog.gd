## SaveDialog - Spore's save flow: name (MANDATORY), description, tags.
##
## SPORE_CLONE_SPEC section 6, last line: "Save flow is name (mandatory) + description +
## tags." Section 5 lists the two walls that stand between a creation and a save file, and
## both of them are hard: a creation needs at least THREE parts (wall 1) and it needs a NAME
## (wall 4). Neither is negotiable and neither is a warning.
##
## IT IS AN IN-SCENE CONTROL, AND THAT IS NOT A STYLE PREFERENCE
## ------------------------------------------------------------
## The whole builder renders into one SubViewport and is mapped onto a diegetic device in
## MHZ_Origins (SPEC section 10, AGENTS section 7). A `FileDialog`, an `AcceptDialog` or any
## other `Window` is a NATIVE OS window: it would open behind the game, on the desktop, on a
## machine the player's character is not looking at - which is to say it would not exist on
## the texture the player can see. So this is a plain `Control` that covers its parent, dims
## what is behind it, and swallows the mouse. Nothing here reads the OS display server, an OS
## window handle, or a global mouse position; the literal names are left out of this comment
## on purpose, because the render-to-texture rule is verified by a grep.
##
## For the same reason it never calls `ShipBuilder.show_message()`. That is the builder's own
## in-scene modal, and it is a SIBLING of this node added earlier in the tree - it would
## render UNDERNEATH this dialog and look like the app had frozen. Every refusal is therefore
## reported on this dialog's own gate line, in place.
##
## THE GATE MESSAGE IS SHOWN VERBATIM. `ShipGate.check_save()` returns
## `{"ok": bool, "reason": int, "message": String}` and `message` is written to be read by a
## player: it names the failing gate and its numbers ("NEED 3 PARTS TO SAVE - THIS SHIP HAS
## 2"). Two independent gates can refuse a save - complexity and the 3-part minimum - and
## that sentence is the ONLY thing that says which. It is never paraphrased, never truncated,
## and never replaced with "cannot save".
##
## The gate is run WITHOUT a ShipMetrics (its optional last argument), so it checks complexity
## and the part minimum and skips the physical budgets. Deliberate: those need a full sampling
## grid, they are already enforced on every commit that could break them, and a dialog that
## stalls for a grid pass when it opens is a dialog nobody presses twice.
##
## WHERE THE METADATA GOES. Into `doc.settings`, through `begin_edit()`/`commit_edit()` like
## every other document change - naming a ship IS a document change, it belongs on the undo
## stack, and mutating a ShipDoc outside that pair is the one thing panels may never do.
## `commit_edit()` can refuse, and this reports it rather than writing a file whose contents
## were rolled back.
class_name SaveDialog
extends Control

## The save completed and `path` was written. For anything that wants to react - a status
## line, a Sporepedia-style card later. The dialog has already closed itself.
signal save_committed(path: String)
## The player backed out. Nothing was written and the document was not touched.
signal save_cancelled

## Node name used by [method open_for] to find an existing instance instead of stacking a
## second dialog on the first.
const NODE_NAME: String = "SaveDialog"

## `doc.settings` keys this dialog owns. THE VALUE SHAPES ARE PART OF THE CONTRACT - pinning
## a field name without its shape is precisely the silent cross-module bug FOLLOWUPS F0 was
## written about, so:
##   KEY_NAME:        String - non-empty, exactly what the player typed, trimmed
##   KEY_DESCRIPTION: String - may be ""
##   KEY_TAGS:        Array  - of String, lower-cased, de-duplicated, entry order preserved
const KEY_NAME: String = "name"
const KEY_DESCRIPTION: String = "description"
const KEY_TAGS: String = "tags"

const DIALOG_WIDTH: float = 420.0
const LABEL_WIDTH: float = 76.0
const ROW_HEIGHT: float = 18.0
const DESCRIPTION_HEIGHT: float = 54.0
const TICK_LENGTH: float = 4.0
const DIM_ALPHA: float = 0.78

## Authoring caps. None of these is a Spore rule - Spore's own limits are unpublished - so
## they are ours, they are generous, and they exist only so a save file cannot be given a
## 4 KB name by a stuck key.
const MAX_NAME_CHARS: int = 48
const MAX_DESCRIPTION_CHARS: int = 480
const MAX_TAGS_CHARS: int = 240
const MAX_TAGS: int = 12
const MAX_FILE_NAME_CHARS: int = 40

const TAG_SEPARATOR: String = ","

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null

var _dim: ColorRect = null
var _title: Label = null
var _gate_line: Label = null
var _name_edit: LineEdit = null
var _description_edit: TextEdit = null
var _tags_edit: LineEdit = null
var _tags_preview: Label = null
var _file_preview: Label = null
var _save_button: Button = null
var _cancel_button: Button = null
var _tag_labels: Array[Label] = []
var _value_labels: Array[Label] = []

## Last gate verdict, so the SAVE press does not have to re-derive why it is disabled.
var _gate_ok: bool = true


func _ready() -> void:
	name = NODE_NAME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not PASS: while this is up, nothing behind it may be clicked.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var frame: PanelContainer = PanelContainer.new()
	frame.name = "Frame"
	frame.custom_minimum_size = Vector2(ShipTheme.pxf(DIALOG_WIDTH), ShipTheme.pxf(0.0))
	center.add_child(frame)

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Body"
	box.add_theme_constant_override("separation", 3)
	frame.add_child(box)
	_build_body(box)


func _draw() -> void:
	NumericField.draw_corner_ticks(
		self, Rect2(Vector2.ZERO, size), _role_color("line"), TICK_LENGTH
	)


## Escape backs out, Enter saves - and EVERY OTHER KEY IS SWALLOWED while the dialog is up.
##
## The swallowing is the point, not a side effect. `mouse_filter = STOP` stops the mouse and
## nothing else; a `Control` overlay has no effect whatsoever on the keyboard, and
## `ShipBuilder._unhandled_key_input` gates its hotkeys on ITS OWN private modal layer, which
## has no idea this dialog exists. Without this, DELETE, G, F and Ctrl+Z would still reach the
## document underneath a dialog that is visually claiming to be a hard modal - the player
## would delete the part they were about to save.
##
## Typing is unaffected: a focused LineEdit or TextEdit consumes its keys at the GUI stage,
## long before input is ever offered as "unhandled". That is also why Enter reaches here at
## all only when the multi-line description does not want it - in the description box Return
## is a newline, which is the behaviour you want there.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	get_viewport().set_input_as_handled()
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		_on_cancel_pressed()
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_on_save_pressed()


# ---------------------------------------------------------------- entry points


## Find-or-create this dialog as a child of [param builder] and open it. One call is the
## whole wiring a toolbar SAVE button needs.
##
## Added as the LAST child so it draws over the console and over ShipBuilder's own modal
## layer, and so `_unhandled_key_input` reaches it before the builder's hotkeys.
static func open_for(builder: ShipBuilder) -> SaveDialog:
	if builder == null:
		return null
	var found: Node = builder.get_node_or_null(NODE_NAME)
	var dialog: SaveDialog = found as SaveDialog
	if dialog == null:
		dialog = SaveDialog.new()
		dialog.name = NODE_NAME
		builder.add_child(dialog)
		dialog.setup(builder)
	dialog.open()
	return dialog


## Same shape as every other panel: called once, straight after the node is mounted.
func setup(builder: ShipBuilder) -> void:
	_builder = builder
	if _builder == null:
		return
	_ship_theme = _builder.get_ship_theme()
	if _ship_theme != null and not _ship_theme.palette_changed.is_connected(_on_palette_changed):
		_ship_theme.palette_changed.connect(_on_palette_changed)
	_apply_palette()


## Show the dialog, seeded from whatever the document was last saved as, and run the gate.
func open() -> void:
	if _builder == null:
		return
	var doc: ShipDoc = _builder.get_doc()
	_name_edit.text = _setting_string(doc, KEY_NAME)
	_description_edit.text = _setting_string(doc, KEY_DESCRIPTION)
	# Joined with a space after the comma for reading; _typed_tags() strips it again on the
	# way back, so the round trip is stable.
	_tags_edit.text = (TAG_SEPARATOR + " ").join(_setting_tags(doc))
	visible = true
	_refresh_gate()
	_refresh_previews()
	_name_edit.grab_focus()
	_name_edit.select_all()
	queue_redraw()


func close() -> void:
	visible = false


# ---------------------------------------------------------------- construction


func _build_body(box: VBoxContainer) -> void:
	_title = Label.new()
	_title.name = "Title"
	_title.text = "SAVE SHIP"
	_title.add_theme_font_size_override("font_size", ShipTheme.font_title())
	box.add_child(_title)
	box.add_child(HSeparator.new())

	# The gate's own sentence, verbatim. Hidden while the save is legal so an empty warning
	# line never trains the player to ignore this row.
	_gate_line = Label.new()
	_gate_line.name = "GateLine"
	_gate_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gate_line.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_gate_line.visible = false
	box.add_child(_gate_line)

	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.max_length = MAX_NAME_CHARS
	_name_edit.placeholder_text = "REQUIRED"
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	box.add_child(_field_row("NAME *", _name_edit))

	_description_edit = TextEdit.new()
	_description_edit.name = "DescriptionEdit"
	_description_edit.custom_minimum_size = Vector2(
		0.0, ShipTheme.pxf(DESCRIPTION_HEIGHT)
	)
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Same reason as the LineEdits below: a context menu is a PopupMenu, i.e. a Window.
	_description_edit.context_menu_enabled = false
	_description_edit.add_theme_font_size_override("font_size", ShipTheme.font_small())
	box.add_child(_tag_label("DESCRIPTION"))
	box.add_child(_description_edit)

	_tags_edit = LineEdit.new()
	_tags_edit.name = "TagsEdit"
	_tags_edit.max_length = MAX_TAGS_CHARS
	_tags_edit.placeholder_text = "COMMA SEPARATED"
	_tags_edit.text_changed.connect(_on_tags_changed)
	box.add_child(_field_row("TAGS", _tags_edit))

	_tags_preview = _value_label("TagsPreview")
	box.add_child(_tags_preview)
	_file_preview = _value_label("FilePreview")
	box.add_child(_file_preview)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 4)
	box.add_child(buttons)
	_cancel_button = _make_button("CANCEL", _on_cancel_pressed)
	buttons.add_child(_cancel_button)
	_save_button = _make_button("SAVE", _on_save_pressed)
	buttons.add_child(_save_button)
	_wire_focus_ring()


## Tab and Shift+Tab loop around the three fields and never leave the dialog.
##
## An overlay Control does not scope focus traversal the way a Window does, so without an
## explicit ring Tab walks straight out into the console behind it and lands on a control the
## player cannot see. The buttons are deliberately not in the ring - they are FOCUS_NONE, and
## Enter/Escape already reach them.
func _wire_focus_ring() -> void:
	var ring: Array[Control] = [_name_edit, _description_edit, _tags_edit]
	for i: int in ring.size():
		var here: Control = ring[i]
		var after: Control = ring[(i + 1) % ring.size()]
		var before: Control = ring[(i - 1 + ring.size()) % ring.size()]
		here.focus_next = here.get_path_to(after)
		here.focus_neighbor_bottom = here.get_path_to(after)
		here.focus_previous = here.get_path_to(before)
		here.focus_neighbor_top = here.get_path_to(before)


func _field_row(label_text: String, editor: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	row.add_theme_constant_override("separation", 4)
	row.add_child(_tag_label(label_text))
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A LineEdit's context menu is a PopupMenu, i.e. a Window - forbidden on the device
	# texture for exactly the same reason a FileDialog is (SPEC section 10).
	var line: LineEdit = editor as LineEdit
	if line != null:
		line.context_menu_enabled = false
		line.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(editor)
	return row


func _tag_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(ShipTheme.pxf(LABEL_WIDTH), ShipTheme.pxf(0.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_tag_labels.append(label)
	return label


func _value_label(node_name: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.clip_text = true
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_value_labels.append(label)
	return label


func _make_button(label: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(ROW_HEIGHT))
	button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	button.pressed.connect(handler)
	return button


# ---------------------------------------------------------------- the gate


## Both save walls, re-read from the document. `message` goes onto the gate line exactly as
## `ShipGate` wrote it; the mandatory-name wall is ours to report because the gate cannot see
## a name the player has not typed yet.
func _refresh_gate() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		_set_gate(false, "NO DOCUMENT TO SAVE.")
		return
	var verdict: Dictionary = ShipGate.check_save(doc, data, cfg)
	if not bool(verdict.get("ok", true)):
		_set_gate(false, _string_of(verdict, "message", "THIS SHIP CANNOT BE SAVED."))
		return
	if _typed_name() == "":
		_set_gate(false, "A NAME IS REQUIRED TO SAVE.")
		return
	_set_gate(true, "")


func _set_gate(ok: bool, message: String) -> void:
	_gate_ok = ok
	_gate_line.visible = not ok
	_gate_line.text = message
	if _save_button != null:
		_save_button.disabled = not ok
	_apply_palette()


# ---------------------------------------------------------------- previews


func _refresh_previews() -> void:
	var tags: PackedStringArray = _typed_tags()
	if tags.is_empty():
		_tags_preview.text = "TAGS     NONE"
	else:
		_tags_preview.text = "TAGS     %s  (%d)" % [", ".join(tags).to_upper(), tags.size()]
	_file_preview.text = _file_preview_text()


## What pressing SAVE will actually write. Shown before the press, because a save that
## silently lands on top of yesterday's ship is the kind of thing you find out about later.
func _file_preview_text() -> String:
	var file_name: String = _file_name()
	if file_name == "":
		return "FILE     ---"
	var path: String = _path_for(file_name)
	if FileAccess.file_exists(path):
		return "FILE     %s.json  (OVERWRITES)" % file_name
	return "FILE     %s.json" % file_name


func _on_name_changed(_text: String) -> void:
	_refresh_gate()
	_refresh_previews()


func _on_name_submitted(_text: String) -> void:
	_on_save_pressed()


func _on_tags_changed(_text: String) -> void:
	_refresh_previews()


# ---------------------------------------------------------------- save


func _on_cancel_pressed() -> void:
	close()
	save_cancelled.emit()


## Re-runs the gate before doing anything: the cached verdict can be one keystroke old, and
## this is the answer the player acts on.
func _on_save_pressed() -> void:
	if _builder == null:
		return
	_refresh_gate()
	if not _gate_ok:
		return
	var file_name: String = _file_name()
	if file_name == "":
		_set_gate(
			false,
			(
				"THAT NAME HAS NO LETTERS OR DIGITS IN IT, SO IT CANNOT BECOME A FILE NAME. "
				+ "ADD AT LEAST ONE."
			)
		)
		return
	if not _write_metadata():
		return
	var path: String = _path_for(file_name)
	if not _write_file(path):
		return
	_builder.set_status("SAVED %s" % path)
	close()
	save_committed.emit(path)


## Name, description and tags into `doc.settings`, through the edit protocol.
##
## `commit_edit()` rolls a refused edit back by REPLACING the document with a fresh one built
## from the history head, so a changed ShipDoc instance across the call is exactly a refusal.
## Known interaction, stated rather than hidden: the builder's commit guard also rejects a
## document whose bounding box is over `max_bbox_m`, and loading is budget-exempt - so an
## over-size ship opened from disk refuses this metadata edit and therefore refuses the save.
## The alternative, writing to the document outside the edit protocol, is worse.
func _write_metadata() -> bool:
	var doc: ShipDoc = _builder.get_doc()
	if doc == null:
		return false
	var tags: PackedStringArray = _typed_tags()
	var tag_list: Array = []
	for tag: String in tags:
		tag_list.append(tag)
	_builder.begin_edit("ship metadata")
	doc.settings[KEY_NAME] = _typed_name()
	doc.settings[KEY_DESCRIPTION] = _typed_description()
	doc.settings[KEY_TAGS] = tag_list
	# Empty ids: "the topology moved, diff everything". Nothing per-part changed, and there
	# is no id to name.
	_builder.commit_edit(PackedStringArray())
	if _builder.get_doc() != doc:
		_set_gate(false, "EDIT REFUSED AND ROLLED BACK - A BUDGET WOULD BE EXCEEDED.")
		return false
	return true


## The file itself. These eight lines duplicate `ShipBuilder._save_named()`, which is
## private; if it is ever made public this should call it instead of re-deriving the path.
func _write_file(path: String) -> bool:
	var doc: ShipDoc = _builder.get_doc()
	if doc == null:
		return false
	DirAccess.make_dir_recursive_absolute(_ship_dir())
	var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if handle == null:
		_set_gate(false, "COULD NOT WRITE %s - THE FOLDER IS NOT WRITABLE." % path)
		return false
	handle.store_string(JSON.stringify(doc.to_dict(), "  "))
	handle.close()
	return true


func _ship_dir() -> String:
	# Read inside a function body, never at const level: a const-level reference between two
	# class_name scripts is the form that bites when the load order is not what you assumed.
	return ShipBuilder.SHIP_DIR


func _path_for(file_name: String) -> String:
	return "%s/%s.json" % [_ship_dir(), file_name]


# ---------------------------------------------------------------- field readers


func _typed_name() -> String:
	if _name_edit == null:
		return ""
	return _name_edit.text.strip_edges()


func _typed_description() -> String:
	if _description_edit == null:
		return ""
	return _description_edit.text.strip_edges().substr(0, MAX_DESCRIPTION_CHARS)


## Comma-separated in, normalised out: trimmed, lower-cased, empties dropped, duplicates
## dropped, entry order kept, capped at MAX_TAGS.
func _typed_tags() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _tags_edit == null:
		return out
	var seen: Dictionary = {}
	for raw: String in _tags_edit.text.split(TAG_SEPARATOR, false):
		var tag: String = raw.strip_edges().to_lower()
		if tag == "" or seen.has(tag):
			continue
		seen[tag] = true
		out.append(tag)
		if out.size() >= MAX_TAGS:
			break
	return out


## The ship's name reduced to a file name. Hand-rolled from an explicit whitelist rather than
## through String.validate_filename(), so the mapping is identical on every platform and
## every engine build: letters and digits survive, every other run of characters collapses to
## a single underscore.
func _file_name() -> String:
	var source: String = _typed_name().to_lower()
	var out: String = ""
	var pending_break: bool = false
	for i: int in source.length():
		var c: String = source.substr(i, 1)
		if _is_slug_char(c):
			if pending_break and out != "":
				out += "_"
			pending_break = false
			out += c
			if out.length() >= MAX_FILE_NAME_CHARS:
				break
		else:
			pending_break = true
	return out


static func _is_slug_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "0" and c <= "9")


# ---------------------------------------------------------------- document readers


static func _setting_string(doc: ShipDoc, key: String) -> String:
	if doc == null:
		return ""
	var value: Variant = doc.settings.get(key, null)
	if value is String:
		return value
	return ""


## Tags come back off disk as a plain Array of whatever JSON held. Anything that is not a
## non-empty String is dropped rather than str()-ed into the field.
static func _setting_tags(doc: ShipDoc) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		return out
	var value: Variant = doc.settings.get(KEY_TAGS, null)
	if not (value is Array):
		return out
	var list: Array = value
	for entry: Variant in list:
		if not (entry is String):
			continue
		var tag: String = entry
		if tag.strip_edges() != "":
			out.append(tag.strip_edges().to_lower())
	return out


static func _string_of(entry: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = entry.get(key, null)
	if value is String:
		var text: String = value
		if text.strip_edges() != "":
			return text
	return fallback


# ---------------------------------------------------------------- palette


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_apply_palette()


func _apply_palette() -> void:
	if _dim != null and _ship_theme != null:
		_dim.color = _ship_theme.color_for_role_a("background", DIM_ALPHA)
	if _title != null:
		_title.add_theme_color_override("font_color", _role_color("accent"))
	if _gate_line != null:
		_gate_line.add_theme_color_override("font_color", _role_color("warning"))
	for label: Label in _tag_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", _role_color("text_dim"))
	for label: Label in _value_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", _role_color("text"))
	queue_redraw()


## The only sanctioned colour lookup. Never an index (SPEC section 11).
func _role_color(role: String) -> Color:
	if _ship_theme == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	return _ship_theme.color_for_role(role)
