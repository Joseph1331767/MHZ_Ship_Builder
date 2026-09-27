# The exploded view's fundamental cells (ADR 0031/0032): every piece cut once, in its own axes (Y
# its placement normal), at 1/3, 1/2 and 2/3 along each - 64 cells - so every slicer setting is a
# grouping of cells that exist and every setting, like the animation, only moves them. A lone
# sphere where the rooms do not matter, a carbon where they do.
class_name TestExplodeSlicing
extends GdUnitTestSuite
const SETTINGS_TEST_PATH: String = "user://test_explode_settings.json"

var _data: ShipData
var _cfg: ShipConfig


## TEMPLATE LINKS ARE OPEN BY DEFAULT since 2026-09-26 ("by default in the prebuilds we dont want
## any walls in our prebuilds by default"). This suite is about what a ship with LINKS does - its
## walls, its doors, the rooms they bound or the meshes they cut - so it asks for the hatches the
## templates used to place, instead of resting on a default that no longer says that.
func _linked(extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {ShipTemplates.OPT_LINK_MODE: ShipJoint.MODE_HATCHED}
	out.merge(extra)
	return out


func before() -> void:
	_data = ShipData.new()
	(
		assert_bool(_data.load_all())
		. append_failure_message("ShipData.load_all() failed: %s" % [str(_data.load_errors)])
		. is_true()
	)
	_cfg = ShipConfig.defaults()


func _lone_sphere() -> ShipDoc:
	var mfr: String = _data.manufacturers_for("sphere_pod")[0]
	return ShipDoc.create_new("sphere_pod", mfr, _data, 6.0)


func _carbon() -> ShipDoc:
	return ShipTemplates.build(
		_data, _cfg, "carbon", _linked({ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"})
	)


func _cut(doc: ShipDoc) -> Dictionary:
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	return await ShipCsgBake.bake_extras(self, report)


## The volume of each group [param modes] makes of [param cells]: group key -> m3.
func _groups(cells: Array, modes: Vector3i) -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in cells:
		var key: Vector3 = ShipExplodeView._cell_shift(Basis.IDENTITY, entry["cell"], modes)
		out[key] = float(out.get(key, 0.0)) + (entry["solid"] as PolyMesh).volume()
	return out


## "choose orthogonal axes where one points radially with the parts placement, so alignment is
## preserved to the part itself" (2026-09-21): every frame is orthonormal and right-handed, sits at
## the part's origin, and its Y is the part's own placement normal - twins included.
func test_the_slicing_frame_is_the_parts_own_with_y_its_placement_normal() -> void:
	var doc: ShipDoc = _carbon()
	var frames: Dictionary = ShipMeshBake.plan(doc, _data, _cfg)["frames"]
	var xforms: Dictionary = ShipAttach.resolve_all(doc, _data, _cfg)
	assert_int(frames.size()).is_greater(0)
	for id: String in frames:
		var frame: Transform3D = frames[id]
		var b: Basis = frame.basis
		assert_float(b.determinant()).append_failure_message(id).is_equal_approx(1.0, 1.0e-4)
		assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 1.0e-4)
		assert_float(b.y.dot(b.z)).is_equal_approx(0.0, 1.0e-4)
		assert_float(b.z.dot(b.x)).is_equal_approx(0.0, 1.0e-4)
		assert_bool(xforms.has(id)).is_true()
		var placed: Transform3D = xforms[id]
		assert_vector(frame.origin).is_equal_approx(placed.origin, Vector3.ONE * 1.0e-5)
		(
			assert_float(b.y.dot(placed.basis.y.normalized()))
			. append_failure_message("%s: the frame's Y is not the placement normal" % id)
			. is_greater(0.999)
		)


## "all nodes should be both bisected, and trisected leaving 4 total chunks after both bi and tri
## are dissected, in all orthogonal directions" (2026-09-21): at most 64 closed cells, each at four
## slabs an axis, that together are the piece - a cell wholly inside the cavity is simply not there.
func test_every_piece_is_cut_into_its_fundamental_cells() -> void:
	var doc: ShipDoc = _lone_sphere()
	var out: Dictionary = await _cut(doc)
	var cells: Array = out["cells"][doc.root]
	assert_int(cells.size()).is_between(40, 64)
	var total: float = 0.0
	for entry: Dictionary in cells:
		var cell: Vector3i = entry["cell"]
		for axis: int in 3:
			assert_int(cell[axis]).is_between(0, 3)
		var solid: PolyMesh = entry["solid"]
		assert_int(solid.open_edges()).is_equal(0)
		assert_object(entry["mesh"]).is_not_null()
		assert_object(entry["wire"]).is_not_null()
		total += solid.volume()
	var piece: float = (out["solids"][doc.root] as PolyMesh).volume()
	assert_float(total).is_equal_approx(piece, piece * 0.001)


## Every slicer setting is a grouping of the same cells: OFF one group, BISECT two halves, TRISECT
## three thirds; three axes bisected, eight octants of about an eighth each. Nothing is re-cut.
func test_every_slicing_is_a_grouping_of_the_cells() -> void:
	var doc: ShipDoc = _lone_sphere()
	var out: Dictionary = await _cut(doc)
	var cells: Array = out["cells"][doc.root]
	var piece: float = (out["solids"][doc.root] as PolyMesh).volume()
	assert_int(_groups(cells, Vector3i.ZERO).size()).is_equal(1)
	var halves: Dictionary = _groups(cells, Vector3i(0, 1, 0))
	assert_int(halves.size()).is_equal(2)
	for key: Vector3 in halves:
		assert_float(float(halves[key])).is_equal_approx(piece * 0.5, piece * 0.05)
	assert_int(_groups(cells, Vector3i(0, 2, 0)).size()).is_equal(3)
	var octants: Dictionary = _groups(cells, Vector3i(1, 1, 1))
	assert_int(octants.size()).is_equal(8)
	for key: Vector3 in octants:
		assert_float(float(octants[key])).is_equal_approx(piece / 8.0, piece / 8.0 * 0.15)


## A cluster's chunks are cut like any piece ("including each node cluster chunks splicing",
## 2026-09-21), and a room shown whole has cells of its own in its keeper's frame.
func test_cluster_chunks_and_whole_rooms_are_cut_too() -> void:
	var doc: ShipDoc = _carbon()
	var out: Dictionary = await _cut(doc)
	var cells: Dictionary = out["cells"]
	for members: PackedStringArray in out["rooms"]:
		for id: String in members:
			assert_bool(cells.has(id)).append_failure_message(id).is_true()
			var piece: float = (out["solids"][id] as PolyMesh).volume()
			var total: float = 0.0
			for entry: Dictionary in cells[id]:
				total += (entry["solid"] as PolyMesh).volume()
			assert_float(total).append_failure_message(id).is_equal_approx(piece, piece * 0.001)
		if members.size() > 1:
			assert_int((out["room_cells"][members[0]] as Array).size()).is_greater(8)


## A cell is pulled the way its group goes along each axis of its frame: a trisection's outer
## slabs outward and its two middle slabs not at all, a bisection's two halves each their own way,
## an axis left whole not at all. A visual that is not a cell never moves.
func test_a_cell_is_pulled_the_way_its_group_goes() -> void:
	var frame: Basis = Basis.IDENTITY
	var tri: Vector3i = Vector3i(0, 2, 0)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(0, 0, 0), tri)).is_equal(Vector3.DOWN)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(0, 1, 0), tri)).is_equal(Vector3.ZERO)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(0, 2, 0), tri)).is_equal(Vector3.ZERO)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(0, 3, 0), tri)).is_equal(Vector3.UP)
	var bi: Vector3i = Vector3i(0, 1, 0)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(0, 1, 0), bi)).is_equal(Vector3.DOWN)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(0, 2, 0), bi)).is_equal(Vector3.UP)
	assert_vector(ShipExplodeView._cell_shift(frame, Vector3i(3, 3, 3), Vector3i.ZERO)).is_equal(
		Vector3.ZERO
	)
	assert_vector(ShipExplodeView._cell_shift(frame, ShipExplodeView.NO_CELL, tri)).is_equal(
		Vector3.ZERO
	)
	# In the part's own frame, not the ship's.
	var turned: Basis = Basis(Vector3.FORWARD, PI * 0.5)
	assert_vector(ShipExplodeView._cell_shift(turned, Vector3i(0, 3, 0), tri)).is_equal_approx(
		turned.y, Vector3.ONE * 1.0e-6
	)


## "modules split from modules, then module chunk clusters separate, then parts 'slice' separate"
## (2026-09-21): three stages, a third of the explode each, in that order.
func test_the_explode_runs_in_three_stages() -> void:
	assert_vector(ShipExplodeView._stages(0.0)).is_equal(Vector3.ZERO)
	assert_vector(ShipExplodeView._stages(1.0 / 3.0)).is_equal_approx(
		Vector3(1.0, 0.0, 0.0), Vector3.ONE * 1.0e-5
	)
	assert_vector(ShipExplodeView._stages(0.5)).is_equal_approx(
		Vector3(1.0, 0.5, 0.0), Vector3.ONE * 1.0e-5
	)
	assert_vector(ShipExplodeView._stages(1.0)).is_equal(Vector3.ONE)


## The first stage moves a room as one body: every chunk of it holds still together while the
## modules around it travel. The nucleus of a class stands on NOTHING (ADR 0034/0035), so a class
## holds its core where it is and pulls its pods off it - it does not slide off its own top body,
## which is what the author saw: "the entire ship moves down from the top node" (2026-09-22).
func test_in_the_first_stage_a_rooms_chunks_ride_it() -> void:
	var doc: ShipDoc = _carbon()
	var sdf: ShipSdf = ShipSdf.build(doc, _data, _cfg)
	var rooms: Array = ShipMeshBake.plan(doc, _data, _cfg)["rooms"]
	# Every member of a room of several rides it; the one standing on something OUTSIDE the room
	# would be the one carrying it off, and a nucleus has none.
	var riders: Dictionary = {}
	for members: PackedStringArray in rooms:
		if members.size() > 1:
			for id: String in members:
				riders[id] = true
	assert_int(riders.size()).is_equal(6)
	var boxes: Dictionary = {}
	for i: int in sdf.part_count():
		boxes[sdf.part_id_at(i)] = sdf.part_aabb(i)
	var full: Dictionary = ShipSeams.explode_offsets(sdf.seams(), _cfg, boxes)
	var first: Dictionary = ShipSeams.explode_offsets(sdf.seams(), _cfg, boxes, riders)
	for id: String in riders:
		(
			assert_vector(first.get(id, Vector3.ZERO) as Vector3)
			. append_failure_message("%s left the room in the first stage" % id)
			. is_equal_approx(Vector3.ZERO, Vector3.ONE * 1.0e-5)
		)
		# And it does come apart in the full explode - away from the beacon, which is where a body
		# that stands on nothing goes.
		var out: Vector3 = full.get(id, Vector3.ZERO)
		assert_float(out.length()).append_failure_message(id).is_greater(0.1)
		var centre: Vector3 = (boxes[id] as AABB).get_center()
		(
			assert_float(out.normalized().dot(centre.normalized()))
			. append_failure_message("%s did not travel away from the centre" % id)
			. is_greater(0.99)
		)
	var travelling: int = 0
	for id: String in first:
		if not riders.has(id) and (first[id] as Vector3).length() > 0.1:
			travelling += 1
	assert_int(travelling).is_greater_equal(8)


## The player's settings survive the file, clamp what they cannot hold, and group a cluster's
## chunks by its own settings - or not at all when they are not included.
func test_the_settings_keep_what_the_player_chose() -> void:
	var base: ShipExplodeSettings = ShipExplodeSettings.defaults(_cfg)
	assert_float(base.separation_m).is_equal_approx(_cfg.explode_gap_m, 1.0e-6)
	assert_int(base.mode_for(2, false)).is_equal(ShipExplodeSettings.BISECT)
	var chosen: ShipExplodeSettings = base.copy()
	chosen.separate = false
	chosen.separation_m = 3.5
	chosen.slices = Vector3i(2, 0, 1)
	chosen.cluster_slicing = false
	chosen.speed = 2.5
	assert_int(chosen.mode_for(0, true)).is_equal(ShipExplodeSettings.OFF)
	assert_int(chosen.mode_for(0, false)).is_equal(ShipExplodeSettings.TRISECT)
	assert_bool(chosen.save(SETTINGS_TEST_PATH)).is_true()
	var back: ShipExplodeSettings = ShipExplodeSettings.load_or_defaults(_cfg, SETTINGS_TEST_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_PATH))
	assert_bool(back.separate).is_false()
	assert_float(back.separation_m).is_equal_approx(3.5, 1.0e-6)
	assert_that(back.slices).is_equal(Vector3i(2, 0, 1))
	assert_bool(back.cluster_slicing).is_false()
	assert_float(back.speed).is_equal_approx(2.5, 1.0e-6)
	var junk: ShipExplodeSettings = ShipExplodeSettings.from_dict(
		{"separation_m": 99.0, "slices": [7, -3, 1], "cluster_slices": "nonsense", "speed": 40.0},
		base
	)
	assert_float(junk.separation_m).is_equal(ShipExplodeSettings.SEPARATION_MAX_M)
	assert_that(junk.slices).is_equal(Vector3i(2, 0, 1))
	assert_that(junk.cluster_slices).is_equal(base.cluster_slices)
	assert_float(junk.speed).is_equal(ShipExplodeSettings.SPEED_MAX)
