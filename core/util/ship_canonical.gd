class_name ShipCanonical
extends RefCounted

## The determinism contract — SPEC section 4, API_CONTRACT section 1.
##
## Every byte that ever feeds a hash passes through this file. A ship that hashes to X
## today must hash to X forever under its recorded ruleset version, so changing the
## behaviour of ANY function here moves every saved ship and requires a ruleset bump
## plus an ADR. Adding a new helper is free; changing an existing one is not.
##
## Pure static utility. No state, no RandomNumberGenerator, no engine singletons,
## no allocation beyond the strings it returns.

## Decimal places kept by [method quantize]. Six decimals at the 250 m maximum ship
## extent is one micrometre — three orders of magnitude below the finest authored
## feature (~0.01 m), so quantizing can never move geometry. It only kills the
## last-bit float noise that would otherwise flip a hash between two runs.
const DECIMALS: int = 6

## 10 ^ DECIMALS. Must agree with [constant DECIMALS] and [constant FLOAT_FORMAT].
const SCALE: float = 1000000.0

## printf form emitted for every float by [method canonical_json]. Must have exactly
## [constant DECIMALS] decimals. This is what keeps int 4 and float 4.0 from colliding:
## the int emits bare "4", the float emits "4.000000".
const FLOAT_FORMAT: String = "%.6f"

## FNV-1a 64-bit constants. GDScript ints are signed two's-complement int64, so the
## unsigned offset basis 14695981039346656037 is written here as its signed bit
## pattern (14695981039346656037 - 2^64).
const FNV_OFFSET_BASIS: int = -3750763034362895579
const FNV_PRIME: int = 1099511628211

## splitmix64 finalizer constants, again as signed bit patterns:
## 0xBF58476D1CE4E5B9 and 0x94D049BB133111EB.
const MIX_A: int = -4658895280553007687
const MIX_B: int = -7723592293110705685

## Low 53 bits — the exactly-representable range of a float64 mantissa.
const MANTISSA_MASK: int = 0x1FFFFFFFFFFFFF
const MANTISSA_DIV: float = 9007199254740992.0

const HEX_DIGITS: String = "0123456789abcdef"

## Tokens for the three non-finite floats. [method canonical_json] is a *hashing*
## serialization, not a round-trippable JSON document, so these are emitted bare
## rather than being coerced to null (which would collide with a real null).
const TOKEN_INF: String = "Infinity"
const TOKEN_NEG_INF: String = "-Infinity"
const TOKEN_NAN: String = "NaN"


## Rounds [param f] to exactly [constant DECIMALS] decimal places.
##
## Non-finite values pass through untouched. Negative zero is normalised to positive
## zero so that -0.0 and 0.0 can never produce two different hashes for the same ship.
static func quantize(f: float) -> float:
	if not is_finite(f):
		return f
	var q: float = round(f * SCALE) / SCALE
	if q == 0.0:
		# Catches -0.0, which compares equal to 0.0 but formats as "-0.000000".
		return 0.0
	return q


## Serializes [param v] to the canonical byte string used for hashing.
##
## Rules, all load-bearing:
## [br]- dictionary keys are sorted lexicographically, recursively, at every depth
## [br]- arrays keep their order (order is data)
## [br]- floats are quantized and always emitted with [constant DECIMALS] decimals
## [br]- ints are emitted bare, so int 4 ("4") never collides with float 4.0 ("4.000000")
## [br]- no whitespace anywhere
## [br]
## Vectors, colours, transforms and the packed arrays are flattened to plain arrays of
## their (quantized) components. Objects are not serializable state and emit "null" —
## convert them to dictionaries before hashing. Two dictionary keys whose string forms
## are equal collapse to one entry; JSON-sourced dictionaries always have string keys,
## so this cannot happen in practice.
static func canonical_json(v: Variant) -> String:
	var out: PackedStringArray = PackedStringArray()
	_write(v, out)
	return "".join(out)


## Standard 64-bit FNV-1a over the UTF-8 bytes of [param s].
##
## The accumulator is a signed int64 and the multiply is allowed to overflow: GDScript
## ints are two's-complement, so `h * FNV_PRIME` wraps modulo 2^64 exactly as the
## reference unsigned implementation does. The returned int is therefore the signed
## reading of an unsigned 64-bit hash and is frequently negative. Use [method hex64]
## when a stable printable form is wanted.
static func fnv1a_64(s: String) -> int:
	var bytes: PackedByteArray = s.to_utf8_buffer()
	var h: int = FNV_OFFSET_BASIS
	var n: int = bytes.size()
	for i: int in n:
		h ^= bytes[i]
		h = h * FNV_PRIME
	return h


## Zero-padded lowercase hex of the unsigned 64-bit reading of [param v].
##
## Written by hand rather than with "%x" because Godot's format operator renders a
## negative int64 with a leading minus, which is not a 64-bit hash.
static func hex64(v: int) -> String:
	var out: String = ""
	for i: int in 16:
		var nibble: int = (v >> ((15 - i) * 4)) & 0xF
		out += HEX_DIGITS[nibble]
	return out


## Derives an independent sub-stream from [param seed].
##
## Rib phase and scallop phase must never correlate, so each detail generator asks for
## its own stream by name ("rib_phase", "scallop_phase", ...) instead of pulling
## successive values off one sequence. Two different stream names always avalanche to
## unrelated seeds; the same (seed, stream) pair always returns the same value.
@warning_ignore("shadowed_global_identifier")
static func sub_seed(seed: int, stream: String) -> int:
	# `seed` shadows the global seed() utility. The name is pinned by API_CONTRACT
	# section 1 and parameter names are not part of a GDScript call site, so the
	# contract wins and the warning is suppressed here rather than renamed.
	return _mix64(seed ^ fnv1a_64(stream))


## Deterministic value in [param lo] .. [param hi], a pure function of [param seed].
##
## No RandomNumberGenerator, no state carried between calls: calling this a thousand
## times with the same seed returns the same number a thousand times. The seed is
## avalanched, the low 53 bits are taken (the exactly-representable mantissa range),
## normalised to [0, 1) and lerped. Half-open at the top, like every other RNG range.
@warning_ignore("shadowed_global_identifier")
static func rand_range_from(seed: int, lo: float, hi: float) -> float:
	# See sub_seed() for why the parameter keeps the shadowing name.
	var bits: int = _mix64(seed) & MANTISSA_MASK
	var u: float = float(bits) / MANTISSA_DIV
	return lo + (hi - lo) * u


# --- internals ---------------------------------------------------------------------


## splitmix64 finalizer. Avalanches every input bit across all 64 output bits, so
## seeds that differ by one (p_0001 vs p_0002) produce completely unrelated streams.
## Multiplies wrap modulo 2^64, same as [method fnv1a_64].
static func _mix64(x: int) -> int:
	var z: int = x
	z = (z ^ _ushr(z, 30)) * MIX_A
	z = (z ^ _ushr(z, 27)) * MIX_B
	z = z ^ _ushr(z, 31)
	return z


## Logical (zero-filling) right shift. GDScript's >> is arithmetic and sign-extends,
## which would feed the hash back its own sign bit sixty-odd times.
static func _ushr(v: int, n: int) -> int:
	if n <= 0:
		return v
	if n >= 64:
		return 0
	return ((v >> 1) & 0x7FFFFFFFFFFFFFFF) >> (n - 1)


static func _float_token(f: float) -> String:
	var q: float = quantize(f)
	if is_nan(q):
		return TOKEN_NAN
	if is_inf(q):
		return TOKEN_NEG_INF if q < 0.0 else TOKEN_INF
	return FLOAT_FORMAT % q


static func _quote(s: String) -> String:
	var out: String = '"'
	var n: int = s.length()
	for i: int in n:
		var code: int = s.unicode_at(i)
		if code == 34:
			out += '\\"'
		elif code == 92:
			out += "\\\\"
		elif code == 8:
			out += "\\b"
		elif code == 9:
			out += "\\t"
		elif code == 10:
			out += "\\n"
		elif code == 12:
			out += "\\f"
		elif code == 13:
			out += "\\r"
		elif code < 32:
			out += "\\u%04x" % code
		else:
			out += s[i]
	out += '"'
	return out


static func _write(v: Variant, out: PackedStringArray) -> void:
	match typeof(v):
		TYPE_NIL:
			out.append("null")
		TYPE_BOOL:
			var b: bool = v
			out.append("true" if b else "false")
		TYPE_INT:
			var i: int = v
			out.append(str(i))
		TYPE_FLOAT:
			var f: float = v
			out.append(_float_token(f))
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			out.append(_quote(str(v)))
		TYPE_DICTIONARY:
			var d: Dictionary = v
			_write_dict(d, out)
		TYPE_ARRAY:
			var a: Array = v
			_write_array(a, out)
		TYPE_PACKED_BYTE_ARRAY:
			var pba: PackedByteArray = v
			_write_array(Array(pba), out)
		TYPE_PACKED_INT32_ARRAY:
			var pi32: PackedInt32Array = v
			_write_array(Array(pi32), out)
		TYPE_PACKED_INT64_ARRAY:
			var pi64: PackedInt64Array = v
			_write_array(Array(pi64), out)
		TYPE_PACKED_FLOAT32_ARRAY:
			var pf32: PackedFloat32Array = v
			_write_array(Array(pf32), out)
		TYPE_PACKED_FLOAT64_ARRAY:
			var pf64: PackedFloat64Array = v
			_write_array(Array(pf64), out)
		TYPE_PACKED_STRING_ARRAY:
			var psa: PackedStringArray = v
			_write_array(Array(psa), out)
		TYPE_PACKED_VECTOR2_ARRAY:
			var pv2: PackedVector2Array = v
			_write_array(Array(pv2), out)
		TYPE_PACKED_VECTOR3_ARRAY:
			var pv3: PackedVector3Array = v
			_write_array(Array(pv3), out)
		TYPE_PACKED_VECTOR4_ARRAY:
			var pv4: PackedVector4Array = v
			_write_array(Array(pv4), out)
		TYPE_PACKED_COLOR_ARRAY:
			var pca: PackedColorArray = v
			_write_array(Array(pca), out)
		TYPE_VECTOR2:
			var v2: Vector2 = v
			_write_floats([v2.x, v2.y], out)
		TYPE_VECTOR2I:
			var v2i: Vector2i = v
			_write_ints([v2i.x, v2i.y], out)
		TYPE_VECTOR3:
			var v3: Vector3 = v
			_write_floats([v3.x, v3.y, v3.z], out)
		TYPE_VECTOR3I:
			var v3i: Vector3i = v
			_write_ints([v3i.x, v3i.y, v3i.z], out)
		TYPE_VECTOR4:
			var v4: Vector4 = v
			_write_floats([v4.x, v4.y, v4.z, v4.w], out)
		TYPE_VECTOR4I:
			var v4i: Vector4i = v
			_write_ints([v4i.x, v4i.y, v4i.z, v4i.w], out)
		TYPE_COLOR:
			var c: Color = v
			_write_floats([c.r, c.g, c.b, c.a], out)
		TYPE_QUATERNION:
			var q: Quaternion = v
			_write_floats([q.x, q.y, q.z, q.w], out)
		TYPE_PLANE:
			var pl: Plane = v
			_write_floats([pl.normal.x, pl.normal.y, pl.normal.z, pl.d], out)
		TYPE_RECT2:
			var r2: Rect2 = v
			_write_floats([r2.position.x, r2.position.y, r2.size.x, r2.size.y], out)
		TYPE_RECT2I:
			var r2i: Rect2i = v
			_write_ints([r2i.position.x, r2i.position.y, r2i.size.x, r2i.size.y], out)
		TYPE_AABB:
			var bb: AABB = v
			_write_floats(
				[
					bb.position.x,
					bb.position.y,
					bb.position.z,
					bb.size.x,
					bb.size.y,
					bb.size.z,
				],
				out
			)
		TYPE_BASIS:
			var bs: Basis = v
			_write_floats(
				[
					bs.x.x,
					bs.x.y,
					bs.x.z,
					bs.y.x,
					bs.y.y,
					bs.y.z,
					bs.z.x,
					bs.z.y,
					bs.z.z,
				],
				out
			)
		TYPE_TRANSFORM2D:
			var t2: Transform2D = v
			_write_floats([t2.x.x, t2.x.y, t2.y.x, t2.y.y, t2.origin.x, t2.origin.y], out)
		TYPE_TRANSFORM3D:
			var t3: Transform3D = v
			_write_floats(
				[
					t3.basis.x.x,
					t3.basis.x.y,
					t3.basis.x.z,
					t3.basis.y.x,
					t3.basis.y.y,
					t3.basis.y.z,
					t3.basis.z.x,
					t3.basis.z.y,
					t3.basis.z.z,
					t3.origin.x,
					t3.origin.y,
					t3.origin.z,
				],
				out
			)
		TYPE_OBJECT:
			# Objects carry an instance id that changes every run. Anything hashable
			# must be reduced to a dictionary by its owner first.
			out.append("null")
		_:
			out.append(_quote(str(v)))


static func _write_dict(d: Dictionary, out: PackedStringArray) -> void:
	var names: PackedStringArray = PackedStringArray()
	var values: Dictionary = {}
	for key: Variant in d:
		var name: String = str(key)
		if not values.has(name):
			names.append(name)
		values[name] = d[key]
	names.sort()
	out.append("{")
	var n: int = names.size()
	for i: int in n:
		if i > 0:
			out.append(",")
		out.append(_quote(names[i]))
		out.append(":")
		_write(values[names[i]], out)
	out.append("}")


static func _write_array(a: Array, out: PackedStringArray) -> void:
	out.append("[")
	var n: int = a.size()
	for i: int in n:
		if i > 0:
			out.append(",")
		_write(a[i], out)
	out.append("]")


static func _write_floats(values: Array, out: PackedStringArray) -> void:
	out.append("[")
	var n: int = values.size()
	for i: int in n:
		if i > 0:
			out.append(",")
		var f: float = values[i]
		out.append(_float_token(f))
	out.append("]")


static func _write_ints(values: Array, out: PackedStringArray) -> void:
	out.append("[")
	var n: int = values.size()
	for i: int in n:
		if i > 0:
			out.append(",")
		var iv: int = values[i]
		out.append(str(iv))
	out.append("]")
