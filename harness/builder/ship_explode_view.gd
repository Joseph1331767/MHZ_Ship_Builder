class_name ShipExplodeView
extends Node3D

## The EXPLODED view: every module of the ship baked on its own - cut flat at the seam it stands
## on, its children's collars kept, its doors bored - and pulled off along its seam normal so the
## walls between rooms and the hatches cut into them can be seen. ADR 0008.
##
## "we want an auto explode btn that explodes all the modules apart revealing their internal
## hatch walls."
##
## BAKED, NOT SHIFTED. Sliding the preview meshes apart would show the same closed primitives in
## new places and no wall at all: a seam wall is INSIDE the assembled hull, and only a solid cut
## at the seam plane exposes it. So each module is a real [HullBake] of
## [method ShipSdf.module_view] - a closed shell with its interior, at a coarse cell chosen per
## module (ShipConfig.explode_cells_per_axis) so a whole ship explodes in seconds rather than the
## minutes a full-grid bake costs (FOLLOWUPS F5). One module per frame, so the status line can
## count up and the console never freezes.
##
## A MODULE IS A PART, AND STILL BEHAVES LIKE ONE (2026-09-02). Each one carries a pick body on
## [constant ShipSceneBuilder.PICK_LAYER] with the same `PART_META` a part's body carries, so the
## view's ordinary pick path selects it with no special case, and it wears the display mode's own
## materials and wireframe. Both were missing on the first cut - "exploded view does not let part
## selection, and doesnt render it anything other then flat".
##
## Lives beside ShipSceneBuilder under the view's SubViewport and borrows its materials, so a
## module shades exactly like the part it was baked from.

## One more module has baked. `done` of `total`.
signal progress(done: int, total: int)
## Every module has baked. `modules` is how many are on screen, `seams` how many the field had.
signal finished(modules: int, seams: int, ms: int)
## How far exploded the view is now, 0 (assembled) to 1 - on every animation frame and every
## position override, so a panel can follow.
signal amount_changed(amount: float)

const NODE_PREFIX: String = "module_"
## Floor on the per-module grid resolution, whatever the lever says.
const MIN_CELLS_PER_AXIS: int = 4

## Preview wall thickness, in grid cells. The cavity of a module is what shows its walls, and a
## shell thinner than a cell is invisible to the extractor - at the explode grid the real 0.15 m
## hull is often exactly that, and the second isosurface then dips in and out of resolvability and
## welds noise onto the outer surface. So a module previews at a wall this many cells thick, never
## thinner than the real one. The same "widen it until the grid can see it" rule [HullBake]
## applies to seam plates (ADR 0008), for the same reason and with the same honesty: it is a
## preview of where the walls are, not a measurement of how thick they are.
const WALL_PREVIEW_CELLS: float = 1.6

## How far each slice of a module is pulled off its cut, as a fraction of the explode gap, when
## no [ShipExplodeSettings] were handed over.
const HALF_GAP_FRACTION: float = 0.35

## Which separation moves a visual (ADR 0031): none (a whole piece, a door), the slice separation
## of a piece standing alone or a room shown whole, or the cluster chunks' own.
const SEP_NONE: int = 0
const SEP_PARTS: int = 1
const SEP_CLUSTER: int = 2
## Every visual remembers where it hangs, so the view can move it without a rebuild: the module
## whose offset it rides, its fundamental cell (ADR 0032) and the frame that cell was cut in, and
## which separation pulls it off its cut.
const META_MODULE: String = "explode_module"
const META_CELL: String = "explode_cell"
const META_FRAME: String = "explode_frame"
const META_KIND: String = "explode_kind"
## The cell of a visual that is not a cell - a whole piece, a door: it never slices.
const NO_CELL: Vector3i = Vector3i(-1, -1, -1)
## How the four slabs along an axis group, per slicer setting (ShipExplodeSettings OFF, BISECT,
## TRISECT): the way each slab is pulled. A bisection is slabs {0, 1 | 2, 3}, a trisection
## {0 | 1, 2 | 3} - the cuts at 1/3, 1/2 and 2/3 that every piece already carries (ShipCsgBake).
const GROUP_SIGN: Array = [[0, 0, 0, 0], [-1, -1, 1, 1], [-1, 0, 0, 1]]

## THE EXPLODE, ANIMATED (ADR 0032): the pieces travel from where they stand to where the settings
## put them over this long at speed 1 - "modules split from modules, then module chunk clusters
## separate, then parts 'slice' separate" (2026-09-21), a third of the way each.
const EXPLODE_S: float = 2.4

## THE DOORS (ADR 0029). Every piece at a hatched or doorway seam carries its own door over the
## opening - one per module, "so one can be closed or both" - built from the bake's door records
## by [method ShipDoors.leaves] at whatever amount it is open, and rebuilt as it swings.
## How long a door takes to swing, in seconds.
const DOOR_TWEEN_S: float = 0.35
## A door leaf wears its module's material with its ramp scaled by this: a darker plate, so a
## door reads as a door and not as more hull.
const DOOR_SHADE: float = 0.55


## One exploded module: the baked shell, its wireframe, and its pick body.
class Module:
	extends RefCounted

	var id: String = ""
	## The visuals, one per slice of the piece's slicing grid (ADR 0031) - "in manufacturing they
	## are made in 2 pieces" (2026-09-05) was the first grid - or one when it is not sliced.
	## `solid` is the first, for a check that wants one.
	var solids: Array[MeshInstance3D] = []
	var wires: Array[MeshInstance3D] = []
	var bodies: Array[StaticBody3D] = []
	## The door leaves this piece carries (ADR 0029), solids and their wires.
	var doors: Array[MeshInstance3D] = []
	var door_wires: Array[MeshInstance3D] = []
	var selected: bool = false

	var solid: MeshInstance3D:
		get:
			return solids[0] if not solids.is_empty() else null

	var wire: MeshInstance3D:
		get:
			return wires[0] if not wires.is_empty() else null

	var body: StaticBody3D:
		get:
			return bodies[0] if not bodies.is_empty() else null


var _scene: ShipSceneBuilder = null
var _sdf: ShipSdf = null
var _cfg: ShipConfig = null
var _queue: PackedStringArray = PackedStringArray()
var _offsets: Dictionary = {}
var _selected: Dictionary = {}
var _modules: Array[Module] = []
var _mesh_gen: ShipMeshGen = ShipMeshGen.new()
## Exact per-part solids from [ShipMeshBake], keyed by placed id. Empty falls back to the
## Surface Nets bake, which is still what a module made of several placed ids (an expanded
## component instance) uses - the exact bake is per PART, and combining several into one module
## solid is a boolean, which belongs with the seam work rather than here.
var _solids: Dictionary = {}
## The whole bake report, when the exact path handed one over: halves, split planes, rooms and
## the named-surface meshes the INSIDE mode reads.
var _bake: Dictionary = {}
## Explode a room as one whole shell rather than its pieces.
var _rooms_whole: bool = false
## The player's explode settings (ADR 0031): separations and slicing. Null falls back to the tuning
## pack's explode gap and the old half gap.
var _settings: ShipExplodeSettings = null
## Module id -> ship-space box, kept from [method show_modules] so [method relayout] can work the
## offsets out again.
var _boxes: Dictionary = {}
## The first stage's offsets (ADR 0032): every room parting from its neighbours as one body, its
## chunks riding it. [member _offsets] is the whole explode; the second stage is the difference.
var _stage_one: Dictionary = {}
## How far exploded, 0..1, and the tween moving it.
var _amount: float = 0.0
var _tween: Tween = null
## Cells are on screen (an exploded exact bake), so there is something to animate.
var _cells_built: bool = false
## ASSEMBLE is playing backwards; what to show when it lands (show_modules' arguments), if anything.
var _collapsing: bool = false
var _pending_whole: Array = []
## Where everything will be once fully exploded - what the camera frames while the pieces travel.
var _target_bounds: AABB = AABB()
var _has_target: bool = false
## The bake's door records (ADR 0029), and how far open each door is: key -> {side -> 0..1}.
## The amounts outlive [method clear] - a rebake does not shut every door.
var _doors: Array = []
var _door_open: Dictionary = {}
var _door_tweens: Dictionary = {}
## Door materials by the module material they shade, so a mode change makes each once.
var _door_materials: Dictionary = {}
var _isolated: String = ""
var _washed: Material = null
## ASSEMBLED: every piece where it stands, whole - the baked view, not the explode (ADR 0023).
var _assembled: bool = false
var _mode: int = 0
var _bounds: AABB = AABB()
var _has_bounds: bool = false
var _total: int = 0
var _started_ms: int = 0
var _showing: bool = false


func _ready() -> void:
	_mode = ShipSceneBuilder.DisplayMode.SHADED_WIRE
	set_process(false)


func setup(scene: ShipSceneBuilder) -> void:
	_scene = scene
	if scene != null:
		_mode = scene.get_display_mode()


## Start showing `sdf` exploded - or, with [param assembled], every piece where it stands (the
## baked view, ADR 0023). `selected` are the builder's selected doc ids; their modules wear the
## selection ramp so the player keeps their bearings among the pieces. `finished` fires when the
## last module is placed.
##
## AN EXPLODE OF CELLS IS ANIMATED (ADR 0032): built at once where the pieces stand, then carried
## out over EXPLODE_S / speed. Asked for the assembled view while an ASSEMBLE is playing backwards,
## the view waits for it to land; asked to explode the same bake again mid-way, it turns round.
func show_modules(
	sdf: ShipSdf,
	cfg: ShipConfig,
	selected: PackedStringArray,
	solids: Dictionary = {},
	assembled: bool = false
) -> void:
	if assembled and _collapsing:
		_pending_whole = [sdf, cfg, selected, solids]
		return
	if not assembled and _collapsing and is_same(solids, _bake):
		_collapsing = false
		_pending_whole = []
		_animate_to(1.0, Callable())
		return
	_kill_tween()
	_collapsing = false
	_pending_whole = []
	var cells: bool = not assembled and not (solids.get("cells", {}) as Dictionary).is_empty()
	_amount = 0.0 if assembled or cells else 1.0
	_build(sdf, cfg, selected, solids, assembled)
	amount_changed.emit(_amount)
	if cells and _cells_built:
		_animate_to(1.0, Callable())


## ASSEMBLE, animated (ADR 0032): the cells travel back to where the pieces stand, then the view
## shows the whole pieces a following [method show_modules] asked for, or empties.
func collapse() -> void:
	if not has_cells_showing() or _amount <= 0.0 or not is_inside_tree():
		clear()
		return
	_collapsing = true
	_animate_to(0.0, _land_collapse)


## Cells of an exploded exact bake are on screen.
func has_cells_showing() -> bool:
	return _showing and _cells_built and not _assembled and not _collapsing


## The POSITION override: put everything [param amount] of the way exploded (0 assembled, 1 as the
## settings say), stopping any animation. Only an exploded view of cells moves.
func set_amount(amount: float) -> void:
	if not has_cells_showing():
		return
	_kill_tween()
	_set_amount(amount)


## How far exploded the view is, 0..1.
func amount() -> float:
	return _amount


func _set_amount(amount: float) -> void:
	_amount = clampf(amount, 0.0, 1.0)
	_place_all()
	amount_changed.emit(_amount)


## Tween [member _amount] to [param target] at the settings' speed, then call [param done].
func _animate_to(target: float, done: Callable) -> void:
	_kill_tween()
	var span: float = absf(target - _amount)
	if span <= 1.0e-4 or not is_inside_tree():
		_set_amount(target)
		if done.is_valid():
			done.call()
		return
	var speed: float = _settings.speed if _settings != null else 1.0
	_tween = create_tween()
	_tween.tween_method(_set_amount, _amount, target, EXPLODE_S * span / maxf(speed, 0.01))
	if done.is_valid():
		_tween.tween_callback(done)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _land_collapse() -> void:
	_collapsing = false
	var args: Array = _pending_whole
	_pending_whole = []
	if args.is_empty():
		clear()
		return
	_amount = 0.0
	_build(args[0], args[1], args[2], args[3], true)
	amount_changed.emit(_amount)


## Everything [method show_modules] puts on screen, built at once for an exact bake - every piece
## and every cell is already made, so there is nothing to spread over frames (the one-module-a-frame
## queue is the field fallback's, whose modules are baked here; for the exact path it read as "a
## slow pop in", 2026-09-21). Placed at the current [member _amount].
func _build(
	sdf: ShipSdf, cfg: ShipConfig, selected: PackedStringArray, solids: Dictionary, assembled: bool
) -> void:
	clear()
	_assembled = assembled
	# Either the bare solids, or the whole exact report (it carries a "solids" of its own).
	if solids.has("solids") and solids["solids"] is Dictionary:
		_bake = solids
		_solids = solids["solids"]
	else:
		_bake = {}
		_solids = solids
	_doors = _bake.get("doors", [])
	if sdf == null or cfg == null:
		return
	_sdf = sdf
	_cfg = cfg
	for pid: String in selected:
		_selected[ShipSymmetry.source_of_twin(pid)] = true
	# Modules in the field's own order, each with the union of its entries' boxes - what the
	# explode offsets measure a module's extent along its seam normal from.
	var boxes: Dictionary = {}
	for i: int in sdf.part_count():
		var pid: String = sdf.part_id_at(i)
		# A piece the engine baked is its own module, a component's inner pieces included (ADR
		# 0024: the inner seams give each its travel); only a part with no exact solid folds
		# into its component's module for the field fallback.
		var module: String = pid if _solids.has(pid) else ShipSeams.module_of(pid)
		if boxes.has(module):
			boxes[module] = (boxes[module] as AABB).merge(sdf.part_aabb(i))
		else:
			_queue.append(module)
			boxes[module] = sdf.part_aabb(i)
	# Assembled, nothing moves: the pieces sit exactly where the document puts them.
	_boxes = boxes
	if not assembled:
		_compute_offsets()
	# A room shown WHOLE is one module under its first member; the other members wait unseen.
	if _rooms_whole and _bake.has("rooms"):
		for members: PackedStringArray in _bake["rooms"]:
			if members.size() < 2:
				continue
			for i: int in range(1, members.size()):
				var at: int = _queue.find(members[i])
				if at >= 0:
					_queue.remove_at(at)
	_total = _queue.size()
	_started_ms = Time.get_ticks_msec()
	_showing = true
	visible = true
	if _queue.is_empty():
		finished.emit(0, sdf.seam_count(), 0)
		return
	for id: String in _queue:
		if not _solids.has(id):
			set_process(true)
			return
	while not _queue.is_empty():
		var id: String = _queue[0]
		_queue.remove_at(0)
		_bake_module(id)
	_measure_target()
	finished.emit(_modules.size(), sdf.seam_count(), Time.get_ticks_msec() - _started_ms)


func _process(_delta: float) -> void:
	if _queue.is_empty():
		set_process(false)
		return
	var id: String = _queue[0]
	_queue.remove_at(0)
	_bake_module(id)
	progress.emit(_total - _queue.size(), _total)
	if _queue.is_empty():
		set_process(false)
		finished.emit(_modules.size(), _sdf.seam_count(), Time.get_ticks_msec() - _started_ms)


## Take every module down. Safe to call when nothing is showing. The explode amount is left as it
## is: [method show_modules] sets it for what it builds next.
func clear() -> void:
	set_process(false)
	_kill_tween()
	_cells_built = false
	_collapsing = false
	_pending_whole = []
	_stage_one = {}
	_has_target = false
	for module: Module in _modules:
		for node: MeshInstance3D in module.solids:
			if is_instance_valid(node):
				node.queue_free()
		for node: MeshInstance3D in module.wires:
			if is_instance_valid(node):
				node.queue_free()
		for node: StaticBody3D in module.bodies:
			if is_instance_valid(node):
				node.queue_free()
		_free_doors(module)
	_modules.clear()
	_bake = {}
	_doors = []
	_queue = PackedStringArray()
	_offsets = {}
	_boxes = {}
	_selected = {}
	_bounds = AABB()
	_has_bounds = false
	_total = 0
	_showing = false
	_sdf = null
	_cfg = null
	_solids = {}
	_assembled = false


func is_showing() -> bool:
	return _showing


## Showing the pieces assembled (no offsets, no slices) rather than exploded - or on the way there.
func is_assembled() -> bool:
	return _assembled or _collapsing


## Still baking modules, or the pieces are still travelling.
func is_busy() -> bool:
	if _showing and not _queue.is_empty():
		return true
	return _tween != null and _tween.is_valid() and _tween.is_running()


func module_count() -> int:
	return _modules.size()


## The ship-space box round every module placed so far - or, exploding, round where they will be
## once fully apart, so the camera frames the spread while the pieces travel. Empty before the
## first.
func bounds() -> AABB:
	return _target_bounds if _has_target else _bounds


## Which display mode the modules wear. Forwarded from ShipView3D so the dropdown means the same
## thing exploded as assembled.
func set_display_mode(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	for module: Module in _modules:
		_apply_materials(module)


## Highlight the modules of the selected parts. A module is one part to the player, so an
## expanded component id and a twin both resolve to the instance the player clicked.
func set_selection(ids: PackedStringArray) -> void:
	var next: Dictionary = {}
	for pid: String in ids:
		next[ShipSymmetry.source_of_twin(pid)] = true
	_selected = next
	for module: Module in _modules:
		var want: bool = _is_selected(module.id)
		if want != module.selected:
			module.selected = want
			_apply_materials(module)


## One module's pick body, by module id, for a check that needs to look at it.
func module_body(id: String) -> StaticBody3D:
	for module: Module in _modules:
		if module.id == id:
			return module.body
	return null


## The module meshes on screen, for a check that wants to count or measure them: every half.
func module_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for module: Module in _modules:
		out.append_array(module.solids)
	return out


## The player's explode settings (ADR 0031). Held by reference: the panel writes into the same
## object, and [method relayout] reads it.
func set_settings(settings: ShipExplodeSettings) -> void:
	_settings = settings


## Move everything on screen to where the settings now put it - module offsets, cluster chunks and
## slices - without rebuilding a node. What every explode setting calls on every change (ADR 0032).
func relayout() -> void:
	if not _showing or _sdf == null or _cfg == null:
		return
	if not _assembled and not _collapsing:
		_compute_offsets()
		_measure_target()
	_place_all()


## Every visual to where it hangs at the current amount.
func _place_all() -> void:
	_bounds = AABB()
	_has_bounds = false
	for child: Node in get_children():
		if not (child is Node3D) or not child.has_meta(META_MODULE):
			continue
		var node: Node3D = child
		node.position = _placed_meta(node, _amount)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var box: AABB = node.transform * (node as MeshInstance3D).mesh.get_aabb()
			_bounds = _bounds.merge(box) if _has_bounds else box
			_has_bounds = true


## The box round every visual as it will stand fully exploded.
func _measure_target() -> void:
	_has_target = false
	if _assembled:
		return
	for child: Node in get_children():
		if not (child is MeshInstance3D) or not child.has_meta(META_MODULE):
			continue
		var node: MeshInstance3D = child
		if node.mesh == null:
			continue
		var box: AABB = Transform3D(Basis.IDENTITY, _placed_meta(node, 1.0)) * node.mesh.get_aabb()
		_target_bounds = _target_bounds.merge(box) if _has_target else box
		_has_target = true


func _placed_meta(node: Node3D, amount: float) -> Vector3:
	return _placed_at(
		str(node.get_meta(META_MODULE)),
		node.get_meta(META_CELL, NO_CELL) as Vector3i,
		node.get_meta(META_FRAME, Basis.IDENTITY) as Basis,
		int(node.get_meta(META_KIND, SEP_NONE)),
		amount
	)


## Whether an exploded room shows as its pieces or as one whole shell. When one is showing it
## is rebuilt on the spot.
func set_rooms_whole(on: bool) -> void:
	if on == _rooms_whole:
		return
	_rooms_whole = on
	# Rebuilt where the pieces are now - no animation from the start again.
	if _showing and _sdf != null and _cfg != null and not _collapsing:
		var selected: PackedStringArray = PackedStringArray()
		for id: String in _selected:
			selected.append(id)
		var bake: Dictionary = _bake if not _bake.is_empty() else _solids
		var travelling: bool = is_busy()
		_build(_sdf, _cfg, selected, bake, _assembled)
		if travelling and _cells_built:
			_animate_to(1.0, Callable())


# --- internals -----------------------------------------------------------------------------


## Bake one module and put it on screen at its explode offset. The cell is the coarser of the
## bake lever and the module's longest axis over explode_cells_per_axis, so a hull and a stud
## both resolve at a sensible count rather than the hull at millions and the stud at eight.
func _bake_module(id: String) -> void:
	# The exact path (ADR 0011): the part was tessellated analytically, so there is nothing to
	# extract and nothing to resolve - just place it. Its wireframe comes from the model edges
	# rather than from triangles, which is why a baked box shows twelve lines and not eighteen.
	var exact: PolyMesh = _solids.get(id, null) as PolyMesh
	if exact != null:
		if not exact.is_empty():
			_bake_exact(id, exact)
		return
	var view: ShipSdf = _sdf.module_view(id)
	if view.part_count() == 0:
		return
	var box: AABB = view.aabb().abs()
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	var cfg: ShipConfig = ShipConfig.from_dict(_cfg.snapshot())
	var cells: int = maxi(_cfg.explode_cells_per_axis, MIN_CELLS_PER_AXIS)
	cfg.bake_cell_m = maxf(_cfg.bake_cell_m, longest / float(cells))
	# See WALL_PREVIEW_CELLS: a wall the grid cannot resolve is not a thinner wall, it is noise.
	cfg.hull_thickness_m = maxf(_cfg.hull_thickness_m, cfg.bake_cell_m * WALL_PREVIEW_CELLS)
	var report: Dictionary = HullBake.bake(view, cfg, 0.0)
	var mesh: ArrayMesh = report.get("mesh", null) as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	_place_module(id, mesh, _mesh_gen.wire_from_mesh(mesh))


## The exact path: the piece - or, with rooms shown whole, the room's shell under its first
## member - drawn whole when ASSEMBLED (the baked view, ADR 0023) or when the bake brought no cells,
## and otherwise as its 64 fundamental cells (ADR 0032), each its own visual, grouped and pulled
## apart by the settings at every relayout.
func _bake_exact(id: String, exact: PolyMesh) -> void:
	_bake_exact_as(id, id, exact)


## [method _bake_exact] for a piece drawn under another module's offset: [param module_id] is
## where it sits, [param id] which piece of the bake it is (its own pick id).
func _bake_exact_as(module_id: String, id: String, exact: PolyMesh) -> void:
	# Which solid this module shows: with rooms whole and this id keeping a room's shell, the
	# shell; otherwise the piece. Each comes with its drawn (named-surface) mesh and its cells.
	var whole: PolyMesh = exact
	var whole_mesh: ArrayMesh = _bake.get("meshes", {}).get(id, null)
	var cells: Array = _bake.get("cells", {}).get(id, [])
	var kind: int = SEP_CLUSTER if _in_cluster(id) else SEP_PARTS
	if _rooms_whole and _bake.get("room_shells", {}).has(id):
		whole = _bake["room_shells"][id]
		whole_mesh = _bake.get("room_meshes", {}).get(id, null)
		cells = _bake.get("room_cells", {}).get(id, [])
		kind = SEP_PARTS
	if whole_mesh == null:
		whole_mesh = whole.to_array_mesh()
	if _assembled or cells.is_empty():
		_place_module_at(module_id, id, whole_mesh, whole.to_wire_mesh())
		return
	var frame: Basis = (_bake.get("frames", {}).get(id, Transform3D.IDENTITY) as Transform3D).basis
	var module: Module = Module.new()
	module.id = id
	module.selected = _is_selected(id)
	for entry: Dictionary in cells:
		var cell: Vector3i = entry["cell"]
		_add_visual_at(
			module,
			module_id,
			id,
			entry["mesh"],
			entry["wire"],
			cell,
			frame,
			"_c%d%d%d" % [cell.x, cell.y, cell.z],
			kind,
			true
		)
	_cells_built = true
	_add_doors(module, module_id)
	_apply_materials(module)
	_modules.append(module)


## Puts one baked module on screen at its explode offset, with its wireframe and pick body.
func _place_module(id: String, mesh: ArrayMesh, wire: Mesh) -> void:
	_place_module_at(id, id, mesh, wire)


## [method _place_module] for a piece of module [param module_id] picked as [param id].
func _place_module_at(module_id: String, id: String, mesh: ArrayMesh, wire: Mesh) -> void:
	var module: Module = Module.new()
	module.id = id
	module.selected = _is_selected(id)
	_add_visual_at(module, module_id, id, mesh, wire, NO_CELL, Basis.IDENTITY, "", SEP_NONE, false)
	_add_doors(module, module_id)
	_apply_materials(module)
	_modules.append(module)


## A module is highlighted when its id is selected or, for a piece of a component, when its
## instance is - the same rule the assembled scene uses.
func _is_selected(id: String) -> bool:
	var own: String = ShipSymmetry.source_of_twin(id)
	if _selected.has(own):
		return true
	if not ShipComponents.is_expanded_id(id):
		return false
	return _selected.has(ShipSymmetry.source_of_twin(ShipComponents.instance_of(id)))


## One visual of [param module] - a whole piece, or one fundamental cell - at module
## [param module_id]'s explode offset, the cell [param cell] of [param frame] pulled off its cut by
## the separation [param kind] names, with its wireframe and its pick body, picked as [param id].
## A cell picks by its box ([param box_pick]): a convex hull per cell is hundreds of hulls a ship.
func _add_visual_at(
	module: Module,
	module_id: String,
	id: String,
	mesh: ArrayMesh,
	wire: Mesh,
	cell: Vector3i,
	frame: Basis,
	suffix: String,
	kind: int,
	box_pick: bool
) -> void:
	# A node name cannot hold the slash of an expanded id or the tilde of a twin.
	var node_name: String = id.replace("/", "__").replace("~", "_") + suffix
	var placed: Transform3D = Transform3D(
		Basis.IDENTITY, _placed_at(module_id, cell, frame, kind, _amount)
	)

	# The exterior (with the cuts) and the interior are SEPARATE meshes (ADR 0028): the bake
	# names them as surfaces of one ArrayMesh, and the split here gives each its own node, so
	# the interior can be culled, hidden or picked on its own.
	var split: Array = _split_interior(mesh)
	var solid: MeshInstance3D = MeshInstance3D.new()
	solid.name = NODE_PREFIX + node_name
	solid.mesh = split[0]
	solid.transform = placed
	_hang(solid, module_id, cell, frame, kind)
	add_child(solid)
	module.solids.append(solid)
	if split[1] != null:
		var inner: MeshInstance3D = MeshInstance3D.new()
		inner.name = NODE_PREFIX + node_name + "_inner"
		inner.mesh = split[1]
		inner.transform = placed
		_hang(inner, module_id, cell, frame, kind)
		add_child(inner)
		module.solids.append(inner)

	var wire_node: MeshInstance3D = MeshInstance3D.new()
	wire_node.name = NODE_PREFIX + node_name + "_wire"
	wire_node.mesh = wire
	wire_node.transform = placed
	_hang(wire_node, module_id, cell, frame, kind)
	add_child(wire_node)
	module.wires.append(wire_node)

	# The pick body carries the module's DOC id under the same meta a part's body uses, so
	# ShipSceneBuilder.part_id_for() resolves it and the view's ordinary pick path selects it.
	#
	# CONVEX, exactly as a part's collider is (ShipMeshGen.collision_for). A trimesh built from
	# the shell was the obvious choice and did not work: measured, a body that was in the tree,
	# on the right layer and holding 1652 triangles was passed straight through by every ray,
	# with backface_collision on and off, in a space where a part's convex body was hit from the
	# same camera in the same frame. A convex hull is proven in this space, and it is the trade
	# ShipMeshGen already documents for a torus - filling a cavity costs a click near a hole and
	# buys a click anywhere else.
	var body: StaticBody3D = StaticBody3D.new()
	body.name = NODE_PREFIX + node_name + "_pick"
	body.collision_layer = ShipSceneBuilder.PICK_LAYER
	body.collision_mask = 0
	body.set_meta(ShipSceneBuilder.PART_META, id)
	body.transform = placed
	_hang(body, module_id, cell, frame, kind)
	var collider: CollisionShape3D = CollisionShape3D.new()
	if box_pick:
		var local: AABB = mesh.get_aabb()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = local.size.max(Vector3.ONE * 0.01)
		collider.shape = box
		collider.position = local.get_center()
	else:
		collider.shape = mesh.create_convex_shape(true, true)
	body.add_child(collider)
	add_child(body)
	module.bodies.append(body)

	var world_box: AABB = placed * mesh.get_aabb()
	if _has_bounds:
		_bounds = _bounds.merge(world_box)
	else:
		_bounds = world_box
		_has_bounds = true


## ISOLATION (ADR 0024): the instance being edited; modules outside it wear [param washed].
func set_isolated(instance_id: String, washed: Material = null) -> void:
	if instance_id == _isolated and (washed == null or washed == _washed):
		return
	_isolated = instance_id
	if washed != null:
		_washed = washed
	for module: Module in _modules:
		_apply_materials(module)


func _in_isolation(id: String) -> bool:
	return ShipSymmetry.source_of_twin(ShipComponents.instance_of(id)) == _isolated


func _apply_materials(module: Module) -> void:
	if _scene == null or module.solids.is_empty():
		return
	if not _isolated.is_empty() and _washed != null and not _in_isolation(module.id):
		for node: MeshInstance3D in module.solids:
			var mesh: Mesh = node.mesh
			if mesh != null:
				for i: int in mesh.get_surface_count():
					node.set_surface_override_material(i, null)
			node.material_override = _washed
		for node: MeshInstance3D in module.wires:
			node.visible = false
		_apply_door_materials(module, _washed, null, true)
		return
	if _mode == ShipSceneBuilder.DisplayMode.INSIDE:
		# Per named surface (ADR 0024): the interior's fronts, the exterior's backs, the cuts both
		# sides, no wire. A mesh without named surfaces (the field fallback) wears the exterior's.
		var mats: Dictionary = _scene.inside_materials(module.selected)
		for solid: MeshInstance3D in module.solids:
			solid.material_override = null
			solid.visible = true
			var mesh: Mesh = solid.mesh
			if mesh == null:
				continue
			var named: bool = false
			for i: int in mesh.get_surface_count():
				var name: String = mesh.surface_get_name(i)
				if mats.has(name):
					solid.set_surface_override_material(i, mats[name])
					named = true
			if not named:
				solid.material_override = mats["exterior"]
		for wire: MeshInstance3D in module.wires:
			wire.material_override = mats["wire"]
			wire.visible = mats["wire"] != null and wire.mesh != null
		_apply_door_materials(module, _door_material(mats["cut"]), null, true)
		return
	var pair: Array = _scene.materials_for(_mode, module.selected)
	for solid: MeshInstance3D in module.solids:
		var mesh: Mesh = solid.mesh
		if mesh != null:
			for i: int in mesh.get_surface_count():
				solid.set_surface_override_material(i, null)
		solid.material_override = pair[0]
		solid.visible = ShipSceneBuilder.mode_shows_solid(_mode)
	for wire: MeshInstance3D in module.wires:
		wire.material_override = pair[1]
		wire.visible = pair[1] != null and wire.mesh != null
	_apply_door_materials(
		module, _door_material(pair[0]), pair[1], ShipSceneBuilder.mode_shows_solid(_mode)
	)


# --- doors (ADR 0029) -------------------------------------------------------------------------


## Swings the door of [param key] (ShipDoors.DOOR_KEY) on [param side] (ShipDoors.SIDE_*) to
## [param amount] open (0 shut, 1 open), over DOOR_TWEEN_S when [param animate]. A door of a
## seam not on screen only remembers the amount for when it is.
func set_door_open(key: String, side: String, amount: float, animate: bool = true) -> void:
	var target: float = clampf(amount, 0.0, 1.0)
	var from: float = door_amount(key, side)
	var slot: String = key + "|" + side
	if _door_tweens.has(slot):
		var old: Tween = _door_tweens[slot]
		if old != null and old.is_valid():
			old.kill()
		_door_tweens.erase(slot)
	if not animate or not is_inside_tree() or is_equal_approx(from, target):
		_set_door_amount(target, key, side)
		return
	var tween: Tween = create_tween()
	tween.tween_method(
		Callable(self, "_set_door_amount").bind(key, side), from, target, DOOR_TWEEN_S
	)
	_door_tweens[slot] = tween


## Every door at once, without animation: `key -> {side -> amount}`, as the view keeps them.
func set_doors_open(states: Dictionary) -> void:
	for key: Variant in states:
		var sides: Variant = states[key]
		if typeof(sides) != TYPE_DICTIONARY:
			continue
		for side: Variant in sides as Dictionary:
			set_door_open(str(key), str(side), float((sides as Dictionary)[side]), false)


## How far open the door of [param key] on [param side] is: 0 when never touched.
func door_amount(key: String, side: String) -> float:
	var sides: Dictionary = _door_open.get(key, {})
	return float(sides.get(side, 0.0))


## The door leaf meshes on screen, for a check that wants to count them.
func door_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for module: Module in _modules:
		out.append_array(module.doors)
	return out


func _set_door_amount(amount: float, key: String, side: String) -> void:
	var sides: Dictionary = _door_open.get(key, {})
	sides[side] = amount
	_door_open[key] = sides
	for module: Module in _modules:
		if _carries_door(module.id, key, side):
			_free_doors(module)
			_add_doors(module, _module_of_piece(module.id))
			_apply_materials(module)


## Does the piece [param id] carry the door of [param key] on [param side]?
func _carries_door(id: String, key: String, side: String) -> bool:
	for door: Dictionary in _doors:
		if str(door[ShipDoors.DOOR_KEY]) == key and str(door[side]) == id:
			return true
	return false


## The module a piece is drawn under - itself, or with rooms whole the room's keeper.
func _module_of_piece(id: String) -> String:
	if _rooms_whole and _bake.has("rooms"):
		for members: PackedStringArray in _bake["rooms"]:
			if members.has(id):
				return members[0]
	return id


## The door leaves of every door [param module]'s piece is a side of, at [param module_id]'s
## explode offset, each as it stands at its current amount.
func _add_doors(module: Module, module_id: String) -> void:
	if _doors.is_empty():
		return
	var placed: Transform3D = Transform3D(
		Basis.IDENTITY, _offsets.get(module_id, Vector3.ZERO) as Vector3
	)
	var count: int = 0
	for door: Dictionary in _doors:
		for side: String in ShipDoors.SIDES:
			if str(door[side]) != module.id:
				continue
			var amount: float = door_amount(str(door[ShipDoors.DOOR_KEY]), side)
			for leaf: PolyMesh in ShipDoors.leaves(door, side, amount):
				if leaf.is_empty():
					continue
				count += 1
				var node_name: String = (
					NODE_PREFIX + module.id.replace("/", "__").replace("~", "_") + "_door%d" % count
				)
				var solid: MeshInstance3D = MeshInstance3D.new()
				solid.name = node_name
				solid.mesh = leaf.to_array_mesh()
				solid.transform = placed
				_hang(solid, module_id, NO_CELL, Basis.IDENTITY, SEP_NONE)
				add_child(solid)
				module.doors.append(solid)
				var wire: MeshInstance3D = MeshInstance3D.new()
				wire.name = node_name + "_wire"
				wire.mesh = leaf.to_wire_mesh()
				wire.transform = placed
				_hang(wire, module_id, NO_CELL, Basis.IDENTITY, SEP_NONE)
				add_child(wire)
				module.door_wires.append(wire)


func _free_doors(module: Module) -> void:
	for node: MeshInstance3D in module.doors:
		if is_instance_valid(node):
			node.queue_free()
	for node: MeshInstance3D in module.door_wires:
		if is_instance_valid(node):
			node.queue_free()
	module.doors.clear()
	module.door_wires.clear()


func _apply_door_materials(
	module: Module, solid_mat: Material, wire_mat: Material, show_solid: bool
) -> void:
	for node: MeshInstance3D in module.doors:
		node.material_override = solid_mat
		node.visible = show_solid and solid_mat != null
	for node: MeshInstance3D in module.door_wires:
		node.material_override = wire_mat
		node.visible = wire_mat != null and node.mesh != null


## [param base] - a module's material - darkened for a door: the same shader with its ramp
## scaled by DOOR_SHADE and no depth cue (a leaf is small, and the cue's range moves with the
## camera, which a copy would not follow). Cached per base material.
func _door_material(base: Material) -> Material:
	if base == null:
		return null
	var key: int = base.get_instance_id()
	if _door_materials.has(key):
		return _door_materials[key]
	var out: Material = base
	if base is ShaderMaterial:
		var dup: ShaderMaterial = (base as ShaderMaterial).duplicate()
		var ramp: Variant = dup.get_shader_parameter("ramp")
		if ramp is PackedVector3Array:
			var dark: PackedVector3Array = PackedVector3Array()
			for v: Vector3 in ramp as PackedVector3Array:
				dark.append(v * DOOR_SHADE)
			dup.set_shader_parameter("ramp", dark)
		dup.set_shader_parameter("depth_strength", 0.0)
		out = dup
	_door_materials[key] = out
	return out


## Where a visual sits [param amount] of the way exploded, in the three stages of ADR 0032:
## modules part from modules (the first third), then a room's chunks separate (the second), then
## the slices (the last) - "modules split from modules, then module chunk clusters separate, then
## parts 'slice' separate" (2026-09-21).
func _placed_at(
	module_id: String, cell: Vector3i, frame: Basis, kind: int, amount: float
) -> Vector3:
	var stage: Vector3 = _stages(amount)
	var full: Vector3 = _offsets.get(module_id, Vector3.ZERO)
	var first: Vector3 = _stage_one.get(module_id, Vector3.ZERO)
	var slice: Vector3 = _cell_shift(frame, cell, _modes(kind)) * _separation(kind)
	return first * stage.x + (full - first) * stage.y + slice * stage.z


## How far each of the three stages has run at [param amount]: a third of the way each.
static func _stages(amount: float) -> Vector3:
	var t: float = clampf(amount, 0.0, 1.0) * 3.0
	return Vector3(clampf(t, 0.0, 1.0), clampf(t - 1.0, 0.0, 1.0), clampf(t - 2.0, 0.0, 1.0))


## The distance a separation of [param kind] pulls a slice off its cut, from the settings.
func _separation(kind: int) -> float:
	if kind == SEP_NONE:
		return 0.0
	if _settings == null:
		return maxf(_cfg.explode_gap_m, 0.0) * HALF_GAP_FRACTION if _cfg != null else 0.0
	if kind == SEP_CLUSTER:
		return _settings.cluster_slice_separation_m
	return _settings.slice_separation_m


## The slicer settings a visual of [param kind] groups by, per axis (ShipExplodeSettings OFF,
## BISECT, TRISECT); the old single cut across Z when no settings were handed over.
func _modes(kind: int) -> Vector3i:
	if kind == SEP_NONE:
		return Vector3i.ZERO
	if _settings == null:
		return Vector3i(0, 0, ShipExplodeSettings.BISECT)
	var cluster: bool = kind == SEP_CLUSTER
	return Vector3i(
		_settings.mode_for(0, cluster),
		_settings.mode_for(1, cluster),
		_settings.mode_for(2, cluster)
	)


## Both stages' offsets from the current settings: the whole explode, and the first stage with
## every cluster chunk riding its room.
func _compute_offsets() -> void:
	_offsets = _offsets_for(_boxes, {})
	_stage_one = _offsets_for(_boxes, _riders())


## The module offsets for [param boxes], at the settings' separation, [param still] riding their
## hosts: none when the player turned separation off, the tuning pack's gap with no settings.
func _offsets_for(boxes: Dictionary, still: Dictionary) -> Dictionary:
	if _sdf == null or _cfg == null:
		return {}
	if _settings == null:
		return ShipSeams.explode_offsets(_sdf.seams(), _cfg, boxes, still)
	if not _settings.separate:
		return {}
	var cfg: ShipConfig = ShipConfig.from_dict(_cfg.snapshot())
	cfg.explode_gap_m = _settings.separation_m
	return ShipSeams.explode_offsets(_sdf.seams(), cfg, boxes, still)


## The chunks of every room of several whose seam holds them to another member of it: in the first
## stage they ride their room (ShipSeams.explode_offsets, `still`).
func _riders() -> Dictionary:
	var room_of: Dictionary = {}
	for members: PackedStringArray in _bake.get("rooms", []):
		if members.size() > 1:
			for id: String in members:
				room_of[id] = members[0]
	var out: Dictionary = {}
	if room_of.is_empty() or _sdf == null:
		return out
	for seam: Dictionary in _sdf.seams():
		var child: String = str(seam.get(ShipSeams.SEAM_CHILD, ""))
		var host: String = str(seam.get(ShipSeams.SEAM_HOST, ""))
		if room_of.has(child) and str(room_of.get(host, "")) == str(room_of[child]):
			out[child] = true
	return out


## Remember on [param node] where it hangs.
static func _hang(node: Node3D, module_id: String, cell: Vector3i, frame: Basis, kind: int) -> void:
	node.set_meta(META_MODULE, module_id)
	node.set_meta(META_CELL, cell)
	node.set_meta(META_FRAME, frame)
	node.set_meta(META_KIND, kind)


## The direction the fundamental [param cell] of [param frame] is pulled under the slicer settings
## [param modes]: along each axis, the way its slab's group goes (GROUP_SIGN) - away from the middle
## for an outer group, not at all for the middle one or an axis left whole. Diagonal when several
## axes slice. Zero for a visual that is not a cell.
static func _cell_shift(frame: Basis, cell: Vector3i, modes: Vector3i) -> Vector3:
	if cell.x < 0:
		return Vector3.ZERO
	var axes: Array[Vector3] = [frame.x, frame.y, frame.z]
	var out: Vector3 = Vector3.ZERO
	for axis: int in 3:
		var signs: Array = GROUP_SIGN[clampi(modes[axis], 0, GROUP_SIGN.size() - 1)]
		out += axes[axis] * float(signs[clampi(cell[axis], 0, signs.size() - 1)])
	return out


## Is [param id] a chunk of a room of several - a cluster (ADR 0031)?
func _in_cluster(id: String) -> bool:
	for members: PackedStringArray in _bake.get("rooms", []):
		if members.size() > 1 and members.has(id):
			return true
	return false


## [param mesh] as two: every surface but the interior, and the interior alone (null when the
## mesh names none). Surface names travel, so the materials still find them.
static func _split_interior(mesh: ArrayMesh) -> Array:
	var interior: int = mesh.surface_find_by_name(ShipCsgBake.SURFACE_INTERIOR)
	if interior < 0:
		return [mesh, null]
	var outer: ArrayMesh = ArrayMesh.new()
	var inner: ArrayMesh = ArrayMesh.new()
	for i: int in mesh.get_surface_count():
		var target: ArrayMesh = inner if i == interior else outer
		target.add_surface_from_arrays(
			mesh.surface_get_primitive_type(i), mesh.surface_get_arrays(i)
		)
		target.surface_set_name(target.get_surface_count() - 1, mesh.surface_get_name(i))
	if outer.get_surface_count() == 0:
		return [mesh, null]
	return [outer, inner]
