# MHZ Ship Builder — Specification (the node of truth)

**Status:** Phase 1 in progress. **Engine:** Godot 4.7 Forward+. **Ruleset version:** `1.0.0`.

Read this before touching `core/` or `data/`. Every decision below was made explicitly with the
author; do not relitigate them in code. Changes to anything marked **CONTRACT** require an ADR.

---

## 1. What this is

A CAD-style ship hull builder with the interaction feel of the Spore spaceship editor and the
determinism of a parametric CAD kernel. Parts are placed on the *surface* of other parts by typed
angular coordinates or by dragging, and the assembly resolves to an exact signed distance field
which can be baked into a solid hull shell.

**Phase 1 (this phase): craft a hull.** Out of scope, but designed for: working components
(thrusters, sensors), a Phase 2 interior build with power/data/fuel routing, hull regions with
material layers resolved from MHZ_Materials, and destructible per-layer damage.

**This module renders to a texture.** The whole builder lives under one `SubViewport` so the real
game can map it onto a diegetic device. See section 10 — this is structural, not cosmetic.

---

## 2. Architecture — three views of one truth

```
                    ShipDoc  (JSON, the truth)
                       |
      +----------------+--------------------+
      |                |                    |
   build            evaluate               bake
      |                |                    |
      v                v                    v
 Scene view        ShipSdf              Surface Nets
 1 mesh/part    sample(p)->float        -> welded shell
 crisp, picky   volume, mass, depth     -> (P2) interior,
 never remeshed  validity, budgets          layers, damage
 while dragging
```

The editing view is never the SDF, and the SDF is never remeshed per frame. That split is what
allows crisp CAD primitives *and* a volumetric destructible hull without either compromising the
other.

---

## 3. The attach model — CONTRACT

Every non-root part stores four numbers plus a parent.

| field | unit | range | meaning |
|---|---|---|---|
| `yaw` | deg | `[-180, 180)` | ray azimuth in the parent's local frame |
| `pitch` | deg | `[-90, 90]` | ray elevation |
| `rot` | deg (Vector3) | each `[-180, 180)` | child's orientation in the mount frame; `rot.z` spins about the normal, `rot.x`/`rot.y` tilt off it. RETIRED(ADR 0004, 2026-08-31): was `roll: float` |
| `offset` | m | unbounded | along the surface normal; `0` = flush |

**Resolution algorithm — this order, exactly:**

1. Direction `d` from (yaw, pitch) in parent-local space:
   `d = (cos(pitch)*sin(yaw), sin(pitch), cos(pitch)*cos(yaw))`, normalized.
   Godot is Y-up. `yaw=0, pitch=0` therefore points at parent-local **+Z**.
2. **Sphere-trace `d` outward from the parent's local origin** against the parent's resolved shape
   SDF until it crosses zero. Anchor `P`. No mesh, no collider, no physics query.
3. `N` = normalized gradient of the parent SDF at `P` (central differences, 6 samples,
   `h = ShipConfig.gradient_eps`). This is the mount axis.
4. Roll reference tangent: project parent-local **-Z** (forward) onto the tangent plane at `P` and
   normalize. If `abs(N dot -Z) > 0.999` (pole), fall back to parent-local **+Y**. Then rotate that
   tangent (NOT pre-rotated; the spin is applied as `rot.z` in step 5). `rot = 0` therefore means *"child's forward points toward the
   parent's nose"*.
5. Mount frame `F = Basis(tangent x N, tangent, N)` — **`+Z = N`, the placement normal**.
   Child basis `= F * Rz(rot.z) * Ry(rot.y) * Rx(rot.x + 90 deg)`. Orthonormalize.
   The fixed `+90 deg` about X stands the part's own `+Y` up along `N`, because every family
   is authored Y-major (section 6); without it a cone would point along the surface instead
   of out of it. At `rot == (0, 0, roll)` this is bit-for-bit the pre-ADR-0004 basis
   `Basis(tangent' x N, N, -tangent')`.
   RETIRED(ADR 0004, 2026-08-31): `+Y = N, -Z = rolled tangent` -> the frame above. See
   `docs/adr/0004-three-axis-part-orientation.md`.
6. Child origin = `P + N * (offset + mount_inset)`, where `mount_inset` is the distance from the
   child's own origin to its attach face along child `-Y`, so that `offset = 0` puts the child's
   attach face tangent to the parent surface (flush). Positive floats out, negative embeds.

**Non-convex shapes.** A torus's local origin is outside its solid, so "march outward from the
centre" has nothing to march from. `ShipAttach` therefore has two trace modes, declared per shape
family by `origin_inside: bool`:

- `origin_inside = true` — march from origin, step by `abs(sdf)`, stop at first sign change.
- `origin_inside = false` — march from the shape's bounding sphere *inward* along `d`, take the
  **first** zero crossing.

**Lipschitz safety.** Domain-warping ops (taper, twist, shear) make the field a *bound*, not a true
distance, so a naive sphere-trace can overshoot and tunnel. Every resolved shape exposes
`lipschitz` (>= 1.0); the tracer steps `abs(sdf) / lipschitz`. Non-uniform scale contributes
`max(scale) / min(scale)` to that factor.

**Angular input is non-linear across a face.** Near a box corner, half a degree of yaw moves the
anchor much further than it does mid-face. The stored record is exact; the *mouse drag* maps screen
motion to surface arc-length and solves back to yaw/pitch so dragging feels linear. The numeric
fields and the drag are two views of the same four numbers and must stay bound both ways.

---

## 4. Shape generation — CONTRACT

**There is no nonce and no rollable seed. Params fully determine the shape.**

```
seed = ShipHash.shape_seed(family_id, manufacturer_id, params, RULESET_VERSION)
```

The seed is **derived, never stored, never rolled**. It drives only the *micro-detail* the player
does not expose — rib phase offsets, scallop noise, panel-line placement, subtle asymmetry — all
within family-authored ranges. Identical params therefore give an identical shape, forever, and
every visible difference traces to something the player set.

**Manufacturers are legible style presets, not disguised randomness.** A manufacturer narrows a
family's parameter ranges, may disable ops, and carries a cost multiplier. The player picks a
company, then tunes within that company's ranges. "Voss makes ribbed things" is knowledge a player
can act on.

**The safety property that makes content iteration cheap:** *ranges gate input, the hash consumes
output.* Param values are stored explicitly in the doc, so retuning a manufacturer's ranges later
does **not** move any saved ship. Only changing the *generator* — what `taper = 0.3` means
geometrically — moves ships, and that is what earns a ruleset bump and an ADR.

**Op order is the ruleset. It is fixed and immutable:**

```
p' = taper(p)              domain warp
p' = twist(p')             domain warp
p' = shear(p')             domain warp        (ADR 0007)
d  = base_sdf(p', size)    box | sphere | cylinder | torus
d  = d - round_r           inflate
d  = d + rib_disp(p')      displacement
d  = d + scallop_disp(p')  displacement
```

Adding an op appends to the END of this list, never inserts. Reordering is a ruleset bump.

**The one exception, and why it is not a licence.** A DOMAIN WARP cannot be appended: everything
after `base_sdf` operates on a distance, not on a point, so there is nowhere at the end for one to
go. `shear` was therefore INSERTED, last of the three warps, by
[ADR 0007](adr/0007-shear-the-fourth-morph-verb.md) with a ruleset bump — and it is only safe
because at its default of zero it is the identity, so no shape that predates it moved by a float.
Any future domain warp faces the same argument and the same bump; anything that is not a domain
warp still appends.

RETIRED(ADR 0005, 2026-09-01): `cone` and `capsule` as separate base primitives -> `cylinder`
carrying `end_radius` and `end_round`. The two enum values still evaluate for an old document;
no family produces them. See [ADR 0005](adr/0005-one-parametric-body-of-revolution.md).

---

## 5. Data model — CONTRACT

### 5.1 ShipDoc

```json
{
  "format": "mhz_ship",
  "version": 1,
  "ruleset_version": "1.0.0",
  "units": "metres",
  "root": "p_0001",
  "settings": { "snap_deg": 0.5, "snap_m": 0.05, "snap_scale": 0.05 },
  "parts": {
    "p_0007": {
      "parent": "p_0001",
      "kind": "primitive",
      "family": "box_hull",
      "manufacturer": "kessler",
      "params": { "taper": 0.30, "bevel": 0.08, "ribs": 4, "scallop": 0.15 },
      "attach": { "yaw": 45.0, "pitch": 30.0, "rot": [0.0, 0.0, 0.0], "offset": 0.0 },
      "scale": [2.0, 1.0, 3.0],
      "blend": 0.0,
      "mirror": { "source": null, "plane": null },
      "name": "dorsal fin",
      "locked": false
    }
  },
  "joints": {
    "j_0003": {
      "a": "p_0001", "b": "p_0007",
      "mode": "open",
      "hatch": { "family": "iris_round", "manufacturer": "kessler",
                 "params": { "radius": 0.9, "leaves": 6 } }
    }
  },
  "components": {
    "comp_wing_a": { "label": "Wing A", "root": "cp_0001", "parts": {} }
  }
}
```

**Rules.**

- Strict tree over `parts`: single `root`, every other part has exactly one `parent`, no cycles.
- Part ids are **immutable once created** — regions, damage state and routing will reference them.
- `kind` is `"primitive"` or `"component_instance"`. For an instance, `family` holds the component
  definition id and `params` is empty.
- `joints` is keyed over **unordered part pairs** — siblings overlap too, so a joint is NOT a
  parent/child edge. Canonical ordering: `a` < `b` lexicographically.
- `mirror.source` non-null makes the part a **derivative**: it is generated at rebuild by
  reflecting its source's resolved world transform across the ship root's plane. It is not
  independently editable until "break link" materializes it.
- `blend` is the smooth-union radius; `0.0` = hard union.

### 5.2 Reserved now, read by nothing in Phase 1

Present in the schema so no Phase 1 ship needs migrating:
`hull: {thickness_m, layers[]}` · `regions[]` · `part.material_ref` (an MHZ_Materials id) ·
`part.role` (`"structural"` | `"greeble"` | `"mount"`).

### 5.3 Data packs

| file | contents |
|---|---|
| `data/shapes/families.json` | shape families: base primitive, op list, param ranges, `origin_inside` |
| `data/shapes/manufacturers.json` | style presets: per-family range narrowing, disabled ops, cost multiplier |
| `data/shapes/hatches.json` | hatch families (authored in Phase 1, geometry unbuilt) |
| `data/palette.json` | the 16-entry base palette plus one alert palette per budget |
| `data/tuning.json` | every dev lever (section 8) |
| `data/schema/*.json` | schemas the validator enforces |

**Every entry carries a real `description` written for a reader.** `data/` is documentation. An
entry with a placeholder description is unfinished.

---

## 6. Mirror, components, selection, snapping

**Mirror** — live linked, one record plus a flag, reflected across the ship root's X/Y/Z plane.
Symmetric ships are half-size on disk and cannot drift. Mirroring a subtree carries its children.
"Break link" materializes real records with fresh ids. Reflection flips winding, so mirrored meshes
need front-face culling or a determinant-aware material.

**Components** — SketchUp-true definition + instances. Edit the definition, every instance updates
at rebuild. "Make Unique" clones the definition and repoints one instance. An instance attaches
with the same four numbers as a primitive, so it drops into the palette with no special-casing.
Nesting allowed; depth- and cycle-checked by the validator.

**Selection** lives only in the UI layer, never in the doc. Click / Ctrl-click, plus
*Select All Children* (extend to the full descendant subtree) and *Select No Children* (collapse to
the clicked part alone).

**Snapping** quantizes at input time, so what is stored is exactly what is displayed. Angular
`0.5` deg default per axis independently (`0.1 / 0.5 / 1 / 5 / 15 / off`), linear `0.05` m on
offset, `0.05` on scale with a uniform-lock toggle. A held modifier bypasses momentarily.

---

## 7. Joints and hatches — authored in Phase 1, geometry in Phase 2

RETIRED(ADR 0008, 2026-09-02): "geometry in Phase 2" and "the Phase 1 bake produces the all-open
studio hull with no walls" -> the seam geometry is built. Every part lays a **seam** where it
stands on its parent — the plane through `P` with normal `N` that section 3 computes — and the
seam carries a **wall of hull thickness** unless its joint says otherwise: no record or `sealed`
is a solid wall (the default: "if its 2 separate rooms, just a solid wall"); `doorway` is the
wall with a plain centred opening (`ShipConfig.doorway_width_m x doorway_height_m`); `hatched`
is the wall with the hatch family's opening, centred on the seam; `open` is no wall — one room.
`ShipSeams` computes the seams, `ShipSdf` lays the plates in the assembled field and cuts/adds
the modules the EXPLODE view bakes, `HullBake` widens a plate to its grid so a coarse bake gets a
thicker bulkhead rather than none.
AMENDED(ADR 0009, 2026-09-02): a seam also has a **style** — `flat` (the plane through the
anchor, the default and ADR 0008's only shape), `parent` (the seam follows the PARENT's surface;
the child is dented and the overlap stays with the parent) or `child` (the mirror of it). One
rule serves all three: the plate is the shell of hull thickness just inside the seam SURFACE,
clipped to the other solid. All three partition the overlap exactly, so the choice is taste, not
correctness. `flat` on a CURVED host is a tangent plane and the two cavities can meet around its
rim — which is what a flat plane means, and why the other two exist.
AMENDED(ADR 0029, 2026-09-06): the opening IS bored. A hatched or doorway seam's hole goes
through both modules' walls at a gasket plane on the indenting module's mesh, each module takes a
flat collar of the frame's outline and its own door (single hinge, double leaves or iris) over
the same opening, and the hole is clamped to what both cavities take, never under
`ShipConfig.hatch_min_m` without saying so. `ShipDoors` plans it, `ShipCsgBake` bores it.
The original text follows as written.

Phase 1 ships the **full authoring UI**: select an overlapping pair, toggle
`open` / `hatched` / `sealed`, pick a hatch family and tune it. The SDF partition geometry is
**not** implemented, so **the Phase 1 bake produces the all-open "studio" hull with no walls**.
That is by design and must not be read as a bug.

Two supports so the authored data is not garbage:

- **Auto-discovery** — the builder detects overlapping pairs from the SDF and offers them as
  candidate joints. The player does not hunt for pairs.
- **Validity** — "do these two cavities actually merge?" is a cheap SDF sample, no meshing. A hatch
  between parts that merely touch is flagged, because it would mean nothing.

For Phase 2, the intended construction is recorded here so it is not reinvented: the partition is a
plate of hull thickness lying in the joint plane (which the attach model already computes — the
plane through `P` with normal `N`), clipped to where both solids are, with a seeded hatch SDF
subtracted, unioned into the hull field.
RETIRED(ADR 0008, 2026-09-02): built as described, with two refinements found in the building.
The plate lies on the INNER side of the plane, `[P - T, P]` along `N`, clipped to the child's
cross-section rather than to both solids — it is the host's own skin continued across the
opening the union removed. And it cannot be *unioned* into a `min()` field, which is already
deep inside there; it enters as `f = max(union, -T - plate)`, which leaves the outer surface
alone and gives the interior isosurface the plate's two faces.

---

## 8. Budgets and dev tuning — CONTRACT

**Four budgets: bounding box (per axis), internal volume, weight, cost.** Surface area was dropped
as a cap but is still *computed* — it is the input to weight — and is displayed uncapped.

- **Weight** = `surface_area_m2 * areal_density_kg_m2`. This is a shell model and is deliberately
  the right shape: when MHZ_Materials plugs in, `areal_density` becomes
  `thickness * material.density` and the formula does not change.
- **Cost** = sum over parts of `family_base_cost * manufacturer_multiplier * size_factor *
  param_complexity`. `max_cost` defaults to infinite in Phase 1 — displayed and gauged, never
  blocking.
- **`max_bbox` is per-axis, not diagonal.** A 200 m x 20 m hull is legal where a 78 m cube is not.

**Enforcement is a hard block** on edits that increase usage, with **three exemptions, or you build
a trap**: loading, deleting, and undo are never refused. Otherwise the day a lever is lowered,
every ship that was legal yesterday becomes unopenable. Over-budget-on-load shows as a violation
state — visible, fixable, not fatal.

**Feedback.** Each budget owns an alert palette in `data/palette.json`. Because the whole builder
renders through one 16-entry palette LUT (section 11), a budget maxing out swaps the LUT — one
uniform write, not a UI refactor. A fixed priority order in `data/tuning.json` resolves ties when
two max at once. Gauge bars along the bottom show percent-used per budget in that budget's accent.

**Every lever lives in `data/tuning.json` and must appear in `ShipConfig.snapshot()`** — a lever
missing from the snapshot means reports do not record what produced them.

Levers: `max_bbox_m` (Vector3), `max_internal_volume_m3`, `max_weight_kg`, `max_cost`,
`areal_density_kg_m2`, `hull_thickness_m`, `bake_cell_m`, `metrics_cell_m`, `snap_deg`, `snap_m`,
`snap_scale`, `budget_priority`, `gradient_eps`, `trace_max_steps`, `trace_epsilon`,
`part_scale_min`, `part_scale_max`.

---

## 9. The SDF and the bake

`min()` unions the per-part fields; `blend > 0` swaps in a polynomial smooth-min.

**Two honest caveats, both real, both bounded, neither a bug to be fixed away:**

1. **Interior distance from a union of `min()`s is not exact.** Exact outside; inside it only
   considers each part's own surface, some of which is no longer real boundary. Near joints the
   `-T` level set sits too far out, so the shell reads slightly thick. Fix path when it matters:
   grid plus an eikonal sweep.
2. **Non-uniform scale makes an SDF a bound, not a distance.** Conservative correction: divide by
   the max scale component. Fine for meshing; matters only if sphere-tracing for speed.

**The bake.** AABB padded by thickness, voxel grid at `bake_cell_m` (default 0.25 m), sample
corners, **Surface Nets**, weld, normals from the SDF gradient, `ArrayMesh` plus a report (tris,
area, enclosed volume, bake time). Chunked on a worker thread with progress.

**THE EXTRACTOR IS NOT THE MESH (ADR 0010, 2026-09-03).** The paragraph above describes one stage
where there are two, and reading it as the whole bake is what produced 588 triangles for a 2 m box
and 1568 for a 3 m room module, 65% of that area dead flat. Dual Contouring emits one quad per
sign-changing grid edge: a faithful *sampling* of a surface, never a model of one. `HullSimplify`
is the second stage — project onto the exact isosurface, grow planar patches, absorb the sub-cell
fillet noise beside them, snap every vertex onto the planes meeting at it, straighten the patch
boundaries and retriangulate with holes bridged. Same field, same extractor, both untouched. A box
comes out of it as 12 triangles with an area of 23.999 m² against an exact 24.000, and the shell
stays closed: 0 open edges after a positional weld. Curved surfaces keep their tessellation on
purpose.

**The upgrade path, written down now so it is not rediscovered:** replace *only* `place_vertex()`
with a QEF solve over the gradients at the edge crossings, clamped to the cell. Same grid, same
loop, one function — and Surface Nets becomes Dual Contouring, and boxes get their sharp edges
back. Do that when the rounding is a problem, not before.
RETIRED(ADR 0009, 2026-09-02): DONE, exactly as written — one function, same grid, same loops.
Cutting parts flat at their seams made the rounding the problem ("its not flattened along the
plane of intersection its all bumped out and weird looking"). The crossing normals come from the
trilinear gradient of the cell's own eight corner samples, so the QEF costs no extra field
evaluations at all; it is regularised toward the centroid and clamped strictly into its cell.

**A SECOND BAKE, AND IT IS NOT AN ISOSURFACE (ADR 0011, 2026-09-03).** Everything above still
describes the Surface Nets path, which still runs. Beside it there is now an EXACT path in
`core/mesh/`: each part is tessellated analytically from its `ResolvedShape` by inverting the very
domain warps `sdf()` applies, and comes out as ONE CLOSED SOLID PER PART — "all primatives can be
their own mesh ... they can remain in parts as in space they will have detach capabilities". No
grid, no resolution parameter, and no boolean: parts are not unioned. A box is six faces and twelve
model edges at any size, and every baked vertex samples to zero in the field it came from. `round`,
ribs and scallops are not built yet and a part carrying one bakes sharp (FOLLOWUPS F22).

**Phase 2 hooks (specified, unbuilt):** interior shell = the isosurface at level `-T`; volume
between shells = hull material volume, giving real mass; a UV atlas over the outer shell is the
texture per-texel layer damage and routing will write into.

---

## 10. Render-to-texture — CONTRACT

The builder ends up on a diegetic device in MHZ_Origins, so this is structural:

- The **entire** builder — 3D viewport *and* all UI — lives under one `SubViewport` at a fixed
  virtual resolution of **1280x800**, nearest filtering.
- `harness/dev_host.tscn` is a thin `SubViewportContainer` wrapper for standalone runs. The in-game
  host later is a quad: raycast, UV, synthesized mouse event via `Viewport.push_input()`.
- **Nothing in the builder may read window size or `DisplayServer`.** Ever.
- `embed_subwindows = true`, and every dialog is an in-scene `Control`. A native `FileDialog`
  simply will not exist on the texture.
- Text entry in-game needs the device to supply focus and a keypad. Phase N, but the numeric fields
  are designed to accept it.

---

## 11. Look

Fixed low-colour blue-green palette, 70s-remembered future. **One palette-quantization
post-process over the whole SubViewport**, so the 3D and the UI share a colour language
automatically rather than being matched by hand. Optional 4x4 Bayer dither for era-correct banding.
Ramp: deep ink, teal, cyan-green, pale mint, with warm slots reserved for selection and warning.

Display modes: **flat-shaded**, **wireframe**, **shaded + wireframe**, **x-ray/ghost** (to see
buried parts). Placement ghost in the accent colour. Monospace, caps labels, 1 px boxes, corner
ticks, numbers always to 3 decimals so fields do not jitter width.

---

## 12. Layout and isolation

```
core/     pure data - no Node, no SceneTree, no signals, no res:// outside ShipData
data/     JSON packs - families, manufacturers, hatches, palette, tuning, schema, ships
harness/  the builder, SubViewport-rooted; may depend on core/, never the reverse
tools/    headless: validate, selfcheck, bake, screenshot
tests/    gdUnit4
docs/     this file, adr/, devlog/
scratch/  gitignored
```

`core/` + `data/` is the drop-in unit that lifts into MHZ_Origins. Nothing in `core/` may reference
anything outside `core/` and `data/`.

**Ported from `MHZ_Origins/AGENTS.md`:** section 7c GPU slot booking applies (we render windowed)
and the two-harness rule applies (dev host vs. diegetic host). **Section 3a coordinate spaces does
not** — a ship is local, small, and float32-safe throughout.
`PRECISION_OK(RENDER): ship-local geometry, max extent ~250 m, finest feature ~0.01 m; float32
resolves 3e-5 m at that range.`

---

## 13. Milestones

| | | status |
|---|---|---|
| **M0** | Stand up: template, rename, spec, bootstrap, parses clean | Completed |
| **M1** | Truth layer, headless: doc, shapes+manufacturers, SDF, attach, validator, hash, tests | Completed |
| **M2** | It draws: SubViewport app, orbit camera, scene from doc, palette, tree, picking | Completed |
| **M3** | It builds: ghost, drag/numeric, snap, scale, delete, undo/redo, bbox budget | Completed |
| **M4** | It measures: volume/area/weight/cost, four budgets, gauges, palette flip, dev overlay | Completed |
| **M5** | Multiplicity: multi-select, mirror, components, joint authoring, save/load | Completed |
| **M6** | It's solid: surface-nets bake + report, interior shell (ADR 0006), seam walls + doorways/hatches in the bake and the EXPLODE view (ADR 0008). **Phase 1 done.** | Testing |
| **M7** | Diegetic placeholder: builder on a panel in 3D, input through UV | Not Started |
