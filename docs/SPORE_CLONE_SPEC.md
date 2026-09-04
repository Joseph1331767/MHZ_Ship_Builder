# Spore UFO Editor — researched mechanic inventory and clone gap analysis

Compiled 2026-08-31 from four independent research passes (UI, placement, input, constraints).
Every line here traces to a source; claims the researchers could not confirm are marked
**UNVERIFIED** and must not be implemented as if they were fact.

**The strongest sources, in order of weight:**

1. **Spore ModAPI** — the community's reverse-engineering of the shipped binary, publishing the
   actual `Editors::EditorRigblock` and `Editors::EditorModel` C++ classes with field comments.
   This is the real data model, not a description of one.
   `https://github.com/Spore-Community/Spore-ModAPI`
2. **The official Spore PC manual**, OCR'd: `https://archive.org/details/spore-pc-manual-en`
3. SporeWiki (`spore.fandom.com`), GameFAQs walkthroughs, SporeModder-FX wiki.
4. Maxis design commentary: Chaim Gingold's GDC 2007 "Magic Crayons", Soren Johnson's
   "Spore: My View of the Elephant", Chris Hecker's liner notes, IEEE Spectrum "Engineering Spore".

---

## 0. The finding that reframes the whole project

**In the Space Stage UFO editor, parts are 100% cosmetic. They contribute no stats at all.**
Confirmed independently by all four research passes.

> "In contrast to other vehicles in creators, every part of the spaceship is cosmetic and won't
> affect its attributes." — SporeWiki, *Spaceship*

Spore splits the ship into two systems that never touch:

| System | Contains | Constraint model |
|---|---|---|
| **Spaceship Creator** (the 3D editor) | Vehicle palette + exclusive Space tab | Complexity budget, 3-part minimum. No money, no stats, no unlocks. |
| **Ship Tools** (a separate shop/toolbar, ~184 items) | ALL actual function — weapons, health, energy, cargo, drives | Badge-gated unlock, then Sporebuck purchase |

An in-editor tooltip jokes about it: *"The only thing between you and the vacuum of space is 6 feet
of solid style."*

**Soren Johnson (Spore's final lead designer) names this as an unresolved internal fight**, not an
accident: *"Should the editor enable unparalleled aesthetic customization, at the expense of
gameplay consequence, or should the game mechanics support every choice made by the player?"* The
team never resolved whether Spore was "an interactive art museum or a customizable video game."
The later-stage editors were resolved toward aesthetics.

**Why this matters here:** MHZ_Ship_Builder's entire Phase 2 — hull regions, material layers from
MHZ_Materials, resolved structural strength, power/data/fuel routing — is the *opposite* choice.
A literal clone of the UFO editor would delete the reason this project exists. See section 8.

---

## 1. The data model (from the reverse-engineered binary)

`Editors::EditorRigblock` — every placeable object in every Spore editor is a "rigblock".

| Field | Meaning | Our equivalent |
|---|---|---|
| `mpParent`, `mChildren` (**max 8**) | parent/child tree | `ShipPart.parent`, no cap |
| `mPosition` | position | derived from attach |
| `mOrientation` | surface-derived orientation | mount basis from SDF gradient |
| `mUserOrientation` | player-applied rotation delta | `roll` |
| `mTotalOrientation` | the composite actually rendered | final `Transform3D` |
| `mCSnapBoneIndex` | index of the model bone literally named `csnap` — **attachment points are named bones baked into the part mesh** | none; we ray-trace the SDF |
| `mpBallConnectorHandle`, `mpSocketConnectorModel`, `mSocketConnectorOffset` with min/max | a real ball-and-socket joint with a draggable offset range | `offset` |
| `mpSymmetricRigblock`, `mpAsymmetricRigblock`, `kEditorRigblockModelIsAsymmetric` | mirror twin links | `mirror_source` / `mirror_plane` |
| `mModelMinScale` / `mModelMaxScale` | **per-part-type** scale clamp (e.g. 0.2x–2.0x) | one global clamp |
| `mMorphHandles` (**max 8**) | non-uniform deform handles per part | none |
| `mCapabilities` (**max 20**) | typed stat contributions | none |
| `mModelSnapToParentTypes`, `mModelTypesToInteractWith`, `mModelTypesNotToInteractWith` (cap 16), `mModelTypesToSnapReplace` + `mModelReplaceSnapDelta` (0.4) | data-driven allow/deny/replace rules | none |
| `mBooleanAttributes` — `eastl::bitset<64>` | per-type behaviour flags | none |

Snap-target flags (a part uses one): `SnapToParentCenter`, `SnapToParentSnapVectors`,
`SnapToCenterOfEditor` (this is how cockpits lock to the centreline).
Orientation flags: `OrientToSurfaces`, `OrientWhenSnapped`, `PointForward`, `RemainUpright`,
`RemainUprightOnTop`. Handle-suppression flags: `HideDeformHandles`, `HideRotationHandles`.
Root-capability: `CannotBeParentless` distinguishes body/chassis types from ordinary parts.

`Editors::EditorModel` holds a **flat** `mRigblocks` vector plus a creation-level `mUsingSymmetry`;
the hierarchy lives in the rigblocks themselves. **That is structurally identical to our `ShipDoc`.**

A single `Editors::cEditor` serves every editor with exactly three modes:
**`BuildMode`, `PaintMode`, `PlayMode`.**

---

## 2. Input grammar — VERIFIED against the official manual

| Input | Action |
|---|---|
| **Plain mouse wheel** | **scale the selected part** (also Up/Down arrows) |
| **Shift + wheel**, `+`/`-`, on-screen buttons | zoom the camera |
| Right-drag background, or left-drag the dais, or `<`/`>` | orbit the camera |
| **Hold `Tab`** with a part selected | reveal additional handles — rotation rings and morph/distort handles |
| **`Alt`** on a selected part | clone it |
| **`Ctrl` + drag** | move part **vertically** (may float in mid-air or sink into geometry) |
| **`Shift` + drag** | move part **horizontally** across the dais; in the Vehicle editor, moves **all** blocks |
| Drag part off the creation, or `Delete`/`Backspace` | remove it |
| **Hold `A`** while selecting | break symmetry for that part **and cascade to its children** |
| `Ctrl+S` | save |
| `B` | Sporepedia |
| Paint mode: `Shift+LMB` / `Shift+Ctrl+LMB` / `Alt+LMB` / keys `1`–`5` | paint whole part / all parts of that type / eyedropper / region + eyedropper modes |

**The camera is an orbit/turntable only — rotate and zoom. There is no pan verb documented
anywhere.** No reset-view control, no front/side/top snap views, and no placement grid were found
in the manual, the wikis, or any forum. Our `1/2/3/4` axis-snap views are an invention.

**No key rebinding exists in Spore.**

**Same modifier, different meaning per editor:** `Ctrl` removes a limb section in the *creature*
editor but moves a part vertically in the *vehicle* editor. Most online "Spore hotkey" lists blend
the two. Ours must not.

---

## 3. Placement — how a part actually attaches

1. Pick up from the palette and drag. The editor triangle-picks against existing geometry
   (`mTrianglePickOrigin`; `UseHullForPicking` lets a part use its convex hull instead).
2. Live preview carries a UI state: `Default`, `Invalid`, `Ghost`, `BadLocation`, `Prevent`.
   (The states are VERIFIED to exist; their exact visual treatment is UNVERIFIED.)
3. If the type has `OrientToSurfaces`, orientation is recomputed from the surface normal.
4. **Snap** pulls the drop point to a typed target — parent centre, authored snap vectors, or the
   editor centreline. **Spore does NOT place freely at the raw cursor position.**
5. Type filtering decides legality and whether this is a *replace* rather than an addition.
6. On release the part gets `mpParent`, joins `mChildren` (cap 8), and — if mirrorable — a
   symmetric twin is created and cross-linked.

A player-authored description of the feel: *"parts tend to 'snap' to a point located on the centre
of a part's 'face' or the editor base… it's as if other parts will be attracted to imaginary lines
crossing the centre of the original part."*

**Parts attach to other parts, not just the hull.** **Vehicle/building editors are the PERMISSIVE
ones** — a popular mod exists to port their free movement *into* the creature editor. Creature-editor
constraint language describes the opposite of what we are cloning.

---

## 4. Symmetry

- **On by default, always, at launch (2008)** — with no way to break it; an "Asymmetry Mod" was
  required. Applies to creature, outfit, vehicle and UFO editors.
- A later patch added **hold `A`** to break symmetry for the part being selected.
- **Breaking cascades:** breaking on a parent breaks it for every part attached to it, and all
  future parts attached to it.
- Placing off the centreline **creates a mirrored duplicate**; it does not refuse the placement.
- Symmetry **doubles complexity cost** — breaking it is a documented budget exploit.
- Only bilateral mirroring is confirmed. **No native radial symmetry** (players fake it with
  `Alt`-clone plus manual rotation). UNVERIFIED-but-likely-absent.

---

## 5. Constraints — the complete list of hard walls

For the UFO editor specifically, this is *all* of them:

1. **>= 3 parts** to save or upload.
2. **A complexity ceiling**, independently configured for this editor (confirmed by modder
   testing). **The numeric value is unpublished anywhere reachable** — only the creature cap
   (138, or 148 outfitted) is documented.
3. Part must be on the editor's **whitelist manifest** (`*_EditorKeys` `.prop` file). Only bites
   modders adding custom parts — but note it is a *whitelist of legal part ids*, not a rule engine.
4. A **name** is required to save.
5. **Per-part** scale clamps, individually authored. No universal default exists.
6. A **build-volume boundary** exists (confirmed by player complaint); magnitude unpublished.

And explicitly **NOT** constraints:

- **No contiguity requirement.** Bodies "require no base"; cockpits "are considered independent
  shapes and do not have to be attached." Parts can float disconnected and still save. No
  "disconnected parts" error exists in any editor.
- No required functional part — no mandated engine or cockpit.
- No currency cost to build. No unlock gating on hull parts.
- No stat consequence from anything you build.
- No test mode in the ship editor.

**Enforcement feedback:** over-budget parts **render red in the palette and cannot be placed.**
Over-budget creations (achieved via the `freedom` cheat) get a red complexity symbol on their
Sporepedia card, are never pollinated, and cannot appear in game.

---

## 6. UI inventory

**Nine palette categories**, the UFO editor being the union of all three vehicle editors plus one
exclusive tab: Bodies, Cockpits, **Space**, Land, Water, Air, Weaponry, Effects, Details.
(Sources disagree on tab order — SporeWiki puts Space 3rd, GameFAQs 6th. UNVERIFIED.)

Paginated grids of part icons; the creature editor's is documented as up to four columns of
eight to ten. **No search or filter exists in any Spore editor palette.**

**Paint mode in the vehicle/building/ship editors is per-part/per-region manual painting** — NOT
the creature editor's whole-body procedural system. Three sub-options: complete styles, partial
styles, and Paint Brush mode. ("Complete" vs "partial" styles are named in sources but never
explained — UNVERIFIED.)

Editor background is space with drifting asteroids. A note plays when a part is added. Save flow
is name (mandatory) + description + tags.

---

## 7. Design intent — sourced, and worth cloning deliberately

- **Gingold, GDC 2007:** *"You should be able to make something cool in three clicks."* *"They
  would make something, and something would go wrong, but they'd still love what they made."*
  *"We definitely went more the route of soft mastery."*
- **Why the complexity cap is measured in PARTS, not polygons** — Hecker: the system deliberately
  avoids polygon-level editing to keep the creation "recipe" small enough to transmit through
  Sporepedia. Wright's GDC 2005 figure: a **5000:1** ratio, ~1 KB of recipe to ~5 MB of content.
- **How Maxis decided what to forbid** — looped spines were removed because *"doughnut-shaped
  animals raised all sorts of exceptions to the animation rules."* A topology got banned when it
  broke a downstream procedural system, never because it was ugly or unbalanced. Limbless
  creatures were not banned; they got a graceful fallback.
- **Hecker:** *"Bugs + Player Creativity = Features"* — accidental metaball webbing between limbs
  became bat wings. Every hard wall forecloses one of those.

---

## 8. Gap analysis against MHZ_Ship_Builder

### 8a. Already matching (arrived at independently)

- Three-layer orientation: surface-derived + user delta + composite.
- Flat part collection with hierarchy in the parts themselves.
- A connector offset with a min/max range.
- Parent/child attachment of parts to other parts.

### 8b. Missing — pure additions, no conflict with existing decisions

| # | Mechanic |
|---|---|
| 1 | Drag-from-palette placement with a live ghost and its five UI states |
| 2 | Selection handles: ball rotation handle; `Tab` reveals rotation rings + morph handles |
| 3 | Wheel scales the selected part; Shift+wheel zooms camera |
| 4 | `Ctrl`+drag vertical / `Shift`+drag horizontal / `Shift`+drag moves whole ship |
| 5 | `Alt` clone |
| 6 | Drag-off-to-delete |
| 7 | Undo/redo as on-screen arrows, bottom-right |
| 8 | Symmetry ON by default, `A` to break, cascading to children, doubles cost |
| 9 | Complexity meter + **parts turn red in the palette when unaffordable** |
| 10 | Minimum 3 parts to save; name required |
| 11 | Categorised, paginated icon palette (no search) |
| 12 | **Paint mode** — per-part/per-region, with its own hotkey set. We have none. |
| 13 | Bodies-as-roots; `CannotBeParentless` distinction |
| 14 | Max 8 children per part; per-part-type scale clamps |
| 15 | Typed attach allow/deny lists; replace-on-drop |
| 16 | Snap-to authored points / parent centre / centreline |
| 17 | Remove our invented axis-snap views and camera pan (Spore has neither) |

### 8c. Direct conflicts with decisions the author already made

These cannot be resolved by research. They are choices. See the conversation for the decision.

| Conflict | Spore | This project |
|---|---|---|
| **Part function** | cosmetic only; all function in a separate shop | weight/volume/cost budgets now, materials + structural strength in Phase 2 |
| **Numeric input** | none; drag and handles only | typed angular placement, explicitly chosen for determinism |
| **Contiguity** | parts may float disconnected | strict tree; `orphan_part` is a validator ERROR |
| **Budget shape** | part-count complexity | physical: bbox, internal volume, weight, cost |
| **Snapping** | to authored points; no documented angular snap | 0.5 deg angular snap, configurable |
| **Part catalog** | hundreds of hand-authored meshes with baked `csnap` bones | 6 procedural SDF families x manufacturers x params |
