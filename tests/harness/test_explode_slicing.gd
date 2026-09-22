# The exploded view's slicer (ADR 0031): every part cut in its own axes - Y its placement normal -
# off, bisected or trisected per axis; a cluster's chunks by their own settings or not at all; and
# the settings the player keeps. A lone sphere where the rooms do not matter, a carbon where they
# do.
class_name TestExplodeSlicing
extends GdUnitTestSuite

const SETTINGS_TEST_PATH: String = "user://test_explode_settings.json"

var _data: ShipData
var _cfg: ShipConfig


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
	return ShipTemplates.build(_data, _cfg, "carbon", {ShipTemplates.OPT_ROOM_FAMILY: "sphere_pod"})


func _sliced(doc: ShipDoc, parts: Vector3i, clusters: Vector3i) -> Dictionary:
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	return await ShipCsgBake.bake_extras(self, report, {"parts": parts, "clusters": clusters})


func _volume(polys: Array) -> float:
	var total: float = 0.0
	for poly: PolyMesh in polys:
		total += poly.volume()
	return total


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


## A trisection: three closed slices along the axis, cells 0, 1 and 2, that together are the piece.
func test_a_trisection_cuts_three_closed_slices_that_make_the_piece() -> void:
	var doc: ShipDoc = _lone_sphere()
	var out: Dictionary = await _sliced(doc, Vector3i(0, 2, 0), Vector3i.ZERO)
	var id: String = doc.root
	var chunks: Array = out["chunks"][id]
	var cells: Array = out["chunk_cells"][id]
	assert_int(chunks.size()).is_equal(3)
	assert_that(out["chunk_counts"][id]).is_equal(Vector3i(0, 2, 0))
	var ys: Array = []
	for i: int in chunks.size():
		var cell: Vector3i = cells[i]
		assert_int(cell.x + cell.z).is_equal(0)
		ys.append(cell.y)
		assert_int((chunks[i] as PolyMesh).open_edges()).is_equal(0)
	ys.sort()
	assert_array(ys).is_equal([0, 1, 2])
	var piece: float = (out["solids"][id] as PolyMesh).volume()
	assert_float(_volume(chunks)).is_equal_approx(piece, piece * 0.02)
	assert_str(str(out[ShipCsgBake.EXTRAS_SLICING])).is_equal(
		ShipCsgBake.slicing_key({"parts": Vector3i(0, 2, 0), "clusters": Vector3i.ZERO})
	)


## All three axes bisected: eight closed octants of about an eighth each.
func test_three_bisections_make_eight_octants() -> void:
	var doc: ShipDoc = _lone_sphere()
	var out: Dictionary = await _sliced(doc, Vector3i(1, 1, 1), Vector3i.ZERO)
	var chunks: Array = out["chunks"][doc.root]
	assert_int(chunks.size()).is_equal(8)
	var piece: float = (out["solids"][doc.root] as PolyMesh).volume()
	for chunk: PolyMesh in chunks:
		assert_int(chunk.open_edges()).is_equal(0)
		assert_float(chunk.volume()).is_equal_approx(piece / 8.0, piece / 8.0 * 0.15)


## "a nodecluster bisector includer toggle that lets chunks from nodes get sliced with its own
## isolated slicing settings" (2026-09-21): not included, a cluster's chunks are drawn whole while
## the modules around them are sliced; included, they take their own counts. A room shown whole
## keeps the parts' slicing either way.
func test_a_clusters_chunks_take_their_own_slicing_or_none() -> void:
	var doc: ShipDoc = _carbon()
	var report: Dictionary = await ShipCsgBake.bake(self, doc, _data, _cfg)
	var parts: Vector3i = Vector3i(0, 0, 1)
	var none: Dictionary = await ShipCsgBake.bake_extras(
		self, report, {"parts": parts, "clusters": Vector3i.ZERO}
	)
	# The clusters cut on a DIFFERENT axis from the parts: each job keeps its own cells.
	var own: Dictionary = await ShipCsgBake.bake_extras(
		self, report, {"parts": parts, "clusters": Vector3i(1, 0, 0)}
	)
	var clusters: int = 0
	for members: PackedStringArray in report["rooms"]:
		for id: String in members:
			var piece: float = (report["solids"][id] as PolyMesh).volume()
			if members.size() == 1:
				assert_int((none["chunks"][id] as Array).size()).is_equal(2)
				(
					assert_int((own["chunks"][id] as Array).size())
					. append_failure_message("%s lost its slices beside an X-cut cluster" % id)
					. is_equal(2)
				)
				continue
			clusters += 1
			assert_bool((none["chunks"] as Dictionary).has(id)).is_false()
			var cut: Array = own["chunks"][id]
			assert_int(cut.size()).is_between(1, 2)
			assert_that(own["chunk_counts"][id]).is_equal(Vector3i(1, 0, 0))
			assert_float(_volume(cut)).is_equal_approx(piece, maxf(piece * 0.02, 0.01))
		if members.size() > 1:
			assert_that(own["room_chunk_counts"][members[0]]).is_equal(parts)
	assert_int(clusters).is_equal(6)


## A slice is pulled away from the middle along each sliced axis of its frame: a trisection's
## outer slices outward and its middle one not at all, a bisection's halves each their own way.
func test_a_slice_is_pulled_away_from_the_middle() -> void:
	var frame: Transform3D = Transform3D.IDENTITY
	var tri: Vector3i = Vector3i(0, 2, 0)
	assert_vector(ShipExplodeView._shift_unit(frame, Vector3i(0, 0, 0), tri)).is_equal(Vector3.DOWN)
	assert_vector(ShipExplodeView._shift_unit(frame, Vector3i(0, 1, 0), tri)).is_equal(Vector3.ZERO)
	assert_vector(ShipExplodeView._shift_unit(frame, Vector3i(0, 2, 0), tri)).is_equal(Vector3.UP)
	var bi: Vector3i = Vector3i(1, 0, 1)
	assert_vector(ShipExplodeView._shift_unit(frame, Vector3i(1, 0, 0), bi)).is_equal(
		Vector3(1.0, 0.0, -1.0)
	)
	# In the part's own frame, not the ship's.
	var turned: Transform3D = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO)
	assert_vector(ShipExplodeView._shift_unit(turned, Vector3i(0, 2, 0), tri)).is_equal_approx(
		turned.basis.y, Vector3.ONE * 1.0e-6
	)


## The player's settings survive the file, clamp what they cannot hold, and a separation is not a
## slicing: moving a gap never asks the engine for anything.
func test_the_settings_keep_what_the_player_chose() -> void:
	var base: ShipExplodeSettings = ShipExplodeSettings.defaults(_cfg)
	assert_float(base.separation_m).is_equal_approx(_cfg.explode_gap_m, 1.0e-6)
	assert_that(base.slicing()["parts"]).is_equal(Vector3i(0, 0, 1))
	var chosen: ShipExplodeSettings = base.copy()
	chosen.separate = false
	chosen.separation_m = 3.5
	chosen.slices = Vector3i(2, 0, 1)
	chosen.cluster_slicing = false
	assert_that(chosen.slicing()["clusters"]).is_equal(Vector3i.ZERO)
	assert_bool(chosen.save(SETTINGS_TEST_PATH)).is_true()
	var back: ShipExplodeSettings = ShipExplodeSettings.load_or_defaults(_cfg, SETTINGS_TEST_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST_PATH))
	assert_bool(back.separate).is_false()
	assert_float(back.separation_m).is_equal_approx(3.5, 1.0e-6)
	assert_that(back.slices).is_equal(Vector3i(2, 0, 1))
	assert_bool(back.cluster_slicing).is_false()
	var gap: ShipExplodeSettings = base.copy()
	gap.separation_m = 9.0
	gap.slice_separation_m = 4.0
	assert_str(ShipCsgBake.slicing_key(gap.slicing())).is_equal(
		ShipCsgBake.slicing_key(base.slicing())
	)
	assert_str(ShipCsgBake.slicing_key(chosen.slicing())).is_not_equal(
		ShipCsgBake.slicing_key(base.slicing())
	)
	var junk: ShipExplodeSettings = ShipExplodeSettings.from_dict(
		{"separation_m": 99.0, "slices": [7, -3, 1], "cluster_slices": "nonsense"}, base
	)
	assert_float(junk.separation_m).is_equal(ShipExplodeSettings.SEPARATION_MAX_M)
	assert_that(junk.slices).is_equal(Vector3i(2, 0, 1))
	assert_that(junk.cluster_slices).is_equal(base.cluster_slices)
