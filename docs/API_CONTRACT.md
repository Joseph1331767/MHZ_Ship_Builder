# API CONTRACT — pinned before parallel implementation

**This file is frozen for the duration of M1–M6.** Every agent codes against these exact names and
signatures. If you believe a signature is wrong, say so in your report — **do not change it
unilaterally**, because three other agents are compiling against it right now.

Companion to `docs/SHIP_BUILDER_SPEC.md`. The spec says *why*; this says *exactly what to type*.

## Global rules

- Godot 4.7, GDScript, **strict static typing**. Every var and every signature typed. Warnings are
  errors (`untyped_declaration=2`).
- `core/` is pure data: **no `Node`, no `SceneTree`, no `@onready`, no signals, no `await`, and no
  `res://` access outside `ShipData`.** Everything in `core/` is `RefCounted` or a static-only class.
- All `core/` classes carry a `class_name`. Adding one requires
  `& $env:GODOT_BIN --headless --path . --import` before anything can see it.
- Angles are **degrees** at every API boundary. Convert to radians inside a function, never across
  one.
- Distances are **metres**. Godot is Y-up.
- Never mutate an argument. Return new values.

---

## 1. `core/util/ship_canonical.gd` — `class_name ShipCanonical`

The determinism contract. **Do not change without a ruleset bump and an ADR.**

```gdscript
static func quantize(f: float) -> float                       # round to 6 dp, kills float noise
static func canonical_json(v: Variant) -> String              # sorted keys, quantized floats, no spaces
static func fnv1a_64(s: String) -> int                        # 64-bit FNV-1a, returns signed int
static func sub_seed(seed: int, stream: String) -> int        # derive an independent sub-stream
static func rand_range_from(seed: int, lo: float, hi: float) -> float   # deterministic, no RNG state
```

---

## 2. `core/ship_hash.gd` — `class_name ShipHash`

```gdscript
static func shape_seed(family_id: String, manufacturer_id: String,
                       params: Dictionary, ruleset: String) -> int
static func doc_hash(doc: ShipDoc) -> String                  # hex, for save integrity + tests
```

---

## 3. `core/ship_config.gd` — `class_name ShipConfig` (RefCounted)

Every lever from SPEC section 8. **Every field must appear in `snapshot()`.**

```gdscript
var max_bbox_m: Vector3
var max_internal_volume_m3: float
var max_weight_kg: float
var max_cost: float
var areal_density_kg_m2: float
var hull_thickness_m: float
var bake_cell_m: float
var metrics_cell_m: float
var snap_deg: float
var snap_m: float
var snap_scale: float
var budget_priority: PackedStringArray      # e.g. ["weight","volume","bbox","cost"]
var gradient_eps: float
var trace_epsilon: float
var trace_max_steps: int
var part_scale_min: float
var part_scale_max: float

static func defaults() -> ShipConfig
static func from_dict(d: Dictionary) -> ShipConfig
func snapshot() -> Dictionary
```

---

## 4. `core/ship_data.gd` — `class_name ShipData` (RefCounted)

**The only class in `core/` permitted to touch `res://`.**

```gdscript
var families: Dictionary          # family_id -> Dictionary (raw pack entry)
var manufacturers: Dictionary     # manufacturer_id -> Dictionary
var hatches: Dictionary           # hatch_id -> Dictionary
var palette: Dictionary           # raw palette pack
var config: ShipConfig
var load_errors: PackedStringArray

func load_all(base_path: String = "res://data") -> bool
func family_ids() -> PackedStringArray
func manufacturer_ids() -> PackedStringArray
func manufacturers_for(family_id: String) -> PackedStringArray
func has_family(family_id: String) -> bool
```

---

## 5. `core/shapes/resolved_shape.gd` — `class_name ResolvedShape` (RefCounted)

The hot path. **A concrete class with a concrete `sdf()` — no virtual dispatch, no interfaces.**
`sdf()` is called millions of times per bake; keep it allocation-free.

```gdscript
enum Base { BOX, SPHERE, CYLINDER, CONE, CAPSULE, TORUS }

var base: int                 # Base enum
var size: Vector3             # box half-extents / (radius, half_height, _) / (major_r, minor_r, _)
var round_r: float
var taper: float
var twist_deg: float
var rib_count: int
var rib_amp: float
var rib_phase: float
var scallop_amp: float
var scallop_freq: float
var scallop_phase: float
var lipschitz: float          # >= 1.0, divides the sphere-trace step
var origin_inside: bool
var bound_radius: float

func sdf(p: Vector3) -> float          # ops applied in SPEC section 4 order, exactly
func local_aabb() -> AABB
func mount_inset() -> float            # origin -> attach face along local -Y
```

---

## 6. `core/sdf/sdf_prims.gd` — `class_name SdfPrims` (static only)

Standard analytic forms. All take **shape-local** `p`.

```gdscript
static func box(p: Vector3, half: Vector3) -> float
static func sphere(p: Vector3, r: float) -> float
static func cylinder(p: Vector3, r: float, half_h: float) -> float
static func cone(p: Vector3, r: float, half_h: float) -> float        # apex +Y, base -Y
static func capsule(p: Vector3, r: float, half_h: float) -> float
static func torus(p: Vector3, major_r: float, minor_r: float) -> float # ring in XZ, axis +Y
```

## 7. `core/sdf/sdf_ops.gd` — `class_name SdfOps` (static only)

```gdscript
static func taper(p: Vector3, amount: float, half_h: float) -> Vector3   # domain warp
static func twist(p: Vector3, deg_per_m: float) -> Vector3               # domain warp
static func inflate(d: float, r: float) -> float                         # d - r
static func rib_disp(p: Vector3, count: int, amp: float, phase: float, half_h: float) -> float
static func scallop_disp(p: Vector3, amp: float, freq: float, phase: float) -> float
static func smooth_min(a: float, b: float, k: float) -> float            # polynomial; k<=0 -> min()
static func lipschitz_for(taper_amt: float, twist_deg: float, scale: Vector3) -> float
```

---

## 8. `core/shapes/shape_gen.gd` — `class_name ShapeGen` (static only)

Manufacturer narrows family ranges. Seed drives **micro-detail only** (rib phase, scallop phase,
sub-range jitter within authored detail bounds) — never anything the player set.

```gdscript
static func effective_ranges(data: ShipData, family_id: String, manufacturer_id: String) -> Dictionary
static func default_params(data: ShipData, family_id: String, manufacturer_id: String) -> Dictionary
static func clamp_params(data: ShipData, family_id: String, manufacturer_id: String,
                         params: Dictionary) -> Dictionary
static func resolve(data: ShipData, family_id: String, manufacturer_id: String,
                    params: Dictionary, scale: Vector3) -> ResolvedShape
static func param_complexity(data: ShipData, family_id: String, params: Dictionary) -> float
```

---

## 9. `core/ship_part.gd` — `class_name ShipPart` (RefCounted, pure record)

```gdscript
var id: String
var parent: String            # "" for root
var kind: String              # "primitive" | "component_instance"
var family: String            # family id, or component definition id when kind is component_instance
var manufacturer: String
var params: Dictionary
var yaw: float
var pitch: float
var rot: Vector3   # RETIRED(ADR 0004, 2026-08-31): was `var roll: float`.
                   # Degrees per axis in the MOUNT FRAME, whose +Z IS the placement normal.
                   # rot.z is the old `roll` (spin on the surface); rot.x / rot.y tilt off it.
                   # On disk: "attach": { ..., "rot": [x, y, z] }. A legacy scalar "roll"
                   # is still READ into rot.z, never written.
var offset: float
var scale: Vector3
var blend: float
var mirror_source: String     # "" = not a mirror
var mirror_plane: String      # "" | "x" | "y" | "z"
var display_name: String
var locked: bool
var material_ref: String      # RESERVED, Phase 2
var role: String              # RESERVED, Phase 3: "" | "structural" | "greeble" | "mount"

static func from_dict(id: String, d: Dictionary) -> ShipPart
func to_dict() -> Dictionary
func is_mirror() -> bool
func duplicate_part() -> ShipPart
```

## 10. `core/ship_joint.gd` — `class_name ShipJoint` (RefCounted)

```gdscript
var id: String
var a: String                 # always lexicographically < b
var b: String
var mode: String              # "open" | "hatched" | "sealed"
var hatch_family: String
var hatch_manufacturer: String
var hatch_params: Dictionary

static func from_dict(id: String, d: Dictionary) -> ShipJoint
func to_dict() -> Dictionary
```

---

## 11. `core/ship_doc.gd` — `class_name ShipDoc` (RefCounted)

```gdscript
const FORMAT: String = "mhz_ship"
const VERSION: int = 1
const RULESET_VERSION: String = "1.0.0"

var units: String
var root: String
var settings: Dictionary
var parts: Dictionary         # String -> ShipPart
var joints: Dictionary        # String -> ShipJoint
var components: Dictionary    # String -> Dictionary {label, root, parts}

static func create_new(family_id: String, manufacturer_id: String, data: ShipData) -> ShipDoc
static func from_dict(d: Dictionary) -> ShipDoc
func to_dict() -> Dictionary
func duplicate_doc() -> ShipDoc

func new_part_id() -> String              # "p_0001", monotonic, never reused
func new_joint_id() -> String             # "j_0001"
func add_part(part: ShipPart) -> String
func remove_part(id: String) -> PackedStringArray     # returns every removed id (subtree)
func children_of(id: String) -> PackedStringArray
func descendants_of(id: String) -> PackedStringArray  # depth-first, excludes id itself
func ancestors_of(id: String) -> PackedStringArray
func part_order() -> PackedStringArray                # deterministic: root first, then DFS by id
static func joint_key_for(a: String, b: String) -> String   # sorted pair -> "a|b"
```

---

## 12. `core/attach/ship_attach.gd` — `class_name ShipAttach` (static only)

Implements SPEC section 3 **exactly**. This is the most-tested code in the project.

```gdscript
static func direction_from_angles(yaw_deg: float, pitch_deg: float) -> Vector3
static func angles_from_direction(dir: Vector3) -> Vector2     # returns (yaw_deg, pitch_deg)
static func trace_surface(shape: ResolvedShape, dir: Vector3, cfg: ShipConfig) -> Vector3
static func gradient(shape: ResolvedShape, p: Vector3, eps: float) -> Vector3
static func mount_basis(shape: ResolvedShape, p: Vector3, normal: Vector3,
                        rot: Vector3) -> Basis   # RETIRED(ADR 0004, 2026-08-31): was roll_deg: float
static func mount_frame(normal: Vector3) -> Basis   # +Z = N, +Y = tangent, +X = Y x Z
static func local_transform(parent_shape: ResolvedShape, child_shape: ResolvedShape,
                            part: ShipPart, cfg: ShipConfig) -> Transform3D
static func resolve_all(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary
    # part_id -> Transform3D in SHIP space. Includes generated mirror derivatives.
static func resolve_shapes(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary
    # part_id -> ResolvedShape. Computed once, reused by attach / sdf / metrics / bake.
```

---

## 13. `core/sdf/ship_sdf.gd` — `class_name ShipSdf` (RefCounted)

```gdscript
static func build(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> ShipSdf
func sample(p: Vector3) -> float          # p in SHIP space
func gradient(p: Vector3, eps: float) -> Vector3
func aabb() -> AABB                        # union of transformed part AABBs
func part_count() -> int
func part_id_at(index: int) -> String
func sample_part(index: int, p: Vector3) -> float
```

---

## 14. `core/ship_validate.gd` — `class_name ShipValidate` (static only)

```gdscript
static func validate(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Array[Dictionary]
    # each entry: { "severity": "error"|"warn", "code": String,
    #               "part": String, "message": String }
```

Required codes: `no_root`, `orphan_part`, `cycle`, `unknown_family`, `unknown_manufacturer`,
`param_out_of_range`, `scale_out_of_range`, `mirror_source_missing`, `mirror_of_mirror`,
`joint_part_missing`, `joint_not_overlapping`, `component_cycle`, `component_missing`,
`budget_exceeded`.

---

## 15. `core/metrics/ship_metrics.gd` — `class_name ShipMetrics` (RefCounted)

```gdscript
var bbox: AABB
var surface_area_m2: float
var solid_volume_m3: float
var internal_volume_m3: float
var weight_kg: float
var cost: float
var sample_cell_m: float

static func compute_bbox(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> AABB   # cheap, no grid
static func compute(sdf: ShipSdf, doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> ShipMetrics
static func compute_cost(doc: ShipDoc, data: ShipData) -> float
func to_dict() -> Dictionary
```

`weight_kg = surface_area_m2 * cfg.areal_density_kg_m2`.
`internal_volume_m3` = volume of the region where `sdf(p) < -cfg.hull_thickness_m`.

## 16. `core/metrics/ship_budgets.gd` — `class_name ShipBudgets` (static only)

```gdscript
enum Budget { BBOX, VOLUME, WEIGHT, COST }

static func usage(m: ShipMetrics, cfg: ShipConfig) -> Dictionary   # Budget -> float, 1.0 = at cap
static func violations(m: ShipMetrics, cfg: ShipConfig) -> Array[int]
static func top_violation(m: ShipMetrics, cfg: ShipConfig) -> int  # -1 none; honours budget_priority
static func budget_key(b: int) -> String                           # "bbox"|"volume"|"weight"|"cost"
```

---

## 17. `core/bake/surface_nets.gd` — `class_name SurfaceNets` (static only)

```gdscript
static func extract(sdf: ShipSdf, bounds: AABB, cell: float, iso: float) -> Dictionary
    # { "vertices": PackedVector3Array, "normals": PackedVector3Array,
    #   "indices": PackedInt32Array, "cells": int }
```

Naive Surface Nets: one vertex per sign-changing cell at the centroid of its edge crossings, quads
across cell faces, normals from the SDF gradient. **Isolate vertex placement in a single private
function `_place_vertex()`** so the documented QEF/Dual-Contouring upgrade is a one-function swap.

## 18. `core/bake/hull_bake.gd` — `class_name HullBake` (static only)

```gdscript
static func bake(sdf: ShipSdf, cfg: ShipConfig, iso: float) -> Dictionary
    # { "mesh": ArrayMesh, "tris": int, "verts": int,
    #   "area_m2": float, "volume_m3": float, "cells": int, "ms": int }
static func mesh_area(verts: PackedVector3Array, idx: PackedInt32Array) -> float
static func mesh_volume(verts: PackedVector3Array, idx: PackedInt32Array) -> float  # divergence theorem
```

---

## 19. `core/ship_mirror.gd` — `class_name ShipMirror` (static only)

```gdscript
static func plane_normal(plane: String) -> Vector3
static func reflect(t: Transform3D, plane: String) -> Transform3D
static func mirror_subtree(doc: ShipDoc, part_id: String, plane: String) -> PackedStringArray
static func break_link(doc: ShipDoc, part_id: String) -> PackedStringArray
static func derivative_ids(doc: ShipDoc) -> PackedStringArray
```

## 20. `core/ship_components.gd` — `class_name ShipComponents` (static only)

```gdscript
static func make_component(doc: ShipDoc, part_ids: PackedStringArray, label: String) -> String
static func instantiate(doc: ShipDoc, component_id: String, parent_id: String) -> String
static func make_unique(doc: ShipDoc, instance_id: String) -> String
static func expand(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary
    # flattened "instance_id/inner_id" -> { "shape": ResolvedShape, "xform": Transform3D }
static func check_cycles(doc: ShipDoc) -> PackedStringArray
```

## 21. `core/ship_joints.gd` — `class_name ShipJoints` (static only)

```gdscript
static func discover(doc: ShipDoc, sdf: ShipSdf, cfg: ShipConfig) -> Array[Dictionary]
    # candidate pairs: [{ "a": String, "b": String, "overlaps": bool, "merges": bool }]
static func cavities_merge(sdf: ShipSdf, ia: int, ib: int, thickness: float) -> bool
```

---

## 22. Harness (`harness/`) — may depend on `core/`, never the reverse

```gdscript
harness/dev_host.tscn                  # SubViewportContainer -> SubViewport(1280x800) -> ShipBuilder
harness/builder/ship_builder.gd        class_name ShipBuilder        (Control) — the app root
harness/builder/ship_view3d.gd         class_name ShipView3D         (SubViewport host for the 3D)
harness/builder/ship_scene_builder.gd  class_name ShipSceneBuilder   (doc -> MeshInstance3D tree)
harness/builder/orbit_camera.gd        class_name OrbitCamera        (Node3D)
harness/builder/ship_history.gd        class_name ShipHistory        (snapshot undo/redo)
harness/builder/ship_theme.gd          class_name ShipTheme          (palette -> Theme + shader)
harness/builder/ship_mesh_gen.gd       class_name ShipMeshGen        (ResolvedShape -> preview mesh)
harness/panels/                        # part palette, inspector, tree, gauges, dev overlay
shaders/palette_post.gdshader          # the 16-entry LUT quantizer + Bayer dither
```

**Undo is snapshot-based, not command-based.** `ShipHistory` stores `doc.to_dict()` snapshots with
a depth cap from tuning. A few hundred parts is a small dict; this is simpler than command objects
and cannot desynchronise.

```gdscript
# ship_history.gd
func push(doc: ShipDoc, label: String) -> void
func undo() -> ShipDoc      # returns null when empty
func redo() -> ShipDoc
func can_undo() -> bool
func can_redo() -> bool
func clear() -> void
```

---

## 23. Tools (`tools/`) — headless entry points

```
tools/ship_selfcheck.gd         parse + determinism smoke
tools/ship_validate_data.gd     data/ packs are schema-clean, every description real
tools/ship_bake_cli.gd          bake a ship file, write a report to reports/
tools/ship_run.ps1              wrapper that FAILS the run on any runtime error (AGENTS 2a)
```

---

## 24. Test layout (`tests/`, gdUnit4)

```
tests/core/test_canonical.gd      quantize/canonical_json/fnv1a stability
tests/core/test_hash.gd           same params -> same seed, forever (determinism gate)
tests/core/test_sdf_prims.gd      known point -> known distance, per primitive
tests/core/test_shape_gen.gd      manufacturer clamping, default params, param->shape stability
tests/core/test_attach.gd         known (yaw,pitch,rot,offset) -> known Transform3D, per shape
tests/core/test_doc.gd            tree ops, id monotonicity, JSON round-trip
tests/core/test_validate.gd       every error code fires on a crafted doc
tests/core/test_mirror.gd         reflection correctness, break_link, no mirror-of-mirror
tests/core/test_components.gd     make/instantiate/make_unique/cycle detection
tests/core/test_metrics.gd        analytic solids: sphere/box volume + area within tolerance
tests/core/test_bake.gd           bake a unit sphere, check area/volume within tolerance
```

**The determinism tests are a gate, not a feature.** A doc that hashed to X today must hash to X
forever under its recorded ruleset version.
