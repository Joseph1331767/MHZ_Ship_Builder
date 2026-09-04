extends SceneTree

## Headless smoke test: does the data load, does a doc build and resolve, and is it deterministic?
##
##   & $env:GODOT_BIN --headless --path . -s res://tools/ship_selfcheck.gd
##   ./tools/ship_run.ps1 res://tools/ship_selfcheck.gd     (preferred - AGENTS §8a)
##
## This is the cheapest gate in the project and it should run in well under a second. It is NOT the
## determinism suite (that lives in tests/, per docs/API_CONTRACT.md §24) - it is the thing you run
## after touching core/ to find out whether you broke it before spending a minute on gdUnit4.
##
## Coded against docs/API_CONTRACT.md exactly. If core/ classes are not on disk yet,
## this script will fail to PARSE, not silently pass - that is expected during early
## milestones (AGENTS §9) and is not a
## bug in this tool.
##
## What it checks, in order:
##   1. ShipData loads data/ cleanly (reports every load_errors entry as a failure).
##   2. ShipDoc.create_new() produces a valid root part for the first
##      family/manufacturer pair found.
##   3. A couple of child parts can be added, one of them under a *different* family
##      if the catalog has
##      more than one, to exercise cross-family attach resolution.
##   4. ShipAttach.resolve_shapes() / resolve_all() cover every part in the doc.
##   5. ShipSdf.build() samples cleanly at a handful of points, including one far
##      outside the ship's own
##      AABB, which must read as outside (positive distance).
##   6. ShipHash.doc_hash() is stable across repeat calls on an unchanged doc (the determinism gate,
##      AGENTS §8b), survives duplicate_doc() unchanged, and changes when a part's param changes.

var _failures: int = 0


func _init() -> void:
	print("=== MHZ Ship Builder self-check ===")

	var data := ShipData.new()
	var loaded := data.load_all()
	for e: String in data.load_errors:
		_fail("data load: %s" % e)
	if not loaded:
		_finish()
		return

	var family_ids := data.family_ids()
	if family_ids.is_empty():
		_fail("no shape families loaded - nothing to build a doc from")
		_finish()
		return

	print("  loaded: %d families, %d manufacturers, %d hatch families"
		% [family_ids.size(), data.manufacturer_ids().size(), data.hatches.size()])

	var family_id: String = family_ids[0]
	var manu_ids := data.manufacturers_for(family_id)
	if manu_ids.is_empty():
		_fail("family '%s' has no manufacturer that can build it" % family_id)
		_finish()
		return
	var manufacturer_id: String = manu_ids[0]

	var cfg := ShipConfig.defaults()
	var doc := ShipDoc.create_new(family_id, manufacturer_id, data)
	if doc == null or doc.root == "" or not doc.parts.has(doc.root):
		_fail(
			"ShipDoc.create_new(%s, %s) did not produce a valid root part"
			% [family_id, manufacturer_id]
		)
		_finish()
		return
	print(
		"  create_new: root='%s' family='%s' manufacturer='%s'"
		% [doc.root, family_id, manufacturer_id]
	)

	var child_a := _add_child_part(doc, data, doc.root, family_id, manufacturer_id,
		45.0, 10.0, Vector3.ZERO, 0.0, "test part A")
	if child_a == "":
		_finish()
		return

	# Exercise a second family if the catalog has one, to check cross-family attach resolution -
	# the parent and child shapes are then genuinely different SDFs, not two copies of the same one.
	var second_family_id := family_id
	for fid: String in family_ids:
		if fid != family_id:
			second_family_id = fid
			break
	var second_manu_ids := data.manufacturers_for(second_family_id)
	var second_manufacturer_id: String = manufacturer_id
	if not second_manu_ids.is_empty():
		second_manufacturer_id = second_manu_ids[0]

	var child_b := _add_child_part(doc, data, doc.root, second_family_id, second_manufacturer_id,
		-90.0, -20.0, Vector3(12.0, -8.0, 15.0), 0.1, "test part B")
	if child_b == "":
		_finish()
		return

	_check_attach(doc, data, cfg)
	_check_sdf(doc, data, cfg)
	_check_hash(doc, child_a)

	_finish()


func _add_child_part(doc: ShipDoc, data: ShipData, parent_id: String, family_id: String,
		manufacturer_id: String, yaw: float, pitch: float, rot: Vector3, offset: float,
		name: String) -> String:
	if not data.has_family(family_id):
		_fail("family '%s' does not exist - cannot add '%s'" % [family_id, name])
		return ""
	var params := ShapeGen.default_params(data, family_id, manufacturer_id)
	var part_id := doc.new_part_id()
	var part_dict := {
		"parent": parent_id,
		"kind": "primitive",
		"family": family_id,
		"manufacturer": manufacturer_id,
		"params": params,
		"attach": {"yaw": yaw, "pitch": pitch, "rot": [rot.x, rot.y, rot.z], "offset": offset},
		"scale": [1.0, 1.0, 1.0],
		"blend": 0.0,
		"mirror": {"source": null, "plane": null},
		"name": name,
		"locked": false,
	}
	var part := ShipPart.from_dict(part_id, part_dict)
	var added_id := doc.add_part(part)
	if added_id != part_id:
		_fail("add_part returned '%s', expected the id it was given ('%s')" % [added_id, part_id])
	print("  add_part: '%s' (%s) attached to '%s' via %s/%s"
		% [part_id, name, parent_id, family_id, manufacturer_id])
	return part_id


func _check_attach(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	var shapes := ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms := ShipAttach.resolve_all(doc, data, cfg)
	var expected: int = doc.parts.size()
	if shapes.size() < expected:
		_fail("resolve_shapes() returned %d shapes for %d parts" % [shapes.size(), expected])
	if xforms.size() < expected:
		_fail("resolve_all() returned %d transforms for %d parts" % [xforms.size(), expected])
	for pid: Variant in doc.parts.keys():
		var id := String(pid)
		if not xforms.has(id):
			_fail("part '%s' has no resolved transform" % id)
			continue
		var t: Transform3D = xforms[id]
		var origin := t.origin
		if is_nan(origin.x) or is_nan(origin.y) or is_nan(origin.z):
			_fail("part '%s' resolved to a NaN transform origin" % id)
	print("  attach: %d/%d parts resolved to a transform" % [xforms.size(), expected])


func _check_sdf(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> void:
	var sdf := ShipSdf.build(doc, data, cfg)
	if sdf.part_count() < doc.parts.size():
		_fail("ShipSdf covers %d parts, doc has %d" % [sdf.part_count(), doc.parts.size()])

	var bounds := sdf.aabb()
	var center := bounds.get_center()
	var reach := bounds.size.length() * 5.0 + 10.0
	var far_point := center + Vector3(1.0, 1.0, 1.0).normalized() * reach
	var sample_points: Array[Vector3] = [Vector3.ZERO, center, bounds.position, bounds.end, far_point]

	for p: Vector3 in sample_points:
		var d := sdf.sample(p)
		if is_nan(d) or is_inf(d):
			_fail("sdf.sample(%s) returned a non-finite distance (%f)" % [p, d])

	var d_far := sdf.sample(far_point)
	if not (is_nan(d_far) or is_inf(d_far)) and d_far <= 0.0:
		_fail(
			(
				"sample far outside the ship's AABB (%s) returned non-positive distance (%.3f)"
				+ " - sdf.sample() looks broken"
			)
			% [far_point, d_far]
		)
	else:
		print("  sdf: aabb=%s, far-outside sample=%.3f (positive, as expected)" % [bounds, d_far])


func _check_hash(doc: ShipDoc, mutable_part_id: String) -> void:
	var h1 := ShipHash.doc_hash(doc)
	var h2 := ShipHash.doc_hash(doc)
	if h1 != h2:
		_fail(
			"doc_hash is not stable across two calls on the same unchanged doc: '%s' vs '%s'"
			% [h1, h2]
		)
	else:
		print("  hash: stable across repeat calls (%s)" % h1)

	var doc_dup := doc.duplicate_doc()
	var h3 := ShipHash.doc_hash(doc_dup)
	if h3 != h1:
		_fail(
			"duplicate_doc() produced a doc that hashes to '%s' instead of the source's '%s'"
			% [h3, h1]
		)
	else:
		print("  hash: duplicate_doc() preserves the hash")

	if not doc_dup.parts.has(mutable_part_id):
		_fail("duplicate_doc() lost part '%s'" % mutable_part_id)
		return
	var mutated_part := doc_dup.parts[mutable_part_id] as ShipPart
	if mutated_part == null or mutated_part.params.is_empty():
		_fail("part '%s' has no params to mutate for the sensitivity check" % mutable_part_id)
		return
	var pkeys := mutated_part.params.keys()
	var k0 := String(pkeys[0])
	var v0 := float(mutated_part.params[k0])
	mutated_part.params[k0] = v0 + 0.01
	var h4 := ShipHash.doc_hash(doc_dup)
	if h4 == h1:
		_fail(
			(
				"changing part '%s' param '%s' did not change doc_hash"
				+ " - the determinism gate is not sensitive to input"
			)
			% [mutable_part_id, k0]
		)
	else:
		print(
			"  hash: changing param '%s' on '%s' changes the hash (sensitivity confirmed)"
			% [k0, mutable_part_id]
		)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  FAIL: %s" % msg)


func _finish() -> void:
	if _failures == 0:
		print("=== self-check PASSED ===")
		quit(0)
	else:
		printerr("=== self-check FAILED (%d) ===" % _failures)
		quit(1)
