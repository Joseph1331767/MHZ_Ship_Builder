class_name ShipConfig
extends RefCounted

## Every dev lever in one record — SPEC section 8, API_CONTRACT section 3.
##
## Loaded from `data/tuning.json` by [ShipData]. The field defaults below ARE the
## shipped defaults: [method defaults] just hands back a fresh instance, so there is
## exactly one place a default is written down.
##
## [b]Every field must appear in [method snapshot].[/b] A lever missing from the snapshot
## means a bake report does not record what produced it, which makes the report a lie.

## Keys accepted for [member max_cost] and friends when a tuning file spells infinity
## out rather than using a JSON number.
const INF_TOKENS: Array = ["inf", "+inf", "infinity", "+infinity"]
const NEG_INF_TOKENS: Array = ["-inf", "-infinity"]

## Per-axis bounding box cap in metres. Per-axis, not diagonal: a 200 x 20 x 200 hull is
## legal where a 78 m cube is not.
var max_bbox_m: Vector3 = Vector3(250.0, 120.0, 250.0)

## Cap on the volume enclosed by the -hull_thickness_m level set.
var max_internal_volume_m3: float = 60000.0

## Cap on shell weight. See [member areal_density_kg_m2].
var max_weight_kg: float = 4.0e6

## Infinite in Phase 1: cost is displayed and gauged, never blocking.
var max_cost: float = INF

## Shell mass model: weight_kg = surface_area_m2 * areal_density_kg_m2. When
## MHZ_Materials plugs in this becomes thickness * material.density and the formula
## does not change.
var areal_density_kg_m2: float = 120.0

## Hull shell thickness. The interior isosurface is the -hull_thickness_m level set.
var hull_thickness_m: float = 0.4

## Voxel edge for the surface-nets bake grid.
var bake_cell_m: float = 0.25

## Voxel edge for the (coarser, cheaper) metrics sampling grid.
var metrics_cell_m: float = 0.5

## Input quantization. What is stored is exactly what is displayed, so snapping happens
## at input time and never at resolve time.
var snap_deg: float = 0.5
var snap_m: float = 0.05
var snap_scale: float = 0.05

## Tie-break order when two budgets max out at once. Entries are the keys produced by
## [method ShipBudgets.budget_key]; earlier wins.
var budget_priority: PackedStringArray = PackedStringArray(["weight", "volume", "bbox", "cost"])

## Central-difference step for SDF gradients (the mount normal, and bake normals).
var gradient_eps: float = 1.0e-4

## Sphere-trace hit threshold, in metres.
var trace_epsilon: float = 1.0e-5

## Sphere-trace iteration cap. Domain-warped fields converge slowly; this is the
## backstop that keeps a bad shape from hanging the resolve.
var trace_max_steps: int = 128

## Per-axis part scale clamp.
var part_scale_min: float = 0.05
var part_scale_max: float = 50.0

## Complexity ceiling — API_CONTRACT_SPORE section 5/6. This is the gate Spore actually
## enforces (SPORE_CLONE_SPEC section 5 constraint 2).
##
## [b]148.0 is a stand-in, not a researched figure.[/b] The UFO editor's own cap is
## confirmed to exist and to be configured independently of the other editors, but its
## numeric value is unpublished anywhere reachable — four research passes found nothing.
## 148 is the documented CREATURE cap (138 base, 148 outfitted), borrowed here purely so
## the lever has a defensible starting number. Retuning it is free: it is a range gate on
## input, never an input to the hash (AGENTS section 8b).
##
## A cap of INF, NAN or <= 0 means "unbounded" — the same convention [ShipBudgets] uses.
var max_complexity: float = 148.0

## Minimum part records required to save or upload — SPORE_CLONE_SPEC section 5
## constraint 1. Counts records in [member ShipDoc.parts], not the mirrored twins
## [ShipSymmetry] generates from them: a twin is derived, so a "2 parts plus symmetry"
## ship is a two-part ship on disk and is refused.
var min_parts_to_save: int = 3

## Half-width, in metres, of the band around the symmetry plane inside which a part is
## treated as sitting ON the plane and therefore generates no mirrored twin (and is not
## billed the symmetry doubling). The document root always lands here.
var symmetry_plane_epsilon: float = 0.01

## Radius, in metres, within which a dragged part snaps to a parent's snap target
## ([SnapTargets.nearest]). Beyond it the placement stays free-form.
var snap_tolerance_m: float = 0.35

## Widest bounding-box axis, in metres, a freshly founded ROOT part is scaled to
## ([method ShipDoc.create_new]). Without it the first part's size came from whichever
## `base_size` its family happened to author, so founding on a sphere gave a 2 m ship and
## founding on a torus a 4 m one, and the player's sense of scale depended on which icon they
## clicked. Every other part is still sized by hand from here.
var root_span_m: float = 5.0

## Default INTERIOR span, in metres, of a template room module - the widest axis of the primitive
## a room is built from. 3 m is "a person can barely fit", which is the cramped, modular,
## non-futuristic read the whole game is after.
var room_span_m: float = 3.0

## Default outside diameter, in metres, of a template hallway. 1 m is a crawl-through: shoulders
## touching, which is the point.
var tunnel_bore_m: float = 1.0

## Default length, in metres, of a template hallway between two room modules, measured centre to
## centre of the rooms it joins minus their radii - i.e. the open run a crew member crawls.
var tunnel_length_m: float = 2.0

## How deep a NEWLY PLACED part is sunk into its parent: the part's lowest point ends up this
## far below the parent's surface. This is the DEFAULT `offset` a new part is written with, not
## a change to what `offset` means - 0 is still flush, and a part seated flush on a curved
## parent touches it at a single point, "theres no real connection". Keep it above twice
## hull_thickness_m so the two interiors meet through the join. See
## [method ShipAttach.default_offset].
var attach_embed_m: float = 0.45
## Cap on that depth as a fraction of the part's own height, so a thin plate is not buried.
var attach_embed_max_fraction: float = 0.5

## Clear width and height, in metres, of the plain DOORWAY cut into a seam wall between two
## rooms linked without a hatch (ShipJoint.MODE_DOORWAY, ADR 0008). Centred on the seam.
var doorway_width_m: float = 0.8
var doorway_height_m: float = 1.9

## EXPLODE view: the fixed gap, in metres, each module is pulled away from the module it stands
## on, along its own seam normal, on top of half its extent along that normal
## ([method ShipSeams.explode_offsets]).
var explode_gap_m: float = 1.5
## Grid resolution the exploded modules are baked at, as cells across the module's longest axis.
## A preview, not the bake: coarse enough that a ten-module ship explodes in seconds.
## Total enclosed volume a TEMPLATE ship is built to, in cubic metres, shared out across every
## body it has (ADR 0014). The same for every class: a hydrogen ship spends all of it on one
## module, a helium ship halves it between two, an argon ship splits it sixteen ways. That is what
## makes the classes read as different SHAPES rather than as different sizes - "keep default total
## volume constant acrost all class ships".
##
## Tunnels are not counted against it. They are structure between the bodies rather than volume a
## crew lives in, and their size comes from tunnel_bore_m and tunnel_length_m.
var template_volume_m3: float = 8000.0

var explode_cells_per_axis: int = 32


## A fresh config carrying the shipped defaults.
static func defaults() -> ShipConfig:
	return ShipConfig.new()


## Reads a tuning dictionary, falling back to the default for any lever it does not
## mention. Unknown keys are ignored, so `data/tuning.json` may carry descriptions and
## schema references alongside the levers.
##
## Levers may sit at the top level or one level down inside a grouping dictionary
## (`{"budgets": {"max_weight_kg": ...}}`), because grouping a tuning file by topic is
## the obvious thing for an author to do and should not silently lose values.
static func from_dict(d: Dictionary) -> ShipConfig:
	var c: ShipConfig = ShipConfig.new()
	c.max_bbox_m = _as_vec3(_lookup(d, "max_bbox_m"), c.max_bbox_m)
	c.max_internal_volume_m3 = _as_float(
		_lookup(d, "max_internal_volume_m3"), c.max_internal_volume_m3
	)
	c.max_weight_kg = _as_float(_lookup(d, "max_weight_kg"), c.max_weight_kg)
	c.max_cost = _as_float(_lookup(d, "max_cost"), c.max_cost)
	c.areal_density_kg_m2 = _as_float(_lookup(d, "areal_density_kg_m2"), c.areal_density_kg_m2)
	c.hull_thickness_m = _as_float(_lookup(d, "hull_thickness_m"), c.hull_thickness_m)
	c.bake_cell_m = _as_float(_lookup(d, "bake_cell_m"), c.bake_cell_m)
	c.metrics_cell_m = _as_float(_lookup(d, "metrics_cell_m"), c.metrics_cell_m)
	c.snap_deg = _as_float(_lookup(d, "snap_deg"), c.snap_deg)
	c.snap_m = _as_float(_lookup(d, "snap_m"), c.snap_m)
	c.snap_scale = _as_float(_lookup(d, "snap_scale"), c.snap_scale)
	c.budget_priority = _as_string_array(_lookup(d, "budget_priority"), c.budget_priority)
	c.gradient_eps = _as_float(_lookup(d, "gradient_eps"), c.gradient_eps)
	c.trace_epsilon = _as_float(_lookup(d, "trace_epsilon"), c.trace_epsilon)
	c.trace_max_steps = _as_int(_lookup(d, "trace_max_steps"), c.trace_max_steps)
	c.part_scale_min = _as_float(_lookup(d, "part_scale_min"), c.part_scale_min)
	c.part_scale_max = _as_float(_lookup(d, "part_scale_max"), c.part_scale_max)
	c.max_complexity = _as_float(_lookup(d, "max_complexity"), c.max_complexity)
	c.min_parts_to_save = _as_int(_lookup(d, "min_parts_to_save"), c.min_parts_to_save)
	c.symmetry_plane_epsilon = _as_float(
		_lookup(d, "symmetry_plane_epsilon"), c.symmetry_plane_epsilon
	)
	c.snap_tolerance_m = _as_float(_lookup(d, "snap_tolerance_m"), c.snap_tolerance_m)
	c.root_span_m = _as_float(_lookup(d, "root_span_m"), c.root_span_m)
	c.room_span_m = _as_float(_lookup(d, "room_span_m"), c.room_span_m)
	c.tunnel_bore_m = _as_float(_lookup(d, "tunnel_bore_m"), c.tunnel_bore_m)
	c.tunnel_length_m = _as_float(_lookup(d, "tunnel_length_m"), c.tunnel_length_m)
	c.attach_embed_m = _as_float(_lookup(d, "attach_embed_m"), c.attach_embed_m)
	c.attach_embed_max_fraction = _as_float(
		_lookup(d, "attach_embed_max_fraction"), c.attach_embed_max_fraction
	)
	c.doorway_width_m = _as_float(_lookup(d, "doorway_width_m"), c.doorway_width_m)
	c.doorway_height_m = _as_float(_lookup(d, "doorway_height_m"), c.doorway_height_m)
	c.explode_gap_m = _as_float(_lookup(d, "explode_gap_m"), c.explode_gap_m)
	c.template_volume_m3 = _as_float(_lookup(d, "template_volume_m3"), c.template_volume_m3)
	c.explode_cells_per_axis = _as_int(
		_lookup(d, "explode_cells_per_axis"), c.explode_cells_per_axis
	)
	return c


## Every lever, in a plain JSON-shaped dictionary, for bake and validation reports.
##
## [method from_dict] accepts what this emits, so `from_dict(cfg.snapshot())` round-trips.
## Vector3 and PackedStringArray are flattened to arrays so the snapshot survives
## [method JSON.stringify] unchanged.
func snapshot() -> Dictionary:
	return {
		"max_bbox_m": [max_bbox_m.x, max_bbox_m.y, max_bbox_m.z],
		"max_internal_volume_m3": max_internal_volume_m3,
		"max_weight_kg": max_weight_kg,
		"max_cost": max_cost,
		"areal_density_kg_m2": areal_density_kg_m2,
		"hull_thickness_m": hull_thickness_m,
		"bake_cell_m": bake_cell_m,
		"metrics_cell_m": metrics_cell_m,
		"snap_deg": snap_deg,
		"snap_m": snap_m,
		"snap_scale": snap_scale,
		"budget_priority": _priority_as_array(),
		"gradient_eps": gradient_eps,
		"trace_epsilon": trace_epsilon,
		"trace_max_steps": trace_max_steps,
		"part_scale_min": part_scale_min,
		"part_scale_max": part_scale_max,
		"max_complexity": max_complexity,
		"min_parts_to_save": min_parts_to_save,
		"symmetry_plane_epsilon": symmetry_plane_epsilon,
		"snap_tolerance_m": snap_tolerance_m,
		"root_span_m": root_span_m,
		"room_span_m": room_span_m,
		"tunnel_bore_m": tunnel_bore_m,
		"tunnel_length_m": tunnel_length_m,
		"attach_embed_m": attach_embed_m,
		"attach_embed_max_fraction": attach_embed_max_fraction,
		"doorway_width_m": doorway_width_m,
		"doorway_height_m": doorway_height_m,
		"explode_gap_m": explode_gap_m,
		"template_volume_m3": template_volume_m3,
		"explode_cells_per_axis": explode_cells_per_axis,
	}


# --- internals ---------------------------------------------------------------------


func _priority_as_array() -> Array:
	var out: Array = []
	var n: int = budget_priority.size()
	for i: int in n:
		out.append(budget_priority[i])
	return out


## Direct hit first, then one level of nesting. Nested dictionaries are visited in
## sorted key order so that two tuning files with the same content always resolve the
## same lever, whatever order the author wrote the groups in.
static func _lookup(d: Dictionary, key: String) -> Variant:
	if d.has(key):
		return _unwrap(d[key])
	var names: PackedStringArray = PackedStringArray()
	var values: Dictionary = {}
	for k: Variant in d:
		var name: String = str(k)
		if not values.has(name):
			names.append(name)
		values[name] = d[k]
	names.sort()
	var n: int = names.size()
	for i: int in n:
		var sub: Variant = values[names[i]]
		if sub is Dictionary:
			var sd: Dictionary = sub
			if sd.has(key):
				return _unwrap(sd[key])
	return null


## Unwrap the annotated-lever form `{"value": X, "description": ..., "min": ..., "max": ...}`
## down to X.
##
## `data/tuning.json` stores every lever this way so a dev slider has its own bounds and a
## human reading the pack learns what the lever does (AGENTS: the data packs are documentation).
## Without this, every `_as_*` coercer below is handed a Dictionary, matches none of its accepted
## types, and returns the caller-supplied default — so the whole tuning file loads cleanly and is
## then silently ignored. That is exactly what happened before this function existed: all 17
## levers fell back to their code defaults with nothing logged and nothing thrown.
##
## `min`/`max` here are dev-slider bounds, NOT the value, so the unwrap keys on `value` alone.
## A lever whose value is legitimately a dictionary would need a different shape; none is.
static func _unwrap(v: Variant) -> Variant:
	if v is Dictionary:
		var vd: Dictionary = v
		if vd.has("value"):
			return vd["value"]
	return v


static func _as_float(v: Variant, def: float) -> float:
	if v is float:
		var f: float = v
		return f
	if v is int:
		var i: int = v
		return float(i)
	if v is String:
		var s: String = v
		var low: String = s.strip_edges().to_lower()
		if INF_TOKENS.has(low):
			return INF
		if NEG_INF_TOKENS.has(low):
			return -INF
		if low.is_valid_float():
			return low.to_float()
	return def


static func _as_int(v: Variant, def: int) -> int:
	if v is int:
		var i: int = v
		return i
	if v is float:
		var f: float = v
		if is_finite(f):
			return int(round(f))
		return def
	if v is String:
		var s: String = v
		if s.strip_edges().is_valid_int():
			return s.strip_edges().to_int()
	return def


static func _as_vec3(v: Variant, def: Vector3) -> Vector3:
	if v is Vector3:
		var v3: Vector3 = v
		return v3
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Vector3(_as_float(a[0], def.x), _as_float(a[1], def.y), _as_float(a[2], def.z))
	if v is Dictionary:
		var d: Dictionary = v
		return Vector3(
			_as_float(d.get("x", null), def.x),
			_as_float(d.get("y", null), def.y),
			_as_float(d.get("z", null), def.z)
		)
	return def


static func _as_string_array(v: Variant, def: PackedStringArray) -> PackedStringArray:
	if v is PackedStringArray:
		var p: PackedStringArray = v
		return p.duplicate()
	if v is Array:
		var a: Array = v
		var out: PackedStringArray = PackedStringArray()
		var n: int = a.size()
		for i: int in n:
			out.append(str(a[i]))
		return out
	return def.duplicate()
