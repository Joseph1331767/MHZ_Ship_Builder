# Symmetry — notes

**Status:** not built. Captured 2026-09-21. Not CONTRACT; see [README](README.md). Unlike the other
notes here, part of this is **current-phase work** (section 1), recorded here until it is scheduled.

---

## 1. Mirror on any combination of axes — current phase

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
