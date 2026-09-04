# ShipSymmetry — API_CONTRACT_SPORE section 4. The load-bearing property of this whole class is
# that a per-part `asymmetric` flag is never the answer by itself: breaking symmetry on a part
# CASCADES to every descendant, so the only correct question is is_effectively_asymmetric(), which
# walks the ancestor chain. Every cascade test below asserts BOTH the raw ShipPart.asymmetric field
# (which must stay false on a descendant that was never touched) AND the effective answer (which
# must be true for it) -- asserting only one of the two would not catch a regression back to
# reading the raw flag directly, which is exactly the bug this API exists to prevent.
class_name TestSymmetry
extends GdUnitTestSuite

var _data: ShipData
var _family_id: String
var _manufacturer_id: String


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	assert_bool(ok).append_failure_message(
		"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
	).is_true()
	var families: PackedStringArray = _data.family_ids()
	assert_array(families).append_failure_message(
		"no families loaded from res://data"
	).is_not_empty()
	_family_id = families[0]
	var mfrs: PackedStringArray = _data.manufacturers_for(_family_id)
	assert_array(mfrs).append_failure_message(
		"no manufacturers for family '%s'" % _family_id
	).is_not_empty()
	_manufacturer_id = mfrs[0]


func _new_doc() -> ShipDoc:
	return ShipDoc.create_new(_family_id, _manufacturer_id, _data)


func _add_child(doc: ShipDoc, parent_id: String) -> ShipPart:
	var part: ShipPart = ShipPart.new()
	part.id = doc.new_part_id()
	part.parent = parent_id
	part.kind = ShipPart.KIND_PRIMITIVE
	part.family = _family_id
	part.manufacturer = _manufacturer_id
	part.params = ShapeGen.default_params(_data, _family_id, _manufacturer_id)
	part.yaw = 0.0
	part.pitch = 0.0
	part.rot = Vector3.ZERO
	part.offset = 0.0
	part.scale = Vector3.ONE
	part.blend = 0.0
	part.display_name = "part " + part.id
	@warning_ignore("return_value_discarded")
	doc.add_part(part)
	return part


func _part(doc: ShipDoc, id: String) -> ShipPart:
	return doc.parts[id] as ShipPart


func test_asymmetric_defaults_false_symmetry_is_on_by_default() -> void:
	var part: ShipPart = ShipPart.new()
	assert_bool(part.asymmetric).append_failure_message(
		"ShipPart.asymmetric must default to false -- symmetry is ON by default (Spore 2008)"
	).is_false()


func test_is_effectively_asymmetric_cascades_while_raw_flags_of_descendants_stay_false() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var grandchild: ShipPart = _add_child(doc, child.id)

	assert_bool(ShipSymmetry.is_effectively_asymmetric(doc, child.id)).append_failure_message(
		"a freshly placed part must not report effectively asymmetric before anything is set"
	).is_false()

	@warning_ignore("return_value_discarded")
	ShipSymmetry.set_asymmetric(doc, child.id, true)

	# The part that was actually marked: raw flag AND effective answer both true.
	assert_bool(_part(doc, child.id).asymmetric).append_failure_message(
		"set_asymmetric(child, true) should set the raw flag on the part itself"
	).is_true()
	assert_bool(ShipSymmetry.is_effectively_asymmetric(doc, child.id)).is_true()

	# The cascade target: raw flag stays FALSE (nobody touched it), effective answer is TRUE
	# (it inherits asymmetry from its ancestor). Asserting only one of these would miss a
	# regression to reading ShipPart.asymmetric directly.
	assert_bool(_part(doc, grandchild.id).asymmetric).append_failure_message(
		"breaking symmetry on an ancestor must NOT flip the descendant's own raw flag"
	).is_false()
	assert_bool(ShipSymmetry.is_effectively_asymmetric(doc, grandchild.id)).append_failure_message(
		"is_effectively_asymmetric() must cascade to descendants of an asymmetric part"
	).is_true()

	# The root, an unrelated ancestor of neither, stays symmetric throughout.
	assert_bool(ShipSymmetry.is_effectively_asymmetric(doc, doc.root)).append_failure_message(
		"marking a child asymmetric must not affect its parent"
	).is_false()


func test_set_asymmetric_returns_the_affected_subtree() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var grandchild: ShipPart = _add_child(doc, child.id)
	var sibling: ShipPart = _add_child(doc, doc.root)

	var changed: PackedStringArray = ShipSymmetry.set_asymmetric(doc, child.id, true)
	assert_int(changed.size()).append_failure_message(
		"set_asymmetric(child, true) should report exactly {child, grandchild} changed, got %s"
		% [changed]
	).is_equal(2)
	assert_array(changed).contains(child.id, grandchild.id)
	assert_array(changed).not_contains(sibling.id, doc.root)

	# Re-asserting the same value is a no-op: nothing's effective state changes, so nothing is
	# reported changed.
	var noop: PackedStringArray = ShipSymmetry.set_asymmetric(doc, child.id, true)
	assert_array(noop).append_failure_message(
		"re-setting the same value should report no changes, got %s" % [noop]
	).is_empty()

	# Flipping back reports the same subtree again.
	var reverted: PackedStringArray = ShipSymmetry.set_asymmetric(doc, child.id, false)
	assert_int(reverted.size()).append_failure_message(
		"reverting should report exactly {child, grandchild} changed again, got %s" % [reverted]
	).is_equal(2)
	assert_array(reverted).contains(child.id, grandchild.id)
	assert_bool(ShipSymmetry.is_effectively_asymmetric(doc, grandchild.id)).is_false()


func test_generates_twin_false_when_asymmetric() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()
	var off_plane: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0))

	assert_bool(ShipSymmetry.generates_twin(doc, child.id, off_plane, cfg)).append_failure_message(
		"an off-plane, symmetric part should generate a twin"
	).is_true()

	@warning_ignore("return_value_discarded")
	ShipSymmetry.set_asymmetric(doc, child.id, true)
	assert_bool(ShipSymmetry.generates_twin(doc, child.id, off_plane, cfg)).append_failure_message(
		"an asymmetric part must never generate a twin"
	).is_false()


func test_generates_twin_false_when_symmetry_plane_is_off() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()
	var off_plane: Transform3D = Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0))

	doc.symmetry_plane = ""
	assert_bool(ShipSymmetry.generates_twin(doc, child.id, off_plane, cfg)).append_failure_message(
		"generates_twin() must be false whenever the document has symmetry off entirely"
	).is_false()


func test_generates_twin_false_on_the_plane_within_epsilon() -> void:
	var doc: ShipDoc = _new_doc()
	var child: ShipPart = _add_child(doc, doc.root)
	var cfg: ShipConfig = ShipConfig.defaults()
	assert_float(cfg.symmetry_plane_epsilon).is_greater(0.0)

	var inside_band: Transform3D = Transform3D(
		Basis.IDENTITY, Vector3(cfg.symmetry_plane_epsilon * 0.5, 0.0, 0.0)
	)
	assert_bool(ShipSymmetry.generates_twin(doc, child.id, inside_band, cfg)).append_failure_message(
		"a part sitting on the symmetry plane (within epsilon) must not generate a twin"
	).is_false()

	var outside_band: Transform3D = Transform3D(
		Basis.IDENTITY, Vector3(cfg.symmetry_plane_epsilon * 4.0, 0.0, 0.0)
	)
	assert_bool(
		ShipSymmetry.generates_twin(doc, child.id, outside_band, cfg)
	).append_failure_message(
		"a part clearly off the symmetry plane must generate a twin"
	).is_true()


func test_twin_id_format_and_source_of_twin_round_trip() -> void:
	assert_str(ShipSymmetry.twin_id("p_0007")).is_equal("p_0007~m")
	assert_str(ShipSymmetry.source_of_twin(ShipSymmetry.twin_id("p_0007"))).is_equal("p_0007")
	assert_bool(ShipSymmetry.is_twin_id("p_0007~m")).is_true()
	assert_bool(ShipSymmetry.is_twin_id("p_0007")).is_false()
	# Per the contract's own docs: source_of_twin() hands back a non-twin id unchanged, so a
	# caller never has to test is_twin_id() before calling it.
	assert_str(ShipSymmetry.source_of_twin("p_0007")).is_equal("p_0007")
