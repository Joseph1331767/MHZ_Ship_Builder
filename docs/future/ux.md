# UX Redesign — Idea on Paper

> `docs/future/ux.md`. Per AGENTS §3 this directory is **design notes for phases not built yet**: not CONTRACT, read by no code. Nothing here overrides `docs/API_CONTRACT.md`, `docs/API_CONTRACT_UI.md`, or any SPEC section marked CONTRACT. Where this document proposes changing something those files pin, it says so and routes the change through an ADR.
>
> Written 2026-09-27 from the author's overnight brief, a code survey, a precedent scan of eleven builders, four competing proposals and three adversarial reviews. Every number below was checked against the source; citations are `file:line`.

---

## 1. The brief, and what it is asking for underneath

### 1.1 Verbatim

> "ok, prebuilds should be fine for now. now we can focus on ux, which will have a lot to do with the UI. - ill give you a mixture of intent and ideas and you can run with them while i sleep. - the UI is too complecated for children to use, theres too much information on the screen and no directive. - there needs to be 5 degree snaps in place. there needs to be a large hint/tip/directive bar at the bottom that should react to any state of the builder, any mouse hover and any state of operation. so if user clicks an object, the hint will tell them possible things they can do next. - when adding pieces and parts and mirroring and all the features and functions we have need to all be super linear and user friendly. , use thinktank, iteration, idea-on-paper-first, ui mechanic cloning taking best from known mechanics. - better rotation, position, stretching handles - a super simple view, a more advanced view, and an expert advanced view mode., and just in general making it super easy for a player to build a ship and super duper easy for them, with very small learning curve via direct constant non intrusive real time teaching and guidance. . - also camera fly around modes, hot key legend, etc etc etc."

### 1.2 What it is actually asking for

Eight distinct asks are in there, and they are not equally weighted. Underneath the words:

| The words | The actual requirement |
|---|---|
| "too much information on the screen" | Not "hide things" — **reduce the number of things competing for attention at one time to one**. The screen currently has no focal point and no hierarchy; 65 controls all shout at the same volume. |
| "no directive" | The builder **reports** (`SELECTED p_0003`) and never **instructs**. Of 60 distinct status strings, 5 contain an instruction and one of those is a refusal. |
| "react to any state... any mouse hover" | There is **no hover channel at all**. This is not a tuning job; the data feed does not exist and must be built before any hover-reactive anything can work. |
| "5 degree snaps in place" | 5° already exists and has since the inspector was written. The real ask is a **default**, a **visible** snap, and a snap that **all four input paths obey**. See §2.3 — the code contradicts the complaint, and the underlying problem is worse than the complaint. |
| "super linear" | Every multi-panel flow (make component: 7 steps, 3 panels; link: a 4-state blind cycle) collapses to one surface. |
| "better rotation, position, stretching handles" | The handles are not merely ugly — **three of them are functionally broken** (residue discard, delta.x-only rings, frozen-mid-drag gizmo). "Better" here means "working first". |
| "simple / advanced / expert" | A named ladder where the bottom rung is a **complete** shipbuilding tool, not a crippled one, and the top rung is **provably** a superset of today. |
| "camera fly around modes" | Reverses a documented decision (`orbit_camera.gd:24-25`, SPORE_CLONE_SPEC §8b item 17). Needs an ADR, not a diff. |

And one thing the brief does not say but every part of it implies: **the person who uses this daily is the author, and he must not lose speed.** Two of the three judges weighted that above the child.

---

## 2. What we measured

Everything in this section was read out of the source today. Where a claim in the brief or in a docstring was wrong, it is marked **CONTRADICTED**.

### 2.1 The screen, counted

| Region | Interactive controls | Numbers on screen | Source |
|---|---|---|---|
| Top toolbar | 13 | 0 | `ship_builder.gd:1160-1217` |
| Part palette | 16 (12 cells, 8 permanently blank) | 7 | `part_palette.gd:54-58, 159-185` |
| Tree | 7 | 0 | `part_tree.gd:102-162` |
| Inspector (box_hull, nothing hatched) | 24 | 19 | `inspector.gd:173-214` |
| Inspector (cylinder_spar + hatched seam) | 34 | 27 | same |
| Budget strip | 0 (5 hoverable bars) | 13 | `gauges.gd:113-135` |
| Layers explorer | 3 | 0 | `ship_layers_control.gd:30-50` |
| Tutorial card | 2 | 2 | `tutorial.gd:290-336` |
| **Total at rest, one part selected, tutorial open** | **65** | **~41** | |

Plus **11 grabbable 3D handles** on the selected part, all drawn at once, all always live (`ship_handles.gd:14-16, 54-61`).

Nearly all of it renders at `ShipTheme.FONT_SIZE_SMALL = 11` design px (`ship_theme.gd:30-32`) against `DESIGN_SIZE = Vector2i(1280, 800)` (`ship_theme.gd:37`).

### 2.2 The pixel budget

Verified at `ship_builder.gd:84-88`:

```
HEADER_HEIGHT = 30   LEFT_WIDTH = 236   RIGHT_WIDTH = 292
GAUGE_HEIGHT  = 78   STATUS_HEIGHT = 22
```

Derived: the 3D view gets **748 × 664 = 48.5% of the console**. Of that, the always-on key legend occupies roughly the bottom 140 px — **~21% of the 3D view** — with 10 lines, 502 characters, longest line 72 characters, at 11 px, in the dimmest palette role (`ship_view3d.gd:1286-1319`).

**Important correction that three of the four proposals got wrong.** `LEFT_WIDTH` and `RIGHT_WIDTH` are `custom_minimum_size` on the **columns**, not on the slot frames:

```
ship_builder.gd:1095   left.custom_minimum_size  = Vector2(ShipTheme.pxf(float(LEFT_WIDTH)), 0.0)
ship_builder.gd:1118   right.custom_minimum_size = Vector2(ShipTheme.pxf(float(RIGHT_WIDTH)), 0.0)
```

Hiding `get_slot("TreeSlot").get_parent().get_parent()` therefore yields an **empty 236 px gutter**, not a wider viewport. Any mode that wants the width back must change the value applied at `:1095` / `:1118` / `:1123`.

### 2.3 Snapping — the code contradicts the brief, and the truth is worse

**CONTRADICTED: "there needs to be 5 degree snaps in place."** 5° has been present since the inspector was written.

```
inspector.gd:96   const SNAP_CHOICES: Array = [0.1, 0.5, 1.0, 5.0, 15.0, 0.0]
inspector.gd:97   const SNAP_LABELS:  Array = ["0.100","0.500","1.000","5.000","15.000","OFF"]
inspector.gd:98   const SNAP_DEFAULT_INDEX: int = 1        # 0.500
ship_config.gd:50 var snap_deg: float = 0.5
```

That exact list is also pinned by `docs/API_CONTRACT_UI.md:156`, so **nothing in the frozen contract has to move** to satisfy the brief. What is actually wrong is three separate defects, each worse than the stated complaint:

**(a) There are two angular lattices and the picker only drives one.**

```
inspector.gd:634        _placement.snap_deg = chosen      # the only write
ship_view3d.gd:1148     if _doc != null and _doc.settings.has("snap_deg"):   # read FIRST
ship_doc.gd:128         doc.settings = {"snap_deg": cfg.snap_deg, ...}       # written ONCE, at creation
```

Choose `5.000` and mouse drags plus typed fields snap to 5°, while **numpad rotation and arrow-key placement keep stepping 0.5° forever**. A repo-wide grep finds no other writer of `settings["snap_deg"]`.

**(b) The comment that says otherwise is wrong.** `ship_view3d.gd:128-129` claims the arrow keys use "the same lattice the numpad rotations and the typed fields use". They do not. AGENTS §10a: the code wins, then fix the comment.

**(c) A 5° snap, turned on today, would break rotation entirely.** Verified at `ship_view3d.gd:1381-1405`:

```gdscript
var delta: Vector2 = pos - _handle_last
_handle_last = pos                                    # advances unconditionally
...
var degrees: float = delta.x * ShipPlacement.ROT_DEG_PER_PIXEL   # 0.56
_placement.rotate_selected(axis, degrees)             # RELATIVE, onto an already-snapped value
```

The sub-snap remainder is discarded every motion event. Simulated over 100 events at `snap_deg = 5.0`: a drag delivering 1–4 px per event produces **exactly 0.00°** over 400 px of travel; at 5 px/event it produces 1.000°/px, 79% faster than nominal. The same pattern is **already live** on the offset stalk at the shipped `snap_m = 0.05`: 1 px/event moves 0.000 m over 100 px; 3 px/event moves 5.000 m where 3.00 m was asked.

**Ordering consequence, non-negotiable: the residue fix must ship before the 5° default, or the author will correctly report the brief's headline feature as a regression on day one.**

Two more snap holes found while checking:

- **Committed-part keyboard edits bypass the quantizer.** `ship_placement.gd:638` does `wrap_yaw_deg(value[component] + deg)` with no `_snap_rot()`; `:682` does `part.offset = part.offset + delta_m` raw. A part nudged once off-grid can never be tapped back on.
- **`snap_scale` reaches no drag path.** `ship_config.gd:52 var snap_scale: float = 0.05` has exactly one consumer in the whole repo — a `NumericField` step at `inspector.gd:644`. Two parts cannot be made the same size by hand.

### 2.4 Guidance — where it is silent

- **`set_status()` is the whole channel**: `ship_builder.gd:629-631`, two lines, **78 call sites** across `harness/`, 60 distinct strings, of which **5 contain an instruction**. A selection reports as `SELECTED p_0003`. The bar is 22 px, one line, no autowrap, and its initial text is `READY`.
- **Nothing reacts to hover.** `grep mouse_entered|mouse_exited|make_custom_tooltip harness/ → 0 matches.` `ShipHandles.hit_test()` is called from exactly one place, on a left **press** (`ship_view3d.gd:924`).
- **Nothing reacts to selection.** `_hints_key` is built from five bits — `placing, _axis_lock, _aim_to_normal, _attached_pivot, exploded|baked|isolated` (`ship_view3d.gd:1256-1266`). The selection is not in it, so clicking a part changes zero characters of the legend.
- **34 `tooltip_text` assignments** in all of `harness/`, against 65+ interactive controls, delivered as a 0.5 s hover popup (no `gui/timers/tooltip_delay_sec` override in `project.godot`).
- **The tutorial names two buttons that were deleted.** Verified at `tutorial.gd:154` ("PRESS MAKE ROOM IN THE TREE PANEL", retired 2026-09-04 per ADR 0016) and `tutorial.gd:163` ("PRESS LINK HATCH", retired 2026-09-02). Two of eight steps are dead ends, and step 8's predicate is `_check_never()` so the card can never mark itself finished.
- **Thirteen live verbs appear on no surface**: `G`, `DELETE`, `BACKSPACE`, `F`, `E`, `Ctrl+Z`, `Ctrl+Shift+Z`, `Ctrl+Y`, `ESC`, drag-off-to-delete, right-click-for-the-seam-menu, double-click-to-isolate, `SHIFT+F`.

### 2.5 Verified blockers

| # | Defect | Evidence |
|---|---|---|
| B1 | **Ctrl+Z / Ctrl+Y are dead** whenever the 3D view has focus — which it grabs on every left click (`:916`). `_dispatch_press` passes a bare keycode: `ship_view3d.gd:1081 if _handle_axis_key(key.keycode)`, and `:1092 if AXIS_LOCK_KEYS.has(code)` has no modifier test. `_gui_input` then calls `accept_event()`. Undo silently sets an invisible axis lock instead. | verified in source today |
| B2 | **Drag residue discarded** — §2.3(c). | `ship_view3d.gd:1384-1385, 1401` |
| B3 | **Two snap lattices** — §2.3(a). | `ship_view3d.gd:1148` vs `inspector.gd:634` |
| B4 | **The gizmo freezes mid-drag.** `_refresh_handles()` is called from `_sync_part`, `set_selection`, `set_exploded` and `set_handle_pixel_size` — never from `show_ghost()` or `set_suppressed_part()`. The ring stays at its pre-drag orientation while the ghost spins. | `ship_scene_builder.gd:724, 395-416, 530-535` |
| B5 | **A loaded ship has no handles and no way back.** Bake-on-LOAD ends in `_baked = true`; `ship_view3d.gd:792` routes every event to `_handle_explode_input`. `ShipBuilder._set_baked(false)` has **zero callers in `harness/`** — only `tools/ship_check_views.gd:402` and `tools/ship_visual_check.gd:1368/1969`. | verified today |
| B6 | **The offset stalk and the +Y stretch arrow start at the identical point.** `offset_tail()` returns `Vector3(0, size.y*0.5*MORPH_FACTOR, 0)`; `morph_points()` UP entry is `Vector3(axis.x*half.x, axis.y*half.y, axis.z*half.z)` with `half = size*0.5*MORPH_FACTOR` — the same y. Two unrelated verbs draw as one arrow with a bulge. | `ship_handles.gd:374-398` |
| B7 | **The wheel lies.** `_handle_wheel` scales the selected part whenever `_can_scale()` and only dollies as a fallback, while the legend prints `WHEEL ZOOM`. Select a part, scroll to look closer, the hull inflates 8% a notch. | `ship_view3d.gd:1019-1036` vs `:1298` |
| B8 | **`set_snap_bypass()` has no key bound to it.** It compiles, works, is promised by SPEC §6 and by `data/tuning.json:69`, and the only references in the repo are its own definition and three comments. Shift was reassigned to `DragMode.HORIZONTAL`. | `ship_placement.gd:495` |
| B9 | **Auto-repeat flushes the undo stack.** Echo events pass through for numpad and arrows; each runs a full `begin_edit`/`commit_edit` pushing a whole `doc.to_dict()` snapshot, against `ShipHistory.DEFAULT_DEPTH = 64`. Two seconds of held numpad-4 consumes the entire history. | `ship_view3d.gd:1061`, `ship_history.gd:21` |

### 2.6 Budgets and blocked routes

- **`ship_builder.gd` is 1997 of 2000 lines and 30 of 30 public methods.** Verified. Nothing in any plan fits until lines are bought back.
- **`_viewport.gui_disable_input = true`** (`ship_view3d.gd:297`). Controls placed inside the inner SubViewport **cannot be clicked**. The obvious rescue is also blocked: the `SubViewportContainer` and `view_frame` are Containers and override a child Control's rect on every sort — the bug already written up at `ship_view3d.gd:1222-1231`. **Any clickable floating widget over the 3D view needs a new full-rect `Control` added as a sibling of `Root` on `ShipBuilder` itself** (which is a `Control`, not a Container — the same place `ShipContextMenu`, `ModalLayer`, `ShipStartDialog` and `ShipTutorial` already live).
- **`ShipHistory.undo_label()` / `redo_label()` are written, correct, and called by nothing.** `UNDO` reports the bare word `UNDO`.
- **`PaintMode.handle_key` (KEY_1..KEY_5) has no caller anywhere**, and `_pick_shift` / `_pick_ctrl` / `_pick_alt` are written every click and read nowhere. Keys 1–5 are free.

---

## 3. The design

### 3.0 Where this came from, and the disagreement

Four proposals were written from four angles. Three judges scored them.

| Judge | Winner | Reason |
|---|---|---|
| The eight-year-old | **P1, Kid First** (8) — with mandatory grafts from P4 | Only proposal whose default screen a child can parse in one glance; only one that removes numerals |
| The implementer | **P2, Three Modes** (8.5) | Only plan that buys line budget first; only one that recovers the column width it promises; only one that reached the panels through an existing seam |
| The author as expert | **P2, Three Modes** (8.5) | Only plan that makes expert-tier completeness a falsifiable invariant; found the two bugs that fire in the author's hands (B9, and the unquantized document branch) |

**The synthesis takes P2's spine** — three modes with a strict-superset invariant, and P2's step ordering — **and grafts every `must_graft` the judges named**:

| Graft | From | Why it is mandatory |
|---|---|---|
| Exposure-count decay as the implementation of verbosity | P1 | The only mechanism in any proposal that makes the bar go quiet by itself. Without it every hint bar is a permanent tax on the person who needs it least. |
| Numerals off the child's screen | P1 | A ratio is unreadable at eight; a word is not. |
| Every chip is clickable | P3 | Makes the bar a menu rather than a caption, and a caption is what an expert stops reading in a week. |
| Never write `doc.settings` from the UI | P3 | `doc.settings` is inside `ShipDoc.to_dict()` and therefore inside `ShipHash`; a view preference there becomes an undoable, hash-moving document mutation. |
| Cold open — a framed, selected, grabbable ship on frame one | P4 | Every other plan makes the child choose a ship before they know a single word. |
| Drag a selected part to move it | P4 | The one gesture every beginner tries first currently spins the world. |
| The honest axis lock | P4 | `tests/core/test_attach.gd:754` asserts a ring turns about the axis it is drawn around; the runtime lock breaks that invariant invisibly. |
| Value chip docked to the handle + named inference badge | P4 | The only expert-speed additions in the set that are not bug fixes. |
| Count only states the player COMPLETED | P2 | Otherwise the struggling child is promoted fastest and has their teaching shortened first. |
| Strict-superset invariant on the top tier | P2 | Turns "nothing is lost" from a promise into a test. |

**And it adds the persistent mode strip**, which the author-as-expert judge identified as an omission that disqualifies all four plans as written — see §3.2.4.

**Rejected from all four: the on-object action pill, for now.** It is specified in three proposals as a Control anchored inside the 3D view, where `gui_disable_input = true` makes it unclickable. The chips row does the same job, in a place that already receives input. If the author wants a true on-object pill later, §5 step 19 describes the overlay layer it needs.

---

### 3.1 The three modes

**Names: BUILD / SHAPE / ENGINEER.** (Open question O1 — the child judge preferred `PLAY / BUILD / WORKSHOP`. "BUILD" as tier 1 and "SHAPE" as tier 2 are both building verbs, which is a real weakness. Author's call.)

**Three rules, written into the owner class's docstring and enforced in review:**

1. **ENGINEER is a strict superset.** It is defined as *today's application, plus the hint bar, the mode chip and the gizmo fixes, minus nothing*. If ENGINEER is ever missing a control, that is a defect, not a design decision.
2. **No code path branches on mode to change BEHAVIOUR — only visibility, and which handles are drawn.** Every handle is created in every mode; hiding it must never make it un-drivable by keyboard.
3. **There is exactly one owner of the level** (`harness/builder/ship_ui_mode.gd`, `enum {BUILD, SHAPE, ENGINEER}`, private setter, one `mode_changed(level)` signal). Consumers **query** it; nobody caches it into a bool; no test supplies its own value.

Rule 3 exists because this repo has already paid for breaking it. `ship_handles.gd:5-13` records the retired Tab-gated handle set: *"the flag lived in THREE places at once with different defaults, and a focus change reset it silently. With it off, hit_test returned BALL_ROTATE for every grab... Reported twice before it was found, because the unit test supplied the flag by hand instead of using the app's."* The symptom looked like a maths error. This is the single highest-risk idea in the document.

The mode is persisted in `user://ship_ui.json` following the `ShipExplodeSettings` pattern (`SAVE_PATH` + `FILE_VERSION` + `load_or_defaults`/`save`). It is **view state, never document state** — it must never enter `ShipDoc`.

#### 3.1.1 Control-by-control allocation

| Control | Source | BUILD | SHAPE | ENGINEER | Note |
|---|---|:-:|:-:|:-:|---|
| NEW / OPEN / SAVE | `ship_builder.gd:1191-1193` | ● | ● | ● | |
| UNDO / REDO | `:1195-1198` | ● large, labelled | ● | ● | label from `ShipHistory.undo_label()` |
| ERASE mode toggle | new | ● | ● | ● | for hands that cannot hold DEL |
| FRAME → **FIT** | `:1204` | ● | ● | ● | rename |
| Mode chip | new | ● | ● | ● | |
| Display mode OptionButton | `:1201-1208` | ○ locked SHADED+WIRE | ● 3 of 6 | ● all 6 | |
| DITHER | `ship_view_toggles.gd:26` | ○ | ○ | ● | |
| EXPLODE | `:1205` | ○ | ● | ● | |
| ROOMS: PIECES → **SHOW: PIECES** | `:1207` | ○ | ○ | ● | rename |
| UPDATE MESHES → **BUILD IT** | `:1210` | ○ (via NEXT) | ● | ● | keeps the ` *` stale marker |
| BAKE → **REPORT** | `:1216` | ○ | ○ | ● | rename; it changes nothing on screen |
| HELP | `:1203` | ○ | ○ | ● | replaced by hold-`?` |
| EDIT (leave baked view) | **new**, wraps `_set_baked(false)` | ● | ● | ● | fixes B5 |
| Part shelf — 6 large cells | `part_palette.gd` reskin | ● | ○ | ○ | `can_be_root` filtered while doc is empty |
| Full palette grid + pager + MFR | `part_palette.gd:159-313` | ○ | ● | ● | |
| COMPONENTS list + IMPORT | `:191-249` | ○ | ○ | ● | |
| TREE panel | `part_tree.gd` | ○ | ● | ● | |
| ALL / NO CHILDREN | `:110-111` | ○ | ● | ● | contract-named, hidden not removed |
| BREAK SYMMETRY → **ONLY THIS SIDE** | `:131` | ○ | ● | ● | becomes a view of the MIRROR owner |
| MAKE COMP / MAKE UNIQUE / LINK | `:137-147` | ○ | ○ | ● | LINK becomes 3 explicit buttons |
| INSPECTOR — ATTACH (6 fields + snap) | `inspector.gd:246-283` | ○ | ● | ● | |
| INSPECTOR — SCALE (3 + UNIFORM) | `:285-306` | ○ | ● | ● | |
| INSPECTOR — SYMMETRY row | `:357-408` | ○ | ● | ● | view of the MIRROR owner |
| INSPECTOR — SNAP TARGET readout | `:325-343` | ○ | ● | ● | |
| INSPECTOR — HATCH (8 controls) | `:1102-1143` | ○ | ○ | ● | |
| INSPECTOR — per-family SHAPE params | `:308-315` | ○ | ○ | ● | labelled from a harness-side map, not raw JSON keys |
| Gauges — COMPLEXITY | `gauges.gd` | ● **as a word** | ● as a bar | ● | ROOMY / FILLING UP / NEARLY FULL / FULL |
| Gauges — BBOX / VOLUME / WEIGHT / COST | `gauges.gd:70-76` | ○ | ● | ● | **still computed in every mode** |
| LAYERS explorer | `ship_layers_control.gd` | ○ | ● | ● | also fix its draw order — see §5 step 11 |
| EXPLODE OPTIONS panel | `explode_panel.gd` | ○ | ○ | ● | |
| Seam right-click menu (6 styles) | `ship_builder.gd:73-83` | ○ | ○ | ● | |
| 10-line key legend | `ship_view3d.gd:1212` | **deleted in all modes** | | | content → chips + hold-`?` card |
| Hint bar | new | ● 52 px | ● 52 px | ● 36 px | |
| Gizmo handles | `ship_handles.gd` | 3 | 6 | 11 | created always, drawn by mode |
| FLY camera | new | ○ | ● | ● | |

● shown ○ hidden

**Critical: `GaugesPanel` must keep computing all five rows and keep calling `builder.set_budget_alert()` in every mode.** `API_CONTRACT_UI.md:163-167` — the first such call permanently disables ShipBuilder's own bbox auto-check, so a hidden bar that stops reporting makes a violation silent.

#### 3.1.2 Promotion

Counters live in `user://ship_ui.json`. **A counter increments only on a state the player COMPLETED, never on one they escaped out of** — so a child who cancels five placements in a row is not promoted for failing.

| From → To | Earned when | Offer (hint bar rung 3, 8 s, two in-bar buttons, never a modal) |
|---|---|---|
| BUILD → SHAPE | 12 parts committed, 6 rotation drags completed, 1 save | `YOU HAVE THE HANG OF THIS - SHOW THE NUMBERS?  [Y] YES  [N] NOT YET` |
| SHAPE → ENGINEER | 1 bake completed, 1 seam selected | `DOORS, ROOMS AND SHAPE DIALS LIVE IN ENGINEER - TURN IT ON?` |

A decline costs nothing and sets a three-session cooldown. **Auto-promotion only ever moves up**; stepping down is always manual and always free. The mode chip jumps to any level at any time.

The predicates above are **invented**. See §6, open question O5.

---

### 3.2 The hint bar

#### 3.2.1 Anatomy

Replaces the `StatusBar` `PanelContainer` at `ship_builder.gd:1127-1151`. `STATUS_HEIGHT` 22 → **52** design px in BUILD/SHAPE, 36 in ENGINEER. Every metric through `ShipTheme.pxf()`; nothing reads the window.

```
+----------------------------------------------------------------------------------+
| DRAG THE GREEN RING TO TURN IT                          BOX HULL · 3 PARTS        |  line 1
| it clicks every 5 degrees                  PIVOT FLOAT · AIM NORM · SNAP 5° · MIRROR X |  line 2
|  [R] TURN   [DEL] BIN IT   [CTRL+Z] OOPS                        [ BUILD IT * ]    |  chips + NEXT
+----------------------------------------------------------------------------------+
   LEDE 620px            FACTS 240px          CHIPS 300px          NEXT 120px
```

Four zones in one `HBoxContainer`, stretch ratios 62 / 24 / 30 / 12:

1. **LEDE** — left. Line one at `ShipTheme.font_title()` (16 px, the largest type in the application) in the `text` role, hard-capped at **62 characters**, never wraps, unit-tested for length. Line two (SUB) at `font_small()` in `text_dim`, carries the secondary clause or a gate's verbatim refusal.
2. **FACTS** — right-aligned. Line one is the object schema (`BOX HULL · 3 PARTS`). **Line two is the mode strip** — see §3.2.4.
3. **CHIPS** — up to **3 buttons in BUILD at `font_normal()` (13 px)**, 4 in SHAPE, 6 in ENGINEER at 11 px. Each is `[KEY] VERB`, key glyph in `accent`, verb in `text`. `focus_mode = FOCUS_NONE`. **Every chip is a real Button that performs its verb.** This is the graft from P3 and it is what makes the bar pay rent for an expert instead of being furniture. Sizing note: at 13 px a chip like `[DEL] BIN IT` is ~96 px including padding, so three fit in 300 px and six do not — hence the per-mode cap. P3's original six-at-11-px specification does not fit and is corrected here.
4. **NEXT** — one Button whose label is the highest-priority blocker (Civ's next-turn button). `text_dim` when nothing is pending, `accent` when actionable, `warning` when a budget is violated.

The bake `ProgressBar` becomes a 2 px hairline across the bar's top edge, so it never competes for a zone.

**The bar is outside the 3D SubViewport** — a sibling in the root `VBoxContainer` — which is precisely why its chips can be clicked while an on-object pill cannot (§2.6).

**Non-intrusive is enforced structurally, not by taste.** It never animates, slides, stacks, pops, plays a sound, steals focus or requires dismissal. Only text inside a zone changes. The NEXT button's appearance is **frozen for the entire duration of any gesture** — peripheral motion during a drag is the loudest possible intrusion. Its idle state is an invitation with a verb, never a status word; `READY` (`ship_builder.gd:1134`) is deleted.

#### 3.2.2 Implementation shape

Two files, so the hard part is testable with no GPU slot:

- **`harness/builder/ship_hint_text.gd`** (`class_name ShipHintText`) — **static only, engine-free**. `static func rung(state: Dictionary) -> int`, `static func compose(state: Dictionary, mode: int) -> Dictionary` returning `{lede, sub, facts, strip, chips, next}`. Every literal string in the application's guidance lives here and nowhere else. Unit-tested against a fabricated Dictionary with no scene. This is exactly what `.gdlintrc` means by "a self-contained, statically testable unit with no reference back to the file it came from".
- **`harness/builder/ship_hint_bar.gd`** (`class_name ShipHintBar extends Control`) — the renderer. **It connects itself** to `doc_changed`, `selection_changed`, `history_changed`, `placement_state_changed`, `ghost_state_changed`, `ghost_validity_changed`, `part_picked`, `pick_cleared`, and the new hover signals.

`ShipBuilder.set_status(text)` keeps its exact signature and all **78** call sites; its body now pushes into the transient rung with a 2.5 s decay. **`ShipBuilder` gains zero public methods** (it is at 30/30) and should net *lose* lines, because ~30 literal strings move out.

#### 3.2.3 Verbosity decay — the graft that makes it survivable

Each distinct hint state carries an id and an exposure counter in `user://ship_ui.json`.

| Exposures | Render |
|---|---|
| 0–3 | Full: LEDE line one + SUB line two |
| 4–8 | Short: LEDE line one only |
| 9+ | Chips only; LEDE reduced to the object name |

**The three modes are implemented as three seed values for that counter — 0, 4, 9.** This is the single cheapest structural idea in the whole set: three verbosity levels for one integer instead of three maintained copies of the prose, and it is the only mechanism that makes the bar stop talking at hour 100 without the author disabling it.

A counter advances only on a **completed** state (§3.1.2).

**The inverse ramp, which no proposal had and which matters more for a child than decay does.** Three consecutive refusals of the same kind, or 60 s with no committed edit after a failed attempt, raises the bar back to full form and appends the specific remedy. Guidance that only ever recedes abandons exactly the person it was written for.

#### 3.2.4 The mode strip — always present, never rewritten by hover

**This is the fix for the omission that disqualified all four proposals as written.** The ten-line legend being deleted does not only carry keys; it is the only on-screen display of two **stateful** toggles:

- `P` toggles attached vs floating pivot, and at `ship_view3d.gd:1402` a ring drag **forks on that flag** into `_swing_placement` — the identical handle means two different geometric verbs.
- `NUMPAD 0` toggles aim-at-normal vs aim-at-placement-vector.

Both print their current value permanently today (`ship_view3d.gd:1304-1315`). A hold-to-reveal card cannot show a mode you must read with your hand on the mouse, and a per-gesture chip row cannot carry a flag that is true *between* gestures.

**FACTS line two is therefore a fixed-format, always-present strip**, rewritten only by the state it names, never by hover, never by the rung ladder:

```
PIVOT FLOAT · AIM NORM · SNAP 5° · MIRROR X · LOCK -
```

Shown in all three modes. In BUILD the pivot and aim fields are omitted (neither toggle is bound there) and it reads `SNAP 5° · MIRROR X`.

**Direct consequence for §3.3:** any swept-angle rotation rewrite that writes through `rotate_selected(axis, deg, true)` bypasses `_swing_placement` and silently kills attached pivot. Two of the four proposals specified exactly that. The swept-angle solve must fork on `_attached_pivot` the same way `_drive_handle` does today.

#### 3.2.5 The priority ladder

**Channels first, ranking second.** Most contention never happens because the zones are independent: a **part** hover writes only FACTS; a modifier press writes only CHIPS; a blocker writes only NEXT; the mode strip is owned by nothing else.

Only the LEDE zone needs a ladder. Six rungs, lowest number wins, evaluated by `ShipHintText.rung(state)`; the bar falls back the instant a rung clears, and is never silent because rung 5 always exists.

| # | Rung | Owns LEDE when | Hold |
|---|---|---|---|
| 0 | **REFUSED** | `commit_edit` rolled back, or `GhostState.PREVENT` / `INVALID` | 4 s minimum, `warning` role |
| 1 | **MODAL** | start chooser, save panel, prompt, seam menu — **or the tutorial card, in which case LEDE goes BLANK** so two teachers never talk at once | while open |
| 2 | **GESTURE** | any handle drag, live placement, type-capture, FLY | while live, `selection` role |
| 3 | **TRANSIENT** | 2.5 s post-commit echo; every existing `set_status()` call; a promotion offer (8 s) | timer |
| 4 | **HANDLE HOVER** | pointer within `HOVER_PX` of a gizmo handle | while hovered |
| 5 | **SELECTION / IDLE** | what you can do to the thing you clicked, or the standing invitation (IDLE suppressed in ENGINEER) | default |

**Rung 4 is the one arbitration decision the whole design turns on.** Hovering a *handle* outranks the selection because a ring, an arrow, a stalk and a collar are visually indistinguishable and unguessable. Hovering a *part* is self-evident and is demoted to FACTS, where it can change at 60 Hz without disturbing the instruction.

All hover-driven changes carry a **400 ms dwell in, 150 ms out**, and every zone early-outs on an unchanged composed string — reusing the `_hints_key` comparison pattern already proven at `ship_view3d.gd:1256-1266`.

#### 3.2.6 The state table

Literal strings. LEDE ≤ 62 characters. BUILD wording shown; SHAPE/ENGINEER differ only by decay level and by FACTS carrying ids and 3-decimal values.

| Rung | When | LEDE | SUB | FACTS | CHIPS |
|:-:|---|---|---|---|---|
| 5 | Empty document | `PICK A SHAPE ON THE LEFT TO START YOUR SHIP` | `every ship begins with one piece` | `0 PARTS` | `[?] KEYS` |
| 5 | Idle, nothing selected | `CLICK A PART TO PICK IT UP - OR PICK A SHAPE TO ADD ONE` | `drag the background to look around` | `3 PARTS` | `[RMB] LOOK` `[F] FIT` `[?] KEYS` |
| 5 | Hover a part (LEDE unchanged) | — | — | `BOX HULL · KESSLER` | — |
| 5 | Hover a shelf cell | — | — | *(the family's pack `description`)* | `[LMB] TAKE IT` |
| 0 | Hover an unaffordable cell | *(gate message verbatim)* | `take a part off, or break one pair's mirror` | `HULL RING` | — |
| 5 | One part selected | `BOX HULL PICKED UP - DRAG THE RING TO TURN IT` | `or drag the collar to slide it round` | `BOX HULL · 1 OF 3` | `[R] TURN` `[DEL] BIN IT` `[CTRL+Z] OOPS` |
| 5 | Four parts selected | `4 PARTS PICKED UP - BIN, COPY AND MIRROR HIT ALL FOUR` | `` | `4 PARTS · VALUES DIFFER` | `[M] MIRROR` `[DEL] BIN` |
| 4 | Hover a rotation ring | `DRAG THIS RING TO TURN IT - IT CLICKS EVERY 5 DEGREES` | `hold ALT for any angle` | `RING Y · 0.000°` | `[ALT] FREE` |
| 4 | Hover the collar | `DRAG THIS COLLAR TO SLIDE IT ROUND THE PART BELOW` | `it stays stuck to that surface` | `ON HULL RING` | `[CTRL] LIFT` |
| 4 | Hover a stretch arrow | `DRAG THIS ARROW TO MAKE IT LONGER OR SHORTER` | `` | `STRETCH +Y · 4.000 M` | `[TYPE] EXACT` |
| 4 | Hover the offset stalk | `DRAG THIS STALK TO LIFT IT OFF THE PART BELOW` | `push down to sink it in` | `LIFT · 0.000 M` | `[TYPE] EXACT` |
| 2 | Ring drag live | `TURNING - LET GO TO KEEP IT, ESC TO PUT IT BACK` | `or type a number for an exact angle` | `+45.000° (45.000°)` | `[ALT] FREE` `[ESC] BACK` |
| 2 | Stretch drag live | `STRETCHING - LET GO TO KEEP IT` | `or type a number in metres` | `3.150 M` | `[ESC] BACK` |
| 2 | Offset drag live | `LIFTING IT OFF - LET GO TO KEEP IT` | `it stops every 0.05 m` | `LIFT 0.350 M` | `[ALT] FREE` |
| 2 | Collar / move drag live | `SLIDING IT ROUND - LET GO WHEN IT LOOKS RIGHT` | `` | `ON HULL RING` | `[CTRL] LIFT` `[ESC] BACK` |
| 2 | Placement over empty space | `POINT AT YOUR SHIP - PARTS STICK ONTO OTHER PARTS` | `nothing under the pointer yet` | `PLACING SPHERE POD` | `[ESC] CANCEL` |
| 2 | Placement legal, free surface | `GOOD SPOT - CLICK TO STICK IT ON` | `slide around to find the place` | `FREE SURFACE` | `[ESC] CANCEL` |
| 2 | Placement on a typed target | `SNAPPED TO THE NOSE - CLICK TO STICK IT ON` | `the dots are where this part likes to sit` | `SNAP: NOSE MOUNT` | `[ESC] CANCEL` |
| 2 | Placement, symmetry on | `THIS MAKES TWO - ONE ON EACH SIDE. CLICK TO PLACE.` | `hold A to place just one` | `MIRROR X · COSTS DOUBLE` | `[A] ONE ONLY` |
| 0 | Placement refused (PREVENT) | `TOO HEAVY - TAKE SOMETHING OFF FIRST` | *(gate message verbatim)* | `CANNOT PLACE` | `[ESC] CANCEL` |
| 0 | Moving, pointer off the ship | `LET GO OUT HERE AND THE PART GOES IN THE BIN` | `bring it back over the ship to keep it` | `MOVING BOX HULL` | `[ESC] KEEP IT` |
| 3 | Commit echo | `PUT THE WING ON. CTRL+Z IF THAT WAS WRONG.` | `` | `4 PARTS · ROOMY` | `[CTRL+Z] UNDO` |
| 3 | Delete echo | `REMOVED 3 PARTS` | `ctrl+Z brings them back` | `1 PART` | `[CTRL+Z] UNDO` |
| 3 | Undo echo (`undo_label()`) | `UNDID: PLACE PART` | `ctrl+Y does it again` | — | `[CTRL+Y] REDO` |
| 0 | `commit_edit` rolled back | `THAT WOULD MAKE IT TOO BIG - SO I PUT IT BACK` | *(gate message verbatim)* | `NOTHING CHANGED` | `[CTRL+Z] UNDO` |
| 3 | Undo on an empty stack | `NOTHING LEFT TO UNDO - THIS IS WHERE YOU STARTED` | `` | — | `[CTRL+Y] REDO` |
| 2 | Axis lock engaged | `LOCKED TO X - PRESS X AGAIN TO FREE IT` | `every ring now turns around X` | `LOCK X` | `[X] FREE` `[ESC] FREE` |
| 2 | Type-capture active | `TYPE THE NUMBER THEN PRESS ENTER` | `esc forgets it and keeps the drag` | `45.000° → 4_` | `[ENTER] SET` `[ESC] DROP` |
| 2 | FLY live | `FLYING - W A S D MOVES, HOLD RIGHT-CLICK TO LOOK` | `` | `FLY · 4.0 M/S` | `[SHIFT] FAST` `[ESC] BACK` |
| 2 | Bake running | `BUILDING YOUR SHIP - THIS TAKES A MOMENT` | `it is working, nothing is broken` | `CSG PASS 3 OF 7` | *(none)* |
| 5 | Baked view | `THIS IS THE FINISHED SHIP - PRESS EDIT TO CHANGE IT` | `or press E to pull it apart` | `BAKED · 13 PIECES` | `[EDIT] BUILD` `[E]` `[F]` |
| 5 | Exploded view | `CLICK A PIECE TO LOOK AT IT - PRESS E TO PUT IT BACK` | `` | `13 MODULES · 12 SEAMS` | `[E] ASSEMBLE` |
| 5 | Two touching parts selected | `PRESS L TO PUT A DOOR BETWEEN THESE TWO` | `press again for wall, hatch or open` | `SEAM: WALL` | `[L] NEXT KIND` |
| 0 | Two parts selected, not touching | `THESE TWO DO NOT TOUCH - SLIDE ONE INTO THE OTHER` | `a door needs two parts that overlap` | `NO SEAM` | `[G] SLIDE` |
| 0 | Disabled control clicked | `NEEDS A PART PICKED UP FIRST - CLICK ONE` | `` | — | — |
| 1 | Hold-`?` legend open | `LET GO OF ? TO CLOSE` | `the keys you can use now are lit` | — | — |
| 1 | Tutorial card open | *(blank)* | *(blank)* | *(still live)* | *(still live)* |
| 3 | Promotion offered | `YOU HAVE THE HANG OF THIS - SHOW THE NUMBERS?` | *(in-bar buttons)* `[Y] YES  [N] NOT YET` | `MODE: BUILD` | — |
| 5 | Mode just changed | `SHAPE MODE - NUMBERS ON THE RIGHT, PART LIST ON THE LEFT` | `` | `MODE: SHAPE` | `[?] KEYS` |

**A gate refusal is printed verbatim, never paraphrased.** `ship_builder.gd:670-677` records the reason: the message names the failing quantity and its cap, and wrapping it in a generic prefix buys nothing. In BUILD the child-facing sentence goes in LEDE and the gate's own sentence goes in SUB, so both rules are kept.

---

### 3.3 Handles

**Three fixes first — the gizmo is broken in ways no amount of tiering hides.**

**H1. Carry the residue.** Hold `_ref_px: Vector2` and `_ref_value: float` for the life of a drag and integrate `value = _ref_value + (pos - _ref_px) * gain`, **rebasing both on any modifier transition** so the value never jumps when ALT goes down or up. Quantize only what is written. The quantizer stays exactly where `API_CONTRACT_UI.md:106-108` and SPEC §6 put it — at input time inside `ShipPlacement` — so "what is stored is exactly what is displayed" holds. Fixes B2 for rotation, offset and morph at once.

**H2. Make the rings angular, and keep attached pivot alive.** `_drive_handle` spends only `delta.x`, so all three rings answer identically to horizontal motion and a ring projecting as a tall ellipse cannot be traced. Replace with a swept angle: intersect the pointer ray with the ring's plane, take the angle about the part origin, subtract the angle recorded at the grab so the handle stays under the cursor. Write it through the **absolute** form `rotate_selected(axis, deg, true)`, which already exists (`ship_placement.gd:619-640`, used by the numpad's zeroing keys). **It must still fork on `_attached_pivot` into `_swing_placement`** — see §3.2.4.

**H3. Un-freeze the gizmo.** Give `_refresh_handles()` an optional override transform and call it from `show_ghost()` / `set_suppressed_part()`. Fixes B4. Reuse the existing `HANDLE_PX_TOLERANCE` rebuild gate so frames where nothing moved are skipped.

**Then the design:**

**Three radii per handle**, stated as a rule the code enforces:

| Radius | Value | Meaning |
|---|---|---|
| DRAW | existing `SHAFT_PX 1.5`, `HEAD_PX 4.5`, `ARROW_PX 26`, `TUBE_PX 1.5` | what is painted |
| GRAB | `HIT_PX 9.0` loops, `MORPH_HIT_PX 11.0` points — kept, but must exceed DRAW by a stated margin | what a press catches |
| **HOVER** | **`HOVER_PX 16.0`** — new | what lights up |

**Hover is the single biggest win for the least code.** `ShipHandles.hit_test()` is static, screen-space, allocation-light, physics-free, and is currently called from **one** place, on a press. Calling the same maths on `InputEventMouseMotion` costs nothing and delivers: the hovered handle brightens one LUT step and thickens ×1.6, **every other handle drops to 35% alpha**, the hint bar names the verb, and the cursor changes. An eleven-target gizmo collapses to one readable affordance on approach — which is the real answer to "eleven overlapping targets on a small part".

**Per-mode sets** (created always, drawn by mode):

| Mode | Handles drawn | Count |
|---|---|---|
| BUILD | footprint collar (MOVE), one ring about the mount normal (TURN), one uniform size grip (SIZE) | 3 |
| SHAPE | + the other two rings, + the offset stalk | 6 |
| ENGINEER | + the six morph arrows, + the top/bottom skew gesture | 11 |

Filtered in **exactly two places** — `ShipSceneBuilder._refresh_handles()` for drawing, `ShipView3D._try_begin_handle_drag()` for grabbing — both calling `ShipUiMode.handles_for(level)`, neither caching.

**Identity without hue.** The 16-entry LUT has one red, two ambers and a teal ramp, so saturated per-axis RGB collapses into neighbours after quantization, and red/amber is the classic dichromat pair. Axis identity is carried by a **glyph**: a small `X` / `Y` / `Z` Label drawn in the existing `ViewOverlay` at `Camera3D.unproject_position()` of each ring's screen-rightmost vertex, and the axis letter at each morph arrow's head. Cheap, 2D, survives the whole-LUT alert swap. Adding `axis_x/y/z` roles to `data/palette.json` is a change to a nine-role list `API_CONTRACT_UI.md:70-73` pins — **REPORTED, not done.**

**Geometry fixes:**

- **Separate the offset stalk from the +Y arrow** (B6). Raise `OFFSET_FACTOR` so the stalk's tail clears the morph head by ≥ 14 projected px, draw the shaft as three dashes with a double-chevron head so it cannot read as a seventh stretch arrow.
- **Fair hit precedence.** `_hit_offset` currently returns the moment it is within 11 px, *before* `_hit_morph` is called (`ship_handles.gd:462-466`). Replace with nearest-wins across all candidates, **preserving F13's rings-before-collar intent by adding a +4.0 px bias to the collar's distance rather than by reordering.**
- **Clamp the ring radius in projected pixels.** Today it is `1.42 × bounding-sphere radius` with no screen term, so on a cube the gizmo is 2.46× the part's width — off-screen when close, a knot of crossing arrows when far. Convert through the `m_per_px` `ShipView3D._push_handle_scale()` already pushes and clamp to **[90, 260] projected px**.
- **Honest axis lock.** `_drive_handle` takes `_axis_lock` in preference to `axis_for_handle(_handle_drag)`, so with X locked, grabbing the Z ring rotates about X — and `tests/core/test_attach.gd:754` exists specifically to assert a ring turns about the axis it is drawn around. Fix: when a lock is engaged, **switch the live drag to the locked ring** and dim the two it disables, so what is drawn is still what turns.
- **A drawn cursor.** `Input.set_custom_mouse_cursor()` produces nothing on a diegetic quad and AGENTS §7 forbids reading DisplayServer. `ShipCursor` is a small Control inside the `ViewOverlay` following the last event-local pointer position, with six glyphs: arrow, four-way move, curved rotate, axis-oriented double arrow, crosshair over bare surface, slashed circle over an illegal drop.
- **Click-move-click parity.** A press-and-release inside 4 px and 250 ms does not cancel — it **arms**: the part follows with the button up and a second click commits. Derive the threshold from the existing `CLICK_SLOP_PX = 4.0` so it cannot disagree with the camera's own drag threshold. Serves small hands and trackpads today and **is** the diegetic input path tomorrow, where a synthetic pointer is reliably a tap and unreliably a held drag. **Excluded: drag-off-to-delete stays held-drag only**, or an armed part could wander off the ship and be silently destroyed.
- **Dead code**, ~110 lines with zero callers anywhere: `ring_axis()`, `arrow_lines()` and its three constants, `morph_tick()`, and the whole retired ball chain `_hit_ball()` → `ball_loops()` → `ball_radius()`.

---

### 3.4 Snapping

Four changes, plus three holes closed while the files are open.

**S1 — Make 5° the default.** `data/tuning.json` `snap_deg` 0.5 → 5.0 (the annotated lever already carries min 0.0 / max 15.0 and a player-facing description); `inspector.gd:98 SNAP_DEFAULT_INDEX` 1 → 3.

This is a **tuning retune, not a ruleset bump**. SPEC §4: "ranges gate input, the hash consumes output". Nothing in `core/util/ship_canonical.gd`, `core/ship_hash.gd` or the `ResolvedShape.sdf()` op order moves, so AGENTS §8b's gate does not fire and no ADR is required. **One honest caveat for the devlog:** `doc.settings` is inside `ShipDoc.to_dict()` and therefore inside `ShipHash.doc_hash()`, so **newly created documents will hash differently**. No saved ship's hash moves — `from_dict` restores each doc's own stored value verbatim (`ship_doc.gd:224`) — and `tests/core/test_hash.gd` asserts only doc-to-doc equality, so there is no golden hex to break.

**S2 — One lattice.** Reorder `_snap_degrees()` (`ship_view3d.gd:1147-1155`) to read `_placement.snap_deg` **first**, then `doc.settings`, then `cfg`. One function, three lines, and the numpad and arrow keys finally obey the picker.

**Deliberately NOT doing the obvious fix.** Writing `doc.settings["snap_deg"]` from the inspector would put a view preference inside hashed territory and inside the `begin_edit`/`commit_edit` protocol, making a non-document change undoable — which `ship_view_toggles.gd:4-6` and `ship_layers_control.gd:14-15` both forbid. `doc.settings` stays the load-time seed it already is.

**S3 — Bind the bypass.** `set_snap_bypass()` (B8) gets **ALT held**. Shift is `DragMode.HORIZONTAL` and Ctrl is `DragMode.VERTICAL`, both pinned by `API_CONTRACT_SPORE §8`, so ALT is the only free modifier. The mode strip reads `SNAP OFF` and the ring's ticks fade while it is down, so the bypass is never invisible. **Every simplifying default in this document ships with its release visible in the same frame.**

**S4 — Make the snap visible, three ways at once.**

1. **Ticks cut into the ring**, permanently: 2 px every 5°, 4 px every 15°, a full tick with a printed number at 0/90/180/270 (numbers in SHAPE and ENGINEER only). A child watching the lit tick jump from notch to notch learns discretisation geometrically, before the drag, with no words. Cost note: 72 tick segments against the existing `RING_SEGMENTS = 32` is 2.25× — **measure before assuming it is free.**
2. **A swept wedge** from the grab angle to the current angle at ~40% alpha in `selection`, with the currently-snapped tick one LUT step brighter. **Rendered from the STORED value that `values_changed` carries — never re-rounded here**, or the lit tick drifts half a step from the committed number (SPEC §6).
3. **The mode strip** reads `SNAP 5°` in every mode, and a segmented chip in SHAPE/ENGINEER cycles it (`C` up, `SHIFT+C` down) writing straight to `ShipPlacement.snap_deg`, so the inspector's OptionButton and the chip are two views of one value.

**S5 — The named inference badge.** `ShipPlacement.snap_preview()` already returns `{points, ids, live}` in ship space and is currently consumed only as a ghost tint — that is free information discarded on every drag. Draw the candidates as 6 px screen-space dots, the captured one as a 10 px filled ring, a 1 px dashed leader from the pointer, and a badge 14 px down-right naming it: `NOSE MOUNT`, `FACE +X`, `RIM 3 OF 8`, or `FREE SURFACE` in `text_dim`. **A silent magnet is indistinguishable from a bug.** (Note: some `SnapTargets` ids are generated and will humanise badly; hide the badge text when the id matches `^p_\d+$`. Do not rename ids — SPEC §5.1 makes them immutable.)

**S6 — Close the three holes.** Quantize the document branches of `rotate_selected` (`:638`) and `offset_selected` (`:682`); route `morph_selected` / `scale_selected` / `skew_selected` through a new `_snap_scale()` beside `_snap_angle()` / `_snap_linear()`; coalesce consecutive edits with the same label and changed_ids within 400 ms into one history entry (B9).

**One thing `_try_snap()` must keep doing.** `ship_placement.gd:1040-1042` stores typed-target angles **unquantized** on purpose: "rounding it to the nearest 0.5 degrees would shift the ghost straight back off the point it just snapped to". At 5° that is ten times worse. Do not reroute `_try_snap()` through `_apply_values()`.

**No world grid, ever.** Parts attach by yaw/pitch on a curved surface; nothing is square and 37.4° is a legitimate value. A lattice visual would promise a regularity the geometry cannot deliver. Snap here is presented as an **angle dial**, never a grid.

---

### 3.5 Camera

**This reverses documented decisions and needs an ADR before a line is written.** `orbit_camera.gd:24-25` and `:135-137` record `pan_by()` and the `View {PERSPECTIVE, TOP, FRONT, SIDE}` presets as RETIRED(2026-08-31); `SPORE_CLONE_SPEC.md §8b item 17` asks to "remove our invented axis-snap views and camera pan (Spore has neither)"; and `§2` cites plain-wheel-scaling as researched fact from the official manual. The brief asks for fly modes, and B7 makes the wheel behaviour actively contradict the on-screen text. The ADR states that **the brief's audience overrides the clone target for the camera**, and says so once, in writing, rather than the code quietly disagreeing with the spec.

**Free in every mode (no ADR needed, ship these first):**

- **Easing.** `OrbitCamera` has no `_process`, no tween, no lerp — F, EXPLODE, NEW and OPEN all cut to a new viewpoint in one frame. Add a 220 ms smoothstep on focus/distance/yaw/pitch. All seven existing frame call sites inherit it free. **`camera_moved` must fire on every applied frame**: its consumers are load-bearing (`_push_depth_range` feeds the part shader's distance cue, `_push_handle_scale` sets the gizmo's metres-per-pixel), and a mode that integrates without emitting leaves both stale.
- **Tighter framing.** `frame_aabb` uses `radius = aabb.size.length() * 0.5` — half the *diagonal* — then `× FRAME_MARGIN 1.25`, giving `radius × 2.707` at fov 55. A 10 m cube ends up filling 44% of the view height, so FIT reads as a zoom-out button. Derive from the largest extent and drop the margin to 1.05.
- **FIT is one key and one button, in every state** including FLY, exploded and baked. The number one way a beginner abandons a 3D editor is flying somewhere they cannot return from.

**Needs the ADR:**

- **Plain wheel always zooms** (fixes B7); part scaling moves to `CTRL+wheel` alongside the SIZE grip and PgUp/PgDn. Highest-frequency lie on the screen, and the gesture a beginner tries second.
- **Zoom to cursor.** `handle_input(event, _view_size)` already receives the view size and deliberately ignores it — `orbit_camera.gd:76-77` says the parameter stays precisely so the call site reads as "one event localised to this view of this size". That is the seam. Dolly toward the pointer's unprojected ray.
- **FLY on `V`** (SHAPE and above). `W/A/S/D` translate, `Q/E` rise and fall, `SHIFT ×3`, `CTRL ×0.3`. **Look is hold-RMB-and-drag, never a captured cursor** — `Input.MOUSE_MODE_CAPTURED` and `warp_mouse` are global input-server calls, AGENTS §7 forbids them, and there is no OS cursor on a diegetic quad. **Key state from `InputEventKey.pressed`/`echo`, never `Input.is_key_pressed`** — `DiegeticHost` feeds the builder through `Viewport.push_input()`, which does not set the Input singleton, so a polled WASD would simply be dead in the shipping context. (`diegetic_host.gd:263-270` polls Input for its *own* room camera, which lives in the OS window and is not a pattern to copy inward.) While FLY is live, `A` is strafe rather than hold-break-symmetry; the mode strip says so.
- **The exit contract is printed the whole time and is guaranteed.** `ENTER` keeps the view and hands the orbit rig a pivot at the ray hit ahead; `V` or `ESC` **restores the exact pre-fly pose** over 250 ms. A mode you cannot reliably escape is how you lose a beginner permanently.

**Also:** `CTRL+click` on empty space currently dies at `_do_pick`'s early return before it can move the focus, so there is no way to look at a chosen point in space. Route it to the ray's surface hit. And keyboard orbit is horizontal-only at 8.4°/press (24 px × 0.35), a number that divides neither 90 nor 360 — add a vertical pair and set `ORBIT_KEY_PX` so one press is exactly 5°.

**Do not rename `get_orbit_camera()`, `get_camera()`, `frame_all()` or `frame_aabb()`.** Six headless tool sites reach them through `Object.call()` (`ship_check_views.gd:73`; `ship_visual_check.gd:243/507/1587`; `ship_explode_check.gd:264`; `ship_resolve_check.gd:125/211`) and a rename fails at runtime, not at parse.

**ESCAPE is eaten in the shipping path.** `diegetic_host.gd:122-125` consumes it to unfocus the device before `push_input`. Fly's exit, placement's cancel and the axis-lock clear all ride on that key. Reported; the mitigation is a second non-ESC back-out (`Q` in fly, a `[CANCEL]` chip elsewhere) named alongside ESC in every chip row that mentions it.

---

### 3.6 The hotkey legend

**One table, four consumers, one test.**

`harness/builder/ship_keymap.gd` (`class_name ShipKeymap`, static only) holds `const KEYS: Array[Dictionary]` of `{code, mods, context, group, verb, chip, min_mode}`. Groups are plain words: **LOOK AROUND / PICK AND PLACE / CHANGE A PART / FILE**. Verbs are phrases, not nouns — "put the last thing back" beats "undo".

| Consumer | How |
|---|---|
| The hint bar's CHIPS zone | filtered by live context + mode, so a chip is never offered for an action that is currently illegal |
| The hold-`?` card | the whole table, grouped, current context in `accent`, above-mode rows dimmed and tagged with their mode name (which makes the card a recruitment poster for the next rung at zero extra cost) |
| The mode strip | reads which toggles exist in this mode |
| Eventually, the dispatchers themselves | which is also the structural fix for B1 |

**The card is hold-to-reveal, never a toggle.** Holding `?` or `/` dims the 3D view to 25% and draws a two-column card; releasing removes it. No open state to get stuck in, nothing to dismiss, and it cannot be left covering the ship. It is an in-scene `Control` child of the existing `ViewOverlay` inside the inner SubViewport (`ship_view3d.gd:1231-1236`) — never a `Window` (AGENTS §7) — and `MOUSE_FILTER_IGNORE`.

**The gate:** `tests/harness/test_keymap.gd` greps every `KEY_*` constant dispatched in `ship_builder.gd:1953-1996`, `ship_view3d.gd:1049-1200` (including `NUMPAD_ROTATE`, `ARROW_DELTA`, `AXIS_LOCK_KEYS`) and `ship_dev_feedback.gd`, and **fails if any is missing from the table**. Runs headless, no GPU slot. This is the only mechanism that keeps a legend honest over a year, and it is why the hand-maintained legend currently advertises `WHEEL ZOOM` while the wheel scales.

**`ShipDevFeedback` (`SHIFT+F`) gets a row.** It is the author's most-used binding and it appears in none of the four source proposals except as a grep target. It belongs in the table and in the ENGINEER card.

**Also retire on the way through:** `PaintMode.handle_key` (KEY_1..KEY_5, no caller), `ShipView3D._paint` (assigned, never read), `_pick_shift` / `_pick_ctrl` / `_pick_alt` (written every click, read nowhere). That frees 1–5 and removes three misleading reads.

**BUILD's eleven bright rows:** `LMB` pick a part · `RMB drag` spin the view · `WHEEL` zoom · `F` show me my ship · `M` mirror this part · `DEL` remove it · `CTRL+Z` undo · `CTRL+Y` redo · `ESC` back out · `ALT` any angle (hold) · `?` this card.

---

### 3.7 The linear flows

Counted as **user actions** (clicks, drags, keypresses) plus **panel visits** — a trip from one column to another is the real cost.

#### Add a part

| | Before | After |
|---|---|---|
| 1 | Click a palette cell (12 cells, 8 blank, a dead pager, a disabled MFR picker) | Click a shelf cell (6 large cells, `can_be_root` filtered while the doc is empty) |
| 2 | Ghost raises at yaw 0 / pitch 0 on the parent's nose — often off-screen | Ghost raises **under the pointer**, pre-attached and pre-oriented; **the mirror twin is drawn too** |
| 3 | Move; nothing names the snap | Move; dots on the parent, the captured one ringed and **named** |
| 4 | Click. The twin appears as a surprise | Click. `ADDED ... AND ITS MIRROR. CTRL+Z IF THAT WAS WRONG.` |
| | **2 actions, 1 panel, 1 surprise** | **2 actions, 0 panels, 0 surprises** |

#### Move a part

| | Before | After |
|---|---|---|
| 1 | Click to select | Press on the part and drag. Done. |
| 2 | Press `G` — **named in no legend, no tooltip, no tutorial step** — or hit a 9 px collar with no hover feedback | *(the collar and `G` both still work, and are both named on hover)* |
| 3 | Dragging the part body spins the world instead | Press on empty space spins the world |
| | **2 actions + 1 unadvertised key, or a 9 px target** | **1 gesture** |

**Rule, one sentence:** press on a **selected** part and drag → move; press on an **unselected** part and drag past `CLICK_SLOP_PX` → select and move in one gesture; press **empty space** → orbit.

#### Rotate

| | Before | After |
|---|---|---|
| 1 | Select | Select |
| 2 | Find the right ring among 11 identical grey targets, by clicking | Hover: the ring lights, the others dim, the bar says what it does |
| 3 | Drag; at 5° it moves 0.00°; `delta.y` is discarded so the ring cannot be traced | Drag; the handle stays under the cursor, the protractor ticks, the number rides the handle |
| 4 | Read the result 292 px away in the inspector, among 20 near-identical spinners | Or type the number |
| | **~4 actions + 1 cross-screen read + a broken drag** | **2 actions, no cross-screen read** |

#### Mirror

| | Before | After |
|---|---|---|
| | Three names for one idea across two panels and a held key: the inspector's `MIRROR X/Y/Z/OFF` row, the tree's `BREAK SYMMETRY`, the legend's `A HOLD BREAK SYMMETRY`. The inspector's own tooltip has to send you to a different panel to finish. The twin is invisible until commit. | **One owner** — a `MIRROR: X` badge in the header, cycling OFF→X→Y→Z on click or `M`. The two panel controls become views that write through it and hold no state of their own. The twin is **drawn during the drag** (reflect the already-computed `preview_transform()` through `ShipMirror` — never a second attach solve). |
| | **2 panels, 3 names, 1 surprise** | **1 control, 1 word, 0 surprises** |

#### Link two parts

| | Before | After |
|---|---|---|
| 1 | Select two | Select two |
| 2 | Press `LINK` — the button's label is the constant word "LINK", it never says what the next press will do, the result is reported only *after*, and the starting state is unpredictable because placement auto-hatches | Chips offer **DOOR · WALL · OPEN** explicitly, current one lit; press the outcome you want |
| 3–4 | Press again. And maybe again. | — |
| | **1–3 blind presses** | **1 press** |

BUILD and SHAPE never meet this, because `_default_link_for_placed` already auto-hatches a placed part to its host.

#### Bake

| | Before | After |
|---|---|---|
| | Two adjacent buttons both named after baking. `BAKE` is the obvious one and is **wrong** — it runs a surface-nets pass, changes nothing on screen, and shows a wall of numbers. `UPDATE MESHES` is the one that builds the ship. | `UPDATE MESHES` → **`BUILD IT`**, and it is also what the NEXT button says when the meshes are stale. `BAKE` → **`REPORT`**, moved to ENGINEER. |
| | **1 press, ~50% wrong** | **1 press, 0% wrong** |

#### Make a component (ENGINEER only)

7 steps across 3 panels, whose failure mode is a refusal telling you to go press a button in a fourth place. Minimum change: make `ALL CHILDREN` implicit — `MAKE COMP` on a partial subtree offers `INCLUDE THE 4 PARTS ATTACHED BELOW?  [YES]  [JUST THESE]` through the existing in-scene modal instead of refusing. **7 steps → 5.**

---

## 4. What we are borrowing, and from where

| Mechanic | Source | How it lands here | Status |
|---|---|---|---|
| Complexity as the only gauge a beginner sees, enforced in the palette not a dialog | Spore UFO editor (SPORE_CLONE_SPEC §5) | BUILD shows one bar, as a **word**; all five keep computing | verified |
| Snap to typed targets, never the raw cursor | Spore §3 (`SnapToParentSnapVectors`) | Already cloned in `core/shapes/snap_targets.gd`; we add the dots, the ring and the **name** | verified |
| Five typed ghost states as machine-readable reasons | Spore §3 (`eBlockUIState`) | Already `ShipPlacement.GhostState`; each gets one fixed sentence | states verified; **visual treatment UNVERIFIED in the source game** |
| Symmetry on by default, cascading break, doubled cost | Spore §4 | Already in `core/ship_symmetry.gd`; we draw the twin during the drag and give it a visible release | verified |
| `CannotBeParentless` — teach build order by omission | Spore §1 | `can_be_root` filters the shelf while the doc is empty | verified (field exists in `families.json`) |
| Flat, searchless palette | Spore §6 | Kept flat; **do not add search or categories** — both were removed at the author's instruction | verified |
| Contextual one-line tip at the bottom that rewrites per sub-step | SketchUp status bar | The LEDE zone, verb-first, ≤ 62 chars, one instruction at a time | verified |
| Named inference feedback ("Endpoint", "On Face") | SketchUp | The snap badge — a silent magnet is indistinguishable from a bug | verified |
| Type-a-number mid-drag with no field to click | SketchUp Measurements box | Digits during or just after a drag → `ShipPlacement.set_values()` | verified |
| Click-move-click parity on every tool | SketchUp | Press-release inside 4 px / 250 ms arms instead of cancelling | verified |
| Key **chips** while the hand moves, prose while it is still | Blender modal status bar | CHIPS vs LEDE | verified |
| No-jump precision modifier (rebase the reference on transition) | Blender | The residue accumulator rebases on any modifier change | verified |
| Fly as an announced mode with a **restoring** cancel | Blender walk/fly | `V` / `ESC` restores the exact pre-fly pose | verified |
| Nine-slot hotbar as the whole choice set at minute zero | Minecraft Creative | The six-cell shelf (six, not nine — the pack has four families) | verified |
| Pick-block: "another one of THAT" is a pointing problem | Minecraft Creative | Middle-click or `Q` copies a placed part's family+manufacturer into the shelf | verified |
| Undo and erase as large, permanently visible, named objects | Super Mario Maker (Undodog, Mr. Eraser) | Large labelled UNDO carrying `undo_label()`, plus an ERASE mode toggle | verified |
| Visible menu beats a clever hidden gesture | SMM1 shake → SMM2 tap menu | Every gesture in this document has a visible twin | verified |
| Next-action button whose label **is** the blocker | Civilization V/VI | The NEXT zone, clickable, dim when nothing is pending, never auto-running | verified |
| Disabled-with-reason, and speak the reason on a failed **click** | StarCraft II / Warcraft III | Required, because a diegetic touch screen has no hover | verified |
| Persistent badges showing the current snap and symmetry, cycled by one key | KSP VAB (`C`, `X`) | The mode strip + the `C` snap chip | verified |
| Engineer's Report as non-blocking advice | KSP VAB | Folded into NEXT rather than a separate panel | verified; *whether clicking a row highlights the part is* **UNVERIFIED** |
| Ghost turns red **before** you click | Space Engineers | `GhostState` → ghost tint + LEDE, pre-click | verified |
| Mirror plane as a visible object, not a checkbox | Space Engineers | A `MIRROR` row in `ShipLayersControl.LAYERS` (one entry, by that class's own design) | mechanic verified; *exact keys* **UNVERIFIED** |
| Variant cycling without leaving the ghost | Space Engineers | `[` / `]` step the armed family's manufacturer mid-placement | mechanic verified; *default key* **UNVERIFIED** |
| Three radii per handle; siblings dim on approach | Figma / Illustrator | `HOVER_PX 16` + 35% alpha on the others | verified |
| Rotate zone just outside the resize handle | Figma / Illustrator | Optional last step: an annulus between `MORPH_HIT_PX` and 26 px | verified |
| Dimension chip docked to the manipulator | Fusion 360 / Onshape | The value chip, with its side **frozen at drag start** so it cannot chase the cursor | verified |
| Constraint-state readout ("fully defined") | Onshape | `SNAP: NOSE MOUNT` vs `FREE SURFACE` in FACTS | verified |
| Chrome bound to the gesture that needs it | Animal Crossing / Happy Home | Dots, guides and the protractor appear on grab and vanish on release | mechanic verified; *per-title behaviour* **UNVERIFIED** |
| One verb, fixed anchor, never a sentence | Dark Souls | The chip format | verified |
| Only offer what fits | LEGO Builder's Journey | Grey (never hide) families that cannot attach to the current selection | *"wordless" claim* **UNVERIFIED**; the curated-tray mechanic is not |
| Three fixed semantic zones so a hover cannot disturb the instruction | Windows Explorer / macOS status bars | The four-zone bar | verified |
| Self-paced, scrubbable, one-step-at-a-time build instructions | Nintendo Labo Toy-Con Garage | **Not built now.** Recorded as where a future guided-build mode should go. | verified |

---

## 5. The order of work

**Before any Godot invocation, headless included, claim the GPU slot** (AGENTS §8c):
`../../MHZ_Origins/scripts/gpu_slot.ps1 -Action claim -Lane MHZ-SHIP-BUILDER -Reason "..."`, released in the same message. **After adding any `class_name`**, run `& $env:GODOT_BIN --headless --path . --import` or every reference fails with "Identifier not declared". Verify through the wrapper — `./tools/ship_run.ps1 res://tools/ship_selfcheck.gd` — never bare `-s` (AGENTS §8a).

### 5.1 Steps

| # | Step | Files | Effort | Risk | Alone? | Supervision |
|:-:|---|---|:-:|---|:-:|---|
| **0** | **Buy the line budget.** Extract the four-mode modal into `ShipModal` (`RefCounted`, `(parent, theme)`, the `ShipBakeHud` mould). `_build_modal` (`:1420-1468`) and `_open_dialog` (`:1471-1526`) move wholesale, ~90 lines. `prompt()` (`:641`) and `show_message()` (`:645`) stay as two-line forwarders, so the public count stays at **exactly 30** and no caller moves. Give the modal the keyboard it lacks (ENTER = OK, ESC = cancel), matching `save_dialog.gd:151-165`. | `ship_builder.gd`, NEW `harness/builder/ship_modal.gd`, NEW `tests/harness/test_modal.gd` | S | Low. Grep `tools/ship_resolve_check.gd` and `ship_visual_check.gd` for `_modal` first and keep any name they reach by string. | ✅ | **SAFE TONIGHT.** Nothing in this plan fits on disk until it lands. |
| **1** | **Fix B1.** Pass the whole `InputEventKey` into `_handle_axis_key` and refuse when `ctrl_pressed` or `meta_pressed`. Keyboard undo works again. | `ship_view3d.gd:1076-1095` | T | None. Keep `_handle_key`'s name — `ship_visual_check.gd:783` calls it by string. | ✅ | **SAFE TONIGHT.** |
| **2** | **Fix B3.** Reorder `_snap_degrees()` to read `_placement.snap_deg` first. Fix the false comment at `ship_view3d.gd:128-129` and the two "sixty taps" figures at `:119-120` and `:1059-1060` (a quarter turn at 0.5° is 180 taps, not 60). | `ship_view3d.gd:1147-1155` | T | None; strictly widens the source. | ✅ | **SAFE TONIGHT.** |
| **3** | **Fix B5.** Add an `EDIT` button beside EXPLODE wired to the existing `_set_baked(false)`. Add the baked hint-bar state. | `ship_builder.gd:925-937, 1204-1216` | T | Leave "assemble returns into baked" as is; this only adds the exit. | ✅ | **SAFE TONIGHT.** |
| **4** | **Fix the tutorial's dead steps.** Rewrite steps 6 and 7 against the live controls; give step 8 a predicate that can clear; persist a "seen" flag. | `tutorial.gd:100-178` | S | `ship_visual_check.gd:1454-1488` reaches `_builder.get("_tutorial")` and `tutorial.get("_next_button")` **by name** (FOLLOWUPS F40 item 5). Change strings, never member names. Keep the step-as-method pattern — gdformat duplicates a file header into multi-line lambdas in literals. | ✅ | **SAFE TONIGHT.** |
| **5** | **`ShipKeymap` + the coverage test.** Author the table from all ~37 live bindings including `SHIFT+F`. Nothing reads it for dispatch yet; the test runs one-directionally. Retire `PaintMode.handle_key`, `_paint`, `_pick_shift/_ctrl/_alt`. | NEW `ship_keymap.gd`, NEW `tests/harness/test_keymap.gd` | S | None — pure addition. The `context` column must exist from the first commit or the card will print contradictory rows. | ✅ | **SAFE TONIGHT.** |
| **6** | **Fix B9.** Coalesce consecutive edits with the same label and changed_ids within 400 ms. | `ship_history.gd`, `ship_placement.gd` | S | Changes undo granularity — note it in the devlog. | ✅ | **SAFE TONIGHT.** |
| **7** | **`ShipHintText`** — the pure static resolver and the whole state table of §3.2.6, with a gdUnit4 case per state and a ≤62-char assertion. Renders nothing yet. | NEW `ship_hint_text.gd`, NEW `tests/harness/test_hint_text.gd` | M | None — no renderer exists yet. This is where the value is: the ladder and every literal become tested artifacts. | ✅ | **SAFE TONIGHT.** |
| **8** | **Fix B2 (residue) + H2 (swept-angle rings, forking on `_attached_pivot`).** Add a static test: a synthetic 400 px drag at 1 px/event at snap 5.0 must produce 80 × 5.0°. | `ship_view3d.gd:1381-1447`, `ship_placement.gd` (gains only) | M | **This is the drag feel for every rotation and offset.** Land alone, verify at 0.5 first so a regression bisects to one commit. Re-run `ship_visual_check.gd`'s five-release F13 gate. | ✅ | **AUTHOR'S EYES.** Taste call on feel, and it touches the F13 path. |
| **9** | **Fix B4.** Optional override transform on `_refresh_handles()`, called from `show_ghost()` / `set_suppressed_part()`. | `ship_scene_builder.gd:395-416, 530-535, 724-790` | S | One ImmediateMesh rebuild per motion event; reuse `HANDLE_PX_TOLERANCE`. | ✅ | **AUTHOR'S EYES** (visual). |
| **10** | **Make 5° the default + bind ALT bypass + wire `snap_scale` + quantize the document branches.** | `data/tuning.json`, `ship_config.gd:50`, `inspector.gd:98`, `ship_placement.gd:495/638/682/694-756`, `ship_view3d.gd` | S | Moves the hash of **newly created** docs only (§3.4 S1) — say so in the devlog. Run `ship_validate_data.gd` after the tuning edit. **Must follow step 8.** | ❌ after 8 | **AUTHOR'S EYES.** Taste call on the default. |
| **11** | **`ShipHintBar`** — the renderer. `STATUS_HEIGHT` 22 → 52, four zones, mode strip, clickable chips, NEXT, the progress hairline. Re-point `set_status()`'s body. Surface `undo_label()`. **Also fix the LAYERS explorer**, which is constructed at `ship_builder.gd:1109` *before* `view_frame.add_child(_view)` at `:1114`, so the opaque SubViewport draws over it — move it after `_build_layout()`, where `ShipExplodeControl` already is and visibly works. | NEW `ship_hint_bar.gd`, `ship_builder.gd:88/629/1109/1127-1151` | M | 30 px comes out of the 3D view until step 14 reclaims the gauge strip. Must add **no** public method. Verify the layout at 1280×800 with a headless capture; never read a window size. | ✅ after 0,7 | **AUTHOR'S EYES** (it changes the layout). |
| **12** | **The hover channel.** `static func hover_test()` at `HOVER_PX 16`, plus a part hover through the existing pick path; 400/150 ms dwell; early-out on an unchanged `(part, handle, index)` triple. Brighten the hovered handle, drop the siblings to 35%. Add the drawn `ShipCursor`. | `ship_handles.gd`, `ship_view3d.gd`, `ship_scene_builder.gd`, NEW `ship_cursor.gd` | M | **Adding signals to `ShipView3D` is an addition to a FROZEN contract** — land as a reported addendum plus an ADR in the FOLLOWUPS "additive extensions" series (F18–F47 are all this shape), never a silent diff. Reuse the existing **convex** pick bodies; a `ConcavePolygonShape3D` pick body gets no raycast hits in this SubViewport. Never resolve an SDF on hover. | ✅ after 11 | **AUTHOR'S EYES** (contract addendum + frame cost). |
| **13** | **Hit fairness + the collinear stalk (B6) + the projected-px ring clamp + the honest axis lock.** | `ship_handles.gd:374-477`, `ship_view3d.gd:1398-1405` | M | **Highest-attention.** This is F13's code (FOLLOWUPS:296-345) and the Tab-gate's. Write a static `hit_test()` test with fixed projected positions **before** the edit. `tests/core/test_attach.gd:754` must stay green. | ✅ after 8 | **AUTHOR'S EYES.** |
| **14** | **`ShipUiMode`.** One owner, private setter, one signal, `shows()` and `handles_for()` over one const table. Make `LEFT_WIDTH`/`RIGHT_WIDTH`/`GAUGE_HEIGHT` **tier-aware at the point they are applied** (`:1095/:1118/:1123`) — not by hiding a frame inside a column that carries the minimum. Give `_make_button` an optional key so the header can be addressed without matching on mutable display text. Persist to `user://ship_ui.json`. | NEW `ship_ui_mode.gd`, NEW test, `ship_builder.gd` (~4 lines) | M | **The single highest structural risk in this document** — §3.1 rule 3. Enforce single ownership in review, not by hope. | ❌ after 0 | **AUTHOR'S EYES.** |
| **15** | **Tier the panels.** Additive `set_ui_mode(level)` on the four mounted panels, reached through the duck-typed `has_method` probe `_try_mount` already uses at `:1288-1294`. Each panel hides its **own** sections (every section VBox is unnamed — nothing may reach in from outside). Human labels for the 11 closed `param_key` values; skip any field whose effective range has `min == max`. | `inspector.gd`, `part_tree.gd`, `part_palette.gd`, `gauges.gd`, `docs/FOLLOWUPS.md` | M | **AGENTS §6 lane collision — `harness/panels/` is Antigravity's.** Do every panel edit in **one contiguous handoff**, not interleaved with builder steps. Gauges must keep computing and keep calling `set_budget_alert`. | ❌ after 14 | **AUTHOR'S EYES** (lane handoff). |
| **16** | **Tier the gizmo + the protractor + the ring ticks.** | `ship_handles.gd`, `ship_scene_builder.gd` | M | Measure the 72-segment tick cost. The lit tick comes from `values_changed`, never a display-side round. | ❌ after 13,14 | **AUTHOR'S EYES.** |
| **17** | **Drag-to-move + click-arm parity + gate ALT-clone behind a hit test.** | `ship_view3d.gd:914-957`, `orbit_camera.gd:100-105` | M | The arm threshold must sit below the camera's own drag threshold — derive it from `CLICK_SLOP_PX`, do not invent a second number. Drag-off-to-delete stays held-drag. | ✅ after 12 | **AUTHOR'S EYES** (changes the primary gesture). |
| **18** | **Unify mirror onto one owner + draw the twin ghost + a MIRROR layer row.** | `ship_builder.gd` (badge), `inspector.gd`, `part_tree.gd`, `ship_scene_builder.gd`, `ship_layers_control.gd` | M | Three writers → one writer and two views. The panels must hold no plane state. Reflect the computed `preview_transform()`; never a second attach solve. The plane draws hatched, not low-alpha — the quantizer turns transparency into noise. | ❌ after 14 | **AUTHOR'S EYES.** |
| **19** | **Camera, no-ADR half:** easing, tighter FIT, `CTRL+click` on empty space. **Then the ADR**, then: plain-wheel zoom, zoom-to-cursor, FLY on `V`, vertical keyboard orbit, 5°/press. | `orbit_camera.gd`, NEW `ship_fly_camera.gd`, `ship_view3d.gd:1019-1046, 1186-1199`, NEW `docs/adr/00xx-camera.md` | M | **Two documented reversals.** No captured mouse, no `Input.is_key_pressed`, no renames of the four tool-reached methods. `camera_moved` on every eased frame. | ✅ (first half) | **AUTHOR'S GO REQUIRED** for the ADR half. |
| **20** | **The hold-`?` card**, generated from `ShipKeymap`. | NEW `ship_key_legend.gd` | S | `Control`, never a `Window`; `MOUSE_FILTER_IGNORE`; **inside** the inner SubViewport or its rect gets overridden on sort. | ✅ after 5 | **SAFE** once 5 lands. |
| **21** | **Delete the 10-line legend.** Keep the `ViewOverlay` node and the `_hints_key` early-out pattern; the content is now in the chips, the card and the mode strip. | `ship_view3d.gd:1244-1320` | S | **Do not land before step 11's mode strip exists**, or the pivot and aim toggles become invisible (§3.2.4). | ❌ after 11,20 | **AUTHOR'S EYES.** |
| **22** | **Type-to-commit + the docked value chip + the inference badge.** | NEW `ship_value_box.gd`, `ship_view3d.gd`, `numeric_field.gd` (reuse the parser and the 3-decimal formatter) | M | Digit capture must consume before `G`/`E`/`F`/`DEL`/`ESC`/`CTRL+Z`, and self-cancel on selection change. Use the existing re-entrancy flag for the `set_values`/`update_from_ray` binding — never disconnect a signal. Freeze the chip's side at drag start; clamp 8 px inside the view. | ❌ after 12 | **AUTHOR'S EYES.** |
| **23** | **BUILD's shelf + the cold open.** Six large cells, no pager, no price glyph, no MFR picker; `can_be_root` filter on an empty doc; the pack `description` into FACTS on hover. The app opens on a framed, selected starter hull; the chooser moves behind `START OVER`. | `part_palette.gd`, `start_dialog.gd`, `ship_builder.gd:205-216, 767-781` | L | The starter hull must load **through the normal document path** or the tutorial's predicates stop being honest. Keep the palette's FULL `ShipGate` pass scoped to visible cells when the page size changes. **Do not add search or categories.** | ❌ after 14 | **AUTHOR'S EYES** (biggest taste call in the plan). |
| **24** | **Three-tier headless capture.** Extend `tools/ship_check_views.gd` to capture each mode in one run. | `tools/ship_check_views.gd` | S | None. This is the only thing that stops the two modes the author never opens from rotting silently. | ✅ after 14 | **SAFE** once 14 lands. **Do not ship 14 without it.** |
| **25** | *(optional, last)* The rotate annulus just outside each morph handle. | `ship_handles.gd:450-477` | S | Widening the morph band eats clicks that used to reach the rings. Ship last, behind the mode, and let the author feel it. | ❌ | **AUTHOR'S EYES.** |

### 5.2 Tonight, unsupervised

**Steps 0, 1, 2, 3, 4, 5, 6, 7** — and nothing else. Every one is a bug fix, a pure refactor with forwarders, a string correction, or a new file that nothing reads yet. Together they fix four of the nine verified blockers, buy back ~90 lines of budget, author the entire guidance text as a tested artifact, and leave the running application looking exactly as it does now except that Ctrl+Z works, the snap picker reaches the keyboard, a loaded ship can be edited again, and the tutorial stops naming deleted buttons.

Everything from step 8 on either changes how a gesture **feels**, changes the **layout**, touches F13's code, or makes a **taste call** the author has to see.

---

## 6. What this gives up, and the open questions

### 6.1 What it gives up

**Precision, in BUILD, almost completely.** No numeric field is drawn. A child who wants 47° holds ALT and eyeballs it, or changes mode. Step 22's type-to-commit softens this — you can type a number at the handle without a panel — but it lands late and it is still typing. The full inspector returns unchanged in SHAPE.

**The whole room / seam / hatch / door / component layer is unreachable in BUILD.** A child cannot make a hatched ship, open a door, name a room or make a component. Parts are auto-hatched on placement so a BUILD ship still bakes into something sensible, but the second half of this builder's actual subject matter has no beginner path. This is the largest single cost and I am accepting it rather than inventing a shallow version of a mechanic the SPEC treats as load-bearing.

**BUILD will be under-tested.** The author will live in ENGINEER. The pure static parts (`ShipHintText`, `ShipKeymap`, `ShipUiMode`, `next_action`) are headlessly gated, and step 24 captures all three modes automatically — but the *look* of BUILD remains a human check, and AGENTS §8.5 puts that on the author.

**Three layouts to keep working, forever.** Mitigated by one built tree with a visibility filter (never three construction paths) and by step 24, but the verification cost is real and permanent.

**Mode sprawl is a rebuilt landmine.** `ship_handles.gd:5-13` is the postmortem of the last time this repo had a gated UI flag. The single-owner rule is a discipline, not a mechanism; a later agent adding a fourth read site will not be stopped by anything but review.

**It does less for the author than for the child.** ENGINEER is today's application plus a bar, a chip and the gizmo fixes. The person paying the verification cost gets the smallest share of the work. The bug fixes (steps 1, 2, 6, 8, 9, 13) and the camera work are the parts that land on him.

**It spends two documented reversals** (fly, plain-wheel zoom) on a camera only the author will use daily. Both are behind an ADR and the second half of step 19; both can be dropped without affecting anything else.

**It does not fix the palette grid.** Eight of twelve cells are still blank in SHAPE and ENGINEER, and a pager that can never move is still drawn. BUILD hides it; the grid itself is a one-line tuning question nobody addressed.

**The on-object pill is dropped.** Three proposals wanted one; `gui_disable_input = true` makes it unclickable where they put it. The chips do the job from a place that works. If the author wants a true pill, it needs a full-rect `Control` added as a **sibling of `Root` on `ShipBuilder`** (the same layer `ShipContextMenu` and `ShipTutorial` use) — buildable, but its own step, and it re-fragments guidance the bar exists to consolidate.

### 6.2 What no proposal had, and this document only names

These are real gaps. None is in the step list above because each needs the author's decision first.

**A. There is no sound.** Roughly forty thousand words of proposals and not one mentions audio. Every feedback channel here is text or colour, aimed at the audience that reads slowest. A seat-click when a part lands on a typed target, a softer click on a free surface, a thud on refusal, a tick per snap notch, a pitch that rises with the budget — that is the same lesson the protractor teaches, free, and it works with your eyes on the ship instead of on the gizmo. Nothing in AGENTS or the diegetic contract forbids it; the render-to-texture rule is about DisplayServer and window size, not the audio bus. **This is the largest single omission in the whole exercise.**

**B. The only mandatory typing in the child's flow is the gate between them and keeping their ship.** No proposal mentions autosave. A child who loses twenty minutes of work once does not come back. BUILD needs a zero-character save — an auto-named slot with a rendered thumbnail they recognise by picture, renameable later or never — with continuous autosave behind it.

**C. Every string in this document is uppercase**, inherited from the existing look, for an audience mid-way through learning to read. Early readers lean on word shape, ascenders and descenders, all of which caps destroy. A document whose central artifact is a sentence should have an opinion about the casing of that sentence, and mine is that BUILD should be sentence case — but that is a look change and it is the author's.

**D. Nobody has watched a child use this.** Every promotion predicate in every proposal is invented, and the proposed tests verify that the invented numbers are implemented correctly, which validates nothing. One session — the author sits a child in front of `harness/dev_host.tscn`, says nothing for two minutes, and writes down where they stall — would settle more disagreements between these four documents than every headless test in all four step lists combined.

**E. Nobody asked which of the 65 controls the author has not touched in a month.** The cheapest possible answer to "too much information on the screen" is to instrument the header and the panels for a week and delete what the instrumentation finds dead. Every proposal skipped straight past it to a tier system. It is still the cheapest thing available and it is not in this plan either.

### 6.3 Open questions — only the author can answer

| # | Question | Why it matters | Default if you say nothing |
|:-:|---|---|---|
| **O1** | **Mode names.** `BUILD / SHAPE / ENGINEER` or `PLAY / BUILD / WORKSHOP`? | "BUILD" as tier 1 and "SHAPE" as tier 2 are both building verbs; the child judge preferred the second set. | BUILD / SHAPE / ENGINEER |
| **O2** | **Does the camera ADR go ahead?** Fly mode and plain-wheel-zoom both reverse `SPORE_CLONE_SPEC §8b`. | Clone fidelity is a standing project value; the brief asks for fly explicitly. Step 19's first half ships either way. | Do **not** proceed without your word |
| **O3** | **Is the plain wheel allowed to stop scaling the selected part?** It is sourced to Spore's official manual, and it currently contradicts the on-screen legend. | The single most-attempted beginner gesture does the opposite of what every surface promises (B7). | Ship the fix; it is a bug in the eyes of any user |
| **O4** | **Is a child-facing sentence over a verbatim gate message acceptable?** BUILD shows `TOO HEAVY - TAKE SOMETHING OFF FIRST` in LEDE and the gate's own `COMPLEXITY 148 + 4 / 148 ...` in SUB. | `ship_builder.gd:670-677` records that a refusal should name its quantity and cap and not be wrapped. Both rules are kept here, but it is your call. | Both lines, as specified |
| **O5** | **Promotion predicates.** 12 parts / 6 rotations / 1 save; then 1 bake / 1 seam. | Entirely invented. Unfalsifiable without watching someone. | Ship them, flag them as provisional, revisit after O7 |
| **O6** | **Sentence case in BUILD?** (§6.2 C) | Legibility for early readers vs the console look. | Keep caps |
| **O7** | **Will you sit one child in front of it for two minutes?** (§6.2 D) | Would settle O1, O5 and most of §3.1 on its own. | — |
| **O8** | **Audio.** (§6.2 A) Is an `AudioStreamPlayer` in the builder acceptable, and does the diegetic host route it? | Biggest missing teaching channel; needs to be answered before it is designed. | Not built |
| **O9** | **Zero-typing save + autosave in BUILD.** (§6.2 B) | The one place a child can lose everything. | Not built |
| **O10** | **`data/palette.json` axis roles.** Adding `axis_x/y/z` would break the nine-role list `API_CONTRACT_UI.md:70-73` pins. | Per-axis colour is the biggest legibility win left on the gizmo; glyphs are the fallback shipped here. | Glyphs only; colour REPORTED not done |
