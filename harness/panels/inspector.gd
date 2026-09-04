## InspectorPanel - the numeric surface. Four attach fields, three scale fields, the snap
## selector, the per-family shape parameters, the snap-target readout and the symmetry
## readout.
##
## THE SNAP-TARGET READOUT, AND WHY IT DISABLES TWO FIELDS
## ------------------------------------------------------
## Spore does not place a part at the raw cursor. A drop is pulled to a TYPED target - the
## parent's centre, an authored snap vector, or the editor centreline (SPORE_CLONE_SPEC
## section 3 step 4) - and we derive the equivalent set from each family's own SDF
## (`SnapTargets`). When a part carries a non-empty `ShipPart.snap_id` it is standing on one
## of those targets, and API_CONTRACT_SPORE section 2 is explicit about what that costs:
## "Attach angles are then DERIVED from the target, not authored, and yaw/pitch are ignored
## on load."
##
## An editable field whose value is discarded on the next load is a lie, so YAW and PITCH go
## read-only for a snapped part and the SNAP section says where their numbers come from.
## The three ROT fields and OFFSET stay editable - they are the player's own orientation in
## the mount frame and the standoff along its normal, and nothing derives those.
##
## ROT X / ROT Y / ROT Z ARE THE MOUNT FRAME'S AXES, NOT THE SHIP'S (ADR 0004). The frame's
## +Z IS the parent's surface normal at the anchor, so ROT Z spins the part on the surface
## like a dial and ROT X / ROT Y tilt it off that surface. The unit label says DEG; the axis
## labels say which axis, and the Z field's tooltip says it is the normal, because a player
## typing into three boxes has no other way to find out.
##
## The numbers come from `ShipAttach.angles_for_target()` - the SAME call `ShipPlacement`
## makes when it stores them on the part - so the readout cannot drift from what was written.
## The target itself is fetched with `ShipAttach.snap_target()`. Both are deliberate: this
## panel derives NOTHING about attachment on its own, because a second implementation of the
## attach model is a second answer to a question that must have exactly one.
##
## SYMMETRY IS A READOUT HERE, NOT A COMMAND. RETIRED(2026-08-31): the MIRROR X / Y / Z /
## UNLINK row -> `PartTreePanel`'s BREAK SYMMETRY toggle. Those buttons drove `ShipMirror`,
## whose `mirror_source` / `mirror_plane` fields API_CONTRACT_SPORE section 2 retires
## outright ("Do not write them"). The replacement command is deliberately NOT duplicated
## into this panel: breaking symmetry cascades to a whole subtree, and one destructive
## command living in two places is one place too many. This panel says what the state IS and
## what it costs; the tree is where it changes.
##
## TWO-WAY BINDING, AND THE THREE THINGS THAT BREAK IT
## ---------------------------------------------------
## The four attach numbers have two authors: the mouse (ShipPlacement.update_from_ray) and
## this panel (ShipPlacement.set_values). Both write the same four floats and both emit
## ghost_moved, so the naive wiring oscillates. Three independent defences, because any one
## of them alone leaves a hole:
##
##   1. STRUCTURAL - NumericField.set_value() never emits. A model-to-view write therefore
##      cannot become a view-to-model write, whatever the call order is.
##   2. RE-ENTRANCY FLAG - `_binding` is raised around every crossing in either direction, so
##      the synchronous echo (set_values -> ghost_moved -> _write_attach_fields) is dropped at
##      the boundary. A flag, not a disconnect: disconnecting also drops the events that
##      arrive from the OTHER author while the wire is down, which is the bug this replaces.
##   3. FOCUS - NumericField refuses to restyle the text of a field that currently has focus
##      and an uncommitted edit, and refuses to restyle mid-scrub. This is the failure the
##      user actually feels: type "4" into YAW, the ghost re-emits, and the field is stamped
##      back to "0.000" before the "5" lands. The model value is still taken, so abandoning
##      the edit with Escape lands on the CURRENT number rather than a stale one.
##
## WITH NO PLACEMENT ACTIVE the same four fields edit the SELECTED part's attach numbers
## straight through the edit protocol, because an inspector that goes inert the moment the
## ghost is committed is not an inspector. Snapping is applied by the field itself (its
## `step` is the snap increment) so what is stored is exactly what is displayed, SPEC
## section 6.
##
## REFUSAL IS NEVER SILENT. commit_edit() returns nothing but can roll the document back;
## ShipBuilder does that by REPLACING the document with a fresh one rebuilt from the history
## head, so a changed ShipDoc instance across a commit is exactly a refusal. Every commit
## here goes through _commit_edit(), which detects that, notes it in the panel and resyncs
## every field from the document rather than leaving rolled-back numbers on screen.
##
## PLACEMENT IS STATICALLY TYPED against ShipPlacement (API_CONTRACT_UI sections 1-2). It is
## still null-guarded everywhere, because get_placement() is only non-null after
## ShipBuilder._ready() and this panel edits the selected part directly when no ghost is up.
class_name InspectorPanel
extends VBoxContainer

const TICK_LENGTH: float = 4.0
## A UI-side authoring bound on the attach offset, NOT a model constraint: ShipPlacement and
## ShipPart both leave `offset` unclamped. It exists so the field has a finite range to
## scrub against; a ship needing a boom further out than this wants a spar part, not a
## 100 m float. Raise it here if that turns out to be wrong.
const OFFSET_LIMIT: float = 100.0
const OFFSET_SCRUB: float = 0.05
const SCALE_SCRUB: float = 0.02
const ANGLE_LIMIT: float = 180.0
const PITCH_LIMIT: float = 90.0
## Fallback quantization when snapping is switched off: fine enough to feel continuous,
## coarse enough that the 3-decimal display is the whole truth.
const SNAP_OFF_STEP: float = 0.001

## The snap selector, SPEC section 6. 0.0 is "off".
## Document mirror planes, in button order. "" is OFF and must stay last so the row reads
## X | Y | Z | OFF. Mirrors ShipSymmetry.PLANES plus the off state.
const MIRROR_PLANES: Array = ["x", "y", "z", ""]

const SNAP_CHOICES: Array = [0.1, 0.5, 1.0, 5.0, 15.0, 0.0]
const SNAP_LABELS: Array = ["0.100", "0.500", "1.000", "5.000", "15.000", "OFF"]
const SNAP_DEFAULT_INDEX: int = 1

var _builder: ShipBuilder = null
var _ship_theme: ShipTheme = null
## The session's placement state machine. Non-null after ShipBuilder._ready().
var _placement: ShipPlacement = null

var _header: Label = null
var _note: Label = null
var _body: VBoxContainer = null
var _param_box: VBoxContainer = null
var _snap_option: OptionButton = null
var _uniform_check: CheckButton = null

var _yaw: NumericField = null
var _pitch: NumericField = null
var _rot_x: NumericField = null
var _rot_y: NumericField = null
var _rot_z: NumericField = null
var _offset: NumericField = null
var _scale_x: NumericField = null
var _scale_y: NumericField = null
var _scale_z: NumericField = null
## param key -> NumericField, rebuilt only when the family/manufacturer pair changes.
var _param_fields: Dictionary = {}
var _param_signature: String = ""
var _section_labels: Array[Label] = []
## Value lines - the snap and symmetry readouts. Tinted "text", not "text_dim".
var _readout_labels: Array[Label] = []

## The SNAP section: hidden entirely for a part that is not snapped, because an empty
## readout is worse than no readout.
var _snap_section: VBoxContainer = null
var _snap_target_label: Label = null
var _snap_parent_label: Label = null
var _snap_angles_label: Label = null
var _snap_note_label: Label = null
## Guards the SnapTargets pass: it resolves the PARENT's shape and projects every target
## onto the real surface, which is far too much to redo on a scale keystroke. Rebuilt only
## when the part, its target, or the parent's geometry actually moves.
var _snap_signature: String = ""

## The SYMMETRY section - a readout, not a command. See the class docs.
var _symmetry_label: Label = null
## The MIRROR X / Y / Z / OFF row, in MIRROR_PLANES order.
var _plane_buttons: Array[Button] = []

## The part the fields are pointed at: the first id in the selection, or the placement's.
var _target_id: String = ""
## Raised across every model/view crossing. See defence 2 in the class docs.
var _binding: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)

	_header = Label.new()
	_header.name = "InspectorHeader"
	_header.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_header.clip_text = true
	_header.text = "NO SELECTION"
	add_child(_header)

	_note = Label.new()
	_note.name = "InspectorNote"
	_note.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.text = ""
	add_child(_note)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "InspectorScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_body = VBoxContainer.new()
	_body.name = "InspectorBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	scroll.add_child(_body)

	# SYMMETRY sits above the shape params on purpose. The param list is per-family and
	# open-ended (seven fields for a box_hull today, more as families are added), so anything
	# below it is off the bottom of the panel at the device's 800px height and reachable only by
	# scrolling. The mirror-plane row is a top-level document setting; it should not be the thing
	# a player has to go looking for.
	_build_attach_section()
	_build_snap_section()
	_build_scale_section()
	_build_symmetry_section()
	_build_param_section()


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
	for field: NumericField in _all_fields():
		field.bind_theme(_ship_theme)
	_builder.doc_changed.connect(_on_doc_changed)
	_builder.selection_changed.connect(_on_selection_changed)
	_connect_placement()
	_apply_config_ranges()
	_apply_snap(SNAP_DEFAULT_INDEX)
	_sync_from_doc()
	_apply_palette()


# ---------------------------------------------------------------- construction


func _build_attach_section() -> void:
	_body.add_child(_make_section("ATTACH"))
	_yaw = _make_field("YAW", "DEG", -ANGLE_LIMIT, ANGLE_LIMIT)
	_pitch = _make_field("PITCH", "DEG", -PITCH_LIMIT, PITCH_LIMIT)
	_rot_x = _make_field("ROT X", "DEG", -ANGLE_LIMIT, ANGLE_LIMIT)
	_rot_y = _make_field("ROT Y", "DEG", -ANGLE_LIMIT, ANGLE_LIMIT)
	_rot_z = _make_field("ROT Z", "DEG", -ANGLE_LIMIT, ANGLE_LIMIT)
	_rot_x.tooltip_text = "TILT OFF THE SURFACE, ABOUT THE MOUNT FRAME X"
	_rot_y.tooltip_text = "TILT OFF THE SURFACE, ABOUT THE MOUNT FRAME Y"
	_rot_z.tooltip_text = "SPIN ON THE SURFACE - THE MOUNT FRAME Z IS THE PLACEMENT NORMAL"
	_offset = _make_field("OFFSET", "M", -OFFSET_LIMIT, OFFSET_LIMIT)
	# The clamp range is generous; the drag has to move in centimetres to be usable.
	_offset.set_scrub_rate(OFFSET_SCRUB)
	for field: NumericField in _attach_fields():
		field.value_changed.connect(_on_attach_field_changed)
		_body.add_child(field)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_body.add_child(row)
	var tag: Label = Label.new()
	tag.text = "SNAP DEG"
	tag.custom_minimum_size = Vector2(ShipTheme.pxf(NumericField.LABEL_WIDTH), ShipTheme.pxf(0.0))
	tag.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(tag)
	_section_labels.append(tag)

	_snap_option = OptionButton.new()
	_snap_option.name = "SnapOption"
	_snap_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snap_option.focus_mode = Control.FOCUS_NONE
	_snap_option.add_theme_font_size_override("font_size", ShipTheme.font_small())
	for i: int in SNAP_CHOICES.size():
		_snap_option.add_item(str(SNAP_LABELS[i]), i)
	_snap_option.select(SNAP_DEFAULT_INDEX)
	_snap_option.item_selected.connect(_apply_snap)
	row.add_child(_snap_option)


func _build_scale_section() -> void:
	_body.add_child(_make_section("SCALE"))
	# Seeded from the SHIPPED defaults rather than a made-up pair, because setup() has not run
	# yet and a placeholder range here would silently clamp the first value written in.
	# _apply_config_ranges() replaces these with the live tuning.json values.
	var shipped: ShipConfig = ShipConfig.defaults()
	_scale_x = _make_field("SCALE X", "", shipped.part_scale_min, shipped.part_scale_max)
	_scale_y = _make_field("SCALE Y", "", shipped.part_scale_min, shipped.part_scale_max)
	_scale_z = _make_field("SCALE Z", "", shipped.part_scale_min, shipped.part_scale_max)
	for field: NumericField in [_scale_x, _scale_y, _scale_z]:
		field.set_scrub_rate(SCALE_SCRUB)
		field.value_changed.connect(_on_scale_field_changed.bind(field))
		_body.add_child(field)

	_uniform_check = CheckButton.new()
	_uniform_check.name = "UniformLock"
	_uniform_check.text = "UNIFORM"
	_uniform_check.tooltip_text = "LOCK ALL THREE SCALE AXES TOGETHER"
	_uniform_check.focus_mode = Control.FOCUS_NONE
	_uniform_check.add_theme_font_size_override("font_size", ShipTheme.font_small())
	_body.add_child(_uniform_check)


func _build_param_section() -> void:
	_body.add_child(_make_section("SHAPE"))
	_param_box = VBoxContainer.new()
	_param_box.name = "ParamBox"
	_param_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_param_box.add_theme_constant_override("separation", 2)
	_body.add_child(_param_box)


## Shown only while the selected part carries a snap_id. Four flat lines rather than fields:
## none of this is editable, and a disabled NumericField would invite the player to try.
##
## TWO UNRELATED THINGS ARE CALLED SNAP IN THIS PANEL and they sit next to each other, so:
## the SNAP DEG selector directly above is angular QUANTIZATION - the increment typed and
## dragged values round to (SPEC section 6). This section is Spore's snap TARGETS - the typed
## points on a parent's surface a part can stand on (API_CONTRACT_SPORE section 1). They share
## a word and nothing else. Do not unify them.
func _build_snap_section() -> void:
	_snap_section = VBoxContainer.new()
	_snap_section.name = "SnapSection"
	_snap_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snap_section.add_theme_constant_override("separation", 1)
	_snap_section.visible = false
	_snap_section.add_child(_make_section("SNAP TARGET"))
	_snap_target_label = _make_readout_label("SnapTarget")
	_snap_parent_label = _make_readout_label("SnapParent")
	_snap_angles_label = _make_readout_label("SnapAngles")
	_snap_note_label = _make_readout_label("SnapNote")
	_snap_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label: Label in [
		_snap_target_label, _snap_parent_label, _snap_angles_label, _snap_note_label
	]:
		_snap_section.add_child(label)
	_body.add_child(_snap_section)


## RETIRED(2026-08-31): _build_mirror_section() -> here. See the class docs for why the
## command did not come with it.
## SYMMETRY: the document's mirror plane, plus the per-part state readout.
##
## THE X / Y / Z ROW IS BACK, and it is not the row that was retired. The brief asked for
## "a click-and-select 'mirror acrost z, y, or z'" in the very first message; the retired buttons
## were per-part MIRROR X / Y / Z commands driving ShipMirror's opt-in derivative model, which
## API_CONTRACT_SPORE section 2 replaced with automatic symmetry. Removing them removed the
## command AND the axis choice, and the axis choice was never the thing that was wrong.
##
## So this row sets ShipDoc.symmetry_plane - which plane the WHOLE ship mirrors across - and
## nothing else. Breaking symmetry for one part is still the tree panel's cascading toggle, and
## still deliberately not duplicated here.
func _build_symmetry_section() -> void:
	_body.add_child(_make_section("SYMMETRY"))

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "MirrorPlaneRow"
	row.add_theme_constant_override("separation", 2)
	_body.add_child(row)

	var tag: Label = Label.new()
	tag.text = "MIRROR"
	tag.custom_minimum_size = Vector2(ShipTheme.pxf(NumericField.LABEL_WIDTH), 0.0)
	tag.add_theme_font_size_override("font_size", ShipTheme.font_small())
	row.add_child(tag)
	_section_labels.append(tag)

	_plane_buttons.clear()
	for entry: Variant in MIRROR_PLANES:
		var plane: String = str(entry)
		var button: Button = Button.new()
		button.name = "Mirror_" + plane
		button.text = plane.to_upper() if plane != "" else "OFF"
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", ShipTheme.font_small())
		button.tooltip_text = (
			"MIRROR THE WHOLE SHIP ACROSS THIS PLANE"
			if plane != ""
			else "NO MIRRORING - EVERY PART STANDS ALONE"
		)
		button.pressed.connect(_on_mirror_plane_pressed.bind(plane))
		row.add_child(button)
		_plane_buttons.append(button)

	_symmetry_label = _make_readout_label("SymmetryState")
	_symmetry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_symmetry_label.tooltip_text = (
		"SYMMETRY IS ON BY DEFAULT AND DOUBLES A PART'S COMPLEXITY COST.\n"
		+ "BREAKING IT HALVES THAT AND CASCADES TO EVERY PART ATTACHED BELOW.\n"
		+ "BREAK IT WITH THE TREE PANEL'S BREAK SYMMETRY TOGGLE."
	)
	_body.add_child(_symmetry_label)


## Set which plane the document mirrors across. Goes through the edit protocol like any other
## document change, so it is undoable and the budget guard sees it - flipping the plane can change
## how many parts generate twins, which changes the complexity total.
func _on_mirror_plane_pressed(plane: String) -> void:
	var doc: ShipDoc = _builder.get_doc()
	if doc == null or doc.symmetry_plane == plane:
		_refresh_mirror_buttons(doc)
		return
	_builder.begin_edit("mirror plane")
	doc.symmetry_plane = plane
	# Every part can gain or lose a twin, so the whole document is the changed set.
	var ids: PackedStringArray = PackedStringArray()
	for id: Variant in doc.parts.keys():
		ids.append(str(id))
	_commit_edit(ids, doc)
	_refresh_mirror_buttons(_builder.get_doc())


func _refresh_mirror_buttons(doc: ShipDoc) -> void:
	var live: String = doc.symmetry_plane if doc != null else ""
	for i: int in _plane_buttons.size():
		var button: Button = _plane_buttons[i]
		if is_instance_valid(button):
			button.set_pressed_no_signal(str(MIRROR_PLANES[i]) == live)


func _make_readout_label(node_name: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.clip_text = true
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	label.text = ""
	# Tracked apart from _section_labels: a section HEADING is dim furniture, a readout is
	# the number the player came here to read.
	_readout_labels.append(label)
	return label


func _make_section(title: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var label: Label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", ShipTheme.font_small())
	box.add_child(label)
	box.add_child(HSeparator.new())
	_section_labels.append(label)
	return box


func _make_field(
	field_label: String, suffix: String, minimum: float, maximum: float
) -> NumericField:
	var field: NumericField = NumericField.new()
	field.name = "Field" + field_label.replace(" ", "")
	field.configure(field_label, minimum, maximum, SNAP_OFF_STEP, false)
	field.set_suffix(suffix)
	return field


# ---------------------------------------------------------------- placement wiring


## Both ends of the ghost binding: ghost_moved is the placement's own emission (mouse or
## typed), attach_preview_changed is the builder's relay of the same numbers with the part id
## attached. Listening to both is deliberate - the panel must not care which author moved
## the ghost, and `_binding` makes double delivery a no-op rather than a double edit.
func _connect_placement() -> void:
	_placement = _builder.get_placement()
	if _placement != null:
		_placement.ghost_moved.connect(_on_ghost_moved)
	_builder.attach_preview_changed.connect(_on_attach_preview_changed)
	_builder.placement_state_changed.connect(_on_placement_state_changed)


func _placement_active() -> bool:
	return _placement != null and _placement.active


## Model -> view. Defence 2: dropped when this panel is the author of the change.
func _on_ghost_moved(yaw: float, pitch: float, rot: Vector3, offset: float) -> void:
	if _binding:
		return
	_binding = true
	_write_attach_fields(yaw, pitch, rot, offset)
	_binding = false


func _on_attach_preview_changed(
	part_id: String, yaw: float, pitch: float, rot: Vector3, offset: float
) -> void:
	if _binding:
		return
	_binding = true
	_target_id = part_id
	_write_attach_fields(yaw, pitch, rot, offset)
	_binding = false
	_set_header_for_placement(part_id)


func _on_placement_state_changed(is_active: bool) -> void:
	if is_active:
		_set_note("PLACING - TYPE OR DRAG TO POSITION, THEN COMMIT")
		# Only the attach fields. The ghost is not a document part yet, so scale and shape
		# params have nothing to write to and must not look as though they do.
		for field: NumericField in _attach_fields():
			field.set_editable(true)
		return
	_set_note("")
	_sync_from_doc()


func _write_attach_fields(yaw: float, pitch: float, rot: Vector3, offset: float) -> void:
	_yaw.set_value(yaw)
	_pitch.set_value(pitch)
	_rot_x.set_value(rot.x)
	_rot_y.set_value(rot.y)
	_rot_z.set_value(rot.z)
	_offset.set_value(offset)


## Every field that writes an attach number, in display order. One list, so a field added here
## cannot be missed by the editability pass or the signal hookup.
func _attach_fields() -> Array:
	return [_yaw, _pitch, _rot_x, _rot_y, _rot_z, _offset]


func _rot_from_fields() -> Vector3:
	return Vector3(_rot_x.get_value(), _rot_y.get_value(), _rot_z.get_value())


# ---------------------------------------------------------------- attach edits


## View -> model. Either the live ghost or, with no placement running, the selected part.
func _on_attach_field_changed(_value: float) -> void:
	if _binding:
		return
	if _placement_active():
		# set_values() emits ghost_moved synchronously; the flag is what stops that echo from
		# stamping the quantized result back over a field the user is still working in.
		_binding = true
		_placement.set_values(
			_yaw.get_value(), _pitch.get_value(), _rot_from_fields(), _offset.get_value()
		)
		_binding = false
		return
	_write_attach_to_part()


func _write_attach_to_part() -> void:
	var doc: ShipDoc = _builder.get_doc()
	var part: ShipPart = _part(doc, _target_id)
	if part == null or not _is_part_editable(part):
		return
	_builder.begin_edit("attach numbers")
	part.yaw = _yaw.get_value()
	part.pitch = _pitch.get_value()
	part.rot = _rot_from_fields()
	part.offset = _offset.get_value()
	_commit_edit(PackedStringArray([_target_id]), doc)


func _on_scale_field_changed(value: float, source: NumericField) -> void:
	if _binding:
		return
	var doc: ShipDoc = _builder.get_doc()
	var part: ShipPart = _part(doc, _target_id)
	if part == null or not _is_part_editable(part):
		return
	if _uniform_check != null and _uniform_check.button_pressed:
		_binding = true
		for field: NumericField in [_scale_x, _scale_y, _scale_z]:
			if field != source:
				field.set_value(value)
		_binding = false
	_builder.begin_edit("scale part")
	part.scale = Vector3(_scale_x.get_value(), _scale_y.get_value(), _scale_z.get_value())
	_commit_edit(PackedStringArray([_target_id]), doc)


func _on_param_changed(value: float, key: String) -> void:
	if _binding:
		return
	var doc: ShipDoc = _builder.get_doc()
	var data: ShipData = _builder.get_data()
	var part: ShipPart = _part(doc, _target_id)
	if part == null or data == null or not _is_part_editable(part):
		return
	var params: Dictionary = part.params.duplicate(true)
	params[key] = value
	_builder.begin_edit("shape %s" % key)
	# clamp_params() is the input gate (SPEC section 4) and keeps integer params integral, so
	# the canonical hash of an already-legal document does not churn on a float round-trip.
	part.params = ShapeGen.clamp_params(data, part.family, part.manufacturer, params)
	_commit_edit(PackedStringArray([_target_id]), doc)


# ---------------------------------------------------------------- snap


func _apply_snap(index: int) -> void:
	var chosen: float = 0.0
	if index >= 0 and index < SNAP_CHOICES.size():
		chosen = float(SNAP_CHOICES[index])
	var step: float = chosen if chosen > 0.0 else SNAP_OFF_STEP
	# Each angular axis snaps independently (SPEC section 6), which is what per-field steps
	# give for free.
	for field: NumericField in [_yaw, _pitch, _rot_x, _rot_y, _rot_z]:
		field.set_step(step)
	if _placement != null:
		# Snapping is applied at INPUT time inside ShipPlacement, so the panel hands it the
		# increment rather than quantizing on the way in and again on the way out. 0.0 is
		# "off", which is exactly what the OFF entry carries.
		_placement.snap_deg = chosen


func _apply_config_ranges() -> void:
	var cfg: ShipConfig = _builder.get_config()
	if cfg == null:
		return
	_offset.set_step(maxf(cfg.snap_m, 0.0))
	for field: NumericField in [_scale_x, _scale_y, _scale_z]:
		field.set_range(cfg.part_scale_min, cfg.part_scale_max)
		field.set_step(maxf(cfg.snap_scale, 0.0))
	if _placement != null:
		_placement.snap_m = cfg.snap_m


# ---------------------------------------------------------------- doc sync


func _on_doc_changed(_doc: ShipDoc) -> void:
	_sync_from_doc()


func _on_selection_changed(_selected: PackedStringArray) -> void:
	_sync_from_doc()


## Model -> view for everything that is not the live ghost. Every write goes through
## NumericField.set_value(), which is silent and which refuses to stamp over a field the user
## is typing into, so this is safe to call from any signal at any time.
func _sync_from_doc() -> void:
	if _builder == null:
		return
	var doc: ShipDoc = _builder.get_doc()
	var selected: PackedStringArray = _builder.get_selection()
	_target_id = selected[0] if not selected.is_empty() else ""
	var part: ShipPart = _part(doc, _target_id)
	_binding = true
	_refresh_header(part, selected.size())
	_refresh_snap(doc, part)
	_refresh_symmetry(doc, part)
	_refresh_mirror_buttons(doc)
	if part == null:
		_set_fields_editable(false)
		_rebuild_params(null)
		_binding = false
		return
	if not _placement_active():
		_write_attach_fields(part.yaw, part.pitch, part.rot, part.offset)
	_scale_x.set_value(part.scale.x)
	_scale_y.set_value(part.scale.y)
	_scale_z.set_value(part.scale.z)
	_set_fields_editable(_is_part_editable(part))
	_apply_snap_lock(part)
	_rebuild_params(part)
	_binding = false


## A snapped part's yaw and pitch come from its target and are ignored on load
## (API_CONTRACT_SPORE section 2), so the two fields go read-only rather than accepting
## numbers the next load will discard. Roll and offset are untouched: nothing derives those.
func _apply_snap_lock(part: ShipPart) -> void:
	if part == null or part.snap_id == "":
		return
	_yaw.set_editable(false)
	_pitch.set_editable(false)


func _refresh_header(part: ShipPart, selection_size: int) -> void:
	if part == null:
		_header.text = "NO SELECTION"
		_set_note("SELECT A PART, OR PICK A FAMILY FROM THE PALETTE")
		return
	var name: String = part.display_name
	if name.strip_edges() == "":
		name = part.family
	var suffix: String = ("  +%d" % (selection_size - 1)) if selection_size > 1 else ""
	_header.text = "%s  %s%s" % [_target_id, name.to_upper(), suffix]
	if part.is_mirror():
		# RETIRED(2026-08-31): "USE UNLINK" -> nothing. Legacy derivatives are still shown and
		# still read-only, but the command that materialised them is gone with the rest of
		# the old mirror model; the way to get an independent part now is to place one.
		_set_note("LEGACY MIRROR OF %s - NOT EDITABLE" % part.mirror_source)
		return
	if part.locked:
		_set_note("LOCKED PART - NOT EDITABLE")
		return
	if part.kind == ShipPart.KIND_COMPONENT_INSTANCE:
		_set_note("COMPONENT INSTANCE - EDIT THE DEFINITION, OR MAKE UNIQUE FIRST")
		return
	_set_note("%s / %s" % [part.family.to_upper(), part.manufacturer.to_upper()])


## ShipBuilder relays ShipPlacement.moving_part_id(), which is "" while a NEW part is being
## placed and the real id only while an existing one is being re-placed. Both are legal.
func _set_header_for_placement(part_id: String) -> void:
	if _header == null:
		return
	if part_id == "":
		_header.text = "PLACING NEW PART"
		return
	_header.text = "MOVING %s" % part_id.to_upper()


## A legacy mirror derivative has no independent geometry of its own - it is reflected from
## its source every resolve - so editing its numbers would write values nothing ever reads.
## A locked part is flagged not editable by its author.
static func _is_part_editable(part: ShipPart) -> bool:
	return part != null and not part.is_mirror() and not part.locked


func _set_fields_editable(on: bool) -> void:
	for field: NumericField in _all_fields():
		field.set_editable(on)
	for key: Variant in _param_fields.keys():
		var field: NumericField = _param_field(str(key))
		if field != null:
			field.set_editable(on)


func _all_fields() -> Array[NumericField]:
	var fields: Array[NumericField] = [
		_yaw, _pitch, _rot_x, _rot_y, _rot_z, _offset, _scale_x, _scale_y, _scale_z
	]
	return fields


# ---------------------------------------------------------------- shape params


## Fields are rebuilt only when the family/manufacturer pair changes, because tearing down
## and recreating a NumericField on every commit would destroy focus, caret and any
## half-typed entry - i.e. it would reintroduce the exact bug the focus guard exists to stop.
func _rebuild_params(part: ShipPart) -> void:
	var data: ShipData = _builder.get_data()
	var signature: String = ""
	if part != null and data != null:
		signature = "%s|%s" % [part.family, part.manufacturer]
	if signature != _param_signature:
		_param_signature = signature
		_clear_params()
		if signature != "":
			_create_params(data, part)
	_write_params(part)


func _clear_params() -> void:
	_param_fields = {}
	for child: Node in _param_box.get_children():
		_param_box.remove_child(child)
		child.queue_free()


func _create_params(data: ShipData, part: ShipPart) -> void:
	var ranges: Dictionary = ShapeGen.effective_ranges(data, part.family, part.manufacturer)
	var keys: PackedStringArray = PackedStringArray()
	for key: Variant in ranges.keys():
		keys.append(str(key))
	keys.sort()
	if keys.is_empty():
		var empty: Label = Label.new()
		empty.text = "NO TUNABLE PARAMETERS"
		empty.add_theme_font_size_override("font_size", ShipTheme.font_small())
		# Coloured here rather than tracked in _section_labels: this Label is freed again on
		# the next family switch, and a list of freed Labels is a leak with a valid-check
		# bolted on.
		empty.add_theme_color_override("font_color", _role_color("text_dim"))
		_param_box.add_child(empty)
		return
	for key: String in keys:
		_create_param_field(key, _range_of(ranges, key))


func _create_param_field(key: String, spec: Dictionary) -> void:
	var minimum: float = _num(spec.get("min", null), 0.0)
	var maximum: float = _num(spec.get("max", null), minimum)
	var is_int: bool = bool(spec.get("is_int", false))
	# rib_count and friends: is_int makes the step 1 and rounds every path into the field,
	# so the doc never receives 4.31 ribs.
	var step: float = 1.0 if is_int else SNAP_OFF_STEP
	var field: NumericField = NumericField.new()
	field.name = "Param" + key
	field.configure(key, minimum, maximum, step, is_int)
	field.bind_theme(_ship_theme)
	field.tooltip_text = (
		"%s\nRANGE %s .. %s"
		% [key.to_upper(), NumericField.format_number(minimum), NumericField.format_number(maximum)]
	)
	field.value_changed.connect(_on_param_changed.bind(key))
	_param_box.add_child(field)
	_param_fields[key] = field


func _write_params(part: ShipPart) -> void:
	if part == null:
		return
	for key: Variant in _param_fields.keys():
		var name: String = str(key)
		var field: NumericField = _param_field(name)
		if field != null:
			field.set_value(_num(part.params.get(name, null), field.get_value()))


func _param_field(key: String) -> NumericField:
	var value: Variant = _param_fields.get(key, null)
	if value is NumericField:
		return value
	return null


static func _range_of(ranges: Dictionary, key: String) -> Dictionary:
	var value: Variant = ranges.get(key, null)
	if value is Dictionary:
		return value
	return {}


static func _num(value: Variant, fallback: float) -> float:
	var kind: int = typeof(value)
	if kind == TYPE_FLOAT or kind == TYPE_INT:
		var out: float = value
		if is_finite(out):
			return out
	return fallback


# ---------------------------------------------------------------- snap readout


## The whole SNAP section, refreshed from the document. Hidden - not blanked - when the part
## is not snapped, so the section header does not sit over four empty lines.
##
## `_snap_signature` is what keeps this off the keystroke path: the readout only re-derives
## when the part, its target id, or the PARENT's geometry moves. Editing this part's own
## scale does not move its snap point on the parent, so it does not re-derive either.
func _refresh_snap(doc: ShipDoc, part: ShipPart) -> void:
	if _snap_section == null:
		return
	if part == null or part.snap_id == "" or doc == null:
		_snap_section.visible = false
		_snap_signature = ""
		return
	var parent: ShipPart = _part(doc, part.parent)
	var signature: String = _snap_signature_of(part, parent)
	_snap_section.visible = true
	if signature == _snap_signature:
		return
	_snap_signature = signature
	_write_snap_lines(part, parent)


func _write_snap_lines(part: ShipPart, parent: ShipPart) -> void:
	# Resolved ONCE and handed down: SnapTargets projects every target onto the real warped
	# surface, so asking twice would pay for that twice.
	var shape: ResolvedShape = _parent_shape(parent)
	var target: Dictionary = ShipAttach.snap_target(shape, part.snap_id)
	var kind: String = _text_of(target, "kind", "UNKNOWN")
	_snap_target_label.text = "ON      %s  (%s)" % [part.snap_id.to_upper(), kind.to_upper()]
	if parent == null:
		# A snap_id with no parent record. Reported, not swallowed: it means the document
		# refers to a target on a part that is no longer there.
		_snap_parent_label.text = "OF      %s  (MISSING)" % part.parent.to_upper()
	else:
		var label: String = parent.display_name
		if label.strip_edges() == "":
			label = parent.family
		_snap_parent_label.text = "OF      %s  %s" % [part.parent.to_upper(), label.to_upper()]
	_snap_angles_label.text = _snap_angles_text(target, shape)
	_snap_note_label.text = (
		"YAW AND PITCH ARE DERIVED FROM THIS TARGET, NOT AUTHORED - "
		+ "THEY ARE IGNORED ON LOAD. ROLL AND OFFSET ARE STILL YOURS."
	)


## The two derived angles, from the engine's own derivation.
##
## `ShipAttach.angles_for_target()` is the SAME call `ShipPlacement` makes when it stores those
## angles on the part, so this readout cannot drift from what was actually written. That
## includes the `center` target: it sits at the shape origin where there is no direction from
## the origin to take, and `angles_for_target()` reports the direction of the target's own
## mount normal instead - which is where a child snapped to a parent's centre really stands.
## Do not reimplement this locally; a second copy of the derivation is a second answer.
func _snap_angles_text(target: Dictionary, shape: ResolvedShape) -> String:
	if target.is_empty() or shape == null:
		return "DERIVED  TARGET NOT FOUND ON THE PARENT SHAPE"
	var angles: Vector2 = ShipAttach.angles_for_target(shape, target)
	return (
		"DERIVED  YAW %s  PITCH %s"
		% [NumericField.format_number(angles.x), NumericField.format_number(angles.y)]
	)


## The parent's resolved shape - the frame every snap question is asked in. Null when the
## parent is gone or its family is not in the pack.
func _parent_shape(parent: ShipPart) -> ResolvedShape:
	var data: ShipData = _builder.get_data()
	if parent == null or data == null or not data.has_family(parent.family):
		return null
	return ShapeGen.resolve(data, parent.family, parent.manufacturer, parent.params, parent.scale)


## Everything the readout depends on. The parent's params and scale are in because they warp
## the surface the target sits on; this part's own scale is deliberately NOT.
static func _snap_signature_of(part: ShipPart, parent: ShipPart) -> String:
	if parent == null:
		return "%s|%s|MISSING" % [part.parent, part.snap_id]
	return (
		"%s|%s|%s|%s|%s|%s"
		% [
			part.parent,
			part.snap_id,
			parent.family,
			parent.manufacturer,
			str(parent.params),
			str(parent.scale),
		]
	)


# ---------------------------------------------------------------- symmetry readout


## State, source and price for the selected part. Always through
## ShipSymmetry.is_effectively_asymmetric() - a part's own `asymmetric` flag is not the
## answer to this question when an ancestor has already broken it.
func _refresh_symmetry(doc: ShipDoc, part: ShipPart) -> void:
	if _symmetry_label == null:
		return
	if doc == null or part == null or _target_id == "":
		_symmetry_label.text = "---"
		return
	if ShipSymmetry.plane_axis(doc.symmetry_plane) < 0:
		_symmetry_label.text = "NO MIRROR PLANE - SINGLE COST"
		return
	var cost: String = NumericField.format_number(_cost_of(doc, _target_id))
	if not ShipSymmetry.is_effectively_asymmetric(doc, _target_id):
		# ON THE PLANE IS NOT MIRRORED. This used to report every symmetric part as "MIRRORED
		# ACROSS X", including one sitting on the centre line - where a twin would land on top of
		# the original and is correctly not generated. So the panel claimed a mirror that did not
		# exist, and the only way to find out was to count the parts on screen. Reported as "i add
		# a piece to the base cube and only 1 piece is added".
		if not _has_twin(doc, _target_id):
			_symmetry_label.text = (
				"ON THE %s MIRROR PLANE - NO TWIN. MOVE IT OFF THE CENTRE LINE TO MIRROR."
				% doc.symmetry_plane.to_upper()
			)
			return
		_symmetry_label.text = (
			"MIRRORED ACROSS %s - COSTS %s, DOUBLED" % [doc.symmetry_plane.to_upper(), cost]
		)
		return
	var source: String = _break_source(doc, _target_id)
	if source == _target_id:
		_symmetry_label.text = "BROKEN HERE - COSTS %s, HALVED. CASCADES DOWN." % cost
		return
	_symmetry_label.text = (
		"BROKEN AT %s - COSTS %s, HALVED. INHERITED." % [source.to_upper(), cost]
	)


## Does this part ACTUALLY have a mirrored twin right now?
##
## Asks the attach pass rather than re-deriving the epsilon test, so the readout and the geometry
## cannot disagree: a twin exists exactly when resolve_all() emitted a transform for its id.
func _has_twin(doc: ShipDoc, part_id: String) -> bool:
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return false
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, cfg)
	return xforms.has(ShipSymmetry.twin_id(part_id))


## The outermost effectively-asymmetric part in this one's ancestor chain - the part that
## owns the break. Derived from is_effectively_asymmetric() alone, never from the raw flag;
## effective asymmetry only propagates downward, so the furthest ancestor that has it is the
## one that started it. Mirrors PartTreePanel._break_source(); the two panels may not reach
## into each other (API_CONTRACT_UI section 0), so the derivation is stated in both.
func _break_source(doc: ShipDoc, part_id: String) -> String:
	if doc == null or not ShipSymmetry.is_effectively_asymmetric(doc, part_id):
		return ""
	var source: String = part_id
	for ancestor_id: String in doc.ancestors_of(part_id):
		if ShipSymmetry.is_effectively_asymmetric(doc, ancestor_id):
			source = ancestor_id
	return source


func _cost_of(doc: ShipDoc, part_id: String) -> float:
	var data: ShipData = _builder.get_data()
	var cfg: ShipConfig = _builder.get_config()
	if doc == null or data == null or cfg == null:
		return 0.0
	return ShipComplexity.cost_of(doc, part_id, data, cfg)


static func _text_of(entry: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = entry.get(key, null)
	if value is String:
		var text: String = value
		if text.strip_edges() != "":
			return text
	return fallback


# ---------------------------------------------------------------- edit plumbing


## The single commit path. `before` is the ShipDoc instance the mutation was applied to;
## ShipBuilder rolls a refused edit back by replacing the document with a fresh one rebuilt
## from the history head, so a different instance afterwards is exactly a refusal. The
## builder shows its own BUDGET dialog; this makes sure the panel does not keep displaying
## numbers that no longer exist.
##
## Known limit: if the history stack were empty, peek() would return null and the builder
## would keep the same instance on a refusal, so the note would be missed. That cannot happen
## in practice - ShipBuilder pushes one snapshot at document creation - and _sync_from_doc()
## runs either way, so the numbers on screen are the document's regardless.
func _commit_edit(changed: PackedStringArray, before: ShipDoc) -> bool:
	_builder.commit_edit(changed)
	var accepted: bool = _builder.get_doc() == before
	if not accepted:
		_set_note("EDIT REFUSED AND ROLLED BACK - A BUDGET WOULD BE EXCEEDED")
	_sync_from_doc()
	return accepted


static func _part(doc: ShipDoc, part_id: String) -> ShipPart:
	if doc == null or part_id == "":
		return null
	var value: Variant = doc.parts.get(part_id, null)
	if value is ShipPart:
		return value
	return null


func _set_note(text: String) -> void:
	if _note != null:
		_note.text = text


# ---------------------------------------------------------------- palette


func _on_palette_changed(_palette: PackedColorArray) -> void:
	_apply_palette()


func _apply_palette() -> void:
	if _header != null:
		_header.add_theme_color_override("font_color", _role_color("accent"))
	if _note != null:
		_note.add_theme_color_override("font_color", _role_color("text_dim"))
	for label: Label in _section_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", _role_color("text_dim"))
	for label: Label in _readout_labels:
		if is_instance_valid(label):
			label.add_theme_color_override("font_color", _role_color("text"))
	queue_redraw()


## The only sanctioned colour lookup. Never an index (SPEC section 11).
func _role_color(role: String) -> Color:
	if _ship_theme == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	return _ship_theme.color_for_role(role)
