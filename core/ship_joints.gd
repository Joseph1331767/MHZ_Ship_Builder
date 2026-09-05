class_name ShipJoints
extends RefCounted

## Joint discovery and validity — SPEC section 7, API_CONTRACT section 21. Static only, no state.
##
## Phase 1 authors joints; it does not build their geometry. Two supports keep the authored data
## from being garbage:
##
##   * discovery — the builder finds overlapping pairs from the SDF and offers them, so the player
##     never has to hunt for pairs by hand;
##   * validity — "do these two cavities actually merge?" is a cheap SDF sample, no meshing. A
##     hatch between parts that merely touch would mean nothing, so it gets flagged.
##
## Both run interactively, so both are deliberately coarse: a grid pass over the SDF, no meshing,
## no per-cell refinement. A feature thinner than one grid cell can be missed; that is the price of
## running this on every edit, and it is a heuristic offered to the player, not a proof.

## Grid resolution per axis for the occupancy pre-pass that brackets each part in space.
const COARSE_STEPS: int = 12

## Grid resolution per axis for the pairwise scan inside two parts' overlapping brackets.
const FINE_STEPS: int = 10

## Bounds on the pairwise resolution when it is derived from a config cell size.
const MIN_PAIR_STEPS: int = 4
const MAX_PAIR_STEPS: int = 14

## Grid resolution per axis for [method solid_pair_state]. Coarse on purpose - the validator runs
## it per joint, per edit (SPEC 7: "a cheap SDF sample, no meshing") - but not so coarse that it
## reports a real connection as absent.
##
## RETIRED(ADR 0015, 2026-09-04): 10. THE THING BEING LOOKED FOR IS A CAVITY, AND A CAVITY SHRINKS
## WITH THE WALL. At the 0.15 m hull the pack used to ship, ten steps found every template joint;
## at 0.20 m it started missing the narrow ones - a neon class tunnel, 0.6 m of cavity inside a 1 m
## bore, meeting a pod eight metres across. The giveaway that it was sampling and not geometry: the
## answer was NOT MONOTONIC in the embed depth, going from eight unmerged joints to none and back
## as the overlap slid between grid lines. Sixteen steps is about four times the samples on a
## region that is small by definition, and it is still a sample rather than a mesh.
const SOLID_SAMPLE_STEPS: int = 16


## Candidate joint pairs, deterministic, one entry per overlapping bracket:
##   [{ "a": String, "b": String, "overlaps": bool, "merges": bool }]
##
## `a` < `b` lexicographically, matching the canonical unordered-pair key SPEC 5.1 uses for the
## `joints` map. `overlaps` means the two solids share space at all; `merges` means their interior
## cavities connect at the configured hull thickness — the difference between a real joint and two
## parts that happen to touch.
##
## Only parts that exist in `doc` are considered, so expanded component sub-parts (which are not
## addressable as joint endpoints) are skipped.
static func discover(doc: ShipDoc, sdf: ShipSdf, cfg: ShipConfig) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if doc == null or sdf == null or cfg == null:
		return out
	var count: int = sdf.part_count()
	if count < 2:
		return out
	var index_of: Dictionary = {}
	for i: int in count:
		index_of[sdf.part_id_at(i)] = i
	var ids: PackedStringArray = PackedStringArray()
	for id: String in ShipAttach.ordered_part_ids(doc):
		if index_of.has(id):
			ids.append(id)
	var bounds: AABB = sdf.aabb()
	var boxes: Dictionary = {}
	for id: String in ids:
		var index: int = index_of[id]
		boxes[id] = part_box(sdf, index, bounds, COARSE_STEPS)
	var thickness: float = maxf(cfg.hull_thickness_m, 0.0)
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			var entry: Dictionary = _pair_entry(
				sdf, cfg, index_of, boxes, ids[i], ids[j], thickness
			)
			if not entry.is_empty():
				out.append(entry)
	return out


## Do the two parts' INTERIOR cavities actually merge, or do the parts merely touch?
##
## True when there is a point inside both parts by more than `thickness` — that is, a point that
## would still be hollow in both after the hull shell is subtracted, which is what makes a joint
## (and any hatch in it) mean something. Both parts are bracketed first so the scan only covers the
## space they share.
static func cavities_merge(sdf: ShipSdf, ia: int, ib: int, thickness: float) -> bool:
	if sdf == null or ia == ib:
		return false
	var count: int = sdf.part_count()
	if ia < 0 or ib < 0 or ia >= count or ib >= count:
		return false
	var bounds: AABB = sdf.aabb()
	var box_a: AABB = part_box(sdf, ia, bounds, COARSE_STEPS)
	var box_b: AABB = part_box(sdf, ib, bounds, COARSE_STEPS)
	if not box_a.intersects(box_b):
		return false
	var state: Dictionary = pair_state(
		sdf, ia, ib, box_a.intersection(box_b), thickness, FINE_STEPS
	)
	var merges: bool = state["merges"]
	return merges


## The bracket a part occupies: the AABB of the grid samples that landed inside it, grown by one
## cell. An empty AABB means the coarse grid never found the part (it is smaller than a cell).
static func part_box(sdf: ShipSdf, index: int, bounds: AABB, steps: int) -> AABB:
	var n: int = maxi(steps, 2)
	var cell: Vector3 = bounds.size / float(n)
	var box: AABB = AABB()
	var found: bool = false
	for ix: int in n:
		for iy: int in n:
			for iz: int in n:
				var p: Vector3 = _cell_centre(bounds, cell, ix, iy, iz)
				if sdf.sample_part(index, p) >= 0.0:
					continue
				if found:
					box = box.expand(p)
				else:
					box = AABB(p, Vector3.ZERO)
					found = true
	if not found:
		return AABB()
	return box.grow(maxf(maxf(cell.x, cell.y), cell.z))


## Scan `region` for the two facts a joint is judged on:
##   { "overlaps": bool, "merges": bool }
static func pair_state(
	sdf: ShipSdf, ia: int, ib: int, region: AABB, thickness: float, steps: int
) -> Dictionary:
	var n: int = maxi(steps, 2)
	var cell: Vector3 = region.size / float(n)
	var iso: float = -absf(thickness)
	var overlaps: bool = false
	for ix: int in n:
		for iy: int in n:
			for iz: int in n:
				var p: Vector3 = _cell_centre(region, cell, ix, iy, iz)
				var da: float = sdf.sample_part(ia, p)
				if da >= 0.0:
					continue
				var db: float = sdf.sample_part(ib, p)
				if db >= 0.0:
					continue
				overlaps = true
				if da < iso and db < iso:
					return {"overlaps": true, "merges": true}
	return {"overlaps": overlaps, "merges": false}


## Do two PLACED SOLIDS share space, and do their interiors merge at `thickness`?
##   { "overlaps": bool, "merges": bool }
##
## The shape-level twin of [method pair_state]: no [ShipSdf] and no part index, just two resolved
## shapes and where they stand, so anything holding an attach pass can ask "are these two
## connected?" - the validator for every joint, the tree panel before it opens a hatch. `merges`
## is the same fact as everywhere else in this file: a point inside both by more than `thickness`.
##
## ShapeGen bakes a part's scale into its ResolvedShape, so a part's world transform is rigid and
## `xform.affine_inverse() * p` is an exact shape-local point - no scale correction needed here.
static func solid_pair_state(
	shape_a: ResolvedShape,
	xform_a: Transform3D,
	shape_b: ResolvedShape,
	xform_b: Transform3D,
	thickness: float
) -> Dictionary:
	var box_a: AABB = xform_a * shape_a.local_aabb()
	var box_b: AABB = xform_b * shape_b.local_aabb()
	if not box_a.intersects(box_b):
		return {"overlaps": false, "merges": false}
	var region: AABB = box_a.intersection(box_b)
	var inv_a: Transform3D = xform_a.affine_inverse()
	var inv_b: Transform3D = xform_b.affine_inverse()
	var cell: Vector3 = region.size / float(SOLID_SAMPLE_STEPS)
	var iso: float = -absf(thickness)
	var overlaps: bool = false
	for ix: int in SOLID_SAMPLE_STEPS:
		for iy: int in SOLID_SAMPLE_STEPS:
			for iz: int in SOLID_SAMPLE_STEPS:
				var p: Vector3 = _cell_centre(region, cell, ix, iy, iz)
				var da: float = shape_a.sdf(inv_a * p)
				if da >= 0.0:
					continue
				var db: float = shape_b.sdf(inv_b * p)
				if db >= 0.0:
					continue
				overlaps = true
				if da < iso and db < iso:
					return {"overlaps": true, "merges": true}
	return {"overlaps": overlaps, "merges": false}


# --- private -------------------------------------------------------------------------------


static func _pair_entry(
	sdf: ShipSdf,
	cfg: ShipConfig,
	index_of: Dictionary,
	boxes: Dictionary,
	id_a: String,
	id_b: String,
	thickness: float
) -> Dictionary:
	var box_a: AABB = boxes[id_a]
	var box_b: AABB = boxes[id_b]
	if not box_a.intersects(box_b):
		return {}
	var region: AABB = box_a.intersection(box_b)
	var ia: int = index_of[id_a]
	var ib: int = index_of[id_b]
	var steps: int = _steps_for(region, cfg.metrics_cell_m)
	var state: Dictionary = pair_state(sdf, ia, ib, region, thickness, steps)
	var overlaps: bool = state["overlaps"]
	var merges: bool = state["merges"]
	var lo: String = id_a
	var hi: String = id_b
	if lo > hi:
		lo = id_b
		hi = id_a
	return {"a": lo, "b": hi, "overlaps": overlaps, "merges": merges}


# Resolution for a pairwise scan: follow the configured metrics cell size where it is sane, but
# never below MIN_PAIR_STEPS (too coarse to see anything) or above MAX_PAIR_STEPS (too slow to run
# on every edit).
static func _steps_for(region: AABB, cell_m: float) -> int:
	if cell_m <= 0.0:
		return FINE_STEPS
	var longest: float = maxf(maxf(region.size.x, region.size.y), region.size.z)
	var wanted: int = int(ceil(longest / cell_m))
	return clampi(wanted, MIN_PAIR_STEPS, MAX_PAIR_STEPS)


static func _cell_centre(bounds: AABB, cell: Vector3, ix: int, iy: int, iz: int) -> Vector3:
	return (
		bounds.position
		+ Vector3(
			(float(ix) + 0.5) * cell.x, (float(iy) + 0.5) * cell.y, (float(iz) + 0.5) * cell.z
		)
	)
