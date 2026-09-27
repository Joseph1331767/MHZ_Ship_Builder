# Follow-ups — contract gaps and reconciliations found during implementation

Running list. Each entry is something an implementing agent found that the frozen
`docs/API_CONTRACT.md` could not express, or a mismatch between two independently written pieces.
Resolved entries stay, marked RESOLVED, so the reasoning is not lost.

---

## F1 — `HullBake` / `SurfaceNets` cannot report progress — OPEN

`SPEC` section 9 promises "chunked on a worker thread with progress". But `SurfaceNets.extract()`
and `HullBake.bake()` are single opaque synchronous calls with no callback and no resumable chunk
boundary, so a harness can only run the whole bake on a thread as one unit and show an
*indeterminate* spinner. It cannot show percent-complete.

**Decision:** accept the indeterminate spinner for M6. When a real progress bar is wanted, add an
optional trailing `progress: Callable = Callable()` to both functions — an additive optional
parameter, so every existing call site still compiles and no other agent is broken.

## F2 — `SurfaceNets.extract()` cannot honour `gradient_eps` — OPEN

`extract()` takes no `ShipConfig`, but `gradient_eps` is a tuning lever (SPEC section 8) and
gradient normals need an eps. The bake currently derives `eps = 0.25 * cell` (floored at 1e-5),
which is arguably better than a fixed lever anyway since it scales with grid resolution.

**Decision:** leave as derived. Document in `tuning.json` that `gradient_eps` applies to attach and
metrics, NOT to the bake, which scales its own. Do not silently let the two diverge unexplained.

## F3 — `"cells"` is a count, not a spacing — RESOLVED

The brief asked the bake to report "the cell actually used" in `"cells"`, but the contract types
that `int` and a spacing is a float. The bake returns the grid **cell count** in `"cells"`
(contract-conformant) and adds `"cell_m": float` and `"dims": Vector3i`.

**Consequence:** anything printing the bake's real resolution — `tools/ship_bake_cli.gd`, the M6
bake report panel — must read `cell_m`, not `cells`.

## F4 — `areal_density_kg_m2` default disagreed between code and data — OPEN

`data/tuning.json` ships `40.0`; the `ShipConfig.defaults()` figure handed to the core agent was
`120.0`. Data wins at load, and `40.0` is the more physical number (a 0.4 m shell at ~100 kg/m³
effective), so the **code default should be aligned down to 40.0**, not the pack raised.

**Must actually verify** that `ShipConfig.from_dict()` genuinely overrides the default rather than
merging partially — a silent fallback to 120 would make every weight reading wrong by 3x and
nothing would error.

## F5 — Bake cost at full grid is minutes, not seconds — OPEN, EXPECTED

The 8M-cell cap is ~64 MB of packed arrays and 8M GDScript `sdf.sample()` calls. This is inherent
to a GDScript grid sampler, not a defect in the implementation. The documented escalation path, in
order: coarsen the default cell, then chunk-and-thread, then a compute shader (MHZ_Origins already
has that muscle, and its rule that `.glsl` is not covered by any headless check).

**Do not quote a bake time that was measured while other Godot processes held the GPU slot.**

## F9 — `ShipPart.absolute` is dead data — RESOLVED by ADR 0033

The field is declared, documented as "positions it in ship space directly", and round-tripped
through `to_dict()`/`from_dict()` — but **`ShipAttach` never reads it.** Repo-wide grep confirms.

A floating (parentless, non-root) part is therefore positioned by the ordinary yaw/pitch/offset
ray-trace with `parent_shape == null`, i.e. treating the absent parent as a point at the ship
origin. That happens to produce a sane placement, which is exactly why it will not be noticed: the
part appears somewhere plausible and the transform the author stored is silently ignored.

Consequence: the `Ctrl`+drag vertical move, which Spore explicitly allows to leave a part hovering
in mid-air, cannot currently persist that position for a parentless part.

**Fix:** `ShipAttach.local_transform()` / `resolve_all()` must use `part.absolute` when
`part.parent == ""` and the part is not the doc root. Small change, but it needs a test that saves,
reloads, and asserts the floating part did not move — otherwise this regresses invisibly.

**RESOLVED 2026-09-22 (ADR 0033), and wider than this entry asked.** `ShipAttach._place_part` now
returns `part.absolute` for the root AND for any parentless part: the ship's origin is a BEACON that
every class is built around, and the root is anchored to it rather than pinned to identity. The test
this entry asked for is `tests/core/test_beacon.gd::test_a_floating_part_keeps_where_it_was_put`,
beside one that saves and reloads an anchored root.

## F8 — `HullBake._islands_of()` was called but never defined — RESOLVED

The connectivity agent was killed by a rate limit after writing the two CALL SITES and the doc
comment, but before writing the function. `gdparse` and `gdlint` both passed the file cleanly —
GDScript identifier resolution happens at analysis time inside the engine, so the entire `HullBake`
class would have failed to compile the moment Godot loaded it, taking `bake()` and the pre-existing
`tests/core/test_bake.gd` down with it.

Found by the tests agent reading the file it was writing tests against, not by any tool.

**Third instance of the same lesson:** `gdparse` is a fast pre-filter and is not the gate. It does
not resolve `class_name` references (F-series: `part_palette.gd` referencing classes that did not
exist), does not apply `inferred_declaration` as an error (the `var x := <Variant>` breakages), and
does not resolve intra-class calls. Only the engine does.

Implemented as union-find over `ShipJoints.part_box` / `pair_state` — deliberately REUSING joint
discovery's overlap predicate rather than writing a second one, since two disagreeing definitions of
"these parts touch" would surface to the player as a joint that exists beside an island that does not.

## F7 — OPEN, ROOT CAUSE UNKNOWN: shaded materials render black in the 3D SubViewport

**The symptom.** With `SHADING_MODE_PER_PIXEL`, a part renders pure black and the palette
quantizer rounds it to the background entry, so the ship is invisible while the grid (unshaded)
draws fine. The first windowed render showed an empty grid floor and nothing else.

**Proven by experiment**, not inferred: flipping the solid material to `SHADING_MODE_UNSHADED`
and changing nothing else took the part from **0 px** to **115,582 px (23.9% of the 3D panel)**.

**What was checked and is NOT the cause** — all verified at runtime, in-engine:

| checked | result |
|---|---|
| mesh exists, has a mesh resource | `solid_p_0001`, `BoxMesh` (a Godot primitive — has normals) |
| visibility | `visible_in_tree = true`, every ancestor visible |
| world | same `World3D` instance as the camera and the grid |
| viewport | same `View3DViewport`; not a nested-world mismatch |
| camera aim | `looking_dir` (0.524, -0.407, -0.748) == `normalize(origin - pos)` exactly |
| framing | box 2.04 m at 4.78 m, ~64% of viewport height — it is not off-screen or tiny |
| light | `KeyLight` energy 1.15, `visible_in_tree`, `light_cull_mask` = all, inside the viewport |
| environment | `ViewEnvironment`, `AMBIENT_SOURCE_COLOR`, energy 0.75, `BG_COLOR` |
| mesh layers vs light cull | layers 1 vs cull mask 0xFFFFF — no mismatch |
| palette shader | per-channel luma-weighted distance; amber maps to amber exactly, verified by maths |

**Shipped workaround, deliberately not called a fix.** The solid material is `UNSHADED` and the
default display mode is `SHADED_WIRE` so the wireframe overlay carries the form (an unshaded solid
alone is a flat silhouette with no edges). This is defensible on its own terms — at 16 colours a
shading gradient is mostly quantized away, and flat-fill-plus-edges is the CAD read this builder
wants — but it is a workaround, and the underlying lighting failure is real and unexplained.

**Why it matters later.** Phase 2 wants shading for interior/layer visualisation. Whatever is
wrong here will still be wrong then. Next things to try: render the inner SubViewport texture in
isolation to separate rendering from compositing; test a shaded material in a plain (non-nested)
SubViewport to see whether nesting is the trigger; check whether `own_world_3d` plus a
`WorldEnvironment` added *after* `add_child(_viewport)` leaves the world's environment unset.

## F0 — CRITICAL: every tuning lever was silently ignored — RESOLVED

**The bug.** `data/tuning.json` stores each lever as an annotated record —
`{"value": X, "description": ..., "min": ..., "max": ...}` — so a dev slider carries its own
bounds and a reader learns what the lever does. But `ShipConfig._as_float()` accepts only
float / int / String; handed a Dictionary it fell through to the caller-supplied default.
`_lookup()` returned the whole record, so **all 17 levers fell back to their code defaults.**

**Why it was dangerous.** Nothing threw, nothing logged, and `load_all()` reported success. The
pack parsed, `ShipData.config` was populated, and every value in it was wrong. The dev tuning
panel would have appeared to work while changing nothing. The divergences were not cosmetic:

| lever | pack | code default | effect if ignored |
|---|---|---|---|
| `hull_thickness_m` | 0.15 | 0.40 | interior cavity wrong by 2.7x; weight and volume budgets both off |
| `max_internal_volume_m3` | 200000 | 60000 | volume budget fires at 30% of the intended limit |
| `part_scale_max` | 20 | 50 | scale clamp 2.5x too permissive |
| `gradient_eps` | 0.001 | 0.0001 | attach normals computed at the wrong scale |
| `trace_epsilon` | 0.0005 | 0.00001 | sphere-trace converges 50x tighter than tuned, wasting steps |

**Root cause is a contract omission, not an agent error.** `API_CONTRACT` section 3 pinned the
lever NAMES but never the tuning file's VALUE SHAPE. The data agent chose the annotated form
(correct — it makes the pack self-documenting, which the house rules require). The core agent
wrote coercers for bare scalars (also reasonable). Neither could see the other.

**Fix.** `ShipConfig._unwrap()` reduces `{"value": X, ...}` to `X`, applied at both return sites
of `_lookup()`. Keys on `value` alone, so the `min`/`max` slider bounds are never mistaken for the
value. Verified against the real pack: 17/17 levers now resolve, `gdparse` and `gdlint` clean.

**Lesson for the contract:** pinning a key name is not pinning a schema. Any future contract entry
that names a data field must also state the field's shape, or two agents will assume differently
and the mismatch will be silent rather than loud.

## F6 — Mirror derivatives must not be double-counted in metrics — OPEN

`ShipAttach.resolve_all()` emits mirror derivatives as first-class entries. `ShipSdf.build()` must
include them (they are real geometry) but `ShipMetrics.compute_cost()` walks `doc.part_order()`,
which lists only stored records. Confirm at the gate that cost counts a mirrored part *once per
physical instance*, and that this is the intended answer — a mirrored wing is two wings to build
and should presumably cost twice.

---

## F10 — Brief items still NOT implemented, after the 2026-08-31 audit — OPEN

The author asked, verbatim: "self identify any mechanics or features requested by me that are not
implemented. and implement them." Most of that audit landed on 2026-08-31 (see the devlog entry of
that date). This is the honest remainder — everything traced back to a real sentence in the brief
that is still missing, so it cannot quietly drop off the list again.

**1. Interior shell and thickness at bake — RESOLVED 2026-09-01 (ADR 0006).**
> "i certainly want to give it a thickness and an interior mesh, trach its volum and mass etc."

`HullBake` now extracts a second isosurface at `iso - hull_thickness_m`, reverses its winding AND
its normals, and welds it to the outer surface, so the bake returns a closed shell with a real
cavity. The report gained `interior_mesh`, `interior_tris`, `interior_volume_m3`,
`shell_volume_m3` and `shell_mass_kg`; `volume_m3` deliberately keeps its old meaning (the OUTER
volume, which is what every budget reads).

The conflation this entry named turned out to be exactly the cause: SPEC section 7's "no walls" is
about JOINT partitions, and had been read as covering the hull's own skin. It does not. Joint
partitions remain unbuilt, as designed.

**2. Component palette — RESOLVED 2026-08-31.** The part palette lists `doc.components` under the
shape grid, MAKE COMP prompts for a name, and clicking a component arms a real placement ghost
(`ShipBuilder.begin_component_placement`). Driven end to end in `scratch/diag_component.gd`.

**3. "Skew" on the post-placement handles - RESOLVED 2026-09-01 (ADR 0007).**
> "spor has handles that reveal after placement that lets you stretch, skew, twist, rotate etc"

All four verbs now exist. `SdfOps.shear()` is a domain warp; `ResolvedShape.shear` carries it;
`skew_x` / `skew_z` are params on every family; and the TOP and BOTTOM morph arrows do double duty
- pulled along their own axis they stretch, pushed sideways they lean.

It needed exactly the ruleset decision this entry predicted, plus one nobody predicted: a domain
warp CANNOT be appended to the op order, because everything after the base operates on a distance
rather than a point. Shear is therefore the one op inserted rather than appended, and it is only
safe because at zero it is the identity - asserted bit-exactly, not approximately. SPEC section 4
carries the exception with its reasoning attached.

**4. Hatch authoring UI.** Judged SATISFIED for this phase, recorded so the judgement is visible:
the author said "full hatch authoring, but doesnt need to be actually implemented in this phase,
just track the connection datas." `ShipJoints` discovers and stores joint pairs and
`data/shapes/hatches.json` is schema-clean, so the connection data IS tracked. There is no UI to
pick a hatch configuration, and by that sentence there does not need to be one yet.

**5. `data/paint_styles.json` was not in the validator's pack list — RESOLVED 2026-08-31.**
`tools/ship_validate_data.gd` `_PACKS` omitted it, so the one pack `PaintPanel` reads was the one
pack never checked against its schema. Added; it validates clean.

**6. BUILD | PAINT should probably swap the LEFT column, not add a right one.** In Spore these are
modes, and the palette changes contents with the mode. Mounting PaintPanel as a third permanent
panel costs the inspector half its height at the device's 1280x800. Deliberately NOT changed
unilaterally — it moves a panel the author has not seen yet, and the current layout works.

## F11 — Every antialiased edge in the console was being erased — RESOLVED

Recorded because it explains a complaint that was answered wrongly twice. The author reported
"its hard to read that font esp at that size" and the response was to look at font SIZE. Size was
half of it. The other half: `shaders/palette_post.gdshader`'s branchless nearest-entry search was
mapping every non-exact colour to `palette[0]`, the background — measured with a swatch strip,
`#ffffff -> #081216`. Glyph antialiasing is *entirely* non-exact colours, so every letterform was
being reduced to a hard 1-bit stencil against the background.

**Lesson, and it is the same one as F0 and F8:** a rendering claim is only worth what its
measurement is worth. Three rounds of "verified with a screenshot" passed over this because the
screenshots were only ever checked for "did something draw". `tools/ship_visual_check.gd` exists to
make the check adversarial instead: it fails on off-palette pixels, on collapsed shading bands, and
on two display modes producing identical frames.

---

## F12 — A laterally-spread part still lifts off a CONVEX parent — OPEN

`offset == 0` seats a child by pushing it out along the parent's surface NORMAL by the child's own
extent in that direction (`ShipAttach.support_inset`, ADR 0004). That is exact on a locally flat
surface and an under-push on a convex one: a part whose contact material sits away from its own
axis rides up the curvature.

Measured, torus_ring on a 5 m sphere parent at offset 0: **0.20 m gap**. The torus's lowest
material is 1.5 m off its own axis, so seating it by the distance straight down its axis leaves
the ring hanging. Every other family on that sphere, and every family on a flat parent, touches —
`tests/core/test_attach.gd::test_no_family_floats_off_its_parent_at_any_tilt` gates the flat case
across all six families and five tilts.

**Not fixed, deliberately.** The correct answer is a contact solve — push out until the minimum of
the parent's field over the child's surface reaches zero — and that is a 1-D root find with a
surface sweep inside it, per part, inside `resolve_all`, which runs on every document change. It
would also enter the hash.

**Re-examined 2026-09-01, and the cheap version this entry proposed does not work.** Two candidate
shortcuts were worked through and both are wrong:

- *Sample the child's AABB corners against the parent field.* An AABB corner is OUTSIDE the child's
  real surface for anything rounded, so seating against it pushes the part away and manufactures the
  very gap this is about.
- *Probe the parent's field at the child's lateral reach and subtract the drop* (4 sdf evaluations,
  no traces — genuinely cheap). Correct for the torus, wrong for a box: a box's material at its
  lateral reach is at the SAME height as its centre, so the correction would sink a flat-faced part
  into a curved parent until its corners touched and bury its face. The correction has to know how
  far down the CHILD reaches at that lateral offset, which means sampling the child's own surface.

The cheapest honest version is therefore `SnapTargets.for_shape(child)` — already-projected,
already-deterministic surface points — evaluated against the parent field: roughly 105 extra field
evaluations per part per rebuild, on a path that runs on every drag frame. That is a real cost for
a 0.20 m gap on one family/parent combination that has a one-key workaround, so the decision stands.
It is recorded here so the next person does not re-derive the two dead ends.

Workaround today: nudge `OFFSET` negative, which is what it is for.

**Mitigated 2026-09-02; still OPEN at flush.** A part now STARTS sunk: every creation path seeds
`offset` from `ShipAttach.default_offset()`, which samples the child's sole (`sole_points()` - the
lowest point of each column of its -Y footprint) against the parent's field and bisects the offset
until the deepest sole point sits `attach_embed_m` inside. Measured on the surfaces, so a ring on
a sphere seats by its rim and not by its axis - the "sample the child's own surface" answer this
entry arrived at, paid ONCE at placement instead of on every rebuild, which is why it is affordable
there and still is not in `resolve_all()`. `offset == 0` is unchanged: a player who types 0 gets
flush, and flush on a convex parent is still what this entry describes. See F16.

---

## F13 — A part "disappears" after repeated rotation or offset drags — RESOLVED

Reported: "after some rotations it just disappears. and after some offsets it disappears."

`scratch/diag_vanish.gd` drives 14 rotation drags and 14 offset drags through ShipView3D's own
press/drag/release path, frames the camera once, and after each release checks: present in the
document, present in the scene builder's visuals, placement not left live, nothing suppressed,
gate validity, and the fraction of the rendered frame wearing the selected part's ramp. Nothing
fails. The visible fraction never drops below 1.13%.

Candidates ruled OUT by that run: `remove_if_dragged_off()` firing, a refused commit leaving the
real part suppressed behind a faint ghost, the budget guard rolling the document back, and the
part being pushed out of frame by offset (it stays in frame to 7 m).

Candidates NOT ruled out, because the synthetic drive does not exercise them:
- repeated STRETCH drags on the shrink side - six presses at 0.8x reach 0.26 scale, which is
  nearly invisible and is not what "rotations or offsets" describes, but is worth excluding;
- rotating or offsetting the ROOT part, which has no parent surface to seat against;
- a part whose mirrored TWIN is what was being watched, so breaking symmetry or crossing the
  centre line removes the half being looked at;
- an interaction with the camera orbit during the drag.

**To locate it, the useful details are:** which handle, whether the part was the root or a child,
whether UNDO brings it back, and whether the tree panel still lists it after it goes.

**RESOLVED 2026-09-02.** The author answered: "undo brings it back. it happens with random rotation
(try in every direction around all axises) and also when sinking a part into its parent." UNDO
bringing it back meant a DOCUMENT edit, and the only edit a release makes on its own is
`ShipPlacement.remove_if_dragged_off()` - the candidate the synthetic drive above had "ruled out",
because the drive never let a release stray off the parent's silhouette. Four faults stacked:

- the placement arrow won hit-test ties against the rotation rings (it runs from the part's
  origin to the parent's, so it crosses every ring somewhere), so a grab on a ring at the crossing
  became a placement drag - `ship_handles.gd` now tests the rings first;
- a gizmo release was treated as an ordinary drag and re-solved the ghost from the pointer, so a
  rotation whose pointer ended off the silhouette landed as a drag-off - `ship_view3d.gd` records
  `_release_may_remove` before the handle is cleared, and only a plain surface drag may remove;
- the off-ship probe ignored the moving part and its subtree, so the ray "missed" whenever the
  pointer was over the moving part's own body, which is most of the time - the test is now
  against the ship's bounds with the ghost included (`ShipPlacement._pointer_off_ship`), and the
  VERTICAL / HORIZONTAL modifier drags never count;
- `remove_if_dragged_off()` deleted on any collider miss, which is how a Ctrl-drag sinking a part
  into its parent ended with no part.

Gated: `tools/ship_visual_check.gd` drives five releases through the real input path - the
placement arrow, a G-move released over the part's own body, a Ctrl-drag sinking the part, a ring
drag released off the silhouette, and a G-move released in empty space - and asserts the first four
keep the part and only the last removes it. All five read as expected on 2026-09-02.

---

## F14 — `ShipConfig` gained four levers the frozen contract does not list — OPEN, DELIBERATE

`root_span_m`, `room_span_m`, `tunnel_bore_m` and `tunnel_length_m` were added to `ShipConfig`,
`data/tuning.json` and `data/schema/tuning.schema.json` on 2026-09-01. `docs/API_CONTRACT.md`
section 3 pins the lever NAMES and is frozen for M1-M6, so this is recorded rather than done
quietly.

Additive, not a change: every name the contract lists still exists, means the same thing and reads
from the same place, and `ShipConfig.from_dict()` falls back to the code default for any lever a
pack omits — so a `tuning.json` written before these existed still loads, and any agent compiling
against the contract's list is unaffected. The same reasoning F1 uses for adding an optional
trailing `progress: Callable` to `bake()`.

They exist because three of the author's requests are SIZES that must not be hardcoded in a panel:
"the player should pick the first base primitives' and it should be 5m^3 diameter/bounding box",
and "make teh smallest room module the default ... skinny tunnels like 3ft and the rooms like 9f
(but 1m and 3m really)". A number typed into `start_dialog.gd` would have been unfindable and
untunable; a lever in the tuning pack is both, and carries its own description and slider bounds.

**If the contract is ever unfrozen, section 3 should absorb these four rather than treat them as
strays.**

## F15 — `ShipDoc.create_new()` and `ShipView3D.setup()` gained trailing optional arguments — OPEN, DELIBERATE

`create_new(family, manufacturer, data, span_m := 0.0)` and `setup(theme, owner_builder := null)`.
Both are pinned by `docs/API_CONTRACT.md` and both were extended rather than changed: every
existing call site passes the original argument count and gets the original behaviour exactly.
This is the pattern F1 already established for `HullBake.bake()`.

`span_m` is what stops a new ship's size from being an accident of which family the player clicked
(see F14). `owner_builder` gives the 3D view the application root it needs for the two keyboard
verbs that edit the document directly (`ShipReseat`); a host that omits it simply has no arrow-key
stepping and no numpad-0 aim, rather than a crash.

## F16 — A new part starts sunk into its parent, not flush — OPEN, DELIBERATE

> "your default modles do not overlap enough, when attaching an object to a sphere surface
> obviously its at its tangent point and theres no real connection. ALL added parts must by
> default upon placement be deep enough such that there are no barely touching surfaces."

`ShipConfig` gained `attach_embed_m` (0.45) and `attach_embed_max_fraction` (0.5), in
`data/tuning.json` and its schema, and `ShipAttach` gained `default_offset(parent_shape,
child_shape, part, cfg) -> float` and `sole_points(shape) -> PackedVector3Array`. Neither is in
`docs/API_CONTRACT.md` section 3 or 12; both are additive in the F14 sense - every pinned name
still exists and means the same thing, and a `tuning.json` without the levers loads on the code
defaults.

The attach model (SPEC section 3, CONTRACT) is untouched: `offset` still means what it meant,
`offset == 0` is still flush, and the hash still consumes the stored offset. What changed is the
NUMBER a new part is created with. The palette drop, `ShipBuilder.add_part()` and the stock
templates all seed the offset from `default_offset()`, which is measured on the child's sole
against the parent's field rather than read off the child's mount inset, capped at
`attach_embed_max_fraction` of the child's own height so a thin plate is not buried. A pair that
cannot reach the target (a ring whose tube is thinner than it, a wide part overhanging a narrow
one) is sunk to the shallowest offset with nearly its best contact instead; a pair that never
touches stays flush. `tests/core/test_attach_embed.gd` gates it across the family pairs, and
`tests/core/test_rooms.gd::test_a_default_placement_meets_its_parent_for_a_hatch` asserts every
compact pair at a default placement MERGES at the hull thickness - which is what makes F18's
"any two parts that meet can be hatched" true out of the box.

**If the contract is ever unfrozen, section 3 should absorb the two levers and section 12 the
two functions.**

## F17 — Component instances are expanded by the attach pass; what that still cannot do — OPEN, KNOWN LIMITATIONS

> "when i selected multiple parts and press make component they all dissapear."

They disappeared because an instance resolved to its definition's ROOT alone: the scene builder,
the SDF and the budgets all walk `ShipAttach.resolve_shapes()` / `resolve_all()`, and nothing put
the rest of the definition into either. Now `resolve_shapes()` emits every inner part but the root
under `"<instance>/<inner>"` (nesting chains keys), `resolve_all_from_shapes()` hangs their
transforms from the instance's own, twins included, and `ShipComponents.expand()` reads those
entries back out - so the contract's `expand()` still returns exactly what section 20 says, from a
different source. `ShipMetrics.compute_cost()` costs an instance as the sum of its definition's
parts. `ShipComponents.is_expanded_id()`, `instance_of()` and `definition_order()` are the
additive helpers every consumer uses to tell an expanded key from a doc part.

Gated by `tests/core/test_component_expansion.gd` (the geometry an attach pass places is identical
before and after a lift, compared as geometry because a lift renames every part it takes) and by
the MAKE COMP stage of `tools/ship_visual_check.gd` (mesh count before == after, origins unchanged,
undo restores the parts).

What it deliberately does NOT do yet, read off the code rather than reproduced unless stated:

- **A component is one part to the player.** A pick on an expanded mesh resolves to its INSTANCE
  (`ShipSceneBuilder.part_id_for`), so a part dropped on an inner part attaches to the instance and
  seats on its proxy surface - the definition root's shape - not on the inner part it was dropped
  over. Selecting, moving and deleting an inner part on its own is not possible by design.
- **The palette ghost of a component is its proxy alone.** A NEW instance dragged from the
  palette resolves through `resolve_shapes_for_part()`, which knows one part; the expansion only
  exists in the document's attach pass. Moving an EXISTING instance shows the whole thing, because
  its riders come from that pass.
- **Inner parts twin on the instance's terms.** Whether an expanded part gets a symmetry twin
  follows the instance's asymmetric flag and each inner part's own position; an inner part's own
  asymmetric flag is not consulted.
- **A definition whose root is itself an instance resolves to nothing.** `_component_proxy_shape`
  reads the root's `family`, which for an instance is a component id and not a family, so the
  proxy is null and the whole instance is absent from the shapes map. `make_component()` does not
  refuse a selection headed by an instance, so this is reachable. Not reproduced.
- **A definition whose root FAMILY is unresolvable (a pack that lost the family) draws and bakes
  as nothing for the whole instance** - the proxy is null and the expansion is skipped - while its
  transforms and its cost, which reads the definition, still exist. Raised by review, not
  reproduced; the validator already reports a missing family.

## F18 — Additive contract extensions of 2026-09-02 — OPEN, DELIBERATE

Recorded in the F14/F15 pattern: every pinned name still exists and behaves as pinned; these are
additions, and one changed DEFAULT.

- `ShipPart.ROLE_ROOM = "room"`, `ShipPart.ROLE_HALLWAY = "hallway"`, `ShipPart.is_room()`. The
  contract's section 9 marks `role` RESERVED with the vocabulary `"" | "structural" | "greeble" |
  "mount"`; `"room"` had been in use since 2026-09-01, and **the default for a NEW part is now
  `"room"`** ("each and every primitave should by default be a room"). `from_dict()` keeps reading
  `""` from a file that has no role and `to_dict()` writes it back as `""`, so an old file's
  canonical form and hash are untouched - no ruleset bump - and `is_room()` is true for `"room"`
  and `""` alike. A new document hashes with `"room"` on every part, which is its recorded truth.
- `ShipJoints.SOLID_SAMPLE_STEPS` and `ShipJoints.solid_pair_state(shape_a, xform_a, shape_b,
  xform_b, thickness) -> {"overlaps", "merges"}`: the one pair test the validator
  (`ShipValidate._solid_pair_state`) and the tree panel's LINK HATCH refusal both call, so the
  panel and the validator cannot disagree about whether two parts meet.
- `ShipComponents.is_expanded_id()`, `instance_of()`, `definition_order()` (F17).
- `ShipAttach.default_offset()`, `sole_points()` (F16); `resolve_shapes_for_part()` and
  `resolve_all_from_shapes()` predate this and were never pinned either.
- `ShipTutorial.current_step()`, `step_count()`, `press_next()`: read-only and one press, so the
  visual gate can drive the card the way a player does. `ShipTutorial` is harness, which section
  22 does not pin function by function.
- `ShipComponents.make_component()` re-seats joints (F17's mechanism, `_reseat_joints`): a joint
  between a lifted part and an outside part is kept under its own id against the instance; a joint
  wholly inside the lift is dropped; two joints landing on one pair collapse to the hatched one,
  and between equals the lower id. Behaviour the contract does not describe either way.

**If the contract is ever unfrozen, section 9 should state the `role` default and vocabulary,
section 20 should absorb the three helpers and the joint rule, and section 21 the pair test.**

## F19 — Additive contract extensions of 2026-09-02b: seams, walls, the exploded view — OPEN, DELIBERATE

ADR 0008. Recorded in the F14/F18 pattern: every pinned name still exists and behaves as pinned;
these are additions, and one of them changes what a bake produces.

- **`ShipJoint.MODE_DOORWAY = "doorway"`**, in `VALID_MODES`. Section 10 pins the vocabulary as
  `"open" | "hatched" | "sealed"`; a plain opening with no hatch hardware is the fourth way two
  rooms link, and `from_dict()`'s unknown-mode fallback to `open` would have silently merged two
  rooms a file said had a doorway. `to_dict()` writes it as `"doorway"`. A doc that never uses it
  is byte-identical on disk; no ruleset bump, the hash never consumed joints.
- **`ShipAttach.anchor_for(parent_shape, part, cfg) -> {"pos", "normal"}`**: SPEC 3 steps 1–3
  alone, in host-local space, both paths (snap target / trace). `local_transform()` is now built
  on it; results are bit-identical (the same calls in the same order). Section 12 should list it.
- **`core/sdf/ship_seams.gd` — `class_name ShipSeams`** (static only): `seams()`, `mode_for()`,
  `hole_for()`, `hole_distance()`, `module_ids()`, `module_of()`, `explode_offsets()`, and the
  `MODE_*` / `SEAM_*` / `HOLE_*` / `KIND_*` vocabulary. A new core class; the contract has no
  section for it. `--import` was run.
- **`ShipSdf`** gains `seams()`, `seam_count()`, `thickness()`, `plate_thickness()`,
  `module_view(module_id) -> ShipSdf` and `with_min_wall_m(m) -> ShipSdf`. Section 13's pinned
  six are unchanged in name and signature. **`sample()` now returns the field WITH seam plates**
  for any doc whose parts stand on each other with a non-`open` joint (which is every doc with
  more than one part) — the bake produces walls where it produced the studio hull. `sample_part()`
  is the bare part, as it always was.
- **`SurfaceNets.fitted_cell(size, cell)`**: the spacing `extract()` will really use. Section 17
  should list it.
- **`HullBake.bake()`** is unchanged in signature and now extracts from
  `sdf.with_min_wall_m(fitted_cell * WALL_MIN_CELLS)`: a plate thinner than a grid cell is a bump
  the grid steps over, so it is widened INTO the host to at least one cell. The report's numbers
  keep their meanings. Section 18 should say so.
- **`ShipConfig`** gains `doorway_width_m`, `doorway_height_m`, `explode_gap_m`,
  `explode_cells_per_axis` — in `from_dict`, `snapshot`, `data/tuning.json` and its schema
  (extends F14's list).
- **`ShipHandles.hit_test()`**'s sixth optional parameter changed: `parent_local: Vector3` ->
  `seam_local: Transform3D`, plus a seventh `has_seam: bool`. Harness, not pinned function by
  function (section 22), and the only caller is `ShipView3D`. `Handle.PLACEMENT` keeps its
  number and its meaning; only the geometry it is hit-tested against moved.
- **`harness/builder/ship_explode_view.gd` — `class_name ShipExplodeView`** (Node3D), and the
  builder's `set_exploded()`, `is_exploded()`, `link_mode()`, `cycle_link()`, `LINK_CYCLE`;
  the view's `set_exploded()`, `is_exploded()`, `get_explode_view()`; the scene builder's
  `set_exploded()`, `is_exploded()`, `part_seam()`, `part_has_seam()`, `set_handle_pixel_size()`,
  `solid_material_for()`. Harness.
- **`ShipReseat.step_snap_target()` and `ROW_STRIDE` are gone** (replaced by `step_placement()`);
  both were harness and never pinned.

**F10 item 4, revisited.** The link modes now have UI (the tree panel's LINK cycles them) and
geometry. Hatch FAMILY picking is still the default family (`ShipTemplates.DEFAULT_HATCH`, or
whatever the joint already carries): the hole is cut from the family's pack defaults merged with
the joint's stored params, so a family chosen any other way — a template option, a hand-edited
file — is honoured. A picker is the remaining piece of that item.

**Known limits, recorded rather than hidden.** RETIRED(ADR 0034, 2026-09-22): "A seam exists only
where a part stands on its parent; two siblings that overlap have no attach plane and merge as they
always did, whatever joint they carry" -> a JOINED pair that meets has a seam wherever the two
stand, from the line between their centres (`ShipSeams._sibling_seams`). A pair with no joint
record still merges. The metrics grid (`metrics_cell_m`, 0.5 m) is coarser than a wall and does not
see the plates, so the interior-volume gauge reads the studio hull's cavity; the bake report
does not. The explode view's per-module cell is coarse by design (`explode_cells_per_axis`).

**If the contract is ever unfrozen, section 10 should state the four modes, section 12 should
list `anchor_for`, section 13 should describe the plates and `module_view`, sections 17 and 18
the fitted cell and the widening, and a section 25 should pin `ShipSeams`.**


## F20 — Additive contract extensions of 2026-09-02c: Dual Contouring, seam styles, FRESNEL — OPEN, DELIBERATE

ADR 0009. Same pattern as F14/F18/F19: every pinned name still exists and behaves as pinned.

- **`SurfaceNets._place_vertex()` changed signature** — `(crossings)` -> `(crossings, corners,
  cell_min, size)`, and now solves a QEF. Private, but API_CONTRACT section 17 names the function
  by name as the isolated site of vertex placement, so the change is recorded. Section 17 should
  drop the word "Naive" and say Dual Contouring.
- **`SurfaceNets._trilinear_gradient()`** (new, private) and the `QEF_*` constants.
- **`ShipJoint.SEAM_FLAT` / `SEAM_PARENT` / `SEAM_CHILD`, `VALID_SEAM_STYLES`, `seam_style`**.
  Section 10 pins the record; `seam_style` is additive and is written to `to_dict()` ONLY when it
  is not `flat`, so no existing file's canonical form or hash moves. Measured: the selfcheck doc
  hashes `5536787c6c35d236` before and after.
- **`ShipSeams.SEAM_STYLE`, `STYLE_FLAT/PARENT/CHILD`, `style_for()`**; the seam record carries a
  `style` key.
- **`ShipSdf.style_code()`, `ShipSdf.Clip`** (a nested class), and the plate/module-view rework.
  The pinned six functions of section 13 are untouched in name and signature. `sample()` now
  honours the seam style, which changes geometry only for a doc that sets one.
- **`ShipSceneBuilder.DisplayMode.FRESNEL`** — appended, so no existing value moves; plus
  `materials_for()`, `mode_shows_solid()` (replacing `solid_material_for()`, which pinned the
  exploded modules to one mode) and `_fresnel_ramp()`.
- **`shaders/part_faceted.gdshader` gains `lambert_strength`**, so a mode can stand the shading
  down and leave the rim as the only lit thing.
- **`ShipMeshGen.wire_from_mesh()`** — the wireframe of an arbitrary mesh, for the baked modules.
- **`ShipExplodeView.module_body()`, `set_display_mode()`, `set_selection()`, `WALL_PREVIEW_CELLS`**;
  **`ShipView3D.seam_menu_requested`** (a new signal), `_explode_left_button()`,
  `_track_right_button()`; **`ShipBuilder.SEAM_STYLE_ITEMS`** and the seam-style edit;
  **`harness/panels/ship_context_menu.gd` — `class_name ShipContextMenu`** (new);
  **`tools/ship_check_views.gd` — `class_name ShipCheckViews`** (new). All harness or tools, which
  section 22 does not pin function by function.
- **`ShipConfig.explode_cells_per_axis` default 32 -> 48**, in `data/tuning.json` too.

**Known limits, recorded rather than hidden.**

1. **A module's pick collider is CONVEX**, so a click into a module's open cavity selects that
   module rather than what is behind it. A trimesh collider was built first and could not be hit
   at all (ADR 0009, Consequences); convex is what parts already use and what this space is known
   to raycast.
2. **The exploded view previews walls at 1.6 grid cells**, not at `hull_thickness_m`. It shows
   where the walls are, not how thick they are; the assembled bake is unaffected.
3. **`flat` on a curved host is a tangent plane**, so the two cavities can meet around its rim.
   The `parent` and `child` styles are the exact answers there, and the author asked for them.
4. **The metrics grid still does not see plates** (F19 limit, unchanged): the interior-volume
   gauge reads the studio cavity while the bake report does not.

**If the contract is ever unfrozen, section 17 should describe Dual Contouring and the new
`_place_vertex()` signature, section 10 the seam styles, and section 13 the styled plate.**

## F21 — Additive contract extensions of 2026-09-03: the simplification stage — OPEN, DELIBERATE

ADR 0010. Same pattern as F14/F18/F19/F20: every pinned name still exists and behaves as pinned,
and `SurfaceNets` — the class section 17 pins — is not touched at all.

- **`core/bake/hull_simplify.gd` — `class_name HullSimplify`** (new, static only). One public
  entry, `simplify(field, verts, idx, iso, cell) -> Dictionary`, returning `vertices`, `normals`,
  `indices`, `patches`, `planar_patches`, `flat_tris`, `curved_tris`. `field` may be null.
- **`HullBake.bake()` gained a report key, `planar_patches`** — how many flat faces the outer
  surface was rebuilt as; a box reports 6. Section 18 pins `bake()`'s signature, which is
  unchanged; the report is a dictionary and every existing key still carries what it carried.
- **`tests/core/test_simplify.gd` — `class_name TestSimplify`** (new).

**Known limits, recorded rather than hidden.**

1. **Curved regions are not decimated.** A cylinder or a torus keeps every triangle Dual
   Contouring gave it, smooth-shaded from the analytic gradient. That is deliberate — a cylinder
   showing its tessellation is what CAD looks like — but it does mean the triangle win is
   concentrated on flat-faced parts. A curved-region pass needs a geometric error metric and is
   the obvious next step if the count still bites.
2. **Absorption squares off any fillet the grid cannot resolve.** A `round: 0.02` corner at a
   0.25 m cell becomes a sharp corner, so the baked hull is very slightly larger than the field
   it came from — a lone box with `round: 0.02` reads 8.437 m³ against the field's 8.490 m³ AABB.
   The alternative is the band of noise this replaced. It is a preview-and-report mesh, never the
   source of truth; metrics run their own co-area grid (SPEC §8) and are unaffected.
3. **A patch that cannot be retriangulated safely keeps its original triangles.** An unbridgeable
   hole or an ear-clip returning the wrong triangle count falls back rather than risking a torn
   face, so a pathological patch degrades to the old density silently. `planar_patches` in the
   report is how you notice: it counts only the patches actually rebuilt.
4. **The exploded view's 1.6-cell wall preview (F20 limit 2) is unchanged**, and was measured to
   be inert at default settings — `max(0.4, 0.25 * 1.6)` is 0.4, the real thickness. It only bites
   on modules longer than 8 m. Left alone deliberately: it is the only thing keeping a large
   module's walls visible at all, and nothing in this ADR made it worse.
5. **The metrics grid still does not see plates** (F19/F20 limit, unchanged).

**If the contract is ever unfrozen, section 17 should say that `SurfaceNets` output is a sampling
and not a mesh, a new section should describe `HullSimplify`, and section 18 should list the
`planar_patches` report key.**


## F22 — Additive contract extensions of 2026-09-03b: the exact mesh path — OPEN, DELIBERATE

ADR 0011. Same pattern as F14/F18/F19/F20/F21: every pinned name still exists and behaves as
pinned. Nothing in `core/sdf/` or `core/bake/surface_nets.gd` is touched, and `HullBake.bake()`
keeps its signature and every report key.

- **`core/mesh/` — a new directory** holding `PolyMesh`, `Poly2D`, `MeshCsg`, `MeshMerge` and
  `ShapeMesh`. All `core/`-pure: `RefCounted` or static-only, no `Node`, no `res://`.
- **`core/bake/ship_mesh_bake.gd` — `class_name ShipMeshBake`** (new). `bake(doc, data, cfg,
  segments)` and `bake_part(doc, data, cfg, id, segments)`.
- **`tests/core/test_mesh_csg.gd` — `class_name TestMeshCsg`** and
  **`tests/core/test_shape_mesh.gd` — `class_name TestShapeMesh`** (new).
- **Harness, which section 22 does not pin function by function**:
  `ShipExplodeView.show_modules()` and `ShipView3D.set_exploded()` each gained a trailing optional
  `solids: Dictionary = {}`; `ShipExplodeView._place_module()` is new (private).

**Known limits, recorded rather than hidden.**

1. **`round`, ribs and scallops are not built.** They are OFFSET and DISPLACEMENT ops rather than
   domain warps, so no amount of moving a base vertex reaches them — a rounded box needs real
   fillet geometry along twelve edges and eight corners. A part carrying one bakes SHARP and reads
   larger than its field by exactly `round_r * min(scale)`. That is not slack: `TestShapeMesh`
   computes the figure and asserts the disagreement never exceeds it, so the day fillets are built
   the test tightens on its own.
2. **A circle is a 24-gon** (`ShapeMesh.RADIAL_SEGMENTS`), matching SketchUp's default. It is a
   constant rather than a `ShipConfig` lever, so changing it today means editing `core/` — worth a
   lever the moment anyone wants to tune it per part.
3. RETIRED(2026-09-03c): "Parts overlap where they meet, and are not trimmed." They are trimmed
   now - the three ADR 0009 seam styles reach the mesh, non-destructively, read from the joint
   rather than baked into the part. What remains untrimmed is the OPENINGS: hatch and doorway
   holes are not bored into the exact mesh yet, so a seam that is a doorway currently shows as a
   plain mating face. `MeshCsg.subtract` is built and tested for it.
4. **A module made of several placed ids still uses the Surface Nets path.** The exact bake is per
   PART; combining several parts into one module solid is a boolean, which belongs with the seam
   work. In practice this is only an expanded component instance.
5. **Repeated unions of NEAR-COPLANAR solids are slow.** Measured: exactly tangential placement is
   fine after the flood-fill fix (nine parts, ~1.5 s, linear), but a mixed near-coplanar assembly
   still degrades. Architecturally unreachable today — `ShipMeshBake` runs no boolean at all — and
   `MeshCsg`'s split budget bounds any single operation. Worth revisiting before the seam work
   leans on repeated booleans.
6. **`ShipMeshBake` reports `parts_volume_m3`, which is the SUM OF THE PARTS** and therefore
   over-reads the ship wherever two overlap, which is at every joint. Named that way on purpose;
   `ShipMetrics` remains the answer for what the ship encloses.

7. **`MeshMerge` decides in three passes and the order is load-bearing.** Rings are walked and
   CHECKED BY AREA first, then the surviving corners are chosen GLOBALLY, then faces are emitted.
   Both orderings were arrived at by measurement: dropping a collinear vertex per face put back
   the very T-junctions the repair had just fixed (a hull with two collars: 0 open edges repaired,
   46 after a per-face drop), and validating a group AFTER the keep set was chosen left a rejected
   group holding vertices its merged neighbours had already dropped (7 open edges). A merge that
   cannot reproduce a group faithfully keeps that group original faces - it is a tidying pass and
   must never make a solid worse.

**If the contract is ever unfrozen, a new section should describe `core/mesh/`, and section 18
should note that `HullBake` is no longer the only bake.**


## F23 — The FLAT seam plane is a TANGENT on a curved host — RESOLVED by ADR 0012

The seam frame sits at the ATTACH POINT on the host's surface, and the FLAT style cuts the child on
the plane through it. On a flat host face that plane IS the host's surface and the fit is exact. On
a curved host, or at a box CORNER, it is only the tangent there:

- a sphere child on a sphere host actually intersects it along a CIRCLE, and that circle's plane
  sits below the tangent plane, so a flat cut takes off more than the overlap;
- `argon` attaches eight branches at the corners of a box, where the tangent plane touches at a
  single point and the child's overlap reaches well past it.

This is not new — ADR 0009 recorded it as F20 limit 3, "`flat` on a curved host is a tangent plane"
— but it became visible once the meshes were exact and separated: "somehow it cut the upper sphere
way into the sphere, and short of the lower sphere. so the cuts arent happening at intersection."

**`parent` and `child` are the exact answers today** and always were: both cut on the other solid's
real surface, so they fit whatever its shape. FLAT is the one that trades exactness for a flat
mating face.

**The open question is where a flat plane should sit.** Two spheres intersect in a circle, and that
circle is planar, so "a flat plane at the intersection" is well defined for that case and is NOT the
tangent plane. Fitting the plane to the actual intersection curve would make FLAT mean what it says
on a curved host, at the cost of computing the curve. Left as a decision rather than taken
unilaterally, because it changes what an existing, authored setting produces.


## F24 — Additive contract extensions of 2026-09-03e: the flat flanges — OPEN, DELIBERATE

ADR 0012. `flat` is retired as a NAME and replaced by four; the string still loads.

- **`core/mesh/mesh_flange.gd` — `class_name MeshFlange`** (new), with a nested `Piece`. One public
  entry, `resolve(a, b, axis, origin, outward, slice)`.
- **`ShipJoint.SEAM_FLAT_IN` / `SEAM_FLAT_OUT` / `SEAM_SLICE_IN` / `SEAM_SLICE_OUT`**, and
  `SEAM_LEGACY_FLAT` for the old string. `SEAM_FLAT` survives as an ALIAS of `SEAM_FLAT_IN`, so
  every existing reference still reads and still means the default.
- **`ShipSeams.STYLE_FLAT_IN` / `STYLE_FLAT_OUT` / `STYLE_SLICE_IN` / `STYLE_SLICE_OUT`.**
- **`ShipMeshBake._apply_seams()`** gained `shapes` and `xforms` arguments (private).
- **Harness**: `ShipBuilder.SEAM_STYLE_ITEMS` is six entries.

**No hash moves.** `seam_style` is written to a document only when it is not the default, and the
default is still the flat family - so a joint that was `flat` wrote nothing then and writes nothing
now. Measured: the selfcheck doc hashes `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **Out-bump degrades on a many-branch hub.** It needs a UNION, the only operation that grows a
   mesh. On `argon`, whose hub takes eight, the first union was closed at 101 faces and the second
   left 60 open edges; unguarded it reached 11049 open edges and 73 seconds by the seventh. A union
   whose result is not closed is now REFUSED - the host keeps what it had - so `argon` finishes in
   24 s with every part closed and seven stubs not added. The gap that leaves was allowed for by
   the author ("if a thin unseen buffer of space is needed between modules thats fine"), but the
   real fix is a union that does not break, which is the same fragility F22 limit 5 records.
2. **Out-bump is slow even when it works** - about 24 s on `argon` against 594 ms for in-bump,
   because every refused union is still attempted before it is thrown away.
3. **A tube cut at a steep diagonal plane can leave the smaller solid with a few open edges** -
   measured, 9 on a tube meeting a box corner. In-bump on ordinary joints is clean.
4. **The SDF still knows only the ADR 0009 three.** `ShipSdf.style_code()` maps anything else to its
   own flat, so `module_view` treats all four flat styles as the old tangent cut. Nothing renders
   from that path now, so the divergence is cosmetic - but it is a divergence.
5. **`flat_in` and `child` reach the same shape on a flat host**, by different routes. Deliberate,
   and the author's reason is worth keeping: it "lets people quickly switch linkage manifolds
   without changing base shapes".


## F25 — Additive contract extensions of 2026-09-04: seams as two axes — OPEN, DELIBERATE

ADR 0013. A pure rename of six existing behaviours onto one scheme, plus the two-axis input.

- **`ShipJoint.SEAM_SMALL_FLAT_INSERT` / `SEAM_SMALL_FLAT_CUTOFF` / `SEAM_SMALL_NATIVE` /
  `SEAM_BIG_FLAT_INSERT` / `SEAM_BIG_FLAT_CUTOFF` / `SEAM_BIG_NATIVE`**, the axis constants
  `INDENT_SMALL` / `INDENT_BIG` / `SURFACE_FLAT_INSERT` / `SURFACE_FLAT_CUTOFF` / `SURFACE_NATIVE`,
  and `LEGACY_SEAM_STYLES`. `SEAM_FLAT` survives as an alias of the default.
- **`ShipJoint.indent_of()` / `surface_of()` / `style_for_axes()`** (new, static).
- **`ShipSeams.STYLE_SMALL_*` / `STYLE_BIG_*`.** `STYLE_PARENT` and `STYLE_CHILD` still exist and
  now point at the two NATIVE styles, so `ShipSdf` reads unchanged.
- **Harness**: `SEAM_STYLE_ITEMS` carries `header` rows; `ShipContextMenu.open()` renders them.
- **RETIRED**: `SEAM_FLAT_IN`, `SEAM_FLAT_OUT`, `SEAM_SLICE_IN`, `SEAM_SLICE_OUT`, `SEAM_PARENT`,
  `SEAM_CHILD` as ShipJoint constants. Every one of their STRINGS still loads.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **`big` / `small` is decided by VOLUME, where `parent` / `child` used the attach tree.** Most
   joints are unaffected because the tree parent is usually the larger solid. Where it is not, the
   answer changes - measured on `helium`, whose tunnel is the tree parent of a room ten times its
   volume: the old `parent` dented the ROOM, `big_native` dents the TUNNEL. This is the intended
   consequence of the reclassification, not a regression, but it does mean a ship built before the
   change can bake differently at such a joint.
2. **The out-bump limits of F24 are unchanged** and now read `big_flat_insert` / `big_flat_cutoff`:
   they need a union, degrade on a many-branch hub by refusing stubs rather than corrupting the
   hull, and are slow (~24 s on `argon` against ~0.6 s for the `small_` styles).
3. **The SDF still knows only its own three codes.** `ShipSdf.style_code()` maps the natives onto
   `STYLE_PARENT` / `STYLE_CHILD` and everything else onto flat, so `module_view` sees the ADR 0009
   model. Nothing renders from that path now.


## F26 — Additive contract extensions of 2026-09-04b: multi-seam styling and the atomic templates — OPEN, DELIBERATE

ADR 0014, plus the multi-select seam change.

- **`ShipConfig.template_volume_m3`** (new lever, default 8000.0), in `data/tuning.json` and its
  schema. Section 14's list of ShipConfig levers grows again, as F14 records it may.
- **`ShipTemplates.nucleus_count()` / `extremity_count()` / `body_count()` / `nucleus_dirs()` /
  `extremity_dirs()`** (new, static, public so a palette can describe a class without building it);
  `LINK_ROOT` / `LINK_FUSE` / `LINK_TUNNEL`, `MAX_NUCLEUS`, `FUSE_OVERLAP`, `SECTION_PERIODS`.
  `_node()` gained a trailing optional `link` argument.
- **`data/templates.json`**: a new `periods` section; elements carry `period` and `valence` and no
  longer carry `arrangement`, which is derived. Schema updated to match.
- **`ShipMeshBake._cut()`** (new, private) and the closure guard in `MeshFlange.resolve()`.
- **Harness**: `ShipBuilder._seam_pairs` replaces `_seam_pair`, `_common_seam_style()` and
  `_apply_seam_style()` are new (private), and `ShipView3D.set_exploded`'s right-click gate widened
  from exactly two selected parts to two or more.

**No hash moves.** Templates build documents; they are not part of one. Measured:
`5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **A seam operation that would open a closed solid is REFUSED**, and refusing leaves the two
   parts overlapping where they would have met flush. On a class whose nucleus hosts many seams -
   carbon has nine - some joints will not be cut. Closed and slightly overlapping beats flush and
   open, but the real fix is booleans that do not break, which F22 limit 5 and F24 limit 1 already
   record.
2. **Out-bump styles on a high-nucleus class do little.** Their stub unions are the operation most
   likely to be refused, so `big_flat_insert` on a carbon or argon class can come out looking much
   like `small_flat_insert`. Visible in the tests: the in/out difference is asserted over the WHOLE
   bake rather than over the host alone, because the host can legitimately come out unchanged.
3. **Molecule templates are unchanged in structure** - one room per node, joined by tunnels - and
   are NOT built on the nucleus-and-extremities model. They share the volume budget, so they are
   the right size, but a water-class ship is still three rooms on tunnels rather than three atoms.
4. **`MAX_NUCLEUS` is 8 and `valence` is capped at 8**, so classes past argon would repeat the
   argon silhouette. The pack stops at argon for that reason rather than by accident.
5. **Seam styling covers connections with BOTH ends selected.** A part selected on its own offers
   nothing, which is the reading that generalises the old two-part behaviour exactly - but it does
   mean there is no way to say "restyle everything attached to this one part" in a single gesture.


## F27 — Additive contract extensions of 2026-09-04c: the interior shell — OPEN, DELIBERATE

ADR 0015.

- **`ShapeMesh.inset(shape, thickness)`** (new, static, public) and `_collapsed()` (private).
- **`MeshFlange.resolve()`** gained a trailing optional `inset`; `small_plane_face()` is new.
- **`ShipMeshBake._apply_seams()`** gained `cutters` and `inset` arguments (private). The report
  gains `hull_thickness_m` and `hollowed_parts`.
- **Retuned levers**: `hull_thickness_m` 0.15 -> 0.20, `attach_embed_m` 0.45 -> 0.60,
  `tunnel_bore_m` 1.0 -> 1.4, `ShipJoints.SOLID_SAMPLE_STEPS` 10 -> 16. Each is the smallest value
  that satisfies a stated invariant at the new wall; each carries the reasoning at its declaration.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **Hollowing roughly doubles the bake.** Every part is now two tessellations, two seam passes and
   a subtraction: an argon class goes from about 0.6 s to 7.6 s.
2. **The interior is derived from the PRIMITIVE, not offset from the mesh**, so it is exact only
   where the primitive is. A sphere under non-uniform scale is an ellipsoid, and an ellipsoid inset
   by a constant is not another ellipsoid - the wall is made uniform by shrinking against the
   SMALLEST scale component, which is too thick on the long axes rather than too thin anywhere.
   Same for `round_r`, which is still not built at all (F22 limit 1), so a part with an authored
   fillet has a slightly larger wall than asked for at its corners.
3. **A part thinner than twice the wall stays solid.** Correct, and worth knowing: at a 0.20 m wall
   four of argon's twenty-four parts have no interior, all of them tunnels.
4. **`hull_thickness_m`, `attach_embed_m` and `tunnel_bore_m` are a coupled set.** Retuning one
   without the others breaks the "two interiors meet" invariant, and the failure is quiet - the
   validator reports a joint that only touches. The couplings are written at each declaration; the
   test that holds them to it is
   `test_attach_embed :: test_default_embed_joins_every_compact_pair_in_every_direction`, which
   reads the shipped defaults on purpose.
5. **Hatch and doorway openings are still not cut**, so a module is a sealed shell. That is the
   next piece of work, and it is what the interior was built for.


## F28 — Additive contract extensions of 2026-09-04d: LINK over a selection — OPEN, DELIBERATE

ADR 0016.

- **`ShipSeams.pairs_within(doc, ids)`** and **`ShipSeams.shared_mode(doc, pairs)`** (new, static,
  public). Which seams a selection contains, and what they currently are.
- **`ShipSeams.EXPLODE_RELAX_PASSES`** (new const) and `explode_offsets()` now separates SIBLINGS
  as well as clearing each module from its host. Same signature.
- **`ShipBuilder.cycle_link()` CHANGED SHAPE**: `(a: String, b: String)` -> `(ids:
  PackedStringArray)`. Not in `API_CONTRACT.md`; recorded in F-notes only, and the public-method
  count is unchanged at 30 (gdlint's cap).
- **`ShipMeshBake.bake()` report** gains `open_seams` and `pending_seams`.
- **REMOVED from `PartTreePanel`**: `_on_make_room`, `_make_room_named`, `_make_room_joined`,
  `_room_suggestion`, `_instance_of_definition`, and the MAKE ROOM button. LINK does the joining;
  the tree row does the naming.
- **REMOVED from `ship_visual_check.gd`**: `_rooms_name_one`, `_rooms_join_three`; added
  `_rooms_link_group` and `_sink_until_meeting`.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **Fused modules were never walled from each other.** Of argon's 23 seams, 14 are between nucleus
   bodies whose interiors already interpenetrate by 97-159 m3 - `FUSE_OVERLAP` is 0.34 of the span
   - so LINK OPEN correctly does nothing to them. ADR 0015's "a module is a sealed shell" holds
   PER MODULE (every one closes) but not BETWEEN two fused ones. This belongs with the hatch work.
2. **One seam in one class is a genuine miss**: lithium's tunnel-to-nucleus joint. Its plates come
   to 0.2 and 1.1 m3 and lie outside both shells - the interiors barely reach each other, the same
   marginal case the ADR 0015 tuning triple was built around.
3. **DOORWAY and HATCHED still resolve as WALL.** Reported as `pending_seams` rather than silently
   treated as done. Cutting a bounded opening and welding its frame is the next piece of work.
4. **`ShipComponents` still drops joints internal to a lift**, which walls them. MAKE COMP is the
   only caller now, and a component definition has nowhere to keep a joint (`{label, root, parts}`
   - adding one is a schema change and a ruleset bump). Making a room no longer goes through it.
5. **The bake roughly doubles again when everything is open**: an argon class 7.6 s -> 13.5 s. A
   ship with no open seam pays nothing - the extra surfaces are built only when one exists.


## F29 — Additive contract extensions of 2026-09-04e: the nucleus layout — OPEN, DELIBERATE

ADR 0017.

- **`ShipTemplates.root_slot(dirs)`** (new, static, public) and `_layout(data, element)` (private,
  the one place the whole arrangement is worked out). `nucleus_dirs()` and `extremity_dirs()` keep
  their signatures and are now views onto it.
- **`ShipMeshBake._apply_seams()`** gained a trailing `keep_open: bool`; `_pierce()` is new. The
  ADR 0016 bore - `_open_seams`, `_wall_between`, `_slab`, `seam_key` - is GONE.
- **`MeshFlange._footprint_cutter()`** gained a trailing optional `drop`.
- **`ShipSeams._descends_from()`** (private) - the explode relaxation's chain rule.

**No hash moves.** Measured: `5536787c6c35d236` either side. Template CONTENT does move - every
class above helium is laid out differently - but a template is a factory for documents, not a
document, and nothing about how one is read or hashed changed.

**Known limits, recorded rather than hidden.**

1. **DOORWAY and HATCHED still resolve as WALL**, reported as `pending_seams`. Cutting a bounded
   opening and welding its frame is the next piece of work, and it is now the only piece left
   between here and a hull a crew could walk through.
2. **A tunnel is still too thin to hollow at some sizes.** Argon now hollows 24 of 24 where ADR
   0015 measured 20 of 24, but the rule has not changed: a part thinner than two walls stays solid,
   and a seam between two such parts cannot be opened. It is reported, not silently skipped.
3. **`_apply_seams` is not order-independent for the FLAT styles**, whatever its docstring says: it
   flanges against `out[...]`, the accumulating result, not against `solids` as they arrived. On a
   nucleus where several bodies are the same size this decides which of a pair gets cut, and the
   answer depends on seam order. It has always been so; ADR 0017 did not introduce it and does not
   fix it. Worth a look before the hatch work leans on it.
4. **The arrangement for a given count is chosen by NAME order among equals.** Four slots resolves
   to `square` rather than `tetrahedral` because "s" sorts first. Deterministic, and arbitrary.
5. **Bake cost, measured across all 22 classes**: outer only 0-525 ms, shelled 13 ms - 3.9 s
   (`molecule:hydrogen_peroxide` is the slowest, argon 3.0 s). Every one closes.


## F30 — Additive contract extensions of 2026-09-04f: native open seams — OPEN, DELIBERATE

ADR 0018.

- **`MeshFlange.first_is_larger(a, b)`** (new, static, public) and **`MeshFlange.TIE_REL`**. The one
  tie rule; the flange, the native branch and the pierce all use it.
- **`ShipTemplates._hang_direction()`** (private). `nucleus_dirs()` unchanged in signature; a
  carbon rim now hangs 30 degrees below level, not 45.
- **`ShipMeshBake._pierce()`** re-shaped: `(solids, seams, shapes, xforms, thickness, segments)`,
  resolves every overlapping pair within a room (union-find over the open seams), natively and
  asymmetrically. `_join_rooms`, `_room_root`, `_pair_key` (private) are new.
  **`ShipMeshBake.OPEN_SEAM_CLEARANCE_M`** (new const, held at 0 - see below).
- **`ShipMeshBake._apply_seams()`** now skips an OPEN seam in BOTH passes.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **Two of a carbon nucleus's sibling cuts are refused.** Same-size boxes centred on each other's
   faces put faces on exactly the same planes, and once a target carries faces from an earlier cut
   on those planes the BSP's coplanar path fails the guard. Measured: in isolation every cut is
   right; accumulated, two of six rim protons keep their skin standing (30 m3) in the room beside
   them. **Robust coplanar handling in `MeshCsg` is the next piece of work**, and the only thing
   left between this and a nucleus that comes out entirely right.
2. **A clearance does not help; both directions were measured.** 1 mm and 1 cm (body grown, room
   shrunk) put the cutter near-coplanar and the bake did not finish in 400 s; the other way leaves
   a sliver the merge welds open. `OPEN_SEAM_CLEARANCE_M` is held at 0 and kept as the knob.
3. **`MeshCsg.intersect` can return more than one of its operands** on a heavily carved shell (252
   m3 from a 37 m3 solid with zero open edges). The probe flags it; the intrusion metric is not
   to be read on such a shell. Same root as limit 1.
4. **Sibling overlaps on a WALLED nucleus are still unresolved** - the attach tree has no seam
   between them, and joints are only over pairs the player links. ADR 0017 limit, unchanged.
   RESOLVED(ADR 0034, 2026-09-22): a joined pair that meets has a seam whether or not one stands on
   the other, and the nucleus writes its own joints.
5. **DOORWAY and HATCHED still resolve as WALL**, reported as `pending_seams`.


## F31 — Additive contract extensions of 2026-09-05: nested shells and surface unions — OPEN, DELIBERATE

ADR 0019.

- **`ShapeMesh.build()`** gained a trailing optional `phase`; `_base_mesh` and `_lathe` carry it.
- **`ShipMeshBake`**: `_nest()`, `_room_surface()`, `_clip_outside()`, `_zero_crossing()` are new
  (private); `PHASE_STRIDE` is a new const. GONE: `_pierce`, `_pair_key`, `OPEN_SEAM_CLEARANCE_M`,
  and the `_cut(outer, inner)` hollowing. The report gains **`absorbed: PackedStringArray`**.
- **`ShipExplodeView._bake_module`**: a solid that is present but EMPTY draws nothing (an absorbed
  room member); only a part absent from the solids falls back to the field.
- Tests: two per-part open-seam tests replaced by a room test and a sphere-shell test that builds
  every class on `sphere_pod`. Suite still 275.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **A room's seams are hairlines that do not close.** Each side of a two-member seam is bisected on
   its own edges, so the two boundaries agree only to a segment's sagitta - about 6 cm on a 9 m
   sphere at 24 segments. Carbon's six-proton room reports 464 open edges; it renders as a faint
   lip. Stitching both sides to one shared curve (insert each side's crossing points into the
   other's boundary, then T-junction repair) is the next piece of work.
2. **A room does not resolve its WALLED seams to the outside differently from a part**: each member
   is seam-cut as a part before the union, which is right for flat cuts and untested for the native
   styles on a room.
3. **The BSP is still used** for the flat footprint and the native walled styles. Same-axis lathes
   no longer share planes (the phase), which removes its worst case, not its brittleness.
4. **`MeshCsg.intersect` is unreliable on a heavily carved shell** (F30 limit 3, unchanged); probes
   flag it rather than read it.
5. **Every probe before this one measured boxes.** `ShipTemplates.build(..., {})` is a box; the
   author builds with `sphere_pod`. Recorded in memory so it does not happen again.


## F32 — Additive contract extensions of 2026-09-05b: the engine does the booleans — OPEN, DELIBERATE

ADR 0020.

- **`ShipCsgBake`** (new class, `harness/builder/ship_csg_bake.gd`, static): `bake(host, doc, data,
  cfg)` is a coroutine - callers `await` it - and returns the same report as `ShipMeshBake.bake`.
  `READ_WELD_M`, `READY_FRAMES`.
- **`ShipMeshBake.plan()`** and **`ShipMeshBake.report()`** (new, static, public); `bake()` is now
  `plan` + `_carve` + `report`. `CUT_BODY`, `CUT_ROOM`, `CUT_GROWN` name a part's cutters.
- **`MeshClip`** (new class, `core/mesh/mesh_clip.gd`): `Cutter`, `PlaneFinder`, `clip`,
  `clip_all`, `subdivided`, `seam_split`, `take` and the field combinators. The pure executor's
  primitive; `seam_split` is kept for the record and is NOT on the bake path.
- **`ShipBuilder._explode_baking`** (private var); `_set_exploded` is a coroutine. The visual check
  waits on the flag.
- **`ShipTemplates._local_direction()`** (private); a pod node carries `"world": true`.
- **`ShipConfig.hull_thickness_m`** default 0.20 -> **0.10**.
- **RETIRED**: `ShipMeshBake._pierce`, `_room_surface`, `_fuse`, `_open_seams`, `_cut`, `_tidy`,
  `_apply_seams`, `OPEN_SEAM_CLEARANCE_M`; the report's `absorbed` is always empty now.
- Tests: `tests/harness/test_csg_bake.gd` (new, 3 tests, builds on `sphere_pod` AND `box_hull`);
  five `test_shape_mesh` tests re-scoped to what the pure path promises. Suite **278/278**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **Flat and native styles are one surface for now.** Every walled seam takes the native socket.
   The plane cut (a box beyond the plane) and the footprint prism (the flange builds it already)
   are straightforward CSG operands; the plan needs to name them as cutters. Next piece of work.
2. **The engine bake is asynchronous** and needs a scene tree. Headless tools that want the exact
   meshes must run as a SceneTree script and await frames; `tools/ship_selfcheck.gd` and the data
   validator do not need it. The pure `ShipMeshBake.bake()` is the tree-less fallback and is
   approximate on curved seams (open edges on every seam-cut sphere piece).
3. **Merging the engine's triangles into n-gons can tear an edge**; such a piece is drawn as its
   triangles (its wireframe shows them). Cosmetic; the solid is closed.
4. **Argon-sized ships bake in about 4 s** on spheres; the walk over 24 parts is per-part combiners
   with no sharing. Fine for EXPLODE; not for anything per frame.
5. **`MeshClip.seam_split`** does not yet make the two sides agree either (sockets 0 of 4 on the
   pure path with it on); kept off the path, kept in the file for the record.


## F33 — Additive contract extensions of 2026-09-05c: rooms built whole — OPEN, DELIBERATE

ADR 0021.

- **`ShipMeshBake.plan()`** gains `rooms: Array[PackedStringArray]` (every part in exactly one,
  members sorted) and `open_cuts` (the per-part reading of open seams, for the pure executor);
  `cuts` is now the WALLED seams only. `_join_rooms`, `_room_root` (private) return.
- **`ShipCsgBake.bake()`** is two engine passes: room shells, then pieces; `_less_cuts`,
  `_engine_mesh`, `_add_engine_mesh`, `_until_ready`, `_read_combiner` (private).
- Tests: `test_no_room_piece_keeps_hull_inside_another_member` (engine-measured, both families).
  Suite **279/279**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits.** F32's stand: flat and native styles are still one surface; the pure executor
still reads open seams per part and is approximate on curves. Bake time for a sphere nucleus made
one room is about 4.7 s (two passes); fine for EXPLODE.


## F34 — Additive contract extensions of 2026-09-05d: halves, rooms whole, the interior view — OPEN, DELIBERATE

ADR 0022.

- **`ShipMeshBake.plan()`** gains `split: {id: {"origin", "normal"}}`.
- **`PolyMesh.to_array_mesh_grouped(group_of, names)`** (new, public): named surfaces.
- **`ShipCsgBake`**: a third pass; the report gains `halves`, `half_meshes`, `split`, `rooms`,
  `room_shells`, `room_meshes`, `room_half_meshes`, and `meshes` now carries three named surfaces
  (`SURFACE_EXTERIOR`, `SURFACE_INTERIOR`, `SURFACE_CUT`). `ON_SURFACE_M`, `CALIBRATION_SAMPLES`.
- **`ShipSceneBuilder.DisplayMode.INSIDE`** and **`inside_materials(selected)`** (new, public).
- **`ShipExplodeView`**: `Module` holds `solids`/`wires`/`bodies` (halves) with `solid`/`wire`/
  `body` as the first of each; `set_rooms_whole(on)`; `show_modules` accepts the whole report;
  `module_nodes()` returns every half. `HALF_GAP_FRACTION`.
- **`ShipView3D.set_rooms_whole(on)`** (new, public). **`ShipBuilder`**: `ROOMS: PIECES/WHOLE`
  button, `INTERIOR` in the mode dropdown (private handlers; the public count stays at the cap).
- Tests: `test_every_piece_is_sliced_into_two_closed_halves`,
  `test_every_drawn_mesh_names_its_exterior_and_interior`. Suite **281/281**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **The box tessellation sits inside its own distance field by the fillet**: `ShapeMesh` builds
   the box at `size - round_r`, the field is the rounded envelope, and every point of the mesh
   reads a constant `-round_r * scale` (-0.200 m on a carbon box). The classifier calibrates to it;
   nothing else has noticed yet because nothing else compared a box mesh to its field at a
   millimetre. Building the fillet, or building the sharp box at `size`, is the honest fix.
2. **The third pass roughly doubles a bake** (carbon: 9 s / 12 s on spheres). Fine for EXPLODE.
3. **The assembled preview cannot separate interior from exterior** - its parts are one surface -
   so INTERIOR there is the exterior's two passes only. Use it exploded.
4. **A room shown WHOLE keeps only its first member's pick body**; clicking it selects that part.
5. F32/F33 stand: flat and native styles are one surface; the pure executor is approximate.


## F35 — Additive contract extensions of 2026-09-06: the baked view, its update, the ghost — OPEN, DELIBERATE

ADR 0023.

- **`ShipTemplates.build`** now emits an open joint per meeting pair of nucleus bodies
  (`_open_nucleus`). A template's `joints` are no longer empty on a multi-body nucleus.
- **`ShipCsgBake.bake(host, doc, data, cfg, progress: Callable = Callable())`** — a trailing
  optional; `progress.call(fraction, label)` at each pass. `_tick`.
- **`ShipExplodeView.show_modules(..., assembled: bool = false)`**, `is_assembled()`.
- **`ShipView3D.set_baked(on, sdf, selected, report)`**, `is_baked()`, `set_meshes_stale(on)`,
  `get_ghost_view()` (public count 24 of 30).
- **`ShipGhostView`** (new, `harness/builder/ship_ghost_view.gd`) and
  **`shaders/ship_ghost.gdshader`** (new): `show_doc`, `set_ghosting`, `set_color`, `part_count`,
  `fade`; `MAX_PARTS = 32`.
- **`ShipBuilder`**: `UPDATE MESHES` button, `AUTO` toggle, `BakeProgress` bar in the status row;
  private `_update_meshes` (coroutine), `_show_bake`, `_set_baked`, `_mark_meshes_stale`,
  `_drop_bake`, `_schedule_update`, `_on_update_pressed`, `_on_auto_toggled`,
  `_on_bake_progress`, `_refresh_update_button`, `_show_progress`, `_hide_progress`;
  `_set_exploded(false)` lands in the baked view. Read-backs: `_baked`, `_meshes_stale`,
  `_auto_update`, `_last_bake`. The file is at 1923 of 2000 lines.
- **`ShipCheckViews.failures()`, `module_count(doc)`, `check_update_finish(...)`,
  `check_ghost_up(vp, path)`**; the visual check gains an UPDATE MESHES stage and turns AUTO off
  at setup (the mode captures assert about the primitives).
- Tests: `test_the_nucleus_is_one_open_room_by_default`,
  `test_the_bake_reports_progress_in_order`. Suite **281/281**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **The ghost knows no walls, no hatches, no seam styles** — it is the union shell. Where a
   wall stands, the ghost shows an opening until the update lands. By design; the update is the
   truth.
2. **The ghost carries a ship's first 32 parts** (a uniform array is fixed-length). A bigger
   ship ghosts partially. Raising `MAX_PARTS` is a two-line change (shader + node) at a per-pixel
   cost proportional to it.
3. **The ghost's inset is `d + thickness` in the scaled metric** — for a non-uniformly scaled
   part the wall reads slightly thinner along the stretched axis than the bake's. Invisible at
   the ghost's alpha.
4. **AUTO re-bakes on EVERY commit**, including a parameter nudge: a carbon of spheres costs
   9–12 s per edit while it is on. The bar says so; the toggle is there for the heavy sessions.
5. **A placement leaves the baked view** (the handles live on the primitives) and the commit
   after it re-bakes. The preview flashes between. Handles on the baked pieces would remove it.
6. **A packed array handed to a function is shared, one read out of a container is a copy** —
   see ADR 0023 and the memory note; `ShipCheckViews.failures()` exists for reading only.


## F36 — Additive contract extensions of 2026-09-06b: components are rooms, the nucleus is the root component — OPEN, DELIBERATE

ADR 0024.

- **Attach model (SPEC §3)**: a part's `parent` may be an inner part of a component instance,
  `"<instance>/<inner>"` (nested: `"<instance>/<inner>/<deeper>"`). `ShipAttach` expands an
  instance the moment it is placed; `_can_place` waits for an expanded parent.
- **`ShipDoc`**: `part_at(id)`, `store_inner(id)`, `drop_inner_cache()`; `_children_index`,
  `children_of`, `ancestors_of` and the dead-joint sweep see a child of `"<instance>/<inner>"`
  as the instance's.
- **`ShipComponents`**: `inner_part`, `store_inner_part`, `inner_exists`, `inner_host_key`,
  `import_from(doc, other, ship_label)`, `dissolve(doc, instance_id)`.
- **`ShipValidate`**: an inner part is a legal parent and joint end. **`ShipSeams`**: inner
  seams of every instance, OPEN; `_joint_for` collapses stored ends too.
- **`ShipMeshBake.plan`**: members of one instance join one room by membership.
- **`ShipTemplates.build`**: the nucleus lifted into the root instance (`_lift_nucleus`,
  `_symbol_of`); `_open_nucleus` of ADR 0023 removed; `_hatch` may name an inner host.
- **`ShipSceneBuilder`**: `set_isolated(instance_id, washed)`; `inside_materials` = interior
  fronts + exterior backs + cuts, no wire. `_resolve_pick` inside isolation returns the inner id.
- **`ShipExplodeView`**: every exactly baked piece is its own module (inner pieces included);
  `set_isolated(instance_id, washed)`; `_is_selected` lights a piece of a selected instance.
- **`ShipView3D`**: `part_double_clicked(part_id)` signal, `set_isolated(instance_id)`,
  `_pid_under`, `WASHED_ALPHA`; the ghost is gone.
- **`ShipBuilder`**: `_isolate`, `_leave_isolation`, `_on_part_double_clicked`,
  `_on_import_pressed`, `_import_named`; `cancel_placement` (ESC) closes an isolation; AUTO,
  `_schedule_update`, `_on_auto_toggled` removed; `commit_edit` stores inner edits.
- **`PartPalettePanel`**: `IMPORT COMPONENTS` button (calls the builder's private handler by
  name — the facade is at its public cap).
- **Removed**: `harness/builder/ship_ghost_view.gd`, `shaders/ship_ghost.gdshader`.
- Visual check: an isolation stage (a shallow subtree lifted, opened, picked inside, closed).
  Tests: nucleus root component and one room; `import_from`; `dissolve`; `part_at`; the
  component's inner seam is open; a component's inner parts pair and read open. Suite
  **287/287**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **A drag-placement onto a component attaches to the instance**, not to the inner part under
   the cursor (`ShipPlacement` checks `doc.parts.has(parent)` throughout). The model allows it
   (a template does it); the interaction does not yet.
2. **A component shown WHOLE with rooms whole** draws under its instance's proxy id; the other
   pieces wait unseen, as any room's do.
3. **Inner parts are edited through a cache** (`ShipDoc.part_at`) written back at
   `commit_edit`; an edit that never commits is dropped at the next document swap.
4. **A dissolved component keeps its definition** in the palette; nothing removes an unused
   definition yet.
5. **Imported joints are dropped**: a ship brought in as a component is one open room, walls and
   hatches included. By the rule of this ADR; a walled import would need joints inside
   definitions, which the model does not hold.
6. **The INTERIOR mode has no wire**, by the ask; a wire toggle would be a mode of its own.
7. **The culled faceted variants are made by string edit of the authored shader**
   (`ShipSceneBuilder._faceted_shader`): a rename of `cull_disabled` in
   `shaders/part_faceted.gdshader` silently returns the mode to both-sided. The visual check
   saves `reports/visual_interior.png` from the baked view to catch exactly that.
8. **`ShipSeams.pairs_within` now pairs inner parts** (`inner_host_key`), and `mode_for` reads
   OPEN within one instance without a joint (`within_one_instance`). Callers that stored a
   joint between two inner parts of one instance would find it ignored - by design.


## F37 — Additive contract extensions of 2026-09-06d: a component's links live in its definition — OPEN, DELIBERATE

ADR 0025 (withdraws ADR 0024's membership rule).

- **Definition record**: `doc.components[id].joints` (optional) - joint records keyed by id,
  ends as inner ids.
- **`ShipComponents`**: `inner_pair`, `definition_of`, `inner_joint_for`, `set_inner_joint`;
  `make_component` moves inside joints into the definition (`_move_inside_joints`,
  `_inner_id_map`); `dissolve` brings them back; `import_from` carries the ship's joints
  (`_imported_end`).
- **`ShipSeams`**: `within_one_instance(doc, a, b)` (now takes the doc); `_joint_for` reads the
  definition for an inner pair; the inner seams take their mode/hole/style from it.
- **`ShipMeshBake.plan`**: the membership join is gone; rooms are OPEN seams, as before 0024.
- **`ShipTemplates._lift_nucleus`**: OPEN joints into the nucleus definition.
- **`ShipBuilder`**: `_set_link` / `_apply_seam_style` write inner joints; `_is_part_alive`;
  the LINK refusal removed; import through **`ShipComponentImport`** (new: `sources`,
  `source_doc`, `label_of`, `template_options`, `CLASS_PREFIX`); the button/bar through
  **`ShipBakeHud`** (new: `style_bar`, `refresh_button`, `show_progress`, `hide_progress`).
- **`PartTreePanel`**: the LINK refusal removed; `_meet_for_hatch` names inner parts; the
  instance row reads `(N PARTS)`.
- Tests: the nucleus definition's open joints; inner pairs read/erase/set their definition's
  joint; the lift moves the inside joint in; dissolve returns the open links; the imported ship
  keeps its joints. Suite **287/287**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **A dissolved nucleus with its open links back baked 8 open pieces** in the walled fixture
   (`test_every_piece_is_sliced_into_two_closed_halves`, before the fixture stripped them). The
   same links bake closed through the component. Not on the player's path - `dissolve` has no
   verb - and not understood; measure before giving it one.
2. **A part placed inside an open component still goes into the document**, attached to the
   instance; SketchUp would put it into the definition. F36 item 1 stands.
3. **A definition's joints are shared by every instance** (as its parts are); MAKE UNIQUE
   copies them with the definition.
4. **Nested pairs across a definition boundary** (a nested instance's inner part against its
   host's part) are the nested instance's seam on its host, not a link of their own.
5. **The bake HUD is constructed twice** because the status row is built before the toolbar; a
   layout change that reorders them must keep the second construction after both exist.


## F38 — Additive contract extensions of 2026-09-06e: a definition's root is a primitive; imports at the host's size — OPEN, DELIBERATE

ADR 0026.

- **`ShipComponents.make_component`** refuses a head that is an instance ("" with a warning).
- **`ShipComponents.import_from`** flattens a source whose root is an instance (dissolved on a
  copy), lifts every ARM off the root (`_subtree_signature` dedupes; `_definition_from` builds a
  definition with its joints; `_imported_end`), then the ship. A carbon yields three: nucleus,
  `<SHIP> ARM 1`, `<SHIP>`.
- **`ShipComponentImport.template_options(doc, data)`** derives room family/manufacturer/span
  and hall family/manufacturer/bore/length from the host's resolved shapes (`_widest`).
- Tests: the import's three definitions, primitive root and full expansion; the refused
  instance head; the host-derived options (`test_an_imported_class_is_built_at_the_host_ships_
  dimensions`, in the CSG suite because the helper is harness). Suite **289/289**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **A placed instance mirrors part by part** across the symmetry plane (a nucleus placed
   off-centre grows twins of its off-plane protons). The rule predates components; a
   component-as-a-unit twin needs `_add_symmetry_twins` to treat an instance's expansion as
   one body when the instance itself is off-plane.
2. **Arms are deduplicated by structure**, so a class's four identical arms are one entry; two
   arms that differ only in a pod's name are still one. Names are not structure, by choice.
3. **The freeze was not reproduced in core** (every step under 0.5 s headlessly); it followed
   the shapeless whole-ship instance into the builder. If placement of a large component still
   stalls, `ShipPlacement`'s per-frame trial documents are the next suspect (F36 item 1).
4. **The import reads the host's first tunnel** for bore and length; a ship with tunnels of
   several sizes lends its first in tree order.


## F39 — Additive contract extensions of 2026-09-06f: default hatches, inner-safe LINK — OPEN, DELIBERATE

ADR 0027.

- **`ShipSeams.default_link_for(doc, a, b)`** and **`role_of(doc, id)`** (new, public).
- **`ShipBuilder._default_link_for_placed`**, called from `_on_placement_committed`; the seam
  menu's `_seam_pairs` come from `ShipSeams.pairs_within`.
- **`PartTreePanel._on_link`** reads its pair through `part_at`.
- Tests: `test_a_tunnel_meeting_a_module_is_hatched_by_default` and the inner-pairs test now
  live in `tests/core/test_components.gd` (the seams suite is at the 30-method cap). Suite
  **290/290**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **"Electron clusters" do not exist in the templates** - every electron is one tunnel and
   one pod. When a class places pods together, write open joints into their definition as the
   nucleus does (`_lift_nucleus`).
2. **The default hatch is applied at placement commit as its own undo step**; UNDO takes the
   hatch first, the part second. A single step would need the placement to hand the builder its
   commit before it happens.
3. **A hatch by default does not check that the interiors meet** (`_meet_for_hatch` is the
   tree's, for a hand-made link). A flush-placed tunnel's hatch is declared and reported pending
   by the bake, as any hatch is until openings are built.
4. **Every harness lookup fed by a selection must go through `ShipDoc.part_at`**; the
   remaining `doc.parts[...]` in `ShipPlacement` and `ShipReseat` are guarded by
   `parts.has` and simply skip inner parts, which is why a drag inside an open component does
   nothing (F36 item 1).
5. The Phase One Hull Review artifact (2026-09-06) ranks the next work: bake by room with a
   cache, one interaction contract rendered as tooltips/hints/help, twin the instance not its
   parts, a checked-in baseline ship for the budgets, reserved identities for later phases.


## F40 — Additive contract extensions of 2026-09-06g: a ship arrives resolved; the interior is its own mesh — OPEN, DELIBERATE

ADR 0028.

- **`ShipBuilder._resolve_on_load`**, `_resolve_on_load_enabled` (the visual check sets it
  false); `_update_meshes` queues one more request during a bake and discards a bake of a
  replaced document; the placement starts no longer leave the baked view.
- **`ShipSceneBuilder.set_exploded(on, covered)`**, `_is_covered`, `_covered`;
  `set_depth_range(near, far, cut_plane)`, `NO_CUT`, `_cut_plane`; `INTERIOR_AMBIENT`,
  `INTERIOR_CAVITY_AMBIENT`, `INTERIOR_DEPTH_STRENGTH`; `inside_materials` = exterior
  `cull_back`, interior `cull_front`, cut both - Godot's front face is clockwise.
- **`ShipExplodeView._split_interior`**: every placed piece is two nodes (exterior+cut,
  interior); `module_nodes()` returns both.
- **`shaders/part_faceted.gdshader`**: `uniform vec4 cut_plane` (default: no cut).
- **`tools/ship_resolve_check.gd`** (new, windowed): the user's scenario, three frames.
- No test count change. Suite **290/290**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **The load costs a whole bake** (9-12 s on a carbon of spheres). The phase-one review's
   room-keyed bake cache is the fix; until then the bar is the answer.
2. **A part moved after the bake keeps showing its stale piece** (its id is still covered);
   a part ADDED shows as a primitive beside the pieces. Deliberate: the button lights either
   way, and UPDATE MESHES is the only thing that moves a baked piece.
3. **The cut plane is plumbed and unused** (`NO_CUT`); a SECTION mode would push a plane
   through the orbit focus - built, measured, and withdrawn because it hid half the ship.
4. **Godot's clockwise front face** means every baked mesh presents back faces from the side
   its normal points to; any future material that culls must be written against that, not
   against the normals. The faceted shader's `cull_disabled` + `FRONT_FACING` hides it
   everywhere else.
5. **`tools/ship_resolve_check.gd` dismisses the start chooser and the tutorial through their
   private handlers**, as the main check does; a rename there breaks both.


## F41 — Additive contract extensions of 2026-09-06h: openings capped, collared and doored — OPEN, DELIBERATE

ADR 0029.

- **`core/bake/ship_doors.gd`** (new, `ShipDoors`): `plan(entries, thickness, min_clear_m,
  segments)` -> `{doors, misfits}`; `limits(doc, data, cfg, child, host)` for a panel;
  `leaves(door, side, open)` -> the leaves as closed solids; `prism`, `field_of`,
  `mesh_crossing`, `indenter_for`; the `Field` class (a cutter calibrated to its own mesh,
  F34); the DOOR_* / MISFIT_* / ENTRY_* record keys.
- **`ShipSeams`**: `KIND_SQUARE`, `KIND_TRIANGLE`, `KIND_POLYGON`, `VALID_HOLE_KINDS`,
  `HOLE_SIDES`, `HOLE_STYLE`, `HOLE_BLADES`, `DOOR_NONE/SINGLE/DOUBLE/IRIS`, `VALID_DOORS`, the
  `PARAM_*` override keys, `HOLE_SEGMENTS`, `CORNER_SEGMENTS`; `hole_profile(hole, segments)`,
  `hole_scaled(hole, scale)`, `polygon_distance(outline, uv)`; `_hatch_hole` resolves shape,
  style, size and sides from the joint over the family; `_doorway_hole` takes a shape and size.
- **`ShipMeshBake.plan`**: `"doors"`, `"door_misfits"`; `"pending_seams"` now means bounded
  seams nothing could be bored for. `report`: `"doors"`, `"door_misfits"`, `"bored"`.
- **`ShipConfig.hatch_min_m`** (0.5), in `data/tuning.json` and its schema.
- **`data/shapes/hatches.json`**: every family names `shape` and `style`; `pressure_hex` gains
  `sides`; the `_note` and `hatches.schema.json` say what a family is now.
- **`ShipCsgBake`**: the DOORS pass (`_door_work`, `_with_doors`); `report["bored"]`,
  `report["door_failed"]`; `_read` keeps a merge only when its volume matches the triangles
  (`READ_VOLUME_REL`).
- **`harness/builder/ship_hatch_edit.gd`** (new, `ShipHatchEdit`): `pair_for`, `state`,
  `write`, `joint_for`, `families`, `door_key`, `is_bounded`.
- **`ShipExplodeView`**: `set_door_open(key, side, amount, animate)`, `set_doors_open(states)`,
  `door_amount`, `door_nodes`; `Module.doors` / `door_wires`; `DOOR_TWEEN_S`, `DOOR_SHADE`.
- **`ShipView3D`**: `set_door_open(key, side, amount)`, `door_open(key, side)`; the amounts
  survive a rebake.
- **`InspectorPanel`**: the HATCH section (`_build_hatch_section`, `_refresh_hatch`,
  `_write_hatch`, `_on_door_toggled`); `HATCH_SHAPES`, `HATCH_STYLES`.
- **`tools/ship_resolve_check.gd`**: a doors stage and `reports/visual_resolved_doors.png`.
- Tests: `tests/core/test_doors.gd` (9), one in `test_csg_bake.gd`; the pending test in
  `test_shape_mesh.gd` says what pending means now. Suite **300/300**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **The pure executor (`ShipMeshBake.bake`) does not bore.** It carries the door records and
   reports `bored` empty; the engine is what the player sees. Boring on the BSP path is a
   separate piece of work if anything headless ever needs it.
2. **A door on a curved wall is a flat gasket, always.** The author allowed "steady topologies"
   to shape the door to the surface; every door here takes the collar. A conformal leaf on a
   uniform curve is a follow-up.
3. **The iris is a shutter of straight-cut wedges**, withdrawn radially as the aperture grows.
   Real iris blades pivot; a pivoting blade needs a housing wider than the frame, which the
   hull's wall does not give it.
4. **"Double hung" is read as two leaves meeting at the centre**, hinged on opposite edges -
   the ship's double door - not the vertical sash the term means in a window catalogue.
5. **Door leaves are not pickable and carry no collider**; the HATCH section reaches them
   through the seam's parts.
6. **The door material is a copy** of the module's with its ramp darkened and no depth cue; the
   cue's camera range does not follow into a copy, so it is switched off there.
7. **`MeshMerge` mis-bridges annular faces** (three of twelve bored pieces on a box carbon);
   those pieces fall back to the engine's triangles and show them in WIRE. The merge itself is
   the follow-up.
8. **The fit is measured on twelve rim samples** and marched at half a wall; a cavity thinner
   than that, or a rim feature between samples, is missed. The bore margin (`BORE_MARGIN_M`)
   covers the ordinary case.


## F42 — Additive extensions of 2026-09-21: the bake makes what is on screen — OPEN, DELIBERATE

ADR 0030. Harness only; nothing in `core/` changed.

- **`ShipCsgBake.bake()`** no longer returns `halves`, `half_meshes`, `room_shells`,
  `room_meshes` or `room_half_meshes`. It returns `EXTRAS_READY: false` and `EXTRAS_INPUT`
  (`{"plan", "engine": {id: Mesh}, "room_engine": {keeper: Mesh}}`). Its progress ticks are
  PLANNING, ROOM SHELLS, PIECES, DOORS, READING, SURFACES.
- **`ShipCsgBake.bake_extras(host, bake, progress)`** (new, async): a copy of the report with those
  five keys in, plus **`room_shell_halves`**, which the view already read and no bake had ever
  written.
- **`ShipCsgBake.EXTRAS_INPUT`, `EXTRAS_READY`** (new constants); `_door_work`'s second argument
  is any id-keyed map now.
- **`harness/builder/ship_bake_session.gd` — `class_name ShipBakeSession`** (new): `last`,
  `stale`, `busy`, `request_update()`, `request_extras()`, `has_extras()`, `drop()`. `--import`
  was run.
- **`ShipBuilder`**: `_explode_baking`, `_last_bake`, `_meshes_stale` and `_bake_pending` are gone,
  replaced by `_bake_session`; `_current_doc()` is new (private). `_show_bake` asks for the extras
  when exploded or rooms-whole; `_on_rooms_pressed` does too over the baked view.
- **Tools**: `ship_visual_check.gd` and `ship_resolve_check.gd` read `_bake_session.busy` and
  `.last`.
- Tests: `test_the_assembled_bake_leaves_the_extras_for_the_first_ask`; the halving and
  named-surface tests call `bake_extras`. Suite **301/301**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **The first EXPLODE after an update costs the extras**: 9.7 s on a carbon of spheres, 4.0 s on
   boxes, with the bar up. Accepted by the author in exchange for the assembled bake's 19.3 -> 6.0 s.
2. **A report now keeps its plan and the engine's meshes alive** under `EXTRAS_INPUT` for as long
   as the builder holds the bake. That is one ship's worth of operands, released with the bake.
3. **An extras pass cannot be cancelled.** An edit during one queues an update behind it, and the
   extras of the replaced bake are thrown away when they land.
4. **The n-gon merge is still the largest single cost** of the read-back. The step-2 cache makes it
   rarer; making the merge itself cheaper is separate work.


## F43 — Additive extensions of 2026-09-21b: explode options and the slicer — OPEN, DELIBERATE

ADR 0031.

- **`ShipMeshBake.plan`** gains **`frames`** (`{id: Transform3D}`, orthonormal, right-handed,
  Y the placement normal). Core, additive; `split` stays in the plan and is no longer read by the
  harness.
- **`ShipCsgBake.bake_extras(host, bake, slicing = DEFAULT_SLICING, progress)`**: returns
  `chunks`, `chunk_cells`, `chunk_counts`, `chunk_meshes`, `frames`, `room_shells`, `room_meshes`,
  `room_chunks`, `room_chunk_cells`, `room_chunk_counts`, `room_chunk_meshes`, and
  `EXTRAS_SLICING`. **Gone**: `halves`, `half_meshes`, `room_shell_halves`, `room_half_meshes`
  (a bisection across Z is the same result under the new keys). New: `slicing_key()`,
  `DEFAULT_SLICING`, `MAX_CUTS`, `ROOM_PREFIX`, `EXTRAS_SLICING`, and the private `_counts`,
  `_slice_job`, `_slice`, `_slab`; `_halve` and `_basis_facing` removed.
- **`ShipBakeSession.has_extras(slicing)` / `request_extras(slicing)`** take the slicing.
- **New classes** (`--import` run): `ShipExplodeSettings` (harness/builder), `ShipExplodePanel`
  (harness/panels), `ShipExplodeControl` (harness/builder).
- **`ShipExplodeView`**: `set_settings()`, `relayout()`, `SEP_*`, `META_*`; `_add_visual` removed
  and `_add_visual_at` takes a unit direction and a separation kind; `_placed_at`, `_separation`,
  `_offsets_for`, `_hang`, `_shift_unit`, `_in_cluster`.
- **`ShipBuilder`**: `_explode_opts`; the panel shows while exploded; `_show_bake` asks for extras
  with the player's slicing. 1997 of 2000 lines.
- **Tools**: `tools/ship_explode_check.gd` (new, windowed; `reports/visual_explode_*.png`).
- Tests: `tests/harness/test_explode_slicing.gd` (six); the CSG suite reads `chunks`. Suite
  **307/307**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **Cost grows with the grid**: a combiner and a read-back per cell. Three axes trisected is 27
   cells a piece, minutes on a carbon. The room cache is the answer.
   RETIRED(ADR 0032): per-setting grids -> one fixed 64-cell cut per piece, 9.6 s on a carbon,
   and every setting a move (F44).
2. **A cell wholly inside a cavity is dropped**, so a piece can show fewer slices than its grid.
   The cell index still says where each one sits.
3. **The slices of a piece are placed by its frame, not by its seam**: a cluster chunk's slices pull
   along its own axes, which for a proton of a nucleus is its placement normal, not the direction it
   leaves the nucleus in.
4. **Settings changed by code, not the panel,** show in the panel only on the next `refresh()`;
   the checks refresh where they read it.
5. **The door leaves ride their module's offset, not a slice's**: a sliced piece's door stays where
   the whole piece would have carried it.


## F44 — Additive extensions of 2026-09-21c: the fundamental cells and the animated explode — OPEN, DELIBERATE

ADR 0032.

- **`ShipSeams.explode_offsets(seams, cfg, boxes, still = {})`**: `still` modules ride their host
  and sit out the relaxation pass. Core, additive; `_relaxed` gains the same optional argument.
- **`ShipCsgBake.bake_extras(host, bake, progress)`**: no slicing argument. Returns `cells` and
  `room_cells` (id -> `[{"cell", "solid", "mesh", "wire"}]`), `frames`, `room_shells`,
  `room_meshes`. New: `FINE_CUTS`, `WIRE_FEATURE_DEG`, `_read_cell`, `_feature_wire`; `_slice` and
  `_slab` cut every job on every axis. **Retired**: `DEFAULT_SLICING`, `EXTRAS_SLICING`,
  `MAX_CUTS`, `slicing_key`, `_counts`, the `chunk*` keys.
- **`ShipBakeSession.has_extras()` / `request_extras()`**: no slicing argument again.
- **`ShipExplodeSettings`**: `speed`, `SPEED_MIN/MAX`, `mode_for()`; `slicing()` retired.
- **`ShipExplodePanel`**: SPEED and POSITION; `speed_changed`, `position_changed`,
  `show_amount()`; APPLY SLICES, `slicing_changed`, `apply_pressed`, `set_stale()` retired.
- **`ShipExplodeControl`**: `_init(frame, view, cfg, theme)` (no session, no reslice).
- **`ShipExplodeView`**: `collapse()`, `has_cells_showing()`, `set_amount()`, `amount()`,
  `amount_changed`; `EXPLODE_S`, `GROUP_SIGN`, `NO_CELL`, `META_CELL`, `META_FRAME` (`META_SHIFT`
  retired); `_build`, `_place_all`, `_measure_target`, `_placed_meta`, `_stages`, `_modes`,
  `_compute_offsets`, `_riders`, `_cell_shift` (`_shift_unit` retired); an exact bake builds at
  once, not a module a frame.
- **`ShipView3D.set_exploded(false)`** calls `collapse()` rather than `clear()`.
- **Tools**: `tools/ship_explode_check.gd` rewritten (`reports/visual_explode_{default,sliced,half,
  spread}.png`).
- Tests: `test_explode_slicing.gd` rewritten (eight); the CSG halving test groups cells. Suite
  **309/309**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits, recorded rather than hidden.**

1. **About 1,100 mesh nodes a carbon**, plus a wire node and a pick box per cell. A ship several
   times a carbon will want the cells batched per piece (a MultiMesh or one mesh per group).
2. **The internal cut faces show in the translucent modes** (X-RAY, FRESNEL, the INTERIOR ghost),
   and every seam shows in the wireframe. The author wanted the seams; the translucent faces are the
   price of drawing every cell.
3. **A cell picks by its box.**
4. **The first EXPLODE after an update pays the cut** (9.6 s on a carbon of spheres); the room cache
   and its disk copy are the next piece of work.
5. **A module that is not a cluster chunk can move a little in the second stage**: the relaxation
   pass settles modules differently with and without the chunks riding.


## F45 — Additive extensions of 2026-09-22: the beacon — OPEN, DELIBERATE

ADR 0033. The public surfaces `docs/API_CONTRACT.md` pins are unchanged in name and signature; what
changed is what `_place_part` (private) returns for a part that stands on nothing, and what the
templates build.

- **`ShipAttach`**: the root and any parentless part are placed by `ShipPart.absolute`. RETIRED: the
  root pinned to `Transform3D.IDENTITY`. Section 12's pinned functions are untouched.
- **`ShipTemplates._centre_on_the_beacon`** (new, private): every class is shifted so its core rings
  the beacon. The root module is now `asymmetric`, like every other part a template makes.
- **`ShipComponents`**: `make_component` carries the head's `absolute` onto the instance;
  `dissolve` carries the instance's `absolute` and `asymmetric` back onto the new root.
- **`ShipCsgBake.bake_extras`**: a room's cells are cut in the keeper's frame across the room's
  extent, and the report gains **`cell_frames`** (the frame each piece's cells were cut in).
- **`ShipExplodeView`** reads `cell_frames`; **`ShipView3D`** draws the beacon dot
  (`BEACON_ARM_M`), no depth test.
- **`MeshFlange`**: `PLANE_D_REL` and `_plane_match_tolerance` — the cap-face plane match is
  relative to the distance from the origin.
- Tests: `tests/core/test_beacon.gd` (five). Suite **314/314**.

**No hash moves.** Measured: `5536787c6c35d236` either side. A document written before this carries
`absolute` as identity on every part, so it resolves exactly as it did.

**Known limits, recorded rather than hidden.**

1. **Nothing in the harness places a part ON the beacon yet.** A central module means a part with no
   parent and an `absolute`, which only code can make today. The author asked for the beacon so
   things can grow away from it; the UI for growing FROM it is not built.
2. **The beacon does not move.** It is the origin, not a stored point: a ship cannot be re-centred
   on some other spot, and `_centre_on_the_beacon` runs at build time only. A ship edited afterwards
   drifts off centre exactly as far as the player takes it.
3. **The dot reads through everything** (no depth test), so it shows inside a hull it sits in. That
   is deliberate; it is also the only thing on screen that ignores depth besides the overlays.
4. **`MeshFlange`'s relative tolerance changed no measured number** — it is a hardening, not a fix.


## F46 - Additive extensions of 2026-09-22: the nucleus rings the beacon - OPEN, DELIBERATE

ADR 0034. The public surfaces `docs/API_CONTRACT.md` pins are unchanged in name and signature.

- **`ShipSeams.seams()`** also returns SIBLING seams: one per joined pair that meets without one
  standing on the other. New private `_sibling_seams`, `_joined_pairs`, `_expanded_key`,
  `_add_pair`, `_placement_rank`, `_sibling_frame`, `_crossing`, `_stand_apart`; new consts
  `SIBLING_WALK_STEPS`, `SIBLING_REFINE_STEPS`.
- **`ShipSeams.pairs_within()`** returns pairs of parts that stand side by side - two parts of one
  definition, or two anchored to the beacon - as well as the tree pairs it always did.
- **`ShipComponents.make_component()`** accepts anchored RIDERS beside the head (new private
  `_anchored_tops`; `_selection_root` generalised; `_build_definition` stores a rider's anchor
  relative to the head; `_swap_in_instance` takes a trailing `riders`, defaulted).
  **`dissolve()`** returns a rider to the beacon.
- **`ShipAttach._expand_instance_transforms`** places a parentless inner part by its `absolute`.
- **`ShipTemplates`**: `_nucleus_radius`, `_reach_along`, `_anchored_at`, `_clump_pairs` (new,
  private), `_lift_nucleus` takes `data`/`cfg`, `_layout` returns `slots`, `_node` carries an
  `anchor`. `NUCLEUS_SOLVE_STEPS` is a new const. `nucleus_dirs()` is unchanged and still returns
  the hang directions, which the fallback layout still uses.
- **`ShipComponents.definition_order()`** walks each anchored member's own subtree instead of
  leaving it to the id sort, so a parent precedes its child in a definition whose ids were not
  handed out by `make_component`.
- **`ShipSeams._sibling_frame()`** returns `{SEAM_FRAME: Transform3D}` or `{}`, not a sentinel
  transform - the identity is a legal frame for a seam that lands on the origin.
- Tests: `tests/core/test_sibling_seams.gd` (new, three), two in `tests/core/test_beacon.gd`, one
  in `tests/core/test_components.gd`. Suite **320/320**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits** are ADR 0034's four: a sibling seam needs the pair to meet on the line between
their centres; `dissolve` resolves a rider against the instance's own anchor (exact for an anchored
instance, which is where nucleus components live); the radius is solved for the arrangement's
tightest pair; and nothing places a part on the beacon from the UI yet.


## F47 - Additive extensions of 2026-09-22: the pieces of a clump - OPEN, DELIBERATE

ADR 0035. The public surfaces `docs/API_CONTRACT.md` pins are unchanged in name and signature.

- **`ShipMeshBake.plan()`** gains **`room_splits`**: `{id: [{"other", "origin", "normal"}]}`, where
  two equal members of one room divide. New private `_equidistant`, `_add_split`; new const
  `SPLIT_SOLVE_STEPS`. The pure executor ignores it.
- **`ShipSeams`**: seam records carry **`SEAM_SIBLING`** (bool). `explode_offsets()` gives a module
  that stands on nothing a radial travel from the beacon and leaves sibling seams out of the host
  chains. `_record()` takes a trailing `sibling`, defaulted.
- **`ShipCsgBake`**: pass two cuts at the plan's planes (new private `_half_space`, `_room_reach`;
  new const `HALF_SPACE_REACH`).
- **`ShipExplodeView._riders()`**: every member of a room of several rides it but the one standing
  on something outside it.
- Tests: two new, one rewritten. Suite **322/322**.

**No hash moves.** Measured: `5536787c6c35d236` either side.

**Known limits** are ADR 0035's four: the pure executor does not cut on the planes; the plane is a
plane where the true equidistant surface curves; a clump mixing equal and unequal pairs could strand
a sliver in a triple overlap; and a module centred on the beacon has no radial direction to take.


## F48 - A room's pieces SPLIT AT THEIR SEAMS AND CAPPED - DONE

Raised by the author 2026-09-22, after ADR 0035 and its amendment; the author gave the go the same
day. `core/mesh/mesh_seam_split.gd` is the construction, and it WORKS - see "What it does, measured"
below. It is NOT wired into `ShipCsgBake`, because the pieces it makes cannot be carried through the
engine work that follows. What remains is written down here rather than guessed at again.

### What the author asked for

> "the proper way is to union all primitave shapes together, then cut them along the shape of
> interior seam to exterior seam."

> "the cut shapes inner seams all have vertexes, and the outter shell has vertexes, their end caps
> would be the capping of inner seam verticies to outter seam verticies, independantly for each
> piece right? think of a cuve in a cube, and think of the cubes edges as the "seams" of 2 joined
> shapes. the inner cube line between verticies i,j exist, and the outter cubes a,b exists, so a
> face between i,a,b,j would be the cap .. yeilding 4 thick square faces with champered edges"

And, ruling out what had been floated in reply: **"we will never marsh cubes or use surface nets.
weve already decided on excat mesh cfg stuff."** No marching, no field extraction, no dual
contouring. Exact mesh CSG and mesh surgery only.

### Why the present mechanism cannot give it

ADR 0021 cuts a room back into pieces with SOLID cutters, and ADR 0035 divides two equal members on
a PLANE. A plane is the right divider only where the two bodies are mirror images across it - two
axis-aligned cubes 90 degrees apart on an octahedron, which is why a carbon of cubes comes out
right. Where the seam curve is not planar (a boron class, whose equatorial bodies sit 120 degrees
apart) no plane contains it, so the cut crosses the seam instead of following it.

### What was measured, and it is the thing that makes this buildable

**The seam loops are already in the baked mesh.** Manifold puts vertices on the intersection curve
because that is what exact CSG does. Measured on a helium of `box_hull`: the room shell's keeper
piece has 21 vertices, of which **exactly 4 lie on BOTH bodies' outer surfaces** - the rectangle
where the two cubes cross. Nothing has to be found or approximated; the vertices are there.

**Every such test must be calibrated (F34).** A `box_hull` tessellation sits INSIDE its own field:
measured here, -0.159 m for both the body and its inset. `ShipCsgBake._offset_of(cutter, surface)`
gives the offset; a test against a raw `sdf() == 0` finds nothing at all, which is what the first
run of the probe did.

### The build, as proposed

1. Read the room shell back (already done) and classify every face by which member's surface it lies
   on, outer or inner, using the calibrated offsets.
2. The boundary between one member's faces and another's IS the seam loop - outer and inner, both
   already real edges of the mesh.
3. Cap each piece by joining its outer loop to its inner loop, the author's `(i, a, b, j)` quad per
   segment. Both pieces of a pair share those two loops, so their caps are the same surface and the
   pieces meet exactly: no overlap, no gap, no plane anywhere.
4. Drop `room_splits`, `_beyond` and the half-space cutter entirely (ADR 0035's machinery).

**The one wrinkle.** In the author's cube-in-cube the inner loop is a scaled copy of the outer, so
vertex `i` pairs with vertex `a` one for one. Where two DIFFERENT bodies cross, the outer loop
(where the two bodies meet) and the inner loop (where their two insets meet) are found independently
and have their own vertex counts, so the cap has to zip the two loops by arc-length rather than by
index. That is bookkeeping, and it is the only part of the author's construction that is not
literally as described.

### Two things this will NOT fix, recorded so they are not chased again

1. **A clump of CUBES on a THREE-fold arrangement cannot have identical pieces.** A cube has no
   three-fold symmetry about a face axis, so a boron class's three equatorial bodies meet its two
   axial ones differently whatever the cut does: measured, 34.29 against 34.85 m³. Carbon's
   octahedron lines up with the cube's own four-fold axes, which is why its six match. The lever for
   that is the arrangement or the body orientation, not the cut.
2. **Framing the bodies on the arrangement's pole does not help.** Tried 2026-09-22 so that a ring of
   bodies would be exact rotations of each other: it changed boron's numbers not at all and left a
   sphere carbon with cells that would not close. Reverted; `ShipAttach.mount_frame` stands.

### And one hazard the build must respect

**A cutter standing on the surface it cuts is a coincidence the engine will not resolve.** Clipping
a member's half-space to its neighbour's own SOLID is the exact answer and was measured to give a
sphere nucleus an open piece and cells that would not close - the neighbour's surface IS the room
shell's surface there. ADR 0035's amendment uses the pair's shared AABB for that reason. Mesh
surgery sidesteps it, but anything that goes back to solid cutters will meet it again.


### What it does, measured (2026-09-22)

`MeshSeamSplit.split(shell, members, bodies, rooms)` takes the room's shell as the engine's own
triangles and hands back one [PolyMesh] per member.

- **A cube carbon**: six pieces of **26.64 m3**, summing to **159.82** against a shell of **159.82**
  - an exact partition, no overlap and no gap, every piece closed. With the tunnel sockets in, the
  six read 26.64 / 26.72 - within 0.3%, and the difference is the sockets, which are real.
- **A sphere carbon**: six pieces, all closed, 20.66 to 21.19 m3 against a shell of 126.32.
- **Helium**, whose two bodies share their side planes: nothing unclaimed, 239.49 against 239.49.
- The split itself costs **4 ms** on a cube carbon and **127 ms** on a sphere one.

### The five things that had to be right, and are

1. **Read the shell BEFORE the n-gon merge.** A merged face spanning two bodies' coplanar surfaces
   lies wholly on neither: measured, a helium left 2188 m2 - most of its area - claimed by nobody.
   `ShipCsgBake._read_raw` exists for this; each piece is merged again afterwards.
2. **Classify by VERTICES, not centroids.** A face's centroid sits inside a curved surface by its
   own sagitta, centimetres on a 9 m sphere.
3. **Calibrate every field** (F34), or nothing is found on any surface at all.
4. **A member's surface includes the SOCKETS cut into it.** The face at the bottom of a socket lies
   on the tunnel's surface and belongs to the member; leaving those out is what made every room
   fall back.
5. **Walk the boundary, do not chain it.** Where three bodies meet, one vertex carries two seams'
   edges, and an edge-set walk hops between them: measured, a sphere carbon's four room seams came
   back as one loop of 149. The half-edge walk - turn about the far vertex through this patch until
   a boundary edge comes round - is the fix.

### THE ORDER IS WRONG, and the author named it (2026-09-22)

> "use standard 3d software pipelines, what would i do in blender, sketchup, autocad, etc.. the
> workflows are almost always a pattern we can repeat" / "dicing is a simple cut, no weird caps,
> simple slice all the way through so i dont see how it could be failing"

Every CAD workflow does the same five things in the same order: union the primitives, hollow the
result, **cut every opening while it is still one body**, then separate into parts (in Blender:
select the faces, `P` to separate, fill the boundary), then dice. This pipeline does the third step
LAST - it separates the nucleus into pieces and bores the hatches into the fragments - and that is
the step that fails. The author is also right that the dicing is innocent: a split piece with no
tunnel dices perfectly, and only a piece bored AFTER separation is refused.

**The reorder was tested** (`scratch`, 2026-09-22). Hatches bored into the whole room first, then
split: a cube carbon's six pieces come to **159.99 m3 against a room of 159.99** - still an exact
partition - and a sphere carbon's to 126.00 against 126.48. So the order is right and the split
survives it.

### What blocks the wiring

**A piece with a door bored through it will not slice into its cells.** Measured on a cube carbon:
the two protons with no tunnel slice correctly; the four that carry one bore a door and then their
64 cells come back summing to ZERO. The pieces themselves are sound by every test available here -
closed, every edge shared by exactly two faces (`MeshSeamSplit.is_sound`), the right volume - and
passing them through a CSG node before the door pass does not help.

Under the reorder the question sharpens to one thing: **the hatch hardware belongs to no member.**

A door is a collar unioned on, a clearance subtracted and a bore through both (`ShipDoors`
DOOR_COLLAR / DOOR_CLEAR / DOOR_BORE). Once those are in the room, the shell carries faces that lie
on none of the members' surfaces, and `MeshSeamSplit` hands each to whichever member is nearest.
That guess scatters single faces into the wrong patch, every one of them becomes an island with its
own boundary and its own cap, and the piece comes out NON-MANIFOLD - `is_sound` reports false for
every piece of a bored room, and three of six then refuse to dice.

**The fix is the one the sockets already got.** A socket's faces lie on the tunnel's surface and
belong to the member it was cut into; the split was taught that and every room stopped falling back.
A door's faces belong to the member its side names - `door[ShipDoors.SIDE_CHILD]` and
`door[ShipDoors.SIDE_HOST]` say which - and the split has to be told the same way.

One wrinkle to solve when doing it: a socket arrives as a `MeshClip.Cutter`, which carries a field,
so `ShipDoors.field_of` calibrates it directly. A door's collar and bore arrive as plain
[PolyMesh]es with no field at all, so either they need one (a cutter built from the door prism) or
the faces have to be claimed another way - their own bounds are small and belong to exactly one
member per side, which is probably enough.

### The order to build it in, once the above is solved

1. Union the members' bodies (with their sockets) and subtract the union of their interiors - the
   room's shell, as `ShipCsgBake` pass one already makes it.
2. Bore EVERY hatch of that room into the shell, while it is one body (`_with_doors` takes the
   whole room's door work just as it takes a piece's).
3. Read it with the raw reader, split it, cap it.
4. Merge each piece back into n-gons.
5. Dice - and nothing that was bored is ever handed back to the engine, which is the whole point.

### How to see it for yourself

Build a room's shell as `ShipCsgBake.bake` does (bodies and interiors with their cuts, via
`_less_cuts`), read it with `_read_raw(_engine_mesh(shell))`, build a body and a room field per
member with `ShipDoors.field_of` plus one per socket from `plan["cuts"]`, and call `split`. Print
each piece's volume, `open_edges()` and whether `is_sound` holds. The wiring that was removed -
pass two rebuilt around the split, with a fallback to the old cut-back for any room the split could
not divide soundly - is in this session's history if it is wanted back.


### DONE 2026-09-22, as ADR 0036 - and what is left

Wired, in the CAD order the author named: the room's hatches are bored while it is one body, then it
is split. A carbon of CUBE rooms comes out as six pieces of 26.64/26.68 m³ summing to 159.99 against
a room of 159.99, all sound, all dicing. `ShipCsgBake` reports `split_rooms` and `cut_back_rooms` so
which construction a room took is never a guess.

**The sphere case had a ROOT CAUSE, and it was the classifier, not the construction** (found
2026-09-22 after the author said, correctly, that the method cannot be shape-dependent):

> "spheres should work out of the box with cubes and any shape fundamentally .. how could the inside
> ever overlap the outside.. and if that isnt the issue then explain what you mean by seam
> overlapping itself?"

A boolean cuts its inputs along their intersections and puts NEW vertices on the TRIANGLES it cut,
not on the surface those triangles approximate. On a curve that is the sagitta away - measured on a
sphere carbon, up to 10 cm - while the test for "is this face on that surface" allowed 2 mm. So
**5853 of 10110 faces of the shell lay on no surface the classifier knew**, a third of the hull was
handed to whichever member was nearest, and the caps built from that were nonsense. A box never
shows it: a flat face has no sagitta.

Each field now measures how far its OWN tessellation dips inside it (`_tolerance_of`, sampling its
faces' centres) and that is the tolerance. **Zero faces unclaimed on either family.** Three of a
sphere carbon's six pieces came right immediately.

**What is left is the cap where the two boundaries do not correspond.** For members whose body patch
is cut into several loops while their cavity makes one - measured, body loops [76,10,10,3,5] against
room loops [3,130] - the cap has one outer ring per inner ring to work with and there is no such
pairing. Those three pieces come out non-manifold and the room still falls back. Deeply overlapping
spheres do this because a cavity can be swallowed whole where the outer surfaces are merely cut.


### What a split piece IS, measured (2026-09-22)

The author, on first sight of the exploded nucleus: **"the cube faces after exploding are looking
very strange like a book shelf"**. Measured on a cube carbon, every piece of the nucleus carries:

- its OWN outer wall - 271.4 m² on each of the four that have a hatch, 270.1 on the two that do not
- its OWN cavity wall - 264.4 and 262.7 m², the same across all six
- and its caps, and nothing else. No piece holds a face of anybody else's hull.

So a piece is a complete hollow shell SEGMENT, and it is OPEN where it fused, because a fused seam
is an OPEN seam - the nucleus is one room, and one room has one cavity. Looking into a piece you see
the far side of its own cavity, which is the shelf.

**That is a change, and it is the correct one.** The older cut-back gave each piece "the shell
within my own body", which swept up the NEIGHBOUR's cavity wall where it reached inside - material
belonging to the next module along - and that stray wall is what used to close the piece off. The
split hands it back to whoever owns it.

**What it leaves open is a design question, not a defect:** a printed module of a fused clump has a
mouth where it meets the next one. If each piece should instead be closed in its own right, that is
a WALLED seam between the nucleus bodies rather than an OPEN one (they are open by default, ADR
0025, and every link is editable) - not a change to how a room is split.


### DONE 2026-09-23, as ADR 0037 - the sphere case, and what it really was

The sphere case closed without anyone touching the split. Its pieces were non-manifold because the
SHELL they were split from was read inside out: `ShipCsgBake._read_raw` took the engine's triangles
in the engine's order, and the engine winds them the other way round from `PolyMesh`. Every baked
solid in the project was inside out, and `PolyMesh.volume()` is absolute, so no check in this
pipeline could see it.

A sphere carbon now splits into six closed pieces summing to **250.809 m3 against a room of
250.821**, and a cube carbon to **315.727 against 315.727**. `MeshSeamSplit` was not changed.


## F49 - The lump at the ship's core, which no piece is joined to

**Measured 2026-09-23** (ADR 0037), on a cube carbon, and present on every `box_hull` class swept.

Where the nucleus bodies meet at the ship's centre, each body's cavity is inset from it by the wall
thickness, so the six cavities all stop short of the middle and leave a small HOLLOW BOX of material
sitting at the core: 1.0028 m3 of shell around a -0.2170 m3 void, a 1 m cube.

**The split divides it correctly** - that is not the question. Each of the six members takes one
face slab of the cube, 0.1310 m3 apiece, and six of those come to 0.7858 m3, which is the lump's net
volume exactly. What each member takes is its own material by every rule the split follows.

**The question is whether the lump should exist at all.** Each slab is detached from the piece that
owns it - cavity surrounds it - so a printed chunk arrives as two solids, one of them a 1 x 1 x 0.2
plate that belongs nowhere anyone can see. Three ways out, none of them chosen:

1. **Let the cavities meet.** Grow the nucleus members' cavities so their union covers the centre
   and no residue forms. Changes what a room's interior IS at a junction, so it needs the author.
2. **Give the lump to one member**, joined or not, so five chunks come out clean and one carries a
   detached cube. Cheapest, and honest about being a fudge.
3. **Drop a piece's detached parts below a size.** Simple, and silently discards real material - the
   pieces would no longer sum to their room, which is the check that catches everything else.

Sphere classes do not have it in any size that matters: their strays measure ~1e-8 m3, float dust.
A cube helium, boron, carbon and neon all do (0.190, 0.253, 0.131 and 0.680 m3 per piece).


## F50 - Halving a coplanar band exactly - DONE (ADR 0039)

**Measured 2026-09-23** (ADR 0038). With a coplanar tie going to the nearer body, a cube helium
divides 242.458 against 231.461 m3 - 4.5% apart, down from 8.9%, where symmetry says halve. The two
bodies were checked and ARE identical: 4000.001 m3 each, span (22.27, 22.27, 15.87), centred at
x = +-5.84.

**Why the rest does not go.** An exact boolean has no reason to split a band where two surfaces share
a plane, so it comes back as a few very large faces: the whole shell of a cube helium is **64 faces**,
about 74 m2 each. The split can only give a face WHOLE, so a face straddling the bisector takes all
of its area to one side. The 110 m2 of surface separating the two pieces is roughly one such face.

**What it would take.** Cut the band's faces at the plane between the two bodies before assigning
them - which puts NEW VERTICES in the shell. ADR 0036 is built on never doing that ("the seam loops
are already vertices of the shell, because that is what an exact union puts there ... this file reads
what the engine already computed and never invents a point"), so it is the author's call, not a
tidy-up. It is also narrow: only a pair whose surfaces share a plane is affected, which is cube
classes standing side by side, and never a curved family.

**The cheaper half-answer**, if it is ever wanted without touching the construction: cut the coplanar
band in the PLAN, by splitting the two members' body meshes along their bisector before the union, so
the engine itself puts the vertices there and the split still invents nothing.


### DONE 2026-09-23, as ADR 0039

Taken by the cheaper half-answer this entry already named, which turned out to be the whole answer:
the band is cut **in the plan**. Both bodies and both cavities are sliced along the plane between
them before anything is unioned, so the ENGINE puts the vertices on the bisector and `MeshSeamSplit`
reads a division it did not invent - ADR 0036's refusal stays intact.

Proved on the shell before it was built: straddling faces went from 4 carrying 234.40 m2 to NONE,
with the shell otherwise identical. A helium of cubes then divided **236.960 against 236.959 m3,
0.0% apart**, from 4.5%. Nothing else in the sweep moved, and the 0.39% a neon of cubes had lost to
ADR 0038's tie-break came back to 0.26%.


## F51 - Four classes are symmetric on no axis at all

**Measured 2026-09-25** (ADR 0044) by `tools/ship_symmetry_check.gd`: `fluorine`, `sodium`,
`phosphorus` and `chlorine` fail the author's hard X rule, each by exactly one arm's weight.

**The cause is structural, not a mistake.** A class takes one nucleus body per proton, clamped to
eight - which is the CUBIC arrangement - and one arm per valence electron. Arms are handed out in
mirror pairs, so an even count balances exactly. **A cube has no vertex on the X plane**, so an ODD
count is left with one arm that has nowhere balanced to stand. All four have odd valence: 7, 1, 5, 7.

**Four ways out, none chosen - it is a decision about what a class IS:**

1. **Give the odd arm a berth on the plane** that is not a nucleus slot - an arm hanging off the
   waist rather than off a corner. Keeps every class's body count, adds a placement rule.
2. **Use a nucleus arrangement that has an X-plane vertex** for odd-valence classes - `pentagonal`
   and `bipyramidal` both do, after ADR 0044's rotation. Changes what those classes look like.
3. **Pair the odd arm**, making the arm count even - i.e. valence stops mapping one-to-one onto arms
   for odd-valence elements. Cheapest to build, and it breaks the chemistry conceit the classes are
   named for.
4. **Let them be asymmetric** and narrow the rule to "where the arrangement allows it". Honest, and
   it gives up the thing the rule was for.

The residual is small - 0.038 to 0.078 of the half extent - so nothing is blocked while it waits.
`ship_symmetry_check.gd` reports rather than gates, and its `GATE` constant is the one line to flip
when this is settled.


### Corrected 2026-09-25 (ADR 0045), and the author's own remedies

The rule is **any one axis**, not X: "com only has to adhear to the axes that are symetrical, and
with 3 orthognal axies to choose from and the constraint that only 1 has to be symetrical means that
any of our pre built shapes should be able to obtain that." Read that way these four are worse than
first recorded, not better - they are symmetric on **no axis at all**, because the leftover arm sits
on a CUBE CORNER and so is off every plane by the same amount. A sodium reads
`centre (1.17, 1.17, -1.17)`, `balance (0.923, 0.923, 0.915)`.

The author's own remedies, which replace the four guesses recorded above:

> "if their structure makes it such that it cant be obtained then you can always increase the sizes
> of one component or more to make it obtainable. but some of the structures are wildly un symetrical
> so my vote is force them to exist in such a way that they are, or cull them."

So: **resize a body to compensate** - the odd arm's moment is known exactly, so the body opposite it
can be grown to cancel it, which keeps the class's shape and its chemistry conceit - **or cull the
class**. Neither is chosen yet, and nothing is blocked while it waits: the builder now reports the
number and marks the centre (ADR 0045) rather than enforcing anything, and balancing by adding
ballast is a later mechanic the author has already sketched as its own minigame.


## F52 - AGENTS.md section 1 still describes the retired all-open studio hull

`AGENTS.md` section 1 says the Phase 1 bake "produces the all-open 'studio' hull with **no walls** -
joint geometry is authored in Phase 1 but not built. That is by design (SPEC section 7) and must
never be read as a bug."

`SHIP_BUILDER_SPEC.md` section 7 retired exactly that sentence four weeks ago:

> RETIRED(ADR 0008, 2026-09-02): "geometry in Phase 2" and "the Phase 1 bake produces the all-open
> studio hull with no walls" -> the seam geometry is built.

So the shared rules file cites a spec section that disowns it. Nothing depends on the stale wording
and no code reads it, but it is the kind of thing an agent leans on: it was nearly used here as
justification for ADR 0047, which needed none - the author asked directly. `AGENTS.md` is the single
source of truth for the rules and belongs to the author, so this is reported rather than edited.

The fix is one RETIRED marker in `AGENTS.md` section 1, per section 10a.


### A lever on F51 that did not exist before (ADR 0048, 2026-09-27)

A cluster can now carry TWO shapes (`OPT_PROTON_FAMILY_B`), and a second shape is a second density.
The four classes symmetric on no axis fail because one arm sits on a cube corner; giving the bodies
opposite it a denser shape is a way to cancel that moment without resizing anything, which is one of
the author's own remedies in a form that is now cheap to try. Not attempted, and the check still
reports the same four.


## F53 - ESC does not leave a component, and two surfaces say it does

Found 2026-09-27 while authoring `ShipKeymap`, not by the UX survey.

`ShipBuilder._leave_isolation()` is reached from exactly two places: `cancel_placement()` and
`_on_part_double_clicked`. With a component open and NO ghost up, `_handle_edit_hotkey` sends ESC
to `set_selection(PackedStringArray())` and the component stays open.

Meanwhile `_isolate()` sets the status line to "EDITING COMPONENT ... - ESC TO CLOSE" and the
on-screen legend (`ship_view3d.gd:1272`) repeats the same promise. So two surfaces tell the player
a key works and it does not - the same shape as B1 (Ctrl+Z) and B7 (the wheel), and the fourth
member of that family found so far.

NOT FIXED. It was not in the step list of `docs/future/ux.md` section 5.1, which was surveyed,
judged and marked safe; adding an unreviewed input change to an overnight run is how a "safe"
batch stops being one. `ShipKeymap` carries the row with `status` DEAD and the note, so the hold-?
card will not print it as if it worked.

The fix is one branch in `_handle_edit_hotkey`: ESC leaves isolation before it clears the
selection, since a player inside a component means the inner thing when they press it.

## F54 - ShipHistory.push gained an additive third parameter

`docs/API_CONTRACT.md:414` pins `func push(doc: ShipDoc, label: String) -> void`. On 2026-09-27 it
gained `key: String = ""`, naming what the edit touched, so that a held key folds into one undo
while two edits to different parts keep their own.

ADDITIVE, in the shape F18-F47 established: the pinned two-argument form still compiles and behaves
exactly as before, because an empty key never folds. Nothing that was written against the contract
had to change. Reported here rather than edited into the contract, per AGENTS section 9.


## F55 - A field shows as many decimals as its step can produce

`API_CONTRACT_UI.md:160` and `SHIP_BUILDER_SPEC.md:435` both say numbers render to **exactly three
decimals** "so field widths do not jitter". As of 2026-09-27 a `NumericField` shows as many as its
own step can produce: 0 for a whole-number step, 1 for a tenth, 2 for a hundredth, 3 otherwise.

THE REASON THE CONTRACT GIVES IS FULLY PRESERVED. The width is held by `FIELD_WIDTH`, a fixed 68 px
right-aligned box, not by the digit count - nothing jitters. The rule as written is stricter than
the reason it states.

The author, seeing it: "angles are to a precision of x.xxx when our smallest snap precision is much
smaller." The arithmetic is theirs. The finest angular snap offered anywhere is 0.1 degrees and the
display resolved 0.001, so at the shipped 0.5 default two of three decimals were structurally zero
on YAW, PITCH and ROT X/Y/Z.

The static `NumericField.format_number()` is UNCHANGED and still gives three - twenty callers
outside the class read it. Only a field's own `_refresh_text()` narrows, and an unquantized field
(a snapped yaw, which really can be 37.418) still shows all three.

Reported, not edited, per AGENTS section 9.

## F56 - effective_ranges() returns five keys and the contract documents four

`API_CONTRACT.md:162` lists four keys returned by `ShapeGen.effective_ranges()`. It returns five -
`step` is the fifth, authored per parameter in `data/shapes/families.json` and carried through both
`_narrow()` and `_pin_neutral()` (`shape_gen.gd:472, 496-502`).

Nothing was broken by the omission, but the inspector threw the key away for as long as it existed
(`inspector.gd:814`, `var step: float = 1.0 if is_int else SNAP_OFF_STEP`), quantizing every float
parameter to 0.001 whatever the pack said - so `round`, authored at 0.01, read `0.020`. Fixed
2026-09-27; the contract line is reported rather than edited.
