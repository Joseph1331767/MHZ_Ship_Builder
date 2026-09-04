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

## F9 — `ShipPart.absolute` is dead data — OPEN

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

**Known limits, recorded rather than hidden.** A seam exists only where a part stands on its
parent; two siblings that overlap have no attach plane and merge as they always did, whatever
joint they carry. The metrics grid (`metrics_cell_m`, 0.5 m) is coarser than a wall and does not
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
