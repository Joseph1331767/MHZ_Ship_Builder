# Symmetry — notes

**Status:** not built. Captured 2026-09-21. Not CONTRACT; see [README](README.md). Unlike the other
notes here, part of this is **current-phase work** (section 1), recorded here until it is scheduled.

---

## 1. Mirror on any combination of axes — BUILT (ADR 0043, 2026-09-25)

> "mirror is kinda been out of alignment for a minute.. as i can only select x, y, or z, when it
> should be x, and/or, y, and/or z, where reflections can happen across all 3 axis at once. there
> are also other forms of symmetry that we can implement later, but keep them in mind. the idea is
> that its a game and not really software, and i want it easy for a player to make a symmetrical
> ship if they wish." — the author, 2026-09-21

**Today:** a document carries ONE mirror plane, `ShipDoc.symmetry_plane` — `"x"`, `"y"` or `"z"`
(default `"x"`), read by `ShipSymmetry`, `ShipAttach` (the twins), `ShipSeams` and
`ShipComplexity`. A part flagged `asymmetric` (cascading to its descendants) opts out.

**Wanted:** any combination — X, Y, Z, X+Y, X+Z, Y+Z, X+Y+Z. With all three, one part placed off
every plane becomes eight: the group of reflections across the chosen planes.

What it touches, for when it is scheduled:

- **The document model is CONTRACT** (SPEC §5.1, §6). `symmetry_plane` changes shape (one axis →
  a set), and it is written into every document, so it enters the canonical form and the hash. That
  needs an ADR and, if old files are to keep hashing as they did, a reading that maps `"x"` to
  `{x}` without moving existing hashes.
- **A part near one plane but not another** twins across only the planes it is off (the existing
  on-plane exemption, `ShipConfig.symmetry_plane_epsilon`, applied per axis).
- **Twin the unit, not its parts** (Phase One Hull Review rec 3) should land together with this:
  a component instance mirrors as one body.
- **Game, not software.** The control is three toggles, not a menu of combinations.

## 2. Other forms of symmetry — later

Keep in mind, do not build yet. Candidates:

- **Radial / rotational:** n copies around an axis (a ring of engines, a turret cluster).
- **Point symmetry:** reflection through the centre (a special case of X+Y+Z).
- **Linear repeat:** copies at a fixed step along an axis (ribs, a row of modules).

Design the section 1 data so that a symmetry is a **list of operations** (reflections now,
rotations and repeats later), not a fixed set of three booleans, so these can be added without
changing the document shape again.

---

## A PREBUILT SHIP MUST BE SYMMETRIC BY WEIGHT - current phase, from a dev note

> "after reviewing many of these, i realized that many of our presets are asemetrical in every
> direction. the rule i created now is we need symetry across at least 1 axis with reguards to our
> prebuilds. with a left-right being a min, top-bot, and frnt-back can be asymetrical if the themed
> part calls for it, with our default guidlines to be as symetrical as possible with all 3 being
> ideal. make it based on weight (mirrored weight) as thats really the only symetry we care about,
> and most often will align with part size and placement, but in the future of this game we may deal
> closer to weight so may as well do that now." - the author, dev note 2026-09-24 13:42

**The rule.** Every prebuilt class is symmetric across **at least one** axis, measured by MIRRORED
WEIGHT rather than by shape or placement. Left-right is the minimum; top-bottom and front-back may be
asymmetric where the theme calls for it; all three is ideal and is the default aim.

**Why weight and not geometry.** It is the property the game will eventually care about - handling,
balance, thrust alignment - and it usually coincides with size and placement anyway, so measuring it
now costs nothing and means the presets are already right when it starts to matter.

**What it asks of the code.**

- `ShipMetrics` already computes weight per part, so the measure exists: mirror every placed part's
  centre of mass across the candidate plane and compare the two sums. A tolerance is needed, since a
  hatch on one side is a real asymmetry and a rounding difference is not.
- It wants to be a CHECK before it is a constraint: a tool that reports each class's weight balance
  on all three axes, run over every template, so the presets that fail are known before anything is
  changed to fix them. `tools/ship_validate_data.gd` is the natural home - a class that fails the
  one-axis minimum is a data fault in the same sense as a missing description (AGENTS §10b).
- Only then, the layouts themselves. `ShipTemplates._layout` places nodes on an arrangement; the
  arrangements that come out lopsided are the ones to correct.

**Not yet measured.** Nobody has yet run the numbers to see which classes actually fail, and that is
the first piece of work: the rule is clear, the offenders are not.
