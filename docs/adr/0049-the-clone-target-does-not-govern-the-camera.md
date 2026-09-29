# 0049 - The clone target does not govern the camera

- **Date**: 2026-09-28
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - measured `79445dff48f81978` either side of this work. A camera
  reads the document and stores nothing in it; no part, angle or hash is touched, and nothing in
  this ADR goes near `core/`. (That value is **not** the `5536787c6c35d236` quoted by ADRs 0009-0048:
  the fixture moved at some earlier point and the boilerplate was copied rather than measured. See
  FOLLOWUPS F59 - the gate itself passes, and rolling `core/` back to before this session reproduces
  `79445dff48f81978`, so this work did not move it.)
- **Reverses, narrowly**: the camera half of `SPORE_CLONE_SPEC.md` section 2 / section 8b item 17
- **Records**: `docs/future/ux.md` section 7.2.5 (the design this ADR unblocks)

## Context

`orbit_camera.gd` has said since 2026-08-31 that the camera is an orbit turntable and that this is
not a simplification but **the clone target**:

> THE CAMERA IS AN ORBIT/TURNTABLE ONLY: rotate and zoom, nothing else. That is not a
> simplification, it is the clone target.

Two verbs were deleted under that heading and are recorded as `RETIRED(2026-08-31)` in place:
`pan_by()` and `enum View { PERSPECTIVE, TOP, FRONT, SIDE }` with `set_view_preset()`. The evidence
was real - four independent research passes over the official manual, the wikis and the ModAPI
found no pan verb, no reset-view control and no axis-snap views in **any** Spore editor - and the
deletions were correct on the evidence they had.

**The author has now asked for a fly camera twice, the second time in full detail:**

> "a fly mode like minecraft with a themed blue clay with wire edges rendering mode with a
> completely dark environment like deep void of space, where a flashlight is attached to camera,
> and player flys with newtonian physics with some dampening but the feeling of floating in space,
> counter acting your thrust as linear momentum and angular momentum should be continous and
> conserves aside from the very slight dampening we add." (2026-09-27)

and, on finding it absent, "note i dont see flying mode either.." (2026-09-28).

**A fly camera is strictly more camera freedom than either thing that was deleted for being too
free.** Shipping it while the class docstring says the opposite would leave the code quietly
disagreeing with the spec, which is the failure mode AGENTS section 9 exists to prevent. So this is
an ADR, not a diff.

**Why the clone target does not reach here.** The Spore research answers "what did Spore's editor
do", and for the *build gesture grammar* that remains the right question: wheel-scales-the-part,
right-drag-orbits, Alt-clones and hold-A-breaks-symmetry are all researched fact and all stay.
But two premises of this project are not Spore's:

1. **The audience.** The brief is "the UI is too complecated for children to use". A child
   exploring the inside of a ship they built is the single most legible thing in the whole message.
2. **The subject.** Spore's UFO is a prop a few metres across on a dais. This builder produces
   **enterable hulls** with rooms, seams, doors and interior walls (SPEC section 7, ADR 0036,
   ADR 0046). An orbit rig cannot get inside a room, so half of what this module builds has never
   been directly visible. That is a gap in the clone target, not a feature of it.

The clone target also has nothing to say about the diegetic host: Spore had no in-fiction screen.

## Decision

**`SPORE_CLONE_SPEC.md` governs the build gesture grammar. It does not govern the camera.** The
camera answers to the brief's audience and to the fact that these hulls have insides.

Concretely:

- **FLY is added as an announced mode**, a new `ShipFlyCamera` alongside `OrbitCamera` - not a
  mode of it. `OrbitCamera`'s state is four scalars with Y-up welded into `_rig_basis()`; it cannot
  represent roll and must not learn to.
- **`OrbitCamera` is otherwise untouched.** This ADR **does not reopen** `pan_by()` or the
  axis-snap view presets. Both remain retired on their own evidence: they were inventions *within*
  the orbit grammar, where the research applies. Fly is a separate, announced, exitable mode.
- **The exit is guaranteed and printed the whole time.** `V` or `ESC` restores the exact pre-fly
  pose; `F` leaves and frames the ship; `ENTER` leaves keeping the view, discarding roll. `ESC` is
  never the only exit - `diegetic_host.gd` eats it to unfocus the device, so in the shipping path
  it may never arrive.
- **Momentum is conserved, as asked.** Linear and angular momentum both persist, with exponential
  damping so the decay is frame-rate independent and has a statable half-life. Inertia is
  **isotropic**: free-body tumbling is physically gorgeous and, on a camera, is motion sickness.
- **CLAY, the void and the torch are separable and are NOT covered by this ADR.** They are render
  types and shader terms, they touch no camera, and they need no reversal - `DisplayMode` documents
  itself as append-safe. They ship on their own merits.
- **The flashlight is a real `SpotLight3D`** - real cone angle, real inverse-square falloff, real
  shadows, parented to the fly camera.

  **REVISED 2026-09-28, and the first version of this bullet was wrong.** It said the torch had to
  be a faked shader term because `part_faceted.gdshader` is `render_mode unshaded` and "a
  `SpotLight3D` would light exactly nothing", citing FOLLOWUPS F7. The author refused that premise -
  "godot cant render real light sources, shadows, pbr material effects etc.. why do we have to fake
  lighting" - and they were right. F7 was an OPEN finding with **ROOT CAUSE UNKNOWN**, and I treated
  an unsolved bug as a property of the engine.

  Measured in the real viewport: a shaded box reads luma **0.836** under the existing directional
  light, **0.922** with an `OmniLight3D` added, **0.928** with a `SpotLight3D`. Real lights work and
  always did. F7 was a mid-dark albedo multiplied by light and then rounded onto the background
  entry by the 16-colour quantizer - see F7, now RESOLVED.

  So `DisplayMode.CLAY` is a genuinely lit `StandardMaterial3D` with a deliberately bright albedo,
  and the faceted shader keeps every other mode. Its banding is a **style** - every band is an exact
  palette entry, which is what stops a part rendering as one lit face floating in space - and not a
  workaround for a renderer that was never broken.

**Marked in place**: `orbit_camera.gd`'s "THE CAMERA IS AN ORBIT/TURNTABLE ONLY" paragraph carries
a `RETIRED(ADR 0049)` note pointing at `ShipFlyCamera`, per AGENTS section 10a. The sentence stays
true *of that class*, which is why it is annotated rather than deleted.

## Consequences

**Easier.** The insides of a baked hull become directly inspectable for the first time - rooms,
wall thickness at a cut, whether a door was actually bored. That was previously reachable only
through the INTERIOR cutaway mode and a cross-section. Flying a finished hull works in the exploded
and baked views for free, because those already keep the camera's verbs live.

**Harder.** There are now two cameras, and anything hanging off `camera_moved` has to be fed by
both. Two consumers are load-bearing and silent when they starve: `_push_depth_range()` feeds the
part shader's distance cue, and `_push_handle_scale()` the gizmo's metres-per-pixel. A frozen
distance cue looks exactly like a shading bug, so fly keeps the depth range fed from its own
position.

**Corrected.** This ADR shipped once with a faked flashlight, on the strength of an unclosed
finding nobody had re-measured. The correction cost a day and closed a month-old bug. An OPEN
finding with ROOT CAUSE UNKNOWN is a question, not a constraint, and it becomes a false constraint
the moment someone designs around it.

**Constrained.**

- **No `MOUSE_MODE_CAPTURED`, no `warp_mouse`, no `DisplayServer`** - AGENTS section 7. The honest
  cost is that a look-drag reaching the view edge stops. That is why the arrow-key torque pair is
  not optional: it is the only look verb that works on a diegetic quad.
- **No `Input.is_key_pressed`.** `DiegeticHost` feeds the builder through `Viewport.push_input()`,
  which does not set the `Input` singleton. Polled key state is not "worse" in the shipping path,
  it is *dead*. All key state comes from `InputEventKey.pressed`.
- **A budget alert always beats a render variant.** CLAY swaps the palette; a maxed budget must
  never be hidden by a pretty render mode.
- **The clone spec now has a stated boundary**, which is the real cost of this ADR: "is this the
  build grammar or the camera?" becomes a question someone has to answer for each future verb. The
  boundary is written here so it is answered once, in writing, rather than re-litigated per diff.
