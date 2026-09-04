class_name ShipGate
extends RefCounted

## The refusal gate — API_CONTRACT_SPORE section 6.
##
## This project runs TWO hard-blocking gates at once: Spore's complexity budget, and this project's
## own physical budgets (bbox / internal volume / weight / cost). That is a deliberate divergence
## from Spore, which has no physical budgets at all — its ship parts are entirely cosmetic
## (SPORE_CLONE_SPEC section 0).
##
## [b]The whole mitigation for having two gates is that a refusal always names its cause.[/b] A
## player refused by an invisible rule will read it as the editor being broken; a player told
## "WEIGHT 5.01Mkg / 5.00Mkg - OVER BUDGET" can act. So [member message] is player-facing, states
## the failing quantity and its cap, and every caller is expected to surface it verbatim rather
## than substituting a generic "cannot place part".
##
## Every check returns the same shape:
## [codeblock]
## { "ok": bool, "reason": int (Reason), "message": String }
## [/codeblock]
## `message` is "" when ok.

enum Reason {
	OK,
	COMPLEXITY,
	BUDGET_BBOX,
	BUDGET_VOLUME,
	BUDGET_WEIGHT,
	BUDGET_COST,
	MIN_PARTS,
}


## Can a part of this family be added right now?
##
## Runs complexity FIRST and returns on failure, because complexity is cheap (no grid sampling) and
## is also the gate Spore itself enforces — when both would refuse, the Spore-faithful reason is the
## more useful one to show. The physical budgets need a metrics pass and are checked second.
##
## [param metrics] may be null, in which case only the complexity gate runs. Callers on a hot path
## (the palette's per-keystroke red-out) should pass null and re-check with metrics on an
## idle timer.
static func check_add(
	doc: ShipDoc,
	data: ShipData,
	cfg: ShipConfig,
	family_id: String,
	symmetric: bool,
	metrics: ShipMetrics = null
) -> Dictionary:
	if doc == null or data == null or cfg == null:
		return _ok()

	if not ShipComplexity.can_afford(doc, data, cfg, family_id, symmetric):
		var state: Dictionary = ShipComplexity.compute(doc, data, cfg)
		var used: float = float(state["used"])
		var cap: float = float(state["cap"])
		var add: float = ShipComplexity.cost_of_new(data, family_id, symmetric)
		var hint: String = ""
		if symmetric:
			hint = " - REMOVE A PART OR BREAK SYMMETRY"
		else:
			hint = " - REMOVE A PART"
		return _refuse(
			Reason.COMPLEXITY,
			(
				"COMPLEXITY %s + %s / %s%s"
				% [_num(used), _num(add), _num(cap), hint]
			)
		)

	if metrics != null:
		return check_metrics(metrics, cfg)
	return _ok()


## Is the document currently legal? Same gates, no prospective part.
static func check_doc(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, metrics: ShipMetrics = null
) -> Dictionary:
	if doc == null or data == null or cfg == null:
		return _ok()

	var state: Dictionary = ShipComplexity.compute(doc, data, cfg)
	var used: float = float(state["used"])
	var cap: float = float(state["cap"])
	if is_finite(cap) and cap > 0.0 and used > cap:
		return _refuse(
			Reason.COMPLEXITY, "COMPLEXITY %s / %s - OVER BUDGET" % [_num(used), _num(cap)]
		)

	if metrics != null:
		return check_metrics(metrics, cfg)
	return _ok()


## Can this document be saved? Adds Spore's 3-part minimum on top of [method check_doc].
##
## The minimum counts STORED records, not generated twins: a twin is derived from its source, so a
## "two parts plus symmetry" ship is a two-part ship on disk and is refused, which matches Spore
## requiring three real parts.
static func check_save(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, metrics: ShipMetrics = null
) -> Dictionary:
	if doc == null or cfg == null:
		return _ok()
	var count: int = doc.parts.size()
	if count < cfg.min_parts_to_save:
		return _refuse(
			Reason.MIN_PARTS,
			"NEED %d PARTS TO SAVE - THIS SHIP HAS %d" % [cfg.min_parts_to_save, count]
		)
	return check_doc(doc, data, cfg, metrics)


## The four physical budgets, in [member ShipConfig.budget_priority] order so the reported reason
## matches the one the gauge strip highlights.
static func check_metrics(metrics: ShipMetrics, cfg: ShipConfig) -> Dictionary:
	if metrics == null or cfg == null:
		return _ok()
	var top: int = ShipBudgets.top_violation(metrics, cfg)
	if top < 0:
		return _ok()

	match top:
		ShipBudgets.Budget.BBOX:
			var size: Vector3 = metrics.bbox.size.abs()
			var axis: int = _worst_axis(size, cfg.max_bbox_m)
			return _refuse(
				Reason.BUDGET_BBOX,
				(
					"BBOX %s %s / %s M - OVER BUDGET"
					% [_axis_name(axis), _num(size[axis]), _num(cfg.max_bbox_m[axis])]
				)
			)
		ShipBudgets.Budget.VOLUME:
			return _refuse(
				Reason.BUDGET_VOLUME,
				(
					"VOLUME %s / %s M3 - OVER BUDGET"
					% [_num(metrics.internal_volume_m3), _num(cfg.max_internal_volume_m3)]
				)
			)
		ShipBudgets.Budget.WEIGHT:
			return _refuse(
				Reason.BUDGET_WEIGHT,
				(
					"WEIGHT %s / %s KG - OVER BUDGET"
					% [_num(metrics.weight_kg), _num(cfg.max_weight_kg)]
				)
			)
		ShipBudgets.Budget.COST:
			return _refuse(
				Reason.BUDGET_COST,
				"COST %s / %s - OVER BUDGET" % [_num(metrics.cost), _num(cfg.max_cost)]
			)
	return _ok()


## Short label for a reason, for logs and reports.
static func reason_key(reason: int) -> String:
	match reason:
		Reason.COMPLEXITY:
			return "complexity"
		Reason.BUDGET_BBOX:
			return "bbox"
		Reason.BUDGET_VOLUME:
			return "volume"
		Reason.BUDGET_WEIGHT:
			return "weight"
		Reason.BUDGET_COST:
			return "cost"
		Reason.MIN_PARTS:
			return "min_parts"
	return "ok"


static func _ok() -> Dictionary:
	return {"ok": true, "reason": Reason.OK, "message": ""}


static func _refuse(reason: int, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message}


## Axis furthest over its own cap. Per-axis, not diagonal (SPEC section 8).
static func _worst_axis(size: Vector3, cap: Vector3) -> int:
	var worst: int = 0
	var worst_ratio: float = -1.0
	for i: int in 3:
		var c: float = cap[i]
		if not is_finite(c) or c <= 0.0:
			continue
		var ratio: float = size[i] / c
		if ratio > worst_ratio:
			worst_ratio = ratio
			worst = i
	return worst


static func _axis_name(axis: int) -> String:
	match axis:
		0:
			return "X"
		1:
			return "Y"
		2:
			return "Z"
	return "?"


## Compact human number. Large magnitudes get a k/M suffix so a refusal line stays readable at the
## status bar's width instead of running to nine digits.
static func _num(v: float) -> String:
	if not is_finite(v):
		return "INF"
	var a: float = absf(v)
	if a >= 1.0e6:
		return "%.2fM" % (v / 1.0e6)
	if a >= 1.0e4:
		return "%.1fk" % (v / 1.0e3)
	if a >= 100.0:
		return "%.0f" % v
	return "%.2f" % v
