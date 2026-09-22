## PartTreePanel - the part hierarchy, and the home of the selection, symmetry and component
## commands.
##
## SYMMETRY IS NOW A MODEL, NOT A COMMAND - AND IT IS ON BY DEFAULT
## ---------------------------------------------------------------
## RETIRED(2026-08-31): MIR X / MIR Y / MIR Z / UNLINK -> the BREAK SYMMETRY toggle below
## (`ShipSymmetry`, API_CONTRACT_SPORE section 4). Those four buttons implemented the old
## opt-in model: nothing was mirrored until you asked, and asking created a second, derived
## part you then had to UNLINK to edit. Spore is the other way round. Symmetry is automatic
## and unbreakable in the 2008 release - an "Asymmetry Mod" existed precisely because there
## was no in-game way - and a later patch added hold-`A` to break it for one part. So there
## is nothing to switch ON here; there is only something to BREAK.
##
## THREE CONSEQUENCES, ALL OF THEM VISIBLE IN THIS PANEL:
##
##   1. BREAKING CASCADES. `ShipSymmetry.set_asymmetric()` returns the whole affected
##      subtree, because breaking on a parent breaks it for every part attached to it and
##      for every part attached later. The status line reports that count rather than "1",
##      and the tree marks inherited breaks differently from the one that caused them.
##   2. NEVER READ `part.asymmetric`. It is a per-part FLAG, not a per-part ANSWER: a child
##      under a broken parent has a false flag and is asymmetric anyway. Every question in
##      this file goes through `ShipSymmetry.is_effectively_asymmetric()`, including the one
##      that finds WHICH ancestor did the breaking (`_break_source`, which never touches the
##      field either). Reading the raw flag is the documented bug the class exists to stop.
##   3. IT HALVES COMPLEXITY, AND WE SAY SO. A symmetric part is billed double, so breaking
##      it costs half. Players used exactly that to fit bigger builds; it is a documented
##      trade-off, not an exploit to paper over, so the button tooltip states it up front and
##      the status line prints the real before/after total after every break.
##
## FLOATING PARTS ARE LEGAL AND ARE NOT ERRORS. Spore's ship editor has no contiguity
## requirement at all - bodies "require no base", cockpits "do not have to be attached", and
## no editor in the game has a "disconnected parts" error (SPORE_CLONE_SPEC section 5).
## `doc.floating_part_ids()` is therefore marked `(FLOAT)` in plain text, never in the
## `warning` role and never in a refusal.
##
## SELECTION IS TWO-WAY AND LIVES ONLY HERE AND IN THE BUILDER (SPEC section 6: never in the
## doc). A click in the Tree pushes through builder.set_selection(); a pick in the 3D view
## comes back through builder.selection_changed. Both paths run through the same `_syncing`
## re-entrancy flag rather than through connect/disconnect, because disconnecting a signal to
## avoid a loop drops the events that arrive from a third source while it is down.
##
## Tree.multi_selected fires once PER ITEM, so a plain click that clears five items and sets
## one emits six times. Pushing on each would rebuild the 3D selection six times, so the push
## is coalesced onto one deferred call.
##
## THE TWO NAMED FEATURES (SPEC section 6) are the two buttons at the top:
##   SELECT ALL CHILDREN - extend the selection to doc.descendants_of() of everything in it.
##   SELECT NO CHILDREN  - collapse to the part that was actually clicked last, alone.
##
## LEGACY MIRROR DERIVATIVES are still drawn dim with a (MIRROR) suffix and are still not
## editable, because an old file can contain them and hiding them would be worse than
## showing them. The COMMANDS that created and materialised them are gone - see the
## RETIRED note above. Component instances are drawn in the accent role with a [C] marker.
##
## Every mutation goes through builder.begin_edit()/commit_edit(). commit_edit() can refuse
## and roll back the whole document, so each command re-reads builder.get_doc() afterwards
## and checks that what it made actually survived - a refusal is never silent here.
class_name PartTreePanel
extends VBoxContainer

const TICK_LENGTH: float = 4.0
const BUTTON_HEIGHT: float = 18.0
## RETIRED(2026-08-31): written only by the removed mirror commands. Still READ, so a legacy
## document's derivatives are visible rather than silently indistinguishable.
const MIRROR_SUFFIX: String = " (MIRROR)"
const COMPONENT_MARK: String = "[C] "
const COMPONENT_LABEL_PREFIX: String = "COMP "

## The part carries the break itself: this is where it was made and where it can be undone.
const ASYM_SUFFIX: String = " (ASYM)"
## The break came from an ancestor and cascaded down. The caret points up the tree at the
## part that actually owns it; the tooltip names it. Kept short because this panel is
## 236 px wide (ShipBuilder.LEFT_WIDTH) and the row already carries an id and a name.
const ASYM_INHERITED_SUFFIX: String = " (ASYM^)"
## Parentless and not the root. LEGAL - see the class docs.
const FLOATING_SUFFIX: String = " (FLOAT)"

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null

var _tree: Tree = null
var _status: Label = null
var _command_buttons: Array[Button] = []
## The BREAK SYMMETRY toggle. Its pressed state is the EFFECTIVE state of the first
## selected part, never the raw flag.
var _break_button: Button = null
## part id -> TreeItem, rebuilt with the tree.
var _items: Dictionary = {}
## Set of ids from doc.floating_part_ids(), rebuilt with the tree. Membership only.
var _floating: Dictionary = {}
## Ids whose TreeItem was collapsed, so a rebuild does not spring the whole tree open.
var _collapsed: Dictionary = {}
## Signature of the last built tree; a doc_changed that does not move it is ignored.
var _signature: String = ""
## The part the user last actually clicked - what SELECT NO CHILDREN collapses to.
var _last_clicked: String = ""

var _syncing: bool = false
var _push_queued: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)

	add_child(
		_make_row(
			[
				_make_button("ALL CHILDREN", _on_select_all_children, "SELECT ALL CHILDREN"),
				_make_button("NO CHILDREN", _on_select_no_children, "SELECT NO CHILDREN"),
			]
		)
	)

	_tree = Tree.new()
	_tree.name = "PartTree"
	_tree.columns = 1
	_tree.hide_root = true
	_tree.allow_reselect = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_tree.multi_selected.connect(_on_multi_selected)
	_tree.nothing_selected.connect(_on_nothing_selected)
	_tree.item_collapsed.connect(_on_item_collapsed)
	_tree.item_edited.connect(_on_item_edited)
	add_child(_tree)

	_break_button = _make_toggle("BREAK SYMMETRY", _on_break_symmetry_toggled)
	add_child(_make_row([_break_button]))
	add_child(
		_make_row(
			[
				_make_button(
					"MAKE COMP", _on_make_component, "LIFT THE SELECTED SUBTREE INTO A COMPONENT"
				),
				_make_button("MAKE UNIQUE", _on_make_unique, "CLONE THIS INSTANCE'S DEFINITION"),
			]
		)
	)
	add_child(
		_make_row(
			[
				_make_button(
					"LINK",
					_on_link,
					(
						"SELECT PARTS THAT MEET - CYCLES EVERY SEAM BETWEEN THEM: "
						+ "WALL / DOORWAY / HATCH / OPEN. OPEN IS ONE ROOM."
					)
				),
			]
		)
	)

	_status = Label.new()
	_status.name = "TreeStatus"
	_status.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "NO SELECTION"
	add_child(_status)


func _draw() -> void:
	NumericField.draw_corner_ticks(
		self, Rect2(Vector2.ZERO, size), _role_color("line"), TICK_LENGTH
	)


## Called by ShipBuilder._ready() straight after this scene is mounted into its slot.
func setup(builder: ShipBuilder) -> void:
	_builder = builder
	if _builder == null:
		return
	_ship_theme = _builder.get_ship_theme()
	if _ship_theme != null and not _ship_theme.palette_changed.is_connected(_on_palette_changed):
		_ship_theme.palette_changed.connect(_on_palette_changed)
	_builder.doc_changed.connect(_on_doc_changed)
	_builder.selection_changed.connect(_on_selection_changed)
	_rebuild(true)
	_apply_selection(_builder.get_selection())
	_refresh_symmetry_button()
	_apply_palette()


# ---------------------------------------------------------------- tree build


func _on_doc_changed(_doc: ShipDoc) -> void:
	_rebuild(false)


## `force` rebuilds unconditionally; otherwise the tree is left alone when nothing it draws
## has changed, which keeps an inspector keystroke from tearing down the whole widget.
func _rebuild(force: bool) -> void:
	var doc: ShipDoc = _builder.get_doc()
	var signature: String = _signature_of(doc)
	if not force and signature == _signature:
		return
	_signature = signature
	_items = {}
	_floating = {}
	_tree.clear()
	if doc == null:
		_set_status("NO DOCUMENT")
		return
	# Floating parts are LEGAL (class docs). Collected once per rebuild rather than asked
	# per row, because floating_part_ids() walks part_order() every call.
	for floating_id: String in doc.floating_part_ids():
		_floating[floating_id] = true
	var root: TreeItem = _tree.create_item()
	for part_id: String in doc.part_order():
		var part: ShipPart = _part(doc, part_id)
		if part == null:
			continue
		_add_item(root, doc, part_id, part)
	_apply_selection(_builder.get_selection())
	_refresh_symmetry_button()


func _add_item(root: TreeItem, doc: ShipDoc, part_id: String, part: ShipPart) -> void:
	# part_order() is root-first depth-first, so a parent is always already in _items.
	var parent_item: TreeItem = root
	# A part hung off an inner part of a component sits under the component's row (ADR 0024).
	var found: Variant = _items.get(ShipComponents.instance_of(part.parent), null)
	if found is TreeItem:
		parent_item = found
	var item: TreeItem = _tree.create_item(parent_item)
	item.set_text(0, _text_for(doc, part_id, part))
	item.set_metadata(0, part_id)
	item.set_tooltip_text(0, _tooltip_for(doc, part_id, part))
	# A legacy derivative is generated by reflecting its source, so renaming it in place
	# would be a lie. Same for a locked part.
	item.set_editable(0, not part.is_mirror() and not part.locked)
	item.set_custom_color(0, _role_color(_role_for(doc, part_id, part)))
	item.collapsed = _collapsed.has(part_id)
	_items[part_id] = item


func _text_for(doc: ShipDoc, part_id: String, part: ShipPart) -> String:
	var name: String = part.display_name
	if name.strip_edges() == "":
		name = part.family
	var text: String = "%s  %s" % [part_id, name.to_upper()]
	if part.kind == ShipPart.KIND_COMPONENT_INSTANCE:
		# A component is one room of its parts (ADR 0024); the row says so.
		var definition: Variant = doc.components.get(part.family, null)
		var inner: int = 0
		if definition is Dictionary:
			inner = ((definition as Dictionary).get("parts", {}) as Dictionary).size()
		text = COMPONENT_MARK + text + "  (%d PARTS)" % inner
	if part.is_mirror():
		text += MIRROR_SUFFIX
	# Two different marks on purpose: (ASYM) is a break you can undo here, (ASYM^) is one
	# that cascaded down from an ancestor and has to be undone THERE.
	if ShipSymmetry.is_effectively_asymmetric(doc, part_id):
		var owns: bool = _break_source(doc, part_id) == part_id
		text += ASYM_SUFFIX if owns else ASYM_INHERITED_SUFFIX
	if _floating.has(part_id):
		text += FLOATING_SUFFIX
	if part.locked:
		text += " *"
	return text


func _tooltip_for(doc: ShipDoc, part_id: String, part: ShipPart) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("ID        %s" % part_id)
	lines.append("KIND      %s" % part.kind.to_upper())
	lines.append("FAMILY    %s" % part.family.to_upper())
	if part.manufacturer != "":
		lines.append("MFR       %s" % part.manufacturer.to_upper())
	lines.append("SYMMETRY  %s" % _symmetry_phrase(doc, part_id))
	lines.append("COST      %s COMPLEXITY" % NumericField.format_number(_cost_of(doc, part_id)))
	if _floating.has(part_id):
		# Stated as a fact, not a fault. No editor in Spore has a disconnected-parts error.
		lines.append("FLOATING  LEGAL - THIS EDITOR HAS NO CONTIGUITY REQUIREMENT")
	if part.is_mirror():
		lines.append("MIRROR OF %s ACROSS %s" % [part.mirror_source, part.mirror_plane.to_upper()])
	lines.append("CHILDREN  %d" % doc.children_of(part_id).size())
	return "\n".join(lines)


func _role_for(doc: ShipDoc, part_id: String, part: ShipPart) -> String:
	if part.is_mirror() or part.locked:
		return "text_dim"
	if part.kind == ShipPart.KIND_COMPONENT_INSTANCE:
		return "accent"
	# "ghost" is the only role in data/palette.json (SPEC section 11) not already spoken for
	# in this panel, and it is the apt one: an asymmetric part is one whose twin is not
	# there. In the shipped pack it resolves to the same index as "accent", so the marks in
	# the row text - not the colour - are what separate an asymmetric part from a component
	# instance today. A pack that gives "ghost" its own entry gets the colour too, free.
	# NOT "warning": asymmetry is a choice the player made, not a violation.
	if ShipSymmetry.is_effectively_asymmetric(doc, part_id):
		return "ghost"
	return "text"


## Everything the tree actually draws, in part_order(). Cheap to build, and a string compare
## is far cheaper than tearing down and re-creating every TreeItem on each commit.
##
## The EFFECTIVE asymmetry goes in, not the raw `asymmetric` field: breaking a part changes
## how its whole subtree draws, and a signature built from per-part flags would miss that a
## descendant's mark just changed. `root` and `symmetry_plane` are in for the same reason -
## both move the floating and symmetry marks without touching a single part record.
static func _signature_of(doc: ShipDoc) -> String:
	if doc == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%s|%s" % [doc.root, doc.symmetry_plane])
	for part_id: String in doc.part_order():
		var value: Variant = doc.parts.get(part_id, null)
		if not (value is ShipPart):
			continue
		var part: ShipPart = value
		(
			parts
			. append(
				(
					"%s|%s|%s|%s|%s|%s|%s|%s"
					% [
						part_id,
						part.parent,
						part.kind,
						part.family,
						part.mirror_source,
						part.display_name,
						str(part.locked),
						str(ShipSymmetry.is_effectively_asymmetric(doc, part_id)),
					]
				)
			)
		)
	return "\n".join(parts)


# ---------------------------------------------------------------- selection


func _on_multi_selected(item: TreeItem, _column: int, selected: bool) -> void:
	if _syncing:
		return
	if selected:
		_last_clicked = _id_of(item)
	_queue_push()


func _on_nothing_selected() -> void:
	if _syncing:
		return
	_last_clicked = ""
	_queue_push()


## Tree.multi_selected fires once per item; coalesce so one click is one set_selection().
func _queue_push() -> void:
	if _push_queued:
		return
	_push_queued = true
	_push_selection.call_deferred()


func _push_selection() -> void:
	_push_queued = false
	if _builder == null or _syncing:
		return
	var ids: PackedStringArray = PackedStringArray()
	for key: Variant in _items.keys():
		var part_id: String = str(key)
		var item: TreeItem = _item_for(part_id)
		if item != null and item.is_selected(0):
			ids.append(part_id)
	_syncing = true
	_builder.set_selection(ids)
	_syncing = false
	_report_selection(ids)


func _on_selection_changed(selected: PackedStringArray) -> void:
	if _syncing:
		return
	_apply_selection(selected)
	_report_selection(selected)


func _apply_selection(selected: PackedStringArray) -> void:
	if _tree == null:
		return
	var wanted: Dictionary = {}
	for part_id: String in selected:
		wanted[part_id] = true
	# TreeItem.select()/deselect() emit multi_selected, hence the guard rather than a
	# disconnect: a disconnect would also drop a 3D pick that lands during the rewrite.
	_syncing = true
	for key: Variant in _items.keys():
		var part_id: String = str(key)
		var item: TreeItem = _item_for(part_id)
		if item == null:
			continue
		if wanted.has(part_id):
			item.select(0)
			_reveal(item)
		else:
			item.deselect(0)
	_syncing = false
	if _last_clicked != "" and not wanted.has(_last_clicked):
		_last_clicked = selected[0] if not selected.is_empty() else ""


func _reveal(item: TreeItem) -> void:
	var walker: TreeItem = item.get_parent()
	while walker != null:
		walker.collapsed = false
		walker = walker.get_parent()


func _on_select_all_children() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	if doc == null or selected.is_empty():
		_set_status("SELECT A PART FIRST")
		return
	var seen: Dictionary = {}
	var out: PackedStringArray = PackedStringArray()
	for part_id: String in selected:
		_append_unique(out, seen, part_id)
		for child_id: String in doc.descendants_of(part_id):
			_append_unique(out, seen, child_id)
	_builder.set_selection(out)


func _on_select_no_children() -> void:
	var selected: PackedStringArray = _builder.get_selection()
	if selected.is_empty():
		_set_status("SELECT A PART FIRST")
		return
	var keep: String = _last_clicked
	if keep == "" or not selected.has(keep):
		keep = selected[0]
	_builder.set_selection(PackedStringArray([keep]))


static func _append_unique(out: PackedStringArray, seen: Dictionary, part_id: String) -> void:
	if seen.has(part_id):
		return
	seen[part_id] = true
	out.append(part_id)


# ---------------------------------------------------------------- rename


func _on_item_edited() -> void:
	var item: TreeItem = _tree.get_edited()
	if item == null or _builder == null:
		return
	var part_id: String = _id_of(item)
	var doc: ShipDoc = _builder.get_doc()
	var part: ShipPart = _part(doc, part_id)
	if part == null:
		return
	var name: String = _undecorate(part_id, item.get_text(0))
	_builder.begin_edit("rename part")
	part.display_name = name
	_builder.commit_edit(PackedStringArray([part_id]))
	_rebuild(true)


## The Tree hands back the whole DECORATED row - id, marks and all - so every mark this panel
## can add has to come back off before the remainder is stored as a name. Iterated rather
## than sequenced: an asymmetric floating part carries three suffixes at once, and a fixed
## chain of trim_suffix() calls goes stale the moment that order moves.
func _undecorate(part_id: String, raw: String) -> String:
	var text: String = raw.trim_prefix(COMPONENT_MARK)
	var marks: PackedStringArray = PackedStringArray(
		[" *", FLOATING_SUFFIX, ASYM_INHERITED_SUFFIX, ASYM_SUFFIX, MIRROR_SUFFIX]
	)
	var stripped: bool = true
	while stripped:
		stripped = false
		for mark: String in marks:
			if text.ends_with(mark):
				text = text.trim_suffix(mark)
				stripped = true
	return text.trim_prefix(part_id).strip_edges()


# ---------------------------------------------------------------- symmetry


## The one symmetry command. `pressed` is the state the toggle just moved TO, so this both
## breaks and restores; there is no separate command for the other direction because there
## is no third state.
##
## The whole selection is acted on, not just the last click, because SELECT ALL CHILDREN
## exists two rows up and "break this whole limb" is the obvious thing to want after it.
func _on_break_symmetry_toggled(pressed: bool) -> void:
	var doc: ShipDoc = _builder.get_doc()
	var targets: PackedStringArray = _symmetry_targets(doc)
	if targets.is_empty():
		_refuse(
			"SYMMETRY",
			(
				"SELECT AN EDITABLE PART FIRST.\n"
				+ "SYMMETRY IS PER PART, AND BREAKING IT CASCADES TO EVERYTHING ATTACHED BELOW."
			)
		)
		_refresh_symmetry_button()
		return
	if ShipSymmetry.plane_axis(doc.symmetry_plane) < 0:
		_refuse(
			"SYMMETRY",
			(
				"THIS SHIP MIRRORS ACROSS NO PLANE, SO THERE IS NOTHING TO BREAK.\n"
				+ "NOTHING IS BEING DOUBLED AND NOTHING IS BEING CHARGED TWICE."
			)
		)
		_refresh_symmetry_button()
		return

	var before: float = _complexity_used(doc)
	_builder.begin_edit("break symmetry" if pressed else "restore symmetry")
	# set_asymmetric() returns the EFFECTIVE subtree, which is what has to be repainted and
	# re-totalled - not the single id that was clicked.
	var changed: PackedStringArray = PackedStringArray()
	for part_id: String in targets:
		changed.append_array(ShipSymmetry.set_asymmetric(doc, part_id, pressed))
	# Committed unconditionally: set_asymmetric() can write a part's own flag while changing
	# no EFFECTIVE state (a child under an already-broken ancestor), and that is still a real
	# document change - it decides what happens when the ancestor is restored later.
	#
	# Committed with an EMPTY id list - the contract's "topology moved, diff everything" -
	# and NOT with `changed`. A break adds or removes a mirrored TWIN, whose id is derived
	# ("<source>~m") and therefore never appears in `changed`; a per-id partial refresh would
	# leave that twin on screen after the part that generated it stopped generating one.
	# `changed` is still what the status line reports, because that is the cascade's size.
	_builder.commit_edit(PackedStringArray())
	if _builder.get_doc() != doc:
		_refuse("SYMMETRY", "EDIT REFUSED AND ROLLED BACK - A BUDGET WOULD BE EXCEEDED.")
		return
	_report_symmetry(pressed, changed.size(), before, _complexity_used(_builder.get_doc()))
	_refresh_symmetry_button()


## Parts the command may touch: the selection, minus legacy derivatives and locked parts,
## which have no independent symmetry to break.
func _symmetry_targets(doc: ShipDoc) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if doc == null:
		return out
	for part_id: String in _builder.get_selection():
		var part: ShipPart = _part(doc, part_id)
		if part != null and not part.is_mirror() and not part.locked:
			out.append(part_id)
	return out


## The cascade and the price, in one line, with the real numbers. The halving is a
## documented Spore trade-off (SPORE_CLONE_SPEC section 4) and is reported rather than
## buried: a player who cannot see the saving cannot make the decision the game intends.
func _report_symmetry(broke: bool, count: int, before: float, after: float) -> void:
	var verb: String = "BROKE" if broke else "RESTORED"
	if count <= 0:
		_set_status("%s SYMMETRY - NO CHANGE, AN ANCESTOR ALREADY OWNS IT" % verb)
		return
	_set_status(
		(
			"%s SYMMETRY ON %d PART(S)  COMPLEXITY %s -> %s"
			% [verb, count, NumericField.format_number(before), NumericField.format_number(after)]
		)
	)


## Pressed state, enablement and tooltip, all from the EFFECTIVE state of the first selected
## part. Set with set_pressed_no_signal(), so a model-to-view write can never come back as a
## view-to-model command.
func _refresh_symmetry_button() -> void:
	if _break_button == null or _builder == null:
		return
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	if doc == null or selected.is_empty():
		_break_button.set_pressed_no_signal(false)
		_break_button.disabled = true
		_break_button.tooltip_text = "SELECT A PART TO BREAK ITS SYMMETRY"
		return
	var part_id: String = selected[0]
	var effective: bool = ShipSymmetry.is_effectively_asymmetric(doc, part_id)
	var source: String = _break_source(doc, part_id)
	var inherited: bool = effective and source != part_id
	var plane_off: bool = ShipSymmetry.plane_axis(doc.symmetry_plane) < 0
	_break_button.set_pressed_no_signal(effective)
	# An inherited break cannot be undone here: clearing this part's own flag would leave
	# the ancestor's break in force and the button would spring back. Say where to go.
	_break_button.disabled = inherited or plane_off
	_break_button.tooltip_text = _symmetry_tooltip(doc, part_id, effective, source, plane_off)


func _symmetry_tooltip(
	doc: ShipDoc, part_id: String, effective: bool, source: String, plane_off: bool
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("SYMMETRY IS ON BY DEFAULT - EVERY PART IS MIRRORED UNTIL YOU BREAK IT")
	if plane_off:
		lines.append("THIS SHIP MIRRORS ACROSS NO PLANE - NOTHING TO BREAK")
		return "\n".join(lines)
	lines.append("PLANE %s" % doc.symmetry_plane.to_upper())
	lines.append("THIS PART: %s" % _symmetry_phrase(doc, part_id))
	if effective and source != part_id:
		lines.append("BROKEN AT %s - RESTORE IT THERE, NOT HERE" % source.to_upper())
	else:
		lines.append("BREAKING CASCADES TO EVERY PART ATTACHED BELOW THIS ONE")
		lines.append("A SYMMETRIC PART COSTS DOUBLE - BREAKING IT HALVES THAT")
	return "\n".join(lines)


## One phrase describing a part's effective symmetry, shared by the tooltip and the tree.
func _symmetry_phrase(doc: ShipDoc, part_id: String) -> String:
	if ShipSymmetry.plane_axis(doc.symmetry_plane) < 0:
		return "NO MIRROR PLANE - SINGLE COST"
	if not ShipSymmetry.is_effectively_asymmetric(doc, part_id):
		return "MIRRORED - DOUBLE COST"
	var source: String = _break_source(doc, part_id)
	if source == part_id:
		return "BROKEN HERE - HALF COST, CASCADES DOWN"
	return "BROKEN AT %s - HALF COST, INHERITED" % source.to_upper()


## The part that actually owns an effective break: the OUTERMOST effectively-asymmetric part
## in this one's ancestor chain. "" when the part is not asymmetric at all.
##
## Deliberately derived from is_effectively_asymmetric() alone. Walking the chain looking for
## a raw `asymmetric == true` would be the one thing ShipSymmetry exists to stop, and this
## reaches the same answer with no access to the field: effective asymmetry only ever
## propagates downward, so the furthest ancestor that has it is the one that started it.
func _break_source(doc: ShipDoc, part_id: String) -> String:
	if doc == null or not ShipSymmetry.is_effectively_asymmetric(doc, part_id):
		return ""
	var source: String = part_id
	for ancestor_id: String in doc.ancestors_of(part_id):
		if ShipSymmetry.is_effectively_asymmetric(doc, ancestor_id):
			source = ancestor_id
	return source


## Total charged complexity for a document, for the before/after report.
func _complexity_used(doc: ShipDoc) -> float:
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return 0.0
	return float(ShipComplexity.compute(doc, data, cfg).get("used", 0.0))


## What one part is billed, including its symmetry doubling. Used by the row tooltip.
func _cost_of(doc: ShipDoc, part_id: String) -> float:
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return 0.0
	return ShipComplexity.cost_of(doc, part_id, data, cfg)


# ---------------------------------------------------------------- rooms and hatches


## "i should be able to add a hatch between any 2 connected shapes" ... "it should have dynamic
## options for how 2 rooms link." LINK steps every seam inside the selection round
## ShipBuilder.LINK_CYCLE (ADR 0008) together: WALL - the default, a solid bulkhead - to DOORWAY, a
## plain centred opening, to HATCH, the hatch family opening, to OPEN, no wall at all and one room,
## and back to WALL. Any parts that meet qualify; every part is a room, so there is nothing to
## declare first.
##
## THIS IS ALSO WHAT MAKE ROOM WAS. "they shouldn't really be separate options, as when making a
## room it defines open structures at their link" (2026-09-04). Select the parts and step them to
## OPEN and they are one room, which is the whole of it. Naming one is a rename, done in the tree
## row itself (_on_item_edited).
##
## RETIRED(2026-09-04): MAKE ROOM, _make_room_named, _make_room_joined, _room_suggestion,
## _instance_of_definition. Its single-part branch renamed a part, which the row already does. Its
## multi-part branch lifted the selection into a COMPONENT, which MAKE COMP already does - and it
## did not open the seams between the joined parts. It could not: ShipComponents drops a joint whose
## two ends are both inside the lift, and a dropped joint IS a wall (ShipSeams.mode_for returns
## MODE_WALL when no record exists), so "combining multiple into the same room removes all internal
## walls" did the exact opposite. Measured on a lithium class: 2 joints before the lift, 0 after,
## none of them open.
## RETIRED(2026-09-02): LINK HATCH, which toggled hatched / nothing, and _is_hatched().
##
## CONNECTED is checked before a seam is OPENED - stepping onto doorway, hatch or open - with the
## sample the validator judges every joint by (ShipJoints.solid_pair_state): an opening between
## parts that never meet does nothing, and one between parts that merely touch leads into solid
## hull. A pair that fails is named and the step is refused. Stepping back to a WALL is never
## refused: parts that have drifted apart since must still be closable.
##
## Each joint is keyed over the unordered pair, which is what ShipDoc.joint_key_for() exists for, so
## linking A to B and then B to A is one seam and not two.
func _on_link() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	if doc == null:
		return
	if selected.size() < 2:
		_refuse("LINK", "SELECT TWO OR MORE PARTS THAT MEET.")
		return
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(doc, selected)
	if pairs.is_empty():
		_refuse(
			"LINK",
			(
				"NOTHING IN THE SELECTION IS JOINED TO ANYTHING ELSE IN IT.\n"
				+ "SELECT A PART AND WHAT IT STANDS ON."
			)
		)
		return
	# OPEN steps back to WALL, which closes a seam and needs no contact; every other step opens one
	# wider and does. Checked over the WHOLE group before anything is edited, so a selection with
	# one bad pair in it does not half-apply.
	var current: String = ShipSeams.shared_mode(doc, pairs)
	if current != ShipSeams.MODE_OPEN:
		for pair: PackedStringArray in pairs:
			if not _meet_for_hatch(doc, pair[0], pair[1]):
				return
	var next: String = _builder.cycle_link(selected)
	if next.is_empty():
		_refuse("LINK", "THAT SELECTION COULD NOT BE LINKED.")
		return
	_set_status(
		(
			"LINK %s: %s"
			% [
				(
					(
						"%s <-> %s"
						% [
							_display_of(doc.part_at(pairs[0][0]), pairs[0][0]).to_upper(),
							_display_of(doc.part_at(pairs[0][1]), pairs[0][1]).to_upper(),
						]
					)
					if pairs.size() == 1
					else "%d SEAMS" % pairs.size()
				),
				_link_label(next),
			]
		)
	)


## What the status line calls each link mode.
static func _link_label(mode: String) -> String:
	match mode:
		ShipSeams.MODE_DOORWAY:
			return "DOORWAY"
		ShipSeams.MODE_HATCHED:
			return "HATCH"
		ShipSeams.MODE_OPEN:
			return "OPEN - ONE ROOM"
	return "WALL"


## Do the two parts' interiors meet at the hull thickness, so a hatch between them opens onto air?
## Refuses - with what to do about it - when they do not. A pair the attach pass could not place
## is let through: the validator flags such a joint, and this panel cannot say more than it can.
func _meet_for_hatch(doc: ShipDoc, a: String, b: String) -> bool:
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if data == null or cfg == null:
		return true
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	if not (shapes.has(a) and shapes.has(b) and xforms.has(a) and xforms.has(b)):
		return true
	var state: Dictionary = ShipJoints.solid_pair_state(
		shapes[a], xforms[a], shapes[b], xforms[b], maxf(cfg.hull_thickness_m, 0.0)
	)
	if bool(state["merges"]):
		return true
	var names: Array = [
		_display_of(doc.part_at(a), a).to_upper(), _display_of(doc.part_at(b), b).to_upper()
	]
	if bool(state["overlaps"]):
		_refuse(
			"LINK",
			(
				(
					"%s AND %s ONLY TOUCH: AT THE HULL THICKNESS THEIR INTERIORS NEVER MEET, SO AN "
					+ "OPENING THERE WOULD LEAD INTO SOLID HULL.\n"
					+ "SINK ONE DEEPER INTO THE OTHER, THEN LINK."
				)
				% names
			)
		)
	else:
		_refuse("LINK", "%s AND %s DO NOT MEET.\nMOVE ONE INTO THE OTHER, THEN LINK." % names)
	return false


func _display_of(part: ShipPart, pid: String) -> String:
	return part.display_name if not part.display_name.is_empty() else pid


# ---------------------------------------------------------------- components


## MAKE COMP now ASKS FOR A NAME first. The name is what identifies a component in the palette's
## component list - there is no glyph to recognise it by - so deriving one silently from whichever
## part happened to be selected made saved components indistinguishable from each other.
func _on_make_component() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	if doc == null or selected.is_empty():
		_refuse("MAKE COMPONENT", "SELECT A COMPLETE SUBTREE FIRST.")
		return
	_builder.prompt(
		"MAKE COMPONENT",
		"NAME THIS COMPONENT - IT WILL APPEAR IN THE PALETTE UNDER COMPONENTS.",
		_component_label(doc),
		_make_component_named
	)


func _make_component_named(entered: String) -> void:
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	if doc == null or selected.is_empty():
		_refuse("MAKE COMPONENT", "THE SELECTION CHANGED - SELECT A COMPLETE SUBTREE AND RETRY.")
		return
	var label: String = entered.strip_edges()
	if label == "":
		_refuse("MAKE COMPONENT", "A COMPONENT NEEDS A NAME.")
		return
	_builder.begin_edit("make component")
	var component_id: String = ShipComponents.make_component(doc, selected, label)
	if component_id == "":
		# Refused before touching the doc, so there is nothing to roll back - but the player
		# still has to be told why, and told what to press to fix it.
		_refuse(
			"MAKE COMPONENT",
			(
				"THE SELECTION IS NOT A COMPLETE SUBTREE, OR IT CROSSES A MIRROR LINK.\n"
				+ "PRESS ALL CHILDREN AND TRY AGAIN."
			)
		)
		return
	_builder.commit_edit(PackedStringArray())
	if not _builder.get_doc().components.has(component_id):
		_refuse("MAKE COMPONENT", "EDIT REFUSED AND ROLLED BACK - A BUDGET WOULD BE EXCEEDED.")
		return
	_set_status("COMPONENT %s CREATED - PLACE IT FROM THE PALETTE" % component_id.to_upper())


func _on_make_unique() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	var instance_id: String = ""
	if doc != null:
		for part_id: String in selected:
			var part: ShipPart = _part(doc, part_id)
			if part != null and part.kind == ShipPart.KIND_COMPONENT_INSTANCE:
				instance_id = part_id
				break
	if instance_id == "":
		_refuse("MAKE UNIQUE", "SELECT A COMPONENT INSTANCE - MARKED [C] IN THE TREE.")
		return
	_builder.begin_edit("make unique")
	var component_id: String = ShipComponents.make_unique(doc, instance_id)
	if component_id == "":
		_refuse("MAKE UNIQUE", "THAT PART IS NOT A COMPONENT INSTANCE.")
		return
	_builder.commit_edit(PackedStringArray([instance_id]))
	if not _builder.get_doc().components.has(component_id):
		_refuse("MAKE UNIQUE", "EDIT REFUSED AND ROLLED BACK - A BUDGET WOULD BE EXCEEDED.")
		return
	_set_status("DEFINITION %s IS NOW UNIQUE" % component_id.to_upper())


## A label for a new definition, taken from the topmost selected part so the component reads
## as something rather than as a serial number. There is no in-scene text prompt available
## on the frozen ShipBuilder surface (show_message is the only public dialog), so this is
## derived rather than asked for - rename it in the tree afterwards.
func _component_label(doc: ShipDoc) -> String:
	for part_id: String in _builder.get_selection():
		var part: ShipPart = _part(doc, part_id)
		if part == null:
			continue
		if part.display_name.strip_edges() != "":
			return part.display_name
		if part.family != "":
			return COMPONENT_LABEL_PREFIX + part.family
	return COMPONENT_LABEL_PREFIX + "GROUP"


# ---------------------------------------------------------------- edit plumbing


## HOW A REFUSAL IS DETECTED, since commit_edit() returns nothing. ShipBuilder rolls a refused
## edit back by REPLACING the document with a fresh one rebuilt from the history head, so a
## different ShipDoc instance across the call is exactly a refusal - that is the test the
## symmetry command uses. The component commands instead look for the definition they just
## made in the doc the builder now holds, which answers the same question for an edit whose
## result is a component rather than a part.
func _refuse(title: String, body: String) -> void:
	_set_status("%s REFUSED" % title)
	_builder.show_message(title, body)
	_rebuild(true)


# ---------------------------------------------------------------- widgets


func _make_row(buttons: Array) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for entry: Variant in buttons:
		if entry is Button:
			var button: Button = entry
			row.add_child(button)
	return row


func _make_button(label: String, handler: Callable, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(BUTTON_HEIGHT))
	button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	button.pressed.connect(handler)
	_command_buttons.append(button)
	return button


## A latching command button. `handler` takes the state the toggle moved TO.
func _make_toggle(label: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(ShipTheme.pxf(0.0), ShipTheme.pxf(BUTTON_HEIGHT))
	button.add_theme_font_size_override("font_size", ShipTheme.font_small())
	button.toggled.connect(handler)
	_command_buttons.append(button)
	return button


func _on_item_collapsed(item: TreeItem) -> void:
	var part_id: String = _id_of(item)
	if part_id == "":
		return
	if item.collapsed:
		_collapsed[part_id] = true
	else:
		_collapsed.erase(part_id)


func _report_selection(selected: PackedStringArray) -> void:
	# The toggle reads the FIRST selected part, so it moves with every selection change -
	# from this panel, from a 3D pick, or from SELECT ALL CHILDREN.
	_refresh_symmetry_button()
	if selected.is_empty():
		_set_status("NO SELECTION")
		return
	if selected.size() == 1:
		_set_status("SELECTED %s" % selected[0])
		return
	_set_status("SELECTED %d PARTS" % selected.size())


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# ---------------------------------------------------------------- lookups


func _item_for(part_id: String) -> TreeItem:
	var value: Variant = _items.get(part_id, null)
	if value is TreeItem:
		return value
	return null


static func _id_of(item: TreeItem) -> String:
	if item == null:
		return ""
	var meta: Variant = item.get_metadata(0)
	if meta is String:
		return meta
	return ""


static func _part(doc: ShipDoc, part_id: String) -> ShipPart:
	if doc == null:
		return null
	var value: Variant = doc.parts.get(part_id, null)
	if value is ShipPart:
		return value
	return null


# ---------------------------------------------------------------- palette


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_apply_palette()
	_rebuild(true)


func _apply_palette() -> void:
	if _status != null:
		_status.add_theme_color_override("font_color", _role_color("text_dim"))
	for button: Button in _command_buttons:
		if is_instance_valid(button):
			button.add_theme_color_override("font_color", _role_color("text"))
	queue_redraw()


## The only sanctioned colour lookup. Never an index (SPEC section 11).
func _role_color(role: String) -> Color:
	if _ship_theme == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	return _ship_theme.color_for_role(role)
