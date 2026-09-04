## ShipPlacement - the single source of truth for one in-progress placement (M3).
##
## API_CONTRACT_UI section 1. One instance lives on ShipBuilder for the whole session and
## is reused; `active` says whether a ghost is currently up.
##
## THE TWO-WAY BINDING IS THE POINT OF THIS CLASS. update_from_ray() (the mouse) and
## set_values() (the inspector's four numeric fields) write the SAME four numbers and both
## emit ghost_moved. Whichever side did not originate the change updates from the signal.
## The loop that would otherwise form - field -> set_values -> ghost_moved -> field ->
## set_values - is broken by the _emitting re-entrancy flag, NOT by disconnecting signals.
## A re-entrant call still STORES its value (so nothing is silently dropped); it only
## declines to emit again. Disconnect/reconnect is how you get a field that quietly stops
## updating three edits later, which is why it is banned here.
##
## ANGULAR SNAPPING HAPPENS AT INPUT TIME (SPEC section 6). Every value is quantized inside
## _apply_values() before it is stored, so what is stored is exactly what is displayed and
## exactly what commits. Nothing downstream may round for display. Each angular axis snaps
## independently and `snap_deg <= 0.0` means off. The ONE exception is a value derived from
## a typed snap target, which goes through _store_values() unquantized - see _try_snap().
##
## RETIRED(2026-08-31): Shift as the momentary snap bypass -> Shift is now the horizontal
## drag modifier (API_CONTRACT_SPORE section 8, from the official manual), and ShipView3D no
## longer routes it here. set_snap_bypass() itself is unchanged and still works; it simply
## has no key bound to it until one is chosen.
##
## WHY THE DRAG IS A SURFACE HIT AND NOT A MOUSE DELTA (SPEC section 3). Angular input is
## non-linear across a face: near a box corner half a degree of yaw walks the anchor a
## couple of centimetres, mid-face it walks it metres. Mapping mouse pixels onto yaw/pitch
## therefore makes a box feel like it has ice patches. So the drag does the opposite: it
## raycasts the pointer into the scene, takes the point where it lands on the parent's
## COLLIDER, converts that point into the parent's local frame, and solves BACK to
## (yaw, pitch) with ShipAttach.angles_from_direction(). The mouse is tracking a real
## surface position, so linear-on-the-surface feel comes out for free and every stored
## number stays exactly the four the contract defines.
##
## The physics query cannot run here: a direct space state is only valid inside a physics
## frame, and this class is a RefCounted with no viewport. ShipView3D owns the query (it
## already picks that way) and hands it over as the surface probe Callable, calling
## update_from_ray() from its _physics_process. That also keeps this file free of any
## DisplayServer / global-mouse dependency, which SPEC section 10 forbids outright.
##
## WHERE THE SURFACE SOLVE DEGRADES, honestly:
##   - the collider is a CONVEX HULL of the preview mesh, not the SDF surface, so on a
##     ribbed or twisted shape the hit point is near, not on, the real surface. Only the
##     DIRECTION is used, and the anchor still comes from the exact ShipAttach trace, so
##     the ghost lands on the true surface either way.
##   - a torus (origin_inside = false) traces INWARD and takes the first crossing, which
##     may be the far side of the ring from the point the pointer actually hit. The ghost
##     can therefore hop across the hole. The stored numbers stay exact.
##   - any direction that maps to two surface points resolves to one of them
##     deterministically, so a drag across a self-occluding feature snaps rather than
##     sliding.
##   - when the ray hits nothing, _analytic_direction() falls back to the bounding sphere
##     (SPEC's analytic path via ShipAttach.trace_surface). That feel is spherical, not
##     surface-linear - it is the degraded mode, used only off-surface.
##
## SNAPPING TO TYPED TARGETS (API_CONTRACT_SPORE section 1 and 8, SPORE_CLONE_SPEC section 3
## step 4) is the single biggest change to how this class feels, and it is the answer to
## "very nice start, but very clunky to use". The surface solve above is exact and still
## wrong as a DEFAULT, because Spore does not place at the raw cursor: every drop is pulled
## to a typed target - the parent's centre, an authored snap vector, or the editor
## centreline. A player-authored description of the feel, quoted in the spec: parts "snap to
## a point located on the centre of a part's face... as if other parts will be attracted to
## imaginary lines crossing the centre of the original part."
##
## So the drag now runs the surface solve FIRST and then asks SnapTargets.nearest() whether
## the point it landed on is within ShipConfig.snap_tolerance_m of a real target on the
## hovered parent. In range, the ghost jumps to that target exactly, the target's id is
## stored on the part, and yaw/pitch become DERIVED values (ShipAttach.angles_for_target).
## Out of range, nothing is stored, snap_id stays "" and the free-surface path is used
## unchanged. Both paths commit, both paths save, and ShipAttach.local_transform() is the
## one router that decides which a stored part uses.
##
## The typed path (set_values, the inspector's four fields) always CLEARS the snap. Typing a
## yaw is an explicit statement that this part is not on a target, and silently re-snapping
## the number the player just typed is the exact behaviour that makes a numeric field feel
## broken.
##
## THE SPORE INPUT GRAMMAR (API_CONTRACT_SPORE section 8) lives here as five verbs plus a
## drag mode, because the view must not hold interaction state of its own: ShipView3D
## decides which physical input happened, this class decides what it means. Every verb
## works whether or not a ghost is up - with a ghost it edits the ghost, without one it
## edits the selection through the builder's edit protocol - so the same wheel notch scales
## the part the player is looking at either way.
##
## EVERY VERB THAT TOUCHES THE DOCUMENT CANCELS THE PLACEMENT FIRST. That is not tidiness:
## ShipBuilder.commit_edit() re-enters _refresh_view(), which on a topology change calls
## ShipView3D.rebuild() -> ShipSceneBuilder.clear_scene() -> hide_ghost(). A ghost left up
## across that call is destroyed in the scene while this object still believes it is live,
## and nothing puts it back. cancel() first makes the teardown explicit and observable
## through placement_cancelled.
class_name ShipPlacement
extends RefCounted

## The four numbers changed, from either input path. Always carries the STORED (snapped)
## values, never a raw one.
signal ghost_moved(yaw: float, pitch: float, rot: Vector3, offset: float)
## Validity of the pending placement changed. `reason` is "" when valid, and a short
## uppercase console string when not.
signal ghost_validity_changed(is_valid: bool, reason: String)
## The edit protocol accepted the placement. Carries the new or moved part id.
signal placement_committed(part_id: String)
## The placement ended without an edit. Every listener must drop its ghost here.
signal placement_cancelled
## The gizmo set changed - Tab was pressed or released, or the part it belongs to changed.
## `part_id` is "" when nothing owns handles right now.
## RETIRED(2026-08-31): signal handles_changed(part_id, advanced) -> removed with the Tab-gated
## handle set. It carried a THIRD copy of a flag that already lived on ShipView3D and
## ShipSceneBuilder, with a different default, and re-broadcasting it is what silently reset
## the other two. See ShipHandles' class docs.
## The ghost's UI state changed. `state` is a GhostState value.
signal ghost_state_changed(state: int)

## The selection gizmo's parts (API_CONTRACT_SPORE section 8). ShipHandles produces these
## codes from its screen-space hit test; this class never draws them and never projects
## anything, it only says what a drag on one MEANS.
## OFFSET is APPENDED, never inserted: the numbers are the handle codes ShipHandles returns
## and API_CONTRACT_SPORE section 8 pins the existing five.
## PLACEMENT is the parent-side handle: the arrow drawn from the PARENT's origin out to the
## anchor this part sits on. Appended, never inserted - API_CONTRACT_SPORE section 8 pins the
## numbers of the values before it, and a renumber would silently repoint every stored comparison.
enum Handle { NONE, BALL_ROTATE, RING_X, RING_Y, RING_Z, MORPH, OFFSET, PLACEMENT }

## What a drag currently moves (API_CONTRACT_SPORE section 8, from the official manual).
##
##   FREE       - the default. Drag across the ship; the ghost re-targets onto whatever part
##                is under the pointer and snaps to that part's typed targets.
##   VERTICAL   - Ctrl. Only `offset` changes, so the part slides along its own mount axis
##                and OFF the surface. This is our reading of Spore's "move the part
##                vertically, may float in mid-air": the four-number attach model has
##                exactly one axis a part can leave its parent along, and it is the mount
##                normal, not world +Y. A part parked at a positive offset hangs in space
##                exactly as Spore's does; it just keeps its parent link while doing it.
##   HORIZONTAL - Shift. Drag across the CURRENT parent's surface only; the ghost will not
##                jump to another parent and `offset` is held. Spore's "move horizontally
##                across the dais" with our surface in place of the dais.
##   WHOLE_SHIP - Shift with nothing selected. Declared by the contract and accepted here,
##                but there is nothing to translate: ShipAttach places the document root at
##                Transform3D.IDENTITY by construction, so ship space IS the root's frame
##                and the ship cannot move within it. Wiring this to the camera instead
##                would re-introduce exactly the pan that section 8 says to delete. Left as
##                a documented no-op rather than a fake one - see the report.
enum DragMode { FREE, VERTICAL, HORIZONTAL, WHOLE_SHIP }

## Mirrors Spore's `eBlockUIState` (API_CONTRACT_SPORE section 8). The five states are
## VERIFIED to exist; their exact visual treatment in Spore is not (SPORE_CLONE_SPEC section
## 3 step 2), so the MEANING is pinned here and ShipSceneBuilder chooses the colour:
##
##   DEFAULT      legal, and sitting on a typed snap target - the good drop.
##   GHOST        legal, but free on the surface with no target in range.
##   BAD_LOCATION structurally impossible here: nothing under the pointer, no parent, or a
##                validator error that is about WHERE this is rather than what it costs.
##   PREVENT      a gate refuses it - complexity or a physical budget. The click will be
##                refused, and validity_reason() carries the gate's own message verbatim.
##   INVALID      there is nothing placeable at all: no document, or a family that will not
##                resolve to a shape.
##
## Ordered by precedence in _refresh_validity(): INVALID, BAD_LOCATION, PREVENT, then the
## two legal states.
enum GhostState { DEFAULT, INVALID, GHOST, BAD_LOCATION, PREVENT }

## Edit labels, so undo reads correctly in the history stack.
const LABEL_PLACE: String = "place part"
const LABEL_MOVE: String = "move part"
const LABEL_CLONE: String = "clone part"
const LABEL_SCALE: String = "scale part"
const LABEL_ROTATE: String = "rotate part"
const LABEL_OFFSET: String = "offset part"
const LABEL_MORPH: String = "morph part"
const LABEL_SKEW: String = "skew part"
const LABEL_SYMMETRY: String = "break symmetry"
const LABEL_DRAG_OFF: String = "remove part"

## One wheel notch multiplies a part's scale by this (or divides it, scrolling the other
## way). 8% is small enough to aim with and large enough that a full palette-to-hull resize
## is a second of scrolling rather than a minute.
const SCALE_STEP: float = 1.08

## Degrees of roll per pixel of horizontal drag on a rotation handle. A 360 degree spin is
## then a ~640 px drag, which is a comfortable sweep at the builder's 1280 px virtual width.
## Degrees of rotation per pixel of a gizmo drag, on whichever mount-frame axis the grabbed
## handle drives (ADR 0004).
const ROT_DEG_PER_PIXEL: float = 0.56

## Metres of standoff one pixel of offset-handle drag adds. Small: `offset` is the difference
## between a part sitting flush and a part floating, and that reads at centimetre scale.
## Lean per pixel of sideways drag. An eighth of the authored +/-0.8 range across a 200 px pull,
## which puts the whole range inside one comfortable gesture without making a stray pixel visible.
const SKEW_PER_PIXEL: float = 0.001

const OFFSET_M_PER_PIXEL: float = 0.01

## Fraction of a part's size one pixel of morph-handle drag adds along that axis.
const MORPH_PER_PIXEL: float = 0.004

## Below this a morph axis is not pointing anywhere and the drag is ignored.
const MIN_AXIS: float = 0.5

## Two lines are treated as parallel below this, and a vertical drag holds its offset
## instead of solving a division by nearly zero.
const MIN_LINE_DENOM: float = 1.0e-6

## Reported when commit_edit() rolled the edit back (SPEC section 8: budget enforcement is
## a hard block on edits that increase usage).
const REASON_REFUSED: String = "EDIT REFUSED BY BUDGET GUARD"
const REASON_NO_DOC: String = "NO DOCUMENT"
const REASON_NO_PARENT: String = "NO PARENT PART"
const REASON_NO_SHAPE: String = "FAMILY WILL NOT RESOLVE TO A SHAPE"

## Dragged clear of the SHIP - see _pointer_off_ship() for what "clear" means. A NEW part
## has nowhere to land; an EXISTING one is about to be deleted, which is Spore's
## drag-off-the-creation removal (SPORE_CLONE_SPEC section 2). Both are BAD_LOCATION, and
## both say so before the button comes up.
const REASON_OFF_SHIP: String = "NOTHING UNDER THE POINTER - DRAG ONTO A PART"
const REASON_OFF_SHIP_REMOVE: String = "RELEASE OFF THE SHIP TO REMOVE THIS PART"

## How far past the ship's bounds the pointer ray must pass before a drag counts as OFF the
## ship: the larger of this many metres and this fraction of the ship's longest axis. The
## ship, not the colliders - see _pointer_off_ship().
const OFF_SHIP_MARGIN_M: float = 0.75
const OFF_SHIP_MARGIN_FRACTION: float = 0.25

## Below this a direction is noise and the previous one is kept.
const MIN_DIR_LENGTH_SQ: float = 1.0e-12

## Probe result keys. The probe is supplied by ShipView3D; these are its contract.
const PROBE_HIT: String = "hit"
const PROBE_POINT: String = "point"
const PROBE_PART: String = "part"

## Angular snap step in degrees; 0.0 is off. Seeded from ShipConfig.snap_deg by setup()
## and owned by the inspector's snap selector afterwards (0.1 / 0.5 / 1 / 5 / 15 / off).
var snap_deg: float = 0.5

## Linear snap step in metres for `offset`; 0.0 is off. Seeded from ShipConfig.snap_m.
var snap_m: float = 0.05

## The part the ghost is attaching to. Re-targeted live when the pointer crosses onto
## another part, which is what makes placement feel Spore-ish rather than modal.
var target_parent: String = ""

## True between begin()/begin_move() and commit()/cancel(). A ghost is up exactly then.
var active: bool = false

var _builder: ShipBuilder = null
var _probe: Callable = Callable()

## What the pending part IS: ShipPart.KIND_PRIMITIVE for a catalogue family, or
## KIND_COMPONENT_INSTANCE when `_family_id` names a saved component instead. A component has
## no manufacturer and no shape params of its own - it resolves through its definition's root
## part (ShipAttach._component_proxy_shape) - so both are left empty for one.
var _kind: String = ShipPart.KIND_PRIMITIVE
var _family_id: String = ""
var _manufacturer_id: String = ""
var _params: Dictionary = {}
var _part_scale: Vector3 = Vector3.ONE
## "" when placing a new part; the part id when re-placing an existing one.
var _moving_id: String = ""
## Ids the surface probe must not target: the moving part and its subtree.
var _blocked: PackedStringArray = PackedStringArray()

var _yaw: float = 0.0
var _pitch: float = 0.0
## Orientation in the mount frame, degrees per axis (ADR 0004). z spins about the surface
## normal - the old scalar `roll`; x and y tilt the part off that normal.
var _rot: Vector3 = Vector3.ZERO
var _offset: float = 0.0

var _snap_bypass: bool = false
var _emitting: bool = false
var _in_commit: bool = false

var _shape: ResolvedShape = null
var _scratch: ShipPart = ShipPart.new()
var _shapes: Dictionary = {}
var _xforms: Dictionary = {}
var _preview: Transform3D = Transform3D.IDENTITY
## Union of every part that is NOT moving, in ship space. The live budget preview merges
## the ghost into this instead of re-resolving the whole document per drag frame.
var _base_bbox: AABB = AABB()
var _base_seeded: bool = false
## The ghost's own AABB plus, when re-placing, its descendants' AABBs expressed in the
## ghost's local frame - a moved subtree travels rigidly with its root.
var _ghost_boxes: Array[AABB] = []
## Id the ghost carries inside the trial document used for validation.
var _trial_id: String = ""

## The typed target the ghost is currently pulled to; "" is the free-surface path. Stored on
## the part at commit and read back by ShipAttach.local_transform().
var _snap_id: String = ""
## The UNSCALED SnapTargets dictionary behind `_snap_id`, cached so the per-frame preview
## does not regenerate the parent's whole target array (which costs a Newton projection per
## target). Re-derived whenever the parent or its shape changes, never per drag frame.
var _snap_target: Dictionary = {}
## The current parent's targets in SHIP space, index-aligned with `_snap_ids`, so the view
## can draw every candidate and highlight the live one without re-deriving anything. The
## parent does not move during a drag, so this is a cache with one invalidation point.
var _snap_points: PackedVector3Array = PackedVector3Array()
var _snap_ids: PackedStringArray = PackedStringArray()

var _drag_mode: int = DragMode.FREE
var _ghost_state: int = GhostState.DEFAULT
## True when the pointer ray is clear of the SHIP - not merely of every collider. See
## _pointer_off_ship() and REASON_OFF_SHIP.
var _off_ship: bool = false

## The last FULL gate result (complexity plus the physical budgets), from the idle re-check.
## Sticky between re-checks on purpose: volume, weight and cost do not depend on where the
## ghost is, so a refusal for one of them stays true while the pointer moves, and the one
## budget that DOES move with the pointer - the bounding box - is re-checked exactly per
## frame by _budget_reason(). Cleared on begin, on cancel and on a document change.
var _metrics_reason: String = ""

var _valid: bool = true
var _reason: String = ""
## Non-empty when ShipValidate rejects the placement for a reason that does not depend on
## the four numbers (unknown family, missing parent, a cycle). Recomputed on begin, on a
## parent re-target and on a document change - never per drag frame.
var _static_reason: String = ""


## Bind to the application root. Snap steps are seeded from the config exactly once; the
## inspector owns them from then on, so a re-begin never clobbers the player's choice.
func setup(builder: ShipBuilder) -> void:
	_builder = builder
	var cfg: ShipConfig = _config()
	if cfg != null:
		snap_deg = cfg.snap_deg
		snap_m = cfg.snap_m


## Install the surface probe. ShipView3D supplies it, because only the view can run a
## physics query and only inside a physics frame:
## `probe(origin: Vector3, dir: Vector3, blocked: PackedStringArray) -> Dictionary`
## returning { "hit": bool, "point": Vector3 (ship space), "part": String }.
func set_surface_probe(probe: Callable) -> void:
	_probe = probe


# ---------------------------------------------------------------- lifecycle


## Start placing a NEW primitive under `parent_id`. Any placement already in flight is
## cancelled first, so a second palette click can never leave two ghosts up.
func begin(
	family_id: String,
	manufacturer_id: String,
	parent_id: String,
	kind: String = ShipPart.KIND_PRIMITIVE
) -> void:
	cancel()
	if _builder == null or family_id == "":
		return
	var doc: ShipDoc = _doc()
	if doc == null:
		return
	_kind = kind
	_family_id = family_id
	if _kind == ShipPart.KIND_COMPONENT_INSTANCE:
		# `family_id` is a component id here. Its geometry comes from its definition, so there is
		# no manufacturer to narrow and no param set to seed.
		_manufacturer_id = ""
		_params = {}
	else:
		_manufacturer_id = _resolve_manufacturer(family_id, manufacturer_id)
		_params = ShapeGen.default_params(_data(), _family_id, _manufacturer_id)
	_part_scale = Vector3.ONE
	_moving_id = ""
	_blocked = PackedStringArray()
	_snap_id = ""
	_snap_target = {}
	target_parent = parent_id if doc.parts.has(parent_id) else doc.root
	active = true
	_refresh_scene_cache()
	# A fresh part starts on the parent's nose: yaw = pitch = 0 is parent-local +Z, and it
	# stands square on the surface with no user rotation applied - and sunk INTO the surface by
	# the default embed, so it is joined to the parent rather than kissing it at one point
	# (ShipAttach.default_offset). Ctrl+drag and the offset stalk move it from there.
	_scratch.yaw = 0.0
	_scratch.pitch = 0.0
	_scratch.rot = Vector3.ZERO
	var embed: float = ShipAttach.default_offset(_parent_shape(), _shape, _scratch, _config())
	_store_values(0.0, 0.0, Vector3.ZERO, embed)


## Re-place an EXISTING part. Identical machinery to begin(), seeded from the part's own
## attach record and committing a modification instead of an addition.
##
## The seed is stored WITHOUT snapping: those four numbers are what the document already
## holds, and quantizing them here would silently move a part just because the player
## started dragging it. Snapping resumes on the first actual input.
func begin_move(part_id: String) -> void:
	cancel()
	if _builder == null:
		return
	var doc: ShipDoc = _doc()
	if doc == null or not doc.parts.has(part_id):
		return
	var part: ShipPart = doc.parts[part_id]
	if part.locked or part.is_mirror() or part_id == doc.root:
		return
	_kind = part.kind
	_family_id = part.family
	_manufacturer_id = part.manufacturer
	_params = part.params.duplicate(true)
	_part_scale = part.scale
	_moving_id = part_id
	_blocked = PackedStringArray([part_id])
	_blocked.append_array(doc.descendants_of(part_id))
	# Seeded BEFORE _refresh_scene_cache(), which resolves the id against the parent's real
	# shape and drops it if that family no longer carries the target. A part that was snapped
	# stays snapped through a move; one that was not, is not silently snapped by being moved.
	_snap_id = part.snap_id
	_snap_target = {}
	target_parent = part.parent
	active = true
	_refresh_scene_cache()
	_store_values(part.yaw, part.pitch, part.rot, part.offset)


## End the placement with no edit. Idempotent, and the ONLY teardown path other than a
## successful commit - every listener drops its ghost on placement_cancelled.
func cancel() -> void:
	if not active:
		return
	_reset()
	placement_cancelled.emit()


# ---------------------------------------------------------------- input paths


## Mouse path. `origin` and `dir` are in SHIP space (which is world space inside the 3D
## viewport). Call this from a physics frame: the surface probe runs a space-state query.
##
## Three drag modes reach here (see DragMode). VERTICAL never touches the angles at all -
## it solves the pointer onto the mount axis and writes `offset`. FREE and HORIZONTAL share
## the surface solve and differ only in whether the ghost may jump to another parent.
func update_from_ray(origin: Vector3, dir: Vector3) -> void:
	if not active:
		return
	# Nothing to translate; see DragMode.WHOLE_SHIP. Returning here rather than earlier keeps
	# the ghost exactly where it was instead of letting it drift on a drag we cannot honour.
	if _drag_mode == DragMode.WHOLE_SHIP:
		return
	var doc: ShipDoc = _doc()
	if doc == null:
		return
	var hit: Dictionary = _probe_surface(origin, dir)
	var landed: bool = bool(hit.get(PROBE_HIT, false))
	_set_off_ship(_pointer_off_ship(origin, dir, landed))
	if _drag_mode == DragMode.VERTICAL:
		_apply_rot_offset(_rot, _offset_from_ray(origin, dir))
		return
	if landed and _drag_mode != DragMode.HORIZONTAL:
		var pid: String = str(hit.get(PROBE_PART, ""))
		if pid != "" and pid != target_parent and doc.parts.has(pid):
			_retarget(pid)
	var local_dir: Vector3 = Vector3.ZERO
	if landed:
		var point: Vector3 = hit.get(PROBE_POINT, Vector3.ZERO)
		local_dir = _to_parent_local(point)
		# The whole point of the rework: a drop within tolerance of a typed target lands ON
		# it, exactly, instead of wherever the pixel happened to be (SPORE_CLONE_SPEC 3.4).
		if _try_snap(local_dir):
			return
	else:
		local_dir = _analytic_direction(origin, dir)
	if local_dir.length_squared() < MIN_DIR_LENGTH_SQ:
		# A noise frame changes NOTHING - including the snap. Clearing it here and then
		# returning would leave `_snap_id` saying "free" while `_preview`, which is only
		# rebuilt by _store_values(), still held the snapped transform.
		return
	_clear_snap()
	# The exact inverse of the direction the attach model traces along, so the anchor the
	# tracer finds is the surface point the pointer is over - SPEC section 3.
	var angles: Vector2 = ShipAttach.angles_from_direction(local_dir)
	_apply_values(angles.x, angles.y, _rot, _offset)


## Numeric path. The inspector's four fields land here; snapping and wrapping are applied
## exactly as they are for the mouse, so the two inputs cannot disagree.
##
## Typing a number CLEARS the typed-target snap. A yaw the player entered by hand is a
## statement that this part is not on a target, and re-snapping it on the next frame is how
## a numeric field comes to feel broken.
func set_values(yaw: float, pitch: float, rot: Vector3, offset: float) -> void:
	if not active:
		return
	_clear_snap()
	_apply_values(yaw, pitch, rot, offset)


## Suspend snapping while a modifier is held (SPEC section 6).
func set_snap_bypass(on: bool) -> void:
	_snap_bypass = on


# ---------------------------------------------------------------- readers


func values() -> Dictionary:
	return {"yaw": _yaw, "pitch": _pitch, "rot": _rot, "offset": _offset}


## The ghost's transform in SHIP space. Cached: it is recomputed once per value change,
## not once per reader, because it costs a sphere trace.
func preview_transform() -> Transform3D:
	return _preview


## The shape the ghost renders with - the very same ResolvedShape the committed part will
## use, so the preview cannot disagree with the result.
func ghost_shape() -> ResolvedShape:
	return _shape


## "" while placing a new part; the part id while re-placing one.
func moving_part_id() -> String:
	return _moving_id


func is_valid() -> bool:
	return _valid


func validity_reason() -> String:
	return _reason


## The ghost's UI state - a GhostState value. Drives the ghost's colour, and it is a finer
## signal than is_valid(): DEFAULT and GHOST are both legal but only one is on a target.
func ghost_state() -> int:
	return _ghost_state


## The typed target the ghost is on, or "" on the free-surface path.
func snap_id() -> String:
	return _snap_id


## Everything the view needs to show WHICH target is live, in one read:
## [codeblock]
## "points": PackedVector3Array   # every target on the hovered parent, in SHIP space
## "live":   int                  # index into `points`, or -1 when nothing is snapped
## [/codeblock]
## Both come from a cache rebuilt only when the parent or its shape changes, so calling this
## once per ghost redraw costs nothing.
func snap_preview() -> Dictionary:
	var live: int = -1
	if _snap_id != "":
		for i: int in _snap_ids.size():
			if _snap_ids[i] == _snap_id:
				live = i
				break
	return {"points": _snap_points, "live": live}


# ---------------------------------------------------------------- the Spore grammar


## The part the gizmo belongs to: the one being re-placed while a move is live, otherwise
## the first selected part. "" when nothing owns handles.
func handle_part_id() -> String:
	if _moving_id != "":
		return _moving_id
	var ids: PackedStringArray = _selection()
	return ids[0] if not ids.is_empty() else ""


## Ctrl / Shift. `mode` is a DragMode value; an unknown value falls back to FREE rather than
## leaving the drag in a mode nothing implements.
func set_drag_mode(mode: int) -> void:
	var next: int = mode
	if next < DragMode.FREE or next > DragMode.WHOLE_SHIP:
		next = DragMode.FREE
	_drag_mode = next


## Plain mouse wheel, and the Up/Down arrows. `delta` is in notches: +1 grows, -1 shrinks.
##
## With a ghost up this resizes the GHOST and never touches the document, so the player can
## size a part before committing it - which is also what keeps the wheel from tearing the
## ghost down through commit_edit(). With no ghost it resizes every selected part through
## the edit protocol.
func scale_selected(delta: float) -> void:
	if is_zero_approx(delta):
		return
	var factor: float = pow(SCALE_STEP, delta)
	if active:
		_part_scale = _clamp_scale(_part_scale * factor)
		_rebuild_ghost_shape()
		return
	var doc: ShipDoc = _doc()
	if doc == null or _builder == null:
		return
	var ids: PackedStringArray = _editable_selection(doc)
	if ids.is_empty():
		return
	_builder.begin_edit(LABEL_SCALE)
	for pid: String in ids:
		var part: ShipPart = doc.parts[pid]
		part.scale = _clamp_scale(part.scale * factor)
	_builder.commit_edit(ids)


## A rotation handle drag. `axis` is 0/1/2 for the mount frame X/Y/Z; anything else spins the
## normal axis, which is what the free "ball" handle does.
##
## RETIRED(ADR 0004, 2026-08-31): rotate_selected(delta_deg) -> rotate_selected(axis, delta_deg).
## The attach model used to store ONE user rotation, about the mount normal, so all three rings
## drove the same number and the advanced handles felt inert however you dragged them.
## [member ShipPart.rot] is a Vector3 now and each ring drives its own component.
## `absolute` SETS the axis to `deg` instead of adding to it, which is what the middle key of
## each numpad row does: 8 stands the part up again about X, 5 about Y, 2 about Z. A part nudged
## half a degree at a time otherwise has no way back to square except by counting, and that is the
## thing the key exists to remove. A trailing optional argument, so every existing call site is
## the relative form it always was.
func rotate_selected(axis: int, deg: float, absolute: bool = false) -> void:
	if is_zero_approx(deg) and not absolute:
		return
	var component: int = axis if axis >= 0 and axis <= 2 else Vector3.AXIS_Z
	if active:
		var next: Vector3 = _rot
		next[component] = deg if absolute else next[component] + deg
		_apply_rot_offset(next, _offset)
		return
	var doc: ShipDoc = _doc()
	if doc == null or _builder == null:
		return
	var ids: PackedStringArray = _editable_selection(doc)
	if ids.is_empty():
		return
	_builder.begin_edit(LABEL_ROTATE)
	for pid: String in ids:
		var part: ShipPart = doc.parts[pid]
		var value: Vector3 = part.rot
		value[component] = deg if absolute else ShipAttach.wrap_yaw_deg(value[component] + deg)
		part.rot = value
	_builder.commit_edit(ids)


## RETIRED(2026-09-01): step_snap_target() and aim_selection() -> harness/builder/
## ship_reseat.gd. Both are document-only: a live ghost has no committed snap_id to step from
## and no stored rot to aim, so neither ever touched this class's state. See ShipReseat's
## class docs for the seam.


## Mount-frame axis index a Handle value drives: RING_X/Y/Z -> 0/1/2. The free ball spins about
## the normal (Z), the gesture a surface-mounted part can always make.
static func axis_for_handle(handle: int) -> int:
	match handle:
		Handle.RING_X:
			return Vector3.AXIS_X
		Handle.RING_Y:
			return Vector3.AXIS_Y
		_:
			return Vector3.AXIS_Z


## An offset-handle drag: slide the part along its parent's surface normal.
##
## `offset` was reachable only by typing a number into the inspector or by holding Ctrl during a
## placement drag, so a selected part had no way to be pulled off its parent by hand at all -
## reported as "i see no handles that stretch and pull offset and rotate". This is the same verb
## the Ctrl+drag does, bound to a handle.
func offset_selected(delta_m: float) -> void:
	if is_zero_approx(delta_m):
		return
	if active:
		_apply_rot_offset(_rot, _offset + delta_m)
		return
	var doc: ShipDoc = _doc()
	if doc == null or _builder == null:
		return
	var ids: PackedStringArray = _editable_selection(doc)
	if ids.is_empty():
		return
	_builder.begin_edit(LABEL_OFFSET)
	for pid: String in ids:
		var part: ShipPart = doc.parts[pid]
		part.offset = part.offset + delta_m
	_builder.commit_edit(ids)


## A morph handle drag. `axis` is a part-local direction from ShipHandles.morph_axis();
## `delta` is the drag in pixels along it.
##
## Spore's morph handles are free deformations of an authored mesh. Ours are the same
## gesture against a procedural shape: the six handles sit on the six faces of the part's
## local AABB, and dragging one stretches the part along that ONE axis. That is a real
## non-uniform deform, expressed in the per-axis `scale` the shape already has, and it needs
## no new stored field.
func morph_selected(axis: Vector3, delta: float) -> void:
	var component: int = _dominant_axis(axis)
	if component < 0 or is_zero_approx(delta):
		return
	var factor: float = 1.0 + delta * MORPH_PER_PIXEL * signf(axis[component])
	if factor <= 0.0:
		return
	if active:
		var next: Vector3 = _part_scale
		next[component] = next[component] * factor
		_part_scale = _clamp_scale(next)
		_rebuild_ghost_shape()
		return
	var doc: ShipDoc = _doc()
	if doc == null or _builder == null:
		return
	var ids: PackedStringArray = _editable_selection(doc)
	if ids.is_empty():
		return
	_builder.begin_edit(LABEL_MORPH)
	for pid: String in ids:
		var part: ShipPart = doc.parts[pid]
		var s: Vector3 = part.scale
		s[component] = s[component] * factor
		part.scale = _clamp_scale(s)
	_builder.commit_edit(ids)


## SKEW: drags the selection's lean along one local axis. The fourth of Spore's morph verbs and
## the last one this builder was missing (ADR 0007).
##
## `param` is `skew_x` or `skew_z`. Unlike scale, rotation and offset, the lean is a SHAPE PARAM,
## not a field on the part record - a shear is a domain warp in the generator, so it lives where
## taper and twist live and it clamps through the family's own authored range like they do.
##
## Nothing happens on a family that does not enable the `skew` op: clamp_params() pins a disabled
## op's params, so writing one would be silently discarded and the handle would feel broken. It is
## refused up front instead.
func skew_selected(param: String, delta: float) -> void:
	if is_zero_approx(delta):
		return
	var doc: ShipDoc = _doc()
	if doc == null or _builder == null:
		return
	var step: float = delta * SKEW_PER_PIXEL
	if active:
		var pid_live: String = handle_part_id()
		if pid_live.is_empty():
			return
		var live: ShipPart = doc.parts.get(pid_live, null) as ShipPart
		if live == null:
			return
		live.params = _nudged_params(live, param, step)
		_rebuild_ghost_shape()
		return
	var ids: PackedStringArray = _editable_selection(doc)
	if ids.is_empty():
		return
	_builder.begin_edit(LABEL_SKEW)
	for pid: String in ids:
		var part: ShipPart = doc.parts[pid]
		part.params = _nudged_params(part, param, step)
	_builder.commit_edit(ids)


## `part.params` with one key nudged and the whole set re-clamped into the family's effective
## ranges - the same gate a typed value goes through, so a dragged lean can never leave a part in
## a state the inspector would refuse.
func _nudged_params(part: ShipPart, param: String, step: float) -> Dictionary:
	var data: ShipData = _builder.get_data()
	var out: Dictionary = part.params.duplicate(true)
	var was: float = 0.0
	if out.has(param) and (out[param] is float or out[param] is int):
		was = float(out[param])
	out[param] = was + step
	return ShapeGen.clamp_params(data, part.family, part.manufacturer, out)


## Alt on a selected part. Copies it under the same parent with the same placement, selects
## the copy and starts moving it, which is Spore's alt-drag: a duplicate peels off under the
## pointer. Returns the new id, or "" when nothing was cloned or the edit was refused.
func clone_selected() -> String:
	var doc: ShipDoc = _doc()
	if _builder == null or doc == null:
		return ""
	var ids: PackedStringArray = _selection()
	if ids.is_empty() or not doc.parts.has(ids[0]):
		return ""
	var source: ShipPart = doc.parts[ids[0]]
	# A legacy mirror derivative has no placement of its own to copy, and the root has no
	# parent to copy either - a cloned root would land parentless, which is legal by
	# API_CONTRACT_SPORE section 2 but is a `orphan_part` error to ShipValidate today. Both
	# refuse quietly rather than producing a part the validator will immediately condemn.
	if source.is_mirror() or source.parent == "":
		return ""
	# commit_edit() rebuilds the view, which destroys any ghost in the scene. Tear ours down
	# first so the teardown is announced instead of discovered.
	cancel()
	var copy: ShipPart = source.duplicate_part()
	# duplicate_part() keeps the source id on purpose (ids are never reused), so the copy has
	# to be un-identified before the document can name it.
	copy.id = ""
	_builder.begin_edit(LABEL_CLONE)
	var new_id: String = doc.add_part(copy)
	if new_id == "":
		return ""
	_builder.commit_edit(PackedStringArray())
	var after: ShipDoc = _builder.get_doc()
	if after == null or not after.parts.has(new_id):
		return ""
	_builder.set_selection(PackedStringArray([new_id]))
	begin_move(new_id)
	return new_id


## Hold A while selecting. Breaks symmetry on the selection, CASCADING to every descendant -
## ShipSymmetry.set_asymmetric() returns exactly the ids whose effective state changed, and
## those are what the view repaints.
func break_symmetry_selected() -> void:
	if _builder == null:
		return
	var doc: ShipDoc = _doc()
	if doc == null:
		return
	var ids: PackedStringArray = _selection()
	if ids.is_empty():
		return
	cancel()
	# Mutating BEFORE begin_edit() is safe and deliberate here: begin_edit() only records a
	# label (it snapshots nothing - the history head already holds the pre-edit document),
	# and set_asymmetric() returns an empty array precisely when it changed nothing, so an
	# empty result means there is no edit to announce rather than an edit half-announced.
	var changed: PackedStringArray = PackedStringArray()
	for pid: String in ids:
		changed.append_array(ShipSymmetry.set_asymmetric(doc, pid, true))
	if changed.is_empty():
		return
	_builder.begin_edit(LABEL_SYMMETRY)
	# Empty changed_ids: twins appear and disappear, so the whole scene has to be diffed.
	_builder.commit_edit(PackedStringArray())


## Spore's drag-off-the-creation removal. Deletes the part being re-placed when the pointer
## is clear of the ship (_pointer_off_ship); returns true when it did, so the caller can fall
## through to commit() when it did not. A NEW part is never removed this way - there is
## nothing to remove yet, and the placement simply refuses to land.
##
## The CALLER decides whether the release may remove at all. Only a plain surface drag may:
## a gizmo release - a ring, the offset stalk, a morph arrow, the placement arrow - has been
## editing numbers, not carrying the part somewhere, and a part that vanishes at the end of
## a rotation reads as a bug, not as a gesture. That was FOLLOWUPS F13.
func remove_if_dragged_off() -> bool:
	if not active or _moving_id == "" or not _off_ship or _builder == null:
		return false
	var doc: ShipDoc = _doc()
	if doc == null or not doc.parts.has(_moving_id):
		return false
	var doomed: String = _moving_id
	cancel()
	_builder.begin_edit(LABEL_DRAG_OFF)
	doc.remove_part(doomed)
	_builder.commit_edit(PackedStringArray())
	return true


## The FULL gate, including the physical budgets - the idle half of the two-tier check
## described on `_metrics_reason`. Costs a sampling grid through ShipSdf, so it must never
## be called from a drag frame; ShipView3D runs it on an idle timer, exactly as the gauge
## strip does.
func recheck_gate_with_metrics() -> void:
	if not active:
		return
	var data: ShipData = _data()
	var cfg: ShipConfig = _config()
	var trial: ShipDoc = _trial_doc()
	if trial == null or data == null or cfg == null:
		return
	var sdf: ShipSdf = ShipSdf.build(trial, data, cfg)
	var metrics: ShipMetrics = ShipMetrics.compute(sdf, trial, data, cfg)
	var result: Dictionary = ShipGate.check_doc(trial, data, cfg, metrics)
	_metrics_reason = "" if bool(result.get("ok", true)) else str(result.get("message", ""))
	_refresh_validity()


# ---------------------------------------------------------------- commit


## Push the placement through the edit protocol and NOTHING else.
##
## SPEC section 8: commit_edit() runs the budget guard and may REFUSE and roll the document
## back. It returns nothing, so a refusal is detected by reading the document back: on a
## rollback the builder swaps in the pre-edit snapshot, which does not carry the new id (or
## still carries the old attach values). A refusal is never swallowed - the ghost stays up,
## "" comes back, and ghost_validity_changed says why.
func commit() -> String:
	if not active or _builder == null:
		return ""
	var doc: ShipDoc = _doc()
	if doc == null:
		_set_validity(false, REASON_NO_DOC, GhostState.INVALID)
		return ""
	if not _valid:
		# The ghost has been showing this refusal since before the click (that is the whole
		# mitigation for having two hard gates), so do not spend an edit rediscovering it.
		# Re-emitted unconditionally: _set_validity() is silent when nothing changed, and a
		# second click on the same bad spot must still put the message back on the status bar.
		_emit_validity()
		return ""
	# commit_edit() emits doc_changed; the guard stops notify_doc_changed() tearing our own
	# caches down mid-commit. They are rebuilt explicitly below, refusal or not.
	_in_commit = true
	var placed_id: String = _commit_move(doc) if _moving_id != "" else _commit_new(doc)
	_in_commit = false
	if placed_id == "":
		# A refusal rolls the document back, and the builder's rollback path is a FULL view
		# rebuild - which tears the ghost down through clear_scene(). notify_doc_changed()
		# was suppressed for the duration of the commit, so nothing else will put it back.
		# _set_validity() alone is not enough: it stays silent when the reason has not
		# changed (a second click on the same over-budget spot), so re-emit unconditionally.
		_refresh_scene_cache()
		_recompute_preview()
		_set_validity(false, REASON_REFUSED, GhostState.PREVENT)
		_emit_validity()
		_emit_moved()
		return ""
	_reset()
	placement_committed.emit(placed_id)
	return placed_id


## The document changed under us - an undo, an open, another panel's edit. Refresh what we
## cached from it, and cancel outright when the ghost has nothing left to attach to, so a
## ghost can never outlive the part it was pointing at.
func notify_doc_changed(_changed: ShipDoc) -> void:
	if not active or _in_commit:
		return
	var doc: ShipDoc = _doc()
	if doc == null or not doc.parts.has(target_parent):
		cancel()
		return
	if _moving_id != "" and not doc.parts.has(_moving_id):
		cancel()
		return
	_refresh_scene_cache()
	_store_values(_yaw, _pitch, _rot, _offset)


# ---------------------------------------------------------------- value plumbing


## Snap, then store. Every input path goes through here; nothing writes the four numbers
## directly (SPEC section 6: quantize at input time, never in the display layer).
func _apply_values(yaw: float, pitch: float, rot: Vector3, offset: float) -> void:
	_store_values(_snap_angle(yaw), _snap_angle(pitch), _snap_rot(rot), _snap_linear(offset))


## Write rotation and offset through the quantizer while leaving yaw and pitch untouched.
##
## A snapped part's yaw/pitch are DERIVED from its target, and pushing them back through the
## 0.5 degree angular snap on every vertical drag or handle spin would walk them a little
## further off the target each frame. The two verbs that change only rotation or only offset -
## Ctrl+drag and a rotation handle - go through here instead of _apply_values().
func _apply_rot_offset(rot: Vector3, offset: float) -> void:
	_store_values(_yaw, _pitch, _snap_rot(rot), _snap_linear(offset))


## Store already-quantized values, re-derive everything that depends on them, then emit.
## Validity is emitted BEFORE the move so a listener redrawing on ghost_moved already has
## the right colour.
func _store_values(yaw: float, pitch: float, rot: Vector3, offset: float) -> void:
	_yaw = ShipAttach.wrap_yaw_deg(yaw)
	_pitch = clampf(pitch, -90.0, 90.0)
	_rot = Vector3(
		ShipAttach.wrap_yaw_deg(rot.x),
		ShipAttach.wrap_yaw_deg(rot.y),
		ShipAttach.wrap_yaw_deg(rot.z)
	)
	_offset = offset
	_recompute_preview()
	_refresh_validity()
	_emit_moved()


## The re-entrancy guard. A handler that writes back into set_values() from inside this
## emit still stores its value above; it just does not start a second emit. That is what
## keeps the numeric fields and the drag bound in both directions without a disconnect.
func _emit_moved() -> void:
	if _emitting:
		return
	_emitting = true
	ghost_moved.emit(_yaw, _pitch, _rot, _offset)
	_emitting = false


## Per-component angular snap. The brief asks for "a snaping system of .5 degrees
## (changeable) for all 3 angular axises" - ONE step, applied independently to each axis.
func _snap_rot(v: Vector3) -> Vector3:
	return Vector3(_snap_angle(v.x), _snap_angle(v.y), _snap_angle(v.z))


func _snap_angle(v: float) -> float:
	if _snap_bypass or snap_deg <= 0.0:
		return v
	return roundf(v / snap_deg) * snap_deg


func _snap_linear(v: float) -> float:
	if _snap_bypass or snap_m <= 0.0:
		return v
	return roundf(v / snap_m) * snap_m


func _recompute_preview() -> void:
	var cfg: ShipConfig = _config()
	if cfg == null or _shape == null:
		_preview = Transform3D.IDENTITY
		return
	var parent_xf: Transform3D = _parent_transform()
	if _snap_id != "" and not _snap_target.is_empty():
		# The snapped path enters the attach model at SPEC 3 step 4: there is nothing to
		# trace, because the target already carries both the anchor and the outward normal.
		var snapped: Transform3D = ShipAttach.snap_transform(
			_parent_shape(), _shape, _snap_target, _rot, _offset
		)
		_preview = parent_xf * snapped
		return
	_scratch.yaw = _yaw
	_scratch.pitch = _pitch
	_scratch.rot = _rot
	_scratch.offset = _offset
	# _scratch carries no snap_id, so this is always the free-surface branch of
	# local_transform() even while the ghost is between two targets.
	var local: Transform3D = ShipAttach.local_transform(_parent_shape(), _shape, _scratch, cfg)
	_preview = parent_xf * local


# ---------------------------------------------------------------- snapping


## Pull the drop onto a typed target when the surface point is within tolerance of one.
##
## `local_point` is in the parent's SCALED local frame, which is the frame
## SnapTargets.nearest() measures its metre tolerance in and the frame the surface probe's
## hit point converts into. Returns true when the ghost was snapped, in which case the
## caller must not also run the free-surface solve.
##
## The derived angles are stored WITHOUT the angular quantizer. The target is the exact
## value; rounding it to the nearest 0.5 degrees would shift the ghost straight back off the
## point it just snapped to, which is the failure this whole mechanic exists to remove.
func _try_snap(local_point: Vector3) -> bool:
	var cfg: ShipConfig = _config()
	var shape: ResolvedShape = _parent_shape()
	if cfg == null or shape == null or cfg.snap_tolerance_m <= 0.0:
		return false
	var target: Dictionary = SnapTargets.nearest(shape, local_point, cfg.snap_tolerance_m)
	if target.is_empty():
		return false
	_snap_target = target
	_snap_id = str(target.get("id", ""))
	var angles: Vector2 = ShipAttach.angles_for_target(shape, target)
	_store_values(angles.x, angles.y, _rot, _offset)
	return true


## Back to the free-surface path. Cheap and idempotent, so the drag can call it every frame.
func _clear_snap() -> void:
	_snap_id = ""
	_snap_target = {}


## Re-resolve the cached target after the parent, or the parent's shape, changed.
##
## A stored id the parent's family no longer carries drops back to the free path rather than
## failing: the derived yaw/pitch are still on record and still point at roughly the right
## place, which is a far better degradation than the part jumping to the parent's nose.
func _resolve_snap_target() -> void:
	if _snap_id == "":
		_snap_target = {}
		return
	_snap_target = ShipAttach.snap_target(_parent_shape(), _snap_id)
	if _snap_target.is_empty():
		_snap_id = ""


## Cache every target on the current parent in SHIP space, for the view's markers. Rebuilt
## only on a re-target or a scene refresh - the parent does not move during a drag, and
## regenerating the array per frame would double the drag's cost for no new information.
func _rebuild_snap_points() -> void:
	_snap_points = PackedVector3Array()
	_snap_ids = PackedStringArray()
	var shape: ResolvedShape = _parent_shape()
	if shape == null:
		return
	var parent_xf: Transform3D = _parent_transform()
	for target: Dictionary in SnapTargets.for_shape(shape):
		var scaled: Dictionary = SnapTargets.apply_scale(target, shape.scale)
		var pos: Vector3 = scaled["local_pos"]
		_snap_points.append(parent_xf * pos)
		_snap_ids.append(str(target.get("id", "")))


# ---------------------------------------------------------------- surface solve


func _probe_surface(origin: Vector3, dir: Vector3) -> Dictionary:
	var miss: Dictionary = {PROBE_HIT: false, PROBE_POINT: Vector3.ZERO, PROBE_PART: ""}
	if not _probe.is_valid():
		return miss
	var raw: Variant = _probe.call(origin, dir, _blocked)
	if typeof(raw) != TYPE_DICTIONARY:
		return miss
	var out: Dictionary = raw
	return out


## Ship-space point -> the parent's local frame. Its direction from the parent's local
## origin is exactly what ShipAttach traces along, which is the whole trick.
func _to_parent_local(point: Vector3) -> Vector3:
	return _parent_transform().affine_inverse() * point


## Whether the pointer ray is clear of the SHIP, which is what "off the ship" has to mean
## before it is allowed to delete a part.
##
## A collider miss is NOT that. The probe ignores the part being moved and its subtree, so
## the ray misses whenever the pointer is over the moving part's own body wherever that body
## sticks out past the parent's silhouette - which is most of the time, because the pointer
## is ON the part being dragged. Deleting on that was the "random rotation / sinking makes
## the part vanish" bug (F13): every such release went through remove_if_dragged_off().
##
## So the test is against the ship's bounds - the static ship plus the ghost and its subtree
## where they are drawn this frame - grown by a margin that scales with the ship. Near the
## ship the analytic fallback carries the part round the parent's surface, exactly as it
## does over a blocked collider; only genuinely empty space is off-ship.
##
## The modifier drags never count: VERTICAL and HORIZONTAL use the pointer as a one-axis
## control, not as a place, and the pointer leaves the ship on both as a matter of course.
func _pointer_off_ship(origin: Vector3, dir: Vector3, landed: bool) -> bool:
	if landed or _drag_mode != DragMode.FREE:
		return false
	return not _ray_near_ship(origin, dir)


## The ray-versus-grown-bounds half of _pointer_off_ship(). Errs towards "near": with no
## bounds to test against there is nothing to be off of.
func _ray_near_ship(origin: Vector3, dir: Vector3) -> bool:
	var boxes: Array[AABB] = []
	if _base_seeded:
		boxes.append(_base_bbox)
	for local_box: AABB in _ghost_boxes:
		boxes.append((_preview * local_box).abs())
	if boxes.is_empty():
		return true
	var whole: AABB = boxes[0]
	for box: AABB in boxes:
		whole = whole.merge(box)
	var longest: float = maxf(whole.size.x, maxf(whole.size.y, whole.size.z))
	var margin: float = maxf(OFF_SHIP_MARGIN_M, longest * OFF_SHIP_MARGIN_FRACTION)
	for box: AABB in boxes:
		if box.grow(margin).intersects_ray(origin, dir) != null:
			return true
	return false


## The analytic fallback for when the ray hits no collider at all - the pointer is off the
## ship, or over a part that is blocked. Intersect the parent's bounding sphere in its own
## local frame and take the near hit; failing that, the closest approach of the ray to the
## parent origin. ShipAttach.trace_surface() then still lands the anchor on the real
## surface, so the numbers stay valid; only the FEEL degrades from surface-linear to
## spherical, which is the honest best available with nothing under the pointer.
func _analytic_direction(origin: Vector3, dir: Vector3) -> Vector3:
	var inv: Transform3D = _parent_transform().affine_inverse()
	var local_origin: Vector3 = inv * origin
	var local_dir: Vector3 = inv.basis * dir
	if local_dir.length_squared() < MIN_DIR_LENGTH_SQ:
		return Vector3.ZERO
	local_dir = local_dir.normalized()
	var t_close: float = -local_origin.dot(local_dir)
	var closest: Vector3 = local_origin + local_dir * maxf(t_close, 0.0)
	var radius: float = 1.0
	var parent_shape: ResolvedShape = _parent_shape()
	if parent_shape != null:
		radius = maxf(parent_shape.bound_radius, 0.001)
	var off_axis_sq: float = closest.length_squared()
	if t_close > 0.0 and off_axis_sq < radius * radius:
		var half_chord: float = sqrt(maxf(radius * radius - off_axis_sq, 0.0))
		return local_origin + local_dir * maxf(t_close - half_chord, 0.0)
	return closest


## Ctrl + drag. Solve the pointer onto the part's own mount axis and read `offset` off it.
##
## The axis is the line through the anchor along the mount normal, both in ship space; the
## drag is the closest approach between that line and the pointer ray. Solving a line rather
## than mapping pixels keeps the part under the cursor at any camera angle, and a ray nearly
## parallel to the axis (where the solution explodes) holds the current offset instead.
##
## `offset` is measured from the anchor to the child's attach FACE, so the child's origin
## sits at `offset + mount_inset()` along the axis - hence the inset coming back off `s`.
func _offset_from_ray(origin: Vector3, dir: Vector3) -> float:
	var cfg: ShipConfig = _config()
	if cfg == null or dir.length_squared() < MIN_DIR_LENGTH_SQ:
		return _offset
	var shape: ResolvedShape = _parent_shape()
	var anchor: Vector3 = Vector3.ZERO
	var normal: Vector3 = ShipAttach.direction_from_angles(_yaw, _pitch)
	if _snap_id != "" and not _snap_target.is_empty() and shape != null:
		var scaled: Dictionary = SnapTargets.apply_scale(_snap_target, shape.scale)
		anchor = scaled["local_pos"]
		normal = scaled["normal"]
	elif shape != null:
		anchor = ShipAttach.trace_surface(shape, normal, cfg)
		normal = ShipAttach.gradient(shape, anchor, cfg.gradient_eps)

	var parent_xf: Transform3D = _parent_transform()
	var axis_origin: Vector3 = parent_xf * anchor
	var axis: Vector3 = (parent_xf.basis * normal).normalized()
	var ray: Vector3 = dir.normalized()
	var b: float = axis.dot(ray)
	var denom: float = 1.0 - b * b
	if absf(denom) < MIN_LINE_DENOM:
		return _offset
	var w: Vector3 = axis_origin - origin
	var s: float = (b * ray.dot(w) - axis.dot(w)) / denom
	if not is_finite(s):
		return _offset
	var inset: float = _shape.mount_inset() if _shape != null else 0.0
	return s - inset


## Move the ghost onto another part. Cheap enough to do live, but it re-runs the static
## validation, so it is deliberately gated on the target actually changing.
##
## The snap goes with the parent: a target id is only meaningful on the shape it came from,
## and the next frame's _try_snap() re-acquires one on the new parent if there is one to
## acquire.
func _retarget(part_id: String) -> void:
	if part_id == target_parent or _is_blocked(part_id):
		return
	target_parent = part_id
	_clear_snap()
	_rebuild_snap_points()
	_static_reason = _validate_trial()


func _is_blocked(part_id: String) -> bool:
	for pid: String in _blocked:
		if pid == part_id:
			return true
	return false


# ---------------------------------------------------------------- validity


## Everything that can refuse this placement, in precedence order, resolved to one
## (valid, reason, GhostState) triple.
##
## The ORDER is the design. A player refused by an invisible rule reads the editor as broken,
## and this project runs two hard gates at once (complexity AND the physical budgets), so the
## whole mitigation is that the reason is specific and arrives BEFORE the click. Structural
## impossibility outranks affordability, because "there is nothing under the pointer" is more
## useful than "you also cannot afford it".
func _refresh_validity() -> void:
	if not active:
		return
	var reason: String = ""
	var state: int = GhostState.DEFAULT
	if _shape == null:
		reason = REASON_NO_SHAPE
		state = GhostState.INVALID
	elif _static_reason != "":
		reason = _static_reason
		state = GhostState.BAD_LOCATION
		if _static_reason == REASON_NO_DOC:
			state = GhostState.INVALID
	elif _off_ship:
		reason = REASON_OFF_SHIP_REMOVE if _moving_id != "" else REASON_OFF_SHIP
		state = GhostState.BAD_LOCATION
	else:
		reason = _refusal_reason()
		if reason != "":
			state = GhostState.PREVENT
		elif _snap_id == "":
			# Legal, but loose on the surface rather than on a typed target.
			state = GhostState.GHOST
	_set_validity(reason == "", reason, state)


## The three affordability refusals, cheapest first, as one message or "".
##
## Complexity is the cheap per-frame gate; the sticky full-gate result covers the budgets
## that do not move with the pointer; the bounding box is the one that does and is measured
## exactly, per frame, against the same per-axis caps ShipBuilder enforces at commit.
func _refusal_reason() -> String:
	var gate: String = _gate_reason()
	if gate != "":
		return gate
	if _metrics_reason != "":
		return _metrics_reason
	return _budget_reason()


## The CHEAP half of the two-tier gate: complexity only, `metrics` deliberately null, safe to
## run on every drag frame (API_CONTRACT_SPORE section 6 says so in as many words). The
## physical budgets need a sampling grid and are handled by recheck_gate_with_metrics() on
## idle, plus the exact per-frame bounding-box test in _budget_reason().
##
## Only a NEW part can trip it. Moving an existing part changes no part count and no family,
## so its complexity is identical before and after, and running the check would be pure cost.
##
## The message is the gate's own, forwarded verbatim - never summarised, never replaced with a
## generic refusal.
func _gate_reason() -> String:
	if _moving_id != "":
		return ""
	var doc: ShipDoc = _doc()
	var data: ShipData = _data()
	var cfg: ShipConfig = _config()
	if doc == null or data == null or cfg == null:
		return ""
	var symmetric: bool = not ShipSymmetry.is_effectively_asymmetric(doc, target_parent)
	var result: Dictionary = ShipGate.check_add(doc, data, cfg, _family_id, symmetric, null)
	if bool(result.get("ok", true)):
		return ""
	return str(result.get("message", ""))


func _set_validity(ok: bool, reason: String, state: int) -> void:
	var state_changed: bool = state != _ghost_state
	_ghost_state = state
	if ok == _valid and reason == _reason:
		if state_changed:
			ghost_state_changed.emit(_ghost_state)
		return
	_valid = ok
	_reason = reason
	ghost_validity_changed.emit(_valid, _reason)
	ghost_state_changed.emit(_ghost_state)


## Emit the current validity whether or not it changed. _set_validity() is deliberately
## silent on a no-op, which is right for a drag frame and wrong for a refused click: the
## second click on the same bad spot has to put the message back on the status bar.
func _emit_validity() -> void:
	ghost_validity_changed.emit(_valid, _reason)
	ghost_state_changed.emit(_ghost_state)


func _set_off_ship(value: bool) -> void:
	if value == _off_ship:
		return
	_off_ship = value
	_refresh_validity()


## The live budget preview. Deliberately the SAME comparison ShipBuilder._bbox_exceeded()
## makes at commit time (SPEC section 8: max_bbox_m is per-axis, not a diagonal), just
## computed incrementally: the static part of the ship was unioned once in
## _refresh_scene_cache(), and only the ghost's boxes are re-transformed per drag frame.
##
## For a NEW part this is exact. For a MOVE it is exact too, because a re-placed part
## carries its subtree rigidly, and _ghost_boxes holds those descendants in the ghost's own
## local frame. Mirror derivatives of a moved part are the one gap - they are M5, and they
## stay counted at their pre-move position, which over-reads rather than under-reads.
func _budget_reason() -> String:
	var cfg: ShipConfig = _config()
	if cfg == null or _ghost_boxes.is_empty():
		return ""
	var box: AABB = _base_bbox
	var seeded: bool = _base_seeded
	for local_box: AABB in _ghost_boxes:
		var world_box: AABB = (_preview * local_box).abs()
		if seeded:
			box = box.merge(world_box)
		else:
			box = world_box
			seeded = true
	if not seeded:
		return ""
	var s: Vector3 = box.size
	var cap: Vector3 = cfg.max_bbox_m
	if s.x > cap.x:
		return "BBOX X %.2f > %.2f" % [s.x, cap.x]
	if s.y > cap.y:
		return "BBOX Y %.2f > %.2f" % [s.y, cap.y]
	if s.z > cap.z:
		return "BBOX Z %.2f > %.2f" % [s.z, cap.z]
	return ""


## Run the real validator over a document that already contains the ghost, and keep the
## first BLOCKING_CODES error that is about the ghost (or about the document as a whole).
##
## budget_exceeded is not in that list because it is the one finding that moves with the
## four numbers, and _budget_reason() covers it per frame at a fraction of the cost.
## Everything else this can report - unknown family, a cycle, a missing parent - cannot
## change while the pointer moves, so this runs on begin, on re-target and on a document
## change only, never per drag frame.
func _validate_trial() -> String:
	var trial: ShipDoc = _trial_doc()
	if trial == null:
		return REASON_NO_DOC
	if target_parent == "" or not trial.parts.has(target_parent):
		return REASON_NO_PARENT
	var findings: Array[Dictionary] = ShipValidate.validate(trial, _data(), _config())
	for finding: Dictionary in findings:
		if str(finding.get("severity", "")) != ShipValidate.SEVERITY_ERROR:
			continue
		var code: String = str(finding.get("code", ""))
		if not _is_blocking(code):
			continue
		var pid: String = str(finding.get("part", ""))
		if pid != "" and pid != _trial_id:
			continue
		return "%s %s" % [code.to_upper(), str(finding.get("message", ""))]
	return ""


## Does this ShipValidate code make the placement genuinely impossible - the part cannot be
## resolved to geometry, or the tree would stop being a tree?
##
## A WHITELIST on purpose. ShipValidate also reports authoring smells at error severity:
## `unknown_manufacturer` fires on an EMPTY manufacturer, and `param_out_of_range` fires on
## a value a since-retuned pack has narrowed. A part carrying either still resolves, still
## renders, and is still accepted by ShipBuilder.add_part(). Blocking on the whole error
## list would make placing a part stricter than adding one - so a data pack shipped without
## manufacturers would quietly make the builder unable to build anything. Ghost validity
## must mean exactly "this click will be refused" and nothing looser.
##
## `budget_exceeded` is absent because _budget_reason() owns it: it is the one finding that
## moves with the four numbers, and it is checked every frame instead of every re-target.
static func _is_blocking(code: String) -> bool:
	var blocking: Array = [
		ShipValidate.CODE_NO_ROOT,
		ShipValidate.CODE_ORPHAN_PART,
		ShipValidate.CODE_CYCLE,
		ShipValidate.CODE_UNKNOWN_FAMILY,
		ShipValidate.CODE_SCALE_OUT_OF_RANGE,
		ShipValidate.CODE_MIRROR_SOURCE_MISSING,
		ShipValidate.CODE_MIRROR_OF_MIRROR,
		ShipValidate.CODE_COMPONENT_CYCLE,
		ShipValidate.CODE_COMPONENT_MISSING,
	]
	return blocking.has(code)


## A throwaway copy of the document with the placement already applied. Never handed to
## anything that could commit it - it exists so ShipValidate sees what the player is about
## to make rather than what they have.
func _trial_doc() -> ShipDoc:
	var doc: ShipDoc = _doc()
	if doc == null:
		return null
	var trial: ShipDoc = doc.duplicate_doc()
	if _moving_id != "":
		var moved: ShipPart = trial.parts.get(_moving_id, null)
		if moved == null:
			return null
		moved.parent = target_parent
		moved.yaw = _yaw
		moved.pitch = _pitch
		moved.rot = _rot
		moved.offset = _offset
		moved.snap_id = _snap_id
		moved.scale = _part_scale
		_trial_id = _moving_id
		return trial
	var part: ShipPart = _new_part()
	_trial_id = trial.add_part(part)
	return trial


# ---------------------------------------------------------------- caches


## Re-resolve everything that depends on the document rather than on the four numbers.
## Called on begin, on commit and on a document change - never per drag frame, where only
## _recompute_preview() (one sphere trace) runs.
func _refresh_scene_cache() -> void:
	_shapes = {}
	_xforms = {}
	_shape = null
	_ghost_boxes = []
	_base_bbox = AABB()
	_base_seeded = false
	_static_reason = ""
	# The document moved under the full gate's feet, so its sticky result is meaningless.
	# recheck_gate_with_metrics() re-establishes it on the next idle window.
	_metrics_reason = ""
	_snap_points = PackedVector3Array()
	_snap_ids = PackedStringArray()
	var doc: ShipDoc = _doc()
	var data: ShipData = _data()
	var cfg: ShipConfig = _config()
	if doc == null or data == null or cfg == null:
		_static_reason = REASON_NO_DOC
		return
	_shapes = ShipAttach.resolve_shapes(doc, data, cfg)
	_xforms = ShipAttach.resolve_all_from_shapes(doc, _shapes, cfg)
	_reseed_from_moving_part(doc)
	_shape = _resolve_ghost_shape(data)
	_resolve_snap_target()
	_rebuild_snap_points()
	_build_ghost_boxes(doc)
	_build_base_bbox(doc)
	_static_reason = _validate_trial()


## Re-read the shape inputs of the part being re-placed. The inspector can edit scale and
## family params while a move is in flight, and the ghost must show what the part actually
## is, not what it was when the move started. The four ATTACH numbers are deliberately not
## re-read: those belong to the placement while it is live.
func _reseed_from_moving_part(doc: ShipDoc) -> void:
	if _moving_id == "":
		return
	var part: ShipPart = doc.parts.get(_moving_id, null)
	if part == null:
		return
	_kind = part.kind
	_family_id = part.family
	_manufacturer_id = part.manufacturer
	_params = part.params.duplicate(true)
	_part_scale = part.scale


func _build_ghost_boxes(doc: ShipDoc) -> void:
	if _shape != null:
		_ghost_boxes.append(_shape.local_aabb())
	if _moving_id == "":
		return
	var origin: Variant = _xforms.get(_moving_id, null)
	if not (origin is Transform3D):
		return
	var inv: Transform3D = (origin as Transform3D).affine_inverse()
	# Everything that rides with the moving part: its descendants, and every expanded part
	# ("<instance>/<inner>") the transform map holds for an instance among them - the moving part
	# itself or any descendant, at any depth. Partitioned by the owning doc id, the same way
	# _build_base_bbox() decides what stays behind, so the two never disagree about a part.
	var moving: Dictionary = {}
	for pid: String in _blocked:
		moving[pid] = true
	var riders: PackedStringArray = PackedStringArray()
	for key: Variant in _xforms.keys():
		var pid: String = str(key)
		if pid == _moving_id or ShipSymmetry.is_twin_id(pid):
			continue
		if moving.has(ShipComponents.instance_of(pid)):
			riders.append(pid)
	for pid: String in riders:
		var shape: ResolvedShape = _shape_for(pid, doc)
		var xf_v: Variant = _xforms.get(pid, null)
		if shape == null or not (xf_v is Transform3D):
			continue
		var xf: Transform3D = xf_v
		_ghost_boxes.append(((inv * xf) * shape.local_aabb()).abs())


func _build_base_bbox(doc: ShipDoc) -> void:
	var skip: Dictionary = {}
	for pid: String in _blocked:
		skip[pid] = true
	for key: Variant in _xforms.keys():
		var pid: String = str(key)
		# An expanded component part rides with its instance, so it is skipped when that is.
		if skip.has(pid) or skip.has(ShipComponents.instance_of(pid)):
			continue
		var shape: ResolvedShape = _shape_for(pid, doc)
		if shape == null:
			continue
		var xf_v: Variant = _xforms[key]
		if not (xf_v is Transform3D):
			continue
		var xf: Transform3D = xf_v
		var box: AABB = (xf * shape.local_aabb()).abs()
		if _base_seeded:
			_base_bbox = _base_bbox.merge(box)
		else:
			_base_bbox = box
			_base_seeded = true


## A mirror derivative has no shape of its own; it borrows its source's, the way
## ShipMetrics does. Anything unresolvable is simply skipped.
func _shape_for(part_id: String, doc: ShipDoc) -> ResolvedShape:
	var direct: Variant = _shapes.get(part_id, null)
	if direct is ResolvedShape:
		return direct
	var part_v: Variant = doc.parts.get(part_id, null)
	if part_v is ShipPart:
		var part: ShipPart = part_v
		if part.mirror_source != "":
			var source: Variant = _shapes.get(part.mirror_source, null)
			if source is ResolvedShape:
				return source
	return null


func _parent_transform() -> Transform3D:
	var xf_v: Variant = _xforms.get(target_parent, null)
	if xf_v is Transform3D:
		return xf_v
	return Transform3D.IDENTITY


func _parent_shape() -> ResolvedShape:
	var shape_v: Variant = _shapes.get(target_parent, null)
	if shape_v is ResolvedShape:
		return shape_v
	return null


# ---------------------------------------------------------------- edit protocol


func _commit_new(doc: ShipDoc) -> String:
	var part: ShipPart = _new_part()
	_builder.begin_edit(LABEL_PLACE)
	var new_id: String = doc.add_part(part)
	if new_id == "":
		return ""
	# Empty changed_ids: the topology changed, so the view must diff everything.
	_builder.commit_edit(PackedStringArray())
	var after: ShipDoc = _builder.get_doc()
	if after == null or not after.parts.has(new_id):
		return ""
	_builder.set_selection(PackedStringArray([new_id]))
	return new_id


func _commit_move(doc: ShipDoc) -> String:
	var part: ShipPart = doc.parts.get(_moving_id, null)
	if part == null:
		return ""
	var reparented: bool = part.parent != target_parent
	_builder.begin_edit(LABEL_MOVE)
	part.parent = target_parent
	part.yaw = _yaw
	part.pitch = _pitch
	part.rot = _rot
	part.offset = _offset
	# Carries the whole placement, not just the four numbers: a wheel notch or a morph drag
	# during the move edits _part_scale, and the snap decides which attach path the stored
	# part takes from here on.
	part.snap_id = _snap_id
	part.scale = _part_scale
	var changed: PackedStringArray = PackedStringArray()
	if not reparented:
		# The subtree rides along, so it is refreshed too; a re-parent changed the topology
		# and must go through the full diff instead.
		changed.append(_moving_id)
		changed.append_array(doc.descendants_of(_moving_id))
	_builder.commit_edit(changed)
	var after_doc: ShipDoc = _builder.get_doc()
	if after_doc == null:
		return ""
	var after: ShipPart = after_doc.parts.get(_moving_id, null)
	if after == null or not _matches(after):
		return ""
	return _moving_id


## Did the edit survive? On a refusal the builder restores the pre-edit snapshot, so the
## part read back carries its OLD values and this is false. A no-op move cannot be refused
## (it cannot increase any budget), so a false positive here is not reachable.
func _matches(part: ShipPart) -> bool:
	return (
		part.parent == target_parent
		and part.snap_id == _snap_id
		and is_equal_approx(part.yaw, _yaw)
		and is_equal_approx(part.pitch, _pitch)
		and part.rot.is_equal_approx(_rot)
		and is_equal_approx(part.offset, _offset)
	)


## Every part needs a manufacturer - it narrows the family's ranges and prices the part, and
## ShipValidate reports an empty one. A caller that does not care gets the family's first,
## the same fallback ShipBuilder uses when it creates a document.
## The ghost's ResolvedShape. A component instance has no family in the catalogue, so it goes
## through the same proxy path the attach pass uses - a scratch ShipPart handed to ShipAttach -
## rather than through ShapeGen, which would find no such family and return null (an invisible
## ghost that refuses every drop).
func _resolve_ghost_shape(data: ShipData) -> ResolvedShape:
	if _kind != ShipPart.KIND_COMPONENT_INSTANCE:
		return ShapeGen.resolve(data, _family_id, _manufacturer_id, _params, _part_scale)
	var doc: ShipDoc = _doc()
	if doc == null:
		return null
	var probe: ShipPart = ShipPart.new()
	probe.kind = ShipPart.KIND_COMPONENT_INSTANCE
	probe.family = _family_id
	probe.scale = _part_scale
	return ShipAttach.resolve_shapes_for_part(doc, data, _config(), probe)


func _resolve_manufacturer(family_id: String, manufacturer_id: String) -> String:
	if manufacturer_id != "":
		return manufacturer_id
	var data: ShipData = _data()
	if data == null:
		return ""
	var ids: PackedStringArray = data.manufacturers_for(family_id)
	return ids[0] if not ids.is_empty() else ""


func _new_part() -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.parent = target_parent
	part.kind = _kind
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = _params.duplicate(true)
	part.yaw = _yaw
	part.pitch = _pitch
	part.rot = _rot
	part.offset = _offset
	part.scale = _part_scale
	# "" is the free-surface path and is not a missing value - see ShipAttach's class
	# docstring. Both paths are permanent; neither is a migration state.
	part.snap_id = _snap_id
	return part


# ---------------------------------------------------------------- internals


## Drop every trace of the placement. Called by cancel() and by a successful commit(), so
## there is exactly one teardown and no exit path can forget half of it.
func _reset() -> void:
	active = false
	target_parent = ""
	_kind = ShipPart.KIND_PRIMITIVE
	_family_id = ""
	_manufacturer_id = ""
	_params = {}
	_part_scale = Vector3.ONE
	_moving_id = ""
	_blocked = PackedStringArray()
	_shape = null
	_shapes = {}
	_xforms = {}
	_ghost_boxes = []
	_base_bbox = AABB()
	_base_seeded = false
	_preview = Transform3D.IDENTITY
	_snap_bypass = false
	_trial_id = ""
	_static_reason = ""
	_metrics_reason = ""
	_snap_id = ""
	_snap_target = {}
	_snap_points = PackedVector3Array()
	_snap_ids = PackedStringArray()
	_off_ship = false
	# The drag mode IS reset: it comes from modifiers read off the event that started the drag,
	# and a stale VERTICAL would silently reinterpret the next placement's first motion.
	_drag_mode = DragMode.FREE
	_ghost_state = GhostState.DEFAULT
	_valid = true
	_reason = ""


func _selection() -> PackedStringArray:
	return _builder.get_selection() if _builder != null else PackedStringArray()


## The selected parts a grammar verb may actually edit. A locked part and a legacy mirror
## derivative are both skipped for the same reason begin_move() refuses them: neither owns
## its own placement.
func _editable_selection(doc: ShipDoc) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for pid: String in _selection():
		if not doc.parts.has(pid):
			continue
		var part: ShipPart = doc.parts[pid]
		if part.locked or part.is_mirror():
			continue
		out.append(pid)
	return out


## Per-part scale clamp. Spore clamps scale PER PART TYPE (`mModelMinScale` / `mModelMaxScale`,
## SPORE_CLONE_SPEC section 1); we have one global pair in ShipConfig, which is section 8c's
## recorded divergence and not an oversight. Clamping here rather than at commit means the
## ghost stops growing where the part will stop growing.
func _clamp_scale(v: Vector3) -> Vector3:
	var lo: float = 0.05
	var hi: float = 50.0
	var cfg: ShipConfig = _config()
	if cfg != null:
		lo = maxf(cfg.part_scale_min, 0.001)
		hi = maxf(cfg.part_scale_max, lo)
	return Vector3(clampf(v.x, lo, hi), clampf(v.y, lo, hi), clampf(v.z, lo, hi))


## Re-resolve the ghost's shape after a scale or morph edit, and re-emit. The ghost boxes go
## with it: they are what the live bounding-box budget preview measures, so a resize that did
## not rebuild them would report the old size and let an over-budget part through.
func _rebuild_ghost_shape() -> void:
	var data: ShipData = _data()
	if data == null:
		return
	_shape = _resolve_ghost_shape(data)
	_ghost_boxes = []
	var doc: ShipDoc = _doc()
	if doc != null:
		_build_ghost_boxes(doc)
	_store_values(_yaw, _pitch, _rot, _offset)


## Which of the three local axes a morph handle points along, or -1 when it points nowhere.
func _dominant_axis(axis: Vector3) -> int:
	var best: int = -1
	var best_value: float = MIN_AXIS
	for i: int in 3:
		var v: float = absf(axis[i])
		if v >= best_value:
			best_value = v
			best = i
	return best


func _doc() -> ShipDoc:
	return _builder.get_doc() if _builder != null else null


func _data() -> ShipData:
	return _builder.get_data() if _builder != null else null


func _config() -> ShipConfig:
	return _builder.get_config() if _builder != null else null
