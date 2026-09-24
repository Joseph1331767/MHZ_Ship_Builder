# 0040 - A size lever means the MESH, not the field around it

- **Date**: 2026-09-24
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. No
  document means anything different; prebuilt ships are built at the size they were always asked for.
- **Amends**: ADR 0029 (`hatch_min_m` raised from 0.5 to 0.66)
- **Records**: dev note 2026-09-24 13:44

## Context

The author, from inside the builder:

> "the hatches on here are visually only about .33m acrost, i want to maintain our smallest hatches
> will be .66 of a meter so a human can fit through with a suit on."

Measured on the ship attached to that note: both holes **0.380 x 0.380 m**, both reported TIGHT,
`fit 0.544` against an ask of 0.699. Raising the floor would have changed nothing - the seam could
not give 0.699 either.

**The seam could not give it because the tunnel was built smaller than it was asked for.** In its own
axes that tunnel measured 0.98 m across; the aperture its cavity offered was 0.580, and 0.580 less
the 0.100 frame ring each side is 0.380 - the hole, exactly.

**And the tunnel was small because every size lever measured the wrong thing.** `ShipTemplates` sizes
a part by dividing the wanted metres by `ResolvedShape.local_aabb()`, which is the envelope of the
SIGNED DISTANCE FIELD - and the tessellation sits inside that envelope by the family's own rounding,
which is the same gap FOLLOWUPS F34 records for door fields. Measured at scale one:

| family | `local_aabb()` | built mesh | built/asked |
|---|---|---|---|
| `box_hull` | 2.04 | 2.00 | 0.980 |
| `sphere_pod` | 2.00 | 1.95 | 0.975 |
| `torus_ring` | 4.00 | 4.00 | 1.000 |
| **`cylinder_spar`** | **1.20** | **1.00** | **0.833** |

A hallway is a `cylinder_spar`. A 1.4 m bore was therefore built 1.166 m across - and 1.4 x 0.833 is
1.166 to the millimetre.

## Decision

**A size lever is measured on the mesh that gets built.** `ShipTemplates._unscaled_size` tessellates
the family at scale one and measures THAT. Asking for a 1.4 m bore builds a 1.4 m bore.

**The same instrument reads a size back.** `ShipComponentImport` derives a host ship's span and bore
the same way, because a ship read back and rebuilt has to come out the shape it was. Until now the
two errors cancelled: correcting only the sizing made a carbon asked for a 2.2 m bore hand back 2.64.

**`hatch_min_m` is 0.66**, a person in a suit, up from 0.5.

**A tunnel is sized to pass its own smallest hatch.** `ShipDoors.bore_for_hatch()` gives the
narrowest hallway that can carry a hole of a given width - the hole, its frame ring either side, and
the wall either side of that - and a template floors the bore at it. A floor is only worth what the
geometry honours: `hatch_min_m` clamps what a PANEL may ask for and says nothing about whether the
seam can give it, which is how a 0.66 m floor produced a 0.38 m hole.

## Consequences

**Hatches are a suited person's, everywhere.** Across lithium, carbon and neon in `box_hull`,
`sphere_pod` and `cylinder_spar`, the narrowest hole on any prebuilt ship is **0.700 m**, up from
0.568 - and none is TIGHT. A test asserts it over all nine, and a second asserts the tunnel is wide
enough to be the reason.

**Tunnels are the size they say.** 1.399 to 1.400 m across against a 1.400 m lever, up from 1.166.
Rooms gain about 2%, 2.941 to 3.000 against a 3.000 m lever.

**A lithium of `cylinder_spar` gets doors it never had** - it planned none before and plans two now,
which is the same fault seen from the other end: the bore was too small to seat a hatch at all.

**Every prebuilt ship changes size slightly**, which is the point: the levers were always meant to
mean this, and the numbers in the panel now describe what gets built. Saved ships are untouched -
they carry their own scales, and nothing here reinterprets a stored document.

**gdUnit4 335/335** with two new; selfcheck PASSED with the hash unchanged; validator PASSED;
gdformat and gdlint clean; resolve, explode and visual checks PASSED.

**A CONTRACT delta to record, not to edit in**: `ShipDoors.bore_for_hatch(hatch, wall)` is a new
public static on a frozen class (AGENTS section 9). Nothing existing changed name or signature.
