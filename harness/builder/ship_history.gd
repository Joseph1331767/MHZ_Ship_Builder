## ShipHistory - snapshot undo/redo (API_CONTRACT section 22).
##
## Deliberately NOT command-based. Each entry is a whole doc.to_dict() snapshot with a
## depth cap. A few hundred parts is a small dictionary, and a snapshot stack cannot
## desynchronise from the document the way a stack of inverse commands can.
##
## Usage pattern - mutate, then push the state you ARRIVED at:
##
##     ...mutate doc...
##     history.push(doc, "add part")     # snapshot of the post-edit doc
##
## so the head always equals the live document - which is what lets peek() serve as the
## rollback in ShipBuilder._commit - and undo() hands back the state before that edit. The
## builder seeds the stack with one push at document creation so the first edit has somewhere
## to go back to.
##
## RETIRED(2026-09-27): "push the state you are LEAVING, before you mutate". It never described
## the only caller: ShipBuilder.begin_edit() records a label and nothing else, and _commit()
## pushes AFTER the mutation. The code wins (AGENTS section 10a).
##
## SPEC section 8: undo is one of the three budget-enforcement exemptions (with loading
## and deleting). Undo must never be refused - this class therefore knows nothing about
## budgets and the caller must not gate it on them.
class_name ShipHistory
extends RefCounted

const DEFAULT_DEPTH: int = 64

## How long a push of the SAME label folds into the one before it instead of taking a slot.
##
## AUTO-REPEAT IS WHY. The numpad rotations and the arrow steps deliberately pass their echo
## events through (`ShipView3D._handle_key`) because they are the two bindings a player holds
## down on purpose - but every echo ran a full begin_edit/commit_edit, and every commit pushed a
## whole `doc.to_dict()`. Against [constant DEFAULT_DEPTH] that is 64 slots gone in about two
## seconds of held numpad-4, taking every earlier edit with them (docs/future/ux.md section 2.5,
## B9). Folding the run into its FIRST snapshot means one undo steps back over the whole hold,
## which is also what a player means by "undo that turn".
##
## 400 ms is comfortably longer than any key-repeat interval and far shorter than a deliberate
## second press, so a run coalesces and two separate edits do not.
const COALESCE_MS: int = 400

## Maximum number of snapshots retained. Oldest are dropped from the front.
var depth: int = DEFAULT_DEPTH

## The coalescing window, in milliseconds. Zero switches it off, which is one snapshot per push -
## the behaviour before 2026-09-27, and what a test asserting the raw stack wants.
var coalesce_ms: int = COALESCE_MS

var _stack: Array[Dictionary] = []
var _labels: PackedStringArray = PackedStringArray()
## Index of the snapshot representing the CURRENT committed state, -1 when empty.
var _index: int = -1
## The label, key and clock of the last push, for the coalescing window above. An empty key or a
## clock of -1 means "no run open".
var _last_label: String = ""
var _last_key: String = ""
var _last_ms: int = -1


func _init(max_depth: int = DEFAULT_DEPTH) -> void:
	depth = maxi(1, max_depth)


## Snapshot doc and make it the new head. Any redo tail is discarded, as it must be:
## a new edit branched from here invalidates the future that was undone away.
## [param key] names WHAT the edit touched, and two pushes only fold together when it matches.
## Additive third parameter (2026-09-27): the contract pins `push(doc, label)` and every existing
## caller still compiles and behaves identically, because an empty key never folds.
func push(doc: ShipDoc, label: String, key: String = "") -> void:
	if doc == null:
		return
	if _coalesces(label, key):
		# REPLACE THE HEAD, never skip. The head has to keep matching the live document: the
		# budget refusal in ShipBuilder._commit restores from peek() BEFORE the push, so a
		# stale head there would silently roll a legitimate hold back to where it started.
		# Replacing folds the run into one slot AND keeps peek() honest.
		_stack[_index] = doc.to_dict()
		_labels[_index] = label
		return
	if _index < _stack.size() - 1:
		_stack.resize(_index + 1)
		_labels.resize(_index + 1)
	_stack.append(doc.to_dict())
	_labels.append(label)
	while _stack.size() > depth:
		_stack.remove_at(0)
		_labels.remove_at(0)
	_index = _stack.size() - 1


## Whether this push folds into the one before it rather than taking a slot of its own. Stamps
## the run either way, so the window is measured from the last push and a steady stream of
## repeats keeps folding into the one snapshot the run opened with.
##
## ONLY AT THE HEAD. After an undo there is a redo tail to discard, and discarding it is the
## appending branch's job - folding there would leave a future that no longer follows from the
## present.
##
## AND ONLY WITH A KEY. An edit that names no parts - a joint or a topology change - never folds:
## without the ids there is nothing to say two pushes were one gesture, and folding two different
## ones costs an undo the player expected. `tools/ship_visual_check.gd` caught exactly that, by
## making two seam-style edits faster than any human could and finding one undo had swallowed
## both.
func _coalesces(label: String, key: String) -> bool:
	var now: int = Time.get_ticks_msec()
	var same_run: bool = (
		coalesce_ms > 0
		and not key.is_empty()
		and key == _last_key
		and label == _last_label
		and _last_ms >= 0
		and now - _last_ms <= coalesce_ms
		and _index >= 0
		and _index == _stack.size() - 1
	)
	_last_label = label
	_last_key = key
	_last_ms = now
	return same_run


## Step back one snapshot and rebuild a ShipDoc from it. Returns null when there is
## nothing to undo (contract: "returns null when empty").
func undo() -> ShipDoc:
	if not can_undo():
		return null
	_close_run()
	_index -= 1
	return ShipDoc.from_dict(_stack[_index])


## Step forward one snapshot. Returns null when there is nothing to redo.
func redo() -> ShipDoc:
	if not can_redo():
		return null
	_close_run()
	_index += 1
	return ShipDoc.from_dict(_stack[_index])


## End the open run, so the next edit takes a slot of its own however fast it follows. Stepping
## through history is a deliberate act and the edit after it is a new one by definition.
func _close_run() -> void:
	_last_label = ""
	_last_key = ""
	_last_ms = -1


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index >= 0 and _index < _stack.size() - 1


func clear() -> void:
	_close_run()
	_stack.clear()
	_labels = PackedStringArray()
	_index = -1


## Label of the edit that undo() would step back over, "" when none.
func undo_label() -> String:
	if not can_undo():
		return ""
	return _labels[_index]


## Label of the edit that redo() would step forward into, "" when none.
func redo_label() -> String:
	if not can_redo():
		return ""
	return _labels[_index + 1]


func size() -> int:
	return _stack.size()


## Rebuild the current head as a fresh ShipDoc. Useful for "revert" without moving the
## cursor. Returns null when the stack is empty.
func peek() -> ShipDoc:
	if _index < 0:
		return null
	return ShipDoc.from_dict(_stack[_index])
