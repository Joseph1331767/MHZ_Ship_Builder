# API CONTRACT — UI layer (Wave 3 addendum)

**Frozen for M3/M4/M5.** Companion to `docs/API_CONTRACT.md`. Two agents build against this
concurrently: the **panels** agent owns `harness/panels/`, the **interaction** agent owns
`harness/builder/ship_placement.gd` and the edits to `ship_view3d.gd` / `ship_builder.gd`.

Same rule as the core contract: if a signature here is wrong, **report it, do not change it** —
someone else is compiling against it right now. The one contract defect that cost this project real
time (`docs/FOLLOWUPS.md` F0) was a field whose *name* was pinned and whose *shape* was not. So
every signal below states its argument types, and every dictionary states its keys.

---

## 0. What already exists — do not redesign it

`ShipBuilder` (`harness/builder/ship_builder.gd`) is the application root and the ONLY surface
panels may talk to. Panels must never reach into each other, and must never mutate `ShipDoc`
directly — that is what the edit protocol exists to prevent.

**Slots** — all four are `VBoxContainer`, reachable by `builder.get_slot(name)`:
`"PartPaletteSlot"`, `"TreeSlot"`, `"InspectorSlot"`, `"GaugeSlot"`.

`%UniqueName` lookup resolves through the *owner*, so a panel instantiated from its own `.tscn`
**must** use `get_slot()`, not `%PartPaletteSlot`.

**Auto-mount.** `ShipBuilder._ready()` loads the first path that exists into each slot and calls
`setup(builder)` on it if present. Use exactly these paths and this method:

| slot | scene path |
|---|---|
| PartPaletteSlot | `res://harness/panels/part_palette.tscn` |
| TreeSlot | `res://harness/panels/part_tree.tscn` |
| InspectorSlot | `res://harness/panels/inspector.tscn` |
| GaugeSlot | `res://harness/panels/gauges.tscn` |

```gdscript
func setup(builder: ShipBuilder) -> void
```

**Existing signals.**

```gdscript
# ShipBuilder
signal doc_changed(doc: ShipDoc)
signal selection_changed(selected: PackedStringArray)
signal history_changed(can_undo: bool, can_redo: bool)
# ShipTheme
signal palette_changed(palette: PackedColorArray)
# ShipView3D
signal part_picked(part_id: String, additive: bool)
signal pick_cleared
# OrbitCamera
signal camera_moved
```

**Edit protocol — the only legal way to change the document.**

```gdscript
builder.begin_edit("move part")
# ... mutate builder.get_doc() ...
builder.commit_edit(changed_ids)   # may REFUSE and roll back (budget guard)
```

`commit_edit` returns nothing but can reject the edit. An empty `changed_ids` means "topology
changed, diff everything". Never mutate the doc outside a begin/commit pair.

**Colour.** Never hardcode a palette index. Always `builder.get_ship_theme().color_for_role(role)`
with a role from `data/palette.json`: `background`, `grid`, `text`, `text_dim`, `line`, `accent`,
`selection`, `warning`, `ghost`. Reconnect on `palette_changed` — the palette swaps wholesale when
a budget maxes out.

---

## 1. `harness/builder/ship_placement.gd` — `class_name ShipPlacement` (RefCounted)

Owned by the **interaction** agent. The single source of truth for an in-progress placement.

```gdscript
signal ghost_moved(yaw: float, pitch: float, rot: Vector3, offset: float)   # RETIRED(ADR 0004, 2026-08-31)
signal ghost_validity_changed(is_valid: bool, reason: String)
signal placement_committed(part_id: String)
signal placement_cancelled

var snap_deg: float          # 0.0 = off
var snap_m: float
var target_parent: String    # the part the ghost is attaching to
var active: bool

func begin(family_id: String, manufacturer_id: String, parent_id: String) -> void
func begin_move(part_id: String) -> void          # re-place an existing part
func update_from_ray(origin: Vector3, dir: Vector3) -> void   # ship space; mouse drag path
func set_values(yaw: float, pitch: float, rot: Vector3, offset: float) -> void  # numeric path
func values() -> Dictionary   # {"yaw": float, "pitch": float, "rot": Vector3, "offset": float}
func rotate_selected(axis: int, delta_deg: float) -> void   # RETIRED(ADR 0004, 2026-08-31): axis added
static func axis_for_handle(handle: int) -> int              # RING_X/Y/Z -> 0/1/2, ball -> 2
func preview_transform() -> Transform3D
func commit() -> String       # "" if refused; otherwise the new/moved part id
func cancel() -> void
```

**The two-way binding is the point of this class.** `update_from_ray` (mouse) and `set_values`
(typed) both write the same four numbers and both emit `ghost_moved`. Whoever did not originate
the change updates from the signal. Guard against feedback loops with a re-entrancy flag, not by
disconnecting signals.

**Snapping is applied at input time**, inside `set_values`/`update_from_ray`, before the values are
stored — so what is stored is exactly what is displayed (SPEC section 6). Snap each angular axis
independently.

**Drag must feel linear on the surface** (SPEC section 3). Do not map mouse delta straight onto
yaw/pitch — near a box corner that moves the anchor far faster than mid-face. Map screen motion to
surface arc-length and solve back to yaw/pitch.

## 2. Additions to `ShipBuilder` — interaction agent adds these

```gdscript
signal attach_preview_changed(
    part_id: String, yaw: float, pitch: float, rot: Vector3, offset: float
)   # RETIRED(ADR 0004, 2026-08-31)
signal placement_state_changed(is_active: bool)

func get_placement() -> ShipPlacement
func begin_placement(family_id: String, manufacturer_id: String) -> void
func begin_move_selected() -> void
func cancel_placement() -> void
```

`gdlint max-public-methods` is raised to 30 in `.gdlintrc` (documented there) specifically so these
four fit without deleting an existing accessor.

---

## 3. `harness/panels/` — panels agent owns all of these

```
harness/panels/part_palette.tscn / .gd   class_name PartPalettePanel
harness/panels/part_tree.tscn   / .gd    class_name PartTreePanel
harness/panels/inspector.tscn   / .gd    class_name InspectorPanel
harness/panels/gauges.tscn      / .gd    class_name GaugesPanel
harness/panels/numeric_field.gd          class_name NumericField    (shared spinner-ish Control)
```

**PartPalettePanel** — lists families from `builder.get_data().family_ids()`, with a manufacturer
selector per family (`manufacturers_for(family_id)`). Clicking a family calls
`builder.begin_placement(family_id, manufacturer_id)`. Show each entry's `label` and its
`description` as a tooltip — the pack was written to be read.

**PartTreePanel** — a `Tree` of the part hierarchy from `doc.part_order()` / `children_of()`.
Reflects and drives selection through `builder.get_selection()` / `set_selection()`. Must provide
**Select All Children** (extend to `doc.descendants_of()` of every selected part) and **Select No
Children** (collapse to the clicked part alone) as buttons — these are named features. Mark mirror
derivatives visually and make them non-editable; mark component instances distinctly.

**InspectorPanel** — the numeric surface. Six `NumericField`s for yaw/pitch/rot x/rot y/rot z/
offset (RETIRED(ADR 0004, 2026-08-31): was four, with one `roll`) bound
two-way to `ShipPlacement`, three for scale, a snap selector (`0.1 / 0.5 / 1 / 5 / 15 / off`), a
uniform-scale lock, per-family param fields built from
`ShapeGen.effective_ranges(data, family, manufacturer)` (which returns
`key -> {"min","max","default","is_int"}`), and the mirror buttons (X / Y / Z / break link).
**Always render numbers to exactly 3 decimals** so field widths do not jitter (SPEC section 11).

**GaugesPanel** — four horizontal fill bars: BBOX, VOLUME, WEIGHT, COST, from
`ShipBudgets.usage(metrics, cfg)`. Show `used / cap` numerically beside each. On a violation call
`builder.set_budget_alert(ShipBudgets.budget_key(top))` to swap the whole console palette; call
`builder.set_budget_alert("")` to clear. **Taking this hands alert control to you** — ShipBuilder
disables its own bbox-only auto-check once you call it, so you must then report all four.

Metrics are expensive (a grid pass). **Never compute them synchronously in a signal handler.**
Debounce on a `Timer` (250 ms idle) and use `ShipMetrics.compute_bbox()` — which is cheap and
grid-free — for the live bbox bar between full passes.

---

## 4. Rules that bind both agents

- Godot 4.7, strict static typing, `untyped_declaration=2` and `untyped_signal=1` — **every signal
  argument typed**.
- **Nothing may read `DisplayServer`, `get_window()`, or a global mouse position.** The builder
  renders to a texture on a diegetic device (SPEC section 10). Use `_gui_input` and event-local
  positions only. This is verified by grep at the gate.
- No native dialogs. `builder.show_message(title, body)` is in-scene; use it.
- `.tscn` files stay minimal — build structure programmatically in `_ready()`.
- Use the Write tool, not Bash heredocs (large heredocs fail in this environment).
- **Verify with `gdparse` and `gdlint`** (gdtoolkit 4.5.0, pure Python, no engine, no GPU slot).
  Every one of the 43 GDScript files in this repo currently passes both. Yours must too.
- **Do not run Godot.** The GPU is a booked single-slot resource; the orchestrator runs all
  engine verification serially.
