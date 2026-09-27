# Determinism primitives: ShipCanonical.quantize / canonical_json / fnv1a_64 / sub_seed /
# rand_range_from. These are the foundation everything in ShipHash and ShipDoc.duplicate_doc
# stands on, so every property here is load-bearing for the rest of the suite.
class_name TestCanonical
extends GdUnitTestSuite


func test_quantize_rounds_to_6dp() -> void:
	# 7th decimal digit is 1: rounds down under every rounding convention, no tie ambiguity.
	assert_float(ShipCanonical.quantize(2.1234561)).is_equal_approx(2.123456, 0.0000001)
	# 7th decimal digit is 9: rounds up under every rounding convention, no tie ambiguity.
	assert_float(ShipCanonical.quantize(2.1234569)).is_equal_approx(2.123457, 0.0000001)


func test_quantize_kills_float_noise() -> void:
	# The canonical textbook float-noise case: 0.1 + 0.2 != 0.3 at full double precision.
	# quantize() is documented to kill exactly this kind of noise.
	var noisy: float = 0.1 + 0.2
	assert_float(ShipCanonical.quantize(noisy)).is_equal_approx(0.3, 0.0000001)


func test_quantize_negative_values() -> void:
	assert_float(ShipCanonical.quantize(-1.2345678)).is_equal_approx(-1.234568, 0.0000001)


func test_quantize_is_idempotent() -> void:
	# Quantizing an already-quantized value must not drift further.
	var once: float = ShipCanonical.quantize(3.14159265)
	var twice: float = ShipCanonical.quantize(once)
	assert_float(twice).is_equal_approx(once, 0.0000001)


func test_canonical_json_key_order_independent() -> void:
	var a: Dictionary = {}
	a["zebra"] = 1
	a["apple"] = 2
	a["mango"] = 3
	var b: Dictionary = {}
	b["mango"] = 3
	b["apple"] = 2
	b["zebra"] = 1
	assert_str(ShipCanonical.canonical_json(a)).is_equal(ShipCanonical.canonical_json(b))


func test_canonical_json_nested_sorted() -> void:
	var a: Dictionary = {}
	a["b"] = {"y": 1, "x": 2}
	a["a"] = 3
	var b: Dictionary = {}
	b["a"] = 3
	b["b"] = {"x": 2, "y": 1}
	assert_str(ShipCanonical.canonical_json(a)).is_equal(ShipCanonical.canonical_json(b))


func test_canonical_json_int_vs_float_differ() -> void:
	# The determinism contract explicitly requires int 4 and float 4.0 to canonicalize
	# differently, so a param authored as an int never silently collides with the same
	# value authored as a float.
	assert_str(ShipCanonical.canonical_json(4)).is_not_equal(ShipCanonical.canonical_json(4.0))
	var with_int: Dictionary = {"n": 4}
	var with_float: Dictionary = {"n": 4.0}
	var json_int: String = ShipCanonical.canonical_json(with_int)
	var json_float: String = ShipCanonical.canonical_json(with_float)
	assert_str(json_int).is_not_equal(json_float)


func test_canonical_json_has_no_spaces() -> void:
	var d: Dictionary = {"taper": 0.3, "ribs": 4, "nested": {"a": 1, "b": 2}}
	var json: String = ShipCanonical.canonical_json(d)
	assert_str(json).not_contains(" ")


func test_fnv1a_64_stable_for_repeated_calls() -> void:
	var h1: int = ShipCanonical.fnv1a_64("hello world")
	var h2: int = ShipCanonical.fnv1a_64("hello world")
	assert_int(h2).is_equal(h1)


func test_fnv1a_64_known_value_for_empty_string() -> void:
	# FROZEN REFERENCE. For zero input bytes, FNV-1a processes nothing and must return the
	# raw 64-bit offset basis (14695981039346656037) unchanged, regardless of string
	# encoding, since there are no bytes to XOR/multiply against. Reinterpreted as a signed
	# 64-bit int (two's complement, since the unsigned value exceeds INT64_MAX) that is
	# -3750763034362895579. This is pure math, not an implementation guess: any faithful
	# 64-bit FNV-1a returns exactly this for "".
	assert_int(ShipCanonical.fnv1a_64("")).is_equal(-3750763034362895579)


func test_fnv1a_64_differs_for_different_input() -> void:
	var h_a: int = ShipCanonical.fnv1a_64("abc")
	var h_b: int = ShipCanonical.fnv1a_64("abd")
	assert_int(h_a).is_not_equal(h_b)


func test_sub_seed_deterministic() -> void:
	var s1: int = ShipCanonical.sub_seed(42, "ribs")
	var s2: int = ShipCanonical.sub_seed(42, "ribs")
	assert_int(s2).is_equal(s1)


func test_sub_seed_depends_on_stream_and_seed() -> void:
	var base: int = ShipCanonical.sub_seed(42, "ribs")
	var other_stream: int = ShipCanonical.sub_seed(42, "scallop")
	var other_seed: int = ShipCanonical.sub_seed(43, "ribs")
	assert_int(other_stream).is_not_equal(base)
	assert_int(other_seed).is_not_equal(base)


func test_rand_range_from_is_pure_and_interleavable() -> void:
	# No RNG state: calling with unrelated seeds in between must not perturb the result.
	var v1: float = ShipCanonical.rand_range_from(7, 0.0, 10.0)
	@warning_ignore("return_value_discarded")
	ShipCanonical.rand_range_from(999, -5.0, 5.0)
	@warning_ignore("return_value_discarded")
	ShipCanonical.rand_range_from(1, 0.0, 1.0)
	var v2: float = ShipCanonical.rand_range_from(7, 0.0, 10.0)
	assert_float(v2).is_equal(v1)


func test_rand_range_from_stays_in_half_open_bounds() -> void:
	var seed_index: int = 0
	while seed_index < 25:
		var v: float = ShipCanonical.rand_range_from(seed_index, -3.0, 8.0)
		(
			assert_float(v)
			. append_failure_message(
				"seed %d produced %f, expected in [-3.0, 8.0)" % [seed_index, v]
			)
			. is_greater_equal(-3.0)
		)
		(
			assert_float(v)
			. append_failure_message(
				"seed %d produced %f, expected in [-3.0, 8.0)" % [seed_index, v]
			)
			. is_less(8.0)
		)
		seed_index += 1
