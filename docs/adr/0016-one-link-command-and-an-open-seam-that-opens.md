# 0016 — One LINK command, and an open seam that actually opens

- **Date**: 2026-09-04
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) — measured: the selfcheck doc hashes `5536787c6c35d236` before
  and after. Nothing here changes a field, a document or how one serializes.
- **Amends**: ADR 0008 (LINK acts on a selection, not a pair); ADR 0011/0015 (the exact bake now
  reads the seam MODE, not only its style)
- **Records**: FOLLOWUPS F28

## Context

> "explode failed, and thats because i believe the link, and makeroom arent working properly.
> infact they shouldn't really be separate options, as when making a room it defines open
> structures at their link.. but i guess more is happening there as well so ill let you hash that
> out. - explode has some parts overlapping and thats incorrect."

Three separate defects, all confirmed by measurement before anything was changed.

**1. EXPLODE left modules overlapping.** `explode_offsets` moved each child along its own seam
normal far enough to clear its HOST, which is the only thing one seam knows about. Nothing
separated SIBLINGS — and the atomic templates (ADR 0014) make near-parallel siblings ordinary,
because a nucleus body and an extremity take their directions from two different arrangements that
are free to point the same way. Measured: lithium put a fused body 1.40 m inside a tunnel and
2.76 m inside a pod; carbon had six overlapping pairs, neon and argon one each.

**2. LINK did not reach the geometry at all.** `ShipSdf` honours `SEAM_MODE`, and the SDF bake is
what BAKE still uses. `ShipMeshBake` — the exact path ADR 0011 introduced, and the one EXPLODE
shows — read only `SEAM_STYLE`. Measured on a helium class: sealed, doorway, hatched and open all
produced the same 24 faces and the same 514.89 m³, to the last digit. The pipeline swap dropped the
link modes on the floor and nothing noticed.

**3. MAKE ROOM did the opposite of what it said.** Its multi-part branch lifted the selection into
a component, and `ShipComponents` drops a joint whose two ends are both inside the lift — the
comment there says that is how "joining parts into one room removes the walls between them". It is
not: a wall is the ABSENCE of a record (`ShipSeams.mode_for` returns `MODE_WALL` when no joint
exists, and `cycle_link` erases the record to make one). Dropping the joint therefore WALLED every
internal seam. Measured on a lithium class: 2 joints before the lift, 0 after, none of them open.

## Decision

**LINK takes a selection, and there is no MAKE ROOM.** `ShipBuilder.cycle_link()` now takes a
`PackedStringArray` and steps every seam inside it round `LINK_CYCLE` as one unit, in one undo
step. A selection whose links already agree steps on from there; a mixed one unifies at the wall
first, so the second press is predictable instead of depending on dictionary order. Selecting parts
and stepping them to OPEN **is** making them one room, which is the whole of what MAKE ROOM
promised — *"when making a room it defines open structures at their link"*. Naming a room is a
rename, which the part tree row has always done in place.

`ShipSeams.pairs_within()` and `ShipSeams.shared_mode()` are new statics: which seams a selection
contains, and what they currently are. They live in `core/` because the answer is a fact about the
document, and both the panel (to decide what to refuse) and the builder (to apply the step) have to
get the same answer to the same question.

**A two-part selection always names its own pair**, even when neither part stands on the other. A
joint is keyed over an unordered pair, not over the attach tree, and two siblings that grew into
each other meet as truly as a child meets its host.

**An OPEN seam is BORED, not inset.** `ShipMeshBake._open_seams()` takes the plate of hull standing
between the two cavities out of both modules. `_wall_between(cavity, body, other)` names that plate
without needing to know where the seam surface ended up: what one cavity reaches into the other
body and does not find cavity there. It is taken from both sides, because either part can be the
one that pokes into the other, and both results are bored out of both shells.

**A module stays a closed solid when it opens.** It becomes a cup rather than a box, with the seam
face an annulus of hull around the passage — so nothing downstream needs a special case for an open
room. Measured: helium's two protons go 294.83 → 246.94 m³ and 220.06 → 172.17 m³, a full 0.20 m
plate off each, both with zero open edges.

**DOORWAY and HATCHED still resolve as WALL**, and the bake now says so: `pending_seams` counts
them. Cutting a bounded opening and welding its frame is the next piece of work, and a bake that
quietly treated one as a wall would read as finished.

## Consequences

**Measured, on the shipped templates.** Explode: helium, lithium, carbon, neon and argon all report
zero overlapping pairs, with the exploded span 1.7–2× the assembled one — a stack, not a scatter.
Opening every seam: carbon 860.0 → 722.7 m³, argon 1299.6 → 1157.6 m³, nothing open-edged either
side. Opening ONE seam on a nucleus that hosts nine changes exactly that seam's two parts and no
others.

**Not every seam has a wall to open, and the accounting says which.** Of argon's 23 seams, 9 open
and **14 were already one room**: the fused nucleus bodies overlap so deeply (`FUSE_OVERLAP` is
0.34 of the span) that their interiors interpenetrate by 97–159 m³ and were never separated. Carbon
is 8 and 5. That is a real gap against ADR 0015's *"the hatch and seam surfaces remain solid"* — it
holds per module (every one closes) but not BETWEEN two fused ones. It belongs with the hatch work,
where the seam surface between linked modules gets built rather than inferred.

**One seam in one class is a genuine miss**: lithium's tunnel-to-nucleus joint, whose plates come
to 0.2 and 1.1 m³ and lie outside both shells. Its interiors barely reach each other — the same
marginal joint the `attach_embed_m` / `tunnel_bore_m` / `hull_thickness_m` triple was tuned around
in ADR 0015.

**Three wrong shapes for the plate, each ruled out by measurement**, recorded because each was
reasonable:

1. *Zero inset at an open seam*, letting the existing interior cut do it. Opens ONE side. The
   interior pass computes its own crossing plane from the interior surfaces, which is not the plane
   the outer surfaces crossed at, so a zero inset there is not the seam face.
2. *The smaller part's whole interior.* Needs a "which is smaller" test, and helium's two protons
   are the same size to within float noise — the tie fell to the host and the bore did nothing.
   It would also have opened every OTHER seam on that part at once.
3. *The lens where the two interiors overlap.* For a fused pair that lens is most of the host's
   cavity and misses the plate entirely.

**The reach is TWO walls, not one.** One wall reaches the far module's skin only if the two hulls
touch exactly, and they do not always: on a helium class, whose protons are the same size and share
their side faces, the flange put the cut 0.16 m past the host's surface and a one-wall reach took
0.04 m off a 0.20 m plate. The extra band costs nothing — it lies inside the neighbour's cavity,
where there is no hull to remove.

**Cost.** An extra tessellation per part and two booleans per open seam, and only when something is
actually open: an argon class with every seam open goes from about 7.6 s to 13.5 s. Nothing changes
for a ship with no open seam.
