class_name HullBake
## The hull bake: a [ShipSdf] in, an [ArrayMesh] shell plus a report out (SPEC §9).
##
## Bounds are the SDF's own AABB padded by the hull thickness (the Phase 2 interior shell
## at level [code]-T[/code] has to fit inside the same grid) plus one cell, so the outer
## surface is never clipped by the grid boundary. [SurfaceNets] does the extraction; this
## class only frames it, packs the arrays into a mesh, and measures the result.
##
## RETIRED(ADR 0008, 2026-09-02): "Phase 1 bakes the all-open studio hull with no interior
## PARTITIONS" -> every seam now lays a plate in the field itself ([ShipSdf], [ShipSeams]), so
## the cavity mesh carries the walls and their doorways. This class widens those plates to its
## grid (see WALL_MIN_CELLS) and otherwise frames the extraction exactly as before.
##
## THE HULL ITSELF IS A WALL, THOUGH, AND IT HAS TWO SIDES. The author asked for it in the first
## brief — "i certainly want to give it a thickness and an interior mesh, trach its volum and mass
## etc" — and FOLLOWUPS F10 recorded it as still missing, because the "no walls" ruling about
## JOINTS had been quietly read as covering the shell as well. Two different things. The bake now
## extracts a SECOND isosurface at `iso - hull_thickness_m`, reverses it, and welds it to the
## outer surface, so what comes out is a closed shell of real thickness with a real cavity inside
## rather than a skin. `hull_thickness_m == 0` skips the second pass entirely and produces exactly
## what it always did.
##
## Pure data (SPEC §12): [ArrayMesh] is a [Resource], not a [Node], so returning one is
## inside the boundary. No [SceneTree], no signals, no [code]res://[/code]. Arguments are
## never mutated.

## Bakes the [param iso] level set of [param sdf] at [member ShipConfig.bake_cell_m].
##
## Returns [code]{ "mesh": ArrayMesh, "tris": int, "verts": int, "area_m2": float,
## "volume_m3": float, "cells": int, "cell_m": float, "dims": Vector3i, "ms": int,
## "islands": int, "floating": PackedStringArray, "interior_mesh": ArrayMesh,
## "interior_tris": int, "interior_volume_m3": float, "shell_volume_m3": float,
## "shell_mass_kg": float }[/code].
##
## [code]mesh[/code] is the CLOSED SHELL — outer surface plus the reversed interior — so a caller
## that only renders it sees no difference from outside and gets a solid wall in section.
## [code]interior_mesh[/code] is the cavity surface on its own, outward-facing, for a caller that
## wants to show the inside. [code]volume_m3[/code] stays the OUTER volume it always was;
## [code]interior_volume_m3[/code] is the cavity, and [code]shell_volume_m3[/code] the difference
## — the material actually built, which is what [code]shell_mass_kg[/code] weighs at
## [member ShipConfig.areal_density_kg_m2] over the outer area.
## [code]cells[/code] is the grid cell COUNT and [code]cell_m[/code] the spacing actually
## used, which differs from [member ShipConfig.bake_cell_m] when [SurfaceNets] had to
## coarsen the grid to stay under its cap. The mesh has zero surfaces when the field has no
## crossing of [param iso] inside the bounds.
##
## [param doc] is OPTIONAL and additive only, API_CONTRACT_SPORE §7: every existing caller
## passes three arguments and keeps working unchanged. When supplied, [code]islands[/code]
## is the connected-component count computed directly from [param sdf] (never a second SDF
## rebuild — [method connectivity] already does that from a bare doc, but [param sdf] is
## already in hand here) and [code]floating[/code] is read from [param doc]'s
## [code]floating_part_ids()[/code], called dynamically because that method is landing in a
## concurrently-edited file and may not exist yet — a direct typed call would fail to parse
## until it does. Omitting [param doc] reports zero islands and no floating parts, exactly
## as if connectivity were never asked about — this is a report, never a block, so a caller
## that does not care about it pays nothing and breaks nothing.
## Grid resolution for the per-part occupancy boxes the island pass works from. Deliberately
## coarse: this runs inside a bake that is already the most expensive thing in the project, and
## an island is a topological question, not a metric one.
## RETIRED(2026-08-31): ISLAND_BOX_STEPS -> ShipSdf.part_aabb(). Island boxes were probed off the
## union field on a grid of this many steps across the WHOLE ship, so accuracy fell as the ship
## grew. The pair probe below still samples, but only inside the small AABB where two parts
## actually overlap, so its resolution is local and does not drift with scene size.

## Resolution of the per-pair overlap probe, over the INTERSECTION of two part boxes only.
const ISLAND_PAIR_STEPS: int = 6

## Minimum seam-plate thickness, in grid cells, passed to [method ShipSdf.with_min_wall_m]. A
## band exactly one spacing wide always holds a sample; the margin is for the rounding that
## would otherwise let a wall depend on where the grid happens to start.
const WALL_MIN_CELLS: float = 1.05


static func bake(sdf: ShipSdf, cfg: ShipConfig, iso: float, doc: ShipDoc = null) -> Dictionary:
	var t0: int = Time.get_ticks_msec()

	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	var in_verts: PackedVector3Array = PackedVector3Array()
	var in_norms: PackedVector3Array = PackedVector3Array()
	var in_idx: PackedInt32Array = PackedInt32Array()
	var cells: int = 0
	var used_cell: float = 0.0
	var dims: Vector3i = Vector3i.ZERO
	var island_count: int = 0
	var patches: int = 0

	if sdf != null and cfg != null:
		var cell: float = maxf(cfg.bake_cell_m, SurfaceNets.MIN_CELL_M)
		# SPEC §9: AABB padded by thickness, plus one cell of slack so the outermost band
		# of cells is fully outside the solid and the shell closes instead of being cut off
		# flat against the grid boundary.
		var pad: float = absf(cfg.hull_thickness_m) + cell
		var bounds: AABB = sdf.aabb().abs().grow(pad)
		# SEAM WALLS (ADR 0008) must be at least one grid cell thick or the grid steps over
		# them: a plate is a bump in the field, not a crossing, and a bump between two samples
		# is invisible. Widened against the spacing the extractor will REALLY use - the cap in
		# SurfaceNets can coarsen it - never against the one asked for. A coarse bake gets a
		# thicker bulkhead rather than none; the hull thickness the report weighs is unchanged.
		var spacing: float = SurfaceNets.fitted_cell(bounds.size, cell)
		var field: ShipSdf = sdf.with_min_wall_m(spacing * WALL_MIN_CELLS)
		var res: Dictionary = SurfaceNets.extract(field, bounds, cell, iso)
		cells = res["cells"]
		used_cell = res["cell_m"]
		dims = res["dims"]
		# THE EXTRACTOR IS NOT THE MESH. Dual Contouring emits one quad per sign-changing grid
		# edge and knows nothing about the fact that most of a hull is flat, so a 3 m room came
		# out of it with 1568 triangles, 65% of them coplanar, and every box edge wearing a band
		# of sub-cell noise. HullSimplify rebuilds the flat parts as flat parts; it changes no
		# field, so no hash and no ruleset version move with it (AGENTS section 8b).
		var flat: Dictionary = HullSimplify.simplify(
			field, res["vertices"], res["indices"], iso, used_cell
		)
		verts = flat["vertices"]
		norms = flat["normals"]
		idx = flat["indices"]
		patches = flat["planar_patches"]
		island_count = _islands_of(sdf, cfg).size()
		# The cavity wall: the same field, T metres further in. Negative because the field is
		# negative INSIDE the solid, so `iso - T` is the level set T metres below the surface.
		# Skipped entirely at zero thickness, which is both the honest answer and the cheap one -
		# this pass costs as much as the first.
		var thickness: float = absf(cfg.hull_thickness_m)
		if thickness > 0.0:
			var inner_iso: float = iso - thickness
			var inner: Dictionary = SurfaceNets.extract(field, bounds, cell, inner_iso)
			var inner_flat: Dictionary = HullSimplify.simplify(
				field, inner["vertices"], inner["indices"], inner_iso, used_cell
			)
			in_verts = inner_flat["vertices"]
			in_norms = inner_flat["normals"]
			in_idx = inner_flat["indices"]

	var floating: PackedStringArray = PackedStringArray()
	if doc != null and doc.has_method("floating_part_ids"):
		var floating_v: Variant = doc.call("floating_part_ids")
		if floating_v is PackedStringArray:
			floating = floating_v

	# The shell: the outer surface, plus the interior with its winding reversed and its normals
	# flipped so it faces into the cavity. One surface, not two, so the mesh is a single closed
	# manifold rather than two shapes that happen to be nested.
	var shell_verts: PackedVector3Array = verts.duplicate()
	var shell_norms: PackedVector3Array = norms.duplicate()
	var shell_idx: PackedInt32Array = idx.duplicate()
	_append_reversed(shell_verts, shell_norms, shell_idx, in_verts, in_norms, in_idx)

	var mesh: ArrayMesh = _mesh_from(shell_verts, shell_norms, shell_idx)
	var interior_mesh: ArrayMesh = _mesh_from(in_verts, in_norms, in_idx)

	# The extractor only ever emits triangles, so the index count is always a multiple of 3
	# and the discarded decimal part the warning guards against cannot exist.
	@warning_ignore("integer_division")
	var tri_count: int = shell_idx.size() / 3
	@warning_ignore("integer_division")
	var in_tri_count: int = in_idx.size() / 3

	var outer_area: float = mesh_area(verts, idx)
	var outer_volume: float = mesh_volume(verts, idx)
	var inner_volume: float = mesh_volume(in_verts, in_idx)
	return {
		"mesh": mesh,
		"tris": tri_count,
		"verts": shell_verts.size(),
		"area_m2": outer_area,
		"volume_m3": outer_volume,
		"cells": cells,
		"cell_m": used_cell,
		"dims": dims,
		"ms": Time.get_ticks_msec() - t0,
		"islands": island_count,
		"floating": floating,
		"interior_mesh": interior_mesh,
		"interior_tris": in_tri_count,
		"interior_volume_m3": inner_volume,
		# How many flat faces the outer surface was rebuilt as. A box reports 6.
		"planar_patches": patches,
		# What was actually BUILT, and therefore what it weighs. Never negative: a hull thinner
		# than the shell it was asked for has no cavity at all, and reporting a negative volume
		# would put a negative mass on the gauges.
		"shell_volume_m3": maxf(outer_volume - inner_volume, 0.0),
		"shell_mass_kg": outer_area * maxf(cfg.areal_density_kg_m2, 0.0) if cfg != null else 0.0,
	}


## One PRIMITIVE_TRIANGLES ArrayMesh, or an empty one when there is nothing to build.
static func _mesh_from(
	verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array
) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if verts.is_empty() or idx.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Welds `add_*` onto `out_*` with its triangle winding reversed and its normals negated.
##
## Reversing BOTH is the point. The interior surface comes out of Surface Nets facing the same way
## the outer one does - outward, along the field's gradient - and a shell whose inner wall faces
## outward is a shell you can see straight through from inside, with backface culling removing
## exactly the wall the player is standing behind. Flipping the winding fixes the culling and
## flipping the normals fixes the lighting; doing one without the other trades one artefact for
## another.
static func _append_reversed(
	out_verts: PackedVector3Array,
	out_norms: PackedVector3Array,
	out_idx: PackedInt32Array,
	add_verts: PackedVector3Array,
	add_norms: PackedVector3Array,
	add_idx: PackedInt32Array
) -> void:
	if add_verts.is_empty() or add_idx.is_empty():
		return
	var base: int = out_verts.size()
	out_verts.append_array(add_verts)
	for n: Vector3 in add_norms:
		out_norms.append(-n)
	var i: int = 0
	while i + 2 < add_idx.size():
		out_idx.append(base + add_idx[i])
		out_idx.append(base + add_idx[i + 2])
		out_idx.append(base + add_idx[i + 1])
		i += 3


## Connected components of the placed parts, by overlap. Report only; never blocks — Spore's
## vehicle/UFO editor requires no contiguity at all (SPORE_CLONE_SPEC §5: bodies "require no
## base", cockpits "do not have to be attached"), so this exists to inform the player, never
## to refuse a bake.
##
## Two parts share an island when their solids actually overlap in SHIP space — judged by
## geometry, never by the parent/child tree, because a part may be parented yet placed far
## away (the Ctrl+drag vertical move explicitly allows floating) while two unparented parts
## may physically interpenetrate. The overlap test itself is [ShipJoints]'s: the same AABB
## pre-pass ([method ShipJoints.part_box]) followed by the same SDF-sampling pairwise scan
## ([method ShipJoints.pair_state]), read for its [code]"overlaps"[/code] flag — never its
## [code]"merges"[/code] flag, which additionally requires the two cavities to connect past
## [member ShipConfig.hull_thickness_m] and would under-count islands whose parts only
## share a thin shell. Reusing the exact same predicate is deliberate: a second, differently
## behaved definition of "these parts touch" is a bug source, not a feature.
##
## Returns [code]{ "islands": Array[PackedStringArray], "largest": PackedStringArray }[/code].
## [code]islands[/code] is sorted deterministically — largest island first, ties broken by
## the lowest part id — and the ids within each island are themselves sorted. An empty doc
## yields [code]{ "islands": [], "largest": PackedStringArray() }[/code].
static func connectivity(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary:
	var islands: Array[PackedStringArray] = []
	if doc != null and data != null and cfg != null:
		var sdf: ShipSdf = ShipSdf.build(doc, data, cfg)
		islands = _islands_of(sdf, cfg)

	var largest: PackedStringArray = PackedStringArray()
	if not islands.is_empty():
		largest = islands[0]
	return {"islands": islands, "largest": largest}


## Total surface area of the indexed triangle soup, in square metres.
##
## SPEC §8 feeds this straight into weight: [code]weight_kg = area * areal_density[/code].
## Winding-independent — a flipped triangle still has a positive area.
static func mesh_area(verts: PackedVector3Array, idx: PackedInt32Array) -> float:
	var total: float = 0.0
	var n: int = idx.size()
	var i: int = 0
	while i + 2 < n:
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		var c: Vector3 = verts[idx[i + 2]]
		total += (b - a).cross(c - a).length()
		i += 3
	return total * 0.5


## Enclosed volume of the indexed triangle soup, in cubic metres.
##
## Divergence theorem: each triangle contributes the signed volume of the tetrahedron it
## forms with the origin, [code]a . (b x c) / 6[/code], and the winding-dependent sign is
## discarded at the end.
##
## THIS IS ONLY CORRECT FOR A CLOSED MESH. A bake whose solid runs into the grid bounds
## produces an open shell with a hole where it was clipped, and the number returned for
## that mesh is meaningless, not merely imprecise. [method bake] pads the bounds
## specifically so this does not happen; a caller extracting over hand-chosen bounds must
## check that for itself.
static func mesh_volume(verts: PackedVector3Array, idx: PackedInt32Array) -> float:
	var total: float = 0.0
	var n: int = idx.size()
	var i: int = 0
	while i + 2 < n:
		var a: Vector3 = verts[idx[i]]
		var b: Vector3 = verts[idx[i + 1]]
		var c: Vector3 = verts[idx[i + 2]]
		total += a.dot(b.cross(c))
		i += 3
	return absf(total / 6.0)


## Connected components of the placed parts, by geometric overlap. Report only.
##
## Judges by GEOMETRY, not by the part tree, and the distinction is load-bearing now that
## `Ctrl`+drag lets a part float free of the parent it is still parented to, and that Spore-style
## floating parts may overlap something they were never attached to. A parent/child edge is
## therefore neither necessary nor sufficient for two parts to share an island.
##
## Reuses [method ShipJoints.part_box] and [method ShipJoints.pair_state] rather than introducing a
## second overlap predicate. Two disagreeing definitions of "these parts touch" — one here, one in
## joint discovery — would be a genuine bug source, and the player would meet it as a joint that
## exists but an island that does not.
##
## Union-find over the part set. Ordering is deterministic: islands are sorted largest first with
## ties broken by their lowest part id, and the ids inside each island are sorted, so the report is
## stable across runs. Determinism is a gate in this project, not a nicety.
static func _islands_of(sdf: ShipSdf, cfg: ShipConfig) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	if sdf == null or cfg == null:
		return out
	var count: int = sdf.part_count()
	if count <= 0:
		return out

	# EXACT boxes, not probed ones. ShipJoints.part_box() samples the field on a grid spanning the
	# whole ship, so its accuracy falls as the ship grows; with symmetry on it missed every part
	# and reported a ship of N parts as N separate islands. ShipSdf.part_aabb() is the box the
	# build already computed from the part's own transform.
	var boxes: Array[AABB] = []
	for i: int in count:
		boxes.append(sdf.part_aabb(i).abs())

	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(count)
	for i: int in count:
		parent[i] = i

	var thickness: float = absf(cfg.hull_thickness_m)
	for a: int in count:
		for b: int in range(a + 1, count):
			# AABB pre-pass first: the pair probe is a triple loop and must not run for pairs
			# that cannot possibly touch.
			if not boxes[a].intersects(boxes[b]):
				continue
			var region: AABB = boxes[a].intersection(boxes[b])
			if region.size.x <= 0.0 or region.size.y <= 0.0 or region.size.z <= 0.0:
				continue
			var state: Dictionary = ShipJoints.pair_state(
				sdf, a, b, region, thickness, ISLAND_PAIR_STEPS
			)
			if bool(state.get("overlaps", false)):
				_union(parent, a, b)

	var groups: Dictionary = {}
	for i: int in count:
		var root: int = _find(parent, i)
		if not groups.has(root):
			groups[root] = PackedStringArray()
		var ids: PackedStringArray = groups[root]
		ids.append(sdf.part_id_at(i))
		groups[root] = ids

	for key: Variant in groups:
		var ids: PackedStringArray = groups[key]
		ids.sort()
		out.append(ids)

	# Largest first; ties by lowest id so the order cannot drift between runs.
	out.sort_custom(
		func(x: PackedStringArray, y: PackedStringArray) -> bool:
			if x.size() != y.size():
				return x.size() > y.size()
			var xs: String = x[0] if x.size() > 0 else ""
			var ys: String = y[0] if y.size() > 0 else ""
			return xs < ys
	)
	return out


static func _find(parent: PackedInt32Array, i: int) -> int:
	var root: int = i
	while parent[root] != root:
		root = parent[root]
	# Path compression, so a long chain does not make later lookups quadratic.
	var walk: int = i
	while parent[walk] != root:
		var next: int = parent[walk]
		parent[walk] = root
		walk = next
	return root


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra == rb:
		return
	# Attach the higher root to the lower so the representative is stable.
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb
