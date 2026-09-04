## ShipHistory - snapshot undo/redo (API_CONTRACT section 22).
##
## Deliberately NOT command-based. Each entry is a whole doc.to_dict() snapshot with a
## depth cap. A few hundred parts is a small dictionary, and a snapshot stack cannot
## desynchronise from the document the way a stack of inverse commands can.
##
## Usage pattern - push the state you are LEAVING, before you mutate:
##
##     history.push(doc, "add part")     # snapshot of the pre-edit doc
##     ...mutate doc...
##
## so undo() hands back the doc as it was before that edit. The builder seeds the stack
## with one push at document creation so the first edit has somewhere to go back to.
##
## SPEC section 8: undo is one of the three budget-enforcement exemptions (with loading
## and deleting). Undo must never be refused - this class therefore knows nothing about
## budgets and the caller must not gate it on them.
class_name ShipHistory
extends RefCounted

const DEFAULT_DEPTH: int = 64

## Maximum number of snapshots retained. Oldest are dropped from the front.
var depth: int = DEFAULT_DEPTH

var _stack: Array[Dictionary] = []
var _labels: PackedStringArray = PackedStringArray()
## Index of the snapshot representing the CURRENT committed state, -1 when empty.
var _index: int = -1


func _init(max_depth: int = DEFAULT_DEPTH) -> void:
	depth = maxi(1, max_depth)


## Snapshot doc and make it the new head. Any redo tail is discarded, as it must be:
## a new edit branched from here invalidates the future that was undone away.
func push(doc: ShipDoc, label: String) -> void:
	if doc == null:
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


## Step back one snapshot and rebuild a ShipDoc from it. Returns null when there is
## nothing to undo (contract: "returns null when empty").
func undo() -> ShipDoc:
	if not can_undo():
		return null
	_index -= 1
	return ShipDoc.from_dict(_stack[_index])


## Step forward one snapshot. Returns null when there is nothing to redo.
func redo() -> ShipDoc:
	if not can_redo():
		return null
	_index += 1
	return ShipDoc.from_dict(_stack[_index])


func can_undo() -> bool:
	return _index > 0


func can_redo() -> bool:
	return _index >= 0 and _index < _stack.size() - 1


func clear() -> void:
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
