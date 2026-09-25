# 0045 - The builder shows where the mass sits, and how centred

- **Date**: 2026-09-25
- **Status**: Accepted
- **Ruleset**: unchanged (`4.0.0`) - the selfcheck doc hashes `5536787c6c35d236` either side. A
  readout measures a document; it does not change what one means.
- **Amends**: ADR 0044's reading of the rule - ANY one axis, not X
- **Records**: FOLLOWUPS F51

## Context

Two corrections from the author, both to the agent's reading rather than to the rule.

**The rule is any ONE axis, and X is not special:**

> "com only has to adhear to the axes that are symetrical, and with 3 orthognal axies to choose from
> and the constraint that only 1 has to be symetrical means that any of our pre built shapes should
> be able to obtain that."

ADR 0044 read "with a left-right being a min" as making X mandatory and reported four classes as
failing it. They fail on ALL THREE, and the agent's framing hid that: the leftover arm sits on a
CUBE CORNER, which is off every plane by the same amount.

**And perfecting the balance is a later mechanic, not this one:**

> "thats more of a future mechanic that i was talking about with symetry via weight, but i can also
> have an entire minigame that they weight the system after building with exess material and
> modifications. so maybe during this builder we just give a 0-1 value of how centered it is, and we
> draw a cross where the com is. then i can handle prefection in a balancing via weight addition
> later."

## Decision

**The builder reports balance and marks the centre of mass. It does not enforce anything.**

**`ShipMetrics.balance()`** returns the centre of mass, a 0-1 per axis, and `best` - the axis the
ship does best on, which is the single number the rule cares about, since only one axis has to hold.

**Weight is volume, for now, and the author said so**: "all hull volumes wil be placeholdered at same
density so it translates to volume and shape for now but can be set up via weight". A part's share is
its resolved bound's volume - no meshing, so this costs an attach solve and nothing more, and when
real densities arrive it is the one line that changes.

**A CROSS at the centre of mass**, three bars on the ship's own axes, sized off the ship so it reads
the same on a three-metre pod and a thirty-metre hull. **It ignores depth**, because the centre of
mass is usually inside the hull - that is what being centred means - and a depth-tested mark is
invisible exactly when the ship is right. A bar is drawn calm on an axis the ship is centred on and
in the warning colour on one it is not, so which axis is out says itself.

**A 0-1 in the budgets footer**, beside the cell and area it is measured with, naming its best axis:
`BALANCE 0.92 X`.

**`tools/ship_symmetry_check.gd` asks for any one axis**, not X, and says so when a class has none.

## Consequences

**The four classes are reported honestly.** `fluorine`, `sodium`, `phosphorus` and `chlorine` are
symmetric on NO axis - not "failing X" - and the reason is now stated where it is read: an odd valence
leaves one arm on a cube corner, which is off all three planes at once. Measured, a sodium reads
`centre (1.17, 1.17, -1.17)`, `balance (0.923, 0.923, 0.915)`.

**Nothing is enforced and nothing is culled.** The author's options - resize a body to compensate,
re-berth the odd arm, or cull the class - stay open in F51, and the check reports rather than gates.

**gdUnit4 340/340**; selfcheck PASSED with the hash unchanged; resolve and visual checks PASSED;
gdformat and gdlint clean. Looked at: `reports/visual_com_cross.png`.
