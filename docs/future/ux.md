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

---

## 7. The second pass — the author's response, folded in

> Written 2026-09-27, the morning after commit `113be81`. Section 5 was a plan written from a survey; this section is a plan written from **the author having run the result**. Where the two disagree, this one wins, and it says which line of §5 it is overruling. Same rules apply: this file is design notes (AGENTS §3), it overrides no CONTRACT, and every number below was read out of the source today.

---

### 7.1 What the author said, and what it changes about section 5

#### 7.1.1 Verbatim

> "i dont see any changes when i run, its still somewhat a messy ui experiance. forcing the player to know what to start with and puch. , ill leave some feedback on this that may be applied to our simple to advanced views. these are just ideas without direction. im gonna leav it to you to extrapolate. : angles are to a precision of x.xxx when our smallest snap precision is much smaller. also children may be confused by the inspector, as kids will do it visually by eye, and snaps should be every 5 degrees, or for linear offsets in .1m step grid layout. - i dont see thge tab for simple-to-advanced views. - sclae maybe should read true dimmensions, or have a tab that switches between scale, and true dimensions .1m steps. - i click on a part and do not see your new handle designs or implementations. - when i click on the nucleus i cant select individual parts of that component you know for editing, switching, etc. also when editing the basic meshe3s should be quite fact to stretch or resize, rotate etc, while mesh cutting updates happen in background, i say that because currently something with meshes locks up the ui and doesnt fully let me keep paning etc etc when its supposed to be hot swappable. - we need to address cros children and cross parent children links. as a player may want to build a tunnel that stretched from one electron to another, which would be child of A likning to child of B, where AB are the tunnel nodes. - we should be building the 3d parts in the part palette instead of simple 2d placeholders. - alignment signals that show when parts are aligned, or similar, or symetrical, with center snapping and such. - a fly mode like minecraft with a themed blue clay with wire edges rendering mode with a completely dark environment like deep void of space, where a flashlight is attached to camera, and player flys with newtonian physics with some dampening but the feeling of floating in space, counter acting your thrust as linear momentum and angular momentum should be continous and conserves aside from the very slight dampening we add. - component, make unique, etc are advanced stuff, kisd dont know that stuff, so kids can press a "make part" btn, they simply use it like the ship editor, then when saved it bounces back to real ship editor env and shows the created component in their available parts list )3d render like other symbols). this is where the player can add the part. - our starting node is a selectable option in the beginning, however id rather start with our invisible starting node, and have the players add their first component/part to the env them selves. \*\*\* i have more observations but i think thats a good start such that you can extrapolate. keep in mind that this is an evolving iteration of design so some things that are already in place arent necessaily structured in ui correctly and may be seperate from similar dynamics, may have overlapping btn roles and link / room wall type stuff etc. so ensure all that reads right moving forward. \*\*\*keep the current view as 'dev working view' and ensure you complete the basic, moderate, and advanced views of the software (we may cull some views later if the easiest view is just as composable as the rest)"

And, by SHIFT+F the same morning, on the shape-blend shipped the night before (ADR 0048):

> "the blends on this are technically acceptable, but they arent as balanced as they could be, with only a single electron being a sphere out of 4 total, for best balance there should be 2 sphere electrons and 2 cylinder electrons, opposite sides. also proton is the same way, technically its ok now, but for best balance here having 2 top/bot spheres and 4 boxes, or 4 spheres and 2 tom/bot boxes makes the most symetrical sense. again not a hard constraint but it tech is a better way."

#### 7.1.2 Why the build looked identical — the direct answer

Nothing broke, and nothing was skipped. §5.2 authorised **steps 0–7 and nothing else** overnight, and stated the outcome in advance in its own words: the run would "leave the running application looking exactly as it does now except that Ctrl+Z works, the snap picker reaches the keyboard, a loaded ship can be edited again, and the tutorial stops naming deleted buttons."

Commit `113be81` is exactly that, and the shape of it is the explanation:

| | lines | renders anything? |
|---|---:|---|
| `ship_hint_text.gd` + its test | 2,095 | **no** — the renderer is step 11 |
| `ship_keymap.gd` + its test | 1,564 | **no** — the card is step 20 |
| `ship_modal.gd` (extraction, forwarders kept) | 226 | no change on screen |
| everything else (4 dead bindings, tutorial strings, history coalescing) | ~504 | one new `EDIT` button |
| **total** | **4,389 insertions** | **one button** |

3,659 of 4,389 lines are two data tables and their tests that no code reads yet. The entire visible half of the plan — the hint bar (step 11), the handles (8, 9, 13), the mode tab (14), the 3D palette and the shelf (23) — was marked **AUTHOR'S EYES** and deliberately not attempted unsupervised.

Two further facts about the build that was run: `ShipUiMode` was being written in the working tree at that moment (`git status`: `?? harness/builder/ship_ui_mode.gd`) and was not in it; and the process defect is real — §6.3 O2 said "do not proceed without your word" about fly mode, and then put that consent gate 700 lines into a document rather than in front of the author on waking. That is fixed here: §7.5 is the only thing he has to read to unblock the rest.

#### 7.1.3 What section 5 gets promoted, demoted, or invalidated

Three things in the message change the plan structurally.

**The mode ladder is green-lit, and it is four rungs, not three.** "keep the current view as 'dev working view' and ensure you complete the basic, moderate, and advanced views" answers **O1** outright and removes the risk that made steps 14 and 15 need supervision — the author has named the rungs, and named DEV as *today's UI, preserved*. `harness/builder/ship_ui_mode.gd` has landed with `enum Level { BASIC, MODERATE, ADVANCED, DEV }` and a `SHOWN_FROM` table keyed by node name (`:48-71`). §3.1's `BUILD / SHAPE / ENGINEER` is **retired**: read the §3.1.1 allocation table as BASIC / MODERATE / ADVANCED, with a fourth column DEV that is `●` on every row without exception. The old "ENGINEER is a strict superset" rule becomes "**DEV is today's application, unchanged**", which is a stronger and much more checkable claim.

**"Fly mode" is asked for a second time, in detail.** O2's default was "do not proceed"; the author has now specified thrust, damping, conserved angular momentum, a render type and an environment. That is a go on the *design*, but **not** a licence to skip the ADR: `orbit_camera.gd:7-11, 24-25, 41, 106-107, 135-137` record the orbit-only camera, the axis-snap presets and `pan_by()` as deliberate deletions dated 2026-08-31, citing `SPORE_CLONE_SPEC.md:245` item 17 and four research passes. Step 19's second half stays behind ADR 0049; the CLAY render type, the void and the torch are separable from it and are not.

**Step 23's cold open is half invalidated.** §5 step 23 says "the app opens on a framed, selected starter hull; the chooser moves behind START OVER." The author has reversed that: "id rather start with our invisible starting node, and have the players add their first component/part to the env them selves." The app opens on the **beacon with zero parts**, and the chooser's primitive half is deleted rather than rehomed (it duplicates the part palette exactly — see §7.2.7).

The rest, step by step:

| Old step | Status now | Why |
|:-:|---|---|
| 0–7 | **DONE** (`113be81`) | |
| 8, 9, 13 | **Promoted.** "i click on a part and do not see your new handle designs" is the author noticing that the handle work never started. These move ahead of most of the panel tiering. | |
| 10 | **Promoted and widened.** Still blocked by 8. Gains per-field decimals, the pack's authored step, a `SNAP M` linear picker and a `snap_m` 0.05 → 0.1 retune (§7.2.1). | |
| 11 | **Promoted to the first five.** `ShipHintText` landed last night and renders nothing; this is the step that makes the largest part of last night's work visible. | |
| 12, 16, 17, 18, 22, 25 | **Unchanged**, later. | |
| 14 | **Green-lit, supervision removed, half landed.** Rungs renamed; the tab is not yet on screen. | |
| 15 | **Green-lit.** Now also carries the SCALE/SIZE default and the shape-param labelling. | |
| 19 | **Split.** First half (easing, tighter FIT) unchanged. Second half becomes §7.2.5 in full, behind ADR 0049. | |
| 20 | Unchanged. | |
| 21 | **Demoted and amended.** The 10-line legend may not be deleted in **DEV** — "keep the current view" is explicit. It is hidden from BASIC/MODERATE/ADVANCED by `ShipUiMode` instead. | |
| 23 | **Half invalidated** (see above); the six-cell shelf survives and gains 3D thumbnails (§7.2.4). | |
| 24 | **Promoted from optional to required**, and widened to capture four rungs plus CLAY and a fly pose. It is the only thing that stops three views the author never opens from rotting. | |

Two rules the author added that constrain everything below:

1. **DEV does not lose a control and does not get slower.** Anything that moves a button in DEV is out of scope. Anything that *corrects* a number or a message in DEV is in scope — he made these complaints while running DEV, and pinning the fixes to the other three rungs would leave the one view he uses showing the thing he objected to.
2. **"ensure all that reads right moving forward."** §7.4 is the concrete list of what currently does not.

---

### 7.2 The eight designs

---

#### 7.2.1 The numbers, and the lattice under them — per-field decimals, 5° and 0.1 m, and SCALE vs TRUE DIMENSIONS

**The ask.** Three observations, one topic. (1) "angles are to a precision of x.xxx when our smallest snap precision is much smaller." (2) "snaps should be every 5 degrees, or for linear offsets in .1m step grid layout." (3) "sclae maybe should read true dimmensions, or have a tab that switches between scale, and true dimensions .1m steps."

**What exists today.**

- **The 3-decimal rule is a contract line, not an oversight.** `numeric_field.gd:38-39` pins `DECIMALS = 3` / `NUMBER_FORMAT = "%.3f"`; `API_CONTRACT_UI.md:160` and `SHIP_BUILDER_SPEC.md:435` both say "**always render numbers to exactly 3 decimals** so field widths do not jitter". So this is a request to amend a frozen line.
- **The arithmetic is right.** The finest angular snap offered is 0.1° (`inspector.gd:96 SNAP_CHOICES = [0.1, 0.5, 1.0, 5.0, 15.0, 0.0]`); the display resolves 0.001°. At every one of the five live settings the last two decimals are structurally zero. The shipped default is index 1 = **0.5°** (`:98`), so two of three decimals are dead on YAW, PITCH, ROT X/Y/Z right now.
- **One genuine exception.** `ShipPlacement._try_snap()` stores a snap target's derived angles *unquantized on purpose* (`ship_placement.gd:1030-1042`) — a snapped YAW really can be 37.418, and those two fields are already forced read-only for that reason (`inspector.gd:695-700`).
- **The picker commits the crime it configures.** `inspector.gd:97 SNAP_LABELS = ["0.100","0.500","1.000","5.000","15.000","OFF"]`. Not in any contract.
- **The shape parameters are the worst offender and the data already has the fix.** `data/shapes/families.json` authors a `step` per parameter (`round` 0.01, `twist_deg` 0.5, `end_radius` 0.05, `rib_count` 1); `ShapeGen.effective_ranges()` already returns it (`shape_gen.gd:472, 496-502`, surviving `_narrow()` and `_pin_neutral()`). The inspector throws it away at `:814`: `var step: float = 1.0 if is_int else SNAP_OFF_STEP` — 0.001 for every float param. `round` reads `0.020` against an authored step of 0.01.
- **OFFSET and SCALE both move on 0.05** (`cfg.snap_m`, `cfg.snap_scale`, `ship_config.gd:51-52`, applied at `inspector.gd:637-646`) and both print three decimals: one dead digit each. **There is no linear snap control at all** — `cfg.snap_m` is read once and never exposed.
- **There is no XYZ to put on a grid.** `ship_part.gd:82-86` stores `yaw`, `pitch`, `rot`, `offset` (metres along the parent normal) and `scale`. `offset` is the only authored linear quantity. "linear offsets in .1m step grid layout" can only mean OFFSET and SIZE — §3.4's "no world grid, ever" still holds.
- **True dimensions already exist in `core/`, exactly.** `ResolvedShape.local_aabb()` (`resolved_shape.gd:148-151`) is the part's box with per-axis scale multiplied in; `unscaled_aabb()` (`:157-159`) without. Scale enters as a pure multiply at `:150`, so `scale[i] == size_m[i] / unscaled[i]` — closed form, no solve. Caveat: `_warped_half_extents()` (`:231-250`) pads by `round_r + rib_amp + scallop_amp` deliberately, so on a ribbed part it is the bake's conservative bound, not the exact surface. On the shipped defaults for all four families every amplitude is 0.0.
- `gauges.gd:335-347` already prints `X 12.400 / 30.000 M` — metres on screen is established precedent, at one dead decimal.
- **Budget:** `inspector.gd` is 1,317 lines with **one** public method; `numeric_field.gd` 419 lines. No seam hunt needed. But `format_number()` has **20 callers outside the field** (`gauges.gd` ×11, `part_tree.gd` ×2, `part_palette.gd`, `inspector.gd` ×3) — the static must not move.

**The design.** One principle applied four times: **quantize in the unit the player reads, and show exactly as many decimals as that lattice can produce.**

1. **Per-field decimals.** Add `_decimals: int` to `NumericField`, re-derived in `configure()` and `set_step()`: step ≥ 1.0 → 0; ≥ 0.1 → 1; ≥ 0.01 → 2; else → 3. Four explicit comparisons against a four-entry `const FORMATS`, **not** a dynamic `"%.*f"` — `numeric_field.gd:35-37` already warns that Godot's format operator is a printf subset. `EPSILON_DISPLAY` becomes `0.5 * pow(10, -_decimals)` or `-0` prints at 0 decimals. **Leave the static `format_number()` untouched**; only `_refresh_text()` (`:369-376`) changes. Read-only fields keep 3, which covers the snapped-YAW exception honestly with no special case. Reads become YAW `35` / OFFSET `1.2` / SCALE `1.05` / `round` `0.02` / `twist_deg` `12.5` / `rib_count` `3`. `FIELD_WIDTH` is a fixed 68 px right-aligned box, so nothing jitters — the contract's stated *reason* is fully preserved; the rule as written is stricter than its own reason.
2. **5° default.** `SNAP_DEFAULT_INDEX` 1 → 3 and `data/tuning.json snap_deg` 0.5 → 5.0. This selects an existing entry; `SNAP_CHOICES` does not move and the contract is untouched. `SNAP_LABELS` becomes `["0.1°","0.5°","1°","5°","15°","OFF"]`. **Ship the ALT bypass (§3.4 S3) in the same commit** or a child who needs 37° has no escape, and the mode strip must read `SNAP 5°`.
3. **A linear lattice, and a control for it.** `snap_m` 0.05 → 0.1 — one notch is then exactly one `hull_thickness_m` (`ship_config.gd:40`), a reason a child can feel. Add a `SNAP M` picker beside `SNAP DEG`, choices `[0.01, 0.05, 0.1, 0.5, 1.0, 0.0]`. This is an *addition* to the contract's one-selector sentence (`API_CONTRACT_UI.md:156`) — file it as a FOLLOWUPS addendum in the F18–F47 shape, do not edit the line.
4. **Honour the pack's step.** `inspector.gd:814` → `maxf(_num(spec.get("step", null), 0.0), 0.0)`, falling back to `SNAP_OFF_STEP`. Zero contract cost. Separately report that `API_CONTRACT.md:162` documents four returned keys where five are returned.
5. **SCALE | SIZE M — a toggle, not a replacement.** A two-segment control on the SCALE header. A toggle because `scale` is the stored field and a component author needs the multiplier; because keeping SCALE reachable makes SIZE a second *view* rather than a contract edit; and because it is one control, not a mode. Source of truth `ShapeGen.resolve(..., Vector3.ONE).unscaled_aabb().size`, cached on `family|manufacturer|params`. In SIZE mode the **same three fields** are reconfigured — label `SIZE X/Y/Z`, suffix `M`, step 0.1 (one decimal for free), range `part_scale_min * unscaled[i] .. part_scale_max * unscaled[i]` so the model clamp is expressed in the unit on screen. Typing quantizes and clamps **in metres**, then `part.scale[i] = typed_m / unscaled[i]`. **`snap_scale` is not reapplied on this path** — a cylinder of unscaled Y 3.0 taking a typed 2.5 would produce scale 0.8333, snap to 0.85, and read back 2.55. One lattice at a time, in the unit shown. **The uniform lock is the one thing that cannot be ported verbatim:** `inspector.gd:590-594` copies the raw typed value; in SIZE mode it must copy the *scale* and write `other.set_value(unscaled[j] * new_scale)`, or three axes with different extents get silently distorted. Label the row `SIZE`, never `EXACT SIZE`.
6. **Make the handles agree.** A `_snap_size()` beside `_snap_angle()`/`_snap_linear()` (§3.4 S6) quantizing the resulting **SIZE** to 0.1 m — `scale_selected()` is `pow(SCALE_STEP, delta)` and `morph_selected()` is `1.0 + delta * MORPH_PER_PIXEL`, both multiplicative, so quantizing the product and not the factor is the only thing that stops a drag ratcheting. And give the BBOX gauge the same decimal rule, or the ship's size and a part's size disagree about how precise a metre is.

**Per view.** The decimal fix and the authored-step fix are **the same in all four rungs including DEV** — they are truth fixes, not simplifications, and the complaint was made while running DEV. Everything else tiers: BASIC shows SIZE M only with no SCALE segment and no snap pickers (5° and 0.1 m are simply how the world works, ALT to escape, the mode strip says so); MODERATE shows SIZE by default with the SCALE segment and both pickers minus their OFF entries; ADVANCED shows both segments with the last choice remembered, both pickers with OFF; DEV keeps SCALE as the default readout and both pickers, and gains only the decimals and the authored steps.

**Steps.** (T = trivial, S = small, M = medium)

| | Step | Files | E | Risk |
|:-:|---|---|:-:|---|
| a | Honest picker labels | `inspector.gd:97` | T | none; display only |
| b | Per-field decimals in `NumericField` | `numeric_field.gd:38-40, 138-151, 228-239, 369-376` | S | **amends `API_CONTRACT_UI.md:160` + `SPEC:435`** — report, do not edit. Do not touch the static. |
| c | Honour the pack's authored step | `inspector.gd:814` | T | a saved value coarser than its pack step re-quantizes on first edit of that field, never on load |
| d | 5° default + ALT bypass + `SNAP 5°` in the strip | `inspector.gd:98`, `data/tuning.json:67-72`, `ship_placement.gd` | S | **must follow old step 8.** Moves the hash of *newly created* docs only (`ship_doc.gd:128`); re-run `ship_validate_data.gd`; the tuning `description` at `:69` claims a bypass modifier that does not yet exist |
| e | `snap_m` → 0.1 + the `SNAP M` picker | `data/tuning.json:73-78`, `inspector.gd:260-282, 637-646` | S | contract addendum, not an edit |
| f | The SCALE \| SIZE M toggle | `inspector.gd:285-305, 583-598, 637-690` | M | **the uniform lock must be rewritten in scale units** or the toggle introduces a distortion bug. Panels lane. Cache the extent or it resolves per keystroke. |
| g | `_snap_size()` on the document branches | `ship_placement.gd:586-605, 619-683, 694-756` | S | quantize the product, not the factor. **Do not** reroute `_try_snap()` through it. |
| h | BBOX gauge decimals | `gauges.gd:335-347` | T | local formatter; leave `_cap_text` alone |

---

#### 7.2.2 Editing inside a component, and the MAKE PART flow

**The ask.** (1) "when i click on the nucleus i cant select individual parts of that component you know for editing, switching, etc". (2) "kids can press a 'make part' btn, they simply use it like the ship editor, then when saved it bounces back to real ship editor env and shows the created component in their available parts list (3d render like other symbols)."

**What exists today.** The verdict on (1) is **both, plus a third thing**: isolation works, it is effectively invisible, and once you are in it, it is a dead end.

- **It works.** Double-click an instance → `_isolate` (`ship_builder.gd:1477-1497`); the rest of the ship wears a washed material (`ship_scene_builder.gd:1170-1173`); a pick inside resolves to the **inner** part (`:1098-1101`); the inspector reads it through `doc.part_at` (`ship_doc.gd:447-459`) and the commit writes back into the definition so every instance follows (`ship_components.gd:628`). The literal claim "i cant select individual parts" is **not** true of the code.
- **The nucleus really is a component** — `ShipTemplates._lift_nucleus` calls `make_component` and the instance becomes `doc.root` (`ship_templates.gd:1254-1286`). One click correctly selects the whole nucleus (ADR 0024).
- **It is invisible.** The only place in the entire UI that names the gesture is the 3D legend, and only in the baked (`ship_view3d.gd:1314`) and already-isolated (`:1300`) branches. The assembled branch (`:1324-1345`) is eleven lines of legend that never mentions it. No button, no context-menu entry, no tooltip.
- **The one panel that is a hierarchy browser hides the hierarchy.** `PartTreePanel._build` walks `doc.part_order()` (`part_tree.gd:213-218`) — document parts only — so an instance is a **childless leaf** reading `[C] p_0001 NUCLEUS (7 PARTS)`. The row states that seven parts exist and gives no way to reach one. This is the strongest grounding for the complaint.
- **It is a dead end (F53, confirmed).** `_handle_edit_hotkey` sends ESC to `cancel_placement()` when a ghost is up, otherwise to `set_selection(PackedStringArray())` (`ship_builder.gd:1905-1911`); `_leave_isolation` is never reached. Meanwhile `_isolate` sets "EDITING COMPONENT … - ESC TO CLOSE". `ship_view3d._dispatch_press` does not claim a bare ESC unless an axis lock is live (`:1111`), so the key really does arrive and really is thrown away. The only exit is double-clicking empty space — the same undiscovered gesture in reverse.
- **DEL is silently refused inside a component.** `delete_selected` reads `_doc.parts.get(pid, null)` (`:509`); an inner id is never in `doc.parts`, so the player gets "NOTHING DELETABLE IN SELECTION" — a message that blames their selection for a limitation of the feature.
- **You cannot add to a component from inside it.** `store_inner_part` (`ship_components.gd:628`) only overwrites. A part placed on an inner proton becomes an ordinary document part parented `<instance>/<inner>` — legal (ADR 0024) but not a member of the definition.
- **The component list is text, and the code says why.** `part_palette.gd:199-206` builds an `ItemList`; `:189` states "a component has no single primitive to draw a glyph for". The author's "no 3d render" is literally true and documented.
- **There is no inverse verb.** `ShipComponents.dissolve` (`ship_components.gd:884`) is written, documented, tested, and has **zero callers** in `harness/` or `tools/`.
- **The seam MAKE PART needs already exists.** `ShipComponents.import_from(doc, other, label)` (`:711-762`) takes a whole second `ShipDoc` and lands it in this document's `components`: it flattens an instance root by dissolve-on-a-copy, carries joints (ADR 0025), remaps nested ids, and returns the new ids with the whole ship's **last**.
- **Budget:** `ship_builder.gd` is **1,955 lines / 30 public methods**. No new public method fits. `_replace_doc` (`:611`) swaps `_doc` and leaves `_history` alone.

**The design.** Two halves that share one mechanism.

**Half A — reachable and survivable.**
- **A1. The breadcrumb band.** When `_isolated` is non-empty, a band across the top of the 3D view: `INSIDE: PROTON CLUSTER   [ DONE ]`. It must be a full-rect `Control` added as a **sibling of `Root` on `ShipBuilder`**, beside `ShipContextMenu` / `ModalLayer` — §2.6 establishes that as the only place a clickable overlay can live (`ship_view3d.gd:297` sets `gui_disable_input = true` and the container overrides child rects). Not a tree header: `ship_ui_mode.gd:56` gives BASIC **no tree at all**, and BASIC is exactly where a player most needs the way out.
- **A2. ESC actually leaves (F53).** One branch before the selection clear; order ghost → isolation → selection. Three lines.
- **A3. Click again to go in.** Keep double-click (SketchUp's, and the author knows it) and add: a single click on an already-selected instance descends and selects the piece under the pointer. Blender's and Figma's behaviour. It matters because double-click is a motor skill some eight-year-olds lack, and because it makes the gesture discoverable by accident — the one thing double-click can never be.
- **A4. The tree grows the inside.** Child rows per inner part keyed `"<instance>/<inner>"`; selecting one enters isolation. **Required fix on the way:** `PartTreePanel._part` (`part_tree.gd:999-1005`) reads `doc.parts.get()` and must become `doc.part_at()` — precisely the trap the `components-are-rooms` memory records.
- **A5. An honest refusal before an honest feature.** DEL inside isolation says `PIECES OF A PART CANNOT BE REMOVED YET - PRESS DONE, THEN TAKE APART`. Real inner add/delete needs new core and is later; the lying message is a five-minute fix and should not wait for it.
- **A6. TAKE APART.** Wire the existing `dissolve`. **Gate:** F37 / the `components-are-rooms` memory record a *measured, unexplained* result — a dissolved nucleus with OPEN links baked 8 open pieces where the component bakes closed. Measure headlessly before wiring, and keep it out of BASIC until it bakes identically.

**Half B — MAKE PART.** Press MAKE PART → the builder swaps its document for a fresh empty one → a band replaces the toolbar's normal reading (`MAKING A PART: [name]  [ SAVE PART ]  [ THROW AWAY ]`) → the kid builds with the identical tools, camera, palette and handles → SAVE lands it in the host ship's parts list and returns them with everything as they left it.

It is not a second system, for three reasons that each rest on code that exists: **it is the same editor** (no sub-editor scene, no second input path or camera — `ShipBuilder` swaps `_doc`, every panel already rebuilds from `doc_changed`); **the save is `import_from`**, which already does every hard part including the dissolve-the-instance-root flatten that the `definition-root-is-a-primitive` memory was written about; and **the result is an ordinary definition** placed through `begin_component_placement`, so the SDF, the bake, the tree, the exploded view and the hash learn nothing new. MAKE COMP / MAKE UNIQUE / LINK stay exactly where they are in ADVANCED and DEV.

The one new seam is a **property, not a method**, because the class is at 30/30:

```gdscript
var sub_document: ShipDoc = null: set = _set_sub_document
```

Assigning stashes `_doc`, `_history`, `_selection`, `_isolated` and the bake state and installs a **fresh `ShipHistory`**; assigning `null` restores them. The fresh history is not a nicety — `_replace_doc` leaves `_history` alone, so without it a kid pressing UNDO twice inside MAKE PART walks backwards into their ship and cannot get back. Everything else lives in `harness/builder/ship_make_part.gd` (a `RefCounted` session, the `ShipBakeSession` mould) plus the band.

Rules the flow must obey: SAVE refuses an empty scratch with a real reason (`import_from` returns early on `other.parts.is_empty()`, `:736`); the scratch document starts **however the cold open decides** (§7.2.7) — two different empty-document starts is exactly the overlapping roles the author warned about; THROW AWAY confirms in an in-scene `Control`; the part lives in the host document's `components`, not on disk; and the whole detour is non-destructive until SAVE, which is what makes it safe to put in front of a child.

**Half C — the 3D thumbnail.** Build a throwaway one-instance `ShipDoc`, run `ShipAttach.resolve_all`, feed each `ResolvedShape` to `ShipMeshGen.mesh_for` (so an icon can never disagree with the ship it stands for), render once through a shared offscreen `SubViewport` at `UPDATE_ONCE`, cache on definition id **plus a hash of its record** (MAKE UNIQUE and an inner edit both change a definition without changing its id). This is the same machinery §7.2.4 needs for the primitive cells — build it once, in one class.

**Per view.** DEV unchanged per instruction: it keeps MAKE COMP / MAKE UNIQUE / LINK and gains only the fixes (ESC, the honest DEL, the inner tree rows, the breadcrumb, the thumbnails). ADVANCED puts MAKE PART *beside* MAKE COMP, labelled as the same result without needing a subtree selection; TAKE APART appears here first. MODERATE gets MAKE PART, the MY PARTS shelf, the inner rows and the breadcrumb, with MAKE COMP / MAKE UNIQUE / LINK hidden (already ADVANCED in §3.1.1) — so MAKE PART is the *only* way to author a part and the tree row or a second click the only way into one. BASIC gets MAKE PART as a large cell at the head of the shelf and MY PARTS in the same shelf; **because BASIC has no tree (`ship_ui_mode.gd:56`), its only route in is click-then-click-again and its only route out is the breadcrumb's DONE** — that is why the band cannot be a tree header.

**Steps.** ① ESC leaves isolation (`ship_builder.gd:1905-1911`; update `ship_keymap.gd:896` from DEAD; close F53) — T. ② Honest DEL refusal (`:500-515`) — T. ③ The breadcrumb band (new `ship_isolation_band.gd`) — S; **must be a sibling of `Root`**. ④ Click-again-to-descend — S; must require press+release inside `CLICK_SLOP_PX` and lose to any drag, or select-then-nudge becomes impossible. ⑤ Inner rows in the tree + `_part` → `doc.part_at()` — M. ⑥ The `sub_document` property — M; budget ~25 lines in a file at 1,955/2,000. ⑦ MAKE PART session + band + `import_from` — M. ⑧ The thumbnail renderer — M; lazy and cached or it becomes the automatic heavy work the author already killed. ⑨ TAKE APART — M; **blocked on measuring F37**. ⑩ Real inner add/delete (`add_inner_part` / `remove_inner_part`) — L, **needs its own ADR**; deferred deliberately, ①–⑨ make the feature usable without it.

---

#### 7.2.3 Cross-parent links: joining any two parts, and stretching a tunnel between two fixed ends

**The ask.** "we need to address cros children and cross parent children links. as a player may want to build a tunnel that stretched from one electron to another, which would be child of A likning to child of B, where AB are the tunnel nodes." Two things are bundled: a **link** between two parts that are not parent and child, and a tunnel **part** whose two ends land on two existing parts and stay there.

**What exists today. The attach tree does not prevent a cross-parent link.**

- A joint is keyed over an **unordered pair** and consults the attach tree nowhere (`ship_joint.gd:6-9`, `ship_doc.gd:565`, `ship_joint.gd:130-135`).
- **The bake already honours one.** `ShipSeams._joined_pairs` (`ship_seams.gd:318`) admits every pair whose two ids are both placed; the only test is `if a == b or not xforms.has(a) or not xforms.has(b): return` (`:365`). `_sibling_seams` (`:262`) emits a real seam, frame from `_sibling_frame` (`:412`), flagged `SEAM_SIBLING`. ADR 0034 measured it: "A doorway between two fused siblings plans and bores (doors=1, pending=0)".
- The validator never rejects one — `CODE_JOINT_NOT_OVERLAPPING` is a `_warn` and only fires when the solids do not meet (`ship_validate.gd:394-437`).
- **The gate is one UI-facing function.** `ShipSeams.pairs_within` (`:549`) is the only thing LINK calls. It yields tree pairs (`:559-572`), then a special case at `:583-585`: `if out.is_empty() and members.size() == 2: out.append(members)`. **So selecting exactly two cross-parent parts and pressing LINK already works today, end to end, including the bake.** Past two parts it stops — `_stand_apart` (`:599-613`) requires both parts be parentless or both inner to one definition.
- **Nothing on screen says a link exists**, and LINK's refusal is wrong about its own rule: `part_tree.gd:711-716` prints "SELECT A PART AND WHAT IT STANDS ON", which describes only the tree-pair branch and tells the player the opposite of what the branch above it does.
- **A part's geometry genuinely has one host** (SPEC §3, CONTRACT; `ship_part.gd:44-86`). The templates work around it by *building* the far end: `ship_templates.gd:364-391` makes the tunnel a child of node A and the room a child of the tunnel. There is no path that runs a tunnel to a room that already exists.
- The category needed for position already exists: ADR 0033 made a parentless part legal and placed by its own `absolute` (`ship_attach.gd:1134-1135`), and `_can_place` (`:1103-1116`) plus the fixpoint loop (`:717-736`) already wait on dependencies and degrade rather than hang on a cycle.
- `ShipSeams._crossing` (`:450`) already answers exactly "where does the segment between two parts leave A's surface and enter B's" — the whole geometric primitive a stretched tunnel needs, already deterministic.
- A tunnel-to-room joint already auto-hatches: `default_link_for` (`:518`) returns `MODE_HATCHED` when one end's role is `ROLE_HALLWAY` (ADR 0027).

**The design.** The capability is there; nothing announces it, its refusal describes the opposite rule, it silently stops at three selected parts, and — the real gap — **there is no part whose geometry spans two ends.**

**Increment 1 — JOIN, the verb.** No contract change, visible the next morning. (a) Add `ShipSeams.pairs_between(doc, a, b)` — two explicit ids, unconditional, routed through `within_one_instance` the way `_set_link` already routes (`ship_builder.gd:430-440`) so a pair inside one component still writes into the definition (ADR 0025). **Do not widen `_stand_apart`** — relaxing it would make an 8-part selection write 28 joints. (b) JOIN is a **two-click verb**, not a selection verb: press J, "PICK THE FIRST PART", "PICK THE SECOND", the second click runs the existing contact test (`part_tree.gd:766 _meet_for_hatch`) and writes the joint. This is the right shape because it is the same gesture BRIDGE uses — the player learns one thing, not two. (c) **An explicit JOIN defaults to an opening, not a wall.** `default_link_for` returns `MODE_WALL` for room-to-room, correct for an automatic placement and wrong for a link the player deliberately asked for; add `default_link_for_explicit()` beside it. (d) **Draw the link** — a ring at each `SEAM_SIBLING` frame `ShipSeams.seams()` already returns, plus a dim line between centres. Today the only way to learn a link exists is to bake; this is the highest-value line of the increment. (e) Fix the refusal string.

**Increment 2 — BRIDGE, the noun.** A new part kind `KIND_SPAN`, additive, with `span_a`/`span_b` (part ids) and `span_a_dir`/`span_b_dir` (`Vector2`, sentinel = derive). `parent` stays `""` — a bridge is an **anchored** part, the category ADR 0033 created. Placement, computed in `ShipAttach`:

1. `Pa` = where the segment between the ends' ship-space origins **leaves** A's surface; `Pb` = where it **enters** B's — both from `_crossing`, promoted to a public `ShipSeams.crossing()`. Reusing that exact walk is the point: the bridge's ends and the seam plane the bake later cuts derive from **one** function and cannot drift.
2. Basis = `ShipAttach.mount_frame((Pb - Pa).normalized())` composed with the same `MOUNT_ALIGN_DEG` term every other part uses (`:76, 245-248`), so the tube's Y-major geometry stands along the span.
3. Origin = the midpoint. `scale.y` solved so the tube's length is `|Pb - Pa|` plus `cfg.attach_embed_m` sunk into each end — the same embed `default_offset` targets (`:344`).
4. `_can_place` gains one branch: a span waits until both ends are placed. The fixpoint loop's `blocked.size() == pending.size()` break already handles a dangling end or a cycle.
5. `role = ROLE_HALLWAY`, so `default_link_for` auto-hatches both ends with no special case.

Two ordinary sibling joints are written at creation; `_sibling_seams` emits both with **zero new code**, because by construction the bridge overlaps each end along the line of centres — the payoff for building it out of `_crossing`.

**Determinism:** `scale.y` is derived, never stored, so the hash consumes `(family, params, bore, span_a, span_b)` and not the solved length. New fields are omitted from `to_dict` when unset — the `seam_style` precedent (`ship_joint.gd:149-153`) — so no existing document's canonical form moves. No ruleset bump; the ADR must say so and the selfcheck must show the hash unchanged, exactly as ADR 0034 did.

**The honest limitation, named up front:** the line of centres is the wrong axis for two long spars lying side by side. `_sibling_frame`'s own docstring already admits this for seams (`:408-410`). `span_*_dir` is the escape: when set, the end anchor comes from `ShipAttach.anchor_for` with those angles — the existing yaw/pitch machinery, unchanged.

**Increment 3 — the stretch gesture.** Click A, click B, a ghost tube draws, wheel sets the bore, click commits; then drag either end to write `span_*_dir`. Because the length is solved every resolve pass rather than stored, **moving A or B restretches the tunnel for free** — which is literally what the author described. Cost is two `_crossing` walks per bridge per resolve, the same order as one sibling seam.

**Per view.** BASIC: one button, **CONNECT** — pick two parts and the builder decides (solids already meet → open a door; they do not → run a tunnel). No mode words, no seam styles, no bore field; a child never learns the word "joint". MODERATE: JOIN and BRIDGE as two buttons, a bore slider, the four-state link cycle with each state named in the hint bar rather than blind. ADVANCED: adds seam style (the two axes of ADR 0013), hatch family, door style, and end dragging. DEV: unchanged — `pairs_within` keeps its exact current semantics, so today's multi-select LINK cycle behaves identically; DEV gains only `pairs_between` behind JOIN and the drawn seam ring.

**Steps.** ① `pairs_between` + test — S, pure addition. ② Fix LINK's refusal string — T. ③ Draw every sibling seam — S. ④ JOIN as a two-click verb + `default_link_for_explicit()` — M; **the verb's state must live in its own `RefCounted`** (the `ShipReseat`/`ShipModal` mould), not as new public methods. ⑤ Promote `_crossing` to public `crossing()` + test — T, report as an addendum. ⑥ **ADR 0049** (or next free) — the kind, the six-step rule, the derived length and the unmoved hash, the delete semantics, the limitation. ⑦ `KIND_SPAN` in the data model + round-trip and hash-stability tests — S. ⑧ The solver + `_can_place` — M, **highest risk**: it is inside the transform pass every consumer walks, so a mistake shows up as parts vanishing rather than as an error; write the cycle test first; resolve the span's shape lazily in the transform pass rather than pre-scaling it in `resolve_shapes`. ⑨ Prove the bake needs no change on a two-electron span — S; if a change *is* needed, the solver is wrong, not the seam pass. ⑩ The BRIDGE tool — M. ⑪ Tier it — S; panels lane.

---

#### 7.2.4 The part palette in 3D, and alignment inference

**The ask.** (1) "we should be building the 3d parts in the part palette instead of simple 2d placeholders". (2) "alignment signals that show when parts are aligned, or similar, or symetrical, with center snapping and such."

**What exists today.**

- **Confirmed 2D.** `part_palette.gd:639` calls `draw_glyph(...)`; the glyph (`:666-690`) is a switch on the base primitive drawing `draw_arc`, `_draw_cone`, `_draw_capsule`, `_draw_cylinder` at `GLYPH_WIDTH = 1.0` in one flat tint. No mesh, no camera, no texture in the file.
- **The glyph reads only `base`** (`:744-749`) — identical for every manufacturer and every param value. This matters more than it sounds: ADR 0005 retired `cone_nose` and `capsule_tank` into `cylinder_spar` + `end_radius`/`end_round`, so a tube, a frustum, a cone and a capsule are **all one palette cell, all drawn as a cylinder**.
- 40 px cells with an 8 px inset = a 24×24 drawing; `PAGE_SIZE = 12` over exactly **four** families, so eight cells are permanently blank and the pager can never move (already at `ux.md:693`).
- `draw_glyph` is `static` and public because `start_dialog.gd:471` uses it. Any thumbnail work has two consumers.
- **Everything needed is cheap and exists:** `ShapeGen.default_params` / `ShapeGen.resolve` need no document; `ShipMeshGen.mesh_for` is cached on a scale-free signature.
- **No lights are needed.** The part material's lambert term is computed against a fixed world direction (`ship_scene_builder.gd:88`; F7 explains why the engine lighting path renders these black here). A thumbnail viewport needs a `Camera3D` and `MeshInstance3D`s and nothing else.
- **The quantizer is free.** `palette_post.gdshader` runs on a full-rect `ColorRect` over the whole app viewport; a nested `SubViewport` composites first and is quantized with everything else.
- **Honest limit the author has not been told:** `ShipMeshGen` ignores twist, ribs and scallops by explicit design (`ship_mesh_gen.gd:48-51`), and kessler vs voss `box_hull` differ almost entirely in `rib_count`/`rib_amp`. A thumbnail built on the preview mesh will render **kessler and voss identically**. It will correctly show taper, `end_radius`, `end_round`, `round` and true proportion — which is where `cylinder_spar`'s whole range lives.
- **Alignment: there is nothing.** `grep -i align` over `harness/` and `core/` returns only `HORIZONTAL_ALIGNMENT`, a `BoxContainer.alignment`, and prose.
- **Correction to §3.4 S5**, which says `snap_preview()` "is currently consumed only as a ghost tint". That is wrong: `ship_view3d.gd:1657-1659` calls `_scene.show_snap_targets(...)` on every ghost update and `ship_scene_builder.gd:480-500` draws a 3D cross per candidate, the live one `SNAP_LIVE_FACTOR` larger. **The dots already ship.** What is missing is the *name* and the leader line — so S5 is much smaller than budgeted, and alignment work must not re-implement that renderer.
- Everything the inference needs is already computed: `ShipAttach.resolve_all` returns ship-space transforms **including derived symmetry twins** keyed `<source>~m` (`:757`); `preview_transform()` and `ghost_shape()` give the ghost; `ShipSymmetry.planes_of` the plane. The screen-space tolerance exists too — `_push_handle_scale()` computes metres-per-inner-viewport-pixel and its docstring says "Reads this view's own SubViewport, never the window".
- **Budgets:** `ship_scene_builder.gd` is 1,463 lines with **exactly 30** non-static publics — it can take no new public method. `ship_view3d.gd` is 1,909/2,000 with 27/30. `part_palette.gd` 794 lines, 1 public. `ship_handles.gd` 642 lines, 25 statics, 0 instance publics — the mould for a new static-only helper.
- Colour roles are frozen at nine (`API_CONTRACT_UI.md:70-73`); O10 already ruled per-axis colour out. Guides get no new role.

**The design — Part A: one orthographic atlas, not a viewport per cell.** `harness/builder/ship_part_thumbs.gd`, `class_name ShipPartThumbs extends SubViewport`. **One** SubViewport for the whole palette: one `Camera3D` at `PROJECTION_ORTHOGONAL`, one `MeshInstance3D` per slot on a flat world grid. The trick is the orthographic projection — parallel rays mean every slot is seen from exactly the same direction, so a grid of parts under one camera gives N identical three-quarter views with one render pass and zero parallax. Size is `columns * ShipTheme.pxf(CELL_SIZE)` — 160×120 at the shipped 4×3 grid; it reads `ShipTheme.pxf` and never `DisplayServer`. Each cell samples its own region: `_on_cell_draw` changes from `draw_glyph(...)` to `cell.draw_texture_rect_region(...)`, guarded by a not-ready test that **falls through to the existing `draw_glyph`**. That is the entire palette diff — about six lines — and `draw_glyph` and all five helpers stay, keeping `start_dialog.gd:471` compiling and keeping a live fallback for headless tools.

Cheapness is `render_target_update_mode = UPDATE_ONCE`, re-armed by a dirty flag on exactly five events (page change, manufacturer change for a visible family, `palette_changed`, `doc.components` change, ui_scale change) — **not** on `doc_changed` and not on `selection_changed`.

**Shared scale, not per-cell fit.** One world scale per page from the largest resolved bbox, with a floor so nothing falls under ~45% of its cell. `cylinder_spar` (0.5 × 1.5) then genuinely reads long and thin beside a unit `box_hull`, and `torus_ring` (4.0 across) genuinely reads as the big one. This turns the palette into a size comparison for free — the same read the author wants from SIZE M.

**The red-out survives and improves.** The unaffordable tint moves *into* the atlas via a per-slot `material_override`, so the **part** is red rather than a red badge over it. No low-alpha overlay — the 16-entry quantizer turns transparency into noise.

The player-made part uses the same atlas: reserve the last K slots, feed them `{shape, xform}` pairs from `resolve_shapes` + `resolve_all`, recentre on the common AABB. Then the component `ItemList` becomes a second icon grid, and `part_palette.gd:181-190`'s docstring is marked `RETIRED(<date>): a component has no glyph -> a component has a render (ShipPartThumbs)`.

**Part B: alignment inference.** Taken from SketchUp: an inference is **named in words**, a **dashed line** runs from the reference, and **dwell locks** it. Taken from Figma: guides exist **only during a drag**, an **equals-pip** marks two spans equal, the **measured number** is printed, and the threshold is **pixel-space**. Not taken: SketchUp's axis colours (contract) and Figma's show-everything (a 3D orbit view with eleven live handles cannot afford it).

`harness/builder/ship_inference.gd`, static only, no Node, no viewport — the `ShipHandles` mould and the same shape as `ShipHintText`: author and **test** the table before a pixel moves. One entry point, roughly `detect(doc, transforms, ghost_xform, ghost_shape, plane, m_per_px, prev) -> Array[Dictionary]`, each finding `{kind, target_id, locus_a, locus_b, label, snaps, strength}`. It takes `transforms` so it never pays for a second attach pass, and `m_per_px` so every tolerance is a screen tolerance.

Conditions, in priority order: **1 CENTRED** (on the symmetry plane or a principal axis through the origin — Spore's `SnapToCenterOfEditor`, and on a ship the most useful one); **2 IN LINE** (shares an X, Y or Z with another origin); **3 MIRRORS** (the reflection of a sibling across the plane, same parent, with equals-pips at the half-spans); **4 SAME SIZE**; **5 RING OF N** (yaw is a whole multiple of 360/N of the siblings on that parent — the ship-specific analogue of equal spacing, and on a curved parent the only spacing rule that means anything); **6 FACING**. "Centred on a parent" is deliberately absent — that is `SnapTargets`' `center`/`pole`/`face`, already computed and already drawn; it needs a name, not an engine.

**1, 2 and 3 snap; 4, 5 and 6 draw only,** and the split falls straight out of the attach model: a placed part's degrees of freedom are yaw, pitch and offset on a curved surface, not XYZ, so a snap is committable only if it is expressible as a change in those three. Condition 4 would have to change a **size**, so SAME SIZE snaps during a morph/scale drag instead — which is finally where `snap_scale` gets a consumer.

Lines are 3D (one new `ImmediateMesh` sibling of `_com_cross`, through `_line_material`, so a guide is correctly occluded by the hull), with dash lengths derived from `m_per_px` so the dash reads constant at any zoom. Text and pips are 2D in the `ViewOverlay` `Control` **inside** the inner SubViewport (`ship_view3d.gd:1258-1264`) — the same badge surface §3.2 S5 specifies, shared rather than duplicated. Colour is `accent` (satisfied and snapping) / `text_dim` (informing only); `selection` stays reserved for the part.

**How it stays quiet — five rules:** screen-space tolerance (a world tolerance is hyperactive zoomed out and dead zoomed in); **hysteresis** (acquire at T, release at 1.6T — the single biggest anti-strobe lever); **dwell to appear** (two consecutive motion events, ~80 ms, so conditions crossed mid-sweep never render); **latch to disappear** (~120 ms, so a hand wobble does not blink it); **at most two at once**, one primary and one secondary of a different kind, only during a drag; and a **candidate budget** (parts within ~six ghost-diagonals, capped at twelve, so a sixty-part ship does not run 360 tests per motion event).

**Dwell-lock instead of a modifier**, because there is no free modifier: SHIFT is `DragMode.HORIZONTAL` (pinned by `API_CONTRACT_SPORE` §8), CTRL is `VERTICAL`, ALT is spent on the snap bypass. Hold still on an acquired inference for ~350 ms and it latches until you move 3T away. That is SketchUp's own "encouragement" mechanic, needs no key, and is the only form that survives the diegetic touch path.

**Per view.** Thumbnails are identical in BASIC / MODERATE / ADVANCED (a picture is a better read of the same information at every level and removes no control); the 2D glyph stays alive everywhere as the not-ready/headless fallback. DEV is open question **Q4**. Alignment tiers **by condition**: BASIC gets 1 (CENTRED) and 3 (MIRRORS) with snap on — exactly the two a child reaches for and the two the author named first; MODERATE adds 2 and 5; ADVANCED adds 4 and 6 plus the measured number and an off / draw-only / draw-and-snap chip; DEV gets all six, default on. **The engine itself is mode-blind** — `detect()` always evaluates everything and the *consumer* filters. One computation, four filters.

**Steps.** T1 `ShipPartThumbs` with no consumer + a headless test — M. T2 swap the palette cell (≈6 lines) + mount the node once above the panels — S, **panels lane, bundle with T4**. T3 shared scale + the refused material — S. T4 component thumbnails; the `ItemList` becomes a grid; mark the docstring RETIRED — M. A1 **name the snap targets that already draw** (label + dashed leader in `ViewOverlay`; hide the text when the id matches `^p_\d+$`; never rename an id) and correct `ux.md:465` in the same commit — S. A2 `ShipInference` + its whole test table, no renderer — M. A3 draw the guides — M; **`ShipSceneBuilder` is at exactly 30/30, so the guide node must be owned by `ShipView3D`**. A4 snap 1–3 + dwell-lock — M; **must follow old step 8**. A5 mode-filter + the chip — S. A6 SAME SIZE on the morph drag — S; fold into the `snap_scale` work so there is one quantizer, not two.

---

#### 7.2.5 FLY MODE — conserved momentum, CLAY, the void, and a flashlight that cannot be a light

**The ask.** Five separable deliverables: a 6-DOF camera with conserved linear **and** angular momentum and light damping; a CLAY render type (flat blue clay, wire edges); a deep-void environment; a camera-mounted flashlight; and Minecraft-creative enterability.

**What exists today.**

- **Nothing of fly was built, on purpose.** §5 step 19 is marked **AUTHOR'S GO REQUIRED** and O2 says "Do not proceed without your word."
- **The camera is an orbit rig with no roll and no free position.** `orbit_camera.gd:34-37` is the entire state (`focus`, `distance`, `yaw_deg`, `pitch_deg`); `_rig_basis()` (`:176-178`) welds Y-up in and cannot represent roll. `:24-25`, `:41`, `:106-107`, `:135-137` record the axis-snap presets and `pan_by()` as RETIRED(2026-08-31) citing `SPORE_CLONE_SPEC.md:245` item 17 and "four independent research passes". **Fly is strictly more camera freedom than either thing that was deleted for being too free — ADR, not a diff.**
- **A `SpotLight3D` would light nothing.** `part_faceted.gdshader:2` is `render_mode unshaded, cull_disabled, specular_disabled;` and the header says why: shaded materials render **black** in this SubViewport (F7 proves it — flipping to UNSHADED took a part from **0 px to 115,582 px**). The vestigial `DirectionalLight3D "KeyLight"` (`ship_view3d.gd:309-315`) contributes exactly nothing.
- **There is no blue, and everything quantizes to 16 colours.** `data/palette.json` "base" is eleven cool teals, four warm ambers (indices 3/7/11/14) and one red; `palette_post.gdshader` quantizes the whole app viewport. The mechanism that *can* deliver blue exists: `ShipTheme.set_alert()` (`ship_theme.gd:384-397`) swaps all sixteen entries wholesale.
- The shader already exposes `ramp[8]`/`ramp_size`, `light_dir`, `ambient`, `depth_strength`, `rim_strength`, `lambert_strength` — FRESNEL is built purely by moving those numbers, so CLAY is the same trick with no new shader file. Wire edges are already a per-part node whose visibility test is a `!=` (`ship_scene_builder.gd:1160-1163`), so a new mode gets wire free. `DisplayMode` is **append-safe and says so** (`:65-72`).
- The environment is one function (`ship_view3d.gd:1727-1740`). **The floor grid has no off switch** — a repo grep finds no assignment to `_grid.visible` anywhere.
- **There is already a fixed-timestep tick in the right class** — `ship_view3d.gd:1552 _physics_process`, at Godot's default 60 Hz (`project.godot` sets no override). And the input seam exists: `:795-797`'s `if _exploded or _baked: ...; return` is the first thing `_gui_input` does.
- **Two camera consumers are load-bearing:** `_push_depth_range()` (`:564-574`) feeds the part shader's distance cue and `_push_handle_scale()` (`:581-595`) the gizmo's metres-per-pixel; both hang off `camera_moved`.
- **Polled input is dead in the shipping path.** `diegetic_host.gd:110-114` forwards events via `push_input()`, which does not set the `Input` singleton; `:120-125` eats ESCAPE to unfocus the device. So key state must come from `InputEventKey.pressed`, and ESC cannot be fly's only exit.
- MSAA is off and the inner buffer starts at 640×480 — wire edges will stair-step, and with DITHER on they will crawl.
- §3.5's own camera lines have two holes: `ux.md:489` maps Q/E to rise and fall, but `E` is assemble/explode and `:496` separately proposes `Q` as the back-out; and `:490` promises an ENTER exit that "keeps the view", which the orbit rig **cannot** do if the player is rolled.

**The design.** One new pure-maths class, one appended display mode, one palette variant, three shader uniforms, and a branch at the top of `_gui_input`. Nothing in `core/`; nothing frozen renamed; `ship_builder.gd` gains one button and **zero** public methods.

**The integrator.** `ShipFlyCamera extends Node3D` owning its own `Camera3D`. It cannot be a mode of `OrbitCamera` — four scalars with Y-up welded in. State: `p`, `v` (world), `q`, `w` (body frame). Semi-implicit Euler in `_physics_process`, with **exponential** damping so the decay is exactly frame-rate independent and has a statable half-life:

```
a_body = clamp(thrust,-1,1) * THRUST_A * boost
v += (q * a_body) * dt ;  v *= exp(-LIN_DAMP * dt)
if brake: v = move_toward_zero(v, BRAKE_A * dt)
p += v * dt
w += clamp(torque,-1,1) * ANG_A * boost * dt ;  w *= exp(-ANG_DAMP * dt)
if brake: w = move_toward_zero(w, BRAKE_ANG * dt)
if w.length() > 1e-9: q = (q * Quaternion(w.normalized(), w.length()*dt)).normalized()
```

| const | value | why |
|---|---:|---|
| `THRUST_A` | 12.0 m/s² | ~1.2 g; a 20 m hull crossed in ~2 s from rest |
| `LIN_DAMP` | 0.25 s⁻¹ | half-life **2.77 s** — "very slight". Terminal speed is `THRUST_A/LIN_DAMP` = **48 m/s**, self-limiting |
| `ANG_A` | 90 °/s² | a quarter turn from rest in ~1.4 s |
| `ANG_DAMP` | 0.35 s⁻¹ | half-life 1.98 s; a flick leaves a visible slow drift, which **is** the floating feeling |
| `MAX_SPIN` | 100 °/s | the only place conservation is overridden: past ~120 °/s the quantizer strobes |
| `BRAKE_A` / `BRAKE_ANG` | 24 m/s² / 240 °/s² | full stop from terminal in ~2 s |
| `BOOST` / `PRECISION` | ×3.0 / ×0.3 | SHIFT / ALT |

`q.normalized()` every tick is mandatory, not hygiene — Godot's `real_t` is 32-bit and an un-renormalised quaternion shears the basis within a minute of continuous spin. Angular momentum is carried in the body frame with an implicitly **isotropic** inertia tensor, so there is no Dzhanibekov precession: free-body tumbling is physically gorgeous and, on a camera, is motion sickness.

**Controls:** W/S thrust, A/D strafe, SPACE/Z rise-fall, **Q/E roll** (contradicting `ux.md:489`, which collides with `E` twice), arrows = pitch/yaw torque (the no-mouse and diegetic path), RMB-drag = torque at 2.5 °/s² per px, SHIFT ×3 / ALT ×0.3, **X = BRAKE** (kills linear and angular — the single most important key), F = leave and FIT, **V or ESC = leave, restoring the exact pre-fly pose**, ENTER = leave keeping the view. `V` is the guaranteed non-ESC exit and is the same key that entered. All key state from `InputEventKey`, cleared on exit and on `release_drag()` (the stuck-key guard). **No `MOUSE_MODE_CAPTURED`, no `warp_mouse`, no `DisplayServer`** — the honest cost is that a drag reaching the view edge stops, which is exactly why the arrow-key torque pair is not optional.

**CLAY:** (a) `data/palette.json` gains `"variants": {"clay": [...16...]}`, a deep-void blue ramp with **indices 3/7/11/14 left byte-identical** — not an invention, it is the rule the alert palettes already follow ("the warm ramp is deliberately identical in every alert palette so the selected part stays amber"), so selected parts stay amber against blue clay for free. (b) `ShipTheme.set_palette_variant()` / `clear_palette_variant()` beside `set_alert()`, with **one precedence rule in the docstring: an active budget alert always beats a variant.** A budget violation must never be hidden by a render mode. (c) a **three**-band ramp — clay is matte; a fourth band reads as polish. (d) `DisplayMode.CLAY` appended at 6, one dropdown entry, and a materials table row: `ramp_size 3`, `ambient 0.45`, `depth_strength 0.10`, `rim_strength 0.15` (a Fresnel rim is wet plastic, not clay). (e) DITHER forced off while CLAY is active.

**The void:** background = the variant's index-0 colour exactly, so the quantizer is a no-op on it; ambient 0 (which changes nothing visible, since everything is unshaded — set only so the code does not imply a lighting model it does not have); `_grid.visible = false` (new), cage and CoM cross hidden, all restored on exit. **No starfield** — at 16 colours it quantizes to single-pixel noise indistinguishable from dither.

**The torch is a shader term.** Three uniforms defaulting to off (`torch_pos`, `torch_dir`, `torch_strength = 0.0`, plus cone and range), and in `fragment()`, after the depth cue and **before** the rim, a cone × inverse-square × lambert term pushed **into `t`, never added as a colour** — the same rule the rim follows and the whole reason the quantizer is a no-op on parts. Break it and you get the mint-triangle failures the shader header documents. `world_pos` and `world_n` are already computed. Fed by `ShipSceneBuilder.set_torch(pos, dir, strength)` iterating the `_solid_materials` cache the way `_apply_ramp` does, pushed each tick exactly as `set_depth_range` is.

**Entering and leaving:** a `FLY` toolbar button named `"FLY"` so `SHOWN_FROM` can gate it. Refused during a placement, a handle drag, the modal or a bake; **allowed in the exploded and baked views**, where `_handle_explode_input` already keeps the camera's verbs live — flying around a finished hull is the best thing this mode does, for free. Picking off (one branch above `:795`); the gizmo **hidden, not cleared** (clearing would fire `selection_changed` for nothing). Skip `_push_handle_scale()` while flying and run it once on exit; **keep `_push_depth_range()` running** with `dist` computed from the fly position to the scene AABB centre, or the part shader's distance cue freezes and will be diagnosed as a shading bug. On ENTER-to-keep-the-view, decompose to yaw/pitch and **discard roll** — ease the untwist over 250 ms so it reads as "levelling off", and say so in the bar.

**Per view.** DEV: one added `FLY` button, one added dropdown entry, nothing moves. ADVANCED: identical (`RenderTypeOption` is already ADVANCED). MODERATE: full Newtonian fly, but there is no render-type dropdown at this rung, so fly **forces CLAY** on entry and restores the previous mode on exit — also the more cinematic default. BASIC: `ux.md:237` says no fly below SHAPE and **I am proposing against it** — creative flight is the most kid-legible item in the whole message, and "the little kids' mode cannot fly" is the version a child would resent. BASIC flies with the training wheels on: same class, three constants from the tier table (`LIN_DAMP 0.80`, `ANG_DAMP 2.50`, RMB = direct look rather than torque). That concedes §3.1 rule 2 slightly in letter while honouring it in spirit, and the concession should be visible in review rather than buried.

**Steps.** ① **ADR 0049** — narrow: the clone target governs the build gesture grammar, not the camera, because the brief's audience is a child on a diegetic screen and Spore had neither; explicitly does **not** reopen `pan_by()` or the axis-snap presets; marks `orbit_camera.gd:7-11` RETIRED in place. ② CLAY, no camera work at all — S. ③ The void — T. ④ The torch, defaults off, verified by a headless capture diff — S. ⑤ The integrator as a **pure static** `step(state, input, dt, tune)` with gdUnit4 cases: conservation (|v| and |w| constant to 1e-5 over 10,000 ticks at zero damping), exact exponential half-life, brake never overshooting zero, quaternion norm within 1e-6 after 60 s of spin — M, nothing calls it yet. ⑥ Wire it in — M. ⑦ ENTER-to-keep-the-view with the eased untwist — S. ⑧ Tier it + `ShipKeymap` rows for all thirteen bindings at context FLY + **corrected hint strings** replacing `ux.md:383`, which names no brake, no roll and no non-ESC exit and describes right-click as look — S. ⑨ Capture CLAY and one fly pose per rung in `ship_check_views.gd` — S.

Steps ②–④ touch no camera and **could ship before the ADR is signed**, if the author wants to see blue clay before deciding about flying.

---

#### 7.2.6 The UI lock-up and hot swapping

**The ask.** "the basic meshes should be quite fast to stretch or resize, rotate etc, while mesh cutting updates happen in background … currently something with meshes locks up the ui and doesnt fully let me keep paning etc etc when its supposed to be hot swappable."

**What exists today. The diagnosis in one line: there is no background in this program.**

- `grep -rn "WorkerThreadPool|Thread.new" core/ harness/ tools/` returns **zero hits**. Every millisecond of geometry work runs on the main thread. "Background" in ADR 0042 means `await get_tree().process_frame` between engine passes, nothing more.
- **The bake's only yields are between CSG passes, and on the author's ship there was one of them.** `ship_csg_bake.gd` awaits at `:154`, `:207`, `:252`, `:284`. This morning's SHIFT+F state records `bored: []`, `door_failed: []`, `split_rooms: 1`, `cut_back_rooms: 0`, `pieces: 14` — no doors, no cut-back, so `:207`, `:252` and `:284` were all skipped. Everything from `:155` to the return at `:351` ran as **one uninterrupted synchronous block**. That block is the **18,222 ms** the state reports.
- **The progress bar cannot move through it.** A frame is painted only at an `await`; the last frame drawn shows `ROOM SHELLS 12%`. "PIECES", "DOORS", "READING" and "SURFACES" are all set with no frame between them. The player sees 12% and then a dead application for ~18 s.
- The two hot spots are `_read_combiner` (`:297/:314`) and `_grouped` (`:333`), both O(faces × members) with an SDF evaluation per test. `_grouped`'s inner loop tests every vertex of every face against every member's body and room field — 28 evaluations per vertex on a room of 14 — and re-tests a shared vertex once per incident face. The class's own docstring records "58 read-backs a bake … and the n-gon merge in each read-back was 7.6 s of the 19".
- **The dicing's tail is worse, and it runs exactly when the author tries to pan.** ADR 0042 claims the dicing "runs off-screen, and it never blocks a frame." Its *engine* passes do yield; its **read-out does not** — `_slice`'s READING CELLS loop (`:612-621`) and `bake_extras`' per-cell `_grouped` + `_feature_wire` (`:458-490`) both run with no await. Recorded cost for a carbon: 14 pieces → **713 cells**, engine cut ~4 s (yielding), read-back **9.6 s** (not yielding). Roughly ten seconds of frozen frames land **after** the ship has appeared — precisely the "hot swap" moment.
- **The edit path is already fast, and the complaint does not match it.** A drag runs `_recompute_preview()` — one attach solve — and nothing else; `_refresh_scene_cache()` carries the comment "never per drag frame" and the code agrees. A commit costs three bbox passes, one `to_dict()` and one `resolve_shapes` + `resolve_all`, all O(parts). On 14 parts that is single-digit milliseconds. **Stretching and rotating a primitive is not what is locking up.**
- **What is actually locking up the session is that the author is in the baked view the whole time.** `_resolve_on_load()` is called from `found_document`, the prebuild path and OPEN, and ends in `_baked = true`. In the baked view every event routes to `_handle_explode_input`, `set_exploded(true, covered)` hides every primitive the bake covers, and `_refresh_handles()` frees the gizmo because `_is_covered(ids[0])` is true. So an edit runs, commits, re-resolves, re-meshes hidden nodes — and **nothing on screen changes until UPDATE MESHES is pressed and the 18 s is paid.** That is the whole of "it is supposed to be hot swappable", and it is not a frame-budget problem at all. Step 3's `EDIT` button exists, but the app still *lands* in the baked view.
- A smaller per-camera-frame cost: `camera_moved` → `_push_depth_range` walks every visual for `scene_aabb()` and then `_push_handle_scale`, and past `HANDLE_PX_TOLERANCE` (5%) rebuilds the whole gizmo — a fresh `ImmediateMesh`, 3 rings × 32 segments × 6 tube sides plus 7 arrows and a collar, appended a vertex at a time and drawn twice: roughly **10k `surface_add_vertex` calls**. Unmeasured; it should be on the meter.
- One more fully synchronous freeze behind DEV's BAKE REPORT (`ship_builder.gd:1666-1694`), whose docstring says "Phase 1 ships are small enough that this is a pause, not a hang." The 18,222 ms measurement **retires that sentence** (AGENTS §10a).
- **Nothing here is contract-frozen.** `ShipCsgBake`, `ShipBakeSession` and `ShipExplodeView` appear in neither API_CONTRACT file.

**The design — four layers, each shippable alone.**

**Layer A — stop editing in a view that cannot show edits** (the largest felt win, nearly free). A ship that resolves on load lands in **PREVIEW with the bake kept in hand**, not in BAKED. `_resolve_on_load` still bakes (the author explicitly wants bake-on-LOAD, ADR 0028), but `_show_bake` learns a `show: bool`: the report is stored, the button turns from UPDATE MESHES to **SHOW BAKED**, and the primitives stay on screen with live handles. The weaker fallback is one line in `_commit`: if `_baked`, call `_set_baked(false)` first, so the first edit drops you back into the editable view by itself.

**Layer B — a frame budget, and every long loop breathes into it.** `harness/builder/ship_frame_budget.gd` (`RefCounted`; it touches the SceneTree so it cannot live in `core/`), about forty lines:

```gdscript
var b := ShipFrameBudget.new(host, 25, gen)   # host, ms/frame, generation callable
...one item of work...
await b.breathe()          # a plain value under budget; process_frame over it
if b.superseded(): return {}
```

`breathe()` returns a plain value when under budget (GDScript's `await` on a non-signal continues in the same frame, so the fast path costs one `Time.get_ticks_msec()`). Six call sites, all already coroutines, all with unchanged signatures: `bake()`'s READING (`:296-318`) and SURFACES (`:330-336`) loops and its per-room split (`:178-235`); `_slice`'s READING CELLS (`:614-620`); `bake_extras`' per-cell loop (`:469-489`); and `ShipExplodeView._build` (`:349`), which should reuse the existing `_process` drip (`:357-370`) instead of its `while` loop. **Move each `_tick` into its loop** so the bar reports "READING 6/14" and actually repaints.

**Layer C — a superseded bake dies at its next breath.** `ShipBakeSession` already throws away a stale result — *after paying for all of it*. Give it a monotonic generation counter, hand `ShipCsgBake` the read-only callable, and `b.superseded()` bails within one frame. Then UPDATE MESHES becomes **CANCEL** while busy: a cancellable eighteen seconds is a different experience from an uncancellable one.

**Layer D — cut the work, not just spread it.** **D1** (safe, do it first): memoize `_on_any` **per vertex** in `_grouped` and in `MeshSeamSplit._classify` — each vertex is re-classified once per incident face, a 3–5× waste for nothing; identical output, assert it. **D2** (needs measurement): a cell's faces are either inherited from its parent piece's surface or new faces on a slab-box plane — classify the piece once and inherit, testing only the six slab planes; could take the ~713 `_grouped` calls down an order of magnitude. **D3** (needs the author): the cells are only ever drawn by EXPLODE and ROOMS: WHOLE; with Layer B the dicing genuinely runs behind the frame for the first time, so ADR 0042's promise finally becomes true and I would keep it.

**What must stay instant, and how we keep it:** nothing in A–D touches `_sync_part`, `ShipMeshGen` or `ShipPlacement`. Add a gdUnit4 test asserting `ShipMeshGen.mesh_for` is a cache hit on a repeated signature, and put a `Time.get_ticks_usec()` counter behind the DEV overlay for the per-camera-frame cost.

**How a deferred result swaps in without the screen jumping:** ADR 0042's argument holds (a piece and its cells stand in the same place), with two additions. `ShipExplodeView._build` calls `clear()` — which `queue_free`s at end of frame — and then adds replacements immediately, so for one frame **both sets are in the tree and z-fight**; build into a detached `Node3D` and reparent atomically. And cache the `ShipSdf` on the session so `_show_bake` does not rebuild it on the extras landing.

**What this costs, honestly:** time-slicing makes the bake **slower in wall-clock** — every breath costs a frame, and under vsync a frame can be 16.6 ms. At a 25 ms budget an 18 s bake becomes roughly **25–30 s**: responsive throughout, cancellable, with a bar that moves, but longer. Layer D buys it back. Ship A, then B+C, then D1, measuring at each step.

**Deliberately not chosen: real threads.** `ShipMeshBake.plan`, `PolyMesh.from_polygons`, `MeshMerge.merge`, `MeshSeamSplit.split`, `_grouped` and `_feature_wire` are all pure `core/` code over plain data with no tree access — textbook `WorkerThreadPool` candidates, and the per-cell work is embarrassingly parallel (9.6 s → roughly 1.5 s here). It would be the first thread in the repository, needs an ADR and a determinism proof. Named, not chosen (Q12).

**Per view.** Layers B, C and D are invisible to the mode system. **BASIC should have no UPDATE MESHES and no baked view at all** — a child never meets the 18 s, and Layer A is what makes that possible rather than an extra feature on top. MODERATE gets SHOW BAKED with the cancellable bar; ADVANCED the bar, CANCEL and the stale marker as today; DEV keeps everything including the synchronous BAKE REPORT, the one place a hard freeze is acceptable because a dev asked for a number — though `:1664`'s stale docstring must still be corrected.

**Steps.** P0 **measure first** — per-stage `Time.get_ticks_msec()` splits in `bake()`/`bake_extras()`, reported in the dict and printed by `ship_explode_check.gd`, run on the author's own carbon; nothing below should be sized from a structural reading when one run can replace it. P1 land in PREVIEW — S; **`ship_resolve_check.gd` asserts the baked view is UP after load and will fail; update it in the same commit**. P2 `ShipFrameBudget` + its test — S. P3 breathe in `bake_extras` — S; **raise `MAX_BAKE_FRAMES` in `ship_explode_check.gd:18` (3000) and `ship_resolve_check.gd:20` (1800)** or the checks abort on a bake that is merely kinder. P4 breathe in `bake()` — M; the report is only published at the return, which is the invariant to preserve and assert. P5 generation counter + CANCEL — S; one owner, delete the older discard path rather than layering. P6 the atomic swap + cached `ShipSdf` — M. P7 D1 memoization — S; gate on `split_rooms`/`cut_back_rooms` staying 1/0. P8 camera-frame meter — S. P9 threads — L, ADR-gated.

---

#### 7.2.7 The cold open and the invisible root

**The ask.** "its still somewhat a messy ui experiance. forcing the player to know what to start with and puch", and "our starting node is a selectable option in the beginning, however id rather start with our invisible starting node, and have the players add their first component/part to the env them selves."

**What exists today.**

- **The beacon is already the invisible starting node.** ADR 0033 made the origin an invisible anchor; `ship_attach.gd:1134` returns `part.absolute` for the root **or for any part whose parent is empty**; `ship_templates.gd:413` centres every stock class's core on it; `ship_view3d.gd:95-96, 1772-1784` draw it as a 0.45 m three-arm dot with `no_depth_test = true`. The author does not need a beacon built — he needs the builder to stop putting a module on it before he asks.
- **ADR 0033 already names this exact gap** (`0033:93-95`): "There is no UI yet for dropping a part onto the beacon … That is the next piece if the author wants it." He has now asked for it.
- **The promotion rule is already in `core/`:** `ship_doc.gd:355-357` — "A parentless part added to a document with no root becomes the root."
- **A document with no parts is not a new state.** `ship_builder.gd:795-799` already sets `_doc = null` when the pack has no families, and the chooser's entire lifetime today is spent with a null doc; `ship_visual_check.gd:203-204` records "A fresh console has NO document." The novelty is only that it becomes a non-null **empty** doc and persists.
- **The empty console is not a black screen.** `_rebuild_grid` (`:1743-1787`) draws the grid, the two axis lines and the beacon with no reference to the document, and `frame_all()` already falls back to `AABB(Vector3(-4,-4,-4), Vector3(8,8,8))` when the scene AABB is empty — the cold open frames the beacon at a sensible scale for free.
- **The one hard blocker is one line:** `ship_placement.gd:1397-1398` — `if target_parent == "" or not trial.parts.has(target_parent): return REASON_NO_PARENT`. Its sibling is `:931-934`.
- **The founding part would arrive at the wrong size.** `:367` sets `_part_scale = Vector3.ONE` unconditionally — precisely the defect `start_dialog.gd:8-12` records as fixed ("founding on a sphere_pod gave a 2 m ship and founding on a torus_ring gave a 4 m one"). The fix lives in `ShipDoc._span_scale` (`:154`), which is **private**.
- **A free-space founding drag degrades badly:** `anchor_for` with a null parent shape is documented as "a point at its origin and the normal is the ray itself" (`ship_attach.gd:625-628`).
- **The chooser's primitive half is pure redundancy, measured.** `data/shapes/families.json` holds exactly four families and **all four carry `can_be_root: true`**, so `_root_capable()` returns the same four cells the palette already draws; its YARD picker duplicates `part_palette.gd:290-312`. **The template half is not redundant** — `start_dialog.gd:207-278` is the only surface in the app for the stock atoms and molecules.
- **Nothing here is frozen:** `found_document`, `found_from_template`, `get_start_dialog` and `ShipStartDialog` appear in neither API_CONTRACT file, nor in SPEC / SPORE_CLONE_SPEC / FIRST_RUN. What *is* pinned is `ShipPlacement.begin(family_id, manufacturer_id, parent_id)` — and passing `""` is inside that signature.
- **Three headless tools drive the chooser by string** and will fail the moment it stops appearing: `ship_visual_check.gd:207-215`, `ship_resolve_check.gd:81-93`, `ship_explode_check.gd:82-94`.
- The tutorial's first predicate goes dishonest (`_check_founded` is `_doc() != null`).
- **The hash is not at risk** — an empty doc has a well-defined canonical form. The gates already handle zero parts: `check_add` is `_ok()`, and `check_save` already refuses under `min_parts_to_save = 3`.

**The design. The beacon must not become a part, and the document must be allowed to hold zero parts.** Making the beacon a part puts it in `doc.parts`, and from there into the hash, the complexity budget, the save minimum, the tree, the mirror, the seam solver and the bake — and it would need a `family`, a `manufacturer` and a `can_be_root` entry to satisfy `ShipValidate`. **An invisible thing that costs complexity and appears in the tree is not invisible.** The beacon is a coordinate, and ADR 0033 already treats it as one.

The opening thirty seconds:

- **Second 0.** `_new_document()` creates an **empty** document instead of raising the chooser. On screen: grid, axis lines, beacon — all three already doc-independent — with the camera on the existing 8 m fallback. Left column shows the shelf. Nothing is modal. The hint bar says one sentence: `PICK A SHAPE. IT LANDS ON THE MARKER.`
- **Second 3.** **One click** on a shelf cell founds the part at the beacon: parentless, `absolute = IDENTITY`, scaled to `ShipConfig.root_span_m` (5 m), added through the ordinary edit protocol, selected, camera reframed. A click and not a ghost-drag because with no parent there is no surface to be linear on (the whole justification for the surface solve) and no depth cue in empty space; `anchor_for` degrades to a point at the origin. **A gesture with no meaningful degrees of freedom should not ask for any.**
- **Second 8 onward.** Unchanged.

**Founding is an ordinary undoable edit.** `found_document` clears history (`:821-823`); the new path must not. The empty document is history entry zero, so **Ctrl+Z un-founds**. And because `remove_part` on the root leaves `root` empty and the next parentless add re-founds, **DELETE on a lone root also returns to the cold open** — a child who founds on a box and wanted a sphere needs one keypress, not START OVER. Both are free; both need a hint line, not code.

**Where the stock templates go.** The PRIMITIVE tab is **deleted**, not moved. The TEMPLATE tab survives as the dialog's entire content, renamed **STOCK HULLS**, reached from a cell at the end of the shelf (drawn as a cluster glyph) and from NEW → confirm; it replaces the document, so it routes through the existing `ShipModal.Mode.CONFIRM`.

Two additive core readers, **reported not edited** (AGENTS §9, the F18–F47 shape): `ShipDoc.create_empty(data)` — without it the harness duplicates `create_new`'s settings block and the two drift — and a public reader for `_span_scale`. Neither is in `API_CONTRACT.md`; both go in FOLLOWUPS as F55/F56.

**And an ADR**, because this reverses a recorded decision: `start_dialog.gd:3-6` states that as of 2026-09-01 "NEW now raises this, and nothing exists until a choice is made", which was itself the fix for founding on `family_ids()[0]`. The cold open does **not** go back to auto-founding a box; it founds **nothing at all**. That distinction is the whole ADR, and it is worth writing down because the next agent who sees an empty document will otherwise "fix" it back.

**Per view.** **The cold open is the same in all four rungs, deliberately.** "forcing the player to know what to start with and puch" is not a beginner-specific complaint — the author hits that modal on every run, in what is now DEV. Founding a module before the player asks is wrong at every tier, and the instruction to keep DEV untouched is about not taking his controls away, not about keeping a dialog he just called messy. What differs is only the surroundings, which `SHOWN_FROM` already allocates: BASIC is a marker, a shelf and a 212 px left column with no right column; MODERATE adds the tree, inspector and gauges, all of which render an empty document as empty lists and zeroed bars with no special case. The STOCK HULLS cell is BASIC-and-up; its six shape pickers and three size fields are MODERATE-and-up.

**Steps.** ① The empty document exists and the app opens on it — `create_empty`, `_new_document()` re-pointed, `_resolve_on_load()` early-out on `parts.is_empty()` so BAKING… is not the first word on screen, the tutorial predicate fixed, **and all three headless tools moved in the same commit**. S. ② The founding click — branch `_validate_trial():1397` and `notify_doc_changed():931-934`, seed `_part_scale` from `root_span_m`, place immediately through `begin_edit`/`commit_edit`, select, `frame_all()`. M; earns a gdUnit4 case asserting root, `absolute == IDENTITY` and the widest AABB axis at `root_span_m`. **①and② ship as one pair — ① removes the only way to found a ship and ② restores it.** ③ Retire the primitive half, rehome the templates, rewire NEW — M, **panels lane, one contiguous handoff**; keep `get_start_dialog()`, `found_from_template()`, `_on_cell_pressed` and `_on_start_pressed` under their exact names or move the tools with them. ④ Cold-open hint states into `ShipHintText` — T, renders nothing yet. ⑤ Tier it + capture the empty console in each rung — S. ⑥ **The ADR** + F55/F56 — T; skipping it is the actual risk.

---

#### 7.2.8 The blended cluster splits 3-and-1, not 2-and-2

**The ask (SHIFT+F).** Split the group as evenly as the structure allows, **and** put like shapes **opposite** each other — a stronger condition than the left-right mirror rule the code enforces.

**What exists today.**

- **The complaint is exact and reproduces.** Re-implementing `_layout`, `_mirror_paired`, `_mirror_slot` and `_blend_group` against `data/templates.json` and running all 16 classes: a blended carbon comes out **4 electrons A,A,B,A = 3-and-1** and **6 protons A,B,B,A,B,A = 3-and-3 but with +Z on one shape and −Z on the other**. "only a single electron being a sphere out of 4" is literally what the code produces.
- **The cause is one line of bookkeeping.** `ship_templates.gd:1100-1108`: `_blend_group` assigns `first if turn % 2 == 0 else second`, copies to the mirror partner (`:1107`), and increments `turn` **once per pair claimed**. A berth whose mirror partner is itself claims no partner but still burns a turn, so self-mirrored berths alternate one body at a time while true pairs alternate two — and the parity walks off.
- **Which berths are self-mirrored is the whole story.** `_mirror_slot` (`:799-809`) reflects across **X only**. Carbon's nucleus is 6 bodies, so `_arrangement_holding(6)` picks `octahedral` = [+X,−X,+Y,−Y,+Z,−Z]. Under an X reflection only +X/−X is a true pair; the other four are each their own mirror. Four singletons and one pair — exactly the condition that makes the alternation walk.
- **A 3-3 split of an octahedron cannot be made of whole antipodal pairs** (3 is odd), which is precisely why the author names 4+2.
- **The task brief's premise and the file's own docstring are both wrong.** `ship_templates.gd:17-21` says "carbon really is four berths at 109.5 degrees". `_layout:816` picks the arrangement by **proton count (6)**, so carbon is octahedral. Worse, `tetrahedral` is **never selected for anything**: `_arrangement_holding:953-969` sorts names alphabetically and replaces only on `size < best_size`, so `square` always wins the 4-slot tie and beryllium is a square.
- **The blend is off by default** (`start_dialog.gd:350, 371-372` lead with "- NONE -"), so nothing here touches an unblended ship.
- ADR 0048 states the current rule as design ("A node and its mirror always take the SAME shape"). That is honoured — the defect is that X-mirror pairing was the **only** pairing considered, and on a centrosymmetric arrangement the antipodal pairing is the one the eye reads.
- **Nothing is pinned:** zero hits for `ShipTemplates` in either API_CONTRACT file; all four functions are private statics; the file is 1,425 lines with 13 public statics.
- The existing test (`tests/core/test_components.gd:516-560`) only asserts boxes > 0, spheres > 0, sum == 6 and balance > 0.97 — **a 5-and-1 split would pass it.**

**The design: replace the mirror pair with a symmetry orbit, and split at the orbit boundary.** A shape is assigned to a whole equivalence class of berths, never to a body. Two relations generate the class: **X-mirror** (hard, ADR 0044/0048, unchanged) and **antipode** (new — the j with `berths[j].distance_squared_to(-berths[i]) <= MIRROR_SLOT_EPSILON`, one ~10-line sibling of `_mirror_slot`).

1. `berths[]` from `_berth_of`, exactly as `_mirror_node:1115` already builds it.
2. **Orbits:** flood-fill over both relations, walking i ascending, members sorted ascending. Deterministic, O(n²) on n ≤ 8.
3. **Order the orbits waist-first:** key = (mean over members of |berth · up|, lowest member index), where `up` is the root's own berth. The same preference `_waist_first:918` already uses for arms, lifted to orbits.
4. **Split at one boundary, not by alternating.** Choose the boundary minimising |cumulative − total/2|, ties to the larger prefix. A single boundary keeps like shapes contiguous, so the result reads as a designed band-and-caps rather than a checkerboard.
5. **The first-named family takes the larger side**, so the blend is always the accent, never the majority.
6. **Degenerate fallback:** if the split puts everything on one shape (the whole group is one orbit), redo with the antipode relation **off**. If it is still one class the group genuinely cannot blend (helium's two protons *are* each other's mirror) and it stays one shape, as today. This is the only place "opposite" yields to "blended", and it yields because a +BLEND that visibly does nothing is a broken option.

**What it produces (simulated against the real pack, all 16 classes):**

- **Carbon, 6 protons:** orbits {+X,−X}, {+Z,−Z}, {+Y,−Y}; waist-first, boundary at 4 vs 2 → **four waist bodies A, {+Y,−Y} B**. That is the author's "4 boxes and 2 top/bot spheres" exactly; his other phrasing is the same layout with the pickers swapped.
- **Carbon, 4 electrons:** boundary at 2 → **2-and-2, each shape facing itself across the ship.**
- Beryllium protons 3A/1B → 2A/2B. Boron protons 2A/3B → 3A/2B (the blend was the majority; now it is not). Boron electrons 1A/2B → 2A/1B.
- The 8-body cubic nucleus stays 4-and-4 but goes from `ABABABAB` to `BAABBAAB` — two interpenetrating tetrahedra, each centrosymmetric and each X-mirror-closed. **Rocksalt, not stripes.**
- **Silicon**, 4 electrons on cube vertices: the antipodal orbit swallows all four, so the fallback fires and it stays 2A/2B on mirror classes. On a cube, opposite and blended are mutually exclusive for a 4-arm class; blend wins. No regression.
- **Phosphorus / fluorine / chlorine** electrons get **less even** (3A/2B → 4A/1B), because an odd cube-corner arm has no antipode present and becomes an orbit of one. Worth noting this parks the blend shape on exactly the unpaired corner that ADR 0048's Consequences and F51 name as the thing a second density could cancel — a real trade (Q17).

Net: with a blend named, **13 of 16 classes change**; with no blend named, **zero**. Geometry, arrangements, slot ordering, `_mirror_paired`, `_nucleus_radius`, sizing and joints are all untouched — only which family each already-placed node wears.

**Per view.** Identical in all four: this is `core/`, and `ShipUiMode` cannot reach it (AGENTS §3). What differs is only who can reach the blend — the +BLEND rows read as ADVANCED-shelf controls. The one mode-facing consequence is that a +BLEND which cannot apply to the picked class should **say so** rather than silently do nothing, and that annotation is worth more in BASIC than in DEV.

**Steps.** ① **Land the diagnostic first** — a per-class, per-group blend report (berths, orbits, A/B counts, assignment string) so the fix is judged against a printed before/after, not a screenshot. S. ② `_antipode_slot` beside `_mirror_slot` — T. ③ `_blend_orbits` + `_blend_split` — M; **every sort key needs an explicit index tie-break** (determinism is a gate, AGENTS §8b). ④ Rewire `_blend_group` with the fallback — S; the X-mirror guarantee becomes strictly *stronger* (orbits are mirror-closed by construction), but `ShipMetrics.balance` must be re-measured per class because the two shapes have different densities. ⑤ Tests — M: carbon protons 4-and-2 with the pair on ±Y, carbon electrons 2-and-2 antipodal, every node matching both its mirror and its antipode where the arrangement holds one, silicon still blending, helium unchanged, balance > 0.97. ⑥ Tell the player when +BLEND cannot apply — S. ⑦ **ADR** amending 0048, with ruleset **unchanged at 4.0.0** and the selfcheck hash `5536787c6c35d236` printed either side, as ADR 0044 and 0048 both did. ⑧ Separately: mark `ship_templates.gd:17-21` RETIRED and **report** the `square`-beats-`tetrahedral` tie-break rather than retuning it — changing it would move every 4-proton class's geometry.

---

### 7.3 THE REVISED ORDER OF WORK

One table over everything remaining, old steps and new, renumbered. Each row cites the subsection where its sub-steps live. "Old" is the §5.1 number. Effort: T trivial / S small / M medium / L large.

**Why the first five are the first five.** The author woke to a build that looked identical and said so. These five are the direct answer, and each was chosen against the same four tests: *visible at first launch*, *unblocked today*, *touches nothing frozen except one reported amendment*, and *answers a sentence he actually wrote*.

- **R1** changes **every number in the right column** on the next launch with zero behaviour change — his first complaint, and the cheapest visible change in the whole plan. `inspector.gd` has one public method and 683 lines of headroom; there is no seam hunt in front of it.
- **R2** puts the **mode tab on screen**. "i dont see thge tab for simple-to-advanced views" is true because it is an untracked file that nothing mounts. He asked for the ladder twice and it is the frame every other row hangs off.
- **R3** renders the **hint bar**. 3,659 of last night's 4,389 lines are a guidance table and a keymap table with **no renderer**; this is the step that converts the largest part of the invisible work into a 52 px band at the bottom of the screen. It is also the single biggest pixel change available (22 px → 52 px, four zones, a mode strip).
- **R4** makes **components reachable and survivable**: ESC that works (F53), a DEL message that stops blaming the selection, and a breadcrumb band with a DONE button. Three of the four are under ten lines each, and together they answer "i cant select individual parts".
- **R5** makes the app **land in PREVIEW with the bake in hand**, which is one `bool` and is the whole of "it locks up … when its supposed to be hot swappable" — the editing path is already single-digit milliseconds; he simply cannot see its results from inside the baked view. It ships with P0's stage timings so every later row in §7.2.6 is sized from a measurement, not a reading.

After that the ordering alternates: one feel change (the handles), one structure change (tiering), one visible change (thumbnails), so no week passes without something on screen.

| # | Step | Files | E | Risk | Visible next run | Blocked by | ADR |
|:-:|---|---|:-:|---|:-:|---|:-:|
| **R1** | **Every number tells the truth.** Per-field decimals in `NumericField`; honour the pack's authored `step`; honest snap labels; BBOX gauge decimals. §7.2.1 a–c, h | `numeric_field.gd`, `inspector.gd:97/814`, `gauges.gd:335-347` | S | Amends `API_CONTRACT_UI.md:160` + `SPEC:435` — **report, do not edit**. Do not touch the static `format_number()` (20 callers). | **yes — ~30 numbers** | — | report |
| **R2** | **The mode tab on screen.** Finish `ShipUiMode`: mount it, the four-rung control, tier-aware column widths at the point they are applied, `user://ship_ui.json`. *(old 14)* | `ship_ui_mode.gd`, `ship_builder.gd` (~4 lines) | M | §3.1 rule 3 — **one owner, queried, never cached**. Enforce in review. | **yes** | — | no |
| **R3** | **`ShipHintBar`** — the renderer, 22→52 px, four zones, mode strip, chips, NEXT. **Also fix the LAYERS explorer draw order** (`:1109` before `:1114`, so the opaque SubViewport covers it). *(old 11)* | NEW `ship_hint_bar.gd`, `ship_builder.gd:88/629/1109/1127-1151` | M | 30 px comes out of the 3D view until R6 reclaims the gauge strip. **No new public method.** Verify at 1280×800 headlessly; never read a window size. | **yes — the biggest one** | — | no |
| **R4** | **Components: in, and back out.** ESC leaves isolation (F53); honest DEL refusal; the breadcrumb band. §7.2.2 ①–③ | `ship_builder.gd:500-515, 1489-1507, 1905-1911`, NEW `ship_isolation_band.gd`, `ship_keymap.gd:896` | S | The band **must be a sibling of `Root`** — `gui_disable_input = true` at `ship_view3d.gd:297` makes anything else unclickable. | **yes** | — | no |
| **R5** | **Land in PREVIEW, and measure the bake.** `_show_bake(show:false)`; SHOW BAKED / UPDATE MESHES; per-stage timings in the report. §7.2.6 P1, P0 | `ship_builder.gd:886-963`, `ship_csg_bake.gd`, `tools/ship_explode_check.gd`, `tools/ship_resolve_check.gd` | S | **`ship_resolve_check.gd` asserts the baked view is UP and will fail — move it in the same commit.** Do not land in the same commit as R2. | **yes** | — | no |
| **R6** | **Tier the panels.** Additive `set_ui_mode(level)` via the duck-typed probe; each panel hides its **own** sections; human labels for the 11 closed `param_key`s. *(old 15)* | `inspector.gd`, `part_tree.gd`, `part_palette.gd`, `gauges.gd` | M | **AGENTS §6 lane — `harness/panels/` is Antigravity's; one contiguous handoff.** Gauges must keep computing and keep calling `set_budget_alert` (`API_CONTRACT_UI.md:163-167`). | yes | R2 | no |
| **R7** | **Handles, part 1: the drag feel.** B2 residue + H2 swept-angle rings. Static test: 400 px at 1 px/event at snap 5.0 → 80 × 5.0°. *(old 8)* | `ship_view3d.gd:1381-1447`, `ship_placement.gd` | M | Every rotation and offset in the app. **Land alone**, verify at 0.5 first so a regression bisects. Re-run the five-release F13 gate. | yes (feel) | — | no |
| **R8** | **Palette in 3D.** `ShipPartThumbs` orthographic atlas + the ~6-line cell swap + shared scale + the refused material. §7.2.4 T1–T3 | NEW `ship_part_thumbs.gd`, `part_palette.gd`, `ship_builder.gd` | M | Panels lane — bundle with R19. `UPDATE_ONCE` on a dirty flag, never `UPDATE_ALWAYS`. **Keep `draw_glyph`** — `start_dialog.gd:471` calls it. `--import` after the new `class_name`. | **yes** | — | no |
| **R9** | **Handles, part 2: the gizmo follows the ghost** (B4). *(old 9)* | `ship_scene_builder.gd:395-416, 530-535, 724-790` | S | One `ImmediateMesh` rebuild per motion event; reuse `HANDLE_PX_TOLERANCE`. | yes | — | no |
| **R10** | **Handles, part 3: hit fairness + the collinear stalk (B6) + the projected-px ring clamp + the honest axis lock.** *(old 13)* | `ship_handles.gd:374-477`, `ship_view3d.gd:1398-1405` | M | **Highest-attention.** F13's code and the Tab-gate's. Write the static `hit_test()` test with fixed projected positions **before** the edit; `tests/core/test_attach.gd:754` stays green. | yes | R7 | no |
| **R11** | **The lattice.** 5° default + ALT bypass + `SNAP 5°` in the strip; `snap_m` → 0.1 + the SNAP M picker; `_snap_size()` on the document branches; `snap_scale` wired. §7.2.1 d,e,g + *(old 10)* | `data/tuning.json`, `inspector.gd:98, 260-282`, `ship_placement.gd` | S | **Must follow R7.** Moves the hash of *newly created* docs only — say so in the devlog. Re-run `ship_validate_data.gd`; `tuning.json:69` claims a bypass that does not yet exist. Contract **addendum** for the second picker. | yes | R7 | report |
| **R12** | **Cold open: the empty document + the founding click.** §7.2.7 ①② — **one pair, never split.** | `ship_builder.gd:790-806, 956-961`, `ship_doc.gd` (+`create_empty`, +span reader), `ship_placement.gd:367/931/1397`, `tutorial.gd`, all three view-check tools | M | ① removes the only way to found a ship; ② restores it. All three headless tools drive the chooser **by string** and must move in the same commit. F55/F56 as additive reports. | **yes** | — | **yes** |
| **R13** | **STOCK HULLS.** Delete the chooser's primitive half, rename and rehome the template half, rewire NEW → empty doc, hint states, tier it. §7.2.7 ③–⑥ | `start_dialog.gd`, `part_palette.gd`, `ship_builder.gd:1429-1552`, `ship_hint_text.gd` | M | Panels lane. Keep `get_start_dialog`, `found_from_template`, `_on_cell_pressed`, `_on_start_pressed` under their exact names. | yes | R12, R2 | with R12 |
| **R14** | **The blend splits evenly and opposite.** Report first, then `_antipode_slot`, `_blend_orbits`/`_blend_split`, the rewire, the tests, the UI annotation. §7.2.8 ①–⑥ | `core/templates/ship_templates.gd`, `tests/core/test_components.gd`, `tools/`, `start_dialog.gd` | M | 13 of 16 classes change **when blended**; 0 unblended. Determinism is a gate — explicit index tie-breaks on every sort. Re-measure `ShipMetrics.balance` per class. **Core lane — parallel with everything above.** | yes (blended ships) | — | **yes** (amends 0048) |
| **R15** | **The frame budget.** `ShipFrameBudget` + its test; breathe in `bake_extras`; breathe in `bake()`; generation counter; UPDATE MESHES → CANCEL while busy. §7.2.6 P2–P5 | NEW `ship_frame_budget.gd`, `ship_csg_bake.gd`, `ship_bake_session.gd`, `ship_bake_hud.gd` | M | **Raise `MAX_BAKE_FRAMES`** in `ship_explode_check.gd:18` and `ship_resolve_check.gd:20` or the checks abort on a kinder bake. The report must only be published at the return. Wall-clock gets **longer** (~18 s → ~25–30 s). | **yes — a bar that moves** | R5, P0 | no |
| **R16** | **Cut the work.** Atomic swap in `ShipExplodeView` (no doubled-geometry frame); cached `ShipSdf` on the session; D1 per-vertex memoization. §7.2.6 P6, P7 | `ship_explode_view.gd:292-370`, `ship_builder.gd:939-953`, `ship_csg_bake.gd:804-820`, `core/mesh/mesh_seam_split.gd` | M | Gate D1 on `split_rooms`/`cut_back_rooms` staying 1/0 on the author's ship; `_classify` feeds the seam split. | yes | R15 | no |
| **R17** | **Name the snap targets that already draw.** Label + dashed leader in `ViewOverlay`; correct `ux.md:465` in the same commit. §7.2.4 A1 | `ship_view3d.gd` (~30 lines; 1,909/2,000, 27/30) | S | Shares the overlay with R28's value chip — **decide who owns the layout before both are written.** Hide the text for `^p_\d+$`; never rename an id. | **yes** | — | no |
| **R18** | **Inside a component.** Inner rows in the tree (`_part` → `doc.part_at()`); click-again-to-descend. §7.2.2 ④⑤ | `part_tree.gd:213-238, 343-360, 999-1005`, `ship_view3d.gd:900-935`, `ship_builder.gd:743-750` | M | Every selection-sourced lookup must go through `part_at` — the tree's LINK status line already crashed on exactly this. Descend must require press+release inside `CLICK_SLOP_PX` and **lose to any drag**. | yes | R4 | no |
| **R19** | **MAKE PART.** The `sub_document` property (a public var with a private setter — the class is at 30/30), the session, the band, `import_from`, and component thumbnails on the same atlas. §7.2.2 ⑥⑦⑧ / §7.2.4 T4 | NEW `ship_make_part.gd`, `ship_builder.gd:611`, `part_palette.gd`, `ship_part_thumbs.gd` | M | `ship_builder.gd` is **1,955/2,000** — budget ~25 lines. A fresh `ShipHistory` or UNDO walks into the host ship. `import_from` also brings every scratch definition plus one per deduped ARM (Q6). | **yes** | R8, R12, R2 | report |
| **R20** | **JOIN.** `pairs_between`; the corrected refusal string; sibling seams **drawn**; the two-click verb with `default_link_for_explicit()`. §7.2.3 ①–④ | `core/sdf/ship_seams.gd:518/549`, `part_tree.gd:711-716`, `ship_scene_builder.gd`, `ship_view3d.gd` | M | The verb's state lives in its own `RefCounted` (the `ShipReseat` mould) — no new public method on `ShipBuilder`. **Do not widen `_stand_apart`** (an 8-part selection would write 28 joints). | **yes** | — | no |
| **R21** | **Hover.** `hover_test()` at `HOVER_PX 16`, part hover through the pick path, 400/150 ms dwell, brighten hovered / dim siblings to 35%, `ShipCursor`. *(old 12)* | `ship_handles.gd`, `ship_view3d.gd`, `ship_scene_builder.gd`, NEW `ship_cursor.gd` | M | **Adding signals to `ShipView3D` is an addition to a frozen contract** — reported addendum, never a silent diff. Reuse the **convex** pick bodies. Never resolve an SDF on hover. | yes | R3 | report |
| **R22** | **Alignment inference.** `ShipInference` (static, tested, no renderer) → draw the guides → snap conditions 1–3 + dwell-lock → mode-filter + the chip → SAME SIZE on the morph drag. §7.2.4 A2–A6 | NEW `ship_inference.gd`, `ship_view3d.gd`, `ship_scene_builder.gd`, `ship_placement.gd` | M | `ShipSceneBuilder` is at **exactly 30/30** — the guide node belongs to `ShipView3D`. A4 **must follow R7** or it reproduces B2 as a regression. Fold A6 into R11's quantizer; do not build a second. | **yes** | R7, R11, R2 | no |
| **R23** | **Drag-to-move + click-arm parity + ALT-clone behind a hit test.** *(old 17)* | `ship_view3d.gd:914-957`, `orbit_camera.gd:100-105` | M | The arm threshold must derive from `CLICK_SLOP_PX`, not a second invented number, and must not fight R18's click-again-to-descend. | yes | R21, R18 | no |
| **R24** | **SCALE \| SIZE M.** §7.2.1 f | `inspector.gd:285-305, 583-598, 637-690` | M | **Rewrite the uniform lock in scale units** or the toggle distorts parts. Panels lane. Cache the unscaled extent. Label it SIZE, not EXACT SIZE. | yes | R1, R6 | no |
| **R25** | **Tier the gizmo, the protractor and the ring ticks.** *(old 16)* | `ship_handles.gd`, `ship_scene_builder.gd` | M | Measure the 72-segment tick cost. The lit tick comes from `values_changed`, never a display-side round. | yes | R10, R2 | no |
| **R26** | **Mirror onto one owner** + the twin ghost + a MIRROR layer row. *(old 18)* | `ship_builder.gd`, `inspector.gd`, `part_tree.gd`, `ship_scene_builder.gd`, `ship_layers_control.gd` | M | Three writers → one writer and two views; the panels hold no plane state. Reflect the computed `preview_transform()`, never a second solve. The plane draws **hatched**, not low-alpha. | yes | R2 | no |
| **R27** | **The hold-`?` card**, generated from `ShipKeymap`. *(old 20)* | NEW `ship_key_legend.gd` | S | `Control`, never a `Window`; `MOUSE_FILTER_IGNORE`; **inside** the inner SubViewport. | yes | — | no |
| **R28** | **Type-to-commit + the docked value chip + the inference badge.** *(old 22)* | NEW `ship_value_box.gd`, `ship_view3d.gd`, `numeric_field.gd` | M | Digit capture must consume before `G`/`E`/`F`/`DEL`/`ESC`/`CTRL+Z` and self-cancel on selection change. Shares the overlay with R17. | yes | R21, R17 | no |
| **R29** | **Hide the 10-line legend below DEV.** **Do not delete it** — "keep the current view" is explicit. *(old 21, amended)* | `ship_ui_mode.gd`, `ship_view3d.gd:1244-1320` | S | Must not land before R3's mode strip, or the pivot and aim toggles become invisible below DEV. | yes | R3, R27, R2 | no |
| **R30** | **BASIC's shelf.** Six large cells, no pager, no price glyph, no MFR picker; the pack `description` into FACTS on hover. *(old 23, cold-open half now R12)* | `part_palette.gd` | M | Panels lane. Keep the palette's full `ShipGate` pass scoped to visible cells. **Do not add search or categories.** | **yes** | R8, R6 | no |
| **R31** | **CLAY + the void + the torch.** Palette variant (warm ramp held byte-identical), the three-band ramp, `DisplayMode.CLAY` appended at 6, the environment branch, `_grid.visible = false`, three shader uniforms defaulting to off. §7.2.5 ②–④ | `data/palette.json`, `ship_theme.gd:69-73/384`, `ship_scene_builder.gd:72`, `ship_view3d.gd:1727-1740`, `shaders/part_faceted.gdshader` | S | **One precedence rule: a budget alert always beats a variant.** The torch pushes into `t`, never adds a colour. Verify defaults are bit-identical with a capture diff. Run `ship_validate_data.gd`. | **yes** | — | no |
| **R32** | **ADR 0049 — the camera is not the clone target.** §7.2.5 ① | NEW `docs/adr/00xx-camera.md`, marker at `orbit_camera.gd:7-11` | S | Must explicitly **not** reopen `pan_by()` or the axis-snap presets. | no | author's go | **yes** |
| **R33** | **Camera, no-ADR half:** easing, tighter FIT, `CTRL+click` on empty space. *(old 19a)* | `orbit_camera.gd`, `ship_view3d.gd:1019-1046` | M | `camera_moved` on every eased frame, or the depth cue and handle scale go stale. **No renames** of the four tool-reached methods. | yes | — | no |
| **R34** | **FLY.** The pure static integrator + its conservation tests, then the node, the input branch, the pose stash, ENTER-to-keep-the-view, the tier table and the corrected hint strings. §7.2.5 ⑤–⑧ | NEW `ship_fly_camera.gd`, `ship_view3d.gd:564-595, 795, 1552`, `ship_ui_mode.gd`, `ship_keymap.gd`, `ship_hint_text.gd` | M | Key state from `InputEventKey`, **never `Input.is_key_pressed`** (dead behind `push_input`). Keep `_push_depth_range` fed or the shader's distance cue freezes and is diagnosed as a shading bug. No `MOUSE_MODE_CAPTURED`. | **yes** | R32, R33, R2 | via R32 |
| **R35** | **Four-rung + CLAY + fly headless capture.** *(old 24, promoted to required)* | `tools/ship_check_views.gd` | S | The only thing that stops three views the author never opens from rotting. **Do not ship R2 without it.** | no | R2 | no |
| **R36** | **TAKE APART.** Wire `dissolve` (zero callers today). §7.2.2 ⑨ | `ship_components.gd:884`, `part_tree.gd:804-876` | M | **Blocked on measuring F37** — a dissolved nucleus with OPEN links baked 8 open pieces where the component bakes closed. Shipping before that is explained hands the player a button that silently opens their hull. | yes | measure F37 | no |
| **R37** | **BRIDGE, the data model and the solver.** `crossing()` public; `KIND_SPAN` + the four span fields omitted-when-unset; the `ShipAttach` solver; `_can_place` waiting on both ends; the two end joints. §7.2.3 ⑤–⑨ | `ship_seams.gd:450`, `ship_part.gd`, `ship_attach.gd:1103-1142`, `tests/core/` | M | **Highest-risk core work.** Inside the transform pass every consumer walks — a mistake shows as parts vanishing, not an error. Write the cycle test first. Hash must be byte-identical (the `seam_style` precedent). | no | R20, ADR | **yes** |
| **R38** | **The BRIDGE tool + tiering JOIN/BRIDGE/CONNECT.** §7.2.3 ⑩⑪ | NEW `ship_bridge_tool.gd`, `ship_view3d.gd`, `ship_ui_mode.gd`, `part_tree.gd` | M | The ghost must go through the same solver as the committed part or the tube moves on commit. Panels lane for the tiering. | **yes** | R37, R2 | via R37 |
| **R39** | **Real add and delete inside a component.** `add_inner_part` / `remove_inner_part`, definition joints and order kept consistent. Replaces R4's honest refusal. §7.2.2 ⑩ | `core/ship_components.gd`, `ship_builder.gd:368/500` | L | The one step that changes what a definition **is** mid-life, with every instance following. Needs a determinism run and care that `add_part` stops seating against a null parent shape. | yes | R18, R19 | **yes** |
| **R40** | **The rotate annulus outside each morph handle.** *(old 25, optional, last)* | `ship_handles.gd:450-477` | S | Widening the morph band eats clicks that used to reach the rings. Ship last, behind the mode. | yes | R10, R25 | no |
| **R41** | **Threads for the per-cell read-out.** §7.2.6 P9 | NEW ADR, `ship_csg_bake.gd` | L | **The first thread in the repository.** A race in geometry code surfaces as a rare wrong mesh, not a crash. Needs a selfcheck hashing a threaded and an unthreaded run to the same value. Not part of a UX batch. | yes | P0 numbers + Q12 | **yes** |

**Standing preconditions for every row** (AGENTS §8a/c/d): claim the GPU slot before *any* Godot invocation, headless included; run `--import` after adding any `class_name`; verify through `tools/ship_run.ps1`, never bare `-s`; gdUnit4 exits **103** headlessly with an `InputEvents` message, which is not a failure.

---

### 7.4 What reads wrong today

The author asked that "all that reads right moving forward". These are the concrete collisions the eight surveys turned up — each one is a place where two things share a name, one thing has two names, or a control's label contradicts its behaviour.

**A verb whose refusal describes the opposite of what it does.** `part_tree.gd:711-716` prints `NOTHING IN THE SELECTION IS JOINED TO ANYTHING ELSE IN IT. SELECT A PART AND WHAT IT STANDS ON.` The branch immediately above it (`ship_seams.gd:583-585`) happily links **two unrelated parts**. The message describes the tree-pair branch only and tells the player the exact opposite of what LINK will do with a two-part selection.

**Five buttons, three meanings, in the bake row.** `UPDATE MESHES` is the bake. `BAKE` is a **report** that changes nothing on screen (`ship_builder.gd:1216`, and §3.1.1 already proposes renaming it REPORT). `EXPLODE` and `ROOMS: PIECES` both decide what geometry is drawn, as does the LAYERS explorer, as does the EXPLODE OPTIONS panel — **four surfaces** answering "what am I looking at". And `EDIT`, added last night, is the only way out of the baked view, which the app currently *opens in*.

**Four names for "a part made of parts", and no name for the inverse.** MAKE COMP, MAKE UNIQUE, IMPORT, the COMPONENTS `ItemList`, and `begin_component_placement` are five surfaces over one idea; `ShipComponents.dissolve` is written, documented and tested with **zero callers**, so taking one apart has no name at all. The author's "make part" is a sixth name, and the right move is to make it the *only* one below ADVANCED rather than a sixth.

**Two starts, about to become three.** The START chooser's ONE PRIMITIVE tab offers the same four families the part palette draws (all four carry `can_be_root: true`) with a duplicate YARD picker. MAKE PART would add a third empty-document beginning unless it consumes the cold open's — which is why §7.2.2 makes that a hard rule rather than a preference.

**"Part" means four things.** A document part, an inner part of a definition, a component instance, and a palette cell. The tree renders the collision directly: `[C] p_0001 NUCLEUS (7 PARTS)` as a **childless leaf** — a row that states seven parts exist and offers no way to reach one.

**A promise made twice and kept nowhere.** The isolation status line (`ship_builder.gd:1497`) and the 3D legend (`ship_view3d.gd:1300`) both say "ESC TO CLOSE"; `_handle_edit_hotkey` throws the key away. The only working exit is double-clicking empty space — the same undiscovered gesture, in reverse. Meanwhile DEL inside a component says `NOTHING DELETABLE IN SELECTION`, blaming the player's selection for a limitation of the feature.

**Two units for "how big", neither cross-referenced.** The inspector's SCALE is an abstract multiplier on a 0.05 lattice; the gauges' BBOX is metres on a 3-decimal format. `ResolvedShape.unscaled_aabb()` has been the exact bridge between them since it was written, and nothing shows it.

**A precision control that lies about its own precision.** `SNAP_LABELS` renders the snap choices as `0.100 / 0.500 / 1.000 / 5.000 / 15.000`. And there is **no linear snap control at all** though `cfg.snap_m` silently steps OFFSET at 0.05 — so one of the two lattices the author cares about is invisible and unreachable.

**A step authored in the data and thrown away in the UI.** Every shape parameter in `data/shapes/families.json` carries a `step`; `ShapeGen.effective_ranges()` returns it; `inspector.gd:814` replaces it with 0.001. `round` reads `0.020` against an authored step of 0.01.

**Four guidance surfaces.** The 10-line 3D legend (21% of the view), the tutorial card, the status line, and the hint bar that is authored but not rendered. R3 and R29 consolidate them; until then they are four places to look and three of them are stale.

**The mirror and the opposite are conflated.** `_blend_group` knows exactly one pairing relation (`_mirror_slot`, X only), so "balanced" and "symmetrical" collapse into one test that an octahedron fails in a way the eye reads immediately.

**A docstring that names geometry the code does not build.** `ship_templates.gd:17-21` says carbon is "four berths at 109.5 degrees"; `_layout:816` picks by proton count and makes it octahedral, and `tetrahedral` is unreachable because `square` wins the 4-slot tie alphabetically. Mark it, report the tie-break, do not retune it.

**A performance claim retired by a measurement.** `ship_builder.gd:1664` says the synchronous bake is "a pause, not a hang". The SHIFT+F state says **18,222 ms** with one yield in it. ADR 0042 says the dicing "never blocks a frame"; its read-out never yields and costs ~9.6 s after the ship is already on screen.

**A light that lights nothing.** `DirectionalLight3D "KeyLight"` (`ship_view3d.gd:309-315`) at energy 1.15, in a scene where every material is `unshaded` because shaded ones render black here (F7). It is decoration that reads as a lighting model.

**Eleven grabbable handles at once, with no hover**, and a plain wheel that scales the selected part while the on-screen legend promises it zooms (B7, O3).

---

### 7.5 Open questions — only the author can answer

Answered already by this message, recorded here so nobody re-asks: **O1** (mode names) → BASIC / MODERATE / ADVANCED / DEV. **O2** (does the camera ADR go ahead) → yes on the design; the ADR is still written first.

| # | Question | Why it blocks | Default if you say nothing |
|:-:|---|---|---|
| **Q1** | **The 3-decimal rule.** `API_CONTRACT_UI.md:160` and `SPEC:435` both say "always exactly 3 decimals". Per-field decimals contradicts the letter while satisfying the stated reason (widths do not jitter — a field's decimal count is fixed by its step, and `FIELD_WIDTH` is a fixed 68 px right-aligned box). Proposed wording: *"every field renders a fixed number of decimals, derived from its step."* | **Blocks R1**, which is step one of the whole plan. I will not edit either file. | Ship it and **report** the amendment; treat it as provisional until you bless it |
| **Q2** | **Does `SNAP_CHOICES` itself change?** "snaps should be every 5 degrees" reads either as *make 5 the default* (free) or *make the list 5° multiples* (a contract edit). | R11's scope. | Default only; list untouched |
| **Q3** | **Is 0.1 m too coarse for OFFSET?** It equals `hull_thickness_m`, so one notch is exactly one wall — a good story. 0.05 is what ships today. | R11. | 0.1 default, 0.05 on the picker |
| **Q4** | **Is DEV frozen, or merely preserved?** I read "keep the current view as dev working view" as *do not move my controls or slow me down*, not *never improve a picture* — so thumbnails, guides, honest numbers and the hint bar go into DEV too. But you also said you saw no changes, which you would say again if every improvement landed in rungs you do not open. | **This one governs every other agent's work**, not just this topic. | Corrections and pictures land in DEV; controls do not move |
| **Q5** | **Should a resolved ship land in PREVIEW or in BAKED?** ADR 0028 says a ship that arrives resolves itself, and it does — into a view with no handles where edits change nothing on screen. R5 keeps the bake and shows the primitives. | R5 changes what the app looks like the moment it opens. | PREVIEW, with SHOW BAKED one click away |
| **Q6** | **What does a saved part bring with it?** `import_from` adds every definition the scratch doc used **plus one per deduped ARM** — one saved tower can put four or five rows in a child's palette. (a) keep all, show only the last in BASIC/MODERATE; (b) an additive `import_one()` that skips the arms; (c) an optional `origin` field on the record (ruleset-safe by ADR 0025's argument) and let the palette filter. (c) also answers whether the template's own NUCLEUS definition belongs in a child's parts list, which today it does. | R19. | (a), with (c) reported as the follow-up |
| **Q7** | **What is MAKE PART called, and where does it live?** Your word is "make part", but the button sits next to a shelf of parts, so it may read as *give me a part*. MAKE A NEW PART / BUILD A PART / MY WORKSHOP. Head of the shelf, or the toolbar beside NEW / OPEN / SAVE — which is what it more honestly is? | R19. | MAKE PART, head of the shelf |
| **Q8** | **Does MAKE PART exist in ADVANCED and DEV at all,** or is MAKE COMP enough there? Keeping both is the strict-superset rule and costs nothing; culling it in DEV keeps the expert surface from carrying two buttons for one idea. Your own "may have overlapping btn roles" points straight at this. | R19. | Both, in ADVANCED and DEV |
| **Q9** | **When a part a bridge is anchored to is deleted, what happens to the bridge?** `remove_part` takes the descendant subtree and drops joints naming a removed part — a bridge is neither. (a) it dies with either end (matches the subtree rule; deleting one electron silently removes tunnels elsewhere); (b) it survives as a stump, frozen and marked the way `(FLOAT)` already marks a parentless part; (c) it re-aims at the dead end's parent, which is clever and will surprise people. | **Blocks the bridge ADR, which blocks R37.** | none — I will not pick this one |
| **Q10** | **Is a bridge charged to the complexity budget** as an ordinary part, or not charged because the player did not choose its length? | R37. | Charged as an ordinary part |
| **Q11** | **Responsive-but-slower, or frozen-but-faster?** Time-slicing turns 18 s of dead application into ~25–30 s of a moving bar, a CANCEL button and a camera you can fly. A 25 ms budget is my starting guess; it is one constant and you have to feel it. | R15. | Ship at 25 ms, retune after you feel it |
| **Q12** | **Are threads on the table?** The per-cell work is pure, independent `core/` data and would go roughly 6× faster on a pool. First thread in the repo; needs an ADR and a determinism proof. | R41. | Not started |
| **Q13** | **Does the dicing stay automatic?** ADR 0042 made it automatic on your instruction; with R15 it genuinely runs behind the frame for the first time, so the promise finally becomes true. But it is ~10 s for geometry only EXPLODE and ROOMS: WHOLE ever draw. | R15/R16 scope. | Stays automatic |
| **Q14** | **In fly: is RMB-drag torque or look?** Your words are explicit, so torque is the default — drag applies angular acceleration, release leaves a slow spin, `X` brakes. It is also the version most likely to make you seasick while trying to look at one nacelle, because with no mouse capture a drag that reaches the view edge stops mid-torque. The hybrid is mouse = direct look, keyboard = true torque. One constant, ten-minute A/B, completely changes the feel. | R34. | Torque, with the hybrid one constant away |
| **Q15** | **Does BASIC get fly?** `ux.md:237` says no; I am proposing yes with heavier damping (`LIN_DAMP 0.80`, `ANG_DAMP 2.50`) and direct look, because "the little kids' mode cannot fly" is the version a child would resent. | R34's tier table. | BASIC flies, with training wheels |
| **Q16** | **CLAY's ambient while flying: 0.45 or 0.12?** 0.45 is readable clay; 0.12 makes the torch genuinely the only light source and gives the deep void you described, at the cost of not seeing the far side of your own ship. | R31/R34. | 0.45 static, 0.12 while flying |
| **Q17** | **When even and opposite conflict, which wins?** On the 5-, 6- and 7-arm cubic classes an arm sits on a corner whose antipode is absent, so enforcing "opposite" makes the split **less** even (phosphorus electrons 3A/2B → 4A/1B) — though it also parks the second density on exactly the unpaired corner F51 names as the lever to cancel that class's asymmetry. The alternative is a cap (`ceil(n/2)+1`) that restores 3A/2B and gives up opposite-matching there. You said this is "not a hard constraint". | R14. | Opposite wins; report the three affected classes |
| **Q18** | **On an octahedron, is the minority always the poles?** Your two phrasings are the same layout with the pickers swapped, so I read "the poles are the distinguished pair" as the invariant. If you meant *any* opposite pair, the rule gets simpler and the result less predictable. | R14. | Poles are the minority |
| **Q19** | **Cold open, four small ones.** (a) Does DEV keep the chooser, costing you one extra click per session to get a box on screen — a `user://ship_ui.json` flag would give it back in DEV only. (b) Does the founding click place **immediately** at the beacon, or raise a ghost you drop in free space (a new input mode with its own projection decision)? (c) A founded part is scaled to `root_span_m` (5 m) while the same cell onto a hull gives the family's authored size — a real inconsistency I will not choose silently. (d) Does DELETE on a lone root return to the empty console (free, the cheapest "wrong shape" recovery) or should the root be undeletable? | R12. | (a) same cold open everywhere (b) immediate (c) 5 m when founding (d) yes, returns |
| **Q20** | **The manufacturer picker will not change the thumbnail.** `ShipMeshGen` ignores ribs, scallops and twist by design, and kessler vs voss differ almost entirely in those — so both `box_hull`s render as the same picture. The honest position is that the palette promises exactly what the 3D view will show and the difference belongs in FACTS text; the alternative renders ribs in thumbnails only, which promises something the editing view does not deliver. | R8. | Palette promises what the view shows |
| **Q21** | Still open from §6.3 and unchanged by this message: **O3** (plain wheel), **O5** (promotion predicates), **O6** (sentence case in BASIC), **O7** (watch one child for two minutes), **O8** (audio), **O9** (zero-typing save + autosave). O7 would settle O5, Q4 and most of §3.1 on its own. | | as recorded in §6.3 |
