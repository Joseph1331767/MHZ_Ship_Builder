class_name ShipComplexity
extends RefCounted

## The complexity budget — API_CONTRACT_SPORE section 5, SPORE_CLONE_SPEC section 5.
##
## This is the gate Spore actually enforces. Research found the UFO editor has exactly six hard
## walls, and this is the one players meet constantly: "Adding parts will increase the complexity of
## the creation until it reaches the maximum amount, at which point nothing else can be added.
## [b]Parts will be coloured red when they cannot be added.[/b]" (SporeWiki, Complexity Meter.)
##
## [b]Cost is per-part-type and weighted, not a part count.[/b] In the creature editor a spine
## segment costs 1, a limb segment 1.5, most details 1, and the priciest part in the game 11. Our
## per-family costs live in `data/shapes/families.json` under `"complexity"`.
##
## [b]A symmetric part costs DOUBLE.[/b] Verified: breaking symmetry gets the feature "for half of
## the complexity and DNA cost", and players deliberately exploit this to fit bigger builds. That is
## a real, documented trade-off and MUST remain exploitable — do not "fix" it. The test suite
## asserts the doubling on purpose so nobody quietly removes it.
##
## Why parts and not polygons: Hecker's account is that Spore avoids polygon-level editing to keep
## the creation "recipe" small enough to transmit through Sporepedia — Wright quoted a 5000:1 ratio,
## ~1 KB of recipe to ~5 MB of content. The budget is a transmission and load-time constraint
## wearing a gameplay costume.

## Charged when a family omits `complexity`. Deliberately non-zero: a part that costs nothing is a
## part that can be spammed without ever reddening the palette, which silently disables the gate.
const DEFAULT_COST: float = 1.0

## Multiplier applied to a part that currently generates a mirrored twin.
const SYMMETRY_MULTIPLIER: float = 2.0


## The whole budget in one call.
## Returns [code]{ "used": float, "cap": float, "per_part": Dictionary }[/code] where `per_part`
## maps stored part id -> its charged cost (already including the symmetry doubling).
##
## Only STORED parts are billed. Generated twins are derived, never billed separately — the
## doubling on the source is what pays for them.
static func compute(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary:
	var per_part: Dictionary = {}
	var used: float = 0.0
	if doc != null and data != null and cfg != null:
		for id: String in doc.part_order():
			var cost: float = cost_of(doc, id, data, cfg)
			per_part[id] = cost
			used += cost
	return {
		"used": used,
		"cap": _cap(cfg),
		"per_part": per_part,
	}


## Charged cost of one placed part, including the symmetry doubling.
static func cost_of(doc: ShipDoc, part_id: String, data: ShipData, cfg: ShipConfig) -> float:
	if doc == null or data == null:
		return 0.0
	var part: ShipPart = _part(doc, part_id)
	if part == null:
		return 0.0
	var base: float = base_cost(data, part.family)
	if _is_symmetric(doc, part_id, cfg):
		base *= SYMMETRY_MULTIPLIER
	return base


## Cost of adding a NEW part of this family, before it exists. This is what the palette's red-out
## test asks, so it must agree with what [method cost_of] will report once the part is placed.
static func cost_of_new(data: ShipData, family_id: String, symmetric: bool) -> float:
	var base: float = base_cost(data, family_id)
	if symmetric:
		base *= SYMMETRY_MULTIPLIER
	return base


## Unweighted per-family cost from the data pack.
static func base_cost(data: ShipData, family_id: String) -> float:
	if data == null or not data.families.has(family_id):
		return DEFAULT_COST
	var entry_v: Variant = data.families[family_id]
	if not (entry_v is Dictionary):
		return DEFAULT_COST
	var entry: Dictionary = entry_v
	var raw: Variant = entry.get("complexity", null)
	if raw is float:
		var f: float = raw
		return maxf(f, 0.0)
	if raw is int:
		var i: int = raw
		return maxf(float(i), 0.0)
	return DEFAULT_COST


## Would adding this part fit inside the cap? The palette reddens entries where this is false.
static func can_afford(
	doc: ShipDoc, data: ShipData, cfg: ShipConfig, family_id: String, symmetric: bool
) -> bool:
	var cap: float = _cap(cfg)
	if not is_finite(cap) or cap <= 0.0:
		return true  # unbounded, same convention ShipBudgets uses
	var state: Dictionary = compute(doc, data, cfg)
	var used: float = float(state["used"])
	return used + cost_of_new(data, family_id, symmetric) <= cap


## Fraction of the cap in use. 1.0 is exactly full; an unbounded cap reads 0.0 so a gauge for it
## never shows a misleading fill.
static func usage(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> float:
	var cap: float = _cap(cfg)
	if not is_finite(cap) or cap <= 0.0:
		return 0.0
	var state: Dictionary = compute(doc, data, cfg)
	return float(state["used"]) / cap


static func _cap(cfg: ShipConfig) -> float:
	if cfg == null:
		return INF
	return cfg.max_complexity


## Does this part currently pay the symmetry surcharge?
##
## Deliberately does NOT resolve transforms: that would make the palette's per-keystroke red-out
## test pay for a full attach resolve. A part is treated as symmetric when it is not effectively
## asymmetric and the document mirrors at all. The on-plane exemption that
## [method ShipSymmetry.generates_twin] applies needs a transform, so it is not applied here —
## the only part that reliably sits on the plane is the root, so this over-bills at most one part.
## Stated plainly rather than hidden: the readout is a budget, not a measurement.
static func _is_symmetric(doc: ShipDoc, part_id: String, cfg: ShipConfig) -> bool:
	if doc == null or cfg == null:
		return false
	if ShipSymmetry.plane_axis(doc.symmetry_plane) < 0:
		return false
	return not ShipSymmetry.is_effectively_asymmetric(doc, part_id)


static func _part(doc: ShipDoc, part_id: String) -> ShipPart:
	if doc == null or not doc.parts.has(part_id):
		return null
	var v: Variant = doc.parts[part_id]
	if v is ShipPart:
		return v
	return null
