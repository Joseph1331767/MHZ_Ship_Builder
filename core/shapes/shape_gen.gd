class_name ShapeGen
extends RefCounted

## Turns (family + manufacturer + params + scale) into a `ResolvedShape`.
##
## SPEC section 4 is the contract this implements:
##
## - The FAMILY defines the generator: base primitive, base size, which ops exist, and the
##   authored parameter ranges.
## - The MANUFACTURER is a legible style preset: it NARROWS the family's ranges, may disable
##   ops (`ops_disabled`) and carries a `cost_multiplier`. It can never widen a range.
## - The SEED drives MICRO-DETAIL ONLY — rib phase, scallop phase, sub-range detail jitter.
##   It is derived (`ShipHash.shape_seed`), never stored, never rolled. Identical params give
##   an identical shape, forever.
##
## The safety property, and the reason `resolve()` deliberately does NOT clamp:
## **ranges gate input, the hash consumes output.** Param values live explicitly in the doc, so
## retuning a manufacturer's ranges later must not move a single saved ship. Clamping happens
## at input time through `clamp_params()`; `resolve()` renders exactly what the doc stores.
## Only changing this generator — what `taper = 0.3` means geometrically — moves ships, and
## that earns a ruleset bump and an ADR.
##
## Everything here is cold path: called once per part per rebuild, never per SDF sample.
##
## `core/` purity: static only, no state, no engine objects, no `res://`.

## Ruleset string fed to `ShipHash.shape_seed()`. Mirrors `ShipDoc.RULESET_VERSION` but is kept
## local so `core/shapes/` carries no compile-time dependency on `core/ship_doc.gd`, which calls
## into this class (a mutual `class_name` reference is a known cyclic-parse hazard).
## 4.0.0 (ADR 0007): SHEAR. A fourth morph verb - "spore has handles that ... stretch, skew, twist,
## rotate" - and the first op inserted into the domain-warp stage rather than appended, because a
## domain warp cannot be appended: everything after the base operates on a distance. At its default
## of zero it is the identity, so NO shape moves; the bump is for the canonical form, which now
## carries two more params, and for the op order, which AGENTS section 8b makes a version event
## whatever its visible effect.
const RULESET_VERSION: String = "4.0.0"

## Canonical parameter keys expected in `data/shapes/families.json`. Aliases are accepted on
## read (see `_aliases_for()`), so a pack may use `round` for `bevel` and still resolve.
const KEY_TAPER: String = "taper"
const KEY_TWIST: String = "twist"
const KEY_BEVEL: String = "bevel"
const KEY_RIBS: String = "ribs"
const KEY_RIB_AMP: String = "rib_amp"
const KEY_SCALLOP: String = "scallop"
const KEY_SCALLOP_FREQ: String = "scallop_freq"
## CYLINDER only, ADR 0005. Both are RATIOS, not metres, so they survive a resize:
## `end_radius` scales the +Y end against the -Y end (1 = cylinder, 0 = point-tipped cone) and
## `end_round` rounds both end discs as a fraction of the WIDER end (0 = flat, 1 = capsule).
const KEY_END_RADIUS: String = "end_radius"
const KEY_END_ROUND: String = "end_round"
## Shear, ADR 0007. Metres of sideways travel per metre of local Y, measured from the centre:
## `skew_x` leans the part toward +X as Y rises, `skew_z` toward +Z.
const KEY_SKEW_X: String = "skew_x"
const KEY_SKEW_Z: String = "skew_z"

## Canonical op names, as listed in a family's `ops` array and a manufacturer's `ops_disabled`.
const OP_TAPER: String = "taper"
const OP_TWIST: String = "twist"
const OP_ROUND: String = "round"
const OP_RIBS: String = "ribs"
const OP_SCALLOP: String = "scallop"
## The op that owns `end_radius` and `end_round`. A family that omits "ends" from its `ops`
## list gets a plain flat-ended cylinder, which is what every pre-ADR-0005 pack means.
const OP_ENDS: String = "ends"
## The op that owns `skew_x` and `skew_z`.
const OP_SKEW: String = "skew"

## Sub-seed stream names. Adding one is safe; renaming one re-rolls every ship's micro-detail.
const SEED_RIB_PHASE: String = "rib_phase"
const SEED_SCALLOP_PHASE: String = "scallop_phase"
const SEED_RIB_JITTER: String = "rib_amp"
const SEED_SCALLOP_JITTER: String = "scallop_amp"

## Used when a family exposes a scallop amplitude but authors no frequency.
const DEFAULT_SCALLOP_FREQ: float = 4.0

## Hard ceiling on the family-authored `detail_jitter` (a fraction of the authored amplitude).
const MAX_DETAIL_JITTER: float = 0.5


## Family ranges intersected with the manufacturer's narrowing.
## Returns `param_key -> { "min": float, "max": float, "default": float, "is_int": bool }`,
## keyed by whatever names the family pack uses. A disabled op has its params pinned to zero.
static func effective_ranges(
	data: ShipData, family_id: String, manufacturer_id: String
) -> Dictionary:
	var out: Dictionary = {}
	var fam: Dictionary = _family(data, family_id)
	if fam.is_empty():
		return out
	var raw: Dictionary = _params_section(fam)
	for key: String in raw:
		out[key] = _norm_range(raw[key], key)

	var mfr: Dictionary = _manufacturer(data, manufacturer_id)
	var keys: Array = out.keys()
	var top: Dictionary = _ranges_section(mfr)
	var per: Dictionary = _ranges_section(_mfr_family_entry(mfr, family_id))
	for key: String in keys:
		if top.has(key):
			out[key] = _narrow(_dict_of(out[key]), top[key], key)
		if per.has(key):
			out[key] = _narrow(_dict_of(out[key]), per[key], key)

	var fam_ops: PackedStringArray = _family_ops(fam)
	var disabled: PackedStringArray = _ops_disabled(mfr, family_id)
	for key: String in keys:
		var op: String = _op_for_param(_canonical_key(key))
		if op.is_empty():
			continue
		if disabled.has(op) or not _op_enabled(fam_ops, op):
			out[key] = _pin_neutral(_dict_of(out[key]), _canonical_key(key))
	return out


## The default parameter set for a family/manufacturer pair, already inside the effective
## ranges. This is what a freshly placed part starts with.
static func default_params(
	data: ShipData, family_id: String, manufacturer_id: String
) -> Dictionary:
	var out: Dictionary = {}
	var ranges: Dictionary = effective_ranges(data, family_id, manufacturer_id)
	for key: String in ranges:
		var r: Dictionary = _dict_of(ranges[key])
		var def: float = _num(r.get("default"), 0.0)
		if _bool_of(r.get("is_int"), false):
			out[key] = int(roundf(def))
		else:
			out[key] = def
	return out


## Clamps `params` into the effective ranges and fills in anything missing. Returns a NEW
## dictionary; `params` is never mutated. Integer params stay ints so the canonical hash of an
## already-legal doc does not churn.
##
## Unknown keys are passed through untouched — this is an input gate, not a data shredder.
static func clamp_params(
	data: ShipData, family_id: String, manufacturer_id: String, params: Dictionary
) -> Dictionary:
	var out: Dictionary = params.duplicate(true)
	var ranges: Dictionary = effective_ranges(data, family_id, manufacturer_id)
	for key: String in ranges:
		var r: Dictionary = _dict_of(ranges[key])
		var lo: float = _num(r.get("min"), 0.0)
		var hi: float = _num(r.get("max"), lo)
		var def: float = _num(r.get("default"), lo)
		var raw: Variant = out.get(key)
		var v: float = clampf(_num(raw, def), lo, hi)
		if _bool_of(r.get("is_int"), false) or raw is int:
			out[key] = int(roundf(v))
		else:
			out[key] = v
	return out


## Builds the shape. `size` stays the family's unscaled `base_size`; the part's per-axis
## `scale` goes onto `ResolvedShape.scale`, where `sdf()` applies it as
## `min(scale) * base_sdf(p / scale)` — a real ellipsoid for a stretched sphere, and a
## conservative distance bound. The ship-space transform therefore stays rigid.
##
## Deliberately does not clamp: see the class docs.
static func resolve(
	data: ShipData, family_id: String, manufacturer_id: String, params: Dictionary, scale: Vector3
) -> ResolvedShape:
	var fam: Dictionary = _family(data, family_id)
	if fam.is_empty():
		return _fallback_shape(scale)

	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = _base_enum(fam)
	shape.size = _base_size(fam)
	shape.scale = scale
	shape.origin_inside = _origin_inside(fam, shape.base)

	var fam_ops: PackedStringArray = _family_ops(fam)
	var defs: Dictionary = _canonical_defaults(fam)
	var taper_v: float = 0.0
	if _op_enabled(fam_ops, OP_TAPER):
		taper_v = _param_float(params, KEY_TAPER, _num(defs.get(KEY_TAPER), 0.0))
	var twist_v: float = 0.0
	if _op_enabled(fam_ops, OP_TWIST):
		twist_v = _param_float(params, KEY_TWIST, _num(defs.get(KEY_TWIST), 0.0))
	if _op_enabled(fam_ops, OP_ROUND):
		shape.round_r = _param_float(params, KEY_BEVEL, _num(defs.get(KEY_BEVEL), 0.0))
	if _op_enabled(fam_ops, OP_RIBS):
		shape.rib_count = _param_int(params, KEY_RIBS, _int_of(defs.get(KEY_RIBS), 0))
		shape.rib_amp = _param_float(params, KEY_RIB_AMP, _num(defs.get(KEY_RIB_AMP), 0.0))
	if _op_enabled(fam_ops, OP_SCALLOP):
		shape.scallop_amp = _param_float(params, KEY_SCALLOP, _num(defs.get(KEY_SCALLOP), 0.0))
		shape.scallop_freq = _param_float(
			params, KEY_SCALLOP_FREQ, _num(defs.get(KEY_SCALLOP_FREQ), DEFAULT_SCALLOP_FREQ)
		)
	shape.taper = taper_v
	shape.twist_deg = twist_v
	if _op_enabled(fam_ops, OP_SKEW):
		shape.shear = Vector2(
			_param_float(params, KEY_SKEW_X, _num(defs.get(KEY_SKEW_X), 0.0)),
			_param_float(params, KEY_SKEW_Z, _num(defs.get(KEY_SKEW_Z), 0.0))
		)
	_apply_end_params(shape, params, fam_ops, defs)

	# Micro-detail only. The seed may never touch a value the player set.
	var detail_seed: int = ShipHash.shape_seed(family_id, manufacturer_id, params, RULESET_VERSION)
	shape.rib_phase = ShipCanonical.rand_range_from(
		ShipCanonical.sub_seed(detail_seed, SEED_RIB_PHASE), 0.0, TAU
	)
	shape.scallop_phase = ShipCanonical.rand_range_from(
		ShipCanonical.sub_seed(detail_seed, SEED_SCALLOP_PHASE), 0.0, TAU
	)
	var jitter: float = clampf(_num(fam.get("detail_jitter"), 0.0), 0.0, MAX_DETAIL_JITTER)
	if jitter > 0.0:
		shape.rib_amp *= ShipCanonical.rand_range_from(
			ShipCanonical.sub_seed(detail_seed, SEED_RIB_JITTER), 1.0 - jitter, 1.0 + jitter
		)
		shape.scallop_amp *= ShipCanonical.rand_range_from(
			ShipCanonical.sub_seed(detail_seed, SEED_SCALLOP_JITTER), 1.0 - jitter, 1.0 + jitter
		)

	# refresh() sanitises `scale` and derives `bound_radius`, so it must run before both are read.
	shape.refresh()
	# `lipschitz_for()` only knows the scale, so re-tighten the two domain-warp terms against
	# the geometry we now have. Both warps act in the UNSCALED op frame — the scale warp wraps
	# them — so they are sized against the unscaled radius. Conservative on purpose:
	# underestimating tunnels the sphere-tracer.
	var warp_radius: float = shape.unscaled_aabb().end.length()
	var half_h: float = maxf(absf(shape.size.y), SdfOps.MIN_HALF_H)
	var warp_lip: float = maxf(
		1.0 + absf(deg_to_rad(twist_v)) * warp_radius,
		1.0 + absf(taper_v) * warp_radius / (2.0 * half_h)
	)
	# The shear's cost is exact and multiplicative with the other warps', so it multiplies rather
	# than competing in the max: a sheared AND twisted part is harder to trace than either alone.
	shape.lipschitz = clampf(
		maxf(SdfOps.lipschitz_for(taper_v, twist_v, shape.scale), warp_lip)
		* SdfOps.shear_lipschitz(shape.shear.x, shape.shear.y),
		1.0,
		SdfOps.MAX_LIPSCHITZ
	)
	return shape


## Resolves the two CYLINDER end params into unscaled metres on the shape (ADR 0005).
##
## Both are authored as ratios of the family's own `base_size`, so retuning a family's size does
## not silently turn its cones back into cylinders. A family that does not enable the `ends` op,
## and every non-cylinder base, leaves `radius_b` negative — `ResolvedShape.refresh()` reads that
## as "match size.x", i.e. a true cylinder, so nothing that predates this op changes shape.
static func _apply_end_params(
	shape: ResolvedShape, params: Dictionary, fam_ops: PackedStringArray, defs: Dictionary
) -> void:
	if shape.base != ResolvedShape.Base.CYLINDER or not _op_enabled(fam_ops, OP_ENDS):
		return
	var r1: float = absf(shape.size.x)
	var ratio_b: float = _param_float(
		params, KEY_END_RADIUS, _num(defs.get(KEY_END_RADIUS), 1.0)
	)
	var ratio_e: float = _param_float(params, KEY_END_ROUND, _num(defs.get(KEY_END_ROUND), 0.0))
	shape.radius_b = maxf(r1 * ratio_b, 0.0)
	# Measured against the WIDER end: at ratio 1 every shape in this family converges on the
	# capsule, and a cone - whose narrow end is a point - can still be given a rounded nose.
	# refresh() clamps against the half-height as well.
	shape.end_round = maxf(r1, shape.radius_b) * clampf(ratio_e, 0.0, 1.0)


## How ornamented this part is, in `[1.0, 2.0]`: the mean normalised position of its params
## within the FAMILY's authored ranges, plus one. Feeds the cost model
## (`family_base_cost * manufacturer_multiplier * size_factor * param_complexity`).
static func param_complexity(data: ShipData, family_id: String, params: Dictionary) -> float:
	var fam: Dictionary = _family(data, family_id)
	if fam.is_empty():
		return 1.0
	var raw: Dictionary = _params_section(fam)
	if raw.is_empty():
		return 1.0
	var total: float = 0.0
	var n: int = 0
	for key: String in raw:
		var r: Dictionary = _norm_range(raw[key], key)
		var lo: float = _num(r.get("min"), 0.0)
		var hi: float = _num(r.get("max"), lo)
		if hi - lo <= 0.0:
			continue  # a pinned param is not a choice, so it does not count toward the mean
		# Distance from the param's NEUTRAL value over the longer half-span. For every
		# amplitude-shaped param neutral IS the minimum and this is arithmetically identical to
		# the (v - lo) / (hi - lo) it replaced, so no existing part's cost moves. It differs only
		# for `end_radius`, where neutral sits mid-range and a cone and a bell-mouth are equally
		# far from a plain cylinder — which is the honest reading of "how shaped is this part".
		var canonical: String = _canonical_key(key)
		var neutral: float = clampf(_neutral_of(canonical), lo, hi)
		var reach: float = maxf(hi - neutral, neutral - lo)
		if reach <= 0.0:
			continue
		n += 1
		var v: float = _param_float(params, canonical, _num(r.get("default"), lo))
		total += clampf(absf(v - neutral) / reach, 0.0, 1.0)
	if n == 0:
		return 1.0
	return 1.0 + total / float(n)


# --- data pack readers -------------------------------------------------------------------


static func _family(data: ShipData, family_id: String) -> Dictionary:
	if data == null:
		return {}
	return _dict_of(data.families.get(family_id))


static func _manufacturer(data: ShipData, manufacturer_id: String) -> Dictionary:
	if data == null:
		return {}
	return _dict_of(data.manufacturers.get(manufacturer_id))


## The family's parameter-range section, under whichever key the pack uses.
static func _params_section(fam: Dictionary) -> Dictionary:
	if fam.has("params"):
		return _dict_of(fam.get("params"))
	if fam.has("param_ranges"):
		return _dict_of(fam.get("param_ranges"))
	if fam.has("ranges"):
		return _dict_of(fam.get("ranges"))
	return {}


## A manufacturer's narrowing section, under whichever key the pack uses.
static func _ranges_section(mfr: Dictionary) -> Dictionary:
	if mfr.has("ranges"):
		return _dict_of(mfr.get("ranges"))
	if mfr.has("params"):
		return _dict_of(mfr.get("params"))
	if mfr.has("param_ranges"):
		return _dict_of(mfr.get("param_ranges"))
	return {}


## The manufacturer's per-family override entry, if it authors one. Supports both
## `per_family: { family_id: {...} }` and a dictionary-shaped `families` map.
static func _mfr_family_entry(mfr: Dictionary, family_id: String) -> Dictionary:
	var per: Dictionary = _dict_of(mfr.get("per_family"))
	if per.has(family_id):
		return _dict_of(per.get(family_id))
	var fams: Variant = mfr.get("families")
	if fams is Dictionary:
		var fd: Dictionary = fams
		if fd.has(family_id):
			return _dict_of(fd.get(family_id))
	return {}


## Ops the family supports. Empty means "the family did not say", i.e. all ops are available.
static func _family_ops(fam: Dictionary) -> PackedStringArray:
	return _ops_list(fam.get("ops"))


## Ops the manufacturer switches off, globally and for this family.
static func _ops_disabled(mfr: Dictionary, family_id: String) -> PackedStringArray:
	var out: PackedStringArray = _ops_list(mfr.get("ops_disabled"))
	var entry: Dictionary = _mfr_family_entry(mfr, family_id)
	for op: String in _ops_list(entry.get("ops_disabled")):
		if not out.has(op):
			out.append(op)
	return out


## Reads an authored op-name array, canonicalised and de-duplicated.
static func _ops_list(v: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var arr: Array = []
	if v is Array:
		arr = v
	elif v is PackedStringArray:
		var packed: PackedStringArray = v
		for s: String in packed:
			arr.append(s)
	for item: Variant in arr:
		if not (item is String):
			continue
		var op: String = _canonical_op(String(item))
		if not op.is_empty() and not out.has(op):
			out.append(op)
	return out


static func _op_enabled(fam_ops: PackedStringArray, op: String) -> bool:
	return fam_ops.is_empty() or fam_ops.has(op)


static func _base_enum(fam: Dictionary) -> int:
	var raw: Variant = fam.get("base")
	if not (raw is String):
		raw = fam.get("primitive")
	if not (raw is String):
		raw = fam.get("base_primitive")
	if not (raw is String):
		return ResolvedShape.Base.BOX
	match String(raw).to_lower():
		"sphere", "ellipsoid", "ball":
			return ResolvedShape.Base.SPHERE
		"cylinder", "tube", "rod":
			return ResolvedShape.Base.CYLINDER
		"cone", "nose":
			return ResolvedShape.Base.CONE
		"capsule", "pill":
			return ResolvedShape.Base.CAPSULE
		"torus", "ring":
			return ResolvedShape.Base.TORUS
	return ResolvedShape.Base.BOX


## The family's unscaled dimensions, in the `ResolvedShape.size` layout for its base.
static func _base_size(fam: Dictionary) -> Vector3:
	var raw: Variant = fam.get("base_size")
	if raw == null:
		raw = fam.get("size")
	if raw == null:
		raw = fam.get("dimensions")
	if raw is Array:
		var a: Array = raw
		var x: float = 1.0
		if a.size() > 0:
			x = _num(a[0], 1.0)
		var y: float = x
		if a.size() > 1:
			y = _num(a[1], x)
		var z: float = x
		if a.size() > 2:
			z = _num(a[2], x)
		return Vector3(x, y, z)
	if raw is float or raw is int:
		var v: float = _num(raw, 1.0)
		return Vector3(v, v, v)
	return Vector3.ONE


## A torus's origin is outside its solid, so ShipAttach must trace it inward from the bounding
## sphere instead of outward from the origin (SPEC section 3). Families may state this
## explicitly; otherwise it follows from the base.
static func _origin_inside(fam: Dictionary, base: int) -> bool:
	if fam.has("origin_inside"):
		return _bool_of(fam.get("origin_inside"), true)
	return base != ResolvedShape.Base.TORUS


# --- range algebra -----------------------------------------------------------------------


## Normalises one authored range spec. Accepts `{min,max,default,step,int}`, `[min,max]`,
## `[min,max,default]` and a bare number (a pinned value).
##
## `step` is carried through for the inspector to snap against; it is NOT read as a type hint —
## a pack authors `step: 1.0` on a float param (torus twist_deg) and rounding that to an int
## would both fight the player and churn the canonical hash. Only the canonical rib count and
## an explicit `int: true` make a param integral.
static func _norm_range(spec: Variant, key: String) -> Dictionary:
	var lo: float = 0.0
	var hi: float = 0.0
	var def: float = 0.0
	var step: float = 0.0
	var has_default: bool = false
	var is_int: bool = _canonical_key(key) == KEY_RIBS
	if spec is Dictionary:
		var d: Dictionary = spec
		lo = _num(d.get("min", d.get("lo")), 0.0)
		hi = _num(d.get("max", d.get("hi")), lo)
		if d.has("default"):
			def = _num(d.get("default"), lo)
			has_default = true
		step = maxf(_num(d.get("step"), 0.0), 0.0)
		if _bool_of(d.get("int"), false):
			is_int = true
	elif spec is Array:
		var a: Array = spec
		if a.size() > 0:
			lo = _num(a[0], 0.0)
		hi = lo
		if a.size() > 1:
			hi = _num(a[1], lo)
		if a.size() > 2:
			def = _num(a[2], lo)
			has_default = true
	elif spec is float or spec is int:
		lo = _num(spec, 0.0)
		hi = lo
		def = lo
		has_default = true
	if hi < lo:
		var t: float = lo
		lo = hi
		hi = t
	if not has_default:
		def = clampf(0.0, lo, hi)
	return {
		"min": lo,
		"max": hi,
		"default": clampf(def, lo, hi),
		"is_int": is_int,
		"step": step,
	}


## Intersects a family range with one manufacturer narrowing spec. A manufacturer may only
## move the bounds inward; a spec that names just one bound leaves the other alone.
static func _narrow(base_range: Dictionary, spec: Variant, key: String) -> Dictionary:
	var orig_lo: float = _num(base_range.get("min"), 0.0)
	var orig_hi: float = _num(base_range.get("max"), orig_lo)
	var lo: float = orig_lo
	var hi: float = orig_hi
	var def: float = _num(base_range.get("default"), orig_lo)
	var is_int: bool = _bool_of(base_range.get("is_int"), false)
	var step: float = _num(base_range.get("step"), 0.0)
	if spec is Dictionary:
		var d: Dictionary = spec
		if d.has("min") or d.has("lo"):
			lo = maxf(lo, _num(d.get("min", d.get("lo")), lo))
		if d.has("max") or d.has("hi"):
			hi = minf(hi, _num(d.get("max", d.get("hi")), hi))
		if d.has("default"):
			def = _num(d.get("default"), def)
		if d.has("step"):
			step = maxf(_num(d.get("step"), step), 0.0)
		if _bool_of(d.get("int"), false):
			is_int = true
	elif spec is Array:
		var a: Array = spec
		if a.size() > 0:
			lo = maxf(lo, _num(a[0], lo))
		if a.size() > 1:
			hi = minf(hi, _num(a[1], hi))
		if a.size() > 2:
			def = _num(a[2], def)
	elif spec is float or spec is int:
		var pinned: float = clampf(_num(spec, def), orig_lo, orig_hi)
		lo = pinned
		hi = pinned
		def = pinned
	if hi < lo:
		var collapsed: float = clampf(lo, orig_lo, orig_hi)
		lo = collapsed
		hi = collapsed
	if not is_int and _canonical_key(key) == KEY_RIBS:
		is_int = true
	return {
		"min": lo,
		"max": hi,
		"default": clampf(def, lo, hi),
		"is_int": is_int,
		"step": step,
	}


## Collapses a range onto the param's NEUTRAL value — how a disabled op is expressed.
##
## Neutral is zero for every amplitude-shaped param (no taper, no twist, no ribs), which is why
## this was `_pin_zero`. It is 1.0 for `end_radius`, where zero is not "off" but a point-tipped
## cone: pinning that to zero would turn every cylinder from a manufacturer who does not sell
## end shaping into a spike. See `_neutral_of()`.
static func _pin_neutral(r: Dictionary, canonical: String) -> Dictionary:
	var lo: float = _num(r.get("min"), 0.0)
	var hi: float = _num(r.get("max"), lo)
	var v: float = clampf(_neutral_of(canonical), lo, hi)
	return {
		"min": v,
		"max": v,
		"default": v,
		"is_int": _bool_of(r.get("is_int"), false),
		"step": _num(r.get("step"), 0.0),
	}


## The value at which a param contributes NOTHING — no ornament, no deviation from the family's
## plain form. Zero for every amplitude, and 1.0 for `end_radius`, whose plain form is a cylinder
## with two equal ends.
##
## Used in two places that must agree: pinning a disabled op (`_pin_neutral`) and scoring
## ornamentation (`param_complexity`). They disagreed once, over rib phase, and the result was a
## part that cost more for detail it was not drawing.
static func _neutral_of(canonical: String) -> float:
	if canonical == KEY_END_RADIUS:
		return 1.0
	return 0.0


## Every family default, re-keyed to canonical names, so `resolve()` can fall back to the
## authored value when a doc simply does not carry that key.
static func _canonical_defaults(fam: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = _params_section(fam)
	for key: String in raw:
		var r: Dictionary = _norm_range(raw[key], key)
		out[_canonical_key(key)] = _num(r.get("default"), 0.0)
	return out


# --- naming ------------------------------------------------------------------------------


## Canonical name for a parameter key, so packs may use a synonym and still resolve.
static func _canonical_key(key: String) -> String:
	match key:
		"taper", "taper_amount":
			return KEY_TAPER
		"twist", "twist_deg", "twist_per_m":
			return KEY_TWIST
		"bevel", "round", "round_r", "inflate", "fillet":
			return KEY_BEVEL
		"ribs", "rib_count", "rib_rings":
			return KEY_RIBS
		"rib_amp", "rib_amplitude", "rib_depth":
			return KEY_RIB_AMP
		"scallop", "scallop_amp", "scallop_amplitude", "scallop_depth":
			return KEY_SCALLOP
		"scallop_freq", "scallop_frequency":
			return KEY_SCALLOP_FREQ
		"end_radius", "radius_b", "top_radius", "end_ratio":
			return KEY_END_RADIUS
		"end_round", "cap_round", "end_fillet", "end_bevel":
			return KEY_END_ROUND
		"skew_x", "shear_x", "lean_x":
			return KEY_SKEW_X
		"skew_z", "shear_z", "lean_z":
			return KEY_SKEW_Z
	return key


## Every key that could carry this canonical parameter, most-canonical first.
static func _aliases_for(canonical: String) -> PackedStringArray:
	match canonical:
		KEY_TAPER:
			return PackedStringArray(["taper", "taper_amount"])
		KEY_TWIST:
			return PackedStringArray(["twist", "twist_deg", "twist_per_m"])
		KEY_BEVEL:
			return PackedStringArray(["bevel", "round", "round_r", "inflate", "fillet"])
		KEY_RIBS:
			return PackedStringArray(["ribs", "rib_count", "rib_rings"])
		KEY_RIB_AMP:
			return PackedStringArray(["rib_amp", "rib_amplitude", "rib_depth"])
		KEY_SCALLOP:
			return PackedStringArray(
				["scallop", "scallop_amp", "scallop_amplitude", "scallop_depth"]
			)
		KEY_SCALLOP_FREQ:
			return PackedStringArray(["scallop_freq", "scallop_frequency"])
		KEY_END_RADIUS:
			return PackedStringArray(["end_radius", "radius_b", "top_radius", "end_ratio"])
		KEY_END_ROUND:
			return PackedStringArray(["end_round", "cap_round", "end_fillet", "end_bevel"])
		KEY_SKEW_X:
			return PackedStringArray(["skew_x", "shear_x", "lean_x"])
		KEY_SKEW_Z:
			return PackedStringArray(["skew_z", "shear_z", "lean_z"])
	return PackedStringArray([canonical])


## Canonical name for an op, as used in `ops` / `ops_disabled`.
static func _canonical_op(op: String) -> String:
	match op.to_lower():
		"taper":
			return OP_TAPER
		"twist":
			return OP_TWIST
		"round", "bevel", "inflate", "fillet":
			return OP_ROUND
		"ribs", "rib", "ribbing":
			return OP_RIBS
		"scallop", "scallops", "scalloping":
			return OP_SCALLOP
		"ends", "end", "endcaps", "end_caps":
			return OP_ENDS
		"skew", "shear", "lean":
			return OP_SKEW
	return op.to_lower()


## The op a canonical parameter belongs to, or "" when it is not an op parameter.
static func _op_for_param(canonical: String) -> String:
	match canonical:
		KEY_TAPER:
			return OP_TAPER
		KEY_TWIST:
			return OP_TWIST
		KEY_BEVEL:
			return OP_ROUND
		KEY_RIBS, KEY_RIB_AMP:
			return OP_RIBS
		KEY_SCALLOP, KEY_SCALLOP_FREQ:
			return OP_SCALLOP
		KEY_END_RADIUS, KEY_END_ROUND:
			return OP_ENDS
		KEY_SKEW_X, KEY_SKEW_Z:
			return OP_SKEW
	return ""


# --- geometry ----------------------------------------------------------------------------


## What an unknown family resolves to: a plain unit box, so a broken pack shows up as an
## obvious placeholder instead of a crash or an invisible part. `ShipValidate` reports the real
## cause.
static func _fallback_shape(scale: Vector3) -> ResolvedShape:
	var shape: ResolvedShape = ResolvedShape.new()
	shape.base = ResolvedShape.Base.BOX
	shape.size = Vector3.ONE
	shape.scale = scale
	shape.origin_inside = true
	shape.refresh()
	shape.lipschitz = SdfOps.lipschitz_for(0.0, 0.0, shape.scale)
	return shape


# --- variant readers ---------------------------------------------------------------------


static func _param_float(params: Dictionary, canonical: String, fallback: float) -> float:
	var names: PackedStringArray = _aliases_for(canonical)
	for candidate: String in names:
		if params.has(candidate):
			return _num(params.get(candidate), fallback)
	return fallback


static func _param_int(params: Dictionary, canonical: String, fallback: int) -> int:
	var names: PackedStringArray = _aliases_for(canonical)
	for candidate: String in names:
		if params.has(candidate):
			return _int_of(params.get(candidate), fallback)
	return fallback


static func _dict_of(v: Variant) -> Dictionary:
	if v is Dictionary:
		return v
	return {}


static func _num(v: Variant, fallback: float) -> float:
	if v is float or v is int:
		return float(v)
	return fallback


static func _int_of(v: Variant, fallback: int) -> int:
	if v is int:
		return int(v)
	if v is float:
		return int(roundf(float(v)))
	return fallback


static func _bool_of(v: Variant, fallback: bool) -> bool:
	if v is bool:
		return bool(v)
	if v is int or v is float:
		return float(v) != 0.0
	return fallback
