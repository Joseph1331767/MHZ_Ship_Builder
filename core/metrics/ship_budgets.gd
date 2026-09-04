class_name ShipBudgets
extends RefCounted

# The four budgets — SPEC section 8, API_CONTRACT section 16. Static only; pure data.
#
# usage() returns Budget -> float where 1.0 means EXACTLY AT THE CAP. Above 1.0 is a
# violation; at 1.0 is legal. Gauges read this straight (clamp for display, do not clamp
# here — the caller wants to know it is at 180%, not at 100%).
#
# BBOX IS PER AXIS, NOT DIAGONAL (SPEC section 8). A 200 m x 20 m hull is legal where a 78 m
# cube is not, so bbox usage is the max over the three axes of size.axis / max_bbox_m.axis.
# Comparing lengths, or diagonals, would silently allow the cube.
#
# AN UNBOUNDED CAP READS AS ZERO USAGE. `max_cost` defaults to infinite in Phase 1 (SPEC
# section 8: displayed and gauged, never blocking), and a cap of INF, NAN or <= 0 all mean
# the same thing here: no cap. They yield 0.0 — never a division by zero, never a NaN, never
# a gauge stuck at infinity. This matters because a NaN would compare false against every
# threshold and quietly disable the enforcement it was supposed to drive.
#
# ENFORCEMENT (the caller's job, stated here so it is not reinvented): a hard block on edits
# that INCREASE usage, with three exemptions — loading, deleting and undo are never refused.
# Without those exemptions, lowering a lever makes every ship that was legal yesterday
# unopenable. Over-budget-on-load is a visible violation state, not a fatal one.

enum Budget { BBOX, VOLUME, WEIGHT, COST }

## Slack on the "over the cap" test. Grid-derived metrics carry error orders of magnitude
## larger than this; it exists purely so a value that lands exactly on the cap through float
## arithmetic does not read as a violation.
const OVER_EPSILON: float = 0.000001

const KEY_BBOX: String = "bbox"
const KEY_VOLUME: String = "volume"
const KEY_WEIGHT: String = "weight"
const KEY_COST: String = "cost"


## Budget -> float. 1.0 = exactly at the cap. Always returns all four keys, even for a null
## metrics or config, so a caller can index it without guarding every lookup.
static func usage(m: ShipMetrics, cfg: ShipConfig) -> Dictionary:
	var out: Dictionary = {
		Budget.BBOX: 0.0,
		Budget.VOLUME: 0.0,
		Budget.WEIGHT: 0.0,
		Budget.COST: 0.0,
	}
	if m == null or cfg == null:
		return out
	var size: Vector3 = m.bbox.size.abs()
	var cap: Vector3 = cfg.max_bbox_m
	# Per axis, not diagonal.
	var bbox_use: float = _ratio(size.x, cap.x)
	bbox_use = maxf(bbox_use, _ratio(size.y, cap.y))
	bbox_use = maxf(bbox_use, _ratio(size.z, cap.z))
	out[Budget.BBOX] = bbox_use
	out[Budget.VOLUME] = _ratio(m.internal_volume_m3, cfg.max_internal_volume_m3)
	out[Budget.WEIGHT] = _ratio(m.weight_kg, cfg.max_weight_kg)
	out[Budget.COST] = _ratio(m.cost, cfg.max_cost)
	return out


## Every violated budget, ordered by cfg.budget_priority (anything the priority list omits
## is appended in enum order). violations()[0] is therefore always top_violation().
static func violations(m: ShipMetrics, cfg: ShipConfig) -> Array[int]:
	var out: Array[int] = []
	if m == null or cfg == null:
		return out
	var use: Dictionary = usage(m, cfg)
	for b: int in _priority_order(cfg):
		if _over(use, b):
			out.append(b)
	return out


## The highest-priority violated budget, or -1 when nothing is violated. Priority resolves
## the tie when two budgets max at once (SPEC section 8) and decides which alert palette the
## LUT swaps to.
static func top_violation(m: ShipMetrics, cfg: ShipConfig) -> int:
	if m == null or cfg == null:
		return -1
	var use: Dictionary = usage(m, cfg)
	for b: int in _priority_order(cfg):
		if _over(use, b):
			return b
	return -1


## Budget -> the string used in data/tuning.json's budget_priority and in data/palette.json's
## alert palettes. Returns "" for an unknown value rather than guessing a budget.
static func budget_key(b: int) -> String:
	match b:
		Budget.BBOX:
			return KEY_BBOX
		Budget.VOLUME:
			return KEY_VOLUME
		Budget.WEIGHT:
			return KEY_WEIGHT
		Budget.COST:
			return KEY_COST
	return ""


## Inverse of budget_key(). -1 for an unrecognised key, so a typo in tuning.json is skipped
## rather than silently mapped onto budget 0. (Additive to API_CONTRACT section 16 — the UI
## and the priority walk both need it; no listed signature changed.)
static func budget_from_key(key: String) -> int:
	match key.strip_edges().to_lower():
		KEY_BBOX:
			return Budget.BBOX
		KEY_VOLUME:
			return Budget.VOLUME
		KEY_WEIGHT:
			return Budget.WEIGHT
		KEY_COST:
			return Budget.COST
	return -1


# --- internals ----------------------------------------------------------------------


## cfg.budget_priority resolved to enum values, then every budget it failed to mention
## appended in enum order. A half-written priority list must never make a budget
## unenforceable, so nothing is ever dropped from this walk.
static func _priority_order(cfg: ShipConfig) -> Array[int]:
	var out: Array[int] = []
	for key: String in cfg.budget_priority:
		var b: int = budget_from_key(key)
		if b != -1 and not out.has(b):
			out.append(b)
	for b: int in [Budget.BBOX, Budget.VOLUME, Budget.WEIGHT, Budget.COST]:
		if not out.has(b):
			out.append(b)
	return out


static func _over(use: Dictionary, b: int) -> bool:
	var v: Variant = use.get(b, 0.0)
	var t: int = typeof(v)
	if t != TYPE_FLOAT and t != TYPE_INT:
		return false
	var f: float = v
	if is_nan(f):
		return false
	return f > 1.0 + OVER_EPSILON


## value / cap, with every degenerate case folded to 0.0:
##   cap INF / NAN / <= 0  -> unbounded, no usage to report
##   value NAN             -> upstream bug; 0.0 rather than poisoning the gauge
##   value <= 0            -> nothing built on that axis yet
## A value of +INF against a finite cap deliberately survives as INF: that IS a violation and
## hiding it would be worse than showing a pegged gauge.
static func _ratio(value: float, cap: float) -> float:
	if not is_finite(cap) or cap <= 0.0:
		return 0.0
	if is_nan(value) or value <= 0.0:
		return 0.0
	return value / cap
