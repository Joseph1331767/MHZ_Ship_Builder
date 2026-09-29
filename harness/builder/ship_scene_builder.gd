## ShipSceneBuilder - ShipDoc -> one MeshInstance3D per part, under this Node3D.
##
## SPEC section 2, the "build" branch of the three views of one truth. This is the crisp,
## picky, never-remeshed-while-dragging view. It does NOT touch the SDF: it asks
## ShipAttach for the resolved shapes and their ship-space transforms, and asks
## ShipMeshGen for a primitive preview per shape.
##
## INCREMENTAL BY DESIGN. sync() diffs against what is already in the scene and touches
## only what changed - a part whose mesh signature is unchanged keeps its mesh, and a part
## whose transform is unchanged is not written to. Dragging a part must not rebuild the
## world, so rebuild() (the full teardown) is reserved for a document swap.
##
## MIRRORED PARTS. A mirror derivative arrives from ShipAttach.resolve_all() with a
## negative-determinant basis. That flips triangle winding, so the part renders
## inside-out unless the material culls the other face - hence cull_mode = CULL_FRONT on
## exactly those parts (SPEC section 6).
##
## COMPONENT INSTANCES ARE DRAWN WHOLE. The attach pass emits an instance's own id with its
## definition root as the proxy shape, and every other part of the definition under
## "<instance>/<inner>" (ShipAttach.resolve_shapes). Both maps here are walked by key, so
## those parts are visuals like any other - picked, highlighted and hidden as their instance
## (part_id_for, _is_selected, _apply_visibility). Before this, only the proxy was drawn:
## "when i selected multiple parts and press make component they all dissapear".
##
## COLLISION IS FOR MOUSE PICKING ONLY. One StaticBody3D per part, on its own layer,
## never simulated. It is parented to this root rather than to the mesh so it does not
## inherit a reflected basis, which the physics server does not accept.
##
## THE PLACEMENT GHOST (M3) is a single extra MeshInstance3D with no pick body, driven by
## ShipPlacement through ShipView3D. It uses the SAME ShipMeshGen mesh the committed part
## will use, so the preview cannot disagree with the result. It is created on demand and
## destroyed by hide_ghost() and by clear_scene(), so a document swap mid-drag cannot leave
## an orphan ghost behind.
##
## THREE OVERLAYS, ONE RULE: THEY ALL DIE IN clear_scene(). The ghost, the snap-target
## markers and the selection gizmo are each a single extra node with no pick body, created
## on demand. rebuild() routes through clear_scene(), so any document swap - an undo, an
## open, a refused edit rolling back - takes all three with it, and nothing can be left
## pointing at a part that no longer exists.
##
## THE GHOST'S COLOUR IS ITS UI STATE, not a boolean. ShipPlacement resolves the placement to
## one of Spore's five `eBlockUIState` values (API_CONTRACT_SPORE section 8) and this class
## maps that to a palette role. The distinction that matters most is DEFAULT vs GHOST: both
## are legal, but DEFAULT means the drop is sitting on a typed snap target and GHOST means it
## is loose on the surface. The player can see which before clicking, which is the entire
## point of cloning the snap mechanic.
##
## SNAP MARKERS show WHERE a drop can land. Every target on the hovered parent is drawn as a
## small cross in a dim role, and the one currently live is drawn larger in the selection
## role. Spore's targets are invisible - they are baked `csnap` bones - but Spore also ships
## hundreds of hand-authored parts whose faces read as obvious attachment points; ours are
## derived from an SDF the player has been reshaping with sliders, so showing them is what
## makes the same mechanic legible.
##
## THE SELECTION GIZMO is ShipHandles' geometry, drawn here and hit-tested there. The node
## carries the part's RIGID ship transform: ShipHandles derives its radii from
## ResolvedShape.local_aabb(), which already includes the part's scale, so applying the mesh
## scale here as well would square it.
class_name ShipSceneBuilder
extends Node3D

## SPEC section 11 display modes.
## SPEC section 11 display modes. FRESNEL is appended, so no existing value moves - the header's
## dropdown, the visual check's capture list and any saved index all keep meaning what they meant.
##
## FRESNEL IS ITS OWN RENDER TYPE, not a switch on the others (ADR 0009). The author asked for the
## effect by name - "i really want a frenzal node" - and then, when it shipped as a always-on term
## folded into the shading, asked for it where it could be pointed at: "i mean i wanted that
## rendering effect/node to be listed among wire, flat, shaded options". So it is a mode: the body
## drops to the ramp's dark end and the silhouette rises to its top, which reads as an outlined
## shell rather than as a shaded solid with a bright edge.
## CLAY is appended at 6 for the same reason FRESNEL was appended at 4: nothing already stored,
## captured or listed moves. It is the render type fly mode wears (ADR 0049) - flat blue clay with
## wire edges, in a deep void, lit by the camera's torch. The author: "a themed blue clay with wire
## edges rendering mode with a completely dark environment like deep void of space".
enum DisplayMode { FLAT, WIREFRAME, SHADED_WIRE, XRAY, FRESNEL, INSIDE, CLAY }

## Metadata key carrying the part id on each pick body.
const PART_META: String = "mhz_part_id"
## Picking bodies live alone on layer 1 and collide with nothing.
const PICK_LAYER: int = 1

## Faceted solid shading — see _faceted_material and FOLLOWUPS F7.
const FACETED_SHADER: String = "res://shaders/part_faceted.gdshader"
## The shader's own default cut plane: infinitely far behind everything (ADR 0028).
## The INTERIOR set's shading (ADR 0028): the cavity shades hard so it reads as a hollow, the
## far outer wall keeps a floor so the wall thickness reads, and the distance cue is light.
const INTERIOR_AMBIENT: float = 0.5
const INTERIOR_CAVITY_AMBIENT: float = 0.12
const INTERIOR_DEPTH_STRENGTH: float = 0.1
const NO_CUT: Vector4 = Vector4(0.0, 0.0, 0.0, -1.0e9)
const FACET_LIGHT_DIR: Vector3 = Vector3(-0.45, -0.80, -0.40)
const FACET_AMBIENT: float = 0.28
## How far along the ramp the distance cue may pull a fragment. Enough that a far face drops a
## clear band below a near one at the same angle; not so much that the far side of the ship goes
## black.
const FACET_DEPTH_STRENGTH: float = 0.34
## The Fresnel rim (shaders/part_faceted.gdshader): how far toward the ramp's top band a grazing
## fragment is pushed, and how tightly the band hugs the silhouette. The ordinary modes carry a
## light rim so silhouettes separate; DisplayMode.FRESNEL is the render type built around it and
## takes the whole ramp, with the lambert and distance cues stood down so the body goes dark and
## only the edges light up.
const FACET_RIM_STRENGTH: float = 0.35
const FACET_RIM_POWER: float = 2.5
const FRESNEL_RIM_STRENGTH: float = 0.95
const FRESNEL_RIM_POWER: float = 1.8
const FRESNEL_AMBIENT: float = 0.04

## DisplayMode.CLAY (ADR 0049). CLAY IS MATTE, and every number here says so.
##
## THREE BANDS, not four: a fourth band reads as polish. `_clay_ramp` trims the ramp rather than
## re-authoring the palette, so the clay variant's own colours are what show.
##
## `CLAY_RIM_STRENGTH` is deliberately LOW. A strong Fresnel rim is wet plastic - it is exactly
## what DisplayMode.FRESNEL is for - and on clay it reads as a glaze. Enough is kept that a
## silhouette still separates from the void behind it, which at 16 colours it otherwise would not.
##
## `CLAY_AMBIENT` has two values, and the difference is the whole point of the torch. Static CLAY
## sits at 0.45, which is readable clay you can inspect. While FLYING it drops to CLAY_AMBIENT_FLY,
## where the torch is genuinely the only light source and the far side of your own ship is not
## there until you point at it - the "completely dark environment like deep void of space" the
## author asked for. Answered as design question Q16 in docs/future/ux.md.
const CLAY_AMBIENT: float = 0.45
const CLAY_AMBIENT_FLY: float = 0.12
const CLAY_DEPTH_STRENGTH: float = 0.10
const CLAY_RIM_STRENGTH: float = 0.15
const CLAY_RIM_POWER: float = 2.5
## Bands in the clay ramp. Matte.
const CLAY_BANDS: int = 3

## Transparent-queue priorities of the gizmo's two passes. Both draw after every opaque part;
## the DIM pass (no depth test) draws first and everywhere, the BRIGHT pass (depth-tested)
## draws over it only where the gizmo is in front of the ship. What is behind a part is dim,
## what is in front is bright, and nothing is ever hidden.
const GIZMO_DIM_PRIORITY: int = 90
const GIZMO_BRIGHT_PRIORITY: int = 100
## Relative change of metres-per-pixel that triggers a gizmo rebuild. Coarse: the floors are
## in whole pixels and a rebuild per wheel notch would be wasted work.
const HANDLE_PX_TOLERANCE: float = 0.05
## Wireframe overlay is grown by this factor in the shaded+wireframe mode so the lines
## sit just outside the surface instead of z-fighting with it.
const WIRE_SWELL: float = 1.002
const XRAY_ALPHA: float = 0.30

## Placement ghost translucency. Paired with no_depth_test so the ghost still reads when
## a negative offset embeds it in its parent - the point of a preview is to be seen.
const GHOST_ALPHA: float = 0.45
const GHOST_NODE_NAME: String = "ghost_preview"
const GHOST_TWIN_NODE_NAME: String = "ghost_preview_twin"
const SNAP_NODE_NAME: String = "snap_targets"
const HANDLE_NODE_NAME: String = "selection_gizmo"

## Half-arm of a snap marker's cross, in metres, and how much bigger the live one is drawn.
## Fixed rather than screen-relative: this class never projects anything and never reads a
## camera, so a pixel-constant marker is not available to it and is not worth a camera
## dependency here (ShipHandles is where screen space lives).
const SNAP_MARK_M: float = 0.055
const SNAP_LIVE_FACTOR: float = 2.1

## Ghost alpha per GhostState. Indexed by the enum's own values, so the ordering here is
## ShipPlacement.GhostState's ordering: DEFAULT, INVALID, GHOST, BAD_LOCATION, PREVENT.
# A plain Array, not a PackedFloat32Array: a Packed*Array constructor is a CALL and cannot
# initialise a const. gdparse accepts it; the engine rejects it.
const GHOST_STATE_ALPHA: Array = [0.55, 0.22, GHOST_ALPHA, 0.28, 0.60]


## One part's visual footprint in the scene.
class PartVisual:
	extends RefCounted

	var pid: String = ""
	var solid: MeshInstance3D = null
	var wire: MeshInstance3D = null
	var body: StaticBody3D = null
	var collider: CollisionShape3D = null
	var sig: String = ""
	var xform: Transform3D = Transform3D.IDENTITY
	var flipped: bool = false
	var selected: bool = false
	var valid: bool = false
	## Kept so the selection gizmo and the view's handle hit test can be built from the same
	## ResolvedShape the mesh came from, rather than re-resolving it per frame.
	var shape: ResolvedShape = null
	## The seam the part stands on - origin on the parent's surface, basis.z the mount normal -
	## carried into THIS part's local frame, for the footprint collar (ShipHandles.footprint_loop).
	## `has_seam` is false for the root, a twin, an expanded inner part, and any part whose
	## parent could not be resolved.
	var seam_local: Transform3D = Transform3D.IDENTITY
	var has_seam: bool = false


## WHICH VERB'S HANDLES ARE DRAWN, a `ShipHandles.TOOL_*` mask owned by [ShipEditTool]. A public
## var with a private setter, for the same reason as the layers below: this class stands at
## gdlint's thirty-public-method cap and gdlint counts `func`, not `var`.
var edit_tools: int = ShipHandles.TOOL_ALL:
	set = _set_edit_tools

## TRUE WHILE FLY MODE IS UP (ADR 0049), which HIDES the gizmo. Hidden, not cleared - clearing the
## selection would fire `selection_changed` for nothing and lose the player's place. Eleven handles
## in orange across a dark void is the one thing that stops it reading as being inside a ship.
##
## A public var with a private setter, for the same reason [member edit_tools] is one: this class
## stands at gdlint's thirty-public-method cap and gdlint counts `func`, not `var`.
## THE TORCH (ADR 0049) - the camera-mounted flashlight as `{pos, dir, strength, reach}`, written
## every tick the fly rig moves, exactly as [method set_depth_range] is. `strength` 0 is the
## shader's default and turns the whole term off, so no mode but CLAY-while-flying ever sees it.
##
## IT CANNOT BE A SpotLight3D: the part shader is `unshaded` and would ignore one, and making the
## material shaded to receive it renders it BLACK in this SubViewport (FOLLOWUPS F7, measured at
## 115,582 px -> 0 px). So the setter walks the material cache and writes four uniforms.
##
## A var rather than a setter method for the same reason [member edit_tools] is one: this class
## stands at gdlint's thirty-public-method cap and gdlint counts `func`, not `var`.
var torch: Dictionary = {}:
	set = _set_torch

var flying: bool = false:
	set = _set_flying

## THE LAYERS THAT ARE NOT DRAWN - `ShipCsgBake.SURFACE_*` names, plus
## `ShipLayersControl.LAYER_DOOR` (ADR 0046, extended 2026-09-26). WALLS start dropped, because
## the mode that gains most from the switch is INTERIOR and its whole purpose is looking into
## rooms.
##
## A PROPERTY rather than a setter, because this class stands at gdlint's thirty-public-method
## cap - gdlint counts `func`, not `var`. Assign the WHOLE array and the setter rebuilds the
## materials; mutating it in place does nothing, which is why nothing here hands the array out.
var hidden_layers: PackedStringArray = PackedStringArray([ShipCsgBake.SURFACE_WALL]):
	set = _set_hidden_layers

var _theme: ShipTheme = null
var _mesh_gen: ShipMeshGen = ShipMeshGen.new()
## SHADED_WIRE, not FLAT. The solid material is UNSHADED (see _solid_material), so a FLAT
## part is one uniform colour with no edges at all -- a box reads as a plain hexagonal
## silhouette. The wireframe overlay is what carries the form, and solid-fill-plus-edges is
## the CAD read this builder is going for anyway.
var _mode: int = DisplayMode.SHADED_WIRE
var _visuals: Dictionary = {}
var _selected: Dictionary = {}
var _solid_materials: Dictionary = {}

# THE TORCH's three uniforms (ADR 0049), mirrored here so a material built after the last push
# still gets them - the same reason _depth_near/_depth_far are held.
var _torch_pos: Vector3 = Vector3.ZERO
var _torch_dir: Vector3 = Vector3.FORWARD
var _torch_strength: float = 0.0
var _torch_range: float = 14.0
## The faceted shader by cull mode ("", "back", "front") - see _faceted_shader.
var _faceted_shaders: Dictionary = {}
## The component instance being edited in isolation, or "" (ADR 0024).
var _isolated: String = ""
var _washed: Material = null
var _wire_materials: Dictionary = {}
var _ghost: MeshInstance3D = null
## The MIRRORED preview, shown only while the pending placement would actually generate a
## twin. Null the rest of the time - including on the centre line, where its absence is the
## whole message.
var _ghost_twin: MeshInstance3D = null
var _ghost_sig: String = ""
## A ShipPlacement.GhostState value. Seeded in _ready() rather than in this declaration on
## purpose: ShipSceneBuilder, ShipView3D, ShipBuilder and ShipPlacement already form a ring
## of class-level type references, and reading another class's ENUM CONSTANT from inside
## that ring asks for a value mid-resolution rather than just a declared name. Function
## bodies are the safe place for a mutual class_name reference (the same rule ShipHandles
## documents for ShipAttach/SnapTargets), and _ready() is a function body.
var _ghost_state: int = 0
var _ghost_materials: Dictionary = {}
var _snap_marks: MeshInstance3D = null
var _handles: MeshInstance3D = null
var _line_materials: Dictionary = {}
var _gizmo_materials: Dictionary = {}
## Metres per inner-viewport pixel at the selected part's distance, pushed in from ShipView3D as
## the camera moves; the gizmo's screen-size floors are built against it. 0 before the first
## camera frame, which disables the floors rather than dividing by them.
var _m_per_px: float = 0.0
## The EXPLODED view is showing: every part visual and the gizmo hide behind the module bakes
## (ShipExplodeView), and come back untouched when it clears.
var _exploded: bool = false
## Placed ids the current bake covers (the baked view hides these primitives), ADR 0028.
var _covered: Dictionary = {}
## Distance-cue range in metres, pushed in from ShipView3D as the orbit camera moves. Equal values
## disable the cue, which is the correct behaviour before the first camera frame.
var _depth_near: float = 0.0
var _depth_far: float = 0.0
## The INTERIOR cutaway plane the interior materials wear (ADR 0028).
var _cut_plane: Vector4 = NO_CUT

## Part hidden because it is the one currently being re-placed; "" when none.
var _suppressed: String = ""
## Last document and config handed to sync()/rebuild(). Cached ONLY so the ghost can answer
## "would this placement also make a twin?" without a new accessor on ShipPlacement, which is
## already at the public-method budget .gdlintrc sets (and whose comment says a second wide
## class means fix the facade, not raise the number).
var _doc: ShipDoc = null
var _cfg: ShipConfig = null


func _ready() -> void:
	# See the note on _ghost_state. Nothing reads it before show_ghost() writes it, so this
	# is belt and braces - but a silently wrong default would show every ghost in the wrong
	# colour, which is precisely the class of bug nobody reports as a bug.
	_ghost_state = ShipPlacement.GhostState.DEFAULT


func setup(theme: ShipTheme) -> void:
	_theme = theme
	refresh_materials()


func set_display_mode(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	for key: Variant in _visuals.keys():
		var v: PartVisual = _visuals[key]
		_apply_visibility(v)
		_apply_materials(v)


func get_display_mode() -> int:
	return _mode


func part_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in _visuals.keys():
		out.append(str(key))
	return out


# ---------------------------------------------------------------- build / sync


## Full teardown then sync. Use on a document swap (new / open / undo to a different
## topology), not while editing.
func rebuild(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	clear_scene()
	sync(doc, data, cfg)


## Refresh the scene to match the document, touching only what changed.
func sync(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	if doc == null or data == null or cfg == null:
		clear_scene()
		return

	# Both maps are computed once here and cover mirror derivatives as well as real
	# parts, which is why the loop walks the transform map rather than doc.parts.
	_doc = doc
	_cfg = cfg
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, cfg)

	var live: Dictionary = {}
	for key: Variant in xforms.keys():
		var pid: String = str(key)
		if not shapes.has(pid):
			continue
		var shape: ResolvedShape = shapes[pid]
		if shape == null:
			continue
		var xf: Transform3D = xforms[pid]
		live[pid] = true
		_sync_part(pid, shape, xf, shapes, xforms)

	for key: Variant in _visuals.keys():
		var pid: String = str(key)
		if not live.has(pid):
			_destroy_visual(pid)


## Refresh only the named parts. Cheaper than sync() when the caller already knows which
## ids moved, and it still re-resolves through ShipAttach so the result cannot drift.
##
## EACH ID BRINGS ITS TWIN. A mirrored twin is derived, so it is never in a caller's changed-id
## list - and this is the path ShipBuilder._commit() takes for every ordinary edit. The result was
## that moving a part off the mirror plane produced its twin transform and never its MESH: the
## twin appeared only if some later action happened to force a full sync. Reported as "i add a
## piece to the base cube and only 1 piece is added, its not auto adding on opposite side of x".
##
## The twin is created OR destroyed here, not just created: dragging a part back onto the centre
## line legitimately removes it, and a stale mirrored mesh left behind is the same bug wearing the
## other hat.
func refresh_parts(doc: ShipDoc, data: ShipData, cfg: ShipConfig, ids: PackedStringArray) -> void:
	if doc == null or data == null or cfg == null or ids.is_empty():
		return
	_doc = doc
	_cfg = cfg
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, cfg)
	for pid: String in ids:
		_sync_or_destroy(pid, shapes, xforms)
		# EVERY possible twin key, not the bare one - and every subset of x/y/z whatever the
		# document currently says, because this is also the path the MIRROR row takes: turning a
		# plane OFF has to destroy the visuals its twins left behind, and `_sync_or_destroy`
		# destroys any key that has no transform.
		for twin_key: String in ShipSymmetry.all_twin_ids(pid):
			_sync_or_destroy(twin_key, shapes, xforms)
		_sync_expanded(pid, shapes, xforms)


## EACH ID ALSO BRINGS ITS COMPONENT. A component instance is drawn as its definition: the attach
## pass emits every inner part under "<instance>/<inner>" (ShipAttach.resolve_shapes), and those
## keys move with the instance, appear when a definition gains a part and go when it loses one.
## Every expanded key the pass produced for `pid` is synced, and every expanded visual it no longer
## produces is destroyed - twins of both included.
func _sync_expanded(pid: String, shapes: Dictionary, xforms: Dictionary) -> void:
	var prefix: String = pid + "/"
	for key: Variant in xforms.keys():
		var expanded: String = str(key)
		if expanded.begins_with(prefix):
			_sync_or_destroy(expanded, shapes, xforms)
	for key: Variant in _visuals.keys():
		var drawn: String = str(key)
		if drawn.begins_with(prefix) and not xforms.has(drawn):
			_destroy_visual(drawn)


## Bring one id into line with the resolve result: draw it when the passes produced both a shape
## and a transform for it, and remove whatever is on screen when they did not.
func _sync_or_destroy(pid: String, shapes: Dictionary, xforms: Dictionary) -> void:
	var shape_v: Variant = shapes.get(pid)
	var xform_v: Variant = xforms.get(pid)
	if not (shape_v is ResolvedShape) or not (xform_v is Transform3D):
		if _visuals.has(pid):
			_destroy_visual(pid)
		return
	_sync_part(pid, shape_v, xform_v, shapes, xforms)


func clear_scene() -> void:
	for key: Variant in _visuals.keys():
		_free_visual(_visuals[key])
	_visuals.clear()
	# A teardown must take every overlay with it. rebuild() routes through here, so a document
	# swap in the middle of a drag can never strand a ghost, a marker or a gizmo in the scene;
	# ShipPlacement re-shows the ghost from doc_changed if the placement is still live.
	hide_ghost()
	hide_snap_targets()
	_free_handles()
	set_suppressed_part("")


# ---------------------------------------------------------------- placement ghost


## Show (or move) the placement ghost. `shape` is the ResolvedShape the committed part will
## use and `xform` its ship-space transform, both straight from ShipPlacement. `state` is a
## ShipPlacement.GhostState value and picks the palette role and alpha, so an illegal
## placement looks illegal BEFORE the click and a snapped one looks different from a loose
## one.
## `owner_id` is the part the pending placement belongs to - the part being moved, or the parent
## a new part will attach to. It decides whether the MIRRORED half of the ghost is drawn, because
## a broken symmetry cascades down from the parent.
##
## Showing that mirrored half is what makes symmetry legible. Dragging a part across the centre
## line is the moment mirroring turns on, and with a single ghost there was nothing to see: the
## author reported adding a part and getting one piece, and the reason was that a part dropped on
## the parent's nose sits exactly ON the mirror plane, where a twin would coincide with the
## original and is correctly not generated. Right, and invisible.
func show_ghost(
	shape: ResolvedShape, xform: Transform3D, state: int, owner_id: String = ""
) -> void:
	if shape == null:
		hide_ghost()
		return
	if _ghost == null:
		_ghost = MeshInstance3D.new()
		_ghost.name = GHOST_NODE_NAME
		# No pick body on purpose: the ghost must never be raycast by its own drag.
		add_child(_ghost)
	var sig: String = ShipMeshGen.base_signature(shape)
	if sig != _ghost_sig or _ghost.mesh == null:
		_ghost.mesh = _mesh_gen.mesh_for(shape)
		_ghost_sig = sig
	# Same convention as a real part: ResolvedShape.scale is a transform, not a size, and since
	# ADR 0007 so is the shear. mesh_basis() carries both.
	_ghost.transform = Transform3D(xform.basis * ShipMeshGen.mesh_basis(shape), xform.origin)
	_ghost_state = state
	_ghost.material_override = _ghost_material(state)
	_ghost.visible = true
	_show_ghost_twin(shape, _preview_twin(xform, owner_id), state)


## The mirrored transform this placement would ALSO produce, or null when it would not: symmetry
## off, the owner effectively asymmetric, or the drop sitting on the mirror plane.
##
## Uses the same epsilon test [ShipSymmetry.generates_twin] applies to a stored part, so the
## preview cannot promise a twin the commit will not make. It cannot call that function directly -
## a pending part has no id - so the ownership half of the question is asked about `owner_id`.
##
## ONE GHOST, EVEN WHEN THE COMMIT WILL MAKE SEVERAL (ADR 0043). With two or three planes on, a
## drop off all of them produces three or seven twins; the ghost is a single node and shows the
## first. That under-promises, which is the safe direction - the preview never shows a twin the
## commit will not make - and a ghost per reflection is a view change worth doing on its own.
func _preview_twin(xform: Transform3D, owner_id: String) -> Variant:
	if _doc == null:
		return null
	if owner_id != "" and ShipSymmetry.is_effectively_asymmetric(_doc, owner_id):
		return null
	var epsilon: float = _cfg.symmetry_plane_epsilon if _cfg != null else 0.01
	for plane: String in ShipSymmetry.planes_of(_doc):
		var axis: int = ShipSymmetry.plane_axis(plane)
		if axis >= 0 and absf(xform.origin[axis]) > absf(epsilon):
			return ShipMirror.reflect(xform, plane)
	return null


## The mirrored half of the ghost. Same mesh, same material, reflected transform.
func _show_ghost_twin(shape: ResolvedShape, twin: Variant, state: int) -> void:
	if not (twin is Transform3D):
		if is_instance_valid(_ghost_twin):
			_ghost_twin.queue_free()
		_ghost_twin = null
		return
	if _ghost_twin == null:
		_ghost_twin = MeshInstance3D.new()
		_ghost_twin.name = GHOST_TWIN_NODE_NAME
		add_child(_ghost_twin)
	_ghost_twin.mesh = _mesh_gen.mesh_for(shape)
	var twin_xf: Transform3D = twin
	_ghost_twin.transform = Transform3D(
		twin_xf.basis * ShipMeshGen.mesh_basis(shape), twin_xf.origin
	)
	_ghost_twin.material_override = _ghost_material(state)
	_ghost_twin.visible = true


## Destroy the ghost. Safe to call when there is none, and called on every placement exit
## path - cancel, commit, escape, and a document swap through clear_scene().
func hide_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if is_instance_valid(_ghost_twin):
		_ghost_twin.queue_free()
	_ghost_twin = null
	_ghost_sig = ""


## Draw the hovered parent's snap targets. `points` are in SHIP space and `live` indexes the
## one the ghost is currently pulled to, or -1 when the drop is free on the surface.
##
## Rebuilt whole on every call: the array is at most fifteen crosses, and a partial update
## would need its own diff for no measurable gain.
func show_snap_targets(points: PackedVector3Array, live: int) -> void:
	if points.is_empty():
		hide_snap_targets()
		return
	if _snap_marks == null:
		_snap_marks = MeshInstance3D.new()
		_snap_marks.name = SNAP_NODE_NAME
		add_child(_snap_marks)
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var dim: PackedVector3Array = PackedVector3Array()
	var hot: PackedVector3Array = PackedVector3Array()
	for i: int in points.size():
		var on: bool = i == live
		var arm: float = SNAP_MARK_M * (SNAP_LIVE_FACTOR if on else 1.0)
		var target: PackedVector3Array = hot if on else dim
		_append_cross(target, points[i], arm)
	_append_lines(mesh, dim, _line_material("line"))
	_append_lines(mesh, hot, _line_material("selection"))
	_snap_marks.mesh = mesh
	_snap_marks.visible = true


## Destroy the snap markers. Called on every placement exit path, exactly like hide_ghost().
func hide_snap_targets() -> void:
	if is_instance_valid(_snap_marks):
		_snap_marks.queue_free()
	_snap_marks = null


## The ship-space RIGID transform of a part, for ShipHandles' hit test. IDENTITY when the
## part is not in the scene, which the caller sees as a gizmo that cannot be hit.
func part_transform(pid: String) -> Transform3D:
	var v: PartVisual = _visuals.get(pid, null)
	return v.xform if v != null else Transform3D.IDENTITY


## The stored orientation of a part, for anything that has to place gizmo geometry on the axes
## `rot` really turns (ShipHandles.ring_axis_local). Zero for an id that is not a document part.
func part_rot(pid: String) -> Vector3:
	return _rot_of(pid)


## The ResolvedShape a part was last built from, or null when it is not in the scene.
func part_shape(pid: String) -> ResolvedShape:
	var v: PartVisual = _visuals.get(pid, null)
	return v.shape if v != null else null


## Hide the part that is currently being re-placed, so the player sees the ghost and not
## the stale original underneath it. "" restores everything.
func set_suppressed_part(part_id: String) -> void:
	if part_id == _suppressed:
		return
	_suppressed = part_id
	for key: Variant in _visuals.keys():
		_apply_visibility(_visuals[key])


## `shapes` / `xforms` are the attach pass's maps, read only to place the part's seam (the
## footprint collar's plane) from its parent's shape and transform; a caller without them gets
## a visual with no seam, which draws and hit-tests everything but the collar.
func _sync_part(
	pid: String,
	shape: ResolvedShape,
	xf: Transform3D,
	shapes: Dictionary = {},
	xforms: Dictionary = {}
) -> void:
	var v: PartVisual = _visuals.get(pid, null)
	if v == null:
		v = _create_visual(pid)
		_visuals[pid] = v
	_sync_seam(v, xf, shapes, xforms)

	# The signature covers ResolvedShape.scale, so a scale-only edit - the commonest edit
	# a player makes - counts as changed geometry and re-derives the transform below.
	var sig: String = ShipMeshGen.signature(shape)
	var geometry_changed: bool = v.sig != sig or not v.valid
	# Stored unconditionally: the signature can match while the instance is a different
	# object, and the gizmo reads this rather than re-resolving the shape for itself.
	v.shape = shape
	if geometry_changed:
		v.solid.mesh = _mesh_gen.mesh_for(shape)
		v.wire.mesh = _mesh_gen.wire_for(shape)
		v.collider.shape = _mesh_gen.collision_for(shape)
		v.sig = sig
		v.valid = true

	if geometry_changed or v.xform != xf:
		# ResolvedShape.scale is a per-axis TRANSFORM, not a size - the SDF applies it as
		# min_component(scale) * base_sdf(p / scale). The preview mesh is therefore
		# unscaled and the stretch lives in the instance basis, which is the only way a
		# SphereMesh reads as the ellipsoid the SDF describes. Post-multiplied so it acts
		# in the part's own local axes, not in ship axes.
		var basis: Basis = xf.basis * ShipMeshGen.mesh_basis(shape)
		v.solid.transform = Transform3D(basis, xf.origin)
		v.wire.transform = Transform3D(basis.scaled(Vector3.ONE * WIRE_SWELL), xf.origin)
		# Pick body keeps the rigid transform: the hull points are already scaled.
		v.body.transform = _pick_transform(xf)
		v.xform = xf
		var flipped: bool = basis.determinant() < 0.0
		if flipped != v.flipped:
			v.flipped = flipped
			_apply_materials(v)

	var sel: bool = _is_selected(pid)
	if sel != v.selected:
		v.selected = sel
		_apply_materials(v)
	if v.selected:
		# The gizmo rides the part: a selected part that moved, or was rescaled, has to take
		# its handles with it or they hit-test against where it used to be.
		_refresh_handles()


## The seam a DOC part stands on, in its own local frame - the same P and N ShipAttach placed it
## with ([method ShipAttach.anchor_for]) and ShipSeams lays its wall in, so the collar the player
## grabs is drawn on the plane the hatch will be cut in. Only a doc part with a resolvable parent
## gets one; a twin is never the selection and an expanded inner part selects its instance, so
## neither needs a collar of its own.
func _sync_seam(v: PartVisual, xf: Transform3D, shapes: Dictionary, xforms: Dictionary) -> void:
	v.has_seam = false
	if _doc == null or not _doc.parts.has(v.pid):
		return
	var part: ShipPart = _doc.parts[v.pid]
	if part.parent.is_empty() or not xforms.has(part.parent):
		return
	var host_shape_v: Variant = shapes.get(part.parent)
	if not (host_shape_v is ResolvedShape):
		return
	var anchor: Dictionary = ShipAttach.anchor_for(host_shape_v, part, _cfg)
	var normal: Vector3 = anchor["normal"]
	var pos: Vector3 = anchor["pos"]
	var host_xform: Transform3D = xforms[part.parent]
	var ship_seam: Transform3D = host_xform * Transform3D(ShipAttach.mount_frame(normal), pos)
	var rigid: Transform3D = Transform3D(xf.basis.orthonormalized(), xf.origin)
	v.seam_local = rigid.affine_inverse() * ship_seam
	v.has_seam = true


## A visual is highlighted when its own id is selected or, for an expanded component part, when
## the instance it belongs to is: selecting a component selects all of it. A twin stays plain
## either way, as it does for a primitive - only the authored side carries the selection.
func _is_selected(pid: String) -> bool:
	if _selected.has(pid):
		return true
	return ShipComponents.is_expanded_id(pid) and _selected.has(ShipComponents.instance_of(pid))


func _create_visual(pid: String) -> PartVisual:
	var v: PartVisual = PartVisual.new()
	v.pid = pid
	# An expanded component part's id holds a slash, which a node name cannot. The meta on the
	# pick body keeps the real id; the names are only for the remote inspector.
	var node_name: String = pid.replace("/", "__")

	v.solid = MeshInstance3D.new()
	v.solid.name = "solid_" + node_name
	add_child(v.solid)

	v.wire = MeshInstance3D.new()
	v.wire.name = "wire_" + node_name
	add_child(v.wire)

	# Pick body is a sibling of the mesh, not a child: a mirrored part's basis has a
	# negative determinant and the physics server will not take that as a node scale.
	v.body = StaticBody3D.new()
	v.body.name = "pick_" + node_name
	v.body.collision_layer = PICK_LAYER
	v.body.collision_mask = 0
	v.body.set_meta(PART_META, pid)
	v.collider = CollisionShape3D.new()
	v.body.add_child(v.collider)
	add_child(v.body)

	_apply_visibility(v)
	_apply_materials(v)
	return v


func _destroy_visual(pid: String) -> void:
	var v: PartVisual = _visuals.get(pid, null)
	if v == null:
		return
	_free_visual(v)
	_visuals.erase(pid)


func _free_visual(v: PartVisual) -> void:
	if v == null:
		return
	if is_instance_valid(v.solid):
		v.solid.queue_free()
	if is_instance_valid(v.wire):
		v.wire.queue_free()
	if is_instance_valid(v.body):
		v.body.queue_free()


## Strip the mirror reflection (and any scale) for the pick collider. The collision shape
## was generated from the unreflected preview mesh, and every primitive family in Phase 1
## is symmetric enough that the mirror image picks identically.
func _pick_transform(xf: Transform3D) -> Transform3D:
	var b: Basis = xf.basis.orthonormalized()
	if b.determinant() < 0.0:
		b.x = -b.x
	return Transform3D(b, xf.origin)


# ---------------------------------------------------------------- selection


func set_selection(ids: PackedStringArray) -> void:
	var next: Dictionary = {}
	for pid: String in ids:
		next[pid] = true
	if next.hash() == _selected.hash() and next.size() == _selected.size():
		return
	_selected = next
	for key: Variant in _visuals.keys():
		var v: PartVisual = _visuals[key]
		var sel: bool = _is_selected(str(key))
		if sel != v.selected:
			v.selected = sel
			_apply_materials(v)
	_refresh_handles()


func selection() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in _selected.keys():
		out.append(str(key))
	return out


# ---------------------------------------------------------------- picking


## Rebuild the selection gizmo for the single selected part, or destroy it.
##
## EXACTLY ONE selected part gets handles. A gizmo per part in a multi-selection would be
## unhittable overlapping wireframe, and Spore's editors select one rigblock at a time
## anyway. The geometry all comes from ShipHandles so that what is DRAWN here and what is
## HIT-TESTED there can never drift apart.
func _refresh_handles() -> void:
	var ids: PackedStringArray = selection()
	if ids.size() != 1 or _exploded or flying or _is_covered(ids[0]):
		_free_handles()
		return
	var v: PartVisual = _visuals.get(ids[0], null)
	if v == null or v.shape == null:
		_free_handles()
		return
	if _handles == null:
		_handles = MeshInstance3D.new()
		_handles.name = HANDLE_NODE_NAME
		# No pick body: the gizmo is hit-tested in screen space by ShipHandles and must
		# never be returned by the part picker or by the placement's surface probe.
		add_child(_handles)
	var mesh: ImmediateMesh = ImmediateMesh.new()
	# EVERY handle, every time. No modal reveal - see ShipHandles' class docs for what the
	# Tab-gated set cost. The ball's great circles are gone with it: they were three more
	# concentric circles that swallowed every grab and spun the part about its placement vector.
	#
	# SOLID, with screen floors (ShipHandles' class docs, 2026-09-02): tubes for the rings, prisms
	# with cone heads for the arrows, none of it thinner than a couple of pixels at any zoom.
	# The part's own rot places each ring on the axis that handle really turns.
	var rot: Vector3 = _rot_of(v.pid)
	var shape: ResolvedShape = v.shape
	var tube: float = ShipHandles.tube_radius(shape, _m_per_px)
	var shaft: float = ShipHandles.shaft_radius(shape, _m_per_px)
	var head: float = ShipHandles.head_radius(shape, _m_per_px)
	var length: float = ShipHandles.arrow_length(shape, _m_per_px)
	var own: PackedVector3Array = PackedVector3Array()
	if (edit_tools & ShipHandles.TOOL_TURN) != 0:
		for handle: int in ShipHandles.ring_handles():
			own.append_array(ShipHandles.ring_solid(shape, handle, rot, tube))
	# ARROWS, not crosses. "all handles should be visible as they are in spore tiny 3d arrows
	# that you grab and pull" - each stretch handle is an arrow pointing out along the axis it
	# grows, its head on the hit point just off the part's face and its tail back inside the
	# part, so it reads as an arrow emerging from the face. The offset stalk starts ON the top
	# face and runs out along the mount normal to its hit point.
	if (edit_tools & ShipHandles.TOOL_STRETCH) != 0:
		var points: PackedVector3Array = ShipHandles.morph_points(shape)
		for i: int in points.size():
			var axis: Vector3 = ShipHandles.morph_axis(i)
			var tail: Vector3 = points[i] - axis * length * 0.75
			var tip: Vector3 = points[i] + axis * length * 0.25
			own.append_array(ShipHandles.arrow_solid(tail, tip, shaft, head))
	if (edit_tools & ShipHandles.TOOL_LIFT) != 0:
		own.append_array(
			ShipHandles.arrow_solid(
				ShipHandles.offset_tail(shape), ShipHandles.offset_point(shape), shaft, head
			)
		)
	# The placement handle in the ACCENT role, not the selection role: it belongs to the
	# attachment rather than to the part, and it must be tellable apart from the six stretch
	# arrows pointing out of the same object. A collar on the parent's surface round the base
	# of the part (ShipHandles.footprint_loop); the old parent-centre ray is kept as a dim
	# reference line that grabs nothing.
	var collar: PackedVector3Array = PackedVector3Array()
	if v.has_seam and (edit_tools & ShipHandles.TOOL_MOVE) != 0:
		collar = ShipHandles.tube_solid(ShipHandles.footprint_loop(shape, v.seam_local), tube)
	# Two passes per role, dim under bright - see GIZMO_DIM_PRIORITY.
	_append_triangles(mesh, own, _gizmo_material("selection", true))
	_append_triangles(mesh, collar, _gizmo_material("accent", true))
	_append_lines(mesh, _placement_ray(v), _gizmo_material("accent", true))
	_append_triangles(mesh, own, _gizmo_material("selection", false))
	_append_triangles(mesh, collar, _gizmo_material("accent", false))
	_handles.mesh = mesh
	# RIGID on purpose. ShipHandles sizes itself from ResolvedShape.local_aabb(), which
	# already carries the part's scale; multiplying the mesh scale in here would square it.
	_handles.transform = Transform3D(v.xform.basis.orthonormalized(), v.xform.origin)
	_handles.visible = true


## The placement RAY for the selected part - parent's origin to the part's own - in the SELECTED
## PART's local frame, the frame this whole gizmo mesh is drawn in. Reference only: it is drawn
## dim and grabs nothing. RETIRED(2026-09-02): as the placement HANDLE (an arrow with a hit
## region) - ShipHandles.footprint_loop is the handle now.
##
## Carried into that frame rather than drawn on the parent's node, because the gizmo is one mesh
## with one transform and a second node would have to be kept in step with the selection by hand.
## Returns empty for the root, which has no parent and therefore no placement vector.
func _placement_ray(v: PartVisual) -> PackedVector3Array:
	var empty: PackedVector3Array = PackedVector3Array()
	if _doc == null:
		return empty
	var part: ShipPart = _doc.parts.get(v.pid, null) as ShipPart
	if part == null or part.parent.is_empty():
		return empty
	var parent_visual: PartVisual = _visuals.get(part.parent, null)
	if parent_visual == null:
		return empty
	var inv: Transform3D = (
		Transform3D(v.xform.basis.orthonormalized(), v.xform.origin).affine_inverse()
	)
	return PackedVector3Array([inv * parent_visual.xform.origin, Vector3.ZERO])


## The gizmo's materials, one per role and pass. Both passes live in the TRANSPARENT queue
## (alpha 1, so they look opaque) because that queue draws after every opaque part and sorts by
## render_priority - the one ordering the engine guarantees. The dim pass ignores depth; the
## bright pass honours it. See GIZMO_DIM_PRIORITY.
##
## RETIRED(2026-09-02): the gizmo on _line_material, an OPAQUE no_depth_test material. Opaque
## draw order is not depth-sorted, so whether a handle showed through a part depended on which
## mesh the renderer happened to draw first - "it goes through the part rather than being
## visible outside the part".
func _gizmo_material(role: String, occluded: bool) -> StandardMaterial3D:
	var key: String = "%s|%d" % [role, int(occluded)]
	if _gizmo_materials.has(key):
		return _gizmo_materials[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if occluded:
		m.no_depth_test = true
		m.render_priority = GIZMO_DIM_PRIORITY
		m.albedo_color = _dim_role_color(role)
	else:
		m.no_depth_test = false
		m.render_priority = GIZMO_BRIGHT_PRIORITY
		m.albedo_color = _role_color(role)
	m.albedo_color.a = 1.0
	_gizmo_materials[key] = m
	return m


## The darker palette entry a role's dim pass wears: the second band of the ramp the role
## belongs to, so it is an exact palette colour and still reads as "the same handle, behind".
func _dim_role_color(role: String) -> Color:
	if _theme != null:
		var ramp: PackedColorArray = _theme.ramp_for(
			"part_selected" if role == "selection" else "part"
		)
		if ramp.size() >= 2:
			return ramp[1]
	return _role_color(role).darkened(0.5)


func _append_triangles(
	mesh: ImmediateMesh, tris: PackedVector3Array, material: StandardMaterial3D
) -> void:
	if tris.size() < 3:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for p: Vector3 in tris:
		mesh.surface_add_vertex(p)
	mesh.surface_end()


## Metres per inner-viewport pixel at the selection's distance, for the gizmo's screen floors.
## Pushed by ShipView3D on every camera move; the gizmo is rebuilt only when it moved enough
## to change a floor by a visible amount (HANDLE_PX_TOLERANCE).
func set_handle_pixel_size(m_per_px: float) -> void:
	var next: float = maxf(m_per_px, 0.0)
	if _m_per_px > 0.0 and absf(next - _m_per_px) <= _m_per_px * HANDLE_PX_TOLERANCE:
		return
	_m_per_px = next
	if _handles != null:
		_refresh_handles()


## The seam a part stands on, in its own local frame, for ShipHandles' hit test. IDENTITY, and
## [method part_has_seam] false, when it has none.
func part_seam(pid: String) -> Transform3D:
	var v: PartVisual = _visuals.get(pid, null)
	return v.seam_local if v != null else Transform3D.IDENTITY


func part_has_seam(pid: String) -> bool:
	var v: PartVisual = _visuals.get(pid, null)
	return v != null and v.has_seam


## Hide every part and the gizmo behind the exploded view, or bring them back. The visuals
## are kept, not destroyed: assembling again is a visibility flip, not a rebuild.
func set_exploded(on: bool, covered: PackedStringArray = PackedStringArray()) -> void:
	# With [param covered] given, only the parts the bake COVERS hide (the baked view, ADR
	# 0028): a part placed since the bake still shows as its primitive, so the resolved ship stays
	# on screen while the player works and a new part is not invisible until the next bake.
	var next_covered: Dictionary = {}
	if on:
		for pid: String in covered:
			next_covered[pid] = true
	var hide_all: bool = on and covered.is_empty()
	if hide_all == _exploded and next_covered == _covered:
		return
	_exploded = hide_all
	_covered = next_covered
	for key: Variant in _visuals.keys():
		_apply_visibility(_visuals[key])
	_refresh_handles()


## True when the bake covers [param pid] (its piece stands where the primitive would).
func _is_covered(pid: String) -> bool:
	if _covered.is_empty():
		return false
	return _covered.has(pid) or _covered.has(ShipSymmetry.source_of_twin(pid))


func is_exploded() -> bool:
	return _exploded


## The [solid, wire] materials something drawn beside the parts should wear so it reads as one -
## the exploded view's module bakes. `wire` is null in the modes that draw no wireframe, and the
## caller hides its own wire node then. RETIRED(2026-09-02): solid_material_for(), which pinned
## the modules to SHADED_WIRE whatever the dropdown said - "doesnt render it anything other then
## flat".
func materials_for(mode: int, selected: bool) -> Array:
	var solid: Material = _solid_material(mode, selected, false)
	var wire: Material = null
	if mode != DisplayMode.FLAT and mode != DisplayMode.FRESNEL:
		wire = _wire_material(mode, selected)
	return [solid, wire]


## The INSIDE mode's materials, one per named surface of a baked piece, as
## `{"exterior": Material, "interior": Material, "cut": Material, "wire": Material}`.
##
## The materials of the INTERIOR mode, per named surface (ADR 0022, corrected in ADR 0024):
## "showing only the inner mesh faces (excluding their back faces) and the exterior mesh back
## faces (excluding their outward facing faces) yields the interior view." The interior
## surface draws its FRONT faces only, the exterior surface its BACK faces only, the cuts (the
## wall thickness at every opening) both sides; nothing is translucent and there is no wire, so
## the near wall is simply not there and the far cavity wall faces the camera from any angle.
func inside_materials(selected: bool) -> Dictionary:
	# CLAY REACHES A BAKED PIECE (ADR 0049), and this is the set a baked piece wears - the exploded
	# view asks for it by name. Without this branch fly mode would show blue clay on the preview
	# primitives and teal on the finished hull, which is the one thing it is most for: "flying
	# around a finished hull is the best thing this mode does".
	var clay: bool = _mode == DisplayMode.CLAY
	var base_mode: int = DisplayMode.CLAY if clay else DisplayMode.SHADED_WIRE
	# The mode is in the key because this set is no longer always the same one.
	var key: String = (
		"inside|%d|%d|%s" % [int(selected), base_mode, "/".join(hidden_layers)]
	)
	if _solid_materials.has(key):
		return _solid_materials[key]
	# The faceted shader is cull_disabled by design (mirrored twins, F7); here each surface is
	# culled to the one side the mode wants. Measured before this: the interior surface drew both
	# its sides and the ship read solid again.
	# Literally what ADR 0022 asks for, now that a baked piece is wound the way it says it is: the
	# interior surface draws its FRONT faces (cull "back"), so the far cavity wall faces the camera
	# and the near one is gone, and the exterior draws its BACK faces (cull "front"), so the near
	# outer wall is not in the way and the far wall shows its inner side.
	#
	# RETIRED(ADR 0037): the two were the other way round, and had to be. Every baked piece came
	# back from the engine INSIDE OUT (`_read_raw` read its triangles in the engine's order), so
	# each surface presented Godot the face it does not now, and this mode was the one place in the
	# builder that culled by side and therefore the one place the inversion showed - as the near
	# outer wall drawing as a solid blob and the far cavity wall as a black hole (ADR 0028). The
	# read is fixed; the compensation comes off with it.
	# THE WALL LAYER COMES OFF HERE (ADR 0046). A walled seam authors no plate - the two cavities
	# simply do not merge - so the wall is each room's own surface standing where its neighbour
	# pushed in, and taking it away leaves the open room the pair would otherwise be: "walls should
	# be isolated from the shape its actually apart of, such that when walls layer is removed you
	# see an open room" (2026-09-25). INTERIOR is the mode that looks into rooms, so it is the mode
	# that drops them; the surface is named on every mesh, so any other view can drop it too.
	var out: Dictionary = {
		"exterior": _faceted_material(base_mode, selected, false, "front"),
		"interior": _faceted_material(base_mode, selected, false, "back"),
		"cut": _faceted_material(base_mode, selected, false),
		# A wall wears the CUT material: both sides drawn, because a wall is the one surface the
		# camera can legitimately meet from either room.
		"wall": _faceted_material(base_mode, selected, false),
		# What a DOOR leaf is shaded from. Never dropped with the cut layer - a leaf is its own
		# thing and has its own switch - so it is kept aside before the layers come off.
		"cut_solid": _faceted_material(base_mode, selected, false),
		"wire": null,
	}
	for name: String in ["exterior", "interior", "cut", "wall", "cut_solid"]:
		var m: ShaderMaterial = out[name] as ShaderMaterial
		m.set_shader_parameter("cut_plane", _cut_plane)
		if not clay:
			m.set_shader_parameter("depth_strength", INTERIOR_DEPTH_STRENGTH)
	# The cavity wall is a bowl, and a bowl lit flat reads as a ball (measured: "filled solid").
	# Strong directional shading with a low floor makes it shade bright-to-dark the way a hollow
	# does; the far outer wall's inner side keeps a higher floor so the wall thickness reads.
	#
	# NOT IN CLAY. These two ambients are the whole reason the cavity reads as hollow under a fixed
	# world light - and in CLAY the light is the player's torch, so an ambient floor of 0.45 (let
	# alone 0.62) would flood the room the torch is meant to be the only thing lighting. Clay keeps
	# the single ambient _faceted_material already set from `flying`.
	if not clay:
		(out["interior"] as ShaderMaterial).set_shader_parameter("ambient", INTERIOR_CAVITY_AMBIENT)
		(out["exterior"] as ShaderMaterial).set_shader_parameter("ambient", INTERIOR_AMBIENT)
	# THE LAYERS COME OFF LAST, once every material is shaded - a dropped one is swapped for a
	# fully transparent material rather than left out, because a surface with no override would
	# simply fall back to the mesh's own and draw anyway.
	for layer: String in hidden_layers:
		if out.has(layer):
			out[layer] = _hidden_material()
	_solid_materials[key] = out
	return out


## ISOLATION (ADR 0024): [param instance_id] is the component instance being edited, or "" to
## close it; [param washed] is what everything outside it wears (dim and translucent, made by
## the view from the theme). While open, a pick inside resolves to the inner part rather than
## the instance, so the component's own parts can be selected and edited one by one -
## SketchUp's double-click. [method part_id_for] and the materials read it.
func set_isolated(instance_id: String, washed: Material = null) -> void:
	if instance_id == _isolated and (washed == null or washed == _washed):
		return
	_isolated = instance_id
	if washed != null:
		_washed = washed
	for key: Variant in _visuals.keys():
		_apply_materials(_visuals[key])


## True when [param pid] (a visual's id, expanded or not) belongs to the isolated instance.
func _in_isolation(pid: String) -> bool:
	if _isolated.is_empty():
		return false
	return ShipSymmetry.source_of_twin(ShipComponents.instance_of(pid)) == _isolated


## True when `mode` draws the solid at all.
static func mode_shows_solid(mode: int) -> bool:
	return mode != DisplayMode.WIREFRAME


## The stored orientation of a part, or zero when it is not a document part (a derived twin is
## never the selection, but the lookup has to be safe anyway).
func _rot_of(pid: String) -> Vector3:
	if _doc == null:
		return Vector3.ZERO
	var part: ShipPart = _doc.parts.get(pid, null) as ShipPart
	return part.rot if part != null else Vector3.ZERO


func _free_handles() -> void:
	if is_instance_valid(_handles):
		_handles.queue_free()
	_handles = null


## A closed local-space loop as line-segment pairs.
func _append_loop(out: PackedVector3Array, loop: PackedVector3Array) -> void:
	var count: int = loop.size()
	if count < 2:
		return
	for i: int in count:
		out.append(loop[i])
		out.append(loop[(i + 1) % count])


## A three-axis cross at `centre` with arms of `arm` metres, as line-segment pairs.
func _append_cross(out: PackedVector3Array, centre: Vector3, arm: float) -> void:
	out.append(centre - Vector3(arm, 0.0, 0.0))
	out.append(centre + Vector3(arm, 0.0, 0.0))
	out.append(centre - Vector3(0.0, arm, 0.0))
	out.append(centre + Vector3(0.0, arm, 0.0))
	out.append(centre - Vector3(0.0, 0.0, arm))
	out.append(centre + Vector3(0.0, 0.0, arm))


## One PRIMITIVE_LINES surface, skipped entirely when there is nothing to draw - an empty
## surface_begin/surface_end pair is a valid but pointless draw call every frame.
func _append_lines(
	mesh: ImmediateMesh, points: PackedVector3Array, material: StandardMaterial3D
) -> void:
	if points.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for p: Vector3 in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()


## Resolve a physics collider back to a part id. "" when the node is not one of ours.
##
## An expanded component part ("<instance>/<inner>") resolves to ITS INSTANCE: a component is one
## part to the player - one row in the tree, one selection, one thing to move - and its inner
## parts have no id the rest of the harness could act on. A twin's expanded part resolves to the
## twin, which the builder then resolves to the source as it does for any twin.
func part_id_for(node: Node) -> String:
	if node == null:
		return ""
	if node.has_meta(PART_META):
		return _resolve_pick(str(node.get_meta(PART_META)))
	var parent: Node = node.get_parent()
	if parent != null and parent.has_meta(PART_META):
		return _resolve_pick(str(parent.get_meta(PART_META)))
	return ""


## The id a picked visual stands for: its instance - or, inside the isolated component, the
## inner part itself (ADR 0024). A pick on the isolated instance's own proxy (its definition
## root) is that root's expanded id, which the instance's key alone cannot say; it stays the
## instance.
func _resolve_pick(raw: String) -> String:
	if not _isolated.is_empty() and ShipComponents.is_expanded_id(raw) and _in_isolation(raw):
		return raw
	return ShipComponents.instance_of(raw)


## Union of every part's preview mesh AABB, in this node's local space. Empty when the
## scene holds nothing, which the camera treats as "nothing to frame".
func scene_aabb() -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for key: Variant in _visuals.keys():
		var v: PartVisual = _visuals[key]
		if v.solid == null or v.solid.mesh == null:
			continue
		# The instance transform already carries ResolvedShape.scale, so this is the real
		# extent, not the unscaled mesh's.
		var box: AABB = v.solid.transform * v.solid.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


# ---------------------------------------------------------------- materials


## Rebuild every cached material against the current palette. Called after a palette flip
## (ShipTheme.palette_changed) so an alerting budget recolours the 3D view too.
func _set_hidden_layers(layers: PackedStringArray) -> void:
	if layers == hidden_layers:
		return
	hidden_layers = layers
	refresh_materials()


## ONE FLAG, THREE CONSEQUENCES, because all three follow from the same fact: the gizmo goes away,
## CLAY's ambient floor drops to [constant CLAY_AMBIENT_FLY], and the shader's fixed world sun
## stands down so the torch is the only light there is. `refresh_materials` rebuilds the handles,
## so the gizmo needs no separate call.
func _set_flying(on: bool) -> void:
	if on == flying:
		return
	flying = on
	refresh_materials()


func _set_edit_tools(mask: int) -> void:
	if mask == edit_tools:
		return
	edit_tools = mask
	_refresh_handles()


func refresh_materials() -> void:
	_solid_materials.clear()
	_wire_materials.clear()
	_ghost_materials.clear()
	_line_materials.clear()
	_gizmo_materials.clear()
	for key: Variant in _visuals.keys():
		_apply_materials(_visuals[key])
	if is_instance_valid(_ghost):
		_ghost.material_override = _ghost_material(_ghost_state)
	# The overlays bake their material into the ImmediateMesh surface, so a palette flip has
	# to regenerate the geometry rather than just re-point an override.
	_refresh_handles()


func _apply_visibility(v: PartVisual) -> void:
	if v == null:
		return
	# A suppressed part is the one being re-placed: its ghost stands in for it. An instance
	# being re-placed takes its expanded parts with it, and every one of them takes its
	# symmetry twin: the ghost shows a twin of its own, so the placed one would sit stale at
	# the old position beside it.
	var owner: String = ShipSymmetry.source_of_twin(ShipComponents.instance_of(v.pid))
	var shown: bool = owner != _suppressed and not _exploded and not _is_covered(v.pid)
	v.solid.visible = shown and _mode != DisplayMode.WIREFRAME
	# FRESNEL draws no wireframe: the rim IS the edge, and a bright wire over it would bury the
	# very thing the mode exists to show.
	v.wire.visible = shown and _mode != DisplayMode.FLAT and _mode != DisplayMode.FRESNEL


func _apply_materials(v: PartVisual) -> void:
	if v == null:
		return
	_apply_visibility(v)
	if not _isolated.is_empty() and not _in_isolation(v.pid) and _washed != null:
		v.solid.material_override = _washed
		v.wire.visible = false
		return
	v.solid.material_override = _solid_material(_mode, v.selected, v.flipped)
	v.wire.material_override = _wire_material(_mode, v.selected)


## Returns Material, not StandardMaterial3D: FLAT and SHADED_WIRE use the faceted ShaderMaterial
## that gives parts their depth (see shaders/part_faceted.gdshader and FOLLOWUPS F7); only XRAY
## still wants StandardMaterial3D's alpha/no-depth behaviour.
func _solid_material(mode: int, selected: bool, flipped: bool) -> Material:
	var key: String = "%d|%d|%d" % [mode, int(selected), int(flipped)]
	if _solid_materials.has(key):
		return _solid_materials[key]

	if mode == DisplayMode.INSIDE:
		# A preview part has one surface, so it wears the exterior's two passes: opaque backs,
		# translucent fronts. The exploded view splits a piece's surfaces and does better.
		var exterior: Material = inside_materials(selected)["exterior"]
		_solid_materials[key] = exterior
		return exterior
	if mode != DisplayMode.XRAY:
		var faceted: ShaderMaterial = _faceted_material(mode, selected, flipped)
		_solid_materials[key] = faceted
		return faceted

	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.metallic = 0.0
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# "Flat-shaded" here means the low-spec, unlit-adjacent read the palette quantizer
	# expects, not true per-face normals: Godot's StandardMaterial3D has no faceting flag
	# and the primitive meshes ship smooth normals. Since every pixel lands on one of 16
	# palette entries anyway, the difference is largely quantized away. A real faceted
	# look would need a custom spatial shader; deliberately deferred.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Solid parts sit at "text_dim", NOT "line". A shaded material multiplies its albedo by
	# the incoming light, so an already mid-dark albedo (line, palette index 5) lands on the
	# BACKGROUND entry once the quantizer rounds it -- the first windowed render showed the
	# grid floor and no ship at all, with the mesh present, visible, and correctly framed.
	# The albedo has to start high enough up the ramp that the darkest lit face still
	# quantizes to something visible.
	var role: String = "text_dim"
	if selected:
		role = "selection"
	if mode == DisplayMode.XRAY:
		role = "ghost" if not selected else "selection"
	m.albedo_color = _role_color(role)

	if mode == DisplayMode.XRAY:
		# See buried parts: unlit, translucent, both faces, and ignoring depth so a part
		# inside the hull still reads.
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = XRAY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
	elif flipped:
		# Mirror derivative: reflected basis flips winding, so cull the other face.
		m.cull_mode = BaseMaterial3D.CULL_FRONT
	else:
		m.cull_mode = BaseMaterial3D.CULL_BACK

	_solid_materials[key] = m
	return m


## Solid parts, with their own banded lambert term.
##
## The engine's lighting path renders these black in this SubViewport (FOLLOWUPS F7), so the
## shading is computed in the shader against a fixed world direction. Without this, every face is
## one flat colour and SHADED_WIRE is indistinguishable from FLAT — which is exactly what shipped
## and exactly what the author reported.
## A material that draws nothing and occludes nothing - how a named surface is taken OUT of a mesh
## that was built with it in.
##
## A null override would restore the mesh's own material and draw the surface, which is the
## opposite. Alpha zero under alpha blending writes no colour, and Godot's default depth draw for a
## transparent material is opaque-only, so it writes no depth either: the faces behind it show
## through, which is the whole point of dropping the layer.
func _hidden_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _faceted_material(
	mode: int, selected: bool, _flipped: bool, cull: String = ""
) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = _faceted_shader(cull)
	m.set_shader_parameter("light_dir", FACET_LIGHT_DIR)
	var fresnel: bool = mode == DisplayMode.FRESNEL
	var clay: bool = mode == DisplayMode.CLAY
	if clay:
		# STATIC CLAY is matte but LIT: the fixed world lambert stays at full strength and the
		# flatness comes from the three-band ramp.
		#
		# CLAY IN THE VOID STANDS THE SUN DOWN ENTIRELY. This is the fix for the first capture,
		# which came out as brightly lit as static clay however far the ambient floor dropped: the
		# shader's `light_dir` is a FIXED WORLD DIRECTION that knows nothing about flying, so a face
		# turned toward it still climbed to the top band and the torch was a rounding error on top.
		# With `lambert_strength` at 0 the body sits at `ambient` (0.12) and the ONLY thing that can
		# lift a fragment off that floor is the torch - which is what "completely dark environment
		# like deep void of space, where a flashlight is attached to camera" actually asks for.
		var dark: bool = flying
		m.set_shader_parameter("ambient", CLAY_AMBIENT_FLY if dark else CLAY_AMBIENT)
		m.set_shader_parameter("depth_strength", 0.0 if dark else CLAY_DEPTH_STRENGTH)
		m.set_shader_parameter("lambert_strength", 0.0 if dark else 1.0)
		m.set_shader_parameter("rim_strength", CLAY_RIM_STRENGTH)
		m.set_shader_parameter("rim_power", CLAY_RIM_POWER)
	else:
		m.set_shader_parameter("ambient", FRESNEL_AMBIENT if fresnel else FACET_AMBIENT)
		m.set_shader_parameter("depth_strength", 0.0 if fresnel else FACET_DEPTH_STRENGTH)
		# The body goes dark in FRESNEL: without this the lambert term alone still carries a lit
		# face to the top band and the rim has nothing left to say.
		m.set_shader_parameter("lambert_strength", 0.0 if fresnel else 1.0)
		m.set_shader_parameter(
			"rim_strength", FRESNEL_RIM_STRENGTH if fresnel else FACET_RIM_STRENGTH
		)
		m.set_shader_parameter("rim_power", FRESNEL_RIM_POWER if fresnel else FACET_RIM_POWER)
	_apply_ramp(m, "part_selected" if selected else "part", fresnel, clay)
	_apply_depth(m)
	_apply_torch(m)
	# Mirrored twins need no special case here: the shader runs cull_disabled and flips the
	# normal on back faces via FRONT_FACING, so a negative-determinant basis shades correctly
	# with this same material.
	return m


## The faceted shader as authored (cull_disabled), or the same code culling one side: "back"
## draws front faces only, "front" draws back faces only (ADR 0024, the INTERIOR mode). The
## shader flips its normal on back faces itself, so the culled variants shade the same way.
## Built once from the authored file by editing its render_mode line - one source of truth.
func _faceted_shader(cull: String) -> Shader:
	if _faceted_shaders.has(cull):
		return _faceted_shaders[cull]
	var base: Shader = load(FACETED_SHADER) as Shader
	if cull.is_empty():
		_faceted_shaders[cull] = base
		return base
	var variant: Shader = Shader.new()
	variant.code = base.code.replace("cull_disabled", "cull_" + cull)
	_faceted_shaders[cull] = variant
	return variant


## Upload a named ShipTheme ramp as the shader's shading bands.
##
## The ramp array is a FIXED vec3[8] in the shader, so it is always filled to 8 - a short upload
## leaves stale entries behind from whatever was there before, and `ramp_size` is what actually
## bounds the lookup. The last real colour is repeated into the tail so even a mis-set ramp_size
## reads a sane colour rather than black.
func _apply_ramp(
	m: ShaderMaterial, ramp_name: String, fresnel: bool = false, clay: bool = false
) -> void:
	var colors: PackedColorArray = PackedColorArray()
	if _theme != null:
		colors = _theme.ramp_for(ramp_name)
	if colors.size() < 2:
		colors = PackedColorArray([_role_color("line"), _role_color("text_dim")])
	if fresnel:
		colors = _fresnel_ramp(ramp_name, colors)
	elif clay:
		colors = _clay_ramp(colors, ramp_name)
	var used: int = mini(colors.size(), 8)
	var vecs: PackedVector3Array = PackedVector3Array()
	for i: int in range(8):
		# LINEAR, not raw sRGB. See the `ramp` note in shaders/part_faceted.gdshader: a bare vec3
		# uniform has no source_color hint, so an sRGB value uploaded here is read as linear and
		# gamma-encoded on output, which brightened every band and collapsed two of the four onto
		# one palette entry. BaseMaterial3D.albedo_color does this conversion for you; a raw
		# uniform does not.
		var c: Color = colors[mini(i, used - 1)].srgb_to_linear()
		vecs.append(Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("ramp", vecs)
	m.set_shader_parameter("ramp_size", used)


## The two-entry ramp DisplayMode.FRESNEL uses: a dark body and the role's own brightest band for
## the rim. Two entries, not four, because with the lambert term stood down nothing lands in the
## middle of a ramp anyway - the body sits at the bottom and the rim climbs to the top.
##
## The BODY is the palette's `grid` entry (#153237), one step off the background: the `part`
## ramp's own darkest band is a mid-teal, and with it the mode came out as a flat part with a
## slightly brighter edge rather than a rim render. A SELECTED part keeps its own ramp's darkest
## band instead, which is already dark and is warm, so the selection still reads as amber.
func _fresnel_ramp(ramp_name: String, colors: PackedColorArray) -> PackedColorArray:
	var body: Color = colors[0]
	if ramp_name != "part_selected":
		body = _role_color("grid")
	return PackedColorArray([body, colors[colors.size() - 1]])


## CLAY's ramp: three bands, matte. A fourth reads as polish.
##
## MEASURED, TWICE. The first version trimmed the four-entry part ramp from its DARK end, on the
## reasoning that keeping the top band lets a lit face read as lit. In the void that was exactly
## wrong: it threw away the only dark colour there was, so the body floor sat at a mid blue
## (#3a68a8) and the ship came out uniformly bright however far `ambient` dropped and however
## strong the torch was. There was nothing left to BE dark with.
##
## So the bands are picked across the ramp rather than off one end, and in the void the body is
## replaced outright by a near-black - the same substitution [method _fresnel_ramp] makes, for the
## same reason: the mode needs a floor the palette's own part ramp does not contain.
##
## A SELECTED PART KEEPS ITS OWN DARKEST BAND as the body in both cases, because that band is warm
## and already dark, so the selection still reads amber against the blue (the warm ramp is held
## byte-identical in the clay variant precisely so this works for free).
func _clay_ramp(colors: PackedColorArray, ramp_name: String) -> PackedColorArray:
	var last: int = colors.size() - 1
	if last < 1:
		return colors
	var top: Color = colors[last]
	var mid: Color = colors[maxi(last - 1, 0)]
	var body: Color = colors[0]
	if flying and ramp_name != "part_selected":
		# THE VOID. `grid` is one step off the background, so an unlit face is very nearly the
		# blackness behind it and the torch is the only thing that can lift a fragment off it.
		body = _role_color("grid")
	return PackedColorArray([body, mid, top])


func _apply_depth(m: ShaderMaterial) -> void:
	m.set_shader_parameter("depth_near", _depth_near)
	m.set_shader_parameter("depth_far", _depth_far)


## Distance-cue range, in metres from the camera. ShipView3D derives it from the orbit distance
## and the scene bounds so the ramp always spans the model rather than a fixed world range - at a
## fixed range the cue would wash out entirely on a zoomed-in part and clip on a zoomed-out ship.
func _set_torch(t: Dictionary) -> void:
	var pos: Vector3 = t.get("pos", Vector3.ZERO)
	var dir: Vector3 = t.get("dir", Vector3.FORWARD)
	var strength: float = float(t.get("strength", 0.0))
	var reach: float = float(t.get("reach", 14.0))
	var same: bool = (
		_torch_pos.is_equal_approx(pos)
		and _torch_dir.is_equal_approx(dir)
		and is_equal_approx(_torch_strength, strength)
		and is_equal_approx(_torch_range, reach)
	)
	if same:
		return
	torch = t
	_torch_pos = pos
	_torch_dir = dir
	_torch_strength = strength
	_torch_range = reach
	for key: Variant in _solid_materials.keys():
		var entry: Variant = _solid_materials[key]
		if entry is ShaderMaterial:
			_apply_torch(entry)
		elif entry is Dictionary:
			for name: Variant in entry as Dictionary:
				var mat: Variant = (entry as Dictionary)[name]
				if mat is ShaderMaterial:
					_apply_torch(mat)


func _apply_torch(m: ShaderMaterial) -> void:
	m.set_shader_parameter("torch_pos", _torch_pos)
	m.set_shader_parameter("torch_dir", _torch_dir)
	m.set_shader_parameter("torch_strength", _torch_strength)
	m.set_shader_parameter("torch_range", _torch_range)


func set_depth_range(near_m: float, far_m: float, cut_plane: Vector4 = NO_CUT) -> void:
	# [param cut_plane] is the INTERIOR mode's cutaway (ADR 0028): normal in xyz, distance in w;
	# only the interior materials wear it, every other mode keeps the shader's default.
	var same_depth: bool = (
		is_equal_approx(near_m, _depth_near) and is_equal_approx(far_m, _depth_far)
	)
	if same_depth and cut_plane.is_equal_approx(_cut_plane):
		return
	_depth_near = near_m
	_depth_far = far_m
	_cut_plane = cut_plane
	for key: Variant in _solid_materials.keys():
		var entry: Variant = _solid_materials[key]
		if entry is ShaderMaterial:
			_apply_depth(entry)
		elif entry is Dictionary:
			# The INTERIOR set: exterior, interior and cut, each a faceted variant.
			for name: Variant in entry as Dictionary:
				var mat: Variant = (entry as Dictionary)[name]
				if mat is ShaderMaterial:
					_apply_depth(mat)
					(mat as ShaderMaterial).set_shader_parameter("cut_plane", _cut_plane)
	if _ghost != null and _ghost.material_override is ShaderMaterial:
		_apply_depth(_ghost.material_override)


func _wire_material(mode: int, selected: bool) -> StandardMaterial3D:
	var key: String = "%d|%d" % [mode, int(selected)]
	if _wire_materials.has(key):
		return _wire_materials[key]

	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Edges are ALWAYS the brightest role, never the solid's role.
	#
	# This previously used "selection" when selected — the same role the SOLID uses when selected —
	# so a selected part drew amber edges on an amber body and the wireframe was literally
	# invisible. Unselected was barely better: solid "text_dim" (#41c8a9) against wire "accent"
	# (#79d8ab), two adjacent entries on the same teal ramp that the 16-colour quantizer renders
	# nearly identically. That is why SHADED+WIRE looked exactly like FLAT.
	#
	# "text" (#daf1e0, the brightest entry) reads against both the mid-teal unselected body and the
	# amber selected one.
	var role: String = "text"
	m.albedo_color = _role_color(role)
	if mode == DisplayMode.XRAY:
		m.no_depth_test = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.65

	_wire_materials[key] = m
	return m


## Translucent, unshaded, depth-test-free: the ghost is a hologram, not a solid.
##
## One role and one alpha per GhostState, so the palette alone tells the player what the
## click will do (SPEC section 8, API_CONTRACT_SPORE section 8):
##   DEFAULT      `accent`   - legal AND on a typed snap target. The good drop.
##   GHOST        `ghost`    - legal, loose on the surface. Deliberately the quieter of the two.
##   BAD_LOCATION `warning`, faint - nothing to land on; nearly invisible so it reads as "not
##                             going to happen" rather than as an error the player caused.
##   PREVENT      `warning`, strong - a gate refuses it, and validity_reason() says which.
##   INVALID      `text_dim` - there is nothing placeable at all.
func _ghost_material(state: int) -> StandardMaterial3D:
	var key: String = str(state)
	if _ghost_materials.has(key):
		return _ghost_materials[key]

	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.albedo_color = _role_color(_ghost_role(state))
	m.albedo_color.a = GHOST_ALPHA
	if state >= 0 and state < GHOST_STATE_ALPHA.size():
		m.albedo_color.a = GHOST_STATE_ALPHA[state]

	_ghost_materials[key] = m
	return m


func _ghost_role(state: int) -> String:
	match state:
		ShipPlacement.GhostState.DEFAULT:
			return "accent"
		ShipPlacement.GhostState.GHOST:
			return "ghost"
		ShipPlacement.GhostState.INVALID:
			return "text_dim"
	return "warning"


## Unshaded, both faces, no depth test: an overlay line has to read through the hull it is
## describing. Cached by role, and cleared wholesale by refresh_materials() on a palette flip.
func _line_material(role: String) -> StandardMaterial3D:
	if _line_materials.has(role):
		return _line_materials[role]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.albedo_color = _role_color(role)
	_line_materials[role] = m
	return m


func _role_color(role: String) -> Color:
	if _theme == null:
		return Color(0.35, 0.8, 0.7)
	return _theme.color_for_role(role)
