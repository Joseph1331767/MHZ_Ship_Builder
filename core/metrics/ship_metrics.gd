class_name ShipMetrics
extends RefCounted

# Ship metrics — SPEC section 8 (budgets, dev tuning), section 9 (the SDF caveats).
# API_CONTRACT section 15. Pure data: no Node, no SceneTree, no signals, no res://.
#
# Two paths, deliberately different in cost:
#
#   compute_bbox()  cheap, no grid. Union of transformed part AABBs. Runs on EVERY edit
#                   for the bbox budget, so it must stay allocation-light. It is a BOUND,
#                   not the exact hull extent (a rotated part contributes the AABB of its
#                   rotated AABB, and the smooth-union bulge is not included) — that is
#                   correct and intended: a bound that never under-reads the true extent
#                   is exactly what a hard-block budget wants.
#
#   compute()       the full grid pass at an adaptive cell size. Volume, area, weight, cost.
#                   Run this on idle / on demand, never per drag frame.
#
# WHAT THE GRID PASS COSTS, AND WHY THE CELL IS ADAPTIVE
# ------------------------------------------------------
# A 250 m ship at metrics_cell_m = 0.5 is 500 x 240 x 500 = 60 million samples. GDScript
# manages a few hundred thousand ShipSdf.sample() calls in the time a human tolerates for
# an interactive readout, not sixty million. So `cfg.metrics_cell_m` is a HINT, not a
# promise, and _choose_cell() moves it in BOTH directions:
#
#   coarser  — until the grid fits the sample budget (TARGET_SAMPLES, hard-capped at
#              MAX_SAMPLES). On a big ship the numbers get coarser, not slower.
#   finer    — when the ship is small enough that the budget affords it AND the hinted cell
#              is too coarse to resolve the hull shell. RETIRED(2026-08-31): this used to be
#              a hard floor (coarsen only). That made `internal_volume_m3` read a flat
#              0.000 m3 for a 2 m starter part at cell 0.5 with a 0.15 m shell — the cavity
#              is the region sdf < -thickness, and a cell coarser than the shell cannot
#              resolve it. Area and weight were correct at the same time, so it read as a
#              real measurement rather than a resolution failure.
#
# The cell actually used is recorded in `sample_cell_m` so the caller — and any report —
# knows the fidelity of the numbers it is looking at. Fidelity degrades gracefully;
# responsiveness does not degrade at all.
#
# SURFACE AREA ESTIMATOR — co-area / narrow band, and its bias
# ------------------------------------------------------------
# We use the co-area formula
#
#     A = integral over the volume of  delta_eps(phi) * |grad phi|  dV
#       ~= sum over band cells of  delta_eps(d) * |grad d| * cell^3
#
# with the raised-cosine smoothed delta  delta_eps(s) = (1 + cos(PI*s/eps)) / (2*eps)  for
# |s| <= eps, band half-width eps = BAND_CELLS * cell (1.5 cells), and |grad d| taken from
# central differences on the grid we already have (free — no extra sdf.sample() calls).
#
# Why this and not the cheaper "count sign-changing cell edges times a constant":
# edge counting gives  E = A * (|nx| + |ny| + |nz|) / cell^2, so any single calibration
# constant is only right for one surface orientation. The isotropic constant (L1 norm of a
# random unit normal averages 1.5, giving A ~= (2/3) * E * cell^2) is asymptotically exact
# for a sphere but UNDER-reads an axis-aligned plane by 33% and OVER-reads a (1,1,1) plane
# by 15%. A ship builder whose primitives are mostly boxes would eat that 33% on nearly
# every flat face, and weight is derived from area, so the error would land straight in the
# weight budget. Unacceptable. The co-area estimator has no orientation constant at all.
#
# Expected error of what we actually use:
#   * Orientation bias: essentially none. For an axis-aligned plane the lattice quadrature
#     of the raised-cosine kernel is exact in the limit — with eps = 1.5*cell every aliasing
#     term sits on a zero of the kernel's transform (2*eps*f = 3k, k >= 1). Off-axis planes
#     alias slightly; measured against analytic solids expect ~2-5% at cell <= feature/10.
#   * Convergence: first order, O(cell). Halving the cell roughly halves the error.
#   * Curvature: features with radius of curvature below ~2 cells are smeared by the band
#     and under-read. Same for thin plates: any wall thinner than ~3 cells has its two faces
#     merge into one band and reads as roughly one face, not two.
#   * Creases: at a min() union seam the field has a kink, so the central-difference
#     |grad d| under-reads there and the seam contributes slightly less area than it should.
#     Bounded by the clamp below and small in practice (seams are one-dimensional).
#   * When the adaptive cell has coarsened on a large ship, all of the above grow with it.
#     Read `sample_cell_m` before trusting a number to better than ~10%.
#
# |grad d| is clamped to [GRAD_MIN, GRAD_MAX]: for a true SDF it is 1.0, but domain-warp
# ops (taper, twist) and non-uniform scale make the field a bound rather than a distance
# (SPEC section 9 caveat 2), and a kink can produce a wild finite difference. The clamp is a
# blow-up guard, not a correction.
#
# INTERNAL VOLUME
# ---------------
# The cavity is the region where sdf(p) < -hull_thickness_m (SPEC section 8). SPEC section 9
# caveat 1 applies verbatim: interior distance from a union of min()s is not exact, so near
# joints the -T level set sits too far out and the shell reads slightly thick — internal
# volume therefore under-reads near joints. Bounded, known, not a bug to be fixed away here;
# the fix path is a grid plus an eikonal sweep.
#
# WEIGHT
# ------
# weight_kg = surface_area_m2 * cfg.areal_density_kg_m2 — a shell model. When MHZ_Materials
# plugs in, `areal_density` becomes `thickness * material.density` and THIS FORMULA DOES NOT
# CHANGE. That is the whole reason it is shaped this way.

## Sample-count budget for the full grid pass. TARGET is what _choose_cell() aims at;
## MAX_SAMPLES is the hard ceiling it will not cross no matter how big the ship gets.
const TARGET_SAMPLES: int = 250000
const MAX_SAMPLES: int = 1000000

## Never sample finer than this, whatever tuning.json says. Guards cfg.metrics_cell_m <= 0.
const MIN_CELL_M: float = 0.01

## Narrow-band half-width in cells for the area estimator. 1.5 is not arbitrary: it puts
## every lattice alias on a zero of the raised-cosine kernel's transform. Changing it
## reintroduces orientation bias.
const BAND_CELLS: float = 1.5

## Blow-up guard on the finite-difference gradient magnitude (a true SDF gives 1.0).
const GRAD_MIN: float = 0.25
const GRAD_MAX: float = 4.0

## Each coarsening step multiplies the cell by ~2^(1/3), i.e. halves the sample count.
const COARSEN_STEP: float = 1.2599210498948732
const COARSEN_MAX_STEPS: int = 64

## Fallbacks when a data pack entry is missing or malformed. Metrics never crash on bad data.
const DEFAULT_BASE_COST: float = 1.0
const DEFAULT_COST_MULTIPLIER: float = 1.0
const SIZE_FACTOR_MIN: float = 0.01
const SIZE_FACTOR_MAX: float = 1000.0

var bbox: AABB = AABB()
var surface_area_m2: float = 0.0
var solid_volume_m3: float = 0.0
var internal_volume_m3: float = 0.0
var weight_kg: float = 0.0
var cost: float = 0.0
var sample_cell_m: float = 0.0

# --- the cheap path -----------------------------------------------------------------


## Union of every resolved part AABB, transformed into ship space. No grid sampling.
## Includes generated mirror derivatives, because a mirrored wing sticks out just as far as
## the wing it was mirrored from. This is what the bbox budget reads on every edit.
static func compute_bbox(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> AABB:
	if doc == null or data == null or cfg == null:
		return AABB()
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all(doc, data, cfg)
	var out: AABB = AABB()
	var seeded: bool = false
	for id: String in xforms:
		var shape: ResolvedShape = _shape_for(id, shapes, doc)
		if shape == null:
			continue
		var xf_v: Variant = xforms[id]
		if not (xf_v is Transform3D):
			continue
		var xf: Transform3D = xf_v
		var box: AABB = (xf * shape.local_aabb()).abs()
		if seeded:
			out = out.merge(box)
		else:
			out = box
			seeded = true
	return out


# --- the full pass ------------------------------------------------------------------


## Where the ship's mass sits and how centred that is: `{"centre": Vector3, "balance": Vector3,
## "best": float, "parts": int}`. `balance` is 0-1 per axis, 1 being dead centre.
##
## THE SHIP'S BALANCE, NOT ITS SYMMETRY (ADR 0045). The author's rule for a prebuilt class is
## symmetry across at least ONE axis - "with 3 orthognal axies to choose from and the constraint
## that only 1 has to be symetrical" - so `best` is the axis the ship does best on, and that is the
## single 0-1 number worth showing: "maybe during this builder we just give a 0-1 value of how
## centered it is, and we draw a cross where the com is" (2026-09-25). Perfecting it by adding
## ballast is a later mechanic, and none of this pre-empts it.
##
## WEIGHT IS VOLUME, FOR NOW, and the author said so: "all hull volumes wil be placeholdered at same
## density so it translates to volume and shape for now but can be set up via weight". A part's
## share is its resolved bound's volume - no meshing, so this costs an attach solve and nothing
## more. When real densities arrive this formula is the one line that changes.
##
## INCLUDES MIRRORED TWINS, because a twin is as real as the part it came from - and they are most
## of what makes a ship balanced in the first place.
static func balance(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary:
	var out: Dictionary = {"centre": Vector3.ZERO, "balance": Vector3.ZERO, "best": 0.0, "parts": 0}
	if doc == null or data == null or cfg == null:
		return out
	var shapes: Dictionary = ShipAttach.resolve_shapes(doc, data, cfg)
	var xforms: Dictionary = ShipAttach.resolve_all_from_shapes(doc, shapes, cfg)
	var total: float = 0.0
	var moment: Vector3 = Vector3.ZERO
	var box: AABB = AABB()
	var first: bool = true
	for key: Variant in xforms:
		var id: String = str(key)
		var shape_v: Variant = shapes.get(ShipSymmetry.source_of_twin(id))
		if not (shape_v is ResolvedShape):
			continue
		var part: AABB = (xforms[key] as Transform3D) * (shape_v as ResolvedShape).local_aabb()
		part = part.abs()
		var weight: float = part.size.x * part.size.y * part.size.z
		if weight <= 0.0:
			continue
		total += weight
		moment += part.get_center() * weight
		box = part if first else box.merge(part)
		first = false
		out["parts"] = int(out["parts"]) + 1
	if total <= 0.0 or first:
		return out
	var centre: Vector3 = moment / total
	# Against the ship's OWN half extent, so a small ship and a large one read on one scale.
	var half: Vector3 = box.size * 0.5
	var spread: Vector3 = Vector3.ZERO
	for axis: int in 3:
		spread[axis] = clampf(1.0 - absf(centre[axis]) / maxf(half[axis], 0.001), 0.0, 1.0)
	out["centre"] = centre
	out["balance"] = spread
	out["best"] = maxf(spread.x, maxf(spread.y, spread.z))
	return out


## Full grid pass. Fills every field. `sdf` must have been built from the same doc/data/cfg.
static func compute(sdf: ShipSdf, doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> ShipMetrics:
	var m: ShipMetrics = ShipMetrics.new()
	if doc == null or data == null or cfg == null:
		return m
	# The budget bbox comes from the cheap path even here, so the number the gauge shows
	# after a full compute can never disagree with the number the per-edit check used.
	# ShipSdf.aabb() is contractually the same union; we just refuse to depend on that.
	m.bbox = compute_bbox(doc, data, cfg)
	m.cost = compute_cost(doc, data)
	m.sample_cell_m = maxf(cfg.metrics_cell_m, MIN_CELL_M)
	if sdf == null or doc.part_order().is_empty():
		return m

	# Grid domain: the bbox, padded. The pad covers the smooth-union bulge (a polynomial
	# smin pushes the surface at most ~k/4 outside the union of its operands) plus two
	# cells of margin, so the narrow band never reaches the grid boundary and the area pass
	# can skip the boundary layer instead of special-casing one-sided differences there.
	var base: AABB = m.bbox.abs()
	if not _is_finite_aabb(base):
		# A non-finite bbox means a part resolved to garbage. Refuse to build a grid over it
		# rather than hanging on an infinite one; the validator is the place that reports it.
		return m
	var padded: AABB = base.grow(maxf(_max_blend(doc), 0.0))
	var cell: float = _choose_cell(padded, m.sample_cell_m, absf(cfg.hull_thickness_m))
	var bounds: AABB = padded.grow(2.0 * cell)
	# Regrowing by the margin can push the count back over the ceiling on a pathological
	# doc; coarsen again until it fits.
	var guard: int = 0
	while _sample_count(bounds, cell) > MAX_SAMPLES and guard < COARSEN_MAX_STEPS:
		cell *= COARSEN_STEP
		bounds = padded.grow(2.0 * cell)
		guard += 1
	m.sample_cell_m = cell

	var nx: int = maxi(1, int(ceil(bounds.size.x / cell)))
	var ny: int = maxi(1, int(ceil(bounds.size.y / cell)))
	var nz: int = maxi(1, int(ceil(bounds.size.z / cell)))
	var origin: Vector3 = bounds.position
	var cell_vol: float = cell * cell * cell
	var iso_inner: float = -maxf(cfg.hull_thickness_m, 0.0)

	var solid_cells: int = 0
	var inner_cells: int = 0
	var area: float = 0.0

	# Three rolling z-slabs: sample slab k, then run the area pass on slab k-1 with slab
	# k-2 and slab k as its z-neighbours. Peak memory is 3 * nx * ny floats rather than the
	# whole grid, and the central differences cost nothing extra — they reuse samples the
	# volume count already needed.
	var slab_a: PackedFloat32Array = PackedFloat32Array()
	var slab_b: PackedFloat32Array = PackedFloat32Array()
	var slab_c: PackedFloat32Array = PackedFloat32Array()
	for k: int in range(nz):
		var z: float = origin.z + (float(k) + 0.5) * cell
		slab_a = slab_b
		slab_b = slab_c
		slab_c = _sample_slab(sdf, origin, cell, nx, ny, z)
		var counts: Vector2i = _count_slab(slab_c, iso_inner)
		solid_cells += counts.x
		inner_cells += counts.y
		if k >= 2:
			area += _slab_area(slab_a, slab_b, slab_c, nx, ny, cell)

	m.solid_volume_m3 = float(solid_cells) * cell_vol
	m.internal_volume_m3 = float(inner_cells) * cell_vol
	m.surface_area_m2 = area
	# Shell model. MHZ_Materials later supplies areal_density = thickness * density and this
	# line is untouched.
	m.weight_kg = m.surface_area_m2 * cfg.areal_density_kg_m2
	return m


## Sum over parts of family_base_cost * manufacturer_multiplier * size_factor *
## param_complexity (SPEC section 8). Every lookup falls back to a neutral 1.0 rather than
## failing: cost is a gauge, and a half-authored data pack must not take the builder down.
##
## size_factor is the CUBE ROOT of the product of the scale components — the geometric mean,
## i.e. a linear feel. The alternative (the raw product, a volume feel) makes a uniform 2x
## drag multiply that part's cost by 8, which reads as broken on a gauge the player is
## watching while they drag a scale handle, and lets one big part swamp the whole total.
## It is deliberately an under-charge relative to material use; max_cost is infinite in
## Phase 1 and cost's job here is comparative legibility, not accounting. Revisit when
## MHZ_Materials supplies real per-volume pricing and max_cost becomes a real cap.
##
## Component instances: `family` holds a component definition id, not a family id, so an
## instance is costed as the SUM of its definition's parts, each at its own scale times the
## instance's, nested instances included (to ShipComponents.MAX_NESTING_DEPTH). The gauge
## therefore reads the same before and after a subtree is lifted into a component.
## RETIRED(2026-09-02): the instance costing its neutral fallback until expand() landed.
static func compute_cost(doc: ShipDoc, data: ShipData) -> float:
	if doc == null or data == null:
		return 0.0
	var total: float = 0.0
	var ids: PackedStringArray = doc.part_order()
	for id: String in ids:
		var part_v: Variant = doc.parts.get(id, null)
		if not (part_v is ShipPart):
			continue
		var part: ShipPart = part_v
		total += _record_cost(doc, data, part, Vector3.ONE, 0)
	return total


## One part record's cost, `scale_mul` being the scale of the instance(s) it sits inside. An
## instance record costs its whole definition.
static func _record_cost(
	doc: ShipDoc, data: ShipData, part: ShipPart, scale_mul: Vector3, depth: int
) -> float:
	if part.kind == ShipPart.KIND_COMPONENT_INSTANCE:
		if depth > ShipComponents.MAX_NESTING_DEPTH or not doc.components.has(part.family):
			return 0.0
		var inner: Dictionary = ShipComponents.definition_parts(doc.components[part.family])
		var sum: float = 0.0
		var scale: Vector3 = part.scale * scale_mul
		for inner_id: String in inner:
			sum += _record_cost(doc, data, inner[inner_id], scale, depth + 1)
		return sum
	var fam: Dictionary = _entry(data.families, part.family)
	var manu: Dictionary = _entry(data.manufacturers, part.manufacturer)
	var base_cost: float = _num(fam, "base_cost", DEFAULT_BASE_COST)
	var mult: float = _num(manu, "cost_multiplier", DEFAULT_COST_MULTIPLIER)
	var size_factor: float = _size_factor(part.scale * scale_mul)
	var complexity: float = ShapeGen.param_complexity(data, part.family, part.params)
	if not is_finite(complexity) or complexity <= 0.0:
		complexity = 1.0
	var c: float = base_cost * mult * size_factor * complexity
	return c if is_finite(c) else 0.0


## JSON-safe. Floats are snapped to 6 dp so a report diff shows real changes, not noise.
func to_dict() -> Dictionary:
	var mn: Vector3 = bbox.position
	var sz: Vector3 = bbox.size
	return {
		"bbox_min": [snappedf(mn.x, 0.000001), snappedf(mn.y, 0.000001), snappedf(mn.z, 0.000001)],
		"bbox_size": [snappedf(sz.x, 0.000001), snappedf(sz.y, 0.000001), snappedf(sz.z, 0.000001)],
		"surface_area_m2": snappedf(surface_area_m2, 0.000001),
		"solid_volume_m3": snappedf(solid_volume_m3, 0.000001),
		"internal_volume_m3": snappedf(internal_volume_m3, 0.000001),
		"weight_kg": snappedf(weight_kg, 0.000001),
		"cost": snappedf(cost, 0.000001),
		"sample_cell_m": snappedf(sample_cell_m, 0.000001),
	}


# --- grid helpers -------------------------------------------------------------------


## Coarsen `requested` upward until the grid over `bounds` fits the sample budget. The
## requested cell is a floor: we never sample finer than tuning asks for, only coarser.
static func _choose_cell(bounds: AABB, requested: float, thickness: float) -> float:
	var cell: float = maxf(requested, MIN_CELL_M)
	var sz: Vector3 = bounds.size
	if sz.x <= 0.0 or sz.y <= 0.0 or sz.z <= 0.0:
		return cell
	var vol: float = sz.x * sz.y * sz.z
	if vol > 0.0 and is_finite(vol):
		# cell such that vol / cell^3 ~= TARGET_SAMPLES.
		var target_cell: float = pow(vol / float(TARGET_SAMPLES), 1.0 / 3.0)
		if is_finite(target_cell) and target_cell > cell:
			cell = target_cell

	# REFINE DOWNWARD FOR SMALL SHIPS. `requested` was originally a hard floor -- coarsen
	# only, never refine -- which is right for a 250 m hull and wrong for a 2 m starter part.
	# `internal_volume_m3` is the volume of the region sdf < -hull_thickness, so a cell
	# COARSER THAN THE SHELL cannot resolve the cavity that the shell defines: at cell 0.5 m
	# with a 0.15 m shell, a 2 m box's interior missed every sample centre and the volume
	# budget read a flat 0.000 m3 while area and weight were correct. That is a wrong number
	# presented as a real one, which is the failure mode this file cares most about.
	#
	# So the shell sets a resolution requirement (half the thickness, i.e. two samples across
	# it) and the sample budget still has the final say -- refinement only happens when the
	# finer grid genuinely fits, which for a small ship it always does.
	if thickness > 0.0:
		var shell_cell: float = maxf(thickness * 0.5, MIN_CELL_M)
		if shell_cell < cell and _sample_count(bounds, shell_cell) <= TARGET_SAMPLES:
			cell = shell_cell

	var guard: int = 0
	while _sample_count(bounds, cell) > MAX_SAMPLES and guard < COARSEN_MAX_STEPS:
		cell *= COARSEN_STEP
		guard += 1
	return cell


## Saturating: a degenerate cell or a runaway AABB returns "over the ceiling" rather than
## overflowing the multiply into a negative number, which would read as under the ceiling and
## hand the sampler a grid it can never finish.
static func _sample_count(bounds: AABB, cell: float) -> int:
	if cell <= 0.0 or not _is_finite_aabb(bounds):
		return MAX_SAMPLES + 1
	var nx: float = ceil(bounds.size.x / cell)
	var ny: float = ceil(bounds.size.y / cell)
	var nz: float = ceil(bounds.size.z / cell)
	var total: float = maxf(nx, 1.0) * maxf(ny, 1.0) * maxf(nz, 1.0)
	if not is_finite(total) or total > float(MAX_SAMPLES):
		return MAX_SAMPLES + 1
	return int(total)


## One z-slice of cell-centre samples, row-major (idx = j * nx + i).
static func _sample_slab(
	sdf: ShipSdf, origin: Vector3, cell: float, nx: int, ny: int, z: float
) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	# resize() returns an Error we have no useful response to (a failure here is out of
	# memory, and the grid was already capped to keep that impossible). Annotated rather
	# than assigned to a throwaway, which gdlint rejects.
	@warning_ignore("return_value_discarded")
	out.resize(nx * ny)
	var idx: int = 0
	for j: int in range(ny):
		var y: float = origin.y + (float(j) + 0.5) * cell
		for i: int in range(nx):
			out[idx] = sdf.sample(Vector3(origin.x + (float(i) + 0.5) * cell, y, z))
			idx += 1
	return out


## x = cells inside the solid, y = cells inside the cavity. Counts fit in 32 bits because
## the whole grid is capped at MAX_SAMPLES.
static func _count_slab(slab: PackedFloat32Array, iso_inner: float) -> Vector2i:
	var solid: int = 0
	var inner: int = 0
	var n: int = slab.size()
	for i: int in range(n):
		var d: float = slab[i]
		if d < 0.0:
			solid += 1
			if d < iso_inner:
				inner += 1
	return Vector2i(solid, inner)


## Co-area area contribution of the centre slab `b`, using `a` and `c` as its z-neighbours.
## The boundary layer is skipped: the grid is padded by two cells, so nothing within the
## band can live there.
static func _slab_area(
	a: PackedFloat32Array,
	b: PackedFloat32Array,
	c: PackedFloat32Array,
	nx: int,
	ny: int,
	cell: float
) -> float:
	if nx < 3 or ny < 3:
		return 0.0
	var band: float = BAND_CELLS * cell
	var inv_two_band: float = 1.0 / (2.0 * band)
	var inv_two_h: float = 1.0 / (2.0 * cell)
	var acc: float = 0.0
	for j: int in range(1, ny - 1):
		var row: int = j * nx
		for i: int in range(1, nx - 1):
			var idx: int = row + i
			var d: float = b[idx]
			if d <= -band or d >= band:
				continue
			var gx: float = (b[idx + 1] - b[idx - 1]) * inv_two_h
			var gy: float = (b[idx + nx] - b[idx - nx]) * inv_two_h
			var gz: float = (c[idx] - a[idx]) * inv_two_h
			var g: float = sqrt(gx * gx + gy * gy + gz * gz)
			if not is_finite(g):
				continue
			g = clampf(g, GRAD_MIN, GRAD_MAX)
			var delta: float = inv_two_band * (1.0 + cos(PI * d / band))
			acc += delta * g
	return acc * cell * cell * cell


# --- lookup helpers -----------------------------------------------------------------


## The resolved shape for a part id. A mirror derivative may not carry its own entry — it is
## generated by reflecting its source — so fall back to the source's shape.
static func _shape_for(id: String, shapes: Dictionary, doc: ShipDoc) -> ResolvedShape:
	var sv: Variant = shapes.get(id, null)
	if sv is ResolvedShape:
		return sv
	var pv: Variant = doc.parts.get(id, null)
	if pv is ShipPart:
		var part: ShipPart = pv
		if part.mirror_source != "":
			var mv: Variant = shapes.get(part.mirror_source, null)
			if mv is ResolvedShape:
				return mv
	return null


## The largest smooth-union radius anywhere in the field. Only the doc's own parts are read: an
## expanded component part inherits the blend of the instance it came from (ShipSdf._blend_for),
## never its definition record's own, so the instance's number already bounds every part under
## it and no walk into the definitions is needed.
static func _max_blend(doc: ShipDoc) -> float:
	var out: float = 0.0
	var ids: PackedStringArray = doc.part_order()
	for id: String in ids:
		var pv: Variant = doc.parts.get(id, null)
		if pv is ShipPart:
			var part: ShipPart = pv
			out = maxf(out, absf(part.blend))
	if not is_finite(out):
		return 0.0
	return out


## Geometric mean of |scale|. Zero or non-finite scale collapses to the floor rather than
## zeroing or poisoning the total.
static func _size_factor(scale: Vector3) -> float:
	var v: Vector3 = scale.abs()
	var prod: float = v.x * v.y * v.z
	if not is_finite(prod) or prod <= 0.0:
		return SIZE_FACTOR_MIN
	return clampf(pow(prod, 1.0 / 3.0), SIZE_FACTOR_MIN, SIZE_FACTOR_MAX)


static func _is_finite_aabb(a: AABB) -> bool:
	var p: Vector3 = a.position
	var s: Vector3 = a.size
	return (
		is_finite(p.x)
		and is_finite(p.y)
		and is_finite(p.z)
		and is_finite(s.x)
		and is_finite(s.y)
		and is_finite(s.z)
	)


static func _entry(pack: Dictionary, id: String) -> Dictionary:
	if id == "":
		return {}
	var v: Variant = pack.get(id, null)
	if v is Dictionary:
		return v
	return {}


static func _num(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, null)
	var t: int = typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		var f: float = v
		if is_finite(f):
			return f
	return fallback
