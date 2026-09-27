# The determinism gate. ShipHash.shape_seed and ShipHash.doc_hash are the load-bearing
# promise of SPEC section 4: identical params -> identical shape, forever. These tests must
# never be relaxed to make an implementation pass; if one fails, the canonicalisation broke.
class_name TestHash
extends GdUnitTestSuite

var _data: ShipData
var _family_id: String
var _manufacturer_id: String


func before() -> void:
	_data = ShipData.new()
	var ok: bool = _data.load_all()
	(
		assert_bool(ok)
		. append_failure_message(
			"ShipData.load_all() failed, load_errors=%s" % [str(_data.load_errors)]
		)
		. is_true()
	)
	(
		assert_array(_data.load_errors)
		. append_failure_message(
			"res://data packs reported load_errors: %s" % [str(_data.load_errors)]
		)
		. is_empty()
	)
	var families: PackedStringArray = _data.family_ids()
	(
		assert_array(families)
		. append_failure_message(
			"no families loaded from res://data -- doc_hash tests need at least one"
		)
		. is_not_empty()
	)
	_family_id = families[0]
	var mfrs: PackedStringArray = _data.manufacturers_for(_family_id)
	(
		assert_array(mfrs)
		. append_failure_message("no manufacturers for family '%s'" % _family_id)
		. is_not_empty()
	)
	_manufacturer_id = mfrs[0]


func test_shape_seed_deterministic_across_repeated_calls() -> void:
	var params: Dictionary = {"taper": 0.3, "ribs": 4, "scallop": 0.15}
	var s1: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.0")
	var s2: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.0")
	var s3: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.0")
	assert_int(s2).is_equal(s1)
	assert_int(s3).is_equal(s1)


func test_shape_seed_is_independent_of_param_insertion_order() -> void:
	var a: Dictionary = {}
	a["taper"] = 0.3
	a["ribs"] = 4
	a["scallop"] = 0.15
	var b: Dictionary = {}
	b["scallop"] = 0.15
	b["ribs"] = 4
	b["taper"] = 0.3
	var seed_a: int = ShipHash.shape_seed("hull_box", "voss", a, "1.0.0")
	var seed_b: int = ShipHash.shape_seed("hull_box", "voss", b, "1.0.0")
	assert_int(seed_b).is_equal(seed_a)


func test_shape_seed_changes_with_any_single_param() -> void:
	var base: Dictionary = {"taper": 0.30, "ribs": 4, "scallop": 0.15}
	var base_seed: int = ShipHash.shape_seed("hull_box", "voss", base, "1.0.0")

	var float_changed: Dictionary = {"taper": 0.31, "ribs": 4, "scallop": 0.15}
	var int_changed: Dictionary = {"taper": 0.30, "ribs": 5, "scallop": 0.15}
	var other_float_changed: Dictionary = {"taper": 0.30, "ribs": 4, "scallop": 0.16}

	assert_int(ShipHash.shape_seed("hull_box", "voss", float_changed, "1.0.0")).is_not_equal(
		base_seed
	)
	assert_int(ShipHash.shape_seed("hull_box", "voss", int_changed, "1.0.0")).is_not_equal(
		base_seed
	)
	assert_int(ShipHash.shape_seed("hull_box", "voss", other_float_changed, "1.0.0")).is_not_equal(
		base_seed
	)


func test_shape_seed_changes_with_family() -> void:
	var params: Dictionary = {"taper": 0.3}
	var s1: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.0")
	var s2: int = ShipHash.shape_seed("hull_wedge", "voss", params, "1.0.0")
	assert_int(s2).is_not_equal(s1)


func test_shape_seed_changes_with_manufacturer() -> void:
	var params: Dictionary = {"taper": 0.3}
	var s1: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.0")
	var s2: int = ShipHash.shape_seed("hull_box", "kessler", params, "1.0.0")
	assert_int(s2).is_not_equal(s1)


func test_shape_seed_changes_with_ruleset() -> void:
	var params: Dictionary = {"taper": 0.3}
	var s1: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.0")
	var s2: int = ShipHash.shape_seed("hull_box", "voss", params, "1.0.1")
	assert_int(s2).is_not_equal(s1)


func test_shape_seed_frozen_reference_value() -> void:
	# PROVISIONAL FROZEN REFERENCE -- see the test-writer's report for the full caveat.
	# API_CONTRACT.md pins shape_seed's *properties* (deterministic; order-independent in
	# params; sensitive to every other input) but not the exact byte-level combination of
	# (family_id, manufacturer_id, ruleset, params) fed to fnv1a_64. This literal was
	# computed by hand assuming the most natural faithful implementation: wrap the four
	# inputs in one dict --
	#   {"family": family_id, "manufacturer": manufacturer_id, "params": params,
	#    "ruleset": ruleset}
	# -- canonicalize it with ShipCanonical.canonical_json (sorted keys, quantized floats,
	# no spaces) and hash the resulting UTF-8 string with ShipCanonical.fnv1a_64, keeping
	# the raw 64-bit result as a signed int.
	#
	# If ShipHash.shape_seed combines its inputs differently, THIS ONE TEST fails while
	# every other test in this file still passes -- that is a one-line fix, not evidence of
	# a bug: run shape_seed once for the inputs below, read off the real value, replace the
	# literal below. Once replaced it is frozen for real -- any future change to the
	# canonicalisation (float precision, key names, separators, op order) moves this number
	# and this test catches it, per SPEC section 4's "ruleset bump and an ADR" rule.
	var family_id: String = "hull_box"
	var manufacturer_id: String = "voss"
	var ruleset: String = "1.0.0"
	var params: Dictionary = {"ribs": 4, "segments": 8}
	var seed: int = ShipHash.shape_seed(family_id, manufacturer_id, params, ruleset)
	(
		assert_int(seed)
		. append_failure_message(
			(
				(
					"shape_seed('%s','%s',%s,'%s') = %d, expected frozen -184016924223680967. "
					% [family_id, manufacturer_id, str(params), ruleset, seed]
				)
				+ "See the comment above this assertion before treating this as a real bug."
			)
		)
		. is_equal(-184016924223680967)
	)


func test_doc_hash_deterministic_for_identically_built_docs() -> void:
	var doc1: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var doc2: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	assert_str(ShipHash.doc_hash(doc2)).is_equal(ShipHash.doc_hash(doc1))


func test_doc_hash_changes_when_doc_is_edited() -> void:
	var doc: ShipDoc = ShipDoc.create_new(_family_id, _manufacturer_id, _data)
	var hash_before: String = ShipHash.doc_hash(doc)
	var root_part: ShipPart = doc.parts[doc.root] as ShipPart
	root_part.display_name = root_part.display_name + "_edited_for_test"
	var hash_after: String = ShipHash.doc_hash(doc)
	assert_str(hash_after).is_not_equal(hash_before)
