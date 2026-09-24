class_name ShipDevFeedback
extends RefCounted
## A developer's note taken IN THE MOMENT, with the state that produced it.
##
## SHIFT+F while testing: the frame is grabbed as it stands, a prompt asks what was noticed, and
## the note is appended to `reports/feedback/notes.jsonl` together with the whole document, the
## last bake's report, what the view was showing, and the tail of the engine log. An agent reads
## the file and has the ship, the settings and the picture that went with the remark - rather than
## a remark written up hours later from memory.
##
## WHY SHIFT AND NOT F ALONE. `F` is [method ShipView3D.frame_all], bound long before this and
## worth more; SHIFT+F keeps the mnemonic without taking it. [constant CHORD] changes it.
##
## HIDEABLE AND REMOVABLE, which is the point of a developer feature:
##   - hide it: [constant ENABLED] to `false`, and nothing arms.
##   - it never arms in a release build anyway - see [method is_enabled].
##   - remove it: delete this file and the four lines that call it in `ship_builder.gd`. Nothing
##     else in the project refers to it, by design.
##
## IN-SCENE, LIKE EVERYTHING ELSE (SPEC section 10). It borrows [method ShipBuilder.prompt], the
## app's own modal Control, so no native dialog is opened and the feature works just as well
## once the builder is a texture on a quad. Text entry needs a real keyboard, which is the other
## reason this is a developer feature and not a player one.

## The one switch. False and nothing arms, whatever the build.
const ENABLED: bool = true

## What opens it. SHIFT is not optional - see the note above about `F`.
const CHORD: Key = KEY_F

## Where the notes go, tried in this order: the project's own `reports/` while developing, which is
## gitignored and is where every other tool writes, and `user://` when that is not writable (an
## exported build, where this is off anyway, or a read-only checkout).
const DIR_PROJECT: String = "res://reports/feedback"
const DIR_FALLBACK: String = "user://feedback"

## The compilation an agent reads: one JSON object per line, appended, never rewritten. A line that
## cannot be parsed costs that line and nothing else, which is why it is not one big JSON array.
const NOTES_FILE: String = "notes.jsonl"

## The same notes without the document blob, for a human skimming them.
const DIGEST_FILE: String = "notes.md"

## How much of the engine log to carry, in lines from the end. Enough to hold a bake's worth of
## complaint; not so much that a note becomes a log file.
const LOG_TAIL_LINES: int = 120


## Is the feature live? Debug builds only, so a release can never write notes or bind the chord
## even if someone ships with [constant ENABLED] on.
static func is_enabled() -> bool:
	return ENABLED and OS.is_debug_build()


## Does [param key] open a note?
static func opens(key: InputEventKey) -> bool:
	return is_enabled() and key.keycode == CHORD and key.shift_pressed


## Grabs the frame AS IT STANDS and asks what was noticed.
##
## The picture is taken BEFORE the prompt opens, on purpose: the prompt dims the screen, and the
## thing worth a note is what was on it a moment ago, not the dialog over it.
static func open(builder: Node, session: Object) -> void:
	if not is_enabled() or builder == null or not builder.has_method("prompt"):
		return
	var frame: Image = _frame_of(builder)
	builder.call(
		"prompt",
		"DEVELOPER NOTE",
		"What did you see? It is saved with the ship, the last bake and this frame.",
		"",
		Callable(ShipDevFeedback, "_write").bind(builder, session, frame)
	)


## Appends one note. Never throws and never blocks: a developer feature that can break a test run
## is worse than no developer feature, so every reading below is guarded and a failure to save says
## so in the status line rather than anywhere louder.
static func _write(note: String, builder: Node, session: Object, frame: Image) -> void:
	if note.strip_edges().is_empty():
		_say(builder, "DEV NOTE: empty, nothing saved")
		return
	var dir: String = _directory()
	if dir.is_empty():
		_say(builder, "DEV NOTE: nowhere to write it")
		return
	var stamp: String = Time.get_datetime_string_from_system(false, true)
	var slug: String = stamp.replace(":", "-").replace(" ", "_")
	var shot: String = ""
	if frame != null and frame.save_png("%s/%s.png" % [dir, slug]) == OK:
		shot = "%s.png" % slug

	var entry: Dictionary = {
		"at": stamp,
		"note": note,
		"frame": shot,
		"state": _state_of(builder, session),
		"log": _log_tail()
	}
	var line: String = JSON.stringify(entry)
	if not _append("%s/%s" % [dir, NOTES_FILE], line + "\n"):
		_say(builder, "DEV NOTE: could not write %s" % NOTES_FILE)
		return
	_append("%s/%s" % [dir, DIGEST_FILE], _digest(entry))
	_say(builder, "DEV NOTE saved -> %s" % ProjectSettings.globalize_path(dir))


## What the builder was showing and holding. Every field is optional: this runs while something may
## well be wrong, so nothing here may assume the thing it is reading exists.
static func _state_of(builder: Node, session: Object) -> Dictionary:
	var out: Dictionary = {"ruleset": ShipDoc.RULESET_VERSION, "godot": Engine.get_version_info()}
	var doc: Variant = builder.call("get_doc") if builder.has_method("get_doc") else null
	if doc is ShipDoc:
		# THE WHOLE DOCUMENT, which is the field that earns this feature its keep: a note about a
		# shape is worth little without the ship that made it, and a doc is small and exact.
		out["doc"] = (doc as ShipDoc).to_dict()
		out["parts"] = (doc as ShipDoc).parts.size()
	if builder.has_method("get_selection"):
		out["selection"] = builder.call("get_selection")
	out["exploded"] = _guess(builder, "is_exploded", false)
	var view: Variant = builder.call("get_view") if builder.has_method("get_view") else null
	if view is Node:
		out["view"] = _view_state(view as Node)
	if session != null:
		out["bake"] = _bake_state(session)
	var opts: Variant = builder.get("_explode_opts")
	if opts != null and opts.get("settings") != null:
		var settings: Object = opts.get("settings")
		out["explode"] = {
			"separate": settings.get("separate"),
			"slices": str(settings.get("slices")),
			"cluster_slices": str(settings.get("cluster_slices")),
			"separation_m": settings.get("separation_m")
		}
	return out


static func _view_state(view: Node) -> Dictionary:
	var out: Dictionary = {}
	if view.has_method("display_mode"):
		out["mode"] = view.call("display_mode")
	var explode: Variant = (
		view.call("get_explode_view") if view.has_method("get_explode_view") else null
	)
	if explode is Node:
		out["explode_amount"] = _guess(explode as Node, "amount", 0.0)
		out["cells_showing"] = _guess(explode as Node, "has_cells_showing", false)
	return out


## The last bake's REPORT, less its meshes - the counts and complaints, which is what a note needs.
static func _bake_state(session: Object) -> Dictionary:
	var last: Variant = session.get("last")
	if not (last is Dictionary):
		return {"busy": session.get("busy")}
	var report: Dictionary = last
	var out: Dictionary = {"busy": session.get("busy")}
	for key: String in [
		"ms",
		"open_seams",
		"pending_seams",
		"split_rooms",
		"cut_back_rooms",
		"bored",
		"door_failed",
		"door_misfits"
	]:
		if report.has(key):
			out[key] = report[key]
	if report.has("solids"):
		out["pieces"] = (report["solids"] as Dictionary).size()
	if report.has("rooms"):
		var sizes: PackedInt32Array = PackedInt32Array()
		for members: PackedStringArray in report["rooms"] as Array:
			sizes.append(members.size())
		out["rooms"] = str(sizes)
	return out


## The end of the engine's own log, when file logging is on. Off by default in Godot, so this is
## usually empty and says so - turn on `debug/file_logging/enable_file_logging` to have it.
static func _log_tail() -> PackedStringArray:
	var path: String = str(ProjectSettings.get_setting("debug/file_logging/log_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return PackedStringArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	if lines.size() <= LOG_TAIL_LINES:
		return lines
	return lines.slice(lines.size() - LOG_TAIL_LINES)


## One entry as a human reads it - everything but the document.
static func _digest(entry: Dictionary) -> String:
	var state: Dictionary = entry.get("state", {})
	var bake: Dictionary = state.get("bake", {})
	var out: String = "\n## %s\n\n%s\n\n" % [entry.get("at", ""), entry.get("note", "")]
	out += (
		"- parts %s, selection %s, exploded %s\n"
		% [state.get("parts", "?"), str(state.get("selection", "")), state.get("exploded", "?")]
	)
	if not bake.is_empty():
		out += (
			"- bake: %s pieces, rooms %s, split %s, fell back %s, %s ms\n"
			% [
				bake.get("pieces", "?"),
				bake.get("rooms", "?"),
				bake.get("split_rooms", "?"),
				bake.get("cut_back_rooms", "?"),
				bake.get("ms", "?")
			]
		)
	if not str(entry.get("frame", "")).is_empty():
		out += "- frame: %s\n" % entry["frame"]
	return out


## The builder's own viewport as an image, which under SPEC section 10 is the SubViewport the whole
## app lives in - so the note carries the 1280x800 the player sees, not the desktop window.
static func _frame_of(builder: Node) -> Image:
	var viewport: Viewport = builder.get_viewport()
	if viewport == null:
		return null
	var texture: ViewportTexture = viewport.get_texture()
	return texture.get_image() if texture != null else null


## The first of the two directories that can be made and written. Empty when neither can.
static func _directory() -> String:
	for dir: String in [DIR_PROJECT, DIR_FALLBACK]:
		if DirAccess.make_dir_recursive_absolute(dir) == OK and DirAccess.dir_exists_absolute(dir):
			return dir
	return ""


## Appends [param text] to [param path], making the file if it is not there yet.
static func _append(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(
		path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	)
	if file == null:
		return false
	file.seek_end()
	file.store_string(text)
	file.close()
	return true


static func _guess(node: Node, method: String, fallback: Variant) -> Variant:
	return node.call(method) if node.has_method(method) else fallback


static func _say(builder: Node, text: String) -> void:
	if builder.has_method("set_status"):
		builder.call("set_status", text)
	print(text)
