class_name ShipReseat
extends RefCounted

## Keyboard reseating of an ALREADY-COMMITTED part: stepping its placement vector across its
## parent's surface, and aiming it at a reference direction.
##
## Split out of `ShipPlacement` rather than added to it, and the reason is a real seam and not a
## lint budget. Every other selection verb there — rotate, scale, offset, morph — has to do two
## different things depending on whether a ghost is live: adjust the preview, or edit the
## document. These two do not. A ghost has no committed placement to step and no stored `rot`
## to aim, so both are document-only operations, they need none of the placement's state, and
## living beside it would have meant reaching back into a class they have no business knowing.
##
## Static only, and it talks to the document exclusively through `ShipBuilder.begin_edit()` /
## `commit_edit()` — the edit protocol every other writer uses, so an arrow-key step is undoable
## and budget-checked exactly like a drag.
##
## RETIRED(2026-09-02): `step_snap_target()` and `ROW_STRIDE` -> [method step_placement]. The
## arrows used to walk the parent's [SnapTargets] list - centre, faces, poles, rim points - by
## one entry (LEFT/RIGHT) or eight (UP/DOWN). The list is typed, not spatial, so a press
## teleported the part to whichever face or pole came next in it: "moves the object almost
## randomly at large 90 degree snaps ... i cant even track what its trying to do." The author's
## stated mechanics are the ones below: "the child part - parent part placement vector should
## change angle, smallest snap amount ... all relative motions smallest snaps along parents
## surface."

const LABEL_STEP: String = "step placement"
const LABEL_AIM: String = "aim part"


## Steps the selection's PLACEMENT VECTOR - the yaw/pitch ray from its parent's centre that
## SPEC 3 traces to the anchor - by `step_deg` in the PARENT's own frame: `yaw_dir` turns it
## about the parent's up axis, `pitch_dir` tips it toward or away from that axis, each -1, 0
## or +1. The part slides across its parent's surface by the smallest snap and stays seated.
##
## The result is put ON the snap grid (`round(v / step) * step`), not merely moved by one step:
## a part that was drag-snapped carries the exact, unquantized angles of its target, and the
## first press should land it on the same lattice every later press walks.
##
## Writes `snap_id = ""`. [method ShipAttach.local_transform] takes the snapped anchor whenever
## the stored id names a target the parent has, and the angles would not be read at all; a
## stepped part has, by definition, left its target.
static func step_placement(
	builder: ShipBuilder, yaw_dir: int, pitch_dir: int, step_deg: float
) -> bool:
	if builder == null or step_deg <= 0.0:
		return false
	if yaw_dir == 0 and pitch_dir == 0:
		return false
	var doc: ShipDoc = builder.get_doc()
	if doc == null:
		return false
	var steppable: PackedStringArray = PackedStringArray()
	for pid: String in _editable(doc, builder.get_selection()):
		# A root has no placement vector to step; leaving it out keeps the press from being
		# recorded as an empty, undoable edit.
		if not (doc.parts[pid] as ShipPart).parent.is_empty():
			steppable.append(pid)
	if steppable.is_empty():
		return false
	builder.begin_edit(LABEL_STEP)
	for pid: String in steppable:
		var part: ShipPart = doc.parts[pid]
		# ONLY THE AXIS THE ARROW PRESSED. `_on_grid` was applied to both, so at a five degree
		# lattice a RIGHT press - which is yaw alone - dragged a pitch of 18 up to 20 with it.
		# Harmless at the old half-degree step and plainly wrong at this one.
		var yaw: float = part.yaw
		if yaw_dir != 0:
			yaw = _on_grid(part.yaw + float(yaw_dir) * step_deg, step_deg)
		var pitch: float = part.pitch
		if pitch_dir != 0:
			pitch = _on_grid(part.pitch + float(pitch_dir) * step_deg, step_deg)
		part.yaw = ShipAttach.wrap_yaw_deg(yaw)
		part.pitch = clampf(pitch, -90.0, 90.0)
		part.snap_id = ""
	builder.commit_edit(steppable)
	return true


## Aims the selection's own +Y at its parent's SURFACE NORMAL or at the PLACEMENT VECTOR.
##
## "0 toggles z reference from placement vector to surface normal vector and snaps the part to the
## surface normal." On a sphere the two directions coincide and the toggle visibly does nothing,
## which is correct; on a box face, a cone flank or anything tapered they differ, and this is the
## only way to stand a part square to one of them without typing angles.
##
## `rot.z` — the spin the player set on the surface — survives the toggle untouched.
static func aim_selection(builder: ShipBuilder, to_normal: bool) -> bool:
	if builder == null:
		return false
	var doc: ShipDoc = builder.get_doc()
	if doc == null:
		return false
	var data: ShipData = builder.get_data()
	var cfg: ShipConfig = builder.get_config()
	var aims: Dictionary = {}
	for pid: String in _editable(doc, builder.get_selection()):
		var part: ShipPart = doc.parts[pid]
		if part.parent.is_empty():
			continue
		var aim: Vector3 = _aim_direction(doc, data, cfg, part, to_normal)
		if aim.length_squared() > 0.0:
			aims[pid] = aim
	if aims.is_empty():
		return false
	var touched: PackedStringArray = PackedStringArray()
	builder.begin_edit(LABEL_AIM)
	for pid: String in aims:
		var part: ShipPart = doc.parts[pid]
		var xy: Vector2 = ShipAttach.rot_xy_for_direction(aims[pid], part.rot.z, part.rot.y)
		part.rot = Vector3(xy.x, xy.y, part.rot.z)
		touched.append(pid)
	builder.commit_edit(touched)
	return true


## Swings a PLACEMENT VECTOR about one mount-frame axis and returns the new (yaw, pitch).
##
## The other half of the author's pair: "we also need 'attached pivot, and floating connection'
## where attached pivot changes the angle of the placement vector extending from the parents
## placement spot. but floating rotation rotates the part around its center, keeping its surfaces
## touching."
##
## FLOATING is what the rings have always done - they write `rot`, and ShipAttach re-seats the
## part so it keeps touching. ATTACHED is this: the ray from the parent's centre is turned, so the
## part swings ACROSS the parent's surface and the anchor moves with it. Same gesture, same rings,
## different thing being turned - which is why it is a mode and not four more handles.
##
## Pure: takes the angles, returns the angles, touches no document. ShipView3D drives the ghost
## with the result so an attached-pivot drag previews exactly like a floating one.
static func swing_placement(
	doc: ShipDoc,
	data: ShipData,
	cfg: ShipConfig,
	part_id: String,
	yaw: float,
	pitch: float,
	axis: int,
	degrees: float
) -> Vector2:
	var here: Vector2 = Vector2(yaw, pitch)
	if doc == null or is_zero_approx(degrees):
		return here
	var part: ShipPart = doc.parts.get(part_id, null) as ShipPart
	if part == null or part.parent.is_empty():
		return here
	var parent: ShipPart = doc.parts.get(part.parent, null) as ShipPart
	if parent == null:
		return here
	var parent_shape: ResolvedShape = ShipAttach.resolve_shapes_for_part(doc, data, cfg, parent)
	if parent_shape == null:
		return here
	var ray: Vector3 = ShipAttach.direction_from_angles(yaw, pitch)
	var anchor: Vector3 = ShipAttach.trace_surface(parent_shape, ray, cfg)
	var normal: Vector3 = ShipAttach.gradient(parent_shape, anchor, cfg.gradient_eps).normalized()
	# The mount frame is built at the anchor, so its axes are the same ones the rings name - the
	# ring the player grabbed turns the ray about the axis that ring is drawn around.
	var world_axis: Vector3 = ShipAttach.mount_frame(normal) * _unit_axis(axis)
	if world_axis.length_squared() <= 0.0:
		return here
	var turned: Vector3 = Basis(world_axis.normalized(), deg_to_rad(degrees)) * ray
	return ShipAttach.angles_from_direction(turned)


static func _unit_axis(axis: int) -> Vector3:
	if axis == Vector3.AXIS_X:
		return Vector3.RIGHT
	if axis == Vector3.AXIS_Y:
		return Vector3.UP
	return Vector3.BACK


# --- internals -----------------------------------------------------------------------------


## Selected parts this may write to: present, unlocked, and authored rather than mirrored. A
## mirror derivative is not independently editable until the link is broken.
static func _editable(doc: ShipDoc, selection: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw: String in selection:
		var pid: String = ShipSymmetry.source_of_twin(raw)
		if not doc.parts.has(pid) or out.has(pid):
			continue
		var part: ShipPart = doc.parts[pid]
		if part.locked or part.is_mirror():
			continue
		out.append(pid)
	return out


## `deg` moved onto the lattice of `step` - the same quantizer ShipPlacement applies at input
## time, so a stepped angle and a typed one land on the same values.
static func _on_grid(deg: float, step: float) -> float:
	return roundf(deg / step) * step


## The aim target in MOUNT-FRAME coordinates. The normal is (0, 0, 1) there by construction (ADR
## 0004), which is `Vector3.BACK`; the placement vector has to be carried into the frame, which is
## what the transposed basis does — it is orthonormal, so the transpose is the inverse.
static func _aim_direction(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, part: ShipPart, to_normal: bool
) -> Vector3:
	if to_normal:
		return Vector3.BACK
	var parent: ShipPart = doc.parts.get(part.parent, null) as ShipPart
	if parent == null:
		return Vector3.ZERO
	var parent_shape: ResolvedShape = ShipAttach.resolve_shapes_for_part(doc, data, cfg, parent)
	if parent_shape == null:
		return Vector3.ZERO
	var ray: Vector3 = ShipAttach.direction_from_angles(part.yaw, part.pitch)
	var anchor: Vector3 = ShipAttach.trace_surface(parent_shape, ray, cfg)
	var normal: Vector3 = ShipAttach.gradient(parent_shape, anchor, cfg.gradient_eps).normalized()
	return ShipAttach.mount_frame(normal).transposed() * ray
