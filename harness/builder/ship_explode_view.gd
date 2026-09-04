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


## One exploded module: the baked shell, its wireframe, and its pick body.
class Module:
	extends RefCounted

	var id: String = ""
	var solid: MeshInstance3D = null
	var wire: MeshInstance3D = null
	var body: StaticBody3D = null
	var selected: bool = false


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


## Start showing `sdf` exploded. `selected` are the builder's selected doc ids; their modules
## wear the selection ramp so the player keeps their bearings among the pieces. Bakes one
## module per frame from here on; `finished` fires when the last one is placed.
func show_modules(
	sdf: ShipSdf, cfg: ShipConfig, selected: PackedStringArray, solids: Dictionary = {}
) -> void:
	clear()
	_solids = solids
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
		var module: String = ShipSeams.module_of(sdf.part_id_at(i))
		if boxes.has(module):
			boxes[module] = (boxes[module] as AABB).merge(sdf.part_aabb(i))
		else:
			_queue.append(module)
			boxes[module] = sdf.part_aabb(i)
	_offsets = ShipSeams.explode_offsets(sdf.seams(), cfg, boxes)
	_total = _queue.size()
	_started_ms = Time.get_ticks_msec()
	_showing = true
	visible = true
	if _queue.is_empty():
		finished.emit(0, sdf.seam_count(), 0)
		return
	set_process(true)


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


## Take every module down. Safe to call when nothing is showing.
func clear() -> void:
	set_process(false)
	for module: Module in _modules:
		if is_instance_valid(module.solid):
			module.solid.queue_free()
		if is_instance_valid(module.wire):
			module.wire.queue_free()
		if is_instance_valid(module.body):
			module.body.queue_free()
	_modules.clear()
	_queue = PackedStringArray()
	_offsets = {}
	_selected = {}
	_bounds = AABB()
	_has_bounds = false
	_total = 0
	_showing = false
	_sdf = null
	_cfg = null
	_solids = {}


func is_showing() -> bool:
	return _showing


## Still baking modules.
func is_busy() -> bool:
	return _showing and not _queue.is_empty()


func module_count() -> int:
	return _modules.size()


## The ship-space box round every module placed so far; empty before the first.
func bounds() -> AABB:
	return _bounds


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
	if next.hash() == _selected.hash() and next.size() == _selected.size():
		return
	_selected = next
	for module: Module in _modules:
		var owner: String = ShipSymmetry.source_of_twin(module.id)
		var sel: bool = _selected.has(owner)
		if sel != module.selected:
			module.selected = sel
			_apply_materials(module)


## One module's pick body, by module id, for a check that needs to look at it.
func module_body(id: String) -> StaticBody3D:
	for module: Module in _modules:
		if module.id == id:
			return module.body
	return null


## The module meshes on screen, for a check that wants to count or measure them.
func module_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for module: Module in _modules:
		out.append(module.solid)
	return out


# --- internals -----------------------------------------------------------------------------


## Bake one module and put it on screen at its explode offset. The cell is the coarser of the
## bake lever and the module's longest axis over explode_cells_per_axis, so a hull and a stud
## both resolve at a sensible count rather than the hull at millions and the stud at eight.
func _bake_module(id: String) -> void:
	# The exact path (ADR 0011): the part was tessellated analytically, so there is nothing to
	# extract and nothing to resolve - just place it. Its wireframe comes from the model edges
	# rather than from triangles, which is why a baked box shows twelve lines and not eighteen.
	var exact: PolyMesh = _solids.get(id, null) as PolyMesh
	if exact != null and not exact.is_empty():
		_place_module(id, exact.to_array_mesh(), exact.to_wire_mesh())
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


## Puts one baked module on screen at its explode offset, with its wireframe and pick body.
func _place_module(id: String, mesh: ArrayMesh, wire: Mesh) -> void:
	var module: Module = Module.new()
	module.id = id
	module.selected = _selected.has(ShipSymmetry.source_of_twin(id))
	# A node name cannot hold the slash of an expanded id or the tilde of a twin.
	var node_name: String = id.replace("/", "__").replace("~", "_")
	var placed: Transform3D = Transform3D(Basis.IDENTITY, _offsets.get(id, Vector3.ZERO))

	module.solid = MeshInstance3D.new()
	module.solid.name = NODE_PREFIX + node_name
	module.solid.mesh = mesh
	module.solid.transform = placed
	add_child(module.solid)

	module.wire = MeshInstance3D.new()
	module.wire.name = NODE_PREFIX + node_name + "_wire"
	module.wire.mesh = wire
	module.wire.transform = placed
	add_child(module.wire)

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
	module.body = StaticBody3D.new()
	module.body.name = NODE_PREFIX + node_name + "_pick"
	module.body.collision_layer = ShipSceneBuilder.PICK_LAYER
	module.body.collision_mask = 0
	module.body.set_meta(ShipSceneBuilder.PART_META, id)
	module.body.transform = placed
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = mesh.create_convex_shape(true, true)
	module.body.add_child(collider)
	add_child(module.body)

	_apply_materials(module)
	_modules.append(module)

	var world_box: AABB = placed * mesh.get_aabb()
	if _has_bounds:
		_bounds = _bounds.merge(world_box)
	else:
		_bounds = world_box
		_has_bounds = true


func _apply_materials(module: Module) -> void:
	if _scene == null or module.solid == null:
		return
	var pair: Array = _scene.materials_for(_mode, module.selected)
	module.solid.material_override = pair[0]
	module.solid.visible = ShipSceneBuilder.mode_shows_solid(_mode)
	if module.wire != null:
		module.wire.material_override = pair[1]
		module.wire.visible = pair[1] != null and module.wire.mesh != null
