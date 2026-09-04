# API CONTRACT — Spore-clone rework (Phase 1b)

**FROZEN.** Companion to `docs/API_CONTRACT.md` and `docs/API_CONTRACT_UI.md`. Mechanics and
sources are in `docs/SPORE_CLONE_SPEC.md` — read that first; it says *why*, this says *what to type*.

If a signature here is wrong, **report it, do not change it** — several agents compile against it
simultaneously. And note the lesson that cost this project real time (`FOLLOWUPS.md` F0): pinning a
field NAME without its VALUE SHAPE is what produces silent, un-erroring cross-module bugs. Every
dictionary below states its keys and their types. Honour them exactly.

## The four decisions this contract encodes

1. **Both gates hard-block.** Complexity AND the physical budgets can each refuse an edit. Every
   refusal must name which gate refused it.
2. **Parts may float.** A parentless part is legal and saves. The BAKE reports disconnected islands.
3. **Procedural shapes keep their snap points.** SDF families gain computed snap targets; we clone
   Spore's snap MECHANIC without an authored mesh catalog.
4. Everything ships in one pass.

---

## 1. `core/shapes/snap_targets.gd` — `class_name SnapTargets` (static only)

Spore snaps to typed targets (parent centre / authored snap vectors / editor centreline), never to
the raw cursor. We derive the equivalent from each family's SDF.

**A snap target is a Dictionary with EXACTLY these keys:**

```gdscript
{
    "id": String,          # stable within a family: "face_+x", "pole_+y", "rim_0" ... 
                           # IMMUTABLE once shipped - it is stored in the doc.
    "local_pos": Vector3,  # on the UNSCALED shape surface, in shape-local space
    "normal": Vector3,     # unit, outward
    "kind": String,        # "face" | "pole" | "rim" | "center"
}
```

```gdscript
## Snap targets for a resolved shape, in shape-local space, UNSCALED.
## Deterministic: same shape in, same array out, same order. Order is part of the contract
## because ids are generated from it.
static func for_shape(shape: ResolvedShape) -> Array[Dictionary]

## Nearest target to a shape-local point, or {} when none is within `tolerance` metres.
static func nearest(shape: ResolvedShape, local_point: Vector3, tolerance: float) -> Dictionary

## Scale a target's local_pos/normal into the part's scaled local frame.
static func apply_scale(target: Dictionary, scale: Vector3) -> Dictionary
```

Per base primitive, generate at least: BOX -> 6 face centres + 8 corners; SPHERE -> 6 axis poles;
CYLINDER/CONE/CAPSULE -> 2 end poles + a rim ring of `RIM_SEGMENTS` (**8**, fixed) around the widest
circumference; TORUS -> 8 around the major ring. Plus `"center"` at the origin for every shape
(Spore's `SnapToParentCenter`).

---

## 2. `core/ship_part.gd` — `class_name ShipPart` ADDITIONS

Existing fields keep their meaning. New:

```gdscript
## "" = attached via yaw/pitch/rot/offset to `parent` (the existing path).
## Non-empty = snapped to that snap-target id on the parent. Attach angles are then DERIVED
## from the target, not authored, and yaw/pitch are ignored on load.
var snap_id: String = ""

## Spore allows floating parts (bodies "require no base"). When `parent` is "" and this part is
## NOT the doc root, this transform positions it in ship space directly.
## SERIALIZED AS A FLAT ARRAY OF 12 FLOATS: basis.x.xyz, basis.y.xyz, basis.z.xyz, origin.xyz.
var absolute: Transform3D = Transform3D.IDENTITY

## SYMMETRY IS ON BY DEFAULT (Spore 2008 behaviour). false = this part is mirrored.
## true = the player broke symmetry on it (hold A). Breaking CASCADES to descendants -
## use ShipSymmetry.is_effectively_asymmetric(), never read this field alone.
var asymmetric: bool = false

## Paint state. Keys are region ids from the family's `paint_regions`; values are:
##   { "color": int (index into the active palette), "texture": String (texture id or "") }
var paint: Dictionary = {}
```

**RETIRED:** `mirror_source` / `mirror_plane` as the primary mirroring mechanism. They stay on the
record for loading old files but `ShipSymmetry` is now authoritative. Do not write them.

## 3. `core/ship_doc.gd` — ADDITIONS

```gdscript
## "x" | "y" | "z" | "" (off). Default "x" - bilateral, on by default, like Spore.
var symmetry_plane: String = "x"

## Parts with no parent that are not the root. Legal; the baker reports them as islands.
func floating_part_ids() -> PackedStringArray
```

---

## 4. `core/ship_symmetry.gd` — `class_name ShipSymmetry` (static only) — REPLACES ShipMirror's role

```gdscript
## True when `part_id` or ANY ancestor is marked asymmetric. This is the cascade.
static func is_effectively_asymmetric(doc: ShipDoc, part_id: String) -> bool

## Set the flag on one part. Returns every id whose effective state changed (the subtree).
static func set_asymmetric(doc: ShipDoc, part_id: String, value: bool) -> PackedStringArray

## Would this part generate a mirrored twin? False when asymmetric, when symmetry_plane is "",
## or when the part sits ON the plane within `ShipConfig.symmetry_plane_epsilon`.
static func generates_twin(doc: ShipDoc, part_id: String, xform: Transform3D,
                           cfg: ShipConfig) -> bool

## Derivative id for a mirrored twin. FORMAT IS FIXED: "<source_id>~m".
static func twin_id(source_id: String) -> String
static func is_twin_id(id: String) -> bool
static func source_of_twin(twin: String) -> String
```

`ShipMirror.reflect()` stays as the transform maths. Everything else in `ShipMirror` is superseded.

---

## 5. `core/ship_complexity.gd` — `class_name ShipComplexity` (static only)

Spore's real gate. Per-part cost, **doubled for a symmetric part** (a mirrored pair costs twice —
breaking symmetry to halve the bill is a documented Spore exploit and must remain possible).

```gdscript
## { "used": float, "cap": float, "per_part": Dictionary }  # per_part: part_id -> float
static func compute(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary

## Cost of one part as placed, including the symmetry doubling.
static func cost_of(doc: ShipDoc, part_id: String, data: ShipData, cfg: ShipConfig) -> float

## Cost of adding a NEW part of this family/manufacturer, for the palette's red-out test.
static func cost_of_new(data: ShipData, family_id: String, symmetric: bool) -> float

## Would adding it fit? The palette greys/reddens entries where this is false.
static func can_afford(doc: ShipDoc, data: ShipData, cfg: ShipConfig,
                       family_id: String, symmetric: bool) -> bool
```

Family entries gain `"complexity": float` in `data/shapes/families.json`. Cap is
`ShipConfig.max_complexity`.

---

## 6. Refusal reporting — BOTH gates block, so the reason must be explicit

```gdscript
# core/ship_gate.gd  --  class_name ShipGate (static only)
enum Reason { OK, COMPLEXITY, BUDGET_BBOX, BUDGET_VOLUME, BUDGET_WEIGHT, BUDGET_COST, MIN_PARTS }

## { "ok": bool, "reason": int (Reason), "message": String }
## `message` is player-facing and must NAME the gate, e.g.
##   "COMPLEXITY 148/148 - REMOVE A PART OR BREAK SYMMETRY"
##   "WEIGHT 5.01Mkg / 5.00Mkg - OVER BUDGET"
static func check_add(doc: ShipDoc, data: ShipData, cfg: ShipConfig,
                      family_id: String, symmetric: bool) -> Dictionary
static func check_doc(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary
static func check_save(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary  # incl. MIN_PARTS
```

`ShipConfig` gains: `max_complexity: float = 148.0`, `min_parts_to_save: int = 3`,
`symmetry_plane_epsilon: float = 0.01`, `snap_tolerance_m: float = 0.35`.
All four go in `data/tuning.json` in the annotated `{"value":..., "description":...}` form — the
loader unwraps `value` (F0).

---

## 7. `core/bake/hull_bake.gd` — ADDITION

```gdscript
## Connected components of the placed parts, by overlap. Report only; never blocks.
## Returns { "islands": Array[PackedStringArray], "largest": PackedStringArray }
static func connectivity(doc: ShipDoc, data: ShipData, cfg: ShipConfig) -> Dictionary
```

`bake()`'s report dict gains `"islands": int` and `"floating": PackedStringArray`.

---

## 8. Interaction — `harness/builder/ship_placement.gd` ADDITIONS

Spore's grammar, from the official manual. **These bindings are researched fact, not preference.**

| Input | Action |
|---|---|
| plain wheel | scale the SELECTED PART (also Up/Down arrows) |
| Shift + wheel, `+`/`-` | zoom camera |
| right-drag bg / left-drag empty space / `<` `>` | orbit camera |
| ~~hold `Tab`~~ | RETIRED(2026-08-31): revealed the rotation rings + morph handles. There is no handle set to reveal any more — every handle is always drawn and always grabbable. See below. |
| `Alt` on selected | clone |
| `Ctrl` + drag | move part vertically only (may float free) |
| `Shift` + drag | move part horizontally; with nothing selected, moves the whole ship |
| drag part off the ship, or Delete/Backspace | remove |
| hold `A` while selecting | break symmetry, cascading |

```gdscript
enum Handle { NONE, BALL_ROTATE, RING_X, RING_Y, RING_Z, MORPH, OFFSET }
# OFFSET appended 2026-08-31 (`offset` had no handle at all).
# BALL_ROTATE is RETIRED(2026-08-31) but keeps its number: the enum's values are the
# handle codes ShipHandles returns. It is never produced.
enum DragMode { FREE, VERTICAL, HORIZONTAL, WHOLE_SHIP }

# RETIRED(2026-08-31): signal handles_changed(part_id, advanced)
# func set_advanced_handles(on: bool)
#
# The Tab-gated handle set is gone, and with it the flag. It lived in THREE places at
# once - ShipView3D, ShipSceneBuilder and ShipPlacement - with different defaults, and a
# focus change reset it silently. With it off, hit_test returned BALL_ROTATE for every
# grab, which spins about the mount normal: all three rings rotated the part about its
# placement vector. Reported twice before it was found, because the unit test supplied
# the flag by hand instead of using the app's.
#
# ShipHandles.hit_test() drops its `advanced` argument and gains `rot`, which places the
# rings on the axes they really turn (ADR 0004).
signal ghost_state_changed(state: int)   # GhostState below

## Mirrors Spore's eBlockUIState.
enum GhostState { DEFAULT, INVALID, GHOST, BAD_LOCATION, PREVENT }

func scale_selected(delta: float) -> void        # wheel
func clone_selected() -> String                  # Alt
func set_drag_mode(mode: int) -> void            # Ctrl / Shift
func break_symmetry_selected() -> void           # A
```

**REMOVE** (Spore has neither, and no source in four research passes found either): camera **pan**,
and the `1/2/3/4` front/side/top axis-snap views.

---

## 9. `harness/panels/` — palette rework

RETIRED(2026-08-31): nine categories (`bodies, cockpits, space, land, water, air, weaponry,
effects, details`, SporeWiki gallery order) -> ONE flat list of every family in pack order
(`harness/panels/part_palette.gd`). Removed at the author's explicit instruction: "they are
simple shapes and need no classification. the player classifies this later in the game." Spore's
categories exist to file hundreds of hand-authored parts; six procedural primitives do not need
a filing system, and the tabs were assigning roles (weapon, cockpit) that Phase 1 has no
mechanism to express.

Paginated icon grid, **no search field** (no Spore editor has one). A palette entry whose
`ShipComplexity.can_afford()` or `ShipGate.check_add()` fails renders in the `warning` role — Spore
turns unaffordable parts **red**.

Save dialog: name (**mandatory**), description, tags. Refuses below `min_parts_to_save`.

## 10. Paint mode — `harness/panels/paint_panel.gd`

Editor modes become `BUILD | PAINT` (Spore's third, PLAY, does not exist in the ship editor —
confirmed by two independent passes). Per-part/per-region, NOT whole-creation procedural.

| Input | Action |
|---|---|
| LMB | paint the clicked region |
| `Shift+LMB` | paint every region on that part |
| `Shift+Ctrl+LMB` | paint that region on all parts of the same family |
| `Alt+LMB` | eyedropper |

Regions come from `families.json` -> `"paint_regions": ["base","coat","detail"]`.
Styles from `data/paint_styles.json`.

---

## 11. Data pack additions — EXACT SHAPES

`data/shapes/families.json`, per family:
```json
"complexity": 4.0,
"can_be_root": true,
"max_children": 8,
"scale_min": 0.2,
"scale_max": 2.0,
"paint_regions": ["base", "coat", "detail"],
"snap_kinds": ["face", "pole", "rim", "center"]
```

RETIRED(2026-08-31): `"category": "bodies"` -> removed from every family and from
`data/schema/families.schema.json`. See section 9.

`data/paint_styles.json`:
```json
{
  "complete": { "<id>": { "label": "...", "description": "...",
                          "colors": [0, 5, 13], "texture": "<id>" } },
  "partial":  { "<id>": { "label": "...", "description": "...",
                          "regions": { "base": {"color": 2, "texture": ""} } } },
  "textures": { "<id>": { "label": "...", "description": "..." } }
}
```

Every catalogue entry needs a real `description` — `data/` is documentation, and the validator
fails placeholders.
