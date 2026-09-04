# Diegetic Host (M7)

**Status:** placeholder built, unrun. See "Verification" at the bottom before trusting anything
visual here.

This is the acceptance test for `docs/SHIP_BUILDER_SPEC.md` section 10 (render-to-texture): a
small 3D scene that hosts the whole builder as a texture on a mesh in world space and drives it
by raycast instead of the OS cursor. If something in the builder secretly depended on being a
real window, this is where it breaks.

Files: `harness/diegetic/diegetic_host.tscn`, `harness/diegetic/diegetic_host.gd`
(`class_name DiegeticHost`), `harness/diegetic/screen_surface.gd` (`class_name ScreenSurface`).

## Node structure

`diegetic_host.tscn` is deliberately a single bare `Node3D` with the script attached — no other
nodes are hand-authored in the scene file. Every mesh, light, camera, collider and the
`SubViewport` are built in `DiegeticHost._ready()`, for the same reason `ship_builder.gd` gives
for its own scene: hand-authored `.tscn` text is error-prone and a diff of it is unreadable.

At runtime the tree looks like:

```
DiegeticHost (Node3D)
├── RoomEnvironment (WorldEnvironment)          - dark background, low ambient
├── DimKeyLight (DirectionalLight3D)            - just enough to read room shapes
├── ScreenGlow (OmniLight3D)                    - small warm bleed near the console
├── Floor (MeshInstance3D)                      - no collider (see limitations)
├── Kiosk (MeshInstance3D)                      - podium the screen sits on, no collider
├── ScreenSurface (StaticBody3D, ScreenSurface script)
│     ├── ScreenMesh (MeshInstance3D)           - hand-built quad, StandardMaterial3D
│     ├── Bezel (MeshInstance3D)                 - recessed backing plate
│     ├── FocusIndicator (MeshInstance3D)        - thin bar, recolours on focus
│     └── ScreenCollision (CollisionShape3D)     - thin BoxShape3D flush with the quad
├── FreeLookCamera (Camera3D)                   - current = true, moved by DiegeticHost
└── BuilderViewport (SubViewport, 1280x800)
      └── <ship_builder.tscn instance>          - loaded at runtime, see below
```

`ScreenSurface` has no `.tscn` of its own — `DiegeticHost` builds it with `ScreenSurface.new()`,
sets `width_m` / `height_m` / `viewport_size`, then `add_child()`s it (which is what triggers its
own `_ready()` and the mesh/collider construction). That is the intended reuse shape: it is a
self-contained node type, not a scene, so MHZ_Origins can construct one in code and drop it under
whatever console mesh it already has.

`BuilderViewport` is **not** inside a `SubViewportContainer`. It doesn't need to be — nothing
displays it as 2D UI. It exists purely so `SubViewport.get_texture()` can feed a
`StandardMaterial3D.albedo_texture` in 3D, which is exactly the mechanism SPEC section 10
describes for the in-game host.

## The UV-to-pixel convention, and why no V-flip is needed

`ScreenSurface`'s screen quad is built by hand in `_build_screen_mesh()` (via `SurfaceTool`), not
with `QuadMesh`, specifically so this reasoning can be stated with certainty instead of trusting
an opaque primitive's internal UV layout:

- The quad lies in the node's local XY plane at `z = 0`. Its face normal is local **+Z** — the
  side a player standing in front of the console looks from.
- The vertex at local `(-half_width, +half_height, 0)` — "top-left" to someone facing the
  screen — is assigned `uv = (0, 0)`. The vertex at `(+half_width, -half_height, 0)` —
  "bottom-right" — is assigned `uv = (1, 1)`.
- That makes `u` run left(0)→right(1) and `v` run top(0)→bottom(1). That is **exactly** the
  orientation of `Viewport` pixel space (origin top-left, x right, y down) and of a
  `ViewportTexture` sampled the way it already looks in the editor or on a `TextureRect` (row 0
  of the rendered image is `v = 0`). Both conventions already agree, so
  `ScreenSurface.uv_to_pixel()` is a bare scale — `Vector2(uv.x * 1280, uv.y * 800)` — with **no
  flip**. A vertically mirrored UI is the classic failure mode here, and it is avoided by
  construction rather than by a corrective flip bolted on afterward.
- This agreement is a **choice this file made**, not an engine law. If the quad is ever swapped
  for a built-in primitive mesh (`QuadMesh`, `PlaneMesh`), this has to be re-derived against
  whatever UV layout that primitive actually uses.
- Winding: both triangles in `_build_screen_mesh()` are traced counter-clockwise as seen from
  local +Z (checked by hand with the shoelace formula on both triangles), which is Godot's
  default front face under `cull_mode = CULL_BACK`. Culling is left at its default rather than
  force-disabled, specifically so a mistake here would be *visible* (a black/invisible screen)
  instead of silently masked — see "Verification" below for why that matters here.
- Embedding rule: rotate the **node**, never re-author the mesh. The winding and UV reasoning
  both assume local +Z is still "the viewing side" after any parent transform.

`get_uv_at(world_point)` converts an `intersect_ray()` hit position to local space
(`global_transform.affine_inverse() * world_point`) and reads it against the same half-extents
used to build the mesh, so the mesh and the hit-test can never disagree with each other.

## Input pipeline

Every physics frame, `DiegeticHost` drains a queue of real `InputEventMouseMotion` /
`InputEventMouseButton` events (queued in `_input()`, drained in `_physics_process()` —
`PhysicsDirectSpaceState3D` may only be queried inside a physics frame, the same rule
`ship_view3d.gd`'s `_do_pick()` documents and follows). For each one:

1. Raycast from the active `Camera3D` through **that event's own** screen position
   (`project_ray_origin` / `project_ray_normal`, `PhysicsDirectSpaceState3D.intersect_ray`).
   `DiegeticHost` is the "real world" the builder is mounted in, not the builder itself, so
   reading the camera and mouse position like this is correct here — it would **not** be correct
   inside `harness/builder/` or `core/`, which may never read window size or a global mouse
   position (SPEC section 10 / AGENTS section 7).
2. On a hit whose collider is the `ScreenSurface`, convert the hit point to UV
   (`ScreenSurface.get_uv_at()`) then to a viewport pixel (`ScreenSurface.uv_to_pixel()`).
3. Build a **fresh** `InputEventMouseMotion` / `InputEventMouseButton` — the incoming real event
   is only ever read for its fields, never mutated or reused — and push it into the hosted
   `SubViewport` with `push_input(event, true)`.
4. For motion, `relative` is the difference between this pixel position and the previous one's,
   **in viewport pixel space** (`_last_pixel`, tracked across events while the ray keeps hitting
   the screen) — not the real event's own screen-space `relative`. The first motion event after
   the ray (re)enters the screen gets `relative = Vector2.ZERO` — there is no valid previous
   pixel to diff against yet, and forwarding a large spurious jump on entry is worse than a
   dropped delta on exactly one event.
5. Fields copied onto the fresh event: `button_index`, `pressed`, `double_click`,
   `shift_pressed` / `ctrl_pressed` / `alt_pressed`, and `button_mask` (not in the task's minimum
   list, but real and needed — Godot's own `Control` drag logic reads `button_mask` mid-motion to
   know a drag is in progress) and, for buttons, `factor` (needed for the builder's wheel-driven
   dolly/zoom to scale correctly).
6. On a miss, if a hover/drag was in progress, `sub_viewport.notification(NOTIFICATION_WM_MOUSE_EXIT)`
   fires so hover state does not stick on inside the builder.

Keyboard is forwarded **unchanged** (no coordinate mapping needed) — see the focus model below
for when.

## Focus model

`_focused` is a single bool, and it governs **only keyboard routing**. It exists purely so WASD
and the arrow keys don't drive both the free-look camera and a builder text field at once:

- Entered by any mouse **press** whose ray hits the screen (`_forward_button()` sets it before
  forwarding the click). This means the very click that focuses the device is also delivered to
  whatever it landed on inside the builder — no need to click once to focus and again to act.
- Left only by **Escape**, consumed by `DiegeticHost` and never forwarded.
- While focused, every `InputEventKey` is pushed straight into the `SubViewport`
  (`push_input(key, true)`) and WASD stops moving the free-look camera.
- While not focused, WASD moves the camera and holding the right mouse button while the ray
  **misses** the screen looks around the room.

Mouse routing is **not** gated by `_focused` at all — it is decided purely by the per-event
raycast hit-test. Practically: aiming the cursor at the console always drives the console
(including right-clicks and the scroll wheel); aiming anywhere else always drives the room
camera. This mirrors how a real console works — your hand is either on the device or it isn't —
and avoids a second, redundant "is the mouse allowed to talk to the builder" flag that could
disagree with focus.

`ScreenSurface.set_focused()` swaps the `FocusIndicator` bar's colour and emission energy
(dim teal when unfocused, bright cyan when focused) — the visible half of this state.

## What MHZ_Origins must provide when it adopts this

The placeholder proves the pipeline; it does not ship a production console. When wiring this
into MHZ_Origins:

1. **A collider.** Either reuse `ScreenSurface` as-is (it builds its own `StaticBody3D` +
   `CollisionShape3D`) or, if the game's own console mesh already has a collider, port
   `get_uv_at()` / `uv_to_pixel()` onto that mesh's transform and drop `ScreenSurface`'s built-in
   collider. Either way, the UV convention documented above has to travel with whichever mesh
   ends up doing the raycast hit-test.
2. **A camera.** `DiegeticHost`'s free-look camera is a placeholder for driving the raycast in a
   standalone scene. In the real game the player's own first-person/third-person camera plays
   that role — the only requirement is that *something* calls
   `camera.project_ray_origin/normal(event.position)` against the same event queue pattern shown
   in `_route_event()`.
3. **A focus owner.** Something has to decide when the player's input goes to the device instead
   of their normal character controls — `DiegeticHost`'s click-to-focus/Escape-to-leave model is
   one answer; MHZ_Origins may instead tie this to an interaction prompt ("press E to use
   console"). Either way, the same rule applies: gate **keyboard** on focus, gate **mouse** on
   the raycast hit-test, and don't conflate the two.
4. **A text-entry route for the numeric fields.** SPEC section 10 notes in-game text entry needs
   the device to supply focus and a keypad; the builder's numeric fields are designed to accept
   synthetic input but no keypad exists yet (Phase N, out of scope for M7). Until then, a
   `LineEdit` focused via a forwarded click has no way to receive real character input in-game —
   only a physical keyboard reaches it (through the same `InputEventKey` passthrough this file
   already implements).

## Known limitations of this placeholder

- **Unrun.** This scene has not been opened in the Godot editor or executed. AGENTS section 8c
  reserves the GPU as a single-slot booked resource, and this task was explicitly scoped to not
  claim it — no headless run, no `--import`, no windowed run. Everything above is verified by
  `gdparse`/`gdlint` (pure-Python, no engine) and by hand-reasoning about the mesh/UV
  construction, not by seeing it render. In particular:
  - The winding/culling reasoning (front face visible under default `CULL_BACK`) is derived by
    hand, not confirmed on screen. If the screen renders black from the intended viewing side,
    setting `cull_mode = BaseMaterial3D.CULL_DISABLED` on `_screen_material` is the one-line fix.
  - `harness/builder/ship_builder.tscn` did not exist on disk at the time this was written
    (another agent owns it, still mid-write). `DiegeticHost._load_builder_scene()` checks
    `ResourceLoader.exists()` first and falls back to a solid-colour placeholder `ColorRect` so
    this scene still runs standalone either way, but the *actual* builder-on-a-panel behaviour
    is unverified until that file lands and the whole thing is run once, together.
  - A fresh `class_name` (both `DiegeticHost` and `ScreenSurface`) is invisible to the engine
    until an `--import` pass runs (AGENTS section 8d) — expected, and out of this task's scope.
- **No camera collision.** The free-look camera can fly through the floor and kiosk. Fine for a
  placeholder meant to be flown around and inspected; not fine for a shipped device.
- **Collider depth vs. the true UV plane.** `ScreenSurface`'s collision box has a small physical
  thickness (2 cm) so a StaticBody3D has a real shape at all. A ray hits the box's front face,
  which is flush with (but not infinitesimally on) the quad's `z = 0` plane. At any reasonable
  approach angle for a console the player is meant to stand in front of, the x/y error this
  introduces is negligible; at a nearly grazing angle it would skew the UV slightly. Not
  corrected here — a production version could instead intersect the ray against the mathematical
  plane directly rather than the collider's hit position.
- **No haptic/visual affordance for "hover but not yet focused."** The focus indicator only
  reacts to the `_focused` flag, not to hover. A production console likely wants a lighter
  "you're pointing at me" cue distinct from "you're now controlling me."
- **Single fixed layout.** Screen position, kiosk size and camera start pose are constants, not
  configurable — fine for an acceptance-test placeholder, not for a reusable prefab.
