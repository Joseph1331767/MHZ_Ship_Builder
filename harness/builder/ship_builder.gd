## ShipBuilder - the app root. Everything the builder is, hangs off this Control.
##
## It owns the ShipDoc (the truth), the ShipData packs, the ShipConfig levers, the
## ShipHistory snapshot stack, the ShipTheme palette, and the 3D view. Panels do not own
## any of that; they ask for it through the accessors below and mutate through
## begin_edit()/commit_edit() so undo and the budget guard cannot be bypassed.
##
## RENDER-TO-TEXTURE (SPEC section 10) - the rules this file exists to keep:
##
##   1. NOTHING here reads DisplayServer, get_window(), or any OS window size. The whole
##      layout is derived from this Control's own rect, which is handed to it by the app
##      SubViewport. That is what lets the identical scene render onto a diegetic device
##      in MHZ_Origins driven by Viewport.push_input().
##   2. NO native dialogs. Every dialog is the in-scene _modal Control built below. A
##      FileDialog or AcceptDialog is a native window and simply would not exist on the
##      texture.
##   3. All input arrives through _gui_input on Controls and through _unhandled_key_input,
##      using the positions Godot hands us. Never a global mouse position.
##
## WHY THE SCENE FILES ARE ALMOST EMPTY. ship_builder.tscn is a bare Control with this
## script attached and nothing else; every container, button, slot and layer below is
## created in _ready(). Hand-authoring Godot scene text is error-prone and reviewing a
## diff of it is worse, so the structure lives in code where it can be read and typed.
## The only nodes that stay in .tscn are the two SubViewportContainer/SubViewport pairs
## that define the render-to-texture nesting, because that nesting IS the contract.
##
## PANEL SLOTS. Four empty VBoxContainers are exposed for the panels agent:
## PartPaletteSlot, TreeSlot, InspectorSlot, GaugeSlot - reachable as typed properties,
## via get_slot(), or as %-unique names. If a matching scene exists under harness/panels/
## it is instantiated into its slot automatically and, when it has one, its
## setup(builder) method is called. Nothing in this file needs to change for that.
class_name ShipBuilder
extends Control

## The document was created, replaced, or mutated. Panels rebuild their view of it.
signal doc_changed(doc: ShipDoc)
## The UI-layer selection changed. Selection never lives in the doc (SPEC section 6).
signal selection_changed(selected: PackedStringArray)
## Undo/redo availability changed, for toolbar and menu enablement.
signal history_changed(can_undo: bool, can_redo: bool)
## The in-progress placement moved. `part_id` is the part being re-placed, or "" when the
## ghost is a new part that does not exist in the document yet. Re-emitted from
## ShipPlacement.ghost_moved so a panel can bind to the builder alone.
signal attach_preview_changed(
	part_id: String, yaw: float, pitch: float, rot: Vector3, offset: float
)
## A placement started or ended. Panels use it to enable placement-only affordances.
signal placement_state_changed(is_active: bool)

## In-scene dialog kinds. There is no native dialog here and never will be.

const POST_SHADER_PATH: String = "res://shaders/palette_post.gdshader"
## Above every panel, so the quantizer catches the whole app viewport.
const POST_LAYER: int = 100
const SHIP_DIR: String = "user://ships"
## The four ways two rooms can link (ADR 0008), in the order LINK cycles them. String literals
## rather than ShipSeams' constants only so this class-level const carries no cross-class
## reference; they ARE ShipSeams.MODE_WALL / MODE_DOORWAY / MODE_HATCHED / MODE_OPEN.
const LINK_CYCLE: Array = ["wall", "doorway", "hatched", "open"]

## The three ways two solids can be resolved where they meet, in the order the menu lists them,
## with the labels the author used for them. String literals rather than ShipJoint's constants
## only so this class-level const carries no cross-class reference; they ARE ShipJoint.SEAM_*.
## The six seam styles, laid out as the TWO AXES they are (ADR 0013): which solid indents the
## other, and what the linkage surface is. A `header` entry is a heading rather than a choice.
##
## RETIRED(ADR 0013, 2026-09-04): a flat list of six names drawn from two unrelated schemes - two
## of them by the attach tree ("PARENT INDENTS CHILD") and four by a plane position ("IN-BUMP
## SLICE"). Same six behaviours, one scheme: "i think its more appropriate to classify it as big
## indents small, or small indents big. then to append on the toggles with that of flat inserted,
## flat cutoff, or native inserted."
const SEAM_STYLE_ITEMS: Array = [
	{"header": "SMALL INDENTS BIG"},
	{"id": "small_flat_insert", "label": "FLAT INSERTED"},
	{"id": "small_flat_cutoff", "label": "FLAT CUTOFF"},
	{"id": "small_native", "label": "NATIVE INSERTED"},
	{"header": "BIG INDENTS SMALL"},
	{"id": "big_flat_insert", "label": "FLAT INSERTED"},
	{"id": "big_flat_cutoff", "label": "FLAT CUTOFF"},
	{"id": "big_native", "label": "NATIVE INSERTED"},
]

const HEADER_HEIGHT: int = 30
const LEFT_WIDTH: int = 236
const RIGHT_WIDTH: int = 292
const GAUGE_HEIGHT: int = 78
const STATUS_HEIGHT: int = 22
const DIALOG_WIDTH: int = 420

## Optional auto-mount. First path that exists wins; a panel with a setup(builder) method
## gets called with this node. Nothing breaks when none of them exist.
const PANEL_CANDIDATES: Dictionary = {
	"PartPaletteSlot":
	["res://harness/panels/part_palette.tscn", "res://harness/panels/part_palette_panel.tscn"],
	"TreeSlot": ["res://harness/panels/part_tree.tscn", "res://harness/panels/tree_panel.tscn"],
	"InspectorSlot":
	["res://harness/panels/inspector.tscn", "res://harness/panels/inspector_panel.tscn"],
	"GaugeSlot": ["res://harness/panels/gauges.tscn", "res://harness/panels/gauge_strip.tscn"],
}

## Panel slots - empty VBoxContainers owned by this node, filled by the panels agent.
## Children stack vertically; give a child size_flags_vertical = SIZE_EXPAND_FILL to make
## it take the slot.
var part_palette_slot: VBoxContainer = null
var tree_slot: VBoxContainer = null
var inspector_slot: VBoxContainer = null
var gauge_slot: VBoxContainer = null
## RETIRED(2026-08-31, same day it was mounted): the PAINT slot.
##
## Paint is OUT OF SCOPE for this module. The author: "what is this paint stuff... thats not in
## the scope... i have an AI texturing pipeline. we are only building geometry here." Phase 1
## builds geometry; colour and texture belong to that pipeline, not to the hull builder.
##
## `harness/panels/paint_panel.gd`, `harness/builder/paint_mode.gd`, `core/ship_paint.gd` and
## `data/paint_styles.json` are LEFT ON DISK and still validate - `ShipPart.paint` is reserved in
## the data model (SPEC section 5.1) and the panel is a working dev tool for auditing the palette.
## Nothing mounts it, and PANEL_CANDIDATES no longer lists a PaintSlot, so no click reaches it.
var paint_slot: VBoxContainer = null

var _data: ShipData = null
var _config: ShipConfig = null
var _doc: ShipDoc = null
var _history: ShipHistory = null
var _ship_theme: ShipTheme = null
var _view: ShipView3D = null
var _placement: ShipPlacement = null
var _selection: PackedStringArray = PackedStringArray()
var _slots: Dictionary = {}
var _pending_label: String = "edit"
var _auto_alert: bool = true

var _status_label: Label = null
var _post_rect: ColorRect = null
var _mode_option: OptionButton = null
var _view_toggles: ShipViewToggles = null
var _ui_mode: ShipUiMode = null
var _layers: ShipLayersControl = null
var _undo_button: Button = null
var _redo_button: Button = null
## EXPLODE / ASSEMBLE (ADR 0008). The exploded view shows bakes, not the document, so any edit
## assembles first - see _leave_explode().
var _explode_button: Button = null
var _edit_button: Button = null
var _rooms_button: Button = null
## Whether an open room explodes as its member pieces (false) or as one whole shell (true).
## "an explode control toggle to choose to explode rooms or keep them whole" (2026-09-05).
var _rooms_whole: bool = false
var _exploded: bool = false
## What the engine has made - the last bake, its extras, whether it is stale, whether the engine
## is busy (ADR 0030) - and whether the baked assembled view is on screen (ADR 0023).
var _bake_session: ShipBakeSession = null
var _baked: bool = false
## The explode options: the player's settings, their panel and their file (ADR 0031).
var _explode_opts: ShipExplodeControl = null
var _update_button: Button = null
## The component instance open for editing in isolation (ADR 0024), or "".
var _isolated: String = ""
var _progress: ProgressBar = null
var _bake_hud: ShipBakeHud = null
## Whether a ship that arrives bakes itself (ADR 0028); the visual check turns it off.
var _resolve_on_load_enabled: bool = true
## The right-click seam menu (ADR 0009), and the pair it was opened on.
var _context_menu: ShipContextMenu = null
## Every connection the open seam menu will restyle, as `[child, host]` pairs. Captured when the
## menu opens rather than read back when an item is pressed, so a selection that changes under an
## open menu cannot retarget it.
var _seam_pairs: Array[PackedStringArray] = []

var _start_dialog: ShipStartDialog = null
var _tutorial: ShipTutorial = null
var _modal_ui: ShipModal = null
## The modal's full-rect layer, kept as a member of its own because
## `tools/ship_visual_check.gd` reaches `_builder.get("_modal")` BY NAME (FOLLOWUPS F40 on
## tool-reached members). The dialog itself lives in [ShipModal].
var _modal: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

	# BEFORE the Theme is built and before any panel exists: every font override and minimum size
	# below is authored against ShipTheme.DESIGN_SIZE and multiplied by this on the way in.
	ShipTheme.ui_scale = ShipTheme.scale_for(_own_view_size())
	resized.connect(_on_resized)

	_ship_theme = ShipTheme.new()
	_data = ShipData.new()
	var data_ok: bool = _data.load_all()
	_ship_theme.load_pack(_data)
	_ship_theme.palette_changed.connect(_on_palette_changed)

	_config = _data.config
	if _config == null:
		_config = ShipConfig.defaults()

	theme = _ship_theme.build_theme()
	_history = ShipHistory.new()
	_bake_session = ShipBakeSession.new(self, _current_doc, _show_bake, _on_bake_progress)

	_build_layout()
	_build_context_menu()
	_modal_ui = ShipModal.new(self, _ship_theme, float(DIALOG_WIDTH))
	_modal = _modal_ui.layer()
	_build_start_dialog()
	_build_tutorial()
	_build_post_process()
	_view.setup(_ship_theme, self)
	_layers.use(_view)
	_explode_opts = ShipExplodeControl.new(
		_view.get_parent() as Control, _view, _config, _ship_theme
	)
	_build_placement()

	_new_document()
	_mount_panels()
	# LAST, so every panel it hides has already been mounted into its slot.
	_ui_mode.use(self)

	if not data_ok:
		set_status("DATA LOAD INCOMPLETE - CHECK data/ PACKS")
	# The host may not have sized its viewport until after this node was ready, so take the
	# measurement again now that the tree is up.
	_on_resized()


# ---------------------------------------------------------------- ui scale


## The rect this console was given, NOT the OS window (SPEC section 10 / AGENTS section 7).
##
## `size` is this Control's own rect and is the right answer once layout has run; before that it
## can still be the scene's authored size, so the containing viewport's size is used as the
## fallback. That viewport is the builder's own SubViewport - on the diegetic device it is the
## 1280x800 device texture, never a window - so reading it breaks no rule. Nothing here touches
## DisplayServer, get_window() or a global mouse position.
func _own_view_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	var vp: Viewport = get_viewport()
	if vp != null:
		return vp.get_visible_rect().size
	return Vector2(ShipTheme.DESIGN_SIZE)


## Re-derive the UI scale when the console's rect changes.
##
## ShipTheme.scale_for() quantizes to UI_SCALE_STEP, so dragging a window edge restyles at a
## handful of thresholds rather than every pixel; between thresholds this is a compare and a
## return. rescale_ui() rewrites the EXISTING overrides by the ratio, so it is exact under
## repeated resizes and needs no record of what anything was authored as.
func _on_resized() -> void:
	if _ship_theme == null:
		return
	var want: float = ShipTheme.scale_for(_own_view_size())
	if is_equal_approx(want, ShipTheme.ui_scale):
		return
	_ship_theme.rescale_ui(self, want)


# ---------------------------------------------------------------- accessors


func get_doc() -> ShipDoc:
	return _doc


func get_data() -> ShipData:
	return _data


func get_config() -> ShipConfig:
	return _config


func get_ship_theme() -> ShipTheme:
	return _ship_theme


func get_history() -> ShipHistory:
	return _history


func get_view() -> ShipView3D:
	return _view


## "PartPaletteSlot" | "TreeSlot" | "InspectorSlot" | "GaugeSlot". Null when unknown.
func get_slot(slot_name: String) -> Control:
	return _slots.get(slot_name, null)


func get_selection() -> PackedStringArray:
	return _selection


## The session's placement state machine (API_CONTRACT_UI section 1). Never null after
## _ready(); ask it for `active` rather than tracking a copy of that flag.
func get_start_dialog() -> ShipStartDialog:
	return _start_dialog


func get_placement() -> ShipPlacement:
	return _placement


# ---------------------------------------------------------------- selection


## Selection lives only in the UI layer and is never written to the doc (SPEC section 6).
func set_selection(ids: PackedStringArray) -> void:
	_selection = _filter_selection(ids)
	if _view != null:
		_view.set_selection(_selection)
	selection_changed.emit(_selection)


## Click / ctrl-click behaviour. additive toggles the id in the current selection.
## Select a part by id.
##
## A DERIVED SYMMETRY TWIN RESOLVES TO ITS SOURCE. Twins are drawn and pickable but are not doc
## parts, so selecting one by its own `"<source>~m"` id would put an id in the selection that
## nothing else can resolve - the inspector would find no part, and the selection filter would
## quietly drop it, so clicking the mirrored half of a ship would appear to do nothing.
func select_part(raw_id: String, additive: bool) -> void:
	var part_id: String = ShipSymmetry.source_of_twin(raw_id)
	if part_id == "":
		if not additive:
			set_selection(PackedStringArray())
		return
	if not additive:
		set_selection(PackedStringArray([part_id]))
		return
	var next: PackedStringArray = PackedStringArray()
	var removed: bool = false
	for pid: String in _selection:
		if pid == part_id:
			removed = true
		else:
			next.append(pid)
	if not removed:
		next.append(part_id)
	set_selection(next)


# ---------------------------------------------------------------- editing


## Announce an edit that is about to happen. Pair every call with commit_edit().
## Nothing is snapshotted here: the history head already holds the pre-edit document, so
## a refused edit is restored from it and a committed edit appends the new state.
func begin_edit(label: String) -> void:
	_pending_label = label


## Finish an edit. `changed_ids` lets the 3D view refresh only those parts - pass an
## empty array when the topology changed and the whole scene must be diffed.
##
## SPEC section 8: an edit that pushes a budget past its cap is REFUSED and rolled back.
## Loading, deleting and undo do not come through here, which is what keeps those three
## exempt - lower a lever tomorrow and today's ships still open.
func commit_edit(changed_ids: PackedStringArray) -> void:
	_commit(changed_ids, true)


## Add a primitive part under `parent_id` ("" = current selection, else the root).
## Returns the new part id, or "" when the edit was refused or impossible.
func add_part(family_id: String, manufacturer_id: String, parent_id: String) -> String:
	if _doc == null or _data == null or family_id == "":
		return ""
	var parent: String = parent_id
	if parent == "":
		parent = _selection[0] if not _selection.is_empty() else _doc.root
	begin_edit("add part")
	var part: ShipPart = ShipPart.new()
	part.parent = parent
	part.family = family_id
	part.manufacturer = manufacturer_id
	part.params = ShapeGen.default_params(_data, family_id, manufacturer_id)
	part.scale = Vector3.ONE
	# Seated INTO the parent, not on it - see ShipAttach.default_offset().
	part.offset = ShipAttach.default_offset(
		ShipAttach.resolve_shapes_for_part(_doc, _data, _config, _doc.parts.get(parent, null)),
		ShipAttach.resolve_shapes_for_part(_doc, _data, _config, part),
		part,
		_config
	)
	var new_id: String = _doc.add_part(part)
	_selection = PackedStringArray([new_id])
	if not _commit(PackedStringArray(), true):
		return ""
	set_status("ADDED %s" % new_id)
	return new_id


## Delete every selected part that is deletable. Deleting is budget-exempt by design.
## Toggles a hatched joint between two parts. Returns true when a hatch now exists.
##
## An existing joint between the pair is flipped rather than duplicated: joints are keyed over the
## unordered pair (ShipDoc.joint_key_for), and two joints over one pair would give the bake two
## contradictory answers about whether that wall is there.
## Steps a whole SELECTION one notch round LINK_CYCLE - WALL -> DOORWAY -> HATCH -> OPEN -> WALL -
## and returns the mode they all now carry, or "" if nothing was linkable. Every pair of parts
## within [param ids] that is joined parent-to-child moves together.
##
## TAKES A SELECTION, NOT A PAIR, because a room is not a separate idea from a link: "they
## shouldn't really be separate options, as when making a room it defines open structures at their
## link" (2026-09-04). Selecting several parts and stepping them to OPEN IS making them one room -
## no wall between any of them - and that is the whole of what MAKE ROOM used to promise. Naming
## one is a rename, which the part tree has always done in the row itself.
##
## ONE MODE FOR THE GROUP, and one undo step. A selection whose links already agree steps on from
## there; a mixed one is unified first, at the mode the cycle would reach from a wall, so a second
## press is predictable rather than depending on which pair the walk happened to see first.
##
## A wall is the ABSENCE of a record, so stepping onto WALL erases the joint; a hatch keeps
## whatever family the joint already carried, or takes the default one.
func cycle_link(ids: PackedStringArray) -> String:
	if _doc == null:
		return ""
	var pairs: Array[PackedStringArray] = ShipSeams.pairs_within(_doc, ids)
	if pairs.is_empty():
		return ""
	var here: String = ShipSeams.shared_mode(_doc, pairs)
	var next: String = str(LINK_CYCLE[(LINK_CYCLE.find(here) + 1) % LINK_CYCLE.size()])
	begin_edit("link " + next)
	for pair: PackedStringArray in pairs:
		_set_link(pair[0], pair[1], next)
	commit_edit(PackedStringArray())
	return next


## Puts one pair at [param link]. Caller brackets this with begin_edit/commit_edit.
func _set_link(a: String, b: String, link: String) -> void:
	# Two chunks of one component: the link lives in the definition (ADR 0025).
	if ShipSeams.within_one_instance(_doc, a, b):
		var inner: ShipJoint = ShipComponents.inner_joint_for(_doc, a, b)
		if link == ShipSeams.MODE_WALL:
			ShipComponents.set_inner_joint(_doc, a, b, null)
			return
		if inner == null:
			inner = ShipJoint.new()
		inner.mode = _joint_mode_for_link(link)
		if link == ShipSeams.MODE_HATCHED and inner.hatch_family.is_empty():
			inner.hatch_family = _default_hatch()
		ShipComponents.set_inner_joint(_doc, a, b, inner)
		return
	var existing: String = _joint_id_for(a, b)
	if link == ShipSeams.MODE_WALL:
		if not existing.is_empty():
			_doc.joints.erase(existing)
		return
	var joint: ShipJoint = null
	if existing.is_empty():
		joint = ShipJoint.new()
		joint.id = _doc.new_joint_id()
		joint.a = a if a <= b else b
		joint.b = b if a <= b else a
		_doc.joints[joint.id] = joint
	else:
		joint = _doc.joints[existing]
	joint.mode = _joint_mode_for_link(link)
	if link == ShipSeams.MODE_HATCHED and joint.hatch_family.is_empty():
		joint.hatch_family = _default_hatch()


## The id of the joint over the unordered pair, or "".
func _joint_id_for(a: String, b: String) -> String:
	if _doc == null:
		return ""
	var key: String = ShipDoc.joint_key_for(a, b)
	for jid: String in _doc.joints:
		var joint: ShipJoint = _doc.joints[jid]
		if ShipDoc.joint_key_for(joint.a, joint.b) == key:
			return jid
	return ""


static func _joint_mode_for_link(link: String) -> String:
	match link:
		ShipSeams.MODE_DOORWAY:
			return ShipJoint.MODE_DOORWAY
		ShipSeams.MODE_HATCHED:
			return ShipJoint.MODE_HATCHED
		ShipSeams.MODE_OPEN:
			return ShipJoint.MODE_OPEN
	return ShipJoint.MODE_SEALED


func _default_hatch() -> String:
	if _data == null:
		return ""
	if _data.hatches.has(ShipTemplates.DEFAULT_HATCH):
		return ShipTemplates.DEFAULT_HATCH
	for hid: String in _data.hatches:
		return hid
	return ""


func delete_selected() -> void:
	# A ghost attached to a part that is about to stop existing has nowhere to go.
	cancel_placement()
	if _doc == null or _selection.is_empty():
		return
	var doomed: PackedStringArray = PackedStringArray()
	for pid: String in _selection:
		if pid == _doc.root:
			continue
		var part: ShipPart = _doc.parts.get(pid, null)
		if part == null or part.locked:
			continue
		doomed.append(pid)
	if doomed.is_empty():
		set_status("NOTHING DELETABLE IN SELECTION")
		return
	begin_edit("delete")
	for pid: String in doomed:
		if _doc.parts.has(pid):
			_doc.remove_part(pid)
	_selection = PackedStringArray()
	_commit(PackedStringArray(), false)
	set_status("DELETED %d PART(S)" % doomed.size())


## Undo is never refused - one of the three budget exemptions (SPEC section 8). The budget
## guard lives in commit_edit(), which this deliberately does not go through.
func undo() -> void:
	cancel_placement()
	var restored: ShipDoc = _history.undo()
	if restored == null:
		set_status("NOTHING TO UNDO")
		return
	_replace_doc(restored)
	set_status("UNDO")


## Redo is the mirror of undo and is likewise never budget-checked: it replays a state the
## document has already been in, so refusing it could strand the player mid-history.
func redo() -> void:
	cancel_placement()
	var restored: ShipDoc = _history.redo()
	if restored == null:
		set_status("NOTHING TO REDO")
		return
	_replace_doc(restored)
	set_status("REDO")


# ---------------------------------------------------------------- placement


## Raise a ghost for a NEW part of `family_id`, attached to the current selection (or the
## root). The ghost is not in the document until ShipPlacement.commit() succeeds.
func begin_placement(
	family_id: String, manufacturer_id: String, kind: String = ShipPart.KIND_PRIMITIVE
) -> void:
	if _placement == null or _doc == null or family_id == "":
		return
	var parent: String = _selection[0] if not _selection.is_empty() else _doc.root
	if not _doc.parts.has(parent):
		parent = _doc.root
	_placement.begin(family_id, manufacturer_id, parent, kind)
	if not _placement.active:
		set_status("CANNOT PLACE %s" % family_id)
		return
	placement_state_changed.emit(true)
	set_status("PLACING %s - CLICK TO CONFIRM, ESC TO CANCEL" % family_id)


## Arm a placement for a SAVED COMPONENT rather than a catalogue family. Same ghost, same drag,
## same commit - `kind` is the only difference, and it routes shape resolution through the
## component's definition instead of through ShapeGen.
func begin_component_placement(component_id: String) -> void:
	if _doc == null or not _doc.components.has(component_id):
		set_status("NO SUCH COMPONENT: %s" % component_id.to_upper())
		return
	begin_placement(component_id, "", ShipPart.KIND_COMPONENT_INSTANCE)


## Re-place the selected part with the identical machinery, seeded from its own attach
## record. Commits a modification rather than an addition.
func begin_move_selected() -> void:
	if _placement == null or _doc == null:
		return
	if _selection.size() != 1:
		set_status("SELECT EXACTLY ONE PART TO MOVE")
		return
	var pid: String = _selection[0]
	_placement.begin_move(pid)
	if not _placement.active:
		set_status("%s CANNOT BE MOVED" % pid)
		return
	placement_state_changed.emit(true)
	set_status("MOVING %s - CLICK TO CONFIRM, ESC TO CANCEL" % pid)


## Drop the ghost with no edit. Safe to call when nothing is being placed.
func cancel_placement() -> void:
	_leave_isolation()
	if _placement == null or not _placement.active:
		return
	_placement.cancel()


# ---------------------------------------------------------------- presentation


## ShipSceneBuilder.DisplayMode: FLAT | WIREFRAME | SHADED_WIRE | XRAY.
func set_display_mode(mode: int) -> void:
	if _view != null:
		_view.set_display_mode(mode)
	if _mode_option != null and _mode_option.selected != mode:
		_mode_option.select(mode)


## Force the palette LUT to a budget's alert palette; "" clears it. Calling this hands
## alert control to the caller (the gauges panel) and stops the builder's own cheap
## bounding-box check from fighting it.
func set_budget_alert(budget_key: String) -> void:
	_auto_alert = false
	if _ship_theme == null:
		return
	if budget_key == "":
		_ship_theme.clear_alert()
	else:
		_ship_theme.set_alert(budget_key)


func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


## In-scene message box. There is no native dialog anywhere in this app.
## Ask the player for a line of text. `cb` receives the entered String; it is NOT called if the
## dialog is cancelled, and an empty entry is the caller's to reject.
##
## Public because panels need it: MAKE COMP created a component under an auto-derived label with
## no way to name it ("also doesnt let player name it"), purely because the dialog machinery was
## private to this file.
func prompt(title: String, body: String, default_text: String, cb: Callable) -> void:
	_open_dialog(title, body, ShipModal.Mode.PROMPT, cb, PackedStringArray(), default_text)


func show_message(title: String, body: String) -> void:
	_open_dialog(title, body, ShipModal.Mode.MESSAGE, Callable(), PackedStringArray(), "")


## Every dialog in the app goes through here and then straight out to [ShipModal]. Kept as one
## private forwarder rather than pointing five call sites at `_modal_ui` so the dialog stays one
## named thing in this file.
func _open_dialog(
	title: String,
	body: String,
	mode: int,
	cb: Callable,
	items: PackedStringArray,
	default_text: String
) -> void:
	if _modal_ui != null:
		_modal_ui.open(title, body, mode, cb, items, default_text)


## Take the dialog back down without answering it. Kept as a named verb on the builder because
## `tools/ship_visual_check.gd` drives it by string to clear a refusal before the next step.
func _close_dialog() -> void:
	if _modal_ui != null:
		_modal_ui.close()


# ---------------------------------------------------------------- placement plumbing


## One ShipPlacement for the session. It is bound to the view (which renders its ghost and
## supplies the surface probe) and to doc_changed, so a document that moves underneath a
## live placement either refreshes it or cancels it - never leaves a stale ghost up.
func _build_placement() -> void:
	_placement = ShipPlacement.new()
	_placement.setup(self)
	_placement.ghost_moved.connect(_on_ghost_moved)
	_placement.ghost_validity_changed.connect(_on_ghost_validity_changed)
	_placement.placement_committed.connect(_on_placement_committed)
	_placement.placement_cancelled.connect(_on_placement_cancelled)
	doc_changed.connect(_placement.notify_doc_changed)
	if _view != null:
		_view.set_placement(_placement)


func _on_ghost_moved(yaw: float, pitch: float, rot: Vector3, offset: float) -> void:
	attach_preview_changed.emit(_placement.moving_part_id(), yaw, pitch, rot, offset)


## A refusal is never swallowed: the reason reaches the status bar the moment the
## placement becomes illegal, which is before the click, not after it.
##
## VERBATIM, with no prefix of ours. This project runs two hard gates at once (complexity
## and the physical budgets) and ShipGate's whole mitigation for that is a message that
## names the failing quantity and its cap - "COMPLEXITY 148 + 4 / 148 - REMOVE A PART OR
## BREAK SYMMETRY". Wrapping it in a generic "INVALID -" buys nothing and costs width on a
## status bar that is already only 22 px tall.
func _on_ghost_validity_changed(is_valid: bool, reason: String) -> void:
	if not is_valid and reason != "":
		set_status(reason)


func _on_placement_committed(part_id: String) -> void:
	placement_state_changed.emit(false)
	_default_link_for_placed(part_id)
	set_status("PLACED %s" % part_id)


## A tunnel placed on a module is HATCHED to it by default (ADR 0027); an existing link stays.
func _default_link_for_placed(part_id: String) -> void:
	if _doc == null or not _doc.parts.has(part_id):
		return
	var host: String = (_doc.parts[part_id] as ShipPart).parent
	if host.is_empty():
		return
	if ShipSeams.mode_for(_doc, part_id, host) != ShipSeams.MODE_WALL:
		return
	var link: String = ShipSeams.default_link_for(_doc, part_id, host)
	if link == ShipSeams.MODE_WALL:
		return
	begin_edit("default hatch")
	_set_link(part_id, host, link)
	commit_edit(PackedStringArray())


func _on_placement_cancelled() -> void:
	placement_state_changed.emit(false)
	set_status("PLACEMENT CANCELLED")


# ---------------------------------------------------------------- edit plumbing


func _commit(changed_ids: PackedStringArray, check_budget: bool) -> bool:
	if _doc == null:
		return false
	_leave_explode()
	_mark_meshes_stale()
	if check_budget and _bbox_exceeded():
		var restored: ShipDoc = _history.peek()
		if restored != null:
			_doc = restored
			_selection = _filter_selection(_selection)
		_refresh_view(true)
		_emit_state()
		show_message("BUDGET", "EDIT REFUSED - BOUNDING BOX OVER max_bbox_m.")
		return false
	# An edit made to an inner part of a component (isolation, ADR 0024) lives in a cached
	# object until it is written into the definition; every instance follows at the sync.
	var inner_edit: bool = false
	for pid: String in changed_ids:
		if ShipComponents.is_expanded_id(pid):
			_doc.store_inner(pid)
			inner_edit = true
	# The ids are what make two pushes one gesture, so a held numpad key folds into one undo
	# while two edits to different parts keep their own (ShipHistory._coalesces).
	var touched: PackedStringArray = changed_ids.duplicate()
	touched.sort()
	_history.push(_doc, _pending_label, "".join(touched))
	if changed_ids.is_empty() or inner_edit:
		_refresh_view(false)
	else:
		if _view != null:
			_view.refresh_parts(_doc, _data, _config, changed_ids)
			_view.set_selection(_selection)
		_update_alert()
	_emit_state()
	return true


## Swap the whole document in. Never budget-checked: loading and undo are exempt.
func _replace_doc(doc: ShipDoc) -> void:
	_isolated = ""
	if _view != null:
		_view.set_isolated("")
	_doc = doc
	_selection = _filter_selection(_selection)
	_drop_bake()
	_refresh_view(true)
	_mark_meshes_stale()
	_emit_state()


## Starts the new-ship flow. Does NOT create anything: it raises the start chooser and waits.
##
## RETIRED(2026-09-01): founding the document here on `_first_family()`. That made the starting
## primitive a function of key order in families.json, which is how the console "auto started with
## a block again instead of letting player choose starting choice". The document is now founded by
## [method found_document], from the player's answer.
func _new_document() -> void:
	cancel_placement()
	if _first_family() == "":
		_doc = null
		_refresh_view(true)
		_emit_state()
		set_status("NO SHAPE FAMILIES - data/shapes/families.json IS MISSING OR EMPTY")
		return
	if _start_dialog == null:
		# No chooser (a stripped host, or a build error in the panel): found on the first family
		# rather than leaving the player with an inert console.
		found_document(_first_family(), _first_manufacturer(_first_family()))
		return
	_start_dialog.open(_doc != null)
	set_status("CHOOSE A STARTING MODULE")


## Founds a brand-new one-part ship on `family_id` / `manufacturer_id`, sized to
## `ShipConfig.root_span_m`. Public so a headless tool can start a document without driving the
## chooser's buttons.
func found_document(family_id: String, manufacturer_id: String) -> void:
	if family_id == "":
		return
	var mfr: String = manufacturer_id
	if mfr == "":
		mfr = _first_manufacturer(family_id)
	var span: float = _config.root_span_m if _config != null else 0.0
	_doc = ShipDoc.create_new(family_id, mfr, _data, span)
	_history.clear()
	if _doc != null:
		_history.push(_doc, "new document")
		_selection = PackedStringArray([_doc.root]) if _doc.root != "" else PackedStringArray()
	_refresh_view(true)
	_emit_state()
	if _view != null:
		_view.frame_all()
	set_status("NEW SHIP - %s AT %s m" % [family_id, String.num(span, 1)])
	_resolve_on_load()


func _refresh_view(full: bool) -> void:
	_leave_explode()
	if _view != null:
		if full:
			_view.rebuild(_doc, _data, _config)
		else:
			_view.sync(_doc, _data, _config)
		_view.set_selection(_selection)
	_update_alert()


# ---------------------------------------------------------------- exploded view


## EXPLODE pulls every module off the module it stands on and shows each as its own bake, seam
## face, wall and door included (ShipExplodeView, ADR 0008); ASSEMBLE puts the parts back. The
## document is untouched either way, and an edit while exploded assembles first. Private on
## purpose - the button, the E key and the visual check (through call()) drive it, and the
## facade is at its public-method budget; `_exploded` is the read-back.
func _set_exploded(on: bool) -> void:
	if _view == null:
		return
	if on:
		if _doc == null:
			set_status("NOTHING TO EXPLODE")
			return
		cancel_placement()
		_connect_explode()
		_exploded = true
		_explode_opts.set_shown(true)
		set_status("EXPLODING...")
		# The exact per-part bake, carried out by the ENGINE's CSG (ShipCsgBake, ADR 0020): the
		# plan is core's, the booleans are Manifold's. A fresh bake is shown as it is; a stale or
		# missing one is made first, and _show_bake() finds _exploded set when it lands.
		if _bake_session.last.is_empty() or _bake_session.stale:
			_update_meshes()
		else:
			_show_bake()
	else:
		if not _exploded:
			return
		_exploded = false
		_explode_opts.set_shown(false)
		_view.set_exploded(false)
		# Back into the baked view when there is one - the assembled ship is the finished pieces
		# where they stand, not the preview primitives (ADR 0023).
		if not _bake_session.last.is_empty():
			_show_bake()
		set_status("ASSEMBLED")
	if _explode_button != null:
		_explode_button.text = "ASSEMBLE" if _exploded else "EXPLODE"


## LEAVE THE BAKED VIEW for the primitives, so the ship can be edited again.
##
## A LOADED SHIP HAD NO WAY BACK. A ship that arrives RESOLVES ITSELF (ADR 0028) and lands with
## `_baked = true`; a baked view routes every event to `_handle_explode_input`, which deliberately
## keeps the gizmo, the clone and the placement out because what is on screen is a set of bakes
## and not the document. The exit existed - `_set_baked(false)` - and had ZERO callers anywhere in
## `harness/`: the only references in the repo were three lines of `tools/`. So opening a saved
## ship gave you a hull you could look at and not touch, with nothing on screen saying why
## (docs/future/ux.md section 2.5, B5).
##
## The button is always live: `_set_baked(false)` returns early when nothing is baked. Lighting it
## only when it can do something belongs with the hint bar (step 11), not with the way out.
func _on_edit_pressed() -> void:
	_set_baked(false)


func _on_explode_pressed() -> void:
	_set_exploded(not _exploded)


func _on_rooms_pressed() -> void:
	_rooms_whole = not _rooms_whole
	if _rooms_button != null:
		_rooms_button.text = "ROOMS: WHOLE" if _rooms_whole else "ROOMS: PIECES"
	if _view == null:
		return
	# A whole room is an extra (ADR 0030): shown once made, by _show_bake when it lands.
	if _rooms_whole and (_baked or _exploded) and not _bake_session.has_extras():
		_show_bake()
		return
	_view.set_rooms_whole(_rooms_whole)


# ---------------------------------------------------------------- baked view and its update


## UPDATE MESHES: the engine bake of the document as it is now, shown assembled or exploded
## (ADR 0023). The session queues a request made during a bake and discards a bake of a document
## since replaced (ADR 0028); _show_bake runs when it lands.
func _update_meshes() -> void:
	if _doc == null or _view == null:
		return
	if not _bake_session.busy and _bake_hud != null:
		_bake_hud.refresh_button(false)
		_bake_hud.show_progress(0.0)
		set_status("BAKING...")
	_bake_session.request_update(_data, _config)


## Put the last bake on screen - exploded when the exploded view is up, assembled otherwise.
## THE DICING RUNS BEHIND IT (ADR 0042): pieces are drawn at once and cells cut in the background;
## when they land this runs again (it is the session's `landed`) and rebuilds with them, seamless
## because nothing moves. RETIRED: the screen WAITED, so a ship was undiced until EXPLODE.
func _show_bake() -> void:
	if _view == null or _doc == null or _bake_session.last.is_empty():
		return
	if not _bake_session.has_extras():
		_bake_session.request_extras()
	_connect_explode()
	var sdf: ShipSdf = ShipSdf.build(_doc, _data, _config)
	_view.set_rooms_whole(_rooms_whole)
	if _exploded:
		_baked = false
		_view.set_exploded(true, sdf, _selection, _bake_session.last)
	else:
		_baked = true
		_view.set_baked(true, sdf, _selection, _bake_session.last)
	_explode_opts.refresh()
	if _bake_hud != null:
		_bake_hud.refresh_button(_bake_session.stale)


## A ship that arrives RESOLVES ITSELF: one bake, the bar up, the pieces on screen (ADR 0028).
func _resolve_on_load() -> void:
	if not _resolve_on_load_enabled or _doc == null:
		return
	set_status("RESOLVING SHIP...")
	_update_meshes()


## Leave the baked view for the primitives (the visual check uses this); the bake is kept.
func _set_baked(on: bool) -> void:
	if on:
		if _bake_session.last.is_empty() or _bake_session.stale:
			_update_meshes()
		else:
			_show_bake()
		return
	if not _baked:
		return
	_baked = false
	if _view != null:
		_view.set_baked(false)
	set_status("PREVIEW")


## The document as it is now, for the bake session to tell a replaced one by (ADR 0030).
func _current_doc() -> ShipDoc:
	return _doc


## The document changed: the baked view (if up) is stale and the button lights (ADR 0024).
func _mark_meshes_stale() -> void:
	if _doc == null:
		return
	_bake_session.stale = true
	if _bake_hud != null:
		_bake_hud.refresh_button(true)


## Forget the bake: the document was swapped wholesale.
func _drop_bake() -> void:
	_bake_session.drop()
	if _baked:
		_baked = false
		if _view != null:
			_view.set_baked(false)


func _on_update_pressed() -> void:
	if _doc == null:
		set_status("NOTHING TO BAKE")
		return
	_update_meshes()


func _on_bake_progress(fraction: float, label: String) -> void:
	if _bake_hud != null:
		_bake_hud.show_progress(fraction)
	if label != "":
		set_status("BAKING: %s  %d%%" % [label, int(round(fraction * 100.0))])


## Any path that changes what is on screen assembles first: the exploded modules were baked
## from the document as it was, and would silently go stale.
func _leave_explode() -> void:
	if _exploded:
		_set_exploded(false)


func _connect_explode() -> void:
	var explode: ShipExplodeView = _view.get_explode_view()
	if explode == null or explode.progress.is_connected(_on_explode_progress):
		return
	explode.progress.connect(_on_explode_progress)
	explode.finished.connect(_on_explode_finished)


func _on_explode_progress(done: int, total: int) -> void:
	if _exploded:
		set_status("EXPLODING %d / %d MODULES" % [done, total])
	elif _baked:
		set_status("PLACING %d / %d MODULES" % [done, total])
	if total > 0 and _bake_hud != null:
		_bake_hud.show_progress(0.9 + 0.1 * float(done) / float(total))


func _on_explode_finished(modules: int, seams: int, ms: int) -> void:
	if _bake_hud != null:
		_bake_hud.hide_progress()
	if _baked and not _exploded:
		set_status("MESHES UPDATED: %d MODULES, %d SEAMS  (%d ms)" % [modules, seams, ms])
		return
	if _exploded:
		set_status(
			(
				"EXPLODED %d MODULES, %d SEAMS  (%d ms)   E OR ASSEMBLE TO RETURN"
				% [modules, seams, ms]
			)
		)


func _emit_state() -> void:
	doc_changed.emit(_doc)
	selection_changed.emit(_selection)
	history_changed.emit(_history.can_undo(), _history.can_redo())
	if _undo_button != null:
		_undo_button.disabled = not _history.can_undo()
	if _redo_button != null:
		_redo_button.disabled = not _history.can_redo()


func _filter_selection(ids: PackedStringArray) -> PackedStringArray:
	if _doc == null:
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	for pid: String in ids:
		if _doc.parts.has(pid):
			out.append(pid)
		elif not _isolated.is_empty() and ShipComponents.instance_of(pid) == _isolated:
			# An inner part of the component open in isolation is selectable (ADR 0024).
			if ShipComponents.inner_exists(_doc, pid):
				out.append(pid)
	return out


## Cheap per-axis bounding box check (SPEC section 8: max_bbox_m is per-axis, not a
## diagonal). This is the only budget the shell enforces itself - volume, weight and cost
## need a sampling grid and belong to the metrics/gauges lane.
func _bbox_exceeded() -> bool:
	if _doc == null or _data == null or _config == null:
		return false
	var box: AABB = ShipMetrics.compute_bbox(_doc, _data, _config)
	var s: Vector3 = box.size
	var cap: Vector3 = _config.max_bbox_m
	return s.x > cap.x or s.y > cap.y or s.z > cap.z


func _update_alert() -> void:
	if _ship_theme == null or not _auto_alert:
		return
	if _bbox_exceeded():
		_ship_theme.set_alert("bbox")
	else:
		_ship_theme.clear_alert()


func _first_family() -> String:
	if _data == null:
		return ""
	var ids: PackedStringArray = _data.family_ids()
	return ids[0] if not ids.is_empty() else ""


func _first_manufacturer(family_id: String) -> String:
	if _data == null:
		return ""
	var ids: PackedStringArray = _data.manufacturers_for(family_id)
	return ids[0] if not ids.is_empty() else ""


# ---------------------------------------------------------------- layout


func _build_layout() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	add_child(root)

	root.add_child(_build_header())

	var body: HBoxContainer = HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 2)
	root.add_child(body)

	var left: VBoxContainer = VBoxContainer.new()
	left.name = "LeftColumn"
	left.custom_minimum_size = Vector2(ShipTheme.pxf(float(LEFT_WIDTH)), 0.0)
	left.add_theme_constant_override("separation", 2)
	body.add_child(left)
	left.add_child(_make_slot_panel("PART PALETTE", "PartPaletteSlot"))
	left.add_child(_make_slot_panel("TREE", "TreeSlot"))

	var view_frame: PanelContainer = PanelContainer.new()
	view_frame.name = "ViewPanel"
	view_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(view_frame)
	_view = ShipView3D.new()
	_view.name = "ShipView3D"
	_view.part_picked.connect(_on_part_picked)
	_view.part_double_clicked.connect(_on_part_double_clicked)
	_view.pick_cleared.connect(_on_pick_cleared)
	_view.seam_menu_requested.connect(_on_seam_menu_requested)
	view_frame.add_child(_view)
	# THE LAYERS EXPLORER, top left of the view - what the builder draws, never what it holds.
	# AFTER the view, or it is invisible: the SubViewport is opaque and siblings draw in tree
	# order, so built first it was covered by the 3D view for its whole life. ShipExplodeControl
	# is built after _build_layout() for the same reason, and visibly works.
	_layers = ShipLayersControl.new(view_frame, _ship_theme)

	var right: VBoxContainer = VBoxContainer.new()
	right.name = "RightColumn"
	right.custom_minimum_size = Vector2(ShipTheme.pxf(float(RIGHT_WIDTH)), 0.0)
	body.add_child(right)
	right.add_child(_make_slot_panel("INSPECTOR", "InspectorSlot"))

	var gauges: PanelContainer = _make_slot_panel("BUDGETS", "GaugeSlot")
	gauges.custom_minimum_size = Vector2(0.0, ShipTheme.pxf(float(GAUGE_HEIGHT)))
	gauges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(gauges)

	var status_frame: PanelContainer = PanelContainer.new()
	status_frame.name = "StatusBar"
	status_frame.custom_minimum_size = Vector2(0.0, ShipTheme.pxf(float(STATUS_HEIGHT)))
	root.add_child(status_frame)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_status_label.text = "READY"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.add_child(_status_label)
	# The bake's bar: the engine takes seconds, and a bar that moves says the builder is not
	# frozen. Hidden between bakes.
	_progress = ProgressBar.new()
	_progress.name = "BakeProgress"
	# Measured 1 px tall in the row without these: a ProgressBar does not fill its box on its own.
	_progress.custom_minimum_size = Vector2(ShipTheme.pxf(240.0), ShipTheme.pxf(10.0))
	_progress.size_flags_vertical = Control.SIZE_FILL
	_progress.show_percentage = false
	_progress.visible = false
	status_row.add_child(_progress)
	_bake_hud = ShipBakeHud.new(_update_button, _progress, _ship_theme)
	_bake_hud.style_bar()
	status_frame.add_child(status_row)

	part_palette_slot = _slots.get("PartPaletteSlot", null)
	tree_slot = _slots.get("TreeSlot", null)
	inspector_slot = _slots.get("InspectorSlot", null)
	gauge_slot = _slots.get("GaugeSlot", null)
	_register_unique_names()


func _build_header() -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.name = "Header"
	frame.custom_minimum_size = Vector2(0.0, ShipTheme.pxf(float(HEADER_HEIGHT)))

	var bar: HBoxContainer = HBoxContainer.new()
	frame.add_child(bar)

	var title: Label = Label.new()
	title.text = "MHZ SHIP BUILDER"
	title.add_theme_font_size_override("font_size", ShipTheme.font_title())
	bar.add_child(title)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# THE RUNG PICKER FIRST, before the verbs it governs. The author asked for the views and then
	# for the current UI to survive as one of them, which is what DEV is.
	_ui_mode = ShipUiMode.new(bar, _ship_theme)
	bar.add_child(VSeparator.new())

	bar.add_child(_make_button("NEW", _on_new_pressed))
	bar.add_child(_make_button("OPEN", _on_open_pressed))
	bar.add_child(_make_button("SAVE", _on_save_pressed))
	bar.add_child(VSeparator.new())
	_undo_button = _make_button("UNDO", undo)
	bar.add_child(_undo_button)
	_redo_button = _make_button("REDO", redo)
	bar.add_child(_redo_button)
	bar.add_child(VSeparator.new())

	_mode_option = OptionButton.new()
	_mode_option.name = "RenderTypeOption"
	_mode_option.add_item("FLAT", ShipSceneBuilder.DisplayMode.FLAT)
	_mode_option.add_item("WIRE", ShipSceneBuilder.DisplayMode.WIREFRAME)
	_mode_option.add_item("SHADED+WIRE", ShipSceneBuilder.DisplayMode.SHADED_WIRE)
	_mode_option.add_item("X-RAY", ShipSceneBuilder.DisplayMode.XRAY)
	_mode_option.add_item("FRESNEL", ShipSceneBuilder.DisplayMode.FRESNEL)
	_mode_option.add_item("INTERIOR", ShipSceneBuilder.DisplayMode.INSIDE)
	# Must match ShipSceneBuilder._mode, or the toolbar label lies about what is on screen.
	_mode_option.select(ShipSceneBuilder.DisplayMode.SHADED_WIRE)
	_mode_option.item_selected.connect(_on_mode_selected)
	bar.add_child(_mode_option)

	# DITHER and WALLS live in ShipViewToggles: both only forward to the theme or the view, so
	# they are a seam rather than a split, and the next such toggle costs this file nothing.
	_view_toggles = ShipViewToggles.new(bar, _ship_theme)

	bar.add_child(_make_button("HELP", _on_help_pressed))
	bar.add_child(_make_button("FRAME", _on_frame_pressed))
	_explode_button = _make_button("EXPLODE", _on_explode_pressed)
	bar.add_child(_explode_button)
	_edit_button = _make_button("EDIT", _on_edit_pressed)
	_edit_button.tooltip_text = "LEAVE THE BAKED MESHES AND GO BACK TO EDITING THE SHIP"
	bar.add_child(_edit_button)
	_rooms_button = _make_button("ROOMS: PIECES", _on_rooms_pressed)
	_rooms_button.tooltip_text = "EXPLODE A ROOM INTO ITS PIECES, OR KEEP IT WHOLE"
	bar.add_child(_rooms_button)
	_update_button = _make_button("UPDATE MESHES", _on_update_pressed)
	_update_button.tooltip_text = "BAKE THE EXACT MESHES OF THE DOCUMENT AS IT IS NOW"
	bar.add_child(_update_button)
	# The status row (and its bar) is built before this toolbar: the HUD is remade here with both.
	_bake_hud = ShipBakeHud.new(_update_button, _progress, _ship_theme)
	_bake_hud.style_bar()
	bar.add_child(_make_button("BAKE", _on_bake_pressed))
	return frame


## NAMED FROM ITS LABEL, so [ShipUiMode] can address a button without matching on display text -
## EXPLODE reads ASSEMBLE once the view is exploded and ROOMS: PIECES reads ROOMS: WHOLE, while a
## node name set at build time never moves.
func _make_button(label: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.name = label
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b


## A titled frame whose body is an EMPTY named VBoxContainer registered in _slots.
func _make_slot_panel(title: String, slot_name: String) -> PanelContainer:
	var frame: PanelContainer = PanelContainer.new()
	frame.name = slot_name + "Frame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box: VBoxContainer = VBoxContainer.new()
	frame.add_child(box)

	var label: Label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	box.add_child(label)
	box.add_child(HSeparator.new())

	var slot: VBoxContainer = VBoxContainer.new()
	slot.name = slot_name
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(slot)

	_slots[slot_name] = slot
	return frame


## Make the slots reachable as %PartPaletteSlot and friends. A unique name resolves
## through the OWNER of the node doing the lookup, so this works for anything owned by
## this scene - a panel instantiated from its own .tscn should use get_slot() or the
## typed properties instead.
func _register_unique_names() -> void:
	for key: Variant in _slots.keys():
		var slot: Control = _slots[key]
		if slot == null:
			continue
		slot.owner = self
		slot.unique_name_in_owner = true


func _mount_panels() -> void:
	for key: Variant in PANEL_CANDIDATES.keys():
		var slot_name: String = str(key)
		var slot: Control = _slots.get(slot_name, null)
		if slot == null:
			continue
		if not _try_mount(slot, PANEL_CANDIDATES[key]):
			_add_placeholder(slot, slot_name)


func _try_mount(slot: Control, paths: Array) -> bool:
	for entry: Variant in paths:
		var path: String = str(entry)
		if not ResourceLoader.exists(path):
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			continue
		slot.add_child(inst)
		if inst.has_method("setup"):
			inst.call("setup", self)
		# A mounted PaintPanel is useless until the 3D view knows where to send clicks. Bound
		# here rather than in _mount_panels() so it happens the moment the panel exists,
		# whichever candidate path it came from.
		if inst.has_method("paint_mode") and _view != null:
			_view.set_paint_mode(inst.call("paint_mode"))
		return true
	return false


func _add_placeholder(slot: Control, slot_name: String) -> void:
	var label: Label = Label.new()
	label.text = "[ %s ]" % slot_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	if _ship_theme != null:
		label.add_theme_color_override("font_color", _ship_theme.color_for_role("text_dim"))
	slot.add_child(label)


# ---------------------------------------------------------------- post process


func _build_post_process() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "PalettePost"
	layer.layer = POST_LAYER
	add_child(layer)

	_post_rect = ColorRect.new()
	_post_rect.name = "PaletteQuantizer"
	_post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never eat input: this rect covers the entire app viewport.
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_post_rect)

	# load(), not preload(): a preload of a shader that fails to compile is a hard parse
	# error, and AGENTS section 7.5 warns that a shader failure during _ready kills the
	# scene silently. A runtime load can be checked and degraded instead.
	var shader: Shader = null
	if ResourceLoader.exists(POST_SHADER_PATH):
		shader = load(POST_SHADER_PATH)
	if shader == null:
		_post_rect.visible = false
		push_warning("palette_post.gdshader missing - running without palette quantization")
		return
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	_post_rect.material = mat
	_ship_theme.bind_post_material(mat)


func _on_palette_changed(_palette: PackedColorArray) -> void:
	if _view != null:
		_view.on_palette_changed()
	if _modal_ui != null:
		_modal_ui.refresh_theme()


# ---------------------------------------------------------------- dialogs


## Founds a ship from a stock template - rooms joined by tunnels with a hatch at every
## connection. `options` is passed to ShipTemplates.build() verbatim; anything it omits falls back
## to the tuning levers.
func found_from_template(template_id: String, options: Dictionary) -> void:
	var doc: ShipDoc = ShipTemplates.build(_data, _config, template_id, options)
	if doc == null:
		set_status("TEMPLATE '%s' COULD NOT BE BUILT" % template_id)
		return
	_doc = doc
	_history.clear()
	_history.push(_doc, "new document")
	_selection = PackedStringArray([_doc.root]) if _doc.root != "" else PackedStringArray()
	_refresh_view(true)
	_emit_state()
	if _view != null:
		_view.frame_all()
	set_status(
		(
			"NEW SHIP - %s (%d PARTS, %d HATCHES)"
			% [ShipTemplates.label_of(_data, template_id), _doc.parts.size(), _doc.joints.size()]
		)
	)
	_resolve_on_load()


## The start chooser, layered over everything. Built after the dialog modal so a message raised
## from inside the start flow still lands on top of it.
func _build_start_dialog() -> void:
	_start_dialog = ShipStartDialog.new()
	add_child(_start_dialog)
	_start_dialog.setup(self)
	_start_dialog.chosen.connect(_on_start_chosen)
	_start_dialog.template_chosen.connect(_on_start_template_chosen)
	_start_dialog.cancelled.connect(_on_start_cancelled)


func _on_start_chosen(family_id: String, manufacturer_id: String) -> void:
	found_document(family_id, manufacturer_id)


func _on_start_template_chosen(template_id: String, options: Dictionary) -> void:
	found_from_template(template_id, options)


## The tutorial layer. Built AFTER the start chooser so a step card cannot land on top of the
## chooser it is telling the player to answer, and it opens straight away: step 1 is "found the
## hull", which is exactly what the chooser is waiting for.
func _build_tutorial() -> void:
	_tutorial = ShipTutorial.new()
	add_child(_tutorial)
	_tutorial.setup(self)
	_tutorial.open()


## HELP re-opens the tutorial at the first step the ship does not already satisfy, so a player who
## skipped it and got stuck is not walked back through what they have already built.
func _on_help_pressed() -> void:
	if _tutorial == null:
		return
	if _tutorial.is_open():
		_tutorial.close()
		return
	_tutorial.open()


func _on_start_cancelled() -> void:
	set_status("KEPT THE CURRENT SHIP")


# ---------------------------------------------------------------- toolbar


func _on_part_picked(part_id: String, additive: bool) -> void:
	select_part(part_id, additive)
	var resolved: String = ShipSymmetry.source_of_twin(part_id)
	if resolved != part_id:
		set_status("SELECTED %s (VIA ITS MIRRORED TWIN)" % resolved)
		return
	set_status("SELECTED %s" % resolved)


## SketchUp's double-click (ADR 0024): on a component instance, open it - the rest of the ship
## washes out and its inner parts pick one by one; on empty space, or on anything that is not
## part of the open component, close it.
func _on_part_double_clicked(part_id: String) -> void:
	var resolved: String = ShipSymmetry.source_of_twin(part_id)
	var part: ShipPart = _doc.parts.get(resolved, null) if _doc != null else null
	if part != null and part.kind == ShipPart.KIND_COMPONENT_INSTANCE and resolved != _isolated:
		_isolate(resolved)
		return
	if _isolated.is_empty():
		return
	if part_id.is_empty() or ShipComponents.instance_of(resolved) != _isolated:
		_leave_isolation()


func _isolate(instance_id: String) -> void:
	if _doc == null or not _doc.parts.has(instance_id):
		return
	_isolated = instance_id
	set_selection(PackedStringArray())
	if _view != null:
		_view.set_isolated(instance_id)
	set_status("EDITING COMPONENT %s - ESC TO CLOSE" % instance_id.to_upper())


func _leave_isolation() -> void:
	if _isolated.is_empty():
		return
	var was: String = _isolated
	_isolated = ""
	_selection = _filter_selection(_selection)
	if _view != null:
		_view.set_isolated("")
		_view.set_selection(_selection)
	selection_changed.emit(_selection)
	set_status("CLOSED COMPONENT %s" % was.to_upper())


func _on_pick_cleared() -> void:
	set_selection(PackedStringArray())


func _on_mode_selected(index: int) -> void:
	if _view != null:
		_view.set_display_mode(index)


func _on_frame_pressed() -> void:
	if _view != null:
		_view.frame_all()


func _on_new_pressed() -> void:
	_open_dialog(
		"NEW SHIP",
		"DISCARD THE CURRENT SHIP AND START OVER?",
		ShipModal.Mode.CONFIRM,
		_on_new_confirmed,
		PackedStringArray(),
		""
	)


func _on_new_confirmed(_payload: String) -> void:
	_new_document()


## SAVE opens the real SaveDialog - name (MANDATORY), description, tags, and the
## `min_parts_to_save` gate (API_CONTRACT_SPORE section 9).
##
## RETIRED(2026-08-31): the generic PROMPT dialog this used to open. `harness/panels/
## save_dialog.gd` existed, was complete, and was never called from anywhere, so SAVE asked for a
## bare file name and silently skipped the description, the tags and the minimum-parts refusal
## that the contract requires. If the scene is missing the prompt is still the fallback, because
## refusing to save at all would be worse than saving with less metadata.
func _on_save_pressed() -> void:
	if _doc == null:
		set_status("NOTHING TO SAVE")
		return
	var dialog: SaveDialog = SaveDialog.open_for(self)
	if dialog != null:
		return
	set_status("SAVE PANEL UNAVAILABLE - USING THE BASIC PROMPT")
	_open_dialog(
		"SAVE SHIP", "FILE NAME", ShipModal.Mode.PROMPT, _save_named, PackedStringArray(), "ship"
	)


func _save_named(file_name: String) -> void:
	var clean: String = file_name.strip_edges()
	if clean == "" or _doc == null:
		return
	DirAccess.make_dir_recursive_absolute(SHIP_DIR)
	var path: String = "%s/%s.json" % [SHIP_DIR, clean]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		set_status("SAVE FAILED - %s" % path)
		return
	f.store_string(JSON.stringify(_doc.to_dict(), "  "))
	f.close()
	set_status("SAVED %s" % path)


func _on_open_pressed() -> void:
	var items: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(SHIP_DIR)
	if dir != null:
		for entry: String in dir.get_files():
			if entry.ends_with(".json"):
				items.append(entry.get_basename())
	if items.is_empty():
		show_message("OPEN SHIP", "NO SAVED SHIPS IN %s" % SHIP_DIR)
		return
	_open_dialog("OPEN SHIP", "PICK A FILE", ShipModal.Mode.LIST, _open_named, items, "")


## Loading is budget-exempt (SPEC section 8). An over-budget ship opens as a visible
## violation, never as a refusal - otherwise lowering a lever makes yesterday's ships
## unopenable.
## IMPORT COMPONENTS (ADR 0024/0025): every component of another ship - an atomic class of the
## fleet, or a saved file - and the ship itself as one, into this document's palette. The
## palette's button asks for it; ShipComponentImport knows the sources.
func _on_import_pressed() -> void:
	if _doc == null:
		set_status("NOTHING TO IMPORT INTO")
		return
	var items: PackedStringArray = ShipComponentImport.sources(_data, SHIP_DIR)
	if items.is_empty():
		show_message("IMPORT COMPONENTS", "NO SHIPS TO IMPORT FROM")
		return
	_open_dialog(
		"IMPORT COMPONENTS",
		"PICK A CLASS OR A SAVED SHIP",
		ShipModal.Mode.LIST,
		_import_named,
		items,
		""
	)


func _import_named(name: String) -> void:
	var other: ShipDoc = ShipComponentImport.source_doc(name, _doc, _data, _config, SHIP_DIR)
	if other == null:
		show_message("IMPORT FAILED", "%s IS NOT A SHIP." % name.to_upper())
		return
	begin_edit("import components")
	var label: String = ShipComponentImport.label_of(name)
	var added: PackedStringArray = ShipComponents.import_from(_doc, other, label)
	commit_edit(PackedStringArray())
	set_status("IMPORTED %d COMPONENTS FROM %s" % [added.size(), label])


func _open_named(file_name: String) -> void:
	var path: String = "%s/%s.json" % [SHIP_DIR, file_name]
	if not FileAccess.file_exists(path):
		set_status("MISSING %s" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		show_message("OPEN FAILED", "%s IS NOT VALID JSON." % path)
		return
	var doc: ShipDoc = ShipDoc.from_dict(parsed)
	if doc == null:
		show_message("OPEN FAILED", "%s IS NOT A SHIP DOCUMENT." % path)
		return
	cancel_placement()
	_selection = PackedStringArray()
	_history.clear()
	_history.push(doc, "open")
	_replace_doc(doc)
	if _view != null:
		_view.frame_all()
	set_status("OPENED %s" % path)
	_resolve_on_load()


## Synchronous on purpose for the shell: chunked, threaded baking with progress is M6.
## Phase 1 ships are small enough that this is a pause, not a hang.
func _on_bake_pressed() -> void:
	if _doc == null:
		set_status("NOTHING TO BAKE")
		return
	set_status("BAKING...")
	var sdf: ShipSdf = ShipSdf.build(_doc, _data, _config)
	var report: Dictionary = HullBake.bake(sdf, _config, 0.0)
	var body: String = (
		(
			"TRIS %d   VERTS %d\nOUTER AREA %.3f m2\nOUTER VOLUME %.3f m3\n"
			+ "INTERIOR VOLUME %.3f m3  (%d TRIS)\nSHELL VOLUME %.3f m3 AT %.2f m THICK\n"
			+ "SHELL MASS %.1f kg\n%s\nCELLS %d   TIME %d ms"
		)
		% [
			int(report.get("tris", 0)),
			int(report.get("verts", 0)),
			float(report.get("area_m2", 0.0)),
			float(report.get("volume_m3", 0.0)),
			float(report.get("interior_volume_m3", 0.0)),
			int(report.get("interior_tris", 0)),
			float(report.get("shell_volume_m3", 0.0)),
			_config.hull_thickness_m,
			float(report.get("shell_mass_kg", 0.0)),
			_seam_summary(sdf),
			int(report.get("cells", 0)),
			int(report.get("ms", 0)),
		]
	)
	show_message("BAKE REPORT", body)
	set_status("BAKE COMPLETE")


# ---------------------------------------------------------------- seam styles (ADR 0009)


func _build_context_menu() -> void:
	_context_menu = ShipContextMenu.new()
	_context_menu.name = "ContextMenu"
	_context_menu.setup(_ship_theme)
	_context_menu.chosen.connect(_on_seam_style_chosen)
	add_child(_context_menu)


## Right-clicking a selection offers the seam styles for every connection INSIDE it.
##
## ANY NUMBER OF PARTS, not two: "add ability to select as many modules as desired, right click and
## change the connection surfaces for all at same time even if they differed before." A connection
## counts when BOTH of its ends are selected, which is the reading that generalises the old
## two-part behaviour exactly - select a pair and you get their one seam, select a chain and you
## get every seam along it, and a part selected on its own has no connection to anything else in
## the selection and so offers nothing.
##
## Where the chosen ones do not already agree, nothing is marked as current, because none of them
## is.
func _on_seam_menu_requested(position: Vector2) -> void:
	if _doc == null or _context_menu == null or _exploded:
		return
	var chosen: Dictionary = {}
	for raw: String in _selection:
		var pid: String = ShipSymmetry.source_of_twin(raw)
		if _doc.parts.has(pid):
			chosen[pid] = true
	# Inner parts of a component included (ADR 0025): pairs_within knows what hangs off what.
	_seam_pairs = ShipSeams.pairs_within(_doc, PackedStringArray(chosen.keys()))
	if _seam_pairs.is_empty():
		if chosen.size() > 1:
			set_status("NONE OF THOSE PARTS ARE CONNECTED TO EACH OTHER")
		return

	var items: Array[Dictionary] = []
	for item: Dictionary in SEAM_STYLE_ITEMS:
		items.append(item)
	# The position arrives in the 3D VIEW's coordinates and the menu lives under this Control:
	# carry it across, or a menu opened at the pointer lands wherever the two frames differ by.
	var offset: Vector2 = (
		_view.get_global_transform_with_canvas().origin - get_global_transform_with_canvas().origin
	)
	var title: String = (
		"SEAM: %s <-> %s"
		% [_part_label(_seam_pairs[0][0]).to_upper(), _part_label(_seam_pairs[0][1]).to_upper()]
	)
	if _seam_pairs.size() > 1:
		title = "%d SEAMS" % _seam_pairs.size()
	_context_menu.open(position + offset, title, items, _common_seam_style())


## The style every chosen connection already carries, or "" when they differ - which is what the
## menu shows as "no current choice" rather than picking one of them to look current.
func _common_seam_style() -> String:
	var common: String = ""
	for pair: PackedStringArray in _seam_pairs:
		var style: String = _seam_style_of(pair[0], pair[1])
		if common.is_empty():
			common = style
		elif common != style:
			return ""
	return common


func _seam_style_of(a: String, b: String) -> String:
	return ShipSeams.style_for(_doc, a, b)


## Applies one style to every connection the menu was opened over, as a SINGLE edit - so a
## selection of a dozen seams is one undo, not a dozen.
func _on_seam_style_chosen(style: String) -> void:
	if _doc == null or _seam_pairs.is_empty():
		return
	var live: Array[PackedStringArray] = []
	for pair: PackedStringArray in _seam_pairs:
		if _is_part_alive(pair[0]) and _is_part_alive(pair[1]):
			live.append(pair)
	if live.is_empty():
		set_status("THOSE PARTS ARE GONE")
		return
	if live.size() == 1 and _seam_style_of(live[0][0], live[0][1]) == style:
		set_status("SEAM ALREADY %s" % _seam_style_label(style))
		return

	begin_edit("seam style")
	var changed: int = 0
	for pair: PackedStringArray in live:
		if _apply_seam_style(pair[0], pair[1], style):
			changed += 1
	commit_edit(PackedStringArray())
	if live.size() == 1:
		set_status(
			(
				"SEAM %s <-> %s: %s"
				% [
					_part_label(live[0][0]).to_upper(),
					_part_label(live[0][1]).to_upper(),
					_seam_style_label(style)
				]
			)
		)
	else:
		set_status("%d OF %d SEAMS -> %s" % [changed, live.size(), _seam_style_label(style)])


## Sets one connection's style, creating the joint record if the pair never had one. Returns
## whether anything actually moved.
func _apply_seam_style(a: String, b: String, style: String) -> bool:
	if _seam_style_of(a, b) == style:
		return false
	# Two chunks of one component: the style lives in the definition's joint (ADR 0025).
	if ShipSeams.within_one_instance(_doc, a, b):
		var inner: ShipJoint = ShipComponents.inner_joint_for(_doc, a, b)
		if inner == null:
			inner = ShipJoint.new()
			inner.mode = ShipJoint.MODE_SEALED
		inner.seam_style = style
		return ShipComponents.set_inner_joint(_doc, a, b, inner)
	var existing: String = _joint_id_for(a, b)
	var joint: ShipJoint = null
	if existing.is_empty():
		# A style needs a record to live on. A pair with no joint is a WALL, so the record this
		# creates says exactly what was already true and changes only the seam's SHAPE.
		joint = ShipJoint.new()
		joint.id = _doc.new_joint_id()
		joint.a = a if a <= b else b
		joint.b = b if a <= b else a
		joint.mode = ShipJoint.MODE_SEALED
		_doc.joints[joint.id] = joint
	else:
		joint = _doc.joints[existing]
	joint.seam_style = style
	return true


## The menu label for a style, qualified by the group it sits under.
##
## SEAM_STYLE_ITEMS carries heading rows as well as choices (ADR 0013), and a heading has no id -
## reading one cost a runtime error the PASSED banner said nothing about, which is exactly the
## case AGENTS section 8a exists for.
static func _seam_style_label(style: String) -> String:
	var group: String = ""
	for item: Dictionary in SEAM_STYLE_ITEMS:
		if item.has("header"):
			group = str(item["header"])
			continue
		if str(item.get("id", "")) == style:
			var label: String = str(item.get("label", style))
			return label if group.is_empty() else "%s - %s" % [group, label]
	return style.to_upper()


## A part's display name, or its id when it has none.
## A document part or an inner part of a component (ADR 0024).
func _is_part_alive(pid: String) -> bool:
	return _doc.parts.has(pid) or ShipComponents.inner_exists(_doc, pid)


func _part_label(pid: String) -> String:
	var part: ShipPart = _doc.part_at(pid)
	if part == null:
		return pid
	return part.display_name if not part.display_name.is_empty() else pid


## One line of the bake report: how many seams the field laid and how each is closed.
func _seam_summary(sdf: ShipSdf) -> String:
	var counts: Dictionary = {}
	for mode: String in LINK_CYCLE:
		counts[mode] = 0
	for seam: Dictionary in sdf.seams():
		var mode: String = seam[ShipSeams.SEAM_MODE]
		counts[mode] = int(counts.get(mode, 0)) + 1
	return (
		"SEAMS %d  (%d WALL, %d DOORWAY, %d HATCH, %d OPEN)"
		% [
			sdf.seam_count(),
			int(counts[ShipSeams.MODE_WALL]),
			int(counts[ShipSeams.MODE_DOORWAY]),
			int(counts[ShipSeams.MODE_HATCHED]),
			int(counts[ShipSeams.MODE_OPEN]),
		]
	)


# ---------------------------------------------------------------- keyboard


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# A dialog owns the keyboard while it is up - no hotkey may fire behind it - and until
	# 2026-09-27 that was the whole story, so every dialog had to be finished with the mouse.
	if _modal_ui != null and _modal_ui.is_open():
		if _modal_ui.handle_key(key):
			get_viewport().set_input_as_handled()
		return
	if _handle_hotkey(key):
		get_viewport().set_input_as_handled()


## Split in two only to stay under the lint's return-count cap; the dispatch order is the
## original one, edit keys before view keys.
func _handle_hotkey(key: InputEventKey) -> bool:
	return _handle_edit_hotkey(key) or _handle_view_hotkey(key)


func _handle_edit_hotkey(key: InputEventKey) -> bool:
	if key.ctrl_pressed and key.keycode == KEY_Z:
		if key.shift_pressed:
			redo()
		else:
			undo()
		return true
	if key.ctrl_pressed and key.keycode == KEY_Y:
		redo()
		return true
	if key.keycode == KEY_ESCAPE:
		# Escape backs out one level: the ghost first, the selection only when there is no
		# ghost to drop.
		if _placement != null and _placement.active:
			cancel_placement()
		else:
			set_selection(PackedStringArray())
		return true
	if key.keycode == KEY_G:
		begin_move_selected()
		return true
	if key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
		# Both keys, per SPORE_CLONE_SPEC section 2's input table.
		delete_selected()
		return true
	return false


func _handle_view_hotkey(key: InputEventKey) -> bool:
	# THE DEVELOPER NOTE (SHIFT+F), and the whole of its footprint in this file. Tested before
	# plain F so that FRAME keeps the key it has had all along. Delete these three lines and
	# `ship_dev_feedback.gd` and the feature is gone without a trace.
	if ShipDevFeedback.opens(key):
		ShipDevFeedback.open(self, _bake_session)
		return true
	if key.keycode == KEY_F and _view != null:
		_view.frame_all()
		return true
	if key.keycode == KEY_E:
		_set_exploded(not _exploded)
		return true
	# RETIRED(2026-08-31): 1/2/3/4 -> front/side/top axis-snap views, removed as un-Spore-like
	# inventions; no Spore editor has them (SPORE_CLONE_SPEC section 2). OrbitCamera's
	# set_view_preset() and ShipView3D's forwarder are gone with this binding.
	return false
